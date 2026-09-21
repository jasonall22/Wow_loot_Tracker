import test from 'node:test';
import assert from 'node:assert/strict';
import { createIngestHandler } from '../api/ingest.js';
import { digestPayload, digestSecret } from '../src/ingestion.mjs';

const deviceToken = 'x'.repeat(43);
const guild = '20000000-0000-4000-8000-000000000001';
const raidID = '30000000-0000-4000-8000-000000000001';
const body = () => {
  const value = {
    requestId: '10000000-0000-4000-8000-000000000001', sourceKey: 'source-a', sourceRevision: 2,
    capturedAt: '2026-09-17T14:00:00Z',
    raid: { name: 'Trial', runId: 'run-a', createdAt: '2026-09-17T13:00:00Z', closedAt: null },
    drops: [{ id: 'drop-a', itemId: 123, itemName: 'Test item', boss: 'Boss', droppedAt: '2026-09-17T13:30:00Z', winner: 'Player', awardType: 'MS', awardedAt: '2026-09-17T13:31:00Z', awardNote: '' }],
    members: [{ characterKey: 'player', name: 'Player', class: 'MAGE', raidGroup: 1, present: true, visits: [{ joinedAt: '2026-09-17T13:00:00Z', leftAt: null }] }],
  };
  value.payloadHash = digestPayload(value);
  return value;
};
const request = (value = body(), token = deviceToken) => new Request('https://portal.test/api/ingest', {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(value),
});
const handler = (fetchImpl) => createIngestHandler({
  serverConfig: () => ({ origin: 'https://project.supabase.co', secretKey: 'sb_secret_test' }), fetchImpl,
});

test('manual upload sends explicit fields with a device digest and no guild chosen by client', async () => {
  let sent;
  const handle = handler(async (url, options) => {
    sent = { url, options, payload: JSON.parse(options.body) };
    return Response.json([{ upload_status: 'accepted', guild_id: guild, raid_id: raidID }]);
  });
  const response = await handle(request());
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: 'accepted', guild, raid: raidID });
  assert.match(sent.url, /\/rpc\/ingest_apoc_raid$/);
  assert.equal(sent.payload.p_token_digest, digestSecret(deviceToken));
  assert.equal(sent.payload.p_raid.name, 'Trial');
  assert.equal(sent.payload.p_drops[0].award_type, 'MS');
  assert.equal(sent.payload.p_members[0].visits[0].joined_at, '2026-09-17T13:00:00Z');
  assert.equal(sent.options.body.includes(deviceToken), false);
  assert.equal(Object.hasOwn(sent.payload, 'guild_id'), false);
});

test('a verified upload syncs its complete guild roster after resolving the paired guild', async () => {
  const value = body();
  value.guildRoster = { members: [
    { characterKey: 'player', name: 'Player', class: 'MAGE', rankName: 'Raider', rankIndex: 4 },
  ] };
  const calls = [];
  const handle = handler(async (url, options) => {
    calls.push({ url, payload: JSON.parse(options.body) });
    if (url.endsWith('/rpc/ingest_apoc_raid')) return Response.json([{ upload_status: 'duplicate', guild_id: guild, raid_id: raidID }]);
    return Response.json({ status: 'ok' });
  });
  const response = await handle(request(value));
  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/sync_apoc_guild_roster$/);
  assert.equal(calls[1].payload.p_guild_id, guild);
  assert.equal(calls[1].payload.p_members[0].character_key, 'player');
  assert.equal(calls[1].payload.p_members[0].rank_name, 'Raider');
});

test('upload rejects missing device proof and malformed records before calling cloud', async () => {
  let called = false;
  const handle = handler(async () => { called = true; return Response.json([]); });
  assert.equal((await handle(request(body(), 'short'))).status, 401);
  const invalid = body(); invalid.drops[0].winner = 'changed';
  assert.equal((await handle(request(invalid))).status, 400);
  assert.equal(called, false);
});

test('revoked, stale, and duplicate uploads have distinct results', async () => {
  const responses = [[], [{ upload_status: 'stale', guild_id: guild, raid_id: raidID }], [{ upload_status: 'duplicate', guild_id: guild, raid_id: raidID }]];
  const handle = handler(async () => Response.json(responses.shift()));
  assert.equal((await handle(request())).status, 401);
  assert.equal((await handle(request())).status, 409);
  const duplicate = await handle(request());
  assert.equal(duplicate.status, 200);
  assert.equal((await duplicate.json()).status, 'duplicate');
});
