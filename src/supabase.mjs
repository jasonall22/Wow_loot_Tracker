import { PortalError, unauthorized, unavailable } from './errors.mjs';
import { validID } from './permissions.mjs';
import { SELECT } from './projections.mjs';

export function loadConfig(env = process.env) {
  const missing = () => new PortalError(503, 'cloud_not_configured', 'This portal has not been connected to its dedicated cloud project yet.');
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) throw missing();
  let url;
  try { url = new URL(env.SUPABASE_URL); } catch { throw missing(); }
  // This foundation targets hosted Supabase, not arbitrary per-request URLs.
  if (url.protocol !== 'https:' || !/^[a-z0-9]+\.supabase\.co$/.test(url.hostname) ||
      url.port || url.username || url.password || !['', '/'].includes(url.pathname) || url.search || url.hash ||
      !/^sb_publishable_[A-Za-z0-9_-]+$/.test(env.SUPABASE_PUBLISHABLE_KEY)) throw missing();
  return { origin: url.origin, publishableKey: env.SUPABASE_PUBLISHABLE_KEY };
}

export function loadServerConfig(env = process.env) {
  const config = loadConfig(env);
  if (!/^sb_secret_[A-Za-z0-9_-]+$/.test(env.SUPABASE_SECRET_KEY ?? '')) {
    throw new PortalError(503, 'cloud_not_configured', 'This portal has not been connected to its dedicated cloud project yet.');
  }
  return { ...config, secretKey: env.SUPABASE_SECRET_KEY };
}

export function bearerToken(request) {
  const value = request.headers.get('authorization');
  const match = typeof value === 'string' && value.match(/^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/i);
  if (!match || match[1].length > 16384) throw unauthorized();
  return match[1];
}

function restrictedClaims(token, origin, now) {
  let claims;
  try { claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')); }
  catch { throw unauthorized(); }
  // Parsing is only a rejection filter. It is NOT signature verification.
  // The Auth /user request below must succeed before any identity is accepted.
  const audience = claims?.aud;
  if (!validID(claims?.sub) || claims.role !== 'authenticated' ||
      !(audience === 'authenticated' || (Array.isArray(audience) && audience.includes('authenticated'))) ||
      claims.iss !== `${origin}/auth/v1` || !Number.isFinite(claims.exp) || claims.exp <= now ||
      (claims.nbf !== undefined && (!Number.isFinite(claims.nbf) || claims.nbf > now)) ||
      claims.is_anonymous === true) throw unauthorized();
  return claims;
}

export function createSupabaseBackend({ config, fetchImpl = globalThis.fetch, now = () => Date.now() } = {}) {
  async function call(path, token, isAuth = false) {
    let response;
    try {
      response = await fetchImpl(`${config.origin}${path}`, {
        method: 'GET',
        headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, Accept: 'application/json' },
        cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000),
      });
    } catch { throw unavailable(); }
    if (!response.ok) {
      if (isAuth && [400, 401, 403].includes(response.status)) throw unauthorized();
      if (response.status === 401) throw unauthorized();
      throw unavailable();
    }
    try { return await response.json(); } catch { throw unavailable(); }
  }

  async function rows(table, fields, filters, token, paging = {}) {
    const query = new URLSearchParams({ select: fields, ...filters, ...paging });
    const result = await call(`/rest/v1/${table}?${query}`, token);
    if (!Array.isArray(result)) throw unavailable();
    return result;
  }

  return {
    async authenticate(token) {
      const claims = restrictedClaims(token, config.origin, Math.floor(now() / 1000));
      const user = await call('/auth/v1/user', token, true);
      if (!user || user.id !== claims.sub || user.role !== 'authenticated' || user.is_anonymous !== false ||
          !user.email_confirmed_at || !Number.isFinite(Date.parse(user.email_confirmed_at))) throw unauthorized();
      return { id: user.id, isAnonymous: false };
    },
    async memberships(principal, token) {
      return rows('apoc_memberships', SELECT.membership, { user_id: `eq.${principal.id}`, status: 'eq.active' }, token,
        { order: 'guild_id.asc', limit: '101' });
    },
    async membership(principal, guildID, token) {
      const result = await rows('apoc_memberships', SELECT.membership, {
        user_id: `eq.${principal.id}`, guild_id: `eq.${guildID}`,
      }, token, { limit: '2' });
      if (result.length > 1) throw unavailable();
      return result[0] ?? null;
    },
    async guild(guildID, token) {
      const result = await rows('apoc_guilds', SELECT.guild, { id: `eq.${guildID}` }, token, { limit: '2' });
      if (result.length > 1) throw unavailable();
      return result[0] ?? null;
    },
    async raids(guildID, token, { limit, offset }) {
      return rows('apoc_raids', SELECT.raid, { guild_id: `eq.${guildID}`, deleted_at: 'is.null' }, token,
        { order: 'created_at.desc,id.asc', limit: String(limit), offset: String(offset) });
    },
    async roster_members(guildID, token, { limit, offset }) {
      return rows('apoc_raid_members', SELECT.member, { guild_id: `eq.${guildID}` }, token,
        { order: 'raid_id.asc,character_key.asc', limit: String(limit), offset: String(offset) });
    },
    async roster_drops(guildID, token, { limit, offset }) {
      return rows('apoc_drops', SELECT.drop, { guild_id: `eq.${guildID}`, source_present: 'eq.true', winner: 'not.is.null' }, token,
        { order: 'awarded_at.desc,raid_id.asc,id.asc', limit: String(limit), offset: String(offset) });
    },
    async raid(guildID, raidID, token) {
      const result = await rows('apoc_raids', SELECT.raid, { guild_id: `eq.${guildID}`, id: `eq.${raidID}`, deleted_at: 'is.null' }, token, { limit: '2' });
      if (result.length > 1) throw unavailable();
      return result[0] ?? null;
    },
    async drops(guildID, raidID, token, paging) {
      return rows('apoc_drops', SELECT.drop, { guild_id: `eq.${guildID}`, raid_id: `eq.${raidID}`, source_present: 'eq.true' }, token,
        { order: 'dropped_at.asc,id.asc', limit: String(paging.limit), offset: String(paging.offset) });
    },
    async members(guildID, raidID, token, paging) {
      return rows('apoc_raid_members', SELECT.member, { guild_id: `eq.${guildID}`, raid_id: `eq.${raidID}` }, token,
        { order: 'character_key.asc', limit: String(paging.limit), offset: String(paging.offset) });
    },
    async visits(guildID, raidID, token, paging) {
      return rows('apoc_visits', SELECT.visit, { guild_id: `eq.${guildID}`, raid_id: `eq.${raidID}` }, token,
        { order: 'joined_at.asc,id.asc', limit: String(paging.limit), offset: String(paging.offset) });
    },
    async comparisons(guildID, raidID, token, paging) {
      return rows('apoc_comparisons', SELECT.comparison, { guild_id: `eq.${guildID}`, raid_id: `eq.${raidID}` }, token,
        { order: 'updated_at.desc,id.asc', limit: String(paging.limit), offset: String(paging.offset) });
    },
  };
}
