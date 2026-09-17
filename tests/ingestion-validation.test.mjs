import test from 'node:test';
import assert from 'node:assert/strict';
import { createPairingChallenge, digestSecret, digestPayload, parseUploadBody, PAIRING_TTL_SECONDS } from '../src/ingestion.mjs';

const validUpload = () => {
  const body = {
    requestId: '10000000-0000-4000-8000-000000000001', sourceKey: 'session-a', sourceRevision: 4,
    capturedAt: '2026-09-17T14:00:00Z',
    raid: { name: 'Trial raid', runId: 'run-a', createdAt: '2026-09-17T13:00:00Z', closedAt: null },
    drops: [{ id: 'drop-a', itemId: 123, itemName: 'Test item', boss: 'Test boss', droppedAt: '2026-09-17T13:30:00Z', winner: 'Player', awardType: 'MS', awardedAt: '2026-09-17T13:31:00Z', awardNote: '' }],
    members: [{ characterKey: 'player', name: 'Player', class: 'MAGE', raidGroup: 1, present: true, visits: [{ joinedAt: '2026-09-17T13:00:00Z', leftAt: null }] }],
  };
  body.payloadHash = digestPayload(body);
  return body;
};

test('pairing challenge is random, digest-only, and expires quickly', () => {
  const challenge = createPairingChallenge({ now: Date.parse('2026-09-17T14:00:00Z'), random: () => Buffer.alloc(32, 7) });
  assert.notEqual(challenge.raw, challenge.digest);
  assert.equal(challenge.digest, digestSecret(challenge.raw));
  assert.equal(Date.parse(challenge.expiresAt) - Date.parse(challenge.createdAt), PAIRING_TTL_SECONDS * 1000);
});

test('upload parser accepts bounded explicit metadata', async () => {
  const body = validUpload();
  const request = new Request('https://example.test/api/ingest', { method: 'POST', body: JSON.stringify(body) });
  assert.deepEqual(await parseUploadBody(request), body);
});

test('upload parser rejects opaque, malformed, and oversized input', async () => {
  const negativeRevision = validUpload(); negativeRevision.sourceRevision = -1;
  const duplicateDrop = validUpload(); duplicateDrop.drops.push({ ...duplicateDrop.drops[0] }); duplicateDrop.payloadHash = digestPayload(duplicateDrop);
  const mismatchedHash = validUpload(); mismatchedHash.payloadHash = 'a'.repeat(64);
  const bad = [
    { requestId: 'bad', sourceKey: 'x', sourceRevision: 0, payloadHash: 'a'.repeat(64), capturedAt: '2026-09-17T14:00:00Z' },
    negativeRevision, duplicateDrop, mismatchedHash,
    { snapshot: { drops: [] } },
  ];
  for (const value of bad) await assert.rejects(() => parseUploadBody(new Request('https://example.test', { method: 'POST', body: JSON.stringify(value) })));
  await assert.rejects(() => parseUploadBody(new Request('https://example.test', { method: 'POST', body: 'x'.repeat(1_048_577) })));
});
