-- Independent protocol implementation. Never writes tracker tables or calls tracker methods.
APOCLiveBridge = APOCLiveBridge or {}
local B = APOCLiveBridge
local floor, char, byte = math.floor, string.char, string.byte
local arrayTag = {}
function B.Array(value) return setmetatable(value or {}, arrayTag) end
local function escape(value)
  return '"' .. string.gsub(value, '[%z\1-\31\\"]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', byte(c))
  end) .. '"'
end
local function json(value)
  local kind = type(value)
  if kind == 'string' then return escape(value) end
  if kind == 'number' then
    assert(value == value and value ~= math.huge and value ~= -math.huge, 'Invalid number')
    return tostring(value)
  end
  if kind == 'boolean' then return value and 'true' or 'false' end
  if kind == 'nil' then return 'null' end
  assert(kind == 'table', 'Unsupported JSON type')
  local result = {}
  if getmetatable(value) == arrayTag then
    for _, entry in ipairs(value) do result[#result+1] = json(entry) end
    return '[' .. table.concat(result, ',') .. ']'
  end
  local keys = {}
  for key in pairs(value) do assert(type(key) == 'string', 'Invalid object key'); keys[#keys+1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do result[#result+1] = escape(key) .. ':' .. json(value[key]) end
  return '{' .. table.concat(result, ',') .. '}'
end
B.JSON = json
function B.Adler(value)
  local a,b = 1,0
  for i = 1,#value do a = (a+byte(value,i))%65521; b = (b+a)%65521 end
  return b*65536+a
end
local function u32(n)
  return char(floor(n/16777216)%256,floor(n/65536)%256,floor(n/256)%256,n%256)
end
local function u16(n) return char(floor(n/256)%256,n%256) end
function B.Frames(payload, boot, sequence)
  assert(#payload > 0 and #payload <= 65536, 'Raid snapshot exceeds 64 KiB prototype limit')
  local count = math.ceil(#payload/360)
  local result = {}
  for part = 0,count-1 do
    local chunk = string.sub(payload, part*360+1, (part+1)*360)
    local body = 'APB1' .. u32(boot) .. u32(sequence) .. u16(part) .. u16(count) .. u16(#chunk) .. u16(0) .. chunk
    body = body .. string.rep(char(0),380-#body)
    result[#result+1] = body .. u32(B.Adler(body))
  end
  return result
end
function B.Colors(frame)
  local out = {}
  for i = 1,#frame,3 do
    local n = byte(frame,i)*65536+byte(frame,i+1)*256+byte(frame,i+2)
    for _, divisor in ipairs({262144,4096,64,1}) do
      local cell = floor(n/divisor)%64
      out[#out+1] = {32+floor(cell/16)*64,32+(floor(cell/4)%4)*64,32+(cell%4)*64}
    end
  end
  return out
end
local function plain(value) return tostring(value or '') end
local function num(value) return tonumber(value) or 0 end
local function short(value) return string.lower(string.match(plain(value),'^[^-]+') or '') end
function B.RequestGuildRoster()
  local modern = C_GuildInfo and C_GuildInfo.GuildRoster
  if type(modern) == 'function' then return pcall(modern) end
  if type(GuildRoster) == 'function' then return pcall(GuildRoster) end
  return false
end
local function currentGuildRoster(context)
  local status={api=false,count=0,valid=0,blank=0,duplicate=0,hasPlayer=false,complete=false}
  if type(GetNumGuildMembers) ~= 'function' or type(GetGuildRosterInfo) ~= 'function' then return nil,status end
  status.api=true
  -- Parenthesize the call so Lua keeps only its first return value. Otherwise
  -- the online-member count becomes tonumber's optional numeric base.
  local count = tonumber((GetNumGuildMembers())) or 0
  status.count=count
  if count < 1 or count > 1000 then return nil,status end
  local members,seen,hasPlayer = B.Array(),{},false
  for index = 1,count do
    local name,rankName,rankIndex,_,className,_,_,_,_,_,classFileName = GetGuildRosterInfo(index)
    name = plain(name)
    local key = string.lower(name)
    if name ~= '' and not seen[key] then
      seen[key] = true
      if short(name) == short(context.player) then hasPlayer = true end
      members[#members+1] = {name=name,class=plain(classFileName or className),rankName=plain(rankName),rankIndex=num(rankIndex)}
    elseif name == '' then
      status.blank=status.blank+1
    else
      status.duplicate=status.duplicate+1
    end
  end
  status.valid=#members
  status.hasPlayer=hasPlayer
  if not hasPlayer or #members ~= count then return nil,status end
  status.complete=true
  table.sort(members,function(a,b) return string.lower(a.name) < string.lower(b.name) end)
  return {members=members},status
end
function B.GuildRoster(context) return currentGuildRoster(context) end
local function awardType(award)
  local value = string.upper(plain(award.awardType))
  if value == 'MS' or value == 'OS' or value == 'DE' or value == 'GB' then return value end
  if value == 'OFFSPEC' or value == 'OFF SPEC' then return 'OS' end
  if value == 'DISENCHANT' then return 'DE' end
  if value ~= '' then return 'UNKNOWN' end
  -- Mirror beta.79's legacy display rule, not a new award classification.
  local note = string.lower(plain(award.note))
  if string.find(note,'disenchant',1,true) or string.find(' '..note..' ',' de ',1,true) then return 'DE' end
  if string.find(note,'off spec',1,true) or string.find(note,'offspec',1,true) or string.find(' '..note..' ',' os ',1,true) then return 'OS' end
  return 'MS'
end
local function rollRecord(roll)
  if type(roll) ~= 'table' or num(roll.startedAt) < 1 or num(roll.endsAt) < 1 then return nil end
  local entries = B.Array()
  for _, entry in ipairs(roll.entries or {}) do
    if #entries >= 80 then break end
    local kind = string.upper(plain(entry.rollType or entry.type))
    if kind == 'NEED' then kind = 'MS' elseif kind == 'GREED' then kind = 'OS' end
    local value = num(entry.roll)
    local name = plain(entry.name)
    if name ~= '' and value >= 1 and value <= 100 and (kind == 'MS' or kind == 'OS') then
      entries[#entries+1] = {name=name,roll=value,type=kind}
    end
  end
  return {startedAt=num(roll.startedAt),endsAt=num(roll.endsAt),closed=roll.closed==true,
    copyCount=math.max(1,math.min(40,num(roll.copyCount))),entries=entries}
end
function B.Snapshot(db, context, priorityResolver)
  if type(db) ~= 'table' or type(db.loot) ~= 'table' then return {v=1,idle='Tracker data is not ready.'} end
  local sessions = db.loot.sessions or {}
  local session = db.loot.activeSessionKey and sessions[db.loot.activeSessionKey]
  if not session then return {v=1,idle='No selected loot session in the tracker.'} end
  local run = db.multiRun and db.multiRun.runs and db.multiRun.runs[session.runID]
  local runner = (APOCLootPrio.GetLootSyncAuthorityName and APOCLootPrio:GetLootSyncAuthorityName()) or run and run.owner or session.syncAuthority or session.createdBy
  if short(runner) == '' or short(runner) ~= short(context.player) then
    return {v=1,idle='This character is not the current Master Looter. Use the Master Looter PC.'}
  end
  local raids,drops,members = B.Array(),B.Array(),B.Array()
  for raid in pairs(session.instances or {}) do raids[#raids+1] = plain(raid) end
  table.sort(raids)
  local dropsByID = {}
  for _, candidate in ipairs(session.drops or {}) do dropsByID[plain(candidate.id)] = candidate end
  for _, d in ipairs(session.drops or {}) do
    local drop = {id=plain(d.id),item=plain(d.item),itemID=num(d.itemID),boss=plain(d.boss),at=num(d.droppedAt)}
    local priority,priorityNote=d.bias,d.note
    if type(priorityResolver) == 'function' then
      local resolved,bias,note=pcall(priorityResolver,d,session)
      if resolved then priority,priorityNote=bias,note end
    end
    drop.priority=plain(priority)
    drop.priorityNote=plain(priorityNote)
    local rollSource = dropsByID[plain(d.rollSourceDropID)] or d
    drop.roll=rollRecord(rollSource.roll)
    if d.award and ((d.award.winner and d.award.winner ~= '') or awardType(d.award) == 'GB') then
      drop.award = {winner=plain(d.award.winner),type=awardType(d.award),at=num(d.award.awardedAt),note=plain(d.award.note)}
    end
    drops[#drops+1] = drop
  end
  for _, m in pairs(session.attendance and session.attendance.members or {}) do
    local visits = B.Array()
    for _, visit in ipairs(m.visits or {}) do visits[#visits+1] = B.Array({num(visit.joinedAt),num(visit.leftAt)}) end
    members[#members+1] = {name=plain(m.name),class=plain(m.classFileName or m.className),group=num(m.subgroup),present=m.present==true,visits=visits}
  end
  table.sort(members,function(a,b) return a.name < b.name end)
  local snapshot = {v=1,guild=context.guild,realm=context.realm,faction=context.faction,sender=context.player,sampledAt=context.now,
    session={id=plain(session.key or db.loot.activeSessionKey),run=plain(session.runID or session.key),name=plain(session.name or session.raid),runner=plain(runner),
      revision=num(session.revision),createdAt=num(session.createdAt),closedAt=num(session.closedAt),closed=session.finalized==true or num(session.closedAt)>0,raids=raids},
    drops=drops,members=members}
  -- Guild roster APIs can be temporarily unavailable while zoning or while
  -- Blizzard refreshes the roster. The roster is optional; never let that
  -- prevent the core raid snapshot from reaching the bridge.
  local rosterOK, guildRoster, rosterStatus = pcall(currentGuildRoster,context)
  if rosterOK and rosterStatus then snapshot.rosterStatus=rosterStatus end
  if rosterOK and guildRoster then snapshot.guildRoster = guildRoster end
  if not rosterOK then snapshot.rosterError=string.sub(plain(guildRoster),1,180) end
  return snapshot
end
