import test from 'node:test';
import assert from 'node:assert/strict';
import { createPortalHandler } from '../src/api.mjs';
import { unauthorized } from '../src/errors.mjs';
import { GUILD, OTHER_GUILD, RAID, OTHER_RAID, membership, raid, request, fakeBackend } from './fixtures.mjs';

const route = (view, guild = GUILD, id = RAID) => `?view=${view}&guild=${guild}${['raid','drops','members','visits','comparisons'].includes(view) ? `&raid=${id}` : ''}`;
function setup(overrides) {
  const { backend, calls } = fakeBackend(overrides);
  return { handle: createPortalHandler({ backendFactory: () => backend }), calls };
}

test('unauthenticated request is rejected before backend construction', async () => {
  const handle = createPortalHandler({ backendFactory() { throw new Error('must not be called'); } });
  assert.equal((await handle(request('', { headers: {} }))).status, 401);
});
test('missing cloud configuration is not replaced by a demo or localhost bypass', async () => {
  const handle = createPortalHandler({ backendFactory() { throw new Error('not configured'); } });
  assert.equal((await handle(request())).status, 503);
});
test('verified auth failure does not query memberships', async () => {
  const { handle, calls } = setup({ authenticate() { throw unauthorized(); } });
  assert.equal((await handle(request(route('raids')))).status, 401);
  assert.deepEqual(calls.map(x => x.method), ['authenticate']);
});
test('member sees guild list without auth IDs, hidden notes or trusted client role flags', async () => {
  const { handle } = setup({ guild: async () => ({ id: GUILD, name: 'Test', realm: 'Realm', faction: 'Horde', private_note: 'secret' }) });
  const response = await handle(request());
  assert.equal(response.status, 200);
  const text = await response.text();
  assert.ok(!text.includes('secret'));
  assert.ok(!text.includes('user_id'));
});
for (const view of ['context', 'raids', 'roster_members', 'roster_drops', 'raid', 'drops', 'members', 'visits']) {
  test(`ordinary member can request ${view}`, async () => {
    const { handle } = setup();
    assert.equal((await handle(request(route(view)))).status, 200);
  });
  test(`cross-guild ${view} denied before fetching records`, async () => {
    const { handle, calls } = setup();
    assert.equal((await handle(request(route(view, OTHER_GUILD)))).status, 403);
    assert.deepEqual(calls.map(x => x.method), ['authenticate', 'membership']);
  });
}
test('guild roster reads require membership and reject wrong-guild rows', async () => {
  const { handle } = setup({ roster_drops: async () => [{ guild_id: OTHER_GUILD, raid_id: RAID, id: 'secret' }] });
  assert.equal((await handle(request(route('roster_drops')))).status, 503);
  const { handle: other } = setup({ roster_members: async () => [{ guild_id: OTHER_GUILD, raid_id: RAID, name: 'secret' }] });
  assert.equal((await other(request(route('roster_members')))).status, 503);
});
test('only admins can list archived raids for their current guild', async () => {
  const member = setup();
  assert.equal((await member.handle(request(route('archived_raids')))).status, 403);
  assert.deepEqual(member.calls.map(x => x.method), ['authenticate', 'membership']);
  const crossGuild = setup({ membership: async () => ({ ...membership, role: 'admin' }) });
  assert.equal((await crossGuild.handle(request(route('archived_raids', OTHER_GUILD)))).status, 403);
  assert.deepEqual(crossGuild.calls.map(x => x.method), ['authenticate', 'membership']);
  const admin = setup({ membership: async () => ({ ...membership, role: 'admin' }) });
  const response = await admin.handle(request(route('archived_raids')));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.archived_raids[0].deleted_at, '2026-09-18T00:00:00Z');
  assert.equal(admin.calls.at(-1).method, 'archived_raids');
});
for (const role of ['member', 'uploader']) test(`${role} cannot read comparison endpoint`, async () => {
  const { handle, calls } = setup({ membership: async () => ({ ...membership, can_upload: role === 'uploader' }) });
  assert.equal((await handle(request(route('comparisons')))).status, 403);
  assert.ok(!calls.some(x => x.method === 'comparisons' || x.method === 'raid'));
});
for (const role of ['officer', 'admin']) test(`${role} can request same-guild comparisons`, async () => {
  const { handle } = setup({ membership: async () => ({ ...membership, role }) });
  const response = await handle(request(route('comparisons')));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).comparisons[0].status, 'insufficient_data');
});
test('officer demotion is checked again on the next request', async () => {
  let role = 'officer';
  const { handle } = setup({ membership: async () => ({ ...membership, role }) });
  assert.equal((await handle(request(route('comparisons')))).status, 200);
  role = 'member';
  assert.equal((await handle(request(route('comparisons')))).status, 403);
});
test('revocation removes all guild access without waiting for a new JWT', async () => {
  let status = 'active';
  const { handle } = setup({ membership: async () => ({ ...membership, role: 'admin', status }) });
  assert.equal((await handle(request(route('raids')))).status, 200);
  status = 'revoked';
  assert.equal((await handle(request(route('raids')))).status, 403);
});
test('missing membership is denied', async () => {
  const { handle } = setup({ membership: async () => null });
  assert.equal((await handle(request(route('raids')))).status, 403);
});
test('raid not visible in the requested guild returns a generic 404', async () => {
  const { handle } = setup({ raid: async () => null });
  assert.equal((await handle(request(route('raid')))).status, 404);
});
test('adapter returning wrong raid or guild fails closed', async () => {
  for (const row of [{ ...raid, id: OTHER_RAID }, { ...raid, guild_id: OTHER_GUILD }]) {
    const { handle } = setup({ raid: async () => row });
    assert.equal((await handle(request(route('raid')))).status, 503);
  }
});
test('ordinary projections discard comparison fields even if adapter returns them', async () => {
  const { handle } = setup({ raids: async () => [{ ...raid, comparisons: [{ upgrade: 10 }], officer_notes: 'TOP_SECRET' }] });
  const text = await (await handle(request(route('raids')))).text();
  assert.ok(!text.includes('comparisons') && !text.includes('TOP_SECRET') && !text.includes('upgrade'));
});
test('wrong-guild child data fails closed', async () => {
  const { handle } = setup({ drops: async () => [{ guild_id: OTHER_GUILD, raid_id: RAID, id: 'x' }] });
  assert.equal((await handle(request(route('drops')))).status, 503);
});
test('pagination is bounded and forwarded to adapter', async () => {
  const { handle, calls } = setup();
  const response = await handle(request(`${route('drops')}&limit=10&offset=20`));
  assert.equal(response.status, 200);
  assert.deepEqual(calls.find(x => x.method === 'drops').args[3], { limit: 10, offset: 20 });
});
for (const query of ['?view=__proto__', '?view=raids', `${route('raids')}&role=admin`,
  `${route('raids')}&guild=${OTHER_GUILD}`, `${route('raids')}&limit=201`, `${route('raids')}&offset=-1`,
  `${route('raids')}&limit=1e2`, `${route('raid')}&raid=${OTHER_RAID}`]) {
  test(`rejects invalid/ambiguous query ${query}`, async () => {
    const { handle } = setup();
    assert.equal((await handle(request(query))).status, 400);
  });
}
test('write methods are unavailable, not accepted with a spoofed role', async () => {
  const { handle, calls } = setup();
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
    const response = await handle(request(route('raids'), { method }));
    assert.equal(response.status, 405);
    assert.equal(response.headers.get('allow'), 'GET');
  }
  assert.equal(calls.length, 0);
});
test('success and failure are private/no-store and do not enable cross-origin reads', async () => {
  const { handle } = setup();
  for (const req of [request(route('raids')), request('', { headers: {} })]) {
    const response = await handle(req);
    assert.match(response.headers.get('cache-control'), /no-store/);
    assert.equal(response.headers.get('vercel-cdn-cache-control'), 'no-store');
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  }
});
test('internal errors, URLs and secrets are never reflected in error body', async () => {
  const { handle } = setup({ raids() { throw new Error('postgres://password@host token=TOP_SECRET'); } });
  const response = await handle(request(route('raids')));
  assert.equal(response.status, 503);
  assert.ok(!(await response.text()).includes('TOP_SECRET'));
});
