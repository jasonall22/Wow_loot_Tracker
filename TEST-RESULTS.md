# Verification — 2026-09-17

Build: `0.2.0-foundation.1`

- Node.js 24.11.1: **87 automated checks passed**, none skipped or failed.
- **12 JavaScript files** passed syntax checks.
- API permission tests cover members, upload-only members, officers, admins,
  suspended/revoked membership, cross-guild attempts, immediate next-request demotion,
  metadata role spoofing, no-store responses, no write methods and no internal-error leaks.
- Auth/REST adapter tests cover rejection filters, Auth verification failure,
  unconfirmed/anonymous users, service-role tokens/keys, exact user-token forwarding,
  guild+raid filters, pagination and concurrent user isolation.
- Four SQL-contract checks inspect the draft text only; **they are not database tests**.

## Not yet verified / not implemented

- No live Supabase Auth, PostgREST or RLS execution: dedicated cloud target not selected.
- No Postgres engine available locally. An npm lookup for a small test engine was
  denied network access; no dependency was installed and no bypass attempted.
- `db/security-tests.sql` is prepared but UNEXECUTED. Run in a new test database only.
- No Vercel deployment or runtime smoke test. The entry point follows current runtime
  documentation but has not been exercised on Vercel.
- No browser sign-in/invite UI, upload/pairing implementation, Realtime connection,
  editor/audit workflow or gear simulation in this milestone.
- No end-to-end game-to-online latency measurement.

No installed WoW files, existing companion files, raid data or cloud projects were
modified. This project is source code, not a production-ready website update.
