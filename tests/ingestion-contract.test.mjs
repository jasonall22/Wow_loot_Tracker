import { readFile } from 'node:fs/promises';
import test from 'node:test';
import assert from 'node:assert/strict';

const sql = await readFile(new URL('../db/ingestion.draft.sql', import.meta.url), 'utf8');

test('ingestion draft has guild-scoped device and replay state', () => {
  for (const table of ['apoc_devices', 'apoc_pairing_challenges', 'apoc_upload_receipts', 'apoc_drop_corrections', 'apoc_audit_events']) {
    assert.match(sql, new RegExp(`create table public\\.${table}`));
  }
  assert.match(sql, /foreign key \(guild_id, device_id\) references public\.apoc_devices/);
  assert.match(sql, /unique \(guild_id, request_id\)/);
  assert.match(sql, /unique \(guild_id, source_key, source_revision, payload_hash\)/);
});

test('ingestion draft keeps raw credentials and browser grants out', () => {
  assert.match(sql, /token_digest text not null/);
  assert.match(sql, /challenge_digest text not null/);
  assert.doesNotMatch(sql, /service_role|create policy/);
  assert.match(sql, /revoke all .* from public, anon, authenticated/s);
  for (const table of ['apoc_devices', 'apoc_pairing_challenges', 'apoc_upload_receipts', 'apoc_drop_corrections', 'apoc_audit_events']) {
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
  }
});

test('correction and audit rows are explicit and immutable by contract', () => {
  assert.match(sql, /reason text not null/);
  assert.match(sql, /corrected_by uuid not null references auth\.users/);
  assert.match(sql, /entity_type text not null/);
  assert.match(sql, /occurred_at timestamptz not null/);
  assert.doesNotMatch(sql, /payload jsonb|snapshot jsonb/);
});
