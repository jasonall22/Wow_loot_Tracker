import test from 'node:test';
import assert from 'node:assert/strict';
import { bearerToken, createSupabaseBackend, loadConfig } from '../src/supabase.mjs';
import { createPortalHandler } from '../src/api.mjs';
import { config, token, request, principal, membership, USER, OTHER_USER, GUILD, RAID } from './fixtures.mjs';

const user = { id: USER, role: 'authenticated', is_anonymous: false, email_confirmed_at: '2026-09-01T12:00:00Z' };
function setup(responses) {
  const calls = [];
  const backend = createSupabaseBackend({ config, now: () => 1800000000000, fetchImpl: async (url, init) => {
    calls.push({ url: new URL(url), init });
    const result = responses.shift();
    if (result instanceof Error) throw result;
    return result;
  } });
  return { backend, calls };
}

test('unconfigured backend fails closed', () => {
  for (const env of [{}, { SUPABASE_URL: config.origin }, { SUPABASE_PUBLISHABLE_KEY: config.publishableKey }]) {
    assert.throws(() => loadConfig(env), { status: 503, code: 'cloud_not_configured' });
  }
});
test('configuration accepts only hosted HTTPS Supabase and a publishable key', () => {
  assert.deepEqual(loadConfig({ SUPABASE_URL: config.origin, SUPABASE_PUBLISHABLE_KEY: config.publishableKey }), config);
  for (const url of ['http://exampleproject.supabase.co', 'https://evil.invalid', `${config.origin}.evil.invalid`,
    `${config.origin}/rest/v1`, `${config.origin}?secret=x`, 'https://user:password@exampleproject.supabase.co']) {
    assert.throws(() => loadConfig({ SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: config.publishableKey }), { status: 503 });
  }
  for (const key of ['sb_secret_test', 'service_role', token({ role: 'service_role' })]) {
    assert.throws(() => loadConfig({ SUPABASE_URL: config.origin, SUPABASE_PUBLISHABLE_KEY: key }), { status: 503 });
  }
});
test('accepts only a single bounded bearer token, never cookie/query credentials', () => {
  assert.equal(bearerToken(request()), token());
  for (const authorization of ['', 'Basic anything', `Bearer ${token()}, ${token()}`, 'Bearer abc', `Bearer ${'a'.repeat(17000)}.b.c`]) {
    assert.throws(() => bearerToken(request('', { headers: { authorization } })), { status: 401 });
  }
  assert.throws(() => bearerToken(request(`?token=${token()}`, { headers: { cookie: `token=${token()}` } })), { status: 401 });
});
test('identity is accepted only after Auth verifies the supplied token; metadata is discarded', async () => {
  const { backend, calls } = setup([Response.json({ ...user, user_metadata: { role: 'admin' }, email: 'private@example.invalid' })]);
  assert.deepEqual(await backend.authenticate(token()), principal);
  assert.equal(calls[0].url.pathname, '/auth/v1/user');
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${token()}`);
  assert.equal(calls[0].init.headers.apikey, config.publishableKey);
  assert.equal(calls[0].init.cache, 'no-store');
  assert.equal(calls[0].init.redirect, 'error');
});
test('forged signature is rejected by Auth even with plausible decoded claims', async () => {
  const { backend } = setup([Response.json({ msg: 'bad signature' }, { status: 401 })]);
  await assert.rejects(backend.authenticate(token()), { status: 401 });
});
for (const [name, claims] of Object.entries({
  expired: { exp: 1700000000 }, future: { nbf: 2000000000 }, wrongIssuer: { iss: 'https://other.supabase.co/auth/v1' },
  wrongAudience: { aud: 'anon' }, serviceRole: { role: 'service_role' }, anonymous: { is_anonymous: true },
  noExpiry: { exp: null }, invalidSubject: { sub: 'wrong' }, stringExpiry: { exp: '2100000000' },
})) test(`${name} token fails before any network request`, async () => {
  const { backend, calls } = setup([]);
  await assert.rejects(backend.authenticate(token(claims)), { status: 401 });
  assert.equal(calls.length, 0);
});
test('invalid JSON claims fail before network', async () => {
  const { backend, calls } = setup([]);
  await assert.rejects(backend.authenticate('a.b.c'), { status: 401 });
  assert.equal(calls.length, 0);
});
for (const [name, change] of Object.entries({
  wrongUser: { id: OTHER_USER }, anonymous: { is_anonymous: true }, missingAnonymousFlag: { is_anonymous: undefined },
  unconfirmed: { email_confirmed_at: null }, invalidConfirmation: { email_confirmed_at: 'bad date' },
  privilegedRole: { role: 'service_role' },
})) test(`Auth response ${name} is rejected`, async () => {
  const { backend } = setup([Response.json({ ...user, ...change })]);
  await assert.rejects(backend.authenticate(token()), { status: 401 });
});
test('outages and malformed Auth responses do not create an offline login bypass', async () => {
  for (const result of [new Error('network blocked'), Response.json({}, { status: 500 }), new Response('not-json')]) {
    const { backend } = setup([result]);
    await assert.rejects(backend.authenticate(token()), { status: 503 });
  }
});
test('memberships are filtered by verified user and guild and keep the same user JWT', async () => {
  const { backend, calls } = setup([Response.json([membership])]);
  assert.deepEqual(await backend.membership(principal, GUILD, token()), membership);
  assert.equal(calls[0].url.searchParams.get('guild_id'), `eq.${GUILD}`);
  assert.equal(calls[0].url.searchParams.get('user_id'), `eq.${USER}`);
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${token()}`);
});
test('ambiguous membership data fails closed', async () => {
  const { backend } = setup([Response.json([membership, membership])]);
  await assert.rejects(backend.membership(principal, GUILD, token()), { status: 503 });
});
test('raid reads exclude archived raids and project persistent display names', async () => {
  const { backend, calls } = setup([Response.json([{ guild_id: GUILD, id: RAID, name: 'Bridge name', display_name: 'Admin name' }])]);
  const raids = await backend.raids(GUILD, token(), { limit: 50, offset: 0 });
  assert.equal(calls[0].url.searchParams.get('deleted_at'), 'is.null');
  assert.ok(calls[0].url.searchParams.get('select').includes('display_name'));
  assert.equal(raids[0].display_name, 'Admin name');
});
test('archived raid reads require deleted rows and newest deletion first', async () => {
  const { backend, calls } = setup([Response.json([])]);
  await backend.archived_raids(GUILD, token(), { limit: 50, offset: 0 });
  assert.equal(calls[0].url.searchParams.get('guild_id'), `eq.${GUILD}`);
  assert.equal(calls[0].url.searchParams.get('deleted_at'), 'not.is.null');
  assert.equal(calls[0].url.searchParams.get('order'), 'deleted_at.desc,id.asc');
  assert.ok(calls[0].url.searchParams.get('select').includes('deleted_at'));
});
for (const method of ['drops', 'members', 'visits', 'comparisons']) test(`${method} query includes both guild and raid, bounded pagination, and no wildcard select`, async () => {
  const { backend, calls } = setup([Response.json([])]);
  await backend[method](GUILD, RAID, token(), { limit: 50, offset: 10 });
  const { url, init } = calls[0];
  assert.equal(url.searchParams.get('guild_id'), `eq.${GUILD}`);
  assert.equal(url.searchParams.get('raid_id'), `eq.${RAID}`);
  assert.equal(url.searchParams.get('source_present'), method === 'drops' ? 'eq.true' : null);
  assert.equal(url.searchParams.get('limit'), '50');
  assert.equal(url.searchParams.get('offset'), '10');
  assert.ok(!url.searchParams.get('select').includes('*'));
  assert.equal(init.headers.Authorization, `Bearer ${token()}`);
});
for (const method of ['guild_roster', 'roster_members', 'roster_drops']) test(`${method} is guild-filtered and keeps the user JWT`, async () => {
  const { backend, calls } = setup([Response.json([])]);
  await backend[method](GUILD, token(), { limit: 50, offset: 10 });
  const { url, init } = calls[0];
  assert.equal(url.searchParams.get('guild_id'), `eq.${GUILD}`);
  assert.equal(url.searchParams.get('limit'), '50');
  assert.equal(url.searchParams.get('offset'), '10');
  assert.ok(!url.searchParams.get('select').includes('*'));
  assert.equal(init.headers.Authorization, `Bearer ${token()}`);
});
test('API to real adapter to mocked Auth and REST response works without trusting metadata', async () => {
  const { backend, calls } = setup([
    Response.json({ ...user, user_metadata: { role: 'admin' } }),
    Response.json([membership]),
    Response.json([{ id: GUILD, name: 'Fixture', realm: 'Realm', faction: 'Horde' }]),
  ]);
  const handle = createPortalHandler({ backendFactory: () => backend });
  const response = await handle(request(`?view=context&guild=${GUILD}`));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).permissions.viewComparisons, false);
  assert.equal(calls.length, 3);
  assert.ok(calls.every(x => x.init.headers.Authorization === `Bearer ${token()}`));
});
test('concurrent requests keep distinct user tokens and memberships', async () => {
  const tokens = [token(), token({ sub: OTHER_USER })];
  const backend = createSupabaseBackend({ config, fetchImpl: async (url, init) => {
    const id = init.headers.Authorization === `Bearer ${tokens[0]}` ? USER : OTHER_USER;
    if (new URL(url).pathname === '/auth/v1/user') return Response.json({ ...user, id });
    if (new URL(url).pathname === '/rest/v1/apoc_memberships') return Response.json([{ ...membership, user_id: id, role: id === USER ? 'officer' : 'member' }]);
    return Response.json([{ id: GUILD, name: 'Fixture', realm: 'Realm', faction: 'Horde' }]);
  } });
  const handle = createPortalHandler({ backendFactory: () => backend });
  const responses = await Promise.all(tokens.map(t => handle(request(`?view=context&guild=${GUILD}`, { headers: { Authorization: `Bearer ${t}` } }))));
  const bodies = await Promise.all(responses.map(r => r.json()));
  assert.deepEqual(bodies.map(body => body.permissions.viewComparisons), [true, false]);
});
