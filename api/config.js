import { loadConfig } from '../src/supabase.mjs';

// The publishable key is intended for browser clients. Never expose service-role
// credentials here; the protected data API still requires a user access token.
export default {
  async fetch() {
    try {
      const config = loadConfig();
      return new Response(JSON.stringify({ url: config.origin, publishableKey: config.publishableKey }), {
        status: 200,
        headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
      });
    } catch (error) {
      return new Response(JSON.stringify({ error: { code: error.code ?? 'cloud_not_configured', message: error.publicMessage ?? 'Portal configuration is unavailable.' } }), {
        status: error.status ?? 503,
        headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
      });
    }
  },
};
