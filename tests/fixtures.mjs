export const USER = '11111111-1111-4111-8111-111111111111';
export const OTHER_USER = '22222222-2222-4222-8222-222222222222';
export const GUILD = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
export const OTHER_GUILD = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
export const RAID = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
export const OTHER_RAID = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
export const principal = { id: USER, isAnonymous: false };
export const membership = { guild_id: GUILD, user_id: USER, role: 'member', status: 'active', can_edit: false, can_upload: false };
export const raid = { guild_id: GUILD, id: RAID, name: 'Synthetic raid', run_id: 'test.1', source_key: 'synthetic', revision: 1, created_at: '2026-09-17T00:00:00Z' };
export const config = { origin: 'https://exampleproject.supabase.co', publishableKey: 'sb_publishable_test_only' };
export function token(extra = {}) {
  const claims = { sub: USER, role: 'authenticated', aud: 'authenticated', iss: `${config.origin}/auth/v1`, exp: 2100000000, is_anonymous: false, ...extra };
  return `${Buffer.from(JSON.stringify({ alg: 'RS256' })).toString('base64url')}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.notarealsignature`;
}
export function request(query = '', options = {}) {
  return new Request(`https://portal.invalid/api/portal${query}`, { headers: { Authorization: `Bearer ${token()}` }, ...options });
}
export function fakeBackend(overrides = {}) {
  const calls = [];
  const defaults = {
    authenticate: async () => principal,
    memberships: async () => [membership],
    membership: async () => membership,
    guild: async () => ({ id: GUILD, name: 'Synthetic guild', realm: 'Test realm', faction: 'Horde' }),
    raids: async () => [raid],
    raid: async () => raid,
    drops: async () => [{ guild_id: GUILD, raid_id: RAID, id: 'drop-1', item_name: 'Test item', boss: 'Test boss' }],
    members: async () => [{ guild_id: GUILD, raid_id: RAID, character_key: 'test-realm', name: 'Test-Realm', present: true }],
    visits: async () => [{ guild_id: GUILD, raid_id: RAID, id: 'visit-1', character_key: 'test-realm' }],
    comparisons: async () => [{ guild_id: GUILD, raid_id: RAID, id: 'comparison-1', status: 'insufficient_data', result: null }],
    ...overrides,
  };
  const backend = Object.fromEntries(Object.entries(defaults).map(([key, method]) => [key, async (...args) => {
    calls.push({ method: key, args }); return method(...args);
  }]));
  return { backend, calls };
}
