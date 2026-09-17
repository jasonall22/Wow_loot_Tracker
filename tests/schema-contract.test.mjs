import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../db/schema.draft.sql', import.meta.url), 'utf8');
// These tests only inspect the draft contract; they do NOT execute Postgres/RLS.
test('draft includes RLS and explicit SELECT-only grants for every table', () => {
  const tables = [...sql.matchAll(/create table public\.(apoc_\w+)/g)].map(match => match[1]);
  assert.equal(tables.length, 7);
  for (const name of tables) assert.ok(sql.includes(`alter table public.${name} enable row level security;`));
  assert.match(sql, /grant select on[\s\S]*to authenticated;/);
  assert.doesNotMatch(sql, /grant\s+(?:all|insert|update|delete)/i);
  assert.doesNotMatch(sql, /grant\s+select[^;]*to\s+anon/i);
});
test('officer comparison policy explicitly restricts both guild and role', () => {
  const statement = sql.slice(sql.indexOf('create policy apoc_comparison_officers'), sql.indexOf('-- Explicit grants'));
  assert.match(statement, /m\.guild_id = apoc_comparisons\.guild_id/);
  assert.match(statement, /m\.user_id = \(select auth\.uid\(\)\)/);
  assert.match(statement, /m\.status = 'active'/);
  assert.match(statement, /m\.role in \('admin', 'officer'\)/);
});
test('no raw snapshot JSON in shared tables; no security-definer functions or metadata role check', () => {
  const tables = sql.slice(0, sql.indexOf('create table public.apoc_comparisons'));
  assert.doesNotMatch(tables, /\bjsonb\b/i);
  assert.doesNotMatch(sql, /create\s+(?:or replace\s+)?function/i);
  assert.doesNotMatch(sql, /user_metadata/i);
});
test('child relationships use composite guild foreign keys', () => {
  assert.equal([...sql.matchAll(/foreign key \(guild_id, raid_id\)/g)].length, 2);
  assert.match(sql, /foreign key \(guild_id, raid_id, character_key\)/);
  assert.match(sql, /foreign key \(guild_id, raid_id, drop_id\)/);
});
