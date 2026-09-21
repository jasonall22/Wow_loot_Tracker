import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Script, createContext } from 'node:vm';
const appSource = `${readFileSync(new URL('../src/roster.mjs', import.meta.url), 'utf8').replace('export function', 'function')}\n${readFileSync(new URL('../app.js', import.meta.url), 'utf8').replace("import { buildLootRoster } from './src/roster.mjs';", '')}`;

class Element {
  constructor() {
    this.hidden = false;
    this.open = false;
    this.value = '';
    this.children = [];
    this.listeners = {};
    this.parts = {};
    this.textContent = '';
    this.style = {};
    this.offsetWidth = 240;
    this.offsetHeight = 100;
    this.classList = { add() {}, remove() {} };
  }
  addEventListener(type, handler) { this.listeners[type] = handler; }
  replaceChildren(...children) { this.children = children; }
  append(...children) { this.children.push(...children); }
  querySelector(selector) { return this.parts[selector] ??= new Element(); }
  set innerHTML(value) { this.html = value; this.parts = {}; }
  get innerHTML() { return this.html; }
  setAttribute() {}
  removeAttribute() {}
  getBoundingClientRect() { return { left: 30, right: 210, top: 40, bottom: 80 }; }
  focus() {}
  showModal() { this.open = true; }
  close() { this.open = false; this.listeners.close?.(); }
}

test('an open raid detail refreshes a removed drop without a user click', async () => {
  const elements = new Map();
  const get = (selector) => elements.get(selector) ?? elements.set(selector, new Element()).get(selector);
  const lootGroups = () => get('#drop-list').children;
  const lootRows = () => lootGroups().flatMap((group) => group.children[1].children.slice(1));
  for (const selector of ['#signed-in', '#dashboard', '#raid-detail']) get(selector).hidden = true;
  const storage = new Map([['apoc_session', JSON.stringify({ access_token: 'test-access-token', expires_at: 4102444800 })]]);
  const intervals = [];
  let dropReads = 0;
  let deleted = false;
  let corrected = false;
  const raid = { id: 'raid-1', name: 'Tonight', revision: 2, closed_at: null };
  const adminActions = [];
  const attendance = [
    { character_key: 'player', name: 'Player', class: 'PRIEST', present: true },
    ...Array.from({ length: 199 }, (_, index) => ({ character_key: `raider-${index + 1}`, name: `Raider ${index + 1}`, present: index > 1 })),
    { character_key: 'late-arrival', name: 'Late arrival', present: true },
  ];
  const memberOffsets = [];
  const fetch = async (input, options = {}) => {
    const url = new URL(input, 'https://portal.example');
    const view = url.searchParams.get('view');
    if (view === 'guilds') return Response.json({ guilds: [{ guild: { id: 'guild-1', name: 'APOC' }, membership: { role: 'admin' }, permissions: { uploadRaids: true, manageRaids: true } }] });
    if (view === 'raids') return Response.json({ raids: deleted ? [] : [raid] });
    if (view === 'drops') {
      dropReads += 1;
      const drops = [{ id: 'drop-1', item_id: 32336, item_name: 'Kept', boss: 'Boss', winner: corrected ? 'Player' : 'Off-roster', award_type: 'MS' }];
      if (dropReads === 1) drops.push(
        { item_id: 32337, item_name: 'Removed', boss: 'Trash' },
        { item_name: 'Another boss drop', boss: 'Boss' },
      );
      return Response.json({ drops });
    }
    if (view === 'members') {
      assert.equal(url.searchParams.get('limit'), '200');
      const offset = Number(url.searchParams.get('offset'));
      memberOffsets.push(offset);
      return Response.json({ members: attendance.slice(offset, offset + 200) });
    }
    if (view === 'visits') return Response.json({ visits: [{ character_key: 'raider-1', joined_at: '2026-09-17T13:00:00Z' }] });
    if (url.pathname === '/api/item') {
      assert.equal(url.searchParams.get('format'), '2');
      return Response.json(url.searchParams.get('id') === '32337'
        ? { itemID: 32337, quality: 3, lines: ['Removed', '+10 Intellect'] }
        : { itemID: 32336, quality: 4, lines: [
          [{ text: 'Kept', quality: 'q4' }], [{ text: '+20 Strength', quality: 'q2' }],
        ] });
    }
    if (url.pathname === '/api/admin') {
      const body = JSON.parse(options.body); adminActions.push(body);
      if (body.action === 'delete_raid') deleted = true;
      if (body.action === 'edit_drop') corrected = true;
      return Response.json({ status: 'ok', name: body.name ?? null });
    }
    throw new Error(`unexpected request: ${input}`);
  };
  const document = {
    hidden: false,
    querySelector: get,
    createElement: () => new Element(),
    addEventListener() {},
  };
  const context = createContext({
    document, fetch, Response, URL, AbortController, Date, JSON, window: { innerWidth: 1000, innerHeight: 800, confirm: () => true },
    sessionStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    setInterval: (callback, delay) => intervals.push({ callback, delay }),
    navigator: { clipboard: { writeText: async () => {} } },
  });
  new Script(appSource).runInContext(context);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#guild-list').children.length, 1);
  get('#guild-list').children[0].listeners.click();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#raid-list').children.length, 1);
  get('#raid-list').children[0].listeners.click();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#drop-count').textContent, '3 records');
  assert.equal(get('#member-count').textContent, '201 players');
  assert.equal(get('#member-list').children[0].querySelector('em').textContent, 'Present');
  assert.equal(get('#member-list').children[1].querySelector('em').textContent, 'Left raid');
  assert.equal(get('#member-list').children[2].querySelector('em').textContent, 'No attendance recorded');
  assert.deepEqual(memberOffsets, [0, 200]);
  assert.equal(lootGroups().length, 2);
  assert.equal(lootGroups()[0].children[0].children[0].textContent, 'Boss');
  assert.equal(lootGroups()[0].children[0].children[1].textContent, '2 items');
  assert.equal(lootGroups()[0].children[1].children.length, 3);
  assert.equal(lootGroups()[1].children[0].children[0].textContent, 'Trash');
  assert.deepEqual(lootGroups()[0].children[1].children[0].children.map((column) => column.textContent), ['Item', 'Winner', 'Award']);
  assert.equal(lootRows()[0].children[1].textContent, 'Off-roster');
  assert.equal(lootRows()[0].children[1].className, 'loot-winner');
  assert.equal(lootRows()[0].children[2].textContent, 'MS');
  context.sampleLoot = new Element();
  new Script("renderDropRow(sampleLoot, { item_name: 'For Player', winner: 'Player-Realm', award_type: 'OS' }); renderDropRow(sampleLoot, { item_name: 'Dust', award_type: 'DE' }); renderDropRow(sampleLoot, { item_name: 'Banked', award_type: 'GB' });").runInContext(context);
  assert.equal(context.sampleLoot.children[0].children[1].className, 'loot-winner class-priest');
  assert.equal(context.sampleLoot.children[0].children[2].textContent, 'OS');
  assert.equal(context.sampleLoot.children[1].children[1].textContent, '—');
  assert.equal(context.sampleLoot.children[1].children[2].textContent, 'DE');
  assert.equal(context.sampleLoot.children[2].children[2].textContent, 'Guild');
  const itemButton = lootRows()[0].children[0];
  assert.equal(itemButton.children[0].src, '/api/item?id=32336&icon=1');
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(itemButton.className, 'loot-item item-q4');
  assert.equal(lootGroups()[1].children[1].children[1].children[0].className, 'loot-item item-q3');
  itemButton.listeners.pointerenter();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#item-tooltip').hidden, false);
  assert.equal(get('#item-tooltip').children[0].children[0].className, 'q4');
  assert.equal(get('#item-tooltip').children[1].children[0].textContent, '+20 Strength');
  assert.equal(get('#item-tooltip').style.left, '222px');
  const legacyButton = lootGroups()[1].children[1].children[1].children[0];
  legacyButton.listeners.pointerenter();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#item-tooltip').children[0].children[0].textContent, 'Removed');
  assert.equal(get('#item-tooltip').children[1].children[0].textContent, '+10 Intellect');
  lootGroups()[0].children[0].listeners.click();
  assert.equal(lootGroups()[0].children[1].hidden, true);
  assert.equal(intervals[0].delay, 5000);
  await intervals[0].callback();
  assert.equal(get('#drop-count').textContent, '1 records');
  assert.equal(lootGroups().length, 1);
  assert.equal(lootGroups()[0].children[1].hidden, true);
  assert.equal(get('#item-tooltip').hidden, true);
  lootGroups()[0].children[0].listeners.click();
  assert.equal(lootGroups()[0].children[1].hidden, false);
  new Script("activeRaid.raid.closed_at = '2026-09-17T15:00:00Z'").runInContext(context);
  await intervals[0].callback();
  assert.equal(get('#member-list').children[0].querySelector('em').textContent, 'Attended');
  assert.equal(get('#member-list').children[1].querySelector('em').textContent, 'Attended');
  const unrecorded = get('#member-list').children.find((element) => element.querySelector('strong').textContent === 'Raider 2');
  assert.equal(unrecorded.querySelector('em').textContent, 'No attendance recorded');
  get('#manage-raid').listeners.click();
  get('#raid-name').value = 'Renamed raid';
  await get('#save-raid-name').listeners.click();
  assert.equal(get('#detail-title').textContent, 'Renamed raid');
  lootRows()[0].children.at(-1).listeners.click();
  const recipientOptions = get('#award-winner').children;
  assert.equal(recipientOptions[0].textContent, 'No recipient');
  assert.equal(recipientOptions.length, 203);
  assert.equal(recipientOptions.find(option => option.value === 'Raider 1').textContent, 'Raider 1 (not currently present)');
  assert.equal(recipientOptions.at(-1).textContent, 'Off-roster (not in raid attendance)');
  assert.equal(get('#award-winner').value, 'Off-roster');
  get('#award-winner').value = 'Player';
  get('#award-type').value = 'MS';
  await get('#save-award').listeners.click();
  assert.equal(adminActions.at(-1).action, 'edit_drop');
  assert.equal(adminActions.at(-1).winner, 'Player');
  assert.equal(lootRows()[0].children[1].textContent, 'Player');
  assert.equal(lootRows()[0].children[1].className, 'loot-winner class-priest');
  assert.equal(lootRows()[0].children[2].textContent, 'MS');
  get('#manage-raid').listeners.click();
  await get('#delete-raid').listeners.click();
  assert.equal(adminActions.at(-1).action, 'delete_raid');
  assert.equal(get('#raid-count').textContent, '0');
  assert.equal(get('#raid-detail').hidden, true);
});

test('raid archive loads older pages and refreshes the visible range', async () => {
  const elements = new Map();
  const get = (selector) => elements.get(selector) ?? elements.set(selector, new Element()).get(selector);
  for (const selector of ['#signed-in', '#dashboard', '#raid-detail']) get(selector).hidden = true;
  const storage = new Map([['apoc_session', JSON.stringify({ access_token: 'test-access-token', expires_at: 4102444800 })]]);
  let raids = Array.from({ length: 55 }, (_, index) => ({ id: `raid-${index}`, name: `Raid ${index}`, revision: 1 }));
  const calls = [];
  const intervals = [];
  const fetch = async (input) => {
    const url = new URL(input, 'https://portal.example');
    const view = url.searchParams.get('view');
    if (view === 'guilds') return Response.json({ guilds: [{ guild: { id: 'guild-1', name: 'APOC' }, membership: { role: 'member' } }] });
    if (view === 'raids') {
      const limit = Number(url.searchParams.get('limit'));
      const offset = Number(url.searchParams.get('offset'));
      calls.push({ limit, offset });
      return Response.json({ raids: raids.slice(offset, offset + limit) });
    }
    throw new Error(`unexpected request: ${input}`);
  };
  const context = createContext({
    document: { hidden: false, querySelector: get, createElement: () => new Element(), addEventListener() {} },
    fetch, Response, URL, AbortController, Date, JSON,
    sessionStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    setInterval: (callback) => intervals.push(callback),
    navigator: { clipboard: { writeText: async () => {} } },
  });
  new Script(appSource).runInContext(context);
  await new Promise((resolve) => setImmediate(resolve));
  get('#guild-list').children[0].listeners.click();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#raid-list').children.length, 50);
  assert.equal(get('#raid-count').textContent, '50+');
  assert.equal(get('#load-more-raids').hidden, false);
  assert.deepEqual(calls[0], { limit: 51, offset: 0 });
  await get('#load-more-raids').listeners.click();
  assert.equal(get('#raid-list').children.length, 55);
  assert.equal(get('#raid-count').textContent, '55');
  assert.equal(get('#load-more-raids').hidden, true);
  assert.deepEqual(calls[1], { limit: 101, offset: 0 });
  raids = raids.slice(1);
  await intervals[0]();
  assert.equal(get('#raid-list').children.length, 54);
  assert.equal(get('#raid-count').textContent, '54');
});

test('guild sections and connection button sit in the full-width top menu', () => {
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
  assert.match(html, /id="guild-nav" class="dashboard-topbar"[\s\S]*dashboard-logo[\s\S]*id="nav-overview"[\s\S]*id="open-roster"[\s\S]*id="create-pairing"[\s\S]*<\/header>/);
  assert.doesNotMatch(html, /class="roster-trigger"/);
  assert.match(css, /\.dashboard-topbar\s*\{[^}]*justify-content:\s*space-between/);
});

test('raid archive follows compact overview cards in a single full-width column', () => {
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
  assert.match(html, /class="dashboard-content"[\s\S]*class="dashboard-main"[\s\S]*class="metrics"[\s\S]*class="dashboard-archive"/);
  assert.match(css, /\.dashboard-content\s*\{[^}]*grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  assert.match(css, /\.dashboard-main\s*\{[^}]*width:\s*min\(100%,\s*440px\)/);
});

test('live portal refreshes the signed-in session before polling', async () => {
  const elements = new Map();
  const get = (selector) => elements.get(selector) ?? elements.set(selector, new Element()).get(selector);
  for (const selector of ['#signed-in', '#dashboard', '#raid-detail']) get(selector).hidden = true;
  const storage = new Map([['apoc_session', JSON.stringify({
    access_token: 'old-token', refresh_token: 'old-refresh', expires_at: 1,
  })]]);
  const calls = [];
  const fetch = async (input, options = {}) => {
    calls.push({ input, options });
    if (input === '/api/config') return Response.json({ url: 'https://example.supabase.co', publishableKey: 'test-key' });
    if (input.includes('/auth/v1/token?grant_type=refresh_token')) return Response.json({
      access_token: 'new-token', refresh_token: 'new-refresh', expires_in: 3600,
    });
    if (input === '/api/portal?view=guilds') return Response.json({ guilds: [] });
    throw new Error(`unexpected request: ${input}`);
  };
  const context = createContext({
    document: { hidden: false, querySelector: get, createElement: () => new Element(), addEventListener() {} },
    fetch, Response, URL, AbortController, Date, JSON,
    sessionStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    setInterval() {},
    navigator: { clipboard: { writeText: async () => {} } },
  });
  new Script(appSource).runInContext(context);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls.length, 3);
  assert.equal(JSON.parse(calls[1].options.body).refresh_token, 'old-refresh');
  assert.equal(calls[2].options.headers.Authorization, 'Bearer new-token');
  assert.equal(JSON.parse(storage.get('apoc_session')).refresh_token, 'new-refresh');
});
