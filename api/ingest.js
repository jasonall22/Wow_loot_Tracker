import { jsonResponse, errorResponse, unauthorized, unavailable } from '../src/errors.mjs';
import { databaseRecords, digestSecret, parseUploadBody } from '../src/ingestion.mjs';
import { loadServerConfig } from '../src/supabase.mjs';

const databasePayload = body => ({
  p_token_digest: digestSecret(body.deviceToken),
  p_request_id: body.requestId,
  p_source_key: body.sourceKey,
  p_source_revision: body.sourceRevision,
  p_payload_hash: body.payloadHash,
  p_captured_at: body.capturedAt,
  ...databaseRecords(body),
});

export function createIngestHandler({ serverConfig = () => loadServerConfig(), fetchImpl = globalThis.fetch } = {}) {
  return async function handle(request) {
    if (request.method !== 'POST') return jsonResponse({ error: { code: 'method_not_allowed', message: 'Upload requires POST.' } }, 405, { Allow: 'POST' });
    try {
      const match = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_-]{40,100})$/);
      if (!match) throw unauthorized();
      const body = await parseUploadBody(request);
      const config = serverConfig();
      const payload = databasePayload({ ...body, deviceToken: match[1] });
      let response;
      try {
        response = await fetchImpl(`${config.origin}/rest/v1/rpc/ingest_apoc_raid`, {
          method: 'POST',
          headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(payload), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
        });
      } catch { throw unavailable(); }
      if (!response.ok) throw unavailable();
      const rows = await response.json().catch(() => { throw unavailable(); });
      if (!Array.isArray(rows) || rows.length > 1) throw unavailable();
      const row = rows[0];
      if (!row) throw unauthorized();
      if (!['accepted', 'duplicate', 'stale'].includes(row.upload_status) || typeof row.guild_id !== 'string') throw unavailable();
      if (row.upload_status === 'stale') return jsonResponse({ error: { code: 'stale_revision', message: 'A newer raid revision is already stored.' } }, 409);
      return jsonResponse({ status: row.upload_status, guild: row.guild_id, raid: row.raid_id }, row.upload_status === 'accepted' ? 201 : 200);
    } catch (error) { return errorResponse(error); }
  };
}

export default { fetch: createIngestHandler() };
