import { unavailable } from './errors.mjs';

const RAID = ['id', 'guild_id', 'source_key', 'name', 'run_id', 'revision', 'created_at', 'closed_at', 'updated_at'];
const DROP = ['id', 'guild_id', 'raid_id', 'item_id', 'item_name', 'item_link', 'boss', 'dropped_at', 'winner', 'award_type', 'awarded_at', 'award_note'];
const MEMBER = ['character_key', 'guild_id', 'raid_id', 'name', 'class', 'raid_group', 'present'];
const GUILD_CHARACTER = ['character_key', 'guild_id', 'name', 'class', 'rank_name', 'rank_index',
  'is_current', 'first_seen_at', 'last_seen_at', 'left_at'];
const VISIT = ['id', 'guild_id', 'raid_id', 'character_key', 'joined_at', 'left_at'];
const COMPARISON = ['id', 'guild_id', 'raid_id', 'drop_id', 'status', 'observed_at', 'result', 'updated_at'];

export const SELECT = Object.freeze({
  guild: 'id,name,realm,faction',
  membership: 'guild_id,user_id,role,status,can_upload,can_edit',
  raid: [...RAID, 'display_name', 'deleted_at'].join(','), drop: DROP.join(','), member: MEMBER.join(','),
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
export function dropProjection(row) { return pick(row, DROP); }
export function memberProjection(row) { return pick(row, MEMBER); }
export function guildCharacterProjection(row) { return pick(row, GUILD_CHARACTER); }
export function visitProjection(row) { return pick(row, VISIT); }
export function comparisonProjection(row) { return pick(row, COMPARISON); }
