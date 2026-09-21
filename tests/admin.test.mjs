import test from 'node:test';
import assert from 'node:assert/strict';
import { createAdminHandler, parseAdminBody } from '../api/admin.js';
import { GUILD, OTHER_GUILD, RAID, USER, membership, principal, token } from './fixtures.mjs';
import { raidProjection } from '../src/projections.mjs';
import { readFile } from 'node:fs/promises';

const endpoint = 'https://portal.invalid/api/admin';
const body = { guild: GUILD, raid: RAID, action: 'rename_raid', name: 'New raid name' };
const request = (value = body) => new Request(endpoint, {
  method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'content-type': 'application/json' }, body: JSON.stringify(value),
});

function setup(role = 'admin', rpcResult = { status: 'ok' }) {
  const calls = [];
  const handler = createAdminHandler({
    backendFactory: () => ({
      authenticate: async () => principal,
      membership: async () => ({ ...membership, role }),
    }),
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async (url, init) => { calls.push({ url, init }); return Response.json(rpcResult); },
  });
  return { handler, calls };
}

test('only verified same-guild admins can reach the edit RPC', async () => {
  for (const role of ['member', 'officer']) {
    const { handler, calls } = setup(role);
    assert.equal((await handler(request())).status, 403);
    assert.equal(calls.length, 0);
  }
  const crossGuild = setup();
  assert.equal((await crossGuild.handler(request({ ...body, guild: OTHER_GUILD }))).status, 403);
  assert.equal(crossGuild.calls.length, 0);
  const { handler, calls } = setup();
  assert.equal((await handler(request())).status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://exampleproject.supabase.co/rest/v1/rpc/admin_apoc_edit');
  assert.equal(calls[0].init.headers.Authorization, 'Bearer sb_secret_test');
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    p_actor: USER, p_guild_id: GUILD, p_raid_id: RAID, p_action: 'rename_raid', p_payload: { name: 'New raid name' },
  });
});

test('admin edits accept only exact, bounded raid and award fields', async () => {
  for (const invalid of [
    { ...body, role: 'admin' }, { ...body, name: '' }, { ...body, raid: 'wrong' },
    { guild: GUILD, raid: RAID, action: 'delete_raid', extra: true },
    { guild: GUILD, raid: RAID, action: 'restore_raid', extra: true },
    { guild: GUILD, raid: RAID, action: 'purge_raid', extra: true },
    { guild: GUILD, raid: RAID, action: 'edit_drop', dropId: 'drop', winner: 'Player', awardType: null, awardNote: '' },
    { guild: GUILD, raid: RAID, action: 'edit_drop', dropId: 'drop', winner: null, awardType: 'MS', awardNote: '' },
    { guild: GUILD, raid: RAID, action: 'edit_drop', dropId: 'drop', winner: null, awardType: 'BAD', awardNote: '' },
  ]) assert.throws(() => parseAdminBody(invalid), { status: 400 });
  const clear = parseAdminBody({ guild: GUILD, raid: RAID, action: 'edit_drop', dropId: 'drop', winner: null, awardType: null, awardNote: '' });
  assert.deepEqual(clear.payload, { dropId: 'drop', winner: null, awardType: null, awardNote: '' });
  assert.deepEqual(parseAdminBody({ guild: GUILD, raid: RAID, action: 'delete_raid' }).payload, {});
  assert.deepEqual(parseAdminBody({ guild: GUILD, raid: RAID, action: 'restore_raid' }).payload, {});
  assert.deepEqual(parseAdminBody({ guild: GUILD, raid: RAID, action: 'purge_raid' }).payload, {});
});

test('database permission and missing-raid statuses stay private', async () => {
  for (const [status, expected] of [['forbidden', 403], ['not_found', 404], ['invalid', 400]]) {
    const { handler } = setup('admin', { status });
    assert.equal((await handler(request())).status, expected);
  }
});

test('raid projection shows admin name while keeping bridge source name separate', () => {
  assert.equal(raidProjection({ name: 'Bridge name', display_name: 'Admin name' }).name, 'Admin name');
  assert.equal(raidProjection({ name: 'Bridge name', display_name: null }).name, 'Bridge name');
});

test('admin SQL archives first and permanently deletes only into an ingestion tombstone', async () => {
  const sql = await readFile(new URL('../db/admin-edits.sql', import.meta.url), 'utf8');
  const ingestion = await readFile(new URL('../db/ingestion-tombstones.sql', import.meta.url), 'utf8');
  assert.match(sql, /deleted_at = now\(\)/);
  assert.match(sql, /p_action = 'restore_raid'[\s\S]*deleted_at = null/);
  assert.match(sql, /'raid', p_raid_id::text, 'restored'/);
  assert.match(sql, /p_action = 'purge_raid'[\s\S]*v_raid\.deleted_at is null[\s\S]*insert into public\.apoc_raid_tombstones[\s\S]*delete from public\.apoc_raids as r[\s\S]*r\.deleted_at is not null/i);
  assert.match(sql, /p_action = 'purge_raid'[\s\S]*from public\.apoc_raid_tombstones as t[\s\S]*return jsonb_build_object\('status', 'ok'\)/i);
  assert.match(sql, /'raid', p_raid_id::text, 'purged'/);
  assert.match(sql, /m\.status = 'active' and m\.role = 'admin' for share/);
  assert.match(sql, /insert into public\.apoc_drop_corrections/);
  assert.match(sql, /security invoker/);
  assert.match(sql, /grant execute on function public\.admin_apoc_edit[\s\S]*to service_role/);
  assert.match(ingestion, /enable row level security/);
  assert.match(ingestion, /revoke all on public\.apoc_raid_tombstones from public, anon, authenticated/);
  assert.match(ingestion, /rename to ingest_apoc_raid_core/);
  assert.match(ingestion, /from public\.apoc_raid_tombstones as t[\s\S]*upload_status := 'duplicate'/);
});
