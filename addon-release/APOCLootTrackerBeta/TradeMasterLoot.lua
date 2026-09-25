-- APOC Loot Tracker — Trade award + Master Loot helpers (original clean-room).
-- Conceptual behavior only; no Gargul source, assets, strings, or layouts.

APOCLootPrio = APOCLootPrio or {}

local PreviousSaveRaidLootAward = APOCLootPrio.SaveRaidLootAward

local MAX_TRADE_SLOTS = 6
local MAX_HELPER_ROWS = 8

local function ShortName(name)
  return string.match(name or "", "^([^%-]+)") or name
end

local function NormalizePlayerName(name)
  local shortName = ShortName(name)
  if not shortName then return "" end
  return string.lower(shortName)
end

local function Trim(text)
  return string.match(tostring(text or ""), "^%s*(.-)%s*$") or ""
end

local function CanAwardNow()
  if not APOCLootPrio or not APOCLootPrio.CanEditLootTracker then return false end
  if APOCLootPrio.IsLiveRaidWatchOnly and APOCLootPrio:IsLiveRaidWatchOnly() then return false end
  return APOCLootPrio:IsLocalLootSyncV2Authority()
end

local function DropTime(drop)
  return tonumber(drop and drop.award and drop.award.awardedAt)
    or tonumber(drop and drop.droppedAt)
    or 0
end

local function IsAwarded(drop)
  return drop and drop.award and drop.award.winner and drop.award.winner ~= ""
end

local function IsTraded(drop)
  return IsAwarded(drop) and drop.award.tradedAt ~= nil
end

local function DropItemID(drop)
  return tonumber(drop and drop.itemID)
end

local function RollHighName(drop)
  if not drop then return nil end
  if drop.roll and drop.roll.highName and drop.roll.highName ~= "" then
    return drop.roll.highName
  end
  if APOCLootPrio.GetLootRollWinningEntry then
    local entry = APOCLootPrio:GetLootRollWinningEntry(drop)
    if entry and entry.name and entry.name ~= "" then return entry.name end
  end
  return nil
end

local function SamePlayer(a, b)
  local ak, bk = NormalizePlayerName(a), NormalizePlayerName(b)
  return ak ~= "" and ak == bk
end

---------------------------------------------------------------------------
-- Bag / trade placement helpers (Classic Anniversary 20505 compatible)
---------------------------------------------------------------------------

local function BagNumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
  return 0
end

local function BagItemLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then
    return C_Container.GetContainerItemLink(bag, slot)
  end
  if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
  return nil
end

local function PickupBagItem(bag, slot)
  if C_Container and C_Container.PickupContainerItem then
    C_Container.PickupContainerItem(bag, slot)
    return true
  end
  if PickupContainerItem then
    PickupContainerItem(bag, slot)
    return true
  end
  return false
end

local function FindBagSlotForItemID(itemID, skipUsed)
  itemID = tonumber(itemID)
  if not itemID then return nil, nil end
  skipUsed = skipUsed or {}
  local maxBag = (NUM_BAG_SLOTS and NUM_BAG_SLOTS) or 4
  for bag = 0, maxBag do
    local slots = BagNumSlots(bag)
    for slot = 1, slots do
      local key = tostring(bag) .. ":" .. tostring(slot)
      if not skipUsed[key] then
        local link = BagItemLink(bag, slot)
        local id = APOCLootPrio.GetItemIDFromLink and APOCLootPrio:GetItemIDFromLink(link)
        if tonumber(id) == itemID then
          return bag, slot
        end
      end
    end
  end
  return nil, nil
end

local function EmptyTradeSlot()
  if not GetTradePlayerItemLink then return nil end
  for index = 1, MAX_TRADE_SLOTS do
    if not GetTradePlayerItemLink(index) then return index end
  end
  return nil
end

local function PlaceItemIDInTrade(itemID, usedBags)
  local tradeSlot = EmptyTradeSlot()
  if not tradeSlot then return false, "Trade window is full." end
  local bag, slot = FindBagSlotForItemID(itemID, usedBags)
  if not bag then return false, "Item not found in bags." end
  if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
  if not PickupBagItem(bag, slot) then return false, "Could not pick up item." end
  if ClickTradeButton then
    ClickTradeButton(tradeSlot)
  elseif TradeFrame and _G["TradePlayerItem" .. tradeSlot .. "ItemButton"] then
    local button = _G["TradePlayerItem" .. tradeSlot .. "ItemButton"]
    if button and button.Click then button:Click() end
  else
    if ClearCursor then ClearCursor() end
    return false, "Trade slot click unavailable."
  end
  if usedBags then usedBags[tostring(bag) .. ":" .. tostring(slot)] = true end
  return true
end

---------------------------------------------------------------------------
-- Group unit / master-loot candidate lookup
---------------------------------------------------------------------------

local function FindGroupUnitByName(playerName)
  local targetKey = NormalizePlayerName(playerName)
  if targetKey == "" then return nil end

  local function matchUnit(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return nil end
    local name = APOCLootPrio.GetUnitDisplayName and APOCLootPrio:GetUnitDisplayName(unit)
    if SamePlayer(name, playerName) then return unit end
    if UnitName and SamePlayer(UnitName(unit), playerName) then return unit end
    return nil
  end

  local found = matchUnit("player")
  if found then return found end

  local raidSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  if raidSize == 0 and GetNumRaidMembers then raidSize = GetNumRaidMembers() end
  if (IsInRaid and IsInRaid()) or (raidSize and raidSize > 5) then
    for index = 1, raidSize do
      found = matchUnit("raid" .. tostring(index))
      if found then return found end
    end
  end

  local partySize = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
  if partySize == 0 and GetNumPartyMembers then partySize = GetNumPartyMembers() end
  for index = 1, math.max(partySize, 4) do
    found = matchUnit("party" .. tostring(index))
    if found then return found end
  end

  if UnitExists and UnitExists("target") and SamePlayer(UnitName and UnitName("target"), playerName) then
    return "target"
  end
  return nil
end

local function FindMasterLootCandidateIndex(playerName, slot)
  if not GetMasterLootCandidate then return nil end
  local targetKey = NormalizePlayerName(playerName)
  if targetKey == "" then return nil end

  -- Classic Anniversary uses GetMasterLootCandidate(slot, index). Some clients
  -- also expose a one-arg form; probe both. Candidate count APIs similarly vary.
  local count = 0
  if GetNumMasterLootCandidates then
    if slot ~= nil then
      local ok, result = pcall(function() return GetNumMasterLootCandidates(slot) end)
      if ok and type(result) == "number" and result > 0 then count = result end
    end
    if count == 0 then
      local ok, result = pcall(function() return GetNumMasterLootCandidates() end)
      if ok and type(result) == "number" and result > 0 then count = result end
    end
  end
  if count == 0 then count = 40 end

  for index = 1, count do
    local candidate = nil
    if slot ~= nil then
      local ok, result = pcall(function() return GetMasterLootCandidate(slot, index) end)
      if ok and result then candidate = result end
    end
    if not candidate then
      local ok, result = pcall(function() return GetMasterLootCandidate(index) end)
      if ok and result then candidate = result end
    end
    if candidate and SamePlayer(candidate, playerName) then return index end
  end
  return nil
end

---------------------------------------------------------------------------
-- Drop matching (conservative)
---------------------------------------------------------------------------

local function IterSessionDrops(callback)
  APOCLootPrio:InitDB()
  local sessions = APOCLootPrioDB and APOCLootPrioDB.loot and APOCLootPrioDB.loot.sessions or {}
  for _, session in pairs(sessions) do
    if not session.finalized and not session.archived and session.runID == APOCLootPrio:GetActiveRunID()
      and APOCLootPrio:CanEditLootSession(session) then
      for _, drop in ipairs(session.drops or {}) do
        callback(drop, session)
      end
    end
  end
end

-- Returns candidate rows for a trade partner + optional item ID filter.
-- Each row: {drop, session, kind, score, intendedWinner}
-- kind: "awarded-untraded" | "selected" | "roll-high" | "unawarded"
function APOCLootPrio:FindTradeAwardCandidates(tradeTarget, itemIDFilter)
  local candidates = {}
  if not CanAwardNow() then return candidates end

  local targetKey = NormalizePlayerName(tradeTarget)
  local filterID = tonumber(itemIDFilter)
  local selectedID = self.selectedLootDropID
  local overlaySelected = self.tradeAwardSelectedDropIDs or {}

  IterSessionDrops(function(drop, session)
    local id = DropItemID(drop)
    if filterID and id ~= filterID then return end
    if not id or overlaySelected[drop.id] == false then return end

    local intended = nil
    local kind = nil
    local score = 0

    if IsAwarded(drop) and not IsTraded(drop) and SamePlayer(drop.award.winner, tradeTarget) then
      intended = drop.award.winner
      kind = "awarded-untraded"
      score = 400 + DropTime(drop) / 1e10
    elseif not IsAwarded(drop) then
      local high = RollHighName(drop)
      if selectedID and drop.id == selectedID then
        intended = (targetKey ~= "" and tradeTarget) or high or tradeTarget
        kind = "selected"
        score = 350 + DropTime(drop) / 1e10
      elseif overlaySelected[drop.id] then
        intended = tradeTarget
        kind = "selected"
        score = 340 + DropTime(drop) / 1e10
      elseif high and SamePlayer(high, tradeTarget) then
        intended = high
        kind = "roll-high"
        score = 300 + DropTime(drop) / 1e10
      end
    end

    if kind then
      table.insert(candidates, {
        drop = drop,
        session = session,
        kind = kind,
        score = score,
        intendedWinner = intended or tradeTarget,
        itemID = id,
      })
    end
  end)

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return tostring(a.drop.id) > tostring(b.drop.id)
  end)

  return candidates
end

-- Match each trade item to at most one drop (prefer selected / newest / awarded).
function APOCLootPrio:MatchTradeItemsToDrops(tradeTarget, tradeItems)
  local used, matches = {}, {}
  for _, item in ipairs(tradeItems or {}) do
    local candidates = self:FindTradeAwardCandidates(tradeTarget, tonumber(item.itemID))
    local remaining = math.max(1, math.min(1000, tonumber(item.quantity) or 1))
    for _, candidate in ipairs(candidates) do
      if remaining <= 0 then break end
      if not used[candidate.drop.id] then
        used[candidate.drop.id] = true
        remaining = remaining - 1
        table.insert(matches, {item=item, drop=candidate.drop, session=candidate.session,
          kind=candidate.kind, intendedWinner=tradeTarget})
      end
    end
  end
  return matches
end

function APOCLootPrio:GetPendingAwardsForPlayer(playerName)
  local rows = {}
  if not CanAwardNow() then return rows end
  local targetKey = NormalizePlayerName(playerName)
  if targetKey == "" then return rows end

  IterSessionDrops(function(drop, session)
    if IsAwarded(drop) and not IsTraded(drop) and SamePlayer(drop.award.winner, playerName) then
      table.insert(rows, {drop = drop, session = session, kind = "awarded-untraded"})
    elseif not IsAwarded(drop) then
      local high = RollHighName(drop)
      if high and SamePlayer(high, playerName) then
        table.insert(rows, {drop = drop, session = session, kind = "roll-high"})
      elseif self.selectedLootDropID and drop.id == self.selectedLootDropID then
        table.insert(rows, {drop = drop, session = session, kind = "selected"})
      end
    end
  end)

  table.sort(rows, function(a, b)
    return DropTime(a.drop) > DropTime(b.drop)
  end)
  return rows
end

---------------------------------------------------------------------------
-- Award + mark traded
---------------------------------------------------------------------------

function APOCLootPrio:AwardAndMarkTradeDrop(dropID, winner, note, awardType)
  if not CanAwardNow() then return nil, "Watch-only or insufficient permissions." end
  local drop, session = self:FindRaidLootDrop(dropID)
  if not drop or not session or session.finalized or session.archived
    or not self:CanEditLootSession(session) then return nil, "Drop is not in an editable live session." end
  if IsTraded(drop) then return nil, "Drop already delivered." end

  if not IsAwarded(drop) then
    drop, note = self:AwardRaidLootDrop(dropID, winner, note or "", awardType or "MS")
    if not drop then return nil, note or "Award failed." end
  elseif winner and winner ~= "" and not SamePlayer(drop.award.winner, winner) then
    return nil, "Drop already awarded to someone else."
  end

  drop.award = drop.award or {}
  drop.award.tradedTo = winner or drop.award.winner
  drop.award.tradedAt = time and time() or 0
  drop.award.tradedBy = self:GetPlayerDisplayName()
  if session then
    self:TouchLootSession(session)
    drop.syncRevision = session.revision
    if self.BroadcastLootDropUpdate then
      self:BroadcastLootDropUpdate(session, drop)
    elseif self.BroadcastLootSession then
      self:BroadcastLootSession(session)
    end
  end

  if self.RefreshRaidLootPanel then self:RefreshRaidLootPanel() end
  if self.RefreshGuildLootPanel then self:RefreshGuildLootPanel() end
  if self.RefreshRecentAwardsPanel then self:RefreshRecentAwardsPanel() end
  return drop
end

-- One allocation pass for BOTH existing awards and newly selected awards.
-- Runtime callers commit a frozen match list only after ERR_TRADE_COMPLETE.
function APOCLootPrio:ProcessAcceptedTradeAwards(tradeTarget, tradeItems, frozenMatches)
  if not CanAwardNow() or not tradeTarget or tradeTarget == "" then return 0 end
  local matches = frozenMatches or self:MatchTradeItemsToDrops(tradeTarget, tradeItems)
  local count = 0
  for _, match in ipairs(matches) do
    local current, session = self:FindRaidLootDrop(match.drop.id)
    if current == match.drop and session == match.session then
      local kind = current.award and current.award.awardType
        or (current.roll and current.roll.highType == "GREED" and "OS" or "MS")
      if self:AwardAndMarkTradeDrop(current.id, tradeTarget, "Confirmed trade", kind) then count = count + 1 end
    end
  end
  return count
end

function APOCLootPrio:AutoPlacePendingAwardsInTrade(tradeTarget)
  if not CanAwardNow() then return 0 end
  if not tradeTarget or tradeTarget == "" then return 0 end

  local pending = self:GetPendingAwardsForPlayer(tradeTarget)
  local placed = 0
  local usedBags = {}
  local missing = {}

  for _, row in ipairs(pending) do
    if row.kind == "awarded-untraded" or row.kind == "roll-high" or row.kind == "selected" then
      local itemID = DropItemID(row.drop)
      if itemID and EmptyTradeSlot() then
        local ok, err = PlaceItemIDInTrade(itemID, usedBags)
        if ok then
          placed = placed + 1
          self.tradeAwardSelectedDropIDs = self.tradeAwardSelectedDropIDs or {}
          self.tradeAwardSelectedDropIDs[row.drop.id] = true
        else
          table.insert(missing, {drop = row.drop, err = err})
        end
      end
    end
    if placed >= MAX_TRADE_SLOTS then break end
  end

  if #missing > 0 and self.Print then
    local drop = missing[1].drop
    self:Print(
      "Could not auto-place "
        .. tostring(drop.item or "item")
        .. " for "
        .. tostring(tradeTarget)
        .. (missing[1].err and (": " .. missing[1].err) or ".")
    )
  end

  return placed
end

---------------------------------------------------------------------------
-- Optional InitiateTrade after award + whisper on failure
---------------------------------------------------------------------------

function APOCLootPrio:TryInitiateTradeWithWinner(winner, drop)
  if not CanAwardNow() then return false end
  winner = Trim(winner)
  if winner == "" or string.lower(winner) == "disenchant" then return false end

  local unit = FindGroupUnitByName(winner)
  local itemLabel = (drop and (drop.itemLink or drop.item)) or "loot"

  if unit and InitiateTrade then
    local inRange = true
    if CheckInteractDistance then
      -- 2 = trade distance
      inRange = CheckInteractDistance(unit, 2)
    end
    if inRange then
      local ok = pcall(function() InitiateTrade(unit) end)
      if ok then
        if self.UpdateRaidLootStatus then
          self:UpdateRaidLootStatus("Opening trade with " .. tostring(ShortName(winner)) .. " for " .. tostring(drop and drop.item or "loot") .. ".")
        end
        return true
      end
    end
  end

  -- Whisper fallback when trade cannot start.
  if SendChatMessage and winner ~= "" then
    local msg = "APOC Loot Tracker: please trade me for " .. tostring(itemLabel) .. "."
    pcall(function()
      SendChatMessage(msg, "WHISPER", nil, ShortName(winner))
    end)
    if self.Print then
      self:Print("Whispered " .. tostring(ShortName(winner)) .. " to trade for " .. tostring(drop and drop.item or "loot") .. ".")
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Trade overlay UI (original layout — not a Gargul clone)
---------------------------------------------------------------------------

local function EnsureTradeHelperFont(parent, size, text)
  local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if STANDARD_TEXT_FONT and f.SetFont then
    f:SetFont(STANDARD_TEXT_FONT, size or 11, "")
  end
  f:SetText(text or "")
  return f
end

function APOCLootPrio:HideTradeAwardHelper()
  if self.tradeAwardHelperFrame then
    self.tradeAwardHelperFrame:Hide()
  end
  self.tradeAwardSelectedDropIDs = nil
end

function APOCLootPrio:RefreshTradeAwardHelper()
  if not CanAwardNow() then
    self:HideTradeAwardHelper()
    return
  end
  if not TradeFrame or not TradeFrame:IsShown() then
    self:HideTradeAwardHelper()
    return
  end

  local target = self:GetTradeTargetDisplayName()
  local items = self:CaptureTradePlayerItems()
  local pending = self:GetPendingAwardsForPlayer(target)
  local matches = self:MatchTradeItemsToDrops(target, items)

  -- Merge unique drops for display.
  local rows = {}
  local seen = {}
  local function addRow(drop, session, kind, intended)
    if not drop or seen[drop.id] then return end
    seen[drop.id] = true
    table.insert(rows, {
      drop = drop,
      session = session,
      kind = kind,
      intendedWinner = intended or target,
    })
  end
  for _, match in ipairs(matches) do
    addRow(match.drop, match.session, match.kind, match.intendedWinner)
  end
  for _, row in ipairs(pending) do
    addRow(row.drop, row.session, row.kind, target)
  end

  if #rows == 0 then
    -- Still show a thin status when trading so the runner knows the helper is active.
    rows = {}
  end

  local frame = self.tradeAwardHelperFrame
  if not frame then
    frame = CreateFrame("Frame", "APOCLootTradeAwardHelper", UIParent, BackdropTemplate and "BackdropTemplate" or nil)
    frame:SetSize(260, 140)
    frame:SetFrameStrata("DIALOG")
    if frame.SetBackdrop then
      frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
      })
      frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
      frame:SetBackdropBorderColor(0.75, 0.62, 0.28, 1)
    else
      local bg = frame:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(frame)
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.05, 0.05, 0.08, 0.92)
    end
    frame.title = EnsureTradeHelperFont(frame, 12, "APOC Trade Awards")
    frame.title:SetPoint("TOPLEFT", 10, -8)
    frame.title:SetTextColor(1, 0.85, 0.2)
    frame.subtitle = EnsureTradeHelperFont(frame, 10, "")
    frame.subtitle:SetPoint("TOPLEFT", 10, -24)
    frame.subtitle:SetPoint("TOPRIGHT", -10, -24)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetTextColor(0.8, 0.78, 0.7)
    frame.rows = {}
    for index = 1, MAX_HELPER_ROWS do
      local row = CreateFrame("Button", nil, frame)
      row:SetSize(240, 18)
      row:SetPoint("TOPLEFT", 10, -42 - ((index - 1) * 20))
      row.check = EnsureTradeHelperFont(row, 10, "[ ]")
      row.check:SetPoint("LEFT", 0, 0)
      row.check:SetWidth(18)
      row.label = EnsureTradeHelperFont(row, 10, "")
      row.label:SetPoint("LEFT", 20, 0)
      row.label:SetPoint("RIGHT", 0, 0)
      row.label:SetJustifyH("LEFT")
      row:SetScript("OnClick", function(btn)
        if not btn.dropID then return end
        APOCLootPrio.tradeAwardSelectedDropIDs = APOCLootPrio.tradeAwardSelectedDropIDs or {}
        local cur = APOCLootPrio.tradeAwardSelectedDropIDs[btn.dropID]
        APOCLootPrio.tradeAwardSelectedDropIDs[btn.dropID] = not cur
        APOCLootPrio:RefreshTradeAwardHelper()
      end)
      frame.rows[index] = row
    end
    frame.hint = EnsureTradeHelperFont(frame, 9, "Checked rows award on accept.")
    frame.hint:SetPoint("BOTTOMLEFT", 10, 8)
    frame.hint:SetTextColor(0.65, 0.62, 0.55)
    self.tradeAwardHelperFrame = frame
  end

  if TradeFrame then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 4, 0)
  end

  frame.subtitle:SetText("Partner: " .. tostring(target ~= "" and target or "?"))
  self.tradeAwardSelectedDropIDs = self.tradeAwardSelectedDropIDs or {}

  -- Default-select strong matches.
  for _, row in ipairs(rows) do
    if row.kind == "awarded-untraded" or row.kind == "roll-high" or row.kind == "selected" then
      if self.tradeAwardSelectedDropIDs[row.drop.id] == nil then
        self.tradeAwardSelectedDropIDs[row.drop.id] = true
      end
    end
  end

  local height = 56 + math.max(1, math.min(#rows, MAX_HELPER_ROWS)) * 20
  frame:SetHeight(height)

  for index = 1, MAX_HELPER_ROWS do
    local row = frame.rows[index]
    local data = rows[index]
    if data then
      row.dropID = data.drop.id
      local selected = self.tradeAwardSelectedDropIDs[data.drop.id]
      row.check:SetText(selected and "[x]" or "[ ]")
      local tag = data.kind == "awarded-untraded" and "deliver"
        or (data.kind == "roll-high" and "high roll")
        or (data.kind == "selected" and "selected")
        or "award"
      row.label:SetText(tostring(data.drop.item or "item") .. " (" .. tag .. ")")
      row:Show()
    else
      row.dropID = nil
      row:Hide()
    end
  end

  if #rows == 0 then
    frame.hint:SetText("No matching tracker drops for this partner.")
  else
    frame.hint:SetText("Checked rows award / mark delivered on accept.")
  end

  frame:Show()
end

---------------------------------------------------------------------------
-- Master loot helper UI
---------------------------------------------------------------------------

function APOCLootPrio:HideMasterLootHelper()
  if self.masterLootHelperFrame then self.masterLootHelperFrame:Hide() end
  if self.masterLootNamePicker then self.masterLootNamePicker:Hide() end
end

local function BuildLootSlotMatches()
  local rows = {}
  if not GetNumLootItems or not GetLootSlotLink then return rows end
  if not CanAwardNow() then return rows end
  if not APOCLootPrio.IsMasterLooter or not APOCLootPrio:IsMasterLooter() then return rows end

  local usedDropIDs = {}
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local itemID = APOCLootPrio:GetItemIDFromLink(link)
    if itemID then
      local best = nil
      IterSessionDrops(function(drop, session)
        if usedDropIDs[drop.id] then return end
        if DropItemID(drop) ~= itemID then return end
        if IsAwarded(drop) then return end
        local score = DropTime(drop)
        if APOCLootPrio.selectedLootDropID and drop.id == APOCLootPrio.selectedLootDropID then
          score = score + 1e12
        end
        local high = RollHighName(drop)
        if high then score = score + 1e11 end
        if not best or score > best.score then
          best = {drop = drop, session = session, score = score, highName = high, slot = slot, link = link}
        end
      end)
      if best then
        usedDropIDs[best.drop.id] = true
        table.insert(rows, best)
      end
    end
  end
  return rows
end

function APOCLootPrio:GiveMasterLootAndAward(slot, winner, dropID)
  if not CanAwardNow() then return false, "No live edit permission." end
  winner = Trim(winner)
  local drop, session = self:FindRaidLootDrop(dropID)
  if not drop or not self:CanEditLootSession(session) or session.finalized or session.archived then
    return false, "Choose a live loot drop."
  end
  if IsAwarded(drop) and not SamePlayer(drop.award.winner, winner) then
    return false, "This drop is awarded to someone else."
  end
  local candidate = FindMasterLootCandidateIndex(winner, slot)
  if winner == "" or not candidate or not GiveMasterLoot then return false, "Winner is not a loot candidate." end
  if not GetLootSlotLink or self:GetItemIDFromLink(GetLootSlotLink(slot)) ~= DropItemID(drop) then
    return false, "Loot slot changed. Select the item again."
  end
  self.pendingMasterLoot = self.pendingMasterLoot or {}
  local pending = {dropID=dropID, itemID=DropItemID(drop), winner=winner,
    startedAt=time and time() or 0}
  self.pendingMasterLoot[slot] = pending
  local ok, result = pcall(GiveMasterLoot, slot, candidate)
  if not ok or result == false then
    self.pendingMasterLoot[slot] = nil
    return false, "Master loot did not succeed; no delivery recorded."
  end
  if not IsAwarded(drop) then
    local awarded, message = self:AwardRaidLootDrop(dropID, winner, "Master loot pending confirmation", "MS")
    if not awarded then self.pendingMasterLoot[slot] = nil; return false, message end
  end
  self:UpdateRaidLootStatus("Master loot requested for " .. winner .. "; waiting for loot receipt.")
  self:RefreshMasterLootHelper()
  return true
end

function APOCLootPrio:ConfirmMasterLootReceipt(winner, itemID)
  for slot, pending in pairs(self.pendingMasterLoot or {}) do
    local age = (time and time() or 0) - pending.startedAt
    if age > 30 then
      self.pendingMasterLoot[slot] = nil
    elseif SamePlayer(winner, pending.winner) and tonumber(itemID) == pending.itemID then
      pending.received = true
      if pending.cleared then
        self.pendingMasterLoot[slot] = nil
        self:AwardAndMarkTradeDrop(pending.dropID, winner, "Confirmed master loot", "MS")
      end
      return
    end
  end
end

function APOCLootPrio:ShowMasterLootNamePicker(slot, dropID)
  if not CanAwardNow() then return end
  local picker = self.masterLootNamePicker
  if not picker then
    picker = CreateFrame("Frame", "APOCLootMasterLootNamePicker", UIParent, BackdropTemplate and "BackdropTemplate" or nil)
    picker:SetSize(490, 310)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    if picker.SetBackdrop then
      picker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
      })
      picker:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
      picker:SetBackdropBorderColor(0.75, 0.62, 0.28, 1)
    end
    picker.title = EnsureTradeHelperFont(picker, 11, "Give to…")
    picker.title:SetPoint("TOPLEFT", 8, -8)
    picker.title:SetTextColor(1, 0.85, 0.2)
    picker.close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    picker.close:SetPoint("TOPRIGHT", 2, 2)
    picker.buttons = {}
    self.masterLootNamePicker = picker
  end

  local roster = self.GetGroupRoster and self:GetGroupRoster() or {}
  for index, button in ipairs(picker.buttons) do
    button:Hide()
  end

  local y = -28
  for index, name in ipairs(roster) do
    if index > 40 then break end
    local button = picker.buttons[index]
    if not button then
      button = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
      button:SetSize(150, 18)
      picker.buttons[index] = button
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", 12 + math.floor((index - 1) / 14) * 160, -28 - ((index - 1) % 14) * 20)
    button:SetText(ShortName(name) or name)
    button:SetScript("OnClick", function()
      APOCLootPrio:GiveMasterLootAndAward(picker.slot, name, picker.dropID)
      picker:Hide()
    end)
    button:Show()
    y = y - 20
  end
  picker:SetHeight(math.max(80, 40 + math.min(#roster, 14) * 20))
  picker.slot = slot
  picker.dropID = dropID
  if self.masterLootHelperFrame and self.masterLootHelperFrame:IsShown() then
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", self.masterLootHelperFrame, "TOPRIGHT", 4, 0)
  else
    picker:ClearAllPoints()
    picker:SetPoint("CENTER", UIParent, "CENTER", 120, 80)
  end
  picker:Show()
end

function APOCLootPrio:RefreshMasterLootHelper()
  if not CanAwardNow() or not self:IsMasterLooter() then
    self:HideMasterLootHelper()
    return
  end
  if not LootFrame or not LootFrame.IsShown or not LootFrame:IsShown() then
    -- LootFrame may be hidden while loot still open on some clients; still try if GetNumLootItems > 0
    if not GetNumLootItems or (GetNumLootItems() or 0) == 0 then
      self:HideMasterLootHelper()
      return
    end
  end

  local matches = BuildLootSlotMatches()
  local frame = self.masterLootHelperFrame
  if not frame then
    frame = CreateFrame("Frame", "APOCLootMasterLootHelper", UIParent, BackdropTemplate and "BackdropTemplate" or nil)
    frame:SetSize(280, 120)
    frame:SetFrameStrata("DIALOG")
    if frame.SetBackdrop then
      frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
      })
      frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
      frame:SetBackdropBorderColor(0.75, 0.62, 0.28, 1)
    else
      local bg = frame:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(frame)
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.05, 0.05, 0.08, 0.92)
    end
    frame.title = EnsureTradeHelperFont(frame, 12, "APOC Master Loot")
    frame.title:SetPoint("TOPLEFT", 10, -8)
    frame.title:SetTextColor(1, 0.85, 0.2)
    frame.rows = {}
    for index = 1, MAX_HELPER_ROWS do
      local row = CreateFrame("Frame", nil, frame)
      row:SetSize(260, 22)
      row:SetPoint("TOPLEFT", 10, -28 - ((index - 1) * 24))
      row.label = EnsureTradeHelperFont(row, 10, "")
      row.label:SetPoint("LEFT", 0, 0)
      row.label:SetWidth(140)
      row.label:SetJustifyH("LEFT")
      row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      row.action:SetSize(110, 20)
      row.action:SetPoint("RIGHT", 0, 0)
      frame.rows[index] = row
    end
    self.masterLootHelperFrame = frame
  end

  if LootFrame and LootFrame:IsShown() then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 4, 0)
  else
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
  end

  frame:SetHeight(36 + math.max(1, math.min(#matches, MAX_HELPER_ROWS)) * 24)

  for index = 1, MAX_HELPER_ROWS do
    local row = frame.rows[index]
    local data = matches[index]
    if data then
      row.label:SetText(tostring(data.drop.item or "item"))
      local winner = data.highName
      if winner and winner ~= "" then
        row.action:SetText("Give to " .. tostring(ShortName(winner)))
        row.action:SetScript("OnClick", function()
          APOCLootPrio:GiveMasterLootAndAward(data.slot, winner, data.drop.id)
        end)
      else
        row.action:SetText("Pick winner…")
        row.action:SetScript("OnClick", function()
          APOCLootPrio:ShowMasterLootNamePicker(data.slot, data.drop.id)
        end)
      end
      row:Show()
    else
      row:Hide()
    end
  end

  if #matches == 0 then
    frame:Hide()
  else
    frame:Show()
  end
end

---------------------------------------------------------------------------
-- Trade event wrappers
---------------------------------------------------------------------------

function APOCLootPrio:HandleTradeShow()
  self.closedLootTrade = nil
  self.tradeAwardSelectedDropIDs = {}
  self.pendingLootTrade = {target=self:GetTradeTargetDisplayName(), items={}, bothAccepted=false}
  if CanAwardNow() then
    self:AutoPlacePendingAwardsInTrade(self.pendingLootTrade.target)
    self.pendingLootTrade.items = self:CaptureTradePlayerItems()
    self:RefreshTradeAwardHelper()
  else
    self:HideTradeAwardHelper()
  end
end

function APOCLootPrio:HandleTradePlayerItemChanged()
  local trade = self.pendingLootTrade
  if not trade then return end
  trade.target = self:GetTradeTargetDisplayName()
  trade.items = self:CaptureTradePlayerItems()
  trade.bothAccepted = false
  trade.matches = nil
  if CanAwardNow() then self:RefreshTradeAwardHelper() end
end

function APOCLootPrio:HandleTradeAcceptUpdate(playerAccepted, targetAccepted)
  local trade = self.pendingLootTrade
  if not trade then return end
  trade.target = self:GetTradeTargetDisplayName()
  trade.items = self:CaptureTradePlayerItems()
  trade.bothAccepted = (playerAccepted == 1 or playerAccepted == true)
    and (targetAccepted == 1 or targetAccepted == true)
  trade.matches = trade.bothAccepted and self:MatchTradeItemsToDrops(trade.target, trade.items) or nil
  if CanAwardNow() then self:RefreshTradeAwardHelper() end
end

function APOCLootPrio:HandleTradeClosed()
  -- Close also fires for cancellations. Never commit here.
  local trade = self.pendingLootTrade
  self.pendingLootTrade = nil
  if trade then
    trade.closedAt = time and time() or 0
    self.closedLootTrade = trade
  end
  self:HideTradeAwardHelper()
  self.tradeAwardSelectedDropIDs = nil
end

function APOCLootPrio:CancelLootTrade()
  self.pendingLootTrade = nil
  self.closedLootTrade = nil
  self.tradeAwardSelectedDropIDs = nil
  self:HideTradeAwardHelper()
end

function APOCLootPrio:ConfirmLootTrade()
  local trade = self.pendingLootTrade or self.closedLootTrade
  self.pendingLootTrade, self.closedLootTrade = nil, nil
  if not trade or not trade.bothAccepted or not trade.matches then return 0 end
  if trade.closedAt and (time and time() or 0) - trade.closedAt > 5 then return 0 end
  return self:ProcessAcceptedTradeAwards(trade.target, trade.items, trade.matches)
end

function APOCLootPrio:SaveRaidLootAward()
  local beforeID = self.selectedLootDropID
  local beforeDrop = beforeID and self:FindRaidLootDrop(beforeID) or nil
  local wasAlreadyAwarded = beforeDrop and IsAwarded(beforeDrop) or false

  if PreviousSaveRaidLootAward then
    PreviousSaveRaidLootAward(self)
  end

  if not CanAwardNow() then return end
  if self.suppressPostAwardTrade then return end
  -- Only auto-trade for freshly created awards — not note/type edits of existing awards.
  if wasAlreadyAwarded then return end

  local drop = beforeID and self:FindRaidLootDrop(beforeID) or nil
  if drop and IsAwarded(drop) and not IsTraded(drop) then
    local winner = drop.award.winner
    if winner and string.lower(tostring(winner)) ~= "disenchant" then
      self:TryInitiateTradeWithWinner(winner, drop)
    end
  end
end

---------------------------------------------------------------------------
-- Loot window events
---------------------------------------------------------------------------

local lootHelperEvents = CreateFrame("Frame")
local function RegisterLootHelperEvent(eventName)
  if pcall then
    pcall(function() lootHelperEvents:RegisterEvent(eventName) end)
  else
    lootHelperEvents:RegisterEvent(eventName)
  end
end

RegisterLootHelperEvent("LOOT_OPENED")
RegisterLootHelperEvent("LOOT_CLOSED")
RegisterLootHelperEvent("LOOT_SLOT_CLEARED")
RegisterLootHelperEvent("PLAYER_LOGOUT")
RegisterLootHelperEvent("UI_INFO_MESSAGE")
RegisterLootHelperEvent("UI_ERROR_MESSAGE")
RegisterLootHelperEvent("TRADE_REQUEST_CANCEL")

lootHelperEvents:SetScript("OnEvent", function(_, event, ...)
  if event == "UI_INFO_MESSAGE" then
    local _, message = ...
    if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then APOCLootPrio:ConfirmLootTrade() end
    return
  end
  if event == "TRADE_REQUEST_CANCEL" then APOCLootPrio:CancelLootTrade(); return end
  if event == "UI_ERROR_MESSAGE" then
    APOCLootPrio.pendingMasterLoot = nil
    local _, message = ...
    if (ERR_TRADE_CANCELLED and message == ERR_TRADE_CANCELLED)
      or (ERR_TRADE_FAILED and message == ERR_TRADE_FAILED) then APOCLootPrio:CancelLootTrade() end
    return
  end
  if event == "LOOT_OPENED" then
    if APOCLootPrio.RefreshMasterLootHelper then
      -- Defer slightly so ScanOpenLootForRaidDrops in Core can finish first.
      if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
          if APOCLootPrio.RefreshMasterLootHelper then APOCLootPrio:RefreshMasterLootHelper() end
        end)
      else
        APOCLootPrio:RefreshMasterLootHelper()
      end
    end
    return
  end
  if event == "LOOT_SLOT_CLEARED" then
    local slot = ...
    local pending = APOCLootPrio.pendingMasterLoot and APOCLootPrio.pendingMasterLoot[slot]
    if pending then
      pending.cleared = true
      if pending.received then APOCLootPrio:ConfirmMasterLootReceipt(pending.winner, pending.itemID) end
    end
    if APOCLootPrio.RefreshMasterLootHelper then APOCLootPrio:RefreshMasterLootHelper() end
    return
  end
  if event == "LOOT_CLOSED" or event == "PLAYER_LOGOUT" then
    if APOCLootPrio.HideMasterLootHelper then APOCLootPrio:HideMasterLootHelper() end
    if APOCLootPrio.HideTradeAwardHelper then APOCLootPrio:HideTradeAwardHelper() end
  end
end)
