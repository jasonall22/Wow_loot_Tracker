import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createInviteHandler, parseInviteBody } from '../api/invite.js';
import { createAcceptInviteHandler } from '../api/accept-invite.js';
import { GUILD, OTHER_GUILD, USER, membership, principal, token } from './fixtures.mjs';

const config = { origin: 'https://exampleproject.supabase.co', publishableKey: 'sb_publishable_test', secretKey: 'sb_secret_test' };
const inviteRequest = (body = { guild: GUILD, email: 'new@example.test' }) => new Request('https://portal.invalid/api/invite', {
  method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'content-type': 'application/json' }, body: JSON.stringify(body),
});
const acceptRequest = () => new Request('https://portal.invalid/api/accept-invite', {
  method: 'POST', headers: { Authorization: `Bearer ${token()}` },
});

test('invites require a current admin, exact fields, and normalized email', async () => {
  const calls = [];
  const handler = createInviteHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => membership }), serverConfig: () => config,
    fetchImpl: async (...args) => { calls.push(args); return Response.json({ status: 'ok' }); },
  });
  assert.equal((await handler(inviteRequest())).status, 403);
  assert.equal(calls.length, 0);
  assert.throws(() => parseInviteBody({ guild: GUILD, email: 'a@b.c', role: 'admin' }), { status: 400 });
  assert.throws(() => parseInviteBody({ guild: GUILD, email: 'bad address' }), { status: 400 });
  assert.deepEqual(parseInviteBody({ guild: GUILD, email: ' NEW@Example.Test ' }), { guild: GUILD, email: 'new@example.test' });
});

test('admin preparation precedes email and never grants a role from request data', async () => {
  const calls = [];
  const handler = createInviteHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async (_, guild) => guild === GUILD ? { ...membership, role: 'admin' } : null }),
    serverConfig: () => config,
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return calls.length === 1 ? Response.json({ status: 'ok' }) : Response.json({ id: USER, email: 'new@example.test' });
    },
  });
  assert.equal((await handler(inviteRequest({ guild: OTHER_GUILD, email: 'new@example.test' }))).status, 403);
  assert.equal(calls.length, 0);
  assert.equal((await handler(inviteRequest())).status, 200);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, `${config.origin}/rest/v1/rpc/admin_apoc_prepare_invite`);
  assert.deepEqual(JSON.parse(calls[0].init.body), { p_actor: USER, p_guild_id: GUILD, p_email: 'new@example.test' });
  assert.match(calls[1].url, /\/auth\/v1\/invite\?redirect_to=/);
  assert.deepEqual(JSON.parse(calls[1].init.body), { email: 'new@example.test' });
  assert.equal(calls[1].init.headers.apikey, config.secretKey);
  assert.equal(calls[1].init.headers.Authorization, undefined);
});

test('a rejected DB preparation does not send email', async () => {
  const calls = [];
  const handler = createInviteHandler({
    backendFactory: () => ({ authenticate: async () => principal,
      membership: async () => ({ ...membership, role: 'admin' }) }),
    serverConfig: () => config,
    fetchImpl: async (url) => { calls.push(url); return Response.json({ status: 'forbidden' }); },
  });
  assert.equal((await handler(inviteRequest())).status, 403);
  assert.equal(calls.length, 1);
});

test('acceptance uses only the confirmed Auth email for the verified user', async () => {
  const calls = [];
  const handler = createAcceptInviteHandler({
    backendFactory: () => ({ authenticate: async () => principal }), serverConfig: () => config,
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return calls.length === 1
        ? Response.json({ id: USER, email: 'NEW@Example.Test', role: 'authenticated', is_anonymous: false,
          email_confirmed_at: '2026-09-17T00:00:00Z' })
        : Response.json({ status: 'ok', joined: 1 });
    },
  });
  const response = await handler(acceptRequest());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).joined, 1);
  assert.equal(calls[0].url, `${config.origin}/auth/v1/user`);
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${token()}`);
  assert.deepEqual(JSON.parse(calls[1].init.body), { p_user_id: USER, p_email: 'new@example.test' });
  assert.equal(calls[1].init.headers.apikey, config.secretKey);
  assert.equal(calls[1].init.headers.Authorization, undefined);
});

test('unconfirmed or mismatched identities cannot claim an invitation', async () => {
  for (const user of [
    { id: USER, email: 'new@example.test', is_anonymous: false },
    { id: OTHER_GUILD, email: 'new@example.test', is_anonymous: false, email_confirmed_at: '2026-09-17T00:00:00Z' },
  ]) {
    const calls = [];
    const handler = createAcceptInviteHandler({
      backendFactory: () => ({ authenticate: async () => principal }), serverConfig: () => config,
      fetchImpl: async (url) => { calls.push(url); return Response.json(user); },
    });
    assert.equal((await handler(acceptRequest())).status, 401);
    assert.equal(calls.length, 1);
  }
});

test('invitation SQL never exposes pending emails to browser roles or self-promotes', async () => {
  const sql = await readFile(new URL('../db/member-invitations.sql', import.meta.url), 'utf8');
  assert.match(sql, /apoc_invitations enable row level security/);
  assert.match(sql, /revoke all on public\.apoc_invitations from public, anon, authenticated/);
  assert.match(sql, /role, status, can_upload, can_edit\)[\s\S]*?'member', 'active', false, false/);
  assert.match(sql, /on conflict \(guild_id, user_id\) do nothing/);
  assert.match(sql, /grant execute.*?to service_role/s);
  assert.doesNotMatch(sql, /security definer/i);
});
