-- Live Raid Phase 1: guild discovery + out-of-raid watch, keyed by Live Raid id.
--
-- Mapping: Live Raid id == Multi-Run Run ID (stable string from CreateMultiRun).
-- In-raid live loot still uses existing RAID/PARTY Q4/L4/LM4/HB4/AS4 paths in
-- MultiRun.lua. This module adds:
--   * guild-scoped live-raid beacons (small; not full loot)
--   * out-of-raid watch via WHISPER pull from the runner (full snapshot)
--   * SelectLiveRaid for view-only watch (does not grant CanEditLootTracker)
-- Guild archive GA4/GH4 remains for awarded history only — not live visibility.

local LIVE_PROTOCOL = "4"
local BETA_PREFIX = "APOCLPMR"
local WATCH_CHUNK_BYTES = 68
local GUILD_BEACON_INTERVAL = 20
local GUILD_BEACON_STALE = 90
local WATCH_REFRESH_MIN = 8

local PreviousCanEditLootTracker = APOCLootPrio.CanEditLootTracker
local PreviousSetLootTrackerOwner = APOCLootPrio.SetLootTrackerOwner
local PreviousCreateMultiRun = APOCLootPrio.CreateMultiRun
local PreviousSendMultiRunRunnerHeartbeat = APOCLootPrio.SendMultiRunRunnerHeartbeat
local PreviousApplyMultiRunAssignment = APOCLootPrio.ApplyMultiRunAssignment

local function Now()
  return time and time() or 0
end

local function ShortName(name)
  return string.match(tostring(name or ""), "^([^%-]+)") or tostring(name or "")
end

local function PlayerKey(name)
  return string.lower(ShortName(name))
end

local function SamePlayer(left, right)
  local a, b = PlayerKey(left), PlayerKey(right)
  return a ~= "" and a == b
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

local function IsRaidGroup()
  if IsInRaid and IsInRaid() then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  return GetNumGroupMembers and GetNumGroupMembers() > 5 or false
end

local function IsPartyGroup()
  if IsRaidGroup() then return false end
  if GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then return true end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return true end
  return GetNumGroupMembers and GetNumGroupMembers() > 1 or false
end

local function GetGroupChannel()
  if IsRaidGroup() then return "RAID" end
  if IsPartyGroup() then return "PARTY" end
  return nil
end

local function IsLocalGroupLeaderNow()
  if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
  if IsRaidLeader and IsRaidLeader() then return true end
  if IsPartyLeader and IsPartyLeader() then return true end
  return false
end

local function IsInGuildNow()
  return IsInGuild and IsInGuild() or false
end

function APOCLootPrio:InitLiveRaid()
  self:InitMultiRun()
  APOCLootPrioDB.liveRaid = APOCLootPrioDB.liveRaid or {}
  local state = APOCLootPrioDB.liveRaid
  state.registry = state.registry or {}
  state.selectedLiveRaidID = state.selectedLiveRaidID or nil
  state.watchOnly = state.watchOnly and true or false
  state.watchRestoreRunID = state.watchRestoreRunID or nil
  state.lastGuildBeaconAt = tonumber(state.lastGuildBeaconAt) or 0
  state.diagnostics = state.diagnostics or {
    beaconsSent = 0,
    beaconsApplied = 0,
    watchRequests = 0,
    watchSnapshots = 0,
    rejectedWatch = 0,
  }
  return state
end

function APOCLootPrio:GetLiveRaidID()
  -- Live Raid id maps 1:1 to the Multi-Run Run ID.
  return self:GetActiveRunID()
end

function APOCLootPrio:GetLiveRaidShortID(liveRaidID)
  return self:GetRunShortID(liveRaidID or self:GetLiveRaidID())
end

function APOCLootPrio:IsLiveRaidWatchOnly()
  local state = self:InitLiveRaid()
  return state.watchOnly and true or false
end

function APOCLootPrio:GetSelectedLiveRaidID()
  local state = self:InitLiveRaid()
  return state.selectedLiveRaidID or self:GetActiveRunID()
end

local function LiveRaidLabelFromRun(self, run)
  if not run then return "Live Raid" end
  local zone = ""
  if GetRealZoneText then zone = GetRealZoneText() or "" end
  if zone == "" and GetZoneText then zone = GetZoneText() or "" end
  local short = self:GetRunShortID(run.id)
  if zone ~= "" then return zone .. " [" .. short .. "]" end
  return "Run " .. short
end

local function LiveRaidBossHint()
  if GetRealZoneText then
    local zone = GetRealZoneText()
    if zone and zone ~= "" then return zone end
  end
  if GetZoneText then return GetZoneText() or "" end
  return ""
end

local function LiveRaidRevision(run)
  if not run then return 0 end
  local ownerVersion = run.ownerVersion or {}
  local counter = tonumber(ownerVersion.counter) or 0
  local logical = tonumber(run.logicalClock) or 0
  local heartbeat = tonumber(run.lastAuthorityHeartbeatAt) or 0
  return math.max(counter, logical) * 100000 + math.fmod(heartbeat, 100000)
end

function APOCLootPrio:UpsertLiveRaidRegistry(entry, sender)
  if not entry or not entry.id or entry.id == "" then return false end
  local state = self:InitLiveRaid()
  local existing = state.registry[entry.id] or {}
  local incomingHeartbeat = tonumber(entry.lastHeartbeat) or 0
  local existingHeartbeat = tonumber(existing.lastHeartbeat) or 0
  local incomingRevision = tonumber(entry.revision) or 0
  local existingRevision = tonumber(existing.revision) or 0
  if existing.id and incomingHeartbeat < existingHeartbeat and incomingRevision <= existingRevision then
    return false
  end
  state.registry[entry.id] = {
    id = entry.id,
    name = entry.name or existing.name or ("Run " .. self:GetRunShortID(entry.id)),
    runner = entry.runner or existing.runner,
    bossHint = entry.bossHint or existing.bossHint or "",
    lastHeartbeat = math.max(incomingHeartbeat, existingHeartbeat),
    revision = math.max(incomingRevision, existingRevision),
    announcedBy = sender or existing.announcedBy,
    updatedAt = Now(),
  }
  state.diagnostics.beaconsApplied = (tonumber(state.diagnostics.beaconsApplied) or 0) + 1
  return true
end

function APOCLootPrio:PruneLiveRaidRegistry()
  local state = self:InitLiveRaid()
  local now = Now()
  if now <= 0 then return end
  for id, entry in pairs(state.registry) do
    local last = tonumber(entry.lastHeartbeat) or tonumber(entry.updatedAt) or 0
    if last > 0 and (now - last) > GUILD_BEACON_STALE then
      state.registry[id] = nil
    end
  end
end

function APOCLootPrio:GetKnownLiveRaids()
  self:PruneLiveRaidRegistry()
  local state = self:InitLiveRaid()
  local list = {}
  local activeID = self:GetActiveRunID()
  local selectedID = state.selectedLiveRaidID

  -- Always surface the local active run when present (status == "active").
  -- In a group, GetActiveRun() with status active must appear even if the
  -- guild registry is empty.
  local run = self:GetActiveRun()
  -- The header already prints this Run ID. A Closed & Saved session on
  -- screen must not hide it. List it whenever the run exists.
  local showLocal = run and run.id and run.status ~= "expired"
  if showLocal then
    local health = self:GetMultiRunRunnerHealth()
    table.insert(list, {
      id = run.id,
      name = LiveRaidLabelFromRun(self, run),
      runner = self:GetLootSyncAuthorityName() or run.owner,
      bossHint = LiveRaidBossHint(),
      lastHeartbeat = tonumber(run.lastAuthorityHeartbeatAt) or Now(),
      revision = LiveRaidRevision(run),
      isLocal = true,
      isSelected = (selectedID or activeID) == run.id,
      health = health,
      online = health == "active" or health == "waiting",
    })
  end

  local seen = {}
  for _, row in ipairs(list) do seen[row.id] = true end

  for id, entry in pairs(state.registry) do
    if not seen[id] then
      local age = 0
      local last = tonumber(entry.lastHeartbeat) or 0
      if last > 0 and Now() > 0 then age = math.max(0, Now() - last) end
      local online = age <= GUILD_BEACON_STALE and age <= 45
      table.insert(list, {
        id = id,
        name = entry.name or ("Run " .. self:GetRunShortID(id)),
        runner = entry.runner,
        bossHint = entry.bossHint or "",
        lastHeartbeat = last,
        revision = tonumber(entry.revision) or 0,
        isLocal = false,
        isSelected = selectedID == id,
        health = online and "active" or "offline",
        online = online,
      })
    end
  end

  table.sort(list, function(a, b)
    if a.isLocal ~= b.isLocal then return a.isLocal end
    if (tonumber(a.lastHeartbeat) or 0) ~= (tonumber(b.lastHeartbeat) or 0) then
      return (tonumber(a.lastHeartbeat) or 0) > (tonumber(b.lastHeartbeat) or 0)
    end
    return tostring(a.name or "") < tostring(b.name or "")
  end)
  return list
end

function APOCLootPrio:BuildLiveRaidBeaconPayload()
  local run = self:GetActiveRun()
  if not run or run.status ~= "active" then return nil end
  if not self:IsLocalLootSyncV2Authority() and not GetGroupChannel() then return nil end
  -- Prefer runner beacons; leaders may announce an unowned run briefly.
  if not self:IsLocalLootSyncV2Authority() then
    local owner = run.owner
    if owner and owner ~= "" then return nil end
  end
  local runner = self:GetLootSyncAuthorityName() or self:GetPlayerDisplayName()
  return table.concat({
    "LB4",
    Escape(run.id),
    Escape(LiveRaidLabelFromRun(self, run)),
    Escape(runner or ""),
    Escape(LiveRaidBossHint()),
    tostring(LiveRaidRevision(run)),
    tostring(Now()),
    Escape(self:GetAddonVersion()),
  }, "\t")
end

function APOCLootPrio:BroadcastLiveRaidBeacon()
  if not self:IsLocalLootSyncV2Authority() then return false end
  local payload = self:BuildLiveRaidBeaconPayload()
  if not payload then return false end
  local state, run = self:InitLiveRaid(), self:GetActiveRun()
  state.lastGuildBeaconAt = Now()
  state.diagnostics.beaconsSent = (tonumber(state.diagnostics.beaconsSent) or 0) + 1
  self:UpsertLiveRaidRegistry({id=run.id, name=LiveRaidLabelFromRun(self, run),
    runner=self:GetLootSyncAuthorityName() or run.owner, bossHint=LiveRaidBossHint(),
    lastHeartbeat=Now(), revision=LiveRaidRevision(run)}, self:GetPlayerDisplayName())
  local sent = false
  if GetGroupChannel() then sent = self:QueueMultiRunLive(payload) end
  if IsInGuildNow() then sent = self:QueueMultiRunGuild(payload) or sent end
  return sent
end

function APOCLootPrio:RequestLiveRaidRegistry()
  local payload = table.concat({
    "LR4", LIVE_PROTOCOL, Escape(self:GetAddonVersion()), Escape(self:NextMultiRunTransferID("live-registry")),
  }, "\t")
  local sent = false
  if IsInGuildNow() then
    sent = self:QueueMultiRunGuild(payload) and true or false
  end
  if self.QueueMultiRunLive then
    sent = (self:QueueMultiRunLive(payload) and true or false) or sent
  end
  return sent
end

-- Panel open / Refresh: start and announce the local Live Raid immediately.
-- Does not wait for the 20s guild beacon timer. Watch-only and history edit
-- stay out of group, so this only creates a run for ML / leader / runner.
function APOCLootPrio:AnnounceLocalLiveRaid(reason)
  local state = self:InitLiveRaid()
  state.lastAnnounceReason, state.lastAnnounceAt = reason or "announce", Now()
  -- Opening or refreshing a panel is not a runner assignment.
  if self:IsLocalLootSyncV2Authority() then self:BroadcastLiveRaidBeacon()
  elseif GetGroupChannel() then self:RequestMultiRunSync() end
  if IsInGuildNow() then self:RequestLiveRaidRegistry() end
  return self:GetActiveRun()
end

function APOCLootPrio:ApplyLiveRaidBeacon(parts, sender)
  local inGroup = self.IsCurrentGroupMember and self:IsCurrentGroupMember(sender)
  if not (self:IsGuildSyncSender(sender) or inGroup) then return end
  local id = Unescape(parts[2])
  if not id or id == "" then return end
  local runner = Unescape(parts[4])
  if not SamePlayer(sender, runner) then return end
  local changed = self:UpsertLiveRaidRegistry({
    id = id,
    name = Unescape(parts[3]),
    runner = runner,
    bossHint = Unescape(parts[5]),
    revision = tonumber(parts[6]) or 0,
    lastHeartbeat = tonumber(parts[7]) or Now(),
  }, sender)
  -- Beacons also prove the runner is alive for the active-run health line.
  local run = self.GetActiveRun and self:GetActiveRun() or nil
  local authority = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or nil
  if run and (SamePlayer(sender, authority) or SamePlayer(runner, authority) or (run.id and id == run.id)) then
    if SamePlayer(sender, authority) or SamePlayer(runner, authority) then
      run.lastAuthorityHeartbeatAt = Now()
      run.lastAuthorityHeartbeatFrom = sender or runner
    end
  end
  if changed then
    local state = self:InitLiveRaid()
    state.lastLiveLog = "Heard live raid from " .. tostring(sender or "?") .. "."
    if state.selectedLiveRaidID == id and state.watchOnly then
      local entry = state.registry[id]
      local lastPull = tonumber(state.lastWatchPullAt) or 0
      local revision = entry and tonumber(entry.revision) or 0
      local lastRev = tonumber(state.lastWatchRevision) or -1
      if revision > lastRev and (Now() <= 0 or (Now() - lastPull) >= WATCH_REFRESH_MIN) then
        self:RequestLiveRaidWatchSnapshot(id)
      end
    end
    if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
  end
end

function APOCLootPrio:HandleLiveRaidRegistryRequest(parts, sender)
  local inGroup = self.IsCurrentGroupMember and self:IsCurrentGroupMember(sender)
  if not (self:IsGuildSyncSender(sender) or inGroup) then return end
  if not self:IsLocalLootSyncV2Authority() then return end
  local run = self:GetActiveRun()
  if not run or run.status ~= "active" then return end
  -- Reply with a beacon (guild) so the requester updates their registry.
  self:BroadcastLiveRaidBeacon()
end

function APOCLootPrio:QueueLiveRaidWatchWhisper(message, target)
  if not target or target == "" then return false end
  return self:QueueMultiRunGuild(message, ShortName(target))
end

function APOCLootPrio:RequestLiveFromSyncedPeers()
  if GetGroupChannel() then return self:RequestMultiRunSync() end
  return self:RequestLiveRaidRegistry()
end

function APOCLootPrio:RequestLiveRaidWatchSnapshot(liveRaidID)
  local state = self:InitLiveRaid()
  liveRaidID = liveRaidID or state.selectedLiveRaidID
  if not liveRaidID or liveRaidID == "" then return false end
  local entry = state.registry[liveRaidID]
  local runner = entry and entry.runner
  if not runner or runner == "" then
    -- silent
    return false
  end
  if SamePlayer(runner, self:GetPlayerDisplayName()) then
    -- Local runner already has the data.
    return false
  end
  state.lastWatchPullAt = Now()
  state.diagnostics.watchRequests = (tonumber(state.diagnostics.watchRequests) or 0) + 1
  return self:QueueLiveRaidWatchWhisper(table.concat({
    "LW4", Escape(liveRaidID), LIVE_PROTOCOL, Escape(self:GetAddonVersion()), Escape(self:NextMultiRunTransferID("live-watch")),
  }, "\t"), runner)
end

function APOCLootPrio:SendLiveRaidWatchTransfer(target, kind, payload, liveRaidID)
  local run = self:GetActiveRun()
  liveRaidID = liveRaidID or (run and run.id)
  if not run or not liveRaidID or liveRaidID ~= run.id then return false end
  if not self:IsLocalLootSyncV2Authority() then return false end
  if not target or target == "" then return false end
  local encoded = Escape(payload or "")
  local transferID = self:NextMultiRunTransferID("watch")
  local total = math.max(1, math.ceil(string.len(encoded) / WATCH_CHUNK_BYTES))
  local payloadHash = TextHash(encoded)
  local epoch = self:GetLootAuthorityEpoch()
  local counter = tostring(epoch.counter or 0)
  local writer = Escape(epoch.writer or "")
  local rank = tostring(epoch.rank or 99)
  local epochHash = tostring(epoch.hash or "")
  for index = 1, total do
    local first = ((index - 1) * WATCH_CHUNK_BYTES) + 1
    local chunk = string.sub(encoded, first, first + WATCH_CHUNK_BYTES - 1)
    self:QueueLiveRaidWatchWhisper(table.concat({
      "LQ4", Escape(liveRaidID), transferID, kind, tostring(index), tostring(total), payloadHash,
      counter, writer, rank, epochHash, chunk,
    }, "\t"), target)
  end
  return true
end


-- Live loot uses only run-scoped Q4/LQ4 snapshots; name-only transports removed.

function APOCLootPrio:ReplyLiveRaidWatchRequest(parts, sender)
  local liveRaidID = Unescape(parts[2])
  local run = self:GetActiveRun()
  if liveRaidID == "CURRENT" or liveRaidID == "*" or liveRaidID == "" then
    liveRaidID = run and run.id or nil
  end
  if not run or not liveRaidID or liveRaidID ~= run.id or not self:IsLocalLootSyncV2Authority() then
    local state = self:InitLiveRaid()
    state.diagnostics.rejectedWatch = (tonumber(state.diagnostics.rejectedWatch) or 0) + 1
    return
  end
  local inGroup = self.IsCurrentGroupMember and self:IsCurrentGroupMember(sender)
  if not (self:IsGuildSyncSender(sender) or inGroup) then return end
  local target = ShortName(sender)
  local payload = self:BuildLiveRaidBeaconPayload()
  if payload then self:QueueLiveRaidWatchWhisper(payload, target) end
  for _, session in ipairs(self:GetActiveRunSessions()) do
    local payload = self:BuildLootSessionSyncPayload(session, APOCLootPrioDB.loot.activeSessionKey == session.key)
    if payload then self:SendLiveRaidWatchTransfer(target, "FS", payload, liveRaidID) end
  end
  self:SendLiveRaidWatchTransfer(target, "SC", self:BuildLootSessionCatalogV3(), liveRaidID)
  if self.Print then
    -- silent
  end
end

function APOCLootPrio:ReceiveLiveRaidWatchChunk(parts, sender)
  local liveRaidID = Unescape(parts[2])
  local state = self:InitLiveRaid()
  if not liveRaidID or liveRaidID == "" then return end
  local entry = state.registry[liveRaidID]
  if not state.watchOnly or state.selectedLiveRaidID ~= liveRaidID or GetGroupChannel()
    or not entry or not entry.runner or not SamePlayer(sender, entry.runner)
    or not self:IsGuildSyncSender(sender) then
    state.diagnostics.rejectedWatch = (tonumber(state.diagnostics.rejectedWatch) or 0) + 1
    return
  end

  local transferID, kind = parts[3], parts[4]
  local index, total, hash = tonumber(parts[5]), tonumber(parts[6]), parts[7]
  local chunk = parts[12] or ""
  if kind ~= "FS" and kind ~= "SC" then return end
  local epochKey = table.concat({parts[8] or "", parts[9] or "", parts[10] or "", parts[11] or ""}, ":")
  if not transferID or not kind or not index or not total or index < 1 or index > total or total > 4096 then
    self:MultiRunDiagnostic("corruptTransfers")
    return
  end

  self.incomingLiveRaidWatch = self.incomingLiveRaidWatch or {}
  local key = PlayerKey(sender) .. ":" .. liveRaidID .. ":" .. transferID
  local transfer = self.incomingLiveRaidWatch[key]
  if not transfer or transfer.total ~= total or transfer.hash ~= hash or transfer.kind ~= kind then
    transfer = {
      epochKey = epochKey,
      liveRaidID = liveRaidID,
      kind = kind,
      total = total,
      hash = hash,
      chunks = {},
      received = 0,
      startedAt = Now(),
      epoch = {counter = parts[8], writer = parts[9], rank = parts[10], hash = parts[11]},
    }
    self.incomingLiveRaidWatch[key] = transfer
  end
  if transfer.epochKey ~= epochKey then self.incomingLiveRaidWatch[key] = nil; return end
  if not transfer.chunks[index] then
    transfer.chunks[index] = chunk
    transfer.received = transfer.received + 1
    transfer.lastProgressAt = Now()
  elseif transfer.chunks[index] ~= chunk then
    self.incomingLiveRaidWatch[key] = nil
    self:MultiRunDiagnostic("corruptTransfers")
    return
  end
  if transfer.received < total then return end

  local encoded = table.concat(transfer.chunks, "")
  self.incomingLiveRaidWatch[key] = nil
  if TextHash(encoded) ~= hash then
    self:MultiRunDiagnostic("corruptTransfers")
    return
  end
  local payload = Unescape(encoded)

  -- Ensure run exists for tagging without forcing participate authority.
  local multi = self:InitMultiRun()
  local run = multi.runs[liveRaidID]
  if not run then
    run = {
      id = liveRaidID,
      createdAt = Now(),
      createdBy = sender,
      status = state.watchOnly and "watching" or "active",
      sessions = {},
      participated = false,
    }
    multi.runs[liveRaidID] = run
  end
  if entry and entry.runner then run.owner = entry.runner end

  self.currentMultiRunIncomingRunID = liveRaidID
  local previousActive = multi.activeRunID
  -- Temporarily align activeRunID so catalog quarantine stays scoped.
  if state.watchOnly then multi.activeRunID = liveRaidID end

  if kind == "FS" then
    self:ApplyLootSyncV2Full(payload, sender)
  elseif kind == "SC" then
    self:ApplyLootSessionCatalogV3(payload, sender)
  elseif kind == "MD" then
    self:ApplyLootSyncV2Metadata(payload, sender)
  elseif kind == "DU" then
    self:ApplyLootSyncV2Drop(payload, sender)
  elseif kind == "DD" then
    self:ApplyLootSyncV2DropDelete(payload, sender)
  end

  if state.watchOnly then
    multi.activeRunID = liveRaidID
  else
    multi.activeRunID = previousActive
  end
  self.currentMultiRunIncomingRunID = nil

  local entryRev = entry and tonumber(entry.revision) or 0
  state.lastWatchRevision = math.max(tonumber(state.lastWatchRevision) or 0, entryRev)
  state.diagnostics.watchSnapshots = (tonumber(state.diagnostics.watchSnapshots) or 0) + 1

  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
  if self.RefreshLootSessionPicker then self:RefreshLootSessionPicker() end
end

function APOCLootPrio:ClearLiveRaidWatchMode(opts)
  opts = opts or {}
  local state = self:InitLiveRaid()
  local multi = self:InitMultiRun()
  local skipRestore = opts.skipRestore and true or false
  if (not skipRestore) and state.watchOnly and state.watchRestoreRunID then
    if multi.runs[state.watchRestoreRunID] then
      multi.activeRunID = state.watchRestoreRunID
    end
  end
  state.watchOnly = false
  state.watchRestoreRunID = nil
  state.lastWatchRevision = nil
  -- Keep selectedLiveRaidID aligned with whatever run is actually active now,
  -- so UI / GetSelectedLiveRaidID are not stuck on a prior watch target.
  if multi.activeRunID then
    state.selectedLiveRaidID = multi.activeRunID
  elseif skipRestore then
    state.selectedLiveRaidID = nil
  end
end

local function EnsureWatchRun(self, liveRaidID, entry)
  local multi = self:InitMultiRun()
  if not multi.runs[liveRaidID] then
    multi.runs[liveRaidID] = {
      id = liveRaidID,
      createdAt = Now(),
      createdBy = entry and entry.runner or "remote",
      status = "watching",
      sessions = {},
      participated = false,
      owner = entry and entry.runner or nil,
    }
  else
    local run = multi.runs[liveRaidID]
    if not run.participated and run.status ~= "active" and run.status ~= "review" then
      run.status = "watching"
    end
    if entry and entry.runner and (not run.owner or run.owner == "") then
      run.owner = entry.runner
    end
  end
  multi.activeRunID = liveRaidID
  return multi.runs[liveRaidID]
end

function APOCLootPrio:ShowLiveRaidSession()
  self:InitDB()
  self.historyPeekSessionKey = nil
  self.preferLiveSession = true
  local run = self.GetActiveRun and self:GetActiveRun() or nil
  local sessions = APOCLootPrioDB.loot and APOCLootPrioDB.loot.sessions or {}
  local runID = run and run.id or nil
  local bestKey, bestAt, best = nil, -1, nil
  for key, session in pairs(sessions) do
    if session and not session.archived and not session.finalized then
      if runID and session.runID == runID then
        local at = tonumber(session.createdAt) or 0
        if at >= bestAt then
          bestKey, bestAt, best = key, at, session
        end
      end
    end
  end
  if bestKey then
    APOCLootPrioDB.loot.activeSessionKey = bestKey
    if best.raid and best.raid ~= "" then
      self.selectedLootTrackerRaid = best.raid
      self.selectedRaid = best.raid
    end
  else
    local current = APOCLootPrioDB.loot.activeSessionKey and APOCLootPrioDB.loot.sessions[APOCLootPrioDB.loot.activeSessionKey]
    if not (current and current.drops and #current.drops > 0) then
      APOCLootPrioDB.loot.activeSessionKey = nil
    end
    local zone = LiveRaidBossHint()
    if zone == "" then zone = "Serpentshrine Cavern" end
    self.selectedLootTrackerRaid = zone
    self.selectedRaid = zone
    if run and run.id and self.RequestLiveRaidWatchSnapshot then
      self:RequestLiveRaidWatchSnapshot(run.id)
    elseif self.RequestLiveFromSyncedPeers then
      self:RequestLiveFromSyncedPeers()
    end
  end
  if self.SetGuildLootPanelShown then self:SetGuildLootPanelShown(false) end
  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
  return bestKey ~= nil
end

function APOCLootPrio:SelectLiveRaid(liveRaidID)
  local state = self:InitLiveRaid()
  liveRaidID = tostring(liveRaidID or "")
  if liveRaidID == "" then return false end

  local active = self:GetActiveRun()
  local inGroup = GetGroupChannel() ~= nil
  local entry = state.registry[liveRaidID]
  local multi = self:InitMultiRun()

  -- In-raid: selecting the local active Live Raid restores normal edit rules.
  if inGroup and active and active.id == liveRaidID then
    self:ClearLiveRaidWatchMode()
    state.selectedLiveRaidID = liveRaidID
    self:ShowLiveRaidSession()
    return true
  end

  -- Out of group: selecting own participated/review run restores normal review edit rules.
  if (not inGroup) and active and active.id == liveRaidID and (active.participated or active.status == "review") then
    self:ClearLiveRaidWatchMode()
    state.selectedLiveRaidID = liveRaidID
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
    if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
    return true
  end

  -- In-raid: do not overlay a remote Live Raid on top of your group run.
  if inGroup then
    if self.Print then
      -- silent
    end
    if active then
      self:ClearLiveRaidWatchMode({skipRestore = true})
      multi.activeRunID = active.id
      state.selectedLiveRaidID = active.id
    end
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
    if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
    return false
  end

  -- Out of group: any other Live Raid is view-only watch.
  if not state.watchOnly then
    state.watchRestoreRunID = multi.activeRunID
  end
  state.watchOnly = true
  state.selectedLiveRaidID = liveRaidID
  EnsureWatchRun(self, liveRaidID, entry)
  self:RequestLiveRaidWatchSnapshot(liveRaidID)
  if self.Print then
    -- silent
  end
  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
  return true
end

function APOCLootPrio:AutoSelectLiveRaid()
  local state = self:InitLiveRaid()
  local multi = self:InitMultiRun()
  -- Design lock: in-raid always prefers your Live Raid (not a remote watch).
  if GetGroupChannel() then
    if state.watchOnly then
      self:ClearLiveRaidWatchMode({skipRestore = true})
    end
    local run = self:GetActiveRun()
    -- Drop any leftover watch-shadow run while actually in a group.
    if run and tostring(run.status or "") == "watching" then
      multi.activeRunID = nil
      run = nil
    end
    if run and run.status == "active" then
      state.selectedLiveRaidID = run.id
      return run.id
    end
    state.selectedLiveRaidID = nil
    return nil
  end
  return state.selectedLiveRaidID
end

-- CanEditLootTracker: watching a Live Raid is always view-only.
function APOCLootPrio:CanEditLootTracker()
  if self.historyPeekSessionKey and self.IsHistoryEditContext and self:IsHistoryEditContext() and self.CanEditGuildRaidHistory and self:CanEditGuildRaidHistory() then
    return true
  end
  if self:IsLiveRaidWatchOnly() then return false end
  if PreviousCanEditLootTracker then return PreviousCanEditLootTracker(self) end
  return false
end

-- When AS4 applies a runner change on followers/new runner, refresh guild LB4.
function APOCLootPrio:ApplyMultiRunAssignment(parts, sender)
  local changed = PreviousApplyMultiRunAssignment and PreviousApplyMultiRunAssignment(self, parts, sender)
  if changed and parts and parts[3] == "runner" then
    if self:IsLocalLootSyncV2Authority() then
      self:BroadcastLiveRaidBeacon()
    end
    -- Watchers already subscribed: revision bump on next LB4 pulls snapshot.
    if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  end
  return changed
end

-- After runner handoff, announce guild beacon + note watchers need a new snapshot.
function APOCLootPrio:SetLootTrackerOwner(name, source, setAt, skipBroadcast)
  local result = PreviousSetLootTrackerOwner(self, name, source, setAt, skipBroadcast)
  if self:IsLocalLootSyncV2Authority() or (name and name ~= "") then
    self:BroadcastLiveRaidBeacon()
  end
  return result
end

function APOCLootPrio:CreateMultiRun(reason)
  local run = PreviousCreateMultiRun(self, reason)
  local state = self:InitLiveRaid()
  self:ClearLiveRaidWatchMode()
  if run then
    state.selectedLiveRaidID = run.id
    self:BroadcastLiveRaidBeacon()
  end
  return run
end

function APOCLootPrio:SendMultiRunRunnerHeartbeat()
  local sent = PreviousSendMultiRunRunnerHeartbeat(self)
  local state = self:InitLiveRaid()
  local now = Now()
  if sent and IsInGuildNow() and (now <= 0 or (now - (tonumber(state.lastGuildBeaconAt) or 0) >= GUILD_BEACON_INTERVAL)) then
    self:BroadcastLiveRaidBeacon()
  end
  return sent
end

-- Optional: when runner broadcasts live transfers in-raid, also refresh revision
-- so out-of-raid watchers can pull on next LB4. Full delta whisper is Phase-later.


function APOCLootPrio:HandleWatchSyncMessage(message, sender)
  local parts = SplitTabs(message)
  local kind = parts[1]
  if kind == "LD4" or kind == "LD5" or kind == "PING" or kind == "PLIVE" then
    self:MultiRunDiagnostic("rejectedLegacyMutations")
    return
  end
  if kind == "LB4" then self:ApplyLiveRaidBeacon(parts, sender); return end
  if kind == "LR4" then self:HandleLiveRaidRegistryRequest(parts, sender); return end
  if kind == "LW4" then self:ReplyLiveRaidWatchRequest(parts, sender); return end
  if kind == "LQ4" then self:ReceiveLiveRaidWatchChunk(parts, sender); return end
end


-- UI refresh action: advertise only a real, locally authoritative run.
function APOCLootPrio:PublishLocalLiveRaid(reason)
  return self:AnnounceLocalLiveRaid(reason)
end

if CreateFrame then
  local liveMaint = CreateFrame("Frame")
  liveMaint.elapsed = 0
  liveMaint:SetScript("OnUpdate", function(frame, elapsed)
    frame.elapsed = frame.elapsed + (elapsed or 0)
    if frame.elapsed < 5 then return end
    frame.elapsed = 0
    if not APOCLootPrio then return end
    APOCLootPrio:AutoSelectLiveRaid()
    APOCLootPrio:PruneLiveRaidRegistry()
    local state = APOCLootPrio:InitLiveRaid()
    local now = Now()
    if APOCLootPrio:IsLocalLootSyncV2Authority() and IsInGuildNow()
      and (now - (tonumber(state.lastGuildBeaconAt) or 0) >= GUILD_BEACON_INTERVAL) then
      APOCLootPrio:BroadcastLiveRaidBeacon()
    end
    for key, transfer in pairs(APOCLootPrio.incomingLiveRaidWatch or {}) do
      local progressAt = transfer.lastProgressAt or transfer.startedAt
      if now > 0 and progressAt and now - progressAt > 150 then
        APOCLootPrio.incomingLiveRaidWatch[key] = nil
        APOCLootPrio:MultiRunDiagnostic("expiredTransfers")
      end
    end
  end)
  liveMaint:RegisterEvent("PLAYER_ENTERING_WORLD")
  liveMaint:RegisterEvent("GROUP_JOINED")
  liveMaint:RegisterEvent("GROUP_LEFT")
  liveMaint:SetScript("OnEvent", function(_, event)
    if not APOCLootPrio then return end
    if event == "GROUP_JOINED" then
      -- MultiRun already clears watch with skipRestore; reinforce selection.
      APOCLootPrio:ClearLiveRaidWatchMode({skipRestore = true})
      APOCLootPrio:AutoSelectLiveRaid()
    end
    if event == "GROUP_LEFT" then
      local state = APOCLootPrio:InitLiveRaid()
      -- MultiRun clears watch before promoting the local run to review.
      if state.watchOnly then APOCLootPrio:ClearLiveRaidWatchMode({skipRestore = false}) end
      APOCLootPrio:AutoSelectLiveRaid()
    end
    if event == "PLAYER_ENTERING_WORLD" then
      APOCLootPrio:InitLiveRaid()
      if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
          if APOCLootPrio then APOCLootPrio:RequestLiveRaidRegistry() end
        end)
      else
        APOCLootPrio:RequestLiveRaidRegistry()
      end
    end
  end)
end
