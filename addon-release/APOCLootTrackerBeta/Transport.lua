local PREFIX = "APOCLPMR" -- Module: Transport.lua
local events
local outboundQueue = {}
local outboundFrame
local outboundElapsed, outboundClock, outboundDelay = 0, 0, 0.05
local OUTBOUND_BYTES_PER_SECOND = 900
local OUTBOUND_MAX_QUEUE = 600
local OUTBOUND_MAX_AGE = 180

local function ShortName(name)
  return string.match(name or "", "^([^%-]+)") or name
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

local function SplitMessage(message)
  local parts = {}
  for part in string.gmatch((message or "") .. "\t", "(.-)\t") do
    table.insert(parts, part)
  end
  return parts
end

local function Diagnostic(name, amount)
  if not APOCLootPrioDB or not APOCLootPrioDB.sync then return end
  local diagnostics = APOCLootPrioDB.sync.diagnostics or {}
  APOCLootPrioDB.sync.diagnostics = diagnostics
  diagnostics[name] = (tonumber(diagnostics[name]) or 0) + (tonumber(amount) or 1)
end

local function SendAddonMessageNow(message, channel, target)
  if not channel or type(message) ~= "string" or #message > 255 then return false end
  local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
  if not send then return false end
  local ok, result = pcall(send, PREFIX, message, channel, target)
  if not ok or result == false then return false end
  if type(result) == "number" and Enum and Enum.SendAddonMessageResult then
    return result == Enum.SendAddonMessageResult.Success
  end
  return true
end

local function EnsureOutboundQueue()
  if outboundFrame or not CreateFrame then return end
  outboundFrame = CreateFrame("Frame")
  outboundFrame:SetScript("OnUpdate", function(_, elapsed)
    outboundClock = outboundClock + (elapsed or 0)
    outboundElapsed = outboundElapsed + (elapsed or 0)
    if outboundElapsed < outboundDelay then return end
    outboundElapsed = 0

    local record = outboundQueue[1]
    if not record then return end
    if record.nextAt and outboundClock < record.nextAt then
      outboundDelay = math.max(0.05, record.nextAt - outboundClock)
      return
    end

    local sent = SendAddonMessageNow(record.message, record.channel, record.target)
    if sent then
      table.remove(outboundQueue, 1)
      Diagnostic("nativeMessagesSent")
      outboundDelay = math.max(0.05, (#record.message + 40) / OUTBOUND_BYTES_PER_SECOND)
      return
    end

    record.failures = (record.failures or 0) + 1
    Diagnostic("nativeMessageRetries")
    if outboundClock - (record.startedAt or outboundClock) >= OUTBOUND_MAX_AGE then
      table.remove(outboundQueue, 1)
      Diagnostic("nativeMessagesDropped")
      outboundDelay = 0.05
      return
    end
    local backoff = math.min(4, 0.25 * (2 ^ math.min(record.failures - 1, 4)))
    record.nextAt = outboundClock + backoff
    outboundDelay = backoff
  end)
end

local function SendAddonMessageCompat(message, channel, target)
  if not channel or type(message) ~= "string" or #message > 255 then return false end
  EnsureOutboundQueue()
  if not outboundFrame then return SendAddonMessageNow(message, channel, target) end
  if #outboundQueue >= OUTBOUND_MAX_QUEUE then
    table.remove(outboundQueue, 1)
    Diagnostic("nativeMessagesDropped")
  end
  table.insert(outboundQueue, {message=message, channel=channel, target=target, startedAt=outboundClock})
  Diagnostic("nativeMessagesQueued")
  return true
end

function APOCLootPrio:GetNativeCommsStatus()
  return #outboundQueue, outboundClock, OUTBOUND_BYTES_PER_SECOND
end

function APOCLootPrio:SendProtocolMessage(message, channel, target)
  return SendAddonMessageCompat(message, channel, target)
end

local function RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
  end
end

local function GetSyncChannel()
  APOCLootPrio:InitDB()
  if not IsInGuild or not IsInGuild() then return nil end
  return APOCLootPrioDB.sync.channel or "GUILD"
end







function APOCLootPrio:IsTrustedSender(sender)
  if not sender then return false end
  if ShortName(sender) == (UnitName and UnitName("player")) then return true end
  if not IsInGuild or not IsInGuild() then return false end
  if not GetNumGuildMembers or not GetGuildRosterInfo then return false end

  local maxRankIndex = APOCLootPrioDB and APOCLootPrioDB.sync and APOCLootPrioDB.sync.maxRankIndex or 1
  local senderShort = ShortName(sender)

  for index = 1, GetNumGuildMembers() do
    local guildName, _, rankIndex = GetGuildRosterInfo(index)
    if ShortName(guildName) == senderShort then
      return rankIndex ~= nil and rankIndex <= maxRankIndex
    end
  end

  return false
end

function APOCLootPrio:IsGuildSyncSender(sender)
  if not sender then return false end
  if ShortName(sender) == (UnitName and UnitName("player")) then return true end
  if self.IsCurrentGroupMember and self:IsCurrentGroupMember(sender) then return true end
  if not IsInGuild or not IsInGuild() then return false end
  if not GetNumGuildMembers or not GetGuildRosterInfo then return false end

  local senderShort = ShortName(sender)
  for index = 1, GetNumGuildMembers() do
    local guildName = GetGuildRosterInfo(index)
    if ShortName(guildName) == senderShort then
      return true
    end
  end

  return false
end

function APOCLootPrio:IsLootTrackerSyncSender(sender)
  if self:IsTrustedSender(sender) then return true end
  if self:IsGuildSyncSender(sender) then return true end

  local senderShort = ShortName(sender)
  local senderKey = string.lower(tostring(senderShort or ""))
  if senderKey == "" then return false end

  local owner = self.GetLootTrackerOwner and self:GetLootTrackerOwner() or nil
  if owner and owner ~= "" and string.lower(tostring(ShortName(owner))) == senderKey then
    return true
  end

  local lootMaster = self.GetLootMasterDisplayName and self:GetLootMasterDisplayName() or nil
  if lootMaster and lootMaster ~= "" and string.lower(tostring(ShortName(lootMaster))) == senderKey then
    return true
  end

  if self.GetGuildRankForName and self.GetFeatureAccessRank then
    local rankIndex = self:GetGuildRankForName(senderShort)
    local lootTrackerRank = self:GetFeatureAccessRank("lootTracker")
    if rankIndex ~= nil and lootTrackerRank ~= nil and rankIndex <= lootTrackerRank then
      return true
    end
  end

  return false
end

function APOCLootPrio:SendSyncMessage(message, target)
  local channel = target and "WHISPER" or GetSyncChannel()
  if not channel then return false end
  return SendAddonMessageCompat(message, channel, target and ShortName(target) or nil)
end



function APOCLootPrio:BroadcastAuditEntry(entry)
  if not entry then return end

  local message = table.concat({
    "A",
    Escape(entry.id or ""),
    tostring(entry.time or 0),
    Escape(entry.actor or ""),
    entry.changed and "1" or "0",
    tostring(entry.revision or 0),
    entry.key or "",
    Escape(entry.item or ""),
  }, "\t")

  self:SendSyncMessage(message)
end



















local function GetClientVersion()
  if APOCLootPrio.GetAddonVersion then
    return APOCLootPrio:GetAddonVersion()
  end
  return "unknown"
end

function APOCLootPrio:SendClientVersion(target)
  self:SendSyncMessage("V\t" .. Escape(GetClientVersion()), target)
end





function APOCLootPrio:ApplyIncomingAudit(id, timestamp, actor, changedFlag, revision, key, itemName, sender)
  self:InitDB()

  local cleanID = Unescape(id)
  if cleanID == "" then return end

  local cleanActor = Unescape(actor)
  if cleanActor == "" then cleanActor = sender or "Unknown" end

  local entry = self:AddAuditEntry({
    id = cleanID,
    time = tonumber(timestamp) or (time and time() or 0),
    actor = cleanActor,
    action = changedFlag == "1" and "changed" or "nochange",
    changed = changedFlag == "1",
    revision = tonumber(revision) or 0,
    key = key,
    item = Unescape(itemName),
    source = ShortName(sender),
  })

  if entry and self.RefreshAuditLog then self:RefreshAuditLog() end
end

function APOCLootPrio:ApplyIncomingAccessSettings(adminRank, logRank, lootTrackerRank, guildLootRank, lootSessionDeleteRank, autoTrackMode, lootTrackerViewRank, qualityMask, sender)
  self:InitDB()

  local changed = false
  local incoming = {
    admin = tonumber(adminRank),
    log = tonumber(logRank),
    lootTracker = tonumber(lootTrackerRank),
    lootTrackerView = tonumber(lootTrackerViewRank),
    guildLoot = tonumber(guildLootRank),
    lootSessionDelete = tonumber(lootSessionDeleteRank),
  }

  for feature, rankIndex in pairs(incoming) do
    if rankIndex ~= nil then
      if rankIndex < 0 then rankIndex = 0 end
      if rankIndex > 9 then rankIndex = 9 end
      if APOCLootPrioDB.access[feature] ~= rankIndex then
        APOCLootPrioDB.access[feature] = rankIndex
        changed = true
      end
    end
  end

  if autoTrackMode ~= nil and APOCLootPrioDB.loot then
    local incomingMode = string.lower(tostring(Unescape(autoTrackMode) or "raid"))
    if incomingMode ~= "solo" and incomingMode ~= "party" and incomingMode ~= "raid" and incomingMode ~= "off" then
      incomingMode = "raid"
    end
    if APOCLootPrioDB.loot.autoTrackMode ~= incomingMode then
      APOCLootPrioDB.loot.autoTrackMode = incomingMode
      changed = true
    end
  end

  if qualityMask ~= nil and self.ApplyLootQualitySettingsMask then
    if self:ApplyLootQualitySettingsMask(Unescape(qualityMask)) then changed = true end
  end

  if changed then
    self:AddAuditEntry((sender or "Unknown") .. " updated APOC feature access settings.")
  end

  if self.RefreshOfficerControls then self:RefreshOfficerControls() end
  if self.RefreshSettingsPanel then self:RefreshSettingsPanel() end
  if self.RefreshLootTrackerSettingsPanel then self:RefreshLootTrackerSettingsPanel() end
  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshLootSessionPicker then self:RefreshLootSessionPicker() end
  if self.RefreshAuditLog then self:RefreshAuditLog() end
end











function APOCLootPrio:HandleInfoSyncMessage(message, sender)
  local parts = SplitMessage(message)
  if parts[1] == "V" then
    if self:IsGuildSyncSender(sender) and self.RecordSyncPeer then
      self:RecordSyncPeer(sender, "Version", Unescape(parts[2]))
    end
  elseif parts[1] == "A" and self:IsTrustedSender(sender) then
    self:ApplyIncomingAudit(parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8], sender)
  end
end

function APOCLootPrio:RegisterSync()
  if events then return end
  RegisterPrefix()

  events = CreateFrame("Frame")
  events:RegisterEvent("CHAT_MSG_ADDON")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("GUILD_ROSTER_UPDATE")
  events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "PLAYER_ENTERING_WORLD" then
      if GuildRoster then GuildRoster() end
      APOCLootPrio:RequestSync()
      return
    end

    if event == "GUILD_ROSTER_UPDATE" then return end
    if prefix ~= PREFIX then return end
    APOCLootPrio:HandleSyncMessage(message, sender, channel)
  end)
end
