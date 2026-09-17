import { itemID, fetchItem, fetchIcon } from '../src/items.mjs';

const cacheHeaders = { 'cache-control': 'public, max-age=3600, s-maxage=86400, stale-while-revalidate=86400' };
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const id = itemID(url.searchParams.get('id'));
    if (!id) return new Response('Invalid item ID', { status: 400, headers: { 'cache-control': 'no-store' } });
    try {
      const details = await fetchItem(id);
      if (url.searchParams.get('icon') === '1') {
        const image = await fetchIcon(details.icon);
        return new Response(image, { headers: { ...cacheHeaders, 'content-type': 'image/jpeg', 'x-content-type-options': 'nosniff' } });
      }
      return Response.json(details, { headers: cacheHeaders });
    } catch {
      return new Response('Item details unavailable', { status: 503, headers: { 'cache-control': 'no-store' } });
    }
  },
};
