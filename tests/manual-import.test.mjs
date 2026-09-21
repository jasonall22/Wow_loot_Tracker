import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { extractRaidExport } from '../src/export-file.mjs';
import { normalizeRaidExport, sourceKeyForExport } from '../src/manual-import.mjs';
import { createImportHandler } from '../api/import.js';
import { GUILD, RAID, fakeBackend, principal, membership, token } from './fixtures.mjs';

const snapshot = () => ({
  format: 'apoc-loot-tracker-export-v1', guild: 'APOC', realm: 'Your Realm', faction: 'Horde',
  sender: 'Backup', sampledAt: 1789668000,
  session: { id: 'session-1', run: 'run-1', name: 'Black Temple', runner: 'Backup',
    revision: 8, createdAt: 1789660000, closedAt: 1789667000, closed: true, raids: ['Black Temple'] },
  drops: [{ id: 'drop-1', item: 'Test Item', itemID: 12345, boss: 'Illidan', at: 1789661000,
    award: { winner: 'Backup', type: 'MS', at: 1789662000, note: '' } }],
  members: [{ name: 'Backup', class: 'HUNTER', group: 1, present: false,
    visits: [[1789660000, 1789667000]] }],
});

test('reads only the explicit base64 export from a SavedVariables file', () => {
  const encoded = Buffer.from(JSON.stringify(snapshot())).toString('base64');
  const file = `APOCLootTrackerBetaDB = { ["private"] = "not for upload" }\nAPOCLootTrackerBetaExport = "${encoded}"\n`;
  assert.deepEqual(extractRaidExport(file), snapshot());
  assert.throws(() => extractRaidExport('APOCLootTrackerBetaDB = {}'), /No raid export/);
  assert.throws(() => extractRaidExport('APOCLootTrackerBetaExport = "@@@"'), /No raid export/);
});

test('manual import maps to the same source key and records as the bridge', () => {
  const upload = normalizeRaidExport(snapshot(), '10000000-0000-4000-8000-000000000001');
  assert.equal(sourceKeyForExport(snapshot()), '57b91d3293f694f3eb55bc0062b43eb2dd5cdc46c2a30ae4dcf74a78f149922d');
  assert.equal(upload.sourceKey, sourceKeyForExport(snapshot()));
  assert.equal(upload.raid.name, 'Black Temple');
  assert.equal(upload.drops[0].awardType, 'MS');
  assert.equal(upload.members[0].visits[0].leftAt, new Date(1789667000 * 1000).toISOString());
  assert.match(upload.payloadHash, /^[a-f0-9]{64}$/);
  const invalid = snapshot(); invalid.drops[0].award.at = 0;
  assert.throws(() => normalizeRaidExport(invalid), { status: 400 });
});

test('website import requires fresh upload permission and sends no full SavedVariables file', async () => {
  const denied = fakeBackend();
  let called = false;
  const make = backend => createImportHandler({ backendFactory: () => backend,
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async (_url, options) => {
      called = true;
      const sent = JSON.parse(options.body);
      assert.equal(sent.p_export_guild, 'APOC');
      assert.equal(sent.p_actor, principal.id);
      assert.equal(sent.p_drops[0].item_name, 'Test Item');
      assert.equal(Object.hasOwn(sent, 'APOCLootTrackerBetaDB'), false);
      return Response.json([{ upload_status: 'accepted', guild_id: GUILD, raid_id: RAID }]);
    } });
  const request = () => new Request('https://portal.invalid/api/import', {
    method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ guild: GUILD, export: snapshot() }),
  });
  assert.equal((await make(denied.backend)(request())).status, 403);
  assert.equal(called, false);
  const allowed = fakeBackend({ membership: async () => ({ ...membership, can_upload: true }) });
  const response = await make(allowed.backend)(request());
  assert.equal(response.status, 201);
  assert.equal((await response.json()).raid, RAID);
  assert.equal(called, true);
});

test('website import reports a permanently deleted raid instead of recreating it', async () => {
  const allowed = fakeBackend({ membership: async () => ({ ...membership, can_upload: true }) });
  const handler = createImportHandler({
    backendFactory: () => allowed.backend,
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async () => Response.json([{ upload_status: 'deleted', guild_id: GUILD, raid_id: null }]),
  });
  const response = await handler(new Request('https://portal.invalid/api/import', {
    method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ guild: GUILD, export: snapshot() }),
  }));
  assert.equal(response.status, 410);
  assert.deepEqual(await response.json(), { error: {
    code: 'raid_permanently_deleted',
    message: 'This raid was permanently deleted and cannot be imported again.',
  } });
});

test('manual import avoids output ambiguity and restores an explicitly imported archived raid', () => {
  const sql = readFileSync(new URL('../db/manual-file-import.sql', import.meta.url), 'utf8');
  assert.match(sql, /on conflict on constraint apoc_devices_guild_id_token_digest_key do nothing/i);
  assert.doesNotMatch(sql, /on conflict\s*\(guild_id,\s*token_digest\)/i);
  assert.match(sql, /update public\.apoc_raids as r\s+set deleted_at = null/i);
  assert.match(sql, /from public\.apoc_raid_tombstones as t[\s\S]*upload_status := 'deleted'/i);
  assert.match(sql, /'restored', v_restored_name, p_request_id/i);
  assert.match(sql, /v_result_status := 'accepted'/i);
});
