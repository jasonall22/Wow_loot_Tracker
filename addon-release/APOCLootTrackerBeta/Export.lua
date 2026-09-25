-- Manual fallback for a runner who does not use APOC Live Bridge.
-- WoW writes this one encoded value into APOCLootTrackerBeta.lua on /reload/logout.
local arrayTag = {}
local function Array(value) return setmetatable(value or {}, arrayTag) end
local function Text(value) return tostring(value or "") end
local function Number(value) return math.floor(tonumber(value) or 0) end
local function Short(value) return string.lower(string.match(Text(value), "^[^-]+") or "") end
local function AwardType(award)
  local value = string.upper(Text(award.awardType))
  if value == "MS" or value == "OS" or value == "DE" or value == "GB" then return value end
  if value == "OFFSPEC" or value == "OFF SPEC" then return "OS" end
  if value == "DISENCHANT" then return "DE" end
  if value ~= "" then return "UNKNOWN" end
  local note = string.lower(Text(award.note))
  if string.find(note, "disenchant", 1, true) or string.find(" " .. note .. " ", " de ", 1, true) then return "DE" end
  if string.find(note, "off spec", 1, true) or string.find(note, "offspec", 1, true)
    or string.find(" " .. note .. " ", " os ", 1, true) then return "OS" end
  return "MS"
end
local function RollRecord(roll)
  if type(roll) ~= "table" or Number(roll.startedAt) < 1 or Number(roll.endsAt) < 1 then return nil end
  local entries = Array()
  for _, entry in ipairs(roll.entries or {}) do
    if #entries >= 80 then break end
    local kind = string.upper(Text(entry.rollType or entry.type))
    if kind == "NEED" then kind = "MS" elseif kind == "GREED" then kind = "OS" end
    local value, name = Number(entry.roll), Text(entry.name)
    if name ~= "" and value >= 1 and value <= 100 and (kind == "MS" or kind == "OS") then
      entries[#entries + 1] = { name = name, roll = value, type = kind }
    end
  end
  return { startedAt = Number(roll.startedAt), endsAt = Number(roll.endsAt), closed = roll.closed == true,
    copyCount = math.max(1, math.min(40, Number(roll.copyCount))), entries = entries }
end
local function EscapeJSON(value)
  return '"' .. string.gsub(value, '[%z\1-\31\\"]', function(character)
    if character == '"' then return '\\"' end
    if character == '\\' then return '\\\\' end
    return string.format('\\u%04x', string.byte(character))
  end) .. '"'
end
local function JSON(value)
  local kind = type(value)
  if kind == "string" then return EscapeJSON(value) end
  if kind == "number" then return tostring(value) end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "nil" then return "null" end
  if kind ~= "table" then error("Unsupported export value") end
  local parts = {}
  if getmetatable(value) == arrayTag then
    for _, entry in ipairs(value) do parts[#parts + 1] = JSON(entry) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" then error("Invalid export field") end
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do parts[#parts + 1] = EscapeJSON(key) .. ":" .. JSON(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Base64(value)
  local parts = {}
  for index = 1, #value, 3 do
    local a, b, c = string.byte(value, index, index + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    parts[#parts + 1] = string.sub(alphabet, math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
      .. string.sub(alphabet, math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
      .. (b and string.sub(alphabet, math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "=")
      .. (c and string.sub(alphabet, n % 64 + 1, n % 64 + 1) or "=")
  end
  return table.concat(parts)
end

local function CurrentGuildRoster()
  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then return nil end
  -- Keep only the total-member return value; the API also returns online counts.
  local count = tonumber((GetNumGuildMembers())) or 0
  if count < 1 or count > 1000 then return nil end
  local roster, seen, hasPlayer = Array(), {}, false
  local player = Short(UnitName("player"))
  for index = 1, count do
    local name, rankName, rankIndex, _, className, _, _, _, _, _, classFileName = GetGuildRosterInfo(index)
    name = Text(name)
    local key = string.lower(name)
    if name ~= "" and not seen[key] then
      seen[key] = true
      if Short(name) == player then hasPlayer = true end
      roster[#roster + 1] = { name = name, class = Text(classFileName or className),
        rankName = Text(rankName), rankIndex = Number(rankIndex) }
    end
  end
  if not hasPlayer or #roster ~= count then return nil end
  table.sort(roster, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  return { members = roster }
end

function APOCLootPrio:ExportSelectedLootSession()
  self:InitDB()
  if not self:CanEditLootTracker() then return nil, "Only the Master Looter can export the active session." end
  local session = self:GetActiveHistorySession()
  if not session or not session.key or session.readOnly then return nil, "Select a saved or active raid session first." end
  local guild = GetGuildInfo("player")
  if not guild or guild == "" then return nil, "You must be in a guild to export a raid." end
  local run = APOCLootPrioDB.multiRun and APOCLootPrioDB.multiRun.runs and APOCLootPrioDB.multiRun.runs[session.runID]
  local raids, drops, members = Array(), Array(), Array()
  for raid in pairs(session.instances or {}) do raids[#raids + 1] = Text(raid) end
  table.sort(raids)
  local dropsByID = {}
  for _, candidate in ipairs(session.drops or {}) do dropsByID[Text(candidate.id)] = candidate end
  for _, drop in ipairs(session.drops or {}) do
    local record = { id = Text(drop.id), item = Text(drop.item), itemID = Number(drop.itemID),
      boss = Text(drop.boss), at = Number(drop.droppedAt) }
    local priority, priorityNote = self:GetLootBrowserPriorityForDrop(drop, session)
    record.priority = Text(priority)
    record.priorityNote = Text(priorityNote)
    local rollSource = dropsByID[Text(drop.rollSourceDropID)] or drop
    record.roll = RollRecord(rollSource.roll)
    if drop.award and ((drop.award.winner and drop.award.winner ~= "") or AwardType(drop.award) == "GB") then
      record.award = { winner = Text(drop.award.winner), type = AwardType(drop.award),
        at = Number(drop.award.awardedAt), note = Text(drop.award.note) }
    end
    drops[#drops + 1] = record
  end
  for _, member in pairs(session.attendance and session.attendance.members or {}) do
    local visits = Array()
    for _, visit in ipairs(member.visits or {}) do visits[#visits + 1] = Array({Number(visit.joinedAt), Number(visit.leftAt)}) end
    members[#members + 1] = { name = Text(member.name), class = Text(member.classFileName or member.className),
      group = Number(member.subgroup), present = member.present == true, visits = visits }
  end
  table.sort(members, function(a, b) return a.name < b.name end)
  local snapshot = { format = "apoc-loot-tracker-export-v1", guild = guild, realm = Text(GetRealmName()),
    faction = Text(UnitFactionGroup("player")), sender = Text(UnitName("player")), sampledAt = time(),
    session = { id = Text(session.key), run = Text(session.runID or session.key), name = Text(session.name or session.raid),
      runner = Text((self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName()) or run and run.owner or session.syncAuthority or session.createdBy),
      revision = Number(session.revision), createdAt = Number(session.createdAt), closedAt = Number(session.closedAt),
      closed = session.finalized == true or Number(session.closedAt) > 0, raids = raids },
    drops = drops, members = members }
  local guildRoster = CurrentGuildRoster()
  if not guildRoster then
    local refresh = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
    if type(refresh) == "function" then pcall(refresh) end
    return nil, "Guild roster is refreshing. Wait a few seconds, then click Export again."
  end
  snapshot.guildRoster = guildRoster
  local ok, encoded = pcall(JSON, snapshot)
  if not ok or #encoded > 750000 then return nil, "Raid export is too large or contains unsupported data." end
  APOCLootTrackerBetaExport = Base64(encoded)
  return true, "Export prepared for " .. snapshot.session.name .. ". Type /reload, then upload WTF/Account/<account>/SavedVariables/APOCLootTrackerBeta.lua on the website."
end
