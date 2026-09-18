import { errorResponse, jsonResponse, unauthorized, unavailable } from '../src/errors.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

export function createAcceptInviteHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Invitation acceptance requires POST.' } }, 405, { Allow: 'POST' });
    try {
      const token = bearerToken(request);
      if (Number(request.headers.get('content-length') ?? 0) > 0) return jsonResponse({ error: { code: 'invalid_request', message: 'No request body is expected.' } }, 400);
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const config = serverConfig();
      let identity;
      try {
        identity = await fetchImpl(`${config.origin}/auth/v1/user`, {
          method: 'GET', headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}` },
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
        });
      } catch { throw unavailable(); }
      if (!identity.ok) throw unauthorized();
      const user = await identity.json().catch(() => { throw unavailable(); });
      if (user?.id !== principal.id || user.is_anonymous !== false ||
          typeof user.email !== 'string' || !user.email_confirmed_at ||
          !Number.isFinite(Date.parse(user.email_confirmed_at))) throw unauthorized();

      let response;
      try {
        response = await fetchImpl(`${config.origin}/rest/v1/rpc/claim_apoc_invitations`, {
          method: 'POST',
          headers: { apikey: config.secretKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_user_id: principal.id, p_email: user.email.trim().toLowerCase() }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!response.ok) throw unavailable();
      const result = await response.json().catch(() => { throw unavailable(); });
      if (result?.status !== 'ok' || !Number.isInteger(result.joined) || result.joined < 0) throw unavailable();
      return jsonResponse({ status: 'ok', joined: result.joined });
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createAcceptInviteHandler() };
