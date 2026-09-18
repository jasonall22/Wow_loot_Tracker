// A recorded-player directory, not a claim about current guild membership or equipped gear.
export function buildLootRoster(members, drops, raids) {
  const activeRaids = new Map(raids.map(raid => [raid.id, raid]));
  const players = new Map();
  for (const member of members) {
    if (!activeRaids.has(member.raid_id)) continue;
    const key = String(member.character_key || member.name || '').trim().toLocaleLowerCase();
    if (!key) continue;
    let player = players.get(key);
    if (!player) {
      player = { key, name: member.name || member.character_key, class: '', raids: new Set(), loot: [] };
      players.set(key, player);
    }
    if (member.name) player.name = member.name;
    if (member.class) player.class = member.class;
    player.raids.add(member.raid_id);
  }
  const exact = new Map();
  const short = new Map();
  for (const player of players.values()) {
    const name = String(player.name).trim().toLocaleLowerCase();
    for (const [index, value] of [[exact, name], [short, name.split('-')[0]]]) {
      if (!index.has(value)) index.set(value, []);
      index.get(value).push(player);
    }
  }
  for (const drop of drops) {
    const raid = activeRaids.get(drop.raid_id);
    const winner = String(drop.winner || '').trim();
    if (!raid || !winner || !drop.award_type) continue;
    const name = winner.toLocaleLowerCase();
    const matches = exact.get(name) || short.get(name.split('-')[0]) || [];
    // Never attribute an award to a same-name character when realm identity is ambiguous.
    let player = matches.length === 1 ? matches[0] : null;
    if (!player) {
      const key = `unmatched:${name}`;
      player = players.get(key);
      if (!player) {
        player = { key, name: winner, class: '', raids: new Set(), loot: [] };
        players.set(key, player);
      }
    }
    player.loot.push({ ...drop, raid_name: raid.name, raid_date: raid.created_at });
  }
  return [...players.values()].map(player => ({
    ...player, raidCount: player.raids.size,
    msCount: player.loot.filter(drop => drop.award_type === 'MS').length,
    loot: player.loot.sort((a, b) => String(b.awarded_at || b.dropped_at).localeCompare(String(a.awarded_at || a.dropped_at))),
  })).sort((a, b) => a.name.localeCompare(b.name));
}
