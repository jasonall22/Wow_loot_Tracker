import { createHash, randomUUID } from 'node:crypto';
import { badRequest } from './errors.mjs';
import { digestPayload, validateUploadRecords } from './ingestion.mjs';

function string(value, min, max) {
  if (typeof value !== 'string' || value.length < min || value.length > max) throw badRequest();
  return value;
}
function epoch(value, nullable = false) {
  if (nullable && value === 0) return null;
  if (!Number.isSafeInteger(value) || value < 1 || value > 4_102_444_800) throw badRequest();
  return new Date(value * 1000).toISOString();
}

export function sourceKeyForExport(snapshot) {
  const identity = [snapshot.guild, snapshot.realm, snapshot.faction, snapshot.session.run, snapshot.session.id];
  const pythonJSON = `[${identity.map(value => JSON.stringify(value)).join(', ')}]`;
  return createHash('sha256').update(pythonJSON, 'utf8').digest('hex');
}

export function normalizeRaidExport(snapshot, id = randomUUID()) {
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot) || snapshot.format !== 'apoc-loot-tracker-export-v1' ||
      !snapshot.session || typeof snapshot.session !== 'object' || Array.isArray(snapshot.session) ||
      !Array.isArray(snapshot.drops) || !Array.isArray(snapshot.members)) throw badRequest();
  for (const key of ['guild', 'realm', 'faction']) string(snapshot[key], 1, 100);
  string(snapshot.sender, 1, 200);
  const session = snapshot.session;
  string(session.id, 1, 200);
  string(session.run, 1, 200);
  if (!Number.isSafeInteger(session.revision) || session.revision < 0) throw badRequest();
  const raid = { name: string(session.name, 1, 300), runId: session.run,
    createdAt: epoch(session.createdAt), closedAt: epoch(session.closedAt, true) };
  const drops = snapshot.drops.map(drop => {
    if (!drop || typeof drop !== 'object' || Array.isArray(drop)) throw badRequest();
    const award = drop.award;
    if (award && (typeof award !== 'object' || Array.isArray(award))) throw badRequest();
    return { id: drop.id, itemId: drop.itemID === 0 ? null : drop.itemID, itemName: drop.item,
      boss: drop.boss, droppedAt: epoch(drop.at), winner: award ? award.winner : null,
      awardType: award ? award.type : null, awardedAt: award ? epoch(award.at) : null,
      awardNote: award ? award.note : '' };
  });
  const members = snapshot.members.map(member => {
    if (!member || typeof member !== 'object' || Array.isArray(member) || !Array.isArray(member.visits)) throw badRequest();
    const name = string(member.name, 1, 200);
    return { characterKey: name.toLowerCase(), name, class: member.class, raidGroup: member.group,
      present: member.present, visits: member.visits.map(visit => {
        if (!Array.isArray(visit) || visit.length !== 2) throw badRequest();
        return { joinedAt: epoch(visit[0]), leftAt: epoch(visit[1], true) };
      }) };
  });
  const upload = { requestId: id, sourceKey: sourceKeyForExport(snapshot), sourceRevision: session.revision,
    capturedAt: epoch(snapshot.sampledAt), raid, drops, members };
  validateUploadRecords(upload);
  return { ...upload, payloadHash: digestPayload(upload) };
}
