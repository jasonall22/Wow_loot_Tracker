const MAX_ID = 10000000;
const METADATA_LIMIT = 256 * 1024;
const ICON_LIMIT = 128 * 1024;

export function itemID(value) {
  return typeof value === 'string' && /^[1-9][0-9]{0,7}$/.test(value) && Number(value) <= MAX_ID ? Number(value) : null;
}

async function bounded(url, limit, fetcher) {
  const response = await fetcher(url, { redirect: 'manual', signal: AbortSignal.timeout(5000), headers: { 'user-agent': 'WowLootTracker/1.0 (public item details)' } });
  if (!response.ok || Number(response.headers.get('content-length') ?? 0) > limit || !response.body) throw new Error('Item details unavailable');
  const reader = response.body.getReader();
  const chunks = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) throw new Error('Item details too large');
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const result = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result;
}

function decodeEntities(text) {
  return text.replace(/&(#(?:x[0-9a-f]+|[0-9]+)|amp|lt|gt|quot|apos|nbsp);/gi, (match, entity) => {
    const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
    if (entity[0] !== '#') return named[entity.toLowerCase()] ?? match;
    const code = entity[1].toLowerCase() === 'x' ? Number.parseInt(entity.slice(2), 16) : Number(entity.slice(1));
    return Number.isInteger(code) && code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : '';
  });
}

export function plainTooltip(html) {
  if (typeof html !== 'string') return [];
  const safe = html.slice(0, METADATA_LIMIT)
    .replace(/<(script|style|iframe|object|svg|math|template|noscript)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<(br|p|div|tr|li|h[1-6])\b[^>]*>/gi, '\n')
    .replace(/<\/(p|div|tr|li|h[1-6])\s*>/gi, '\n')
    .replace(/<\/?(?:td|th)\b[^>]*>/gi, '  ')
    .replace(/<[^>]*>/g, '');
  return decodeEntities(safe).split('\n').map(line => line.replace(/\s+/g, ' ').trim()).filter(Boolean).slice(0, 40).map(line => line.slice(0, 300));
}

export async function fetchItem(id, fetcher = fetch) {
  const raw = await bounded(`https://nether.wowhead.com/tooltip/item/${id}?dataEnv=5&locale=0`, METADATA_LIMIT, fetcher);
  const data = JSON.parse(new TextDecoder().decode(raw));
  if (!data || typeof data !== 'object' || !/^[a-zA-Z0-9_]{1,100}$/.test(data.icon ?? '')) throw new Error('Invalid item details');
  return { itemID: id, name: typeof data.name === 'string' ? data.name.slice(0, 200) : '', icon: data.icon.toLowerCase(), lines: plainTooltip(data.tooltip) };
}

export async function fetchIcon(icon, fetcher = fetch) {
  if (!/^[a-z0-9_]{1,100}$/.test(icon)) throw new Error('Invalid icon');
  const bytes = await bounded(`https://wow.zamimg.com/images/wow/icons/medium/${icon}.jpg`, ICON_LIMIT, fetcher);
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) throw new Error('Invalid icon image');
  return bytes;
}
