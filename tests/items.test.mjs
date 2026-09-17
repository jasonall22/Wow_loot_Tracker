import test from 'node:test';
import assert from 'node:assert/strict';
import { itemID, plainTooltip, fetchItem, fetchIcon } from '../src/items.mjs';
import itemAPI from '../api/item.js';

test('item IDs must be bounded decimal identifiers', () => {
  for (const input of [null, '0', '-1', '1e3', '1/2', '10000001', '01', '']) assert.equal(itemID(input), null);
  assert.equal(itemID('32336'), 32336);
});

test('public tooltip HTML becomes inert text and fixed-host icon lookup', async () => {
  const urls = [];
  const fetcher = async (url, options) => {
    urls.push(url);
    assert.equal(options.redirect, 'manual');
    if (url.includes('nether.wowhead.com')) return Response.json({
      icon: 'INV_Boots_05', name: 'Test Boots',
      tooltip: '<span class="q4">Test Boots</span><br><script>alert(1)</script>+20 Strength &amp; Agility',
    });
    return new Response(new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), { headers: { 'content-type': 'image/jpeg' } });
  };
  const item = await fetchItem(32336, fetcher);
  assert.equal(item.icon, 'inv_boots_05');
  assert.deepEqual(item.lines, ['Test Boots', '+20 Strength & Agility']);
  const icon = await fetchIcon(item.icon, fetcher);
  assert.equal(icon.length, 4);
  assert.deepEqual(urls, [
    'https://nether.wowhead.com/tooltip/item/32336?dataEnv=5&locale=0',
    'https://wow.zamimg.com/images/wow/icons/medium/inv_boots_05.jpg',
  ]);
});

test('invalid IDs and overlarge metadata fail without returning remote content', async () => {
  const bad = await itemAPI.fetch(new Request('https://portal.example/api/item?id=1e3'));
  assert.equal(bad.status, 400);
  await assert.rejects(fetchItem(1, async () => new Response('x'.repeat(262145))));
  await assert.rejects(fetchIcon('../secret', async () => { throw new Error('should not fetch'); }));
});
