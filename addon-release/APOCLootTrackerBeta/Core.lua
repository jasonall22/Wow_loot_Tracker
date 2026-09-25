local ADDON = ...
APOCLootPrio = APOCLootPrio or {}

local DEFAULT_LEADER_RANK_INDEX = 1
local DEFAULT_SETTINGS_RANK_INDEX = 1
local FALLBACK_ADDON_VERSION = APOCLootPrio.BUILD_VERSION
local DEFAULT_LOOT_AUTO_TRACK_MODE = "raid"
local DEFAULT_LOOT_ROLL_DURATION = 15
local DEFAULT_LOOT_QUALITY_FILTERS = {[2] = true, [3] = true, [4] = true, [5] = true}
-- TBC phase-3 epic gems (uncut) + Heart of Darkness for raid material counts.
local EPIC_GEM_ITEM_IDS = {
  [32227] = true, -- Crimson Spinel
  [32228] = true, -- Empyrean Sapphire
  [32229] = true, -- Lionseye
  [32230] = true, -- Shadowsong Amethyst
  [32231] = true, -- Pyrestone
  [32249] = true, -- Seaspray Emerald
}
local HEART_ITEM_IDS = {
  [32428] = true, -- Heart of Darkness
}
local EPIC_GEM_NAME_HINTS = {
  "crimson spinel", "empyrean sapphire", "lionseye", "shadowsong amethyst",
  "pyrestone", "seaspray emerald",
}
local AUTO_LOOT_DUPLICATE_WINDOW_SECONDS = 2
local INSTANCE_SESSION_PROMPT_COOLDOWN_SECONDS = 6 * 60 * 60
local DEFAULT_FEATURE_ACCESS = {
  admin = 1,
  log = 1,
  lootTracker = 1,
  lootTrackerView = 1,
  lootSessionDelete = 1,
  guildLoot = 1,
}

local function ShortName(name)
  return string.match(name or "", "^([^%-]+)") or name
end

local function NormalizePlayerName(name)
  local shortName = ShortName(name)
  if not shortName then return "" end
  return string.lower(shortName)
end

local function DeepCopyTable(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, nested in pairs(value) do
    copy[DeepCopyTable(key, seen)] = DeepCopyTable(nested, seen)
  end
  return copy
end

local function IsPlayerInRaidGroup()
  if IsInRaid and IsInRaid() then return true end
  if GetNumGroupMembers and GetNumGroupMembers() > 5 then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  return false
end

local function IsPlayerInPartyGroup()
  if IsPlayerInRaidGroup() then return false end
  if IsInGroup and IsInGroup() then return true end
  if UnitExists and UnitExists("party1") then return true end
  local partySize = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
  if partySize == 0 and GetNumPartyMembers then partySize = GetNumPartyMembers() end
  if partySize > 0 then return true end
  local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  return groupSize > 1
end

local function GetLootAutoTrackContext()
  if IsPlayerInRaidGroup() then return "raid" end
  if IsPlayerInPartyGroup() then return "party" end
  return "solo"
end

local function NormalizeLootAutoTrackMode(mode)
  mode = string.lower(tostring(mode or DEFAULT_LOOT_AUTO_TRACK_MODE))
  if mode == "solo" or mode == "party" or mode == "raid" or mode == "off" then
    return mode
  end
  return DEFAULT_LOOT_AUTO_TRACK_MODE
end

local function IsPlayerGroupLeaderOrAssistant()
  if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
  if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
  if IsRaidLeader and IsRaidLeader() then return true end
  if IsRaidOfficer and IsRaidOfficer() then return true end
  if IsPartyLeader and IsPartyLeader() then return true end
  return false
end

local function IsPlayerGroupLeader()
  if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
  if IsRaidLeader and IsRaidLeader() then return true end
  if IsPartyLeader and IsPartyLeader() then return true end
  return false
end

function APOCLootPrio:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAPOC Loot Tracker|r: " .. tostring(msg))
end

function APOCLootPrio:InitDB()
  -- Belt-and-suspenders guard for WoW's SavedVariables load order. The beta
  -- compatibility name must always point at the isolated persisted table.
  if APOCLootPrioBetaMode and APOCLootTrackerBetaDB then
    APOCLootPrioDB = APOCLootTrackerBetaDB
  end
  APOCLootPrioDB = APOCLootPrioDB or {}
  APOCLootPrioDB.minimap = APOCLootPrioDB.minimap or {}
  if APOCLootPrioDB.minimap.restoredBuild ~= "0.1.59" then
    APOCLootPrioDB.minimap.hide = false
    APOCLootPrioDB.minimap.restoredBuild = "0.1.59"
    APOCLootPrioDB.minimap.shownBuild = nil
  end
  APOCLootPrioDB.overrides = APOCLootPrioDB.overrides or {}
  APOCLootPrioDB.audit = APOCLootPrioDB.audit or {}
  APOCLootPrioDB.auditCounter = APOCLootPrioDB.auditCounter or 0
  APOCLootPrioDB.sync = APOCLootPrioDB.sync or {}
  APOCLootPrioDB.sync.revision = APOCLootPrioDB.sync.revision or 0
  APOCLootPrioDB.sync.logicalClock = math.max(tonumber(APOCLootPrioDB.sync.logicalClock) or 0, tonumber(APOCLootPrioDB.sync.revision) or 0)
  APOCLootPrioDB.sync.protocol = 3
  APOCLootPrioDB.sync.diagnostics = APOCLootPrioDB.sync.diagnostics or {}
  APOCLootPrioDB.sync.maxRankIndex = APOCLootPrioDB.sync.maxRankIndex or DEFAULT_LEADER_RANK_INDEX
  APOCLootPrioDB.sync.peers = APOCLootPrioDB.sync.peers or {}
  if APOCLootPrioDB.sync.channel == nil or APOCLootPrioDB.sync.channel == "OFFICER" then
    APOCLootPrioDB.sync.channel = "GUILD"
  end
  APOCLootPrioDB.access = APOCLootPrioDB.access or {}
  if APOCLootPrioDB.access.lootTrackerView == nil and APOCLootPrioDB.access.lootTracker ~= nil then
    APOCLootPrioDB.access.lootTrackerView = APOCLootPrioDB.access.lootTracker
    APOCLootPrioDB.access.lootTracker = DEFAULT_FEATURE_ACCESS.lootTracker
  end
  for feature, rankIndex in pairs(DEFAULT_FEATURE_ACCESS) do
    if APOCLootPrioDB.access[feature] == nil then
      APOCLootPrioDB.access[feature] = rankIndex
    end
  end
  APOCLootPrioDB.ui = APOCLootPrioDB.ui or {}
  APOCLootPrioDB.ui.main = APOCLootPrioDB.ui.main or {}
  APOCLootPrioDB.ui.lootTracker = APOCLootPrioDB.ui.lootTracker or {}
  APOCLootPrioDB.loot = APOCLootPrioDB.loot or {}
  APOCLootPrioDB.loot.sessions = APOCLootPrioDB.loot.sessions or {}
  APOCLootPrioDB.loot.quarantinedSessions = APOCLootPrioDB.loot.quarantinedSessions or {}
  APOCLootPrioDB.loot.deletedSessions = APOCLootPrioDB.loot.deletedSessions or {}
  APOCLootPrioDB.loot.finalizedSessionBackups = APOCLootPrioDB.loot.finalizedSessionBackups or {}
  for sessionKey, backup in pairs(APOCLootPrioDB.loot.finalizedSessionBackups) do
    local current = APOCLootPrioDB.loot.sessions[sessionKey]
    local backupRevision = tonumber(backup and backup.revision) or 0
    local currentRevision = tonumber(current and current.revision) or -1
    local deletedRevision = tonumber(APOCLootPrioDB.loot.deletedSessions[sessionKey]) or -1
    local restoreArchivedCopy = current and current.archived and backup and not backup.archived and currentRevision <= backupRevision
    if backup and backup.finalized and deletedRevision < backupRevision
      and (not current or currentRevision < backupRevision or restoreArchivedCopy) then
      APOCLootPrioDB.loot.sessions[sessionKey] = DeepCopyTable(backup)
    end
  end
  APOCLootPrioDB.loot.current = APOCLootPrioDB.loot.current or {}
  APOCLootPrioDB.loot.activeSessionKey = APOCLootPrioDB.loot.activeSessionKey or nil
  APOCLootPrioDB.loot.sessionCounter = APOCLootPrioDB.loot.sessionCounter or 0
  APOCLootPrioDB.loot.dropCounter = APOCLootPrioDB.loot.dropCounter or 0
  APOCLootPrioDB.loot.trackerOwner = APOCLootPrioDB.loot.trackerOwner or nil
  APOCLootPrioDB.loot.trackerOwnerSetAt = APOCLootPrioDB.loot.trackerOwnerSetAt or 0
  APOCLootPrioDB.loot.disenchanter = APOCLootPrioDB.loot.disenchanter or nil
  APOCLootPrioDB.loot.disenchanterSetAt = APOCLootPrioDB.loot.disenchanterSetAt or 0
  APOCLootPrioDB.loot.instancePromptHistory = APOCLootPrioDB.loot.instancePromptHistory or {}
  APOCLootPrioDB.loot.autoTrackMode = NormalizeLootAutoTrackMode(APOCLootPrioDB.loot.autoTrackMode)
  APOCLootPrioDB.loot.qualityFilters = APOCLootPrioDB.loot.qualityFilters or {}
  for quality, enabled in pairs(DEFAULT_LOOT_QUALITY_FILTERS) do
    if APOCLootPrioDB.loot.qualityFilters[quality] == nil then
      APOCLootPrioDB.loot.qualityFilters[quality] = enabled
    end
  end
  -- Undo the green-skip experiment: restore green auto-track.
  if (tonumber(APOCLootPrioDB.loot.qualityGreenSkipMigration) or 0) == 1 then
    APOCLootPrioDB.loot.qualityFilters[2] = true
    APOCLootPrioDB.loot.qualityGreenSkipMigration = 2
  end
end

function APOCLootPrio:GetPlayerDisplayName()
  local name = UnitName and UnitName("player") or "Unknown"
  local realm = GetRealmName and GetRealmName() or nil
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

function APOCLootPrio:SetDetectedMasterLooter(name, source)
  name = name and string.match(name, "^%s*(.-)%s*$") or nil
  if not name or name == "" then return false end

  local newName = ShortName(name)
  local changed = NormalizePlayerName(self.detectedMasterLooter) ~= NormalizePlayerName(newName)
  self.detectedMasterLooter = newName
  self.detectedMasterLooterSource = source or "detected"
  self.detectedMasterLooterAt = time and time() or 0

  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshOfficerControls then self:RefreshOfficerControls() end
  if changed and self.ScheduleEnsureRunnerFollowsMasterLooter then
    self:ScheduleEnsureRunnerFollowsMasterLooter(0.25, "detected-ml")
  elseif changed and self.EnsureRunnerFollowsMasterLooter then
    self:EnsureRunnerFollowsMasterLooter("detected-ml")
  end
  return true
end

function APOCLootPrio:HandleSystemLootMessage(message)
  message = tostring(message or "")

  if self:HandleRaidLootRollMessage(message) then
    return true
  end

  local masterName = string.match(message, "^(.+) is now the loot master%.?$")
  if not masterName then
    masterName = string.match(message, "^(.+) is now Loot Master%.?$")
  end

  if masterName then
    self:SetDetectedMasterLooter(masterName, "system")
    return true
  end

  return false
end

-- Localized printf-format parser. Supports Blizzard's positional placeholders.
function APOCLootPrio:MatchLocalizedMessage(message, format)
  if not format or format == "" then return nil end
  local pattern, order, cursor, ordinal = "^", {}, 1, 0
  while cursor <= #format do
    local rest = string.sub(format, cursor)
    local token, position, kind = string.match(rest, "^(%%(%d+)%$([sd]))")
    if not token then token, kind = string.match(rest, "^(%%([sd]))") end
    if token then
      ordinal = ordinal + 1
      table.insert(order, tonumber(position) or ordinal)
      pattern = pattern .. (kind == "d" and "(%d+)" or "(.-)")
      cursor = cursor + #token
    else
      pattern = pattern .. string.gsub(string.sub(format, cursor, cursor), "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      cursor = cursor + 1
    end
  end
  local captures = {string.match(tostring(message or ""), pattern .. "$")}
  if #captures == 0 then return nil end
  local values = {}
  for index, value in ipairs(captures) do values[order[index]] = value end
  return unpack(values)
end

function APOCLootPrio:HandleRaidLootRollMessage(message)
  if not self.activeLootRollDropID then return false end

  local roller, roll, low, high = self:MatchLocalizedMessage(message, RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
  if not roller or not self:IsCurrentGroupMember(roller) then return false end

  roll = tonumber(roll)
  low = tonumber(low)
  high = tonumber(high)
  if not roll or low ~= 1 or (high ~= 100 and high ~= 99) or roll < low or roll > high then return false end
  local rollType = high == 99 and "GREED" or "NEED"

  local drop = self:FindRaidLootDrop(self.activeLootRollDropID)
  if not drop then return false end

  drop.roll = drop.roll or {}
  local now = time and time() or 0
  if drop.roll.endsAt and now >= tonumber(drop.roll.endsAt or 0) then
    drop.roll.closed = true
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
    return true
  end

  local rollerName = ShortName(roller)
  local rollerKey = NormalizePlayerName(rollerName)
  local seenKey = rollerKey .. ":" .. rollType
  drop.roll.seen = drop.roll.seen or {}
  drop.roll.entries = drop.roll.entries or {}
  if drop.roll.seen[seenKey] then
    return true
  end

  drop.roll.seen[seenKey] = true
  table.insert(drop.roll.entries, {
    name = rollerName,
    roll = roll,
    rollType = rollType,
    rolledAt = now,
  })

  local winningEntry = self:GetLootRollWinningEntry(drop)
  if winningEntry then
    drop.roll.highRoll = winningEntry.roll
    drop.roll.highName = winningEntry.name
    drop.roll.highType = winningEntry.rollType
    drop.roll.updatedAt = now
  end

  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.UpdateRaidLootStatus then
    local typeLabel = drop.roll.highType == "GREED" and "OS" or "MS"
    self:UpdateRaidLootStatus("High " .. typeLabel .. " roll: " .. tostring(drop.roll.highName or rollerName) .. " - " .. tostring(drop.roll.highRoll or roll))
  end
  return true
end

function APOCLootPrio:GetLootRollChatType()
  if IsPlayerInRaidGroup() then return "RAID" end
  if IsPlayerInPartyGroup() then return "PARTY" end
  return nil
end

function APOCLootPrio:SendLootRollMessage(message, chatType)
  chatType = chatType or self:GetLootRollChatType()
  if chatType and SendChatMessage then
    SendChatMessage(tostring(message or ""), chatType)
    return true
  end
  if self.Print then self:Print(message) end
  return false
end

function APOCLootPrio:GetLootRollOpeningChatType()
  if IsPlayerInRaidGroup() and IsPlayerGroupLeaderOrAssistant() then
    return "RAID_WARNING"
  end
  return self:GetLootRollChatType()
end

function APOCLootPrio:IsSameLootRollItem(left, right)
  if not left or not right then return false end

  local leftID = tonumber(left.itemID)
  local rightID = tonumber(right.itemID)
  if leftID and rightID then return leftID == rightID end

  local leftKey = left.itemKey and tostring(left.itemKey) or nil
  local rightKey = right.itemKey and tostring(right.itemKey) or nil
  if leftKey and rightKey and leftKey ~= "" and rightKey ~= "" then
    return leftKey == rightKey
  end

  return string.lower(tostring(left.item or "")) == string.lower(tostring(right.item or ""))
end

function APOCLootPrio:GetLootRollCopyDrops(drop, session)
  local copies = {}
  if not drop then return copies end

  if not session then
    local _, foundSession = self:FindRaidLootDrop(drop.id)
    session = foundSession
  end
  if not session then return copies end

  local roll = drop.roll
  if roll and roll.copyDropIDs and #roll.copyDropIDs > 0 then
    for _, copyID in ipairs(roll.copyDropIDs) do
      local copy = self:FindRaidLootDrop(copyID)
      if copy then table.insert(copies, copy) end
    end
    return copies
  end

  local dropTime = tonumber(drop.droppedAt) or 0
  local dropBoss = string.lower(tostring(drop.boss or ""))
  for _, candidate in ipairs(session.drops or {}) do
    local candidateTime = tonumber(candidate.droppedAt) or 0
    local sameDropEvent = dropTime == 0 or candidateTime == 0 or math.abs(candidateTime - dropTime) <= 60
    local sameBoss = string.lower(tostring(candidate.boss or "")) == dropBoss
    local unawarded = not (candidate.award and candidate.award.winner and candidate.award.winner ~= "")
    if unawarded and sameBoss and sameDropEvent and self:IsSameLootRollItem(drop, candidate) then
      table.insert(copies, candidate)
    end
  end

  table.sort(copies, function(a, b)
    if a.id == drop.id then return true end
    if b.id == drop.id then return false end
    local aTime = tonumber(a.droppedAt) or 0
    local bTime = tonumber(b.droppedAt) or 0
    if aTime == bTime then return tostring(a.id or "") < tostring(b.id or "") end
    return aTime < bTime
  end)
  return copies
end

function APOCLootPrio:GetLootRollCopyCount(drop)
  local roll = drop and drop.roll
  if roll and tonumber(roll.copyCount) and tonumber(roll.copyCount) > 0 then
    return tonumber(roll.copyCount)
  end
  local copies = self:GetLootRollCopyDrops(drop)
  return math.max(1, #copies)
end

local function ValidLootRollDuration(value)
  if type(value) ~= "number" and type(value) ~= "string" then return nil end
  local seconds = tonumber(value)
  if not seconds or seconds ~= seconds or seconds < 5 or seconds > 120 or seconds % 1 ~= 0 then return nil end
  return seconds
end

function APOCLootPrio:GetLootRollDuration()
  self:InitDB()
  return ValidLootRollDuration(APOCLootPrioDB.ui.lootTracker.rollDurationSeconds) or DEFAULT_LOOT_ROLL_DURATION
end

function APOCLootPrio:SetLootRollDuration(value)
  if not self:CanManageSettings() then
    return false, "Only players with Settings access can change the roll timer."
  end
  local seconds = ValidLootRollDuration(value)
  if not seconds then return false, "Enter a whole number from 5 to 120 seconds." end
  self:InitDB()
  -- Local preference only: no sync settings, session revisions, or active rolls change.
  APOCLootPrioDB.ui.lootTracker.rollDurationSeconds = seconds
  return true, seconds
end

function APOCLootPrio:StartRaidLootRoll(dropID, raid)
  if not self:CanEditLootTracker() then
    return false, "Only Loot Tracker editors can start a roll."
  end

  local drop, session = self:FindRaidLootDrop(dropID, raid)
  local _, targetSession = self:FindRaidLootDrop(dropID, raid)
  if not self:CanEditLootSession(targetSession) or targetSession.finalized or targetSession.archived then return nil, "No edit permission for this session." end
  if not drop then return false, "Select a loot drop first." end
  if drop.rollSourceDropID and drop.rollSourceDropID ~= drop.id then
    local sourceDrop = self:FindRaidLootDrop(drop.rollSourceDropID)
    if sourceDrop and sourceDrop.roll and sourceDrop.roll.startedAt then
      return false, "One roll already covers every identical copy from this drop."
    end
    drop.rollSourceDropID = nil
  end
  if drop.award and ((drop.award.winner and drop.award.winner ~= "") or self:GetAwardType(drop) == "GB") then
    return false, "That loot drop is already awarded."
  end
  if drop.roll and drop.roll.startedAt then
    local left = self:GetLootRollTimeLeft(drop)
    if left and left > 0 then
      return false, "A roll is already running for this item."
    end
    return false, "That roll is closed. Reset rolls before starting again."
  end

  local copyDrops = self:GetLootRollCopyDrops(drop, session)
  local copyDropIDs = {}
  for _, copy in ipairs(copyDrops) do table.insert(copyDropIDs, copy.id) end
  if #copyDropIDs == 0 then table.insert(copyDropIDs, drop.id) end

  local rollDuration = self:GetLootRollDuration()
  local now = time and time() or 0
  drop.roll = {
    startedAt = now,
    endsAt = now + rollDuration,
    startedBy = self:GetPlayerDisplayName(),
    highName = nil,
    highRoll = nil,
    highType = nil,
    entries = {},
    seen = {},
    awardedEntries = {},
    chatCountdownSent = {},
    closed = false,
    copyCount = #copyDropIDs,
    copyDropIDs = copyDropIDs,
  }
  for _, copy in ipairs(copyDrops) do copy.rollSourceDropID = drop.id end
  self.activeLootRollDropID = drop.id

  local item = {
    name = drop.item,
    id = drop.itemID,
    link = drop.itemLink,
    quality = drop.itemQuality,
    bias = drop.bias,
    note = drop.note,
  }
  local link = self:GetCachedItemLink(item) or drop.itemLink or drop.item or "loot"
  local chatType = self:GetLootRollOpeningChatType()
  local copyText = #copyDropIDs > 1 and (" " .. tostring(#copyDropIDs) .. " copies: top " .. tostring(#copyDropIDs) .. " eligible rolls win.") or ""
  self:SendLootRollMessage("Roll for " .. tostring(link) .. " now!" .. copyText, chatType)
  self:SendLootRollMessage("MS: /roll 1-100. OS: /roll 1-99. " .. tostring(rollDuration) .. " seconds. One MS and one OS roll per player.", chatType)
  drop.roll.chatCountdownSent[rollDuration] = true
  -- A short custom roll must never announce more time than it started with.
  for _, mark in ipairs({10, 5, 3, 2, 1}) do
    if mark >= rollDuration then drop.roll.chatCountdownSent[mark] = true end
  end
  if self.EnsureLootRollCountdownTicker then
    self:EnsureLootRollCountdownTicker()
  end
  if self.lootRollCountdownFrame and self.lootRollCountdownFrame.Show then
    self.lootRollCountdownFrame:Show()
  end

  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  return true, "Roll started for " .. tostring(drop.item or "loot") .. "."
end

function APOCLootPrio:ResetRaidLootRoll(dropID, raid)
  if not self:CanEditLootTracker() then
    return false, "Only Loot Tracker editors can reset rolls."
  end

  local drop, session = self:FindRaidLootDrop(dropID, raid)
  local _, targetSession = self:FindRaidLootDrop(dropID, raid)
  if not self:CanEditLootSession(targetSession) or targetSession.finalized or targetSession.archived then return nil, "No edit permission for this session." end
  if not drop then return false, "Select a loot drop first." end

  local copyDrops = self:GetLootRollCopyDrops(drop, session)
  drop.roll = nil
  for _, copy in ipairs(copyDrops) do
    if copy.rollSourceDropID == drop.id then copy.rollSourceDropID = nil end
  end
  if self.activeLootRollDropID == drop.id then
    self.activeLootRollDropID = nil
  end
  if self.lootRollCountdownFrame and self.lootRollCountdownFrame.Hide then
    self.lootRollCountdownFrame:Hide()
  end
  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  return true, "Rolls reset for " .. tostring(drop.item or "loot") .. "."
end

function APOCLootPrio:ResetRaidLootRollTimer(dropID, raid)
  if not self:CanEditLootTracker() then
    return false, "Only Loot Tracker editors can reset the roll timer."
  end

  local drop, session = self:FindRaidLootDrop(dropID, raid)
  local _, targetSession = self:FindRaidLootDrop(dropID, raid)
  if not self:CanEditLootSession(targetSession) or targetSession.finalized or targetSession.archived then return nil, "No edit permission for this session." end
  if not drop then return false, "Select a loot drop first." end
  if not drop.roll or not drop.roll.startedAt then
    return false, "Start a roll before resetting the timer."
  end

  local now = time and time() or 0
  drop.roll.endsAt = now + 10
  drop.roll.closed = false
  drop.roll.updatedAt = now
  drop.roll.chatCountdownSent = { [10] = true }
  self.activeLootRollDropID = drop.id

  if self:IsLootRollChatAnnouncer(drop) then
    self:SendLootRollMessage("Extra 10 seconds for " .. tostring(self:GetLootRollChatLink(drop)) .. ". First MS and first OS roll still count.", self:GetLootRollChatType())
  end
  if self.EnsureLootRollCountdownTicker then
    self:EnsureLootRollCountdownTicker()
  end
  if self.lootRollCountdownFrame and self.lootRollCountdownFrame.Show then
    self.lootRollCountdownFrame:Show()
  end
  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  return true, "Roll timer reset to 10 seconds for " .. tostring(drop.item or "loot") .. "."
end

function APOCLootPrio:GetLootRollTimeLeft(drop)
  local roll = drop and drop.roll
  if not roll or not roll.endsAt then return nil end
  local now = time and time() or 0
  local left = math.max(0, math.ceil((tonumber(roll.endsAt) or 0) - now))
  if left <= 0 then roll.closed = true end
  return left
end

function APOCLootPrio:IsLootRollChatAnnouncer(drop)
  local roll = drop and drop.roll
  if not roll or not roll.startedBy then return false end
  local me = self.GetPlayerDisplayName and self:GetPlayerDisplayName() or nil
  if (not me or me == "") and UnitName then me = UnitName("player") end
  return NormalizePlayerName(me) == NormalizePlayerName(roll.startedBy)
end

function APOCLootPrio:GetLootRollChatLink(drop)
  if not drop then return "loot" end
  local item = {
    name = drop.item,
    id = drop.itemID,
    link = drop.itemLink,
    quality = drop.itemQuality,
    bias = drop.bias,
    note = drop.note,
  }
  return self:GetCachedItemLink(item) or drop.itemLink or drop.item or "loot"
end

function APOCLootPrio:MaybeAnnounceLootRollCountdown(drop)
  local roll = drop and drop.roll
  if not roll or not roll.startedAt or not roll.endsAt then return end
  if not self:IsLootRollChatAnnouncer(drop) then return end

  roll.chatCountdownSent = roll.chatCountdownSent or {}
  local left = self:GetLootRollTimeLeft(drop)
  if not left then return end

  local mark = nil
  if left <= 0 then
    mark = 0
  elseif left <= 1 then
    mark = 1
  elseif left <= 2 then
    mark = 2
  elseif left <= 3 then
    mark = 3
  elseif left <= 5 then
    mark = 5
  elseif left <= 10 then
    mark = 10
  end
  if mark == nil or roll.chatCountdownSent[mark] then return end

  roll.chatCountdownSent[mark] = true
  local link = self:GetLootRollChatLink(drop)
  local chatType = self:GetLootRollChatType()
  if mark == 0 then
    local winningEntries = self:GetLootRollWinningEntries(drop)
    local winningEntry = winningEntries[1]
    if winningEntry then
      roll.highName = winningEntry.name
      roll.highRoll = winningEntry.roll
      roll.highType = winningEntry.rollType
      if self:GetLootRollCopyCount(drop) > 1 then
        local winnerParts = {}
        for _, entry in ipairs(winningEntries) do
          local typeLabel = entry.rollType == "GREED" and "OS" or "MS"
          table.insert(winnerParts, tostring(ShortName(entry.name)) .. " " .. tostring(entry.roll) .. " " .. typeLabel)
        end
        local winnerChatType = self:GetLootRollOpeningChatType()
        self:SendLootRollMessage("Roll closed for " .. tostring(link) .. ".", winnerChatType)
        self:SendLootRollMessage("Winners: " .. table.concat(winnerParts, ", ") .. ".", winnerChatType)
      else
        local typeLabel = winningEntry.rollType == "GREED" and "OS" or "MS"
        self:SendLootRollMessage("Roll closed for " .. tostring(link) .. ". Winner: " .. tostring(ShortName(winningEntry.name)) .. " - " .. tostring(winningEntry.roll) .. " (" .. typeLabel .. ").", self:GetLootRollOpeningChatType())
      end
    else
      local disenchanter = self.GetLootDisenchanter and self:GetLootDisenchanter() or nil
      local deText = disenchanter and disenchanter ~= "" and self:IsLootDisenchanterInGroup(disenchanter)
        and (" Assigned DE: " .. tostring(ShortName(disenchanter)) .. ".") or ""
      self:SendLootRollMessage("Roll closed for " .. tostring(link) .. ". No valid rolls." .. deText, chatType)
    end
  else
    self:SendLootRollMessage("Roll for " .. tostring(link) .. ": " .. tostring(mark) .. " seconds left.", chatType)
  end
end

function APOCLootPrio:EnsureLootRollCountdownTicker()
  if self.lootRollCountdownFrame or not CreateFrame then return end
  local frame = CreateFrame("Frame")
  frame:Hide()
  frame:SetScript("OnUpdate", function(ticker, elapsed)
    ticker.elapsed = (ticker.elapsed or 0) + (elapsed or 0)
    if ticker.elapsed < .25 then return end
    ticker.elapsed = 0

    if not APOCLootPrio or not APOCLootPrio.activeLootRollDropID then
      ticker:Hide()
      return
    end

    local drop = APOCLootPrio:FindRaidLootDrop(APOCLootPrio.activeLootRollDropID)
    if not drop or not drop.roll then
      ticker:Hide()
      return
    end

    APOCLootPrio:MaybeAnnounceLootRollCountdown(drop)
    if drop.roll.closed and drop.roll.chatCountdownSent and drop.roll.chatCountdownSent[0] then
      ticker:Hide()
    end
  end)
  self.lootRollCountdownFrame = frame
end

function APOCLootPrio:GetLootRollTopEntries(drop, maxEntries, rollType)
  local roll = drop and drop.roll
  local entries = {}
  for _, entry in ipairs((roll and roll.entries) or {}) do
    local entryType = entry.rollType or "NEED"
    if not rollType or entryType == rollType then
      table.insert(entries, {
        name = entry.name,
        roll = tonumber(entry.roll) or 0,
        rollType = entryType,
        rolledAt = tonumber(entry.rolledAt) or 0,
      })
    end
  end

  table.sort(entries, function(a, b)
    if not rollType and a.rollType ~= b.rollType then
      return a.rollType == "NEED"
    end
    if a.roll == b.roll then return a.rolledAt < b.rolledAt end
    return a.roll > b.roll
  end)

  if maxEntries and #entries > maxEntries then
    while #entries > maxEntries do table.remove(entries) end
  end

  return entries
end

function APOCLootPrio:GetLootRollWinningEntry(drop)
  local needEntries = self:GetLootRollTopEntries(drop, 1, "NEED")
  if #needEntries > 0 then return needEntries[1] end

  local greedEntries = self:GetLootRollTopEntries(drop, 1, "GREED")
  if #greedEntries > 0 then return greedEntries[1] end

  return nil
end

function APOCLootPrio:GetLootRollWinningEntries(drop)
  local winners, seen = {}, {}
  local count = self:GetLootRollCopyCount(drop)
  for _, rollType in ipairs({"NEED", "GREED"}) do
    for _, entry in ipairs(self:GetLootRollTopEntries(drop, nil, rollType)) do
      if #winners >= count then break end
      local key = NormalizePlayerName(entry.name)
      if key ~= "" and not seen[key] then
        seen[key] = true
        table.insert(winners, entry)
      end
    end
  end
  return winners
end

function APOCLootPrio:GetLootRollWinnerSlot(drop, playerName, rollType)
  local playerKey = NormalizePlayerName(playerName)
  for index, entry in ipairs(self:GetLootRollWinningEntries(drop)) do
    if NormalizePlayerName(entry.name) == playerKey and (not rollType or entry.rollType == rollType) then return index, entry end
  end
  return nil, nil
end

function APOCLootPrio:GetLootRollAwardKey(playerName, rollType)
  return NormalizePlayerName(playerName) .. ":" .. tostring(rollType or "NEED")
end

function APOCLootPrio:GetLootRollAwardedCopy(drop, playerName, rollType)
  local roll = drop and drop.roll
  if roll and roll.awardedEntries and rollType then
    local awardedDropID = roll.awardedEntries[self:GetLootRollAwardKey(playerName, rollType)]
    if awardedDropID then
      local awardedDrop = self:FindRaidLootDrop(awardedDropID)
      if awardedDrop and awardedDrop.award and awardedDrop.award.winner and awardedDrop.award.winner ~= "" then
        return awardedDrop
      end
      roll.awardedEntries[self:GetLootRollAwardKey(playerName, rollType)] = nil
    end
    return nil
  end

  local playerKey = NormalizePlayerName(playerName)
  for _, copy in ipairs(self:GetLootRollCopyDrops(drop)) do
    if copy.award and NormalizePlayerName(copy.award.winner) == playerKey then
      return copy
    end
  end
  return nil
end

function APOCLootPrio:GetNextLootRollAwardDrop(drop)
  for _, copy in ipairs(self:GetLootRollCopyDrops(drop)) do
    if not (copy.award and copy.award.winner and copy.award.winner ~= "") then
      return copy
    end
  end
  return nil
end

function APOCLootPrio:GetUnitDisplayName(unit)
  if not UnitName then return nil end
  local name, realm = UnitName(unit)
  if not name or name == "" then return nil end
  if realm and realm ~= "" then return name .. "-" .. realm end
  return name
end

function APOCLootPrio:GetGroupRoster()
  local members = {}
  local seen = {}

  local function addName(name)
    name = name and string.match(name, "^%s*(.-)%s*$") or nil
    if not name or name == "" then return end
    local key = string.lower(ShortName(name) or name)
    if seen[key] then return end
    seen[key] = true
    table.insert(members, name)
  end

  local playerName = self:GetPlayerDisplayName()

  local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  if IsPlayerInRaidGroup() then
    if groupSize == 0 and GetNumRaidMembers then groupSize = GetNumRaidMembers() end
    for index = 1, groupSize do
      addName(self:GetUnitDisplayName("raid" .. tostring(index)))
    end
    addName(playerName)
  else
    addName(playerName)
    local partySize = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if partySize == 0 and GetNumPartyMembers then partySize = GetNumPartyMembers() end
    for index = 1, partySize do
      addName(self:GetUnitDisplayName("party" .. tostring(index)))
    end
  end

  return members
end

function APOCLootPrio:GetGroupedRaidRoster()
  local groups = {{}, {}, {}, {}, {}}
  local seen = {}
  local total = 0

  local function addName(groupIndex, name)
    name = name and string.match(name, "^%s*(.-)%s*$") or nil
    if not name or name == "" then return end

    local key = string.lower(ShortName(name) or name)
    if seen[key] then return end
    seen[key] = true

    groupIndex = tonumber(groupIndex) or 1
    if groupIndex < 1 then groupIndex = 1 end
    if groupIndex > 5 then groupIndex = 5 end

    table.insert(groups[groupIndex], name)
    total = total + 1
  end

  local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  if IsPlayerInRaidGroup() then
    if groupSize == 0 and GetNumRaidMembers then groupSize = GetNumRaidMembers() end
    for index = 1, groupSize do
      local rosterName, _, subgroup = nil, nil, nil
      if GetRaidRosterInfo then
        rosterName, _, subgroup = GetRaidRosterInfo(index)
      end
      addName(subgroup or math.floor((index - 1) / 5) + 1, self:GetUnitDisplayName("raid" .. tostring(index)) or rosterName)
    end
    addName(1, self:GetPlayerDisplayName())
  else
    addName(1, self:GetPlayerDisplayName())
    local partySize = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if partySize == 0 and GetNumPartyMembers then partySize = GetNumPartyMembers() end
    for index = 1, partySize do
      addName(1, self:GetUnitDisplayName("party" .. tostring(index)))
    end
  end

  return groups, total
end

function APOCLootPrio:GetLootSessionGroupedRoster(session)
  local groups, total = self:GetGroupedRaidRoster()
  local seen = {}

  for _, group in ipairs(groups) do
    for _, name in ipairs(group) do
      seen[NormalizePlayerName(name)] = true
    end
  end

  local historical = {}
  for _, member in pairs((session and session.attendance and session.attendance.members) or {}) do
    local name = member.name
    local key = NormalizePlayerName(name)
    if key ~= "" and not seen[key] then
      table.insert(historical, {name = name, subgroup = tonumber(member.subgroup)})
      seen[key] = true
    end
  end

  table.sort(historical, function(left, right)
    local leftGroup, rightGroup = tonumber(left.subgroup) or 99, tonumber(right.subgroup) or 99
    if leftGroup ~= rightGroup then return leftGroup < rightGroup end
    return string.lower(ShortName(left.name) or left.name) < string.lower(ShortName(right.name) or right.name)
  end)

  for _, member in ipairs(historical) do
    local groupIndex = member.subgroup
    if not groupIndex or groupIndex < 1 or groupIndex > 5 then
      groupIndex = 1
      for index = 2, 5 do
        if #groups[index] < #groups[groupIndex] then groupIndex = index end
      end
    end
    table.insert(groups[groupIndex], member.name)
    total = total + 1
  end

  return groups, total
end

function APOCLootPrio:GetGroupMemberRole(memberName)
  local targetKey = NormalizePlayerName(memberName)
  if targetKey == "" then return nil end

  local function roleForUnit(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return nil end
    local unitName = self:GetUnitDisplayName(unit)
    if NormalizePlayerName(unitName) ~= targetKey then return nil end

    if UnitGroupRolesAssigned then
      local assignedRole = UnitGroupRolesAssigned(unit)
      if assignedRole == "TANK" or assignedRole == "HEALER" or assignedRole == "DAMAGER" then
        return assignedRole
      end
    end
    return nil
  end

  local playerRole = roleForUnit("player")
  if playerRole then return playerRole end

  if IsPlayerInRaidGroup() then
    local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
    if groupSize == 0 and GetNumRaidMembers then groupSize = GetNumRaidMembers() end
    for index = 1, groupSize do
      local role = roleForUnit("raid" .. tostring(index))
      if role then return role end
    end
  else
    local partySize = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if partySize == 0 and GetNumPartyMembers then partySize = GetNumPartyMembers() end
    for index = 1, partySize do
      local role = roleForUnit("party" .. tostring(index))
      if role then return role end
    end
  end

  return nil
end

function APOCLootPrio:GetItemID(item)
  if not item then return nil end
  return item.id or item.itemId
end

function APOCLootPrio:GetItemKey(item)
  if not item then return nil end
  local id = self:GetItemID(item)
  if id then return "i:" .. tostring(id) end
  if item.name then return "n:" .. string.lower(item.name) end
  return nil
end

function APOCLootPrio:GetOverride(itemOrKey)
  if not APOCLootPrioDB or not APOCLootPrioDB.overrides then return nil end
  local key = type(itemOrKey) == "table" and self:GetItemKey(itemOrKey) or itemOrKey
  return key and APOCLootPrioDB.overrides[key] or nil
end

function APOCLootPrio:GetItemBias(item)
  local override = self:GetOverride(item)
  if override and override.bias ~= nil then return override.bias end
  return item and item.bias or nil
end

function APOCLootPrio:GetItemNote(item)
  local override = self:GetOverride(item)
  if override and override.note ~= nil then
    if override.note == "" then return nil end
    return override.note
  end
  return item and item.note or nil
end

function APOCLootPrio:GetRevision()
  if not APOCLootPrioDB or not APOCLootPrioDB.sync then return 0 end
  return APOCLootPrioDB.sync.revision or 0
end

function APOCLootPrio:SetRevision(revision)
  self:InitDB()
  APOCLootPrioDB.sync.revision = math.max(APOCLootPrioDB.sync.revision or 0, tonumber(revision) or 0)
end

function APOCLootPrio:NextAuditID()
  self:InitDB()
  APOCLootPrioDB.auditCounter = (APOCLootPrioDB.auditCounter or 0) + 1
  return tostring(time and time() or 0) .. ":" .. self:GetPlayerDisplayName() .. ":" .. tostring(APOCLootPrioDB.auditCounter)
end

function APOCLootPrio:AddAuditEntry(entry)
  self:InitDB()

  if type(entry) == "string" then
    entry = {text = entry}
  end

  if type(entry) ~= "table" then return nil end
  entry.time = tonumber(entry.time) or (time and time() or 0)
  entry.actor = entry.actor or self:GetPlayerDisplayName()
  entry.id = entry.id or self:NextAuditID()

  for _, oldEntry in ipairs(APOCLootPrioDB.audit) do
    if oldEntry.id and oldEntry.id == entry.id then
      return oldEntry
    end
  end

  table.insert(APOCLootPrioDB.audit, 1, entry)
  while #APOCLootPrioDB.audit > 100 do
    table.remove(APOCLootPrioDB.audit)
  end

  return entry
end

function APOCLootPrio:FormatAuditTime(timestamp)
  if date then
    return date("%m/%d %H:%M", tonumber(timestamp) or 0)
  end
  return tostring(timestamp or "")
end

function APOCLootPrio:DescribeAuditEntry(entry, includeDetails)
  if not entry then return "" end
  if entry.text then
    return self:FormatAuditTime(entry.time) .. " " .. tostring(entry.text)
  end

  local actor = ShortName(entry.actor or "Unknown")
  local item = entry.item or entry.key or "unknown item"
  local action = entry.changed and "changed" or "saved no change"
  local line = self:FormatAuditTime(entry.time) .. " " .. actor .. " " .. action .. " " .. item

  if entry.revision then
    line = line .. " r" .. tostring(entry.revision)
  end

  if includeDetails and entry.changed then
    local oldBias = entry.oldBias or ""
    local newBias = entry.newBias or ""
    if oldBias ~= newBias then
      line = line .. " [" .. oldBias .. " -> " .. newBias .. "]"
    end
  end

  return line
end

function APOCLootPrio:RecordAdminSave(item, oldBias, oldNote, newBias, newNote, changed, revision)
  local entry = {
    id = self:NextAuditID(),
    time = time and time() or 0,
    actor = self:GetPlayerDisplayName(),
    action = changed and "changed" or "nochange",
    changed = changed and true or false,
    key = self:GetItemKey(item),
    item = item and item.name or "unknown item",
    oldBias = oldBias or "",
    oldNote = oldNote or "",
    newBias = newBias or "",
    newNote = newNote or "",
    revision = revision,
  }

  return self:AddAuditEntry(entry)
end

function APOCLootPrio:FormatLootTime(timestamp)
  if date then
    return date("%m/%d %H:%M", tonumber(timestamp) or 0)
  end
  return tostring(timestamp or "")
end

function APOCLootPrio:GetAddonVersion()
  local version = nil
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON or "APOCLootTrackerBeta", "Version")
  elseif GetAddOnMetadata then
    version = GetAddOnMetadata(ADDON or "APOCLootTrackerBeta", "Version")
  end
  if not version or version == "" then
    version = FALLBACK_ADDON_VERSION
  end
  return tostring(version)
end

function APOCLootPrio:RecordSyncPeer(sender, messageKind, addonVersion)
  self:InitDB()

  local shortName = ShortName(sender)
  if not shortName or shortName == "" or shortName == ShortName(UnitName and UnitName("player")) then return end

  local rankIndex, rankName = nil, nil
  if self.GetGuildRankForName then
    rankIndex, rankName = self:GetGuildRankForName(shortName)
  end

  APOCLootPrioDB.sync.peers[shortName] = {
    name = shortName,
    lastSeen = time and time() or 0,
    messageKind = messageKind or "",
    addonVersion = addonVersion or (APOCLootPrioDB.sync.peers[shortName] and APOCLootPrioDB.sync.peers[shortName].addonVersion) or "",
    rankIndex = rankIndex,
    rankName = rankName,
  }

  if self.RefreshSyncedClientsPanel then self:RefreshSyncedClientsPanel() end
end


local function ParsePeerBetaVersion(version)
  local n = tonumber(string.match(tostring(version or ""), "beta%.(%d+)"))
  return n
end

-- Drop stale or outdated synced clients so archive whispers stay focused.
function APOCLootPrio:PruneOldSyncPeers()
  self:InitDB()
  APOCLootPrioDB.sync.peers = APOCLootPrioDB.sync.peers or {}
  local now = time and time() or 0
  local minBeta = 13
  local staleAfter = 24 * 60 * 60
  local removed = {}
  for key, peer in pairs(APOCLootPrioDB.sync.peers) do
    local version = peer and peer.addonVersion or ""
    local lastSeen = tonumber(peer and peer.lastSeen) or 0
    local betaNum = ParsePeerBetaVersion(version)
    local tooOldVersion = false
    if version ~= "" then
      if betaNum ~= nil then
        tooOldVersion = betaNum < minBeta
      else
        -- Known non-empty version that isn't a current multi-run beta build.
        tooOldVersion = true
      end
    end
    local tooStale = now > 0 and lastSeen > 0 and (now - lastSeen) > staleAfter
    local unknownAndStale = (version == "" or version == "unknown") and (lastSeen == 0 or (now > 0 and (now - lastSeen) > 60 * 60))
    if tooOldVersion or tooStale or unknownAndStale then
      table.insert(removed, peer.name or key)
      APOCLootPrioDB.sync.peers[key] = nil
    end
  end
  table.sort(removed)
  return removed
end

function APOCLootPrio:GetSyncedClients()
  self:InitDB()

  local clients = {}
  local playerName = self:GetPlayerDisplayName()
  local playerRankIndex, playerRankName = nil, nil
  if self.GetGuildRankForName then
    playerRankIndex, playerRankName = self:GetGuildRankForName(playerName)
  end

  table.insert(clients, {
    name = playerName,
    lastSeen = time and time() or 0,
    messageKind = "local",
    addonVersion = self:GetAddonVersion(),
    syncProtocol = 3,
    rankIndex = playerRankIndex,
    rankName = playerRankName,
    isLocal = true,
  })

  self:PruneOldSyncPeers()
  for _, peer in pairs(APOCLootPrioDB.sync.peers or {}) do
    table.insert(clients, peer)
  end

  table.sort(clients, function(a, b)
    if a.isLocal ~= b.isLocal then return a.isLocal end
    local aSeen = tonumber(a.lastSeen) or 0
    local bSeen = tonumber(b.lastSeen) or 0
    if aSeen ~= bSeen then return aSeen > bSeen end
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  return clients
end

function APOCLootPrio:FormatTradeTimeLeft(drop)
  local droppedAt = drop and tonumber(drop.droppedAt)
  if not droppedAt or not time then return "" end
  local remaining = (droppedAt + (2 * 60 * 60)) - time()
  if remaining <= 0 then return "expired" end

  local minutes = math.floor(remaining / 60)
  local hours = math.floor(minutes / 60)
  minutes = minutes - (hours * 60)
  if hours > 0 then
    return tostring(hours) .. "h " .. tostring(minutes) .. "m"
  end
  return tostring(minutes) .. "m"
end

local function NewLootSessionKey(raid, counter)
  local now = time and time() or 0
  local stamp = date and date("%Y-%m-%d", now) or tostring(now)
  local player = UnitName and UnitName("player") or "Unknown"
  return tostring(raid or "Raid") .. ":" .. stamp .. ":" .. tostring(now) .. ":" .. tostring(player) .. ":" .. tostring(counter or 0)
end

-- Authorize the record being changed, never the currently displayed tab.
function APOCLootPrio:CanEditLootSession(session)
  if not session or session.readOnly then return false end
  if self.IsClosedHistorySession and self:IsClosedHistorySession(session) then
    return self:CanEditGuildRaidHistory()
  end
  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() then return false end
  local run = self.GetActiveRun and self:GetActiveRun()
  return run ~= nil and session.runID == run.id
    and self:IsLocalLootSyncV2Authority()
end

function APOCLootPrio:TouchLootSession(session)
  if not session then return 0 end
  session.revision = (tonumber(session.revision) or 0) + 1
  session.updatedAt = time and time() or 0
  session.syncAuthority = self.GetPlayerDisplayName and self:GetPlayerDisplayName() or session.syncAuthority
  if session.finalized and session.key and APOCLootPrioDB and APOCLootPrioDB.loot then
    APOCLootPrioDB.loot.finalizedSessionBackups = APOCLootPrioDB.loot.finalizedSessionBackups or {}
    APOCLootPrioDB.loot.finalizedSessionBackups[session.key] = DeepCopyTable(session)
  end
  return session.revision
end

function APOCLootPrio:RenameLootSession(sessionKey, newName)
  self:InitDB()
  local session = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  if not session then return nil, "Could not find that loot session." end
  if not self:CanEditLootSession(session) then
    return nil, "No edit permission for this session."
  end

  newName = string.match(tostring(newName or ""), "^%s*(.-)%s*$") or ""
  if newName == "" then return nil, "Enter a session name." end
  if #newName > 96 then return nil, "Session names can be up to 96 characters." end
  if string.find(newName, "[%c|]") then
    return nil, "Session names cannot contain line breaks or the | character."
  end
  if newName == tostring(session.name or session.raid or "") then
    return session, "Session name is unchanged.", false
  end

  session.name = newName
  self:TouchLootSession(session)
  -- Any previously prepared backup contains the old title. The runner can
  -- prepare a fresh export after the rename without risking a stale upload.
  APOCLootTrackerBetaExport = nil
  if self.BroadcastLootSessionMetadata then
    self:BroadcastLootSessionMetadata(session)
  elseif self.BroadcastLootSession then
    self:BroadcastLootSession(session)
  end
  return session, "Renamed session to " .. newName .. ".", true
end

function APOCLootPrio:SaveFinalizedLootSessionBackup(session)
  if not session or not session.key or not session.finalized then return false end
  self:InitDB()
  APOCLootPrioDB.loot.finalizedSessionBackups[session.key] = DeepCopyTable(session)
  return true
end

local function GetOrdinalSuffix(day)
  day = tonumber(day) or 0
  local suffix = "th"
  local lastTwo = day % 100
  local lastOne = day % 10
  if lastTwo < 11 or lastTwo > 13 then
    if lastOne == 1 then suffix = "st"
    elseif lastOne == 2 then suffix = "nd"
    elseif lastOne == 3 then suffix = "rd" end
  end
  return suffix
end

local function EscapePattern(text)
  return (string.gsub(tostring(text or ""), "([^%w])", "%%%1"))
end

function APOCLootPrio:GetLootSessionDateName(timestamp)
  if date then
    local day = tonumber(date("%d", timestamp)) or 0
    return date("%A %B ", timestamp) .. tostring(day) .. GetOrdinalSuffix(day) .. date(" %Y", timestamp)
  end

  return "Raid Night"
end

function APOCLootPrio:GetDefaultLootSessionName()
  return self:GetLootSessionDateName(time and time() or nil)
end

function APOCLootPrio:GetNextLootSessionName()
  self:InitDB()

  local baseName = self:GetDefaultLootSessionName()
  local count = 0
  local duplicatePattern = "^" .. EscapePattern(baseName) .. " %(session %d+%)$"
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    local name = session.name or session.raid or ""
    local dateName = self:GetLootSessionDateName(session.createdAt)
    if name == baseName or dateName == baseName or string.match(name, duplicatePattern) then
      count = count + 1
    end
  end

  if count == 0 then
    return baseName
  end

  return baseName .. " (session " .. tostring(count + 1) .. ")"
end

function APOCLootPrio:GetRaidAttendanceRoster()
  local roster = {}
  if not IsPlayerInRaidGroup() then return roster, true end

  local raidSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  if raidSize == 0 and GetNumRaidMembers then raidSize = GetNumRaidMembers() end
  if raidSize <= 0 or not GetRaidRosterInfo then return nil, false end

  for index = 1, raidSize do
    local name, _, subgroup, _, className, classFileName = GetRaidRosterInfo(index)
    local key = NormalizePlayerName(name)
    if key ~= "" then
      roster[key] = {
        name = ShortName(name),
        className = className or "",
        classFileName = classFileName or "",
        subgroup = tonumber(subgroup) or 0,
      }
    end
  end

  if next(roster) == nil then return nil, false end
  return roster, true
end

function APOCLootPrio:CloseRaidAttendanceSession(session, closedAt, skipBroadcast)
  if not session or not session.attendance or not session.attendance.tracking then return false end
  closedAt = tonumber(closedAt) or (time and time() or 0)
  local changed = false

  for _, member in pairs(session.attendance.members or {}) do
    if member.present then
      member.present = false
      member.lastLeftAt = closedAt
      local visits = member.visits or {}
      local visit = visits[#visits]
      if visit and not visit.leftAt then visit.leftAt = closedAt end
      changed = true
    end
  end
  session.attendance.tracking = false
  session.attendance.updatedAt = closedAt
  changed = true

  if changed then
    self:TouchLootSession(session)
    if not skipBroadcast then
      if self.BroadcastLootSessionMetadata then self:BroadcastLootSessionMetadata(session)
      elseif self.BroadcastLootSession then self:BroadcastLootSession(session) end
    end
  end
  return changed
end

function APOCLootPrio:FinalizeLootSession(sessionKey)
  self:InitDB()
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can close live loot tracker sessions."
  end

  sessionKey = sessionKey or APOCLootPrioDB.loot.activeSessionKey
  local session = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey] or nil
  local historyEdit = session and self.IsHistoryEditContext and self:IsHistoryEditContext()
    and self.CanEditGuildRaidHistory and self:CanEditGuildRaidHistory()
    and self.GetActiveHistorySession and session == self:GetActiveHistorySession()
  if not self:CanEditLootSession(session) and not historyEdit then
    return nil, "No edit permission for this session."
  end
  if session.archived and not historyEdit then
    return nil, "Open this saved raid in History with edit access before closing it."
  end
  if session.finalized then return session, "This session is already closed and saved." end

  local now = time and time() or 0
  local wasArchived = session.archived == true
  self:CloseRaidAttendanceSession(session, now, true)
  session.finalized = true
  session.closedAt = now
  session.closedBy = self:GetPlayerDisplayName()
  session.savedAt = now
  session.archived = wasArchived
  self:TouchLootSession(session)
  self:SaveFinalizedLootSessionBackup(session)

  if historyEdit then
    if self.ScheduleHistorySessionPush then self:ScheduleHistorySessionPush(session) end
  else
    if self.SendLootSessionV2 then self:SendLootSessionV2(session) end
    if self.SendLootSyncV2Transfer and self.BuildLootSessionCatalogV3 then
      self:SendLootSyncV2Transfer("SC", self:BuildLootSessionCatalogV3())
    end
    if self.QueueLootManifestV3 then self:QueueLootManifestV3() end
  end
  if self.ScheduleGuildArchivePublish then self:ScheduleGuildArchivePublish(session) end
  return session
end

function APOCLootPrio:UpdateRaidAttendance(session, allowInitialize, skipBroadcast)
  if not self:CanEditLootTracker() then return false end
  self:InitDB()

  session = session or (APOCLootPrioDB.loot.activeSessionKey and APOCLootPrioDB.loot.sessions[APOCLootPrioDB.loot.activeSessionKey])
  if not self:CanEditLootSession(session) or session.finalized or session.archived then return false end
  if not session.attendance then
    if not allowInitialize then return false end
    session.attendance = {tracking = true, members = {}, updatedAt = 0}
  end
  if not session.attendance.tracking then return false end

  local roster, valid = self:GetRaidAttendanceRoster()
  if not valid then return false end

  local now = time and time() or 0
  local members = session.attendance.members or {}
  session.attendance.members = members
  local changed = false

  for key, current in pairs(roster or {}) do
    local member = members[key]
    if not member then
      member = {
        name = current.name,
        className = current.className,
        classFileName = current.classFileName,
        subgroup = current.subgroup,
        firstJoinedAt = now,
        lastJoinedAt = now,
        present = true,
        visits = {{joinedAt = now}},
      }
      members[key] = member
      changed = true
    else
      if member.name ~= current.name then member.name = current.name; changed = true end
      if member.className ~= current.className then member.className = current.className; changed = true end
      if member.classFileName ~= current.classFileName then member.classFileName = current.classFileName; changed = true end
      if member.subgroup ~= current.subgroup then member.subgroup = current.subgroup; changed = true end
      member.visits = member.visits or {}
      if not member.present then
        member.present = true
        member.lastJoinedAt = now
        table.insert(member.visits, {joinedAt = now})
        changed = true
      end
    end
    member.lastSeenAt = now
  end

  for key, member in pairs(members) do
    if member.present and not roster[key] then
      member.present = false
      member.lastLeftAt = now
      member.visits = member.visits or {}
      local visit = member.visits[#member.visits]
      if visit and not visit.leftAt then visit.leftAt = now end
      changed = true
    end
  end

  if changed then
    session.attendance.updatedAt = now
    self:TouchLootSession(session)
    if not skipBroadcast then
      if self.BroadcastLootSessionMetadata then self:BroadcastLootSessionMetadata(session)
      elseif self.BroadcastLootSession then self:BroadcastLootSession(session) end
    end
    if self.RefreshAttendancePanel then self:RefreshAttendancePanel() end
  end
  return changed
end

function APOCLootPrio:ScheduleRaidAttendanceUpdate(delay, allowInitialize)
  self.raidAttendanceScanToken = (self.raidAttendanceScanToken or 0) + 1
  local token = self.raidAttendanceScanToken
  delay = tonumber(delay) or 1

  local function runScan()
    if not APOCLootPrio or token ~= APOCLootPrio.raidAttendanceScanToken then return end
    APOCLootPrio:UpdateRaidAttendance(nil, allowInitialize ~= false)
  end
  if C_Timer and C_Timer.After then C_Timer.After(delay, runScan) else runScan() end
end

function APOCLootPrio:FormatAttendanceTime(timestamp)
  timestamp = tonumber(timestamp) or 0
  if timestamp <= 0 then return "--" end
  if date then
    local value = date("%I:%M:%S %p", timestamp)
    return string.gsub(value, "^0", "")
  end
  return tostring(timestamp)
end

function APOCLootPrio:StartRaidLootSession(sessionName, initialInstance)
  self:InitDB()
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can start live loot tracker sessions."
  end

  sessionName = sessionName or self:GetNextLootSessionName()
  local previousKey = APOCLootPrioDB.loot.activeSessionKey
  local previousSession = previousKey and APOCLootPrioDB.loot.sessions[previousKey] or nil
  if previousSession then self:CloseRaidAttendanceSession(previousSession, nil, false) end
  APOCLootPrioDB.loot.sessionCounter = (APOCLootPrioDB.loot.sessionCounter or 0) + 1

  local key = NewLootSessionKey(sessionName, APOCLootPrioDB.loot.sessionCounter)
  APOCLootPrioDB.loot.sessions[key] = {
    key = key,
    raid = sessionName,
    name = sessionName,
    instances = initialInstance and initialInstance ~= "" and {[initialInstance] = true} or {},
    createdAt = time and time() or 0,
    createdBy = self:GetPlayerDisplayName(),
    drops = {},
    attendance = {tracking = true, members = {}, updatedAt = time and time() or 0},
    revision = 0,
    updatedAt = time and time() or 0,
    syncAuthority = self:GetPlayerDisplayName(),
  }
  APOCLootPrioDB.loot.activeSessionKey = key
  self:TouchLootSession(APOCLootPrioDB.loot.sessions[key])
  self:UpdateRaidAttendance(APOCLootPrioDB.loot.sessions[key], true, true)
  if self.BroadcastLootSessionMetadata then
    self:BroadcastLootSessionMetadata(APOCLootPrioDB.loot.sessions[key])
  elseif self.BroadcastLootSession then
    self:BroadcastLootSession(APOCLootPrioDB.loot.sessions[key])
  end
  return APOCLootPrioDB.loot.sessions[key]
end

function APOCLootPrio:GetActiveLootSessionKey(preferredRaid)
  self:InitDB()

  local key = APOCLootPrioDB.loot.activeSessionKey
  if key and APOCLootPrioDB.loot.sessions[key] then
    return key
  end

  if preferredRaid and APOCLootPrioDB.loot.current then
    key = APOCLootPrioDB.loot.current[preferredRaid]
    if key and APOCLootPrioDB.loot.sessions[key] then
      APOCLootPrioDB.loot.activeSessionKey = key
      return key
    end
  end

  local newestKey, newestCreatedAt = nil, -1
  for sessionKey, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    local createdAt = tonumber(session.createdAt) or 0
    if createdAt > newestCreatedAt then
      newestKey = sessionKey
      newestCreatedAt = createdAt
    end
  end

  if newestKey then
    APOCLootPrioDB.loot.activeSessionKey = newestKey
    return newestKey
  end

  return nil
end

function APOCLootPrio:GetRaidLootSession(raid, createIfMissing)
  self:InitDB()

  local key = self:GetActiveLootSessionKey(raid)
  if key and APOCLootPrioDB.loot.sessions[key] then
    return APOCLootPrioDB.loot.sessions[key]
  end

  if createIfMissing and self:CanEditLootTracker() then
    return self:StartRaidLootSession()
  end

  return {
    raid = self:GetDefaultLootSessionName(),
    name = self:GetDefaultLootSessionName(),
    instances = {},
    createdAt = 0,
    createdBy = "",
    drops = {},
    readOnly = true,
  }
end

function APOCLootPrio:GetLootSessions()
  self:InitDB()

  local sessions = {}
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    table.insert(sessions, session)
  end

  table.sort(sessions, function(a, b)
    return (tonumber(a.createdAt) or 0) > (tonumber(b.createdAt) or 0)
  end)

  return sessions
end

function APOCLootPrio:GetLootSessionDisplayName(session)
  if not session then return "No session" end

  local name = session.name or session.raid or "Raid Night"
  if APOCLootPrioData and APOCLootPrioData[name] then
    name = self:GetLootSessionDateName(session.createdAt)
  end

  local instanceNames = {}
  for instanceName in pairs(session.instances or {}) do
    table.insert(instanceNames, instanceName)
  end
  table.sort(instanceNames)

  if #instanceNames > 0 then
    return name .. " - " .. table.concat(instanceNames, " / ")
  end

  return name
end

function APOCLootPrio:OpenLootSession(sessionKey)
  self:InitDB()

  if not sessionKey or not APOCLootPrioDB.loot.sessions[sessionKey] then
    return nil, "Could not find that loot session."
  end

  local wasActive = APOCLootPrioDB.loot.activeSessionKey == sessionKey
  APOCLootPrioDB.loot.activeSessionKey = sessionKey
  local session = APOCLootPrioDB.loot.sessions[sessionKey]
  if not session.attendance then
    session.attendance = {tracking = wasActive and IsPlayerInRaidGroup() or false, members = {}, updatedAt = 0}
  end
  if self.IsLocalLootSyncV2Authority and self:IsLocalLootSyncV2Authority() then
    self:TouchLootSession(session)
    if self.BroadcastLootSessionMetadata then self:BroadcastLootSessionMetadata(session) end
  end
  return APOCLootPrioDB.loot.sessions[sessionKey]
end

function APOCLootPrio:DeleteLootSession(sessionKey)
  self:InitDB()
  if not self:CanDeleteLootSessions() then
    return nil, "You cannot delete saved sessions at your guild rank."
  end

  local session = sessionKey and APOCLootPrioDB.loot.sessions[sessionKey]
  if not session then
    return nil, "Could not find that loot session."
  end

  local deleteRevision = (tonumber(session.revision) or 0) + 1
  APOCLootPrioDB.loot.deletedSessions[sessionKey] = deleteRevision
  APOCLootPrioDB.loot.sessions[sessionKey] = nil
  if APOCLootPrioDB.loot.finalizedSessionBackups then
    APOCLootPrioDB.loot.finalizedSessionBackups[sessionKey] = nil
  end
  if APOCLootPrioDB.loot.activeSessionKey == sessionKey then
    APOCLootPrioDB.loot.activeSessionKey = nil
  end

  for raidName, key in pairs(APOCLootPrioDB.loot.current or {}) do
    if key == sessionKey then
      APOCLootPrioDB.loot.current[raidName] = nil
    end
  end

  if self.BroadcastLootSessionDelete then self:BroadcastLootSessionDelete(sessionKey, deleteRevision, session.runID) end
  return session
end

function APOCLootPrio:NextLootDropID()
  self:InitDB()
  APOCLootPrioDB.loot.dropCounter = (APOCLootPrioDB.loot.dropCounter or 0) + 1
  return tostring(time and time() or 0) .. ":" .. self:GetPlayerDisplayName() .. ":drop:" .. tostring(APOCLootPrioDB.loot.dropCounter)
end

function APOCLootPrio:AddRaidLootDrop(item, bossName, raid, skipBroadcast)
  if not item then return nil end
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can add live loot drops."
  end

  local session = self:GetRaidLootSession(raid, true)
  if not self:CanEditLootSession(session) then
    return nil, "No edit permission for this session."
  end
  if session.finalized then
    return nil, "This loot session is closed and saved. Start a new session to track more drops."
  end

  raid = raid or self.selectedRaid or session.raid or "Loot"
  session.instances = session.instances or {}
  session.instances[raid] = true

  local drop = {
    id = self:NextLootDropID(),
    raid = raid,
    boss = bossName or "Unknown boss",
    item = item.name or "Unknown item",
    itemID = self:GetItemID(item),
    itemLink = self:GetCachedItemLink(item) or item.link,
    itemQuality = self:GetItemQuality(item),
    itemKey = self:GetItemKey(item),
    bias = self:GetItemBias(item) or "",
    note = self:GetItemNote(item) or "",
    droppedAt = time and time() or 0,
    addedBy = self:GetPlayerDisplayName(),
  }

  table.insert(session.drops, 1, drop)
  self:TouchLootSession(session)
  drop.syncRevision = session.revision
  self.selectedLootDropID = drop.id
  if not skipBroadcast then
    if self.BroadcastLootDropUpdate then
      self:BroadcastLootDropUpdate(session, drop)
    elseif self.BroadcastLootSession then
      self:BroadcastLootSession(session)
    end
  end
  return drop
end

function APOCLootPrio:FindLootItemByID(itemID, preferredRaid)
  itemID = tonumber(itemID)
  if not itemID or not APOCLootPrioData then return nil end

  local function searchRaid(raidName)
    for _, boss in ipairs(APOCLootPrioData[raidName] or {}) do
      for _, item in ipairs(boss.items or {}) do
        if tonumber(self:GetItemID(item)) == itemID then
          return raidName, boss.boss, item
        end
      end
    end
    return nil
  end

  if preferredRaid then
    local raidName, bossName, item = searchRaid(preferredRaid)
    if item then return raidName, bossName, item end
  end

  for raidName in pairs(APOCLootPrioData) do
    if raidName ~= preferredRaid then
      local foundRaid, bossName, item = searchRaid(raidName)
      if item then return foundRaid, bossName, item end
    end
  end

  return nil
end

function APOCLootPrio:FindLootItemByName(itemName, preferredRaid)
  itemName = string.lower(itemName or "")
  if itemName == "" or not APOCLootPrioData then return nil end

  local function searchRaid(raidName)
    for _, boss in ipairs(APOCLootPrioData[raidName] or {}) do
      for _, item in ipairs(boss.items or {}) do
        if string.lower(item.name or "") == itemName then
          return raidName, boss.boss, item
        end
      end
    end
    return nil
  end

  if preferredRaid then
    local raidName, bossName, item = searchRaid(preferredRaid)
    if item then return raidName, bossName, item end
  end

  for raidName in pairs(APOCLootPrioData) do
    if raidName ~= preferredRaid then
      local foundRaid, bossName, item = searchRaid(raidName)
      if item then return foundRaid, bossName, item end
    end
  end

  return nil
end

-- Resolve priority from the Loot Browser at send/export time. Older raid drops
-- may not have copied the catalog bias and note when they were first recorded,
-- and guild overrides can change after a drop was created.
function APOCLootPrio:GetLootBrowserPriorityForDrop(drop, session)
  if not drop then return nil, nil end

  local foundRaid, foundBoss, item
  local preferredRaids = {}
  local seen = {}
  local function addRaid(raidName)
    if raidName and raidName ~= "" and not seen[raidName] then
      seen[raidName] = true
      preferredRaids[#preferredRaids + 1] = raidName
    end
  end

  addRaid(drop.raid)
  addRaid(session and session.raid)
  for raidName in pairs(session and session.instances or {}) do addRaid(raidName) end

  local itemID = tonumber(drop.itemID)
  for _, raidName in ipairs(preferredRaids) do
    if itemID then foundRaid, foundBoss, item = self:FindLootItemByID(itemID, raidName) end
    if not item and drop.item then foundRaid, foundBoss, item = self:FindLootItemByName(drop.item, raidName) end
    if item then break end
  end

  if not item and itemID then foundRaid, foundBoss, item = self:FindLootItemByID(itemID) end
  if not item and drop.item then foundRaid, foundBoss, item = self:FindLootItemByName(drop.item) end
  if not item then return drop.bias, drop.note end

  return self:GetItemBias(item), self:GetItemNote(item)
end

function APOCLootPrio:GetItemIDFromLink(link)
  return tonumber(string.match(link or "", "item:(%d+)"))
end

function APOCLootPrio:GetCurrentLootTrackerContext()
  local instanceName = nil
  if GetInstanceInfo then
    instanceName = GetInstanceInfo()
  end

  if instanceName and instanceName ~= "" then
    return instanceName, "Dungeon Loot"
  end

  return self.selectedRaid or "Loot", "Loot"
end

function APOCLootPrio:GetCurrentSessionPromptInstance()
  if not IsInInstance or not GetInstanceInfo then return nil end
  local inInstance, instanceType = IsInInstance()
  if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return nil end

  local instanceName, _, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
  if not instanceName or instanceName == "" then return nil end
  local key = table.concat({
    string.lower(tostring(instanceName)),
    tostring(instanceType or ""),
    tostring(difficultyID or difficultyName or ""),
    tostring(instanceID or ""),
  }, ":")
  return instanceName, key
end

function APOCLootPrio:MaybePromptNewSessionForInstance()
  self:InitDB()
  if not self:CanEditLootTracker() then return false end

  local instanceName, promptKey = self:GetCurrentSessionPromptInstance()
  if not instanceName or not promptKey then return false end

  local now = time and time() or 0
  local lastPrompted = tonumber(APOCLootPrioDB.loot.instancePromptHistory[promptKey]) or 0
  if lastPrompted > 0 and now > 0 and (now - lastPrompted) < INSTANCE_SESSION_PROMPT_COOLDOWN_SECONDS then
    return false
  end
  if self.pendingInstanceSessionPrompt == instanceName then return false end

  if self.SetInstanceSessionPromptShown and self:SetInstanceSessionPromptShown(true, instanceName) then
    APOCLootPrioDB.loot.instancePromptHistory[promptKey] = now
    return true
  end
  return false
end

function APOCLootPrio:ScheduleInstanceSessionPromptCheck(delay)
  delay = tonumber(delay) or 1
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, function()
      if APOCLootPrio and APOCLootPrio.MaybePromptNewSessionForInstance then
        APOCLootPrio:MaybePromptNewSessionForInstance()
      end
    end)
  elseif self.MaybePromptNewSessionForInstance then
    self:MaybePromptNewSessionForInstance()
  end
end

function APOCLootPrio:CreateGenericLootItemFromLink(link)
  local itemID = self:GetItemIDFromLink(link)
  local itemName = string.match(link or "", "%[(.-)%]")
  if not itemName or itemName == "" then return nil end

  return {
    name = itemName,
    id = itemID,
    link = link,
    bias = "",
    note = "Auto-added dungeon loot",
  }
end

function APOCLootPrio:WasAutoLootRecentlySeen(raid, bossName, item)
  if not item or not time then return false end
  local itemKey = self:GetItemKey(item)
  if not itemKey then return false end

  self.autoLootSeen = self.autoLootSeen or {}
  local key = tostring(raid or "") .. ":" .. tostring(bossName or "") .. ":" .. itemKey
  local now = time()
  local lastSeen = self.autoLootSeen[key]
  self.autoLootSeen[key] = now

  return lastSeen and (now - lastSeen) < 8
end

function APOCLootPrio:GetAutoLootDuplicateKey(raid, bossName, item)
  if not item then return nil end
  local itemKey = self:GetItemKey(item)
  if not itemKey then return nil end
  return string.lower(tostring(raid or "")) .. ":" .. string.lower(tostring(bossName or "")) .. ":" .. tostring(itemKey)
end

function APOCLootPrio:CountRecentAutoLootDuplicates(raid, bossName, item)
  if not item then return 0, nil end
  local session = self:GetRaidLootSession(raid)
  if not session or not session.drops then return 0, nil end

  local itemKey = self:GetItemKey(item)
  local itemID = tonumber(self:GetItemID(item))
  local itemName = string.lower(tostring(item.name or ""))
  local bossKey = string.lower(tostring(bossName or ""))
  local raidKey = string.lower(tostring(raid or session.raid or ""))
  local now = time and time() or 0
  local count = 0
  local firstDrop = nil

  for _, drop in ipairs(session.drops or {}) do
    local dropTime = tonumber(drop.droppedAt) or 0
    local recentEnough = now == 0 or dropTime == 0 or (now - dropTime) <= AUTO_LOOT_DUPLICATE_WINDOW_SECONDS
    if recentEnough and drop.autoAdded then
      local dropItemKey = drop.itemKey or (drop.itemID and ("i:" .. tostring(drop.itemID))) or nil
      local sameItem = false
      if itemKey and dropItemKey and itemKey == dropItemKey then
        sameItem = true
      elseif itemID and tonumber(drop.itemID) == itemID then
        sameItem = true
      elseif itemName ~= "" and string.lower(tostring(drop.item or "")) == itemName then
        sameItem = true
      end

      local sameBoss = string.lower(tostring(drop.boss or "")) == bossKey
      local sameRaid = string.lower(tostring(drop.raid or "")) == raidKey
      if sameItem and sameBoss and sameRaid then
        count = count + 1
        if not firstDrop then firstDrop = drop end
      end
    end
  end

  return count, firstDrop
end

function APOCLootPrio:FindRecentAutoLootDuplicate(raid, bossName, item, allowedRecentCount)
  local count, firstDrop = self:CountRecentAutoLootDuplicates(raid, bossName, item)
  allowedRecentCount = tonumber(allowedRecentCount) or 1
  if count >= allowedRecentCount then return firstDrop end
  return nil
end

function APOCLootPrio:ReportAutoLootDuplicate(item)
  if not self.UpdateRaidLootStatus or not time then return end
  local now = time()
  if self.lastAutoLootDuplicateStatusAt and (now - self.lastAutoLootDuplicateStatusAt) < 15 then return end
  self.lastAutoLootDuplicateStatusAt = now
  self:UpdateRaidLootStatus("Skipped duplicate auto-capture for " .. tostring(item and item.name or "loot") .. ".")
end

function APOCLootPrio:GetLootTrackerOwner()
  self:InitDB()
  return APOCLootPrioDB.loot.trackerOwner
end

function APOCLootPrio:IsLootTrackerOwner(name)
  local owner = self:GetLootTrackerOwner()
  if not owner or owner == "" then return false end

  local playerName = name or self:GetPlayerDisplayName()
  return NormalizePlayerName(owner) ~= "" and NormalizePlayerName(owner) == NormalizePlayerName(playerName)
end

function APOCLootPrio:SetLootTrackerOwner(name, source, setAt, skipBroadcast)
  self:InitDB()

  local cleanName = name and string.match(name, "^%s*(.-)%s*$") or ""
  local timestamp = tonumber(setAt) or (time and time() or 0)

  APOCLootPrioDB.loot.trackerOwner = cleanName ~= "" and cleanName or nil
  APOCLootPrioDB.loot.trackerOwnerSetBy = source or self:GetPlayerDisplayName()
  APOCLootPrioDB.loot.trackerOwnerSetAt = timestamp

  if not skipBroadcast and self.BroadcastLootTrackerOwner then
    self:BroadcastLootTrackerOwner()
  end

  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshOfficerControls then self:RefreshOfficerControls() end
  if self.ScheduleInstanceSessionPromptCheck then self:ScheduleInstanceSessionPromptCheck(1) end
  if self.ScheduleRaidAttendanceUpdate then self:ScheduleRaidAttendanceUpdate(1, true) end
  return APOCLootPrioDB.loot.trackerOwner
end

function APOCLootPrio:ClearLootTrackerOwner()
  return self:SetLootTrackerOwner(nil)
end

function APOCLootPrio:GetLootDisenchanter()
  self:InitDB()
  return APOCLootPrioDB.loot.disenchanter
end

function APOCLootPrio:IsLootDisenchanterInGroup(name)
  name = name or self:GetLootDisenchanter()
  local targetKey = NormalizePlayerName(name)
  if targetKey == "" then return false end
  for _, memberName in ipairs(self:GetGroupRoster()) do
    if NormalizePlayerName(memberName) == targetKey then return true end
  end
  return false
end

function APOCLootPrio:SetLootDisenchanter(name, source, setAt, skipBroadcast)
  self:InitDB()

  local cleanName = name and string.match(name, "^%s*(.-)%s*$") or ""
  local timestamp = tonumber(setAt) or (time and time() or 0)
  APOCLootPrioDB.loot.disenchanter = cleanName ~= "" and cleanName or nil
  APOCLootPrioDB.loot.disenchanterSetBy = source or self:GetPlayerDisplayName()
  APOCLootPrioDB.loot.disenchanterSetAt = timestamp

  if not skipBroadcast and self.BroadcastLootTrackerOwner then
    self:BroadcastLootTrackerOwner()
  end
  if self.RefreshLootTrackerSettingsPanel then self:RefreshLootTrackerSettingsPanel() end
  if self.RefreshLootRollResultsPanel then self:RefreshLootRollResultsPanel() end
  return APOCLootPrioDB.loot.disenchanter
end

function APOCLootPrio:ClearLootDisenchanter()
  return self:SetLootDisenchanter(nil)
end

function APOCLootPrio:GetLootAutoTrackMode()
  self:InitDB()
  APOCLootPrioDB.loot.autoTrackMode = NormalizeLootAutoTrackMode(APOCLootPrioDB.loot.autoTrackMode)
  return APOCLootPrioDB.loot.autoTrackMode
end

function APOCLootPrio:GetLootAutoTrackModeLabel(mode)
  mode = NormalizeLootAutoTrackMode(mode or (APOCLootPrioDB and APOCLootPrioDB.loot and APOCLootPrioDB.loot.autoTrackMode))
  if mode == "solo" then return "Solo" end
  if mode == "party" then return "Party" end
  if mode == "raid" then return "Raid" end
  return "Off"
end

function APOCLootPrio:SetLootAutoTrackMode(mode, source, skipBroadcast)
  self:InitDB()
  if not self:CanManageSettings() then
    return false, "Only the top two guild ranks can change auto tracking."
  end

  local normalized = NormalizeLootAutoTrackMode(mode)
  local oldMode = NormalizeLootAutoTrackMode(APOCLootPrioDB.loot.autoTrackMode)
  if oldMode == normalized then
    APOCLootPrioDB.loot.autoTrackMode = normalized
    return true, normalized
  end

  APOCLootPrioDB.loot.autoTrackMode = normalized

  if self.AddAuditEntry then
    self:AddAuditEntry((source or self:GetPlayerDisplayName() or "Unknown") .. " set Loot Tracker auto track to " .. self:GetLootAutoTrackModeLabel(normalized) .. ".")
  end
  if not skipBroadcast and self.BroadcastAccessSettings then self:BroadcastAccessSettings() end
  return true, normalized
end

function APOCLootPrio:GetLootQualityLabel(quality)
  quality = tonumber(quality)
  if quality == 5 then return "Legendary" end
  if quality == 4 then return "Epic" end
  if quality == 3 then return "Rare" end
  if quality == 2 then return "Green" end
  return "Other"
end

function APOCLootPrio:IsLootQualityTracked(quality)
  self:InitDB()
  quality = tonumber(quality)
  if not DEFAULT_LOOT_QUALITY_FILTERS[quality] then return false end
  return APOCLootPrioDB.loot.qualityFilters[quality] ~= false
end

function APOCLootPrio:SetLootQualityTracked(quality, enabled, source, skipBroadcast)
  self:InitDB()
  quality = tonumber(quality)
  if not DEFAULT_LOOT_QUALITY_FILTERS[quality] then return false, "Unsupported loot quality." end
  if not self:CanManageSettings() then
    return false, "Only the top two guild ranks can change loot quality tracking."
  end

  enabled = enabled and true or false
  APOCLootPrioDB.loot.qualityFilters[quality] = enabled
  if self.AddAuditEntry then
    self:AddAuditEntry((source or self:GetPlayerDisplayName() or "Unknown") .. " turned " .. self:GetLootQualityLabel(quality) .. " auto tracking " .. (enabled and "on" or "off") .. ".")
  end
  if not skipBroadcast and self.BroadcastAccessSettings then self:BroadcastAccessSettings() end
  return true, enabled
end

function APOCLootPrio:GetLootQualitySettingsMask()
  local values = {}
  for _, quality in ipairs({2, 3, 4, 5}) do
    table.insert(values, self:IsLootQualityTracked(quality) and "1" or "0")
  end
  return table.concat(values)
end

function APOCLootPrio:ApplyLootQualitySettingsMask(mask)
  self:InitDB()
  mask = tostring(mask or "")
  if string.len(mask) < 4 then return false end

  local changed = false
  for index, quality in ipairs({2, 3, 4, 5}) do
    local enabled = string.sub(mask, index, index) == "1"
    if APOCLootPrioDB.loot.qualityFilters[quality] ~= enabled then
      APOCLootPrioDB.loot.qualityFilters[quality] = enabled
      changed = true
    end
  end
  return changed
end

function APOCLootPrio:GetLootLinkQuality(link)
  if link and GetItemInfo then
    local _, _, quality = GetItemInfo(link)
    if quality ~= nil then return tonumber(quality) end
  end

  local color = string.lower(string.match(tostring(link or ""), "|c(%x%x%x%x%x%x%x%x)") or "")
  local qualityByColor = {
    ff9d9d9d = 0,
    ffffffff = 1,
    ff1eff00 = 2,
    ff0070dd = 3,
    ffa335ee = 4,
    ffff8000 = 5,
    ffe6cc80 = 7,
  }
  return qualityByColor[color]
end

function APOCLootPrio:CanAutoTrackLoot()
  if not self:CanEditLootTracker() then return false end

  local activeKey = APOCLootPrioDB and APOCLootPrioDB.loot and APOCLootPrioDB.loot.activeSessionKey
  local activeSession = activeKey and APOCLootPrioDB.loot.sessions and APOCLootPrioDB.loot.sessions[activeKey]
  if activeSession and activeSession.finalized then return false end

  local mode = self:GetLootAutoTrackMode()
  if mode == "off" then return false end

  local context = GetLootAutoTrackContext()
  if mode ~= context then return false end

  local trackerOwner = self:GetLootTrackerOwner()
  if trackerOwner and trackerOwner ~= "" then
    return self:IsLootTrackerOwner()
  end

  if context == "solo" then return true end

  if GetLootMethod then
    local lootMethod = GetLootMethod()
    if lootMethod == "master" then
      return self:IsMasterLooter()
    end
  elseif self.detectedMasterLooter then
    return self:IsMasterLooter()
  end

  return IsPlayerGroupLeader()
end

function APOCLootPrio:AutoAddRaidLootDrop(item, bossName, raid, source, allowedRecentCount, detectedQuality, captureKey)
  if not item then return nil end
  if not self:CanAutoTrackLoot() then return nil end

  local quality = tonumber(detectedQuality) or self:GetItemQuality(item)
  if quality ~= nil and not self:IsLootQualityTracked(quality) then return nil end
  if quality ~= nil and not DEFAULT_LOOT_QUALITY_FILTERS[quality] then return nil end

  allowedRecentCount = tonumber(allowedRecentCount) or 1
  if captureKey then
    local session = self:GetRaidLootSession(raid)
    for _, existing in ipairs(session and session.drops or {}) do
      if existing.captureKey == captureKey then return nil end
    end
  end
  if not captureKey and self:FindRecentAutoLootDuplicate(raid, bossName, item, allowedRecentCount) then
    self:ReportAutoLootDuplicate(item)
    return nil
  end

  if not captureKey and allowedRecentCount <= 1 and self:WasAutoLootRecentlySeen(raid, bossName, item) then
    return nil
  end

  self.capturingLiveLoot = true
  local ok, drop = pcall(self.AddRaidLootDrop, self, item, bossName, raid, true)
  self.capturingLiveLoot = nil
  if not ok then error(drop) end
  if drop then
    drop.autoAdded = true
    drop.captureKey = captureKey
    drop.source = source or "loot"
    self.selectedLootTrackerRaid = drop.raid
    self.selectedRaidLootItem = item
    self.selectedRaidLootBoss = bossName or "Unknown boss"
    local session = self:GetRaidLootSession(drop.raid)
    if session then
      if self.BroadcastLootDropUpdate then
        self:BroadcastLootDropUpdate(session, drop)
      elseif self.BroadcastLootSession then
        self:BroadcastLootSession(session)
      end
    end
    if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
    if self.UpdateRaidLootStatus then self:UpdateRaidLootStatus("Auto-added " .. (item.name or "loot") .. ".") end
  end

  return drop
end

function APOCLootPrio:AutoAddLootLink(link, source, allowGeneric, lootWindowCounts, detectedQuality, captureKey)
  local itemID = self:GetItemIDFromLink(link)
  local itemName = string.match(link or "", "%[(.-)%]")
  local raid, bossName, item
  detectedQuality = tonumber(detectedQuality) or self:GetLootLinkQuality(link)

  if itemID then
    raid, bossName, item = self:FindLootItemByID(itemID, self.selectedRaid)
  end

  if not item and itemName then
    raid, bossName, item = self:FindLootItemByName(itemName, self.selectedRaid)
  end

  if item then
    local allowedRecentCount = 1
    if lootWindowCounts then
      local duplicateKey = self:GetAutoLootDuplicateKey(raid, bossName, item)
      if duplicateKey then
        lootWindowCounts[duplicateKey] = (lootWindowCounts[duplicateKey] or 0) + 1
        allowedRecentCount = lootWindowCounts[duplicateKey]
      end
    end
    return self:AutoAddRaidLootDrop(item, bossName, raid, source, allowedRecentCount, detectedQuality, captureKey)
  end

  if allowGeneric then
    raid, bossName = self:GetCurrentLootTrackerContext()
    item = self:CreateGenericLootItemFromLink(link)
    if item then
      local allowedRecentCount = 1
      if lootWindowCounts then
        local duplicateKey = self:GetAutoLootDuplicateKey(raid, bossName, item)
        if duplicateKey then
          lootWindowCounts[duplicateKey] = (lootWindowCounts[duplicateKey] or 0) + 1
          allowedRecentCount = lootWindowCounts[duplicateKey]
        end
      end
      return self:AutoAddRaidLootDrop(item, bossName, raid, source or "loot-window", allowedRecentCount, detectedQuality, captureKey)
    end
  end

  return nil
end

function APOCLootPrio:ScanOpenLootForRaidDrops()
  if not GetNumLootItems or not GetLootSlotLink or not self:CanAutoTrackLoot() then return end
  local counts, added = {}, 0
  self.lootWindowReceipts = self.lootWindowReceipts or {}
  self.lootWindowSlotCaptures = self.lootWindowSlotCaptures or {}
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local itemID = self:GetItemIDFromLink(link)
    local quality, quantity
    if GetLootSlotInfo then
      local _, _, count, _, rarity = GetLootSlotInfo(slot)
      quality, quantity = rarity, tonumber(count)
    end
    if itemID then
      local sources = GetLootSourceInfo and {GetLootSourceInfo(slot)} or {}
      local sourceCount = math.floor(#sources / 2)
      if sourceCount == 0 then
        sources = {"window:" .. tostring(time and time() or 0) .. ":" .. tostring(self.lootWindowSerial or 0) .. ":" .. slot, quantity or 1}
        sourceCount = 1
      end
      for index = 1, sourceCount do
        local guid = tostring(sources[index * 2 - 1] or "")
        local amount = math.max(1, math.min(1000, tonumber(sources[index * 2]) or quantity or 1))
        local base = guid .. ":" .. tostring(itemID)
        for copy = 1, amount do
          counts[base] = (counts[base] or 0) + 1
          local key = base .. ":" .. counts[base]
          if not self.lootWindowSlotCaptures[key] then
            local drop = self:AutoAddLootLink(link, "loot-window", true, nil, quality, key)
            if drop then
              self.lootWindowSlotCaptures[key] = true
              added = added + 1
              local receipt = self.lootWindowReceipts[itemID] or {count=0}
              receipt.count = receipt.count + 1
              receipt.at = time and time() or 0
              self.lootWindowReceipts[itemID] = receipt
            end
          end
        end
      end
    end
  end
  if added > 0 and self.SetRaidLootPanelShown then self:SetRaidLootPanelShown(true) end
end

function APOCLootPrio:ScanLootChatForRaidDrop(message)
  local winner, link, quantity
  if LOOT_ITEM_MULTIPLE then winner, link, quantity = self:MatchLocalizedMessage(message, LOOT_ITEM_MULTIPLE) end
  if not winner and LOOT_ITEM then winner, link = self:MatchLocalizedMessage(message, LOOT_ITEM) end
  if not winner then
    if LOOT_ITEM_SELF_MULTIPLE then link, quantity = self:MatchLocalizedMessage(message, LOOT_ITEM_SELF_MULTIPLE) end
    if not link and LOOT_ITEM_SELF then link = self:MatchLocalizedMessage(message, LOOT_ITEM_SELF) end
    if link then winner = self:GetPlayerDisplayName() end
  end
  if not winner or not self:IsCurrentGroupMember(winner) then return end
  local itemID = self:GetItemIDFromLink(link)
  if not itemID then return end
  if self.ConfirmMasterLootReceipt then self:ConfirmMasterLootReceipt(winner, itemID) end
  local count = math.max(1, math.min(1000, tonumber(quantity) or 1))
  local receipt = self.lootWindowReceipts and self.lootWindowReceipts[itemID]
  if receipt and (time and time() or 0) - receipt.at <= 600 then
    local consumed = math.min(count, receipt.count)
    receipt.count, count = receipt.count - consumed, count - consumed
  end
  self.lootChatSerial = (self.lootChatSerial or 0) + 1
  local counts = {}
  for copy = 1, count do
    local key = "chat:" .. tostring(time and time() or 0) .. ":" .. self.lootChatSerial .. ":" .. copy
    if self:AutoAddLootLink(link, "loot-chat", false, counts, nil, key)
      and self.SetRaidLootPanelShown then self:SetRaidLootPanelShown(true) end
  end
end

function APOCLootPrio:FindRaidLootDrop(dropID, raid)
  if raid then
    local session = self:GetRaidLootSession(raid)
    for _, drop in ipairs(session.drops or {}) do
      if drop.id == dropID then return drop, session end
    end
    return nil, session
  end

  self:InitDB()
  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    for _, drop in ipairs(session.drops or {}) do
      if drop.id == dropID then return drop, session end
    end
  end

  return nil, nil
end

function APOCLootPrio:GetTradeTargetDisplayName()
  local target = nil
  if GetUnitName then target = GetUnitName("NPC", true) end
  if (not target or target == "") and UnitName then target = UnitName("NPC") end
  if (not target or target == "") and TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
    target = TradeFrameRecipientNameText:GetText()
  end

  target = string.match(target or "", "^%s*(.-)%s*$")
  target = string.gsub(target or "", "%s*%([^)]*%)%s*$", "")
  return ShortName(target)
end

function APOCLootPrio:CaptureTradePlayerItems()
  local items = {}
  if not GetTradePlayerItemLink then return items end

  for index = 1, 6 do
    local link = GetTradePlayerItemLink(index)
    local itemID = self:GetItemIDFromLink(link)
    if itemID then
      table.insert(items, {
        itemID = itemID,
        itemLink = link,
        quantity = GetTradePlayerItemInfo and tonumber(select(3, GetTradePlayerItemInfo(index))) or 1,
      })
    end
  end

  return items
end

-- Trade transactions are owned by TradeMasterLoot.lua.

function APOCLootPrio:DeleteRaidLootDrop(dropID, raid)
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can delete live loot drops."
  end

  local drop, session = self:FindRaidLootDrop(dropID, raid)
  local _, targetSession = self:FindRaidLootDrop(dropID, raid)
  if not self:CanEditLootSession(targetSession) then return nil, "No edit permission for this session." end
  if not drop or not session then return nil, "Select a dropped item first." end

  for index = #session.drops, 1, -1 do
    if session.drops[index].id == dropID then
      table.remove(session.drops, index)
      if self.selectedLootDropID == dropID then self.selectedLootDropID = nil end
      self:TouchLootSession(session)
      session.deletedDrops = session.deletedDrops or {}
      session.deletedDrops[dropID] = session.revision
      if self.BroadcastLootDropDelete then
        self:BroadcastLootDropDelete(session, dropID)
      elseif self.BroadcastLootSession then
        self:BroadcastLootSession(session)
      end
      return drop
    end
  end

  return nil, "Could not delete that drop."
end

function APOCLootPrio:UnawardRaidLootDrop(dropID, raid)
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can unaward live loot."
  end

  local drop = self:FindRaidLootDrop(dropID, raid)
  local _, targetSession = self:FindRaidLootDrop(dropID, raid)
  if not self:CanEditLootSession(targetSession) then return nil, "No edit permission for this session." end
  if not drop then return nil, "Select an awarded item first." end
  if not drop.award then return nil, "That item is not awarded." end

  drop.award = nil
  local _, session = self:FindRaidLootDrop(dropID, raid)
  self:TouchLootSession(session)
  drop.syncRevision = session.revision
  if self.BroadcastLootDropUpdate then
    self:BroadcastLootDropUpdate(session, drop)
  elseif self.BroadcastLootSession then
    self:BroadcastLootSession(session)
  end
  return drop
end

function APOCLootPrio:NormalizeAwardType(awardType)
  awardType = string.upper(string.match(awardType or "", "^%s*(.-)%s*$"))
  if awardType == "OS" or awardType == "OFFSPEC" or awardType == "OFF SPEC" then return "OS" end
  if awardType == "DE" or awardType == "DISENCHANT" then return "DE" end
  if awardType == "GB" or awardType == "GUILD BANK" or awardType == "BANK" then return "GB" end
  return "MS"
end

function APOCLootPrio:GetAwardType(drop)
  if not drop or not drop.award then return "MS" end
  if drop.award.awardType and drop.award.awardType ~= "" then
    return self:NormalizeAwardType(drop.award.awardType)
  end

  local note = string.lower(drop.award.note or "")
  local paddedNote = " " .. note .. " "
  if string.find(note, "guild bank", 1, true) or string.find(paddedNote, " gb ", 1, true) then return "GB" end
  if string.find(note, "disenchant", 1, true) or string.find(paddedNote, " de ", 1, true) then return "DE" end
  if string.find(note, "off spec", 1, true) or string.find(note, "offspec", 1, true) or string.find(paddedNote, " os ", 1, true) then return "OS" end
  return "MS"
end

function APOCLootPrio:GetAwardTypeLabel(awardType)
  awardType = self:NormalizeAwardType(awardType)
  if awardType == "OS" then return "Off Spec" end
  if awardType == "DE" then return "Disenchant" end
  if awardType == "GB" then return "Guild Bank" end
  return "Main Spec"
end

function APOCLootPrio:UpdateLootAward(dropID, winner, note, awardType)
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can edit live loot awards."
  end

  winner = string.match(winner or "", "^%s*(.-)%s*$")
  note = string.match(note or "", "^%s*(.-)%s*$")
  awardType = self:NormalizeAwardType(awardType)
  if awardType == "GB" then winner = "" end
  if winner == "" and awardType == "DE" then winner = "Disenchant" end
  if winner == "" and awardType ~= "GB" then return nil, "Enter the winner name." end

  local drop = self:FindRaidLootDrop(dropID)
  local _, targetSession = self:FindRaidLootDrop(dropID)
  if not self:CanEditLootSession(targetSession) then return nil, "No edit permission for this session." end
  if not drop then return nil, "Select a loot award first." end

  drop.award = drop.award or {}
  drop.award.winner = winner
  drop.award.note = note
  drop.award.awardType = awardType
  drop.award.awardedAt = drop.award.awardedAt or (time and time() or 0)
  drop.award.awardedBy = drop.award.awardedBy or self:GetPlayerDisplayName()
  drop.award.editedAt = time and time() or 0
  drop.award.editedBy = self:GetPlayerDisplayName()

  local _, session = self:FindRaidLootDrop(dropID)
  self:TouchLootSession(session)
  drop.syncRevision = session.revision
  if self.BroadcastLootDropUpdate then
    self:BroadcastLootDropUpdate(session, drop)
  elseif self.BroadcastLootSession then
    self:BroadcastLootSession(session)
  end
  return drop
end

function APOCLootPrio:AwardRaidLootDrop(dropID, winner, note, awardType)
  if not self:CanEditLootTracker() then
    return nil, "Only the Master Looter can award live loot."
  end

  winner = string.match(winner or "", "^%s*(.-)%s*$")
  note = string.match(note or "", "^%s*(.-)%s*$")
  awardType = self:NormalizeAwardType(awardType)
  if awardType == "GB" then winner = "" end
  if winner == "" and awardType == "DE" then winner = "Disenchant" end
  if winner == "" and awardType ~= "GB" then return nil, "Enter the winner name." end

  local drop = self:FindRaidLootDrop(dropID)
  local _, targetSession = self:FindRaidLootDrop(dropID)
  if not self:CanEditLootSession(targetSession) then return nil, "No edit permission for this session." end
  if not drop then return nil, "Select a dropped item first." end

  drop.award = {
    winner = winner,
    note = note,
    awardType = awardType,
    awardedAt = time and time() or 0,
    awardedBy = self:GetPlayerDisplayName(),
  }

  local _, session = self:FindRaidLootDrop(dropID)
  self:TouchLootSession(session)
  drop.syncRevision = session.revision
  if self.BroadcastLootDropUpdate then
    self:BroadcastLootDropUpdate(session, drop)
  elseif self.BroadcastLootSession then
    self:BroadcastLootSession(session)
  end
  return drop
end

function APOCLootPrio:GetRaidLootSummary(raid)
  local session = self:GetRaidLootSession(raid)
  return self:GetRaidLootSummaryForSession(session)
end


function APOCLootPrio:ClassifyRaidMaterialDrop(drop)
  if not drop then return nil end
  local id = tonumber(drop.itemID or drop.id)
  if id and EPIC_GEM_ITEM_IDS[id] then return "gem" end
  if id and HEART_ITEM_IDS[id] then return "heart" end
  local name = string.lower(tostring(drop.item or ""))
  name = string.match(name, "%[(.-)%]") or name
  if name == "heart of darkness" then return "heart" end
  for _, hint in ipairs(EPIC_GEM_NAME_HINTS) do
    if name == hint or string.find(name, hint, 1, true) then return "gem" end
  end
  return nil
end

function APOCLootPrio:GetRaidLootSummaryForSession(session)
  session = session or {drops = {}}
  local total, awarded, pending = 0, 0, 0
  local gems, hearts = 0, 0
  local winners = {}

  for _, drop in ipairs(session.drops or {}) do
    total = total + 1
    local kind = self:ClassifyRaidMaterialDrop(drop)
    if kind == "gem" then gems = gems + 1 end
    if kind == "heart" then hearts = hearts + 1 end
    if drop.award and ((drop.award.winner and drop.award.winner ~= "") or self:GetAwardType(drop) == "GB") then
      awarded = awarded + 1
      winners[drop.award.winner] = (winners[drop.award.winner] or 0) + 1
    else
      pending = pending + 1
    end
  end

  return {
    session = session,
    total = total,
    awarded = awarded,
    pending = pending,
    gems = gems,
    hearts = hearts,
    winners = winners,
  }
end

function APOCLootPrio:FormatRaidMaterialSummary(summary)
  summary = summary or {}
  local gems = tonumber(summary.gems) or 0
  local hearts = tonumber(summary.hearts) or 0
  if gems <= 0 and hearts <= 0 then return "" end
  return "Gems " .. tostring(gems) .. " · Hearts " .. tostring(hearts)
end

function APOCLootPrio:IsMainSpecAward(drop)
  if not drop or not drop.award or not drop.award.winner or drop.award.winner == "" then return false end
  return self:GetAwardType(drop) == "MS"
end

function APOCLootPrio:GetGuildLootSummary()
  self:InitDB()

  if GuildRoster then GuildRoster() end

  local players = {}
  local function ensurePlayer(name, className, online, rankName, rankIndex, classFileName)
    name = ShortName(name or "")
    if name == "" then return nil end

    local playerKey = NormalizePlayerName(name)
    if playerKey == "" then return nil end

    players[playerKey] = players[playerKey] or {
      name = name,
      className = className or "",
      classFileName = classFileName or "",
      rankName = rankName or "",
      rankIndex = rankIndex,
      online = online and true or false,
      loot = {},
    }

    if className and className ~= "" then players[playerKey].className = className end
    if classFileName and classFileName ~= "" then players[playerKey].classFileName = classFileName end
    if rankName and rankName ~= "" then players[playerKey].rankName = rankName end
    if rankIndex ~= nil then players[playerKey].rankIndex = rankIndex end
    if online then players[playerKey].online = true end
    return players[playerKey]
  end

  if GetNumGuildMembers and GetGuildRosterInfo then
    for index = 1, GetNumGuildMembers() do
      local name, rankName, rankIndex, _, className, _, _, _, online, _, classFileName = GetGuildRosterInfo(index)
      local shortName = ShortName(name or "")
      if shortName ~= "" then
        ensurePlayer(name, className, online, rankName, rankIndex, classFileName)
      end
    end
  end

  for _, session in pairs(APOCLootPrioDB.loot.sessions or {}) do
    for _, drop in ipairs(session.drops or {}) do
      if self:IsMainSpecAward(drop) then
        local winner = ShortName(drop.award.winner or "")
        -- Saved Loot Tracker awards are the source of truth. Guild roster data
        -- enriches the row with class/rank, but a stale or incomplete roster
        -- must never hide a valid MS award.
        local player = ensurePlayer(winner)
        if player then
          table.insert(player.loot, {
            dropID = drop.id,
            itemID = drop.itemID,
            itemLink = drop.itemLink,
            itemQuality = drop.itemQuality,
            item = drop.item or "Unknown item",
            boss = drop.boss or "Unknown",
            raid = drop.raid or session.raid or "Loot",
            time = drop.award.awardedAt or drop.droppedAt or 0,
            droppedAt = drop.droppedAt or 0,
            awardedAt = drop.award.awardedAt or 0,
            winner = drop.award.winner or player.name,
            awardType = self:GetAwardType(drop),
            note = drop.award.note or "",
          })
        end
      end
    end
  end

  local list = {}
  for _, player in pairs(players) do
    table.sort(player.loot, function(a, b)
      local aTime = a.droppedAt or a.time or 0
      local bTime = b.droppedAt or b.time or 0
      if aTime ~= bTime then return aTime < bTime end
      local aSequence = tonumber(string.match(tostring(a.dropID or ""), ":drop:(%d+)$")) or 0
      local bSequence = tonumber(string.match(tostring(b.dropID or ""), ":drop:(%d+)$")) or 0
      if aSequence ~= bSequence then return aSequence < bSequence end
      return tostring(a.dropID or "") < tostring(b.dropID or "")
    end)
    player.count = #player.loot
    table.insert(list, player)
  end

  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)

  return list
end

function APOCLootPrio:PrintAuditLog(limit)
  self:InitDB()
  limit = tonumber(limit) or 10
  if #APOCLootPrioDB.audit == 0 then
    self:Print("Admin log is empty.")
    return
  end

  self:Print("Recent admin log:")
  for index = 1, math.min(limit, #APOCLootPrioDB.audit) do
    self:Print(self:DescribeAuditEntry(APOCLootPrioDB.audit[index], true))
  end
end

function APOCLootPrio:SetItemOverride(item, bias, note, source, revision)
  self:InitDB()
  local key = self:GetItemKey(item)
  if not key then return nil end

  local currentRevision = self:GetRevision()
  local nextRevision = tonumber(revision) or (currentRevision + 1)
  local old = APOCLootPrioDB.overrides[key]
  if old and old.revision and old.revision > nextRevision then return nil end

  APOCLootPrioDB.overrides[key] = {
    bias = bias or "",
    note = note or "",
    revision = nextRevision,
    updatedBy = source or (UnitName and UnitName("player")) or "Unknown",
    updatedAt = time and time() or 0,
  }

  self:SetRevision(nextRevision)
  return APOCLootPrioDB.overrides[key]
end

function APOCLootPrio:GetPlayerGuildRankIndex()
  if GetGuildInfo then
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex then return rankIndex end
  end

  if not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
  local playerName = UnitName and UnitName("player")
  if not playerName then return nil end

  for index = 1, GetNumGuildMembers() do
    local guildName, _, rankIndex = GetGuildRosterInfo(index)
    if ShortName(guildName) == playerName then return rankIndex end
  end

  return nil
end

function APOCLootPrio:GetGuildRankForName(name)
  local targetName = ShortName(name)
  if not targetName or targetName == "" then return nil, nil end

  local playerName = UnitName and UnitName("player") or nil
  if ShortName(playerName) == targetName then
    return self:GetPlayerGuildRankIndex(), self:GetGuildRankNameForIndex(self:GetPlayerGuildRankIndex())
  end

  if not GetNumGuildMembers or not GetGuildRosterInfo then return nil, nil end

  for index = 1, GetNumGuildMembers() do
    local guildName, rankName, rankIndex = GetGuildRosterInfo(index)
    if ShortName(guildName) == targetName then
      return rankIndex, rankName
    end
  end

  return nil, nil
end

function APOCLootPrio:CanNameRunLootTracker(name)
  if IsInGuild and not IsInGuild() then return true end
  local rankIndex = self:GetGuildRankForName(name)
  return rankIndex ~= nil and rankIndex <= self:GetFeatureAccessRank("lootTracker")
end

function APOCLootPrio:GetEligibleLootTrackerRunners()
  local runners = {}
  local seen = {}

  if GuildRoster then GuildRoster() end

  for _, memberName in ipairs(self:GetGroupRoster()) do
    local key = NormalizePlayerName(memberName)
    if key ~= "" and not seen[key] and self:CanNameRunLootTracker(memberName) then
      seen[key] = true
      local rankIndex, rankName = self:GetGuildRankForName(memberName)
      table.insert(runners, {
        name = memberName,
        rankIndex = rankIndex,
        rankName = rankName,
        isPlayer = self:IsLootTrackerOwner(memberName) or NormalizePlayerName(memberName) == NormalizePlayerName(self:GetPlayerDisplayName()),
      })
    end
  end

  table.sort(runners, function(a, b)
    local aPlayer = NormalizePlayerName(a.name) == NormalizePlayerName(self:GetPlayerDisplayName())
    local bPlayer = NormalizePlayerName(b.name) == NormalizePlayerName(self:GetPlayerDisplayName())
    if aPlayer ~= bPlayer then return aPlayer end
    local aRank = tonumber(a.rankIndex) or 99
    local bRank = tonumber(b.rankIndex) or 99
    if aRank ~= bRank then return aRank < bRank end
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  return runners
end

function APOCLootPrio:IsMasterLooter()
  local playerName = ShortName(UnitName and UnitName("player"))

  if self.detectedMasterLooter and self.detectedMasterLooter == playerName then
    return true
  end

  if not GetLootMethod then return false end

  local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()
  if lootMethod ~= "master" then return false end

  if masterLooterPartyID == 0 or masterLooterRaidID == 0 then return true end

  if type(masterLooterPartyID) == "string" and UnitIsUnit and UnitIsUnit(masterLooterPartyID, "player") then
    return true
  end

  if type(masterLooterRaidID) == "string" and UnitIsUnit and UnitIsUnit(masterLooterRaidID, "player") then
    return true
  end

  if masterLooterRaidID and GetRaidRosterInfo then
    local name = GetRaidRosterInfo(masterLooterRaidID)
    if ShortName(name) == playerName then return true end
  end

  if masterLooterPartyID and GetRaidRosterInfo then
    local name = GetRaidRosterInfo(masterLooterPartyID)
    if ShortName(name) == playerName then return true end
  end

  if masterLooterPartyID and UnitIsUnit and UnitIsUnit("party" .. tostring(masterLooterPartyID), "player") then
    return true
  end

  if IsPlayerInRaidGroup() then
    if UnitIsUnit then
      if masterLooterRaidID and UnitIsUnit("raid" .. tostring(masterLooterRaidID), "player") then return true end
      if masterLooterPartyID and UnitIsUnit("raid" .. tostring(masterLooterPartyID), "player") then return true end
      if masterLooterPartyID and UnitIsUnit("party" .. tostring(masterLooterPartyID), "player") then return true end
    end

    if GetRaidRosterInfo then
      if masterLooterRaidID then
        local name = GetRaidRosterInfo(masterLooterRaidID)
        if ShortName(name) == playerName then return true end
      end

      if masterLooterPartyID then
        local name = GetRaidRosterInfo(masterLooterPartyID)
        if ShortName(name) == playerName then return true end
      end
    end

    return false
  end

  if masterLooterPartyID and UnitIsUnit then
    if UnitIsUnit("party" .. tostring(masterLooterPartyID), "player") then return true end
  end

  if IsPlayerGroupLeaderOrAssistant() then return true end

  return false
end

function APOCLootPrio:GetLootMasterDisplayName()
  -- Prefer live GetLootMethod indices; detected system-message name is fallback.
  if GetLootMethod then
    local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()
    if lootMethod == "master" then
      if masterLooterPartyID == 0 or masterLooterRaidID == 0 then
        return self:GetPlayerDisplayName()
      end

      if masterLooterRaidID and GetRaidRosterInfo then
        local name = GetRaidRosterInfo(masterLooterRaidID)
        if name and name ~= "" then return ShortName(name) end
      end

      if masterLooterPartyID then
        if type(masterLooterPartyID) == "string" and UnitName then
          local name = UnitName(masterLooterPartyID)
          if name and name ~= "" then return ShortName(name) end
        elseif UnitName then
          local name = UnitName("party" .. tostring(masterLooterPartyID))
          if name and name ~= "" then return ShortName(name) end
        end
      end
    elseif lootMethod and lootMethod ~= "" then
      -- Known non-master method: do not stick on a stale detected ML.
      return nil
    end
  end

  if self.detectedMasterLooter and self.detectedMasterLooter ~= "" then
    return ShortName(self.detectedMasterLooter)
  end

  if self:IsMasterLooter() then
    return self:GetPlayerDisplayName()
  end

  return nil
end


-- Hard coupling (beta.24+): while loot method is master, Live Raid runner MUST
-- be the master looter. Auto-reassign on ML change; soft warning remains only
-- as brief fallback UI until the sync tick lands. beta.25 hides runner assign
-- controls under master loot (status line stays read-only).
function APOCLootPrio:IsLootMethodMaster()
  if GetLootMethod then
    local lootMethod = GetLootMethod()
    if lootMethod == "master" then return true end
    if lootMethod and lootMethod ~= "" then
      return false
    end
  end
  if self.detectedMasterLooter and self.detectedMasterLooter ~= "" then
    return true
  end
  return false
end

-- True when aligned OR when the rule does not apply (solo / not master loot /
-- missing names). Soft warning UI uses this as a brief fallback.
function APOCLootPrio:IsRunnerMasterLooterAligned()
  if not IsPlayerInRaidGroup() and not IsPlayerInPartyGroup() then
    return true
  end
  if not self:IsLootMethodMaster() then
    return true
  end

  local runner = self:GetLootSyncAuthorityName()
  local ml = self:GetLootMasterDisplayName()
  if not runner or runner == "" or not ml or ml == "" then
    return true
  end

  return NormalizePlayerName(runner) == NormalizePlayerName(ml)
end

function APOCLootPrio:GetRunnerMasterLooterWarningText()
  if self:IsRunnerMasterLooterAligned() then return nil end
  local runner = ShortName(self:GetLootSyncAuthorityName()) or "?"
  local ml = ShortName(self:GetLootMasterDisplayName()) or "?"
  return "Runner follows master looter (now: " .. tostring(runner) .. " / ML: " .. tostring(ml) .. ")"
end

-- Redirect any attempted non-ML runner name to the current ML while master loot
-- is active. Returns mlName, redirected(bool).
function APOCLootPrio:ResolveRunnerNameForMasterLoot(name)
  local clean = name and string.match(name, "^%s*(.-)%s*$") or ""
  if not self:IsLootMethodMaster() then
    return clean ~= "" and clean or nil, false
  end
  if not IsPlayerInRaidGroup() and not IsPlayerInPartyGroup() then
    return clean ~= "" and clean or nil, false
  end
  local ml = self:GetLootMasterDisplayName()
  if not ml or ml == "" then
    return clean ~= "" and clean or nil, false
  end
  if clean == "" then
    return ml, true
  end
  if NormalizePlayerName(clean) == NormalizePlayerName(ml) then
    return ml, false
  end
  return ml, true
end

function APOCLootPrio:ScheduleEnsureRunnerFollowsMasterLooter(delay, reason)
  delay = tonumber(delay) or 0.5
  self._runnerMlFollowPendingReason = reason or self._runnerMlFollowPendingReason or "scheduled"
  if self._runnerMlFollowScheduled then return end
  self._runnerMlFollowScheduled = true
  local function run()
    self._runnerMlFollowScheduled = false
    local why = self._runnerMlFollowPendingReason or "scheduled"
    self._runnerMlFollowPendingReason = nil
    if self.EnsureRunnerFollowsMasterLooter then
      self:EnsureRunnerFollowsMasterLooter(why)
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, run)
  else
    run()
  end
end

-- Auto-sync Live Raid runner to current master looter. Debounced: only when ML
-- name changes or runner is misaligned. Watch-only clients never assign.
function APOCLootPrio:EnsureRunnerFollowsMasterLooter(reason)
  if self._runnerMlFollowInProgress then return false end
  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() then return false end
  if not IsPlayerInRaidGroup() and not IsPlayerInPartyGroup() then
    self._runnerMlFollowSynced = nil
    return false
  end
  if not self:IsLootMethodMaster() then
    self._runnerMlFollowSynced = nil
    return false
  end

  local ml = self:GetLootMasterDisplayName()
  if not ml or ml == "" then return false end

  local mlKey = NormalizePlayerName(ml)
  local authority = self:GetLootSyncAuthorityName()
  local authorityKey = NormalizePlayerName(authority or "")
  if authorityKey ~= "" and authorityKey == mlKey then
    self._runnerMlFollowSynced = mlKey
    return false
  end

  -- Debounce: same ML already targeted and still misaligned only retries after
  -- a short gap so roster storms do not spam HR4/AS4.
  local now = time and time() or 0
  if self._runnerMlFollowSynced == mlKey then
    local lastAt = tonumber(self._runnerMlFollowLastAttemptAt) or 0
    if now > 0 and (now - lastAt) < 3 then
      return false
    end
  end

  if self.CanAssignMultiRunRunner and not self:CanAssignMultiRunRunner() then
    return false
  end

  self._runnerMlFollowInProgress = true
  self._runnerMlFollowSynced = mlKey
  self._runnerMlFollowLastAttemptAt = now
  local setBy = "ml-follow"
  if reason and reason ~= "" then setBy = "ml-follow:" .. tostring(reason) end
  local ok, err = true, nil
  if pcall then
    ok, err = pcall(function()
      self:SetLootTrackerOwner(ml, setBy)
    end)
  else
    self:SetLootTrackerOwner(ml, setBy)
  end
  self._runnerMlFollowInProgress = false

  if not ok then
    if self.Print then self:Print("Runner ML follow failed: " .. tostring(err)) end
    return false
  end

  local lastPrint = tonumber(self._runnerMlFollowLastPrintAt) or 0
  if self.Print and (now <= 0 or (now - lastPrint) >= 5) then
    self._runnerMlFollowLastPrintAt = now
    self:Print("Runner follows master looter (" .. tostring(ShortName(ml) or ml) .. ").")
  end
  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshLootTrackerSettingsPanel then self:RefreshLootTrackerSettingsPanel() end
  return true
end

function APOCLootPrio:GetGroupLeaderDisplayName()
  if IsPlayerInRaidGroup() and GetRaidRosterInfo then
    local count = GetNumGroupMembers and GetNumGroupMembers() or (GetNumRaidMembers and GetNumRaidMembers() or 0)
    for index = 1, count do
      local name, rank = GetRaidRosterInfo(index)
      if name and rank == 2 then return name end
    end
  end

  if UnitIsGroupLeader and UnitName then
    if UnitIsGroupLeader("player") then return self:GetPlayerDisplayName() end
    for index = 1, 4 do
      local unit = "party" .. tostring(index)
      if UnitExists and UnitExists(unit) and UnitIsGroupLeader(unit) then
        return UnitName(unit)
      end
    end
  end

  return nil
end

function APOCLootPrio:GetLootSyncAuthorityName()
  local owner = self:GetLootTrackerOwner()
  if owner and owner ~= "" then return owner end

  local lootMaster = self:GetLootMasterDisplayName()
  if lootMaster and lootMaster ~= "" then return lootMaster end

  local leader = self:GetGroupLeaderDisplayName()
  if leader and leader ~= "" then return leader end

  if not IsPlayerInRaidGroup() and not IsPlayerInPartyGroup() then
    return self:GetPlayerDisplayName()
  end

  return nil
end

function APOCLootPrio:IsLocalLootSyncAuthority()
  local authority = self:GetLootSyncAuthorityName()
  return NormalizePlayerName(authority) ~= "" and NormalizePlayerName(authority) == NormalizePlayerName(self:GetPlayerDisplayName())
end

function APOCLootPrio:IsOfficer()
  if IsInGuild and not IsInGuild() then return false end
  if CanEditOfficerNote and CanEditOfficerNote() then return true end

  local rankIndex = self:GetPlayerGuildRankIndex()
  return rankIndex ~= nil and rankIndex <= (APOCLootPrioDB.sync.maxRankIndex or DEFAULT_LEADER_RANK_INDEX)
end

function APOCLootPrio:CanViewLootPrio()
  return true
end

function APOCLootPrio:CanManageSettings()
  if IsInGuild and not IsInGuild() then return true end
  local rankIndex = self:GetPlayerGuildRankIndex()
  return rankIndex ~= nil and rankIndex <= DEFAULT_SETTINGS_RANK_INDEX
end

function APOCLootPrio:GetFeatureAccessRank(feature)
  self:InitDB()
  return tonumber(APOCLootPrioDB.access[feature]) or DEFAULT_FEATURE_ACCESS[feature] or DEFAULT_LEADER_RANK_INDEX
end

function APOCLootPrio:SetFeatureAccessRank(feature, rankIndex)
  if not self:CanManageSettings() then
    return false, "Only the top two guild ranks can change APOC settings."
  end

  if not DEFAULT_FEATURE_ACCESS[feature] then
    return false, "Unknown setting."
  end

  rankIndex = tonumber(rankIndex) or DEFAULT_FEATURE_ACCESS[feature]
  if rankIndex < 0 then rankIndex = 0 end
  if rankIndex > 9 then rankIndex = 9 end

  self:InitDB()
  APOCLootPrioDB.access[feature] = rankIndex
  return true
end

function APOCLootPrio:GetGuildRankNameForIndex(rankIndex)
  rankIndex = tonumber(rankIndex)
  if not rankIndex then return nil end

  if GuildControlGetRankName then
    local rankName = GuildControlGetRankName(rankIndex + 1)
    if rankName and rankName ~= "" then return rankName end
  end

  if GetNumGuildMembers and GetGuildRosterInfo then
    for index = 1, GetNumGuildMembers() do
      local _, rankName, memberRankIndex = GetGuildRosterInfo(index)
      if memberRankIndex == rankIndex and rankName and rankName ~= "" then
        return rankName
      end
    end
  end

  return nil
end

function APOCLootPrio:FormatFeatureAccessRank(feature)
  local rankIndex = self:GetFeatureAccessRank(feature)
  local rankName = self:GetGuildRankNameForIndex(rankIndex)
  if rankName then return "Rank " .. tostring(rankIndex) .. " - " .. rankName end
  return "Rank " .. tostring(rankIndex)
end

function APOCLootPrio:GetFeatureLabel(feature)
  local labels = {
    admin = "Admin",
    log = "Log",
    lootTracker = "Loot Tracker",
    lootTrackerView = "Loot Tracker View Only",
    lootSessionDelete = "Session Del Button",
    guildLoot = "Guild Loot",
  }
  return labels[feature] or tostring(feature or "Feature")
end

function APOCLootPrio:CanViewFeature(feature)
  if IsInGuild and not IsInGuild() then return true end
  local rankIndex = self:GetPlayerGuildRankIndex()
  return rankIndex ~= nil and rankIndex <= self:GetFeatureAccessRank(feature)
end

function APOCLootPrio:PrintAccessDebug()
  self:InitDB()

  local playerRank = self:GetPlayerGuildRankIndex()
  local playerRankName = playerRank ~= nil and self:GetGuildRankNameForIndex(playerRank) or nil
  self:Print("Your guild rank index: " .. tostring(playerRank or "unknown") .. (playerRankName and (" - " .. playerRankName) or ""))

  if GetLootMethod then
    local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()
    self:Print("Loot method: " .. tostring(lootMethod) .. ", party ML: " .. tostring(masterLooterPartyID) .. ", raid ML: " .. tostring(masterLooterRaidID) .. ", you are ML: " .. tostring(self:IsMasterLooter()))
    self:Print("Leader/assistant fallback: " .. tostring(IsPlayerGroupLeaderOrAssistant()))
  else
    self:Print("Loot method API unavailable. Detected ML: " .. tostring(self.detectedMasterLooter or "none") .. " from " .. tostring(self.detectedMasterLooterSource or "n/a") .. ", you are ML: " .. tostring(self:IsMasterLooter()))
  end

  for _, feature in ipairs({"admin", "log", "lootTracker", "lootTrackerView", "lootSessionDelete", "guildLoot"}) do
    local allowed = self:CanViewFeature(feature)
    self:Print(self:GetFeatureLabel(feature) .. ": requires " .. self:FormatFeatureAccessRank(feature) .. " - " .. (allowed and "shown" or "hidden"))
  end
end

function APOCLootPrio:CanViewOfficerControls()
  return self:CanViewFeature("admin")
    or self:CanViewFeature("log")
    or self:CanViewLootTracker()
    or self:CanViewFeature("guildLoot")
    or self:CanManageSettings()
end

function APOCLootPrio:CanViewLootTracker()
  return self:CanEditLootTracker() or self:CanViewFeature("lootTrackerView") or self:IsLootTrackerOwner()
end

function APOCLootPrio:CanEditLootTracker()
  local eligible = self:CanManageSettings() or self:CanViewFeature("lootTracker") or self:IsLootTrackerOwner()
  if not eligible then return false end
  if IsPlayerInRaidGroup() or IsPlayerInPartyGroup() then
    -- Live raid control belongs to the actual WoW Master Looter. The old
    -- assignable runner field is retained only for history/compatibility.
    return self.IsMasterLooter and self:IsMasterLooter() or false
  end
  return true
end

function APOCLootPrio:CanDeleteLootSessions()
  local allowedByRank = self:CanManageSettings() or self:CanViewFeature("lootSessionDelete")
  if not allowedByRank then return false end
  if IsPlayerInRaidGroup() or IsPlayerInPartyGroup() then
    return self.IsMasterLooter and self:IsMasterLooter() or false
  end
  return true
end

function APOCLootPrio:RequireLootSessionDelete()
  if self:CanDeleteLootSessions() then return true end
  if self.UpdateRaidLootStatus then
    self:UpdateRaidLootStatus("You cannot delete saved sessions at your guild rank.")
  else
    self:Print("You cannot delete saved sessions at your guild rank.")
  end
  return false
end

function APOCLootPrio:GetLootTrackerAccessText()
  if self:CanEditLootTracker() then
    return "Master Looter mode: full loot tracker controls enabled."
  end
  if self:CanViewLootTracker() then
    return "Viewer mode: only the Master Looter can change live loot data."
  end
  return "Loot tracker is not available for your guild rank."
end

function APOCLootPrio:RequireLootTrackerEdit()
  if self:CanEditLootTracker() then return true end
  if self.UpdateRaidLootStatus then
    self:UpdateRaidLootStatus("Only the Master Looter can change live loot tracker data.")
  else
    self:Print("Only the Master Looter can change live loot tracker data.")
  end
  return false
end

function APOCLootPrio:CanEditPriorities()
  self:InitDB()
  if IsInGuild and not IsInGuild() then return true end
  if CanEditOfficerNote and CanEditOfficerNote() then return true end

  local rankIndex = self:GetPlayerGuildRankIndex()
  return rankIndex ~= nil and rankIndex <= (APOCLootPrioDB.sync.maxRankIndex or DEFAULT_LEADER_RANK_INDEX)
end

function APOCLootPrio:GetCachedItemLink(item)
  if not item then return nil end
  if item.link and string.sub(item.link, 1, 1) == "|" then return item.link end

  local id = self:GetItemID(item)
  if id and GetItemInfo then
    local _, link = GetItemInfo(id)
    if link then return link end
  end

  if item.name and GetItemInfo then
    local _, link = GetItemInfo(item.name)
    if link then return link end
  end

  return nil
end

function APOCLootPrio:GetItemQuality(item)
  if not item then return nil end
  if item.quality ~= nil then return tonumber(item.quality) end
  if item.itemQuality ~= nil then return tonumber(item.itemQuality) end

  local link = item.link
  if link and GetItemInfo then
    local _, _, quality = GetItemInfo(link)
    if quality ~= nil then return tonumber(quality) end
  end

  local id = self:GetItemID(item)
  if id and GetItemInfo then
    local _, _, quality = GetItemInfo(id)
    if quality ~= nil then return tonumber(quality) end
  end

  if item.name and GetItemInfo then
    local _, _, quality = GetItemInfo(item.name)
    if quality ~= nil then return tonumber(quality) end
  end

  return nil
end

function APOCLootPrio:GetTooltipItemRef(item)
  if not item then return nil end
  return self:GetCachedItemLink(item) or item.link or (self:GetItemID(item) and ("item:" .. tostring(self:GetItemID(item))))
end

local function Trim(text)
  return string.match(text or "", "^%s*(.-)%s*$")
end

function APOCLootPrio:Find(query)
  query = string.lower(query or "")
  local results = {}
  for raid, bosses in pairs(APOCLootPrioData) do
    for _, boss in ipairs(bosses) do
      for _, item in ipairs(boss.items) do
        if query == "" or string.find(string.lower(item.name), query, 1, true) then
          table.insert(results, {raid=raid, boss=boss.boss, item=item})
        end
      end
    end
  end
  table.sort(results, function(a,b) return a.item.name < b.item.name end)
  return results
end

SLASH_APOCLOOTBETABIAS1 = "/priobeta"
SlashCmdList.APOCLOOTBETABIAS = function(msg)
  msg = Trim(msg)
  if msg == "" then APOCLootPrio:Toggle(); return end

  local command = string.lower(msg)
  if command == "mini" or command == "minimap" then
    if APOCLootPrio.ToggleMinimapButton then
      APOCLootPrio:ToggleMinimapButton()
    else
      APOCLootPrio:Print("Minimap button is not loaded.")
    end
    return
  end

  if command == "trackerminimap" or command == "lootminimap" then
    if APOCLootPrio.ToggleTrackerMinimapButton then
      APOCLootPrio:ToggleTrackerMinimapButton()
    else
      APOCLootPrio:Print("Loot Tracker minimap button is not loaded.")
    end
    return
  end

  if command == "admin" then
    if APOCLootPrio.ToggleAdminMode then
      APOCLootPrio:ToggleAdminMode()
    else
      APOCLootPrio:Print("Admin UI is not loaded.")
    end
    return
  end

  if command == "sync" then
    if APOCLootPrio.RequestSync then
      APOCLootPrio:RequestSync()
      APOCLootPrio:Print("Sync request sent. Current revision: " .. APOCLootPrio:GetRevision())
    else
      APOCLootPrio:Print("Sync is not loaded.")
    end
    return
  end

  if command == "syncstatus" or command == "syncdebug" then
    if APOCLootPrio.PrintHardenedSyncStatus then
      APOCLootPrio:PrintHardenedSyncStatus()
    else
      APOCLootPrio:Print("Hardened sync diagnostics are not loaded.")
    end
    return
  end

  if command == "access" or command == "settings" then
    if APOCLootPrio.PrintAccessDebug then
      APOCLootPrio:PrintAccessDebug()
    end
    if command == "settings" and APOCLootPrio.ToggleSettingsPanel then
      APOCLootPrio:ToggleSettingsPanel()
    end
    return
  end

  if command == "ml" or command == "masterlooter" then
    APOCLootPrio:SetDetectedMasterLooter(UnitName and UnitName("player") or APOCLootPrio:GetPlayerDisplayName(), "manual")
    APOCLootPrio:Print("Manual loot-master override set for this character.")
    return
  end

  if command == "log" or command == "audit" then
    APOCLootPrio:PrintAuditLog(10)
    return
  end

  if command == "loot" or command == "raidloot" then
    if APOCLootPrio.ToggleRaidLootPanel then
      APOCLootPrio:ToggleRaidLootPanel()
    else
      APOCLootPrio:Print("Raid loot UI is not loaded.")
    end
    return
  end

  if command == "guild" or command == "guildloot" or command == "roster" then
    if APOCLootPrio.ToggleGuildLootPanel then
      APOCLootPrio:ToggleGuildLootPanel()
    else
      APOCLootPrio:Print("Guild loot UI is not loaded.")
    end
    return
  end

  local rankValue = string.match(command, "^rank%s+(%d+)$")
  if rankValue then
    if APOCLootPrio.SetSyncMaxRankIndex then
      APOCLootPrio:SetSyncMaxRankIndex(tonumber(rankValue))
    else
      APOCLootPrio:InitDB()
      APOCLootPrioDB.sync.maxRankIndex = tonumber(rankValue)
    end
    APOCLootPrio:Print("Leadership sync accepts guild rank index " .. tostring(APOCLootPrioDB.sync.maxRankIndex) .. " and above. 0 is guild master.")
    return
  end

  local results = APOCLootPrio:Find(msg)
  if #results == 0 then APOCLootPrio:Print("No item found for: " .. msg); return end
  local r = results[1]
  APOCLootPrio:Print((APOCLootPrio:GetCachedItemLink(r.item) or r.item.name) .. " - " .. (APOCLootPrio:GetItemBias(r.item) or "") .. " (" .. r.raid .. ", " .. r.boss .. ")")
end

local events = CreateFrame("Frame")
local function RegisterEventSafely(eventName)
  if pcall then
    pcall(function() events:RegisterEvent(eventName) end)
  else
    events:RegisterEvent(eventName)
  end
end

RegisterEventSafely("ADDON_LOADED")
RegisterEventSafely("PLAYER_ENTERING_WORLD")
RegisterEventSafely("ZONE_CHANGED_NEW_AREA")
RegisterEventSafely("PLAYER_GUILD_UPDATE")
RegisterEventSafely("GUILD_ROSTER_UPDATE")
RegisterEventSafely("LOOT_OPENED")
RegisterEventSafely("LOOT_READY")
RegisterEventSafely("LOOT_CLOSED")
RegisterEventSafely("LOOT_SLOT_CHANGED")
RegisterEventSafely("CHAT_MSG_LOOT")
RegisterEventSafely("CHAT_MSG_SYSTEM")
RegisterEventSafely("TRADE_SHOW")
RegisterEventSafely("TRADE_PLAYER_ITEM_CHANGED")
RegisterEventSafely("TRADE_ACCEPT_UPDATE")
RegisterEventSafely("TRADE_CLOSED")
RegisterEventSafely("GROUP_ROSTER_UPDATE")
RegisterEventSafely("RAID_ROSTER_UPDATE")
RegisterEventSafely("PARTY_MEMBERS_CHANGED")
RegisterEventSafely("PARTY_LOOT_METHOD_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end
    APOCLootPrio:InitDB()
    if GuildRoster then GuildRoster() end
    if APOCLootPrio.RegisterSync then APOCLootPrio:RegisterSync() end
    if APOCLootPrio.CreateMinimapButton then APOCLootPrio:CreateMinimapButton() end
    if APOCLootPrio.CreateTrackerMinimapButton then APOCLootPrio:CreateTrackerMinimapButton() end
    if APOCLootPrio.RestoreMinimapButtonForBuild then APOCLootPrio:RestoreMinimapButtonForBuild() end
    if APOCLootPrio.CreateUI then
      local ok, err = nil, nil
      if pcall then
        ok, err = pcall(function() APOCLootPrio:CreateUI() end)
      else
        APOCLootPrio:CreateUI()
        ok = true
      end
      if not ok and APOCLootPrio.Print then
        APOCLootPrio:Print("UI load error: " .. tostring(err))
      end
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
    if GuildRoster then GuildRoster() end
    if event == "PLAYER_ENTERING_WORLD" and APOCLootPrio.RestoreMinimapButtonForBuild then
      APOCLootPrio:RestoreMinimapButtonForBuild()
    end
    if APOCLootPrio.RefreshOfficerControls then APOCLootPrio:RefreshOfficerControls() end
    if APOCLootPrio.RefreshSettingsPanel then APOCLootPrio:RefreshSettingsPanel() end
    if APOCLootPrio.RefreshGuildLootPanel then APOCLootPrio:RefreshGuildLootPanel() end
    if event == "PLAYER_ENTERING_WORLD" and APOCLootPrio.ScheduleInstanceSessionPromptCheck then
      APOCLootPrio:ScheduleInstanceSessionPromptCheck(1)
    end
    if event == "PLAYER_ENTERING_WORLD" and APOCLootPrio.ScheduleRaidAttendanceUpdate then
      APOCLootPrio:ScheduleRaidAttendanceUpdate(2, true)
    end
    return
  end

  if event == "ZONE_CHANGED_NEW_AREA" then
    if APOCLootPrio.ScheduleInstanceSessionPromptCheck then
      APOCLootPrio:ScheduleInstanceSessionPromptCheck(1)
    end
    return
  end

  if event == "LOOT_CLOSED" then
    APOCLootPrio.lootWindowActive = false
    return
  end

  if event == "LOOT_OPENED" or event == "LOOT_READY" or event == "LOOT_SLOT_CHANGED" then
    if not APOCLootPrio.lootWindowActive then
      APOCLootPrio.lootWindowActive = true
      APOCLootPrio.lootWindowSerial = (APOCLootPrio.lootWindowSerial or 0) + 1
      APOCLootPrio.lootWindowSlotCaptures = {}
    end
    if APOCLootPrio.ScanOpenLootForRaidDrops then
      APOCLootPrio:ScanOpenLootForRaidDrops()
    end
    return
  end

  if event == "CHAT_MSG_LOOT" then
    local message = ...
    if APOCLootPrio.ScanLootChatForRaidDrop then
      APOCLootPrio:ScanLootChatForRaidDrop(message)
    end
    return
  end

  if event == "CHAT_MSG_SYSTEM" then
    local message = ...
    if APOCLootPrio.HandleSystemLootMessage then
      APOCLootPrio:HandleSystemLootMessage(message)
    end
    return
  end

  if event == "TRADE_SHOW" then
    if APOCLootPrio.HandleTradeShow then APOCLootPrio:HandleTradeShow() end
    return
  end

  if event == "TRADE_PLAYER_ITEM_CHANGED" then
    if APOCLootPrio.HandleTradePlayerItemChanged then APOCLootPrio:HandleTradePlayerItemChanged() end
    return
  end

  if event == "TRADE_ACCEPT_UPDATE" then
    if APOCLootPrio.HandleTradeAcceptUpdate then APOCLootPrio:HandleTradeAcceptUpdate(...) end
    return
  end

  if event == "TRADE_CLOSED" then
    if APOCLootPrio.HandleTradeClosed then APOCLootPrio:HandleTradeClosed() end
    return
  end

  if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LOOT_METHOD_CHANGED" then
    if APOCLootPrio.RefreshGroupMemberList then
      APOCLootPrio:RefreshGroupMemberList()
    end
    if APOCLootPrio.ScheduleInstanceSessionPromptCheck then
      APOCLootPrio:ScheduleInstanceSessionPromptCheck(1)
    end
    if APOCLootPrio.ScheduleRaidAttendanceUpdate then
      APOCLootPrio:ScheduleRaidAttendanceUpdate(1, true)
    end
    if APOCLootPrio.ScheduleEnsureRunnerFollowsMasterLooter then
      local why = event == "PARTY_LOOT_METHOD_CHANGED" and "loot-method" or "roster"
      APOCLootPrio:ScheduleEnsureRunnerFollowsMasterLooter(0.5, why)
    end
  end
end)
