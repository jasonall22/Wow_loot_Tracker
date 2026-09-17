# Access model and rollout gates

## Capabilities

| Identity | Ordinary raid data | Comparisons | Edit records | Upload | Manage members |
| --- | --- | --- | --- | --- | --- |
| Public / no membership | No | No | No | No | No |
| Active member | Yes | No | No | Explicit flag | No |
| Active officer | Yes | Yes | Explicit flag | Explicit flag | No |
| Active admin | Yes | Yes | Yes | Yes | Yes |
| Suspended/revoked | No | No | No | No | No |

This release implements read routes only. No actor can currently use this API to
upload, edit records or manage accounts. Future handlers must enforce these
capabilities independently on the server and in database transactions.

Guild IDs are trusted only after matching current membership. Ingestion must take
the destination guild from an authorized device, NEVER merely from a payload's
guild name/realm. Account membership is not the same as the in-game character roster.

## Defense in depth

1. Auth checks the bearer token with Supabase's `/auth/v1/user` endpoint. Reject
   unconfirmed email, anonymous, non-user role, wrong issuer/audience, expired and
   mismatched-subject responses. No local JWT signature-verification implementation.
2. Read membership on each request; no cached guild roles or `user_metadata` trust.
3. Forward the SAME user JWT to REST queries using a publishable key, not a privileged
   service key. RLS must independently reject revoked/cross-guild requests, including
   a membership change between the app check and the data query.
4. Every relation includes a guild ID; child foreign keys include that guild.
5. Ordinary tables contain explicit fields, not whole snapshot blobs that might
   accidentally include private comparisons. Read projections discard unknown fields.
6. Comparison rows have a separate officer/admin SELECT policy; no public grants.
7. Explicit SELECT-only grants; no write policies or membership self-promotion route.
8. Per-response no-store headers, no shared auth cache, no permissive CORS and no
   exception/credential reflection. Network failures deny access.

An Auth logout does not necessarily invalidate an issued access JWT immediately.
Membership revocation is the current per-request access cutoff. Before sensitive
write actions, implement stronger session checks/revocation as appropriate; do not
claim immediate JWT invalidation. RLS tests must use the `authenticated`/`anon`
roles; querying as `postgres` alone does not test isolation.

## Still required before production

- Execute SQL and direct Data API adversarial tests in a dedicated test project.
- Run Supabase security/performance advisors and correct findings.
- Exercise two genuinely separate guilds, users, sessions, browser sign-in and expiry.
- Configure email confirmation, disable anonymous sign-in, configure production SMTP,
  permitted auth redirect URLs, account recovery and rate limiting. SDK dependencies,
  if added, must be version-pinned with lockfiles.
- Register the verified schema as a real CLI-created migration. Do not claim the
  draft filename represents a registered/applied migration.
- Separate dev/preview/production environments and avoid production credentials in previews.
- Implement invites, member administration, last-admin protection, device pairing,
  upload validation/replay protection, immutable audit records and corrections.
- Review Realtime publication policies before subscribing; ordinary loot streams
  must never contain officer comparison results. Recheck permissions on reconnection.
- Load/rate-limit tests, request timeouts and Vercel deployment verification.

## Sources checked while designing this foundation

- [Supabase Auth getUser](https://supabase.com/docs/reference/javascript/auth-getuser)
- [Supabase JWT claims](https://supabase.com/docs/guides/auth/jwt-fields)
- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase changelog](https://supabase.com/changelog) — checked 2026-09-17; explicit
  table grants and supported Node versions were relevant to this implementation.
- [Vercel Node.js runtime](https://vercel.com/docs/functions/runtimes/node-js)

The Supabase/Supabase Postgres skills guided RLS and explicit grants. Vercel's
function/environment guidance guided the isolated API entry point and empty config
template. No CLI deployment, privileged remote SQL or provisioning was performed.
