import test from 'node:test';
import assert from 'node:assert/strict';
import { createMemberNameHandler, parseMemberNameUpdate } from '../api/member-name.js';
import { GUILD, OTHER_GUILD, OTHER_USER, USER, membership, principal, token } from './fixtures.mjs';

const config = { origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' };
const body = { guild: GUILD, userId: OTHER_USER, characterName: 'Newmain' };
const request = (value = body, method = 'POST') => new Request('https://portal.invalid/api/member-name', {
  method, headers: { Authorization: `Bearer ${token()}`, 'content-type': 'application/json' },
  ...(method === 'POST' ? { body: JSON.stringify(value) } : {}),
});

function setup({ role = 'admin', listMembers = [{ user_id: OTHER_USER }], fetchOverride } = {}) {
  const calls = [];
  const handler = createMemberNameHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => ({ ...membership, role }) }),
    serverConfig: () => config,
    fetchImpl: fetchOverride ?? (async (url, init) => {
      calls.push({ url, init });
      if (calls.length === 1) return Response.json({ status: 'ok', members: listMembers });
      if (init.method === 'GET') return Response.json({ id: OTHER_USER, user_metadata: {
        character_name: 'Oldmain', theme: 'dark', guild_character_names: { [OTHER_GUILD]: 'Othermain' },
      } });
      if (init.method === 'PUT') {
        const update = JSON.parse(init.body);
        return Response.json({ id: OTHER_USER, user_metadata: update.user_metadata });
      }
      return new Response(null, { status: 204 });
    }),
  });
  return { handler, calls };
}

test('admin can rename only an account listed in the selected guild', async () => {
  const { handler, calls } = setup();
  const response = await handler(request({ ...body, characterName: '  Morpheo  ' }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok', characterName: 'Morpheo' });
  assert.equal(calls[0].url, `${config.origin}/rest/v1/rpc/admin_apoc_members`);
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    p_actor: USER, p_guild_id: GUILD, p_action: 'list', p_target: null,
    p_role: null, p_status: null, p_can_upload: null, p_can_edit: null,
  });
  assert.equal(calls[1].url, `${config.origin}/auth/v1/admin/users/${OTHER_USER}`);
  assert.equal(calls[2].init.method, 'PUT');
  assert.deepEqual(JSON.parse(calls[2].init.body), { user_metadata: {
    character_name: 'Oldmain', theme: 'dark', guild_character_names: {
      [OTHER_GUILD]: 'Othermain', [GUILD]: 'Morpheo',
    },
  } });
  assert.equal(calls[3].init.method, 'PATCH');
});

test('members and officers cannot rename accounts', async () => {
  for (const role of ['member', 'officer']) {
    const { handler, calls } = setup({ role });
    assert.equal((await handler(request())).status, 403);
    assert.equal(calls.length, 0);
  }
});

test('admin cannot rename a user outside the selected guild', async () => {
  const { handler, calls } = setup({ listMembers: [{ user_id: USER }] });
  assert.equal((await handler(request())).status, 404);
  assert.equal(calls.length, 1);
});

test('invalid names, role claims, and identifiers are rejected before cloud writes', async () => {
  for (const invalid of [
    { ...body, characterName: 'A' },
    { ...body, characterName: 'Name with spaces' },
    { ...body, role: 'admin' },
    { ...body, guild: 'invalid' },
    { ...body, userId: 'invalid' },
  ]) assert.throws(() => parseMemberNameUpdate(invalid), { status: 400 });
  const { handler, calls } = setup();
  assert.equal((await handler(request({ ...body, role: 'admin' }))).status, 400);
  assert.equal(calls.length, 0);
});

test('member-name endpoint accepts POST only', async () => {
  const { handler, calls } = setup();
  const response = await handler(request(undefined, 'GET'));
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('allow'), 'POST');
  assert.equal(calls.length, 0);
});
