import test from 'node:test';
import assert from 'node:assert/strict';
import { createPairingHandler } from '../api/pairing.js';

const guild = '20000000-0000-4000-8000-000000000001';
const user = '10000000-0000-4000-8000-000000000001';
const jwt = 'a'.repeat(10) + '.' + Buffer.from(JSON.stringify({ sub: user, role: 'authenticated', aud: 'authenticated', iss: 'https://vifojbecldfnfqnvtqpj.supabase.co/auth/v1', exp: 2000000000 })).toString('base64url') + '.' + 'b'.repeat(10);

function handler({ permission = true, inserted = [] } = {}) {
  return createPairingHandler({
    backendFactory: () => ({
      authenticate: async () => ({ id: user, isAnonymous: false }),
      membership: async () => ({ guild_id: guild, user_id: user, role: permission ? 'admin' : 'member', status: 'active', can_upload: permission, can_edit: false }),
    }),
    serverConfig: () => ({ origin: 'https://vifojbecldfnfqnvtqpj.supabase.co', secretKey: 'sb_secret_test' }),
    challengeFactory: () => ({ raw: 'challenge-token', digest: 'a'.repeat(64), createdAt: '2026-09-17T14:00:00.000Z', expiresAt: '2026-09-17T14:05:00.000Z' }),
    fetchImpl: async (_url, options) => { inserted.push(JSON.parse(options.body)); return new Response(null, { status: 201 }); },
  });
}

test('pairing requires POST and an exact guild body', async () => {
  const handle = handler();
  assert.equal((await handle(new Request('https://example.test/api/pairing'))).status, 405);
  assert.equal((await handle(new Request('https://example.test/api/pairing', { method: 'POST', headers: { Authorization: `Bearer ${jwt}` }, body: JSON.stringify({ guild, extra: true }) }))).status, 400);
});

test('authorized uploader receives a short-lived challenge and only its digest is stored', async () => {
  const inserted = []; const response = await handler({ inserted })(new Request('https://example.test/api/pairing', { method: 'POST', headers: { Authorization: `Bearer ${jwt}` }, body: JSON.stringify({ guild }) }));
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { challenge: 'challenge-token', expiresAt: '2026-09-17T14:05:00.000Z', guild });
  assert.equal(inserted[0].challenge_digest, 'a'.repeat(64));
  assert.equal(inserted[0].created_by, user);
  assert.equal(inserted[0].challenge, undefined);
});

test('member without upload capability is denied before insertion', async () => {
  const inserted = []; const response = await handler({ permission: false, inserted })(new Request('https://example.test/api/pairing', { method: 'POST', headers: { Authorization: `Bearer ${jwt}` }, body: JSON.stringify({ guild }) }));
  assert.equal(response.status, 403); assert.equal(inserted.length, 0);
});
