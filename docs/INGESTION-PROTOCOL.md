# Companion ingestion protocol

The pairing flow and atomic upload database function are implemented. The upload
API and manual bridge adapter are in the source tree, but the bridge upload
control remains disabled until the API deployment and a synthetic end-to-end
check pass. No real raid data has been uploaded.

## Current bridge boundary

The companion captures and validates optical-strip data locally, persists bounded
snapshots in its local data directory, and serves its browser UI on `127.0.0.1:8765`.
It stores one device credential after explicit pairing. Capture stays local; the
manual upload control is currently gated off.

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

## Implementation order

1. Add guild-scoped devices, pairing challenges, upload receipts and correction/audit
   tables to a new tested migration.
2. Add authenticated pairing and upload handlers with replay and size limits.
3. Add synthetic end-to-end tests for cross-guild rejection, revocation, retries,
   stale revisions and correction preservation.
4. Add an opt-in companion upload adapter without changing the existing local capture
   path, then test it against a disposable guild and synthetic snapshots.

No real raid data should be uploaded until all four stages pass, including a
synthetic request through the deployed API and a manual bridge upload test.
