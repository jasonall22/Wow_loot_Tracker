import test from 'node:test';
import assert from 'node:assert/strict';
import { createProfileHandler, parseProfileUpdate } from '../api/profile.js';
import { GUILD, OTHER_GUILD, USER, membership, principal, token } from './fixtures.mjs';

const config = { origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' };
const endpoint = `https://portal.invalid/api/profile?guild=${GUILD}`;

function request(method = 'GET', body = { guild: GUILD, characterName: 'Morpheo' }) {
  return new Request(method === 'GET' ? endpoint : 'https://portal.invalid/api/profile', {
    method, headers: { Authorization: `Bearer ${token()}`, 'content-type': 'application/json' },
    ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
  });
}

function handlerWith(fetchImpl, membershipResult = membership) {
  const backendCalls = [];
  const handler = createProfileHandler({
    backendFactory: () => ({
      authenticate: async () => { backendCalls.push('authenticate'); return principal; },
      membership: async () => { backendCalls.push('membership'); return membershipResult; },
    }),
    serverConfig: () => config,
    fetchImpl,
  });
  return { handler, backendCalls };
}

test('an active member can read their guild-scoped character name', async () => {
  const calls = [];
  const { handler, backendCalls } = handlerWith(async (url, init) => {
    calls.push({ url, init });
    return Response.json({ id: USER, user_metadata: {
      character_name: 'Legacyname', guild_character_names: { [GUILD]: 'Morpheo' },
    } });
  });
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { characterName: 'Morpheo' });
  assert.deepEqual(backendCalls, ['authenticate', 'membership']);
  assert.equal(calls[0].url, `${config.origin}/auth/v1/admin/users/${USER}`);
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${config.secretKey}`);
});

test('a member updates only their own display metadata and keeps permissions separate', async () => {
  const calls = [];
  const { handler } = handlerWith(async (url, init) => {
    calls.push({ url, init });
    if (init.method === 'GET') return Response.json({ id: USER, user_metadata: {
      character_name: 'Oldname', theme: 'dark', guild_character_names: { [OTHER_GUILD]: 'Othermain' },
    } });
    if (init.method === 'PUT') {
      const body = JSON.parse(init.body);
      return Response.json({ id: USER, user_metadata: body.user_metadata });
    }
    return new Response(null, { status: 204 });
  });
  const response = await handler(request('POST', { guild: GUILD, characterName: '  Morpheo  ' }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok', characterName: 'Morpheo' });
  assert.equal(calls[1].url, `${config.origin}/auth/v1/admin/users/${USER}`);
  assert.equal(calls[1].init.method, 'PUT');
  assert.deepEqual(JSON.parse(calls[1].init.body), { user_metadata: {
    character_name: 'Oldname', theme: 'dark', guild_character_names: {
      [OTHER_GUILD]: 'Othermain', [GUILD]: 'Morpheo',
    },
  } });
  assert.match(calls[2].url, new RegExp(`guild_id=eq\\.${GUILD}.*user_id=eq\\.${USER}`));
  assert.equal(calls[2].init.method, 'PATCH');
  assert.deepEqual(JSON.parse(calls[2].init.body), { character_name: 'Morpheo' });
});

test('profile updates reject role claims and invalid character names before cloud writes', async () => {
  for (const body of [
    { guild: GUILD, characterName: 'Morpheo', role: 'admin' },
    { guild: GUILD, characterName: 'A' },
    { guild: GUILD, characterName: 'Name with spaces' },
    { guild: 'invalid', characterName: 'Morpheo' },
  ]) assert.throws(() => parseProfileUpdate(body), { status: 400 });

  const calls = [];
  const { handler } = handlerWith(async (...args) => { calls.push(args); return Response.json({}); });
  const response = await handler(request('POST', { guild: GUILD, characterName: 'Morpheo', role: 'admin' }));
  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
});

test('missing, inactive, or cross-guild membership denies profile access before Auth admin calls', async () => {
  for (const deniedMembership of [null, { ...membership, status: 'revoked' }, { ...membership, guild_id: OTHER_GUILD }]) {
    const calls = [];
    const { handler } = handlerWith(async (...args) => { calls.push(args); return Response.json({}); }, deniedMembership);
    assert.equal((await handler(request())).status, 403);
    assert.equal((await handler(request('POST'))).status, 403);
    assert.equal(calls.length, 0);
  }
});

test('profile endpoint rejects unsupported methods', async () => {
  const { handler } = handlerWith(async () => Response.json({}));
  const response = await handler(new Request(endpoint, { method: 'DELETE', headers: { Authorization: `Bearer ${token()}` } }));
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('allow'), 'GET, POST');
});
