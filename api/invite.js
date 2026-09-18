import { badRequest, errorResponse, forbidden, jsonResponse, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission, validID } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';

const REDIRECT_TO = 'https://www.wowguildloot.app/';

export function parseInviteBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).length !== 2 || !Object.hasOwn(body, 'guild') || !Object.hasOwn(body, 'email')) throw badRequest();
  const guild = requireID(body.guild);
  if (typeof body.email !== 'string') throw badRequest();
  const email = body.email.trim().toLowerCase();
  if (email.length < 3 || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw badRequest();
  return { guild, email };
}

export function createInviteHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Invitations require POST.' } }, 405, { Allow: 'POST' });
    try {
      const token = bearerToken(request);
      if (Number(request.headers.get('content-length') ?? 0) > 8192) throw badRequest();
      const { guild, email } = parseInviteBody(await request.json().catch(() => { throw badRequest(); }));
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, guild, token);
      requirePermission(principal, membership, guild, 'manageMembers');
      const config = serverConfig();
      const headers = { apikey: config.secretKey, 'Content-Type': 'application/json' };
      let prepared;
      try {
        prepared = await fetchImpl(`${config.origin}/rest/v1/rpc/admin_apoc_prepare_invite`, {
          method: 'POST', headers,
          body: JSON.stringify({ p_actor: principal.id, p_guild_id: guild, p_email: email }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!prepared.ok) throw unavailable();
      const state = await prepared.json().catch(() => { throw unavailable(); });
      if (state?.status === 'forbidden') throw forbidden();
      if (state?.status === 'invalid') throw badRequest();
      if (state?.status !== 'ok') throw unavailable();

      // The invitation row is committed before an external email call. If email
      // delivery fails, retrying is safe; no membership is granted prematurely.
      let sent;
      try {
        sent = await fetchImpl(`${config.origin}/auth/v1/invite?redirect_to=${encodeURIComponent(REDIRECT_TO)}`, {
          method: 'POST', headers, body: JSON.stringify({ email }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!sent.ok) {
        if (sent.status === 422) return jsonResponse({ status: 'existing_account',
          message: 'This address may already have an account. Ask them to sign in to accept the guild invitation.' });
        return jsonResponse({ error: { code: 'email_not_sent', message: 'The invitation was saved, but email was not sent. Try again later.' } }, 503);
      }
      const user = await sent.json().catch(() => { throw unavailable(); });
      if (!validID(user?.id) || user.email?.trim().toLowerCase() !== email) throw unavailable();
      return jsonResponse({ status: 'sent' });
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createInviteHandler() };
