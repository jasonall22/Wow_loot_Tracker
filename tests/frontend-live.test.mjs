import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Script, createContext } from 'node:vm';

class Element {
  constructor() {
    this.hidden = false;
    this.children = [];
    this.listeners = {};
    this.parts = {};
    this.textContent = '';
    this.classList = { add() {}, remove() {} };
  }
  addEventListener(type, handler) { this.listeners[type] = handler; }
  replaceChildren(...children) { this.children = children; }
  append(...children) { this.children.push(...children); }
  querySelector(selector) { return this.parts[selector] ??= new Element(); }
  set innerHTML(value) { this.html = value; this.parts = {}; }
  get innerHTML() { return this.html; }
  setAttribute() {}
  focus() {}
}

test('an open raid detail refreshes a removed drop without a user click', async () => {
  const elements = new Map();
  const get = (selector) => elements.get(selector) ?? elements.set(selector, new Element()).get(selector);
  for (const selector of ['#signed-in', '#dashboard', '#raid-detail']) get(selector).hidden = true;
  const storage = new Map([['apoc_session', JSON.stringify({ access_token: 'test-access-token', expires_at: 4102444800 })]]);
  const intervals = [];
  let dropReads = 0;
  const fetch = async (input) => {
    const url = new URL(input, 'https://portal.example');
    const view = url.searchParams.get('view');
    if (view === 'guilds') return Response.json({ guilds: [{ guild: { id: 'guild-1', name: 'APOC' }, membership: { role: 'admin' }, permissions: { uploadRaids: true } }] });
    if (view === 'raids') return Response.json({ raids: [{ id: 'raid-1', name: 'Tonight', revision: 2 }] });
    if (view === 'drops') {
      dropReads += 1;
      const drops = [{ item_name: 'Kept', boss: 'Boss' }];
      if (dropReads === 1) drops.push({ item_name: 'Removed', boss: 'Boss' });
      return Response.json({ drops });
    }
    if (view === 'members') return Response.json({ members: [] });
    throw new Error(`unexpected request: ${input}`);
  };
  const document = {
    hidden: false,
    querySelector: get,
    createElement: () => new Element(),
    addEventListener() {},
  };
  const context = createContext({
    document, fetch, Response, URL, AbortController, Date, JSON,
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
  assert.equal(intervals[0].delay, 5000);
  await intervals[0].callback();
  assert.equal(get('#drop-count').textContent, '1 records');
  assert.equal(get('#drop-list').children.length, 1);
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
