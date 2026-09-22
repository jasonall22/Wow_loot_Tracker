import test from 'node:test';
import assert from 'node:assert/strict';
import { createJoinRequestsHandler, parseJoinRequestAction } from '../api/join-requests.js';
import { GUILD, OTHER_GUILD, USER, membership, principal, token } from './fixtures.mjs';

const REQUEST_ID = '33333333-3333-4333-8333-333333333333';
const config = { origin: 'https://exampleproject.supabase.co', secretKey: 'sb_secret_test' };
const getRequest = (guild = GUILD) => new Request(`https://portal.invalid/api/join-requests?guild=${guild}`, { headers: { Authorization: `Bearer ${token()}` } });
const postRequest = (body = { guild: GUILD, requestId: REQUEST_ID, action: 'approve' }) => new Request('https://portal.invalid/api/join-requests', {
  method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'content-type': 'application/json' }, body: JSON.stringify(body),
});

function setup(role, results = [{ status: 'ok', requests: [] }, { status: 'ok' }]) {
  const calls = [];
  const handler = createJoinRequestsHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async (_, guild) => guild === GUILD ? { ...membership, role } : null }),
    serverConfig: () => config,
    fetchImpl: async (url, init) => { calls.push({ url, init }); return Response.json(results[calls.length - 1]); },
  });
  return { handler, calls };
}

test('members cannot view or approve account requests', async () => {
  const { handler, calls } = setup('member');
  assert.equal((await handler(getRequest())).status, 403);
  assert.equal((await handler(postRequest())).status, 403);
  assert.equal(calls.length, 0);
});

test('officers and admins receive pending notifications and can approve members', async () => {
  for (const role of ['officer', 'admin']) {
    const pending = { id: REQUEST_ID, user_id: USER, email: 'member@example.test', character_name: 'Morpheo', created_at: '2026-09-22T12:00:00Z' };
    const { handler, calls } = setup(role, [{ status: 'ok', requests: [pending] }, { status: 'ok' }]);
    const list = await handler(getRequest());
    assert.deepEqual((await list.json()).requests, [pending]);
    assert.equal((await handler(postRequest())).status, 200);
    assert.equal(calls[0].url, `${config.origin}/rest/v1/rpc/review_apoc_join_requests`);
    assert.deepEqual(JSON.parse(calls[0].init.body), { p_actor: USER, p_guild_id: GUILD, p_action: 'list', p_request_id: null });
    assert.deepEqual(JSON.parse(calls[1].init.body), { p_actor: USER, p_guild_id: GUILD, p_action: 'approve', p_request_id: REQUEST_ID });
  }
});

test('requests are guild-scoped and exact approval actions only', async () => {
  assert.deepEqual(parseJoinRequestAction({ guild: GUILD, requestId: REQUEST_ID, action: 'deny' }), {
    guild: GUILD, requestId: REQUEST_ID, action: 'deny',
  });
  for (const body of [
    { guild: GUILD, requestId: REQUEST_ID, action: 'admin' },
    { guild: GUILD, requestId: REQUEST_ID, action: 'approve', role: 'admin' },
  ]) assert.throws(() => parseJoinRequestAction(body), { status: 400 });
  const { handler, calls } = setup('admin');
  assert.equal((await handler(getRequest(OTHER_GUILD))).status, 403);
  assert.equal(calls.length, 0);
});

test('a concurrently reviewed request returns an actionable conflict', async () => {
  const { handler } = setup('officer', [{ status: 'already_reviewed' }]);
  const response = await handler(postRequest());
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error.code, 'already_reviewed');
});
