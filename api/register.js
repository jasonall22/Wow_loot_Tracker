import { badRequest, errorResponse, jsonResponse, unavailable } from '../src/errors.mjs';
import { requireID, validID } from '../src/permissions.mjs';
import { loadServerConfig } from '../src/supabase.mjs';

const REDIRECT_TO = 'https://www.wowguildloot.app/';
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const CHARACTER = /^\p{L}[\p{L}'-]{1,23}$/u;

export function parseRegistration(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length !== 4 ||
      !['guild', 'characterName', 'email', 'password'].every(key => Object.hasOwn(body, key))) throw badRequest();
  const guild = requireID(body.guild);
  if (typeof body.characterName !== 'string' || typeof body.email !== 'string' || typeof body.password !== 'string') throw badRequest();
  const characterName = body.characterName.trim();
  const email = body.email.trim().toLowerCase();
  if (!CHARACTER.test(characterName) || email.length < 3 || email.length > 254 || !EMAIL.test(email) ||
      body.password.length < 12 || body.password.length > 128) throw badRequest();
  return { guild, characterName, email, password: body.password };
}

function headers(key, bearer = false) {
  return { apikey: key, ...(bearer ? { Authorization: `Bearer ${key}` } : {}), 'Content-Type': 'application/json' };
}

export function createRegistrationHandler({ serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch } = {}) {
  return async function handle(request) {
    if (!['GET', 'POST'].includes(request.method)) {
      return jsonResponse({ error: { code: 'method_not_allowed', message: 'Use GET or POST.' } }, 405, { Allow: 'GET, POST' });
    }
    try {
      const config = serverConfig();
      if (request.method === 'GET') {
        let response;
        try {
          response = await fetchImpl(`${config.origin}/rest/v1/apoc_guilds?select=id,name,realm,faction&order=name.asc,realm.asc&limit=100`, {
            method: 'GET', headers: headers(config.secretKey, true), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
          });
        } catch { throw unavailable(); }
        if (!response.ok) throw unavailable();
        const guilds = await response.json().catch(() => { throw unavailable(); });
        if (!Array.isArray(guilds) || guilds.length > 100 || guilds.some(guild => !validID(guild?.id) || typeof guild.name !== 'string')) throw unavailable();
        return jsonResponse({ guilds: guilds.map(guild => ({ id: guild.id, name: guild.name, realm: guild.realm, faction: guild.faction })) });
      }

      if (Number(request.headers.get('content-length') ?? 0) > 8192) throw badRequest();
      const input = parseRegistration(await request.json().catch(() => { throw badRequest(); }));
      let signup;
      try {
        signup = await fetchImpl(`${config.origin}/auth/v1/signup?redirect_to=${encodeURIComponent(REDIRECT_TO)}`, {
          method: 'POST', headers: headers(config.publishableKey),
          body: JSON.stringify({ email: input.email, password: input.password, data: { character_name: input.characterName } }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!signup.ok) {
        if ([400, 409, 422].includes(signup.status)) return jsonResponse({ error: { code: 'account_not_created',
          message: 'The account could not be created. If you already registered, sign in instead.' } }, 409);
        throw unavailable();
      }
      const created = await signup.json().catch(() => { throw unavailable(); });
      const user = created?.user ?? created;
      if (!validID(user?.id) || typeof user.email !== 'string' || user.email.trim().toLowerCase() !== input.email) throw unavailable();

      let requestResult;
      try {
        requestResult = await fetchImpl(`${config.origin}/rest/v1/rpc/create_apoc_join_request`, {
          method: 'POST', headers: headers(config.secretKey, true),
          body: JSON.stringify({ p_user_id: user.id, p_guild_id: input.guild,
            p_email: input.email, p_character_name: input.characterName }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!requestResult.ok) throw unavailable();
      const result = await requestResult.json().catch(() => { throw unavailable(); });
      if (result?.status === 'invalid') throw badRequest();
      if (result?.status === 'already_member') return jsonResponse({ error: { code: 'already_member', message: 'This account already has guild access. Sign in instead.' } }, 409);
      if (result?.status !== 'ok') throw unavailable();

      // Tokens returned when email confirmation is disabled stay server-side and are
      // revoked; approval never depends on client-controlled Auth metadata.
      if (typeof created.access_token === 'string') {
        fetchImpl(`${config.origin}/auth/v1/logout?scope=local`, {
          method: 'POST', headers: { apikey: config.publishableKey, Authorization: `Bearer ${created.access_token}` },
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
        }).catch(() => {});
      }
      return jsonResponse({ status: 'pending', confirmationRequired: !created.access_token,
        message: created.access_token
          ? 'Account created. An officer or admin must approve it before you can enter the guild portal.'
          : 'Account created. Check your email to confirm it, then wait for an officer or admin to approve it.' }, 201);
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createRegistrationHandler() };
