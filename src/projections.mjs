import { unavailable } from './errors.mjs';

const RAID = ['id', 'guild_id', 'source_key', 'name', 'run_id', 'revision', 'created_at', 'closed_at', 'updated_at'];
const DROP = ['id', 'guild_id', 'raid_id', 'item_id', 'item_name', 'item_link', 'boss', 'dropped_at', 'winner', 'award_type', 'awarded_at', 'award_note', 'priority', 'priority_note'];
const DROP_ROLL = ['roll_started_at', 'roll_ends_at', 'roll_closed', 'roll_copy_count', 'roll_entries'];
const MEMBER = ['character_key', 'guild_id', 'raid_id', 'name', 'class', 'raid_group', 'present'];
const GUILD_CHARACTER = ['character_key', 'guild_id', 'name', 'class', 'rank_name', 'rank_index',
  'is_current', 'first_seen_at', 'last_seen_at', 'left_at'];
const VISIT = ['id', 'guild_id', 'raid_id', 'character_key', 'joined_at', 'left_at'];
const COMPARISON = ['id', 'guild_id', 'raid_id', 'drop_id', 'status', 'observed_at', 'result', 'updated_at'];

export const SELECT = Object.freeze({
  guild: 'id,name,realm,faction',
  membership: 'guild_id,user_id,role,status,can_upload,can_edit',
  raid: [...RAID, 'display_name', 'deleted_at'].join(','), drop: [...DROP, ...DROP_ROLL].join(','), member: MEMBER.join(','),
  guildCharacter: GUILD_CHARACTER.join(','),
  visit: VISIT.join(','), comparison: COMPARISON.join(','),
});

function pick(row, keys) {
  return Object.fromEntries(keys.filter(key => Object.hasOwn(row, key)).map(key => [key, row[key]]));
}

export function guildProjection(row) {
  return pick(row, ['id', 'name', 'realm', 'faction']);
}

export function membershipProjection(row) {
  return pick(row, ['guild_id', 'role', 'can_upload', 'can_edit']);
}

// All-or-nothing rather than silently accepting an adapter returning another guild.
export function scopedRows(rows, guildID, raidID = null) {
  if (!Array.isArray(rows) || rows.some(row => !row || row.guild_id !== guildID || (raidID && row.raid_id !== raidID))) {
    throw unavailable();
  }
  return rows;
}

export function raidProjection(row) {
  return { ...pick(row, RAID), name: row.display_name || row.name };
}
export function archivedRaidProjection(row) {
  return { ...raidProjection(row), deleted_at: row.deleted_at };
}
export function dropProjection(row) {
  const drop = pick(row, DROP);
  if (!row.roll_started_at || !row.roll_ends_at) return { ...drop, roll_data: null };
  const entries = [];
  for (const encoded of Array.isArray(row.roll_entries) ? row.roll_entries : []) {
    try {
      const entry = JSON.parse(encoded);
      if (entry && typeof entry.name === 'string' && Number.isInteger(entry.roll) && ['MS', 'OS'].includes(entry.type)) entries.push(entry);
    } catch { /* Invalid legacy rows are ignored rather than exposed. */ }
  }
  return { ...drop, roll_data: { startedAt: row.roll_started_at, endsAt: row.roll_ends_at,
    closed: row.roll_closed === true, copyCount: Number(row.roll_copy_count) || 1, entries } };
}
export function memberProjection(row) { return pick(row, MEMBER); }
export function guildCharacterProjection(row) { return pick(row, GUILD_CHARACTER); }
export function visitProjection(row) { return pick(row, VISIT); }
export function comparisonProjection(row) { return pick(row, COMPARISON); }
