import { badRequest, errorResponse, forbidden, jsonResponse, notFound, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission, validID } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

const ROLES = new Set(['admin', 'officer', 'member']);
const STATUSES = new Set(['active', 'suspended', 'revoked']);

export function parseMemberUpdate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).length !== 6 ||
      !['guild', 'userId', 'role', 'status', 'canUpload', 'canEdit'].every(key => Object.hasOwn(body, key))) throw badRequest();
  const guild = requireID(body.guild);
  const userId = requireID(body.userId);
  if (!ROLES.has(body.role) || !STATUSES.has(body.status) ||
      typeof body.canUpload !== 'boolean' || typeof body.canEdit !== 'boolean' ||
      (body.role === 'member' && body.canEdit)) throw badRequest();
  return { guild, userId, role: body.role, status: body.status,
    canUpload: body.canUpload, canEdit: body.canEdit };
}

export function createMembersHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (!['GET', 'POST'].includes(request.method)) return jsonResponse({ error: { code: 'method_not_allowed', message: 'Use GET or POST.' } }, 405, { Allow: 'GET, POST' });
    try {
      const token = bearerToken(request);
      let input;
      if (request.method === 'GET') {
        const params = new URL(request.url).searchParams;
        if ([...params.keys()].length !== 1 || !params.has('guild')) throw badRequest();
        input = { guild: requireID(params.get('guild')) };
      } else {
        if (Number(request.headers.get('content-length') ?? 0) > 8192) throw badRequest();
        input = parseMemberUpdate(await request.json().catch(() => { throw badRequest(); }));
      }
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, input.guild, token);
      requirePermission(principal, membership, input.guild, 'manageMembers');
      const config = serverConfig();
      let response;
      try {
        response = await fetchImpl(`${config.origin}/rest/v1/rpc/admin_apoc_members`, {
          method: 'POST',
          headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_actor: principal.id, p_guild_id: input.guild,
            p_action: request.method === 'GET' ? 'list' : 'update',
            p_target: input.userId ?? null, p_role: input.role ?? null,
            p_status: input.status ?? null, p_can_upload: input.canUpload ?? null,
            p_can_edit: input.canEdit ?? null }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!response.ok) throw unavailable();
      const result = await response.json().catch(() => { throw unavailable(); });
      if (result?.status === 'forbidden') throw forbidden();
      if (result?.status === 'not_found') throw notFound();
      if (result?.status === 'invalid') throw badRequest();
      if (result?.status === 'last_admin') return jsonResponse({ error: { code: 'last_admin', message: 'Keep at least one active administrator in the guild.' } }, 409);
      if (result?.status !== 'ok') throw unavailable();
      if (request.method === 'GET') {
        if (!Array.isArray(result.members) || result.members.length > 100 ||
            result.members.some(member => !validID(member?.user_id))) throw unavailable();
        const members = [];
        for (let i = 0; i < result.members.length; i += 8) {
          const batch = await Promise.all(result.members.slice(i, i + 8).map(async member => {
            let userResponse;
            try {
              userResponse = await fetchImpl(`${config.origin}/auth/v1/admin/users/${member.user_id}`, {
                method: 'GET', headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}` },
                cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
              });
            } catch { throw unavailable(); }
            if (!userResponse.ok) throw unavailable();
            const user = await userResponse.json().catch(() => { throw unavailable(); });
            if (user?.id !== member.user_id || typeof user.email !== 'string') throw unavailable();
            return { ...member, email: user.email };
          }));
          members.push(...batch);
        }
        return jsonResponse({ members });
      }
      return jsonResponse({ status: 'ok' });
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createMembersHandler() };
