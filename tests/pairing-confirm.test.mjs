import test from 'node:test';
import assert from 'node:assert/strict';
import { createPairingConfirmHandler } from '../api/pairing-confirm.js';
import { digestSecret } from '../src/ingestion.mjs';

const challenge = 'challenge-token-' + 'x'.repeat(32);
const guild = '20000000-0000-4000-8000-000000000001';
const device = '40000000-0000-4000-8000-000000000001';

test('confirmation requires an exact POST body', async () => {
  const handle = createPairingConfirmHandler();
  assert.equal((await handle(new Request('https://example.test'))).status, 405);
  assert.equal((await handle(new Request('https://example.test', { method: 'POST', body: JSON.stringify({ challenge, label: 'PC', extra: true }) }))).status, 400);
});

test('confirmation returns a one-time device token after atomic consumption', async () => {
  const calls = [];
  const handle = createPairingConfirmHandler({
    serverConfig: () => ({ origin: 'https://vifojbecldfnfqnvtqpj.supabase.co', secretKey: 'sb_secret_test' }),
    random: () => Buffer.alloc(32, 9),
    fetchImpl: async (url, options) => { calls.push({ url, body: JSON.parse(options.body) }); return new Response(JSON.stringify([{ device_id: device, guild_id: guild }]), { status: 200 }); },
  });
  const response = await handle(new Request('https://example.test', { method: 'POST', body: JSON.stringify({ challenge, label: 'Master PC' }) }));
  assert.equal(response.status, 201);
  const data = await response.json();
  assert.equal(data.deviceId, device); assert.equal(data.guild, guild); assert.equal(data.deviceToken.length > 32, true);
  assert.equal(calls[0].body.p_challenge_digest, digestSecret(challenge));
  assert.equal(calls[0].body.p_token_digest, digestSecret(data.deviceToken));
});

test('unknown or already consumed challenges fail closed', async () => {
  const handle = createPairingConfirmHandler({
    serverConfig: () => ({ origin: 'https://vifojbecldfnfqnvtqpj.supabase.co', secretKey: 'sb_secret_test' }),
    fetchImpl: async () => new Response('[]', { status: 200 }),
  });
  const response = await handle(new Request('https://example.test', { method: 'POST', body: JSON.stringify({ challenge, label: 'PC' }) }));
  assert.equal(response.status, 401);
});
