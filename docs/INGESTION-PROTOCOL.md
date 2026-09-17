# Companion ingestion protocol

The pairing flow, device-bound upload API, and atomic database function are
implemented. A paired, running bridge syncs changed saved snapshots automatically;
demo snapshots never upload. The website refreshes open raid views periodically.

## Current bridge boundary

The companion captures and validates optical-strip data locally, persists bounded
snapshots in its local data directory, and serves its browser UI on `127.0.0.1:8765`.
It stores one upload-only device credential after explicit pairing. Screen capture
stays local; only validated structured raid records are uploaded. The local saved
sessions are the durable retry source during network outages and bridge restarts.

## Required connection flow

1. An authenticated guild admin or officer starts pairing in the portal.
2. The portal creates a short-lived, single-use challenge for exactly one guild.
3. The companion proves ownership of the challenge; the browser shows explicit consent.
4. The server atomically consumes the challenge and issues a revocable upload-only
   device credential. The raw credential is never stored server-side.
5. The companion sends validated structured records over HTTPS, with an idempotency
   key and monotonically increasing source revision.
6. The server validates the device-to-guild binding, schema, size, revision and replay
   state before writing. Network failure leaves the local queue and capture intact.

## Upload shape

The first implementation should send explicit fields for the session, raid metadata,
loot drops, awards, roster members and presence intervals. It must not send screenshots,
game memory, raw bearer tokens in URLs, or a whole opaque snapshot blob.

Every request must include a bounded body, a source key, source revision, capture time,
client request ID and device credential. The server records received time separately.
Duplicate request IDs and already-accepted revisions must be safe no-ops.

## Corrections and auditability

Incoming snapshots may add new records but must never erase audited officer corrections.
Corrections need their own immutable audit record with actor, time, reason, prior value
and new value. A later companion revision must be reconciled against those corrections.
No upload handler is complete until this behavior has database tests.

## Completed implementation checks

1. Add guild-scoped devices, pairing challenges, upload receipts and correction/audit
   tables to a new tested migration.
2. Add authenticated pairing and upload handlers with replay and size limits.
3. Add synthetic end-to-end tests for cross-guild rejection, revocation, retries,
   stale revisions and correction preservation.
4. Keep capture independent of the background cloud worker, and verify automatic
   add, delete, retry, restart recovery, and demo isolation with synthetic snapshots.

The bridge shows sync errors locally and retries transient failures. A paired
device can be revoked server-side without exposing its credential to the browser.
