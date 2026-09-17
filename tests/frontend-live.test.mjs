import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Script, createContext } from 'node:vm';

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
  for (const selector of ['#signed-in', '#dashboard', '#raid-detail']) get(selector).hidden = true;
  const storage = new Map([['apoc_session', JSON.stringify({ access_token: 'test-access-token', expires_at: 4102444800 })]]);
  const intervals = [];
  let dropReads = 0;
  let deleted = false;
  let corrected = false;
  const adminActions = [];
  const fetch = async (input, options = {}) => {
    const url = new URL(input, 'https://portal.example');
    const view = url.searchParams.get('view');
    if (view === 'guilds') return Response.json({ guilds: [{ guild: { id: 'guild-1', name: 'APOC' }, membership: { role: 'admin' }, permissions: { uploadRaids: true, manageRaids: true } }] });
    if (view === 'raids') return Response.json({ raids: deleted ? [] : [{ id: 'raid-1', name: 'Tonight', revision: 2 }] });
    if (view === 'drops') {
      dropReads += 1;
      const drops = [{ id: 'drop-1', item_id: 32336, item_name: 'Kept', boss: 'Boss', winner: corrected ? 'Player' : null, award_type: corrected ? 'MS' : null }];
      if (dropReads === 1) drops.push({ item_id: 32337, item_name: 'Removed', boss: 'Boss' });
      return Response.json({ drops });
    }
    if (view === 'members') return Response.json({ members: [] });
    if (url.pathname === '/api/item') {
      assert.equal(url.searchParams.get('format'), '2');
      return Response.json(url.searchParams.get('id') === '32337'
        ? { itemID: 32337, lines: ['Removed', '+10 Intellect'] }
        : { itemID: 32336, lines: [
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
  new Script(readFileSync(new URL('../app.js', import.meta.url), 'utf8')).runInContext(context);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#guild-list').children.length, 1);
  get('#guild-list').children[0].listeners.click();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#raid-list').children.length, 1);
  get('#raid-list').children[0].listeners.click();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#drop-count').textContent, '2 records');
  assert.equal(get('#drop-list').children.length, 2);
  const itemButton = get('#drop-list').children[0].children[0];
  assert.equal(itemButton.children[0].src, '/api/item?id=32336&icon=1');
  itemButton.listeners.pointerenter();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#item-tooltip').hidden, false);
  assert.equal(get('#item-tooltip').children[0].children[0].className, 'q4');
  assert.equal(get('#item-tooltip').children[1].children[0].textContent, '+20 Strength');
  assert.equal(get('#item-tooltip').style.left, '222px');
  const legacyButton = get('#drop-list').children[1].children[0];
  legacyButton.listeners.pointerenter();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(get('#item-tooltip').children[0].children[0].textContent, 'Removed');
  assert.equal(get('#item-tooltip').children[1].children[0].textContent, '+10 Intellect');
  assert.equal(intervals[0].delay, 5000);
  await intervals[0].callback();
  assert.equal(get('#drop-count').textContent, '1 records');
  assert.equal(get('#drop-list').children.length, 1);
  assert.equal(get('#item-tooltip').hidden, true);
  get('#manage-raid').listeners.click();
  get('#raid-name').value = 'Renamed raid';
  await get('#save-raid-name').listeners.click();
  assert.equal(get('#detail-title').textContent, 'Renamed raid');
  get('#drop-list').children[0].children.at(-1).listeners.click();
  get('#award-winner').value = 'Player';
  get('#award-type').value = 'MS';
  await get('#save-award').listeners.click();
  assert.equal(adminActions.at(-1).action, 'edit_drop');
  assert.equal(get('#drop-list').children[0].children[2].textContent, 'Awarded to Player · MS');
  get('#manage-raid').listeners.click();
  await get('#delete-raid').listeners.click();
  assert.equal(adminActions.at(-1).action, 'delete_raid');
  assert.equal(get('#raid-count').textContent, 0);
  assert.equal(get('#raid-detail').hidden, true);
});

test('connection button sits in the same full-width header row as the crest', () => {
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
  assert.match(html, /class="dashboard-topbar"[\s\S]*dashboard-logo[\s\S]*id="create-pairing"[\s\S]*<\/div>/);
  assert.match(css, /\.dashboard-topbar\s*\{[^}]*justify-content:\s*space-between/);
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
  new Script(readFileSync(new URL('../app.js', import.meta.url), 'utf8')).runInContext(context);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls.length, 3);
  assert.equal(JSON.parse(calls[1].options.body).refresh_token, 'old-refresh');
  assert.equal(calls[2].options.headers.Authorization, 'Bearer new-token');
  assert.equal(JSON.parse(storage.get('apoc_session')).refresh_token, 'new-refresh');
});
