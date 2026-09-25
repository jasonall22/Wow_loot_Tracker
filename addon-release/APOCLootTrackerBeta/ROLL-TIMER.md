# Optional roll timer — beta.76-timer.1

This small update is based on the exact beta.76 copy installed on this PC. It does
not incorporate other beta.77–79 changes or alter the synchronization protocol.
The addon name, root folder, and SavedVariables name remain APOCLootTrackerBeta.

Open the loot tracker, choose **Settings**, and use **Roll timer (sec)** near the
bottom. Enter a whole number from **5 to 120**, then click **Save** or press Enter.
**Default** restores 15 seconds. Escape cancels an unsaved edit.
The existing Settings access rules are unchanged (top two guild ranks).

This preference is saved locally under `ui.lootTracker.rollDurationSeconds` in the
existing addon SavedVariables. It is not broadcast as a guild setting. Set it on
the master looter/runner's installation. Opening raid chat announcements use the
chosen duration. Invalid or missing stored values safely fall back to 15 seconds.

Only newly started rolls use the preference. Changing it never shortens or extends
a running roll or changes its entries. The existing **Reset** action still sets
10 seconds and keeps recorded rolls. MS/OS rules, winners, awards, identical-copy
handling, loot history, syncing, attendance, and APOCLiveBridge are unchanged.

## Install and test

Back up the current addon folder. Extract the addon ZIP into
`E:\World of Warcraft\_anniversary_\Interface\AddOns`, replacing files in
`APOCLootTrackerBeta`. Do not nest another APOCLootTrackerBeta folder inside it.
Do not delete any SavedVariables or the separate APOCLiveBridge addon. Type
`/reload` after copying. The title remains APOC Loot Tracker - Multi-Run Beta.

Before a real raid, use a disposable/test drop: set 30 seconds, start a roll, check
the chat duration and countdown, then test Reset (10 seconds). Restore your chosen
duration afterward. A saved preference is written to disk by normal WoW logout or
UI reload. Live game behavior still needs this check; no zero-risk guarantee is made.
