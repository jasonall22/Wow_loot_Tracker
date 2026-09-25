local DEFAULT_ANGLE = 225
local DEFAULT_TRACKER_ANGLE = 255
local MINIMAP_RADIUS = 80
local MINIMAP_RESTORE_BUILD = "0.2.0-beta.18"
local TRACKER_MINIMAP_RESTORE_BUILD = "0.2.0-beta.18"

local function GetMinimapSettings()
  APOCLootPrioDB = APOCLootPrioDB or {}
  APOCLootPrioDB.minimap = APOCLootPrioDB.minimap or {}
  return APOCLootPrioDB.minimap
end

local function CalculateAngle()
  local cursorX, cursorY = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cursorX = cursorX / scale
  cursorY = cursorY / scale

  local centerX, centerY = Minimap:GetCenter()
  local dx = cursorX - centerX
  local dy = cursorY - centerY

  if dx == 0 then
    return dy >= 0 and 90 or 270
  end

  local angle = math.deg(math.atan(dy / dx))
  if dx < 0 then angle = angle + 180 end
  if angle < 0 then angle = angle + 360 end
  return angle
end

function APOCLootPrio:PositionMinimapButton()
  local button = self.minimapButton
  if not button then return end

  local settings = GetMinimapSettings()
  local angle = math.rad(settings.angle or DEFAULT_ANGLE)
  local x = math.cos(angle) * MINIMAP_RADIUS
  local y = math.sin(angle) * MINIMAP_RADIUS

  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function APOCLootPrio:PositionTrackerMinimapButton()
  local button = self.trackerMinimapButton
  if not button then return end

  local settings = GetMinimapSettings()
  local angle = math.rad(settings.trackerAngle or DEFAULT_TRACKER_ANGLE)
  local x = math.cos(angle) * MINIMAP_RADIUS
  local y = math.sin(angle) * MINIMAP_RADIUS

  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function APOCLootPrio:SetMinimapButtonShown(show)
  local settings = GetMinimapSettings()
  settings.hide = not show

  if show and not self.minimapButton and self.CreateMinimapButton then
    self:CreateMinimapButton()
  end

  if self.minimapButton then
    if show then
      self:PositionMinimapButton()
      self.minimapButton:Show()
    else
      self.minimapButton:Hide()
    end
  end
end

function APOCLootPrio:SetTrackerMinimapButtonShown(show)
  local settings = GetMinimapSettings()
  settings.trackerHide = not show

  if show and not self.trackerMinimapButton and self.CreateTrackerMinimapButton then
    self:CreateTrackerMinimapButton()
  end

  if self.trackerMinimapButton then
    if show then
      self:PositionTrackerMinimapButton()
      self.trackerMinimapButton:Show()
    else
      self.trackerMinimapButton:Hide()
    end
  end
end

function APOCLootPrio:RestoreMinimapButtonForBuild()
  local settings = GetMinimapSettings()

  if settings.shownBuild ~= MINIMAP_RESTORE_BUILD then
    settings.hide = false
  end
  if settings.trackerShownBuild ~= TRACKER_MINIMAP_RESTORE_BUILD then
    settings.trackerHide = false
  end
  if not self.minimapButton then
    self:CreateMinimapButton()
  end
  if not self.trackerMinimapButton and self.CreateTrackerMinimapButton then
    self:CreateTrackerMinimapButton()
  end

  if self.minimapButton then
    if Minimap and self.minimapButton.SetParent then
      self.minimapButton:SetParent(Minimap)
    end
    self.minimapButton:SetFrameStrata("FULLSCREEN_DIALOG")
    self.minimapButton:SetFrameLevel(120)
    self:PositionMinimapButton()
    if settings.hide then
      self.minimapButton:Hide()
    else
      self.minimapButton:Show()
    end
  end

  settings.shownBuild = MINIMAP_RESTORE_BUILD

  if self.trackerMinimapButton then
    if Minimap and self.trackerMinimapButton.SetParent then
      self.trackerMinimapButton:SetParent(Minimap)
    end
    self.trackerMinimapButton:SetFrameStrata("FULLSCREEN_DIALOG")
    self.trackerMinimapButton:SetFrameLevel(121)
    self:PositionTrackerMinimapButton()
    if settings.trackerHide then
      self.trackerMinimapButton:Hide()
    else
      self.trackerMinimapButton:Show()
    end
  end

  settings.trackerShownBuild = TRACKER_MINIMAP_RESTORE_BUILD
end

function APOCLootPrio:ToggleMinimapButton()
  local settings = GetMinimapSettings()
  local show = settings.hide
  self:SetMinimapButtonShown(show)

  if show then
    self:Print("Minimap icon shown.")
  else
    self:Print("Minimap icon hidden. Type /priobeta minimap to show it again.")
  end
end

function APOCLootPrio:ToggleTrackerMinimapButton()
  local settings = GetMinimapSettings()
  local show = settings.trackerHide
  self:SetTrackerMinimapButtonShown(show)

  if show then
    self:Print("Loot Tracker minimap icon shown.")
  else
    self:Print("Loot Tracker minimap icon hidden. Type /priobeta trackerminimap to show it again.")
  end
end

function APOCLootPrio:CreateMinimapButton()
  if self.minimapButton then
    self:PositionMinimapButton()
    if not GetMinimapSettings().hide then self.minimapButton:Show() end
    return
  end
  if not Minimap then return end

  local button = CreateFrame("Button", "APOCLootPrioMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("FULLSCREEN_DIALOG")
  button:SetFrameLevel(120)
  if button.SetToplevel then button:SetToplevel(true) end
  button:SetClampedToScreen(true)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_05")
  icon:SetTexCoord(.08, .92, .08, .92)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetSize(31, 31)
  highlight:SetPoint("TOPLEFT", 0, 0)
  highlight:SetBlendMode("ADD")

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("APOC Loot Tracker - Multi-Run Beta", .35, .8, 1)
    GameTooltip:AddLine("Left-click: open priority browser", 1, 1, 1)
    GameTooltip:AddLine("Drag: move icon", .75, .75, .75)
    GameTooltip:AddLine("Right-click: reset position", .75, .75, .75)
    GameTooltip:AddLine("Shift-right-click: hide icon", .75, .75, .75)
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  button:SetScript("OnClick", function(_, mouseButton)
    if button.wasDragged then
      button.wasDragged = nil
      return
    end

    if mouseButton == "RightButton" then
      if IsShiftKeyDown() then
        APOCLootPrio:SetMinimapButtonShown(false)
        APOCLootPrio:Print("Minimap icon hidden. Type /priobeta minimap to show it again.")
      else
        GetMinimapSettings().angle = DEFAULT_ANGLE
        APOCLootPrio:PositionMinimapButton()
        APOCLootPrio:Print("Minimap icon reset.")
      end
      return
    end

    APOCLootPrio:Toggle()
  end)

  button:SetScript("OnDragStart", function(self)
    self.wasDragged = true
    self:SetScript("OnUpdate", function()
      GetMinimapSettings().angle = CalculateAngle()
      APOCLootPrio:PositionMinimapButton()
    end)
  end)

  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  self.minimapButton = button
  self:PositionMinimapButton()
  if GetMinimapSettings().hide then button:Hide() end
end

function APOCLootPrio:CreateTrackerMinimapButton()
  if self.trackerMinimapButton then
    self:PositionTrackerMinimapButton()
    if not GetMinimapSettings().trackerHide then self.trackerMinimapButton:Show() end
    return
  end
  if not Minimap then return end

  local button = CreateFrame("Button", "APOCLootPrioTrackerMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("FULLSCREEN_DIALOG")
  button:SetFrameLevel(121)
  if button.SetToplevel then button:SetToplevel(true) end
  button:SetClampedToScreen(true)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
  icon:SetTexCoord(.08, .92, .08, .92)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetSize(31, 31)
  highlight:SetPoint("TOPLEFT", 0, 0)
  highlight:SetBlendMode("ADD")

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("APOC Loot Tracker - Multi-Run Beta", .35, .8, 1)
    GameTooltip:AddLine("Left-click: open loot tracker", 1, 1, 1)
    GameTooltip:AddLine("Drag: move icon", .75, .75, .75)
    GameTooltip:AddLine("Right-click: reset position", .75, .75, .75)
    GameTooltip:AddLine("Shift-right-click: hide icon", .75, .75, .75)
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  button:SetScript("OnClick", function(_, mouseButton)
    if button.wasDragged then
      button.wasDragged = nil
      return
    end

    if mouseButton == "RightButton" then
      if IsShiftKeyDown() then
        APOCLootPrio:SetTrackerMinimapButtonShown(false)
        APOCLootPrio:Print("Loot Tracker minimap icon hidden. Type /priobeta trackerminimap to show it again.")
      else
        GetMinimapSettings().trackerAngle = DEFAULT_TRACKER_ANGLE
        APOCLootPrio:PositionTrackerMinimapButton()
        APOCLootPrio:Print("Loot Tracker minimap icon reset.")
      end
      return
    end

    if APOCLootPrio.ToggleRaidLootPanel then
      APOCLootPrio:ToggleRaidLootPanel()
    else
      APOCLootPrio:Print("Loot Tracker UI is not loaded.")
    end
  end)

  button:SetScript("OnDragStart", function(self)
    self.wasDragged = true
    self:SetScript("OnUpdate", function()
      GetMinimapSettings().trackerAngle = CalculateAngle()
      APOCLootPrio:PositionTrackerMinimapButton()
    end)
  end)

  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  self.trackerMinimapButton = button
  self:PositionTrackerMinimapButton()
  if GetMinimapSettings().trackerHide then button:Hide() end
end
