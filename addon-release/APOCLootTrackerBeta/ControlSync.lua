-- Hardened sync protocol. -- Module: ControlSync.lua
--
-- Design goals:
--   * one authenticated Loot Tracker writer at a time;
--   * authority epochs invalidate packets queued by a previous runner;
--   * logical clocks, writer IDs, and content hashes resolve offline edits
--     deterministically without trusting computer clocks;
--   * all priority overrides are exchanged, so equal global counters cannot
--     hide different per-item changes;
--   * old mutation protocols fail closed instead of replacing current data;
--   * corrupt or partial transfers never apply.

local SYNC_PROTOCOL = "3"
local LOOT_CHUNK_BYTES = 100
local CONTROL_CHUNK_BYTES = 140
local LOOT_TRANSFER_TIMEOUT = 150

local PreviousSetItemOverride = APOCLootPrio.SetItemOverride
local PreviousApplyIncomingAccessSettings = APOCLootPrio.ApplyIncomingAccessSettings
local PreviousSetLootTrackerOwner = APOCLootPrio.SetLootTrackerOwner
local PreviousSetLootDisenchanter = APOCLootPrio.SetLootDisenchanter
local PreviousSetFeatureAccessRank = APOCLootPrio.SetFeatureAccessRank
local PreviousSetLootAutoTrackMode = APOCLootPrio.SetLootAutoTrackMode
local PreviousSetLootQualityTracked = APOCLootPrio.SetLootQualityTracked
local PreviousProcessLootSyncV2Payload = APOCLootPrio.ProcessLootSyncV2Payload

local function ShortName(name)
  return string.match(tostring(name or ""), "^([^%-]+)") or name
end

local function PlayerKey(name)
  return string.lower(tostring(name or ""))
end

local function SamePlayer(a, b)
  local aShort = string.lower(tostring(ShortName(a) or ""))
  local bShort = string.lower(tostring(ShortName(b) or ""))
  return aShort ~= "" and aShort == bShort
end

local function Escape(value)
  value = tostring(value or "")
  value = string.gsub(value, "\\", "\\\\")
  value = string.gsub(value, "\t", "\\t")
  value = string.gsub(value, "\n", "\\n")
  value = string.gsub(value, "\r", "\\r")
  return value
end

local function Unescape(value)
  local slash = string.char(1)
  value = tostring(value or "")
  value = string.gsub(value, "\\\\", slash)
  value = string.gsub(value, "\\r", "\r")
  value = string.gsub(value, "\\n", "\n")
  value = string.gsub(value, "\\t", "\t")
  value = string.gsub(value, slash, "\\")
  return value
end

local function SplitTabs(message)
  local parts = {}
  for part in string.gmatch((message or "") .. "\t", "(.-)\t") do
    table.insert(parts, part)
  end
  return parts
end

local function TextHash(text)
  local hashA, hashB = 7, 11
  for index = 1, string.len(text or "") do
    local byte = string.byte(text, index)
    hashA = math.fmod((hashA * 31) + byte, 2147483647)
    hashB = math.fmod((hashB * 131) + byte, 2147483629)
  end
  return tostring(math.floor(hashA)) .. "." .. tostring(math.floor(hashB)) .. "." .. tostring(string.len(text or ""))
end

local function Canonical(values)
  local encoded = {}
  for index, value in ipairs(values or {}) do encoded[index] = tostring(value or "") end
  return table.concat(encoded, string.char(31))
end

local function Diagnostic(name, amount)
  if not APOCLootPrioDB or not APOCLootPrioDB.sync then return end
  local diagnostics = APOCLootPrioDB.sync.diagnostics or {}
  APOCLootPrioDB.sync.diagnostics = diagnostics
  diagnostics[name] = (tonumber(diagnostics[name]) or 0) + (tonumber(amount) or 1)
end

local function RecordConflict(kind, key, current, incoming, sender)
  if not APOCLootPrioDB or not APOCLootPrioDB.sync then return end
  APOCLootPrioDB.sync.conflicts = APOCLootPrioDB.sync.conflicts or {}
  table.insert(APOCLootPrioDB.sync.conflicts, 1, {
    time = time and time() or 0,
    kind = kind,
    key = key,
    sender = ShortName(sender),
    current = current,
    incoming = incoming,
  })
  while #APOCLootPrioDB.sync.conflicts > 50 do table.remove(APOCLootPrioDB.sync.conflicts) end
end

local function NextControlTransferID()
  APOCLootPrio.controlSyncV3Counter = (APOCLootPrio.controlSyncV3Counter or 0) + 1
  return tostring(time and time() or 0) .. ":c:" .. tostring(APOCLootPrio.controlSyncV3Counter) .. ":" .. PlayerKey(APOCLootPrio:GetPlayerDisplayName())
end

local function SendControlMessage(message, target)
  if string.len(message or "") < 240 then
    APOCLootPrio:SendSyncMessage(message, target)
    return true
  end
  local encoded = Escape(message)
  local transferID = NextControlTransferID()
  local total = math.max(1, math.ceil(string.len(encoded) / CONTROL_CHUNK_BYTES))
  local hash = TextHash(encoded)
  for index = 1, total do
    local first = ((index - 1) * CONTROL_CHUNK_BYTES) + 1
    local chunk = string.sub(encoded, first, first + CONTROL_CHUNK_BYTES - 1)
    local packet = table.concat({"C3", transferID, tostring(index), tostring(total), hash, chunk}, "\t")
    APOCLootPrio:SendSyncMessage(packet, target)
  end
  return true
end

local function WriterRank(writer)
  if APOCLootPrio.GetGuildRankForName then
    local rank = APOCLootPrio:GetGuildRankForName(ShortName(writer))
    if rank ~= nil then return tonumber(rank) or 9 end
  end
  return 9
end

local function NormalizeVersion(version, fallbackHash)
  version = type(version) == "table" and version or {}
  return {
    counter = tonumber(version.counter) or 0,
    writer = PlayerKey(version.writer),
    rank = tonumber(version.rank) or 9,
    hash = tostring(version.hash or fallbackHash or ""),
  }
end

-- Returns -1 when left is older, 0 when identical, and 1 when left wins.
-- Counter is the causal order. Writer/rank/hash are deterministic tie breakers
-- for disconnected clients that create the same counter independently.
local function CompareVersions(left, right)
  left, right = NormalizeVersion(left), NormalizeVersion(right)
  if left.counter ~= right.counter then return left.counter > right.counter and 1 or -1 end
  if left.rank ~= right.rank then return left.rank < right.rank and 1 or -1 end
  if left.writer ~= right.writer then return left.writer > right.writer and 1 or -1 end
  if left.hash ~= right.hash then return left.hash > right.hash and 1 or -1 end
  return 0
end

local function VersionFromParts(counter, writer, rank, hash)
  return NormalizeVersion({counter = counter, writer = Unescape(writer), rank = rank, hash = hash})
end

local function VersionFields(version)
  version = NormalizeVersion(version)
  return tostring(version.counter), Escape(version.writer), tostring(version.rank), version.hash
end

local function SettingsValues()
  return {
    APOCLootPrio:GetFeatureAccessRank("admin"),
    APOCLootPrio:GetFeatureAccessRank("log"),
    APOCLootPrio:GetFeatureAccessRank("lootTracker"),
    APOCLootPrio:GetFeatureAccessRank("guildLoot"),
    APOCLootPrio:GetFeatureAccessRank("lootSessionDelete"),
    APOCLootPrio.GetLootAutoTrackMode and APOCLootPrio:GetLootAutoTrackMode() or "raid",
    APOCLootPrio:GetFeatureAccessRank("lootTrackerView"),
    APOCLootPrio.GetLootQualitySettingsMask and APOCLootPrio:GetLootQualitySettingsMask() or "1111",
    APOCLootPrioDB and APOCLootPrioDB.sync and APOCLootPrioDB.sync.maxRankIndex or 1,
  }
end

local function SettingsHash(values)
  return TextHash(Canonical(values or SettingsValues()))
end

local function AssignmentHash(kind, value, setBy)
  return TextHash(Canonical({kind, value or "", PlayerKey(setBy)}))
end

local function OverrideHash(bias, note)
  return TextHash(Canonical({bias or "", note or ""}))
end

local function EnsureOverrideVersion(override)
  if not override then return NormalizeVersion() end
  local hash = OverrideHash(override.bias, override.note)
  override.syncVersion = NormalizeVersion(override.syncVersion or {
    counter = tonumber(override.revision) or 0,
    writer = override.updatedBy or "legacy",
    rank = WriterRank(override.updatedBy),
    hash = hash,
  }, hash)
  override.syncVersion.hash = override.syncVersion.hash ~= "" and override.syncVersion.hash or hash
  return override.syncVersion
end

function APOCLootPrio:InitHardenedSync()
  self:InitDB()
  local sync = APOCLootPrioDB.sync
  sync.protocol = 3
  sync.logicalClock = math.max(tonumber(sync.logicalClock) or 0, tonumber(sync.revision) or 0)
  sync.diagnostics = sync.diagnostics or {}
  sync.peerStates = sync.peerStates or {}

  for _, override in pairs(APOCLootPrioDB.overrides or {}) do
    local version = EnsureOverrideVersion(override)
    sync.logicalClock = math.max(sync.logicalClock, version.counter)
  end

  local values = SettingsValues()
  sync.settingsVersion = NormalizeVersion(sync.settingsVersion or {
    counter = 0,
    writer = "legacy",
    rank = 9,
    hash = SettingsHash(values),
  }, SettingsHash(values))
  sync.logicalClock = math.max(sync.logicalClock, sync.settingsVersion.counter)

  local loot = APOCLootPrioDB.loot
  loot.trackerOwnerVersion = NormalizeVersion(loot.trackerOwnerVersion or {
    counter = loot.trackerOwnerSetAt and loot.trackerOwnerSetAt > 0 and 1 or 0,
    writer = loot.trackerOwnerSetBy or "legacy",
    rank = WriterRank(loot.trackerOwnerSetBy),
    hash = AssignmentHash("runner", loot.trackerOwner, loot.trackerOwnerSetBy),
  })
  loot.disenchanterVersion = NormalizeVersion(loot.disenchanterVersion or {
    counter = loot.disenchanterSetAt and loot.disenchanterSetAt > 0 and 1 or 0,
    writer = loot.disenchanterSetBy or "legacy",
    rank = WriterRank(loot.disenchanterSetBy),
    hash = AssignmentHash("disenchanter", loot.disenchanter, loot.disenchanterSetBy),
  })
  sync.logicalClock = math.max(sync.logicalClock, loot.trackerOwnerVersion.counter, loot.disenchanterVersion.counter)
end

function APOCLootPrio:NextHardenedSyncVersion(contentHash, previous)
  self:InitHardenedSync()
  previous = NormalizeVersion(previous)
  APOCLootPrioDB.sync.logicalClock = math.max(tonumber(APOCLootPrioDB.sync.logicalClock) or 0, previous.counter) + 1
  local writer = self:GetPlayerDisplayName()
  return NormalizeVersion({
    counter = APOCLootPrioDB.sync.logicalClock,
    writer = writer,
    rank = WriterRank(writer),
    hash = contentHash,
  })
end

function APOCLootPrio:AdvanceHardenedSyncClock(version)
  self:InitHardenedSync()
  APOCLootPrioDB.sync.logicalClock = math.max(tonumber(APOCLootPrioDB.sync.logicalClock) or 0, NormalizeVersion(version).counter)
end

function APOCLootPrio:GetOverrideManifest()
  self:InitHardenedSync()
  local records = {}
  for key, override in pairs(APOCLootPrioDB.overrides or {}) do
    local version = EnsureOverrideVersion(override)
    table.insert(records, Canonical({key, version.counter, version.writer, version.rank, version.hash}))
  end
  table.sort(records)
  return TextHash(table.concat(records, string.char(30))), #records
end



function APOCLootPrio:SetItemOverride(item, bias, note, source, revision)
  self:InitHardenedSync()
  local override = PreviousSetItemOverride(self, item, bias, note, source, revision)
  if not override then return nil end

  local hash = OverrideHash(override.bias, override.note)
  if revision ~= nil and type(source) == "table" and source.syncVersion then
    override.syncVersion = NormalizeVersion(source.syncVersion, hash)
  else
    override.syncVersion = self:NextHardenedSyncVersion(hash, EnsureOverrideVersion(override))
    override.revision = override.syncVersion.counter
    override.updatedBy = self:GetPlayerDisplayName()
    override.updatedAt = time and time() or 0
    self:SetRevision(math.max(self:GetRevision(), override.syncVersion.counter))
  end
  return override
end

function APOCLootPrio:SendOverrideV3(key, override, target)
  if not key or not override then return false end
  local version = EnsureOverrideVersion(override)
  local counter, writer, rank, hash = VersionFields(version)
  SendControlMessage(table.concat({
    "O3", Escape(key), counter, writer, rank, hash,
    Escape(override.bias or ""), Escape(override.note or ""),
  }, "\t"), target)
  return true
end

function APOCLootPrio:BroadcastItemOverride(item)
  local key = self:GetItemKey(item)
  return self:SendOverrideV3(key, key and self:GetOverride(key) or nil)
end

function APOCLootPrio:ApplyOverrideV3(parts, sender)
  self:InitHardenedSync()
  local key = Unescape(parts[2])
  local incoming = VersionFromParts(parts[3], parts[4], parts[5], parts[6])
  local bias, note = Unescape(parts[7]), Unescape(parts[8])
  if key == "" or incoming.hash ~= OverrideHash(bias, note) then
    Diagnostic("corruptRecords")
    return false
  end

  local old = APOCLootPrioDB.overrides[key]
  local oldVersion = old and EnsureOverrideVersion(old) or NormalizeVersion()
  local comparison = CompareVersions(incoming, oldVersion)
  if comparison < 0 then Diagnostic("staleRecords"); return false end
  if comparison == 0 then return false end
  if old and incoming.counter == oldVersion.counter then
    Diagnostic("resolvedConflicts")
    RecordConflict("override", key, oldVersion, incoming, sender)
  end

  APOCLootPrioDB.overrides[key] = {
    bias = bias,
    note = note,
    revision = incoming.counter,
    updatedBy = Unescape(parts[4]) ~= "" and Unescape(parts[4]) or sender,
    updatedAt = time and time() or 0,
    syncVersion = incoming,
  }
  self:AdvanceHardenedSyncClock(incoming)
  self:SetRevision(math.max(self:GetRevision(), incoming.counter))
  if self.frame then self:Refresh() end
  return true
end

function APOCLootPrio:EnsureSettingsVersionCurrent(bumpWhenChanged)
  self:InitHardenedSync()
  local hash = SettingsHash()
  local current = NormalizeVersion(APOCLootPrioDB.sync.settingsVersion, hash)
  if bumpWhenChanged and current.hash ~= hash then current = self:NextHardenedSyncVersion(hash, current) end
  current.hash = hash
  APOCLootPrioDB.sync.settingsVersion = current
  return current
end

function APOCLootPrio:SendAccessSettings(target)
  local values = SettingsValues()
  local version = self:EnsureSettingsVersionCurrent(false)
  local counter, writer, rank, hash = VersionFields(version)
  local message = {"S3", counter, writer, rank, hash}
  for _, value in ipairs(values) do table.insert(message, Escape(value)) end
  self:SendSyncMessage(table.concat(message, "\t"), target)
end

function APOCLootPrio:BroadcastAccessSettings()
  self:EnsureSettingsVersionCurrent(true)
  self:SendAccessSettings()
end

function APOCLootPrio:ApplyAccessSettingsV3(parts, sender)
  self:InitHardenedSync()
  local incoming = VersionFromParts(parts[2], parts[3], parts[4], parts[5])
  local values = {}
  for index = 6, 14 do values[index - 5] = Unescape(parts[index]) end
  if incoming.hash ~= SettingsHash(values) then Diagnostic("corruptRecords"); return false end

  local current = self:EnsureSettingsVersionCurrent(false)
  local comparison = CompareVersions(incoming, current)
  if comparison < 0 then Diagnostic("staleRecords"); return false end
  if comparison == 0 then return false end
  if incoming.counter == current.counter then
    Diagnostic("resolvedConflicts")
    RecordConflict("settings", "shared", current, incoming, sender)
  end

  PreviousApplyIncomingAccessSettings(self, values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], sender)
  local trustedRank = tonumber(values[9])
  if trustedRank ~= nil then
    APOCLootPrioDB.sync.maxRankIndex = math.max(0, math.min(9, trustedRank))
  end
  APOCLootPrioDB.sync.settingsVersion = incoming
  self:AdvanceHardenedSyncClock(incoming)
  return true
end

function APOCLootPrio:SetSyncMaxRankIndex(rankIndex)
  self:EnsureSettingsVersionCurrent(false)
  rankIndex = math.max(0, math.min(9, tonumber(rankIndex) or 1))
  if APOCLootPrioDB.sync.maxRankIndex == rankIndex then return true, rankIndex end
  APOCLootPrioDB.sync.maxRankIndex = rankIndex
  self:BroadcastAccessSettings()
  return true, rankIndex
end

-- Ensure the previous settings state is captured before a local setter mutates it.
if PreviousSetFeatureAccessRank then
  function APOCLootPrio:SetFeatureAccessRank(...)
    self:EnsureSettingsVersionCurrent(false)
    return PreviousSetFeatureAccessRank(self, ...)
  end
end

if PreviousSetLootAutoTrackMode then
  function APOCLootPrio:SetLootAutoTrackMode(...)
    self:EnsureSettingsVersionCurrent(false)
    return PreviousSetLootAutoTrackMode(self, ...)
  end
end

if PreviousSetLootQualityTracked then
  function APOCLootPrio:SetLootQualityTracked(...)
    self:EnsureSettingsVersionCurrent(false)
    return PreviousSetLootQualityTracked(self, ...)
  end
end

local function SendAssignment(kind, value, setBy, version, target, queued)
  local counter, writer, rank, hash = VersionFields(version)
  local message = table.concat({kind, counter, writer, rank, hash, Escape(value or ""), Escape(setBy or "")}, "\t")
  if queued and APOCLootPrio.QueueLootSyncV2Message then
    APOCLootPrio:QueueLootSyncV2Message(message, target)
  else
    APOCLootPrio:SendSyncMessage(message, target)
  end
end

function APOCLootPrio:SendLootTrackerOwner(target)
  self:InitHardenedSync()
  local loot = APOCLootPrioDB.loot
  SendAssignment("AR3", loot.trackerOwner, loot.trackerOwnerSetBy, loot.trackerOwnerVersion, target)
  SendAssignment("AD3", loot.disenchanter, loot.disenchanterSetBy, loot.disenchanterVersion, target)
end

function APOCLootPrio:BroadcastLootTrackerOwner()
  self:SendLootTrackerOwner()
end

function APOCLootPrio:SetLootTrackerOwner(name, source, setAt, skipBroadcast)
  self:InitHardenedSync()
  if skipBroadcast then return PreviousSetLootTrackerOwner(self, name, source, setAt, true) end

  local oldOwner = self:GetLootTrackerOwner()
  local cleanName = name and string.match(name, "^%s*(.-)%s*$") or ""
  local oldAuthority = self:IsLocalLootSyncV2Authority()
  local changed = not SamePlayer(oldOwner or "", cleanName) or ((oldOwner or "") == "") ~= (cleanName == "")

  -- Queue a final canonical snapshot before an active runner hands authority off.
  -- The assignment is queued behind it so addon-message ordering cannot expose
  -- the new runner before the old runner's last complete state.
  if changed and oldAuthority and self.SendAllLootSessions then
    self.lastLootSyncV2FullSend = self.lastLootSyncV2FullSend or {}
    self.lastLootSyncV2FullSend.guild = nil
    self:SendAllLootSessions()
    self:SendLootSyncV2Transfer("SC", self:BuildLootSessionCatalogV3())
    self:QueueLootManifestV3()
  end

  local result = PreviousSetLootTrackerOwner(self, cleanName, source, setAt, true)
  local hash = AssignmentHash("runner", cleanName, source or self:GetPlayerDisplayName())
  APOCLootPrioDB.loot.trackerOwnerVersion = self:NextHardenedSyncVersion(hash, APOCLootPrioDB.loot.trackerOwnerVersion)
  SendAssignment("AR3", APOCLootPrioDB.loot.trackerOwner, APOCLootPrioDB.loot.trackerOwnerSetBy, APOCLootPrioDB.loot.trackerOwnerVersion, nil, changed and oldAuthority)
  return result
end

function APOCLootPrio:SetLootDisenchanter(name, source, setAt, skipBroadcast)
  self:InitHardenedSync()
  if skipBroadcast then return PreviousSetLootDisenchanter(self, name, source, setAt, true) end
  local result = PreviousSetLootDisenchanter(self, name, source, setAt, true)
  local cleanName = APOCLootPrioDB.loot.disenchanter or ""
  local hash = AssignmentHash("disenchanter", cleanName, source or self:GetPlayerDisplayName())
  APOCLootPrioDB.loot.disenchanterVersion = self:NextHardenedSyncVersion(hash, APOCLootPrioDB.loot.disenchanterVersion)
  SendAssignment("AD3", cleanName, APOCLootPrioDB.loot.disenchanterSetBy, APOCLootPrioDB.loot.disenchanterVersion)
  return result
end

function APOCLootPrio:ApplyAssignmentV3(kind, parts, sender)
  self:InitHardenedSync()
  local incoming = VersionFromParts(parts[2], parts[3], parts[4], parts[5])
  local value, setBy = Unescape(parts[6]), Unescape(parts[7])
  local label = kind == "AR3" and "runner" or "disenchanter"
  if incoming.hash ~= AssignmentHash(label, value, setBy) then Diagnostic("corruptRecords"); return false end

  local field = kind == "AR3" and "trackerOwnerVersion" or "disenchanterVersion"
  local current = NormalizeVersion(APOCLootPrioDB.loot[field])
  local comparison = CompareVersions(incoming, current)
  if comparison < 0 then Diagnostic("staleRecords"); return false end
  if comparison == 0 then return false end
  if incoming.counter == current.counter then
    Diagnostic("resolvedConflicts")
    RecordConflict(label, label, current, incoming, sender)
  end

  if kind == "AR3" then
    PreviousSetLootTrackerOwner(self, value, setBy ~= "" and setBy or sender, time and time() or 0, true)
  else
    PreviousSetLootDisenchanter(self, value, setBy ~= "" and setBy or sender, time and time() or 0, true)
  end
  APOCLootPrioDB.loot[field] = incoming
  self:AdvanceHardenedSyncClock(incoming)
  return true
end

function APOCLootPrio:GetLootAuthorityEpoch()
  self:InitHardenedSync()
  local owner = self:GetLootTrackerOwner()
  if owner and owner ~= "" then return NormalizeVersion(APOCLootPrioDB.loot.trackerOwnerVersion) end
  local authority = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or ""
  return NormalizeVersion({
    counter = 0,
    writer = PlayerKey(authority),
    rank = WriterRank(authority),
    hash = TextHash(Canonical({"automatic-authority", PlayerKey(authority)})),
  })
end

local function SameVersion(left, right)
  return CompareVersions(left, right) == 0
end

function APOCLootPrio:NextLootSyncV3TransferID()
  self.lootSyncV3Counter = (self.lootSyncV3Counter or 0) + 1
  return tostring(time and time() or 0) .. ":" .. tostring(self.lootSyncV3Counter) .. ":" .. PlayerKey(self:GetPlayerDisplayName())
end



function APOCLootPrio:ReceiveLootSyncV3Chunk(parts, sender)
  local transferID, kind = parts[2], parts[3]
  local index, total = tonumber(parts[4]), tonumber(parts[5])
  local payloadHash = parts[6]
  local epoch = VersionFromParts(parts[7], parts[8], parts[9], parts[10])
  local chunk = parts[11] or ""
  if not transferID or transferID == "" or not kind or not index or not total then return end
  if index < 1 or total < 1 or index > total or total > 4096 then Diagnostic("corruptTransfers"); return end
  if not SameVersion(epoch, self:GetLootAuthorityEpoch()) then Diagnostic("rejectedAuthorityEpoch"); return end

  self.incomingLootSyncV3 = self.incomingLootSyncV3 or {}
  local key = PlayerKey(sender) .. ":" .. transferID
  local transfer = self.incomingLootSyncV3[key]
  if not transfer or transfer.kind ~= kind or transfer.total ~= total or transfer.hash ~= payloadHash or not SameVersion(transfer.epoch, epoch) then
    transfer = {kind = kind, total = total, hash = payloadHash, epoch = epoch, chunks = {}, received = 0, startedAt = time and time() or 0}
    self.incomingLootSyncV3[key] = transfer
  end

  if not transfer.chunks[index] then
    transfer.chunks[index] = chunk
    transfer.received = transfer.received + 1
    transfer.lastProgressAt = time and time() or 0
  elseif transfer.chunks[index] ~= chunk then
    self.incomingLootSyncV3[key] = nil
    Diagnostic("corruptTransfers")
    return
  end
  if transfer.received < total then return end

  local encoded = table.concat(transfer.chunks, "")
  self.incomingLootSyncV3[key] = nil
  if TextHash(encoded) ~= payloadHash then Diagnostic("corruptTransfers"); return end

  self.currentLootSyncV3Epoch = epoch
  self.currentLootSyncV3PayloadHash = payloadHash
  local decoded = Unescape(encoded)
  local changed = nil
  if kind == "SC" then
    changed = self:ApplyLootSessionCatalogV3(decoded, sender)
  else
    changed = PreviousProcessLootSyncV2Payload and PreviousProcessLootSyncV2Payload(self, kind, decoded, sender)
  end
  self.currentLootSyncV3Epoch = nil
  self.currentLootSyncV3PayloadHash = nil
  if changed then Diagnostic("appliedLootUpdates") end
end







function APOCLootPrio:QueueLootManifestV3(target)
  local epoch = self:GetLootAuthorityEpoch()
  local counter, writer, rank, epochHash = VersionFields(epoch)
  local digest, sessionCount, dropCount = self:GetLootSessionManifest()
  local message = table.concat({
    "LM3", counter, writer, rank, epochHash, digest,
    tostring(sessionCount), tostring(dropCount), Escape(APOCLootPrioDB.loot.activeSessionKey or ""),
  }, "\t")
  self:QueueLootSyncV2Message(message, target)
end

function APOCLootPrio:ApplyLootManifestV3(parts, sender)
  local epoch = VersionFromParts(parts[2], parts[3], parts[4], parts[5])
  if not SameVersion(epoch, self:GetLootAuthorityEpoch()) then Diagnostic("rejectedAuthorityEpoch"); return false end
  local expectedDigest = tostring(parts[6] or "")
  local localDigest, localSessions, localDrops = self:GetLootSessionManifest()
  local peerKey = ShortName(sender)
  local peer = APOCLootPrioDB.sync.peerStates[peerKey] or {}
  peer.lootDigest = expectedDigest
  peer.lootSessionCount = tonumber(parts[7]) or 0
  peer.lootDropCount = tonumber(parts[8]) or 0
  peer.lootActiveSession = Unescape(parts[9])
  peer.lootVerified = expectedDigest ~= "" and expectedDigest == localDigest
    and peer.lootSessionCount == localSessions and peer.lootDropCount == localDrops
  peer.seenAt = time and time() or 0
  APOCLootPrioDB.sync.peerStates[peerKey] = peer

  if peer.lootVerified then
    self.lootSyncV3RetryCounts = self.lootSyncV3RetryCounts or {}
    self.lootSyncV3RetryCounts[peerKey .. ":" .. expectedDigest] = nil
    peer.lootRetryWindowAt = nil
    Diagnostic("verifiedLootSnapshots")
    if self.RefreshSyncedClientsPanel then self:RefreshSyncedClientsPanel() end
    return true
  end

  Diagnostic("lootManifestMismatches")
  self.lootSyncV3RetryCounts = self.lootSyncV3RetryCounts or {}
  local retryKey = peerKey .. ":" .. expectedDigest
  local now = time and time() or 0
  -- Allow a later periodic manifest to restart recovery after a temporary
  -- outage. The previous two-attempt lifetime cap stranded stale awards.
  if not peer.lootRetryWindowAt or now - peer.lootRetryWindowAt >= 30 then
    peer.lootRetryWindowAt = now
    self.lootSyncV3RetryCounts[retryKey] = nil
    peer.lootRetryWarningShown = nil
  end
  local retries = tonumber(self.lootSyncV3RetryCounts[retryKey]) or 0
  if retries < 2 then
    self.lootSyncV3RetryCounts[retryKey] = retries + 1
    if C_Timer and C_Timer.After then
      local runID = self.GetActiveRunID and self:GetActiveRunID()
      C_Timer.After(1 + retries, function()
        if not APOCLootPrio or not APOCLootPrio.RequestLootSessionSync then return end
        if runID and APOCLootPrio:GetActiveRunID() ~= runID then return end
        local current = APOCLootPrioDB.sync.peerStates[peerKey]
        if not current or current.lootVerified or current.lootDigest ~= expectedDigest then return end
        APOCLootPrio:RequestLootSessionSync()
      end)
    end
  elseif self.Print and not peer.lootRetryWarningShown then
    peer.lootRetryWarningShown = true
    self:Print("Loot sync is incomplete; automatic recovery will retry. Use /priobeta-run for delivery diagnostics.")
  end
  if self.RefreshSyncedClientsPanel then self:RefreshSyncedClientsPanel() end
  return false
end

function APOCLootPrio:SendAllHardenedState(target)
  self:InitHardenedSync()
  if not self:IsTrustedSender(self:GetPlayerDisplayName()) then return false end
  local keys = {}
  for key in pairs(APOCLootPrioDB.overrides or {}) do table.insert(keys, key) end
  table.sort(keys)
  for _, key in ipairs(keys) do self:SendOverrideV3(key, APOCLootPrioDB.overrides[key], target) end
  self:SendAccessSettings(target)
  self:SendLootTrackerOwner(target)
  local digest, count = self:GetOverrideManifest()
  local manifest = table.concat({"M3", digest, tostring(count), tostring(APOCLootPrioDB.sync.logicalClock or 0), Escape(self:GetAddonVersion())}, "\t")
  self:SendSyncMessage(manifest, target)
  return true
end

function APOCLootPrio:RequestSync()
  self:InitHardenedSync()
  local nonce = self:NextLootSyncV3TransferID()
  self:SendSyncMessage(table.concat({"H3", SYNC_PROTOCOL, Escape(self:GetAddonVersion()), nonce}, "\t"))
  self:RequestLootSessionSync()
end

local function RecordPeer(sender, kind, version, protocol)
  if APOCLootPrio.RecordSyncPeer then APOCLootPrio:RecordSyncPeer(sender, kind, version) end
  local peer = APOCLootPrioDB and APOCLootPrioDB.sync and APOCLootPrioDB.sync.peers and APOCLootPrioDB.sync.peers[ShortName(sender)]
  if peer then peer.syncProtocol = protocol or 3 end
end

function APOCLootPrio:HandleControlSyncMessage(message, sender)
  if SamePlayer(sender, self:GetPlayerDisplayName()) then return end
  local parts = SplitTabs(message)
  local kind = parts[1]

  if kind == "C3" then
    if not self:IsTrustedSender(sender) then Diagnostic("rejectedUntrusted"); return end
    local transferID, index, total, hash = parts[2], tonumber(parts[3]), tonumber(parts[4]), parts[5]
    local chunk = parts[6] or ""
    if not transferID or transferID == "" or not index or not total or index < 1 or index > total or total > 4096 then
      Diagnostic("corruptTransfers")
      return
    end
    self.incomingControlSyncV3 = self.incomingControlSyncV3 or {}
    local key = PlayerKey(sender) .. ":" .. transferID
    local transfer = self.incomingControlSyncV3[key]
    if not transfer or transfer.total ~= total or transfer.hash ~= hash then
      transfer = {total = total, hash = hash, chunks = {}, received = 0, startedAt = time and time() or 0}
      self.incomingControlSyncV3[key] = transfer
    end
    if not transfer.chunks[index] then
      transfer.chunks[index] = chunk
      transfer.received = transfer.received + 1
    elseif transfer.chunks[index] ~= chunk then
      self.incomingControlSyncV3[key] = nil
      Diagnostic("corruptTransfers")
      return
    end
    if transfer.received < total then return end
    local encoded = table.concat(transfer.chunks, "")
    self.incomingControlSyncV3[key] = nil
    if TextHash(encoded) ~= hash then Diagnostic("corruptTransfers"); return end
    self:HandleSyncMessage(Unescape(encoded), sender)
    return
  end

  if kind == "H3" then
    if not self:IsGuildSyncSender(sender) then return end
    RecordPeer(sender, "Hardened Sync", Unescape(parts[3]), 3)
    self:SendAllHardenedState(sender)
    if self:IsTrustedSender(sender) and self:IsTrustedSender(self:GetPlayerDisplayName()) then
      self:SendSyncMessage("K3\t" .. Escape(parts[4] or ""), sender)
    end
    return
  end

  if kind == "K3" then
    if self:IsTrustedSender(sender) then self:SendAllHardenedState(sender) end
    return
  end

  if kind == "O3" or kind == "S3" or kind == "AR3" or kind == "AD3" or kind == "M3" then
    if not self:IsTrustedSender(sender) then Diagnostic("rejectedUntrusted"); return end
    RecordPeer(sender, "Hardened Sync", nil, 3)
    if kind == "O3" then
      self:ApplyOverrideV3(parts, sender)
    elseif kind == "S3" then
      self:ApplyAccessSettingsV3(parts, sender)
    elseif kind == "AR3" or kind == "AD3" then
      self:ApplyAssignmentV3(kind, parts, sender)
    else
      local peer = APOCLootPrioDB.sync.peerStates[ShortName(sender)] or {}
      peer.overrideDigest = parts[2]
      peer.overrideCount = tonumber(parts[3]) or 0
      peer.logicalClock = tonumber(parts[4]) or 0
      peer.seenAt = time and time() or 0
      APOCLootPrioDB.sync.peerStates[ShortName(sender)] = peer
    end
    return
  end

  -- Mutation protocols before V3 are intentionally read-only. They have no
  -- deterministic conflict token and therefore cannot safely change V3 state.
  if kind == "U" or kind == "S" or kind == "LT" or kind == "LH" or kind == "LD" or kind == "LE" or kind == "LX" or kind == "Q2" then
    Diagnostic("rejectedLegacyMutations")
    RecordPeer(sender, "Update required", nil, 2)
    return
  end

  if kind == "H" or kind == "R" or kind == "H2" then
    local oldVersion = (kind == "H" or kind == "R") and Unescape(parts[3]) or nil
    RecordPeer(sender, "Update required", oldVersion, kind == "H2" and 2 or 1)
    if self:IsGuildSyncSender(sender) then self:SendSyncMessage("V\t" .. Escape(self:GetAddonVersion()), sender) end
    return
  end

  -- Version and audit packets do not mutate canonical synchronized state.

end

function APOCLootPrio:PrintHardenedSyncStatus()
  self:InitHardenedSync()
  local epoch = self:GetLootAuthorityEpoch()
  local digest, overrideCount = self:GetOverrideManifest()
  local settings = NormalizeVersion(APOCLootPrioDB.sync.settingsVersion)
  local diagnostics = APOCLootPrioDB.sync.diagnostics or {}
  local authority = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or "none"
  local active = APOCLootPrioDB.loot.sessions[APOCLootPrioDB.loot.activeSessionKey or ""]
  local lootDigest, sessionCount, dropCount = self:GetLootSessionManifest()
  self:Print("Sync V3 | authority " .. tostring(ShortName(authority) or "none") .. " | epoch " .. tostring(epoch.counter) .. "/" .. tostring(ShortName(epoch.writer) or epoch.writer))
  self:Print("Overrides " .. tostring(overrideCount) .. " | digest " .. tostring(digest) .. " | settings " .. tostring(settings.counter) .. "/" .. tostring(ShortName(settings.writer) or settings.writer))
  self:Print("Loot manifest " .. tostring(lootDigest) .. " | sessions " .. tostring(sessionCount) .. " | drops " .. tostring(dropCount))
  if active then
    self:Print("Active session rev " .. tostring(active.revision or 0) .. " | drops " .. tostring(#(active.drops or {})) .. " | synced from " .. tostring(active.syncedFrom or "local"))
  else
    self:Print("No active loot session.")
  end
  self:Print("Safety counters: conflicts " .. tostring(diagnostics.resolvedConflicts or 0)
    .. ", corrupt " .. tostring((diagnostics.corruptRecords or 0) + (diagnostics.corruptTransfers or 0))
    .. ", stale " .. tostring(diagnostics.staleRecords or 0)
    .. ", wrong authority " .. tostring((diagnostics.rejectedAuthorityEpoch or 0) + (diagnostics.rejectedAuthoritySender or 0))
    .. ", legacy blocked " .. tostring(diagnostics.rejectedLegacyMutations or 0) .. ".")
end

-- Expire abandoned V3 chunk assemblies and request a fresh state after the
-- guild roster is available. This avoids a login race where rank validation
-- cannot yet identify a trusted sender.
if CreateFrame then
  local maintenance = CreateFrame("Frame")
  maintenance:RegisterEvent("PLAYER_ENTERING_WORLD")
  maintenance:RegisterEvent("GUILD_ROSTER_UPDATE")
  maintenance.elapsed = 0
  maintenance.rosterRequested = false
  maintenance:SetScript("OnUpdate", function(frame, elapsed)
    frame.elapsed = frame.elapsed + (elapsed or 0)
    if frame.elapsed < 5 then return end
    frame.elapsed = 0
    local now = time and time() or 0
    for key, transfer in pairs(APOCLootPrio.incomingLootSyncV3 or {}) do
      local progressAt = transfer.lastProgressAt or transfer.startedAt
      if now > 0 and progressAt and (now - progressAt) > LOOT_TRANSFER_TIMEOUT then
        APOCLootPrio.incomingLootSyncV3[key] = nil
        Diagnostic("expiredTransfers")
      end
    end
    for key, transfer in pairs(APOCLootPrio.incomingControlSyncV3 or {}) do
      if now > 0 and transfer.startedAt and (now - transfer.startedAt) > LOOT_TRANSFER_TIMEOUT then
        APOCLootPrio.incomingControlSyncV3[key] = nil
        Diagnostic("expiredTransfers")
      end
    end
  end)
  maintenance:SetScript("OnEvent", function(frame, event)
    if event == "PLAYER_ENTERING_WORLD" then frame.rosterRequested = false end
    if C_Timer and C_Timer.After and not frame.rosterRequested then
      frame.rosterRequested = true
      C_Timer.After(event == "PLAYER_ENTERING_WORLD" and 4 or 1, function()
        if APOCLootPrio and APOCLootPrio.RequestSync then APOCLootPrio:RequestSync() end
      end)
    end
  end)
end
