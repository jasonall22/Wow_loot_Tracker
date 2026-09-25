-- The beta uses a different SavedVariables table from the release addon.
-- Do not enable both addons at once: they intentionally share UI globals so
-- the beta can exercise the same production UI without maintaining a fork.
APOCLootPrio = APOCLootPrio or {}
APOCLootPrio.BUILD_VERSION = "0.2.0-beta.94-guild-bank.3"
APOCLootTrackerBetaDB = APOCLootTrackerBetaDB or {}
APOCLootPrioDB = APOCLootTrackerBetaDB
APOCLootPrioBetaMode = true

-- WoW restores SavedVariables after the addon's files execute and immediately
-- before ADDON_LOADED. Rebind the compatibility name after that restore so the
-- beta UI cannot remain attached to the temporary bootstrap table.
if CreateFrame then
  local savedVariablesBridge = CreateFrame("Frame")
  savedVariablesBridge:RegisterEvent("ADDON_LOADED")
  savedVariablesBridge:SetScript("OnEvent", function(frame, _, addonName)
    if addonName ~= "APOCLootTrackerBeta" then return end
    APOCLootTrackerBetaDB = APOCLootTrackerBetaDB or {}
    APOCLootPrioDB = APOCLootTrackerBetaDB
    APOCLootPrioBetaMode = true
    frame:UnregisterEvent("ADDON_LOADED")
  end)
end
