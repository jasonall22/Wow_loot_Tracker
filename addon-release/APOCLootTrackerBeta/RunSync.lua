-- Multi-run beta protocol. -- Module: RunSync.lua
--
-- Live session state is scoped to one Run ID and travels only through the
-- current RAID/PARTY. Awarded history is copied to the guild as revisioned,
-- merge-only snapshots. This prevents two simultaneous guild raids from
-- electing the same runner or pruning each other's live sessions.

local MULTIRUN_PROTOCOL = "4"
local BETA_PREFIX = "APOCLPMR"
local LIVE_CHUNK_BYTES = 68
local RECOVERY_CHUNK_BYTES = 32
local ARCHIVE_CHUNK_BYTES = 48
local SEND_INTERVAL = 0.06
local SEND_BYTES_PER_SECOND = 600
local SEND_FAILURE_WINDOW = 120
local LIVE_SENDS_PER_GUILD_SEND = 4
local TRANSFER_TIMEOUT = 150
local RUN_MAX_AGE = 12 * 60 * 60
local RUN_HEARTBEAT = 15
local RUN_BEACON = 30
local RUNNER_OFFLINE_AFTER = 45
local RECOVERY_WINDOW = 20
local HISTORY_EDITOR_MAX_RANK = 2
local HISTORY_CHUNK_BYTES = 48
local HISTORY_ACK_TIMEOUT = 8
local HISTORY_MAX_RETRIES = 2
local HISTORY_PEER_CAP = 3

local PreviousRequestSync = APOCLootPrio.RequestSync
local PreviousGetActiveLootSessionKey = APOCLootPrio.GetActiveLootSessionKey
local PreviousGetLootSessions = APOCLootPrio.GetLootSessions
local PreviousTouchLootSession = APOCLootPrio.TouchLootSession
local PreviousStartRaidLootSession = APOCLootPrio.StartRaidLootSession
local PreviousOpenLootSession = APOCLootPrio.OpenLootSession
local PreviousGetLootTrackerOwner = APOCLootPrio.GetLootTrackerOwner
local PreviousSetLootTrackerOwner = APOCLootPrio.SetLootTrackerOwner
local PreviousGetLootDisenchanter = APOCLootPrio.GetLootDisenchanter
local PreviousSetLootDisenchanter = APOCLootPrio.SetLootDisenchanter
local PreviousGetLootSyncAuthorityName = APOCLootPrio.GetLootSyncAuthorityName
local PreviousApplyLootSyncV2Full = APOCLootPrio.ApplyLootSyncV2Full
local PreviousApplyLootSyncV2Metadata = APOCLootPrio.ApplyLootSyncV2Metadata
local PreviousApplyLootSyncV2Drop = APOCLootPrio.ApplyLootSyncV2Drop
local PreviousApplyLootSyncV2DropDelete = APOCLootPrio.ApplyLootSyncV2DropDelete
local PreviousApplyLootSyncV2SessionDelete = APOCLootPrio.ApplyLootSyncV2SessionDelete
local PreviousSendLootSessionV2 = APOCLootPrio.SendLootSessionV2
local PreviousBroadcastLootSessionMetadata = APOCLootPrio.BroadcastLootSessionMetadata
local PreviousBroadcastLootDropUpdate = APOCLootPrio.BroadcastLootDropUpdate
local PreviousBroadcastLootDropDelete = APOCLootPrio.BroadcastLootDropDelete
local PreviousBroadcastLootSessionDelete = APOCLootPrio.BroadcastLootSessionDelete
local PreviousApplyLootManifestV3 = APOCLootPrio.ApplyLootManifestV3
local PreviousCanEditLootTracker = APOCLootPrio.CanEditLootTracker
local PreviousGetLootTrackerAccessText = APOCLootPrio.GetLootTrackerAccessText
local PreviousAddRaidLootDrop = APOCLootPrio.AddRaidLootDrop

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

local function Canonical(values)
  local encoded = {}
  for index, value in ipairs(values or {}) do encoded[index] = tostring(value or "") end
  return table.concat(encoded, string.char(31))
end

local function AssignmentHash(kind, runID, value, setBy)
  return TextHash(Canonical({kind, runID, PlayerKey(value), PlayerKey(setBy)}))
end

local function NormalizeVersion(version)
  version = type(version) == "table" and version or {}
  return {
    counter = math.max(0, tonumber(version.counter) or 0),
    writer = PlayerKey(version.writer),
    rank = math.max(0, math.min(99, tonumber(version.rank) or 99)),
    hash = tostring(version.hash or ""),
  }
end

local function CompareVersions(left, right)
  left, right = NormalizeVersion(left), NormalizeVersion(right)
  if left.counter ~= right.counter then return left.counter > right.counter and 1 or -1 end
  if left.rank ~= right.rank then return left.rank < right.rank and 1 or -1 end
  if left.writer ~= right.writer then return left.writer > right.writer and 1 or -1 end
  if left.hash ~= right.hash then return left.hash > right.hash and 1 or -1 end
  return 0
end

local function VersionFields(version)
  version = NormalizeVersion(version)
  return tostring(version.counter), Escape(version.writer), tostring(version.rank), version.hash
end

local function VersionFromParts(counter, writer, rank, hash)
  return NormalizeVersion({counter = counter, writer = Unescape(writer), rank = rank, hash = hash})
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

local function SendAddonRaw(message, channel, target)
  return APOCLootPrio:SendProtocolMessage(message, channel, target)
end

local function FirstPackedField(payload, full)
  local source = tostring(payload or "")
  if full then source = string.match(source, "^S\t([^\n]*)") or "" end
  return Unescape(string.match(source, "^([^\t]*)") or "")
end

local function FullPayloadRevision(payload)
  local metaLine = string.match(tostring(payload or ""), "^S\t([^\n]*)") or ""
  local fields = SplitTabs(metaLine)
  return tonumber(fields[8]) or 0
end

local function HasAwardedDrop(session)
  for _, drop in ipairs(session and session.drops or {}) do
    if drop.award and ((drop.award.winner and drop.award.winner ~= "") or drop.award.awardType == "GB") then return true end
  end
  return false
end

local function IsLocalGroupLeader()
  if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
  if IsRaidLeader and IsRaidLeader() then return true end
  if IsPartyLeader and IsPartyLeader() then return true end
  return false
end

local function IsLocalGroupAssist()
  if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
  if IsRaidOfficer and IsRaidOfficer() then return true end
  return false
end

local function SenderUnit(sender)
  if SamePlayer(sender, UnitName and UnitName("player") or "") then return "player" end
  if IsRaidGroup() then
    local count = GetNumGroupMembers and GetNumGroupMembers() or (GetNumRaidMembers and GetNumRaidMembers() or 0)
    for index = 1, count do
      local unit = "raid" .. tostring(index)
      if UnitExists and UnitExists(unit) and SamePlayer(sender, UnitName(unit)) then return unit end
    end
  else
    local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or (GetNumPartyMembers and GetNumPartyMembers() or 0)
    for index = 1, count do
      local unit = "party" .. tostring(index)
      if UnitExists and UnitExists(unit) and SamePlayer(sender, UnitName(unit)) then return unit end
    end
  end
  return nil
end

local function IsSenderGroupLeader(sender)
  if not sender or sender == "" then return false end
  local unit = SenderUnit(sender)
  if unit then
    if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return true end
    -- Classic/Anniversary: UnitIsGroupLeader(raidN) can fail; mirror IsLocalGroupLeader.
    if unit == "player" then
      if IsRaidLeader and IsRaidLeader() then return true end
      if IsPartyLeader and IsPartyLeader() then return true end
    end
  end
  -- Classic raid leader rank is 2 via GetRaidRosterInfo.
  if IsRaidGroup() and GetRaidRosterInfo then
    local count = GetNumGroupMembers and GetNumGroupMembers() or (GetNumRaidMembers and GetNumRaidMembers() or 0)
    for index = 1, count do
      local name, rank = GetRaidRosterInfo(index)
      if name and rank == 2 and SamePlayer(sender, name) then return true end
    end
  end
  if APOCLootPrio.GetGroupLeaderDisplayName then
    local leader = APOCLootPrio:GetGroupLeaderDisplayName()
    if leader and SamePlayer(sender, leader) then return true end
  end
  return false
end

local function IsSenderGroupAssist(sender)
  if not sender or sender == "" then return false end
  local unit = SenderUnit(sender)
  if unit then
    if UnitIsGroupAssistant and UnitIsGroupAssistant(unit) then return true end
    if unit == "player" and IsRaidOfficer and IsRaidOfficer() then return true end
  end
  -- Classic: GetRaidRosterInfo rank 1 = assist, rank 2 = leader.
  if IsRaidGroup() and GetRaidRosterInfo then
    local count = GetNumGroupMembers and GetNumGroupMembers() or (GetNumRaidMembers and GetNumRaidMembers() or 0)
    for index = 1, count do
      local name, rank = GetRaidRosterInfo(index)
      if name and rank == 1 and SamePlayer(sender, name) then return true end
    end
  end
  return false
end

function APOCLootPrio:IsCurrentGroupMember(name)
  if SamePlayer(name, self:GetPlayerDisplayName()) then return true end
  if SenderUnit(name) then return true end
  for _, member in ipairs(self.GetGroupRoster and self:GetGroupRoster() or {}) do
    if SamePlayer(name, member) then return true end
  end
  return false
end

function APOCLootPrio:InitMultiRun()
  self:InitDB()
  APOCLootPrioDB.multiRun = APOCLootPrioDB.multiRun or {}
  local state = APOCLootPrioDB.multiRun
  state.protocol = 4
  state.runs = state.runs or {}
  state.runCounter = tonumber(state.runCounter) or 0
  state.diagnostics = state.diagnostics or {
    rejectedWrongRun = 0,
    rejectedWrongGroup = 0,
    rejectedWrongRunner = 0,
    corruptTransfers = 0,
    expiredTransfers = 0,
    archiveApplied = 0,
    liveApplied = 0,
  }
  APOCLootPrioDB.loot.archiveSessionTombstones = APOCLootPrioDB.loot.archiveSessionTombstones or {}

  -- beta.2 cleared activeRunID on GROUP_LEFT. A later guild-history packet
  -- could then relabel that client's live session as archive-only. Recover
  -- those runs once, without promoting ordinary guild-history sessions.
  if (tonumber(state.reviewMigration) or 0) < 1 then
    local newestRunID, newestRunAt = nil, -1
    for runID, run in pairs(state.runs) do
      -- Archive-only runs were created with status "historical". Any other
      -- beta.2 status came from a run this client actually joined.
      if run.status ~= "historical" then
        run.participated = true
        local seenAt = tonumber(run.lastSeenAt) or tonumber(run.createdAt) or 0
        if seenAt > newestRunAt then newestRunID, newestRunAt = runID, seenAt end
      end
    end
    for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
      local run = session.runID and state.runs[session.runID] or nil
      if run and run.participated then session.archived = false end
    end
    state.reviewRunID = state.reviewRunID or newestRunID
    if not state.activeRunID and not GetGroupChannel() and state.reviewRunID then
      state.activeRunID = state.reviewRunID
      if state.runs[state.reviewRunID] then state.runs[state.reviewRunID].status = "review" end
    end
    state.reviewMigration = 1
  end
  return state
end

function APOCLootPrio:MultiRunDiagnostic(name, amount)
  local state = self:InitMultiRun()
  state.diagnostics[name] = (tonumber(state.diagnostics[name]) or 0) + (tonumber(amount) or 1)
end

function APOCLootPrio:GetActiveRun()
  local state = self:InitMultiRun()
  local run = state.activeRunID and state.runs[state.activeRunID] or nil
  if run and run.expiresAt and Now() > 0 and Now() > run.expiresAt then
    -- An explicitly opened closed history session is still a review, even
    -- when this character was not present in the original raid. Do not drop
    -- its Run ID merely because the live-run heartbeat window expired.
    local key = APOCLootPrioDB.loot.activeSessionKey
    local session = key and APOCLootPrioDB.loot.sessions[key]
    if not GetGroupChannel() and session and session.runID == run.id
      and (session.archived or session.finalized) then
      run.status = "review"
      state.reviewRunID = run.id
      return run
    end
    if not GetGroupChannel() and run.participated then
      run.status = "review"
      state.reviewRunID = run.id
      return run
    end
    run.status = "expired"
    state.activeRunID = nil
    return nil
  end
  return run
end

function APOCLootPrio:GetActiveRunID()
  local run = self:GetActiveRun()
  return run and run.id or nil
end

function APOCLootPrio:GetRunShortID(runID)
  runID = tostring(runID or self:GetActiveRunID() or "none")
  if runID == "none" then return runID end
  local hash = TextHash(runID)
  return string.sub(hash, 1, 12)
end

local function EnsureRunDefaults(run)
  if not run then return nil end
  run.owner = run.owner or nil
  run.ownerSetBy = run.ownerSetBy or ""
  run.ownerVersion = NormalizeVersion(run.ownerVersion)
  run.disenchanter = run.disenchanter or nil
  run.disenchanterSetBy = run.disenchanterSetBy or ""
  run.disenchanterVersion = NormalizeVersion(run.disenchanterVersion)
  run.sessions = run.sessions or {}
  run.status = run.status or "active"
  run.lastSeenAt = tonumber(run.lastSeenAt) or Now()
  run.expiresAt = tonumber(run.expiresAt) or ((tonumber(run.createdAt) or Now()) + RUN_MAX_AGE)
  run.authorityChangedAt = tonumber(run.authorityChangedAt) or tonumber(run.createdAt) or Now()
  return run
end

function APOCLootPrio:CreateMultiRun(reason)
  local state = self:InitMultiRun()
  local old = self:GetActiveRun()
  if old then old.status = "closed"; old.closedAt = Now() end
  state.runCounter = state.runCounter + 1
  local creator = self:GetPlayerDisplayName()
  local createdAt = Now()
  local seed = Canonical({createdAt, creator, state.runCounter, reason or "group"})
  local runID = tostring(createdAt) .. ":" .. TextHash(seed)
  local run = EnsureRunDefaults({
    id = runID,
    createdAt = createdAt,
    createdBy = creator,
    reason = reason or "group",
    lastSeenAt = createdAt,
    expiresAt = createdAt + RUN_MAX_AGE,
    authorityChangedAt = createdAt,
    status = "active",
    participated = true,
    sessions = {},
  })
  state.runs[runID] = run
  state.activeRunID = runID
  APOCLootPrioDB.loot.activeSessionKey = nil
  APOCLootPrioDB.loot.current = {}
  self:MirrorMultiRunAssignments(run)
  self:BroadcastMultiRunBeacon()
  if self.Print then self:Print("Started Multi-Run " .. self:GetRunShortID(runID) .. ".") end
  if self.ScheduleEnsureRunnerFollowsMasterLooter then
    self:ScheduleEnsureRunnerFollowsMasterLooter(0.5, "create-run")
  end
  return run
end

function APOCLootPrio:EnsureActiveMultiRun(allowCreate)
  local run = self:GetActiveRun()
  if run and allowCreate and not GetGroupChannel() and run.status == "review" then
    return self:CreateMultiRun("solo")
  end
  -- In a raid, a leftover review/historical run is not the live raid. ML or leader starts one.
  if allowCreate and GetGroupChannel() and (not run or tostring(run.status or "") ~= "active") then
    local isML = self.IsMasterLooter and self:IsMasterLooter()
    if IsLocalGroupLeader() or isML then
      return self:CreateMultiRun("group")
    end
  end
  if run then
    run.lastSeenAt = Now()
    run.expiresAt = math.max(tonumber(run.expiresAt) or 0, Now() + RUN_MAX_AGE)
    if GetGroupChannel() and self.ScheduleEnsureRunnerFollowsMasterLooter and not self._runnerMlFollowInProgress then
      -- Debounced; only reassigns when ML changes / misaligned.
      self:ScheduleEnsureRunnerFollowsMasterLooter(0.75, "ensure-run")
    end
    return run
  end
  if allowCreate and (IsLocalGroupLeader() or (self.IsMasterLooter and self:IsMasterLooter()) or not GetGroupChannel()) then
    return self:CreateMultiRun(GetGroupChannel() and "group" or "solo")
  end
  return nil
end

function APOCLootPrio:AdoptMultiRun(runID, createdAt, createdBy, sender)
  if not runID or runID == "" then return false end
  local state = self:InitMultiRun()
  local current = self:GetActiveRun()
  if current and current.id ~= runID then
    local allow = false
    if IsSenderGroupLeader(sender) then
      allow = true
    elseif tostring(current.status or "") ~= "active" and self:IsCurrentGroupMember(sender) then
      -- Review/historical must not block the current raid's Run ID.
      allow = true
    else
      local lootMaster = self.GetLootMasterDisplayName and self:GetLootMasterDisplayName() or nil
      if lootMaster and SamePlayer(sender, lootMaster) then
        allow = true
      elseif self.IsTrustedLootTrackerEditor and self:IsTrustedLootTrackerEditor(sender) then
        local health = self.GetMultiRunRunnerHealth and self:GetMultiRunRunnerHealth() or "missing"
        if health == "offline" or health == "missing" or health == "waiting" or tostring(current.status or "") ~= "active" then
          allow = true
        end
      end
    end
    if not allow then
      self:MultiRunDiagnostic("rejectedWrongRun")
      return false
    end
  end
  local run = EnsureRunDefaults(state.runs[runID] or {
    id = runID,
    createdAt = tonumber(createdAt) or Now(),
    createdBy = createdBy or sender,
    sessions = {},
  })
  run.participated = true
  run.status = "active"
  run.lastSeenAt = Now()
  run.expiresAt = math.max(tonumber(run.expiresAt) or 0, Now() + RUN_MAX_AGE)
  state.runs[runID] = run
  state.activeRunID = runID
  self:MirrorMultiRunAssignments(run)
  return true
end

function APOCLootPrio:EnsureMultiRunQueues()
  self.multiRunLiveQueue = self.multiRunLiveQueue or {}
  self.multiRunGuildQueue = self.multiRunGuildQueue or {}
  if self.multiRunQueueFrame or not CreateFrame then return end
  local frame = CreateFrame("Frame")
  self.multiRunQueueFrame = frame
  frame.elapsed, frame.liveSendsSinceGuild = 0, 0
  frame.clock, frame.sendDelay = 0, SEND_INTERVAL
  frame:SetScript("OnUpdate", function(_, elapsed)
    frame.clock = frame.clock + (elapsed or 0)
    frame.elapsed = frame.elapsed + (elapsed or 0)
    if frame.elapsed < frame.sendDelay then return end
    frame.elapsed = 0
    local a = APOCLootPrio
    local live, guild = a.multiRunLiveQueue, a.multiRunGuildQueue
    local urgentLive = live[1] and live[1].urgent
    local useGuild = #guild > 0 and (#live == 0 or (not urgentLive and frame.liveSendsSinceGuild >= LIVE_SENDS_PER_GUILD_SEND))
    local queue = useGuild and guild or live
    local record = queue[1]
    if not record then return end
    if useGuild then frame.liveSendsSinceGuild = 0
    else frame.liveSendsSinceGuild = frame.liveSendsSinceGuild + 1 end
    if not useGuild and record.runID ~= a:GetActiveRunID() then table.remove(queue, 1); return end
    -- Pace by bytes, not just packet count. Live and archive traffic share
    -- this budget; a failed API call backs off without immediately losing a chunk.
    frame.sendDelay = math.max(SEND_INTERVAL, (#record.message + 40) / SEND_BYTES_PER_SECOND)
    local sent
    if useGuild then sent = a:SendSyncMessage(record.message, record.target)
    else sent = SendAddonRaw(record.message, GetGroupChannel()) end
    if sent ~= false then
      table.remove(queue, 1)
      if record.onSent then record.onSent() end
    else
      record.failures = (record.failures or 0) + 1
      record.firstFailedAt = record.firstFailedAt or frame.clock
      a:MultiRunDiagnostic("sendRetries")
      frame.sendDelay = math.max(frame.sendDelay, math.min(4, 0.25 * (2 ^ math.min(record.failures - 1, 4))))
      if frame.clock - record.firstFailedAt >= SEND_FAILURE_WINDOW then
        table.remove(queue, 1)
        a:MultiRunDiagnostic("sendFailures")
        -- Bounded failure handling prevents an offline archive peer blocking
        -- its queue forever. Periodic manifests recover incomplete live state.
        if a.Print then a:Print("A sync packet could not be sent after two minutes; live loot will be checked again automatically.") end
      end
    end
  end)
end

function APOCLootPrio:QueueMultiRunLive(message, replaceKey, payloadHash)
  if not GetGroupChannel() then return false end
  self:EnsureMultiRunQueues()
  if not self.multiRunQueueFrame then return SendAddonRaw(message, GetGroupChannel()) end
  local queue = self.multiRunLiveQueue
  local runID = self:GetActiveRunID()
  local kind = string.match(message, "^([^\t]+)")
  if kind == "HB4" or kind == "LM4" or kind == "L4" or kind == "RB4" or kind == "RR4" then
    replaceKey = kind .. ":" .. tostring(runID or "")
  end
  if replaceKey then
    for _, record in ipairs(queue) do
      if record.runID == runID and record.replaceKey == replaceKey and payloadHash and record.payloadHash == payloadHash then
        return true -- This exact transfer is already being delivered.
      end
    end
    for index = #queue, 1, -1 do
      if queue[index].runID == runID and queue[index].replaceKey == replaceKey then
        table.remove(queue, index)
      end
    end
  end
  local urgent = kind == "HB4" or kind == "LM4" or kind == "L4" or kind == "RB4" or kind == "RR4"
  local record = {message=message, runID=runID, replaceKey=replaceKey, payloadHash=payloadHash, urgent=urgent}
  if urgent then table.insert(queue, 1, record) else table.insert(queue, record) end
  return true
end

function APOCLootPrio:QueueMultiRunGuild(message, target, onSent)
  if not target and (not IsInGuild or not IsInGuild()) then return false end
  self:EnsureMultiRunQueues()
  if not self.multiRunQueueFrame then
    local sent = self:SendSyncMessage(message, target)
    if sent ~= false and onSent then onSent() end
    return sent ~= false
  end
  table.insert(self.multiRunGuildQueue, {message=message, target=target, onSent=onSent})
  return true
end

function APOCLootPrio:QueueHistoryTransfer(pending)
  if pending.queued then return false end
  pending.queued, pending.sentAt = true, nil
  for index, message in ipairs(pending.messages or {}) do
    local last = index == #pending.messages
    self:QueueMultiRunGuild(message, pending.peer, last and function()
      pending.queued, pending.sentAt = false, Now()
    end or nil)
  end
  return true
end

function APOCLootPrio:NextMultiRunTransferID(label)
  self.multiRunTransferCounter = (self.multiRunTransferCounter or 0) + 1
  return tostring(Now()) .. ":" .. tostring(self.multiRunTransferCounter)
end

function APOCLootPrio:BroadcastMultiRunBeacon()
  local run = self:GetActiveRun()
  if not run or not GetGroupChannel() then return false end
  run.lastSeenAt = Now()
  self:QueueMultiRunLive(table.concat({"RB4", Escape(run.id), tostring(run.createdAt or 0), Escape(run.createdBy or ""), Escape(self:GetAddonVersion())}, "\t"))
  self:SendMultiRunAssignments()
  return true
end

function APOCLootPrio:RequestMultiRunSync()
  if not GetGroupChannel() then return false end
  self:QueueMultiRunLive(table.concat({"RR4", MULTIRUN_PROTOCOL, Escape(self:GetAddonVersion()), Escape(self:NextMultiRunTransferID("request"))}, "\t"))
  return true
end

function APOCLootPrio:GetRunWriterRank(name)
  if self.GetGuildRankForName then
    local rank = self:GetGuildRankForName(ShortName(name))
    if rank ~= nil then return tonumber(rank) or 99 end
  end
  return 99
end

function APOCLootPrio:MirrorMultiRunAssignments(run)
  if not run then return end
  if PreviousSetLootTrackerOwner then PreviousSetLootTrackerOwner(self, run.owner, run.ownerSetBy, Now(), true) end
  if PreviousSetLootDisenchanter then PreviousSetLootDisenchanter(self, run.disenchanter, run.disenchanterSetBy, Now(), true) end
end

function APOCLootPrio:GetLootTrackerOwner()
  local run = self:GetActiveRun()
  if run and GetGroupChannel() then
    -- A live run is always owned by the current WoW Master Looter. Ignore
    -- legacy runner assignments so a stale handoff cannot take control.
    return self:GetLootSyncAuthorityName()
  end
  if run then return run.owner end
  return PreviousGetLootTrackerOwner and PreviousGetLootTrackerOwner(self) or nil
end

function APOCLootPrio:GetLootDisenchanter()
  local run = self:GetActiveRun()
  if run then return run.disenchanter end
  return PreviousGetLootDisenchanter and PreviousGetLootDisenchanter(self) or nil
end

function APOCLootPrio:NextMultiRunAssignmentVersion(run, kind, value, setBy)
  local field = kind == "runner" and "ownerVersion" or "disenchanterVersion"
  local previous = NormalizeVersion(run[field])
  local counter = math.max(previous.counter, tonumber(run.logicalClock) or 0) + 1
  run.logicalClock = counter
  return NormalizeVersion({
    counter = counter,
    writer = self:GetPlayerDisplayName(),
    rank = self:GetRunWriterRank(self:GetPlayerDisplayName()),
    hash = AssignmentHash(kind, run.id, value, setBy),
  })
end

function APOCLootPrio:SendMultiRunAssignment(kind)
  local run = self:GetActiveRun()
  if not run or not GetGroupChannel() then return false end
  if kind == "runner" then return true end -- live authority is always WoW ML
  local value = kind == "runner" and run.owner or run.disenchanter
  local setBy = kind == "runner" and run.ownerSetBy or run.disenchanterSetBy
  local version = kind == "runner" and run.ownerVersion or run.disenchanterVersion
  local counter, writer, rank, hash = VersionFields(version)
  self:QueueMultiRunLive(table.concat({"AS4", Escape(run.id), kind, counter, writer, rank, hash, Escape(value or ""), Escape(setBy or "")}, "\t"))
  return true
end

function APOCLootPrio:SendMultiRunAssignments()
  self:SendMultiRunAssignment("disenchanter")
end

function APOCLootPrio:SendLootTrackerOwner()
  return self:SendMultiRunAssignments()
end

function APOCLootPrio:BroadcastLootTrackerOwner()
  return self:SendMultiRunAssignments()
end

function APOCLootPrio:SetLootTrackerOwner(name, source, setAt, skipBroadcast)
  local run = self:EnsureActiveMultiRun(true)
  if not run then return PreviousSetLootTrackerOwner(self, name, source, setAt, skipBroadcast) end
  if GetGroupChannel() then
    -- Keep the old field readable for saved-history compatibility, but do not
    -- let any UI, packet, or recovery action assign a live runner.
    local ml = self:GetLootMasterDisplayName()
    if ml and ml ~= "" then
      run.owner = ml
      run.ownerSetBy = "master-looter"
      run.ownerVersion = self:NextMultiRunAssignmentVersion(run, "runner", ml, "master-looter")
    end
    return true
  end
  local clean = name and string.match(name, "^%s*(.-)%s*$") or ""
  -- Hard coupling: while master loot is active, any non-ML (or clear) assign
  -- is redirected to the current master looter. Remote skipBroadcast mirrors
  -- still apply as received; EnsureRunnerFollowsMasterLooter corrects next tick.
  if not skipBroadcast and self.ResolveRunnerNameForMasterLoot then
    local resolved, redirected = self:ResolveRunnerNameForMasterLoot(clean)
    if redirected and resolved then
      clean = resolved
      if not self._runnerMlFollowInProgress and self.Print then
        local now = Now()
        local lastPrint = tonumber(self._runnerMlFollowLastPrintAt) or 0
        if now <= 0 or (now - lastPrint) >= 3 then
          self._runnerMlFollowLastPrintAt = now
          self:Print("Runner follows master looter (" .. tostring(ShortName(resolved) or resolved) .. ").")
        end
      end
      if source == nil or source == "" or source == self:GetPlayerDisplayName() then
        source = "ml-follow"
      end
    elseif resolved then
      clean = resolved
    end
  end
  local setBy = source or self:GetPlayerDisplayName()
  local oldOwner = run.owner
  local changed = not SamePlayer(oldOwner or "", clean) or ((oldOwner or "") == "") ~= (clean == "")
  local oldAuthority = self:IsLocalLootSyncV2Authority()

  -- A non-authority asks the current authority to perform the handoff. The
  -- current authority can then put its final full snapshot/catalog/manifest
  -- ahead of the assignment in the same group queue. If the old authority is
  -- no longer in the group, a group leader or Loot Tracker editor may recover
  -- and force the change.
  if changed and not oldAuthority and GetGroupChannel() then
    local authority = self:GetLootSyncAuthorityName()
    local canForce = IsLocalGroupLeader() or IsLocalGroupAssist() or self:CanManageMultiRunRunnerAssignment()
    if authority and self:IsCurrentGroupMember(authority) and self:IsMultiRunAuthorityHealthy() then
      self:QueueMultiRunLive(table.concat({"HR4", Escape(run.id), Escape(clean), Escape(setBy)}, "\t"))
      if not canForce then
        if self.Print then self:Print("Runner handoff requested from " .. tostring(ShortName(authority)) .. ".") end
        return run.owner
      end
      if self.Print then self:Print("Forcing runner reassignment; requested final snapshot from " .. tostring(ShortName(authority)) .. ".") end
    elseif not canForce then
      if self.Print then self:Print("The current runner is unavailable. A group leader, assist, or Loot Tracker editor must assign the replacement.") end
      return run.owner
    else
      local _, verified = self:QueueMultiRunForcedRecovery(clean, setBy)
      if self.Print then
        self:Print("Runner heartbeat expired. Recovering the latest local snapshot before handoff.")
        if not verified then self:Print("Warning: the old runner did not verify this exact manifest. Review the recovered loot queue after takeover.") end
      end
    end
  end

  if changed and oldAuthority then
    self:SendAllLootSessions()
    self:SendLootSyncV2Transfer("SC", self:BuildLootSessionCatalogV3())
    self:QueueLootManifestV3()
  end
  run.owner = clean ~= "" and clean or nil
  run.ownerSetBy = setBy
  run.ownerSetAt = tonumber(setAt) or Now()
  if changed then
    run.authorityChangedAt = Now()
    run.lastAuthorityHeartbeatAt = nil
    run.lastAuthorityHeartbeatFrom = nil
  end
  run.ownerVersion = self:NextMultiRunAssignmentVersion(run, "runner", clean, setBy)
  self:MirrorMultiRunAssignments(run)
  if not skipBroadcast then self:SendMultiRunAssignment("runner") end
  if self:IsLocalLootSyncV2Authority() then self:SendMultiRunRunnerHeartbeat() end
  return run.owner
end

function APOCLootPrio:SetLootDisenchanter(name, source, setAt, skipBroadcast)
  local run = self:EnsureActiveMultiRun(true)
  if not run then return PreviousSetLootDisenchanter(self, name, source, setAt, skipBroadcast) end
  local clean = name and string.match(name, "^%s*(.-)%s*$") or ""
  local setBy = source or self:GetPlayerDisplayName()
  run.disenchanter = clean ~= "" and clean or nil
  run.disenchanterSetBy = setBy
  run.disenchanterSetAt = tonumber(setAt) or Now()
  run.disenchanterVersion = self:NextMultiRunAssignmentVersion(run, "disenchanter", clean, setBy)
  self:MirrorMultiRunAssignments(run)
  if not skipBroadcast then self:SendMultiRunAssignment("disenchanter") end
  return run.disenchanter
end

function APOCLootPrio:ApplyMultiRunAssignment(parts, sender)
  local runID, kind = Unescape(parts[2]), parts[3]
  if runID ~= self:GetActiveRunID() or (kind ~= "runner" and kind ~= "disenchanter") then
    self:MultiRunDiagnostic("rejectedWrongRun")
    return false
  end
  local run = self:GetActiveRun()
  if kind == "runner" and GetGroupChannel() then
    -- Ignore legacy runner assignment packets. The current WoW Master Looter
    -- is resolved locally on every client and cannot be replaced by a packet.
    local ml = self:GetLootMasterDisplayName()
    if ml and ml ~= "" then run.owner = ml end
    return true
  end
  local incoming = VersionFromParts(parts[4], parts[5], parts[6], parts[7])
  local value, setBy = Unescape(parts[8]), Unescape(parts[9])
  if incoming.hash ~= AssignmentHash(kind, runID, value, setBy) then
    self:MultiRunDiagnostic("corruptTransfers")
    return false
  end
  local field = kind == "runner" and "ownerVersion" or "disenchanterVersion"
  if CompareVersions(incoming, run[field]) <= 0 then return false end
  run[field] = incoming
  run.logicalClock = math.max(tonumber(run.logicalClock) or 0, incoming.counter)
  if kind == "runner" then
    local changed = not SamePlayer(run.owner or "", value) or ((run.owner or "") == "") ~= (value == "")
    run.owner = value ~= "" and value or nil
    run.ownerSetBy = setBy ~= "" and setBy or sender
    if changed then
      run.authorityChangedAt = Now()
      run.lastAuthorityHeartbeatAt = nil
      run.lastAuthorityHeartbeatFrom = nil
    end
  else
    run.disenchanter = value ~= "" and value or nil
    run.disenchanterSetBy = setBy ~= "" and setBy or sender
  end
  self:MirrorMultiRunAssignments(run)
  if kind == "runner" and self:IsLocalLootSyncV2Authority() then self:SendMultiRunRunnerHeartbeat() end
  if kind == "runner" and self.ScheduleEnsureRunnerFollowsMasterLooter then
    self:ScheduleEnsureRunnerFollowsMasterLooter(0.5, "assignment")
  end
  return true
end

function APOCLootPrio:GetLootSyncAuthorityName()
  if GetGroupChannel() then
    -- The WoW loot system is the source of truth for live control. A stale
    -- saved runner or recovery packet must never override the current ML.
    return self:GetLootMasterDisplayName()
  end
  return self:GetPlayerDisplayName()
end

function APOCLootPrio:IsLocalLootSyncV2Authority()
  if GetGroupChannel() then return self:IsMasterLooter() end
  return true
end

function APOCLootPrio:IsLootSyncV2AuthoritySender(sender)
  if not self:IsCurrentGroupMember(sender) then return false end
  local authority = self:GetLootSyncAuthorityName()
  return authority and SamePlayer(sender, authority) or false
end

function APOCLootPrio:GetLootAuthorityEpoch()
  local run = self:GetActiveRun()
  local authority = self:GetLootSyncAuthorityName() or ""
  return NormalizeVersion({
    counter = 0,
    writer = authority,
    rank = self:GetRunWriterRank(authority),
    hash = TextHash(Canonical({"automatic-run-authority", run and run.id or "", PlayerKey(authority)})),
  })
end

function APOCLootPrio:GetMultiRunRunnerHealth()
  local run = self:GetActiveRun()
  if not run then return "missing", "No Run ID", nil end
  local authority = self:GetLootSyncAuthorityName()
  if not authority or authority == "" then return "missing", "No Master Looter", nil end
  local me = self:GetPlayerDisplayName()
  local unit = UnitName and UnitName("player") or nil
  if SamePlayer(authority, me) or SamePlayer(authority, unit) then
    run.lastAuthorityHeartbeatAt = Now()
    run.lastAuthorityHeartbeatFrom = me
    return "active", "Active", 0
  end

  local unitToken = SenderUnit(authority)
  local inGroup = unitToken ~= nil or self:IsCurrentGroupMember(authority)
  if GetGroupChannel() and not inGroup then
    return "offline", "Master Looter left group", nil
  end

  -- UnitIsConnected distinguishes a real logout/DC from a quiet addon pulse.
  local connected = true
  if unitToken and UnitIsConnected then
    connected = UnitIsConnected(unitToken) and true or false
  end
  if inGroup and not connected then
    return "offline", "Master Looter disconnected", nil
  end

  local now = Now()
  local last = tonumber(run.lastAuthorityHeartbeatAt)
  if last and last > 0 then
    local age = math.max(0, now - last)
    if age <= RUNNER_OFFLINE_AFTER then return "active", "Active", age end
    -- Still in raid and connected: do not brand the ML as OFFLINE just because HB4 is quiet.
    if inGroup and connected then return "active", "In raid", age end
    return "offline", "No Master Looter heartbeat", age
  end
  local changedAt = tonumber(run.authorityChangedAt) or tonumber(run.createdAt) or now
  local age = math.max(0, now - changedAt)
  if age <= RUNNER_OFFLINE_AFTER then return "waiting", "Waiting for heartbeat", age end
  if inGroup and connected then return "waiting", "In raid", age end
  return "offline", "No heartbeat", age
end

function APOCLootPrio:IsMultiRunAuthorityHealthy()
  local status = self:GetMultiRunRunnerHealth()
  return status == "active" or status == "waiting"
end

-- Guild Loot Tracker editors may assign the runner without already being
-- the live write authority. Editing loot still requires CanEditLootTracker.
function APOCLootPrio:CanManageMultiRunRunnerAssignment()
  if self.CanManageSettings and self:CanManageSettings() then return true end
  if self.CanViewFeature and self:CanViewFeature("lootTracker") then return true end
  if self.IsLootTrackerOwner and self:IsLootTrackerOwner() then return true end
  return false
end

-- Trusted remote check for RF4/HR4: group leaders are handled separately;
-- this mirrors CanManageMultiRunRunnerAssignment for other players via guild rank.
function APOCLootPrio:IsTrustedLootTrackerEditor(name)
  if not name then return false end
  if SamePlayer(name, self:GetPlayerDisplayName()) then
    return self:CanManageMultiRunRunnerAssignment()
  end
  if self.GetGuildRankForName and self.GetFeatureAccessRank then
    local rankIndex = self:GetGuildRankForName(ShortName(name))
    if rankIndex ~= nil and rankIndex <= (self:GetFeatureAccessRank("lootTracker") or 1) then return true end
    if rankIndex ~= nil and rankIndex <= 1 then return true end -- settings ranks
  end
  return false
end

-- This is intentionally narrower than CanEditLootTracker. A group leader or
-- Loot Tracker editor who normally has view-only write access may replace a
-- missing/offline runner, but does not gain permission to alter sessions,
-- drops, rolls, awards, or settings.
function APOCLootPrio:CanRecoverOfflineMultiRunRunner()
  if not GetGroupChannel() then return false end
  if not (IsLocalGroupLeader() or IsLocalGroupAssist() or self:CanManageMultiRunRunnerAssignment()) then return false end
  local status = self:GetMultiRunRunnerHealth()
  return status == "offline" or status == "missing"
end

function APOCLootPrio:CanAssignMultiRunRunner()
  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() then return false end
  if self:CanManageMultiRunRunnerAssignment() then return true end
  if IsLocalGroupLeader() or IsLocalGroupAssist() then return true end
  if self.CanEditLootTracker and self:CanEditLootTracker() then return true end
  return self:CanRecoverOfflineMultiRunRunner()
end

function APOCLootPrio:RequireMultiRunRunnerAssignment()
  if self:CanAssignMultiRunRunner() then return true end
  local status = self:GetMultiRunRunnerHealth()
  if self.Print then
    if status == "active" or status == "waiting" then
      self:Print("Only the active runner or an authorized Loot Tracker editor can change the runner.")
    else
      self:Print("The runner is unavailable. A group leader or Loot Tracker editor can recover and assign a replacement.")
    end
  end
  return false
end

function APOCLootPrio:SendMultiRunRunnerHeartbeat()
  local run = self:GetActiveRun()
  if not run or not GetGroupChannel() or not self:IsLocalLootSyncV2Authority() then return false end
  local counter, writer, rank, hash = VersionFields(self:GetLootAuthorityEpoch())
  run.lastAuthorityHeartbeatAt = Now()
  run.lastAuthorityHeartbeatFrom = self:GetPlayerDisplayName()
  return self:QueueMultiRunLive(table.concat({
    "HB4", Escape(run.id), counter, writer, rank, hash, Escape(self:GetAddonVersion()),
  }, "\t"))
end

function APOCLootPrio:SendMultiRunRecoveryTransfer(token, kind, payload)
  local run = self:GetActiveRun()
  if not run or not token or token == "" then return false end
  if not (IsLocalGroupLeader() or IsLocalGroupAssist() or self:CanManageMultiRunRunnerAssignment()) then return false end
  local encoded = Escape(payload or "")
  local transferID = self:NextMultiRunTransferID("recovery")
  local total = math.max(1, math.ceil(string.len(encoded) / RECOVERY_CHUNK_BYTES))
  local payloadHash = TextHash(encoded)
  local counter, writer, rank, epochHash = VersionFields(self:GetLootAuthorityEpoch())
  for index = 1, total do
    local first = ((index - 1) * RECOVERY_CHUNK_BYTES) + 1
    local chunk = string.sub(encoded, first, first + RECOVERY_CHUNK_BYTES - 1)
    self:QueueMultiRunLive(table.concat({
      "QR4", Escape(run.id), Escape(token), transferID, kind, tostring(index), tostring(total), payloadHash,
      counter, writer, rank, epochHash, chunk,
    }, "\t"))
  end
  return true
end

function APOCLootPrio:QueueMultiRunForcedRecovery(desiredOwner, setBy)
  local run = self:GetActiveRun()
  if not run then return false end
  if not (IsLocalGroupLeader() or IsLocalGroupAssist() or self:CanManageMultiRunRunnerAssignment()) then return false end
  local localDigest = self:GetLootSessionManifest()
  local oldAuthority = ShortName(self:GetLootSyncAuthorityName())
  local peer = APOCLootPrioDB.sync and APOCLootPrioDB.sync.peerStates and APOCLootPrioDB.sync.peerStates[oldAuthority]
  local verified = peer and peer.lootVerified and peer.lootDigest == localDigest or false
  local token = self:NextMultiRunTransferID("force")
  run.recoveryToken = token
  run.recoverySource = self:GetPlayerDisplayName()
  run.recoveryExpiresAt = Now() + RECOVERY_WINDOW
  self:QueueMultiRunLive(table.concat({"RF4", Escape(run.id), Escape(token), Escape(desiredOwner or ""), Escape(setBy or ""), verified and "1" or "0"}, "\t"))
  for _, session in ipairs(self:GetActiveRunSessions()) do
    local payload = self:BuildLootSessionSyncPayload(session, APOCLootPrioDB.loot.activeSessionKey == session.key)
    if payload then self:SendMultiRunRecoveryTransfer(token, "FS", payload) end
  end
  self:SendMultiRunRecoveryTransfer(token, "SC", self:BuildLootSessionCatalogV3())
  return true, verified
end

function APOCLootPrio:ReceiveMultiRunRecoveryChunk(parts, sender)
  local runID, token = Unescape(parts[2]), Unescape(parts[3])
  local run = self:GetActiveRun()
  local recoveryPermitted = IsSenderGroupLeader(sender) or IsSenderGroupAssist(sender) or (self.IsTrustedLootTrackerEditor and self:IsTrustedLootTrackerEditor(sender))
  if not run or runID ~= run.id or not recoveryPermitted then self:MultiRunDiagnostic("rejectedWrongGroup"); return end
  if run.recoveryToken ~= token or not run.recoveryExpiresAt or Now() > run.recoveryExpiresAt or not SamePlayer(run.recoverySource, sender) then
    self:MultiRunDiagnostic("rejectedWrongRunner")
    return
  end
  local transformed = {
    "Q3", runID .. ":recovery:" .. tostring(parts[4] or ""), parts[5], parts[6], parts[7], parts[8],
    parts[9], parts[10], parts[11], parts[12], parts[13] or "",
  }
  self.currentMultiRunIncomingRunID = runID
  self:ReceiveLootSyncV3Chunk(transformed, sender)
  self.currentMultiRunIncomingRunID = nil
end

function APOCLootPrio:TagSessionForActiveRun(session)
  if not session then return nil end
  local run = self:GetActiveRun()
  -- Editing an explicitly opened review session must not create a new solo
  -- Run ID and strand the saved session behind the run filter.
  if not run or not session.runID or session.runID ~= run.id then
    run = self:EnsureActiveMultiRun(true)
  end
  if not run then return session end
  if not session.runID then session.runID = run.id end
  if session.runID == run.id then
    -- Opening/tagging guild archive for review must not un-archive unless
    -- this client actually participated in that raid night.
    if run.participated then
      session.archived = false
    end
    if not session.archived then
      run.participated = true
    end
    run.sessions[session.key or tostring(session)] = true
  end
  return session
end

function APOCLootPrio:TouchLootSession(session)
  -- Corrections to an opened history session must not start or attach it to a
  -- new solo run. Preserve its original Run ID and archive provenance.
  local historySession = self.GetActiveHistorySession and self:GetActiveHistorySession() or nil
  local editingHistory = session and session == historySession
    and self.IsHistoryEditContext and self:IsHistoryEditContext()
    and self.CanEditGuildRaidHistory and self:CanEditGuildRaidHistory()
  if not editingHistory then self:TagSessionForActiveRun(session) end
  return PreviousTouchLootSession(self, session)
end

function APOCLootPrio:StartRaidLootSession(...)
  self.historyPeekSessionKey = nil
  self:EnsureActiveMultiRun(true)
  local session, reason = PreviousStartRaidLootSession(self, ...)
  if session then self:TagSessionForActiveRun(session) end
  return session, reason
end

function APOCLootPrio:OpenLootSession(sessionKey)
  self:InitDB()
  local session = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  if not session then return nil, "Could not find that loot session." end

  local runID = session.runID
  if not runID or runID == "" then
    if GetGroupChannel() then
      self.historyPeekSessionKey = sessionKey
      self.preferLiveSession = false
      if not session.attendance then
        session.attendance = {tracking = false, members = {}, updatedAt = 0}
      end
      if self.ClearLiveRaidWatchMode then self:ClearLiveRaidWatchMode() end
      return session, "history-peek"
    end
    local opened, reason = PreviousOpenLootSession(self, sessionKey)
    if opened and self.RequestOfficerHistorySync then
      self:RequestOfficerHistorySync("open-session")
    end
    return opened, reason
  end

  local state = self:InitMultiRun()
  local current = state.activeRunID and state.runs[state.activeRunID] or nil
  if GetGroupChannel() then
    local sameLiveRun = current and current.id == runID
    local isHistory = session.archived or session.finalized or not sameLiveRun
    -- Anyone who can view the tracker may open history while in a raid.
    -- Non-ML included. Do not replace the live run.
    if isHistory and not sameLiveRun then
      self.historyPeekSessionKey = sessionKey
      self.preferLiveSession = false
      if not session.attendance then
        session.attendance = {tracking = false, members = {}, updatedAt = 0}
      end
      if self.ClearLiveRaidWatchMode then self:ClearLiveRaidWatchMode() end
      return session, "history-peek"
    end
    if sameLiveRun and (session.archived or session.finalized) then
      self.historyPeekSessionKey = sessionKey
      self.preferLiveSession = false
      if self.ClearLiveRaidWatchMode then self:ClearLiveRaidWatchMode() end
      return session, "history-peek"
    end
    self.historyPeekSessionKey = nil
    return PreviousOpenLootSession(self, sessionKey)
  end

  self.historyPeekSessionKey = nil

  local run = state.runs[runID]
  if not run then
    run = EnsureRunDefaults({
      id = runID,
      createdAt = tonumber(session.createdAt) or Now(),
      createdBy = session.createdBy,
      owner = session.syncAuthority or session.createdBy,
      ownerSetBy = session.createdBy or "",
      reason = "saved-session-review",
      status = "review",
      -- Guild-archive-only opens stay non-participating so archived stays true.
      participated = not session.archived,
      sessions = {},
    })
    state.runs[runID] = run
  end

  run.sessions[sessionKey] = true
  -- Keep guild-history archived unless this client participated in that run.
  -- History editors still edit archived sessions via history-edit mode
  -- without reopening them as live.
  if run.participated then
    session.archived = false
  end
  if not session.archived then
    run.participated = true
  end
  run.status = "review"
  state.reviewRunID = runID
  state.activeRunID = runID
  APOCLootPrioDB.loot.activeSessionKey = sessionKey
  if not session.attendance then
    session.attendance = {tracking = false, members = {}, updatedAt = 0}
  end
  self:MirrorMultiRunAssignments(run)
  if self.RequestOfficerHistorySync then
    self:RequestOfficerHistorySync("open-session")
  end
  return session
end

function APOCLootPrio:GetActiveLootSessionKey(preferredRaid)
  self:InitDB()
  local runID = self:GetActiveRunID()

  if self.historyPeekSessionKey and not self.capturingLiveLoot then
    local peek = APOCLootPrioDB.loot.sessions and APOCLootPrioDB.loot.sessions[self.historyPeekSessionKey]
    if peek then
      return self.historyPeekSessionKey
    end
    self.historyPeekSessionKey = nil
  end

  -- Out of group: keep an explicitly opened session active even if archived
  -- (Guild Raid History / history edit mode).
  if not GetGroupChannel() then
    local key = APOCLootPrioDB.loot.activeSessionKey
    local session = key and APOCLootPrioDB.loot.sessions[key] or nil
    if session then
      if not runID or not session.runID or session.runID == "" or session.runID == runID then
        return key
      end
    end
  end

  if not runID then
    local key = APOCLootPrioDB.loot.activeSessionKey
    local session = key and APOCLootPrioDB.loot.sessions[key] or nil
    if session and not session.archived then return key end
    local newestKey, newestAt = nil, -1
    for sessionKey, candidate in pairs(APOCLootPrioDB.loot.sessions or {}) do
      if not candidate.archived and (tonumber(candidate.createdAt) or 0) > newestAt then
        newestKey, newestAt = sessionKey, tonumber(candidate.createdAt) or 0
      end
    end
    APOCLootPrioDB.loot.activeSessionKey = newestKey
    return newestKey
  end
  local key = APOCLootPrioDB.loot.activeSessionKey
  local session = key and APOCLootPrioDB.loot.sessions[key] or nil
  if session and session.runID == runID then
    local closed = session.archived or session.finalized
    if self.preferLiveSession and closed then
      session = nil
    elseif not closed or not GetGroupChannel() then
      return key
    end
  end
  key = preferredRaid and APOCLootPrioDB.loot.current and APOCLootPrioDB.loot.current[preferredRaid] or nil
  session = key and APOCLootPrioDB.loot.sessions[key] or nil
  if session and session.runID == runID and not session.archived then
    APOCLootPrioDB.loot.activeSessionKey = key
    return key
  end
  local newestKey, newestAt = nil, -1
  for sessionKey, candidate in pairs(APOCLootPrioDB.loot.sessions or {}) do
    if candidate.runID == runID and not candidate.archived and not candidate.finalized and (tonumber(candidate.createdAt) or 0) > newestAt then
      newestKey, newestAt = sessionKey, tonumber(candidate.createdAt) or 0
    end
  end
  -- Out of group fallback: newest closed/history session for this run.
  if not newestKey and not GetGroupChannel() then
    for sessionKey, candidate in pairs(APOCLootPrioDB.loot.sessions or {}) do
      if candidate.runID == runID and (tonumber(candidate.createdAt) or 0) > newestAt then
        newestKey, newestAt = sessionKey, tonumber(candidate.createdAt) or 0
      end
    end
  end
  APOCLootPrioDB.loot.activeSessionKey = newestKey
  return newestKey
end

function APOCLootPrio:GetLootSessions()
  self:InitDB()
  local sessions = {}
  -- Include live and guild-archive sessions so Open Session can show other
  -- officers' closed raid nights. Quarantined copies live outside loot.sessions.
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    table.insert(sessions, session)
  end
  table.sort(sessions, function(a, b)
    if (tonumber(a.createdAt) or 0) ~= (tonumber(b.createdAt) or 0) then return (tonumber(a.createdAt) or 0) > (tonumber(b.createdAt) or 0) end
    return tostring(a.key or "") > tostring(b.key or "")
  end)
  return sessions
end

-- Phase 2 history editors: CanManageSettings OR guild rank index <= 2.
-- CanViewFeature("lootTracker") with rank <= 2 is covered by the rank check
-- whenever lootTracker access is configured within 0-2 (default is 1).
function APOCLootPrio:IsHistoryEditorSender(sender)
  local rank = self.GetGuildRankForName and self:GetGuildRankForName(ShortName(sender))
  return rank ~= nil and rank <= HISTORY_EDITOR_MAX_RANK
end

function APOCLootPrio:CanEditGuildRaidHistory()
  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() then return false end
  if self.CanManageSettings and self:CanManageSettings() then return true end
  local rankIndex = self.GetPlayerGuildRankIndex and self:GetPlayerGuildRankIndex() or nil
  if rankIndex ~= nil and rankIndex <= HISTORY_EDITOR_MAX_RANK then return true end
  if self.CanViewFeature and self:CanViewFeature("lootTracker") then
    if rankIndex ~= nil and rankIndex <= HISTORY_EDITOR_MAX_RANK then return true end
  end
  return false
end

function APOCLootPrio:GetActiveHistorySession()
  self:InitDB()
  local key = self.historyPeekSessionKey or APOCLootPrioDB.loot.activeSessionKey
  return key and APOCLootPrioDB.loot.sessions and APOCLootPrioDB.loot.sessions[key] or nil
end

function APOCLootPrio:IsClosedHistorySession(session)
  if not session or session.readOnly then return false end
  if session.archived or session.finalized then return true end
  return false
end

-- Claim only the selected, closed historical run for local bridge export.
-- This must not call EnsureActiveMultiRun(true): that path intentionally
-- starts a fresh solo run while reviewing history.
function APOCLootPrio:ClaimSelectedHistoryRunner()
  if GetGroupChannel() then return nil, "Leave the raid before taking over a saved history session." end
  if not self:CanEditGuildRaidHistory() then return nil, "Only a history editor can take over this raid." end
  local session = self:GetActiveHistorySession()
  if not self:IsClosedHistorySession(session) or not session.runID or session.runID == "" then
    return nil, "Open a closed raid from History first."
  end
  local me = self:GetPlayerDisplayName()
  if not me or me == "" then return nil, "Your character name is unavailable." end
  local state = self:InitMultiRun()
  if state.activeRunID ~= session.runID then
    return nil, "Open this raid from History again before changing its runner."
  end
  local run = EnsureRunDefaults(state.runs[session.runID] or {
    id = session.runID, createdAt = tonumber(session.createdAt) or Now(),
    createdBy = session.createdBy, status = "review", participated = false,
    sessions = {}, owner = session.syncAuthority or session.createdBy,
  })
  local previous = run.owner or session.syncAuthority or session.createdBy
  if not run.originalOwner or run.originalOwner == "" then run.originalOwner = previous end
  run.owner = me
  run.ownerSetBy = me
  run.ownerSetAt = Now()
  run.ownerVersion = self:NextMultiRunAssignmentVersion(run, "runner", me, me)
  run.status = "review"
  run.sessions[session.key] = true
  state.runs[session.runID] = run
  state.reviewRunID = session.runID
  state.activeRunID = session.runID
  self:MirrorMultiRunAssignments(run)
  return run.owner
end

function APOCLootPrio:IsHistoryEditContext()
  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() and not self.historyPeekSessionKey then return false end
  local session = self:GetActiveHistorySession()
  if self:IsClosedHistorySession(session) then
    -- Out of raid, or peeking history while in a live raid (non-ML included).
    if not GetGroupChannel() or self.historyPeekSessionKey then return true end
  end
  if GetGroupChannel() and not self.historyPeekSessionKey then return false end
  local run = self:GetActiveRun()
  if run and (run.status == "review" or run.status == "historical") then return true end
  return false
end

function APOCLootPrio:ClaimLocalNamedRunner()
  local unit = UnitName and UnitName("player") or nil
  if not unit or unit == "" or unit == "Unknown" then return false end
  local authority = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or nil
  local owner = self.GetLootTrackerOwner and self:GetLootTrackerOwner() or nil
  local named = (owner and owner ~= "" and owner) or authority
  if not named or named == "" or not SamePlayer(named, unit) then return false end
  local run = self:GetActiveRun()
  if run then
    run.lastAuthorityHeartbeatAt = Now()
    run.lastAuthorityHeartbeatFrom = self:GetPlayerDisplayName()
    if run.status == "review" then run.status = "active" end
  end
  if (not owner or owner == "") and self.SetLootTrackerOwner then
    self:SetLootTrackerOwner(self:GetPlayerDisplayName(), "local-name")
  end
  return true
end

function APOCLootPrio:CanEditLootTracker()
  -- History open (including non-ML peek while in a live raid).
  if self:IsHistoryEditContext() and self:CanEditGuildRaidHistory() then
    return true
  end
  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() then return false end
  if self.ClaimLocalNamedRunner and self:ClaimLocalNamedRunner() then
    return PreviousCanEditLootTracker and PreviousCanEditLootTracker(self) or true
  end

  -- Live group / active live raid: Master Looter only.
  if GetGroupChannel() then
    return PreviousCanEditLootTracker and PreviousCanEditLootTracker(self) or false
  end

  return PreviousCanEditLootTracker and PreviousCanEditLootTracker(self) or false
end

function APOCLootPrio:GetLootTrackerAccessText()
  if self:IsHistoryEditContext() and self:CanEditGuildRaidHistory() then
    return "History edit (ranks 0–2)"
  end
  return PreviousGetLootTrackerAccessText and PreviousGetLootTrackerAccessText(self) or "Loot tracker access unavailable."
end

-- History editors may add corrective drops to finalized/archived sessions while
-- out of group. Live finalized capture remains blocked by Core.
function APOCLootPrio:AddRaidLootDrop(item, bossName, raid, skipBroadcast)
  if not item then return nil end
  if self:IsHistoryEditContext() and self:CanEditGuildRaidHistory() then
    local session = self:GetRaidLootSession(raid, false)
    if session and session.key and not session.readOnly and (session.finalized or session.archived) then
      local wasFinalized = session.finalized and true or false
      session.finalized = false
      local drop, err = PreviousAddRaidLootDrop(self, item, bossName, raid, skipBroadcast)
      if wasFinalized then session.finalized = true end
      if drop then
        if wasFinalized and self.SaveFinalizedLootSessionBackup then
          self:SaveFinalizedLootSessionBackup(session)
        end
        if self.ScheduleHistorySessionPush then self:ScheduleHistorySessionPush(session) end
      end
      return drop, err
    end
  end
  return PreviousAddRaidLootDrop(self, item, bossName, raid, skipBroadcast)
end

function APOCLootPrio:GetActiveRunSessions()
  local runID = self:GetActiveRunID()
  local sessions = {}
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    if runID and session.runID == runID and not session.archived then table.insert(sessions, session) end
  end
  table.sort(sessions, function(a, b)
    if (tonumber(a.createdAt) or 0) ~= (tonumber(b.createdAt) or 0) then return (tonumber(a.createdAt) or 0) < (tonumber(b.createdAt) or 0) end
    return tostring(a.key or "") < tostring(b.key or "")
  end)
  return sessions
end

function APOCLootPrio:SendLootSyncV2Transfer(kind, payload)
  if not self:IsLocalLootSyncV2Authority() then return false end
  local run = self:GetActiveRun()
  if not run or not GetGroupChannel() then return false end
  local encoded = Escape(payload or "")
  local payloadHash = TextHash(encoded)
  local counter, writer, rank, epochHash = VersionFields(self:GetLootAuthorityEpoch())
  local replaceKey = self.multiRunLiveReplacementKey or (kind == "SC" and "SC" or nil)
  if replaceKey then
    replaceKey = tostring(run.id) .. ":" .. replaceKey
    self:EnsureMultiRunQueues()
    local queue = self.multiRunLiveQueue or {}
    for _, record in ipairs(queue) do
      if record.replaceKey == replaceKey and record.payloadHash == payloadHash and record.epochHash == epochHash then
        return true -- An identical complete transfer is already queued.
      end
    end
    -- An incomplete older revision cannot help a viewer. Replace its unsent
    -- chunks with one complete transfer of the latest revision.
    for index = #queue, 1, -1 do
      if queue[index].replaceKey == replaceKey then table.remove(queue, index) end
    end
  end
  local transferID = self:NextMultiRunTransferID("live")
  local total = math.max(1, math.ceil(string.len(encoded) / LIVE_CHUNK_BYTES))
  for index = 1, total do
    local first = ((index - 1) * LIVE_CHUNK_BYTES) + 1
    local chunk = string.sub(encoded, first, first + LIVE_CHUNK_BYTES - 1)
    self:QueueMultiRunLive(table.concat({
      "Q4", Escape(run.id), transferID, kind, tostring(index), tostring(total), payloadHash,
      counter, writer, rank, epochHash, chunk,
    }, "\t"))
    if replaceKey and self.multiRunQueueFrame then
      local record = self.multiRunLiveQueue[#self.multiRunLiveQueue]
      record.replaceKey, record.payloadHash, record.epochHash = replaceKey, payloadHash, epochHash
    end
  end
  return true
end

function APOCLootPrio:SendLootSessionV2(session)
  local runID = self:GetActiveRunID()
  if not session or not runID or session.runID ~= runID or session.archived then return false end
  local previous = self.multiRunLiveReplacementKey
  self.multiRunLiveReplacementKey = "FS:" .. tostring(session.key)
  local sent = PreviousSendLootSessionV2(self, session)
  self.multiRunLiveReplacementKey = previous
  return sent
end

function APOCLootPrio:SendAllLootSessions()
  if not self:IsLocalLootSyncV2Authority() then return false end
  for _, session in ipairs(self:GetActiveRunSessions()) do self:SendLootSessionV2(session) end
  return true
end

function APOCLootPrio:BroadcastLootSession(session)
  self:TagSessionForActiveRun(session)
  return self:SendLootSessionV2(session)
end

function APOCLootPrio:ScheduleMultiRunManifest()
  self.multiRunManifestToken = (tonumber(self.multiRunManifestToken) or 0) + 1
  local token = self.multiRunManifestToken
  local function send()
    if not APOCLootPrio or APOCLootPrio.multiRunManifestToken ~= token or not APOCLootPrio:IsLocalLootSyncV2Authority() then return end
    APOCLootPrio:QueueLootManifestV3()
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, send) else send() end
end

function APOCLootPrio:BroadcastLootSessionMetadata(session)
  self:TagSessionForActiveRun(session)
  if session.runID ~= self:GetActiveRunID() or session.archived then
    if HasAwardedDrop(session) then self:ScheduleGuildArchivePublish(session) end
    if self.ScheduleHistorySessionPush then self:ScheduleHistorySessionPush(session) end
    return false
  end
  local previous = self.multiRunLiveReplacementKey
  self.multiRunLiveReplacementKey = "SM:" .. tostring(session.key)
  local sent = PreviousBroadcastLootSessionMetadata(self, session)
  self.multiRunLiveReplacementKey = previous
  if sent then self:ScheduleMultiRunManifest() end
  return sent
end

function APOCLootPrio:BroadcastLootDropUpdate(session, drop)
  self:TagSessionForActiveRun(session)
  if session and (session.runID ~= self:GetActiveRunID() or session.archived or (session.finalized and not GetGroupChannel())) then
    if HasAwardedDrop(session) then self:ScheduleGuildArchivePublish(session) end
    if self.ScheduleHistorySessionPush then self:ScheduleHistorySessionPush(session) end
    return true
  end
  local previous = self.multiRunLiveReplacementKey
  self.multiRunLiveReplacementKey = "drop:" .. tostring(session.key) .. ":" .. tostring(drop and drop.id)
  local sent = PreviousBroadcastLootDropUpdate(self, session, drop)
  self.multiRunLiveReplacementKey = previous
  if sent then self:ScheduleMultiRunManifest() end
  if drop and drop.award and ((drop.award.winner and drop.award.winner ~= "") or drop.award.awardType == "GB") then
    self:ScheduleGuildArchivePublish(session)
  elseif session and session.archivePublishedRevision then
    self:ScheduleGuildArchivePublish(session)
  end
  if session and session.finalized and not GetGroupChannel() and self.ScheduleHistorySessionPush then
    self:ScheduleHistorySessionPush(session)
  end
  return sent
end

function APOCLootPrio:BroadcastLootDropDelete(session, dropID)
  self:TagSessionForActiveRun(session)
  if session and (session.runID ~= self:GetActiveRunID() or session.archived or (session.finalized and not GetGroupChannel())) then
    if HasAwardedDrop(session) then self:ScheduleGuildArchivePublish(session) end
    if self.ScheduleHistorySessionPush then self:ScheduleHistorySessionPush(session) end
    return true
  end
  local previous = self.multiRunLiveReplacementKey
  self.multiRunLiveReplacementKey = "drop:" .. tostring(session.key) .. ":" .. tostring(dropID)
  local sent = PreviousBroadcastLootDropDelete(self, session, dropID)
  self.multiRunLiveReplacementKey = previous
  if sent then self:ScheduleMultiRunManifest() end
  if session and session.archivePublishedRevision then self:ScheduleGuildArchivePublish(session) end
  return sent
end

function APOCLootPrio:BroadcastLootSessionDelete(sessionKey, revision, deletedRunID)
  local session = APOCLootPrioDB.loot.sessions[sessionKey]
  local runID = deletedRunID or (session and session.runID)
  if not runID then return false end
  if runID == self:GetActiveRunID() and self:IsLocalLootSyncV2Authority() then
    local previous = self.multiRunLiveReplacementKey
    self.multiRunLiveReplacementKey = "SD:" .. tostring(sessionKey)
    local sent = PreviousBroadcastLootSessionDelete(self, sessionKey, revision)
    self.multiRunLiveReplacementKey = previous
    if sent then self:ScheduleMultiRunManifest() end
    return sent
  end
  if self:CanEditGuildRaidHistory() then
    APOCLootPrioDB.loot.archiveSessionTombstones[runID .. ":" .. sessionKey] = revision
    return self:QueueMultiRunGuild(table.concat({"GD4", Escape(runID), Escape(sessionKey), tostring(revision or 0)}, "\t"))
  end
  return false
end

function APOCLootPrio:GetLootSessionManifest()
  local records = {"run=" .. tostring(self:GetActiveRunID() or ""), "active=" .. tostring(APOCLootPrioDB.loot.activeSessionKey or "")}
  local sessions, dropCount = self:GetActiveRunSessions(), 0
  for _, session in ipairs(sessions) do
    table.insert(records, Canonical({"session", session.key, session.revision or 0, session.name or "", session.createdAt or 0}))
    local drops = {}
    for _, drop in ipairs(session.drops or {}) do table.insert(drops, drop) end
    table.sort(drops, function(a, b) return tostring(a.id or "") < tostring(b.id or "") end)
    for _, drop in ipairs(drops) do
      local award = drop.award or {}
      dropCount = dropCount + 1
      table.insert(records, Canonical({"drop", session.key, drop.id or "", drop.syncRevision or 0, drop.itemID or "", award.winner or "", award.awardType or "", award.tradedTo or ""}))
    end
  end
  return TextHash(table.concat(records, string.char(30))), #sessions, dropCount
end

function APOCLootPrio:BuildLootSessionCatalogV3()
  local lines = {"A\t" .. Escape(APOCLootPrioDB.loot.activeSessionKey or "")}
  for _, session in ipairs(self:GetActiveRunSessions()) do table.insert(lines, "K\t" .. Escape(session.key)) end
  return table.concat(lines, "\n")
end

function APOCLootPrio:ApplyLootSessionCatalogV3(payload, sender)
  local runID = self.currentMultiRunIncomingRunID
  if not runID or runID ~= self:GetActiveRunID() then return false end
  local expected, activeKey = {}, nil
  for line in string.gmatch((payload or "") .. "\n", "(.-)\n") do
    local recordType, value = string.match(line, "^([^\t]+)\t(.*)$")
    if recordType == "A" then activeKey = Unescape(value)
    elseif recordType == "K" then local key = Unescape(value); if key ~= "" then expected[key] = true end end
  end
  local removed = 0
  APOCLootPrioDB.loot.quarantinedSessions = APOCLootPrioDB.loot.quarantinedSessions or {}
  for key, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    if session.runID == runID and not session.archived and not expected[key] then
      APOCLootPrioDB.loot.quarantinedSessions[key] = {session = session, quarantinedAt = Now(), reason = "Not present in this Run ID catalog", authority = ShortName(sender), runID = runID}
      APOCLootPrioDB.loot.sessions[key] = nil
      removed = removed + 1
    end
  end
  if activeKey and expected[activeKey] and APOCLootPrioDB.loot.sessions[activeKey] then APOCLootPrioDB.loot.activeSessionKey = activeKey end
  if removed > 0 then self:MultiRunDiagnostic("quarantinedSessions", removed) end
  return removed > 0
end

function APOCLootPrio:QueueLootManifestV3()
  local run = self:GetActiveRun()
  if not run then return false end
  local counter, writer, rank, epochHash = VersionFields(self:GetLootAuthorityEpoch())
  local digest, sessionCount, dropCount = self:GetLootSessionManifest()
  return self:QueueMultiRunLive(table.concat({
    "LM4", Escape(run.id), counter, writer, rank, epochHash, digest,
    tostring(sessionCount), tostring(dropCount), Escape(APOCLootPrioDB.loot.activeSessionKey or ""),
  }, "\t"))
end

function APOCLootPrio:RequestLootSessionSync()
  local run = self:GetActiveRun()
  if not run then self:RequestMultiRunSync(); return false end
  local counter, writer, rank, hash = VersionFields(self:GetLootAuthorityEpoch())
  return self:QueueMultiRunLive(table.concat({"L4", Escape(run.id), MULTIRUN_PROTOCOL, Escape(self:GetAddonVersion()), Escape(self:NextMultiRunTransferID("loot-request")), counter, writer, rank, hash}, "\t"))
end

-- A single broadcast serves every group member. Coalesce requests for the
-- same inventory while its actual snapshot packets are queued. Unrelated
-- heartbeats must not suppress recovery, nor should a completed, lost snapshot
-- suppress the viewer's immediate retry.
function APOCLootPrio:QueueActiveRunSnapshot()
  local run = self:GetActiveRun()
  if not run or not GetGroupChannel() or not self:IsLocalLootSyncV2Authority() then return false end
  local digest = self:GetLootSessionManifest()
  local counter, writer, rank, hash = VersionFields(self:GetLootAuthorityEpoch())
  local key = table.concat({run.id, digest, counter, writer, rank, hash}, "|")
  for _, record in ipairs(self.multiRunLiveQueue or {}) do
    if record.snapshotKey == key then return true end
  end
  local first = #(self.multiRunLiveQueue or {}) + 1
  self:SendAllLootSessions()
  self:SendLootSyncV2Transfer("SC", self:BuildLootSessionCatalogV3())
  self:QueueLootManifestV3()
  for index = first, #(self.multiRunLiveQueue or {}) do
    self.multiRunLiveQueue[index].snapshotKey = key
  end
  return true
end

function APOCLootPrio:TagIncomingLiveSession(key)
  if not key or key == "" then return end
  local session = APOCLootPrioDB.loot.sessions[key]
  if not session then return end
  session.runID = self.currentMultiRunIncomingRunID
  session.archived = false
  local run = self:GetActiveRun()
  if run and session.runID == run.id then run.sessions[key] = true end
end

function APOCLootPrio:ApplyLootSyncV2Full(payload, sender)
  local changed = PreviousApplyLootSyncV2Full(self, payload, sender)
  if changed then self:TagIncomingLiveSession(FirstPackedField(payload, true)) end
  return changed
end

function APOCLootPrio:ApplyLootSyncV2Metadata(payload, sender)
  local changed = PreviousApplyLootSyncV2Metadata(self, payload, sender)
  if changed then self:TagIncomingLiveSession(FirstPackedField(payload, false)) end
  return changed
end

function APOCLootPrio:ApplyLootSyncV2Drop(payload, sender)
  local changed = PreviousApplyLootSyncV2Drop(self, payload, sender)
  if changed then self:TagIncomingLiveSession(FirstPackedField(payload, false)) end
  return changed
end

function APOCLootPrio:ApplyLootSyncV2DropDelete(payload, sender)
  local changed = PreviousApplyLootSyncV2DropDelete(self, payload, sender)
  if changed then self:TagIncomingLiveSession(FirstPackedField(payload, false)) end
  return changed
end

function APOCLootPrio:ApplyLootSyncV2SessionDelete(payload)
  return PreviousApplyLootSyncV2SessionDelete(self, payload)
end

function APOCLootPrio:ReceiveMultiRunLiveChunk(parts, sender)
  local runID = Unescape(parts[2])
  if runID ~= self:GetActiveRunID() then self:MultiRunDiagnostic("rejectedWrongRun"); return end
  if not self:IsLootSyncV2AuthoritySender(sender) then self:MultiRunDiagnostic("rejectedWrongRunner"); return end
  local transformed = {"Q3", runID .. ":" .. tostring(parts[3] or ""), parts[4], parts[5], parts[6], parts[7], parts[8], parts[9], parts[10], parts[11], parts[12] or ""}
  self.currentMultiRunIncomingRunID = runID
  self:ReceiveLootSyncV3Chunk(transformed, sender)
  self.currentMultiRunIncomingRunID = nil
  self:MultiRunDiagnostic("liveApplied")
end

function APOCLootPrio:ScheduleGuildArchivePublish(session)
  if not session or not session.key or not HasAwardedDrop(session) then return false end
  self.multiRunArchiveTokens = self.multiRunArchiveTokens or {}
  local token = (tonumber(self.multiRunArchiveTokens[session.key]) or 0) + 1
  self.multiRunArchiveTokens[session.key] = token
  local function publish()
    if not APOCLootPrio or not APOCLootPrio.multiRunArchiveTokens or APOCLootPrio.multiRunArchiveTokens[session.key] ~= token then return end
    APOCLootPrio:PublishGuildArchiveSession(session)
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, publish) else publish() end
  return true
end

function APOCLootPrio:PublishGuildArchiveSession(session, target)
  if not self:IsClosedHistorySyncSession(session) then return false end
  if not session.runID or session.runID == "" then
    session.runID = self:GetActiveRunID() or ("local:" .. tostring(session.key))
  end
  if not session.archived and not session.finalized and session.runID == self:GetActiveRunID() and not self:IsLocalLootSyncV2Authority() then return false end
  local payload = self:BuildLootSessionSyncPayload(session, false)
  if not payload then return false end
  local encoded = Escape(payload)
  local hash = TextHash(encoded)
  local archiveKey = tostring(session.runID) .. ":" .. tostring(session.key) .. ":" .. tostring(target or "guild")
  self:EnsureMultiRunQueues()
  local queue = self.multiRunGuildQueue or {}
  for _, record in ipairs(queue) do
    if record.archiveKey == archiveKey and record.archiveHash == hash then
      return true -- The same revision is already waiting to go out.
    end
  end
  for index = #queue, 1, -1 do
    if queue[index].archiveKey == archiveKey then table.remove(queue, index) end
  end
  local transferID = self:NextMultiRunTransferID("archive")
  local total = math.max(1, math.ceil(string.len(encoded) / ARCHIVE_CHUNK_BYTES))
  for index = 1, total do
    local first = ((index - 1) * ARCHIVE_CHUNK_BYTES) + 1
    local chunk = string.sub(encoded, first, first + ARCHIVE_CHUNK_BYTES - 1)
    local queued = self:QueueMultiRunGuild(table.concat({"GA4", Escape(session.runID), transferID, tostring(index), tostring(total), hash, chunk}, "\t"), target)
    if not queued then return false end
    if self.multiRunQueueFrame then
      local record = self.multiRunGuildQueue[#self.multiRunGuildQueue]
      if record then record.archiveKey, record.archiveHash = archiveKey, hash end
    end
  end
  session.archivePublishedRevision = tonumber(session.revision) or 0
  session.archivePublishedAt = Now()
  return true
end

function APOCLootPrio:SendAllGuildArchive(target)
  local sessions = {}
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    if HasAwardedDrop(session) then table.insert(sessions, session) end
  end
  table.sort(sessions, function(a, b) return tostring(a.key or "") < tostring(b.key or "") end)
  local published = 0
  for _, session in ipairs(sessions) do
    if session.archived or session.finalized or not session.runID or session.runID == "" or session.runID ~= self:GetActiveRunID() or self:IsLocalLootSyncV2Authority() then
      if self:PublishGuildArchiveSession(session, target) then published = published + 1 end
    end
  end
  return published
end

local ARCHIVE_PEER_RECENT = 30 * 60
local ARCHIVE_PEER_UNKNOWN_RECENT = 5 * 60
local ARCHIVE_PEER_CAP = 3
local ARCHIVE_PEER_MIN_BETA = 13

local function ParseBetaAddonVersion(version)
  -- Accept feature-suffixed builds such as beta.90-native-comms.1.
  local betaNum = tonumber(string.match(tostring(version or ""), "^0%.2%.0%-beta%.(%d+)"))
  return betaNum
end

function APOCLootPrio:CollectFilteredGuildArchivePeers()
  self:InitDB()
  local now = Now()
  local candidates = {}
  local seen = {}
  local inSyncedClients = {}

  if self.GetSyncedClients then
    for _, client in ipairs(self:GetSyncedClients() or {}) do
      if client and not client.isLocal and client.name and client.name ~= "" then
        inSyncedClients[PlayerKey(client.name)] = true
      end
    end
  end

  local function consider(name, lastSeen, addonVersion, fromSyncedClients)
    if not name or name == "" then return end
    if SamePlayer(name, self:GetPlayerDisplayName()) then return end
    local key = PlayerKey(name)
    if not key or key == "" or seen[key] then return end

    local seenAt = tonumber(lastSeen)
    local hasSeen = seenAt and seenAt > 0
    if hasSeen then
      if now > 0 and (now - seenAt) > ARCHIVE_PEER_RECENT then return end
    else
      -- Missing lastSeen: only allow if present in this session's GetSyncedClients list.
      if not fromSyncedClients and not inSyncedClients[key] then return end
    end

    local betaNum = ParseBetaAddonVersion(addonVersion)
    local versionUnknown = not addonVersion or addonVersion == ""
    if betaNum then
      if betaNum < ARCHIVE_PEER_MIN_BETA then return end
    elseif versionUnknown then
      -- Unknown version: require lastSeen within 5m, or missing lastSeen from this session's synced-clients list.
      if hasSeen then
        if now > 0 and (now - seenAt) > ARCHIVE_PEER_UNKNOWN_RECENT then return end
      elseif not fromSyncedClients and not inSyncedClients[key] then
        return
      end
    else
      -- Known non-matching version (e.g. release or other beta line): skip.
      return
    end

    seen[key] = true
    table.insert(candidates, {
      name = ShortName(name) or name,
      lastSeen = hasSeen and seenAt or 0,
      addonVersion = addonVersion or "",
    })
  end

  for name, peer in pairs((APOCLootPrioDB.sync and APOCLootPrioDB.sync.peers) or {}) do
    consider(peer and peer.name or name, peer and peer.lastSeen, peer and peer.addonVersion, false)
  end
  if self.GetSyncedClients then
    for _, client in ipairs(self:GetSyncedClients() or {}) do
      if client and not client.isLocal then
        consider(client.name, client.lastSeen, client.addonVersion, true)
      end
    end
  end

  table.sort(candidates, function(a, b)
    local aSeen = tonumber(a.lastSeen) or 0
    local bSeen = tonumber(b.lastSeen) or 0
    if aSeen ~= bSeen then return aSeen > bSeen end
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  local peers = {}
  for index, candidate in ipairs(candidates) do
    if index > ARCHIVE_PEER_CAP then break end
    table.insert(peers, candidate.name)
  end
  return peers
end

function APOCLootPrio:SendGuildArchiveToSyncedPeers()
  self:InitDB()
  local peers = self:CollectFilteredGuildArchivePeers()

  local sessionCount = 0
  if #peers > 0 then
    for _, peerName in ipairs(peers) do
      sessionCount = self:SendAllGuildArchive(peerName) or 0
    end
    self:Print("Whispered archives to " .. table.concat(peers, ", ") .. " (" .. tostring(#peers) .. " peer(s)); " .. tostring(sessionCount) .. " session(s) each.")
  else
    sessionCount = self:SendAllGuildArchive() or 0
    self:Print("Guild archive publish queued for " .. tostring(sessionCount) .. " session(s) (no filtered synced peers; guild broadcast).")
  end
  return #peers, sessionCount, peers
end

-- Phase 2 officer history sync (HS4/HP4/HK4): whisper closed-session payloads
-- among recent compatible peers with ACK + retry. Does not replace live Q4/LB4.
-- GA4/GH4 remain for backward-compatible archive publish.
function APOCLootPrio:IsClosedHistorySyncSession(session)
  if not session or not session.key then return false end
  if session.readOnly then return false end
  if session.archived or session.finalized then return true end
  if HasAwardedDrop(session) and (not GetGroupChannel() or session.runID ~= self:GetActiveRunID()) then
    return true
  end
  return false
end

function APOCLootPrio:CollectHistorySyncPeers()
  local peers = self:CollectFilteredGuildArchivePeers() or {}
  if #peers > HISTORY_PEER_CAP then
    local trimmed = {}
    for index = 1, HISTORY_PEER_CAP do table.insert(trimmed, peers[index]) end
    return trimmed
  end
  return peers
end

function APOCLootPrio:EnsureHistorySyncState()
  self.pendingHistoryAcks = self.pendingHistoryAcks or {}
  self.incomingMultiRunHistory = self.incomingMultiRunHistory or {}
  self.historyPushTokens = self.historyPushTokens or {}
end

function APOCLootPrio:BuildHistorySessionChunks(session)
  if not session or not self.BuildLootSessionSyncPayload then return nil end
  if not session.runID or session.runID == "" then
    session.runID = self:GetActiveRunID() or ("local:" .. tostring(session.key))
  end
  local payload = self:BuildLootSessionSyncPayload(session, false)
  if not payload then return nil end
  local encoded = Escape(payload)
  local transferID = self:NextMultiRunTransferID("history")
  local total = math.max(1, math.ceil(string.len(encoded) / HISTORY_CHUNK_BYTES))
  local hash = TextHash(encoded)
  local messages = {}
  for index = 1, total do
    local first = ((index - 1) * HISTORY_CHUNK_BYTES) + 1
    local chunk = string.sub(encoded, first, first + HISTORY_CHUNK_BYTES - 1)
    table.insert(messages, table.concat({
      "HP4", Escape(session.runID), transferID, tostring(index), tostring(total), hash, chunk,
    }, "\t"))
  end
  return transferID, messages, hash, total
end

function APOCLootPrio:PublishHistorySessionToPeer(session, peerName)
  if not session or not peerName or peerName == "" then return false end
  if not self:IsClosedHistorySyncSession(session) then return false end
  self:EnsureHistorySyncState()
  local transferID, messages = self:BuildHistorySessionChunks(session)
  if not transferID or not messages then return false end
  local peer = ShortName(peerName) or peerName
  self.pendingHistoryAcks[transferID] = {
    peer = peer,
    sessionKey = session.key,
    runID = session.runID,
    messages = messages,
    attempts = 1,
  }
  self:QueueHistoryTransfer(self.pendingHistoryAcks[transferID])
  return true
end

function APOCLootPrio:PushHistorySessionToPeers(session, peers)
  if not session then return 0 end
  peers = peers or self:CollectHistorySyncPeers()
  local sent = 0
  for _, peerName in ipairs(peers or {}) do
    if self:PublishHistorySessionToPeer(session, peerName) then sent = sent + 1 end
  end
  return sent
end

function APOCLootPrio:SendAllClosedHistoryToPeer(peerName)
  if not peerName or peerName == "" then return 0 end
  local sessions = {}
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    if self:IsClosedHistorySyncSession(session) then
      table.insert(sessions, session)
    end
  end
  table.sort(sessions, function(a, b) return tostring(a.key or "") < tostring(b.key or "") end)
  local published = 0
  for _, session in ipairs(sessions) do
    if self:PublishHistorySessionToPeer(session, peerName) then published = published + 1 end
  end
  return published
end

function APOCLootPrio:ScheduleHistorySessionPush(session)
  if not session or not session.key then return false end
  if GetGroupChannel() and not session.archived and not session.finalized then return false end
  self:EnsureHistorySyncState()
  local token = (tonumber(self.historyPushTokens[session.key]) or 0) + 1
  self.historyPushTokens[session.key] = token
  local function push()
    if not APOCLootPrio or not APOCLootPrio.historyPushTokens or APOCLootPrio.historyPushTokens[session.key] ~= token then return end
    local peers = APOCLootPrio:CollectHistorySyncPeers()
    local sent = APOCLootPrio:PushHistorySessionToPeers(session, peers)
    if sent > 0 and APOCLootPrio.Print then
      APOCLootPrio:Print("History sync pushed to " .. tostring(sent) .. " officer peer(s).")
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.8, push) else push() end
  return true
end

function APOCLootPrio:RequestOfficerHistorySync(reason)
  if not IsInGuild or not IsInGuild() then return false end
  local now = Now()
  if now > 0 and self.multiRunLastHistoryRequestAt and (now - self.multiRunLastHistoryRequestAt) < 15 then
    return false
  end
  self.multiRunLastHistoryRequestAt = now
  local peers = self:CollectHistorySyncPeers()
  if #peers == 0 then
    -- No whisper peers: legacy GH4 handled by RequestGuildArchiveSync caller.
    return false
  end
  local requestID = self:NextMultiRunTransferID("history-request")
  local message = table.concat({
    "HS4", MULTIRUN_PROTOCOL, Escape(self:GetAddonVersion()), Escape(requestID), Escape(reason or "manual"),
  }, "\t")
  for _, peerName in ipairs(peers) do
    self:QueueMultiRunGuild(message, peerName)
  end
  if self.Print then
    self:Print("History sync requested from " .. table.concat(peers, ", ") .. " (" .. tostring(reason or "manual") .. ").")
  end
  return true
end

function APOCLootPrio:ReceiveHistorySyncRequest(parts, sender)
  if not self:IsGuildSyncSender(sender) then return end
  local replyTarget = ShortName(sender) or sender
  local now = Now()
  self.multiRunHistoryReplyAt = self.multiRunHistoryReplyAt or {}
  local replyKey = PlayerKey(replyTarget)
  local lastReply = tonumber(self.multiRunHistoryReplyAt[replyKey]) or 0
  if now > 0 and lastReply > 0 and (now - lastReply) < 45 then return end
  self.multiRunHistoryReplyAt[replyKey] = now
  local delay = 1 + math.fmod(tonumber(string.match(TextHash(PlayerKey(self:GetPlayerDisplayName())), "^(%d+)")) or 0, 3)
  self.multiRunHistoryReplyToken = self.multiRunHistoryReplyToken or {}
  local token = (tonumber(self.multiRunHistoryReplyToken[replyKey]) or 0) + 1
  self.multiRunHistoryReplyToken[replyKey] = token
  local function replyHistory()
    if not APOCLootPrio or APOCLootPrio.multiRunHistoryReplyToken[replyKey] ~= token then return end
    local sessionCount = APOCLootPrio:SendAllClosedHistoryToPeer(replyTarget) or 0
    if APOCLootPrio.Print then
      APOCLootPrio:Print("Sending guild raid history to " .. tostring(replyTarget) .. "… " .. tostring(sessionCount) .. " session(s).")
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(delay, replyHistory) else replyHistory() end
end

-- Equal revisions can contain concurrent edits. Retain the losing payload.
function APOCLootPrio:ShouldApplyHistoryPayload(existing, payload, incomingRevision, sender)
  if not existing then return true end
  local revision = tonumber(existing.revision) or 0
  if revision ~= incomingRevision then return incomingRevision > revision end
  local current = self:BuildLootSessionSyncPayload(existing, false) or ""
  if current == payload then return false end
  local currentHash, incomingHash = TextHash(current), TextHash(payload)
  local apply = incomingHash > currentHash
  local loot = APOCLootPrioDB.loot
  loot.historyConflicts = loot.historyConflicts or {}
  table.insert(loot.historyConflicts, {sessionKey=existing.key, revision=revision,
    receivedAt=Now(), sender=sender, payload=apply and current or payload})
  while #loot.historyConflicts > 30 do table.remove(loot.historyConflicts, 1) end
  self:MultiRunDiagnostic("historyConflicts")
  return apply
end

function APOCLootPrio:ReceiveHistorySessionChunk(parts, sender)
  if not self:IsHistoryEditorSender(sender) then return end
  local runID, transferID = Unescape(parts[2]), parts[3]
  local index, total, hash, chunk = tonumber(parts[4]), tonumber(parts[5]), parts[6], parts[7] or ""
  if not runID or runID == "" or not transferID or not index or not total or index < 1 or index > total or total > 4096 then
    self:MultiRunDiagnostic("corruptTransfers")
    return
  end
  self:EnsureHistorySyncState()
  local key = PlayerKey(sender) .. ":" .. runID .. ":" .. transferID
  local transfer = self.incomingMultiRunHistory[key]
  if not transfer or transfer.total ~= total or transfer.hash ~= hash then
    transfer = {runID = runID, total = total, hash = hash, chunks = {}, received = 0, startedAt = Now()}
    self.incomingMultiRunHistory[key] = transfer
  end
  if not transfer.chunks[index] then
    transfer.chunks[index] = chunk
    transfer.received = transfer.received + 1
  elseif transfer.chunks[index] ~= chunk then
    self.incomingMultiRunHistory[key] = nil
    self:MultiRunDiagnostic("corruptTransfers")
    self:QueueMultiRunGuild(table.concat({"HK4", Escape(transferID), "0", "retry"}, "\t"), ShortName(sender) or sender)
    return
  end
  if transfer.received < total then return end
  local encoded = table.concat(transfer.chunks, "")
  self.incomingMultiRunHistory[key] = nil
  if TextHash(encoded) ~= hash then
    self:MultiRunDiagnostic("corruptTransfers")
    self:QueueMultiRunGuild(table.concat({"HK4", Escape(transferID), "0", "retry"}, "\t"), ShortName(sender) or sender)
    return
  end
  local payload = Unescape(encoded)
  local sessionKey = FirstPackedField(payload, true)
  local incomingRevision = FullPayloadRevision(payload)
  local archiveTombstone = tonumber(APOCLootPrioDB.loot.archiveSessionTombstones[runID .. ":" .. tostring(sessionKey or "")]) or -1
  if archiveTombstone >= incomingRevision then
    self:QueueMultiRunGuild(table.concat({"HK4", Escape(transferID), tostring(total), "ok"}, "\t"), ShortName(sender) or sender)
    return
  end
  local state = self:InitMultiRun()
  local existing = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  if existing and (existing.runID ~= runID or (existing.runID == self:GetActiveRunID()
    and not existing.finalized and not existing.archived)) then return end
  if runID == self:GetActiveRunID() and GetGroupChannel() then return end
  if not self:ShouldApplyHistoryPayload(existing, payload, incomingRevision, sender) then
    self:QueueMultiRunGuild(table.concat({"HK4", Escape(transferID), tostring(total), "ok"}, "\t"), ShortName(sender) or sender)
    return
  end
  local existingRun = state.runs[runID]
  local preserveLiveSession = existing and existing.runID == runID
    and (not existing.archived or (existingRun and existingRun.participated)) or false
  local activeKey = APOCLootPrioDB.loot.activeSessionKey
  local changed = PreviousApplyLootSyncV2Full(self, payload, sender)
  APOCLootPrioDB.loot.activeSessionKey = activeKey
  local session = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  if session then
    session.runID = runID
    session.archived = preserveLiveSession and false or true
    session.archivePublishedRevision = tonumber(session.revision) or 0
    session.archiveReceivedAt = Now()
    local run = EnsureRunDefaults(state.runs[runID] or {id = runID, createdAt = session.createdAt, createdBy = session.createdBy, status = "historical", sessions = {}})
    if preserveLiveSession then
      run.participated = true
      if run.status == "historical" then run.status = "review" end
    else
      run.status = run.status == "active" and "active" or "historical"
    end
    run.sessions[sessionKey] = true
    state.runs[runID] = run
    local displayName = (self.GetLootSessionDisplayName and self:GetLootSessionDisplayName(session)) or session.name or session.key or "session"
    self:Print("History sync from " .. tostring(ShortName(sender) or sender) .. ": " .. tostring(displayName) .. " (" .. tostring(#(session.drops or {})) .. " drops).")
  end
  self:QueueMultiRunGuild(table.concat({"HK4", Escape(transferID), tostring(total), "ok"}, "\t"), ShortName(sender) or sender)
  if changed then self:MultiRunDiagnostic("archiveApplied") end
  if changed or session then
    if self.RefreshGuildLootPanel then self:RefreshGuildLootPanel() end
    if self.RefreshRecentAwardsPanel then self:RefreshRecentAwardsPanel() end
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
    if self.RefreshLootSessionPicker then self:RefreshLootSessionPicker() end
  end
end

function APOCLootPrio:ReceiveHistoryAck(parts, sender)
  local transferID, status = Unescape(parts[2]), string.lower(tostring(parts[4] or parts[3] or ""))
  if not transferID or transferID == "" then return end
  self:EnsureHistorySyncState()
  local pending = self.pendingHistoryAcks[transferID]
  if not pending then return end
  if not SamePlayer(pending.peer, sender) then return end
  if status == "ok" then
    self.pendingHistoryAcks[transferID] = nil
    return
  end
  if status == "retry" and not pending.queued then
    pending.attempts = (tonumber(pending.attempts) or 1) + 1
    if pending.attempts > HISTORY_MAX_RETRIES then
      self.pendingHistoryAcks[transferID] = nil
      return
    end
    self:QueueHistoryTransfer(pending)
  end
end

function APOCLootPrio:FlushPendingHistoryAcks()
  self:EnsureHistorySyncState()
  local now = Now()
  for transferID, pending in pairs(self.pendingHistoryAcks) do
    local sentAt = tonumber(pending.sentAt) or 0
    if now > 0 and sentAt > 0 and (now - sentAt) >= HISTORY_ACK_TIMEOUT then
      pending.attempts = (tonumber(pending.attempts) or 1) + 1
      if pending.attempts > HISTORY_MAX_RETRIES then
        self.pendingHistoryAcks[transferID] = nil
      else
        self:QueueHistoryTransfer(pending)
      end
    end
  end
end

function APOCLootPrio:RequestGuildArchiveSync()
  if not IsInGuild or not IsInGuild() then return false end
  local now = Now()
  if now > 0 and self.multiRunLastArchiveRequestAt and (now - self.multiRunLastArchiveRequestAt) < 20 then
    return false
  end
  self.multiRunLastArchiveRequestAt = now
  -- Prefer officer whisper history sync (HS4); GH4 only when no whisper peers.
  if self:RequestOfficerHistorySync("archive-request") then
    return true
  end
  return self:QueueMultiRunGuild(table.concat({"GH4", MULTIRUN_PROTOCOL, Escape(self:GetAddonVersion()), Escape(self:NextMultiRunTransferID("archive-request"))}, "\t"))
end

function APOCLootPrio:ReceiveGuildArchiveChunk(parts, sender)
  if not self:IsHistoryEditorSender(sender) then return end
  local runID, transferID = Unescape(parts[2]), parts[3]
  local index, total, hash, chunk = tonumber(parts[4]), tonumber(parts[5]), parts[6], parts[7] or ""
  if not runID or runID == "" or not transferID or not index or not total or index < 1 or index > total or total > 4096 then
    self:MultiRunDiagnostic("corruptTransfers")
    return
  end
  self.incomingMultiRunArchive = self.incomingMultiRunArchive or {}
  local key = PlayerKey(sender) .. ":" .. runID .. ":" .. transferID
  local transfer = self.incomingMultiRunArchive[key]
  if not transfer or transfer.total ~= total or transfer.hash ~= hash then
    transfer = {runID = runID, total = total, hash = hash, chunks = {}, received = 0, startedAt = Now()}
    self.incomingMultiRunArchive[key] = transfer
  end
  if not transfer.chunks[index] then
    transfer.chunks[index] = chunk
    transfer.received = transfer.received + 1
    transfer.lastProgressAt = Now()
  elseif transfer.chunks[index] ~= chunk then self.incomingMultiRunArchive[key] = nil; self:MultiRunDiagnostic("corruptTransfers"); return end
  if transfer.received < total then return end
  local encoded = table.concat(transfer.chunks, "")
  self.incomingMultiRunArchive[key] = nil
  if TextHash(encoded) ~= hash then self:MultiRunDiagnostic("corruptTransfers"); return end
  local payload = Unescape(encoded)
  local sessionKey = FirstPackedField(payload, true)
  local incomingRevision = FullPayloadRevision(payload)
  local archiveTombstone = tonumber(APOCLootPrioDB.loot.archiveSessionTombstones[runID .. ":" .. tostring(sessionKey or "")]) or -1
  if archiveTombstone >= incomingRevision then return end
  local state = self:InitMultiRun()
  local existing = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  if existing and (existing.runID ~= runID or (existing.runID == self:GetActiveRunID()
    and not existing.finalized and not existing.archived)) then return end
  if runID == self:GetActiveRunID() and GetGroupChannel() then return end
  -- Skip same-run archive only when local already has equal/higher revision; still apply missing history.
  if not self:ShouldApplyHistoryPayload(existing, payload, incomingRevision, sender) then
    return
  end
  local existingRun = state.runs[runID]
  local preserveLiveSession = existing and existing.runID == runID
    and (not existing.archived or (existingRun and existingRun.participated)) or false
  local activeKey = APOCLootPrioDB.loot.activeSessionKey
  local changed = PreviousApplyLootSyncV2Full(self, payload, sender)
  APOCLootPrioDB.loot.activeSessionKey = activeKey
  local session = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  if session then
    session.runID = runID
    session.archived = preserveLiveSession and false or true
    session.archivePublishedRevision = tonumber(session.revision) or 0
    session.archiveReceivedAt = Now()
    local run = EnsureRunDefaults(state.runs[runID] or {id = runID, createdAt = session.createdAt, createdBy = session.createdBy, status = "historical", sessions = {}})
    if preserveLiveSession then
      run.participated = true
      if run.status == "historical" then run.status = "review" end
    else
      run.status = run.status == "active" and "active" or "historical"
    end
    run.sessions[sessionKey] = true
    state.runs[runID] = run
  end
  if session then
    local displayName = (self.GetLootSessionDisplayName and self:GetLootSessionDisplayName(session)) or session.name or session.key or "session"
    local dropCount = #(session.drops or {})
    self:Print("Guild archive received from " .. tostring(ShortName(sender) or sender) .. ": " .. tostring(displayName) .. " (" .. tostring(dropCount) .. " drops).")
  end
  if changed then
    self:MultiRunDiagnostic("archiveApplied")
  end
  if changed or session then
    if self.RefreshGuildLootPanel then self:RefreshGuildLootPanel() end
    if self.RefreshRecentAwardsPanel then self:RefreshRecentAwardsPanel() end
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
    if self.RefreshLootSessionPicker then self:RefreshLootSessionPicker() end
  end
end

function APOCLootPrio:RequestSync()
  if PreviousRequestSync then PreviousRequestSync(self) end
  self:RequestMultiRunSync()
  self:RequestGuildArchiveSync()
end

function APOCLootPrio:HandleRunSyncMessage(message, sender)
  if SamePlayer(sender, self:GetPlayerDisplayName()) then return end
  local parts = SplitTabs(message)
  local kind = parts[1]

  if kind == "RR4" then
    if not self:IsCurrentGroupMember(sender) then self:MultiRunDiagnostic("rejectedWrongGroup"); return end
    local run = self:EnsureActiveMultiRun(IsLocalGroupLeader())
    if run and (IsLocalGroupLeader() or self:IsLocalLootSyncV2Authority()) then self:BroadcastMultiRunBeacon() end
    return
  end

  if kind == "RB4" then
    if not self:IsCurrentGroupMember(sender) then self:MultiRunDiagnostic("rejectedWrongGroup"); return end
    local before = self:GetActiveRunID()
    local adopted = self:AdoptMultiRun(Unescape(parts[2]), tonumber(parts[3]), Unescape(parts[4]), sender)
    if adopted and (before ~= self:GetActiveRunID() or #self:GetActiveRunSessions() == 0) then self:RequestLootSessionSync() end
    return
  end

  if kind == "AS4" then
    if not self:IsCurrentGroupMember(sender) then self:MultiRunDiagnostic("rejectedWrongGroup"); return end
    self:ApplyMultiRunAssignment(parts, sender)
    return
  end

  if kind == "HB4" then
    local runID = Unescape(parts[2])
    if runID ~= self:GetActiveRunID() or not self:IsLootSyncV2AuthoritySender(sender) then self:MultiRunDiagnostic("rejectedWrongRunner"); return end
    local run = self:GetActiveRun()
    -- Credit presence even when the authority epoch drifted; otherwise viewers
    -- falsely show the ML as OFFLINE while they are still in the raid.
    run.lastAuthorityHeartbeatAt = Now()
    run.lastAuthorityHeartbeatFrom = sender
    run.lastAuthorityVersion = Unescape(parts[7])
    local incoming = VersionFromParts(parts[3], parts[4], parts[5], parts[6])
    if CompareVersions(incoming, self:GetLootAuthorityEpoch()) ~= 0 then
      self:MultiRunDiagnostic("heartbeatEpochMismatch")
    end
    return
  end

  if kind == "RF4" then
    local runID, token = Unescape(parts[2]), Unescape(parts[3])
    local permitted = IsSenderGroupLeader(sender) or IsSenderGroupAssist(sender) or (self.IsTrustedLootTrackerEditor and self:IsTrustedLootTrackerEditor(sender))
    if runID ~= self:GetActiveRunID() or not permitted then self:MultiRunDiagnostic("rejectedWrongGroup"); return end
    local run = self:GetActiveRun()
    run.recoveryToken = token
    run.recoverySource = sender
    run.recoveryDesiredOwner = Unescape(parts[4])
    run.recoverySetBy = Unescape(parts[5])
    run.recoverySourceVerified = parts[6] == "1"
    run.recoveryExpiresAt = Now() + RECOVERY_WINDOW
    return
  end

  if kind == "QR4" then self:ReceiveMultiRunRecoveryChunk(parts, sender); return end

  if kind == "HR4" then
    local runID, desired, setBy = Unescape(parts[2]), Unescape(parts[3]), Unescape(parts[4])
    if runID ~= self:GetActiveRunID() or not self:IsCurrentGroupMember(sender) then self:MultiRunDiagnostic("rejectedWrongRun"); return end
    local permitted = IsSenderGroupLeader(sender) or IsSenderGroupAssist(sender)
    if not permitted and self.IsTrustedLootTrackerEditor then permitted = self:IsTrustedLootTrackerEditor(sender) end
    if not permitted and self.CanNameRunLootTracker then permitted = self:CanNameRunLootTracker(sender) end
    if permitted and self:IsLocalLootSyncV2Authority() then self:SetLootTrackerOwner(desired, setBy ~= "" and setBy or sender) end
    return
  end

  if kind == "L4" then
    if not self:IsCurrentGroupMember(sender) or Unescape(parts[2]) ~= self:GetActiveRunID() then self:MultiRunDiagnostic("rejectedWrongRun"); return end
    if self:IsLocalLootSyncV2Authority() then
      self:QueueActiveRunSnapshot()
    end
    return
  end

  if kind == "LM4" then
    local runID = Unescape(parts[2])
    if runID ~= self:GetActiveRunID() or not self:IsLootSyncV2AuthoritySender(sender) then self:MultiRunDiagnostic("rejectedWrongRunner"); return end
    local transformed = {"LM3", parts[3], parts[4], parts[5], parts[6], parts[7], parts[8], parts[9], parts[10]}
    if PreviousApplyLootManifestV3 then PreviousApplyLootManifestV3(self, transformed, sender) end
    return
  end

  if kind == "Q4" then self:ReceiveMultiRunLiveChunk(parts, sender); return end

  if kind == "HS4" then
    self:ReceiveHistorySyncRequest(parts, sender)
    return
  end

  if kind == "HP4" then
    self:ReceiveHistorySessionChunk(parts, sender)
    return
  end

  if kind == "HK4" then
    self:ReceiveHistoryAck(parts, sender)
    return
  end

  if kind == "GH4" then
    if not self:IsGuildSyncSender(sender) then return end
    local replyTarget = ShortName(sender) or sender
    local now = Now()
    self.multiRunArchiveReplyAt = self.multiRunArchiveReplyAt or {}
    local replyKey = PlayerKey(replyTarget)
    local lastReply = tonumber(self.multiRunArchiveReplyAt[replyKey]) or 0
    -- Debounce repeated GH4 floods (sync retries / multiple officers).
    if now > 0 and lastReply > 0 and (now - lastReply) < 60 then
      return
    end
    self.multiRunArchiveReplyAt[replyKey] = now
    local delay = 1 + math.fmod(tonumber(string.match(TextHash(PlayerKey(self:GetPlayerDisplayName())), "^(%d+)")) or 0, 4)
    self.multiRunArchiveReplyToken = self.multiRunArchiveReplyToken or {}
    local token = (tonumber(self.multiRunArchiveReplyToken[replyKey]) or 0) + 1
    self.multiRunArchiveReplyToken[replyKey] = token
    local scheduledFor = replyKey
    local function replyArchives()
      if not APOCLootPrio or APOCLootPrio.multiRunArchiveReplyToken[replyKey] ~= token then return end
      local sessionCount = APOCLootPrio:SendAllGuildArchive(replyTarget) or 0
      -- Status stays on the addon panel. Do not print into the chat window.
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(delay, replyArchives)
    else
      replyArchives()
    end
    return
  end

  if kind == "GA4" then self:ReceiveGuildArchiveChunk(parts, sender); return end

  if kind == "GD4" then
    if not self:IsHistoryEditorSender(sender) then return end
    local runID, sessionKey, revision = Unescape(parts[2]), Unescape(parts[3]), tonumber(parts[4]) or 0
    if runID == self:GetActiveRunID() then return end
    local session = APOCLootPrioDB.loot.sessions[sessionKey]
    if session and session.runID == runID and (tonumber(session.revision) or 0) <= revision then APOCLootPrioDB.loot.sessions[sessionKey] = nil end
    local key = runID .. ":" .. sessionKey
    APOCLootPrioDB.loot.archiveSessionTombstones[key] = math.max(revision, tonumber(APOCLootPrioDB.loot.archiveSessionTombstones[key]) or 0)
    return
  end

  -- The beta prefix is separate, but explicitly block live V3/global runner
  -- packets so a partially upgraded beta client cannot lose Run-ID isolation.
  if kind == "Q3" or kind == "L3" or kind == "LM3" or kind == "AR3" or kind == "AD3" then
    self:MultiRunDiagnostic("rejectedWrongRun")
    return
  end

end

function APOCLootPrio:PrintMultiRunStatus()
  local state = self:InitMultiRun()
  local run = self:GetActiveRun()
  local digest, sessions, drops = self:GetLootSessionManifest()
  local health, healthLabel, heartbeatAge = self:GetMultiRunRunnerHealth()
  local withRunID, withoutRunID, finalizedCount = 0, 0, 0
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    if session.runID and session.runID ~= "" then withRunID = withRunID + 1 else withoutRunID = withoutRunID + 1 end
    if session.finalized then finalizedCount = finalizedCount + 1 end
  end
  local guildQueueLen = #(self.multiRunGuildQueue or {})
  local liveQueueLen = #(self.multiRunLiveQueue or {})
  self:Print("Multi-Run beta protocol " .. MULTIRUN_PROTOCOL .. " | Run " .. self:GetRunShortID(run and run.id) .. " | channel " .. tostring(GetGroupChannel() or "local only"))
  self:Print("Runner " .. tostring(ShortName(self:GetLootSyncAuthorityName()) or "none") .. " | " .. tostring(healthLabel or health)
    .. (heartbeatAge and (" | heartbeat " .. tostring(heartbeatAge) .. "s ago") or "")
    .. " | live sessions " .. tostring(sessions) .. " | drops " .. tostring(drops) .. " | digest " .. tostring(digest))
  self:Print("Isolation counters: wrong run " .. tostring(state.diagnostics.rejectedWrongRun or 0)
    .. ", wrong group " .. tostring(state.diagnostics.rejectedWrongGroup or 0)
    .. ", wrong runner " .. tostring(state.diagnostics.rejectedWrongRunner or 0)
    .. ", archive applied " .. tostring(state.diagnostics.archiveApplied or 0) .. ".")
  self:Print("Queues: live " .. tostring(liveQueueLen) .. " | guild " .. tostring(guildQueueLen)
    .. " | local sessions with runID " .. tostring(withRunID)
    .. " | without " .. tostring(withoutRunID)
    .. " | finalized " .. tostring(finalizedCount))
  local diagnostics = APOCLootPrioDB.sync and APOCLootPrioDB.sync.diagnostics or {}
  self:Print("Delivery: send retries " .. tostring(state.diagnostics.sendRetries or 0)
    .. " | discarded sends " .. tostring(state.diagnostics.sendFailures or 0)
    .. " | applied updates " .. tostring(diagnostics.appliedLootUpdates or 0)
    .. " | corrupt transfers " .. tostring(diagnostics.corruptTransfers or 0)
    .. " | expired transfers " .. tostring(diagnostics.expiredTransfers or 0))
  if self.GetNativeCommsStatus then
    local nativeQueue = self:GetNativeCommsStatus()
    self:Print("Native transport: queued " .. tostring(nativeQueue or 0)
      .. " | sent " .. tostring(diagnostics.nativeMessagesSent or 0)
      .. " | retries " .. tostring(diagnostics.nativeMessageRetries or 0)
      .. " | dropped " .. tostring(diagnostics.nativeMessagesDropped or 0) .. ".")
  end
end

SLASH_APOCMULTIRUNSTATUS1 = "/priobeta-run"
SlashCmdList.APOCMULTIRUNSTATUS = function(msg)
  local raw = string.match(tostring(msg or ""), "^%s*(.-)%s*$") or ""
  local command, rest = string.match(raw, "^(%S+)%s*(.-)$")
  command = string.lower(command or "")
  rest = rest or ""
  if command == "new" or command == "newrun" then
    if IsLocalGroupLeader() or (APOCLootPrio.CanEditLootTracker and APOCLootPrio:CanEditLootTracker()) then APOCLootPrio:CreateMultiRun("manual")
    else APOCLootPrio:Print("Only the group leader or a Loot Tracker editor can start a new Run ID.") end
  elseif command == "sync" then
    APOCLootPrio:RequestMultiRunSync()
    APOCLootPrio:RequestGuildArchiveSync()
    local peerCount, published, peers = APOCLootPrio:SendGuildArchiveToSyncedPeers()
    local function requestLootAfterHandshake()
      if not APOCLootPrio then return end
      if not GetGroupChannel() then return end
      APOCLootPrio:RequestLootSessionSync()
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(2, requestLootAfterHandshake)
    else
      requestLootAfterHandshake()
    end
    local peerList = (peers and #peers > 0) and table.concat(peers, ", ") or "none"
    if not GetGroupChannel() then
      APOCLootPrio:RequestOfficerHistorySync("manual-sync")
    end
    APOCLootPrio:Print("Sync requested; whispering archives/history to " .. peerList .. " (" .. tostring(peerCount or 0) .. " peer(s), " .. tostring(published or 0) .. " session(s)); loot will follow after run handshake.")
  elseif command == "publish" then
    local target = string.match(rest, "^(%S+)")
    if target and target ~= "" then
      local peerName = ShortName(target)
      local published = APOCLootPrio:SendAllGuildArchive(peerName) or 0
      APOCLootPrio:Print("Archive publish: whispering ONLY to " .. tostring(peerName) .. "; " .. tostring(published) .. " session(s).")
    else
      local peerCount, published, peers = APOCLootPrio:SendGuildArchiveToSyncedPeers()
      local peerList = (peers and #peers > 0) and table.concat(peers, ", ") or "none (guild broadcast)"
      APOCLootPrio:Print("Archive publish: " .. peerList .. " (" .. tostring(peerCount or 0) .. " peer(s), " .. tostring(published or 0) .. " session(s)).")
    end
  else
    APOCLootPrio:PrintMultiRunStatus()
  end
end

if CreateFrame then
  local maintenance = CreateFrame("Frame")
  local function RegisterSafely(event)
    if pcall then pcall(function() maintenance:RegisterEvent(event) end) else maintenance:RegisterEvent(event) end
  end
  RegisterSafely("PLAYER_ENTERING_WORLD")
  RegisterSafely("GROUP_ROSTER_UPDATE")
  RegisterSafely("GROUP_JOINED")
  RegisterSafely("GROUP_LEFT")
  maintenance.elapsed = 0
  maintenance.lastRunBeacon = 0
  maintenance.lastAuthorityHeartbeat = 0
  maintenance:SetScript("OnUpdate", function(frame, elapsed)
    frame.elapsed = frame.elapsed + (elapsed or 0)
    if frame.elapsed < 5 then return end
    frame.elapsed = 0
    local now = Now()
    if APOCLootPrio.FlushPendingHistoryAcks then APOCLootPrio:FlushPendingHistoryAcks() end
    if GetGroupChannel() and now - (frame.lastAuthorityHeartbeat or 0) >= RUN_HEARTBEAT then
      frame.lastAuthorityHeartbeat = now
      if APOCLootPrio:IsLocalLootSyncV2Authority() then
        -- Verify quiet clients too: a silently lost award should not remain
        -- stale until somebody presses Share List or another drop is added.
        local idle = #(APOCLootPrio.multiRunLiveQueue or {}) == 0
        APOCLootPrio:SendMultiRunRunnerHeartbeat()
        if idle then APOCLootPrio:QueueLootManifestV3() end
      end
      if APOCLootPrio.EnsureRunnerFollowsMasterLooter then
        APOCLootPrio:EnsureRunnerFollowsMasterLooter("heartbeat")
      end
    end
    if GetGroupChannel() and now - (frame.lastRunBeacon or 0) >= RUN_BEACON then
      frame.lastRunBeacon = now
      if IsLocalGroupLeader() or APOCLootPrio:IsLocalLootSyncV2Authority() then APOCLootPrio:BroadcastMultiRunBeacon() end
    end
    if GetGroupChannel() then
      local run = APOCLootPrio:GetActiveRun()
      if run then
        local health = APOCLootPrio:GetMultiRunRunnerHealth()
        if run.lastDisplayedRunnerHealth ~= health then
          run.lastDisplayedRunnerHealth = health
          if APOCLootPrio.RefreshRaidLootPanel then APOCLootPrio:RefreshRaidLootPanel() end
          if APOCLootPrio.RefreshLootTrackerSettingsPanel then APOCLootPrio:RefreshLootTrackerSettingsPanel() end
        end
        if health == "offline" or health == "missing" then
          if run.lastWarnedRunnerHealth ~= health then
            run.lastWarnedRunnerHealth = health
            APOCLootPrio:MultiRunDiagnostic("runnerHeartbeatTimeouts")
            local warning = "No active Master Looter detected - the WoW Master Looter must have the beta addon and bridge. Manual Add remains available."
            if APOCLootPrio.UpdateRaidLootStatus then APOCLootPrio:UpdateRaidLootStatus(warning) end
            if APOCLootPrio.Print then APOCLootPrio:Print(warning) end
          end
        else
          run.lastWarnedRunnerHealth = nil
        end
        if run.recoveryExpiresAt and now > run.recoveryExpiresAt then
          run.recoveryToken = nil
          run.recoverySource = nil
          run.recoveryDesiredOwner = nil
          run.recoverySetBy = nil
          run.recoverySourceVerified = nil
          run.recoveryExpiresAt = nil
        end
      end
    end
    for key, transfer in pairs(APOCLootPrio.incomingMultiRunArchive or {}) do
      local progressAt = transfer.lastProgressAt or transfer.startedAt
      if now > 0 and progressAt and now - progressAt > TRANSFER_TIMEOUT then
        local fromName = string.match(tostring(key or ""), "^([^:]+)") or "unknown"
        local got = tonumber(transfer.received) or 0
        local total = tonumber(transfer.total) or 0
        APOCLootPrio.incomingMultiRunArchive[key] = nil
        APOCLootPrio:MultiRunDiagnostic("expiredTransfers")
        APOCLootPrio:Print("Guild archive transfer from " .. tostring(fromName) .. " timed out (got " .. tostring(got) .. "/" .. tostring(total) .. " chunks).")
      end
    end
  end)
  maintenance:SetScript("OnEvent", function(frame, event)
    if event == "GROUP_LEFT" then
      -- End watch overlay first so we never mark a remote "watching" run as
      -- local review/participated (activeRunID may point at a watched Live Raid).
      if APOCLootPrio.IsLiveRaidWatchOnly and APOCLootPrio:IsLiveRaidWatchOnly() then
        if APOCLootPrio.ClearLiveRaidWatchMode then
          APOCLootPrio:ClearLiveRaidWatchMode({skipRestore = false})
        end
      end
      local state = APOCLootPrio:InitMultiRun()
      local run = APOCLootPrio:GetActiveRun()
      if run and tostring(run.status or "") ~= "watching" then
        run.status = "review"
        run.participated = true
        run.endedAt = Now()
        state.reviewRunID = run.id
        state.activeRunID = run.id
      elseif run and tostring(run.status or "") == "watching" then
        -- Safety: never promote a watch shadow run to review.
        state.activeRunID = state.reviewRunID
      end
      if APOCLootPrio.RefreshRaidLootPanel then APOCLootPrio:RefreshRaidLootPanel() end
      return
    end
    if event == "GROUP_JOINED" then
      -- Joining a real raid must drop watch overlay without restoring the
      -- previous watched/review run over the cleared activeRunID.
      if APOCLootPrio.ClearLiveRaidWatchMode then
        APOCLootPrio:ClearLiveRaidWatchMode({skipRestore = true})
      end
      local state = APOCLootPrio:InitMultiRun()
      state.activeRunID = nil
      APOCLootPrioDB.loot.activeSessionKey = nil
    end
    local delay = event == "PLAYER_ENTERING_WORLD" and 4 or 1
    if C_Timer and C_Timer.After then
      C_Timer.After(delay, function()
        if not APOCLootPrio then return end
        if GetGroupChannel() then
          APOCLootPrio:RequestMultiRunSync()
          if IsLocalGroupLeader() then
            C_Timer.After(3, function()
              if APOCLootPrio and not APOCLootPrio:GetActiveRun() then APOCLootPrio:CreateMultiRun("group-leader") end
            end)
          end
          if APOCLootPrio.ScheduleEnsureRunnerFollowsMasterLooter then
            APOCLootPrio:ScheduleEnsureRunnerFollowsMasterLooter(1, event == "GROUP_ROSTER_UPDATE" and "roster" or "group")
          end
        end
        if event == "PLAYER_ENTERING_WORLD" then APOCLootPrio:RequestGuildArchiveSync() end
      end)
    end
  end)
end
