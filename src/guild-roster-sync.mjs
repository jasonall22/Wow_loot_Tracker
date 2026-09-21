import { unavailable } from './errors.mjs';

export async function syncGuildRoster({ config, fetchImpl, guildID, capturedAt, members, timeout = 10000 }) {
  if (!members) return;
  let response;
  try {
    response = await fetchImpl(`${config.origin}/rest/v1/rpc/sync_apoc_guild_roster`, {
      method: 'POST',
      headers: { apikey: config.secretKey, Authorization: `Bearer ${config.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_guild_id: guildID, p_captured_at: capturedAt, p_members: members }),
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(timeout),
    });
  } catch { throw unavailable(); }
  if (!response.ok) throw unavailable();
}
