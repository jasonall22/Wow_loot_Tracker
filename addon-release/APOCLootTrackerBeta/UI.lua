local ADDON_NAME = ...
local FALLBACK_ADDON_VERSION = APOCLootPrio.BUILD_VERSION

local ITEM_PURPLE = "|cffa335ee"
local TEXT_GREY = "|cffbbbbbb"
local COLOR_RESET = "|r"

local CLASS_TOKEN_COLORS = {
  ["druid"] = "|cffff7c0a",
  ["balance"] = "|cffff7c0a",
  ["bear"] = "|cffff7c0a",
  ["cat"] = "|cffff7c0a",
  ["feral"] = "|cffff7c0a",

  ["hunter"] = "|cffaad372",
  ["bm"] = "|cffaad372",
  ["survival"] = "|cffaad372",
  ["mm"] = "|cffaad372",

  ["mage"] = "|cff3fc7eb",
  ["arcane"] = "|cff3fc7eb",
  ["fire"] = "|cff3fc7eb",
  ["frost"] = "|cff3fc7eb",

  ["paladin"] = "|cfff48cba",
  ["ret"] = "|cfff48cba",

  ["priest"] = "|cffffffff",
  ["shadow"] = "|cffffffff",
  ["disc"] = "|cffffffff",

  ["rogue"] = "|cfffff468",

  ["shaman"] = "|cff0070dd",
  ["ele"] = "|cff0070dd",
  ["enh"] = "|cff0070dd",
  ["enhance"] = "|cff0070dd",

  ["warlock"] = "|cff8788ee",
  ["demo"] = "|cff8788ee",
  ["destro"] = "|cff8788ee",
  ["affliction"] = "|cff8788ee",

  ["warrior"] = "|cffc69b6d",
  ["arms"] = "|cffc69b6d",
  ["fury"] = "|cffc69b6d",
}

local function GetAddonVersion()
  local version = nil
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON_NAME or "APOCLootPrio", "Version")
  end
  if (not version or version == "") and GetAddOnMetadata then
    version = GetAddOnMetadata(ADDON_NAME or "APOCLootPrio", "Version")
  end
  if not version or version == "" then
    version = FALLBACK_ADDON_VERSION
  end
  return tostring(version)
end

local CLASS_RGB_COLORS = {
  DRUID = {1, .49, .04},
  HUNTER = {.67, .83, .45},
  MAGE = {.25, .78, .92},
  PALADIN = {.96, .55, .73},
  PRIEST = {1, 1, 1},
  ROGUE = {1, .96, .41},
  SHAMAN = {0, .44, .87},
  WARLOCK = {.53, .53, .93},
  WARRIOR = {.78, .61, .43},
}

local PRIORITY_PHRASE_COLORS = {
  {text = "Beast Mastery Hunter", color = CLASS_TOKEN_COLORS["hunter"]},
  {text = "Marksmanship Hunter", color = CLASS_TOKEN_COLORS["hunter"]},
  {text = "Retribution Paladin", color = CLASS_TOKEN_COLORS["paladin"]},
  {text = "Assassination Rogue", color = CLASS_TOKEN_COLORS["rogue"]},
  {text = "Discipline Priest", color = CLASS_TOKEN_COLORS["priest"]},
  {text = "Enhancement Shaman", color = CLASS_TOKEN_COLORS["shaman"]},
  {text = "Protection Paladin", color = CLASS_TOKEN_COLORS["paladin"]},
  {text = "Restoration Shaman", color = CLASS_TOKEN_COLORS["shaman"]},
  {text = "Restoration Druid", color = CLASS_TOKEN_COLORS["druid"]},
  {text = "Protection Warrior", color = CLASS_TOKEN_COLORS["warrior"]},
  {text = "Demonology Warlock", color = CLASS_TOKEN_COLORS["warlock"]},
  {text = "Destruction Warlock", color = CLASS_TOKEN_COLORS["warlock"]},
  {text = "Affliction Warlock", color = CLASS_TOKEN_COLORS["warlock"]},
  {text = "Elemental Shaman", color = CLASS_TOKEN_COLORS["shaman"]},
  {text = "Subtlety Rogue", color = CLASS_TOKEN_COLORS["rogue"]},
  {text = "Survival Hunter", color = CLASS_TOKEN_COLORS["hunter"]},
  {text = "Feral Bear Druid", color = CLASS_TOKEN_COLORS["druid"]},
  {text = "Feral Cat Druid", color = CLASS_TOKEN_COLORS["druid"]},
  {text = "Holy Paladin", color = CLASS_TOKEN_COLORS["paladin"]},
  {text = "Holy Priest", color = CLASS_TOKEN_COLORS["priest"]},
  {text = "Shadow Priest", color = CLASS_TOKEN_COLORS["priest"]},
  {text = "Balance Druid", color = CLASS_TOKEN_COLORS["druid"]},
  {text = "Combat Rogue", color = CLASS_TOKEN_COLORS["rogue"]},
  {text = "Arcane Mage", color = CLASS_TOKEN_COLORS["mage"]},
  {text = "Frost Mage", color = CLASS_TOKEN_COLORS["mage"]},
  {text = "Fire Mage", color = CLASS_TOKEN_COLORS["mage"]},
  {text = "Arms Warrior", color = CLASS_TOKEN_COLORS["warrior"]},
  {text = "Fury Warrior", color = CLASS_TOKEN_COLORS["warrior"]},
  {text = "Resto Shaman", color = CLASS_TOKEN_COLORS["shaman"]},
  {text = "Resto Druid", color = CLASS_TOKEN_COLORS["druid"]},
}

local PRIORITY_MATCH_RULES = {
  {text = "Beast Mastery Hunter", class = "HUNTER", role = "DAMAGER"},
  {text = "Marksmanship Hunter", class = "HUNTER", role = "DAMAGER"},
  {text = "Survival Hunter", class = "HUNTER", role = "DAMAGER"},
  {text = "Retribution Paladin", class = "PALADIN", role = "DAMAGER"},
  {text = "Protection Paladin", class = "PALADIN", role = "TANK"},
  {text = "Holy Paladin", class = "PALADIN", role = "HEALER"},
  {text = "Assassination Rogue", class = "ROGUE", role = "DAMAGER"},
  {text = "Subtlety Rogue", class = "ROGUE", role = "DAMAGER"},
  {text = "Combat Rogue", class = "ROGUE", role = "DAMAGER"},
  {text = "Discipline Priest", class = "PRIEST", role = "HEALER"},
  {text = "Holy Priest", class = "PRIEST", role = "HEALER"},
  {text = "Shadow Priest", class = "PRIEST", role = "DAMAGER"},
  {text = "Enhancement Shaman", class = "SHAMAN", role = "DAMAGER"},
  {text = "Restoration Shaman", class = "SHAMAN", role = "HEALER"},
  {text = "Elemental Shaman", class = "SHAMAN", role = "DAMAGER"},
  {text = "Resto Shaman", class = "SHAMAN", role = "HEALER"},
  {text = "Restoration Druid", class = "DRUID", role = "HEALER"},
  {text = "Resto Druid", class = "DRUID", role = "HEALER"},
  {text = "Feral Bear Druid", class = "DRUID", role = "TANK"},
  {text = "Feral Cat Druid", class = "DRUID", role = "DAMAGER"},
  {text = "Balance Druid", class = "DRUID", role = "DAMAGER"},
  {text = "Protection Warrior", class = "WARRIOR", role = "TANK"},
  {text = "Arms Warrior", class = "WARRIOR", role = "DAMAGER"},
  {text = "Fury Warrior", class = "WARRIOR", role = "DAMAGER"},
  {text = "Demonology Warlock", class = "WARLOCK", role = "DAMAGER"},
  {text = "Destruction Warlock", class = "WARLOCK", role = "DAMAGER"},
  {text = "Affliction Warlock", class = "WARLOCK", role = "DAMAGER"},
  {text = "Arcane Mage", class = "MAGE", role = "DAMAGER"},
  {text = "Frost Mage", class = "MAGE", role = "DAMAGER"},
  {text = "Fire Mage", class = "MAGE", role = "DAMAGER"},
  {text = "BM", class = "HUNTER", role = "DAMAGER"},
  {text = "MM", class = "HUNTER", role = "DAMAGER"},
  {text = "Hunter", class = "HUNTER", role = "DAMAGER"},
  {text = "Ret", class = "PALADIN", role = "DAMAGER"},
  {text = "Prot Paladin", class = "PALADIN", role = "TANK"},
  {text = "Rogue", class = "ROGUE", role = "DAMAGER"},
  {text = "Disc", class = "PRIEST", role = "HEALER"},
  {text = "Shadow", class = "PRIEST", role = "DAMAGER"},
  {text = "Enhance", class = "SHAMAN", role = "DAMAGER"},
  {text = "Enh", class = "SHAMAN", role = "DAMAGER"},
  {text = "Ele", class = "SHAMAN", role = "DAMAGER"},
  {text = "Cat", class = "DRUID", role = "DAMAGER"},
  {text = "Bear", class = "DRUID", role = "TANK"},
  {text = "Balance", class = "DRUID", role = "DAMAGER"},
  {text = "Arms", class = "WARRIOR", role = "DAMAGER"},
  {text = "Fury", class = "WARRIOR", role = "DAMAGER"},
  {text = "Warlock", class = "WARLOCK", role = "DAMAGER"},
  {text = "Demo", class = "WARLOCK", role = "DAMAGER"},
  {text = "Destro", class = "WARLOCK", role = "DAMAGER"},
  {text = "Mage", class = "MAGE", role = "DAMAGER"},
  {text = "Healer", role = "HEALER"},
  {text = "Tank", role = "TANK"},
  {text = "Melee", role = "DAMAGER"},
  {text = "Caster", role = "DAMAGER"},
  {text = "DPS", role = "DAMAGER"},
}

local FRAME_WIDTH = 720
local FRAME_HEIGHT = 580
local LOG_PANEL_WIDTH = 320
local RAID_LOOT_WINDOW_WIDTH = 820
local RAID_LOOT_WINDOW_HEIGHT = 960
local RAID_LOOT_WINDOW_MAX_WIDTH = 1180
local RAID_LOOT_WINDOW_MAX_HEIGHT = 1200
local RAID_LOOT_WINDOW_UI_SCALE = .78
local RAID_LOOT_QUEUE_MAX_WIDTH = 980
local RECENT_AWARDS_PANEL_WIDTH = 400
local RECENT_AWARDS_PANEL_HEIGHT = 420
local GUILD_LOOT_WINDOW_WIDTH = 520
local SETTINGS_PANEL_WIDTH = 360
local LOG_PANEL_GAP = 8
local LOG_PANEL_ANIMATION_SECONDS = .16
local CONTENT_WIDTH = 650
local BOSS_HEADER_HEIGHT = 30
local ITEM_ROW_HEIGHT = 42
local COLUMN_WIDTH = 306
local COLUMN_GAP = 20
local ICON_SIZE = 36
local SIDE_ROW_HEIGHT = 30
local GUILD_LOOT_ROW_WIDTH = GUILD_LOOT_WINDOW_WIDTH - 56
local GUILD_WINNER_ROW_HEIGHT = 56
local GROUP_MEMBER_BUTTON_HEIGHT = 22
local DROP_QUEUE_ROW_HEIGHT = 46
local LOOT_TRACKER_LIST_HEIGHT = 300
local AWARD_LEDGER_ROW_HEIGHT = 44
local RECENT_AWARD_EDITOR_HEIGHT = 210
local GUILD_AWARD_ROW_HEIGHT = 50
local MANUAL_PICKER_RAID_ORDER = {"Serpentshrine Cavern", "The Eye", "Mount Hyjal", "Black Temple"}
local SETTINGS_FEATURES = {
  {key = "admin", label = "Admin"},
  {key = "log", label = "Log"},
  {key = "lootTracker", label = "Loot Tracker"},
  {key = "guildLoot", label = "Guild Loot"},
}
local ADDON_FRAME_STRATA = "TOOLTIP"
local ADDON_FRAME_LEVEL = 900

local function Font(parent, size, text, template)
  local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  f:SetFont(STANDARD_TEXT_FONT, size or 12, "")
  f:SetText(text or "")
  return f
end

local function GetPlayerClassRGB(player)
  if not player then return .31, .63, 1 end

  local classFile = player.classFileName
  if classFile and classFile ~= "" then
    classFile = string.upper(classFile)
  end

  local color = classFile and (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile] or RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
  if color then
    return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1
  end

  color = classFile and CLASS_RGB_COLORS[classFile]
  if not color and player.className and player.className ~= "" then
    local className = string.upper(player.className)
    color = CLASS_RGB_COLORS[className]
  end

  if color then return color[1], color[2], color[3] end
  return .31, .63, 1
end

local function SetTextureColor(texture, r, g, b, a)
  if texture.SetColorTexture then
    texture:SetColorTexture(r, g, b, a)
  else
    texture:SetTexture(r, g, b, a)
  end
end

local APOC_PANEL_BG_R, APOC_PANEL_BG_G, APOC_PANEL_BG_B, APOC_PANEL_BG_A = .045, .050, .062, .98
local APOC_PANEL_TOP_R, APOC_PANEL_TOP_G, APOC_PANEL_TOP_B, APOC_PANEL_TOP_A = .075, .082, .098, .98
local APOC_GOLD_R, APOC_GOLD_G, APOC_GOLD_B, APOC_GOLD_A = .76, .58, .25, .88
local APOC_ROW_BG_R, APOC_ROW_BG_G, APOC_ROW_BG_B, APOC_ROW_BG_A = .055, .060, .073, .88
local GROUP_ROLE_BADGES = {
  TANK = {label = "Tank", coords = {0, 19 / 64, 22 / 64, 41 / 64}},
  HEALER = {label = "Healer", coords = {20 / 64, 39 / 64, 1 / 64, 20 / 64}},
  DAMAGER = {label = "Damage", coords = {20 / 64, 39 / 64, 22 / 64, 41 / 64}},
  UNKNOWN = {text = "?", label = "Role unknown"},
}

local function SetAPOCBodyTexture(texture, alpha)
  if not texture then return end
  SetTextureColor(texture, APOC_PANEL_BG_R, APOC_PANEL_BG_G, APOC_PANEL_BG_B, alpha or APOC_PANEL_BG_A)
end

local function SetAPOCGoldTexture(texture, alpha)
  SetTextureColor(texture, APOC_GOLD_R, APOC_GOLD_G, APOC_GOLD_B, alpha or APOC_GOLD_A)
end

local function AddGroupMemberRoleBadge(button, role)
  if not button then return end

  local badge = GROUP_ROLE_BADGES[role or ""] or GROUP_ROLE_BADGES.UNKNOWN
  if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    if GetTexCoordsForRoleSmallCircle then
      icon:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
    elseif badge.coords then
      icon:SetTexCoord(badge.coords[1], badge.coords[2], badge.coords[3], badge.coords[4])
    end
  else
    local text = Font(button, 9, badge.text, "GameFontHighlightSmall")
    text:SetPoint("LEFT", 10, 0)
    text:SetTextColor(.72, .68, .58)
  end

  if button.SetScript then
    button:SetScript("OnEnter", function(selfButton)
      if not GameTooltip then return end
      GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
      GameTooltip:SetText(badge.label or "Role", 1, .85, .2)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
  end
end

local function AddAPOCBorderTexture(panel, pointA, xA, yA, pointB, xB, yB, width, height)
  local texture = panel:CreateTexture(nil, "BORDER")
  texture:SetPoint(pointA, panel, pointA, xA, yA)
  if pointB then
    texture:SetPoint(pointB, panel, pointB, xB, yB)
    if width then texture:SetWidth(width) end
    if height then texture:SetHeight(height) end
  else
    texture:SetSize(width or 1, height or 1)
  end
  SetAPOCGoldTexture(texture)
  return texture
end

local function ApplyAPOCPanelBackdrop(panel)
  if not panel then return end

  if not panel.apocFramePrepared and panel.GetRegions then
    for _, region in ipairs({panel:GetRegions()}) do
      if region and region.SetAlpha then
        region:SetAlpha(0)
      end
    end
    panel.apocFramePrepared = true
  end

  if not panel.apocTopBar then
    panel.apocTopBar = panel:CreateTexture(nil, "BACKGROUND")
    panel.apocTopBar:SetPoint("TOPLEFT", 8, -8)
    panel.apocTopBar:SetPoint("TOPRIGHT", -8, -8)
    panel.apocTopBar:SetHeight(22)
  end
  SetTextureColor(panel.apocTopBar, APOC_PANEL_TOP_R, APOC_PANEL_TOP_G, APOC_PANEL_TOP_B, APOC_PANEL_TOP_A)

  if not panel.apocBody then
    panel.apocBody = panel:CreateTexture(nil, "BACKGROUND")
    panel.apocBody:SetPoint("TOPLEFT", 8, -30)
    panel.apocBody:SetPoint("BOTTOMRIGHT", -8, 8)
  end
  SetAPOCBodyTexture(panel.apocBody)

  if not panel.apocOuterTop then
    panel.apocOuterTop = AddAPOCBorderTexture(panel, "TOPLEFT", 8, -8, "TOPRIGHT", -8, -8, nil, 1)
    panel.apocOuterBottom = AddAPOCBorderTexture(panel, "BOTTOMLEFT", 8, 8, "BOTTOMRIGHT", -8, 8, nil, 1)
    panel.apocOuterLeft = AddAPOCBorderTexture(panel, "TOPLEFT", 8, -8, "BOTTOMLEFT", 8, 8, 1, nil)
    panel.apocOuterRight = AddAPOCBorderTexture(panel, "TOPRIGHT", -8, -8, "BOTTOMRIGHT", -8, 8, 1, nil)
    panel.apocTitleLine = AddAPOCBorderTexture(panel, "TOPLEFT", 8, -30, "TOPRIGHT", -8, -30, nil, 1)
  else
    SetAPOCGoldTexture(panel.apocOuterTop)
    SetAPOCGoldTexture(panel.apocOuterBottom)
    SetAPOCGoldTexture(panel.apocOuterLeft)
    SetAPOCGoldTexture(panel.apocOuterRight)
    SetAPOCGoldTexture(panel.apocTitleLine)
  end

  if panel.Bg then
    panel.Bg:SetAlpha(0)
  end

  if panel.Inset and panel.Inset.Bg then
    panel.Inset.Bg:SetAlpha(0)
  end

  if panel.Inset and panel.Inset.GetRegions then
    for _, region in ipairs({panel.Inset:GetRegions()}) do
      if region and region.SetAlpha then
        region:SetAlpha(0)
      end
    end
  end

  if panel.SetBackdropColor then
    panel:SetBackdropColor(APOC_PANEL_BG_R, APOC_PANEL_BG_G, APOC_PANEL_BG_B, APOC_PANEL_BG_A)
  end

  if panel.Inset and panel.Inset.SetBackdropColor then
    panel.Inset:SetBackdropColor(APOC_PANEL_BG_R, APOC_PANEL_BG_G, APOC_PANEL_BG_B, APOC_PANEL_BG_A)
  end
end

local function SetAPOCPanelTexture(texture, alpha)
  SetAPOCBodyTexture(texture, alpha)
end

local function SetAPOCRowTexture(texture, alpha)
  SetTextureColor(texture, APOC_ROW_BG_R, APOC_ROW_BG_G, APOC_ROW_BG_B, alpha or APOC_ROW_BG_A)
end

local function AddButtonBorder(button)
  if not button or button.apocButtonBorderTop then return end

  local top = button:CreateTexture(nil, "OVERLAY")
  top:SetPoint("TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", 0, 0)
  top:SetHeight(1)
  SetAPOCGoldTexture(top, .72)

  local bottom = button:CreateTexture(nil, "OVERLAY")
  bottom:SetPoint("BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(1)
  SetAPOCGoldTexture(bottom, .45)

  local left = button:CreateTexture(nil, "OVERLAY")
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", 0, 0)
  left:SetWidth(1)
  SetAPOCGoldTexture(left, .45)

  local right = button:CreateTexture(nil, "OVERLAY")
  right:SetPoint("TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)
  right:SetWidth(1)
  SetAPOCGoldTexture(right, .45)

  button.apocButtonBorderTop = top
  button.apocButtonBorderBottom = bottom
  button.apocButtonBorderLeft = left
  button.apocButtonBorderRight = right
end

local function StyleAPOCButton(button)
  if not button or not button.GetText then return end
  local text = button:GetText()
  if not text or text == "" then return end

  if button.SetNormalTexture then button:SetNormalTexture("Interface\\Buttons\\WHITE8X8") end
  if button.SetPushedTexture then button:SetPushedTexture("Interface\\Buttons\\WHITE8X8") end
  if button.SetDisabledTexture then button:SetDisabledTexture("Interface\\Buttons\\WHITE8X8") end
  if button.SetHighlightTexture then button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8") end

  local normal = button.GetNormalTexture and button:GetNormalTexture()
  local pushed = button.GetPushedTexture and button:GetPushedTexture()
  local disabled = button.GetDisabledTexture and button:GetDisabledTexture()
  local highlight = button.GetHighlightTexture and button:GetHighlightTexture()

  local selected = button.apocSelected and true or false
  if normal then
    if selected then
      SetTextureColor(normal, .28, .22, .10, 1)
    else
      SetTextureColor(normal, .085, .095, .115, .96)
    end
  end
  if pushed then SetTextureColor(pushed, selected and .34 or .13, selected and .26 or .11, selected and .11 or .055, 1) end
  if disabled then SetTextureColor(disabled, .035, .038, .045, .75) end
  if highlight then
    SetTextureColor(highlight, .55, .40, .12, .22)
    if highlight.SetBlendMode then highlight:SetBlendMode("ADD") end
  end

  local label = button.GetFontString and button:GetFontString()
  if label then
    label:SetTextColor(1, selected and .94 or .86, selected and .58 or .38)
  end

  AddButtonBorder(button)
end

local function SetAPOCButtonSelected(button, selected)
  if not button then return end
  button.apocSelected = selected and true or false
  StyleAPOCButton(button)
end

local function StyleAPOCFrameTree(frame)
  if not frame or not frame.GetChildren then return end

  for _, child in ipairs({frame:GetChildren()}) do
    if child and child.GetObjectType and child:GetObjectType() == "Button" then
      StyleAPOCButton(child)
    end
    StyleAPOCFrameTree(child)
  end
end

local function StyleAPOCPanelTitle(frame)
  if not frame or not frame.title then return end

  local title = frame.title
  if title.SetFont then
    title:SetFont(STANDARD_TEXT_FONT, 12, "")
  end
  if title.SetTextColor then
    title:SetTextColor(1, .86, .34)
  end
  if title.SetHeight then
    title:SetHeight(16)
  end
  if title.SetJustifyV then
    title:SetJustifyV("MIDDLE")
  end

  local justify = title.GetJustifyH and title:GetJustifyH() or "LEFT"
  title:ClearAllPoints()
  if justify == "CENTER" then
    title:SetPoint("TOPLEFT", 46, -11)
    title:SetPoint("TOPRIGHT", -46, -11)
    title:SetJustifyH("CENTER")
  else
    title:SetPoint("TOPLEFT", 18, -11)
    title:SetPoint("TOPRIGHT", -38, -11)
    title:SetJustifyH("LEFT")
  end
end

local function SetAddonFrameLayer(frame, level)
  if not frame then return end
  if frame.SetFrameStrata then frame:SetFrameStrata(ADDON_FRAME_STRATA) end
  if frame.SetFrameLevel then frame:SetFrameLevel(level or ADDON_FRAME_LEVEL) end
  if frame.SetToplevel then frame:SetToplevel(true) end
  ApplyAPOCPanelBackdrop(frame)
  StyleAPOCFrameTree(frame)
  StyleAPOCPanelTitle(frame)
end

local function GetSavedPanelSize(key, defaultWidth, defaultHeight)
  if APOCLootPrio and APOCLootPrio.InitDB then APOCLootPrio:InitDB() end
  local saved = APOCLootPrioDB and APOCLootPrioDB.ui and APOCLootPrioDB.ui[key]
  local width = saved and tonumber(saved.width) or defaultWidth
  local height = saved and tonumber(saved.height) or defaultHeight
  return width or defaultWidth, height or defaultHeight
end

local function ClampNumber(value, minValue, maxValue)
  value = tonumber(value)
  if not value then return minValue end
  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function SavePanelSize(key, frame, minWidth, minHeight, maxWidth, maxHeight)
  if not key or not frame or not frame.GetWidth or not frame.GetHeight then return end
  if APOCLootPrio and APOCLootPrio.InitDB then APOCLootPrio:InitDB() end
  APOCLootPrioDB.ui[key] = APOCLootPrioDB.ui[key] or {}

  local width = math.floor((frame:GetWidth() or minWidth) + .5)
  local height = math.floor((frame:GetHeight() or minHeight) + .5)
  if minWidth and width < minWidth then width = minWidth end
  if minHeight and height < minHeight then height = minHeight end
  if maxWidth and width > maxWidth then width = maxWidth end
  if maxHeight and height > maxHeight then height = maxHeight end

  APOCLootPrioDB.ui[key].width = width
  APOCLootPrioDB.ui[key].height = height
end

local function AddResizeGrip(frame, key, minWidth, minHeight, maxWidth, maxHeight, onResize)
  if not frame or frame.apocResizeGrip then return end

  if frame.SetResizable then frame:SetResizable(true) end
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
  else
    if frame.SetMinResize then frame:SetMinResize(minWidth, minHeight) end
    if frame.SetMaxResize then frame:SetMaxResize(maxWidth, maxHeight) end
  end

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(18, 18)
  grip:SetPoint("BOTTOMRIGHT", -9, 9)
  grip:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or ADDON_FRAME_LEVEL) + 8)

  local normal = grip:CreateTexture(nil, "ARTWORK")
  normal:SetAllPoints(grip)
  normal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetNormalTexture(normal)

  local highlight = grip:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(grip)
  highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  highlight:SetBlendMode("ADD")
  grip:SetHighlightTexture(highlight)

  local pushed = grip:CreateTexture(nil, "ARTWORK")
  pushed:SetAllPoints(grip)
  pushed:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetPushedTexture(pushed)

  grip:SetScript("OnMouseDown", function()
    if frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end
  end)
  grip:SetScript("OnMouseUp", function()
    if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
    SavePanelSize(key, frame, minWidth, minHeight, maxWidth, maxHeight)
    if onResize then onResize(frame) end
  end)

  frame:SetScript("OnSizeChanged", function(resizedFrame)
    if onResize then onResize(resizedFrame) end
  end)

  frame.apocResizeGrip = grip
end

local function SetControlEnabled(control, enabled)
  if not control then return end
  if enabled then
    if control.Enable then control:Enable() end
    if control.EnableMouse then control:EnableMouse(true) end
    if control.SetAlpha then control:SetAlpha(1) end
  else
    if control.Disable then control:Disable() end
    if control.EnableMouse then control:EnableMouse(false) end
    if control.SetAlpha then control:SetAlpha(.45) end
  end
end

local function SetControlShown(control, shown)
  if not control then return end
  if shown then
    control:Show()
  else
    control:Hide()
  end
end

local function EnableCleanMouseWheelScroll(scroll, step)
  if not scroll then return end
  step = step or 36
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  scroll:SetScript("OnMouseWheel", function(frame, delta)
    if not frame.GetVerticalScroll or not frame.SetVerticalScroll then return end
    local current = frame:GetVerticalScroll() or 0
    local maxScroll = frame.GetVerticalScrollRange and frame:GetVerticalScrollRange() or 0
    local nextScroll = current - ((delta or 0) * step)
    if nextScroll < 0 then nextScroll = 0 end
    if nextScroll > maxScroll then nextScroll = maxScroll end
    frame:SetVerticalScroll(nextScroll)
    if frame.UpdateAPOCScrollBar then frame:UpdateAPOCScrollBar() end
  end)
end

local function AppendColoredPriorityToken(parts, token)
  if token == "" then return end
  local color = CLASS_TOKEN_COLORS[string.lower(token)]

  if color then
    table.insert(parts, color .. token .. COLOR_RESET)
  else
    table.insert(parts, token)
  end
end

local function IsPriorityWordCharacter(character)
  return character and character ~= "" and string.match(character, "[%w']")
end

local function PriorityTextContainsTerm(text, term)
  text = string.lower(tostring(text or ""))
  term = string.lower(tostring(term or ""))
  if text == "" or term == "" then return false end

  local startIndex = 1
  while true do
    local foundStart, foundEnd = string.find(text, term, startIndex, true)
    if not foundStart then return false end

    local before = foundStart > 1 and string.sub(text, foundStart - 1, foundStart - 1) or ""
    local after = string.sub(text, foundEnd + 1, foundEnd + 1)
    if not IsPriorityWordCharacter(before) and not IsPriorityWordCharacter(after) then
      return true
    end

    startIndex = foundEnd + 1
  end
end

local function AppendColoredPriorityPhrase(parts, text, index)
  for _, phrase in ipairs(PRIORITY_PHRASE_COLORS) do
    local phraseText = phrase.text
    local phraseLength = string.len(phraseText)
    local candidate = string.sub(text, index, index + phraseLength - 1)
    local nextCharacter = string.sub(text, index + phraseLength, index + phraseLength)

    if string.lower(candidate) == string.lower(phraseText) and not IsPriorityWordCharacter(nextCharacter) then
      table.insert(parts, phrase.color .. candidate .. COLOR_RESET)
      return phraseLength
    end
  end

  return 0
end

local function ColorizePriorityText(text)
  text = tostring(text or "")

  local parts = {}
  local token = ""
  local index = 1

  while index <= string.len(text) do
    local phraseLength = AppendColoredPriorityPhrase(parts, text, index)
    if phraseLength > 0 then
      token = ""
      index = index + phraseLength
    else
    local character = string.sub(text, index, index)
    if string.match(character, "[%w']") then
      token = token .. character
    else
      AppendColoredPriorityToken(parts, token)
      token = ""
      table.insert(parts, character)
    end
      index = index + 1
    end
  end

  AppendColoredPriorityToken(parts, token)

  return table.concat(parts)
end

local function AwardTypeText(awardType)
  return APOCLootPrio:GetAwardTypeLabel(awardType or "MS")
end

local function AwardTypeShort(awardType)
  awardType = APOCLootPrio:NormalizeAwardType(awardType)
  if awardType == "OS" then return "OS" end
  if awardType == "DE" then return "DE" end
  if awardType == "GB" then return "GB" end
  return "MS"
end

local function SetLogPanelOffset(panel, x)
  if not panel or not panel.ownerFrame then return end
  panel.currentX = x
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", panel.ownerFrame, "TOPRIGHT", x, 0)
end

local function AnimateLogPanel(panel, show)
  if not panel then return end

  local panelWidth = panel.panelWidth or LOG_PANEL_WIDTH
  local hiddenX = -panelWidth
  local visibleX = LOG_PANEL_GAP
  local fromX = panel.currentX or (show and hiddenX or visibleX)
  local toX = show and visibleX or hiddenX

  panel.animationElapsed = 0
  panel.animationFromX = fromX
  panel.animationToX = toX
  panel.animationHideWhenDone = not show

  panel:Show()
  panel:SetScript("OnUpdate", function(self, elapsed)
    self.animationElapsed = (self.animationElapsed or 0) + (elapsed or 0)
    local progress = math.min(self.animationElapsed / LOG_PANEL_ANIMATION_SECONDS, 1)
    local eased = 1 - ((1 - progress) * (1 - progress))
    SetLogPanelOffset(self, self.animationFromX + ((self.animationToX - self.animationFromX) * eased))

    if progress >= 1 then
      self:SetScript("OnUpdate", nil)
      if self.animationHideWhenDone then self:Hide() end
    end
  end)
end

local function GetItemIcon(item)
  local id = APOCLootPrio:GetItemID(item)

  if id and GetItemInfoInstant then
    local _, _, _, _, icon = GetItemInfoInstant(id)
    if icon then return icon end
  end

  if id and GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if icon then return icon end
  end

  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetItemQualityRGB(item)
  local quality = APOCLootPrio:GetItemQuality(item)

  if quality and GetItemQualityColor then
    local r, g, b = GetItemQualityColor(quality)
    if r and g and b then return r, g, b end
  end

  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    local color = ITEM_QUALITY_COLORS[quality]
    if color.r and color.g and color.b then return color.r, color.g, color.b end
  end

  local link = item and (APOCLootPrio:GetCachedItemLink(item) or item.link)
  local rHex, gHex, bHex = string.match(link or "", "^|cff(%x%x)(%x%x)(%x%x)")
  if rHex and gHex and bHex then
    return tonumber(rHex, 16) / 255, tonumber(gHex, 16) / 255, tonumber(bHex, 16) / 255
  end

  return .72, .25, 1
end

local function RaiseGameTooltip()
  if not GameTooltip then return end
  if GameTooltip.SetFrameStrata then GameTooltip:SetFrameStrata("TOOLTIP") end
  if GameTooltip.SetFrameLevel then GameTooltip:SetFrameLevel(ADDON_FRAME_LEVEL + 1000) end
  if GameTooltip.SetToplevel then GameTooltip:SetToplevel(true) end
end

local function SetCleanItemIcon(icon, item)
  if not icon then return end
  icon:SetTexture(GetItemIcon(item))
  if icon.SetTexCoord then icon:SetTexCoord(.08, .92, .08, .92) end
end

local function HideItemIconFrame(frame)
  if not frame then return end
  if frame.SetTexture then frame:SetTexture(nil) end
  if frame.Hide then frame:Hide() end
end

local function ShowItemTooltip(owner, item)
  RaiseGameTooltip()
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  local itemRef = APOCLootPrio:GetTooltipItemRef(item)
  if itemRef then
    GameTooltip:SetHyperlink(itemRef)
  else
    GameTooltip:SetText(item.name or "Unknown item", 1, 1, 1)
    GameTooltip:AddLine("Full item tooltip needs an item ID or cached item data.", .7, .7, .7, true)
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Priority: " .. ColorizePriorityText(APOCLootPrio:GetItemBias(item) or "None"), 1, 1, 1, true)
  local note = APOCLootPrio:GetItemNote(item)
  if note then GameTooltip:AddLine("Note: " .. note, .75, .75, .75, true) end
  RaiseGameTooltip()
  GameTooltip:Show()
end

local function InsertItemLinkIntoChat(item)
  if not item or not IsShiftKeyDown or not IsShiftKeyDown() then return false end
  if not ChatEdit_InsertLink then return false end

  local link = APOCLootPrio:GetCachedItemLink(item) or item.link
  if link and string.sub(link, 1, 1) == "|" then
    ChatEdit_InsertLink(link)
    return true
  end

  return false
end

local function AddBossHeader(parent, bossName, y)
  local header = CreateFrame("Frame", nil, parent)
  header:SetSize(CONTENT_WIDTH - 12, BOSS_HEADER_HEIGHT)
  header:SetPoint("TOPLEFT", 6, y)

  local line = header:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("BOTTOMLEFT", 0, 2)
  line:SetPoint("BOTTOMRIGHT", 0, 2)
  line:SetHeight(1)
  SetAPOCGoldTexture(line, .55)

  local text = Font(header, 15, bossName, "GameFontHighlight")
  text:SetPoint("LEFT", 0, 4)
  text:SetTextColor(1, .86, .34)

  return header
end

local function AddItemRow(parent, item, bossName, x, y)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(COLUMN_WIDTH, ITEM_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", x, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnEnter", function(button) ShowItemTooltip(button, item) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function()
    if InsertItemLinkIntoChat(item) then return end

    if APOCLootPrio.raidLootPanelShown then
      APOCLootPrio:SelectRaidLootItem(item, bossName)
      return
    end

    if APOCLootPrio.adminMode then
      APOCLootPrio:SelectAdminItem(item)
    end
  end)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", -4, -1)
  bg:SetPoint("BOTTOMRIGHT", 0, 1)
  SetAPOCRowTexture(bg, .78)

  local divider = row:CreateTexture(nil, "BORDER")
  divider:SetPoint("BOTTOMLEFT", 0, 0)
  divider:SetPoint("BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  SetTextureColor(divider, .22, .22, .24, .75)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT", 2, 0)
  SetCleanItemIcon(icon, item)

  local border = row:CreateTexture(nil, "OVERLAY")
  border:SetSize(ICON_SIZE + 16, ICON_SIZE + 16)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)
  HideItemIconFrame(border)
  border:SetVertexColor(GetItemQualityRGB(item))

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(icon)
  highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  highlight:SetBlendMode("ADD")

  local name = Font(row, 12, item.name or "Unknown item", "GameFontNormal")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
  name:SetWidth(COLUMN_WIDTH - ICON_SIZE - 10)
  name:SetJustifyH("LEFT")
  name:SetTextColor(GetItemQualityRGB(item))

  local bias = Font(row, 11, ColorizePriorityText(APOCLootPrio:GetItemBias(item) or "No priority"), "GameFontHighlight")
  bias:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  bias:SetWidth(COLUMN_WIDTH - ICON_SIZE - 10)
  bias:SetJustifyH("LEFT")
  bias:SetTextColor(1, 1, 1)

  return row
end

local function MatchesQuery(item, query)
  return query == "" or string.find(string.lower(item.name or ""), query, 1, true)
end

local function TrimText(text)
  return string.match(text or "", "^%s*(.-)%s*$")
end

local function ShortDisplayName(name)
  return string.match(name or "", "^([^%-]+)") or name
end

local function RosterNameKey(name)
  return string.lower(ShortDisplayName(name) or name or "")
end

local function IsUiPlayerInRaidGroup()
  if IsInRaid and IsInRaid() then return true end
  if GetNumGroupMembers and GetNumGroupMembers() > 5 then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  return false
end

local function GetGuildPlayerClassFileName(name)
  if not name or not APOCLootPrio.GetGuildLootSummary then return nil end

  local targetKey = RosterNameKey(name)
  for _, player in ipairs(APOCLootPrio:GetGuildLootSummary() or {}) do
    if RosterNameKey(player.name) == targetKey then
      return player.classFileName, player.className
    end
  end

  return nil
end

local function GetGroupMemberClassFileName(memberName)
  if not memberName then return nil end
  local targetKey = RosterNameKey(memberName)

  if GetRaidRosterInfo then
    local raidSize = GetNumGroupMembers and GetNumGroupMembers() or 0
    if raidSize == 0 and GetNumRaidMembers then raidSize = GetNumRaidMembers() end
    if raidSize == 0 then raidSize = 40 end

    for index = 1, raidSize do
      local rosterName, _, _, _, className, classFileName = GetRaidRosterInfo(index)
      if rosterName and RosterNameKey(rosterName) == targetKey then
        return classFileName, className
      end
    end
  end

  local function unitMatches(unit)
    if not UnitName then return nil end
    local name, realm = UnitName(unit)
    if not name then return nil end

    local fullName = realm and realm ~= "" and (name .. "-" .. realm) or name
    if RosterNameKey(fullName) == targetKey or RosterNameKey(name) == targetKey then
      if UnitClass then
        local className, classFileName = UnitClass(unit)
        return classFileName, className
      end
    end
    return nil
  end

  local classFileName, className = unitMatches("player")
  if classFileName then return classFileName, className end

  local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  if IsUiPlayerInRaidGroup() then
    if groupSize == 0 and GetNumRaidMembers then groupSize = GetNumRaidMembers() end
    for index = 1, groupSize do
      classFileName, className = unitMatches("raid" .. tostring(index))
      if classFileName then return classFileName, className end
    end
  else
    local partySize = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if partySize == 0 and GetNumPartyMembers then partySize = GetNumPartyMembers() end
    for index = 1, partySize do
      classFileName, className = unitMatches("party" .. tostring(index))
      if classFileName then return classFileName, className end
    end
  end

  return GetGuildPlayerClassFileName(memberName)
end

local function GetGroupMemberClassRGB(memberName)
  local classFileName, className = GetGroupMemberClassFileName(memberName)
  return GetPlayerClassRGB({classFileName = classFileName, className = className})
end

local function ColorHexFromRGB(r, g, b)
  r = math.max(0, math.min(255, math.floor((r or 1) * 255 + .5)))
  g = math.max(0, math.min(255, math.floor((g or 1) * 255 + .5)))
  b = math.max(0, math.min(255, math.floor((b or 1) * 255 + .5)))
  return string.format("|cff%02x%02x%02x", r, g, b)
end

local function ColorizeGroupMemberName(memberName, displayName)
  local r, g, b = GetGroupMemberClassRGB(memberName)
  return ColorHexFromRGB(r, g, b) .. tostring(displayName or memberName or "") .. COLOR_RESET
end

local function NormalizeClassFileName(classFileName, className)
  local value = classFileName or className or ""
  value = string.upper(tostring(value))
  value = string.gsub(value, "%s+", "")
  return value
end

local function PlayerMatchesPriorityRule(classFileName, role, rule)
  if not rule then return false end
  if rule.class and NormalizeClassFileName(classFileName) ~= rule.class then
    return false
  end
  if rule.role and role and role ~= rule.role then
    return false
  end
  return rule.class ~= nil or rule.role ~= nil
end

local function IsRollerPriorityMatch(drop, memberName)
  local priorityText = tostring((drop and (drop.bias or drop.note)) or "")
  if priorityText == "" or priorityText == "None" or not memberName then return false end

  local classFileName, className = GetGroupMemberClassFileName(memberName)
  local playerClass = NormalizeClassFileName(classFileName, className)
  if playerClass == "" then return false end

  local role = APOCLootPrio.GetGroupMemberRole and APOCLootPrio:GetGroupMemberRole(memberName) or nil
  for _, rule in ipairs(PRIORITY_MATCH_RULES) do
    if PriorityTextContainsTerm(priorityText, rule.text) and PlayerMatchesPriorityRule(playerClass, role, rule) then
      return true
    end
  end

  return false
end

local function FilterItems(items, query)
  local filtered = {}
  for _, item in ipairs(items) do
    if MatchesQuery(item, query) then
      table.insert(filtered, item)
    end
  end
  return filtered
end

local function AddEditorLabel(parent, text, x, y)
  local label = Font(parent, 11, text)
  label:SetPoint("TOPLEFT", x, y)
  label:SetTextColor(.85, .75, .45)
  return label
end

local ADMIN_SPEC_GROUPS = {
  {name = "Paladin", color = { .96, .55, .73 }, specs = {"Protection Paladin", "Holy Paladin", "Retribution Paladin"}},
  {name = "Warrior", color = { .78, .61, .43 }, specs = {"Protection Warrior", "Arms Warrior", "Fury Warrior"}},
  {name = "Rogue", color = { 1, .96, .41 }, specs = {"Assassination Rogue", "Combat Rogue", "Subtlety Rogue"}},
  {name = "Hunter", color = { .67, .83, .45 }, specs = {"Beast Mastery Hunter", "Marksmanship Hunter", "Survival Hunter"}},
  {name = "Druid", color = { 1, .49, .04 }, specs = {"Restoration Druid", "Feral Bear Druid", "Feral Cat Druid", "Balance Druid"}},
  {name = "Priest", color = { 1, 1, 1 }, specs = {"Holy Priest", "Discipline Priest", "Shadow Priest"}},
  {name = "Shaman", color = { 0, .44, .87 }, specs = {"Restoration Shaman", "Elemental Shaman", "Enhancement Shaman"}},
  {name = "Mage", color = { .25, .78, .92 }, specs = {"Arcane Mage", "Fire Mage", "Frost Mage"}},
  {name = "Warlock", color = { .53, .53, .93 }, specs = {"Affliction Warlock", "Demonology Warlock", "Destruction Warlock"}},
}

local function AppendAdminPriorityText(panel, text)
  if not panel or not panel.bias then return end
  panel.bias:SetText((panel.bias:GetText() or "") .. tostring(text or ""))
  panel.bias:SetFocus()
end

local function CreateAdminPill(parent, text, x, y, width, color)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 20)
  button:SetPoint("TOPLEFT", x, y)
  button:SetText(text)
  button:SetScript("OnClick", function() AppendAdminPriorityText(parent, text) end)
  if button.GetFontString and color then
    local label = button:GetFontString()
    if label then label:SetTextColor(color[1], color[2], color[3]) end
  end
  return button
end

local function CreateAdminPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioAdminPanel", UIParent, "BasicFrameTemplateWithInset")
  panel:SetSize(560, 620)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 8, 22)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 8)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.45, .35, .18, .72)
  border:Hide()

  panel.title = Font(panel, 13, "Admin Priority Edit", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 14, -10)
  panel.title:SetPoint("TOPRIGHT", -32, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetAdminMode(false) end)

  panel.itemName = Font(panel, 11, "Select an item to edit", "GameFontNormalSmall")
  panel.itemName:SetPoint("TOPLEFT", 14, -34)
  panel.itemName:SetPoint("TOPRIGHT", -14, -34)
  panel.itemName:SetJustifyH("LEFT")
  panel.itemName:SetTextColor(.85, .78, .65)

  AddEditorLabel(panel, "Priority", 14, -62)
  panel.bias = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.bias:SetSize(430, 24)
  panel.bias:SetPoint("TOPLEFT", 82, -60)
  panel.bias:SetAutoFocus(false)
  panel.bias:SetMaxLetters(140)
  panel.bias:SetTextInsets(6, 6, 0, 0)

  local greater = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  greater:SetSize(48, 22)
  greater:SetPoint("TOPLEFT", 82, -90)
  greater:SetText(">")
  greater:SetScript("OnClick", function() AppendAdminPriorityText(panel, " > ") end)

  local equal = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  equal:SetSize(48, 22)
  equal:SetPoint("LEFT", greater, "RIGHT", 8, 0)
  equal:SetText("=")
  equal:SetScript("OnClick", function() AppendAdminPriorityText(panel, " = ") end)

  local classY = -124
  local pillWidth = 170
  for index, group in ipairs(ADMIN_SPEC_GROUPS) do
    local column = (index - 1) % 3
    local row = math.floor((index - 1) / 3)
    CreateAdminPill(panel, group.name, 14 + (column * (pillWidth + 8)), classY - (row * 24), pillWidth, group.color)
  end

  local specY = -210
  for groupIndex, group in ipairs(ADMIN_SPEC_GROUPS) do
    local column = (groupIndex - 1) % 3
    local row = math.floor((groupIndex - 1) / 3)
    local x = 14 + (column * (pillWidth + 8))
    local y = specY - (row * 112)

    local heading = Font(panel, 10, group.name, "GameFontNormalSmall")
    heading:SetPoint("TOPLEFT", x + 4, y)
    heading:SetTextColor(group.color[1], group.color[2], group.color[3])

    for specIndex, spec in ipairs(group.specs) do
      CreateAdminPill(panel, spec, x, y - 18 - ((specIndex - 1) * 22), pillWidth, group.color)
    end
  end

  AddEditorLabel(panel, "Note", 14, -526)
  panel.note = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.note:SetSize(430, 24)
  panel.note:SetPoint("TOPLEFT", 82, -524)
  panel.note:SetAutoFocus(false)
  panel.note:SetMaxLetters(90)
  panel.note:SetTextInsets(6, 6, 0, 0)

  panel.save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.save:SetSize(82, 24)
  panel.save:SetPoint("TOPLEFT", 14, -562)
  panel.save:SetText("Save")
  panel.save:SetScript("OnClick", function() APOCLootPrio:SaveAdminItem() end)

  panel.status = Font(panel, 11, "Admin mode: item clicks select rows for editing.")
  panel.status:SetPoint("LEFT", panel.save, "RIGHT", 10, 0)
  panel.status:SetPoint("RIGHT", -14, 0)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateLogPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLogPanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel.panelWidth = LOG_PANEL_WIDTH
  panel:SetSize(LOG_PANEL_WIDTH, FRAME_HEIGHT)
  SetLogPanelOffset(panel, -LOG_PANEL_WIDTH)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL - 1)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.45, .35, .18, .7)
  border:Hide()

  panel.title = Font(panel, 12, "Admin Log", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", 0, 0)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLogPanelShown(false) end)

  panel.log = Font(panel, 10, "No admin saves logged yet.", "GameFontNormalSmall")
  panel.log:SetPoint("TOPLEFT", 10, -34)
  panel.log:SetPoint("BOTTOMRIGHT", -10, 10)
  panel.log:SetJustifyH("LEFT")
  panel.log:SetJustifyV("TOP")
  panel.log:SetTextColor(.78, .78, .78)

  return panel
end

local function CreateSideRow(parent, y, text, onClick, selected)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(parent.rowWidth or (RAID_LOOT_WINDOW_WIDTH - 38), SIDE_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, y)
  row:RegisterForClicks("LeftButtonUp")

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  if selected then
    SetTextureColor(bg, .28, .08, .06, .85)
  else
    SetAPOCRowTexture(bg, .78)
  end

  local label = Font(row, 10, text or "", "GameFontNormalSmall")
  label:SetPoint("LEFT", 6, 0)
  label:SetPoint("RIGHT", -6, 0)
  label:SetJustifyH("LEFT")
  label:SetTextColor(.9, .84, .72)
  row:SetScript("OnClick", onClick)
  return row
end

local function UpdateAwardTypeButtons(panel)
  if not panel or not panel.awardTypeButtons then return end
  local selectedType = APOCLootPrio:NormalizeAwardType(panel.awardType or "MS")
  for awardType, button in pairs(panel.awardTypeButtons) do
    if awardType == selectedType then
      button:LockHighlight()
    else
      button:UnlockHighlight()
    end
  end
end

local function SetPanelAwardType(panel, awardType)
  if not panel then return end
  panel.awardType = APOCLootPrio:NormalizeAwardType(awardType)
  local guildBank = panel.awardType == "GB"
  for _, fieldName in ipairs({"winner", "editWinner"}) do
    local field = panel[fieldName]
    if field then
      if guildBank then field:SetText("") end
    end
  end
  if guildBank then panel.selectedWinnerName = nil end
  UpdateAwardTypeButtons(panel)
end

local function AddAwardTypeButtons(panel, x, y, buttonWidth, parent)
  panel.awardTypeButtons = {}
  parent = parent or panel
  local types = {
    {key = "MS", text = "MS"},
    {key = "OS", text = "OS"},
    {key = "DE", text = "DE"},
    {key = "GB", text = "Guild Bank", width = 78},
  }

  for index, option in ipairs(types) do
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    local width = option.width or buttonWidth or 54
    local offset = (index - 1) * ((buttonWidth or 54) + 6)
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", x + offset, y)
    button:SetText(option.text)
    button:SetScript("OnClick", function() SetPanelAwardType(panel, option.key) end)
    panel.awardTypeButtons[option.key] = button
  end

  SetPanelAwardType(panel, "MS")
end

local function DropAsItem(drop)
  if not drop then return nil end
  return {
    name = drop.item,
    id = drop.itemID,
    link = drop.itemLink,
    quality = drop.itemQuality,
    bias = drop.bias,
    note = drop.note,
  }
end

local function ShowDropTooltip(owner, drop)
  local item = DropAsItem(drop)
  if item then
    ShowItemTooltip(owner, item)
  end
end

local LOOT_BOSS_HEADER_HEIGHT = 24

local function GetLootBossGroupLabel(drop)
  local boss = TrimText(drop and drop.boss or "")
  local key = string.lower(boss)
  if key == "trash" or key == "trash loot" then
    return "Trash", "trash"
  end
  if boss == "" or key == "unknown" or key == "unknown boss" then
    return "Unknown", "unknown"
  end
  return boss, key
end

local function GroupLootDropsByBoss(drops)
  local groups = {}
  local byKey = {}

  for _, drop in ipairs(drops or {}) do
    local label, key = GetLootBossGroupLabel(drop)
    local group = byKey[key]
    if not group then
      group = {label = label, key = key, drops = {}}
      byKey[key] = group
      table.insert(groups, group)
    end
    table.insert(group.drops, drop)
  end

  table.sort(groups, function(left, right)
    if left.key == "trash" then return false end
    if right.key == "trash" then return true end
    return string.lower(left.label) < string.lower(right.label)
  end)

  return groups
end

local function CreateLootBossHeader(parent, y, label, count, collapsed, onClick)
  local header = CreateFrame("Button", nil, parent)
  header:SetSize(parent.rowWidth or (RAID_LOOT_WINDOW_WIDTH - 38), LOOT_BOSS_HEADER_HEIGHT)
  header:SetPoint("TOPLEFT", 0, y)
  header:RegisterForClicks("LeftButtonUp")
  header:SetScript("OnClick", onClick)

  local bg = header:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(header)
  SetTextureColor(bg, .12, .085, .035, .92)

  local title = Font(header, 11, label .. " (" .. tostring(count or 0) .. ")", "GameFontNormal")
  title:SetPoint("LEFT", 8, 0)
  title:SetPoint("RIGHT", -28, 0)
  title:SetJustifyH("LEFT")
  title:SetTextColor(1, .82, .16)

  local toggle = Font(header, 12, collapsed and "+" or "-", "GameFontNormal")
  toggle:SetPoint("RIGHT", -9, 0)
  toggle:SetJustifyH("RIGHT")
  toggle:SetTextColor(1, .82, .16)

  local highlight = header:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(header)
  SetTextureColor(highlight, .35, .24, .08, .35)

  local line = header:CreateTexture(nil, "ARTWORK")
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1)
  SetTextureColor(line, .45, .30, .10, .9)

  return header
end

local function CreateDropQueueRow(parent, y, drop, onClick, onSecondary, selected, canEdit, secondaryText)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(parent.rowWidth or (RAID_LOOT_WINDOW_WIDTH - 38), DROP_QUEUE_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", function()
    if InsertItemLinkIntoChat(DropAsItem(drop)) then return end
    if onClick then onClick() end
  end)
  row:SetScript("OnEnter", function(button) ShowDropTooltip(button, drop) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  if selected then
    SetTextureColor(bg, .28, .08, .06, .85)
  else
    SetAPOCRowTexture(bg, .78)
  end

  local item = DropAsItem(drop)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT", 2, 0)
  SetCleanItemIcon(icon, item)

  local border = row:CreateTexture(nil, "OVERLAY")
  border:SetSize(ICON_SIZE + 12, ICON_SIZE + 12)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)
  HideItemIconFrame(border)
  border:SetVertexColor(GetItemQualityRGB(item))

  local name = Font(row, 11, drop.item or "Unknown item", "GameFontNormal")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -4)
  name:SetPoint("RIGHT", -96, 0)
  name:SetJustifyH("LEFT")
  name:SetTextColor(GetItemQualityRGB(item))

  local status = "trade " .. (APOCLootPrio:FormatTradeTimeLeft(drop) or "")
  if drop.award and ((drop.award.winner and drop.award.winner ~= "") or APOCLootPrio:GetAwardType(drop) == "GB") then
    local isTraded = drop.award.tradedTo and drop.award.tradedTo ~= ""
    local winner = isTraded and drop.award.tradedTo or drop.award.winner
    local winnerText = ShortDisplayName(winner) or winner
    local label = APOCLootPrio:GetAwardType(drop) == "GB" and "Guild Bank" or ((isTraded and "Traded to " or "Awarded to ") .. ColorizeGroupMemberName(winner, winnerText))
    status = label .. " (" .. AwardTypeShort(APOCLootPrio:GetAwardType(drop)) .. ")"
  end

  local detailText = APOCLootPrio:FormatLootTime(drop.droppedAt) .. " - " .. status
  if not parent.bossGrouped then
    detailText = (drop.boss or "Unknown") .. " - " .. detailText
  end
  local detail = Font(row, 10, detailText, "GameFontNormalSmall")
  detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  detail:SetPoint("RIGHT", -96, 0)
  detail:SetJustifyH("LEFT")
  detail:SetTextColor(.86, .78, .62)

  local actionText = (drop.award and ((drop.award.winner and drop.award.winner ~= "") or APOCLootPrio:GetAwardType(drop) == "GB")) and "View" or (canEdit and "Award" or "View")
  secondaryText = secondaryText or "Del"
  local secondaryWidth = secondaryText == "Unaward" and 62 or 32

  local action = Font(row, 10, actionText, "GameFontHighlight")
  action:SetPoint("RIGHT", -(secondaryWidth + 12), 0)
  action:SetJustifyH("RIGHT")
  action:SetTextColor(1, .85, .2)

  local delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  delete:SetSize(secondaryWidth, 18)
  delete:SetPoint("RIGHT", -4, 0)
  delete:SetText(secondaryText)
  delete:SetScript("OnClick", onSecondary)
  delete:SetScript("OnEnter", function(button) ShowDropTooltip(button, drop) end)
  delete:SetScript("OnLeave", function() GameTooltip:Hide() end)
  SetControlEnabled(delete, canEdit)
  if not canEdit then delete:Hide() end

  return row
end

local function CreateAwardLedgerRow(parent, y, drop, onClick, selected)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(parent.rowWidth or (RAID_LOOT_WINDOW_WIDTH - 72), AWARD_LEDGER_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", function()
    if InsertItemLinkIntoChat(DropAsItem(drop)) then return end
    if onClick then onClick() end
  end)
  row:SetScript("OnEnter", function(button) ShowDropTooltip(button, drop) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  if selected then
    SetTextureColor(bg, .28, .08, .06, .85)
  else
    SetAPOCRowTexture(bg, .78)
  end

  local item = DropAsItem(drop)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(30, 30)
  icon:SetPoint("LEFT", 2, 0)
  SetCleanItemIcon(icon, item)

  local border = row:CreateTexture(nil, "OVERLAY")
  border:SetSize(40, 40)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)
  HideItemIconFrame(border)
  border:SetVertexColor(GetItemQualityRGB(item))

  local winner = drop.award and drop.award.winner or (drop.award and APOCLootPrio:GetAwardType(drop) == "GB" and "Guild Bank") or "Unknown"
  local winnerText = ShortDisplayName(winner) or winner
  local winnerColumnWidth = 122
  local name = Font(row, 10, drop.item or "Unknown item", "GameFontNormal")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -4)
  name:SetPoint("RIGHT", -(winnerColumnWidth + 12), 0)
  name:SetJustifyH("LEFT")
  name:SetTextColor(GetItemQualityRGB(item))

  local detail = Font(row, 9, APOCLootPrio:FormatLootTime(drop.award and drop.award.awardedAt or drop.droppedAt) .. " - " .. AwardTypeShort(APOCLootPrio:GetAwardType(drop)) .. " - " .. (drop.boss or "Unknown"), "GameFontNormalSmall")
  detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  detail:SetPoint("RIGHT", -(winnerColumnWidth + 12), 0)
  detail:SetJustifyH("LEFT")
  detail:SetTextColor(.86, .78, .62)

  local winnerLabel = Font(row, 10, winnerText, "GameFontHighlight")
  winnerLabel:SetPoint("TOPRIGHT", -8, -5)
  winnerLabel:SetSize(winnerColumnWidth, 14)
  winnerLabel:SetJustifyH("RIGHT")
  winnerLabel:SetTextColor(GetGroupMemberClassRGB(winner))

  local winnerDetail = Font(row, 8, "Winner", "GameFontNormalSmall")
  winnerDetail:SetPoint("TOPRIGHT", winnerLabel, "BOTTOMRIGHT", 0, -2)
  winnerDetail:SetSize(winnerColumnWidth, 12)
  winnerDetail:SetJustifyH("RIGHT")
  winnerDetail:SetTextColor(.72, .68, .58)

  return row
end

local function FormatLootRollSummary(drop)
  local roll = drop and drop.roll
  if not roll or not roll.startedAt then return "Results" end

  local left = APOCLootPrio:GetLootRollTimeLeft(drop)
  local prefix = (left and left > 0) and (tostring(left) .. "s") or "Closed"
  local needEntries = APOCLootPrio:GetLootRollTopEntries(drop, 5, "NEED")
  local greedEntries = APOCLootPrio:GetLootRollTopEntries(drop, 5, "GREED")
  if #needEntries == 0 and #greedEntries == 0 then
    return "Results (" .. prefix .. ")"
  end

  return "N" .. tostring(#needEntries) .. "/G" .. tostring(#greedEntries) .. " " .. prefix
end

local function FormatLootRollResultsText(drop)
  local roll = drop and drop.roll
  if not roll or not roll.startedAt then
    return "No roll has been started for the selected item."
  end

  local left = APOCLootPrio:GetLootRollTimeLeft(drop)
  local prefix = (left and left > 0) and (tostring(left) .. " seconds left") or "Closed"
  local needEntries = APOCLootPrio:GetLootRollTopEntries(drop, 5, "NEED")
  local greedEntries = APOCLootPrio:GetLootRollTopEntries(drop, 5, "GREED")
  local lines = {prefix}

  local winningEntry = APOCLootPrio:GetLootRollWinningEntry(drop)
  if winningEntry then
    local displayName = ShortDisplayName(winningEntry.name) or winningEntry.name or "?"
    local typeLabel = winningEntry.rollType == "GREED" and "OS winner" or "MS winner"
    if left and left > 0 then
      typeLabel = winningEntry.rollType == "GREED" and "OS lead" or "MS lead"
    end
    table.insert(lines, typeLabel .. ": " .. ColorizeGroupMemberName(winningEntry.name, displayName) .. " - " .. tostring(winningEntry.roll or 0))
  else
    table.insert(lines, "Waiting for rolls.")
  end

  local function addSection(label, entries)
    table.insert(lines, "")
    table.insert(lines, label)
    if #entries == 0 then
      table.insert(lines, "  none")
      return
    end
    for index, entry in ipairs(entries) do
      local displayName = ShortDisplayName(entry.name) or entry.name or "?"
      table.insert(lines, "  " .. tostring(index) .. ". " .. ColorizeGroupMemberName(entry.name, displayName) .. " - " .. tostring(entry.roll or 0))
    end
  end

  addSection("MS /roll 1-100", needEntries)
  addSection("OS /roll 1-99", greedEntries)

  if #needEntries == 0 and #greedEntries > 0 then
    table.insert(lines, "")
    table.insert(lines, "No MS rolls yet. OS is currently eligible.")
  end

  return table.concat(lines, "\n")
end

-- Roll results refresh frequently. Reuse rows and their regions instead of
-- allocating new frames every half-second (WoW frames are not garbage collected).
local function AcquireRollRow(parent, kind, frameType)
  parent.rollPools, parent.rollPoolUsed = parent.rollPools or {}, parent.rollPoolUsed or {}
  local pool = parent.rollPools[kind] or {}
  parent.rollPools[kind] = pool
  local index = (parent.rollPoolUsed[kind] or 0) + 1
  parent.rollPoolUsed[kind] = index
  local row = pool[index]
  if not row then
    row = CreateFrame(frameType, nil, parent)
    row.apocRollPooled, row.rollFonts, row.rollTextures = true, {}, {}
    pool[index] = row
  end
  row.fontIndex, row.textureIndex = 0, 0
  for _, region in ipairs(row.rollFonts) do region:Hide() end
  for _, region in ipairs(row.rollTextures) do region:Hide() end
  row:ClearAllPoints()
  row:Show()
  return row
end

local function RollFont(row, size, text, template)
  row.fontIndex = row.fontIndex + 1
  local font = row.rollFonts[row.fontIndex]
  if not font then
    font = Font(row, size, text, template)
    row.rollFonts[row.fontIndex] = font
  end
  font:ClearAllPoints()
  font:SetText(text or "")
  font:SetTextColor(1, 1, 1)
  font:Show()
  return font
end

local function RollTexture(row, layer)
  row.textureIndex = row.textureIndex + 1
  local texture = row.rollTextures[row.textureIndex]
  if not texture then
    texture = row:CreateTexture(nil, layer)
    row.rollTextures[row.textureIndex] = texture
  end
  texture:ClearAllPoints()
  texture:Show()
  return texture
end

local function CreateLootRollResultText(parent, y, text, colorR, colorG, colorB)
  local row = AcquireRollRow(parent, "text", "Frame")
  row:SetPoint("TOPLEFT", 0, y)
  row:SetSize(parent.rollRowWidth or 500, 18)

  local line = RollFont(row, 10, text or "", "GameFontNormalSmall")
  line:SetAllPoints(row)
  line:SetHeight(18)
  line:SetJustifyH("LEFT")
  line:SetTextColor(colorR or 1, colorG or .85, colorB or .2)
  return 18
end

local function CreateLootRollSectionHeader(parent, y, label)
  local rowWidth = parent.rollRowWidth or 500
  local row = AcquireRollRow(parent, "header", "Frame")
  row:SetPoint("TOPLEFT", 0, y)
  row:SetSize(rowWidth, 22)

  local bg = RollTexture(row, "BACKGROUND")
  bg:SetAllPoints(row)
  SetTextureColor(bg, .09, .07, .04, .74)

  local title = RollFont(row, 10, label or "", "GameFontHighlightSmall")
  title:SetPoint("LEFT", 8, 0)
  title:SetSize(rowWidth - 100, 18)
  title:SetJustifyH("LEFT")
  title:SetTextColor(1, .85, .2)

  local roll = RollFont(row, 9, "Roll", "GameFontNormalSmall")
  roll:SetPoint("RIGHT", -10, 0)
  roll:SetSize(60, 18)
  roll:SetJustifyH("RIGHT")
  roll:SetTextColor(.9, .84, .72)

  return 24
end

local function CreateLootRollResultPlayerRow(parent, y, dropOrID, entry, index)
  local rowWidth = parent.rollRowWidth or 500
  local drop = type(dropOrID) == "table" and dropOrID or (APOCLootPrio.FindRaidLootDrop and APOCLootPrio:FindRaidLootDrop(dropOrID))
  local dropID = type(dropOrID) == "table" and dropOrID.id or dropOrID
  local row = AcquireRollRow(parent, "player", "Button")
  row:SetPoint("TOPLEFT", 0, y)
  row:SetSize(rowWidth, 24)
  row:RegisterForClicks("LeftButtonUp")

  local bg = RollTexture(row, "BACKGROUND")
  bg:SetAllPoints(row)
  SetAPOCRowTexture(bg, .50)

  local rank = RollFont(row, 10, tostring(index or 1) .. ".", "GameFontNormalSmall")
  rank:SetPoint("LEFT", 8, 0)
  rank:SetSize(22, 18)
  rank:SetJustifyH("LEFT")
  rank:SetTextColor(1, .85, .2)

  local displayName = ShortDisplayName(entry and entry.name) or (entry and entry.name) or "?"
  local nameLeft = 34
  if IsRollerPriorityMatch(drop, entry and entry.name) then
    local priorityMark = RollTexture(row, "ARTWORK")
    priorityMark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    priorityMark:SetPoint("LEFT", nameLeft, 0)
    priorityMark:SetSize(16, 16)
    nameLeft = nameLeft + 22
  end
  local name = RollFont(row, 10, ColorizeGroupMemberName(entry and entry.name, displayName), "GameFontNormalSmall")
  name:SetPoint("LEFT", nameLeft, 0)
  name:SetSize(rowWidth - 178 - (nameLeft - 34), 18)
  name:SetJustifyH("LEFT")

  local winnerSlot = drop and entry and APOCLootPrio:GetLootRollWinnerSlot(drop, entry.name, entry.rollType) or nil
  local awardedCopy = drop and entry and APOCLootPrio:GetLootRollAwardedCopy(drop, entry.name, entry.rollType) or nil
  local rollText = tostring(entry and entry.roll or 0)
  if awardedCopy then
    rollText = rollText .. "  Awarded"
  elseif winnerSlot then
    rollText = rollText .. "  Winner " .. tostring(winnerSlot)
  end
  local roll = RollFont(row, 10, rollText, "GameFontNormalSmall")
  roll:SetPoint("RIGHT", -10, 0)
  roll:SetSize(124, 18)
  roll:SetJustifyH("RIGHT")
  if awardedCopy then
    roll:SetTextColor(.3, 1, .3)
  elseif winnerSlot then
    roll:SetTextColor(1, .85, .2)
  else
    roll:SetTextColor(.9, .84, .72)
  end

  row:SetScript("OnClick", function()
    if APOCLootPrio:CanEditLootTracker() and entry and entry.name then
      APOCLootPrio:SetLootRollAwardPromptShown(true, dropID, entry.name, entry.rollType)
    end
  end)
  row:SetScript("OnEnter", function(selfButton)
    if not GameTooltip then return end
    GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
    if not APOCLootPrio:CanEditLootTracker() then
      GameTooltip:SetText(tostring(displayName) .. " rolled " .. tostring(entry and entry.roll or 0), .9, .84, .72)
    elseif awardedCopy then
      GameTooltip:SetText(tostring(displayName) .. " has been awarded a copy", .3, 1, .3)
    elseif winnerSlot then
      GameTooltip:SetText("Award copy " .. tostring(winnerSlot) .. " to " .. tostring(displayName), 1, .85, .2)
      GameTooltip:AddLine("Choose MS, OS, or DE after the roll closes.", .9, .84, .72)
    else
      GameTooltip:SetText(tostring(displayName) .. " is outside the winning places", .9, .84, .72)
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  return 26
end

local function CreateLootRollDisenchanterRow(parent, y, drop, disenchanter)
  local rowWidth = parent.rollRowWidth or 500
  local row = AcquireRollRow(parent, "disenchanter", "Button")
  row:SetPoint("TOPLEFT", 0, y)
  row:SetSize(rowWidth, 28)
  row:RegisterForClicks("LeftButtonUp")

  local bg = RollTexture(row, "BACKGROUND")
  bg:SetAllPoints(row)
  SetAPOCRowTexture(bg, .56)

  local badge = RollFont(row, 10, "DE", "GameFontNormalSmall")
  badge:SetPoint("LEFT", 8, 0)
  badge:SetSize(28, 18)
  badge:SetTextColor(1, .85, .2)

  local displayName = ShortDisplayName(disenchanter) or disenchanter or "Not assigned"
  local name = RollFont(row, 10, ColorizeGroupMemberName(disenchanter, displayName), "GameFontNormalSmall")
  name:SetPoint("LEFT", 42, 0)
  name:SetSize(rowWidth - 170, 18)
  name:SetJustifyH("LEFT")

  local action = RollFont(row, 10, "Award DE", "GameFontNormalSmall")
  action:SetPoint("RIGHT", -10, 0)
  action:SetSize(110, 18)
  action:SetJustifyH("RIGHT")
  action:SetTextColor(1, .85, .2)

  row:SetScript("OnClick", function()
    if APOCLootPrio:CanEditLootTracker() then
      APOCLootPrio:SetLootRollAwardPromptShown(true, drop and drop.id, disenchanter, "DE")
    end
  end)
  row:SetScript("OnEnter", function(selfButton)
    if not GameTooltip then return end
    GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
    if APOCLootPrio:CanEditLootTracker() then
      GameTooltip:SetText("Award the next copy to " .. tostring(displayName) .. " for disenchant", 1, .85, .2)
      GameTooltip:AddLine("Available because the roll closed without an MS or OS roll.", .9, .84, .72)
    else
      GameTooltip:SetText(tostring(displayName) .. " is the assigned disenchanter", .9, .84, .72)
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return 30
end

local function CanStartLootRollForDrop(drop)
  return drop ~= nil and not drop.rollSourceDropID and not (drop.roll and drop.roll.startedAt)
end

local function GetLootRollButtonText(drop)
  if not drop or not drop.roll or not drop.roll.startedAt then
    if drop and drop.rollSourceDropID and drop.rollSourceDropID ~= drop.id then return "Grouped" end
    return "Roll"
  end
  local left = APOCLootPrio.GetLootRollTimeLeft and APOCLootPrio:GetLootRollTimeLeft(drop) or nil
  if left and left > 0 then
    return "Rolling"
  end
  return "Closed"
end

local function RefreshSelectedDropRollDisplay(panel, drop)
  if not panel then return end
  if panel.selectedDropRollButton then
    panel.selectedDropRollButton:SetText(GetLootRollButtonText(drop))
    SetControlEnabled(panel.selectedDropRollButton, APOCLootPrio:CanEditLootTracker() and CanStartLootRollForDrop(drop))
  end
  if panel.selectedDropRollResultsButton then
    panel.selectedDropRollResultsButton:SetText(FormatLootRollSummary(drop))
  end
  if panel.selectedDropRollResult then
    panel.selectedDropRollResult:SetText("")
  end
end

local function LayoutLootTrackerToolbar(panel)
  if not panel then return -100 end

  local buttons = {
    panel.addDrop,
    panel.newSession,
    panel.renameSession,
    panel.sessionsButton,
    panel.liveRaidsButton,
    panel.getListButton,
    panel.awardsButton,
    panel.attendanceButton,
    panel.trackerSettings,
    panel.exportSession,
    panel.closeSession,
  }

  local width = panel.GetWidth and panel:GetWidth() or RAID_LOOT_WINDOW_WIDTH
  local maxRight = math.max(120, width - 18)
  local x, y = 18, -76
  local gap = 6
  local rowH = 26
  local placed = 0

  for _, button in ipairs(buttons) do
    if button and button.IsShown and button:IsShown() then
      local buttonWidth = button.GetWidth and button:GetWidth() or 78
      if placed > 0 and (x + buttonWidth) > maxRight then
        x = 18
        y = y - rowH
      end
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
      x = x + buttonWidth + gap
      placed = placed + 1
    end
  end

  panel.toolbarBottomY = y - 24
  return panel.toolbarBottomY
end

local function ApplyLootTrackerAccess(panel)
  if not panel then return end

  local canView = APOCLootPrio:CanViewLootTracker()
  local canEdit = APOCLootPrio:CanEditLootTracker()
  local selectedDrop = panel.selectedDropRollButton and panel.selectedDropRollButton.drop or nil
  local trackerRaid = APOCLootPrio.selectedLootTrackerRaid or APOCLootPrio.selectedRaid
  local activeSession = APOCLootPrio:GetRaidLootSession(trackerRaid)
  local exportSession = APOCLootPrio.GetActiveHistorySession and APOCLootPrio:GetActiveHistorySession()
  local renameSession = exportSession or activeSession
  local isFinalized = activeSession and activeSession.finalized
  local historyEdit = APOCLootPrio.IsHistoryEditContext and APOCLootPrio:IsHistoryEditContext() and APOCLootPrio:CanEditGuildRaidHistory()

  SetControlEnabled(panel.addDrop, canEdit and (not isFinalized or historyEdit))
  SetControlShown(panel.addDrop, canEdit)
  SetControlEnabled(panel.newSession, canEdit)
  SetControlShown(panel.newSession, canEdit)
  if panel.renameSession then
    local canRename = canEdit and renameSession and renameSession.key and not renameSession.readOnly
      and APOCLootPrio.CanEditLootSession and APOCLootPrio:CanEditLootSession(renameSession)
    SetControlEnabled(panel.renameSession, canRename)
    SetControlShown(panel.renameSession, canEdit)
  end
  SetControlEnabled(panel.sessionsButton, canView)
  SetControlEnabled(panel.attendanceButton, canView)
  if panel.exportSession then
    SetControlEnabled(panel.exportSession, canEdit and exportSession and exportSession.key and not exportSession.readOnly)
    SetControlShown(panel.exportSession, canEdit)
  end
  if panel.closeSession then
    panel.closeSession:SetText(isFinalized and "Saved" or "Close & Save")
    SetControlEnabled(panel.closeSession, canEdit and activeSession and activeSession.key and not isFinalized)
    SetControlShown(panel.closeSession, canEdit)
  end
  SetControlEnabled(panel.trackerSettings, APOCLootPrio:CanManageSettings())
  SetControlShown(panel.trackerSettings, APOCLootPrio:CanManageSettings())
  LayoutLootTrackerToolbar(panel)
  SetControlEnabled(panel.syncedClients, canEdit)
  SetControlShown(panel.syncedClients, canEdit)
  SetControlEnabled(panel.award, canEdit)
  SetControlShown(panel.award, canEdit)
  SetControlEnabled(panel.me, canEdit)
  -- Viewers can search the raid and see +1s; they cannot pick a winner.
  SetControlEnabled(panel.winner, canView)
  SetControlShown(panel.winner, canView)
  SetControlEnabled(panel.note, canEdit)
  SetControlShown(panel.note, canEdit)

  SetControlShown(panel.awardTitle, canEdit)
  SetControlShown(panel.selectedDropPreview, canView)
  if panel.selectedDropRollButton then
    panel.selectedDropRollButton:SetText(GetLootRollButtonText(selectedDrop))
  end
  SetControlEnabled(panel.selectedDropRollButton, canEdit and CanStartLootRollForDrop(selectedDrop))
  SetControlShown(panel.selectedDropRollButton, canEdit)
  SetControlEnabled(panel.selectedDropRollResultsButton, canEdit and panel.currentDropID ~= nil)
  SetControlShown(panel.selectedDropRollResultsButton, canEdit)
  SetControlEnabled(panel.selectedDropRollResetButton, canEdit and panel.currentDropID ~= nil)
  SetControlShown(panel.selectedDropRollResetButton, canEdit)
  SetControlShown(panel.selectedDropRollResult, false)
  SetControlShown(panel.selectedDropIcon, canView and panel.selectedDropIcon and panel.selectedDropIcon.hasDrop)
  SetControlShown(panel.selectedDrop, canView)
  SetControlShown(panel.selectedDropPrio, canView)
  SetControlShown(panel.winnerLabel, canView)
  SetControlShown(panel.winnerPlaceholder, canView)
  SetControlShown(panel.memberSummary, canView)
  SetControlShown(panel.memberScroll, canView)
  SetControlShown(panel.typeLabel, canEdit)
  SetControlShown(panel.noteLabel, canEdit)
  SetControlShown(panel.status, canView)
  if panel.getListButton then
    SetControlEnabled(panel.getListButton, canView)
    SetControlShown(panel.getListButton, canView)
  end

  if panel.awardTypeButtons then
    for _, button in pairs(panel.awardTypeButtons) do
      SetControlEnabled(button, canEdit)
      SetControlShown(button, canEdit)
    end
  end

  if not canView and panel.Hide then
    panel:Hide()
  end
end

local function SetRecentAwardsEditorShown(panel, shown)
  if not panel or not panel.editor or not panel.scroll then return end

  panel.editorShown = shown and true or false
  panel.scroll:ClearAllPoints()

  if panel.editorShown then
    panel.editor:Show()
    panel.scroll:SetPoint("TOPLEFT", 10, -(58 + RECENT_AWARD_EDITOR_HEIGHT + 8))
  else
    panel.editor:Hide()
    panel.scroll:SetPoint("TOPLEFT", 10, -58)
  end

  panel.scroll:SetPoint("BOTTOMRIGHT", -26, 10)
end

local function CreateRecentAwardEditor(parent)
  local editor = CreateFrame("Frame", nil, parent)
  editor:SetPoint("TOPLEFT", 10, -58)
  editor:SetPoint("TOPRIGHT", -10, -58)
  editor:SetHeight(RECENT_AWARD_EDITOR_HEIGHT)
  editor:Hide()

  local bg = editor:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(editor)
  SetTextureColor(bg, .09, .06, .04, .94)

  local border = editor:CreateTexture(nil, "BORDER")
  border:SetAllPoints(editor)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.55, .36, .10, .72)

  editor.title = Font(editor, 11, "Edit Recent Award", "GameFontHighlight")
  editor.title:SetPoint("TOPLEFT", 8, -8)
  editor.title:SetTextColor(1, .85, .2)

  editor.item = Font(editor, 10, "Select an award.", "GameFontNormalSmall")
  editor.item:SetPoint("TOPLEFT", 8, -28)
  editor.item:SetPoint("TOPRIGHT", -8, -28)
  editor.item:SetJustifyH("LEFT")
  editor.item:SetTextColor(.9, .84, .72)

  AddEditorLabel(editor, "Winner", 8, -54)
  editor.winner = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  editor.winner:SetSize(150, 22)
  editor.winner:SetPoint("TOPLEFT", 58, -52)
  editor.winner:SetAutoFocus(false)
  editor.winner:SetMaxLetters(48)
  editor.winner:SetTextInsets(6, 6, 0, 0)

  editor.me = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  editor.me:SetSize(44, 22)
  editor.me:SetPoint("LEFT", editor.winner, "RIGHT", 6, 0)
  editor.me:SetText("Me")
  editor.me:SetScript("OnClick", function()
    editor.winner:SetText(APOCLootPrio:GetPlayerDisplayName() or "")
    APOCLootPrio:RefreshRecentAwardEditRoster()
  end)

  AddEditorLabel(editor, "Group", 8, -82)
  editor.memberScroll = CreateFrame("ScrollFrame", nil, editor, "UIPanelScrollFrameTemplate")
  editor.memberScroll:SetPoint("TOPLEFT", 58, -80)
  editor.memberScroll:SetSize(RECENT_AWARDS_PANEL_WIDTH - 96, 42)

  editor.memberContent = CreateFrame("Frame", nil, editor.memberScroll)
  editor.memberContent:SetSize(RECENT_AWARDS_PANEL_WIDTH - 122, 1)
  editor.memberScroll:SetScrollChild(editor.memberContent)

  AddEditorLabel(editor, "Type", 8, -130)
  AddAwardTypeButtons(editor, 58, -128, 44)

  AddEditorLabel(editor, "Note", 8, -158)
  editor.note = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  editor.note:SetSize(190, 22)
  editor.note:SetPoint("TOPLEFT", 58, -156)
  editor.note:SetAutoFocus(false)
  editor.note:SetMaxLetters(90)
  editor.note:SetTextInsets(6, 6, 0, 0)

  editor.save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  editor.save:SetSize(56, 22)
  editor.save:SetPoint("TOPLEFT", 8, -184)
  editor.save:SetText("Save")
  editor.save:SetScript("OnClick", function() APOCLootPrio:SaveRecentAwardEdit() end)

  editor.delete = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  editor.delete:SetSize(56, 22)
  editor.delete:SetPoint("LEFT", editor.save, "RIGHT", 6, 0)
  editor.delete:SetText("Del")
  editor.delete:SetScript("OnClick", function() APOCLootPrio:DeleteRecentAwardEdit() end)

  editor.cancel = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  editor.cancel:SetSize(64, 22)
  editor.cancel:SetPoint("LEFT", editor.delete, "RIGHT", 6, 0)
  editor.cancel:SetText("Cancel")
  editor.cancel:SetScript("OnClick", function() APOCLootPrio:CancelRecentAwardEdit() end)

  editor.status = Font(editor, 9, "Click Save to update this award.", "GameFontNormalSmall")
  editor.status:SetPoint("LEFT", editor.cancel, "RIGHT", 6, 0)
  editor.status:SetPoint("RIGHT", -6, 0)
  editor.status:SetJustifyH("LEFT")
  editor.status:SetTextColor(.72, .72, .72)

  return editor
end

local function CreateGuildAwardRow(parent, y, loot, onEdit, onDelete, selected, canEdit)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(GUILD_LOOT_ROW_WIDTH - 24, GUILD_AWARD_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 12, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", onEdit)
  row:SetScript("OnEnter", function(button) ShowDropTooltip(button, loot) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  if selected then
    SetTextureColor(bg, .28, .08, .06, .82)
  else
    SetAPOCRowTexture(bg, .72)
  end

  local item = DropAsItem(loot)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(38, 38)
  icon:SetPoint("LEFT", 4, 0)
  SetCleanItemIcon(icon, item)

  local border = row:CreateTexture(nil, "OVERLAY")
  border:SetSize(48, 48)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)
  HideItemIconFrame(border)
  border:SetVertexColor(GetItemQualityRGB(item))

  local name = Font(row, 11, loot.item or "Unknown item", "GameFontNormal")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -5)
  name:SetPoint("RIGHT", -100, 0)
  name:SetJustifyH("LEFT")
  name:SetTextColor(GetItemQualityRGB(item))

  local detail = Font(row, 10, AwardTypeShort(loot.awardType or "MS") .. " - " .. (loot.raid or "Loot") .. " / " .. (loot.boss or "Unknown") .. " - " .. APOCLootPrio:FormatLootTime(loot.time), "GameFontNormalSmall")
  detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  detail:SetPoint("RIGHT", -100, 0)
  detail:SetJustifyH("LEFT")
  detail:SetTextColor(.86, .78, .62)

  local edit = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  edit:SetSize(42, 20)
  edit:SetPoint("RIGHT", -50, 0)
  edit:SetText("Edit")
  edit:SetScript("OnClick", onEdit)
  SetControlEnabled(edit, canEdit)
  if not canEdit then edit:Hide() end

  local delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  delete:SetSize(42, 20)
  delete:SetPoint("RIGHT", -4, 0)
  delete:SetText("Del")
  delete:SetScript("OnClick", onDelete)
  SetControlEnabled(delete, canEdit)
  if not canEdit then delete:Hide() end

  return row
end

local function GetGuildPlayerLoot(player)
  local lootList = {}
  for _, loot in pairs(player.loot or {}) do
    if loot then table.insert(lootList, loot) end
  end
  table.sort(lootList, function(a, b)
    local aTime = a.droppedAt or a.time or 0
    local bTime = b.droppedAt or b.time or 0
    if aTime ~= bTime then return aTime < bTime end
    local aSequence = tonumber(string.match(tostring(a.dropID or ""), ":drop:(%d+)$")) or 0
    local bSequence = tonumber(string.match(tostring(b.dropID or ""), ":drop:(%d+)$")) or 0
    if aSequence ~= bSequence then return aSequence < bSequence end
    return tostring(a.dropID or "") < tostring(b.dropID or "")
  end)
  return lootList
end

local function ConfigureGuildLootIconHit(hit, icon, loot, canEdit)
  hit:RegisterForClicks("LeftButtonUp")
  hit:SetScript("OnClick", function()
    if canEdit and loot.dropID then
      APOCLootPrio:SelectGuildLootAward(loot.dropID)
    end
  end)
  hit:SetScript("OnEnter", function(frame)
    icon:SetVertexColor(.82, .82, .82)
    ShowDropTooltip(frame, loot)
  end)
  hit:SetScript("OnLeave", function()
    icon:SetVertexColor(1, 1, 1)
    GameTooltip:Hide()
  end)
end

local function CreateGuildWinnerRow(parent, y, player, canEdit)
  local lootList = GetGuildPlayerLoot(player)
  local iconSize = 30
  local iconGap = 5
  local iconStartX = 150
  local iconAreaRight = GUILD_LOOT_ROW_WIDTH - 50
  local iconsPerRow = math.max(1, math.floor((iconAreaRight - iconStartX + iconGap) / (iconSize + iconGap)))
  local iconRows = math.max(1, math.ceil(#lootList / iconsPerRow))
  local rowHeight = math.max(42, 6 + (iconRows * (iconSize + iconGap)))

  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(GUILD_LOOT_ROW_WIDTH, rowHeight)
  row:SetPoint("TOPLEFT", 0, y)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  SetTextureColor(bg, .10, .07, .04, .86)

  local name = Font(row, 11, player.name or "Unknown", "GameFontHighlight")
  name:SetPoint("TOPLEFT", 8, -6)
  name:SetSize(134, 16)
  name:SetJustifyH("LEFT")
  name:SetTextColor(GetPlayerClassRGB(player))

  local details = {}
  if player.className and player.className ~= "" then table.insert(details, player.className) end
  if player.rankName and player.rankName ~= "" then table.insert(details, player.rankName) end
  if player.rankIndex ~= nil then table.insert(details, "rank " .. tostring(player.rankIndex)) end

  local meta = Font(row, 9, table.concat(details, " - "), "GameFontNormalSmall")
  meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
  meta:SetSize(134, 14)
  meta:SetJustifyH("LEFT")
  meta:SetTextColor(.62, .58, .50)

  local count = Font(row, 11, tostring(player.count or 0) .. " MS", "GameFontNormalSmall")
  count:SetPoint("TOPRIGHT", -8, -10)
  count:SetJustifyH("RIGHT")
  count:SetTextColor(1, .85, .2)

  for index, loot in ipairs(lootList) do
    local item = DropAsItem(loot)
    local column = (index - 1) % iconsPerRow
    local iconRow = math.floor((index - 1) / iconsPerRow)
    local x = iconStartX + (column * (iconSize + iconGap))
    local iconY = -6 - (iconRow * (iconSize + iconGap))

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, iconY)
    SetCleanItemIcon(icon, item)

    local hit = CreateFrame("Button", nil, row)
    hit:SetSize(iconSize, iconSize)
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", x, iconY)
    ConfigureGuildLootIconHit(hit, icon, loot, canEdit)
  end

  return rowHeight
end

local function CreateRecentAwardsPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioRecentAwardsPanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel.panelWidth = RECENT_AWARDS_PANEL_WIDTH
  panel:SetSize(RECENT_AWARDS_PANEL_WIDTH, RECENT_AWARDS_PANEL_HEIGHT)
  SetLogPanelOffset(panel, -RECENT_AWARDS_PANEL_WIDTH)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 9)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.45, .35, .18, .7)
  border:Hide()

  panel.title = Font(panel, 12, "Recent Awards", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", 0, 0)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetRecentAwardsPanelShown(false) end)

  panel.summary = Font(panel, 10, "No awards yet.", "GameFontNormalSmall")
  panel.summary:SetPoint("TOPLEFT", 10, -34)
  panel.summary:SetPoint("TOPRIGHT", -10, -34)
  panel.summary:SetJustifyH("LEFT")
  panel.summary:SetTextColor(.72, .72, .72)

  panel.editor = CreateRecentAwardEditor(panel)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("BOTTOMRIGHT", -26, 10)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = RECENT_AWARDS_PANEL_WIDTH - 48
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.scroll:SetScrollChild(panel.content)
  SetRecentAwardsEditorShown(panel, false)

  return panel
end

local function CreateGuildLootEditPopup(panel)
  local popup = CreateFrame("Frame", nil, panel, "BasicFrameTemplateWithInset")
  popup:SetSize(360, 188)
  popup:SetPoint("CENTER", panel, "CENTER", 0, 36)
  popup:Hide()
  SetAddonFrameLayer(popup, ADDON_FRAME_LEVEL + 16)

  local bg = popup:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = popup:CreateTexture(nil, "BORDER")
  border:SetAllPoints(popup)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.65, .42, .12, .9)
  border:Hide()

  panel.editPopup = popup
  panel.editLabels = {}

  panel.editTitle = Font(popup, 12, "Edit Guild Loot Award", "GameFontHighlight")
  panel.editTitle:SetPoint("TOPLEFT", 12, -10)
  panel.editTitle:SetPoint("TOPRIGHT", -34, -10)
  panel.editTitle:SetJustifyH("LEFT")
  panel.editTitle:SetTextColor(1, .85, .2)

  local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() APOCLootPrio:ClearGuildLootAwardEdit() end)

  panel.selectedAward = Font(popup, 10, "Select a loot row to edit or delete.", "GameFontNormalSmall")
  panel.selectedAward:SetPoint("TOPLEFT", 12, -34)
  panel.selectedAward:SetPoint("TOPRIGHT", -12, -34)
  panel.selectedAward:SetJustifyH("LEFT")
  panel.selectedAward:SetTextColor(.9, .84, .72)

  panel.editLabels.winner = AddEditorLabel(popup, "Winner", 12, -66)
  panel.editWinner = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
  panel.editWinner:SetSize(168, 22)
  panel.editWinner:SetPoint("TOPLEFT", 72, -64)
  panel.editWinner:SetAutoFocus(false)
  panel.editWinner:SetMaxLetters(48)
  panel.editWinner:SetTextInsets(6, 6, 0, 0)

  panel.editLabels.note = AddEditorLabel(popup, "Note", 12, -94)
  panel.editNote = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
  panel.editNote:SetSize(260, 22)
  panel.editNote:SetPoint("TOPLEFT", 72, -92)
  panel.editNote:SetAutoFocus(false)
  panel.editNote:SetMaxLetters(90)
  panel.editNote:SetTextInsets(6, 6, 0, 0)

  panel.editLabels.type = AddEditorLabel(popup, "Type", 12, -122)
  AddAwardTypeButtons(panel, 72, -120, 46, popup)

  panel.saveAward = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  panel.saveAward:SetSize(62, 22)
  panel.saveAward:SetPoint("BOTTOMLEFT", 12, 12)
  panel.saveAward:SetText("Save")
  panel.saveAward:SetScript("OnClick", function() APOCLootPrio:SaveGuildLootAwardEdit() end)

  panel.deleteAward = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  panel.deleteAward:SetSize(62, 22)
  panel.deleteAward:SetPoint("LEFT", panel.saveAward, "RIGHT", 8, 0)
  panel.deleteAward:SetText("Delete")
  panel.deleteAward:SetScript("OnClick", function() APOCLootPrio:DeleteGuildLootAward() end)

  panel.cancelAward = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  panel.cancelAward:SetSize(62, 22)
  panel.cancelAward:SetPoint("LEFT", panel.deleteAward, "RIGHT", 8, 0)
  panel.cancelAward:SetText("Cancel")
  panel.cancelAward:SetScript("OnClick", function() APOCLootPrio:ClearGuildLootAwardEdit() end)

  panel.editStatus = Font(popup, 9, "Editing changes the saved loot history.", "GameFontNormalSmall")
  panel.editStatus:SetPoint("LEFT", panel.cancelAward, "RIGHT", 8, 0)
  panel.editStatus:SetPoint("RIGHT", -10, 0)
  panel.editStatus:SetJustifyH("LEFT")
  panel.editStatus:SetTextColor(.72, .72, .72)

  return popup
end

local function ClearFrameChildren(frame)
  if not frame or not frame.GetChildren then return end

  frame.rollPoolUsed = {}
  for _, child in ipairs({frame:GetChildren()}) do
    child:Hide()
    if not child.apocRollPooled then child:SetParent(nil) end
  end
end

local function ClearFrameRegions(frame)
  if not frame or not frame.GetRegions then return end

  for _, region in ipairs({frame:GetRegions()}) do
    if region and region.Hide then region:Hide() end
  end
end

local function AddThinIconBorder(parent, size, r, g, b)
  local thickness = 1

  local top = parent:CreateTexture(nil, "OVERLAY")
  top:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
  top:SetSize(size + 2, thickness)
  SetTextureColor(top, r, g, b, 1)

  local bottom = parent:CreateTexture(nil, "OVERLAY")
  bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -1, -1)
  bottom:SetSize(size + 2, thickness)
  SetTextureColor(bottom, r, g, b, 1)

  local left = parent:CreateTexture(nil, "OVERLAY")
  left:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
  left:SetSize(thickness, size + 2)
  SetTextureColor(left, r, g, b, 1)

  local right = parent:CreateTexture(nil, "OVERLAY")
  right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 1, 1)
  right:SetSize(thickness, size + 2)
  SetTextureColor(right, r, g, b, 1)
end

local function CreateManualPickerButton(parent, x, y, width, height, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, height)
  button:SetPoint("TOPLEFT", x, y)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

local function CreateManualPickerTextRow(parent, y, text, detail, onClick)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(parent.rowWidth or 330, 34)
  row:SetPoint("TOPLEFT", 0, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", onClick)
  row.labels = {}

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  SetAPOCRowTexture(bg, .82)

  local label = Font(row, 11, text or "", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 8, -5)
  label:SetPoint("RIGHT", -8, 0)
  label:SetJustifyH("LEFT")
  label:SetTextColor(1, .85, .2)
  row.labels.title = label

  if detail and detail ~= "" then
    local sub = Font(row, 9, detail, "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
    sub:SetPoint("RIGHT", -8, 0)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(.78, .72, .62)
    row.labels.detail = sub
  end

  return row
end

local function SetManualPickerRowActionSpace(row, rightPadding)
  if not row or not row.labels then return end
  rightPadding = rightPadding or 8

  if row.labels.title then
    row.labels.title:ClearAllPoints()
    row.labels.title:SetPoint("TOPLEFT", 8, -5)
    row.labels.title:SetPoint("RIGHT", -rightPadding, 0)
  end

  if row.labels.detail then
    row.labels.detail:ClearAllPoints()
    row.labels.detail:SetPoint("TOPLEFT", row.labels.title or row, row.labels.title and "BOTTOMLEFT" or "TOPLEFT", row.labels.title and 0 or 8, row.labels.title and -1 or -20)
    row.labels.detail:SetPoint("RIGHT", -rightPadding, 0)
  end
end

local function CreateManualPickerItemRow(parent, y, item, bossName, onClick, selectedCount, onRemove)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(parent.rowWidth or 330, 44)
  row:SetPoint("TOPLEFT", 0, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", onClick)
  row:SetScript("OnEnter", function(button) ShowItemTooltip(button, item) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  selectedCount = tonumber(selectedCount) or 0
  if selectedCount > 0 then
    SetTextureColor(bg, .35, .08, .05, .88)
  else
    SetAPOCRowTexture(bg, .82)
  end

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(34, 34)
  icon:SetPoint("LEFT", 4, 0)
  SetCleanItemIcon(icon, item)

  local border = row:CreateTexture(nil, "OVERLAY")
  border:SetSize(46, 46)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)
  HideItemIconFrame(border)
  border:SetVertexColor(GetItemQualityRGB(item))

  local nameText = selectedCount > 0 and ("|cffffd100x" .. tostring(selectedCount) .. "|r " .. (item.name or "Unknown item")) or (item.name or "Unknown item")
  local name = Font(row, 11, nameText, "GameFontNormal")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -3)
  name:SetPoint("RIGHT", selectedCount > 0 and -36 or -8, 0)
  name:SetJustifyH("LEFT")
  name:SetTextColor(GetItemQualityRGB(item))

  local detailText = (bossName or "Unknown") .. " - " .. ColorizePriorityText(APOCLootPrio:GetItemBias(item) or "No priority")
  local detail = Font(row, 9, detailText, "GameFontNormalSmall")
  detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  detail:SetPoint("RIGHT", -8, 0)
  detail:SetJustifyH("LEFT")
  detail:SetTextColor(.9, .84, .72)

  if selectedCount > 0 and onRemove then
    local minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    minus:SetSize(24, 20)
    minus:SetPoint("RIGHT", -6, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function(button)
      if button and button.GetParent then
        local parentRow = button:GetParent()
        if parentRow and parentRow.SetScript then
          parentRow:SetScript("OnClick", nil)
        end
      end
      onRemove()
    end)
  end

  return row
end

local function CreateManualLootPicker(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioManualLootPicker", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(500, 280)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 18)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Add Manual Loot", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetManualLootPickerShown(false) end)

  panel.instructions = Font(panel, 10, "", "GameFontNormalSmall")
  panel.instructions:SetPoint("TOPLEFT", 10, -34)
  panel.instructions:SetPoint("TOPRIGHT", -10, -34)
  panel.instructions:SetJustifyH("LEFT")
  panel.instructions:SetTextColor(.9, .84, .72)

  panel.back = CreateManualPickerButton(panel, 10, -62, 58, 22, "Back", function() APOCLootPrio:ManualLootPickerBack() end)
  panel.confirm = CreateManualPickerButton(panel, 398, -62, 82, 22, "Add Item", function() APOCLootPrio:ConfirmManualLootPickerItem() end)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 10, -92)
  panel.scroll:SetPoint("BOTTOMRIGHT", -28, 10)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = 452
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.scroll:SetScrollChild(panel.content)

  return panel
end

local function CreateLootDeleteConfirm(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLootDeleteConfirm", parent, "BasicFrameTemplateWithInset")
  panel:SetSize(330, 138)
  panel:SetPoint("CENTER", parent, "CENTER", 0, 36)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 16)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.65, .42, .12, .9)
  border:Hide()

  panel.title = Font(panel, 13, "Remove Loot Drop?", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 12, -10)
  panel.title:SetPoint("TOPRIGHT", -12, -10)
  panel.title:SetJustifyH("CENTER")
  panel.title:SetTextColor(1, .85, .2)

  panel.message = Font(panel, 10, "Remove this item from the loot tracker?", "GameFontNormalSmall")
  panel.message:SetPoint("TOPLEFT", 14, -38)
  panel.message:SetPoint("TOPRIGHT", -14, -38)
  panel.message:SetJustifyH("CENTER")
  panel.message:SetTextColor(.9, .84, .72)

  panel.delete = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.delete:SetSize(82, 24)
  panel.delete:SetPoint("BOTTOMLEFT", 54, 14)
  panel.delete:SetText("Delete")
  panel.delete:SetScript("OnClick", function() APOCLootPrio:ConfirmDeleteSelectedRaidLootDrop() end)

  panel.cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.cancel:SetSize(82, 24)
  panel.cancel:SetPoint("LEFT", panel.delete, "RIGHT", 24, 0)
  panel.cancel:SetText("Cancel")
  panel.cancel:SetScript("OnClick", function() APOCLootPrio:SetLootDeleteConfirmShown(false) end)

  return panel
end

local function CreateLootSessionPicker(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLootSessionPicker", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetSize(620, 360)
  panel:SetPoint("CENTER", parent, "CENTER", 0, 60)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 15)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg)

  panel.title = Font(panel, 13, "Guild Raid History", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 12, -9)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLootSessionPickerShown(false) end)

  panel.summary = Font(panel, 10, "Closed guild raid nights and local saved sessions. Ranks 0–2 can open and edit history.", "GameFontNormalSmall")
  panel.summary:SetPoint("TOPLEFT", 18, -38)
  panel.summary:SetPoint("TOPRIGHT", -12, -34)
  panel.summary:SetJustifyH("LEFT")
  panel.summary:SetTextColor(.9, .84, .72)

  local headerBg = panel:CreateTexture(nil, "ARTWORK")
  headerBg:SetPoint("TOPLEFT", 18, -64)
  headerBg:SetPoint("TOPRIGHT", -36, -64)
  headerBg:SetHeight(20)
  SetTextureColor(headerBg, .22, .05, .02, .72)
  panel.headerBg = headerBg

  panel.sessionHeader = Font(panel, 9, "Session", "GameFontNormalSmall")
  panel.sessionHeader:SetPoint("LEFT", headerBg, "LEFT", 10, 0)
  panel.sessionHeader:SetTextColor(1, .85, .2)

  panel.actionHeader = Font(panel, 9, "Actions", "GameFontNormalSmall")
  panel.actionHeader:SetPoint("RIGHT", headerBg, "RIGHT", -28, 0)
  panel.actionHeader:SetTextColor(1, .85, .2)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 18, -88)
  panel.scroll:SetPoint("BOTTOMRIGHT", -36, 36)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = 552
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.scroll:SetScrollChild(panel.content)

  panel.footer = Font(panel, 10, "Open a History/Closed session to review or correct awards (out of raid).", "GameFontNormalSmall")
  panel.footer:SetPoint("BOTTOMLEFT", 18, 16)
  panel.footer:SetPoint("BOTTOMRIGHT", -18, 16)
  panel.footer:SetJustifyH("LEFT")
  panel.footer:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateLootSessionPickerRow(parent, y, session, detail, isActive, canEdit, onOpen, onDelete)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(parent.rowWidth or 552, 58)
  row:SetPoint("TOPLEFT", 0, y)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", onOpen)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  SetTextureColor(bg, isActive and .16 or .075, isActive and .065 or .055, isActive and .025 or .035, .92)

  local stripe = row:CreateTexture(nil, "ARTWORK")
  stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  stripe:SetWidth(4)
  if isActive then
    SetTextureColor(stripe, 1, .70, .10, 1)
  else
    SetTextureColor(stripe, .55, .34, .10, .9)
  end

  local title = Font(row, 10, APOCLootPrio:GetLootSessionDisplayName(session), "GameFontHighlight")
  title:SetPoint("TOPLEFT", 12, -7)
  title:SetPoint("RIGHT", -130, 0)
  title:SetHeight(26)
  title:SetJustifyH("LEFT")
  if title.SetWordWrap then title:SetWordWrap(true) end
  title:SetTextColor(1, .85, .2)

  local sub = Font(row, 9, detail or "", "GameFontNormalSmall")
  sub:SetPoint("TOPLEFT", 12, -38)
  sub:SetPoint("RIGHT", -130, 0)
  sub:SetJustifyH("LEFT")
  sub:SetTextColor(.84, .78, .66)

  local badgeText
  if session.archived then
    badgeText = "History"
  elseif session.finalized then
    badgeText = "Closed"
  elseif isActive then
    badgeText = "Active"
  else
    badgeText = "Saved"
  end
  local badge = Font(row, 9, badgeText, "GameFontNormalSmall")
  badge:SetPoint("TOPRIGHT", -10, -7)
  badge:SetSize(112, 12)
  badge:SetJustifyH("RIGHT")
  if session.archived then
    badge:SetTextColor(.55, .78, 1)
  else
    badge:SetTextColor(isActive and 1 or .72, isActive and .85 or .72, isActive and .2 or .72)
  end

  local openButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  openButton:SetSize(58, 22)
  openButton:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", canEdit and -56 or -8, 6)
  openButton:SetText("Open")
  openButton:SetScript("OnClick", onOpen)

  if canEdit then
    local deleteButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    deleteButton:SetSize(44, 22)
    deleteButton:SetPoint("LEFT", openButton, "RIGHT", 6, 0)
    deleteButton:SetText("Del")
    deleteButton:SetScript("OnClick", onDelete)
  end

  row:SetScript("OnEnter", function()
    SetTextureColor(bg, isActive and .22 or .12, isActive and .08 or .065, isActive and .03 or .035, .96)
  end)
  row:SetScript("OnLeave", function()
    SetTextureColor(bg, isActive and .16 or .075, isActive and .065 or .055, isActive and .025 or .035, .92)
  end)

  if isActive then row:LockHighlight() end
  return row
end

local function CreateLootSessionDeleteConfirm(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLootSessionDeleteConfirm", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetSize(350, 138)
  panel:SetPoint("CENTER", parent, "CENTER", 0, 36)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 20)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.75, .32, .12, .9)
  border:Hide()

  panel.title = Font(panel, 13, "Delete Saved Session", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 14, -12)
  panel.title:SetTextColor(1, .85, .2)

  panel.message = Font(panel, 10, "Delete this saved loot session?", "GameFontNormalSmall")
  panel.message:SetPoint("TOPLEFT", 14, -42)
  panel.message:SetPoint("TOPRIGHT", -14, -42)
  panel.message:SetJustifyH("LEFT")
  panel.message:SetTextColor(.9, .84, .72)

  panel.delete = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.delete:SetSize(92, 24)
  panel.delete:SetPoint("BOTTOMLEFT", 14, 14)
  panel.delete:SetText("Delete")
  panel.delete:SetScript("OnClick", function() APOCLootPrio:ConfirmDeleteLootSession() end)

  panel.cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.cancel:SetSize(82, 24)
  panel.cancel:SetPoint("LEFT", panel.delete, "RIGHT", 24, 0)
  panel.cancel:SetText("Cancel")
  panel.cancel:SetScript("OnClick", function() APOCLootPrio:SetLootSessionDeleteConfirmShown(false) end)

  return panel
end

local function CreateNewLootSessionConfirm(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioNewLootSessionConfirm", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetSize(360, 138)
  panel:SetPoint("CENTER", parent, "CENTER", 0, 36)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 17)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.65, .42, .12, .9)
  border:Hide()

  panel.title = Font(panel, 13, "Start New Session?", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 14, -12)
  panel.title:SetTextColor(1, .85, .2)

  panel.message = Font(panel, 10, "Start a new saved loot session?", "GameFontNormalSmall")
  panel.message:SetPoint("TOPLEFT", 14, -42)
  panel.message:SetPoint("TOPRIGHT", -14, -42)
  panel.message:SetJustifyH("LEFT")
  panel.message:SetTextColor(.9, .84, .72)

  panel.start = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.start:SetSize(82, 24)
  panel.start:SetPoint("BOTTOMLEFT", 54, 14)
  panel.start:SetText("Start")
  panel.start:SetScript("OnClick", function() APOCLootPrio:ConfirmStartNewRaidLootSession() end)

  panel.cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.cancel:SetSize(82, 24)
  panel.cancel:SetPoint("LEFT", panel.start, "RIGHT", 24, 0)
  panel.cancel:SetText("Cancel")
  panel.cancel:SetScript("OnClick", function() APOCLootPrio:SetNewLootSessionConfirmShown(false) end)

  return panel
end

local function CreateRenameLootSessionPrompt(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioRenameLootSessionPrompt", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetSize(430, 184)
  panel:SetPoint("CENTER", parent, "CENTER", 0, 36)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 26)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .96)

  panel.title = Font(panel, 13, "Rename Session", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 14, -12)
  panel.title:SetTextColor(1, .85, .2)

  panel.message = Font(panel, 10, "Change the title only. The raid data and Run ID stay the same.", "GameFontNormalSmall")
  panel.message:SetPoint("TOPLEFT", 14, -42)
  panel.message:SetPoint("TOPRIGHT", -14, -42)
  panel.message:SetJustifyH("LEFT")
  panel.message:SetTextColor(.9, .84, .72)

  panel.input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.input:SetSize(390, 24)
  panel.input:SetPoint("TOPLEFT", 18, -72)
  panel.input:SetAutoFocus(false)
  panel.input:SetMaxLetters(96)
  panel.input:SetTextInsets(6, 6, 0, 0)
  panel.input:SetScript("OnEnterPressed", function()
    APOCLootPrio:ConfirmRenameLootSession()
  end)
  panel.input:SetScript("OnEscapePressed", function(editBox)
    editBox:ClearFocus()
    APOCLootPrio:SetRenameLootSessionShown(false)
  end)

  panel.error = Font(panel, 10, "", "GameFontNormalSmall")
  panel.error:SetPoint("TOPLEFT", 18, -104)
  panel.error:SetPoint("TOPRIGHT", -18, -104)
  panel.error:SetJustifyH("LEFT")
  panel.error:SetTextColor(1, .35, .35)

  panel.save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.save:SetSize(92, 24)
  panel.save:SetPoint("BOTTOMLEFT", 104, 14)
  panel.save:SetText("Save Name")
  panel.save:SetScript("OnClick", function() APOCLootPrio:ConfirmRenameLootSession() end)

  panel.cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.cancel:SetSize(82, 24)
  panel.cancel:SetPoint("LEFT", panel.save, "RIGHT", 28, 0)
  panel.cancel:SetText("Cancel")
  panel.cancel:SetScript("OnClick", function() APOCLootPrio:SetRenameLootSessionShown(false) end)

  return panel
end

local function CreateCloseLootSessionConfirm(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioCloseLootSessionConfirm", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetSize(390, 154)
  panel:SetPoint("CENTER", parent, "CENTER", 0, 36)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 26)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .96)

  panel.title = Font(panel, 13, "Close & Save Session?", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 14, -12)
  panel.title:SetTextColor(1, .85, .2)

  panel.message = Font(panel, 10, "Finalize this raid session?", "GameFontNormalSmall")
  panel.message:SetPoint("TOPLEFT", 14, -42)
  panel.message:SetPoint("TOPRIGHT", -14, -42)
  panel.message:SetHeight(52)
  panel.message:SetJustifyH("LEFT")
  if panel.message.SetJustifyV then panel.message:SetJustifyV("TOP") end
  panel.message:SetTextColor(.9, .84, .72)

  panel.save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.save:SetSize(104, 24)
  panel.save:SetPoint("BOTTOMLEFT", 64, 14)
  panel.save:SetText("Close & Save")
  panel.save:SetScript("OnClick", function() APOCLootPrio:ConfirmCloseAndSaveLootSession() end)

  panel.cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.cancel:SetSize(82, 24)
  panel.cancel:SetPoint("LEFT", panel.save, "RIGHT", 28, 0)
  panel.cancel:SetText("Cancel")
  panel.cancel:SetScript("OnClick", function() APOCLootPrio:SetCloseLootSessionConfirmShown(false) end)

  return panel
end

local function CreateLootTrackerRunnerPicker(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLootTrackerRunnerPicker", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(400, 320)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 18)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Choose Loot Tracker Runner", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLootTrackerRunnerPickerShown(false) end)

  panel.instructions = Font(panel, 10, "Eligible current group members can be assigned to auto-capture loot.", "GameFontNormalSmall")
  panel.instructions:SetPoint("TOPLEFT", 10, -34)
  panel.instructions:SetPoint("TOPRIGHT", -10, -34)
  panel.instructions:SetJustifyH("LEFT")
  panel.instructions:SetTextColor(.9, .84, .72)

  panel.me = CreateManualPickerButton(panel, 10, -62, 58, 22, "Me", function() APOCLootPrio:SetSelfLootTrackerRunner() end)
  panel.auto = CreateManualPickerButton(panel, 76, -62, 70, 22, "Auto", function() APOCLootPrio:ClearLootTrackerRunnerFromPanel() end)
  panel.refresh = CreateManualPickerButton(panel, 292, -62, 78, 22, "Refresh", function() APOCLootPrio:RefreshLootTrackerRunnerPicker() end)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 10, -92)
  panel.scroll:SetPoint("BOTTOMRIGHT", -28, 34)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = 352
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.scroll:SetScrollChild(panel.content)

  panel.status = Font(panel, 10, "", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", 12, 14)
  panel.status:SetPoint("BOTTOMRIGHT", -12, 14)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateLootDisenchanterPicker(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioDisenchanterPicker", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(400, 320)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 18)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Choose Disenchanter", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLootDisenchanterPickerShown(false) end)

  panel.instructions = Font(panel, 10, "Choose the current group member who receives loot when nobody rolls.", "GameFontNormalSmall")
  panel.instructions:SetPoint("TOPLEFT", 10, -34)
  panel.instructions:SetPoint("TOPRIGHT", -10, -34)
  panel.instructions:SetJustifyH("LEFT")
  panel.instructions:SetTextColor(.9, .84, .72)

  panel.clear = CreateManualPickerButton(panel, 10, -62, 78, 22, "Clear", function() APOCLootPrio:ClearLootDisenchanterFromPanel() end)
  panel.refresh = CreateManualPickerButton(panel, 292, -62, 78, 22, "Refresh", function() APOCLootPrio:RefreshLootDisenchanterPicker() end)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 10, -92)
  panel.scroll:SetPoint("BOTTOMRIGHT", -28, 34)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = 352
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.scroll:SetScrollChild(panel.content)

  panel.status = Font(panel, 10, "", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", 12, 14)
  panel.status:SetPoint("BOTTOMRIGHT", -12, 14)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateLootTrackerSettingsPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLootTrackerSettingsPanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(430, 600)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 17)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Loot Tracker Settings", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLootTrackerSettingsPanelShown(false) end)

  panel.status = Font(panel, 10, "The Master Looter controls live loot; officers manage saved history.", "GameFontNormalSmall")
  panel.status:SetPoint("TOPLEFT", 12, -36)
  panel.status:SetPoint("TOPRIGHT", -12, -36)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.9, .84, .72)

  panel.accessLabel = Font(panel, 11, "Loot Tracker access", "GameFontNormal")
  panel.accessLabel:SetPoint("TOPLEFT", 18, -72)
  panel.accessLabel:SetTextColor(1, .85, .2)

  panel.accessMinus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.accessMinus:SetSize(24, 22)
  panel.accessMinus:SetPoint("TOPLEFT", 150, -68)
  panel.accessMinus:SetText("-")
  panel.accessMinus:SetScript("OnClick", function() APOCLootPrio:AdjustLootTrackerAccessRank(-1) end)

  panel.accessRank = Font(panel, 10, "", "GameFontNormalSmall")
  panel.accessRank:SetPoint("LEFT", panel.accessMinus, "RIGHT", 8, 0)
  panel.accessRank:SetSize(138, 18)
  panel.accessRank:SetJustifyH("CENTER")
  panel.accessRank:SetTextColor(.9, .84, .72)

  panel.accessPlus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.accessPlus:SetSize(24, 22)
  panel.accessPlus:SetPoint("LEFT", panel.accessRank, "RIGHT", 8, 0)
  panel.accessPlus:SetText("+")
  panel.accessPlus:SetScript("OnClick", function() APOCLootPrio:AdjustLootTrackerAccessRank(1) end)

  panel.viewOnlyLabel = Font(panel, 11, "View-only access", "GameFontNormal")
  panel.viewOnlyLabel:SetPoint("TOPLEFT", 18, -112)
  panel.viewOnlyLabel:SetTextColor(1, .85, .2)

  panel.viewOnlyMinus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.viewOnlyMinus:SetSize(24, 22)
  panel.viewOnlyMinus:SetPoint("TOPLEFT", 150, -108)
  panel.viewOnlyMinus:SetText("-")
  panel.viewOnlyMinus:SetScript("OnClick", function() APOCLootPrio:AdjustLootTrackerViewAccessRank(-1) end)

  panel.viewOnlyRank = Font(panel, 10, "", "GameFontNormalSmall")
  panel.viewOnlyRank:SetPoint("LEFT", panel.viewOnlyMinus, "RIGHT", 8, 0)
  panel.viewOnlyRank:SetSize(138, 18)
  panel.viewOnlyRank:SetJustifyH("CENTER")
  panel.viewOnlyRank:SetTextColor(.9, .84, .72)

  panel.viewOnlyPlus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.viewOnlyPlus:SetSize(24, 22)
  panel.viewOnlyPlus:SetPoint("LEFT", panel.viewOnlyRank, "RIGHT", 8, 0)
  panel.viewOnlyPlus:SetText("+")
  panel.viewOnlyPlus:SetScript("OnClick", function() APOCLootPrio:AdjustLootTrackerViewAccessRank(1) end)

  panel.runnerLabel = Font(panel, 11, "Master Looter", "GameFontNormal")
  panel.runnerLabel:SetPoint("TOPLEFT", 18, -152)
  panel.runnerLabel:SetTextColor(1, .85, .2)

  panel.runnerValue = Font(panel, 10, "Master Looter: Not detected", "GameFontNormalSmall")
  panel.runnerValue:SetPoint("TOPLEFT", 150, -154)
  panel.runnerValue:SetPoint("TOPRIGHT", -18, -154)
  panel.runnerValue:SetJustifyH("LEFT")
  panel.runnerValue:SetTextColor(.9, .84, .72)

  panel.setRunner = CreateManualPickerButton(panel, 18, -186, 96, 24, "Set Runner", function() APOCLootPrio:SetLootTrackerRunnerPickerShown(true) end)
  panel.runnerMe = CreateManualPickerButton(panel, 124, -186, 54, 24, "Me", function() APOCLootPrio:SetSelfLootTrackerRunner() end)
  panel.runnerAuto = CreateManualPickerButton(panel, 188, -186, 64, 24, "Auto", function() APOCLootPrio:ClearLootTrackerRunnerFromPanel() end)
  panel.runnerSetML = CreateManualPickerButton(panel, 262, -186, 96, 24, "Set to ML", function() APOCLootPrio:SetRunnerToMasterLooter() end)
  panel.runnerSetML:Hide()

  panel.disenchanterLabel = Font(panel, 11, "Disenchanter", "GameFontNormal")
  panel.disenchanterLabel:SetPoint("TOPLEFT", 18, -228)
  panel.disenchanterLabel:SetTextColor(1, .85, .2)

  panel.disenchanterValue = Font(panel, 10, "Not assigned", "GameFontNormalSmall")
  panel.disenchanterValue:SetPoint("TOPLEFT", 150, -230)
  panel.disenchanterValue:SetPoint("TOPRIGHT", -18, -230)
  panel.disenchanterValue:SetJustifyH("LEFT")
  panel.disenchanterValue:SetTextColor(.9, .84, .72)

  panel.setDisenchanter = CreateManualPickerButton(panel, 18, -260, 110, 24, "Set DE", function() APOCLootPrio:SetLootDisenchanterPickerShown(true) end)
  panel.clearDisenchanter = CreateManualPickerButton(panel, 138, -260, 70, 24, "Clear", function() APOCLootPrio:ClearLootDisenchanterFromPanel() end)

  panel.autoTrackLabel = Font(panel, 11, "Auto Track", "GameFontNormal")
  panel.autoTrackLabel:SetPoint("TOPLEFT", 18, -306)
  panel.autoTrackLabel:SetTextColor(1, .85, .2)

  panel.autoTrackButtons = {}
  local autoModes = {
    {key = "solo", text = "Solo", x = 150, width = 54},
    {key = "party", text = "Party", x = 210, width = 60},
    {key = "raid", text = "Raid", x = 276, width = 54},
    {key = "off", text = "Off", x = 336, width = 48},
  }
  for _, option in ipairs(autoModes) do
    local modeKey = option.key
    panel.autoTrackButtons[modeKey] = CreateManualPickerButton(panel, option.x, -302, option.width, 24, option.text, function()
      APOCLootPrio:SetLootAutoTrackModeFromPanel(modeKey)
    end)
  end

  panel.qualityLabel = Font(panel, 11, "Track Quality", "GameFontNormal")
  panel.qualityLabel:SetPoint("TOPLEFT", 18, -348)
  panel.qualityLabel:SetTextColor(1, .85, .2)

  panel.qualityButtons = {}
  local qualityOptions = {
    {quality = 5, text = "Legendary", x = 110, width = 74},
    {quality = 4, text = "Epic", x = 190, width = 52},
    {quality = 3, text = "Rare", x = 248, width = 52},
    {quality = 2, text = "Green", x = 306, width = 60},
  }
  for _, option in ipairs(qualityOptions) do
    local quality = option.quality
    panel.qualityButtons[quality] = CreateManualPickerButton(panel, option.x, -342, option.width, 24, option.text, function()
      APOCLootPrio:ToggleLootQualityFromPanel(quality)
    end)
  end

  panel.sessionDeleteLabel = Font(panel, 11, "Session Del button", "GameFontNormal")
  panel.sessionDeleteLabel:SetPoint("TOPLEFT", 18, -392)
  panel.sessionDeleteLabel:SetTextColor(1, .85, .2)

  panel.sessionDeleteMinus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.sessionDeleteMinus:SetSize(24, 22)
  panel.sessionDeleteMinus:SetPoint("TOPLEFT", 150, -388)
  panel.sessionDeleteMinus:SetText("-")
  panel.sessionDeleteMinus:SetScript("OnClick", function() APOCLootPrio:AdjustLootSessionDeleteAccessRank(-1) end)

  panel.sessionDeleteRank = Font(panel, 10, "", "GameFontNormalSmall")
  panel.sessionDeleteRank:SetPoint("LEFT", panel.sessionDeleteMinus, "RIGHT", 8, 0)
  panel.sessionDeleteRank:SetSize(138, 18)
  panel.sessionDeleteRank:SetJustifyH("CENTER")
  panel.sessionDeleteRank:SetTextColor(.9, .84, .72)

  panel.sessionDeletePlus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.sessionDeletePlus:SetSize(24, 22)
  panel.sessionDeletePlus:SetPoint("LEFT", panel.sessionDeleteRank, "RIGHT", 8, 0)
  panel.sessionDeletePlus:SetText("+")
  panel.sessionDeletePlus:SetScript("OnClick", function() APOCLootPrio:AdjustLootSessionDeleteAccessRank(1) end)

  panel.syncedClientsLabel = Font(panel, 11, "Synced clients", "GameFontNormal")
  panel.syncedClientsLabel:SetPoint("TOPLEFT", 18, -434)
  panel.syncedClientsLabel:SetTextColor(1, .85, .2)

  panel.syncedClients = CreateManualPickerButton(panel, 150, -430, 96, 24, "Synced", function()
    APOCLootPrio:ToggleSyncedClientsPanel()
  end)

  panel.fullSync = CreateManualPickerButton(panel, 256, -430, 104, 24, "Full Sync", function()
    APOCLootPrio:RequestFullLootSyncFromPanel()
  end)

  panel.rollDurationLabel = Font(panel, 11, "Roll timer (sec)", "GameFontNormal")
  panel.rollDurationLabel:SetPoint("TOPLEFT", 18, -478)
  panel.rollDurationLabel:SetTextColor(1, .85, .2)

  panel.rollDuration = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.rollDuration:SetSize(64, 24)
  panel.rollDuration:SetPoint("TOPLEFT", 150, -472)
  panel.rollDuration:SetAutoFocus(false)
  panel.rollDuration:SetMaxLetters(8)
  panel.rollDuration:SetTextInsets(6, 6, 0, 0)
  panel.rollDuration:SetScript("OnTextChanged", function(_, userInput)
    if userInput then panel.rollDurationDirty = true end
  end)
  panel.rollDuration:SetScript("OnEnterPressed", function()
    APOCLootPrio:SaveLootRollDurationFromPanel()
  end)
  panel.rollDuration:SetScript("OnEscapePressed", function(box)
    panel.rollDurationDirty = false
    box:SetText(tostring(APOCLootPrio:GetLootRollDuration()))
    box:ClearFocus()
  end)
  panel.rollDurationSave = CreateManualPickerButton(panel, 224, -472, 64, 24, "Save", function()
    APOCLootPrio:SaveLootRollDurationFromPanel()
  end)
  panel.rollDurationDefault = CreateManualPickerButton(panel, 298, -472, 86, 24, "Default", function()
    APOCLootPrio:SaveLootRollDurationFromPanel(15)
  end)
  panel.rollDurationHint = Font(panel, 10, "5-120 seconds. Default: 15. Applies to your new rolls only.\nReset still gives 10 seconds; active rolls keep their timer.", "GameFontNormalSmall")
  panel.rollDurationHint:SetPoint("TOPLEFT", 18, -508)
  panel.rollDurationHint:SetPoint("TOPRIGHT", -18, -508)
  panel.rollDurationHint:SetJustifyH("LEFT")
  panel.rollDurationHint:SetTextColor(.72, .72, .72)

  panel.note = Font(panel, 10, "Full access can edit tracker data. View-only can open the tracker read-only.", "GameFontNormalSmall")
  panel.note:SetPoint("BOTTOMLEFT", 12, 16)
  panel.note:SetPoint("BOTTOMRIGHT", -12, 16)
  panel.note:SetJustifyH("LEFT")
  panel.note:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateLiveRaidsPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLiveRaidsPanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(460, 340)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 17)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Current Live Raids", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLiveRaidsPanelShown(false) end)

  panel.instructions = Font(panel, 10, "Out of raid: click a row to watch (view-only). In raid: the Master Looter controls the Live Raid.", "GameFontNormalSmall")
  panel.instructions:SetPoint("TOPLEFT", 10, -34)
  panel.instructions:SetPoint("TOPRIGHT", -10, -34)
  panel.instructions:SetJustifyH("LEFT")
  panel.instructions:SetTextColor(.9, .84, .72)

  panel.getList = CreateManualPickerButton(panel, 10, -62, 90, 22, "Get List", function()
    local ok, message
    if APOCLootPrio.ForceLiveListSync then
      ok, message = APOCLootPrio:ForceLiveListSync()
    end
    if panel.status then panel.status:SetText(message or (ok and "Sync started." or "Could not sync.")) end
    if APOCLootPrio.UpdateRaidLootStatus and message then
      APOCLootPrio:UpdateRaidLootStatus(message)
    end
  end)
  panel.refresh = CreateManualPickerButton(panel, 256, -62, 78, 22, "Refresh", function()
    if panel.status then panel.status:SetText("Refreshing live raid discovery.") end
    if APOCLootPrio.AnnounceLocalLiveRaid then
      APOCLootPrio:AnnounceLocalLiveRaid("refresh")
    end
    APOCLootPrio:RefreshLiveRaidsPanel()
  end)
  panel.watch = CreateManualPickerButton(panel, 342, -62, 88, 22, "Use This", function()
    local id = APOCLootPrio.selectedLiveRaidListID or APOCLootPrio.liveRaidPickID
    if (not id or id == "") and APOCLootPrio.GetActiveRunID then
      id = APOCLootPrio:GetActiveRunID()
    end
    if not id or id == "" then
      if panel.status then panel.status:SetText("No live raid to use.") end
      return
    end
    APOCLootPrio.selectedLiveRaidListID = id
    if APOCLootPrio.InitLiveRaid then APOCLootPrio:InitLiveRaid().selectedLiveRaidID = id end
    if panel.status then panel.status:SetText("Using " .. tostring(APOCLootPrio.GetRunShortID and APOCLootPrio:GetRunShortID(id) or id)) end
    if APOCLootPrio.SelectLiveRaid then APOCLootPrio:SelectLiveRaid(id) end
    APOCLootPrio:RefreshLiveRaidsPanel()
  end)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 10, -92)
  panel.scroll:SetPoint("BOTTOMRIGHT", -28, 34)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = 412
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.content:EnableMouse(true)
  panel.scroll:SetScrollChild(panel.content)
  panel.scroll:EnableMouse(false)

  panel.status = Font(panel, 10, "", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", 12, 14)
  panel.status:SetPoint("BOTTOMRIGHT", -12, 14)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateSyncedClientsPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioSyncedClientsPanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(430, 320)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 17)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Synced Addon Clients", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetSyncedClientsPanelShown(false) end)

  panel.instructions = Font(panel, 10, "Shows trusted clients this addon has heard from through guild sync.", "GameFontNormalSmall")
  panel.instructions:SetPoint("TOPLEFT", 10, -34)
  panel.instructions:SetPoint("TOPRIGHT", -10, -34)
  panel.instructions:SetJustifyH("LEFT")
  panel.instructions:SetTextColor(.9, .84, .72)

  panel.refresh = CreateManualPickerButton(panel, 236, -62, 78, 22, "Refresh", function() APOCLootPrio:RefreshSyncedClients(true) end)
  panel.clearOld = CreateManualPickerButton(panel, 322, -62, 78, 22, "Clear Old", function() APOCLootPrio:ClearOldSyncedClients() end)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 10, -92)
  panel.scroll:SetPoint("BOTTOMRIGHT", -28, 34)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content.rowWidth = 382
  panel.content:SetSize(panel.content.rowWidth, 1)
  panel.scroll:SetScrollChild(panel.content)

  panel.status = Font(panel, 10, "", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", 12, 14)
  panel.status:SetPoint("BOTTOMRIGHT", -12, 14)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  return panel
end

local function CreateLootRollResultsPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioLootRollResultsPanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(560, 480)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:SetScript("OnMouseDown", function() end)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 19)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  panel.title = Font(panel, 12, "Loot Details & Rolls", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetLootRollResultsPanelShown(false) end)

  panel.icon = CreateFrame("Button", nil, panel)
  panel.icon:SetSize(38, 38)
  panel.icon:SetPoint("TOPLEFT", 18, -42)
  panel.icon:EnableMouse(true)
  panel.icon:SetScript("OnEnter", function(button)
    if button.drop then ShowDropTooltip(button, button.drop) end
  end)
  panel.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.iconTexture = panel.icon:CreateTexture(nil, "ARTWORK")
  panel.iconTexture:SetAllPoints(panel.icon)
  panel.icon:Hide()

  panel.item = Font(panel, 11, "Select a loot drop.", "GameFontNormal")
  panel.item:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 10, -2)
  panel.item:SetPoint("TOPRIGHT", -18, -42)
  panel.item:SetJustifyH("LEFT")
  panel.item:SetTextColor(.9, .84, .72)

  panel.itemPrio = Font(panel, 10, "", "GameFontNormalSmall")
  panel.itemPrio:SetPoint("TOPLEFT", panel.item, "BOTTOMLEFT", 0, -3)
  panel.itemPrio:SetPoint("TOPRIGHT", -18, -58)
  panel.itemPrio:SetJustifyH("LEFT")
  panel.itemPrio:SetTextColor(1, .85, .2)

  panel.content = CreateFrame("Frame", nil, panel)
  panel.content:SetPoint("TOPLEFT", 24, -104)
  panel.content:SetPoint("BOTTOMRIGHT", -24, 38)
  panel.content.rollRowWidth = 512
  panel.content:SetSize(panel.content.rollRowWidth, 340)

  panel.status = Font(panel, 10, "One MS and one OS roll per player. MS ranks first.", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", 18, 16)
  panel.status:SetPoint("BOTTOMRIGHT", -226, 16)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  panel.resetTimer = CreateManualPickerButton(panel, 342, -446, 104, 24, "Reset Timer", function()
    APOCLootPrio:ResetSelectedRaidLootRollTimer()
  end)

  panel.resetRolls = CreateManualPickerButton(panel, 456, -446, 86, 24, "Reset Rolls", function()
    APOCLootPrio:SetLootRollResetPromptShown(true)
  end)

  panel.awardPrompt = CreateFrame("Frame", "APOCLootPrioLootRollAwardPrompt", UIParent, "BasicFrameTemplateWithInset")
  panel.awardPrompt.ownerFrame = panel
  panel.awardPrompt:SetSize(300, 122)
  panel.awardPrompt:SetPoint("CENTER", panel, "CENTER", 0, 0)
  panel.awardPrompt:EnableMouse(true)
  if panel.awardPrompt.SetToplevel then panel.awardPrompt:SetToplevel(true) end
  if panel.awardPrompt.SetClampedToScreen then panel.awardPrompt:SetClampedToScreen(true) end
  panel.awardPrompt:Hide()
  SetAddonFrameLayer(panel.awardPrompt, ADDON_FRAME_LEVEL + 80)

  local promptBg = panel.awardPrompt:CreateTexture(nil, "BACKGROUND")
  promptBg:SetPoint("TOPLEFT", 8, -28)
  promptBg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(promptBg, .97)

  panel.awardPrompt.title = Font(panel.awardPrompt, 12, "Award Roll", "GameFontHighlight")
  panel.awardPrompt.title:SetPoint("TOPLEFT", 10, -10)
  panel.awardPrompt.title:SetPoint("TOPRIGHT", -34, -10)
  panel.awardPrompt.title:SetJustifyH("LEFT")
  panel.awardPrompt.title:SetTextColor(1, .85, .2)

  panel.awardPrompt.close = panel.awardPrompt.CloseButton or CreateFrame("Button", nil, panel.awardPrompt, "UIPanelCloseButton")
  panel.awardPrompt.close:SetSize(24, 24)
  panel.awardPrompt.close:SetPoint("TOPRIGHT", -2, -2)
  panel.awardPrompt.close:SetScript("OnClick", function() APOCLootPrio:SetLootRollAwardPromptShown(false) end)

  panel.awardPrompt.message = Font(panel.awardPrompt, 10, "Choose award type.", "GameFontNormalSmall")
  panel.awardPrompt.message:SetPoint("TOPLEFT", 14, -42)
  panel.awardPrompt.message:SetPoint("TOPRIGHT", -14, -42)
  panel.awardPrompt.message:SetHeight(28)
  panel.awardPrompt.message:SetJustifyH("LEFT")
  panel.awardPrompt.message:SetTextColor(.9, .84, .72)

  panel.awardPrompt.ms = CreateManualPickerButton(panel.awardPrompt, 16, -78, 54, 24, "MS", function() APOCLootPrio:AwardRollResultWinner("MS") end)
  panel.awardPrompt.os = CreateManualPickerButton(panel.awardPrompt, 82, -78, 54, 24, "OS", function() APOCLootPrio:AwardRollResultWinner("OS") end)
  panel.awardPrompt.de = CreateManualPickerButton(panel.awardPrompt, 148, -78, 54, 24, "DE", function() APOCLootPrio:AwardRollResultWinner("DE") end)
  panel.awardPrompt.cancel = CreateManualPickerButton(panel.awardPrompt, 214, -78, 64, 24, "Cancel", function() APOCLootPrio:SetLootRollAwardPromptShown(false) end)

  panel.resetPrompt = CreateFrame("Frame", "APOCLootPrioLootRollResetPrompt", UIParent, "BasicFrameTemplateWithInset")
  panel.resetPrompt.ownerFrame = panel
  panel.resetPrompt:SetSize(340, 122)
  panel.resetPrompt:SetPoint("CENTER", panel, "CENTER", 0, 0)
  panel.resetPrompt:EnableMouse(true)
  if panel.resetPrompt.SetToplevel then panel.resetPrompt:SetToplevel(true) end
  if panel.resetPrompt.SetClampedToScreen then panel.resetPrompt:SetClampedToScreen(true) end
  panel.resetPrompt:Hide()
  SetAddonFrameLayer(panel.resetPrompt, ADDON_FRAME_LEVEL + 81)

  local resetPromptBg = panel.resetPrompt:CreateTexture(nil, "BACKGROUND")
  resetPromptBg:SetPoint("TOPLEFT", 8, -28)
  resetPromptBg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(resetPromptBg, .97)

  panel.resetPrompt.title = Font(panel.resetPrompt, 12, "Reset Rolls?", "GameFontHighlight")
  panel.resetPrompt.title:SetPoint("TOPLEFT", 10, -10)
  panel.resetPrompt.title:SetPoint("TOPRIGHT", -34, -10)
  panel.resetPrompt.title:SetJustifyH("LEFT")
  panel.resetPrompt.title:SetTextColor(1, .85, .2)

  panel.resetPrompt.close = panel.resetPrompt.CloseButton or CreateFrame("Button", nil, panel.resetPrompt, "UIPanelCloseButton")
  panel.resetPrompt.close:SetSize(24, 24)
  panel.resetPrompt.close:SetPoint("TOPRIGHT", -2, -2)
  panel.resetPrompt.close:SetScript("OnClick", function() APOCLootPrio:SetLootRollResetPromptShown(false) end)

  panel.resetPrompt.message = Font(panel.resetPrompt, 10, "Reset all rolls?", "GameFontNormalSmall")
  panel.resetPrompt.message:SetPoint("TOPLEFT", 14, -42)
  panel.resetPrompt.message:SetPoint("TOPRIGHT", -14, -42)
  panel.resetPrompt.message:SetHeight(28)
  panel.resetPrompt.message:SetJustifyH("LEFT")
  panel.resetPrompt.message:SetTextColor(.9, .84, .72)

  panel.resetPrompt.confirm = CreateManualPickerButton(panel.resetPrompt, 110, -78, 86, 24, "Reset", function() APOCLootPrio:ConfirmSelectedRaidLootRollReset() end)
  panel.resetPrompt.cancel = CreateManualPickerButton(panel.resetPrompt, 210, -78, 86, 24, "Cancel", function() APOCLootPrio:SetLootRollResetPromptShown(false) end)

  panel:SetScript("OnUpdate", function(frame, elapsed)
    frame.rollUpdateElapsed = (frame.rollUpdateElapsed or 0) + (elapsed or 0)
    if frame.rollUpdateElapsed < .5 then return end
    frame.rollUpdateElapsed = 0
    if APOCLootPrio and APOCLootPrio.RefreshLootRollResultsPanel then
      APOCLootPrio:RefreshLootRollResultsPanel()
    end
  end)

  return panel
end

local function CreateAttendancePanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioAttendancePanel", UIParent, "BasicFrameTemplateWithInset")
  panel.ownerFrame = parent
  panel:SetPoint("CENTER", parent, "CENTER", 0, 42)
  panel:SetSize(590, 500)
  panel:EnableMouse(true)
  if panel.SetToplevel then panel:SetToplevel(true) end
  if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 18)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .96)

  panel.title = Font(panel, 12, "Raid Attendance", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetAttendancePanelShown(false) end)

  panel.session = Font(panel, 10, "No active session", "GameFontNormalSmall")
  panel.session:SetPoint("TOPLEFT", 16, -38)
  panel.session:SetPoint("TOPRIGHT", -118, -38)
  panel.session:SetJustifyH("LEFT")
  panel.session:SetTextColor(.9, .84, .72)

  panel.refresh = CreateManualPickerButton(panel, 486, -34, 82, 22, "Refresh", function()
    if APOCLootPrio.ScheduleRaidAttendanceUpdate then APOCLootPrio:ScheduleRaidAttendanceUpdate(.2, true) end
    APOCLootPrio:RefreshAttendancePanel()
  end)

  local header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", 16, -66)
  header:SetPoint("TOPRIGHT", -28, -66)
  header:SetHeight(24)
  local headerBg = header:CreateTexture(nil, "BACKGROUND")
  headerBg:SetAllPoints(header)
  SetTextureColor(headerBg, .09, .07, .04, .80)
  local hName = Font(header, 10, "Player", "GameFontHighlightSmall")
  hName:SetPoint("LEFT", 10, 0)
  hName:SetTextColor(1, .85, .2)
  local hJoin = Font(header, 10, "Joined", "GameFontHighlightSmall")
  hJoin:SetPoint("LEFT", 220, 0)
  hJoin:SetTextColor(1, .85, .2)
  local hLeave = Font(header, 10, "Left", "GameFontHighlightSmall")
  hLeave:SetPoint("LEFT", 370, 0)
  hLeave:SetTextColor(1, .85, .2)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", 16, -94)
  panel.scroll:SetPoint("BOTTOMRIGHT", -30, 42)
  EnableCleanMouseWheelScroll(panel.scroll, 38)

  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content:SetSize(536, 1)
  panel.scroll:SetScrollChild(panel.content)

  panel.status = Font(panel, 10, "Attendance begins when the loot session starts.", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", 16, 16)
  panel.status:SetPoint("BOTTOMRIGHT", -16, 16)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  return panel
end


local function CreateRaidLootPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioRaidLootPanel", UIParent, "BasicFrameTemplateWithInset")
  local savedWidth, savedHeight = GetSavedPanelSize("lootTracker", RAID_LOOT_WINDOW_WIDTH, RAID_LOOT_WINDOW_HEIGHT)
  savedWidth = ClampNumber(savedWidth, RAID_LOOT_WINDOW_WIDTH, RAID_LOOT_WINDOW_MAX_WIDTH)
  savedHeight = ClampNumber(savedHeight, RAID_LOOT_WINDOW_HEIGHT, RAID_LOOT_WINDOW_MAX_HEIGHT)
  -- Keep a size saved on a 4K display usable on more common 1080p setups.
  local screenWidth = UIParent.GetWidth and UIParent:GetWidth() or savedWidth
  local screenHeight = UIParent.GetHeight and UIParent:GetHeight() or savedHeight
  savedWidth = math.min(savedWidth, math.max(RAID_LOOT_WINDOW_WIDTH, math.floor(screenWidth * .86)))
  savedHeight = math.min(savedHeight, math.max(RAID_LOOT_WINDOW_HEIGHT, math.floor(screenHeight * .90)))
  panel:SetSize(savedWidth, savedHeight)
  panel:SetScale(RAID_LOOT_WINDOW_UI_SCALE)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 12, 0)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 10)
  AddResizeGrip(panel, "lootTracker", RAID_LOOT_WINDOW_WIDTH, RAID_LOOT_WINDOW_HEIGHT, RAID_LOOT_WINDOW_MAX_WIDTH, RAID_LOOT_WINDOW_MAX_HEIGHT, function()
    if APOCLootPrio and APOCLootPrio.LayoutRaidLootPanel then APOCLootPrio:LayoutRaidLootPanel() end
  end)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.45, .35, .18, .72)
  border:Hide()

  panel.title = Font(panel, 13, "APOC Loot Tracker - Multi-Run Beta", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 50, -7)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("CENTER")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:ClearAllPoints()
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetRaidLootPanelShown(false) end)

  -- Esc closes the tracker the same way the X button does (UISpecialFrames).
  if UISpecialFrames then
    local alreadyListed = false
    for _, name in ipairs(UISpecialFrames) do
      if name == "APOCLootPrioRaidLootPanel" then alreadyListed = true; break end
    end
    if not alreadyListed then table.insert(UISpecialFrames, "APOCLootPrioRaidLootPanel") end
  end
  panel:SetScript("OnHide", function()
    if APOCLootPrio and APOCLootPrio.raidLootPanelShown then
      APOCLootPrio:SetRaidLootPanelShown(false)
    end
  end)

  panel.session = Font(panel, 10, "No session", "GameFontNormalSmall")
  panel.session:SetPoint("TOPLEFT", 18, -34)
  panel.session:SetPoint("TOPRIGHT", -18, -34)
  panel.session:SetJustifyH("LEFT")
  panel.session:SetTextColor(.72, .72, .72)

  panel.selectedItem = Font(panel, 10, "Auto Track: Raid. Click an item as a manual fallback.", "GameFontNormalSmall")
  panel.selectedItem:SetPoint("TOPLEFT", 18, -54)
  panel.selectedItem:SetPoint("TOPRIGHT", -314, -54)
  panel.selectedItem:SetJustifyH("LEFT")
  panel.selectedItem:SetTextColor(1, .85, .2)

  panel.addDrop = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.addDrop:SetSize(88, 24)
  panel.addDrop:SetPoint("TOPLEFT", 18, -76)
  panel.addDrop:SetText("Add Manual")
  panel.addDrop:SetScript("OnClick", function() APOCLootPrio:SetManualLootPickerShown(true) end)

  panel.newSession = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.newSession:SetSize(100, 24)
  panel.newSession:SetPoint("LEFT", panel.addDrop, "RIGHT", 8, 0)
  panel.newSession:SetText("New Session")
  panel.newSession:SetScript("OnClick", function() APOCLootPrio:SetNewLootSessionConfirmShown(true) end)

  panel.renameSession = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.renameSession:SetSize(76, 24)
  panel.renameSession:SetPoint("LEFT", panel.newSession, "RIGHT", 8, 0)
  panel.renameSession:SetText("Rename")
  panel.renameSession:SetScript("OnClick", function() APOCLootPrio:SetRenameLootSessionShown(true) end)

  panel.sessionsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.sessionsButton:SetSize(78, 24)
  panel.sessionsButton:SetPoint("LEFT", panel.renameSession, "RIGHT", 8, 0)
  panel.sessionsButton:SetText("History")
  panel.sessionsButton:SetScript("OnClick", function() APOCLootPrio:ToggleLootSessionPicker() end)

  panel.liveRaidsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.liveRaidsButton:SetSize(82, 24)
  panel.liveRaidsButton:SetPoint("LEFT", panel.sessionsButton, "RIGHT", 8, 0)
  panel.liveRaidsButton:SetText("Live Raids")
  panel.liveRaidsButton:SetScript("OnClick", function() APOCLootPrio:ToggleLiveRaidsPanel() end)

  panel.getListButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.getListButton:SetSize(72, 24)
  panel.getListButton:SetPoint("LEFT", panel.liveRaidsButton, "RIGHT", 8, 0)
  panel.getListButton:SetText("Get List")
  panel.getListButton:SetScript("OnClick", function()
    local ok, message
    if APOCLootPrio.ForceLiveListSync then
      ok, message = APOCLootPrio:ForceLiveListSync()
    end
    if APOCLootPrio.UpdateRaidLootStatus then
      APOCLootPrio:UpdateRaidLootStatus(message or (ok and "Sync started." or "Could not sync."))
    end
  end)

  panel.awardsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.awardsButton:SetSize(68, 24)
  panel.awardsButton:SetPoint("LEFT", panel.getListButton, "RIGHT", 8, 0)
  panel.awardsButton:SetText("Awards")
  panel.awardsButton:SetScript("OnClick", function() APOCLootPrio:ToggleRecentAwardsPanel() end)

  panel.attendanceButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.attendanceButton:SetSize(86, 24)
  panel.attendanceButton:SetPoint("LEFT", panel.awardsButton, "RIGHT", 8, 0)
  panel.attendanceButton:SetText("Attendance")
  panel.attendanceButton:SetScript("OnClick", function() APOCLootPrio:ToggleAttendancePanel() end)

  panel.trackerSettings = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.trackerSettings:SetSize(72, 24)
  panel.trackerSettings:SetPoint("LEFT", panel.attendanceButton, "RIGHT", 8, 0)
  panel.trackerSettings:SetText("Settings")
  panel.trackerSettings:SetScript("OnClick", function() APOCLootPrio:ToggleSettingsPanelFromLootTracker() end)

  panel.exportSession = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.exportSession:SetSize(76, 24)
  panel.exportSession:SetText("Export")
  panel.exportSession:SetScript("OnClick", function()
    local ok, message = APOCLootPrio:ExportSelectedLootSession()
    APOCLootPrio:UpdateRaidLootStatus(message or (ok and "Export prepared." or "Could not export this raid."))
  end)

  panel.closeSession = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.closeSession:SetSize(92, 24)
  panel.closeSession:SetPoint("LEFT", panel.trackerSettings, "RIGHT", 8, 0)
  panel.closeSession:SetText("Close & Save")
  panel.closeSession:SetScript("OnClick", function() APOCLootPrio:SetCloseLootSessionConfirmShown(true) end)

  panel.trackerRunner = Font(panel, 10, "Master Looter: Not detected", "GameFontNormalSmall")
  panel.trackerRunner:SetPoint("TOPRIGHT", -18, -34)
  panel.trackerRunner:SetJustifyH("RIGHT")
  if panel.trackerRunner.SetWordWrap then panel.trackerRunner:SetWordWrap(false) end
  panel.trackerRunner:SetTextColor(.9, .84, .72)

  panel.setRunnerToML = CreateManualPickerButton(panel, 0, 0, 96, 20, "Set runner to ML", function() APOCLootPrio:SetRunnerToMasterLooter() end)
  panel.setRunnerToML:ClearAllPoints()
  panel.setRunnerToML:SetPoint("TOPRIGHT", -18, -52)
  panel.setRunnerToML:Hide()

  panel.queueTitle = Font(panel, 11, "Dropped loot queue", "GameFontHighlight")
  panel.queueTitle:SetPoint("TOPLEFT", 18, -112)
  panel.queueTitle:SetTextColor(1, .85, .2)

  panel.queueList = CreateFrame("Frame", nil, panel)
  panel.queueList:SetSize(RAID_LOOT_WINDOW_WIDTH - 38, LOOT_TRACKER_LIST_HEIGHT)
  panel.queueList:SetPoint("TOPLEFT", 18, -132)

  panel.awardTitle = Font(panel, 11, "Award selected drop", "GameFontHighlight")
  panel.awardTitle:SetPoint("TOPLEFT", 18, -374)
  panel.awardTitle:SetTextColor(1, .85, .2)

  panel.selectedDropPreview = CreateFrame("Frame", nil, panel)
  panel.selectedDropPreview:SetSize(RAID_LOOT_WINDOW_WIDTH - 36, 58)
  panel.selectedDropPreview:SetPoint("TOPLEFT", 18, -398)

  panel.selectedDropPreviewBg = panel.selectedDropPreview:CreateTexture(nil, "BACKGROUND")
  panel.selectedDropPreviewBg:SetAllPoints(panel.selectedDropPreview)
  SetAPOCRowTexture(panel.selectedDropPreviewBg, .62)

  panel.selectedDropPreviewTop = panel.selectedDropPreview:CreateTexture(nil, "BORDER")
  panel.selectedDropPreviewTop:SetPoint("TOPLEFT", 0, 0)
  panel.selectedDropPreviewTop:SetPoint("TOPRIGHT", 0, 0)
  panel.selectedDropPreviewTop:SetHeight(1)
  SetTextureColor(panel.selectedDropPreviewTop, .28, .28, .30, .85)

  panel.selectedDropPreviewBottom = panel.selectedDropPreview:CreateTexture(nil, "BORDER")
  panel.selectedDropPreviewBottom:SetPoint("BOTTOMLEFT", 0, 0)
  panel.selectedDropPreviewBottom:SetPoint("BOTTOMRIGHT", 0, 0)
  panel.selectedDropPreviewBottom:SetHeight(1)
  SetTextureColor(panel.selectedDropPreviewBottom, .28, .28, .30, .85)

  panel.selectedDropRollButton = CreateFrame("Button", nil, panel.selectedDropPreview, "UIPanelButtonTemplate")
  panel.selectedDropRollButton:SetSize(52, 22)
  panel.selectedDropRollButton:SetPoint("RIGHT", -156, 0)
  panel.selectedDropRollButton:SetText("Roll")
  panel.selectedDropRollButton:SetScript("OnClick", function()
    APOCLootPrio:StartSelectedRaidLootRoll()
  end)

  panel.selectedDropRollResultsButton = CreateFrame("Button", nil, panel.selectedDropPreview, "UIPanelButtonTemplate")
  panel.selectedDropRollResultsButton:SetSize(86, 22)
  panel.selectedDropRollResultsButton:SetPoint("LEFT", panel.selectedDropRollButton, "RIGHT", 6, 0)
  panel.selectedDropRollResultsButton:SetText("Results")
  panel.selectedDropRollResultsButton:SetScript("OnClick", function()
    APOCLootPrio:ToggleLootRollResultsPanel()
  end)

  panel.selectedDropRollResetButton = CreateFrame("Button", nil, panel.selectedDropPreview, "UIPanelButtonTemplate")
  panel.selectedDropRollResetButton:SetSize(54, 22)
  panel.selectedDropRollResetButton:SetPoint("LEFT", panel.selectedDropRollResultsButton, "RIGHT", 6, 0)
  panel.selectedDropRollResetButton:SetText("Reset")
  panel.selectedDropRollResetButton:SetScript("OnClick", function()
    APOCLootPrio:SetLootRollResetPromptShown(true)
  end)

  panel.selectedDropRollResult = Font(panel.selectedDropPreview, 10, "", "GameFontNormalSmall")
  panel.selectedDropRollResult:SetPoint("LEFT", panel.selectedDropRollButton, "RIGHT", 8, 0)
  panel.selectedDropRollResult:SetPoint("RIGHT", -10, 0)
  panel.selectedDropRollResult:SetHeight(52)
  panel.selectedDropRollResult:SetJustifyH("LEFT")
  if panel.selectedDropRollResult.SetJustifyV then panel.selectedDropRollResult:SetJustifyV("MIDDLE") end
  panel.selectedDropRollResult:SetTextColor(1, .85, .2)
  panel.selectedDropRollResult:Hide()

  panel.selectedDropPreview:SetScript("OnUpdate", function(frame, elapsed)
    frame.rollUpdateElapsed = (frame.rollUpdateElapsed or 0) + (elapsed or 0)
    if frame.rollUpdateElapsed < .5 then return end
    frame.rollUpdateElapsed = 0
    if not APOCLootPrio or not APOCLootPrio.selectedLootDropID then return end
    local trackerRaid = APOCLootPrio.selectedLootTrackerRaid or APOCLootPrio.selectedRaid
    local drop = APOCLootPrio:FindRaidLootDrop(APOCLootPrio.selectedLootDropID, trackerRaid)
    RefreshSelectedDropRollDisplay(APOCLootPrio.frame and APOCLootPrio.frame.raidLootPanel, drop)
    if APOCLootPrio.lootRollResultsPanelShown and APOCLootPrio.RefreshLootRollResultsPanel then
      APOCLootPrio:RefreshLootRollResultsPanel()
    end
  end)

  panel.selectedDropIcon = CreateFrame("Button", nil, panel.selectedDropPreview)
  panel.selectedDropIcon:SetSize(44, 44)
  panel.selectedDropIcon:SetPoint("LEFT", 8, 0)
  panel.selectedDropIcon:EnableMouse(true)
  panel.selectedDropIcon:SetScript("OnEnter", function(button)
    if button.drop then ShowDropTooltip(button, button.drop) end
  end)
  panel.selectedDropIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.selectedDropIcon:RegisterForClicks("LeftButtonUp")
  panel.selectedDropIcon:SetScript("OnClick", function(button)
    if InsertItemLinkIntoChat(DropAsItem(button.drop)) then return end
    APOCLootPrio:SetLootRollResultsPanelShown(true)
  end)
  panel.selectedDropIconTexture = panel.selectedDropIcon:CreateTexture(nil, "ARTWORK")
  panel.selectedDropIconTexture:SetAllPoints(panel.selectedDropIcon)
  panel.selectedDropIcon:Hide()

  panel.selectedDrop = Font(panel.selectedDropPreview, 11, "Select a drop from the queue.", "GameFontNormal")
  panel.selectedDrop:SetPoint("TOPLEFT", panel.selectedDropIcon, "TOPRIGHT", 12, -6)
  panel.selectedDrop:SetPoint("RIGHT", panel.selectedDropRollButton, "LEFT", -12, 0)
  panel.selectedDrop:SetJustifyH("LEFT")
  panel.selectedDrop:SetTextColor(.9, .84, .72)

  panel.selectedDropPrio = Font(panel.selectedDropPreview, 10, "", "GameFontNormalSmall")
  panel.selectedDropPrio:SetPoint("TOPLEFT", panel.selectedDrop, "BOTTOMLEFT", 0, -2)
  panel.selectedDropPrio:SetPoint("RIGHT", panel.selectedDropRollButton, "LEFT", -12, 0)
  panel.selectedDropPrio:SetJustifyH("LEFT")
  panel.selectedDropPrio:SetTextColor(1, .85, .2)

  panel.winnerLabel = AddEditorLabel(panel, "Winner", 18, -438)
  panel.winner = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.winner:SetSize(RAID_LOOT_WINDOW_WIDTH - 36, 26)
  panel.winner:SetPoint("TOPLEFT", 18, -458)
  panel.winner:SetAutoFocus(false)
  panel.winner:SetMaxLetters(48)
  panel.winner:SetTextInsets(6, 6, 0, 0)
  panel.winner:SetScript("OnTextChanged", function() APOCLootPrio:RefreshGroupMemberList() end)

  panel.winnerPlaceholder = Font(panel.winner, 12, "Search raid member", "GameFontNormal")
  panel.winnerPlaceholder:SetPoint("LEFT", 8, 0)
  panel.winnerPlaceholder:SetTextColor(.55, .55, .55)

  panel.me = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.me:SetSize(44, 22)
  panel.me:SetPoint("TOPRIGHT", panel.winner, "TOPRIGHT", -4, 2)
  panel.me:SetText("Me")
  panel.me:SetScript("OnClick", function()
    panel.selectedWinnerName = APOCLootPrio:GetPlayerDisplayName() or ""
    APOCLootPrio:RefreshGroupMemberList()
  end)
  panel.me:Hide()

  panel.memberSummary = Font(panel, 10, "0 shown of 0 raid members", "GameFontNormalSmall")
  panel.memberSummary:SetPoint("TOPLEFT", 18, -490)
  panel.memberSummary:SetPoint("TOPRIGHT", -18, -490)
  panel.memberSummary:SetJustifyH("LEFT")
  panel.memberSummary:SetTextColor(.9, .84, .72)

  -- Use a plain clipped scroll frame here. The Blizzard panel template places
  -- its arrow buttons outside the scaled roster area on some UI scales.
  panel.memberScroll = CreateFrame("ScrollFrame", nil, panel)
  panel.memberScroll:EnableMouseWheel(true)
  panel.memberScroll:SetScript("OnMouseWheel", function(scrollFrame, delta)
    local child = scrollFrame:GetScrollChild()
    local maxScroll = math.max(0, (child and child:GetHeight() or 0) - scrollFrame:GetHeight())
    local nextScroll = math.max(0, math.min(maxScroll, scrollFrame:GetVerticalScroll() - (delta * 32)))
    scrollFrame:SetVerticalScroll(nextScroll)
  end)
  panel.memberScroll:SetPoint("TOPLEFT", 18, -512)
  panel.memberScroll:SetSize(RAID_LOOT_WINDOW_WIDTH - 36, 180)

  panel.memberContent = CreateFrame("Frame", nil, panel.memberScroll)
  panel.memberContent:SetPoint("TOPLEFT", 0, 0)
  panel.memberContent:SetSize(RAID_LOOT_WINDOW_WIDTH - 62, 1)
  panel.memberScroll:SetScrollChild(panel.memberContent)

  panel.typeLabel = AddEditorLabel(panel, "Type", 18, -696)
  AddAwardTypeButtons(panel, 62, -694, 54)

  panel.noteLabel = AddEditorLabel(panel, "Note", 18, -726)
  panel.note = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.note:SetSize(RAID_LOOT_WINDOW_WIDTH - 170, 22)
  panel.note:SetPoint("TOPLEFT", 62, -724)
  panel.note:SetAutoFocus(false)
  panel.note:SetMaxLetters(90)
  panel.note:SetTextInsets(6, 6, 0, 0)

  panel.award = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.award:SetSize(94, 24)
  panel.award:SetPoint("TOPLEFT", 18, -756)
  panel.award:SetText("Save Award")
  panel.award:SetScript("OnClick", function() APOCLootPrio:SaveRaidLootAward() end)

  panel.status = Font(panel, 10, "Drops are saved per raid session.", "GameFontNormalSmall")
  panel.status:SetPoint("LEFT", panel.award, "RIGHT", 8, 0)
  panel.status:SetPoint("RIGHT", -18, 0)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  panel.recentAwardsPanel = CreateRecentAwardsPanel(panel)
  panel.manualPicker = CreateManualLootPicker(panel)
  panel.deleteConfirm = CreateLootDeleteConfirm(panel)
  panel.sessionPicker = CreateLootSessionPicker(panel)
  panel.sessionDeleteConfirm = CreateLootSessionDeleteConfirm(panel)
  panel.newSessionConfirm = CreateNewLootSessionConfirm(panel)
  panel.renameSessionPrompt = CreateRenameLootSessionPrompt(panel)
  panel.closeSessionConfirm = CreateCloseLootSessionConfirm(panel)
  panel.runnerPicker = CreateLootTrackerRunnerPicker(panel)
  panel.disenchanterPicker = CreateLootDisenchanterPicker(panel)
  panel.trackerSettingsPanel = CreateLootTrackerSettingsPanel(panel)
  panel.liveRaidsPanel = CreateLiveRaidsPanel(panel)
  panel.syncedClientsPanel = CreateSyncedClientsPanel(panel)
  panel.lootRollResultsPanel = CreateLootRollResultsPanel(panel)
  panel.attendancePanel = CreateAttendancePanel(panel)

  return panel
end

local function CreateGuildLootPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioGuildLootPanel", UIParent, "BasicFrameTemplateWithInset")
  panel:SetSize(GUILD_LOOT_WINDOW_WIDTH, FRAME_HEIGHT)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 18, -34)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 12)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  border:SetVertexColor(.45, .35, .18, .72)
  border:Hide()

  panel.title = Font(panel, 13, "Guild Main Spec Loot", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 50, -7)
  panel.title:SetPoint("TOPRIGHT", -34, -10)
  panel.title:SetJustifyH("CENTER")
  panel.title:SetTextColor(1, .85, .2)

  panel.close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:ClearAllPoints()
  panel.close:SetPoint("TOPRIGHT", -2, -2)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetGuildLootPanelShown(false) end)

  panel.status = Font(panel, 10, "Lifetime main-spec awards from saved loot sessions.", "GameFontNormalSmall")
  panel.status:SetPoint("TOPLEFT", 18, -34)
  panel.status:SetPoint("TOPRIGHT", -116, -34)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(.72, .72, .72)

  panel.refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.refresh:SetSize(84, 24)
  panel.refresh:SetPoint("TOPRIGHT", -18, -30)
  panel.refresh:SetText("Refresh")
  panel.refresh:SetScript("OnClick", function() APOCLootPrio:RefreshGuildLootPanel() end)

  AddEditorLabel(panel, "Search", 18, -58)
  panel.search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.search:SetSize(116, 22)
  panel.search:SetPoint("TOPLEFT", 70, -56)
  panel.search:SetAutoFocus(false)
  panel.search:SetMaxLetters(48)
  panel.search:SetTextInsets(6, 6, 0, 0)
  panel.search:SetScript("OnTextChanged", function() APOCLootPrio:RefreshGuildLootPanel() end)

  AddEditorLabel(panel, "Class", 198, -58)
  panel.classFilter = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.classFilter:SetSize(92, 22)
  panel.classFilter:SetPoint("TOPLEFT", 240, -56)
  panel.classFilter:SetAutoFocus(false)
  panel.classFilter:SetMaxLetters(32)
  panel.classFilter:SetTextInsets(6, 6, 0, 0)
  panel.classFilter:SetScript("OnTextChanged", function() APOCLootPrio:RefreshGuildLootPanel() end)

  AddEditorLabel(panel, "Sort", 344, -58)
  panel.sortByName = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.sortByName:SetSize(54, 22)
  panel.sortByName:SetPoint("TOPLEFT", 382, -56)
  panel.sortByName:SetText("Name")
  panel.sortByName:SetScript("OnClick", function()
    panel.sortMode = "name"
    APOCLootPrio:RefreshGuildLootPanel()
  end)

  panel.sortByRank = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.sortByRank:SetSize(54, 22)
  panel.sortByRank:SetPoint("LEFT", panel.sortByName, "RIGHT", 5, 0)
  panel.sortByRank:SetText("Rank")
  panel.sortByRank:SetScript("OnClick", function()
    panel.sortMode = "rank"
    APOCLootPrio:RefreshGuildLootPanel()
  end)
  panel.sortMode = "name"

  CreateGuildLootEditPopup(panel)

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 18, -88)
  scroll:SetPoint("BOTTOMRIGHT", -34, 18)
  panel.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(GUILD_LOOT_ROW_WIDTH, 1)
  scroll:SetScrollChild(content)
  panel.content = content

  return panel
end

local function CreateSettingsPanel(parent)
  local panel = CreateFrame("Frame", "APOCLootPrioSettingsPanel", UIParent, "BasicFrameTemplateWithInset")
  panel:SetSize(SETTINGS_PANEL_WIDTH, 230)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", LOG_PANEL_GAP, 22)
  SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 14)
  panel:Hide()

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 8, -28)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  SetAPOCPanelTexture(bg, .94)

  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints()
  border:SetColorTexture(.45, .35, .18, .34)
  border:Hide()

  panel.title = Font(panel, 13, "APOC Settings", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 14, -12)
  panel.title:SetTextColor(1, .85, .2)

  panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  panel.close:SetSize(24, 24)
  panel.close:SetPoint("TOPRIGHT", -4, -4)
  panel.close:SetScript("OnClick", function() APOCLootPrio:SetSettingsPanelShown(false) end)

  panel.status = Font(panel, 10, "Top two guild ranks can change feature visibility.", "GameFontNormalSmall")
  panel.status:SetPoint("TOPLEFT", 14, -36)
  panel.status:SetTextColor(.72, .72, .72)

  panel.rows = {}
  local y = -66
  for _, feature in ipairs(SETTINGS_FEATURES) do
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(SETTINGS_PANEL_WIDTH - 28, 32)
    row:SetPoint("TOPLEFT", 14, y)
    row.featureKey = feature.key

    row.label = Font(row, 11, feature.label, "GameFontNormal")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(96)
    row.label:SetJustifyH("LEFT")
    row.label:SetTextColor(1, .85, .2)

    row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.minus:SetSize(24, 22)
    row.minus:SetPoint("LEFT", 104, 0)
    row.minus:SetText("-")
    row.minus:SetScript("OnClick", function()
      APOCLootPrio:AdjustFeatureAccessRank(feature.key, -1)
    end)

    row.rank = Font(row, 10, "", "GameFontNormalSmall")
    row.rank:SetPoint("LEFT", row.minus, "RIGHT", 8, 0)
    row.rank:SetWidth(140)
    row.rank:SetJustifyH("CENTER")
    row.rank:SetTextColor(.9, .84, .72)

    row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.plus:SetSize(24, 22)
    row.plus:SetPoint("LEFT", row.rank, "RIGHT", 8, 0)
    row.plus:SetText("+")
    row.plus:SetScript("OnClick", function()
      APOCLootPrio:AdjustFeatureAccessRank(feature.key, 1)
    end)

    table.insert(panel.rows, row)
    y = y - 34
  end

  panel.note = Font(panel, 10, "Rank 0 is guild master. Higher numbers allow lower ranks.", "GameFontNormalSmall")
  panel.note:SetPoint("BOTTOMLEFT", 14, 14)
  panel.note:SetWidth(SETTINGS_PANEL_WIDTH - 28)
  panel.note:SetTextColor(.72, .72, .72)

  panel.version = Font(panel, 10, "Version " .. GetAddonVersion(), "GameFontNormalSmall")
  panel.version:SetPoint("BOTTOMRIGHT", -14, 30)
  panel.version:SetTextColor(.72, .72, .72)

  return panel
end

function APOCLootPrio:CreateUI()
  local f = CreateFrame("Frame", "APOCLootPrioFrame", UIParent, "BasicFrameTemplateWithInset")
  local savedWidth, savedHeight = GetSavedPanelSize("main", FRAME_WIDTH, FRAME_HEIGHT)
  self.frame = f; f:SetSize(savedWidth, savedHeight); f:SetPoint("CENTER"); f:Hide()
  SetAddonFrameLayer(f, ADDON_FRAME_LEVEL)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  AddResizeGrip(f, "main", FRAME_WIDTH, FRAME_HEIGHT, 1180, 900, function()
    if APOCLootPrio and APOCLootPrio.LayoutScroll then APOCLootPrio:LayoutScroll() end
  end)
  f:SetScript("OnHide", function()
    self.adminMode = false
    self.logPanelShown = false
    self.settingsPanelShown = false
    self.settingsPanelAnchor = nil
    if self.frame and self.frame.adminPanel then
      self.frame.adminPanel:Hide()
    end
    if self.frame and self.frame.adminButton then self.frame.adminButton:SetText("Admin") end
    if self.frame and self.frame.logPanel then
      self.frame.logPanel:SetScript("OnUpdate", nil)
      SetLogPanelOffset(self.frame.logPanel, -LOG_PANEL_WIDTH)
      self.frame.logPanel:Hide()
    end
    if self.frame and self.frame.logButton then self.frame.logButton:SetText("Log") end
    if self.frame and self.frame.settingsPanel then self.frame.settingsPanel:Hide() end
    if self.frame and self.frame.settingsButton then self.frame.settingsButton:SetText("Settings") end
  end)

  f.title = Font(f, 13, "APOC Loot Tracker - Multi-Run Beta")
  f.title:SetPoint("TOPLEFT", 22, -8)
  f.title:SetPoint("TOPRIGHT", f, "TOPLEFT", FRAME_WIDTH - 220, -8)
  f.title:SetHeight(16)
  f.title:SetJustifyH("LEFT")
  f.title:SetJustifyV("MIDDLE")
  f.title:SetTextColor(1, .92, .72)

  f.headerStatus = Font(f, 10, "Guild view", "GameFontNormalSmall")
  f.headerStatus:SetPoint("TOPRIGHT", -22, -10)
  f.headerStatus:SetSize(200, 14)
  f.headerStatus:SetJustifyH("RIGHT")
  f.headerStatus:SetTextColor(.86, .80, .68)
  StyleAPOCPanelTitle(f)

  f.browserButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.browserButton:SetSize(126, 28)
  f.browserButton:SetPoint("TOPLEFT", 18, -42)
  f.browserButton:SetText("Loot Browser")
  f.browserButton:SetScript("OnClick", function() self:ShowLootBrowser() end)

  f.raidLootButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.raidLootButton:SetSize(128, 28)
  f.raidLootButton:SetPoint("LEFT", f.browserButton, "RIGHT", 8, 0)
  f.raidLootButton:SetText("Loot Tracker")
  f.raidLootButton:SetScript("OnClick", function() self:ToggleRaidLootPanel() end)

  f.guildLootButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.guildLootButton:SetSize(116, 28)
  f.guildLootButton:SetPoint("LEFT", f.raidLootButton, "RIGHT", 8, 0)
  f.guildLootButton:SetText("Guild Loot")
  f.guildLootButton:SetScript("OnClick", function() self:ToggleGuildLootPanel() end)

  f.adminButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.adminButton:SetSize(86, 28)
  f.adminButton:SetPoint("LEFT", f.guildLootButton, "RIGHT", 8, 0)
  f.adminButton:SetText("Admin")
  f.adminButton:SetScript("OnClick", function() self:ToggleAdminMode() end)

  f.settingsButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.settingsButton:SetSize(104, 28)
  f.settingsButton:SetPoint("LEFT", f.adminButton, "RIGHT", 8, 0)
  f.settingsButton:SetText("Settings")
  f.settingsButton:SetScript("OnClick", function() self:ToggleSettingsPanel() end)

  f.tabs = {}; local x, tabY = 18, -82
  for _, raid in ipairs({"Serpentshrine Cavern", "The Eye", "Mount Hyjal", "Black Temple"}) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    local label = raid == "Serpentshrine Cavern" and "SSC" or raid == "Mount Hyjal" and "Hyjal" or raid
    local tabWidth = raid == "Black Temple" and 110 or raid == "The Eye" and 84 or 68
    b:SetSize(tabWidth, 26)
    b:SetPoint("TOPLEFT", x, tabY)
    x = x + tabWidth + 8
    b:SetText(label)
    b.raid = raid
    b:SetScript("OnClick", function(button)
      self.selectedRaid = button.raid
      self.selectedLootTrackerRaid = button.raid
      self.selectedRaidLootItem = nil
      self.selectedLootDropID = nil
      self.frame.search:SetText("")
      self:Refresh(true)
      self:RefreshRaidLootPanel()
    end)
    table.insert(f.tabs, b)
  end

  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(190, 26)
  search:SetPoint("TOPRIGHT", -18, -80)
  search:SetAutoFocus(false)
  search:SetTextInsets(6, 6, 0, 0)
  search:SetScript("OnTextChanged", function() self:Refresh(true) end)
  f.search = search

  local hint = Font(f, 11, "")
  hint:SetPoint("RIGHT", search, "LEFT", -8, 0)
  hint:SetTextColor(.7, .7, .7)

  f.logButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.logButton:SetSize(1, 1)
  f.logButton:SetPoint("TOPLEFT", -200, -200)
  f.logButton:SetText("Log")
  f.logButton:SetScript("OnClick", function() self:ToggleLogPanel() end)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -122)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 18)
  f.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_WIDTH, 1)
  scroll:SetScrollChild(content)
  f.content = content
  f.adminPanel = CreateAdminPanel(f)
  f.logPanel = CreateLogPanel(f)
  f.raidLootPanel = CreateRaidLootPanel(f)
  f.guildLootPanel = CreateGuildLootPanel(f)
  f.settingsPanel = CreateSettingsPanel(f)
  StyleAPOCFrameTree(f)

  self.selectedRaid = "Serpentshrine Cavern"
  self.selectedLootTrackerRaid = self.selectedRaid
  self:RefreshOfficerControls()
  self:SetLogPanelShown(false)
  self:SetRaidLootPanelShown(false)
  self:SetAdminMode(false)
  self:Refresh(true)
end

function APOCLootPrio:LayoutScroll()
  if not self.frame or not self.frame.scroll then return end

  self.frame.scroll:ClearAllPoints()
  self.frame.scroll:SetPoint("TOPLEFT", 16, -122)
  self.frame.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -34, 18)
end

function APOCLootPrio:LayoutRaidLootPanel()
  local panel = self.frame and self.frame.raidLootPanel
  if not panel then return end

  local width = panel.GetWidth and panel:GetWidth() or RAID_LOOT_WINDOW_WIDTH
  local height = panel.GetHeight and panel:GetHeight() or RAID_LOOT_WINDOW_HEIGHT
  local contentWidth = math.max(RAID_LOOT_WINDOW_WIDTH - 36, width - 36)
  local queueWidth = math.min(contentWidth, RAID_LOOT_QUEUE_MAX_WIDTH)
  -- Grow queues with the window, but always leave room for a full 5-row roster + award controls.
  local minRosterHeight = 168
  local awardChrome = 230
  local bottomControls = 104
  local reservedBelowQueue = awardChrome + minRosterHeight + bottomControls + 18
  local listHeight = math.floor(height * 0.36)
  if listHeight < LOOT_TRACKER_LIST_HEIGHT then listHeight = LOOT_TRACKER_LIST_HEIGHT end
  if listHeight > 400 then listHeight = 400 end
  if listHeight > height - reservedBelowQueue then
    listHeight = math.max(220, height - reservedBelowQueue)
  end

  local toolbarBottom = LayoutLootTrackerToolbar(panel)
  local queueTop = math.min(-112, (toolbarBottom or -100) - 12)
  local queueListTop = queueTop - 20
  local awardTopY = queueListTop - listHeight - 18
  local previewY = awardTopY - 24
  local winnerLabelY = previewY - 68
  local winnerY = previewY - 88
  local summaryY = previewY - 120
  local memberY = previewY - 142
  local typeY = -(height - 104)
  local noteY = -(height - 76)
  local saveY = -(height - 44)
  local memberHeight = math.max(minRosterHeight, math.abs(typeY) - math.abs(memberY) - 16)
  if panel.queueTitle then
    panel.queueTitle:ClearAllPoints()
    panel.queueTitle:SetPoint("TOPLEFT", 18, queueTop)
  end
  if panel.queueList then
    panel.queueList:ClearAllPoints()
    panel.queueList:SetPoint("TOP", panel, "TOP", 0, queueListTop)
    panel.queueList:SetSize(queueWidth, listHeight)
  end
  if panel.awardTitle then
    panel.awardTitle:ClearAllPoints()
    panel.awardTitle:SetPoint("TOPLEFT", 18, awardTopY)
  end
  if panel.selectedDropPreview then
    panel.selectedDropPreview:ClearAllPoints()
    panel.selectedDropPreview:SetPoint("TOPLEFT", 18, previewY)
    panel.selectedDropPreview:SetPoint("TOPRIGHT", -18, previewY)
    panel.selectedDropPreview:SetHeight(58)
  end
  if panel.selectedDrop then
    panel.selectedDrop:ClearAllPoints()
    panel.selectedDrop:SetPoint("TOPLEFT", panel.selectedDropIcon, "TOPRIGHT", 12, -6)
    panel.selectedDrop:SetPoint("RIGHT", panel.selectedDropRollButton, "LEFT", -12, 0)
  end
  if panel.selectedDropPrio then
    panel.selectedDropPrio:ClearAllPoints()
    panel.selectedDropPrio:SetPoint("TOPLEFT", panel.selectedDrop, "BOTTOMLEFT", 0, -2)
    panel.selectedDropPrio:SetPoint("RIGHT", panel.selectedDropRollButton, "LEFT", -12, 0)
  end
  if panel.winnerLabel then
    panel.winnerLabel:ClearAllPoints()
    panel.winnerLabel:SetPoint("TOPLEFT", 18, winnerLabelY)
  end
  if panel.winner then
    panel.winner:ClearAllPoints()
    panel.winner:SetPoint("TOPLEFT", 18, winnerY)
    panel.winner:SetPoint("TOPRIGHT", -18, winnerY)
    panel.winner:SetHeight(26)
  end
  if panel.memberSummary then
    panel.memberSummary:ClearAllPoints()
    panel.memberSummary:SetPoint("TOPLEFT", 18, summaryY)
    panel.memberSummary:SetPoint("TOPRIGHT", -18, summaryY)
  end
  if panel.memberScroll then
    panel.memberScroll:ClearAllPoints()
    panel.memberScroll:SetPoint("TOPLEFT", 18, memberY)
    panel.memberScroll:SetPoint("TOPRIGHT", -18, memberY)
    panel.memberScroll:SetHeight(memberHeight)
  end
  if panel.memberContent then
    panel.memberContent:SetSize(math.max(1, contentWidth - 26), 1)
  end
  if panel.typeLabel then
    panel.typeLabel:ClearAllPoints()
    panel.typeLabel:SetPoint("TOPLEFT", 18, typeY)
  end
  if panel.awardTypeButtons then
    local order = {"MS", "OS", "DE", "GB"}
    local positions = {MS = 0, OS = 60, DE = 120, GB = 180}
    for index, awardType in ipairs(order) do
      local button = panel.awardTypeButtons[awardType]
      if button then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 62 + (positions[awardType] or ((index - 1) * 60)), typeY + 2)
      end
    end
  end
  if panel.noteLabel then
    panel.noteLabel:ClearAllPoints()
    panel.noteLabel:SetPoint("TOPLEFT", 18, noteY - 2)
  end
  if panel.note then
    panel.note:ClearAllPoints()
    panel.note:SetPoint("TOPLEFT", 62, noteY)
    panel.note:SetPoint("TOPRIGHT", -108, noteY)
    panel.note:SetHeight(22)
  end
  if panel.award then
    panel.award:ClearAllPoints()
    panel.award:SetPoint("TOPLEFT", 18, saveY)
  end
  if panel.status then
    panel.status:ClearAllPoints()
    panel.status:SetPoint("LEFT", panel.award, "RIGHT", 8, 0)
    panel.status:SetPoint("RIGHT", -18, 0)
  end
  if panel.setRunnerToML and panel.setRunnerToML:IsShown() then
    panel.setRunnerToML:ClearAllPoints()
    panel.setRunnerToML:SetPoint("TOPRIGHT", -18, -52)
  end
  if panel.trackerRunner then
    panel.trackerRunner:ClearAllPoints()
    panel.trackerRunner:SetPoint("TOPRIGHT", -18, -34)
    panel.trackerRunner:SetJustifyH("RIGHT")
    if panel.trackerRunner.SetWordWrap then panel.trackerRunner:SetWordWrap(false) end
  end
end

function APOCLootPrio:RefreshAuditLog()
  if not self.frame or not self.frame.logPanel or not self.frame.logPanel.log then return end
  self:InitDB()

  local lines = {}
  for index = 1, math.min(12, #APOCLootPrioDB.audit) do
    table.insert(lines, self:DescribeAuditEntry(APOCLootPrioDB.audit[index], true))
  end

  if #lines == 0 then
    self.frame.logPanel.log:SetText("No admin saves logged yet.")
  else
    self.frame.logPanel.log:SetText(table.concat(lines, "\n"))
  end
end

function APOCLootPrio:UpdateRaidLootStatus(text)
  if self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.status then
    self.frame.raidLootPanel.status:SetText(text or "")
  end
end

function APOCLootPrio:RefreshGroupMemberList()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.memberContent then return end

  local panel = self.frame.raidLootPanel
  local content = panel.memberContent
  local canEdit = self:CanEditLootTracker()
  local canView = self:CanViewLootTracker()
  ClearFrameChildren(content)
  if not canView then
    if panel.winnerPlaceholder then panel.winnerPlaceholder:Hide() end
    if panel.memberSummary then panel.memberSummary:SetText("") end
    content:SetHeight(1)
    return
  end

  local search = TrimText(panel.winner and panel.winner:GetText() or "")
  local searchKey = string.lower(search)
  if panel.winnerPlaceholder then
    if search == "" then panel.winnerPlaceholder:Show() else panel.winnerPlaceholder:Hide() end
  end

  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local session = self:GetRaidLootSession(trackerRaid)
  local groups, total = self:GetLootSessionGroupedRoster(session)
  local mainSpecCounts = {}
  for _, drop in ipairs((session and session.drops) or {}) do
    if drop.award and drop.award.winner and self:GetAwardType(drop) == "MS" then
      local key = RosterNameKey(drop.award.winner)
      mainSpecCounts[key] = (mainSpecCounts[key] or 0) + 1
    end
  end

  local currentWinnerKey = RosterNameKey(panel.selectedWinnerName)
  -- Stack raid groups in rows so the winner picker stays compact on screen:
  -- Groups 1-3 on the first row, Groups 4-6 on the second row, etc.
  local columns = 3
  local gap = 8
  local rosterWidth = panel.memberScroll and panel.memberScroll.GetWidth and panel.memberScroll:GetWidth() or (RAID_LOOT_WINDOW_WIDTH - 36)
  local columnWidth = math.floor((math.max(1, rosterWidth - 26) - ((columns - 1) * gap)) / columns)
  local shown = 0
  local tallestRows = 1
  local groupBlockHeight = 32 + (5 * (GROUP_MEMBER_BUTTON_HEIGHT + 4))
  local groupCount = math.max(5, #groups)
  local groupRows = math.max(1, math.ceil(groupCount / columns))

  for groupIndex = 1, groupCount do
    local gridColumn = (groupIndex - 1) % columns
    local gridRow = math.floor((groupIndex - 1) / columns)

    local columnFrame = CreateFrame("Frame", nil, content)
    columnFrame:SetPoint("TOPLEFT", gridColumn * (columnWidth + gap), -(gridRow * groupBlockHeight))
    columnFrame:SetSize(columnWidth, groupBlockHeight)

    local heading = Font(columnFrame, 10, "Group " .. tostring(groupIndex), "GameFontHighlight")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetSize(columnWidth, 16)
    heading:SetJustifyH("CENTER")
    heading:SetTextColor(1, .85, .2)

    local underline = columnFrame:CreateTexture(nil, "BACKGROUND")
    underline:SetPoint("TOPLEFT", 0, -18)
    underline:SetSize(columnWidth, 1)
    SetTextureColor(underline, .45, .30, .10, .85)

    local row = 0
    for _, memberName in ipairs(groups[groupIndex] or {}) do
      local displayName = ShortDisplayName(memberName)
      local matchesSearch = searchKey == "" or string.find(string.lower(displayName or ""), searchKey, 1, true)
      if matchesSearch then
        shown = shown + 1
        row = row + 1
        tallestRows = math.max(tallestRows, row)

        local button = CreateFrame("Button", nil, columnFrame, "UIPanelButtonTemplate")
        button:SetSize(columnWidth, GROUP_MEMBER_BUTTON_HEIGHT)
        button:SetPoint("TOPLEFT", 0, -24 - ((row - 1) * (GROUP_MEMBER_BUTTON_HEIGHT + 4)))
        local count = mainSpecCounts[RosterNameKey(memberName)] or 0
        local role = self:GetGroupMemberRole(memberName)
        button:RegisterForClicks("LeftButtonUp")
        button:SetText(ColorizeGroupMemberName(memberName, displayName or memberName))
        button.memberName = memberName
        AddGroupMemberRoleBadge(button, role)
        local buttonText = button:GetFontString()
        if buttonText then
          buttonText:ClearAllPoints()
          buttonText:SetPoint("LEFT", 26, 0)
          buttonText:SetPoint("RIGHT", count > 0 and -28 or -8, 0)
          buttonText:SetJustifyH("CENTER")
        end
        button:SetScript("OnClick", function(selfButton)
          if not APOCLootPrio:CanEditLootTracker() then return end
          panel.selectedWinnerName = selfButton.memberName or ""
          APOCLootPrio:RefreshGroupMemberList()
        end)
        SetControlEnabled(button, true)
        if not canEdit and button.Disable then
          -- Keep readable for viewers; selection clicks stay blocked in OnClick.
        end

        if button.UnlockHighlight then button:UnlockHighlight() end
        SetAPOCButtonSelected(button, currentWinnerKey ~= "" and currentWinnerKey == RosterNameKey(memberName))

        if count > 0 then
          local badge = button:CreateTexture(nil, "OVERLAY")
          badge:SetSize(17, 17)
          badge:SetPoint("RIGHT", -7, 0)
          SetTextureColor(badge, .45, .03, .03, .92)

          local countText = Font(button, 9, tostring(count), "GameFontHighlight")
          countText:SetPoint("CENTER", badge, "CENTER", 0, 0)
          countText:SetTextColor(1, .85, .2)
        end
      end
    end
  end

  if panel.memberSummary then
    panel.memberSummary:SetText(tostring(shown) .. " shown of " .. tostring(total) .. " raid members")
  end

  content:SetHeight(groupRows * groupBlockHeight)
  if panel.memberScroll and panel.memberScroll.UpdateScrollChildRect then
    panel.memberScroll:UpdateScrollChildRect()
  end
end

function APOCLootPrio:RefreshLootTrackerSettingsPanel()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.trackerSettingsPanel then return end

  local panel = self.frame.raidLootPanel.trackerSettingsPanel
  if panel.accessRank then
    panel.accessRank:SetText(self:FormatFeatureAccessRank("lootTracker"))
  end

  if panel.viewOnlyRank then
    panel.viewOnlyRank:SetText(self:FormatFeatureAccessRank("lootTrackerView"))
  end

  if panel.sessionDeleteRank then
    panel.sessionDeleteRank:SetText(self:FormatFeatureAccessRank("lootSessionDelete"))
  end

  if panel.runnerValue then
    local trackerOwner = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or self:GetLootTrackerOwner()
    local runSuffix = self.GetRunShortID and (" | Run " .. self:GetRunShortID()) or ""
    local health = self.GetMultiRunRunnerHealth and self:GetMultiRunRunnerHealth() or "active"
    local healthSuffix = health == "offline" and " | |cffff4040OFFLINE|r"
      or health == "missing" and " | |cffff4040NO RUNNER|r"
      or health == "waiting" and " | |cffffd100Connecting|r"
      or " | |cff40ff40Active|r"
    local suffix = self.IsMasterLooter and self:IsMasterLooter() and " (you)" or ""
    panel.runnerValue:SetText("Master Looter: " .. (trackerOwner and (ShortDisplayName(trackerOwner) or trackerOwner) or "Not detected") .. suffix .. healthSuffix .. runSuffix)
  end
  -- Runner assignment has been removed. Keep old frame fields hidden so saved
  -- layouts and older UI calls remain harmless.
  SetControlShown(panel.setRunner, false)
  SetControlShown(panel.runnerMe, false)
  SetControlShown(panel.runnerAuto, false)
  SetControlShown(panel.runnerSetML, false)
  if panel.status then
    panel.status:SetText("Master Looter controls live loot; officers can manage saved history.")
  end

  if panel.disenchanterValue then
    local disenchanter = self:GetLootDisenchanter()
    if disenchanter and disenchanter ~= "" then
      local suffix = self:IsLootDisenchanterInGroup(disenchanter) and "" or " (not in group)"
      panel.disenchanterValue:SetText((ShortDisplayName(disenchanter) or disenchanter) .. suffix)
    else
      panel.disenchanterValue:SetText("Not assigned")
    end
  end
  SetControlEnabled(panel.setDisenchanter, self:CanEditLootTracker())
  SetControlEnabled(panel.clearDisenchanter, self:CanEditLootTracker() and self:GetLootDisenchanter() ~= nil)

  if panel.autoTrackButtons then
    local selectedMode = self.GetLootAutoTrackMode and self:GetLootAutoTrackMode() or "raid"
    for mode, button in pairs(panel.autoTrackButtons) do
      SetAPOCButtonSelected(button, mode == selectedMode)
    end
  end


  if panel.qualityButtons then
    for quality, button in pairs(panel.qualityButtons) do
      SetAPOCButtonSelected(button, self:IsLootQualityTracked(quality))
    end
  end

  if panel.syncedClients then
    SetControlEnabled(panel.syncedClients, self:CanViewLootTracker())
    panel.syncedClients:SetText(self.syncedClientsPanelShown and "Synced: On" or "Synced")
  end
  if panel.fullSync then
    SetControlEnabled(panel.fullSync, self:CanViewLootTracker())
  end
  if panel.rollDuration then
    -- Status refreshes must not overwrite a value while the user is typing it.
    if not panel.rollDurationDirty then panel.rollDuration:SetText(tostring(self:GetLootRollDuration())) end
    local canChangeTimer = self:CanManageSettings()
    SetControlEnabled(panel.rollDuration, canChangeTimer)
    SetControlEnabled(panel.rollDurationSave, canChangeTimer)
    SetControlEnabled(panel.rollDurationDefault, canChangeTimer)
  end
end

function APOCLootPrio:SetLiveRaidsPanelShown(enabled)
  if enabled and not self:CanViewLootTracker() then
    self.liveRaidsPanelShown = false
    self:Print("Live Raids are shown from the Loot Tracker.")
    return
  end
  self.liveRaidsPanelShown = enabled and true or false
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.liveRaidsPanel then return end
  local panel = self.frame.raidLootPanel.liveRaidsPanel
  if self.liveRaidsPanelShown then
    panel:Show()
    if self.PublishLocalLiveRaid then self:PublishLocalLiveRaid("panel-open") end
    if self.AnnounceLocalLiveRaid then self:AnnounceLocalLiveRaid("panel-open") end
    self:RefreshLiveRaidsPanel()
  else
    panel:Hide()
  end
end

function APOCLootPrio:ToggleLiveRaidsPanel()
  self:SetLiveRaidsPanelShown(not self.liveRaidsPanelShown)
end

function APOCLootPrio:RefreshLiveRaidsPanel()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.liveRaidsPanel then return end
  local panel = self.frame.raidLootPanel.liveRaidsPanel
  if not self.liveRaidsPanelShown and not panel:IsShown() then return end

  for _, child in ipairs({panel.content:GetChildren()}) do
    child:Hide()
    child:SetParent(nil)
  end

  local raids = self.GetKnownLiveRaids and self:GetKnownLiveRaids() or {}
  if #raids == 0 and self.GetActiveRunID and self:GetActiveRunID() then
    local runID = self:GetActiveRunID()
    local runner = (self.GetLootTrackerOwner and self:GetLootTrackerOwner()) or (self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName()) or "runner"
    table.insert(raids, {
      id = runID,
      name = "Live raid [" .. tostring(self.GetRunShortID and self:GetRunShortID(runID) or runID) .. "]",
      runner = runner,
      isLocal = true,
      isSelected = true,
      online = true,
    })
  end
  local y = -2
  local selectedID = self.GetSelectedLiveRaidID and self:GetSelectedLiveRaidID() or nil
  self.selectedLiveRaidListID = self.selectedLiveRaidListID or selectedID

  if #raids == 0 then
    if panel.scroll then panel.scroll:Show() end
    local inGroup = false
    if IsInRaid and IsInRaid() then inGroup = true end
    if not inGroup and GetNumRaidMembers and GetNumRaidMembers() > 0 then inGroup = true end
    if not inGroup and GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then inGroup = true end
    if not inGroup and GetNumPartyMembers and GetNumPartyMembers() > 0 then inGroup = true end
    if not inGroup and GetNumGroupMembers and GetNumGroupMembers() > 1 then inGroup = true end
    local log = self.InitLiveRaid and self:InitLiveRaid().lastLiveLog or nil
    local emptyText = log or (inGroup
      and "In a group, but no Live Raid yet. If you are master looter, click Refresh."
      or "No live raids heard yet. Click Refresh (the master looter must have the tracker open).")
    local empty = Font(panel.content, 11, emptyText, "GameFontNormal")
    empty:SetPoint("TOPLEFT", 8, y)
    empty:SetPoint("TOPRIGHT", -8, y)
    empty:SetJustifyH("LEFT")
    empty:SetTextColor(.72, .72, .72)
    if empty.SetWordWrap then empty:SetWordWrap(true) end
    y = y - (inGroup and 40 or 28)
  end

  if #raids == 1 and not self.selectedLiveRaidListID then
    self.selectedLiveRaidListID = raids[1].id
    if self.InitLiveRaid then
      self:InitLiveRaid().selectedLiveRaidID = raids[1].id
    end
  end

  if panel.livePick and panel.livePick.SetParent then
    panel.livePick:Hide()
    panel.livePick:SetParent(nil)
    panel.livePick = nil
  end

  for _, raid in ipairs(raids) do
    if panel.scroll then panel.scroll:Hide() end
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(420, 44)
    row:SetPoint("TOPLEFT", 16, -96)
    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("AnyUp", "LeftButtonUp") end
    row:SetFrameStrata(panel:GetFrameStrata() or "HIGH")
    row:SetFrameLevel((panel:GetFrameLevel() or 1) + 50)
    row:Show()
    panel.livePick = row
    APOCLootPrio.liveRaidPickID = raid.id

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    local selected = (self.selectedLiveRaidListID == raid.id) or raid.isSelected
    if selected then
      SetTextureColor(bg, .28, .24, .12, .92)
    else
      SetAPOCRowTexture(bg, .55)
    end

    local title = Font(row, 11, tostring(raid.name or "Live Raid"), "GameFontHighlight")
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetPoint("TOPRIGHT", -8, -4)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, .85, .2)

    local runner = ShortDisplayName(raid.runner) or raid.runner or "none"
    local health = raid.online and "|cff40ff40online|r" or "|cffff4040offline|r"
    local localTag = raid.isLocal and " |cff40ff40(yours)|r" or ""
    local watchTag = (self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() and selectedID == raid.id) and " |cffbbbbbbwatching|r" or ""
    local detail = Font(row, 9, "Runner: " .. tostring(runner) .. " · " .. health .. localTag .. watchTag, "GameFontNormalSmall")
    detail:SetPoint("TOPLEFT", 8, -18)
    detail:SetPoint("TOPRIGHT", -8, -18)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(.9, .84, .72)

    local raidID = raid.id
    local function pick()
      APOCLootPrio.selectedLiveRaidListID = raidID
      if APOCLootPrio.InitLiveRaid then
        APOCLootPrio:InitLiveRaid().selectedLiveRaidID = raidID
      end
      if panel.status then panel.status:SetText("Selected " .. tostring(raidID)) end
      if APOCLootPrio.SelectLiveRaid then APOCLootPrio:SelectLiveRaid(raidID) end
      APOCLootPrio:RefreshLiveRaidsPanel()
    end
    row:SetScript("OnClick", pick)
    row:SetScript("OnMouseUp", function(_, button)
      if button == "LeftButton" then pick() end
    end)

    y = y - 40
  end

  panel.content:SetHeight(math.max(1, -y + 4))
  if panel.scroll and panel.scroll.UpdateScrollChildRect then
    panel.scroll:UpdateScrollChildRect()
  end

  local watchOnly = self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly()
  local picked = self.selectedLiveRaidListID or self.liveRaidPickID or selectedID
  if #raids == 1 and (not picked or picked == "") then
    picked = raids[1].id
    self.selectedLiveRaidListID = picked
    if self.InitLiveRaid then self:InitLiveRaid().selectedLiveRaidID = picked end
  end
  local sel = picked and (self.GetRunShortID and self:GetRunShortID(picked) or picked) or "none"
  local log = self.InitLiveRaid and self:InitLiveRaid().lastLiveLog or nil
  panel.status:SetText(tostring(#raids) .. " live raid(s) · selected " .. tostring(sel) .. (watchOnly and " · view-only watch" or "") .. (log and (" · " .. log) or ""))
end

function APOCLootPrio:SetSyncedClientsPanelShown(enabled)
  if enabled and not self:CanViewLootTracker() then
    self.syncedClientsPanelShown = false
    self:Print("Synced clients are shown from the Loot Tracker.")
    return
  end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.syncedClientsPanel then return end

  local panel = self.frame.raidLootPanel.syncedClientsPanel
  self.syncedClientsPanelShown = enabled and true or false

  if self.syncedClientsPanelShown then
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 18)
    panel:Show()
    self:RefreshSyncedClientsPanel()
  else
    panel:Hide()
  end

  if self.frame.raidLootPanel.syncedClients then
    self.frame.raidLootPanel.syncedClients:SetText(self.syncedClientsPanelShown and "Synced: On" or "Synced")
  end
  if self.frame.raidLootPanel.trackerSettingsPanel and self.frame.raidLootPanel.trackerSettingsPanel.syncedClients then
    self.frame.raidLootPanel.trackerSettingsPanel.syncedClients:SetText(self.syncedClientsPanelShown and "Synced: On" or "Synced")
  end
end

function APOCLootPrio:ToggleSyncedClientsPanel()
  self:SetSyncedClientsPanelShown(not self.syncedClientsPanelShown)
end

function APOCLootPrio:ClearOldSyncedClients()
  local removed = self.PruneOldSyncPeers and self:PruneOldSyncPeers() or {}
  if #removed == 0 then
    self:Print("No old or stale synced clients to remove.")
  else
    self:Print("Removed " .. tostring(#removed) .. " old synced client(s): " .. table.concat(removed, ", ") .. ".")
  end
  self:RefreshSyncedClientsPanel()
end

function APOCLootPrio:RefreshSyncedClients(sendRequest)
  if sendRequest and self.RequestSync then
    self:RequestSync()
    self:UpdateRaidLootStatus("Sync request sent. Waiting for addon replies.")
  end
  self:RefreshSyncedClientsPanel()
end

function APOCLootPrio:RequestFullLootSyncFromPanel()
  if not self:CanViewLootTracker() then return end
  if self.RequestLootSessionSync then
    self:RequestLootSessionSync()
    self:UpdateRaidLootStatus("Hardened Sync V3 request sent to the active runner.")
  else
    self:UpdateRaidLootStatus("Hardened Loot Sync is not loaded.")
  end
end

function APOCLootPrio:RefreshSyncedClientsPanel()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.syncedClientsPanel then return end

  local panel = self.frame.raidLootPanel.syncedClientsPanel
  local content = panel.content
  if not content then return end

  ClearFrameChildren(content)

  local clients = self:GetSyncedClients()
  local y = 0

  for _, client in ipairs(clients or {}) do
    local title = ColorizeGroupMemberName(client.name, ShortDisplayName(client.name) or client.name)
    if client.isLocal then title = title .. " |cffbbbbbb(You)|r" end

    local versionText = "Version " .. ((client.addonVersion and client.addonVersion ~= "") and client.addonVersion or "unknown")
    local protocolText = "Sync V" .. tostring(client.syncProtocol or (client.isLocal and 3 or "unknown"))
    local detail = client.isLocal and (versionText .. " - " .. protocolText .. " - Local client")
      or (versionText .. " - " .. protocolText .. " - Last heard " .. self:FormatLootTime(client.lastSeen) .. (client.messageKind and client.messageKind ~= "" and (" - " .. client.messageKind) or ""))
    if client.rankIndex ~= nil then
      detail = detail .. " - Rank " .. tostring(client.rankIndex)
      if client.rankName and client.rankName ~= "" then detail = detail .. " " .. client.rankName end
    end
    local syncState = APOCLootPrioDB and APOCLootPrioDB.sync and APOCLootPrioDB.sync.peerStates and APOCLootPrioDB.sync.peerStates[ShortDisplayName(client.name) or client.name]
    if syncState and syncState.lootVerified ~= nil then
      if syncState.lootVerified then
        detail = detail .. " - |cff55ff55Loot verified|r"
      elseif not client.isLocal and self.IsCurrentGroupMember and not self:IsCurrentGroupMember(client.name) then
        detail = detail .. " - |cffbbbbbbDifferent loot state|r"
      else
        detail = detail .. " - |cffff5555Loot mismatch|r"
      end
    end

    CreateManualPickerTextRow(content, y, title, detail, function() end)
    y = y - 38
  end

  if #clients == 0 then
    CreateManualPickerTextRow(content, y, "No synced clients seen yet.", "Click Refresh to request sync replies.", function() end)
    y = y - 38
  end

  content:SetHeight(math.max(1, -y + 4))
  if panel.scroll and panel.scroll.UpdateScrollChildRect then
    panel.scroll:UpdateScrollChildRect()
  end

  if panel.status then
    local remoteCount = math.max(0, #clients - 1)
    panel.status:SetText(tostring(remoteCount) .. " remote synced client" .. (remoteCount == 1 and "" or "s") .. " heard")
  end
end

function APOCLootPrio:SetLootRollResultsPanelShown(enabled)
  if enabled and not self:CanViewLootTracker() then
    self.lootRollResultsPanelShown = false
    self:UpdateRaidLootStatus("Loot details are not available for your guild rank.")
    return
  end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.lootRollResultsPanel then return end

  local panel = self.frame.raidLootPanel.lootRollResultsPanel
  self.lootRollResultsPanelShown = enabled and true or false

  if self.lootRollResultsPanelShown then
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 19)
    panel:Show()
    self:RefreshLootRollResultsPanel()
  else
    if panel.awardPrompt then
      panel.awardPrompt:Hide()
    end
    if panel.resetPrompt then
      panel.resetPrompt:Hide()
    end
    self.pendingRollAwardDropID = nil
    self.pendingRollAwardSourceDropID = nil
    self.pendingRollAwardWinner = nil
    self.pendingRollAwardRollType = nil
    self.pendingRollResetDropID = nil
    self.pendingRollResetRaid = nil
    panel:Hide()
  end

  local button = self.frame.raidLootPanel.selectedDropRollResultsButton
  if button then
    button:SetText(self.lootRollResultsPanelShown and "Results: On" or "Results")
    RefreshSelectedDropRollDisplay(self.frame.raidLootPanel, self:FindRaidLootDrop(self.selectedLootDropID, self.selectedLootTrackerRaid or self.selectedRaid))
  end
end

function APOCLootPrio:ToggleLootRollResultsPanel()
  self:SetLootRollResultsPanelShown(not self.lootRollResultsPanelShown)
end

function APOCLootPrio:RefreshLootRollResultsPanel()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.lootRollResultsPanel then return end

  local panel = self.frame.raidLootPanel.lootRollResultsPanel
  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local drop = self:FindRaidLootDrop(self.selectedLootDropID, trackerRaid)
  local content = panel.content
  if content then ClearFrameChildren(content) end

  if drop then
    panel.item:SetText(tostring(drop.item or "Unknown item") .. " - " .. tostring(drop.boss or "Unknown drop"))
    panel.item:SetTextColor(GetItemQualityRGB(DropAsItem(drop)))
    if panel.itemPrio then
      panel.itemPrio:SetText("Loot prio: " .. ColorizePriorityText(drop.bias or "None"))
    end
    if panel.icon and panel.iconTexture then
      panel.icon.drop = drop
      SetCleanItemIcon(panel.iconTexture, DropAsItem(drop))
      panel.icon:Show()
    end

    local roll = drop.roll
    local left = self:GetLootRollTimeLeft(drop)
    local y = 0

    if roll and roll.startedAt then
      local winningEntries = self:GetLootRollWinningEntries(drop)
      local winningEntry = winningEntries[1]
      local copyCount = self:GetLootRollCopyCount(drop)
      y = y - CreateLootRollResultText(content, y, (left and left > 0) and (tostring(left) .. " seconds left") or "Closed", .9, .84, .72)
      if copyCount > 1 then
        y = y - CreateLootRollResultText(content, y, tostring(copyCount) .. " identical copies - top " .. tostring(copyCount) .. " eligible rolls win one copy each.", 1, .85, .2)
      end
      if winningEntry then
        local displayName = ShortDisplayName(winningEntry.name) or winningEntry.name or "?"
        local typeLabel = winningEntry.rollType == "GREED" and "OS winner" or "MS winner"
        if left and left > 0 then typeLabel = winningEntry.rollType == "GREED" and "OS lead" or "MS lead" end
        y = y - CreateLootRollResultText(content, y, typeLabel .. ": " .. ColorizeGroupMemberName(winningEntry.name, displayName) .. " - " .. tostring(winningEntry.roll or 0), 1, .85, .2)
      else
        y = y - CreateLootRollResultText(content, y, "Waiting for rolls.", 1, .85, .2)
      end

      local function addSection(label, entries)
        y = y - 8
        y = y - CreateLootRollSectionHeader(content, y, label)
        if #entries == 0 then
          y = y - CreateLootRollResultText(content, y, "  none", .72, .72, .72)
        else
          for index, entry in ipairs(entries) do
            y = y - CreateLootRollResultPlayerRow(content, y, drop, entry, index)
          end
        end
      end

      local resultLimit = math.max(5, copyCount)
      local needEntries = self:GetLootRollTopEntries(drop, resultLimit, "NEED")
      local greedEntries = self:GetLootRollTopEntries(drop, resultLimit, "GREED")
      addSection("MS /roll 1-100", needEntries)
      addSection("OS /roll 1-99", greedEntries)

      if #needEntries == 0 and #greedEntries > 0 then
        y = y - 8
        y = y - CreateLootRollResultText(content, y, "No MS rolls yet. OS is currently eligible.", .72, .72, .72)
      elseif #needEntries == 0 and #greedEntries == 0 and (not left or left <= 0) and self:GetNextLootRollAwardDrop(drop) then
        y = y - 8
        y = y - CreateLootRollSectionHeader(content, y, "No rolls - Disenchant")
        local disenchanter = self:GetLootDisenchanter()
        if disenchanter and disenchanter ~= "" and self:IsLootDisenchanterInGroup(disenchanter) then
          y = y - CreateLootRollDisenchanterRow(content, y, drop, disenchanter)
        elseif disenchanter and disenchanter ~= "" then
          y = y - CreateLootRollResultText(content, y, "Assigned disenchanter " .. tostring(ShortDisplayName(disenchanter) or disenchanter) .. " is not in the group.", 1, .45, .25)
        else
          y = y - CreateLootRollResultText(content, y, "Assign a disenchanter in Loot Tracker Settings.", .72, .72, .72)
        end
      end
    else
      y = y - CreateLootRollResultText(content, y, "No roll has been started for this item.", .9, .84, .72)
    end
  else
    panel.item:SetText("Select a loot drop.")
    panel.item:SetTextColor(.9, .84, .72)
    if panel.itemPrio then
      panel.itemPrio:SetText("")
    end
    if panel.icon then
      panel.icon.drop = nil
      panel.icon:Hide()
    end
    if content then
      CreateLootRollResultText(content, 0, "No selected loot drop.", .9, .84, .72)
    end
  end

  local canEdit = self:CanEditLootTracker()
  if panel.status then
    panel.status:SetText(canEdit
      and "One MS and one OS roll per player. MS ranks before OS. Click each winning row to award."
      or "Live roll results. MS ranks before OS.")
  end
  if panel.resetRolls then
    SetControlEnabled(panel.resetRolls, drop ~= nil and canEdit)
    SetControlShown(panel.resetRolls, canEdit)
  end
  if panel.resetTimer then
    SetControlEnabled(panel.resetTimer, drop ~= nil and drop.roll ~= nil and canEdit)
    SetControlShown(panel.resetTimer, canEdit)
  end
end

function APOCLootPrio:SetLootRollResetPromptShown(enabled)
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.lootRollResultsPanel then return end
  local panel = self.frame.raidLootPanel.lootRollResultsPanel
  local prompt = panel.resetPrompt
  if not prompt then return end

  if enabled then
    if not self:CanEditLootTracker() then
      self:UpdateRaidLootStatus("Only Loot Tracker editors can reset rolls.")
      prompt:Hide()
      return
    end
    local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
    local drop = self:FindRaidLootDrop(self.selectedLootDropID, trackerRaid)
    if not drop then
      self:UpdateRaidLootStatus("Select a loot drop first.")
      prompt:Hide()
      return
    end
    if not drop.roll or not drop.roll.startedAt then
      self:UpdateRaidLootStatus("No roll has been started for that item.")
      prompt:Hide()
      return
    end

    self.pendingRollResetDropID = drop.id
    self.pendingRollResetRaid = trackerRaid
    if panel.awardPrompt then panel.awardPrompt:Hide() end
    prompt.message:SetText("Reset all rolls for " .. tostring(drop.item or "this item") .. "?\nThis cannot be undone.")
    local anchor = (panel.IsShown and panel:IsShown()) and panel or self.frame.raidLootPanel
    prompt:ClearAllPoints()
    prompt:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    if prompt.SetFrameStrata then prompt:SetFrameStrata("TOOLTIP") end
    if prompt.SetFrameLevel then prompt:SetFrameLevel(ADDON_FRAME_LEVEL + 81) end
    if prompt.SetToplevel then prompt:SetToplevel(true) end
    prompt:Show()
    if prompt.Raise then prompt:Raise() end
  else
    self.pendingRollResetDropID = nil
    self.pendingRollResetRaid = nil
    prompt:Hide()
  end
end

function APOCLootPrio:ConfirmSelectedRaidLootRollReset()
  local dropID = self.pendingRollResetDropID
  local trackerRaid = self.pendingRollResetRaid or self.selectedLootTrackerRaid or self.selectedRaid
  if not dropID then
    self:UpdateRaidLootStatus("Choose a roll to reset first.")
    self:SetLootRollResetPromptShown(false)
    return
  end

  local ok, message = self:ResetRaidLootRoll(dropID, trackerRaid)
  self:UpdateRaidLootStatus(message or (ok and "Rolls reset." or "Could not reset rolls."))
  self:SetLootRollResetPromptShown(false)
  if self.frame and self.frame.raidLootPanel then
    local drop = self:FindRaidLootDrop(self.selectedLootDropID, self.selectedLootTrackerRaid or self.selectedRaid)
    RefreshSelectedDropRollDisplay(self.frame.raidLootPanel, drop)
  end
  if self.lootRollResultsPanelShown then
    self:RefreshLootRollResultsPanel()
  end
end

function APOCLootPrio:SetLootRollAwardPromptShown(enabled, dropID, playerName, rollType)
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.lootRollResultsPanel then return end
  local panel = self.frame.raidLootPanel.lootRollResultsPanel
  local prompt = panel.awardPrompt
  if not prompt then return end

  if enabled then
    if not self:CanEditLootTracker() then
      self:UpdateRaidLootStatus("Only Loot Tracker editors can award roll winners.")
      prompt:Hide()
      return
    end
    local sourceDrop = self:FindRaidLootDrop(dropID)
    if not sourceDrop then
      self:UpdateRaidLootStatus("Could not find that loot drop.")
      prompt:Hide()
      return
    end
    local left = self:GetLootRollTimeLeft(sourceDrop)
    if left and left > 0 then
      self:UpdateRaidLootStatus("Wait for the roll to close before awarding winners.")
      prompt:Hide()
      return
    end
    playerName = ShortDisplayName(playerName) or playerName
    if not playerName or playerName == "" then
      self:UpdateRaidLootStatus("Could not find that roller.")
      prompt:Hide()
      return
    end

    rollType = rollType == "GREED" and "GREED" or (rollType == "DE" and "DE" or "NEED")
    local winnerSlot = nil
    if rollType == "DE" then
      if #self:GetLootRollWinningEntries(sourceDrop) > 0 then
        self:UpdateRaidLootStatus("A valid MS or OS roll exists, so the assigned disenchanter cannot be used.")
        prompt:Hide()
        return
      end
      local assignedDE = self:GetLootDisenchanter()
      if RosterNameKey(assignedDE) == "" or RosterNameKey(assignedDE) ~= RosterNameKey(playerName) or not self:IsLootDisenchanterInGroup(assignedDE) then
        self:UpdateRaidLootStatus("The assigned disenchanter is not currently available.")
        prompt:Hide()
        return
      end
    else
      winnerSlot = self:GetLootRollWinnerSlot(sourceDrop, playerName, rollType)
      if not winnerSlot then
        self:UpdateRaidLootStatus(tostring(playerName) .. " is not in a winning place for this roll.")
        prompt:Hide()
        return
      end
      if self:GetLootRollAwardedCopy(sourceDrop, playerName, rollType) then
        self:UpdateRaidLootStatus(tostring(playerName) .. " has already been awarded a copy for that " .. (rollType == "GREED" and "OS" or "MS") .. " roll.")
        prompt:Hide()
        return
      end
    end
    local awardDrop = self:GetNextLootRollAwardDrop(sourceDrop)
    if not awardDrop then
      self:UpdateRaidLootStatus("All copies from this roll have already been awarded.")
      prompt:Hide()
      return
    end

    self.pendingRollAwardSourceDropID = dropID
    self.pendingRollAwardDropID = awardDrop.id
    self.pendingRollAwardWinner = playerName
    self.pendingRollAwardRollType = rollType
    if rollType == "DE" then
      prompt.message:SetText("No valid rolls. Award the next copy to " .. ColorizeGroupMemberName(playerName, playerName) .. " for disenchant?")
      prompt.ms:Hide()
      prompt.os:Hide()
      prompt.de:ClearAllPoints()
      prompt.de:SetPoint("TOPLEFT", 82, -78)
      prompt.cancel:ClearAllPoints()
      prompt.cancel:SetPoint("TOPLEFT", 164, -78)
    else
      prompt.message:SetText("Award copy " .. tostring(winnerSlot) .. " of " .. tostring(self:GetLootRollCopyCount(sourceDrop)) .. " to " .. ColorizeGroupMemberName(playerName, playerName) .. " for their " .. (rollType == "GREED" and "OS" or "MS") .. " roll?\nChoose MS, OS, or DE.")
      prompt.ms:Show()
      prompt.os:Show()
      prompt.de:ClearAllPoints()
      prompt.de:SetPoint("TOPLEFT", 148, -78)
      prompt.cancel:ClearAllPoints()
      prompt.cancel:SetPoint("TOPLEFT", 214, -78)
    end
    prompt.de:Show()
    prompt.cancel:Show()
    if panel.resetPrompt then panel.resetPrompt:Hide() end
    local anchor = (panel.IsShown and panel:IsShown()) and panel or self.frame.raidLootPanel
    prompt:ClearAllPoints()
    prompt:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    if prompt.SetFrameStrata then prompt:SetFrameStrata("TOOLTIP") end
    if prompt.SetFrameLevel then prompt:SetFrameLevel(ADDON_FRAME_LEVEL + 80) end
    if prompt.SetToplevel then prompt:SetToplevel(true) end
    prompt:Show()
    if prompt.Raise then prompt:Raise() end
  else
    self.pendingRollAwardDropID = nil
    self.pendingRollAwardSourceDropID = nil
    self.pendingRollAwardWinner = nil
    self.pendingRollAwardRollType = nil
    prompt:Hide()
  end
end

function APOCLootPrio:AnnounceRollAward(drop, winner, awardType)
  if not drop or not winner or winner == "" then return end

  local link = self:GetLootRollChatLink(drop)
  local chatType = self:GetLootRollChatType()
  local awardLabel = AwardTypeShort(awardType)
  local lootMaster = self:GetLootMasterDisplayName()
  local tradeText = lootMaster and lootMaster ~= "" and ("Loot Master " .. tostring(lootMaster)) or "the Loot Master"
  if awardLabel == "DE" then
    self:SendLootRollMessage(tostring(link) .. " awarded to " .. tostring(ShortDisplayName(winner) or winner) .. " for disenchant. Please open trade with " .. tradeText .. ".", chatType)
  else
    self:SendLootRollMessage(tostring(ShortDisplayName(winner) or winner) .. " won " .. tostring(link) .. " (" .. tostring(awardLabel) .. "). Please open trade with " .. tradeText .. ".", chatType)
  end
end

function APOCLootPrio:AwardRollResultWinner(awardType)
  if not self:RequireLootTrackerEdit() then return end

  local dropID = self.pendingRollAwardDropID
  local sourceDropID = self.pendingRollAwardSourceDropID
  local winner = self.pendingRollAwardWinner
  local rollType = self.pendingRollAwardRollType == "GREED" and "GREED" or (self.pendingRollAwardRollType == "DE" and "DE" or "NEED")
  if not dropID or not winner or winner == "" then
    self:UpdateRaidLootStatus("Choose a roll winner first.")
    return
  end

  local sourceDrop = self:FindRaidLootDrop(sourceDropID or dropID)
  local currentDrop = self:FindRaidLootDrop(dropID)
  if not currentDrop then
    self:UpdateRaidLootStatus("Could not find that loot drop.")
    return
  end
  if not sourceDrop then
    self:UpdateRaidLootStatus("Could not find the source roll.")
    return
  end
  if rollType == "DE" then
    local timeLeft = self:GetLootRollTimeLeft(sourceDrop)
    if timeLeft and timeLeft > 0 then
      self:UpdateRaidLootStatus("Wait for the roll to close before awarding the disenchanter.")
      return
    end
    if #self:GetLootRollWinningEntries(sourceDrop) > 0 or RosterNameKey(self:GetLootDisenchanter()) ~= RosterNameKey(winner) or not self:IsLootDisenchanterInGroup(winner) then
      self:UpdateRaidLootStatus("The assigned disenchanter is no longer eligible for this no-roll award.")
      return
    end
    awardType = "DE"
  else
    if not self:GetLootRollWinnerSlot(sourceDrop, winner, rollType) then
      self:UpdateRaidLootStatus("That player is no longer in a winning place for this roll.")
      return
    end
    if self:GetLootRollAwardedCopy(sourceDrop, winner, rollType) then
      self:UpdateRaidLootStatus(tostring(winner) .. " has already been awarded a copy for that " .. (rollType == "GREED" and "OS" or "MS") .. " roll.")
      return
    end
  end
  if currentDrop.award and currentDrop.award.winner and currentDrop.award.winner ~= "" then
    currentDrop = self:GetNextLootRollAwardDrop(sourceDrop)
    if not currentDrop then
      self:UpdateRaidLootStatus("All copies from this roll have already been awarded.")
      return
    end
    dropID = currentDrop.id
  end

  awardType = self:NormalizeAwardType(awardType)
  local drop, message
  if currentDrop.award and currentDrop.award.winner then
    drop, message = self:UpdateLootAward(dropID, winner, "", awardType)
  else
    drop, message = self:AwardRaidLootDrop(dropID, winner, "", awardType)
  end

  if not drop then
    self:UpdateRaidLootStatus(message or "Could not award roll winner.")
    return
  end

  if rollType ~= "DE" then
    sourceDrop.roll.awardedEntries = sourceDrop.roll.awardedEntries or {}
    sourceDrop.roll.awardedEntries[self:GetLootRollAwardKey(winner, rollType)] = drop.id
  end

  self:AnnounceRollAward(drop, winner, awardType)
  self:SetLootRollAwardPromptShown(false)
  self:UpdateRaidLootStatus("Awarded " .. tostring(drop.item or "loot") .. " to " .. tostring(ShortDisplayName(winner) or winner) .. ".")
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
  self:RefreshLootRollResultsPanel()
end

function APOCLootPrio:SetLootTrackerSettingsPanelShown(enabled)
  if enabled and not self:CanManageSettings() then
    self.lootTrackerSettingsPanelShown = false
    self:Print("Loot Tracker settings are available to the top two guild ranks only.")
    return
  end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.trackerSettingsPanel then return end

  local panel = self.frame.raidLootPanel.trackerSettingsPanel
  self.lootTrackerSettingsPanelShown = enabled and true or false

  if self.lootTrackerSettingsPanelShown then
    panel.rollDurationDirty = false
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 17)
    panel:Show()
    self:RefreshLootTrackerSettingsPanel()
  else
    panel:Hide()
    if self.frame.raidLootPanel.disenchanterPicker then
      self.frame.raidLootPanel.disenchanterPicker:Hide()
      self.lootDisenchanterPickerShown = false
    end
  end

  if self.frame.raidLootPanel.trackerSettings then
    self.frame.raidLootPanel.trackerSettings:SetText(self.lootTrackerSettingsPanelShown and "Settings: On" or "Settings")
  end
end

function APOCLootPrio:ToggleSettingsPanelFromLootTracker()
  self:SetLootTrackerSettingsPanelShown(not self.lootTrackerSettingsPanelShown)
end

function APOCLootPrio:SaveLootRollDurationFromPanel(value)
  local panel = self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.trackerSettingsPanel
  if not panel or not panel.rollDuration then return end
  local ok, result = self:SetLootRollDuration(value or panel.rollDuration:GetText())
  if not ok then
    if panel.status then panel.status:SetText(result) end
    return
  end
  panel.rollDurationDirty = false
  panel.rollDuration:SetText(tostring(result))
  panel.rollDuration:ClearFocus()
  self:RefreshLootTrackerSettingsPanel()
  if panel.status then panel.status:SetText("New rolls: " .. tostring(result) .. " seconds. Active rolls are unchanged.") end
end

function APOCLootPrio:SetLootAutoTrackModeFromPanel(mode)
  local ok, savedMode = self:SetLootAutoTrackMode(mode)
  local panel = self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.trackerSettingsPanel

  if not ok then
    if panel and panel.status then
      panel.status:SetText(savedMode or "Could not save Auto Track mode.")
    else
      self:Print(savedMode or "Could not save Auto Track mode.")
    end
    return
  end

  local label = self:GetLootAutoTrackModeLabel(savedMode)
  if panel and panel.status then
    panel.status:SetText("Auto Track set to " .. label .. ".")
  end
  self:RefreshLootTrackerSettingsPanel()
  self:RefreshRaidLootPanel()
end

function APOCLootPrio:ToggleLootQualityFromPanel(quality)
  local enabled = not self:IsLootQualityTracked(quality)
  local ok, savedEnabled = self:SetLootQualityTracked(quality, enabled)
  local panel = self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.trackerSettingsPanel

  if not ok then
    if panel and panel.status then
      panel.status:SetText(savedEnabled or "Could not save loot quality setting.")
    else
      self:Print(savedEnabled or "Could not save loot quality setting.")
    end
    return
  end

  if panel and panel.status then
    panel.status:SetText(self:GetLootQualityLabel(quality) .. " auto tracking turned " .. (savedEnabled and "On" or "Off") .. ".")
  end
  self:RefreshLootTrackerSettingsPanel()
  self:RefreshRaidLootPanel()
end

function APOCLootPrio:AdjustLootTrackerAccessRank(delta)
  local current = self:GetFeatureAccessRank("lootTracker")
  local ok, message = self:SetFeatureAccessRank("lootTracker", current + (delta or 0))
  local panel = self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.trackerSettingsPanel

  if not ok then
    if panel and panel.status then
      panel.status:SetText(message or "Could not save Loot Tracker setting.")
    else
      self:Print(message or "Could not save Loot Tracker setting.")
    end
    return
  end

  if panel and panel.status then
    panel.status:SetText("Loot Tracker full access set to " .. self:FormatFeatureAccessRank("lootTracker") .. ".")
  end
  self:RefreshOfficerControls()
  self:RefreshLootTrackerSettingsPanel()
  self:RefreshSettingsPanel()
  self:RefreshRaidLootPanel()
  if self.BroadcastAccessSettings then self:BroadcastAccessSettings() end
end

function APOCLootPrio:AdjustLootTrackerViewAccessRank(delta)
  local current = self:GetFeatureAccessRank("lootTrackerView")
  local ok, message = self:SetFeatureAccessRank("lootTrackerView", current + (delta or 0))
  local panel = self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.trackerSettingsPanel

  if not ok then
    if panel and panel.status then
      panel.status:SetText(message or "Could not save View-only setting.")
    else
      self:Print(message or "Could not save View-only setting.")
    end
    return
  end

  if panel and panel.status then
    panel.status:SetText("Loot Tracker view-only access set to " .. self:FormatFeatureAccessRank("lootTrackerView") .. ".")
  end
  self:RefreshOfficerControls()
  self:RefreshLootTrackerSettingsPanel()
  self:RefreshSettingsPanel()
  self:RefreshRaidLootPanel()
  if self.BroadcastAccessSettings then self:BroadcastAccessSettings() end
end

function APOCLootPrio:AdjustLootSessionDeleteAccessRank(delta)
  local current = self:GetFeatureAccessRank("lootSessionDelete")
  local ok, message = self:SetFeatureAccessRank("lootSessionDelete", current + (delta or 0))
  local panel = self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.trackerSettingsPanel

  if not ok then
    if panel and panel.status then
      panel.status:SetText(message or "Could not save Del button setting.")
    else
      self:Print(message or "Could not save Del button setting.")
    end
    return
  end

  if panel and panel.status then
    panel.status:SetText("Session Del button set to " .. self:FormatFeatureAccessRank("lootSessionDelete") .. ".")
  end
  self:RefreshLootTrackerSettingsPanel()
  self:RefreshLootSessionPicker()
  if self.BroadcastAccessSettings then self:BroadcastAccessSettings() end
end

function APOCLootPrio:SetLootTrackerRunnerPickerShown(enabled)
  if enabled and self.RequireMultiRunRunnerAssignment and not self:RequireMultiRunRunnerAssignment() then return end
  if enabled and not self.RequireMultiRunRunnerAssignment and not self:RequireLootTrackerEdit() then return end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.runnerPicker then return end

  local picker = self.frame.raidLootPanel.runnerPicker
  self.lootTrackerRunnerPickerShown = enabled and true or false

  if self.lootTrackerRunnerPickerShown then
    picker:ClearAllPoints()
    picker:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(picker, ADDON_FRAME_LEVEL + 18)
    picker:Show()
    self:RefreshLootTrackerRunnerPicker()
  else
    picker:Hide()
  end
end

function APOCLootPrio:RefreshLootTrackerRunnerPicker()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.runnerPicker then return end

  local picker = self.frame.raidLootPanel.runnerPicker
  local content = picker.content
  if not content then return end

  ClearFrameChildren(content)

  local runners = self:GetEligibleLootTrackerRunners()
  local currentOwner = self:GetLootTrackerOwner()
  local currentOwnerKey = RosterNameKey(currentOwner)
  local playerKey = RosterNameKey(self:GetPlayerDisplayName())
  local y = 0

  if #runners == 0 then
    CreateManualPickerTextRow(content, y, "No eligible players found.", "Invite a player allowed by Loot Tracker settings or refresh guild roster.", function() end)
    y = y - 38
  else
    for _, runner in ipairs(runners) do
      local runnerKey = RosterNameKey(runner.name)
      local title = ColorizeGroupMemberName(runner.name, ShortDisplayName(runner.name) or runner.name)
      if runnerKey == playerKey then
        title = title .. " |cffbbbbbb(You)|r"
      end

      local rankText = "Eligible"
      if runner.rankIndex ~= nil then
        rankText = "Rank " .. tostring(runner.rankIndex)
        if runner.rankName and runner.rankName ~= "" then
          rankText = rankText .. " - " .. runner.rankName
        end
      end
      if currentOwnerKey ~= "" and runnerKey == currentOwnerKey then
        rankText = rankText .. " - Current runner"
      end

      local row = CreateManualPickerTextRow(content, y, title, rankText, function()
        APOCLootPrio:SelectLootTrackerRunner(runner.name)
      end)

      if currentOwnerKey ~= "" and runnerKey == currentOwnerKey then
        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints(row)
        SetTextureColor(selected, .30, .10, .03, .35)
      end

      y = y - 38
    end
  end

  content:SetHeight(math.max(1, -y + 4))
  if picker.scroll and picker.scroll.UpdateScrollChildRect then
    picker.scroll:UpdateScrollChildRect()
  end

  if picker.status then
    picker.status:SetText(tostring(#runners) .. " eligible runner" .. (#runners == 1 and "" or "s"))
  end
end

function APOCLootPrio:SelectLootTrackerRunner(name)
  if self.RequireMultiRunRunnerAssignment and not self:RequireMultiRunRunnerAssignment() then return end
  if not self.RequireMultiRunRunnerAssignment and not self:RequireLootTrackerEdit() then return end

  if not name or name == "" then
    self:UpdateRaidLootStatus("Choose an eligible tracker runner first.")
    return
  end

  local target = name
  local redirected = false
  if self.ResolveRunnerNameForMasterLoot then
    target, redirected = self:ResolveRunnerNameForMasterLoot(name)
  end
  self:SetLootTrackerOwner(target)
  self:SetLootTrackerRunnerPickerShown(false)
  self:RefreshLootTrackerSettingsPanel()
  if redirected then
    local msg = "Runner follows master looter (" .. tostring(ShortDisplayName(target) or target) .. ")."
    self:UpdateRaidLootStatus(msg)
    self:Print(msg)
  else
    self:UpdateRaidLootStatus("Loot Tracker runner set to " .. tostring(target) .. ".")
  end
end

function APOCLootPrio:SetLootTrackerRunnerFromPanel()
  self:SetLootTrackerRunnerPickerShown(true)
end

function APOCLootPrio:SetSelfLootTrackerRunner()
  if self.IsHistoryEditContext and self:IsHistoryEditContext()
    and self.IsClosedHistorySession and self:IsClosedHistorySession(self:GetActiveHistorySession()) then
    local runner, message = self:ClaimSelectedHistoryRunner()
    if not runner then
      self:UpdateRaidLootStatus(message or "Could not take over this history session.")
      if self.Print then self:Print(message or "Could not take over this history session.") end
      return
    end
    self:SetLootTrackerRunnerPickerShown(false)
    self:RefreshLootTrackerSettingsPanel()
    self:RefreshRaidLootPanel()
    self:UpdateRaidLootStatus("History runner set to you. The original runner is preserved in the run record.")
    return
  end
  if self.RequireMultiRunRunnerAssignment and not self:RequireMultiRunRunnerAssignment() then return end
  if not self.RequireMultiRunRunnerAssignment and not self:RequireLootTrackerEdit() then return end

  local runner = self:GetPlayerDisplayName()
  local target = runner
  local redirected = false
  if self.ResolveRunnerNameForMasterLoot then
    target, redirected = self:ResolveRunnerNameForMasterLoot(runner)
  end
  self:SetLootTrackerOwner(target)
  self:SetLootTrackerRunnerPickerShown(false)
  self:RefreshLootTrackerSettingsPanel()

  if redirected then
    local msg = "Runner follows master looter (" .. tostring(ShortDisplayName(target) or target) .. ")."
    self:UpdateRaidLootStatus(msg)
    self:Print(msg)
  else
    self:UpdateRaidLootStatus("Loot Tracker runner set to you.")
  end
end

function APOCLootPrio:ClearLootTrackerRunnerFromPanel()
  if self.RequireMultiRunRunnerAssignment and not self:RequireMultiRunRunnerAssignment() then return end
  if not self.RequireMultiRunRunnerAssignment and not self:RequireLootTrackerEdit() then return end

  local ml = self.GetLootMasterDisplayName and self:GetLootMasterDisplayName() or nil
  if ml and ml ~= "" and self.IsLootMethodMaster and self:IsLootMethodMaster() then
    -- Auto is definitive under master loot: assign the ML, do not leave nil.
    self:SetLootTrackerOwner(ml, "ml-auto")
    self:SetLootTrackerRunnerPickerShown(false)
    self:RefreshLootTrackerSettingsPanel()
    local msg = "Loot Tracker runner set to master looter " .. tostring(ShortDisplayName(ml) or ml) .. " (Auto)."
    self:UpdateRaidLootStatus(msg)
    self:Print(msg)
    return
  end

  self:ClearLootTrackerOwner()
  self:SetLootTrackerRunnerPickerShown(false)
  self:RefreshLootTrackerSettingsPanel()
  self:UpdateRaidLootStatus("Loot Tracker runner cleared. Auto mode will use master looter or leader.")
end

function APOCLootPrio:SetRunnerToMasterLooter()
  if self.RequireMultiRunRunnerAssignment and not self:RequireMultiRunRunnerAssignment() then return end
  if not self.RequireMultiRunRunnerAssignment and not (self.CanAssignMultiRunRunner and self:CanAssignMultiRunRunner()) then
    if not self:RequireLootTrackerEdit() then return end
  end

  local ml = self.GetLootMasterDisplayName and self:GetLootMasterDisplayName() or nil
  if not ml or ml == "" then
    self:UpdateRaidLootStatus("No master looter detected to assign as runner.")
    self:Print("No master looter detected to assign as runner.")
    return
  end

  self:SetLootTrackerOwner(ml)
  self:SetLootTrackerRunnerPickerShown(false)
  self:RefreshLootTrackerSettingsPanel()
  local msg = "Loot Tracker runner set to master looter " .. tostring(ShortDisplayName(ml) or ml) .. "."
  self:UpdateRaidLootStatus(msg)
  self:Print(msg)
end

function APOCLootPrio:SetLootDisenchanterPickerShown(enabled)
  if enabled and not self:RequireLootTrackerEdit() then return end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.disenchanterPicker then return end

  local picker = self.frame.raidLootPanel.disenchanterPicker
  self.lootDisenchanterPickerShown = enabled and true or false
  if self.lootDisenchanterPickerShown then
    picker:ClearAllPoints()
    picker:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(picker, ADDON_FRAME_LEVEL + 18)
    picker:Show()
    self:RefreshLootDisenchanterPicker()
  else
    picker:Hide()
  end
end

function APOCLootPrio:RefreshLootDisenchanterPicker()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.disenchanterPicker then return end
  local picker = self.frame.raidLootPanel.disenchanterPicker
  local content = picker.content
  if not content then return end
  ClearFrameChildren(content)

  local members = self:GetGroupRoster()
  local currentKey = RosterNameKey(self:GetLootDisenchanter())
  local y = 0
  table.sort(members, function(a, b) return tostring(ShortDisplayName(a) or a) < tostring(ShortDisplayName(b) or b) end)

  if #members == 0 then
    CreateManualPickerTextRow(content, y, "No group members found.", "Join a party or raid, then refresh.", function() end)
    y = y - 38
  else
    for _, memberName in ipairs(members) do
      local memberKey = RosterNameKey(memberName)
      local displayName = ShortDisplayName(memberName) or memberName
      local title = ColorizeGroupMemberName(memberName, displayName)
      local detail = memberKey == currentKey and "Current disenchanter" or "Current group member"
      local row = CreateManualPickerTextRow(content, y, title, detail, function()
        APOCLootPrio:SelectLootDisenchanter(memberName)
      end)
      if memberKey == currentKey then
        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints(row)
        SetTextureColor(selected, .30, .10, .03, .35)
      end
      y = y - 38
    end
  end

  content:SetHeight(math.max(1, -y + 4))
  if picker.scroll and picker.scroll.UpdateScrollChildRect then picker.scroll:UpdateScrollChildRect() end
  picker.status:SetText(tostring(#members) .. " current group member" .. (#members == 1 and "" or "s"))
end

function APOCLootPrio:SelectLootDisenchanter(name)
  if not self:RequireLootTrackerEdit() then return end
  if not name or name == "" or not self:IsLootDisenchanterInGroup(name) then
    self:UpdateRaidLootStatus("Choose a current group member as the disenchanter.")
    return
  end
  self:SetLootDisenchanter(name)
  self:SetLootDisenchanterPickerShown(false)
  self:RefreshLootTrackerSettingsPanel()
  self:UpdateRaidLootStatus("Disenchanter set to " .. tostring(ShortDisplayName(name) or name) .. ".")
end

function APOCLootPrio:ClearLootDisenchanterFromPanel()
  if not self:RequireLootTrackerEdit() then return end
  self:ClearLootDisenchanter()
  self:SetLootDisenchanterPickerShown(false)
  self:RefreshLootTrackerSettingsPanel()
  self:UpdateRaidLootStatus("Disenchanter assignment cleared.")
end

function APOCLootPrio:SelectRaidLootItem(item, bossName)
  if not self:CanEditLootTracker() then
    self:UpdateRaidLootStatus("Viewer mode: only leadership or the assigned runner can stage drops.")
    return
  end

  self.selectedRaidLootItem = item
  self.selectedRaidLootBoss = bossName or "Unknown boss"
  self:RefreshRaidLootPanel()
  self:UpdateRaidLootStatus("Ready to add drop.")
end

function APOCLootPrio:AddSelectedRaidLootDrop()
  if not self:RequireLootTrackerEdit() then return end

  if not self.selectedRaidLootItem then
    self:UpdateRaidLootStatus("Click an item first.")
    return
  end

  local drop = self:AddRaidLootDrop(self.selectedRaidLootItem, self.selectedRaidLootBoss, self.selectedRaid)
  if not drop then
    self:UpdateRaidLootStatus("Could not add drop.")
    return
  end

  self.selectedLootTrackerRaid = self.selectedRaid
  self:UpdateRaidLootStatus("Drop added.")
  self:RefreshRaidLootPanel()
end

function APOCLootPrio:SetManualLootPickerShown(enabled)
  if enabled and not self:RequireLootTrackerEdit() then return end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.manualPicker then return end

  local picker = self.frame.raidLootPanel.manualPicker
  self.manualLootPickerShown = enabled and true or false

  if self.manualLootPickerShown then
    self.manualLootPickerStep = "raid"
    self.manualLootRaid = nil
    self.manualLootBoss = nil
    self.manualLootItem = nil
    self.manualLootItems = {}
    picker:ClearAllPoints()
    picker:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(picker, ADDON_FRAME_LEVEL + 18)
    picker:Show()
    self:RefreshManualLootPicker()
    self:UpdateRaidLootStatus("Choose the raid the item dropped from.")
  else
    picker:Hide()
  end
end

function APOCLootPrio:ManualLootPickerBack()
  if self.manualLootPickerStep == "confirm" then
    self.manualLootPickerStep = "item"
    self.manualLootItem = nil
  elseif self.manualLootPickerStep == "item" then
    self.manualLootPickerStep = "boss"
    self.manualLootBoss = nil
    self.manualLootItem = nil
    self.manualLootItems = {}
  elseif self.manualLootPickerStep == "boss" then
    self.manualLootPickerStep = "raid"
    self.manualLootRaid = nil
    self.manualLootBoss = nil
    self.manualLootItem = nil
    self.manualLootItems = {}
  else
    self:SetManualLootPickerShown(false)
    return
  end

  self:RefreshManualLootPicker()
end

function APOCLootPrio:SelectManualLootRaid(raidName)
  if not raidName or not APOCLootPrioData or not APOCLootPrioData[raidName] then return end

  self.manualLootRaid = raidName
  self.manualLootBoss = nil
  self.manualLootItem = nil
  self.manualLootItems = {}
  self.manualLootPickerStep = "boss"
  self:RefreshManualLootPicker()
  self:UpdateRaidLootStatus("Choose the boss, trash, or patterns section.")
end

function APOCLootPrio:SelectManualLootBoss(boss)
  if not boss then return end

  self.manualLootBoss = boss
  self.manualLootItem = nil
  self.manualLootItems = {}
  self.manualLootPickerStep = "item"
  self:RefreshManualLootPicker()
  self:UpdateRaidLootStatus("Choose the item to add.")
end

function APOCLootPrio:SelectManualLootItem(item)
  if not item then return end

  self.manualLootItems = self.manualLootItems or {}
  local key = self:GetItemKey(item) or item.name
  if not key then return end

  local entry = self.manualLootItems[key]
  if entry then
    entry.count = (entry.count or 1) + 1
  else
    self.manualLootItems[key] = { item = item, count = 1 }
  end

  self:RefreshManualLootPicker()
  local count = self:GetManualLootPickerSelectionCount()
  if count > 0 then
    self:UpdateRaidLootStatus("Selected " .. tostring(count) .. " item" .. (count == 1 and "" or "s") .. ".")
  else
    self:UpdateRaidLootStatus("Choose one or more items to add.")
  end
end

function APOCLootPrio:RemoveManualLootItem(item)
  if not item then return end

  self.manualLootItems = self.manualLootItems or {}
  local key = self:GetItemKey(item) or item.name
  if not key or not self.manualLootItems[key] then return end

  local entry = self.manualLootItems[key]
  entry.count = (entry.count or 1) - 1
  if entry.count <= 0 then
    self.manualLootItems[key] = nil
  end

  self:RefreshManualLootPicker()
  local count = self:GetManualLootPickerSelectionCount()
  if count > 0 then
    self:UpdateRaidLootStatus("Selected " .. tostring(count) .. " item" .. (count == 1 and "" or "s") .. ".")
  else
    self:UpdateRaidLootStatus("Choose one or more items to add.")
  end
end

function APOCLootPrio:GetManualLootPickerSelectionCount()
  local count = 0
  for _, entry in pairs(self.manualLootItems or {}) do
    if entry then count = count + (tonumber(entry.count) or 1) end
  end
  return count
end

function APOCLootPrio:GetManualLootPickerSelectedItems()
  local selected = self.manualLootItems or {}
  local list = {}

  for _, item in ipairs((self.manualLootBoss and self.manualLootBoss.items) or {}) do
    local key = self:GetItemKey(item) or item.name
    local entry = key and selected[key]
    local count = entry and (tonumber(entry.count) or 1) or 0
    for index = 1, count do
      table.insert(list, item)
    end
  end

  return list
end

function APOCLootPrio:GetManualLootPickerSelectedEntries()
  local selected = self.manualLootItems or {}
  local list = {}

  for _, item in ipairs((self.manualLootBoss and self.manualLootBoss.items) or {}) do
    local key = self:GetItemKey(item) or item.name
    local entry = key and selected[key]
    local count = entry and (tonumber(entry.count) or 1) or 0
    if count > 0 then
      table.insert(list, { item = item, count = count })
    end
  end

  return list
end

function APOCLootPrio:ConfirmManualLootPickerItem()
  if not self:RequireLootTrackerEdit() then return end

  if not self.manualLootRaid or not self.manualLootBoss then
    self:UpdateRaidLootStatus("Choose a boss first.")
    return
  end

  local selectedItems = self:GetManualLootPickerSelectedItems()
  if #selectedItems == 0 then
    self:UpdateRaidLootStatus("Choose one or more items first.")
    return
  end

  if self.manualLootPickerStep ~= "confirm" then
    self.manualLootPickerStep = "confirm"
    self:RefreshManualLootPicker()
    self:UpdateRaidLootStatus("Confirm the selected items before adding them.")
    return
  end

  local bossName = self.manualLootBoss.boss or "Unknown boss"
  local added, firstDrop, lastMessage = 0, nil, nil
  for _, item in ipairs(selectedItems) do
    local drop, message = self:AddRaidLootDrop(item, bossName, self.manualLootRaid)
    if drop then
      added = added + 1
      firstDrop = firstDrop or drop
      self.selectedRaidLootItem = item
    else
      lastMessage = message
    end
  end

  if added == 0 then
    self:UpdateRaidLootStatus(lastMessage or "Could not add drops.")
    return
  end

  self.selectedLootTrackerRaid = self.manualLootRaid
  self.selectedRaidLootBoss = bossName
  self:SetManualLootPickerShown(false)
  self:RefreshRaidLootPanel()
  if firstDrop then self.selectedLootDropID = firstDrop.id end
  self:UpdateRaidLootStatus("Added " .. tostring(added) .. " item" .. (added == 1 and "" or "s") .. ".")
end

function APOCLootPrio:RefreshManualLootPicker()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.manualPicker then return end

  local picker = self.frame.raidLootPanel.manualPicker
  if not picker:IsShown() then return end

  local content = picker.content
  ClearFrameChildren(content)

  local step = self.manualLootPickerStep or "raid"
  local y = 0

  if step == "raid" then
    picker.title:SetText("Add Manual Loot - Choose Raid")
    picker.instructions:SetText("Pick the raid or loot table first.")
    picker.back:Hide()
    picker.confirm:Hide()

    for _, raidName in ipairs(MANUAL_PICKER_RAID_ORDER) do
      local bosses = APOCLootPrioData and APOCLootPrioData[raidName]
      if bosses then
        local itemCount = 0
        for _, boss in ipairs(bosses) do itemCount = itemCount + #(boss.items or {}) end
        CreateManualPickerTextRow(content, y, raidName, tostring(#bosses) .. " sections - " .. tostring(itemCount) .. " items", function()
          APOCLootPrio:SelectManualLootRaid(raidName)
        end)
        y = y - 38
      end
    end
  elseif step == "boss" then
    picker.title:SetText("Add Manual Loot - " .. (self.manualLootRaid or "Raid"))
    picker.instructions:SetText("Choose a boss, trash, or patterns section.")
    picker.back:Show()
    picker.confirm:Hide()

    for _, boss in ipairs((APOCLootPrioData and APOCLootPrioData[self.manualLootRaid]) or {}) do
      CreateManualPickerTextRow(content, y, boss.boss or "Unknown", tostring(#(boss.items or {})) .. " items", function()
        APOCLootPrio:SelectManualLootBoss(boss)
      end)
      y = y - 38
    end
  elseif step == "item" then
    local bossName = self.manualLootBoss and self.manualLootBoss.boss or "Boss"
    local selectedCount = self:GetManualLootPickerSelectionCount()
    picker.title:SetText("Add Manual Loot - " .. bossName)
    picker.instructions:SetText("Select one or more items that dropped, then review the batch.")
    picker.back:Show()
    picker.confirm:Show()
    picker.confirm:SetText("Review Items")
    SetControlEnabled(picker.confirm, selectedCount > 0)

    for _, item in ipairs((self.manualLootBoss and self.manualLootBoss.items) or {}) do
      local key = self:GetItemKey(item) or item.name
      local entry = key and self.manualLootItems and self.manualLootItems[key]
      local selectedCount = entry and (tonumber(entry.count) or 1) or 0
      CreateManualPickerItemRow(content, y, item, bossName, function()
        APOCLootPrio:SelectManualLootItem(item)
      end, selectedCount, function()
        APOCLootPrio:RemoveManualLootItem(item)
      end)
      y = y - 48
    end
  elseif step == "confirm" then
    local bossName = self.manualLootBoss and self.manualLootBoss.boss or "Unknown boss"
    local selectedItems = self:GetManualLootPickerSelectedItems()
    local selectedEntries = self:GetManualLootPickerSelectedEntries()
    picker.title:SetText("Confirm Manual Loot")
    picker.instructions:SetText("Add these " .. tostring(#selectedItems) .. " items to the dropped queue?")
    picker.back:Show()
    picker.confirm:Show()
    picker.confirm:SetText("Add Items")
    SetControlEnabled(picker.confirm, #selectedItems > 0)

    for _, entry in ipairs(selectedEntries) do
      CreateManualPickerItemRow(content, y, entry.item, bossName, function() end, entry.count or 1)
      y = y - 48
    end

    if #selectedItems > 0 then
      y = y - 8
      CreateManualPickerTextRow(content, y, "Add selected items to dropped queue", (self.manualLootRaid or "Raid") .. " - " .. bossName, function()
        APOCLootPrio:ConfirmManualLootPickerItem()
      end)
      y = y - 38
    end
  end

  content:SetHeight(math.max(1, math.abs(y) + 8))
  if picker.scroll and picker.scroll.UpdateScrollChildRect then
    picker.scroll:UpdateScrollChildRect()
  end
end

function APOCLootPrio:SelectRaidLootDrop(dropID)
  self.selectedLootDropID = dropID
  self:RefreshRaidLootPanel()
  self:SetLootRollResultsPanelShown(true)
  self:UpdateRaidLootStatus("Showing item priority and current rolls.")
end

function APOCLootPrio:StartSelectedRaidLootRoll()
  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local ok, message = self:StartRaidLootRoll(self.selectedLootDropID, trackerRaid)
  self:UpdateRaidLootStatus(message or (ok and "Roll started." or "Could not start roll."))
  if ok then
    self:SetLootRollResultsPanelShown(true)
  end
end

function APOCLootPrio:ResetSelectedRaidLootRoll()
  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local ok, message = self:ResetRaidLootRoll(self.selectedLootDropID, trackerRaid)
  self:UpdateRaidLootStatus(message or (ok and "Rolls reset." or "Could not reset rolls."))
  if self.frame and self.frame.raidLootPanel then
    local drop = self:FindRaidLootDrop(self.selectedLootDropID, trackerRaid)
    RefreshSelectedDropRollDisplay(self.frame.raidLootPanel, drop)
  end
  if self.lootRollResultsPanelShown then
    self:RefreshLootRollResultsPanel()
  end
end

function APOCLootPrio:ResetSelectedRaidLootRollTimer()
  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local ok, message = self:ResetRaidLootRollTimer(self.selectedLootDropID, trackerRaid)
  self:UpdateRaidLootStatus(message or (ok and "Roll timer reset." or "Could not reset roll timer."))
  if self.frame and self.frame.raidLootPanel then
    local drop = self:FindRaidLootDrop(self.selectedLootDropID, trackerRaid)
    RefreshSelectedDropRollDisplay(self.frame.raidLootPanel, drop)
  end
  if self.lootRollResultsPanelShown then
    self:RefreshLootRollResultsPanel()
  end
end

function APOCLootPrio:SelectRecentAwardDrop(dropID)
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.recentAwardsPanel then return end

  if not self:CanEditLootTracker() then
    self:UpdateRaidLootStatus("Officer view: recent awards are read-only.")
    return
  end

  local drop = self:FindRaidLootDrop(dropID)
  if not drop or not drop.award then
    self:UpdateRecentAwardEditStatus("Could not find that award.")
    return
  end

  self.selectedRecentAwardDropID = dropID
  local panel = self.frame.raidLootPanel.recentAwardsPanel
  local editor = panel.editor

  SetRecentAwardsEditorShown(panel, true)
  editor.currentDropID = dropID
  editor.item:SetText((drop.item or "Unknown item") .. " - " .. (drop.boss or "Unknown") .. " - " .. self:FormatLootTime(drop.award.awardedAt or drop.droppedAt))
  editor.winner:SetText(drop.award.winner or "")
  editor.note:SetText(drop.award.note or "")
  SetPanelAwardType(editor, self:GetAwardType(drop))
  self:RefreshRecentAwardEditRoster()
  self:RefreshRaidLootPanel()
  self:UpdateRecentAwardEditStatus("Editing selected recent award.")
end

function APOCLootPrio:UpdateRecentAwardEditStatus(text)
  if self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.recentAwardsPanel and self.frame.raidLootPanel.recentAwardsPanel.editor then
    self.frame.raidLootPanel.recentAwardsPanel.editor.status:SetText(text or "")
  end
end

function APOCLootPrio:RefreshRecentAwardEditRoster()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.recentAwardsPanel then return end
  local editor = self.frame.raidLootPanel.recentAwardsPanel.editor
  if not editor or not editor.memberContent then return end
  local canEdit = self:CanEditLootTracker()

  local content = editor.memberContent
  for _, child in ipairs({content:GetChildren()}) do
    child:Hide()
    child:SetParent(nil)
  end

  local members = self:GetGroupRoster()
  local columns = 2
  local buttonWidth = 92
  local gap = 4
  local currentWinner = TrimText(editor.winner:GetText())

  for index, memberName in ipairs(members) do
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    button:SetSize(buttonWidth, GROUP_MEMBER_BUTTON_HEIGHT)
    button:SetPoint("TOPLEFT", column * (buttonWidth + gap), -(row * (GROUP_MEMBER_BUTTON_HEIGHT + 3)))
    button:SetText(string.match(memberName or "", "^([^%-]+)") or memberName)
    button.memberName = memberName
    button:SetScript("OnClick", function(selfButton)
      if not APOCLootPrio:CanEditLootTracker() then return end
      editor.winner:SetText(selfButton.memberName or "")
      APOCLootPrio:RefreshRecentAwardEditRoster()
    end)
    SetControlEnabled(button, canEdit)

    if button.UnlockHighlight then button:UnlockHighlight() end
    SetAPOCButtonSelected(button, currentWinner ~= "" and currentWinner == memberName)
  end

  local rows = math.max(1, math.ceil(math.max(#members, 1) / columns))
  content:SetHeight(rows * (GROUP_MEMBER_BUTTON_HEIGHT + 3))
  if editor.memberScroll and editor.memberScroll.UpdateScrollChildRect then
    editor.memberScroll:UpdateScrollChildRect()
  end
end

function APOCLootPrio:CancelRecentAwardEdit()
  self.selectedRecentAwardDropID = nil
  if self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.recentAwardsPanel then
    local panel = self.frame.raidLootPanel.recentAwardsPanel
    if panel.editor then panel.editor.currentDropID = nil end
    SetRecentAwardsEditorShown(panel, false)
  end
  self:RefreshRaidLootPanel()
end

function APOCLootPrio:SaveRecentAwardEdit()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.recentAwardsPanel then return end
  if not self:RequireLootTrackerEdit() then return end

  if not self.selectedRecentAwardDropID then
    self:UpdateRecentAwardEditStatus("Select a recent award first.")
    return
  end

  local editor = self.frame.raidLootPanel.recentAwardsPanel.editor
  local winner = TrimText(editor.winner:GetText())
  local note = TrimText(editor.note:GetText())
  local drop, message = self:UpdateLootAward(self.selectedRecentAwardDropID, winner, note, editor.awardType)

  if not drop then
    self:UpdateRecentAwardEditStatus(message or "Could not save award.")
    return
  end

  editor.item:SetText((drop.item or "Unknown item") .. " - " .. (drop.boss or "Unknown") .. " - " .. self:FormatLootTime(drop.award.awardedAt or drop.droppedAt))
  self:UpdateRecentAwardEditStatus("Saved for " .. winner .. ".")
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:DeleteRecentAwardEdit()
  if not self:RequireLootTrackerEdit() then return end

  local targetID = self.selectedRecentAwardDropID
  if not targetID then
    self:UpdateRecentAwardEditStatus("Select a recent award first.")
    return
  end

  local drop, message = self:DeleteRaidLootDrop(targetID)
  if not drop then
    self:UpdateRecentAwardEditStatus(message or "Could not delete award.")
    return
  end

  self.selectedRecentAwardDropID = nil
  if self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.recentAwardsPanel then
    SetRecentAwardsEditorShown(self.frame.raidLootPanel.recentAwardsPanel, false)
  end
  self:UpdateRaidLootStatus("Deleted " .. (drop.item or "loot") .. ".")
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:SaveRaidLootAward()
  if not self.frame or not self.frame.raidLootPanel then return end
  if not self:RequireLootTrackerEdit() then return end

  local panel = self.frame.raidLootPanel
  local winner = panel.selectedWinnerName or TrimText(panel.winner:GetText())
  local note = TrimText(panel.note:GetText())
  local savedAwardType = panel.awardType
  local currentDrop = self:FindRaidLootDrop(self.selectedLootDropID)
  local editingExistingAward = currentDrop and currentDrop.award
  local drop, message

  if editingExistingAward then
    drop, message = self:UpdateLootAward(self.selectedLootDropID, winner, note, panel.awardType)
  else
    drop, message = self:AwardRaidLootDrop(self.selectedLootDropID, winner, note, panel.awardType)
  end

  if not drop then
    self:UpdateRaidLootStatus(message or "Could not save award.")
    return
  end

  panel.selectedWinnerName = nil
  panel.winner:SetText("")
  panel.note:SetText("")
  SetPanelAwardType(panel, "MS")
  self:UpdateRaidLootStatus(editingExistingAward and "Award updated." or (savedAwardType == "GB" and "Saved to Guild Bank." or "Award saved."))
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:SetLootDeleteConfirmShown(enabled, dropID)
  if enabled and not self:RequireLootTrackerEdit() then return end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.deleteConfirm then return end

  local panel = self.frame.raidLootPanel.deleteConfirm
  if enabled then
    local drop = self:FindRaidLootDrop(dropID)
    if not drop then
      self:UpdateRaidLootStatus("Select a dropped item first.")
      return
    end

    self.pendingDeleteLootDropID = dropID
    panel.message:SetText("Remove " .. (drop.item or "this item") .. " from the loot tracker?")
    panel:Show()
  else
    self.pendingDeleteLootDropID = nil
    panel:Hide()
  end
end

function APOCLootPrio:DeleteSelectedRaidLootDrop(dropID)
  self:SetLootDeleteConfirmShown(true, dropID)
end

function APOCLootPrio:ConfirmDeleteSelectedRaidLootDrop()
  if not self:RequireLootTrackerEdit() then return end

  local dropID = self.pendingDeleteLootDropID
  if not dropID then
    self:UpdateRaidLootStatus("Select a dropped item first.")
    return
  end

  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local drop, message = self:DeleteRaidLootDrop(dropID, trackerRaid)

  if not drop then
    self:UpdateRaidLootStatus(message or "Could not delete drop.")
    return
  end

  if self.frame and self.frame.raidLootPanel then
    self.frame.raidLootPanel.winner:SetText("")
    self.frame.raidLootPanel.selectedWinnerName = nil
    self.frame.raidLootPanel.note:SetText("")
    self.frame.raidLootPanel.currentDropID = nil
  end

  self:UpdateRaidLootStatus("Deleted " .. (drop.item or "drop") .. ".")
  self:SetLootDeleteConfirmShown(false)
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:SetLootSessionPickerShown(enabled)
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.sessionPicker then return end
  if enabled and not self:CanViewLootTracker() then return end

  local picker = self.frame.raidLootPanel.sessionPicker
  if enabled then
    if self.RequestOfficerHistorySync then self:RequestOfficerHistorySync("open-history") end
    picker:Show()
    self:RefreshLootSessionPicker()
  else
    picker:Hide()
    if self.frame.raidLootPanel.sessionDeleteConfirm then
      self.frame.raidLootPanel.sessionDeleteConfirm:Hide()
      self.pendingDeleteLootSessionKey = nil
    end
  end
end

function APOCLootPrio:ToggleLootSessionPicker()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.sessionPicker then return end
  self:SetLootSessionPickerShown(not self.frame.raidLootPanel.sessionPicker:IsShown())
end

function APOCLootPrio:RefreshLootSessionPicker()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.sessionPicker then return end

  local picker = self.frame.raidLootPanel.sessionPicker
  local content = picker.content
  ClearFrameChildren(content)

  local sessions = self:GetLootSessions()
  picker.summary:SetText(tostring(#sessions) .. " saved session" .. (#sessions == 1 and "" or "s") .. " available")

  local y = 0
  for index, session in ipairs(sessions) do
    if index > 12 then break end
    local sessionKey = session.key
    local summary = self:GetRaidLootSummaryForSession(session)
    local total = summary and summary.total or #(session.drops or {})
    local pending = summary and summary.pending or 0
    local detail = self:FormatLootTime(session.createdAt) .. " - " .. tostring(total) .. " drops, " .. tostring(pending) .. " unawarded"
    local materials = self.FormatRaidMaterialSummary and self:FormatRaidMaterialSummary(summary) or ""
    if materials ~= "" then detail = detail .. " · " .. materials end
    if session.archived then
      detail = detail .. " - Guild Raid History"
      local fromName = session.createdBy or session.syncedFrom
      if fromName and tostring(fromName) ~= "" then
        local short = string.match(tostring(fromName), "^([^%-]+)") or tostring(fromName)
        if short ~= "" then detail = detail .. " from " .. short end
      end
    elseif session.finalized then
      detail = detail .. " - Closed & Saved"
    end
    local isActive = APOCLootPrioDB and APOCLootPrioDB.loot and APOCLootPrioDB.loot.activeSessionKey == sessionKey
    CreateLootSessionPickerRow(
      content,
      y,
      session,
      detail,
      isActive,
      self:CanDeleteLootSessions(),
      function()
        APOCLootPrio:SelectLootSession(sessionKey)
      end,
      function()
        APOCLootPrio:SetLootSessionDeleteConfirmShown(true, sessionKey)
      end)
    y = y - 64
  end

  if #sessions == 0 then
    CreateManualPickerTextRow(content, y, "No saved sessions yet.", "Click New Session to start one.", function() end)
    y = y - 38
  end

  content:SetHeight(math.max(1, math.abs(y) + 10))
  if picker.scroll and picker.scroll.UpdateScrollChildRect then
    picker.scroll:UpdateScrollChildRect()
  end
  StyleAPOCFrameTree(picker)
end

function APOCLootPrio:SetLootSessionDeleteConfirmShown(enabled, sessionKey)
  if enabled and not self:RequireLootSessionDelete() then return end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.sessionDeleteConfirm then return end

  local panel = self.frame.raidLootPanel.sessionDeleteConfirm
  if enabled then
    self:InitDB()
    local session = sessionKey and APOCLootPrioDB and APOCLootPrioDB.loot and APOCLootPrioDB.loot.sessions and APOCLootPrioDB.loot.sessions[sessionKey]
    if not session then
      self:UpdateRaidLootStatus("Choose a saved session first.")
      return
    end

    self.pendingDeleteLootSessionKey = sessionKey
    panel.message:SetText("Delete " .. self:GetLootSessionDisplayName(session) .. "? This removes its dropped and awarded loot from the tracker.")
    panel:ClearAllPoints()
    if self.frame.raidLootPanel.sessionPicker and self.frame.raidLootPanel.sessionPicker:IsShown() then
      panel:SetPoint("CENTER", self.frame.raidLootPanel.sessionPicker, "CENTER", 0, 4)
    else
      panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 36)
    end
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 24)
    panel:Show()
  else
    self.pendingDeleteLootSessionKey = nil
    panel:Hide()
  end
end

function APOCLootPrio:ConfirmDeleteLootSession()
  if not self:RequireLootSessionDelete() then return end

  local sessionKey = self.pendingDeleteLootSessionKey
  if not sessionKey then
    self:UpdateRaidLootStatus("Choose a saved session first.")
    return
  end

  local deleted, message = self:DeleteLootSession(sessionKey)
  if not deleted then
    self:UpdateRaidLootStatus(message or "Could not delete session.")
    return
  end

  self.pendingDeleteLootSessionKey = nil
  if self.frame and self.frame.raidLootPanel and self.frame.raidLootPanel.sessionDeleteConfirm then
    self.frame.raidLootPanel.sessionDeleteConfirm:Hide()
  end

  self.selectedLootDropID = nil
  self.selectedRaidLootItem = nil
  self:RefreshLootSessionPicker()
  self:RefreshLootTrackerSettingsPanel()
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
  self:UpdateRaidLootStatus("Deleted " .. self:GetLootSessionDisplayName(deleted) .. ".")
end

function APOCLootPrio:SelectLootSession(sessionKey)
  local session, message = self:OpenLootSession(sessionKey)
  if not session then
    self:UpdateRaidLootStatus(message or "Could not open session.")
    return
  end

  self.selectedLootDropID = nil
  self.selectedRaidLootItem = nil
  self:SetLootSessionPickerShown(false)
  self:RefreshRaidLootPanel()
  local status = "Opened " .. self:GetLootSessionDisplayName(session) .. "."
  if message == "history-peek" then
    if self.CanEditGuildRaidHistory and self:CanEditGuildRaidHistory() then
      status = status .. " History open (ranks 0–2 can edit)."
    else
      status = status .. " History open (view-only)."
    end
  elseif self.IsHistoryEditContext and self:IsHistoryEditContext() and self:CanEditGuildRaidHistory() then
    status = status .. " History edit (ranks 0–2)."
  end
  self:UpdateRaidLootStatus(status)
end

function APOCLootPrio:UnawardSelectedRaidLootDrop(dropID)
  if not self:RequireLootTrackerEdit() then return end

  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local drop, message = self:UnawardRaidLootDrop(dropID, trackerRaid)
  if not drop then
    self:UpdateRaidLootStatus(message or "Could not unaward loot.")
    return
  end

  if self.frame and self.frame.raidLootPanel and self.selectedLootDropID == dropID then
    self.frame.raidLootPanel.winner:SetText("")
    self.frame.raidLootPanel.selectedWinnerName = nil
    self.frame.raidLootPanel.note:SetText("")
    self.frame.raidLootPanel.currentDropID = nil
  end

  self:UpdateRaidLootStatus("Unawarded " .. (drop.item or "loot") .. ".")
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:SetNewLootSessionConfirmShown(enabled, instanceName)
  if enabled and not self:RequireLootTrackerEdit() then return false end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.newSessionConfirm then return false end

  local panel = self.frame.raidLootPanel.newSessionConfirm
  if enabled then
    self.pendingInstanceSessionPrompt = instanceName
    if instanceName and instanceName ~= "" then
      panel.title:SetText("New Instance Detected")
      panel.message:SetText("You entered " .. tostring(instanceName) .. ". Would you like to create a new loot session?")
      panel.start:SetText("Yes")
      panel.cancel:SetText("No")
    else
      local nextName = self:GetNextLootSessionName()
      panel.title:SetText("Start New Session?")
      panel.message:SetText("Start " .. nextName .. "? Current dropped and awarded loot stays saved in its existing session.")
      panel.start:SetText("Start")
      panel.cancel:SetText("Cancel")
    end
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 36)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 25)
    panel:Show()
  else
    self.pendingInstanceSessionPrompt = nil
    panel:Hide()
  end
  return true
end

function APOCLootPrio:SetInstanceSessionPromptShown(enabled, instanceName)
  return self:SetNewLootSessionConfirmShown(enabled, instanceName)
end

function APOCLootPrio:SetRenameLootSessionShown(enabled)
  if enabled and not self:RequireLootTrackerEdit() then return false end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.renameSessionPrompt then return false end

  local panel = self.frame.raidLootPanel.renameSessionPrompt
  if enabled then
    local session = self.GetActiveHistorySession and self:GetActiveHistorySession() or nil
    if not session then
      local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
      session = self:GetRaidLootSession(trackerRaid)
    end
    if not session or not session.key or session.readOnly then
      self:UpdateRaidLootStatus("Select a saved or active raid session first.")
      return false
    end
    if not self:CanEditLootSession(session) then
      self:UpdateRaidLootStatus("No edit permission for this session.")
      return false
    end

    self.pendingRenameLootSessionKey = session.key
    panel.error:SetText("")
    panel.input:SetText(tostring(session.name or session.raid or ""))
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 36)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 26)
    panel:Show()
    panel.input:SetFocus()
    panel.input:HighlightText()
  else
    self.pendingRenameLootSessionKey = nil
    panel.error:SetText("")
    panel.input:ClearFocus()
    panel:Hide()
  end
  return true
end

function APOCLootPrio:ConfirmRenameLootSession()
  if not self:RequireLootTrackerEdit() then return end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.renameSessionPrompt then return end

  local panel = self.frame.raidLootPanel.renameSessionPrompt
  local sessionKey = self.pendingRenameLootSessionKey
  local session, message, changed = self:RenameLootSession(sessionKey, panel.input:GetText())
  if not session then
    panel.error:SetText(message or "Could not rename this session.")
    panel.input:SetFocus()
    panel.input:HighlightText()
    return
  end

  self:SetRenameLootSessionShown(false)
  self:RefreshLootSessionPicker()
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
  if self.RefreshLiveRaidsPanel then self:RefreshLiveRaidsPanel() end
  local status = message or "Session renamed."
  if changed then status = status .. " Prepare a new Export if you need a backup file." end
  self:UpdateRaidLootStatus(status)
end

function APOCLootPrio:SetCloseLootSessionConfirmShown(enabled)
  if enabled and not self:RequireLootTrackerEdit() then return false end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.closeSessionConfirm then return false end
  local panel = self.frame.raidLootPanel.closeSessionConfirm
  if enabled then
    local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
    local session = self:GetRaidLootSession(trackerRaid)
    if not session or not session.key or session.readOnly then
      self:UpdateRaidLootStatus("There is no active loot session to close.")
      return false
    end
    if session.finalized then
      self:UpdateRaidLootStatus("This session is already closed and saved.")
      return false
    end
    local summary = self:GetRaidLootSummaryForSession(session)
    if session.archived then
      panel.title:SetText("Close saved history raid?")
      panel.save:SetText("Mark Closed")
      panel.message:SetText("Mark " .. self:GetLootSessionDisplayName(session) .. " closed?\n"
        .. tostring(summary.total or 0) .. " drops and " .. tostring(summary.pending or 0)
        .. " unawarded items remain available for review and corrections. The original Run ID is kept.")
    else
      panel.title:SetText("Close & Save Session?")
      panel.save:SetText("Close & Save")
      panel.message:SetText("Close " .. self:GetLootSessionDisplayName(session) .. "?\n"
        .. tostring(summary.total or 0) .. " drops and " .. tostring(summary.pending or 0)
        .. " unawarded items will remain available for review and awards. New loot will stop being added.")
    end
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 36)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 26)
    panel:Show()
  else
    panel:Hide()
  end
  return true
end

function APOCLootPrio:ConfirmCloseAndSaveLootSession()
  if not self:RequireLootTrackerEdit() then return end
  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local session = self:GetRaidLootSession(trackerRaid)
  local saved, message = self:FinalizeLootSession(session and session.key)
  if not saved then
    self:UpdateRaidLootStatus(message or "Could not close and save this session.")
    return
  end
  self:SetCloseLootSessionConfirmShown(false)
  self:RefreshRaidLootPanel()
  self:RefreshLootSessionPicker()
  self:RefreshAttendancePanel()
  self:UpdateRaidLootStatus("Closed & Saved. Awards remain editable; use /reload or log out to write SavedVariables to disk now.")
end

function APOCLootPrio:ConfirmStartNewRaidLootSession()
  local instanceName = self.pendingInstanceSessionPrompt
  self:SetNewLootSessionConfirmShown(false)
  self:StartNewRaidLootSession(instanceName)
end

function APOCLootPrio:StartNewRaidLootSession(initialInstance)
  if not self:RequireLootTrackerEdit() then return end

  local session, message = self:StartRaidLootSession(nil, initialInstance)
  if not session then
    self:UpdateRaidLootStatus(message or "Could not start a new loot session.")
    return
  end
  self.selectedLootDropID = nil
  self.selectedRaidLootItem = nil
  self:RefreshRaidLootPanel()
  self:UpdateRaidLootStatus("Started " .. self:GetLootSessionDisplayName(session) .. ".")
end

function APOCLootPrio:RefreshRaidLootPanel()
  if not self.frame or not self.frame.raidLootPanel then return end
  self:InitDB()

  local panel = self.frame.raidLootPanel
  self:LayoutRaidLootPanel()
  local canEdit = self:CanEditLootTracker()
  local canView = self:CanViewLootTracker()

  ApplyLootTrackerAccess(panel)
  if not canView then return end

  if self.attendancePanelShown then
    self:RefreshAttendancePanel()
  end
  if self.lootDisenchanterPickerShown then
    self:RefreshLootDisenchanterPicker()
  end

  local trackerRaid = self.selectedLootTrackerRaid or self.selectedRaid
  local session = self:GetRaidLootSession(trackerRaid)
  local summary = self:GetRaidLootSummary(trackerRaid)

  local historyEdit = self.IsHistoryEditContext and self:IsHistoryEditContext() and self:CanEditGuildRaidHistory()
  local sessionState = ""
  if historyEdit then
    sessionState = " - History edit"
  elseif session.archived then
    sessionState = " - Guild Raid History"
  elseif session.finalized then
    sessionState = " - Closed & Saved"
  end
  local sessionLine = self:GetLootSessionDisplayName(session) .. sessionState .. " - " .. tostring(summary.total) .. " drops, " .. tostring(summary.pending) .. " unawarded"
  local materials = self.FormatRaidMaterialSummary and self:FormatRaidMaterialSummary(summary) or ""
  if materials ~= "" then sessionLine = sessionLine .. " · " .. materials end
  panel.session:SetText(sessionLine)

  local runnerHealth = self.GetMultiRunRunnerHealth and self:GetMultiRunRunnerHealth() or "active"
  local runnerMlWarn = self.GetRunnerMasterLooterWarningText and self:GetRunnerMasterLooterWarningText() or nil
  if historyEdit then
    panel.selectedItem:SetText("History edit (ranks 0–2). Awards, notes, and corrections sync to officer peers.")
  elseif session.finalized then
    panel.selectedItem:SetText("Closed & Saved. New loot capture is off; existing awards remain editable.")
  elseif canEdit and (runnerHealth == "offline" or runnerHealth == "missing") then
    if self.IsMasterLooter and self:IsMasterLooter() then
      panel.selectedItem:SetText("|cffff4040No live run yet.|r You are master looter. Reopen Loot Tracker to start it.")
    else
      panel.selectedItem:SetText("|cffff4040No live run yet.|r The Master Looter must open Loot Tracker and have the bridge running.")
    end
  elseif runnerMlWarn then
    panel.selectedItem:SetText("|cffff8040" .. runnerMlWarn .. "|r")
  elseif self.selectedRaidLootItem and canEdit then
    panel.selectedItem:SetText("Staged: " .. (self.selectedRaidLootItem.name or "Unknown item") .. " - " .. (self.selectedRaidLootBoss or "Unknown boss"))
  elseif not canEdit then
    self.selectedRaidLootItem = nil
    self.selectedRaidLootBoss = nil
    panel.selectedItem:SetText(self:GetLootTrackerAccessText())
  else
    local autoMode = self.GetLootAutoTrackMode and self:GetLootAutoTrackMode() or "raid"
    local autoModeLabel = self.GetLootAutoTrackModeLabel and self:GetLootAutoTrackModeLabel(autoMode) or "Raid"
    if autoMode == "off" then
      panel.selectedItem:SetText("Auto Track is Off. Click an item as a manual fallback.")
    else
      panel.selectedItem:SetText("Auto Track: " .. autoModeLabel .. ". Click an item as a manual fallback.")
    end
  end

  if panel.trackerRunner then
    if self.ClaimLocalNamedRunner then self:ClaimLocalNamedRunner() end
    local trackerOwner = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or self:GetLootTrackerOwner()
    local runSuffix = self.GetRunShortID and (" | Run " .. self:GetRunShortID()) or ""
    local health = self.GetMultiRunRunnerHealth and self:GetMultiRunRunnerHealth() or "active"
    local healthSuffix = health == "offline" and " | |cffff4040OFFLINE|r"
      or health == "missing" and " | |cffff4040NO RUNNER|r"
      or health == "waiting" and " | |cffffd100Connecting|r"
      or " | |cff40ff40Active|r"
    local watchSuffix = (self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly()) and " | |cffbbbbbbWATCH|r" or ""
    if (not self.GetActiveRunID or not self:GetActiveRunID()) and health == "missing" then
      panel.trackerRunner:SetText("|cffff4040No live run|r")
    elseif trackerOwner and trackerOwner ~= "" then
      local suffix = self:IsLootTrackerOwner() and " (you)" or ""
      panel.trackerRunner:SetText("Master Looter: " .. (ShortDisplayName(trackerOwner) or trackerOwner) .. suffix .. healthSuffix .. watchSuffix .. runSuffix)
    else
      local authority = self.GetLootSyncAuthorityName and self:GetLootSyncAuthorityName() or nil
      local autoName = authority and authority ~= "" and (" (" .. (ShortDisplayName(authority) or authority) .. ")") or ""
      panel.trackerRunner:SetText("Master Looter: Not detected" .. healthSuffix .. watchSuffix .. runSuffix)
    end
    if runnerMlWarn then
      panel.trackerRunner:SetTextColor(1, .5, .25)
    else
      panel.trackerRunner:SetTextColor(.9, .84, .72)
    end
  end
  -- Set runner to ML is redundant with hard ML→runner auto-follow; keep hidden.
  if panel.setRunnerToML then
    panel.setRunnerToML:Hide()
    if panel.trackerRunner then
      panel.trackerRunner:ClearAllPoints()
      panel.trackerRunner:SetPoint("TOPRIGHT", -18, -34)
      panel.trackerRunner:SetJustifyH("RIGHT")
      if panel.trackerRunner.SetWordWrap then panel.trackerRunner:SetWordWrap(false) end
    end
  end
  if panel.liveRaidsButton then
    panel.liveRaidsButton:SetText(self.liveRaidsPanelShown and "Live: On" or "Live Raids")
  end
  if panel.getListButton then
    local isRunner = self.CanEditLootTracker and self:CanEditLootTracker()
    panel.getListButton:SetText(isRunner and "Share List" or "Get List")
  end

  for _, child in ipairs({panel.queueList:GetChildren()}) do
    child:Hide()
    child:SetParent(nil)
  end

  local columnGap = 12
  local queueWidth = panel.queueList and panel.queueList.GetWidth and panel.queueList:GetWidth() or (RAID_LOOT_WINDOW_WIDTH - 38)
  local queueHeight = panel.queueList and panel.queueList.GetHeight and panel.queueList:GetHeight() or LOOT_TRACKER_LIST_HEIGHT
  local columnWidth = math.floor((queueWidth - columnGap) / 2)
  local pendingList = CreateFrame("Frame", nil, panel.queueList)
  pendingList:SetSize(columnWidth, queueHeight)
  pendingList:SetPoint("TOPLEFT", 0, 0)

  local awardedList = CreateFrame("Frame", nil, panel.queueList)
  awardedList:SetSize(columnWidth, queueHeight)
  awardedList:SetPoint("TOPLEFT", columnWidth + columnGap, 0)

  local pendingTitle = Font(pendingList, 10, "Dropped queue", "GameFontHighlight")
  pendingTitle:SetPoint("TOPLEFT", 0, 0)
  pendingTitle:SetPoint("TOPRIGHT", 0, 0)
  pendingTitle:SetJustifyH("CENTER")
  pendingTitle:SetTextColor(1, .85, .2)

  local awardedTitle = Font(awardedList, 10, "Awarded loot", "GameFontHighlight")
  awardedTitle:SetPoint("TOPLEFT", 0, 0)
  awardedTitle:SetPoint("TOPRIGHT", 0, 0)
  awardedTitle:SetJustifyH("CENTER")
  awardedTitle:SetTextColor(1, .85, .2)

  local pendingLine = pendingList:CreateTexture(nil, "BACKGROUND")
  pendingLine:SetPoint("TOPLEFT", 0, -18)
  pendingLine:SetSize(columnWidth, 1)
  SetTextureColor(pendingLine, .45, .30, .10, .85)

  local awardedLine = awardedList:CreateTexture(nil, "BACKGROUND")
  awardedLine:SetPoint("TOPLEFT", 0, -18)
  awardedLine:SetSize(columnWidth, 1)
  SetTextureColor(awardedLine, .45, .30, .10, .85)

  local function UpdateLootColumnScrollBar(scroll)
    if not scroll or not scroll.apocScrollTrack or not scroll.apocScrollThumb then return end

    local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
    if range <= 1 then
      scroll.apocScrollTrack:Hide()
      scroll.apocScrollThumb:Hide()
      return
    end

    local trackHeight = scroll.apocScrollTrack:GetHeight() or 0
    local viewHeight = scroll:GetHeight() or 0
    if trackHeight <= 1 then trackHeight = viewHeight end
    if viewHeight <= 1 or trackHeight <= 1 then return end

    local childHeight = viewHeight + range
    local thumbHeight = math.floor(trackHeight * (viewHeight / childHeight))
    if thumbHeight < 24 then thumbHeight = 24 end
    if thumbHeight > trackHeight then thumbHeight = trackHeight end

    local current = scroll:GetVerticalScroll() or 0
    local travel = trackHeight - thumbHeight
    local offset = 0
    if range > 0 and travel > 0 then
      offset = (current / range) * travel
    end

    scroll.apocScrollTrack:Show()
    scroll.apocScrollThumb:Show()
    scroll.apocScrollThumb:ClearAllPoints()
    scroll.apocScrollThumb:SetPoint("TOP", scroll.apocScrollTrack, "TOP", 0, -offset)
    scroll.apocScrollThumb:SetHeight(thumbHeight)
  end

  local function CreateLootColumnScroll(container)
    local scroll = CreateFrame("ScrollFrame", nil, container)
    scroll:SetPoint("TOPLEFT", 0, -24)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    EnableCleanMouseWheelScroll(scroll, DROP_QUEUE_ROW_HEIGHT)

    local track = container:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", container, "TOPRIGHT", -3, -26)
    track:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -3, 2)
    track:SetWidth(4)
    SetTextureColor(track, .30, .22, .10, .55)
    track:Hide()

    local thumb = container:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    SetTextureColor(thumb, .95, .70, .18, .95)
    thumb:Hide()

    local content = CreateFrame("Frame", nil, scroll)
    content.rowWidth = columnWidth - 18
    content:SetSize(content.rowWidth, 1)
    scroll:SetScrollChild(content)
    scroll.apocScrollTrack = track
    scroll.apocScrollThumb = thumb
    scroll.UpdateAPOCScrollBar = UpdateLootColumnScrollBar
    if scroll.HookScript then
      scroll:HookScript("OnScrollRangeChanged", function(frame) frame:UpdateAPOCScrollBar() end)
      scroll:HookScript("OnVerticalScroll", function(frame) frame:UpdateAPOCScrollBar() end)
      scroll:HookScript("OnSizeChanged", function(frame) frame:UpdateAPOCScrollBar() end)
    end

    return scroll, content
  end

  local pendingScroll, pendingContent = CreateLootColumnScroll(pendingList)
  local awardedScroll, awardedContent = CreateLootColumnScroll(awardedList)
  pendingContent.bossGrouped = true
  awardedContent.bossGrouped = true
  local pendingY = 0
  local awardedY = 0
  local pendingShown = 0
  local awardedShown = 0
  local pendingDrops = {}
  local awardedDrops = {}
  self.lootBossCollapseState = self.lootBossCollapseState or {}
  local collapseSessionKey = tostring(session.key or trackerRaid or "current")
  for _, drop in ipairs(session.drops or {}) do
    if drop.award and ((drop.award.winner and drop.award.winner ~= "") or self:GetAwardType(drop) == "GB") then
      table.insert(awardedDrops, drop)
    else
      table.insert(pendingDrops, drop)
    end
  end

  local function RenderBossGroups(content, drops, y, awarded)
    local shown = 0
    for _, group in ipairs(GroupLootDropsByBoss(drops)) do
      local columnKey = awarded and "awarded" or "pending"
      local collapseKey = collapseSessionKey .. "|" .. columnKey .. "|" .. group.key
      local collapsed = self.lootBossCollapseState[collapseKey] == true
      CreateLootBossHeader(content, y, group.label, #group.drops, collapsed, function()
        self.lootBossCollapseState[collapseKey] = not collapsed
        self:RefreshRaidLootPanel()
      end)
      y = y - LOOT_BOSS_HEADER_HEIGHT - 2
      shown = shown + #group.drops
      if not collapsed then
        for _, drop in ipairs(group.drops) do
          local dropID = drop.id
          CreateDropQueueRow(
            content,
            y,
            drop,
            function() APOCLootPrio:SelectRaidLootDrop(dropID) end,
            awarded
              and function() APOCLootPrio:UnawardSelectedRaidLootDrop(dropID) end
              or function() APOCLootPrio:DeleteSelectedRaidLootDrop(dropID) end,
            drop.id == self.selectedLootDropID,
            canEdit,
            awarded and "Unaward" or "Del"
          )
          y = y - DROP_QUEUE_ROW_HEIGHT - 2
        end
      end
      y = y - 4
    end
    return y, shown
  end

  pendingY, pendingShown = RenderBossGroups(pendingContent, pendingDrops, pendingY, false)
  awardedY, awardedShown = RenderBossGroups(awardedContent, awardedDrops, awardedY, true)

  if pendingShown == 0 then
    CreateSideRow(pendingContent, pendingY, "No unawarded drops.", function() end, false)
    pendingY = pendingY - SIDE_ROW_HEIGHT - 2
  end

  if awardedShown == 0 then
    CreateSideRow(awardedContent, awardedY, "No awarded loot yet.", function() end, false)
    awardedY = awardedY - SIDE_ROW_HEIGHT - 2
  end

  pendingContent:SetHeight(math.max(1, math.abs(pendingY) + 4))
  awardedContent:SetHeight(math.max(1, math.abs(awardedY) + 4))
  if pendingScroll.UpdateScrollChildRect then
    pendingScroll:UpdateScrollChildRect()
  end
  if awardedScroll.UpdateScrollChildRect then
    awardedScroll:UpdateScrollChildRect()
  end
  if pendingScroll.UpdateAPOCScrollBar then
    pendingScroll:UpdateAPOCScrollBar()
  end
  if awardedScroll.UpdateAPOCScrollBar then
    awardedScroll:UpdateAPOCScrollBar()
  end

  local selectedDrop = self:FindRaidLootDrop(self.selectedLootDropID, trackerRaid)
  if selectedDrop then
    if panel.currentDropID ~= selectedDrop.id then
      panel.winner:SetText("")
      panel.selectedWinnerName = nil
      panel.note:SetText("")
      SetPanelAwardType(panel, "MS")
      panel.currentDropID = selectedDrop.id
    end
    panel.selectedDrop:SetText(selectedDrop.item or "Unknown item")
    panel.selectedDrop:SetTextColor(GetItemQualityRGB(DropAsItem(selectedDrop)))
    if panel.selectedDropIcon and panel.selectedDropIconTexture then
      panel.selectedDropIcon.drop = selectedDrop
      panel.selectedDropIcon.hasDrop = true
      SetCleanItemIcon(panel.selectedDropIconTexture, DropAsItem(selectedDrop))
      if canEdit then panel.selectedDropIcon:Show() end
    end
    if panel.selectedDropPrio then
      panel.selectedDropPrio:SetText("Loot prio: " .. ColorizePriorityText(selectedDrop.bias or "None"))
    end
    if panel.selectedDropRollButton then
      panel.selectedDropRollButton.drop = selectedDrop
      panel.selectedDropRollButton:SetText(GetLootRollButtonText(selectedDrop))
      SetControlEnabled(panel.selectedDropRollButton, canEdit and CanStartLootRollForDrop(selectedDrop))
    end
    if panel.selectedDropRollResultsButton then
      panel.selectedDropRollResultsButton.drop = selectedDrop
      SetControlEnabled(panel.selectedDropRollResultsButton, canEdit)
    end
    if panel.selectedDropRollResetButton then
      panel.selectedDropRollResetButton.drop = selectedDrop
      SetControlEnabled(panel.selectedDropRollResetButton, canEdit)
    end
    if panel.selectedDropRollResult then
      RefreshSelectedDropRollDisplay(panel, selectedDrop)
    end
    if selectedDrop.award and ((selectedDrop.award.winner and selectedDrop.award.winner ~= "") or self:GetAwardType(selectedDrop) == "GB") then
      panel.selectedWinnerName = selectedDrop.award.winner or ""
      panel.note:SetText(selectedDrop.award.note or "")
      SetPanelAwardType(panel, self:GetAwardType(selectedDrop))
      panel.award:SetText("Update Award")
    else
      panel.award:SetText("Save Award")
    end
  else
    panel.currentDropID = nil
    panel.selectedDrop:SetText("Select a drop from the queue.")
    panel.selectedDrop:SetTextColor(.9, .84, .72)
    if panel.selectedDropIcon then
      panel.selectedDropIcon.drop = nil
      panel.selectedDropIcon.hasDrop = false
      panel.selectedDropIcon:Hide()
    end
    if panel.selectedDropRollButton then
      panel.selectedDropRollButton.drop = nil
      panel.selectedDropRollButton:SetText("Roll")
      SetControlEnabled(panel.selectedDropRollButton, false)
    end
    if panel.selectedDropRollResultsButton then
      panel.selectedDropRollResultsButton.drop = nil
      panel.selectedDropRollResultsButton:SetText("Results")
      SetControlEnabled(panel.selectedDropRollResultsButton, false)
    end
    if panel.selectedDropRollResetButton then
      panel.selectedDropRollResetButton.drop = nil
      SetControlEnabled(panel.selectedDropRollResetButton, false)
    end
    if panel.selectedDropRollResult then
      panel.selectedDropRollResult:SetText("")
    end
    if panel.selectedDropPrio then panel.selectedDropPrio:SetText("") end
    panel.selectedWinnerName = nil
    SetPanelAwardType(panel, "MS")
    panel.award:SetText("Save Award")
  end

  self:RefreshGroupMemberList()

  local awardsPanel = panel.recentAwardsPanel
  local awardsContent = awardsPanel and awardsPanel.content
  if awardsContent then
    ClearFrameChildren(awardsContent)
  end
  if not awardsContent then return end

  local awardY = 0
  local awardCount = 0
  for _, drop in ipairs(session.drops or {}) do
    if drop.award and ((drop.award.winner and drop.award.winner ~= "") or self:GetAwardType(drop) == "GB") then
      awardCount = awardCount + 1
      local dropID = drop.id
      CreateAwardLedgerRow(
        awardsContent,
        awardY,
        drop,
        function()
          if APOCLootPrio:CanEditLootTracker() then
            APOCLootPrio:SelectRecentAwardDrop(dropID)
          else
            APOCLootPrio:UpdateRaidLootStatus("Officer view: awarded loot is read-only.")
          end
        end,
        dropID and dropID == self.selectedRecentAwardDropID
      )
      awardY = awardY - AWARD_LEDGER_ROW_HEIGHT - 2
    end
  end

  if awardCount == 0 then
    local empty = Font(awardsContent, 10, "No awards yet.", "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT", 2, -2)
    empty:SetPoint("RIGHT", -8, 0)
    empty:SetJustifyH("LEFT")
    empty:SetTextColor(.78, .78, .78)
    awardY = -20
  end

  if awardsPanel and awardsPanel.summary then
    awardsPanel.summary:SetText(tostring(awardCount) .. " awards in this session")
  end

  if awardsContent then
    awardsContent:SetHeight(math.max(1, -awardY + 4))
  end

  if awardsPanel and awardsPanel.scroll and awardsPanel.scroll.UpdateScrollChildRect then
    awardsPanel.scroll:UpdateScrollChildRect()
  end
  StyleAPOCFrameTree(panel)
end

function APOCLootPrio:SetLogPanelShown(enabled)
  if enabled and not self:CanViewFeature("log") then
    self.logPanelShown = false
    self:Print("Admin log is not available for your guild rank.")
    return
  end

  self.logPanelShown = enabled and true or false
  if not self.frame then return end

  if self.frame.logPanel then
    if self.logPanelShown then
      SetAddonFrameLayer(self.frame.logPanel, ADDON_FRAME_LEVEL - 1)
      AnimateLogPanel(self.frame.logPanel, true)
    else
      if self.frame.logPanel:IsShown() then
        AnimateLogPanel(self.frame.logPanel, false)
      else
        self.frame.logPanel:SetScript("OnUpdate", nil)
        SetLogPanelOffset(self.frame.logPanel, -LOG_PANEL_WIDTH)
        self.frame.logPanel:Hide()
      end
    end
  end

  if self.frame.logButton then
    self.frame.logButton:SetText("Log")
  end

  self:RefreshAuditLog()
  self:RefreshTopButtonStates()
end

function APOCLootPrio:ToggleLogPanel()
  self:SetLogPanelShown(not self.logPanelShown)
end

function APOCLootPrio:RefreshAttendancePanel()
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.attendancePanel then return end
  local panel = self.frame.raidLootPanel.attendancePanel
  local session = self:GetRaidLootSession(self.selectedLootTrackerRaid or self.selectedRaid)
  local attendance = session and session.attendance or nil
  local content = panel.content
  ClearFrameChildren(content)

  panel.session:SetText(session and self:GetLootSessionDisplayName(session) or "No active session")
  local entries = {}
  local uniqueCount = 0
  local presentCount = 0
  for _, member in pairs(attendance and attendance.members or {}) do
    uniqueCount = uniqueCount + 1
    if member.present then presentCount = presentCount + 1 end
    if #(member.visits or {}) == 0 then
      table.insert(entries, {member = member, visit = {joinedAt = member.firstJoinedAt or 0}, visitIndex = 1})
    else
      for visitIndex, visit in ipairs(member.visits or {}) do
        table.insert(entries, {member = member, visit = visit, visitIndex = visitIndex})
      end
    end
  end

  table.sort(entries, function(a, b)
    local aJoin = tonumber(a.visit and a.visit.joinedAt) or 0
    local bJoin = tonumber(b.visit and b.visit.joinedAt) or 0
    if aJoin ~= bJoin then return aJoin < bJoin end
    local aName = string.lower(tostring(a.member and a.member.name or ""))
    local bName = string.lower(tostring(b.member and b.member.name or ""))
    if aName ~= bName then return aName < bName end
    return (a.visitIndex or 0) < (b.visitIndex or 0)
  end)

  local y = 0
  for index, entry in ipairs(entries) do
    local member = entry.member or {}
    local visit = entry.visit or {}
    local isPresent = member.present and not visit.leftAt and entry.visitIndex == #(member.visits or {})
    local row = CreateFrame("Frame", nil, content)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(536, 38)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    if isPresent then SetTextureColor(bg, .06, .16, .08, .82)
    elseif index % 2 == 0 then SetTextureColor(bg, .08, .07, .05, .72)
    else SetTextureColor(bg, .05, .05, .05, .72) end

    local name = Font(row, 10, member.name or "Unknown", "GameFontNormal")
    name:SetPoint("TOPLEFT", 10, -5)
    name:SetSize(195, 15)
    name:SetJustifyH("LEFT")
    name:SetTextColor(GetPlayerClassRGB(member))

    local details = member.className and member.className ~= "" and member.className or "Raid member"
    if (member.subgroup or 0) > 0 then details = details .. " - Group " .. tostring(member.subgroup) end
    if #(member.visits or {}) > 1 then details = details .. " - Visit " .. tostring(entry.visitIndex) end
    local meta = Font(row, 8, details, "GameFontNormalSmall")
    meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    meta:SetSize(195, 12)
    meta:SetJustifyH("LEFT")
    meta:SetTextColor(.66, .62, .54)

    local joined = Font(row, 10, self:FormatAttendanceTime(visit.joinedAt), "GameFontNormalSmall")
    joined:SetPoint("LEFT", 220, 0)
    joined:SetSize(130, 18)
    joined:SetJustifyH("LEFT")
    joined:SetTextColor(.9, .84, .72)

    local leftText = isPresent and "Present" or self:FormatAttendanceTime(visit.leftAt or member.lastLeftAt)
    local left = Font(row, 10, leftText, "GameFontNormalSmall")
    left:SetPoint("LEFT", 370, 0)
    left:SetSize(145, 18)
    left:SetJustifyH("LEFT")
    if isPresent then left:SetTextColor(.3, 1, .3) else left:SetTextColor(.9, .84, .72) end

    y = y - 40
  end

  if #entries == 0 then
    local empty = Font(content, 11, "No raid members have been recorded in this session yet.", "GameFontNormal")
    empty:SetPoint("TOPLEFT", 10, -10)
    empty:SetTextColor(.72, .72, .72)
    y = -40
  end

  content:SetHeight(math.max(1, -y + 4))
  if panel.scroll and panel.scroll.UpdateScrollChildRect then panel.scroll:UpdateScrollChildRect() end
  if attendance and attendance.tracking then
    panel.status:SetText(tostring(presentCount) .. " currently present - " .. tostring(uniqueCount) .. " unique raid members recorded")
  else
    panel.status:SetText(tostring(uniqueCount) .. " unique raid members recorded - attendance tracking closed")
  end
end

function APOCLootPrio:SetAttendancePanelShown(enabled)
  if enabled and not self:CanViewLootTracker() then
    self.attendancePanelShown = false
    return
  end
  if not self.frame or not self.frame.raidLootPanel or not self.frame.raidLootPanel.attendancePanel then return end
  local panel = self.frame.raidLootPanel.attendancePanel
  self.attendancePanelShown = enabled and true or false

  if self.attendancePanelShown then
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame.raidLootPanel, "CENTER", 0, 42)
    SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 18)
    panel:Show()
    self:RefreshAttendancePanel()
  else
    panel:Hide()
  end
  if self.frame.raidLootPanel.attendanceButton then
    self.frame.raidLootPanel.attendanceButton:SetText(self.attendancePanelShown and "Attendance: On" or "Attendance")
  end
end

function APOCLootPrio:ToggleAttendancePanel()
  self:SetAttendancePanelShown(not self.attendancePanelShown)
end

function APOCLootPrio:SetRecentAwardsPanelShown(enabled)
  self.recentAwardsPanelShown = enabled and true or false
  if not self.frame or not self.frame.raidLootPanel then return end

  local panel = self.frame.raidLootPanel.recentAwardsPanel
  if panel then
    if self.recentAwardsPanelShown then
      SetAddonFrameLayer(panel, ADDON_FRAME_LEVEL + 9)
      AnimateLogPanel(panel, true)
    else
      if panel:IsShown() then
        AnimateLogPanel(panel, false)
      else
        panel:SetScript("OnUpdate", nil)
        SetLogPanelOffset(panel, -RECENT_AWARDS_PANEL_WIDTH)
        panel:Hide()
      end
      self.selectedRecentAwardDropID = nil
      SetRecentAwardsEditorShown(panel, false)
    end
  end

  if self.frame.raidLootPanel.awardsButton then
    self.frame.raidLootPanel.awardsButton:SetText(self.recentAwardsPanelShown and "Awards: On" or "Awards")
  end

  self:RefreshRaidLootPanel()
end

function APOCLootPrio:ToggleRecentAwardsPanel()
  self:SetRecentAwardsPanelShown(not self.recentAwardsPanelShown)
end

function APOCLootPrio:SetRaidLootPanelShown(enabled)
  if enabled and not self:CanViewLootTracker() then
    self.raidLootPanelShown = false
    self:Print("Loot Tracker is not available for your guild rank.")
    return
  end

  self.raidLootPanelShown = enabled and true or false
  if not self.frame then return end

  if self.frame.raidLootPanel then
    if self.raidLootPanelShown then
      SetAddonFrameLayer(self.frame.raidLootPanel, ADDON_FRAME_LEVEL + 10)
      self.frame.raidLootPanel:Show()
      if self.AnnounceLocalLiveRaid then self:AnnounceLocalLiveRaid("loot-panel") end
    else
      self.recentAwardsPanelShown = false
      self.attendancePanelShown = false
      if self.frame.raidLootPanel.attendancePanel then
        self.frame.raidLootPanel.attendancePanel:Hide()
      end
      if self.frame.raidLootPanel.attendanceButton then
        self.frame.raidLootPanel.attendanceButton:SetText("Attendance")
      end
      if self.frame.raidLootPanel.recentAwardsPanel then
        self.frame.raidLootPanel.recentAwardsPanel:SetScript("OnUpdate", nil)
        SetLogPanelOffset(self.frame.raidLootPanel.recentAwardsPanel, -RECENT_AWARDS_PANEL_WIDTH)
        SetRecentAwardsEditorShown(self.frame.raidLootPanel.recentAwardsPanel, false)
        self.frame.raidLootPanel.recentAwardsPanel:Hide()
      end
      self.selectedRecentAwardDropID = nil
      if self.frame.raidLootPanel.awardsButton then
        self.frame.raidLootPanel.awardsButton:SetText("Awards")
      end
      if self.frame.raidLootPanel.manualPicker then
        self.frame.raidLootPanel.manualPicker:Hide()
        self.manualLootPickerShown = false
      end
      if self.frame.raidLootPanel.runnerPicker then
        self.frame.raidLootPanel.runnerPicker:Hide()
        self.lootTrackerRunnerPickerShown = false
      end
      if self.frame.raidLootPanel.disenchanterPicker then
        self.frame.raidLootPanel.disenchanterPicker:Hide()
        self.lootDisenchanterPickerShown = false
      end
      if self.frame.raidLootPanel.sessionPicker then
        self.frame.raidLootPanel.sessionPicker:Hide()
      end
      if self.frame.raidLootPanel.sessionDeleteConfirm then
        self.frame.raidLootPanel.sessionDeleteConfirm:Hide()
        self.pendingDeleteLootSessionKey = nil
      end
      if self.frame.raidLootPanel.newSessionConfirm then
        self.frame.raidLootPanel.newSessionConfirm:Hide()
      end
      if self.frame.raidLootPanel.renameSessionPrompt then
        self.frame.raidLootPanel.renameSessionPrompt.input:ClearFocus()
        self.frame.raidLootPanel.renameSessionPrompt:Hide()
        self.pendingRenameLootSessionKey = nil
      end
      if self.frame.raidLootPanel.closeSessionConfirm then
        self.frame.raidLootPanel.closeSessionConfirm:Hide()
      end
      if self.frame.raidLootPanel.trackerSettingsPanel then
        self.frame.raidLootPanel.trackerSettingsPanel:Hide()
        self.lootTrackerSettingsPanelShown = false
        if self.frame.raidLootPanel.trackerSettings then self.frame.raidLootPanel.trackerSettings:SetText("Settings") end
      end
      if self.frame.raidLootPanel.syncedClientsPanel then
        self.frame.raidLootPanel.syncedClientsPanel:Hide()
        self.syncedClientsPanelShown = false
        if self.frame.raidLootPanel.syncedClients then self.frame.raidLootPanel.syncedClients:SetText("Synced") end
      end
      if self.frame.raidLootPanel.lootRollResultsPanel then
        if self.frame.raidLootPanel.lootRollResultsPanel.awardPrompt then
          self.frame.raidLootPanel.lootRollResultsPanel.awardPrompt:Hide()
        end
        if self.frame.raidLootPanel.lootRollResultsPanel.resetPrompt then
          self.frame.raidLootPanel.lootRollResultsPanel.resetPrompt:Hide()
        end
        self.frame.raidLootPanel.lootRollResultsPanel:Hide()
        self.lootRollResultsPanelShown = false
        self.pendingRollAwardDropID = nil
        self.pendingRollAwardSourceDropID = nil
        self.pendingRollAwardWinner = nil
        self.pendingRollAwardRollType = nil
        self.pendingRollResetDropID = nil
        self.pendingRollResetRaid = nil
      end
      self.frame.raidLootPanel:Hide()
    end
  end

  if self.frame.raidLootButton then
    self.frame.raidLootButton:SetText("Loot Tracker")
  end

  self:RefreshRaidLootPanel()
  self:RefreshTopButtonStates()
end

function APOCLootPrio:ToggleRaidLootPanel()
  self:SetRaidLootPanelShown(not self.raidLootPanelShown)
end

function APOCLootPrio:UpdateGuildLootEditStatus(text)
  if self.frame and self.frame.guildLootPanel and self.frame.guildLootPanel.editStatus then
    self.frame.guildLootPanel.editStatus:SetText(text or "")
  end
end

function APOCLootPrio:SetGuildLootEditorShown(enabled)
  if not self.frame or not self.frame.guildLootPanel then return end
  local panel = self.frame.guildLootPanel

  if panel.editPopup then
    if enabled then
      panel.editPopup:Show()
    else
      panel.editPopup:Hide()
    end
  end
end

function APOCLootPrio:ClearGuildLootAwardEdit()
  self.selectedGuildLootDropID = nil
  if not self.frame or not self.frame.guildLootPanel then return end

  local panel = self.frame.guildLootPanel
  panel.currentGuildLootDropID = nil
  panel.selectedAward:SetText("Select a loot row to edit or delete.")
  panel.editWinner:SetText("")
  panel.editNote:SetText("")
  SetPanelAwardType(panel, "MS")
  self:SetGuildLootEditorShown(false)
end

function APOCLootPrio:SelectGuildLootAward(dropID)
  if not self.frame or not self.frame.guildLootPanel then return end
  if not self:CanManageSettings() then
    self:UpdateGuildLootEditStatus("Officer view: guild loot stats are read-only.")
    return
  end

  local drop = self:FindRaidLootDrop(dropID)
  if not drop or not drop.award then
    self:UpdateGuildLootEditStatus("Could not find that saved award.")
    return
  end

  self.selectedGuildLootDropID = dropID
  local panel = self.frame.guildLootPanel
  panel.currentGuildLootDropID = dropID
  panel.selectedAward:SetText((drop.item or "Unknown item") .. " - " .. (drop.raid or "Loot") .. " / " .. (drop.boss or "Unknown"))
  panel.editWinner:SetText(drop.award.winner or "")
  panel.editNote:SetText(drop.award.note or "")
  SetPanelAwardType(panel, self:GetAwardType(drop))
  self:SetGuildLootEditorShown(true)
  self:UpdateGuildLootEditStatus("Editing " .. (drop.item or "selected loot") .. ".")
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:SaveGuildLootAwardEdit()
  if not self.frame or not self.frame.guildLootPanel then return end
  if not self:CanManageSettings() then
    self:UpdateGuildLootEditStatus("Only the top two guild ranks can edit saved loot.")
    return
  end

  if not self.selectedGuildLootDropID then
    self:UpdateGuildLootEditStatus("Select a loot row first.")
    return
  end

  local panel = self.frame.guildLootPanel
  local winner = TrimText(panel.editWinner:GetText())
  local note = TrimText(panel.editNote:GetText())
  local drop, message = self:UpdateLootAward(self.selectedGuildLootDropID, winner, note, panel.awardType)

  if not drop then
    self:UpdateGuildLootEditStatus(message or "Could not save award.")
    return
  end

  self:UpdateGuildLootEditStatus("Saved " .. (drop.item or "loot") .. " for " .. winner .. ".")
  self:SetGuildLootEditorShown(false)
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:DeleteGuildLootAward(dropID)
  if not self:CanManageSettings() then
    self:UpdateGuildLootEditStatus("Only the top two guild ranks can delete saved loot.")
    return
  end

  local targetID = dropID or self.selectedGuildLootDropID
  if not targetID then
    self:UpdateGuildLootEditStatus("Select a loot row first.")
    return
  end

  local drop, message = self:DeleteRaidLootDrop(targetID)
  if not drop then
    self:UpdateGuildLootEditStatus(message or "Could not delete award.")
    return
  end

  if self.selectedGuildLootDropID == targetID then
    self:ClearGuildLootAwardEdit()
  end

  self:UpdateGuildLootEditStatus("Deleted " .. (drop.item or "loot") .. ".")
  self:RefreshRaidLootPanel()
  self:RefreshGuildLootPanel()
end

function APOCLootPrio:RefreshGuildLootPanel()
  if not self.frame or not self.frame.guildLootPanel then return end
  self:InitDB()

  local panel = self.frame.guildLootPanel
  local canEdit = self:CanManageSettings()
  SetControlEnabled(panel.saveAward, canEdit)
  SetControlEnabled(panel.deleteAward, canEdit)
  SetControlEnabled(panel.editWinner, canEdit)
  SetControlEnabled(panel.editNote, canEdit)
  if panel.awardTypeButtons then
    for _, button in pairs(panel.awardTypeButtons) do
      SetControlEnabled(button, canEdit)
    end
  end

  local content = panel.content
  ClearFrameRegions(content)
  for _, child in ipairs({content:GetChildren()}) do
    child:Hide()
    child:SetParent(nil)
  end

  local roster = self:GetGuildLootSummary()
  local totalWinners, totalMainSpec = 0, 0
  for _, player in ipairs(roster) do
    if (player.count or 0) > 0 then totalWinners = totalWinners + 1 end
    totalMainSpec = totalMainSpec + (player.count or 0)
  end

  local searchFilter = string.lower(TrimText(panel.search and panel.search:GetText() or ""))
  local classFilter = string.lower(TrimText(panel.classFilter and panel.classFilter:GetText() or ""))

  local filteredRoster = {}
  local shownMainSpec = 0
  for _, player in ipairs(roster) do
    local nameText = string.lower(player.name or "")
    local classText = string.lower((player.className or "") .. " " .. (player.classFileName or ""))
    local matchesSearch = searchFilter == "" or string.find(nameText, searchFilter, 1, true)
    local matchesClass = classFilter == "" or string.find(classText, classFilter, 1, true)

    if (player.count or 0) > 0 and matchesSearch and matchesClass then
      table.insert(filteredRoster, player)
      shownMainSpec = shownMainSpec + (player.count or 0)
    end
  end

  if (panel.sortMode or "name") == "rank" then
    table.sort(filteredRoster, function(a, b)
      local ar = a.rankIndex == nil and 999 or a.rankIndex
      local br = b.rankIndex == nil and 999 or b.rankIndex
      if ar ~= br then return ar < br end
      return (a.name or "") < (b.name or "")
    end)
  else
    table.sort(filteredRoster, function(a, b)
      return (a.name or "") < (b.name or "")
    end)
  end

  if panel.sortByName and panel.sortByRank then
    if (panel.sortMode or "name") == "rank" then
      panel.sortByRank:LockHighlight()
      panel.sortByName:UnlockHighlight()
    else
      panel.sortByName:LockHighlight()
      panel.sortByRank:UnlockHighlight()
    end
  end

  if searchFilter ~= "" or classFilter ~= "" then
    panel.status:SetText(tostring(#filteredRoster) .. " shown / " .. tostring(totalWinners) .. " winners - " .. tostring(shownMainSpec) .. " shown MS / " .. tostring(totalMainSpec) .. " total")
  else
    panel.status:SetText(tostring(#filteredRoster) .. " MS winners - " .. tostring(totalMainSpec) .. " lifetime MS awards")
  end

  if self.selectedGuildLootDropID then
    local selectedDrop = self:FindRaidLootDrop(self.selectedGuildLootDropID)
    if selectedDrop and selectedDrop.award then
      panel.selectedAward:SetText((selectedDrop.item or "Unknown item") .. " - " .. (selectedDrop.raid or "Loot") .. " / " .. (selectedDrop.boss or "Unknown"))
      if panel.currentGuildLootDropID ~= selectedDrop.id then
        panel.currentGuildLootDropID = selectedDrop.id
        panel.editWinner:SetText(selectedDrop.award.winner or "")
        panel.editNote:SetText(selectedDrop.award.note or "")
        SetPanelAwardType(panel, self:GetAwardType(selectedDrop))
      end
    else
      self:ClearGuildLootAwardEdit()
      self:UpdateGuildLootEditStatus("Selected award was deleted.")
    end
  end

  local y = -4
  for _, player in ipairs(filteredRoster) do
    y = y - CreateGuildWinnerRow(content, y, player, canEdit) - 6
  end

  if #filteredRoster == 0 then
    local emptyText = totalMainSpec == 0 and "No main-spec guild loot has been recorded yet." or "No MS winners match the current filters."
    local empty = Font(content, 12, emptyText, "GameFontNormal")
    empty:SetPoint("TOPLEFT", 8, y)
    empty:SetTextColor(.75, .75, .75)
    y = y - 28
  end

  content:SetHeight(math.max(1, -y + 18))
  if panel.scroll and panel.scroll.UpdateScrollChildRect then
    panel.scroll:UpdateScrollChildRect()
  end
end

function APOCLootPrio:SetGuildLootPanelShown(enabled)
  if enabled and not self:CanViewFeature("guildLoot") then
    self.guildLootPanelShown = false
    self:Print("Guild loot stats are not available for your guild rank.")
    return
  end

  self.guildLootPanelShown = enabled and true or false
  if not self.frame then return end

  if self.frame.guildLootPanel then
    if self.guildLootPanelShown then
      SetAddonFrameLayer(self.frame.guildLootPanel, ADDON_FRAME_LEVEL + 12)
      self.frame.guildLootPanel:Show()
    else
      self.frame.guildLootPanel:Hide()
    end
  end

  if self.frame.guildLootButton then
    self.frame.guildLootButton:SetText("Guild Loot")
  end

  self:RefreshGuildLootPanel()
  self:RefreshTopButtonStates()
end

function APOCLootPrio:ToggleGuildLootPanel()
  self:SetGuildLootPanelShown(not self.guildLootPanelShown)
end

function APOCLootPrio:RefreshOfficerControls()
  if not self.frame then return end

  local canViewAdmin = self:CanViewFeature("admin")
  local canViewLog = self:CanViewFeature("log")
  local canViewLootTracker = self:CanViewLootTracker()
  local canViewGuildLoot = self:CanViewFeature("guildLoot")
  local canManageSettings = self:CanManageSettings()

  if self.frame.headerStatus then
    local rankIndex = self:GetPlayerGuildRankIndex()
    local rankName = rankIndex ~= nil and self:GetGuildRankNameForIndex(rankIndex) or nil
    self.frame.headerStatus:SetText("Guild view" .. (rankIndex ~= nil and (" · Rank " .. tostring(rankIndex)) or "") .. (rankName and (" " .. rankName) or ""))
  end

  SetControlShown(self.frame.browserButton, true)
  SetControlShown(self.frame.adminButton, canViewAdmin)
  SetControlShown(self.frame.logButton, false)
  SetControlShown(self.frame.raidLootButton, canViewLootTracker)
  SetControlShown(self.frame.guildLootButton, canViewGuildLoot)
  SetControlShown(self.frame.settingsButton, canManageSettings)

  if not canViewAdmin then
    self.adminMode = false
    if self.frame.adminPanel then self.frame.adminPanel:Hide() end
  end

  if not canViewLog then
    self.logPanelShown = false
    if self.frame.logPanel then
      self.frame.logPanel:SetScript("OnUpdate", nil)
      SetLogPanelOffset(self.frame.logPanel, -LOG_PANEL_WIDTH)
      self.frame.logPanel:Hide()
    end
  end

  if not canViewLootTracker then
    self.raidLootPanelShown = false
    if self.frame.raidLootPanel then
      self.frame.raidLootPanel:Hide()
      if self.frame.raidLootPanel.recentAwardsPanel then
        self.frame.raidLootPanel.recentAwardsPanel:SetScript("OnUpdate", nil)
        SetLogPanelOffset(self.frame.raidLootPanel.recentAwardsPanel, -RECENT_AWARDS_PANEL_WIDTH)
        self.frame.raidLootPanel.recentAwardsPanel:Hide()
      end
    end
  end

  if not canViewGuildLoot then
    self.guildLootPanelShown = false
    if self.frame.guildLootPanel then self.frame.guildLootPanel:Hide() end
  end

  if not canManageSettings then
    self.settingsPanelShown = false
    if self.frame.settingsPanel then self.frame.settingsPanel:Hide() end
  end

  StyleAPOCFrameTree(self.frame)
  self:RefreshTopButtonStates()
end

function APOCLootPrio:RefreshTopButtonStates()
  if not self.frame then return end

  local browserActive = not self.adminMode and not self.raidLootPanelShown and not self.guildLootPanelShown and not self.settingsPanelShown
  SetAPOCButtonSelected(self.frame.browserButton, browserActive)
  SetAPOCButtonSelected(self.frame.raidLootButton, self.raidLootPanelShown)
  SetAPOCButtonSelected(self.frame.guildLootButton, self.guildLootPanelShown)
  SetAPOCButtonSelected(self.frame.adminButton, self.adminMode)
  SetAPOCButtonSelected(self.frame.settingsButton, self.settingsPanelShown)

  for _, button in ipairs(self.frame.tabs or {}) do
    SetAPOCButtonSelected(button, button.raid == self.selectedRaid)
  end
end

function APOCLootPrio:ShowLootBrowser()
  if not self.frame then return end

  self.adminMode = false
  self.logPanelShown = false
  self.raidLootPanelShown = false
  self.guildLootPanelShown = false
  self.settingsPanelShown = false
  self.recentAwardsPanelShown = false
  self.attendancePanelShown = false
  self.manualLootPickerShown = false
  self.lootTrackerRunnerPickerShown = false
  self.lootDisenchanterPickerShown = false
  self.lootTrackerSettingsPanelShown = false
  self.syncedClientsPanelShown = false
  self.pendingDeleteLootSessionKey = nil
  self.settingsPanelAnchor = nil

  if self.frame.adminPanel then self.frame.adminPanel:Hide() end
  if self.frame.logPanel then
    self.frame.logPanel:SetScript("OnUpdate", nil)
    SetLogPanelOffset(self.frame.logPanel, -LOG_PANEL_WIDTH)
    self.frame.logPanel:Hide()
  end
  if self.frame.raidLootPanel then
    if self.frame.raidLootPanel.recentAwardsPanel then
      self.frame.raidLootPanel.recentAwardsPanel:SetScript("OnUpdate", nil)
      SetLogPanelOffset(self.frame.raidLootPanel.recentAwardsPanel, -RECENT_AWARDS_PANEL_WIDTH)
      self.frame.raidLootPanel.recentAwardsPanel:Hide()
    end
    if self.frame.raidLootPanel.attendancePanel then self.frame.raidLootPanel.attendancePanel:Hide() end
    if self.frame.raidLootPanel.attendanceButton then self.frame.raidLootPanel.attendanceButton:SetText("Attendance") end
    if self.frame.raidLootPanel.manualPicker then self.frame.raidLootPanel.manualPicker:Hide() end
    if self.frame.raidLootPanel.runnerPicker then self.frame.raidLootPanel.runnerPicker:Hide() end
    if self.frame.raidLootPanel.disenchanterPicker then self.frame.raidLootPanel.disenchanterPicker:Hide() end
    if self.frame.raidLootPanel.sessionPicker then self.frame.raidLootPanel.sessionPicker:Hide() end
    if self.frame.raidLootPanel.sessionDeleteConfirm then self.frame.raidLootPanel.sessionDeleteConfirm:Hide() end
    if self.frame.raidLootPanel.newSessionConfirm then self.frame.raidLootPanel.newSessionConfirm:Hide() end
    if self.frame.raidLootPanel.renameSessionPrompt then
      self.frame.raidLootPanel.renameSessionPrompt.input:ClearFocus()
      self.frame.raidLootPanel.renameSessionPrompt:Hide()
      self.pendingRenameLootSessionKey = nil
    end
    if self.frame.raidLootPanel.trackerSettingsPanel then self.frame.raidLootPanel.trackerSettingsPanel:Hide() end
    if self.frame.raidLootPanel.syncedClientsPanel then self.frame.raidLootPanel.syncedClientsPanel:Hide() end
    self.frame.raidLootPanel:Hide()
  end
  if self.frame.guildLootPanel then self.frame.guildLootPanel:Hide() end
  if self.frame.settingsPanel then self.frame.settingsPanel:Hide() end

  self:RefreshTopButtonStates()
end

function APOCLootPrio:SetAdminMode(enabled)
  if enabled and not self:CanViewFeature("admin") then
    self.adminMode = false
    self:Print("Admin controls are not available for your guild rank.")
    return
  end

  self.adminMode = enabled and true or false
  if not self.frame then return end

  if self.frame.adminPanel then
    if self.adminMode then
      SetAddonFrameLayer(self.frame.adminPanel, ADDON_FRAME_LEVEL + 8)
      self.frame.adminPanel:Show()
    else
      self.frame.adminPanel:Hide()
    end
  end

  if self.frame.adminButton then
    self.frame.adminButton:SetText("Admin")
  end

  self:LayoutScroll()
  self:RefreshAuditLog()
  self:Refresh()
  self:RefreshTopButtonStates()

  if self.adminMode then
    if self:CanEditPriorities() then
      self:UpdateAdminStatus("Admin mode: item clicks select rows for editing.")
    else
      self:UpdateAdminStatus("Admin mode: view only. Saving requires guild leadership permission.")
    end
  end
end

function APOCLootPrio:ToggleAdminMode()
  if not self.frame then return end
  self:SetAdminMode(not self.adminMode)
end

function APOCLootPrio:RefreshSettingsPanel()
  if not self.frame or not self.frame.settingsPanel then return end

  local panel = self.frame.settingsPanel
  if panel.status then
    panel.status:SetText("Top two guild ranks can change feature visibility.")
  end

  for _, row in ipairs(panel.rows or {}) do
    if row.rank then
      row.rank:SetText(self:FormatFeatureAccessRank(row.featureKey))
    end
  end
end

function APOCLootPrio:SetSettingsPanelShown(enabled, anchorFrame, anchorName)
  if enabled and not self:CanManageSettings() then
    self.settingsPanelShown = false
    self:Print("Settings are available to the top two guild ranks only.")
    return
  end

  self.settingsPanelShown = enabled and true or false
  if not self.frame then return end

  if self.frame.settingsPanel then
    if self.settingsPanelShown then
      self.settingsPanelAnchor = anchorName
      self.frame.settingsPanel:ClearAllPoints()
      if anchorFrame then
        self.frame.settingsPanel:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", LOG_PANEL_GAP, 22)
      else
        self.frame.settingsPanel:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", LOG_PANEL_GAP, 22)
      end
      SetAddonFrameLayer(self.frame.settingsPanel, ADDON_FRAME_LEVEL + 14)
      self.frame.settingsPanel:Show()
    else
      self.settingsPanelAnchor = nil
      self.frame.settingsPanel:Hide()
    end
  end

  if self.frame.settingsButton then
    self.frame.settingsButton:SetText("Settings")
  end

  self:RefreshSettingsPanel()
  self:RefreshTopButtonStates()
end

function APOCLootPrio:ToggleSettingsPanel()
  local shouldShow = not self.settingsPanelShown or self.settingsPanelAnchor ~= "main"
  self:SetSettingsPanelShown(shouldShow, nil, "main")
end

function APOCLootPrio:AdjustFeatureAccessRank(feature, delta)
  local current = self:GetFeatureAccessRank(feature)
  local ok, message = self:SetFeatureAccessRank(feature, current + (delta or 0))
  if not ok then
    if self.frame and self.frame.settingsPanel and self.frame.settingsPanel.status then
      self.frame.settingsPanel.status:SetText(message or "Could not save setting.")
    else
      self:Print(message or "Could not save setting.")
    end
    return
  end

  self:RefreshSettingsPanel()
  self:RefreshOfficerControls()

  local entry = self:AddAuditEntry({
    text = self:GetPlayerDisplayName() .. " updated " .. self:GetFeatureLabel(feature) .. " access to " .. self:FormatFeatureAccessRank(feature) .. ".",
  })

  if self.BroadcastAccessSettings then self:BroadcastAccessSettings() end
  if self.BroadcastAuditEntry and entry then self:BroadcastAuditEntry(entry) end
  if self.RefreshAuditLog then self:RefreshAuditLog() end
  self:Print("Updated " .. self:GetFeatureLabel(feature) .. " access to " .. self:FormatFeatureAccessRank(feature) .. ".")
end

function APOCLootPrio:UpdateAdminStatus(text)
  if self.frame and self.frame.adminPanel and self.frame.adminPanel.status then
    self.frame.adminPanel.status:SetText(text or "")
  end
end

function APOCLootPrio:SelectAdminItem(item)
  if not self.frame or not self.frame.adminPanel then return end
  self.selectedAdminItem = item

  local panel = self.frame.adminPanel
  panel.itemName:SetText(item.name or "Unknown item")
  panel.bias:SetText(self:GetItemBias(item) or "")
  panel.note:SetText(self:GetItemNote(item) or "")
  if self:CanEditPriorities() then
    self:UpdateAdminStatus("Editing " .. (item.name or "selected item") .. ". Save broadcasts to synced leaders.")
  else
    self:UpdateAdminStatus("Viewing " .. (item.name or "selected item") .. ". Saving requires guild leadership permission.")
  end
end

function APOCLootPrio:SaveAdminItem()
  if not self.selectedAdminItem then
    self:UpdateAdminStatus("Select an item first.")
    return
  end

  if not self:CanEditPriorities() then
    self:UpdateAdminStatus("You do not have leadership edit permission.")
    return
  end

  local panel = self.frame.adminPanel
  local bias = TrimText(panel.bias:GetText())
  local note = TrimText(panel.note:GetText())
  panel.bias:SetText(bias)
  panel.note:SetText(note)

  local oldBias = self:GetItemBias(self.selectedAdminItem) or ""
  local oldNote = self:GetItemNote(self.selectedAdminItem) or ""

  if oldBias == bias and oldNote == note then
    local entry = self:RecordAdminSave(self.selectedAdminItem, oldBias, oldNote, bias, note, false, self:GetRevision())
    if self.BroadcastAuditEntry then self:BroadcastAuditEntry(entry) end
    self:UpdateAdminStatus("Logged no-change save for " .. (self.selectedAdminItem.name or "selected item") .. ".")
    self:RefreshAuditLog()
    self:SetAdminMode(false)
    return
  end

  local override = self:SetItemOverride(self.selectedAdminItem, bias, note)
  if not override then
    self:UpdateAdminStatus("Could not save this item.")
    return
  end

  local entry = self:RecordAdminSave(self.selectedAdminItem, oldBias, oldNote, bias, note, true, override.revision)
  if self.BroadcastItemOverride then self:BroadcastItemOverride(self.selectedAdminItem) end
  if self.BroadcastAuditEntry then self:BroadcastAuditEntry(entry) end
  self:Refresh()
  self:SelectAdminItem(self.selectedAdminItem)
  self:UpdateAdminStatus("Saved revision " .. tostring(override.revision) .. ", logged admin change, and broadcast sync.")
  self:RefreshAuditLog()
  self:SetAdminMode(false)
end

function APOCLootPrio:Refresh(resetScroll)
  if not self.frame then return end

  self:RefreshOfficerControls()

  for _, child in ipairs({self.frame.content:GetChildren()}) do
    child:Hide()
    child:SetParent(nil)
  end
  -- FontStrings are regions, not children — clear leftover empty-state text.
  ClearFrameRegions(self.frame.content)

  local y = -4
  local query = string.lower(self.frame.search:GetText() or "")

  for _, boss in ipairs(APOCLootPrioData[self.selectedRaid] or {}) do
    local items = FilterItems(boss.items, query)

    if #items > 0 then
      AddBossHeader(self.frame.content, boss.boss, y)
      y = y - BOSS_HEADER_HEIGHT - 12

      local leftCount = math.ceil(#items / 2)
      local rows = leftCount

      for index, item in ipairs(items) do
        local column = index <= leftCount and 0 or 1
        local row = column == 0 and index or index - leftCount
        local itemX = 10 + column * (COLUMN_WIDTH + COLUMN_GAP)
        local itemY = y - ((row - 1) * ITEM_ROW_HEIGHT)
        AddItemRow(self.frame.content, item, boss.boss, itemX, itemY)
      end

      y = y - (rows * ITEM_ROW_HEIGHT) - 18
    end
  end

  if y == -4 then
    -- Parent empty text to a frame so the next Refresh clears it with GetChildren().
    local emptyFrame = CreateFrame("Frame", nil, self.frame.content)
    emptyFrame:SetSize(CONTENT_WIDTH - 12, 28)
    emptyFrame:SetPoint("TOPLEFT", 10, y)
    local empty = Font(emptyFrame, 13, "No items found.", "GameFontNormal")
    empty:SetPoint("LEFT", 0, 0)
    empty:SetTextColor(.75, .75, .75)
    y = y - 28
  end

  self.frame.content:SetHeight(math.max(1, -y + 20))
  if self.frame.scroll and self.frame.scroll.UpdateScrollChildRect then
    self.frame.scroll:UpdateScrollChildRect()
  end
  if resetScroll and self.frame.scroll and self.frame.scroll.SetVerticalScroll then
    self.frame.scroll:SetVerticalScroll(0)
  end
  StyleAPOCFrameTree(self.frame.content)
end

function APOCLootPrio:Toggle()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    SetAddonFrameLayer(self.frame, ADDON_FRAME_LEVEL)
    self.frame:Show()
    self:RefreshOfficerControls()
  end
end
