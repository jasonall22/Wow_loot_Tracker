import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Script, createContext } from 'node:vm';
const appSource = `${readFileSync(new URL('../src/roster.mjs', import.meta.url), 'utf8').replace('export function', 'function')}\n${readFileSync(new URL('../src/export-file.mjs', import.meta.url), 'utf8').replace('export function', 'function')}\n${readFileSync(new URL('../app.js', import.meta.url), 'utf8').replace(/^import .*;$/gm, '')}`;

class Element {
  constructor() {
    this.hidden = false; this.value = ''; this.children = []; this.listeners = {};
    this.textContent = ''; this.className = ''; this.style = {};
    this.classList = { add() {}, remove() {} };
  }
  addEventListener(type, handler) { this.listeners[type] = handler; }
  querySelector() { return this.button ??= new Element(); }
  replaceChildren(...children) { this.children = children; }
  append(...children) { this.children.push(...children); }
  reset() { this.value = ''; }
  set innerHTML(value) { this.html = value; }
  get innerHTML() { return this.html; }
}

test('invite URL opens password setup, clears tokens from URL, and joins on submit', async () => {
  const elements = new Map();
  const get = selector => elements.get(selector) ?? elements.set(selector, new Element()).get(selector);
  const storage = new Map();
  const calls = [];
  get('#invite-password-fields').querySelectorAll = () => [get('#invite-password'), get('#invite-password-confirm')];
  let cleanUrl = '';
  const window = { location: { hash: '#access_token=one.two.three&refresh_token=refresh-token&type=invite&expires_in=3600', pathname: '/', search: '' },
    history: { replaceState: (_, __, value) => { cleanUrl = value; } } };
  const fetch = async (input, options = {}) => {
    calls.push({ input, options });
    if (input === '/api/config') return Response.json({ url: 'https://exampleproject.supabase.co', publishableKey: 'sb_publishable_test' });
    if (input === 'https://exampleproject.supabase.co/auth/v1/user') return Response.json({ id: 'member-id' });
    if (input === '/api/accept-invite') return Response.json({ status: 'ok', joined: 1 });
    if (input === '/api/portal?view=guilds') return Response.json({ guilds: [] });
    throw new Error(`unexpected request: ${input}`);
  };
  const context = createContext({
    document: { hidden: false, querySelector: get, createElement: () => new Element(), addEventListener() {} },
    window, fetch, Response, URL, URLSearchParams, Date, JSON, AbortController,
    sessionStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
    setInterval() {}, navigator: { clipboard: { writeText: async () => {} } },
  });
  new Script(appSource).runInContext(context);
  assert.equal(get('#invite-setup').hidden, false);
  assert.equal(get('#signed-out').hidden, true);
  assert.equal(cleanUrl, '/');
  assert.equal(storage.get('apoc_invite_setup'), '1');
  get('#invite-password').value = 'very-long-new-password';
  get('#invite-password-confirm').value = 'very-long-new-password';
  const form = get('#invite-password-form');
  const event = { preventDefault() {}, currentTarget: form };
  const pending = form.listeners.submit(event);
  event.currentTarget = null; // Browsers clear currentTarget when async event dispatch finishes.
  await pending;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(get('#invite-setup').hidden, true);
  assert.equal(get('#signed-in').hidden, false);
  assert.equal(storage.has('apoc_invite_setup'), false);
  assert.deepEqual(calls.map(call => call.input), [
    '/api/config', 'https://exampleproject.supabase.co/auth/v1/user',
    '/api/accept-invite', '/api/portal?view=guilds',
  ]);
  assert.deepEqual(JSON.parse(calls[1].options.body), { password: 'very-long-new-password' });
  assert.equal(calls[1].options.headers.Authorization, 'Bearer one.two.three');
});

test('reloaded invite finishes joining without setting the password a second time', async () => {
  const elements = new Map();
  const get = selector => elements.get(selector) ?? elements.set(selector, new Element()).get(selector);
  get('#invite-password-fields').querySelectorAll = () => [get('#invite-password'), get('#invite-password-confirm')];
  const storage = new Map([
    ['apoc_session', JSON.stringify({ access_token: 'one.two.three', refresh_token: 'refresh-token', expires_at: Math.floor(Date.now() / 1000) + 3600 })],
    ['apoc_invite_setup', '1'], ['apoc_invite_password_saved', '1'],
  ]);
  const calls = [];
  const fetch = async input => {
    calls.push(input);
    if (input === '/api/accept-invite') return Response.json({ status: 'ok', joined: 0 });
    if (input === '/api/portal?view=guilds') return Response.json({ guilds: [] });
    throw new Error(`unexpected request: ${input}`);
  };
  const context = createContext({
    document: { hidden: false, querySelector: get, createElement: () => new Element(), addEventListener() {} },
    window: { location: { hash: '' } }, fetch, Response, URL, URLSearchParams, Date, JSON, AbortController,
    sessionStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
    setInterval() {}, navigator: { clipboard: { writeText: async () => {} } },
  });
  new Script(appSource).runInContext(context);
  assert.equal(get('#invite-password-fields').hidden, true);
  const form = get('#invite-password-form');
  const event = { preventDefault() {}, currentTarget: form };
  const pending = form.listeners.submit(event);
  event.currentTarget = null;
  await pending;
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['/api/accept-invite', '/api/portal?view=guilds']);
  assert.equal(get('#signed-in').hidden, false);
  assert.equal(get('#invite-setup').hidden, true);
  assert.equal(storage.has('apoc_invite_setup'), false);
  assert.equal(storage.has('apoc_invite_password_saved'), false);
});
