import { randomBytes } from 'node:crypto';
import { jsonResponse, errorResponse, badRequest, unauthorized, unavailable } from '../src/errors.mjs';
import { digestSecret } from '../src/ingestion.mjs';
import { loadServerConfig } from '../src/supabase.mjs';

async function consume(config, challengeDigest, label, tokenDigest, fetchImpl = globalThis.fetch) {
  let response;
  try {
    response = await fetchImpl(`${config.origin}/rest/v1/rpc/consume_apoc_pairing_challenge`, {
      method: 'POST',
      headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_challenge_digest: challengeDigest, p_label: label, p_token_digest: tokenDigest }),
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
    });
  } catch { throw unavailable(); }
  if (!response.ok) throw unavailable();
  const rows = await response.json().catch(() => { throw unavailable(); });
  if (!Array.isArray(rows) || rows.length > 1) throw unavailable();
  return rows[0] ?? null;
}

export function createPairingConfirmHandler({ serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch, random = randomBytes } = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Pairing confirmation requires POST.' } }, 405, { Allow: 'POST' });
    try {
      const body = await request.json().catch(() => { throw badRequest(); });
      if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => !['challenge', 'label'].includes(key)) ||
          typeof body.challenge !== 'string' || body.challenge.length < 32 || body.challenge.length > 4096 ||
          typeof body.label !== 'string' || body.label.length < 1 || body.label.length > 100) throw badRequest();
      const deviceToken = random(32).toString('base64url');
      const row = await consume(serverConfig(), digestSecret(body.challenge), body.label, digestSecret(deviceToken), fetchImpl);
      if (!row || typeof row.device_id !== 'string' || typeof row.guild_id !== 'string') throw unauthorized();
      return jsonResponse({ deviceToken, deviceId: row.device_id, guild: row.guild_id }, 201);
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createPairingConfirmHandler() };
