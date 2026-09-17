const state = { config: null, session: null };
const signedOut = document.querySelector('#signed-out');
const signedIn = document.querySelector('#signed-in');
const form = document.querySelector('#sign-in-form');
const message = document.querySelector('#message');
const guildList = document.querySelector('#guild-list');

function setMessage(text, kind = '') {
  message.textContent = text;
  message.className = `message ${kind}`;
}

async function getConfig() {
  if (!state.config) {
    const response = await fetch('/api/config', { cache: 'no-store' });
    state.config = await response.json();
    if (!response.ok) throw new Error(state.config.error?.message ?? 'Portal configuration is unavailable.');
  }
  return state.config;
}

async function auth(path, body) {
  const config = await getConfig();
  const response = await fetch(`${config.url}/auth/v1/${path}`, {
    method: 'POST',
    headers: { apikey: config.publishableKey, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error_description ?? data.msg ?? 'Sign-in failed.');
  return data;
}

async function loadGuilds() {
  const response = await fetch('/api/portal?view=guilds', {
    headers: { Authorization: `Bearer ${state.session.access_token}` },
    cache: 'no-store',
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error?.message ?? 'Could not load guilds.');
  guildList.replaceChildren();
  if (!data.guilds?.length) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = 'No active guild memberships were found.';
    guildList.append(empty);
    return;
  }
  for (const guild of data.guilds) {
    const button = document.createElement('button');
    button.className = 'guild';
    button.type = 'button';
    button.innerHTML = `<strong></strong><span>Open guild <b>→</b></span>`;
    button.querySelector('strong').textContent = guild.name ?? 'Unnamed guild';
    button.addEventListener('click', () => {
      sessionStorage.setItem('apoc_selected_guild', guild.id);
      button.querySelector('span').textContent = 'Selected';
    });
    guildList.append(button);
  }
}

function showSignedIn() {
  signedOut.hidden = true;
  signedIn.hidden = false;
  loadGuilds().catch((error) => setMessage(error.message, 'error'));
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const submit = form.querySelector('button');
  submit.disabled = true;
  setMessage('Signing in…');
  try {
    state.session = await auth('token?grant_type=password', {
      email: form.email.value.trim(), password: form.password.value,
    });
    sessionStorage.setItem('apoc_access_token', state.session.access_token);
    setMessage('');
    showSignedIn();
  } catch (error) {
    setMessage(error.message, 'error');
  } finally {
    submit.disabled = false;
  }
});

document.querySelector('#sign-out').addEventListener('click', () => {
  state.session = null;
  sessionStorage.removeItem('apoc_access_token');
  signedIn.hidden = true;
  signedOut.hidden = false;
  form.reset();
});

const existingToken = sessionStorage.getItem('apoc_access_token');
if (existingToken) {
  state.session = { access_token: existingToken };
  showSignedIn();
}
