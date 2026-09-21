import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../db/guild-roster-history.sql', import.meta.url), 'utf8');

test('guild roster history is RLS-protected and browser access is read-only', () => {
  assert.match(sql, /create table public\.apoc_guild_characters/i);
  assert.match(sql, /create table public\.apoc_guild_roster_state/i);
  assert.match(sql, /alter table public\.apoc_guild_characters enable row level security/i);
  assert.match(sql, /alter table public\.apoc_guild_roster_state enable row level security/i);
  assert.match(sql, /create policy apoc_guild_character_read[\s\S]*membership\.user_id = \(select auth\.uid\(\)\)[\s\S]*membership\.status = 'active'/i);
  assert.match(sql, /grant select on public\.apoc_guild_characters to authenticated/i);
  assert.doesNotMatch(sql, /grant\s+(insert|update|delete|all)[\s\S]*apoc_guild_characters[\s\S]*to authenticated/i);
});

test('complete newer snapshots move members between current and former without losing identity', () => {
  assert.match(sql, /create or replace function public\.sync_apoc_guild_roster/i);
  assert.match(sql, /security invoker/i);
  assert.doesNotMatch(sql, /security definer/i);
  assert.match(sql, /v_previous >= p_captured_at[\s\S]*'stale'/i);
  assert.match(sql, /set is_current = false, left_at = p_captured_at/i);
  assert.match(sql, /on conflict \(guild_id, character_key\) do update[\s\S]*is_current = true[\s\S]*left_at = null/i);
  assert.match(sql, /revoke all on function public\.sync_apoc_guild_roster[\s\S]*from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.sync_apoc_guild_roster[\s\S]*to service_role/i);
});
