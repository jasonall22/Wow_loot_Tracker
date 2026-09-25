local B = APOCLiveBridge
local owningAddon = ... or 'APOCLiveBridge'
local frame = CreateFrame('Frame','APOCLiveBridgeStrip',UIParent)
frame:SetFrameStrata('TOOLTIP')
frame:EnableMouse(false)
frame:Hide()
local textures, packets, index, elapsed, sequence = {},nil,1,0,0
local previousContent, refreshedAt = nil,0
local rosterRequestedAt = 0
local layoutReady = false
local boot = ((time and time() or 0)+(GetTime and math.floor(GetTime()*1000) or 0))%4294967296
local function announce(message)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffedc16fAPOC Live Bridge:|r '..message) end
end
local function layout()
  local db = APOCLiveBridgeDB
  local _, physicalHeight = GetPhysicalScreenSize()
  local parentScale = UIParent:GetEffectiveScale()
  layoutReady = false
  if not physicalHeight or physicalHeight <= 0 or not parentScale or parentScale <= 0 then
    frame:Hide()
    return false
  end
  -- WoW's UI coordinate space is 768 units high, not physicalHeight pixels.
  -- Match Blizzard's PixelUtil factor, then cancel only this frame's parent scale.
  -- Do not alter UIParent, ElvUI, the tracker, or the player's global UI scale.
  frame:SetScale((768 / physicalHeight) / parentScale)
  frame:ClearAllPoints()
  frame:SetPoint('TOPLEFT',UIParent,'TOPLEFT',db.x,-db.y)
  frame:SetSize(64*db.cell,8*db.cell)
  for i = 1,512 do
    local texture = textures[i] or frame:CreateTexture(nil,'OVERLAY')
    textures[i] = texture
    texture:ClearAllPoints()
    texture:SetPoint('TOPLEFT',frame,'TOPLEFT',((i-1)%64)*db.cell,-math.floor((i-1)/64)*db.cell)
    texture:SetSize(db.cell,db.cell)
    texture:SetColorTexture(0,0,0,1)
  end
  layoutReady = true
  return true
end
local function refreshLayout()
  packets=nil
  if layout() and APOCLiveBridgeDB.enabled then frame:Show() else frame:Hide() end
end
local function context()
  local player = UnitName('player') or ''
  return {player=player,realm=GetRealmName() or '',faction=UnitFactionGroup('player') or '',
    guild=GetGuildInfo('player') or ('Unguilded: '..player),now=time()}
end
local function nextSnapshot()
  local now=time()
  local ok, snapshot = pcall(function()
    local resolver = nil
    if APOCLootPrio and APOCLootPrio.GetLootBrowserPriorityForDrop then
      resolver = function(drop,session) return APOCLootPrio:GetLootBrowserPriorityForDrop(drop,session) end
    end
    return B.Snapshot(APOCLootTrackerBetaDB,context(),resolver)
  end)
  if not ok then snapshot={v=1,idle='Cannot read this tracker snapshot. See bridge status.'} end
  if not snapshot.guildRoster and now-rosterRequestedAt>=30 then
    rosterRequestedAt=now
    B.RequestGuildRoster()
  end
  snapshot.sampledAt=0
  local encoded, content=pcall(B.JSON,snapshot)
  if not encoded then snapshot={v=1,idle='Unsupported tracker data.'};content=B.JSON(snapshot) end
  -- A very large guild roster must never block the raid itself from syncing.
  -- Omit only the optional roster when the fixed strip protocol cannot carry both.
  if #content > 65500 and snapshot.guildRoster then
    snapshot.guildRoster=nil
    content=B.JSON(snapshot)
  end
  -- Replay the SAME sequence so a missed fragment can arrive on the next pass.
  -- Never interrupt a partial pass; new state replaces it at the cycle boundary.
  if packets and content==previousContent and now-refreshedAt<10 then index=1;return end
  previousContent=content;refreshedAt=now
  snapshot.sampledAt=now
  local payload=B.JSON(snapshot)
  if #payload > 65536 then payload=B.JSON({v=1,idle='Selected raid exceeds the 64 KiB prototype limit.'}) end
  sequence = (sequence+1)%4294967296
  packets = B.Frames(payload,boot,sequence)
  index = 1
end
frame:SetScript('OnUpdate',function(_,delta)
  if not layoutReady then return end
  elapsed = elapsed+delta
  if elapsed < 0.15 then return end
  elapsed = 0
  if not packets or index > #packets then nextSnapshot() end
  local pixels = B.Colors(packets[index])
  for i,color in ipairs(pixels) do textures[i]:SetColorTexture(color[1]/255,color[2]/255,color[3]/255,1) end
  index = index+1
end)
local events = CreateFrame('Frame')
events:RegisterEvent('ADDON_LOADED')
events:RegisterEvent('UI_SCALE_CHANGED')
events:RegisterEvent('DISPLAY_SIZE_CHANGED')
events:RegisterEvent('PLAYER_LOGIN')
events:RegisterEvent('PLAYER_ENTERING_WORLD')
events:RegisterEvent('GUILD_ROSTER_UPDATE')
events:SetScript('OnEvent',function(_,event,name)
  if event=='ADDON_LOADED' and name~=owningAddon then return end
  if event=='GUILD_ROSTER_UPDATE' then packets=nil;return end
  if event=='ADDON_LOADED' then
    APOCLiveBridgeDB = APOCLiveBridgeDB or {enabled=false,x=0,y=0,cell=3}
    local db=APOCLiveBridgeDB
    db.x=math.max(0,math.floor(tonumber(db.x) or 0));db.y=math.max(0,math.floor(tonumber(db.y) or 0))
    db.cell=math.max(2,math.min(8,math.floor(tonumber(db.cell) or 3)))
    -- Migrate only the old untouched default; preserve explicitly chosen positions.
    if not db.pixelLayoutVersion then
      if db.x==20 and db.y==80 then db.x=0;db.y=0 end
      db.pixelLayoutVersion=1
    end
  end
  if event=='PLAYER_LOGIN' or event=='PLAYER_ENTERING_WORLD' then
    rosterRequestedAt=time()
    B.RequestGuildRoster()
  end
  if APOCLiveBridgeDB then refreshLayout() end
end)
SLASH_APOCLIVEBRIDGE1='/apocbridge'
SlashCmdList.APOCLIVEBRIDGE=function(message)
  local command,a,b=string.match(message or '', '^(%S*)%s*(%-?%d*)%s*(%-?%d*)')
  command=string.lower(command or '')
  local db=APOCLiveBridgeDB
  if not db then announce('Still loading.');return end
  if command=='on' then
    db.enabled=true;refreshLayout()
    if layoutReady then announce('Strip enabled: '..(64*db.cell)..' x '..(8*db.cell)..' physical pixels, top-left '..db.x..','..db.y..'. This does not confirm companion capture or upload.')
    else announce('Waiting for valid display dimensions. The strip will retry on login/display changes.') end
  elseif command=='off' then db.enabled=false;frame:Hide();announce('Strip disabled.')
  elseif command=='pos' and tonumber(a) and tonumber(b) and tonumber(a)>=0 and tonumber(b)>=0 then
    db.x=math.floor(tonumber(a));db.y=math.floor(tonumber(b));refreshLayout()
  elseif command=='size' and tonumber(a) and tonumber(a)>=2 and tonumber(a)<=8 then
    db.cell=math.floor(tonumber(a));refreshLayout()
  elseif command=='roster' then
    local ok,roster=pcall(B.GuildRoster,context())
    if ok and roster then
      packets=nil
      announce('Complete guild roster ready: '..#roster.members..' members. The next strip snapshot will include it.')
    else
      local count=type(GetNumGuildMembers)=='function' and tonumber((GetNumGuildMembers())) or 0
      rosterRequestedAt=time()
      B.RequestGuildRoster()
      announce('Guild roster refresh requested (WoW currently reports '..(count or 0)..' entries). Wait a few seconds and try /apocbridge roster again.')
    end
  else
    announce('Prototype 0.1.3 | '..(db.enabled and 'On' or 'Off')..' | position '..db.x..','..db.y..' | cell '..db.cell..' physical px | '..(64*db.cell)..' x '..(8*db.cell)..' px. Commands: on, off, pos X Y, size 2-8, roster.')
    announce('Reads only the selected session owned by this character. No game inputs, tracker changes, or upload acknowledgement.')
  end
end
