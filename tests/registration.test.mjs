import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRegistrationHandler, parseRegistration } from '../api/register.js';
import { GUILD, USER } from './fixtures.mjs';

const config = { origin: 'https://exampleproject.supabase.co', publishableKey: 'sb_publishable_test', secretKey: 'sb_secret_test' };
const registration = { guild: GUILD, characterName: 'Morpheo', email: 'member@example.test', password: 'a-strong-password' };
const request = (method = 'POST', body = registration) => new Request('https://portal.invalid/api/register', {
  method, headers: { 'content-type': 'application/json' }, ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
});

test('registration requires exact bounded guild, character, email, and password fields', () => {
  assert.deepEqual(parseRegistration({ ...registration, email: ' MEMBER@Example.Test ', characterName: ' Morpheo ' }), registration);
  for (const invalid of [
    { ...registration, extra: true }, { ...registration, guild: 'bad' }, { ...registration, characterName: 'A' },
    { ...registration, characterName: 'Name 2' }, { ...registration, email: 'bad' }, { ...registration, password: 'short' },
  ]) assert.throws(() => parseRegistration(invalid), { status: 400 });
});

test('public registration options expose only bounded guild identity fields', async () => {
  const calls = [];
  const handler = createRegistrationHandler({ serverConfig: () => config, fetchImpl: async (url, init) => {
    calls.push({ url, init });
    return Response.json([{ id: GUILD, name: 'APOC', realm: 'Nightslayer', faction: 'Horde', private_note: 'hidden' }]);
  } });
  const response = await handler(request('GET'));
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).guilds, [{ id: GUILD, name: 'APOC', realm: 'Nightslayer', faction: 'Horde' }]);
  assert.match(calls[0].url, /select=id,name,realm,faction/);
  assert.equal(calls[0].init.headers.Authorization, 'Bearer sb_secret_test');
});

test('signup captures character metadata but grants no membership before server-side approval', async () => {
  const calls = [];
  const handler = createRegistrationHandler({ serverConfig: () => config, fetchImpl: async (url, init) => {
    calls.push({ url, init });
    return calls.length === 1
      ? Response.json({ user: { id: USER, email: registration.email } })
      : Response.json({ status: 'ok', request_id: '33333333-3333-4333-8333-333333333333' });
  } });
  const response = await handler(request());
  assert.equal(response.status, 201);
  assert.equal((await response.json()).status, 'pending');
  assert.match(calls[0].url, /\/auth\/v1\/signup\?redirect_to=/);
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    email: registration.email, password: registration.password, data: { character_name: registration.characterName },
  });
  assert.equal(calls[0].init.headers.apikey, config.publishableKey);
  assert.equal(calls[1].url, `${config.origin}/rest/v1/rpc/create_apoc_join_request`);
  assert.deepEqual(JSON.parse(calls[1].init.body), {
    p_user_id: USER, p_guild_id: GUILD, p_email: registration.email, p_character_name: registration.characterName,
  });
  assert.equal(calls[1].init.headers.Authorization, 'Bearer sb_secret_test');
});

test('failed or duplicate signup never creates an approval request', async () => {
  const calls = [];
  const handler = createRegistrationHandler({ serverConfig: () => config, fetchImpl: async (url, init) => {
    calls.push({ url, init }); return Response.json({ msg: 'duplicate' }, { status: 422 });
  } });
  const response = await handler(request());
  assert.equal(response.status, 409);
  assert.equal(calls.length, 1);
});

test('join-request database contract is private and approval always creates a plain member', async () => {
  const sql = await readFile(new URL('../supabase/migrations/20260922144742_member_requests.sql', import.meta.url), 'utf8');
  assert.match(sql, /alter table public\.apoc_join_requests enable row level security/i);
  assert.match(sql, /revoke all on public\.apoc_join_requests from public, anon, authenticated/i);
  assert.match(sql, /values \(p_guild_id, v_request\.user_id, 'member', 'active', false, false\)/i);
  assert.match(sql, /m\.role in \('admin', 'officer'\) and m\.status = 'active'/i);
  assert.match(sql, /grant execute[\s\S]*to service_role/i);
  assert.doesNotMatch(sql, /grant (?:select|insert|update|delete|all)[\s\S]*to authenticated/i);
});
