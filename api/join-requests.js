import { badRequest, errorResponse, forbidden, jsonResponse, notFound, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission, validID } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

const ACTIONS = new Set(['approve', 'deny']);

export function parseJoinRequestAction(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length !== 3 ||
      !['guild', 'requestId', 'action'].every(key => Object.hasOwn(body, key)) || !ACTIONS.has(body.action)) throw badRequest();
  return { guild: requireID(body.guild), requestId: requireID(body.requestId), action: body.action };
}

export function createJoinRequestsHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (!['GET', 'POST'].includes(request.method)) return jsonResponse({ error: { code: 'method_not_allowed', message: 'Use GET or POST.' } }, 405, { Allow: 'GET, POST' });
    try {
      const token = bearerToken(request);
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      let input;
      if (request.method === 'GET') {
        const params = new URL(request.url).searchParams;
        if ([...params.keys()].length !== 1 || !params.has('guild')) throw badRequest();
        input = { guild: requireID(params.get('guild')), action: 'list', requestId: null };
      } else {
        if (Number(request.headers.get('content-length') ?? 0) > 8192) throw badRequest();
        input = parseJoinRequestAction(await request.json().catch(() => { throw badRequest(); }));
      }
      const membership = await backend.membership(principal, input.guild, token);
      requirePermission(principal, membership, input.guild, 'approveMembers');
      const config = serverConfig();
      let response;
      try {
        response = await fetchImpl(`${config.origin}/rest/v1/rpc/review_apoc_join_requests`, {
          method: 'POST', headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_actor: principal.id, p_guild_id: input.guild,
            p_action: input.action, p_request_id: input.requestId }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!response.ok) throw unavailable();
      const result = await response.json().catch(() => { throw unavailable(); });
      if (result?.status === 'forbidden') throw forbidden();
      if (result?.status === 'not_found') throw notFound();
      if (result?.status === 'invalid') throw badRequest();
      if (result?.status === 'already_reviewed') return jsonResponse({ error: { code: 'already_reviewed', message: 'Another officer already reviewed this request.' } }, 409);
      if (result?.status !== 'ok') throw unavailable();
      if (request.method === 'GET') {
        if (!Array.isArray(result.requests) || result.requests.length > 100 || result.requests.some(row =>
          !validID(row?.id) || !validID(row?.user_id) || typeof row.email !== 'string' || typeof row.character_name !== 'string')) throw unavailable();
        return jsonResponse({ requests: result.requests });
      }
      return jsonResponse({ status: 'ok', action: input.action });
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createJoinRequestsHandler() };
