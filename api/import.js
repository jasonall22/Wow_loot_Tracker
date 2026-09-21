import { jsonResponse, errorResponse, badRequest, forbidden, unavailable } from '../src/errors.mjs';
import { requireID, requirePermission } from '../src/permissions.mjs';
import { bearerToken, createSupabaseBackend, loadConfig, loadServerConfig } from '../src/supabase.mjs';
import { databaseGuildRoster, databaseRecords } from '../src/ingestion.mjs';
import { syncGuildRoster } from '../src/guild-roster-sync.mjs';
import { normalizeRaidExport } from '../src/manual-import.mjs';

const MAX_IMPORT_REQUEST_BYTES = 1_048_576;

export function createImportHandler({
  backendFactory = () => createSupabaseBackend({ config: loadConfig() }),
  serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch,
} = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Import requires POST.' } }, 405, { Allow: 'POST' });
    try {
      const token = bearerToken(request);
      const length = request.headers.get('content-length');
      if (length && (!/^\d+$/.test(length) || Number(length) > MAX_IMPORT_REQUEST_BYTES)) throw badRequest();
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > MAX_IMPORT_REQUEST_BYTES) throw badRequest();
      let body;
      try { body = JSON.parse(raw); } catch { throw badRequest(); }
      if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length !== 2 ||
          !Object.hasOwn(body, 'guild') || !Object.hasOwn(body, 'export')) throw badRequest();
      const guild = requireID(body.guild);
      const upload = normalizeRaidExport(body.export);
      const backend = backendFactory();
      const principal = await backend.authenticate(token);
      const membership = await backend.membership(principal, guild, token);
      requirePermission(principal, membership, guild, 'uploadRaids');
      const config = serverConfig();
      let response;
      try {
        response = await fetchImpl(`${config.origin}/rest/v1/rpc/import_apoc_raid`, {
          method: 'POST',
          headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_actor: principal.id, p_guild_id: guild, p_export_guild: body.export.guild,
            p_request_id: upload.requestId, p_source_key: upload.sourceKey,
            p_source_revision: upload.sourceRevision, p_payload_hash: upload.payloadHash,
            p_captured_at: upload.capturedAt, ...databaseRecords(upload) }),
          cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(15000),
        });
      } catch { throw unavailable(); }
      if (!response.ok) throw unavailable();
      const rows = await response.json().catch(() => { throw unavailable(); });
      if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.guild_id !== guild) throw unavailable();
      const result = rows[0];
      if (result.upload_status === 'forbidden') throw forbidden();
      if (!['accepted', 'duplicate', 'stale'].includes(result.upload_status)) throw unavailable();
      await syncGuildRoster({ config, fetchImpl, guildID: guild, capturedAt: upload.capturedAt,
        members: databaseGuildRoster(upload), timeout: 15000 });
      return jsonResponse({ status: result.upload_status, raid: result.raid_id }, result.upload_status === 'accepted' ? 201 : 200);
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createImportHandler() };
