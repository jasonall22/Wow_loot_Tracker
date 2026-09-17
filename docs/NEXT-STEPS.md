# Agreed next phase — retained requirements

Vercel hosts the portal; Supabase provides accounts and shared raid data. Multiple
guilds use the same app with strict per-guild data isolation. The installed tracker
and local optical bridge remain independent, functional and backed up.

## Gate 1: user-owned cloud projects

Read-only account inventory found a connected Vercel team and a connected Supabase
organization, but the owner has not selected the destination organization yet.
Ask explicitly, obtain a project cost quote, confirm it with the owner, then create
dedicated APOC projects. Do not reuse an unrelated website's database. No cloud
resource has been created or linked by this foundation.

Test the draft schema in the new test database, run `db/security-tests.sql`, then
test the same access via real Supabase user JWTs/PostgREST. Apply only a verified,
registered migration. Do not weaken policies to get a demo working.

## Gate 2: sign-in and administration

Real Supabase login and invite acceptance; admin-controlled membership and separate
officer-edit/uploader grants. Never grant a role requested in signup metadata. Protect
the last administrator and record permission changes in an immutable audit trail.
Add guild selection and connect the current local archive/attendance/player-history UI
to authenticated API data. Avoid rebuilding or renaming the functioning WoW addon.

## Gate 3: master-looter connection

The invited master looter signs into the website and authorizes the companion PC for
one guild. They do not receive owner credentials or automatic officer permissions.
Pairing must use short-lived, single-use challenges, explicit browser consent,
proof that the companion owns the challenge, and revocable upload-only credentials.
No browser login tokens in command lines/URLs; no permanent raw device token stored
server-side. Pairing confirmation and consumption must be atomic, not in process RAM.

The companion captures only the optical strip, sends decoded raid data, and retries
idempotently. No whole screenshots or game memory are uploaded. Keep local capture
working during network outages, persist a bounded upload queue locally, and display
last confirmed server receipt. No extra per-item/award click for the master looter.

Trust the authenticated guild/device binding, validate schema/size/revision, prevent
stale replay, and handle changes of raid runner explicitly. Never let the next raw
addon snapshot erase audited officer corrections. Record source and received times.

## Gate 4: member pages and history

Live loot grouped by boss, item icons/stats, awards (MS/OS/DE/GB), current raid groups,
recorded presence intervals, date-filtered history, and clickable per-player loot
history. Preserve realm-qualified character identity. General public access stays
off until an explicit policy is selected.

Attendance percentages need scheduled raids and an expected roster. Missing data is
not absence. Track approved time off, bench/disconnect context and intervals before
adding lateness/consistency summaries. Do not label players "unreliable" automatically.

## Gate 5: officer-only comparison assistance

Warcraft Logs data, if authorized and available, is last-recorded equipment, not proof
of current worn gear. Show source/time and stale or missing data. Assess support in
WoWSims TBC Anniversary per class/role before exposing estimates. Whole sets, talents,
gems/enchants, caps, buffs and encounter assumptions matter; set bonuses can reverse
an apparent upgrade. No invented percentages, stat-score-as-DPS percentages or
universal cross-role ranking. The loot master retains the award decision.

Only admins/officers may access comparison inputs, estimates and rankings. Regular
members can view the other raid information. Keep simulations out of the live upload
path. The earlier additional 1–2 second online delay was a design target, NOT a measured
guarantee; measure actual end-to-end latency after real deployment.
