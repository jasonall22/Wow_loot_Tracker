import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createMembersHandler, parseMemberUpdate } from '../api/members.js';
import { GUILD, OTHER_GUILD, USER, membership, principal, token } from './fixtures.mjs';

const endpoint = `https://portal.invalid/api/members?guild=${GUILD}`;
const update = { guild: GUILD, userId: USER, role: 'officer', status: 'active', canUpload: true, canEdit: true };
const request = (method = 'GET', body = update) => new Request(method === 'GET' ? endpoint : 'https://portal.invalid/api/members', {
  method, headers: { Authorization: `Bearer ${token()}`, 'content-type': 'application/json' },
  ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
});

function setup(role = 'admin', result = { status: 'ok', members: [] }) {
  const calls = [];
  const handler = createMembersHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => ({ ...membership, role }) }),
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async (url, init) => { calls.push({ url, init }); return Response.json(result); },
  });
  return { handler, calls };
}

test('member management is admin-only and guild-scoped before the service RPC', async () => {
  for (const role of ['member', 'officer']) {
    const { handler, calls } = setup(role);
    assert.equal((await handler(request())).status, 403);
    assert.equal((await handler(request('POST'))).status, 403);
    assert.equal(calls.length, 0);
  }
  const cross = setup();
  const crossRequest = new Request(`https://portal.invalid/api/members?guild=${OTHER_GUILD}`, { headers: { Authorization: `Bearer ${token()}` } });
  assert.equal((await cross.handler(crossRequest)).status, 403);
  assert.equal(cross.calls.length, 0);
});

test('valid list and update use server-only key and verified actor', async () => {
  const { handler, calls } = setup();
  assert.equal((await handler(request())).status, 200);
  assert.equal((await handler(request('POST'))).status, 200);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://exampleproject.supabase.co/rest/v1/rpc/admin_apoc_members');
  assert.equal(calls[0].init.headers.Authorization, 'Bearer sb_secret_test');
  assert.equal(JSON.parse(calls[0].init.body).p_actor, USER);
  assert.deepEqual(JSON.parse(calls[1].init.body), {
    p_actor: USER, p_guild_id: GUILD, p_action: 'update', p_target: USER,
    p_role: 'officer', p_status: 'active', p_can_upload: true, p_can_edit: true,
  });
});

test('profile metadata overrides the approved request name after the guild-scoped admin RPC', async () => {
  const calls = [];
  const handler = createMembersHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => ({ ...membership, role: 'admin' }) }),
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (calls.length === 1) return Response.json({ status: 'ok', members: [{ user_id: USER, role: 'admin', status: 'active', can_edit: false, can_upload: false }] });
      if (calls.length === 2) return Response.json([{ user_id: USER, character_name: 'Oldname' }]);
      return Response.json({ id: USER, user_metadata: { guild_character_names: { [GUILD]: 'Morpheo' } } });
    },
  });
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).members[0], {
    user_id: USER, role: 'admin', status: 'active', can_edit: false,
    can_upload: false, character_name: 'Morpheo', email: 'Morpheo',
  });
  assert.equal(calls[1].url, `https://exampleproject.supabase.co/rest/v1/apoc_join_requests?select=user_id,character_name&guild_id=eq.${GUILD}&status=eq.approved&limit=100`);
  assert.equal(calls[1].init.headers.Authorization, 'Bearer sb_secret_test');
  assert.equal(calls[2].url, `https://exampleproject.supabase.co/auth/v1/admin/users/${USER}`);
});

test('legacy invited members can use profile metadata without exposing email', async () => {
  const calls = [];
  const handler = createMembersHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => ({ ...membership, role: 'admin' }) }),
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (calls.length === 1) return Response.json({ status: 'ok', members: [{ user_id: USER, role: 'member', status: 'active', can_edit: false, can_upload: false }] });
      if (calls.length === 2) return Response.json([]);
      return Response.json({ id: USER, user_metadata: { character_name: 'Legacyname' } });
    },
  });
  const response = await handler(request());
  const member = (await response.json()).members[0];
  assert.equal(member.character_name, 'Legacyname');
  assert.equal(member.email, 'Legacyname');
  assert.doesNotMatch(member.email, /@/);
});

test('approved request name remains available when Auth profile lookup fails', async () => {
  const calls = [];
  const handler = createMembersHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => ({ ...membership, role: 'admin' }) }),
    serverConfig: () => ({ origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (calls.length === 1) return Response.json({ status: 'ok', members: [{ user_id: USER, role: 'member', status: 'active', can_edit: false, can_upload: false }] });
      if (calls.length === 2) return Response.json([{ user_id: USER, character_name: 'Fallback' }]);
      throw new Error('Auth temporarily unavailable');
    },
  });
  const member = (await (await handler(request())).json()).members[0];
  assert.equal(member.character_name, 'Fallback');
  assert.equal(member.email, 'Fallback');
});

test('invalid fields and self-promotion claims never reach RPC', async () => {
  for (const invalid of [
    { ...update, extra: 1 }, { ...update, role: 'owner' },
    { ...update, role: 'member', canEdit: true },
    { ...update, canUpload: 'true' }, { ...update, userId: 'invalid' },
  ]) assert.throws(() => parseMemberUpdate(invalid), { status: 400 });
  const { handler, calls } = setup();
  assert.equal((await handler(request('POST', { ...update, role: 'owner' }))).status, 400);
  assert.equal(calls.length, 0);
});

test('last-admin guard is an actionable conflict', async () => {
  const { handler } = setup('admin', { status: 'last_admin' });
  const response = await handler(request('POST'));
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error.code, 'last_admin');
});

test('database function serializes guild changes and audits membership updates', async () => {
  const sql = await readFile(new URL('../db/member-admin.sql', import.meta.url), 'utf8');
  assert.match(sql, /apoc_guilds where id = p_guild_id for update/);
  assert.match(sql, /m\.role = 'admin' and m\.status = 'active' for share/);
  assert.match(sql, /status', 'last_admin'/);
  assert.match(sql, /insert into public\.apoc_audit_events/);
  assert.match(sql, /grant execute.*?to service_role/s);
  assert.doesNotMatch(sql, /auth\.users/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete).*?authenticated/i);
});
