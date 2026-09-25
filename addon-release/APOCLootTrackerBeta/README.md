# APOC Loot Tracker Beta — 0.2.0-beta.97-guild-bank.6

Cleanup candidate for TBC Anniversary (Interface 20505). Live raid authority
is now always the WoW Master Looter; the separate assignable runner has been
removed from live control. The bridge, pixel strip, and website sync remain.

## Install only when ready to test

1. Exit WoW on both test clients.
2. Back up the currently installed APOCLootTrackerBeta addon folder and the
   account's WTF SavedVariables files APOCLootTrackerBeta.lua and its .bak.
3. Replace the old addon folder with this entire APOCLootTrackerBeta folder in:
   E:\World of Warcraft\_anniversary_\Interface\AddOns
4. Enable only the beta, not APOCLootPrio/release at the same time. They share UI globals.
5. All test participants, including the Master Looter, should run beta.91-ml-authority.1.
   Do not mix builds during verification.
6. Open with /priobeta. The Master Looter uses Share List; viewers use Ask List
   or Get List to request a full run-scoped snapshot.

## Live authority

The current WoW Master Looter is the only live writer. Everyone in the group
resolves the authority from `GetLootMethod`; saved runner names and old runner
assignment packets cannot take control. If the Master Looter disconnects, live
editing pauses until WoW appoints a new Master Looter. The new ML must run this
addon and the bridge to resume website sync. Archived raid history can still
be reviewed and edited according to the guild's history permissions.

Your existing beta SavedVariables name is unchanged. This package does not
replace or clear saved raid history.

## Backup raid upload (no bridge)

The backup loot runner selects the raid and clicks **Export** in Loot Tracker.
Then type `/reload` (or log out) so WoW writes its SavedVariables file. On the
website, an admin or guild member with raid-upload permission chooses **Import
raid** and selects `WTF/Account/<account>/SavedVariables/APOCLootTrackerBeta.lua`
from that player's WoW folder. The browser extracts only the exported raid; it
does not send the full SavedVariables file. Importing the same or an older
revision again does not overwrite newer website data.

The Export button prepares one selected raid for WoW's normal file write; WoW
addons cannot create a separate arbitrary file on click. No bridge, strip, or
screen capture is needed for this fallback.

## What changed

### beta.90-native-comms.1: RCLootCouncil-style native transport

- All APOC addon messages now pass through one throttled outbound queue instead
  of allowing control and live-sync chunks to burst independently.
- Failed messages back off and retry for a bounded period; queue overflow and
  expired messages are recorded in sync diagnostics.
- `/priobeta-run` now reports native transport queue, sent, retry, and dropped
  message counts.
- The pixel-strip bridge and website sync remain unchanged.

### beta.89-browser-priority.1: Loot Browser priority source

- Website sync and manual exports now resolve priority from the Loot Browser's
  item list and current guild overrides at send time.
- Existing raids can gain missing priority text on their next bridge sync or
  manual re-import without recreating the raid.

### beta.88-web-loot-details.1: website priority and roll history

- Live bridge snapshots and manual raid exports now include each item's loot priority and recorded MS/OS rolls.
- This supplies the website's click-to-open loot details window without exposing unrelated SavedVariables data.

### beta.87-loot-popup.1: click-to-open loot details

- Clicking any dropped or awarded loot row now opens a focused Loot Details &
  Rolls popup.
- The popup shows the item and boss, the configured loot priority, the live MS
  and OS roll lists, the current leader, and time remaining.
- Loot Tracker viewers can read the popup. Award and reset controls remain
  restricted to the active runner or authorized editor.

### beta.86-roster-fix.1: correct multi-return roster count

- Fixes the confirmed Lua `tonumber` “base out of range” error caused by
  `GetNumGuildMembers()` returning total and online counts.
- Live bridge snapshots and manual raid exports can now include the complete
  guild roster.

### beta.85-roster-error.1: local roster error reporting

- If Blizzard's roster reader raises an error, the bridge now records a short
  local diagnostic while continuing to sync the raid. The diagnostic is never
  included in the cloud upload.

### beta.84-roster-diagnostic.1: automatic roster diagnostics

- The local bridge records safe roster readiness counts automatically, so a
  missing or duplicate Blizzard roster row can be diagnosed without a slash
  command. These counts are not uploaded to the website.

### beta.83-roster-sync.1: wait for Blizzard's completed roster update

- Live roster capture now requests a refresh, waits for `GUILD_ROSTER_UPDATE`,
  and reads the completed cache without immediately resetting it again.
- Manual Export refuses to prepare a roster-less backup. If Blizzard is still
  refreshing, wait a few seconds and click Export again.

### beta.82-unified.1: one in-game addon

- APOC Live Bridge is now built directly into APOC Loot Tracker Beta. Players
  install only the `APOCLootTrackerBeta` addon folder.
- The strip remains off until `/apocbridge on` is used. Its saved position and
  size remain in `APOCLiveBridgeDB`.
- Guild roster refresh now uses the TBC Anniversary `C_GuildInfo.GuildRoster`
  API with the older global API as a fallback.
- The separate Windows bridge is still required on computers that send live
  raid data to the website; WoW addons cannot make website connections.

### beta.81-guild-roster.1: website guild membership history

- A manual raid export now includes a complete in-game guild roster when WoW has
  a verified roster snapshot available.
- The website uses that snapshot to separate current and former members. Raid
  attendance by itself does not add PUGs to Guild loot.
- A player who joins later is matched to older recorded awards, and a returning
  former member keeps the same loot history.

### beta.80-session-name.1: rename a raid session

- The Loot Tracker toolbar now has a **Rename** button for the selected active
  or saved History session.
- Renaming changes only the displayed session title. Loot, attendance, runner,
  and Run ID remain attached to the same raid record.
- The new name increments the session revision and follows the existing live or
  officer-history sync path. A previously prepared manual Export is cleared so
  it cannot upload the old title; click Export again after renaming if needed.

### beta.78-history.2: close an opened history raid

- An authorized history editor can use Close & Save on the selected old raid.
  The old Run ID and archived provenance are retained;
  this does not create a new solo run.
- Finalizing history sends the updated saved raid to officer history sync,
  not to the active live-run channel.
- This path needs an in-game test before relying on it for guild records.

### beta.78-history.1: closed-history runner handoff

- While out of a raid, open a closed raid in History, then choose Settings → Me.
  This claims that saved run for the current character without starting a new
  solo run or changing its loot/session identity. The original runner remains
  recorded in the local run metadata.
- No live-raid runner behavior is changed. This local handoff does not prove
  that another player's later corrections have arrived; review the drop count
  before letting the bridge upload it.

### beta.77-sync.1: bounded live-sync backlog

- Replaces unsent older live transfers for the same session, drop, or catalog
  with the latest revision. Identical pending transfers are not queued twice.
- Coalesces repeated runner heartbeats and manifests, sends them ahead of bulk
  snapshots, and gives live raid traffic four turns for each guild-history turn.
- Replaces unsent older guild archive transfers for the same session and target.
- Does not change SavedVariables or stored raid history. Test with all clients
  on this build after the current raid; this build has not been multiplayer-tested.

### beta.76: award delivery and recovery

- Reproduced beta.75 losing an award after a 1.2-second simulated send failure.
  Failed packets now use exponential backoff for up to two minutes, instead of
  being discarded after ten rapid attempts. Traffic is paced by byte count.
- Idle runners broadcast a verification manifest on their 15-second heartbeat.
  A follower that missed an update can request a full snapshot automatically.
- Snapshot coalescing only considers queued packets for that exact snapshot;
  unrelated heartbeat packets and the old five-second cooldown no longer block retries.
- Verification retries can resume after 30 seconds instead of permanently giving
  up after two attempts for the same loot digest. Stale timers cannot request
  data after leaving the run or after successful verification.
- Live, archive and watch transfers expire after 150 seconds without progress,
  rather than expiring during a large, steadily arriving transfer.
- /priobeta-run now includes send retries, discarded sends, applied updates,
  corrupt transfers and expired transfers. Counters include prior sessions.
- No changes to addon identity, saved-variable names, run authorization or loot history.

Validated offline: 43 existing checks plus 10 new delivery/recovery checks pass.
This reproduces and fixes a failure mechanism, not proof of the exact cause on
Rixler's client. Multiplayer verification is still required: Share List once,
then award an existing drop and confirm it moves to awarded loot on the viewer
without manual Get List. If stale after a minute, collect /priobeta-run on both.

### Earlier beta.75 cleanup

- Fixed both Lua syntax errors in the original LiveRaid module.
- Removed name-only N1/NK/LD4/LD5 state mutation and synthetic PING/PLIVE raids.
- Removed obsolete V1/V2 loot packet receivers and their separate send queue.
- One SyncRouter dispatches messages explicitly to transport, control, run/history,
  or watch handlers. Live state remains scoped to one Run ID and current runner.
- Full snapshots preserve each drop's ID, revision and capture identity, including
  multiple copies of the same item. Verification no longer hashes receiver-only metadata.
- Duplicate full-list requests are coalesced. Failed sends stay queued for bounded
  retries. History ACK timeout starts when the final queued chunk is attempted.
- Capture uses source GUID + item + occurrence when the client exposes it, with a
  window-local fallback. Multiple quantities and separate corpses remain separate.
- Trade allocation has one owner. Delivery is recorded only on a confirmed trade,
  not merely both players accepting and the window closing. Unchecked selections
  and ambiguous unselected items are not auto-awarded.
- Master-loot delivery waits for the intended player's loot receipt and slot
  clearance. A successful Lua function call alone is not delivery confirmation.
- Mutations authorize the actual target session. Viewing history does not give a
  non-runner access to live drops or attendance.
- History receivers enforce editor rank; equal-revision conflicts converge by a
  deterministic snapshot hash. Up to 30 losing payloads are retained in
  loot.historyConflicts for developer-assisted recovery.
- Refresh only refreshes discovery; it cannot claim runner ownership.
- Removed the old Test button. Roll results reuse frames and regions.
- Rolls use the client's localized message format, reject non-group rollers and
  invalid values, and allocate at most one winning copy per player.
- Fixed sync-status and beta slash-command help text.

## Module map

- BetaBootstrap.lua: beta SavedVariables bridge and fallback build version
- Data.lua: existing item/priority data, unchanged
- Core.lua: sessions, permissions, capture, rolls, attendance, settings
- Transport.lua: prefix registration, checked sends, trust, version/audit messages
- LootCodec.lua: session/drop serialization and canonical apply operations
- ControlSync.lua: versioned priority/settings synchronization and chunk assembly
- RunSync.lua: run identity, authority, live snapshots, history, recovery, queues
- LiveRaid.lua: discovery and explicit read-only out-of-group watching
- UI.lua / Minimap.lua: panels and launch controls
- TradeMasterLoot.lua: trade transaction and master-loot helpers
- SyncControls.lua: user-facing sync actions
- SyncRouter.lua: the single addon-message receive entry point

Some internal method names retain V2/V3 for compatibility between modules.
Those names do not mean the retired unscoped wire protocols are enabled.

## Required in-game verification

Use a small group before a raid. Turn on script errors with
/console scriptErrors 1 and reload.

- ML captures several items; viewer receives identical item count and IDs.
- Capture two or three copies of the same token; award only one.
- Viewer reloads, requests the list, and still has all copies and awards.
- Open history while in the group; return to Live and confirm the active list.
- Trade one token, cancel an accepted trade, then complete a real trade.
- Master-loot to a player outside the first 12 roster entries.
- Test runner handoff, reconnects, a full 25-player raid, and out-of-group watch.
- Use /priobeta syncstatus and compare both clients if a list diverges.

## Boundaries

Offline tests cannot verify Blizzard protected-action behavior, real network
throttling, combat taint, UI appearance, localization on every client, or server
event ordering. Automatic delivery may remain pending if the client does not
supply its confirmation event; it must never be assumed delivered.

In-progress roll state is still local rather than fully synchronized during runner
handoff. Finish or restart rolls when changing runner. Large general panels still
use the existing rendering design; row pooling here is specific to roll results.
The embedded item/priority table was structurally checked, not revalidated against
every current raid loot table.

## API references consulted

[Blizzard Classic event definitions](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua)
and [first-hand GetLootSourceInfo API observations](https://www.wowinterface.com/forums/showthread.php?p=260129)
were used for the loot-event/source handling. Live client verification is still required.
