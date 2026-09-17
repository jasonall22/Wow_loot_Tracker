import test from 'node:test';
import assert from 'node:assert/strict';
import { createPairingChallenge, digestSecret, parseUploadBody, PAIRING_TTL_SECONDS } from '../src/ingestion.mjs';

test('pairing challenge is random, digest-only, and expires quickly', () => {
  const challenge = createPairingChallenge({ now: Date.parse('2026-09-17T14:00:00Z'), random: () => Buffer.alloc(32, 7) });
  assert.notEqual(challenge.raw, challenge.digest);
  assert.equal(challenge.digest, digestSecret(challenge.raw));
  assert.equal(Date.parse(challenge.expiresAt) - Date.parse(challenge.createdAt), PAIRING_TTL_SECONDS * 1000);
});

test('upload parser accepts bounded explicit metadata', async () => {
  const body = { requestId: '10000000-0000-4000-8000-000000000001', sourceKey: 'session-a', sourceRevision: 4, payloadHash: 'a'.repeat(64), capturedAt: '2026-09-17T14:00:00Z' };
  const request = new Request('https://example.test/api/ingest', { method: 'POST', body: JSON.stringify(body) });
  assert.deepEqual(await parseUploadBody(request), body);
});

test('upload parser rejects opaque, malformed, and oversized input', async () => {
  const bad = [
    { requestId: 'bad', sourceKey: 'x', sourceRevision: 0, payloadHash: 'a'.repeat(64), capturedAt: '2026-09-17T14:00:00Z' },
    { requestId: '10000000-0000-4000-8000-000000000001', sourceKey: 'x', sourceRevision: -1, payloadHash: 'a'.repeat(64), capturedAt: '2026-09-17T14:00:00Z' },
    { snapshot: { drops: [] } },
  ];
  for (const value of bad) await assert.rejects(() => parseUploadBody(new Request('https://example.test', { method: 'POST', body: JSON.stringify(value) })));
  await assert.rejects(() => parseUploadBody(new Request('https://example.test', { method: 'POST', body: 'x'.repeat(1_048_577) })));
});
