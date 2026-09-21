import { jsonResponse, errorResponse, badRequest, forbidden, notFound, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

const TYPES = new Set(['MS', 'OS', 'DE', 'GB', 'UNKNOWN']);

function exactKeys(value, expected) {
  return value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === expected.length
    && expected.every(key => Object.hasOwn(value, key));
}

export function parseAdminBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw badRequest();
  const guild = requireID(body.guild);
  const raid = requireID(body.raid);
  const action = body.action;
  if (action === 'rename_raid') {
    if (!exactKeys(body, ['guild', 'raid', 'action', 'name']) || typeof body.name !== 'string') throw badRequest();
    const name = body.name.trim();
    if (!name || name.length > 300) throw badRequest();
    return { guild, raid, action, payload: { name } };
  }
  if (action === 'delete_raid') {
    if (!exactKeys(body, ['guild', 'raid', 'action'])) throw badRequest();
    return { guild, raid, action, payload: {} };
  }
  if (action === 'restore_raid') {
    if (!exactKeys(body, ['guild', 'raid', 'action'])) throw badRequest();
    return { guild, raid, action, payload: {} };
  }
  if (action === 'edit_drop') {
    if (!exactKeys(body, ['guild', 'raid', 'action', 'dropId', 'winner', 'awardType', 'awardNote'])) throw badRequest();
    if (typeof body.dropId !== 'string' || !body.dropId || body.dropId.length > 200
        || ![null, 'string'].includes(body.winner === null ? null : typeof body.winner)
        || ![null, 'string'].includes(body.awardType === null ? null : typeof body.awardType)
        || typeof body.awardNote !== 'string' || body.awardNote.length > 2000) throw badRequest();
    const winner = body.winner?.trim() || null;
    const awardType = body.awardType || null;
    if ((winner && winner.length > 200) || (awardType && !TYPES.has(awardType))
        || (!awardType && winner) || (['MS', 'OS'].includes(awardType) && !winner)) throw badRequest();
    return { guild, raid, action, payload: { dropId: body.dropId, winner, awardType, awardNote: body.awardNote } };
  }
  throw badRequest();
}

export function createAdminHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Admin edits require POST.' } }, 405, { Allow: 'POST' });
    try {
      const token = bearerToken(request);
      if (Number(request.headers.get('content-length') ?? 0) > 8192) throw badRequest();
      const body = await request.json().catch(() => { throw badRequest(); });
      const { guild, raid, action, payload } = parseAdminBody(body);
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, guild, token);
      requirePermission(principal, membership, guild, 'manageRaids');
      const config = serverConfig();
      let response;
      try {
        response = await fetchImpl(`${config.origin}/rest/v1/rpc/admin_apoc_edit`, {
          method: 'POST', headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_actor: principal.id, p_guild_id: guild, p_raid_id: raid, p_action: action, p_payload: payload }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!response.ok) throw unavailable();
      const result = await response.json().catch(() => { throw unavailable(); });
      if (result?.status === 'forbidden') throw forbidden();
      if (result?.status === 'not_found') throw notFound();
      if (result?.status === 'invalid') throw badRequest();
      if (result?.status !== 'ok') throw unavailable();
      return jsonResponse({ status: 'ok', name: result.name ?? null });
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createAdminHandler() };
