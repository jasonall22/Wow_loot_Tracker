import { badRequest, errorResponse, jsonResponse, notFound, unavailable } from './errors.mjs';
import { requireID, permissionsFor, requirePermission } from './permissions.mjs';
import { bearerToken, loadConfig, createSupabaseBackend } from './supabase.mjs';
import {
  scopedRows, guildProjection, membershipProjection, raidProjection,
  dropProjection, memberProjection, visitProjection, comparisonProjection,
} from './projections.mjs';

const CHILDREN = { drops: dropProjection, members: memberProjection, visits: visitProjection, comparisons: comparisonProjection };

function parseQuery(request) {
  const params = new URL(request.url).searchParams;
  const view = params.get('view') ?? 'guilds';
  const allowed = ['guilds', 'context', 'raids', 'raid', ...Object.keys(CHILDREN)];
  if (!allowed.includes(view)) throw badRequest();
  const keys = new Set(['view']);
  if (view !== 'guilds') keys.add('guild');
  if (view === 'raid' || Object.hasOwn(CHILDREN, view)) keys.add('raid');
  const paginated = view === 'raids' || Object.hasOwn(CHILDREN, view);
  if (paginated) { keys.add('limit'); keys.add('offset'); }
  for (const key of params.keys()) if (!keys.has(key) || params.getAll(key).length !== 1) throw badRequest();
  function integer(name, fallback, min, max) {
    if (!params.has(name)) return fallback;
    const value = params.get(name);
    if (!/^\d+$/.test(value) || Number(value) < min || Number(value) > max) throw badRequest();
    return Number(value);
  }
  return {
    view,
    guildID: view === 'guilds' ? null : requireID(params.get('guild')),
    raidID: keys.has('raid') ? requireID(params.get('raid')) : null,
    paging: { limit: integer('limit', 50, 1, 200), offset: integer('offset', 0, 0, 100000) },
  };
}

// No mutable global user, session, membership, cache, or service-role client.
// Every data request retains the user's token so database RLS remains in force.
export function createPortalHandler({ backendFactory = () => createSupabaseBackend({ config: loadConfig() }) } = {}) {
  return async function handle(request) {
    if (request.method !== 'GET') return jsonResponse({ error: { code: 'method_not_allowed', message: 'This foundation exposes read-only endpoints.' } }, 405, { Allow: 'GET' });
    try {
      const token = bearerToken(request);
      const { view, guildID, raidID, paging } = parseQuery(request);
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      if (view === 'guilds') {
        const memberships = await backend.memberships(principal, token);
        if (!Array.isArray(memberships) || memberships.length > 100) throw unavailable();
        const result = [];
        for (const member of memberships) {
          const permissions = permissionsFor(principal, member, member.guild_id);
          if (!permissions.viewRaids) continue;
          const guild = await backend.guild(member.guild_id, token);
          if (!guild) continue; // Revoked between the two RLS-protected queries.
          if (guild.id !== member.guild_id) throw unavailable();
          result.push({ guild: guildProjection(guild), membership: membershipProjection(member), permissions });
        }
        return jsonResponse({ guilds: result });
      }
      const membership = await backend.membership(principal, guildID, token);
      const permissions = requirePermission(principal, membership, guildID,
        view === 'comparisons' ? 'viewComparisons' : 'viewRaids');
      if (view === 'context') {
        const guild = await backend.guild(guildID, token);
        if (!guild) throw notFound();
        if (guild.id !== guildID) throw unavailable();
        return jsonResponse({ guild: guildProjection(guild), membership: membershipProjection(membership), permissions });
      }
      if (view === 'raids') {
        const rows = scopedRows(await backend.raids(guildID, token, paging), guildID);
        return jsonResponse({ raids: rows.map(raidProjection), page: paging });
      }
      const raid = await backend.raid(guildID, raidID, token);
      if (!raid) throw notFound();
      if (raid.id !== raidID || raid.guild_id !== guildID) throw unavailable();
      if (view === 'raid') return jsonResponse({ raid: raidProjection(raid), permissions });
      const rows = scopedRows(await backend[view](guildID, raidID, token, paging), guildID, raidID);
      return jsonResponse({ [view]: rows.map(CHILDREN[view]), page: paging });
    } catch (error) { return errorResponse(error); }
  };
}
