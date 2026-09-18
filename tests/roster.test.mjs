import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLootRoster } from '../src/roster.mjs';

test('roster deduplicates attendance and sorts awarded gear by date', () => {
  const raids = [{ id: 'a', name: 'Raid A' }, { id: 'b', name: 'Raid B' }];
  const members = ['a', 'b'].map(raid_id => ({ raid_id, character_key: 'bel-realm', name: 'Bel-Realm', class: 'HUNTER' }));
  const drops = [
    { raid_id: 'a', winner: 'Bel', award_type: 'MS', item_name: 'Old', awarded_at: '2026-09-01' },
    { raid_id: 'b', winner: 'Bel-Realm', award_type: 'OS', item_name: 'New', awarded_at: '2026-09-02' },
  ];
  const [player] = buildLootRoster(members, drops, raids);
  assert.equal(player.raidCount, 2);
  assert.equal(player.msCount, 1);
  assert.deepEqual(player.loot.map(drop => drop.item_name), ['New', 'Old']);
});

test('deleted raids are excluded and ambiguous short names are not attributed', () => {
  const raids = [{ id: 'a', name: 'Active' }];
  const members = [
    { raid_id: 'a', character_key: 'alex-a', name: 'Alex-A' },
    { raid_id: 'a', character_key: 'alex-b', name: 'Alex-B' },
    { raid_id: 'deleted', character_key: 'gone', name: 'Gone' },
  ];
  const drops = [{ raid_id: 'a', winner: 'Alex', award_type: 'MS' }, { raid_id: 'deleted', winner: 'Gone', award_type: 'MS' }];
  const players = buildLootRoster(members, drops, raids);
  assert.equal(players.find(player => player.name === 'Alex-A').loot.length, 0);
  assert.equal(players.find(player => player.name === 'Alex-B').loot.length, 0);
  assert.equal(players.find(player => player.name === 'Alex').loot.length, 1);
  assert.ok(!players.some(player => player.name === 'Gone'));
});
