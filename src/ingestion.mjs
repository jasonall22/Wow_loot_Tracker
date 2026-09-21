import { createHash, randomBytes } from 'node:crypto';
import { badRequest } from './errors.mjs';

export const MAX_UPLOAD_BYTES = 1_048_576;
export const PAIRING_TTL_SECONDS = 300;

export function digestSecret(value) {
  if (typeof value !== 'string' || value.length < 32 || value.length > 4096) throw badRequest();
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function createPairingChallenge({ now = Date.now(), random = randomBytes } = {}) {
  const raw = random(32).toString('base64url');
  return {
    raw,
    digest: digestSecret(raw),
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + PAIRING_TTL_SECONDS * 1000).toISOString(),
  };
}

export async function parseUploadBody(request) {
  const length = request.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_UPLOAD_BYTES)) throw badRequest();
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_UPLOAD_BYTES) throw badRequest();
  let body;
  try { body = JSON.parse(text); } catch { throw badRequest(); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw badRequest();
  const required = ['requestId', 'sourceKey', 'sourceRevision', 'payloadHash', 'capturedAt', 'raid', 'drops', 'members'];
  const allowed = [...required, 'guildRoster'];
  if (required.some(key => !Object.hasOwn(body, key)) || Object.keys(body).some(key => !allowed.includes(key))) throw badRequest();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.requestId) ||
      typeof body.sourceKey !== 'string' || body.sourceKey.length < 1 || body.sourceKey.length > 200 ||
      !Number.isSafeInteger(body.sourceRevision) || body.sourceRevision < 0 ||
      !/^[a-f0-9]{64}$/.test(body.payloadHash) || !Number.isFinite(Date.parse(body.capturedAt))) throw badRequest();
  validateUploadRecords(body);
  if (digestPayload(body) !== body.payloadHash) throw badRequest();
  return body;
}

const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const bounded = (value, min, max) => typeof value === 'string' && value.length >= min && value.length <= max;
const stamp = value => bounded(value, 1, 40) && Number.isFinite(Date.parse(value));
const optionalStamp = value => value === null || stamp(value);

export function canonicalJSON(value) {
  if (Array.isArray(value)) return '[' + value.map(canonicalJSON).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonicalJSON(value[key])).join(',') + '}';
  return JSON.stringify(value);
}

export function digestPayload({ raid, drops, members }) {
  return createHash('sha256').update(canonicalJSON({ raid, drops, members }), 'utf8').digest('hex');
}

export function databaseRecords(body) {
  return {
    p_raid: { name: body.raid.name, run_id: body.raid.runId,
      created_at: body.raid.createdAt, closed_at: body.raid.closedAt },
    p_drops: body.drops.map(drop => ({
      id: drop.id, item_id: drop.itemId, item_name: drop.itemName,
      boss: drop.boss, dropped_at: drop.droppedAt, winner: drop.winner,
      award_type: drop.awardType, awarded_at: drop.awardedAt, award_note: drop.awardNote,
    })),
    p_members: body.members.map(member => ({
      character_key: member.characterKey, name: member.name, class: member.class,
      raid_group: member.raidGroup, present: member.present,
      visits: member.visits.map(visit => ({ joined_at: visit.joinedAt, left_at: visit.leftAt })),
    })),
  };
}

export function databaseGuildRoster(body) {
  if (!body.guildRoster) return null;
  return body.guildRoster.members.map(member => ({
    character_key: member.characterKey,
    name: member.name,
    class: member.class,
    rank_name: member.rankName,
    rank_index: member.rankIndex,
  }));
}

export function validateUploadRecords(body) {
  const { raid, drops, members } = body;
  if (!exact(raid, ['name', 'runId', 'createdAt', 'closedAt']) ||
      !bounded(raid.name, 1, 300) || !bounded(raid.runId, 1, 200) ||
      !stamp(raid.createdAt) || !optionalStamp(raid.closedAt) ||
      (raid.closedAt !== null && Date.parse(raid.closedAt) < Date.parse(raid.createdAt)) ||
      !Array.isArray(drops) || drops.length > 500 || !Array.isArray(members) || members.length > 200) throw badRequest();
  const dropIDs = new Set();
  for (const drop of drops) {
    if (!exact(drop, ['id', 'itemId', 'itemName', 'boss', 'droppedAt', 'winner', 'awardType', 'awardedAt', 'awardNote']) ||
        !bounded(drop.id, 1, 200) || dropIDs.has(drop.id) ||
        (drop.itemId !== null && (!Number.isSafeInteger(drop.itemId) || drop.itemId < 1 || drop.itemId > 10_000_000)) ||
        !bounded(drop.itemName, 1, 300) || !bounded(drop.boss, 0, 200) || !stamp(drop.droppedAt) ||
        (drop.winner !== null && !bounded(drop.winner, 1, 200)) ||
        (drop.awardType !== null && !['MS', 'OS', 'DE', 'GB', 'UNKNOWN'].includes(drop.awardType)) ||
        !optionalStamp(drop.awardedAt) || !bounded(drop.awardNote, 0, 2000) ||
        (drop.awardType === null && (drop.winner !== null || drop.awardedAt !== null)) ||
        (drop.awardType !== null && drop.awardedAt === null)) throw badRequest();
    dropIDs.add(drop.id);
  }
  const memberIDs = new Set();
  for (const member of members) {
    if (!exact(member, ['characterKey', 'name', 'class', 'raidGroup', 'present', 'visits']) ||
        !bounded(member.characterKey, 1, 200) || memberIDs.has(member.characterKey) ||
        !bounded(member.name, 1, 200) || !bounded(member.class, 0, 30) ||
        !Number.isSafeInteger(member.raidGroup) || member.raidGroup < 0 || member.raidGroup > 8 ||
        typeof member.present !== 'boolean' || !Array.isArray(member.visits) || member.visits.length > 100) throw badRequest();
    memberIDs.add(member.characterKey);
    const starts = new Set();
    for (const visit of member.visits) {
      if (!exact(visit, ['joinedAt', 'leftAt']) || !stamp(visit.joinedAt) || !optionalStamp(visit.leftAt) ||
          starts.has(visit.joinedAt) || (visit.leftAt !== null && Date.parse(visit.leftAt) < Date.parse(visit.joinedAt))) throw badRequest();
      starts.add(visit.joinedAt);
    }
  }
  if (body.guildRoster !== undefined) {
    const roster = body.guildRoster;
    if (!exact(roster, ['members']) || !Array.isArray(roster.members) ||
        roster.members.length < 1 || roster.members.length > 1000) throw badRequest();
    const rosterIDs = new Set();
    for (const member of roster.members) {
      if (!exact(member, ['characterKey', 'name', 'class', 'rankName', 'rankIndex']) ||
          !bounded(member.characterKey, 1, 200) || !bounded(member.name, 1, 200) || member.name !== member.name.trim() ||
          member.characterKey !== member.name.toLocaleLowerCase() || rosterIDs.has(member.characterKey) ||
          !bounded(member.class, 0, 30) || !bounded(member.rankName, 0, 100) ||
          !Number.isSafeInteger(member.rankIndex) || member.rankIndex < 0 || member.rankIndex > 99) throw badRequest();
      rosterIDs.add(member.characterKey);
    }
  }
}
