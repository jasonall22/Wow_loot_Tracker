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

export function tooltipLines(html) {
  if (typeof html !== 'string') return [];
  const lines = []; let current = []; let length = 0; let blocked = null;
  const stack = [];
  const flush = () => {
    if (current.length) {
      current[0].text = current[0].text.trimStart();
      current.at(-1).text = current.at(-1).text.trimEnd();
      const spans = current.filter(span => span.text);
      if (spans.length && lines.length < 40) lines.push(spans);
    }
    current = []; length = 0;
  };
  for (const token of html.slice(0, METADATA_LIMIT).match(/<!--[\s\S]*?-->|<[^>]*>|[^<]+/g) ?? []) {
    if (token.startsWith('<!--')) continue;
    if (token.startsWith('<')) {
      const match = /^<\s*(\/?)\s*([a-z][a-z0-9]*)\b/i.exec(token);
      if (!match) continue;
      const [, closing, rawTag] = match; const tag = rawTag.toLowerCase();
      if (blocked) { if (closing && tag === blocked) blocked = null; continue; }
      if (!closing && /^(script|style|iframe|object|svg|math|template|noscript)$/.test(tag)) { blocked = tag; continue; }
      if (/^(br|p|div|tr|li|h[1-6])$/.test(tag)) flush();
      if (/^(td|th)$/.test(tag) && current.length && length < 300) { current.at(-1).text += '  '; length += 2; }
      if (closing) {
        const index = stack.findLastIndex(entry => entry.tag === tag);
        if (index !== -1) stack.splice(index);
      } else if (!/^(br|img|hr|input|meta|link)$/.test(tag)) {
        const classes = /\bclass\s*=\s*["']([^"']*)["']/i.exec(token)?.[1] ?? '';
        const quality = /(?:^|\s)(q[0-7]?)(?=\s|$)/.exec(classes)?.[1] ?? stack.at(-1)?.quality ?? 'q1';
        stack.push({ tag, quality });
      }
    } else if (!blocked && lines.length < 40 && length < 300) {
      const value = decodeEntities(token).replace(/\s+/g, ' ').slice(0, 300 - length);
      if (!value.trim() && !current.length) continue;
      const quality = stack.at(-1)?.quality ?? 'q1';
      if (current.at(-1)?.quality === quality) current.at(-1).text += value;
      else current.push({ text: value, quality });
      length += value.length;
    }
  }
  flush();
  return lines;
}

export function plainTooltip(html) {
  return tooltipLines(html).map(line => line.map(span => span.text).join('').replace(/\s+/g, ' ').trim());
}

export async function fetchItem(id, fetcher = fetch) {
  const raw = await bounded(`https://nether.wowhead.com/tooltip/item/${id}?dataEnv=5&locale=0`, METADATA_LIMIT, fetcher);
  const data = JSON.parse(new TextDecoder().decode(raw));
  if (!data || typeof data !== 'object' || !/^[a-zA-Z0-9_]{1,100}$/.test(data.icon ?? '')) throw new Error('Invalid item details');
  return { itemID: id, name: typeof data.name === 'string' ? data.name.slice(0, 200) : '', icon: data.icon.toLowerCase(), lines: tooltipLines(data.tooltip) };
}

export async function fetchIcon(icon, fetcher = fetch) {
  if (!/^[a-z0-9_]{1,100}$/.test(icon)) throw new Error('Invalid icon');
  const bytes = await bounded(`https://wow.zamimg.com/images/wow/icons/medium/${icon}.jpg`, ICON_LIMIT, fetcher);
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) throw new Error('Invalid icon image');
  return bytes;
}
