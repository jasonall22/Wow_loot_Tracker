import { buildLootRoster } from './src/roster.mjs';

const state = { config: null, session: null };
const shell = document.querySelector('.shell');
const signedOut = document.querySelector('#signed-out');
const signedIn = document.querySelector('#signed-in');
const inviteSetup = document.querySelector('#invite-setup');
const dashboard = document.querySelector('#dashboard');
const raidDetail = document.querySelector('#raid-detail');
const guildRoster = document.querySelector('#guild-roster');
const guildNav = document.querySelector('#guild-nav');
const form = document.querySelector('#sign-in-form');
const message = document.querySelector('#message');
const guildList = document.querySelector('#guild-list');
const guildMessage = document.querySelector('#guild-message');
const dashboardMessage = document.querySelector('#dashboard-message');
const pairingButton = document.querySelector('#create-pairing');
const pairingDialog = document.querySelector('#pairing-dialog');
const pairingResult = document.querySelector('#pairing-result');
const pairingCode = document.querySelector('#pairing-code');
const pairingMessage = document.querySelector('#pairing-message');
const raidDialog = document.querySelector('#raid-dialog');
const awardDialog = document.querySelector('#award-dialog');
const membersDialog = document.querySelector('#members-dialog');
const memberSelect = document.querySelector('#member-select');
const membersNotice = document.querySelector('#members-dialog-message');
let memberRows = [];
let pairingRequest = null;
let selectedGuildID = null;
let guilds = [];
let activeRaid = null;
let rosterPlayers = [];
let rosterRequest = 0;
let raidMembers = [];
let editingDrop = null;
let canManageRaids = false;
let refreshPromise = null;
let refreshingView = false;
let raidArchiveSignature = '';
const RAID_ARCHIVE_PAGE_SIZE = 50;
let raidArchiveVisibleLimit = RAID_ARCHIVE_PAGE_SIZE;
let raidArchiveRequest = 0;
let raidDetailSignature = '';
const collapsedLootBosses = new Set();
const itemTooltip = document.querySelector('#item-tooltip');
const itemDetails = new Map();
const itemQualityRequests = new Map();
const itemQualityQueue = [];
let activeItemQualityRequests = 0;
let tooltipAnchor = null;
let tooltipSequence = 0;

function loadItemDetails(id) {
  let pending = itemDetails.get(id);
  if (!pending) {
    pending = fetch(`/api/item?id=${id}&format=2`)
      .then(response => { if (!response.ok) throw new Error('Unavailable'); return response.json(); })
      .catch((error) => { if (itemDetails.get(id) === pending) itemDetails.delete(id); throw error; });
    itemDetails.set(id, pending);
    if (itemDetails.size > 256) itemDetails.delete(itemDetails.keys().next().value);
  }
  return pending;
}

function drainItemQualityQueue() {
  while (activeItemQualityRequests < 4 && itemQualityQueue.length) {
    const { id, resolve } = itemQualityQueue.shift();
    activeItemQualityRequests += 1;
    loadItemDetails(id).then((details) => {
      resolve(details.itemID === id && Number.isInteger(details.quality) && details.quality >= 0 && details.quality <= 7 ? details.quality : null);
    }, () => { itemQualityRequests.delete(id); resolve(null); }).finally(() => {
      activeItemQualityRequests -= 1;
      drainItemQualityQueue();
    });
  }
}

function itemQuality(id) {
  if (!itemQualityRequests.has(id)) {
    const pending = new Promise((resolve) => { itemQualityQueue.push({ id, resolve }); drainItemQualityQueue(); });
    itemQualityRequests.set(id, pending);
    if (itemQualityRequests.size > 2048) itemQualityRequests.delete(itemQualityRequests.keys().next().value);
  }
  return itemQualityRequests.get(id);
}

function hideItemTooltip() {
  tooltipSequence += 1;
  tooltipAnchor?.removeAttribute('aria-describedby');
  tooltipAnchor = null;
  itemTooltip.hidden = true;
}

function positionItemTooltip(anchor) {
  const rect = anchor.getBoundingClientRect();
  const width = itemTooltip.offsetWidth; const height = itemTooltip.offsetHeight;
  const left = rect.right + width + 12 < window.innerWidth ? rect.right + 12 : rect.left - width - 12;
  itemTooltip.style.left = `${Math.max(12, Math.min(left, window.innerWidth - width - 12))}px`;
  itemTooltip.style.top = `${Math.max(12, Math.min(rect.top, window.innerHeight - height - 12))}px`;
}

async function showItemTooltip(anchor, id, name) {
  if (tooltipAnchor === anchor && !itemTooltip.hidden) return;
  hideItemTooltip();
  tooltipAnchor = anchor;
  anchor.setAttribute('aria-describedby', 'item-tooltip');
  itemTooltip.replaceChildren();
  const heading = document.createElement('strong'); heading.className = 'tooltip-name'; heading.textContent = name;
  const note = document.createElement('p'); note.className = 'tooltip-note'; note.textContent = 'Loading item stats…';
  itemTooltip.append(heading, note);
  itemTooltip.hidden = false;
  positionItemTooltip(anchor);
  const sequence = tooltipSequence;
  try {
    const details = await loadItemDetails(id);
    if (tooltipSequence !== sequence || tooltipAnchor !== anchor) return;
    itemTooltip.replaceChildren();
    const lines = details.itemID === id && Array.isArray(details.lines) ? details.lines.slice(0, 40) : [];
    let renderedLines = 0;
    for (const line of lines) {
      const p = document.createElement('p'); p.className = 'tooltip-line';
      const parts = typeof line === 'string' ? [{ text: line, quality: 'q1' }] : Array.isArray(line) ? line : [];
      let hasText = false;
      for (const part of parts) {
        if (typeof part?.text !== 'string' || !part.text.trim()) continue;
        const span = document.createElement('span');
        span.className = /^q[0-7]?$/.test(part.quality) ? part.quality : 'q1';
        span.textContent = part.text;
        p.append(span);
        hasText = true;
      }
      if (hasText) { itemTooltip.append(p); renderedLines += 1; }
    }
    if (!renderedLines) throw new Error('Unavailable');
    const credit = document.createElement('p'); credit.className = 'tooltip-credit'; credit.textContent = 'TBC · Wowhead · base item stats'; itemTooltip.append(credit);
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
  if (membersDialog.open) membersDialog.close();
  if (raidDialog.open) raidDialog.close();
  if (awardDialog.open) awardDialog.close();
  state.session = null;
  activeRaid = null;
  selectedGuildID = null;
  canManageRaids = false;
  sessionStorage.removeItem('apoc_session');
  sessionStorage.removeItem('apoc_access_token');
  sessionStorage.removeItem('apoc_invite_setup');
  sessionStorage.removeItem('apoc_invite_password_saved');
  signedIn.hidden = true;
  inviteSetup.hidden = true;
  dashboard.hidden = true;
  raidDetail.hidden = true;
  guildRoster.hidden = true;
  guildNav.hidden = true;
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

async function acceptPendingInvites() {
  const response = await portalFetch('/api/accept-invite', { method: 'POST' });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error?.message ?? 'Could not finish your guild invitation.');
  return data;
}

async function adminEdit(action, fields = {}) {
  if (!activeRaid || !canManageRaids) throw new Error('Admin access is required.');
  const response = await portalFetch('/api/admin', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ guild: activeRaid.guildID, raid: activeRaid.raid.id, action, ...fields }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error?.message ?? 'Could not save the change.');
  return data;
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
  if (membersDialog.open) membersDialog.close();
  if (raidDialog.open) raidDialog.close();
  if (awardDialog.open) awardDialog.close();
  const details = entry.guild ?? {};
  const membership = entry.membership ?? {};
  selectedGuildID = details.id;
  activeRaid = null;
  guildRoster.hidden = true;
  rosterRequest += 1;
  canManageRaids = entry.permissions?.manageRaids === true;
  raidArchiveSignature = '';
  raidArchiveVisibleLimit = RAID_ARCHIVE_PAGE_SIZE;
  raidArchiveRequest += 1;
  shell.classList.add('workspace-view');
  signedIn.hidden = true;
  dashboard.hidden = false;
  guildNav.hidden = false;
  setGuildNav('overview');
  document.querySelector('#dashboard-title').textContent = details.name ?? 'Guild';
  document.querySelector('#dashboard-subtitle').textContent = [details.realm, details.faction].filter(Boolean).join(' · ');
  document.querySelector('#access-label').textContent = membership.role === 'admin' ? 'Admin' : membership.role === 'officer' ? 'Officer' : 'Member';
  pairingButton.hidden = entry.permissions?.uploadRaids !== true;
  document.querySelector('#manage-members').hidden = entry.permissions?.manageMembers !== true;
  const raidList = document.querySelector('#raid-list');
  raidList.replaceChildren();
  document.querySelector('#load-more-raids').hidden = true;
  dashboardMessage.textContent = 'Loading raid archive…';
  dashboardMessage.className = 'message';
  await loadRaidArchive(details.id);
}

async function loadRaidArchive(guildID, quiet = false) {
  const raidList = document.querySelector('#raid-list');
  const loadMore = document.querySelector('#load-more-raids');
  const request = ++raidArchiveRequest;
  loadMore.disabled = true;
  try {
    const rows = [];
    let hasMore = false;
    while (rows.length <= raidArchiveVisibleLimit) {
      const limit = Math.min(200, raidArchiveVisibleLimit + 1 - rows.length);
      const response = await portalFetch(`/api/portal?view=raids&guild=${encodeURIComponent(guildID)}&limit=${limit}&offset=${rows.length}`);
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error?.message ?? 'Could not load raids.');
      if (selectedGuildID !== guildID || dashboard.hidden || request !== raidArchiveRequest) return;
      const batch = data.raids ?? [];
      rows.push(...batch);
      if (batch.length < limit) break;
    }
    hasMore = rows.length > raidArchiveVisibleLimit;
    const raids = rows.slice(0, raidArchiveVisibleLimit);
    document.querySelector('#raid-count').textContent = `${raids.length}${hasMore ? '+' : ''}`;
    loadMore.hidden = !hasMore;
    dashboardMessage.textContent = '';
    dashboardMessage.className = 'message';
    if (!raids.length) dashboardMessage.textContent = 'No raids have been recorded for this guild yet.';
    const signature = JSON.stringify([hasMore, raids.map((raid) => [raid.id, raid.name, raid.revision, raid.created_at, raid.updated_at])]);
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
    if (selectedGuildID === guildID && !dashboard.hidden && request === raidArchiveRequest) {
      dashboardMessage.textContent = quiet ? `Live refresh paused: ${error.message}` : error.message;
      dashboardMessage.className = 'message error';
    }
  } finally {
    if (request === raidArchiveRequest) loadMore.disabled = false;
  }
}

async function loadGuildPages(guildID, view, maxRows = 20000) {
  const rows = [];
  for (let offset = 0; offset <= maxRows; offset += 200) {
    const response = await portalFetch(`/api/portal?view=${view}&guild=${encodeURIComponent(guildID)}&limit=200&offset=${offset}`);
    const data = await response.json().catch(() => ({}));
    if (!response.ok || !Array.isArray(data[view])) throw new Error(`Could not load ${view.replace('_', ' ')}.`);
    rows.push(...data[view]);
    if (data[view].length < 200) return rows;
  }
  throw new Error('The roster is too large to load completely. Please contact the site administrator.');
}

function setGuildNav(section) {
  for (const [name, selector] of [['overview', '#nav-overview'], ['roster', '#open-roster']]) {
    const button = document.querySelector(selector);
    if (name === section) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  }
}

function returnToOverview() {
  rosterRequest += 1;
  hideItemTooltip();
  activeRaid = null;
  guildRoster.hidden = true;
  raidDetail.hidden = true;
  dashboard.hidden = false;
  setGuildNav('overview');
  refreshVisible();
}

document.querySelector('#nav-overview').addEventListener('click', returnToOverview);

function renderGuildRoster() {
  const list = document.querySelector('#roster-list');
  const search = document.querySelector('#roster-search').value.trim().toLocaleLowerCase();
  list.replaceChildren();
  const visible = rosterPlayers.filter(player => player.name.toLocaleLowerCase().includes(search));
  if (!visible.length) {
    const empty = document.createElement('p'); empty.className = 'muted';
    empty.textContent = rosterPlayers.length ? 'No player matches that search.' : 'No raid participants or awards have been recorded yet.';
    list.append(empty); return;
  }
  for (const player of visible) {
    const card = document.createElement('details'); card.className = 'roster-player';
    const summary = document.createElement('summary'); summary.className = 'roster-player-summary';
    const identity = document.createElement('span'); identity.className = 'roster-identity';
    const name = document.createElement('strong'); name.textContent = player.name;
    const className = String(player.class || '').trim().toLowerCase().replace(/\s+/g, '');
    if (WOW_CLASSES.has(className.toUpperCase())) name.className = `class-${className}`;
    const meta = document.createElement('small');
    meta.textContent = `${player.class || 'Class not recorded'} · ${player.raidCount} recorded ${player.raidCount === 1 ? 'raid' : 'raids'}`;
    identity.append(name, meta);
    const icons = document.createElement('span'); icons.className = 'roster-icons';
    for (const drop of player.loot.slice(0, 4)) {
      const id = Number(drop.item_id);
      if (!Number.isInteger(id) || id < 1 || id > 10000000) continue;
      const icon = document.createElement('img'); icon.alt = ''; icon.width = 34; icon.height = 34;
      icon.src = `/api/item?id=${id}&icon=1`; icon.addEventListener('error', () => { icon.hidden = true; });
      icons.append(icon);
    }
    const count = document.createElement('b'); count.className = 'roster-count'; count.textContent = `${player.msCount} MS · ${player.loot.length} awards`;
    summary.append(identity, icons, count); card.append(summary);
    const history = document.createElement('div'); history.className = 'roster-history';
    if (!player.loot.length) {
      const empty = document.createElement('p'); empty.className = 'muted'; empty.textContent = 'No awarded loot recorded.'; history.append(empty);
    }
    for (const drop of player.loot) {
      const row = document.createElement('div'); row.className = 'roster-award';
      const id = Number(drop.item_id); const validID = Number.isInteger(id) && id > 0 && id <= 10000000;
      const title = document.createElement(validID ? 'button' : 'strong'); title.className = 'loot-item';
      if (validID) {
        title.type = 'button'; title.setAttribute('aria-label', `Item details: ${drop.item_name}`);
        const icon = document.createElement('img'); icon.className = 'loot-icon'; icon.alt = ''; icon.width = 38; icon.height = 38;
        icon.src = `/api/item?id=${id}&icon=1`; icon.addEventListener('error', () => { icon.hidden = true; }); title.append(icon);
        title.addEventListener('pointerenter', () => showItemTooltip(title, id, drop.item_name));
        title.addEventListener('pointerleave', hideItemTooltip);
        title.addEventListener('focus', () => showItemTooltip(title, id, drop.item_name));
        title.addEventListener('blur', hideItemTooltip);
        title.addEventListener('click', () => showItemTooltip(title, id, drop.item_name));
        itemQuality(id).then(quality => { if (quality !== null) title.className = `loot-item item-q${quality}`; });
      }
      const label = document.createElement('strong'); label.textContent = drop.item_name || 'Unknown item'; title.append(label);
      const details = document.createElement('span'); details.className = 'roster-award-meta';
      const when = drop.awarded_at || drop.dropped_at;
      const date = when && Number.isFinite(Date.parse(when)) ? new Date(when).toLocaleString() : 'Date unavailable';
      details.textContent = `${drop.award_type || 'Other'} · ${date} · ${drop.raid_name || 'Raid'}`;
      row.append(title, details); history.append(row);
    }
    card.append(history); list.append(card);
  }
}

document.querySelector('#open-roster').addEventListener('click', async () => {
  if (!selectedGuildID) return;
  const guildID = selectedGuildID; const request = ++rosterRequest;
  activeRaid = null;
  dashboard.hidden = true; raidDetail.hidden = true; guildRoster.hidden = false;
  setGuildNav('roster');
  document.querySelector('#roster-list').replaceChildren();
  const notice = document.querySelector('#roster-message'); notice.textContent = 'Loading tracked players and awards…'; notice.className = 'message';
  try {
    const [raids, members, drops] = await Promise.all([
      loadGuildPages(guildID, 'raids'), loadGuildPages(guildID, 'roster_members'), loadGuildPages(guildID, 'roster_drops'),
    ]);
    if (guildRoster.hidden || guildID !== selectedGuildID || request !== rosterRequest) return;
    rosterPlayers = buildLootRoster(members, drops, raids);
    notice.textContent = `${rosterPlayers.length} recorded players · ${rosterPlayers.reduce((sum, player) => sum + player.loot.length, 0)} awards`;
    renderGuildRoster();
  } catch (error) {
    if (request === rosterRequest && !guildRoster.hidden) { notice.textContent = error.message; notice.className = 'message error'; }
  }
});
document.querySelector('#roster-search').addEventListener('input', renderGuildRoster);

document.querySelector('#load-more-raids').addEventListener('click', async () => {
  if (!selectedGuildID || dashboard.hidden) return;
  raidArchiveVisibleLimit += RAID_ARCHIVE_PAGE_SIZE;
  await loadRaidArchive(selectedGuildID);
});

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
  if (activeRaid?.raid.id !== raid.id || activeRaid.guildID !== guildID) collapsedLootBosses.clear();
  activeRaid = { raid, guildID };
  raidMembers = [];
  raidDetailSignature = '';
  dashboard.hidden = true;
  raidDetail.hidden = false;
  setGuildNav('');
  document.querySelector('#manage-raid').hidden = !canManageRaids;
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
    const [dropResponse, members, visits] = await Promise.all([
      portalFetch(`${base}&view=drops`),
      loadRaidMembers(base),
      loadRaidVisits(base),
    ]);
    const drops = await dropResponse.json();
    if (!dropResponse.ok) throw new Error('Could not load raid details.');
    if (activeRaid?.raid.id !== raid.id || raidDetail.hidden) return;
    raidMembers = members;
    const signature = JSON.stringify([drops.drops ?? [], members, visits, Boolean(raid.closed_at)]);
    document.querySelector('#detail-message').textContent = '';
    document.querySelector('#detail-message').className = 'message';
    if (!drops.drops?.length && !members.length) document.querySelector('#detail-message').textContent = 'No loot or roster records have been captured for this raid yet.';
    if (signature === raidDetailSignature) return;
    raidDetailSignature = signature;
    if (awardDialog.open) populateRecipientOptions(document.querySelector('#award-winner').value);
    document.querySelector('#drop-count').textContent = `${drops.drops?.length ?? 0} records`;
    document.querySelector('#member-count').textContent = `${members.length} players`;
    hideItemTooltip();
    dropList.replaceChildren();
    memberList.replaceChildren();
    renderDropList(dropList, drops.drops ?? []);
    const attended = new Set(visits.map((visit) => String(visit.character_key || '').toLowerCase()));
    renderDetailList(memberList, members, (member) => {
      const hasVisit = attended.has(String(member.character_key || '').toLowerCase());
      const status = raid.closed_at
        ? (hasVisit || member.present ? 'Attended' : 'No attendance recorded')
        : (member.present ? 'Present' : hasVisit ? 'Left raid' : 'No attendance recorded');
      return [member.name, member.class || 'Class not recorded', status];
    });
  } catch (error) {
    if (activeRaid?.raid.id === raid.id && !raidDetail.hidden) {
      document.querySelector('#detail-message').textContent = quiet ? `Live refresh paused: ${error.message}` : error.message;
      document.querySelector('#detail-message').className = 'message error';
    }
  }
}

async function loadRaidMembers(base) {
  const members = [];
  for (let offset = 0; offset <= 1000; offset += 200) {
    const response = await portalFetch(`${base}&view=members&limit=200&offset=${offset}`);
    const data = await response.json();
    if (!response.ok || !Array.isArray(data.members)) throw new Error('Could not load raid attendance.');
    members.push(...data.members);
    if (data.members.length < 200) return members;
  }
  throw new Error('Raid attendance is too large to load.');
}

async function loadRaidVisits(base) {
  const visits = [];
  for (let offset = 0; offset <= 5000; offset += 200) {
    const response = await portalFetch(`${base}&view=visits&limit=200&offset=${offset}`);
    const data = await response.json();
    if (!response.ok || !Array.isArray(data.visits)) throw new Error('Could not load raid attendance visits.');
    visits.push(...data.visits);
    if (data.visits.length < 200) return visits;
  }
  throw new Error('Raid attendance has too many visits to load.');
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

const WOW_CLASSES = new Set(['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID']);

function winnerClass(winner) {
  if (!winner) return null;
  const name = winner.trim().toLocaleLowerCase();
  const exact = raidMembers.find((member) => String(member.name || '').trim().toLocaleLowerCase() === name);
  const shortName = name.split('-')[0];
  const matches = exact ? [exact] : raidMembers.filter((member) => String(member.name || '').trim().toLocaleLowerCase().split('-')[0] === shortName);
  if (matches.length !== 1) return null;
  const className = String(matches[0].class || '').trim().toUpperCase().replace(/\s+/g, '');
  return WOW_CLASSES.has(className) ? className.toLowerCase() : null;
}

function renderDropList(container, drops) {
  // Keep the encounter order supplied by the raid record, while placing all
  // drops from the same boss together and retaining their order within it.
  const groups = new Map();
  for (const drop of drops) {
    const bossName = typeof drop.boss === 'string' && drop.boss.trim() ? drop.boss.trim() : 'Boss not recorded';
    if (!groups.has(bossName)) groups.set(bossName, []);
    groups.get(bossName).push(drop);
  }
  for (const [bossName, bossDrops] of groups) {
    const group = document.createElement('section'); group.className = 'loot-boss-group';
    const toggle = document.createElement('button'); toggle.className = 'loot-boss-toggle'; toggle.type = 'button';
    const label = document.createElement('strong'); label.textContent = bossName;
    const count = document.createElement('span'); count.textContent = `${bossDrops.length} ${bossDrops.length === 1 ? 'item' : 'items'}`;
    const chevron = document.createElement('span'); chevron.className = 'loot-boss-chevron'; chevron.textContent = '▾'; chevron.setAttribute('aria-hidden', 'true');
    toggle.append(label, count, chevron);
    const body = document.createElement('div'); body.className = 'loot-boss-items';
    const setExpanded = (expanded) => {
      body.hidden = !expanded;
      toggle.setAttribute('aria-expanded', String(expanded));
      if (expanded) collapsedLootBosses.delete(bossName);
      else { collapsedLootBosses.add(bossName); hideItemTooltip(); }
    };
    setExpanded(!collapsedLootBosses.has(bossName));
    toggle.addEventListener('click', () => setExpanded(body.hidden));
    group.append(toggle, body);
    const headings = document.createElement('div'); headings.className = 'loot-column-headings';
    for (const heading of ['Item', 'Winner', 'Award']) {
      const column = document.createElement('span'); column.textContent = heading; headings.append(column);
    }
    body.append(headings);
    container.append(group);
    for (const drop of bossDrops) renderDropRow(body, drop);
  }
}

function renderDropRow(container, drop) {
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
    if (validID) itemQuality(id).then((quality) => {
      if (quality === null) return;
      title.className = `loot-item item-q${quality}`;
      const qualityNames = ['Poor', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Artifact', 'Heirloom'];
      title.setAttribute('aria-label', `${qualityNames[quality]} item: ${name}. Show item details`);
    });
    const winner = document.createElement('span'); winner.className = 'loot-winner';
    const winnerName = typeof drop.winner === 'string' ? drop.winner.trim() : '';
    winner.textContent = winnerName || (drop.award_type ? '—' : 'Unawarded');
    const className = winnerClass(winnerName);
    if (className) winner.className += ` class-${className}`;
    const awardType = document.createElement('span'); awardType.className = 'loot-award-type';
    const typeLabels = { MS: 'MS', OS: 'OS', DE: 'DE', GB: 'Guild', UNKNOWN: 'Other' };
    const type = typeof drop.award_type === 'string' ? drop.award_type.toUpperCase() : '';
    awardType.textContent = typeLabels[type] || '—';
    if (['MS', 'OS', 'DE', 'GB'].includes(type)) awardType.className += ` type-${type.toLowerCase()}`;
    item.append(title, winner, awardType);
    if (canManageRaids && drop.id) {
      const edit = document.createElement('button');
      edit.className = 'drop-edit secondary'; edit.type = 'button'; edit.textContent = 'Edit award';
      edit.setAttribute('aria-label', `Edit award for ${name}`);
      edit.addEventListener('click', () => {
        editingDrop = drop;
        document.querySelector('#award-item').textContent = name;
        populateRecipientOptions(drop.winner);
        document.querySelector('#award-type').value = drop.award_type ?? '';
        document.querySelector('#award-note').value = drop.award_note ?? '';
        document.querySelector('#award-dialog-message').textContent = '';
        awardDialog.showModal();
      });
      item.append(edit);
    }
    container.append(item);
}

function populateRecipientOptions(currentWinner) {
  const select = document.querySelector('#award-winner');
  select.replaceChildren();
  const empty = document.createElement('option');
  empty.value = ''; empty.textContent = 'No recipient'; select.append(empty);
  const names = new Map();
  for (const member of raidMembers) {
    const name = typeof member.name === 'string' ? member.name.trim() : '';
    if (name && !names.has(name)) names.set(name, member.present === true);
    else if (name && member.present === true) names.set(name, true);
  }
  for (const [name, present] of [...names].sort(([a], [b]) => a.localeCompare(b))) {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = present ? name : `${name} (not currently present)`;
    select.append(option);
  }
  if (currentWinner && !names.has(currentWinner)) {
    const option = document.createElement('option');
    option.value = currentWinner;
    option.textContent = `${currentWinner} (not in raid attendance)`;
    select.append(option);
  }
  select.value = currentWinner || '';
}

document.querySelector('#manage-raid').addEventListener('click', () => {
  if (!activeRaid || !canManageRaids) return;
  document.querySelector('#raid-name').value = activeRaid.raid.name ?? '';
  document.querySelector('#raid-dialog-message').textContent = '';
  raidDialog.showModal();
});
document.querySelector('#close-raid-dialog').addEventListener('click', () => raidDialog.close());
document.querySelector('#close-award-dialog').addEventListener('click', () => awardDialog.close());
awardDialog.addEventListener('close', () => { editingDrop = null; });

document.querySelector('#save-raid-name').addEventListener('click', async () => {
  const button = document.querySelector('#save-raid-name');
  const notice = document.querySelector('#raid-dialog-message');
  button.disabled = true;
  try {
    const name = document.querySelector('#raid-name').value.trim();
    if (!name) throw new Error('Enter a raid name.');
    await adminEdit('rename_raid', { name });
    activeRaid.raid.name = name;
    document.querySelector('#detail-title').textContent = name;
    raidArchiveSignature = '';
    raidDialog.close();
  } catch (error) { notice.textContent = error.message; notice.className = 'message error'; }
  finally { button.disabled = false; }
});

document.querySelector('#delete-raid').addEventListener('click', async () => {
  if (!activeRaid || !window.confirm(`Delete “${activeRaid.raid.name}” from the raid archive? Its audit history will remain.`)) return;
  const button = document.querySelector('#delete-raid');
  const notice = document.querySelector('#raid-dialog-message');
  button.disabled = true;
  try {
    const guildID = activeRaid.guildID;
    await adminEdit('delete_raid');
    raidDialog.close();
    activeRaid = null;
    raidDetail.hidden = true;
    dashboard.hidden = false;
    setGuildNav('overview');
    raidArchiveSignature = '';
    await loadRaidArchive(guildID);
  } catch (error) { notice.textContent = error.message; notice.className = 'message error'; }
  finally { button.disabled = false; }
});

document.querySelector('#save-award').addEventListener('click', async () => {
  if (!editingDrop || !activeRaid) return;
  const button = document.querySelector('#save-award');
  const notice = document.querySelector('#award-dialog-message');
  button.disabled = true;
  try {
    const winner = document.querySelector('#award-winner').value.trim() || null;
    const awardType = document.querySelector('#award-type').value || null;
    const awardNote = document.querySelector('#award-note').value;
    if (!awardType && winner) throw new Error('Choose an award type or clear the recipient.');
    if (['MS', 'OS'].includes(awardType) && !winner) throw new Error('Enter the recipient for MS or OS loot.');
    await adminEdit('edit_drop', { dropId: editingDrop.id, winner, awardType, awardNote });
    awardDialog.close();
    raidDetailSignature = '';
    await loadRaidDetail(activeRaid.raid, activeRaid.guildID);
  } catch (error) { notice.textContent = error.message; notice.className = 'message error'; }
  finally { button.disabled = false; }
});

function selectedMember() { return memberRows.find(member => member.user_id === memberSelect.value); }

function populateMemberEditor() {
  const member = selectedMember();
  document.querySelector('#save-member').disabled = !member;
  if (!member) return;
  document.querySelector('#member-role').value = member.role;
  document.querySelector('#member-status').value = member.status;
  document.querySelector('#member-upload').checked = member.can_upload === true;
  document.querySelector('#member-edit').checked = member.can_edit === true;
}

async function loadAdminMembers() {
  const response = await portalFetch(`/api/members?guild=${encodeURIComponent(selectedGuildID)}`);
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(data.error?.message ?? 'Could not load members.');
    error.status = response.status;
    throw error;
  }
  memberRows = Array.isArray(data.members) ? data.members : [];
  const previous = memberSelect.value;
  memberSelect.replaceChildren();
  for (const member of memberRows) {
    const option = document.createElement('option');
    option.value = member.user_id;
    option.textContent = member.email || member.user_id;
    memberSelect.append(option);
  }
  if (memberRows.some(member => member.user_id === previous)) memberSelect.value = previous;
  populateMemberEditor();
}

document.querySelector('#manage-members').addEventListener('click', async () => {
  if (!selectedGuildID) return;
  document.querySelector('#invite-member-message').textContent = '';
  membersNotice.textContent = 'Loading members…';
  membersNotice.className = 'message';
  membersDialog.showModal();
  try { await loadAdminMembers(); membersNotice.textContent = ''; }
  catch (error) { membersNotice.textContent = error.message; membersNotice.className = 'message error'; }
});
document.querySelector('#invite-member-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!selectedGuildID) return;
  const inviteForm = event.currentTarget;
  const submit = inviteForm.querySelector('button');
  const notice = document.querySelector('#invite-member-message');
  submit.disabled = true;
  notice.textContent = 'Preparing invitation…';
  notice.className = 'message';
  try {
    const response = await portalFetch('/api/invite', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ guild: selectedGuildID, email: document.querySelector('#invite-member-email').value.trim() }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error?.message ?? 'Could not send the invitation.');
    notice.textContent = data.status === 'existing_account' ? data.message : 'Invitation sent. They can set their own password from the email link.';
    inviteForm.reset();
  } catch (error) { notice.textContent = error.message; notice.className = 'message error'; }
  finally { submit.disabled = false; }
});
document.querySelector('#close-members-dialog').addEventListener('click', () => membersDialog.close());
memberSelect.addEventListener('change', populateMemberEditor);
document.querySelector('#member-role').addEventListener('change', () => {
  if (document.querySelector('#member-role').value === 'member') document.querySelector('#member-edit').checked = false;
});
document.querySelector('#save-member').addEventListener('click', async () => {
  const member = selectedMember();
  if (!member || !selectedGuildID) return;
  const button = document.querySelector('#save-member');
  button.disabled = true;
  membersNotice.textContent = '';
  try {
    const response = await portalFetch('/api/members', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ guild: selectedGuildID, userId: member.user_id,
        role: document.querySelector('#member-role').value,
        status: document.querySelector('#member-status').value,
        canUpload: document.querySelector('#member-upload').checked,
        canEdit: document.querySelector('#member-edit').checked }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error?.message ?? 'Could not update member.');
    try {
      await loadAdminMembers();
      membersNotice.textContent = 'Member access saved.';
      membersNotice.className = 'message';
    } catch (error) {
      if (error.status !== 403) throw error;
      membersDialog.close();
      dashboard.hidden = true;
      guildNav.hidden = true;
      signedIn.hidden = false;
      shell.classList.remove('workspace-view');
      await loadGuilds();
    }
  } catch (error) { membersNotice.textContent = error.message; membersNotice.className = 'message error'; }
  finally { button.disabled = false; }
});

function showSignedIn(checkInvites = false) {
  guildNav.hidden = true;
  inviteSetup.hidden = true;
  signedOut.hidden = true;
  signedIn.hidden = false;
  guildMessage.textContent = '';
  guildMessage.className = 'message';
  const beforeGuilds = checkInvites ? acceptPendingInvites().catch((error) => {
    guildMessage.textContent = error.message;
    guildMessage.className = 'message error';
  }) : Promise.resolve();
  beforeGuilds.then(() => loadGuilds()).catch((error) => {
    guildMessage.textContent = error.message;
    guildMessage.className = 'message error';
  });
}

function updateInviteSetup() {
  const saved = sessionStorage.getItem('apoc_invite_password_saved') === '1';
  const fields = document.querySelector('#invite-password-fields');
  fields.hidden = saved;
  for (const input of fields.querySelectorAll('input')) input.required = !saved;
  document.querySelector('#invite-join-button').textContent = saved ? 'Finish joining guild →' : 'Join guild →';
}

document.querySelector('#invite-password-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const inviteForm = event.currentTarget;
  const passwordSaved = sessionStorage.getItem('apoc_invite_password_saved') === '1';
  const password = document.querySelector('#invite-password').value;
  const confirm = document.querySelector('#invite-password-confirm').value;
  const submit = inviteForm.querySelector('button');
  const notice = document.querySelector('#invite-setup-message');
  if (!passwordSaved && (password.length < 12 || password !== confirm)) {
    notice.textContent = 'Use at least 12 characters, and make sure both passwords match.';
    notice.className = 'message error';
    return;
  }
  submit.disabled = true;
  notice.textContent = passwordSaved ? 'Joining your guild…' : 'Setting your password…';
  notice.className = 'message';
  try {
    if (!passwordSaved) {
      const config = await getConfig();
      const accessToken = await currentToken();
      const response = await fetch(`${config.url}/auth/v1/user`, {
        method: 'PUT',
        headers: { apikey: config.publishableKey, Authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
        body: JSON.stringify({ password }), cache: 'no-store', redirect: 'error',
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error_description ?? data.msg ?? 'Could not set your password.');
      sessionStorage.setItem('apoc_invite_password_saved', '1');
      updateInviteSetup();
    }
    notice.textContent = 'Joining your guild…';
    await acceptPendingInvites();
    inviteForm.reset();
    sessionStorage.removeItem('apoc_invite_setup');
    sessionStorage.removeItem('apoc_invite_password_saved');
    updateInviteSetup();
    showSignedIn();
  } catch (error) { notice.textContent = error.message; notice.className = 'message error'; }
  finally { submit.disabled = false; }
});

document.querySelector('#back-to-guilds').addEventListener('click', () => {
  if (pairingDialog.open) pairingDialog.close();
  if (membersDialog.open) membersDialog.close();
  dashboard.hidden = true;
  guildNav.hidden = true;
  signedIn.hidden = false;
  shell.classList.remove('workspace-view');
});
document.querySelector('#back-to-dashboard').addEventListener('click', returnToOverview);

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
    showSignedIn(true);
  } catch (error) {
    setMessage(error.message, 'error');
  } finally {
    submit.disabled = false;
  }
});

document.querySelector('#sign-out').addEventListener('click', () => {
  if (pairingDialog.open) pairingDialog.close();
  if (membersDialog.open) membersDialog.close();
  if (raidDialog.open) raidDialog.close();
  if (awardDialog.open) awardDialog.close();
  state.session = null;
  activeRaid = null;
  selectedGuildID = null;
  canManageRaids = false;
  sessionStorage.removeItem('apoc_session');
  sessionStorage.removeItem('apoc_access_token');
  sessionStorage.removeItem('apoc_invite_setup');
  sessionStorage.removeItem('apoc_invite_password_saved');
  signedIn.hidden = true;
  inviteSetup.hidden = true;
  signedOut.hidden = false;
  guildNav.hidden = true;
  shell.classList.remove('workspace-view');
  form.reset();
});

function receiveInviteLink() {
  if (typeof window === 'undefined') return false;
  const hash = window.location?.hash;
  if (!hash) return false;
  const params = new URLSearchParams(hash.slice(1));
  if (params.get('type') !== 'invite' && !params.has('error')) return false;
  window.history?.replaceState(null, '', window.location.pathname + window.location.search);
  const accessToken = params.get('access_token');
  const refreshToken = params.get('refresh_token');
  if (params.get('type') !== 'invite' || !accessToken || !refreshToken) {
    setMessage('This invitation link is invalid or expired. Ask your guild admin for a new one.', 'error');
    return true;
  }
  saveSession({ access_token: accessToken, refresh_token: refreshToken,
    expires_in: Number(params.get('expires_in') ?? 3600) });
  sessionStorage.setItem('apoc_invite_setup', '1');
  sessionStorage.removeItem('apoc_invite_password_saved');
  updateInviteSetup();
  signedOut.hidden = true;
  signedIn.hidden = true;
  inviteSetup.hidden = false;
  return true;
}

const inviteLinkHandled = receiveInviteLink();
const existingSession = sessionStorage.getItem('apoc_session');
const existingToken = sessionStorage.getItem('apoc_access_token');
if (!inviteLinkHandled && (existingSession || existingToken)) {
  try { state.session = existingSession ? JSON.parse(existingSession) : { access_token: existingToken }; }
  catch { state.session = null; }
  if (state.session?.access_token && sessionStorage.getItem('apoc_invite_setup') === '1') {
    updateInviteSetup();
    signedOut.hidden = true;
    signedIn.hidden = true;
    inviteSetup.hidden = false;
  } else if (state.session?.access_token) showSignedIn();
  else { sessionStorage.removeItem('apoc_session'); sessionStorage.removeItem('apoc_access_token'); }
}
