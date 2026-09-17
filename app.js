const state = { config: null, session: null };
const shell = document.querySelector('.shell');
const signedOut = document.querySelector('#signed-out');
const signedIn = document.querySelector('#signed-in');
const dashboard = document.querySelector('#dashboard');
const raidDetail = document.querySelector('#raid-detail');
const form = document.querySelector('#sign-in-form');
const message = document.querySelector('#message');
const guildList = document.querySelector('#guild-list');
const dashboardMessage = document.querySelector('#dashboard-message');
const pairingButton = document.querySelector('#create-pairing');
const pairingDialog = document.querySelector('#pairing-dialog');
const pairingResult = document.querySelector('#pairing-result');
const pairingCode = document.querySelector('#pairing-code');
const pairingMessage = document.querySelector('#pairing-message');
let pairingRequest = null;
let selectedGuildID = null;
let guilds = [];
let activeRaid = null;
let refreshPromise = null;
let refreshingView = false;
let raidArchiveSignature = '';
let raidDetailSignature = '';
const itemTooltip = document.querySelector('#item-tooltip');
const itemDetails = new Map();
let tooltipAnchor = null;
let tooltipSequence = 0;

function hideItemTooltip() {
  tooltipSequence += 1;
  tooltipAnchor?.removeAttribute('aria-describedby');
  tooltipAnchor = null;
  itemTooltip.hidden = true;
}

function positionItemTooltip(anchor) {
  const rect = anchor.getBoundingClientRect();
  itemTooltip.style.left = `${Math.max(12, Math.min(rect.left, window.innerWidth - itemTooltip.offsetWidth - 12))}px`;
  itemTooltip.style.top = `${rect.bottom + itemTooltip.offsetHeight + 12 < window.innerHeight ? rect.bottom + 8 : Math.max(12, rect.top - itemTooltip.offsetHeight - 8)}px`;
}

async function showItemTooltip(anchor, id, name) {
  if (tooltipAnchor === anchor && !itemTooltip.hidden) return;
  hideItemTooltip();
  tooltipAnchor = anchor;
  anchor.setAttribute('aria-describedby', 'item-tooltip');
  itemTooltip.replaceChildren();
  const heading = document.createElement('strong'); heading.textContent = name;
  const note = document.createElement('p'); note.textContent = 'Loading item stats…';
  itemTooltip.append(heading, note);
  itemTooltip.hidden = false;
  positionItemTooltip(anchor);
  const sequence = tooltipSequence;
  try {
    let pending = itemDetails.get(id);
    if (!pending) {
      pending = fetch(`/api/item?id=${id}`).then(response => { if (!response.ok) throw new Error('Unavailable'); return response.json(); });
      itemDetails.set(id, pending);
      if (itemDetails.size > 256) itemDetails.delete(itemDetails.keys().next().value);
    }
    const details = await pending;
    if (tooltipSequence !== sequence || tooltipAnchor !== anchor) return;
    itemTooltip.replaceChildren();
    const lines = details.itemID === id && Array.isArray(details.lines) ? details.lines.slice(0, 40) : [];
    if (!lines.length) throw new Error('Unavailable');
    for (const line of lines) {
      const p = document.createElement('p'); p.textContent = String(line); itemTooltip.append(p);
    }
    const credit = document.createElement('small'); credit.textContent = 'TBC · Wowhead · base item stats'; itemTooltip.append(credit);
    positionItemTooltip(anchor);
  } catch {
    itemDetails.delete(id);
    if (tooltipSequence !== sequence || tooltipAnchor !== anchor) return;
    note.textContent = 'Item stats are temporarily unavailable.';
    itemTooltip.replaceChildren(heading, note);
  }
}
document.addEventListener('keydown', (event) => { if (event.key === 'Escape') hideItemTooltip(); });

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
  if (!response.ok) {
    const error = new Error(data.error_description ?? data.msg ?? 'Sign-in failed.');
    error.status = response.status;
    throw error;
  }
  return data;
}

function saveSession(session) {
  state.session = {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at ?? Math.floor(Date.now() / 1000) + Number(session.expires_in ?? 3600),
  };
  sessionStorage.setItem('apoc_session', JSON.stringify(state.session));
  sessionStorage.removeItem('apoc_access_token');
}

function sessionExpired() {
  state.session = null;
  activeRaid = null;
  selectedGuildID = null;
  sessionStorage.removeItem('apoc_session');
  sessionStorage.removeItem('apoc_access_token');
  signedIn.hidden = true;
  dashboard.hidden = true;
  raidDetail.hidden = true;
  signedOut.hidden = false;
  shell.classList.remove('workspace-view');
  setMessage('Your session expired. Sign in again to see live updates.', 'error');
}

async function currentToken() {
  if (!state.session) throw new Error('Sign in to continue.');
  const expiresAt = Number(state.session.expires_at);
  if (!state.session.refresh_token || !expiresAt || expiresAt > Date.now() / 1000 + 60) return state.session.access_token;
  if (!refreshPromise) {
    const previous = state.session;
    refreshPromise = auth('token?grant_type=refresh_token', { refresh_token: previous.refresh_token })
      .then((session) => {
        if (state.session !== previous) throw new Error('Sign in to continue.');
        saveSession(session);
      })
      .catch((error) => {
        if (state.session === previous && [400, 401, 403].includes(error.status)) sessionExpired();
        throw error;
      })
      .finally(() => { refreshPromise = null; });
  }
  await refreshPromise;
  return state.session.access_token;
}

async function portalFetch(url, options = {}) {
  const accessToken = await currentToken();
  const response = await fetch(url, {
    ...options, cache: 'no-store',
    headers: { ...options.headers, Authorization: `Bearer ${accessToken}` },
  });
  if (response.status === 401 && state.session?.access_token === accessToken) sessionExpired();
  return response;
}

async function loadGuilds() {
  const response = await portalFetch('/api/portal?view=guilds');
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error?.message ?? 'Could not load guilds.');
  guildList.replaceChildren();
  guilds = data.guilds ?? [];
  if (!guilds.length) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = 'No active guild memberships were found.';
    guildList.append(empty);
    return;
  }
  for (const guild of guilds) {
    const details = guild.guild ?? {};
    const button = document.createElement('button');
    button.className = 'guild';
    button.type = 'button';
    button.innerHTML = `<strong></strong><span>Open guild <b>→</b></span>`;
    button.querySelector('strong').textContent = details.name ?? 'Unnamed guild';
    button.addEventListener('click', () => {
      sessionStorage.setItem('apoc_selected_guild', details.id);
      button.querySelector('span').textContent = 'Selected';
      openDashboard(guild);
    });
    guildList.append(button);
  }
}

async function openDashboard(entry) {
  if (pairingDialog.open) pairingDialog.close();
  const details = entry.guild ?? {};
  const membership = entry.membership ?? {};
  selectedGuildID = details.id;
  activeRaid = null;
  raidArchiveSignature = '';
  shell.classList.add('workspace-view');
  signedIn.hidden = true;
  dashboard.hidden = false;
  document.querySelector('#dashboard-title').textContent = details.name ?? 'Guild';
  document.querySelector('#dashboard-subtitle').textContent = [details.realm, details.faction].filter(Boolean).join(' · ');
  document.querySelector('#dashboard-role').textContent = membership.role ?? 'member';
  document.querySelector('#access-label').textContent = membership.role === 'admin' ? 'Admin' : membership.role === 'officer' ? 'Officer' : 'Member';
  pairingButton.hidden = entry.permissions?.uploadRaids !== true;
  const raidList = document.querySelector('#raid-list');
  raidList.replaceChildren();
  dashboardMessage.textContent = 'Loading raid archive…';
  dashboardMessage.className = 'message';
  await loadRaidArchive(details.id);
}

async function loadRaidArchive(guildID, quiet = false) {
  const raidList = document.querySelector('#raid-list');
  try {
    const response = await portalFetch(`/api/portal?view=raids&guild=${encodeURIComponent(guildID)}`);
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error?.message ?? 'Could not load raids.');
    if (selectedGuildID !== guildID || dashboard.hidden) return;
    const raids = data.raids ?? [];
    document.querySelector('#raid-count').textContent = raids.length;
    dashboardMessage.textContent = '';
    dashboardMessage.className = 'message';
    if (!raids.length) dashboardMessage.textContent = 'No raids have been recorded for this guild yet.';
    const signature = JSON.stringify(raids.map((raid) => [raid.id, raid.name, raid.revision, raid.created_at]));
    if (signature === raidArchiveSignature) return;
    raidArchiveSignature = signature;
    raidList.replaceChildren();
    if (!raids.length) return;
    for (const raid of raids) {
      const item = document.createElement('div');
      item.className = 'raid-row';
      item.tabIndex = 0;
      item.setAttribute('role', 'button');
      const date = raid.created_at ? new Date(raid.created_at).toLocaleDateString() : 'Date unavailable';
      item.innerHTML = '<div><strong></strong><span></span></div><b>→</b>';
      item.querySelector('strong').textContent = raid.name;
      item.querySelector('span').textContent = `${date} · revision ${raid.revision}`;
      item.addEventListener('click', () => openRaidDetail(raid, guildID));
      item.addEventListener('keydown', (event) => { if (event.key === 'Enter' || event.key === ' ') openRaidDetail(raid, guildID); });
      raidList.append(item);
    }
  } catch (error) {
    if (selectedGuildID === guildID && !dashboard.hidden) {
      dashboardMessage.textContent = quiet ? `Live refresh paused: ${error.message}` : error.message;
      dashboardMessage.className = 'message error';
    }
  }
}

pairingDialog.addEventListener('close', () => {
  pairingRequest?.abort();
  pairingRequest = null;
  pairingCode.textContent = '';
  document.querySelector('#pairing-expiry').textContent = '';
  pairingResult.hidden = true;
  pairingMessage.textContent = '';
  pairingMessage.className = 'message';
  if (!pairingButton.hidden) pairingButton.focus();
});

document.querySelector('#close-pairing').addEventListener('click', () => pairingDialog.close());

pairingButton.addEventListener('click', async () => {
  if (pairingDialog.open || !selectedGuildID || !state.session) return;
  const guildID = selectedGuildID;
  const controller = new AbortController();
  pairingRequest = controller;
  pairingButton.disabled = true;
  pairingResult.hidden = true;
  pairingCode.textContent = '';
  pairingMessage.textContent = 'Creating one-time code…';
  pairingMessage.className = 'message';
  pairingDialog.showModal();
  try {
    const response = await portalFetch('/api/pairing', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ guild: guildID }), signal: controller.signal,
    });
    const data = await response.json().catch(() => ({}));
    if (!pairingDialog.open || controller.signal.aborted) return;
    if (!response.ok) throw new Error(data.error?.message ?? 'Could not create a connection code.');
    pairingCode.textContent = data.challenge;
    document.querySelector('#pairing-expiry').textContent = `Expires ${new Date(data.expiresAt).toLocaleTimeString()}`;
    pairingResult.hidden = false;
    pairingMessage.textContent = '';
  } catch (error) {
    if (error.name !== 'AbortError' && pairingDialog.open) {
      pairingMessage.textContent = error.message;
      pairingMessage.className = 'message error';
    }
  } finally {
    if (pairingRequest === controller) pairingRequest = null;
    pairingButton.disabled = false;
  }
});

document.querySelector('#copy-pairing').addEventListener('click', async () => {
  if (!pairingDialog.open || !pairingCode.textContent) return;
  const button = document.querySelector('#copy-pairing');
  button.disabled = true;
  try {
    await navigator.clipboard.writeText(pairingCode.textContent);
    pairingDialog.close();
  } catch {
    pairingMessage.textContent = 'Could not copy the code. Please try again.';
    pairingMessage.className = 'message error';
  } finally { button.disabled = false; }
});

async function openRaidDetail(raid, guildID) {
  activeRaid = { raid, guildID };
  raidDetailSignature = '';
  dashboard.hidden = true;
  raidDetail.hidden = false;
  document.querySelector('#detail-title').textContent = raid.name ?? 'Raid';
  document.querySelector('#detail-meta').textContent = raid.created_at ? new Date(raid.created_at).toLocaleString() : 'Date unavailable';
  const dropList = document.querySelector('#drop-list');
  const memberList = document.querySelector('#member-list');
  dropList.replaceChildren(); memberList.replaceChildren();
  document.querySelector('#detail-message').textContent = 'Loading raid details…';
  await loadRaidDetail(raid, guildID);
}

async function loadRaidDetail(raid, guildID, quiet = false) {
  const dropList = document.querySelector('#drop-list');
  const memberList = document.querySelector('#member-list');
  try {
    const base = `/api/portal?guild=${encodeURIComponent(guildID)}&raid=${encodeURIComponent(raid.id)}`;
    const [dropResponse, memberResponse] = await Promise.all([
      portalFetch(`${base}&view=drops`),
      portalFetch(`${base}&view=members`),
    ]);
    const drops = await dropResponse.json(); const members = await memberResponse.json();
    if (!dropResponse.ok || !memberResponse.ok) throw new Error('Could not load raid details.');
    if (activeRaid?.raid.id !== raid.id || raidDetail.hidden) return;
    const signature = JSON.stringify([drops.drops ?? [], members.members ?? []]);
    document.querySelector('#detail-message').textContent = '';
    document.querySelector('#detail-message').className = 'message';
    if (!drops.drops?.length && !members.members?.length) document.querySelector('#detail-message').textContent = 'No loot or roster records have been captured for this raid yet.';
    if (signature === raidDetailSignature) return;
    raidDetailSignature = signature;
    document.querySelector('#drop-count').textContent = `${drops.drops?.length ?? 0} records`;
    document.querySelector('#member-count').textContent = `${members.members?.length ?? 0} players`;
    hideItemTooltip();
    dropList.replaceChildren();
    memberList.replaceChildren();
    renderDropList(dropList, drops.drops ?? []);
    renderDetailList(memberList, members.members ?? [], (member) => [member.name, member.class || 'Class not recorded', member.present ? 'Present' : 'Absent']);
  } catch (error) {
    if (activeRaid?.raid.id === raid.id && !raidDetail.hidden) {
      document.querySelector('#detail-message').textContent = quiet ? `Live refresh paused: ${error.message}` : error.message;
      document.querySelector('#detail-message').className = 'message error';
    }
  }
}

async function refreshVisible() {
  if (document.hidden || !state.session || refreshingView) return;
  refreshingView = true;
  try {
    if (!raidDetail.hidden && activeRaid) await loadRaidDetail(activeRaid.raid, activeRaid.guildID, true);
    else if (!dashboard.hidden && selectedGuildID) await loadRaidArchive(selectedGuildID, true);
  } finally { refreshingView = false; }
}
setInterval(refreshVisible, 5000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshVisible(); });

function renderDetailList(container, rows, fields) {
  for (const row of rows) {
    const item = document.createElement('div'); item.className = 'detail-row';
    item.innerHTML = '<strong></strong><span></span><em></em>';
    const values = fields(row); item.querySelector('strong').textContent = values[0]; item.querySelector('span').textContent = values[1]; item.querySelector('em').textContent = values[2]; container.append(item);
  }
}

function renderDropList(container, drops) {
  for (const drop of drops) {
    const item = document.createElement('div'); item.className = 'detail-row loot-row';
    const id = Number(drop.item_id);
    const validID = Number.isInteger(id) && id > 0 && id <= 10000000;
    const name = String(drop.item_name || 'Unknown item');
    const title = document.createElement(validID ? 'button' : 'strong');
    title.className = 'loot-item';
    if (validID) {
      title.type = 'button';
      title.setAttribute('aria-label', `Item details: ${name}`);
      const icon = document.createElement('img');
      icon.className = 'loot-icon'; icon.alt = ''; icon.width = 38; icon.height = 38;
      icon.src = `/api/item?id=${id}&icon=1`;
      icon.addEventListener('error', () => { icon.hidden = true; });
      title.append(icon);
      title.addEventListener('pointerenter', () => showItemTooltip(title, id, name));
      title.addEventListener('pointerleave', hideItemTooltip);
      title.addEventListener('focus', () => showItemTooltip(title, id, name));
      title.addEventListener('blur', hideItemTooltip);
      title.addEventListener('click', () => showItemTooltip(title, id, name));
    }
    const label = document.createElement('strong'); label.textContent = name; title.append(label);
    const boss = document.createElement('span'); boss.textContent = drop.boss || 'Boss not recorded';
    const award = document.createElement('em'); award.textContent = drop.winner ? `Awarded to ${drop.winner}` : 'Unawarded';
    item.append(title, boss, award); container.append(item);
  }
}

function showSignedIn() {
  signedOut.hidden = true;
  signedIn.hidden = false;
  loadGuilds().catch((error) => setMessage(error.message, 'error'));
}

document.querySelector('#back-to-guilds').addEventListener('click', () => {
  if (pairingDialog.open) pairingDialog.close();
  dashboard.hidden = true;
  signedIn.hidden = false;
  shell.classList.remove('workspace-view');
});
document.querySelector('#back-to-dashboard').addEventListener('click', () => { activeRaid = null; raidDetail.hidden = true; dashboard.hidden = false; refreshVisible(); });

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const submit = form.querySelector('button');
  submit.disabled = true;
  setMessage('Signing in…');
  try {
    const session = await auth('token?grant_type=password', {
      email: form.email.value.trim(), password: form.password.value,
    });
    saveSession(session);
    setMessage('');
    showSignedIn();
  } catch (error) {
    setMessage(error.message, 'error');
  } finally {
    submit.disabled = false;
  }
});

document.querySelector('#sign-out').addEventListener('click', () => {
  if (pairingDialog.open) pairingDialog.close();
  state.session = null;
  activeRaid = null;
  selectedGuildID = null;
  sessionStorage.removeItem('apoc_session');
  sessionStorage.removeItem('apoc_access_token');
  signedIn.hidden = true;
  signedOut.hidden = false;
  shell.classList.remove('workspace-view');
  form.reset();
});

const existingSession = sessionStorage.getItem('apoc_session');
const existingToken = sessionStorage.getItem('apoc_access_token');
if (existingSession || existingToken) {
  try { state.session = existingSession ? JSON.parse(existingSession) : { access_token: existingToken }; }
  catch { state.session = null; }
  if (state.session?.access_token) showSignedIn();
  else { sessionStorage.removeItem('apoc_session'); sessionStorage.removeItem('apoc_access_token'); }
}
