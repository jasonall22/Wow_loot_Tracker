-- Loot session codec and canonical apply/broadcast operations. -- Module: LootCodec.lua
-- V2 packet receivers and its separate timer queue have been retired.

local function ShortName(name)
  return string.match(name or "", "^([^%-]+)") or name
end

local function PlayerKey(name)
  return string.lower(tostring(ShortName(name) or ""))
end

local function SamePlayer(a, b)
  return PlayerKey(a) ~= "" and PlayerKey(a) == PlayerKey(b)
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

local function PackFields(fields)
  local packed = {}
  for index, value in ipairs(fields or {}) do
    packed[index] = Escape(value)
  end
  return table.concat(packed, "\t")
end

local function UnpackFields(text)
  local fields = SplitTabs(text)
  for index, value in ipairs(fields) do
    fields[index] = Unescape(value)
  end
  return fields
end

local function TextHash(text)
  local hash = 7
  for index = 1, string.len(text or "") do
    hash = math.fmod((hash * 31) + string.byte(text, index), 2147483647)
  end
  return tostring(math.floor(hash))
end

local function EncodeInstances(instances)
  local names = {}
  for name in pairs(instances or {}) do table.insert(names, tostring(name)) end
  table.sort(names)
  return table.concat(names, string.char(30))
end

local function DecodeInstances(text)
  local instances = {}
  for name in string.gmatch(tostring(text or "") .. string.char(30), "(.-)" .. string.char(30)) do
    if name ~= "" then instances[name] = true end
  end
  return instances
end

local function EncodeAttendance(attendance)
  if not attendance then return "" end
  local lines = {PackFields({attendance.tracking and "1" or "0", attendance.updatedAt or 0})}
  local keys = {}
  for key in pairs(attendance.members or {}) do table.insert(keys, key) end
  table.sort(keys)

  for _, key in ipairs(keys) do
    local member = attendance.members[key]
    local visits = {}
    for _, visit in ipairs(member.visits or {}) do
      table.insert(visits, tostring(visit.joinedAt or 0) .. "," .. tostring(visit.leftAt or ""))
    end
    table.insert(lines, "M\t" .. PackFields({
      key,
      member.name or "",
      member.className or "",
      member.classFileName or "",
      member.subgroup or 0,
      member.firstJoinedAt or 0,
      member.lastJoinedAt or 0,
      member.lastLeftAt or "",
      member.lastSeenAt or 0,
      member.present and "1" or "0",
      table.concat(visits, string.char(30)),
    }))
  end
  return table.concat(lines, "\n")
end

local function DecodeAttendance(text)
  text = tostring(text or "")
  if text == "" then return nil end
  local attendance = {tracking = false, members = {}, updatedAt = 0}
  local lineIndex = 0
  for line in string.gmatch(text .. "\n", "(.-)\n") do
    lineIndex = lineIndex + 1
    if lineIndex == 1 then
      local header = UnpackFields(line)
      attendance.tracking = header[1] == "1"
      attendance.updatedAt = tonumber(header[2]) or 0
    else
      local record = string.match(line, "^M\t(.*)$")
      if record then
        local fields = UnpackFields(record)
        local key = fields[1]
        if key and key ~= "" then
          local member = {
            name = fields[2],
            className = fields[3],
            classFileName = fields[4],
            subgroup = tonumber(fields[5]) or 0,
            firstJoinedAt = tonumber(fields[6]) or 0,
            lastJoinedAt = tonumber(fields[7]) or 0,
            lastLeftAt = tonumber(fields[8]) or nil,
            lastSeenAt = tonumber(fields[9]) or 0,
            present = fields[10] == "1",
            visits = {},
          }
          for visitText in string.gmatch(tostring(fields[11] or "") .. string.char(30), "(.-)" .. string.char(30)) do
            local joinedAt, leftAt = string.match(visitText, "^(%d+),?(%d*)$")
            if joinedAt then
              table.insert(member.visits, {joinedAt = tonumber(joinedAt) or 0, leftAt = leftAt ~= "" and tonumber(leftAt) or nil})
            end
          end
          attendance.members[key] = member
        end
      end
    end
  end
  return attendance
end

local function IsInRaidGroup()
  if IsInRaid and IsInRaid() then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  return GetNumGroupMembers and GetNumGroupMembers() > 5 or false
end

local function IsInPartyGroup()
  if IsInRaidGroup() then return false end
  if GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then return true end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return true end
  return GetNumGroupMembers and GetNumGroupMembers() > 1 or false
end





local function RefreshLootViews()
  if APOCLootPrio.RefreshRaidLootPanel then APOCLootPrio:RefreshRaidLootPanel() end
  if APOCLootPrio.RefreshGuildLootPanel then APOCLootPrio:RefreshGuildLootPanel() end
  if APOCLootPrio.RefreshRecentAwardsPanel then APOCLootPrio:RefreshRecentAwardsPanel() end
  if APOCLootPrio.RefreshLootSessionPicker then APOCLootPrio:RefreshLootSessionPicker() end
  if APOCLootPrio.RefreshAttendancePanel then APOCLootPrio:RefreshAttendancePanel() end
end

function APOCLootPrio:IsLocalLootSyncV2Authority()
  self:InitDB()
  local owner = self:GetLootTrackerOwner()
  if owner and owner ~= "" then return self:IsLootTrackerOwner() end
  if not IsInRaidGroup() and not IsInPartyGroup() then return false end
  return self.IsLocalLootSyncAuthority and self:IsLocalLootSyncAuthority() or false
end

function APOCLootPrio:IsLootSyncV2AuthoritySender(sender)
  self:InitDB()
  if not sender or SamePlayer(sender, self:GetPlayerDisplayName()) then return false end

  local owner = self:GetLootTrackerOwner()
  if owner and owner ~= "" then return SamePlayer(sender, owner) end
  if not IsInRaidGroup() and not IsInPartyGroup() then
    if self:IsTrustedSender(sender) then return true end
    if self.GetGuildRankForName and self.GetFeatureAccessRank then
      local rankIndex = self:GetGuildRankForName(ShortName(sender))
      return rankIndex ~= nil and rankIndex <= self:GetFeatureAccessRank("lootTracker")
    end
    return false
  end

  local authority = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or nil
  return authority and SamePlayer(sender, authority) or false
end



-- Compatibility name retained for the settings serializer; one queue owns sends.
function APOCLootPrio:QueueLootSyncV2Message(message, target)
  if target or (IsInGuild and IsInGuild()) then return self:QueueMultiRunGuild(message, target) end
  return self:QueueMultiRunLive(message)
end





local function SerializeSessionMeta(session, activeOverride)
  local active = activeOverride
  if active == nil then
    active = APOCLootPrioDB and APOCLootPrioDB.loot and APOCLootPrioDB.loot.activeSessionKey == session.key
  end
  return PackFields({
    session.key or "",
    session.name or "",
    session.raid or "",
    session.createdAt or 0,
    session.createdBy or "",
    active and "1" or "0",
    EncodeInstances(session.instances),
    session.revision or 0,
    session.updatedAt or 0,
    session.syncAuthority or "",
    #(session.drops or {}),
    EncodeAttendance(session.attendance),
    session.finalized and "1" or "0",
    session.closedAt or 0,
    session.closedBy or "",
    session.savedAt or 0,
  })
end

local function SerializeDrop(drop)
  local award = drop.award or {}
  return PackFields({
    drop.id or "",
    drop.raid or "",
    drop.boss or "",
    drop.item or "",
    drop.itemID or "",
    drop.itemQuality or "",
    drop.itemKey or "",
    drop.bias or "",
    drop.note or "",
    drop.droppedAt or 0,
    drop.addedBy or "",
    award.winner or "",
    award.note or "",
    award.awardType or "",
    award.awardedAt or "",
    award.awardedBy or "",
    award.editedAt or "",
    award.editedBy or "",
    award.tradedTo or "",
    award.tradedAt or "",
    award.tradedBy or "",
    drop.autoAdded and "1" or "0",
    drop.source or "",
    drop.itemLink or "",
    drop.syncRevision or 0,
    drop.captureKey or "",
  })
end

local function DeserializeSessionMeta(text)
  local fields = UnpackFields(text)
  if not fields[1] or fields[1] == "" then return nil end
  return {
    key = fields[1],
    name = fields[2],
    raid = fields[3],
    createdAt = tonumber(fields[4]) or 0,
    createdBy = fields[5],
    active = fields[6] == "1",
    instances = DecodeInstances(fields[7]),
    revision = tonumber(fields[8]) or 0,
    updatedAt = tonumber(fields[9]) or 0,
    syncAuthority = fields[10],
    expectedDrops = tonumber(fields[11]) or 0,
    attendance = DecodeAttendance(fields[12]),
    finalized = fields[13] == "1",
    closedAt = tonumber(fields[14]) or 0,
    closedBy = fields[15] or "",
    savedAt = tonumber(fields[16]) or 0,
  }
end

local function DeserializeDrop(text, revision)
  local fields = UnpackFields(text)
  if not fields[1] or fields[1] == "" then return nil end
  local winner = fields[12] or ""
  local award = nil
  if winner ~= "" or (fields[14] or "") == "GB" then
    award = {
      winner = winner,
      note = fields[13] or "",
      awardType = fields[14] or "",
      awardedAt = tonumber(fields[15]) or 0,
      awardedBy = fields[16] or "",
      editedAt = tonumber(fields[17]) or nil,
      editedBy = fields[18] or "",
      tradedTo = fields[19] or "",
      tradedAt = tonumber(fields[20]) or nil,
      tradedBy = fields[21] or "",
    }
  end

  return {
    id = fields[1],
    raid = fields[2],
    boss = fields[3],
    item = fields[4],
    itemID = tonumber(fields[5]) or nil,
    itemQuality = tonumber(fields[6]) or nil,
    itemKey = fields[7],
    bias = fields[8],
    note = fields[9],
    droppedAt = tonumber(fields[10]) or 0,
    addedBy = fields[11],
    award = award,
    autoAdded = fields[22] == "1",
    source = fields[23],
    itemLink = fields[24] ~= "" and fields[24] or nil,
    -- Full snapshots must retain each drop's revision. Replacing every drop
    -- revision with the session revision makes the manifest disagree after
    -- any award/update, even when the item list itself arrived intact.
    -- Older payloads do not contain field 25; retain their original fallback.
    syncRevision = tonumber(fields[25]) or tonumber(revision) or 0,
    captureKey = fields[26] ~= "" and fields[26] or nil,
  }
end

local function ParseFullSessionPayload(payload)
  local meta = nil
  local drops = {}
  local deletedDrops = {}
  for line in string.gmatch((payload or "") .. "\n", "(.-)\n") do
    local recordType, record = string.match(line, "^([^\t]+)\t(.*)$")
    if recordType == "S" then
      meta = DeserializeSessionMeta(record)
    elseif recordType == "D" then
      local drop = DeserializeDrop(record, meta and meta.revision or 0)
      if drop then table.insert(drops, drop) end
    elseif recordType == "X" then
      local fields = UnpackFields(record)
      if fields[1] and fields[1] ~= "" then deletedDrops[fields[1]] = tonumber(fields[2]) or 0 end
    end
  end
  if not meta or #drops ~= (tonumber(meta.expectedDrops) or 0) then return nil end
  return meta, drops, deletedDrops
end

local function FindDropIndex(session, dropID)
  for index, drop in ipairs(session and session.drops or {}) do
    if drop.id == dropID then return index, drop end
  end
  return nil, nil
end

local function ApplyMeta(session, meta, sender)
  session.key = meta.key
  if meta.revision >= (tonumber(session.metadataRevision) or 0) then
    session.name = meta.name
    session.raid = meta.raid
    session.createdAt = meta.createdAt
    session.createdBy = meta.createdBy
    session.instances = meta.instances
    session.updatedAt = meta.updatedAt
    session.syncAuthority = meta.syncAuthority ~= "" and meta.syncAuthority or ShortName(sender)
    session.metadataRevision = meta.revision
    if meta.attendance ~= nil then session.attendance = meta.attendance end
    if meta.finalized then
      session.finalized = true
      session.closedAt = meta.closedAt
      session.closedBy = meta.closedBy
      session.savedAt = meta.savedAt
      session.archived = false
    end
    if meta.active then
      APOCLootPrioDB.loot.activeSessionKey = meta.key
    elseif APOCLootPrioDB.loot.activeSessionKey == meta.key then
      APOCLootPrioDB.loot.activeSessionKey = nil
    end
  end
  session.revision = math.max(tonumber(session.revision) or 0, meta.revision)
  session.syncedFrom = ShortName(sender)
  session.syncedAt = time and time() or 0
  if session.finalized and APOCLootPrio.SaveFinalizedLootSessionBackup then
    APOCLootPrio:SaveFinalizedLootSessionBackup(session)
  end
end

function APOCLootPrio:ApplyLootSyncV2Full(payload, sender)
  self:InitDB()
  local meta, drops, syncedDeletedDrops = ParseFullSessionPayload(payload)
  if not meta then return false end

  local deletedRevision = tonumber(APOCLootPrioDB.loot.deletedSessions[meta.key]) or -1
  if deletedRevision >= meta.revision then return false end

  local current = APOCLootPrioDB.loot.sessions[meta.key]
  if current and (tonumber(current.revision) or 0) > meta.revision then return false end

  local existingByID = {}
  for _, drop in ipairs(current and current.drops or {}) do existingByID[drop.id] = drop end
  for _, drop in ipairs(drops) do
    local existing = existingByID[drop.id]
    if existing and existing.roll then drop.roll = existing.roll end
  end

  local session = {
    key = meta.key,
    name = meta.name,
    raid = meta.raid,
    createdAt = meta.createdAt,
    createdBy = meta.createdBy,
    instances = meta.instances,
    drops = drops,
    revision = meta.revision,
    metadataRevision = meta.revision,
    updatedAt = meta.updatedAt,
    syncAuthority = meta.syncAuthority ~= "" and meta.syncAuthority or ShortName(sender),
    syncedFrom = ShortName(sender),
    syncedAt = time and time() or 0,
    -- The complete snapshot is canonical for this authority epoch, including
    -- its deletion history. Keeping follower-only tombstones could block a
    -- legitimate drop and would make manifest verification fail forever.
    deletedDrops = syncedDeletedDrops or {},
    attendance = meta.attendance or (current and current.attendance) or nil,
    finalized = (meta.finalized or (current and current.finalized)) and true or nil,
    closedAt = meta.finalized and meta.closedAt or (current and current.closedAt) or nil,
    closedBy = meta.finalized and meta.closedBy or (current and current.closedBy) or nil,
    savedAt = meta.finalized and meta.savedAt or (current and current.savedAt) or nil,
    fullSyncRevision = meta.revision,
  }
  APOCLootPrioDB.loot.sessions[meta.key] = session
  if APOCLootPrioDB.loot.quarantinedSessions then APOCLootPrioDB.loot.quarantinedSessions[meta.key] = nil end
  APOCLootPrioDB.loot.deletedSessions[meta.key] = nil
  if meta.active then
    APOCLootPrioDB.loot.activeSessionKey = meta.key
  elseif APOCLootPrioDB.loot.activeSessionKey == meta.key then
    APOCLootPrioDB.loot.activeSessionKey = nil
  end
  if session.finalized and self.SaveFinalizedLootSessionBackup then
    self:SaveFinalizedLootSessionBackup(session)
  end
  return true
end

function APOCLootPrio:ApplyLootSyncV2Metadata(payload, sender)
  self:InitDB()
  local meta = DeserializeSessionMeta(payload)
  if not meta then return false end
  local deletedRevision = tonumber(APOCLootPrioDB.loot.deletedSessions[meta.key]) or -1
  if deletedRevision >= meta.revision then return false end

  local session = APOCLootPrioDB.loot.sessions[meta.key] or {drops = {}, deletedDrops = {}}
  ApplyMeta(session, meta, sender)
  APOCLootPrioDB.loot.sessions[meta.key] = session
  return true
end

function APOCLootPrio:ApplyLootSyncV2Drop(payload, sender)
  self:InitDB()
  local metaText, dropText = string.match(payload or "", "^(.-)\n(.*)$")
  local meta = metaText and DeserializeSessionMeta(metaText) or nil
  local drop = meta and DeserializeDrop(dropText, meta.revision) or nil
  if not meta or not drop then return false end

  local deletedSessionRevision = tonumber(APOCLootPrioDB.loot.deletedSessions[meta.key]) or -1
  if deletedSessionRevision >= meta.revision then return false end

  local session = APOCLootPrioDB.loot.sessions[meta.key] or {drops = {}, deletedDrops = {}}
  session.deletedDrops = session.deletedDrops or {}
  local deletedDropRevision = tonumber(session.deletedDrops[drop.id]) or -1
  if deletedDropRevision >= meta.revision then return false end

  local index, existing = FindDropIndex(session, drop.id)
  if existing and (tonumber(existing.syncRevision) or 0) > meta.revision then return false end
  -- A complete snapshot is an authoritative inventory at its revision. A
  -- delayed update at or below that floor cannot introduce a drop that the
  -- snapshot did not contain. Incremental-only sessions keep accepting unique
  -- out-of-order drops because they do not have a fullSyncRevision yet.
  if not existing and meta.revision <= (tonumber(session.fullSyncRevision) or -1) then return false end
  if existing and existing.roll then drop.roll = existing.roll end
  if index then session.drops[index] = drop else table.insert(session.drops, 1, drop) end
  session.deletedDrops[drop.id] = nil
  ApplyMeta(session, meta, sender)
  APOCLootPrioDB.loot.sessions[meta.key] = session
  return true
end

function APOCLootPrio:ApplyLootSyncV2DropDelete(payload, sender)
  self:InitDB()
  local fields = UnpackFields(payload)
  local key, revision, updatedAt, dropID = fields[1], tonumber(fields[2]) or 0, tonumber(fields[3]) or 0, fields[4]
  if not key or key == "" or not dropID or dropID == "" then return false end
  local session = APOCLootPrioDB.loot.sessions[key]
  if not session then
    session = {key = key, drops = {}, deletedDrops = {}, revision = 0, updatedAt = 0}
    APOCLootPrioDB.loot.sessions[key] = session
  end

  session.deletedDrops = session.deletedDrops or {}
  if (tonumber(session.deletedDrops[dropID]) or -1) > revision then return false end
  local index, existing = FindDropIndex(session, dropID)
  if not existing or (tonumber(existing.syncRevision) or 0) <= revision then
    if index then table.remove(session.drops, index) end
    session.deletedDrops[dropID] = revision
  end
  session.revision = math.max(tonumber(session.revision) or 0, revision)
  session.updatedAt = math.max(tonumber(session.updatedAt) or 0, updatedAt)
  session.syncedFrom = ShortName(sender)
  session.syncedAt = time and time() or 0
  return true
end

function APOCLootPrio:ApplyLootSyncV2SessionDelete(payload)
  self:InitDB()
  local fields = UnpackFields(payload)
  local key, revision = fields[1], tonumber(fields[2]) or 0
  if not key or key == "" then return false end
  local current = APOCLootPrioDB.loot.sessions[key]
  if current and (tonumber(current.revision) or 0) > revision then return false end
  if (tonumber(APOCLootPrioDB.loot.deletedSessions[key]) or -1) > revision then return false end

  APOCLootPrioDB.loot.sessions[key] = nil
  APOCLootPrioDB.loot.deletedSessions[key] = revision
  if APOCLootPrioDB.loot.activeSessionKey == key then APOCLootPrioDB.loot.activeSessionKey = nil end
  return true
end

function APOCLootPrio:ProcessLootSyncV2Payload(kind, payload, sender)
  local changed = false
  if kind == "FS" then
    changed = self:ApplyLootSyncV2Full(payload, sender)
  elseif kind == "SM" then
    changed = self:ApplyLootSyncV2Metadata(payload, sender)
  elseif kind == "DU" then
    changed = self:ApplyLootSyncV2Drop(payload, sender)
  elseif kind == "DD" then
    changed = self:ApplyLootSyncV2DropDelete(payload, sender)
  elseif kind == "SD" then
    changed = self:ApplyLootSyncV2SessionDelete(payload)
  end
  if changed then RefreshLootViews() end
  return changed
end



local function BuildFullPayload(session, activeOverride)
  local lines = {"S\t" .. SerializeSessionMeta(session, activeOverride)}
  for _, drop in ipairs(session.drops or {}) do
    table.insert(lines, "D\t" .. SerializeDrop(drop))
  end
  local deletedIDs = {}
  for dropID in pairs(session.deletedDrops or {}) do table.insert(deletedIDs, dropID) end
  table.sort(deletedIDs)
  for _, dropID in ipairs(deletedIDs) do
    table.insert(lines, "X\t" .. PackFields({dropID, session.deletedDrops[dropID] or 0}))
  end
  return table.concat(lines, "\n")
end

function APOCLootPrio:BuildLootSessionSyncPayload(session, activeOverride)
  if not session or not session.key then return nil end
  return BuildFullPayload(session, activeOverride)
end

function APOCLootPrio:SendLootSessionV2(session, target)
  if not session or not session.key or not self:IsLocalLootSyncV2Authority() then return false end
  self:SendLootSyncV2Transfer("FS", BuildFullPayload(session), target)
  return true
end

function APOCLootPrio:SendLootSession(session, target)
  return self:SendLootSessionV2(session, target)
end



function APOCLootPrio:BroadcastLootSession(session)
  return self:SendLootSessionV2(session)
end

function APOCLootPrio:BroadcastLootSessionMetadata(session)
  if not session or not session.key or not self:IsLocalLootSyncV2Authority() then return false end
  self:SendLootSyncV2Transfer("SM", SerializeSessionMeta(session))
  return true
end

function APOCLootPrio:BroadcastLootDropUpdate(session, drop)
  if not session or not drop or not self:IsLocalLootSyncV2Authority() then return false end
  local payload = SerializeSessionMeta(session) .. "\n" .. SerializeDrop(drop)
  self:SendLootSyncV2Transfer("DU", payload)
  return true
end

function APOCLootPrio:BroadcastLootDropDelete(session, dropID)
  if not session or not dropID or not self:IsLocalLootSyncV2Authority() then return false end
  self:SendLootSyncV2Transfer("DD", PackFields({session.key, session.revision or 0, session.updatedAt or 0, dropID}))
  return true
end

function APOCLootPrio:BroadcastLootSessionDelete(sessionKey, revision)
  if not sessionKey or not self:IsLocalLootSyncV2Authority() then return false end
  self:SendLootSyncV2Transfer("SD", PackFields({sessionKey, revision or 0, time and time() or 0}))
  return true
end




