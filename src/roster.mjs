const normalized = value => String(value || '').trim().toLocaleLowerCase();
const shortName = value => normalized(value).split('-')[0];
const datedRaidName = /\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|session\s+\d+|recovered|live raid)\b/i;

function zoneFromRaidName(value) {
  const name = String(value || '').trim();
  if (!name) return 'Zone unavailable';
  for (const separator of [' - ', ' : ']) {
    const parts = name.split(separator).map(part => part.trim()).filter(Boolean);
    if (parts.length < 2) continue;
    const datePart = parts.findIndex(part => datedRaidName.test(part));
    if (datePart === 0) return parts.slice(1).join(separator);
    if (datePart === parts.length - 1) return parts.slice(0, -1).join(separator);
  }
  return name;
}

function addIndex(index, value, player) {
  if (!value) return;
  const entries = index.get(value) ?? [];
  if (!entries.includes(player)) entries.push(player);
  index.set(value, entries);
}

function singleMatch(index, value) {
  const entries = index.get(value) ?? [];
  return entries.length === 1 ? entries[0] : null;
}

// Guild roster snapshots define membership. Raid attendance and awards only enrich
// characters that have appeared in one of those snapshots, so PUGs stay excluded.
export function buildLootRoster(guildRoster, members, drops, raids) {
  const activeRaids = new Map(raids.map(raid => [raid.id, raid]));
  const players = new Map();
  for (const member of guildRoster) {
    const key = normalized(member.character_key || member.name);
    if (!key || players.has(key)) continue;
    players.set(key, {
      key,
      name: member.name || member.character_key,
      class: member.class || '',
      rankName: member.rank_name || '',
      rankIndex: member.rank_index,
      isCurrent: member.is_current === true,
      firstSeenAt: member.first_seen_at || null,
      lastSeenAt: member.last_seen_at || null,
      leftAt: member.left_at || null,
      raids: new Set(),
      loot: [],
    });
  }

  const exact = new Map();
  const short = new Map();
  for (const player of players.values()) {
    addIndex(exact, normalized(player.key), player);
    addIndex(exact, normalized(player.name), player);
    addIndex(short, shortName(player.name), player);
  }
  function resolve(...identities) {
    for (const identity of identities) {
      const match = singleMatch(exact, normalized(identity));
      if (match) return match;
    }
    for (const identity of identities) {
      const match = singleMatch(short, shortName(identity));
      if (match) return match;
    }
    return null;
  }

  for (const member of members) {
    if (!activeRaids.has(member.raid_id)) continue;
    const player = resolve(member.character_key, member.name);
    if (!player) continue;
    if (!player.class && member.class) player.class = member.class;
    player.raids.add(member.raid_id);
  }
  for (const drop of drops) {
    const raid = activeRaids.get(drop.raid_id);
    const winner = String(drop.winner || '').trim();
    if (!raid || !winner || !drop.award_type) continue;
    const player = resolve(winner);
    if (!player) continue;
    player.loot.push({ ...drop, raid_name: raid.name, raid_zone: zoneFromRaidName(raid.name), raid_date: raid.created_at });
  }

  return [...players.values()].map(player => ({
    ...player,
    raidCount: player.raids.size,
    msCount: player.loot.filter(drop => drop.award_type === 'MS').length,
    loot: player.loot.sort((a, b) => String(b.awarded_at || b.dropped_at).localeCompare(String(a.awarded_at || a.dropped_at))),
  })).sort((a, b) => a.name.localeCompare(b.name));
}
