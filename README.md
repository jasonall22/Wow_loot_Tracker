# APOC Raid Portal — online backend foundation

Version: `0.2.0-foundation.1` — 2026-09-17

This is a NEW, portable development project. It does not replace APOCLootTrackerBeta,
APOCLiveBridge, the running local companion, or any existing website/database.
There is no browser login screen or live cloud uploader in this milestone.

## Implemented here

- A Vercel-compatible read-only API handler with a Supabase Auth/REST adapter.
- Identity is checked with Supabase Auth before any guild query. Parsed JWT claims
  are rejection filters, not a substitute for signature verification by Auth.
- Current membership is checked on each request. Guild permissions never come from
  browser-selected roles or user-editable metadata.
- Members can read ordinary raid records. Only admins/officers can request the
  separate comparisons endpoint. Upload permission is independent of officer status;
  officer editing requires its own flag. These flags describe the intended capability
  model, not currently working upload/edit endpoints.
- No service-role key, cross-user session cache, public raid access, write endpoint,
  fallback demo login, or localhost security bypass.
- A draft seven-table schema with explicit grants, RLS, and guild-scoped foreign keys.
  This draft has NOT been executed in a database.
- Dependency-free Node tests, small timestamped source backups, portable packaging.

## Local verification

Requires Node.js 24. No `npm install` is needed.

```powershell
node --test tests/*.test.mjs
node scripts/check.mjs
```

The automated Auth/REST tests use synthetic responses, not real accounts or tokens.
Schema-contract checks inspect SQL text only. See `TEST-RESULTS.md` for exact limits.

## API contract

All calls use `GET /api/portal`, with an actual Supabase user access token in
`Authorization: Bearer <access_token>`. No tokens in URLs or cookie support yet.
All responses, including errors, are private/no-store. The browser sign-in client
will be implemented after the dedicated cloud projects are approved and configured.

| Query | Access / response |
| --- | --- |
| `?view=guilds` | Current user's active guild memberships (maximum 100) |
| `?view=context&guild=<uuid>` | Guild display details and current capabilities |
| `?view=raids&guild=<uuid>` | Raid archive records |
| `?view=raid&guild=<uuid>&raid=<uuid>` | One raid's details |
| `?view=drops&guild=<uuid>&raid=<uuid>` | Loot, boss and award records |
| `?view=members&guild=<uuid>&raid=<uuid>` | Captured raid roster/groups |
| `?view=visits&guild=<uuid>&raid=<uuid>` | Recorded presence intervals |
| `?view=comparisons&guild=<uuid>&raid=<uuid>` | Admin/officer only; no simulation implemented |

Collection views except `guilds` take `limit` (1–200, default 50) and `offset`
(0–100000, default 0). Consumers must page, not treat a single page as a full raid.
Guild and raid IDs are database UUIDs, NOT the addon's run ID or guild name.

Only hosted `https://<project-ref>.supabase.co` URLs and modern `sb_publishable_`
keys are accepted. `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are intentionally
empty in `.env.example`. No project is linked, keys saved, schema applied or deployment
created. The handler fails closed until those server environment values exist.
Never paste account passwords, database passwords or service-role keys into chat.

## Move to E: later

Copy the complete `APOC-Raid-Portal` folder to `E:\APOC-Raid-Portal`, or extract the
portable source ZIP into `E:\`. There are no hardcoded C: paths in the implementation.
This is source code, not a replacement for `E:\APOC-Loot-Tracker-Bridge` and not a
WoW addon. Nothing needs to go in WoW's AddOns directory.

Back up before each edit batch:

```powershell
.\backup.ps1 -Label before-my-change
```

Source backups exclude credentials, runtime data and dependencies. They are not
database backups. Keep future cloud backups separate and access-controlled.

Package source and these non-secret backups:

```powershell
.\package.ps1
```

## Next milestone

Confirm the cloud organization/team, review provisioning cost, create separate
APOC projects, execute and test the schema, and implement real sign-in/invitations.
Then implement the revocable companion-device connection and authenticated uploads.
See `docs/NEXT-STEPS.md` and `docs/SECURITY.md`; do not expose this foundation as a
finished production portal.
