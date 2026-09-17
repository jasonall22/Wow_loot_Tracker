import { jsonResponse, errorResponse, badRequest, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';
import { createPairingChallenge } from '../src/ingestion.mjs';

async function insertChallenge(config, row, fetchImpl = globalThis.fetch) {
  let response;
  try {
    response = await fetchImpl(`${config.origin}/rest/v1/apoc_pairing_challenges`, {
      method: 'POST',
      headers: {
        apikey: config.secretKey,
        Authorization: `Bearer ${config.secretKey}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal',
      },
      body: JSON.stringify(row),
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
    });
  } catch { throw unavailable(); }
  if (!response.ok) throw unavailable();
}

export function createPairingHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(),
  fetchImpl = globalThis.fetch,
  challengeFactory = createPairingChallenge,
} = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Pairing requires POST.' } }, 405, { Allow: 'POST' });
    try {
      const token = bearerToken(request);
      const body = await request.json().catch(() => { throw badRequest(); });
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw badRequest();
      const guildID = requireID(body.guild);
      if (Object.keys(body).some(key => key !== 'guild')) throw badRequest();
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, guildID, token);
      const permissions = requirePermission(principal, membership, guildID, 'uploadRaids');
      const challenge = challengeFactory();
      await insertChallenge(serverConfig(), {
        guild_id: guildID, challenge_digest: challenge.digest, created_by: principal.id,
        created_at: challenge.createdAt, expires_at: challenge.expiresAt,
      }, fetchImpl);
      return jsonResponse({ challenge: challenge.raw, expiresAt: challenge.expiresAt, guild: guildID }, 201);
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createPairingHandler() };
