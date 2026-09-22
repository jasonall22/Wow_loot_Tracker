import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLootRoster } from '../src/roster.mjs';

test('current guild member receives all earlier attendance and awarded loot', () => {
  const raids = [{ id: 'a', name: 'Tuesday September 1st 2026 - Black Temple' }, { id: 'b', name: 'Hyjal : Wednesday September 2nd 2026' }];
  const guildRoster = [{ character_key: 'bel-realm', name: 'Bel-Realm', class: 'HUNTER',
    rank_name: 'Raider', rank_index: 4, is_current: true }];
  const members = ['a', 'b'].map(raid_id => ({ raid_id, character_key: 'bel-realm', name: 'Bel-Realm', class: 'HUNTER' }));
  const drops = [
    { raid_id: 'a', winner: 'Bel', award_type: 'MS', item_name: 'Old', awarded_at: '2026-09-01' },
    { raid_id: 'b', winner: 'Bel-Realm', award_type: 'OS', item_name: 'New', awarded_at: '2026-09-02' },
  ];
  const [player] = buildLootRoster(guildRoster, members, drops, raids);
  assert.equal(player.isCurrent, true);
  assert.equal(player.rankName, 'Raider');
  assert.equal(player.raidCount, 2);
  assert.equal(player.msCount, 1);
  assert.deepEqual(player.loot.map(drop => drop.item_name), ['New', 'Old']);
  assert.deepEqual(player.loot.map(drop => drop.raid_zone), ['Hyjal', 'Black Temple']);
});

test('former members remain, deleted raids and PUGs are excluded, and ambiguous names are not attributed', () => {
  const raids = [{ id: 'a', name: 'Active' }];
  const guildRoster = [
    { character_key: 'alex-a', name: 'Alex-A', is_current: true },
    { character_key: 'alex-b', name: 'Alex-B', is_current: false, left_at: '2026-09-10' },
    { character_key: 'gone', name: 'Gone', is_current: false },
  ];
  const members = [
    { raid_id: 'a', character_key: 'alex-a', name: 'Alex-A' },
    { raid_id: 'a', character_key: 'alex-b', name: 'Alex-B' },
    { raid_id: 'a', character_key: 'pug', name: 'Pug' },
    { raid_id: 'deleted', character_key: 'gone', name: 'Gone' },
  ];
  const drops = [
    { raid_id: 'a', winner: 'Alex', award_type: 'MS' },
    { raid_id: 'a', winner: 'Pug', award_type: 'MS' },
    { raid_id: 'deleted', winner: 'Gone', award_type: 'MS' },
  ];
  const players = buildLootRoster(guildRoster, members, drops, raids);
  assert.equal(players.find(player => player.name === 'Alex-A').loot.length, 0);
  assert.equal(players.find(player => player.name === 'Alex-B').loot.length, 0);
  assert.equal(players.find(player => player.name === 'Alex-B').isCurrent, false);
  assert.ok(!players.some(player => player.name === 'Pug'));
  assert.equal(players.find(player => player.name === 'Gone').loot.length, 0);
});

test('a raider who joins later gains loot recorded before their first guild snapshot', () => {
  const guildRoster = [{ character_key: 'later', name: 'Later', class: 'MAGE', is_current: true,
    first_seen_at: '2026-09-20T00:00:00Z' }];
  const raids = [{ id: 'old', name: 'Old raid', created_at: '2026-09-01T00:00:00Z' }];
  const members = [{ raid_id: 'old', character_key: 'later', name: 'Later', class: 'MAGE' }];
  const drops = [{ raid_id: 'old', winner: 'Later', award_type: 'MS', item_name: 'Earlier item' }];
  const [player] = buildLootRoster(guildRoster, members, drops, raids);
  assert.equal(player.raidCount, 1);
  assert.deepEqual(player.loot.map(drop => drop.item_name), ['Earlier item']);
});
