import { badRequest, errorResponse, jsonResponse, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission, validID } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

const CHARACTER = /^\p{L}[\p{L}'-]{1,23}$/u;

function validCharacterName(value) {
  return typeof value === 'string' && CHARACTER.test(value);
}

export function parseProfileUpdate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).length !== 2 ||
      !['guild', 'characterName'].every(key => Object.hasOwn(body, key)) ||
      typeof body.characterName !== 'string') throw badRequest();
  const characterName = body.characterName.trim();
  if (!validCharacterName(characterName)) throw badRequest();
  return { guild: requireID(body.guild), characterName };
}

function authHeaders(secretKey, json = false) {
  return {
    apikey: secretKey,
    Authorization: `Bearer ${secretKey}`,
    ...(json ? { 'Content-Type': 'application/json' } : {}),
  };
}

function guildCharacterName(user, guild) {
  const scoped = user?.user_metadata?.guild_character_names?.[guild];
  if (validCharacterName(scoped)) return scoped;
  const legacy = user?.user_metadata?.character_name;
  return validCharacterName(legacy) ? legacy : null;
}

export function createProfileHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (!['GET', 'POST'].includes(request.method)) {
      return jsonResponse({ error: { code: 'method_not_allowed', message: 'Use GET or POST.' } }, 405, { Allow: 'GET, POST' });
    }
    try {
      const token = bearerToken(request);
      let input;
      if (request.method === 'GET') {
        const params = new URL(request.url).searchParams;
        if ([...params.keys()].length !== 1 || !params.has('guild')) throw badRequest();
        input = { guild: requireID(params.get('guild')) };
      } else {
        if (Number(request.headers.get('content-length') ?? 0) > 4096) throw badRequest();
        input = parseProfileUpdate(await request.json().catch(() => { throw badRequest(); }));
      }

      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, input.guild, token);
      requirePermission(principal, membership, input.guild, 'viewRaids');
      const config = serverConfig();

      let userResponse;
      try {
        userResponse = await fetchImpl(`${config.origin}/auth/v1/admin/users/${principal.id}`, {
          method: 'GET', headers: authHeaders(config.secretKey), cache: 'no-store',
          redirect: 'error', signal: AbortSignal.timeout(8000),
        });
      } catch { throw unavailable(); }
      if (!userResponse.ok) throw unavailable();
      const user = await userResponse.json().catch(() => { throw unavailable(); });
      if (user?.id !== principal.id) throw unavailable();

      if (request.method === 'GET') {
        return jsonResponse({ characterName: guildCharacterName(user, input.guild) });
      }

      const currentMetadata = user.user_metadata && typeof user.user_metadata === 'object' && !Array.isArray(user.user_metadata)
        ? user.user_metadata : {};
      const currentGuildNames = currentMetadata.guild_character_names &&
        typeof currentMetadata.guild_character_names === 'object' && !Array.isArray(currentMetadata.guild_character_names)
        ? currentMetadata.guild_character_names : {};
      const userMetadata = {
        ...currentMetadata,
        guild_character_names: { ...currentGuildNames, [input.guild]: input.characterName },
      };

      let updateResponse;
      try {
        updateResponse = await fetchImpl(`${config.origin}/auth/v1/admin/users/${principal.id}`, {
          method: 'PUT', headers: authHeaders(config.secretKey, true),
          body: JSON.stringify({ user_metadata: userMetadata }), cache: 'no-store',
          redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!updateResponse.ok) throw unavailable();
      const updated = await updateResponse.json().catch(() => { throw unavailable(); });
      if (!validID(updated?.id) || updated.id !== principal.id ||
          guildCharacterName(updated, input.guild) !== input.characterName) throw unavailable();

      // Keep approved registration records current as a fallback label. Legacy
      // invited accounts may not have a request row, which is expected.
      try {
        await fetchImpl(`${config.origin}/rest/v1/apoc_join_requests?guild_id=eq.${encodeURIComponent(input.guild)}&user_id=eq.${encodeURIComponent(principal.id)}&status=eq.approved`, {
          method: 'PATCH', headers: { ...authHeaders(config.secretKey, true), Prefer: 'return=minimal' },
          body: JSON.stringify({ character_name: input.characterName }), cache: 'no-store',
          redirect: 'error', signal: AbortSignal.timeout(8000),
        });
      } catch {
        // Auth metadata is authoritative; this compatibility update is best effort.
      }

      return jsonResponse({ status: 'ok', characterName: input.characterName });
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createProfileHandler() };
