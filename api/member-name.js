import { badRequest, errorResponse, forbidden, jsonResponse, notFound, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission, validID } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

const CHARACTER = /^\p{L}[\p{L}'-]{1,23}$/u;

export function parseMemberNameUpdate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).length !== 3 ||
      !['guild', 'userId', 'characterName'].every(key => Object.hasOwn(body, key)) ||
      typeof body.characterName !== 'string') throw badRequest();
  const characterName = body.characterName.trim();
  if (!CHARACTER.test(characterName)) throw badRequest();
  return { guild: requireID(body.guild), userId: requireID(body.userId), characterName };
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
  return typeof scoped === 'string' && CHARACTER.test(scoped) ? scoped : null;
}

export function createMemberNameHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') {
      return jsonResponse({ error: { code: 'method_not_allowed', message: 'Use POST.' } }, 405, { Allow: 'POST' });
    }
    try {
      if (Number(request.headers.get('content-length') ?? 0) > 4096) throw badRequest();
      const token = bearerToken(request);
      const input = parseMemberNameUpdate(await request.json().catch(() => { throw badRequest(); }));
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, input.guild, token);
      requirePermission(principal, membership, input.guild, 'manageMembers');
      const config = serverConfig();

      let listResponse;
      try {
        listResponse = await fetchImpl(`${config.origin}/rest/v1/rpc/admin_apoc_members`, {
          method: 'POST', headers: authHeaders(config.secretKey, true),
          body: JSON.stringify({ p_actor: principal.id, p_guild_id: input.guild,
            p_action: 'list', p_target: null, p_role: null, p_status: null,
            p_can_upload: null, p_can_edit: null }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!listResponse.ok) throw unavailable();
      const list = await listResponse.json().catch(() => { throw unavailable(); });
      if (list?.status === 'forbidden') throw forbidden();
      if (list?.status !== 'ok' || !Array.isArray(list.members) || list.members.length > 100 ||
          list.members.some(member => !validID(member?.user_id))) throw unavailable();
      if (!list.members.some(member => member.user_id === input.userId)) throw notFound();

      let userResponse;
      try {
        userResponse = await fetchImpl(`${config.origin}/auth/v1/admin/users/${input.userId}`, {
          method: 'GET', headers: authHeaders(config.secretKey), cache: 'no-store',
          redirect: 'error', signal: AbortSignal.timeout(8000),
        });
      } catch { throw unavailable(); }
      if (!userResponse.ok) throw unavailable();
      const user = await userResponse.json().catch(() => { throw unavailable(); });
      if (user?.id !== input.userId) throw unavailable();

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
        updateResponse = await fetchImpl(`${config.origin}/auth/v1/admin/users/${input.userId}`, {
          method: 'PUT', headers: authHeaders(config.secretKey, true),
          body: JSON.stringify({ user_metadata: userMetadata }), cache: 'no-store',
          redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!updateResponse.ok) throw unavailable();
      const updated = await updateResponse.json().catch(() => { throw unavailable(); });
      if (updated?.id !== input.userId || guildCharacterName(updated, input.guild) !== input.characterName) throw unavailable();

      try {
        await fetchImpl(`${config.origin}/rest/v1/apoc_join_requests?guild_id=eq.${encodeURIComponent(input.guild)}&user_id=eq.${encodeURIComponent(input.userId)}&status=eq.approved`, {
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

export default { fetch: createMemberNameHandler() };
