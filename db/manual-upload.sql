-- One device-bound upload transaction per raid revision. Browser roles have no
-- table or function grants. The application validates each explicit field and
-- size before calling this service_role-only function.
alter table public.apoc_visits add constraint apoc_visit_source_interval
  unique (guild_id, raid_id, character_key, joined_at);

create or replace function public.ingest_apoc_raid(
  p_token_digest text, p_request_id uuid, p_source_key text,
  p_source_revision bigint, p_payload_hash text, p_captured_at timestamptz,
  p_raid jsonb, p_drops jsonb, p_members jsonb
)
returns table(upload_status text, guild_id uuid, raid_id uuid)
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_device public.apoc_devices%rowtype;
  v_receipt public.apoc_upload_receipts%rowtype;
  v_raid_id uuid;
  v_revision bigint;
  v_drop jsonb;
  v_member jsonb;
  v_visit jsonb;
begin
  if p_token_digest !~ '^[a-f0-9]{64}$' or p_payload_hash !~ '^[a-f0-9]{64}$'
     or p_source_key is null or char_length(p_source_key) not between 1 and 200
     or p_source_revision is null or p_source_revision < 0
     or jsonb_typeof(p_raid) <> 'object' or jsonb_typeof(p_drops) <> 'array'
     or jsonb_typeof(p_members) <> 'array' then
    raise exception 'invalid upload input' using errcode = '22023';
  end if;

  select * into v_device from public.apoc_devices as d
   where d.token_digest = p_token_digest and d.revoked_at is null for share;
  if not found then return; end if;

  select * into v_receipt from public.apoc_upload_receipts as r
   where r.guild_id = v_device.guild_id and r.request_id = p_request_id;
  if found then
    if v_receipt.source_key <> p_source_key or v_receipt.source_revision <> p_source_revision
       or v_receipt.payload_hash <> p_payload_hash then
      raise exception 'request id reused with different upload' using errcode = '22023';
    end if;
    upload_status := 'duplicate'; guild_id := v_device.guild_id;
    select r.id into raid_id from public.apoc_raids as r
      where r.guild_id = v_device.guild_id and r.source_key = p_source_key;
    return next; return;
  end if;

  insert into public.apoc_raids(guild_id, source_key, name, run_id, revision, created_at, closed_at)
  values (v_device.guild_id, p_source_key, p_raid->>'name', p_raid->>'run_id',
          p_source_revision, (p_raid->>'created_at')::timestamptz,
          (p_raid->>'closed_at')::timestamptz)
  on conflict on constraint apoc_raids_guild_id_source_key_key
  do nothing returning id into v_raid_id;

  if v_raid_id is null then
    select r.id, r.revision into v_raid_id, v_revision from public.apoc_raids as r
      where r.guild_id = v_device.guild_id and r.source_key = p_source_key for update;
    -- Another request may have committed while the first insert waited.
    select * into v_receipt from public.apoc_upload_receipts as r
      where r.guild_id = v_device.guild_id and r.request_id = p_request_id;
    if found then
      if v_receipt.source_key <> p_source_key or v_receipt.source_revision <> p_source_revision
         or v_receipt.payload_hash <> p_payload_hash then
        raise exception 'request id reused with different upload' using errcode = '22023';
      end if;
      upload_status := 'duplicate'; guild_id := v_device.guild_id; raid_id := v_raid_id;
      return next; return;
    end if;
    if p_source_revision <= v_revision then
      upload_status := 'stale'; guild_id := v_device.guild_id; raid_id := v_raid_id;
      return next; return;
    end if;
    update public.apoc_raids as r set name = p_raid->>'name', run_id = p_raid->>'run_id',
      revision = p_source_revision, created_at = (p_raid->>'created_at')::timestamptz,
      closed_at = (p_raid->>'closed_at')::timestamptz, updated_at = now()
      where r.guild_id = v_device.guild_id and r.id = v_raid_id;
  end if;

  for v_drop in select value from jsonb_array_elements(p_drops) loop
    insert into public.apoc_drops as existing
      (guild_id, raid_id, id, item_id, item_name, boss, dropped_at,
       winner, award_type, awarded_at, award_note)
    values (v_device.guild_id, v_raid_id, v_drop->>'id', (v_drop->>'item_id')::integer,
            v_drop->>'item_name', v_drop->>'boss', (v_drop->>'dropped_at')::timestamptz,
            v_drop->>'winner', v_drop->>'award_type', (v_drop->>'awarded_at')::timestamptz,
            v_drop->>'award_note')
    on conflict on constraint apoc_drops_pkey do update set
      item_id = excluded.item_id, item_name = excluded.item_name,
      boss = excluded.boss, dropped_at = excluded.dropped_at,
      winner = case when exists (
        select 1 from public.apoc_drop_corrections as c where c.guild_id = existing.guild_id
          and c.raid_id = existing.raid_id and c.drop_id = existing.id
      ) then existing.winner else excluded.winner end,
      award_type = case when exists (
        select 1 from public.apoc_drop_corrections as c where c.guild_id = existing.guild_id
          and c.raid_id = existing.raid_id and c.drop_id = existing.id
      ) then existing.award_type else excluded.award_type end,
      awarded_at = case when exists (
        select 1 from public.apoc_drop_corrections as c where c.guild_id = existing.guild_id
          and c.raid_id = existing.raid_id and c.drop_id = existing.id
      ) then existing.awarded_at else excluded.awarded_at end,
      award_note = case when exists (
        select 1 from public.apoc_drop_corrections as c where c.guild_id = existing.guild_id
          and c.raid_id = existing.raid_id and c.drop_id = existing.id
      ) then existing.award_note else excluded.award_note end;
  end loop;

  for v_member in select value from jsonb_array_elements(p_members) loop
    insert into public.apoc_raid_members as existing
      (guild_id, raid_id, character_key, name, class, raid_group, present)
    values (v_device.guild_id, v_raid_id, v_member->>'character_key', v_member->>'name',
            v_member->>'class', (v_member->>'raid_group')::smallint,
            (v_member->>'present')::boolean)
    on conflict on constraint apoc_raid_members_pkey do update set
      name = excluded.name, class = excluded.class, raid_group = excluded.raid_group,
      present = excluded.present;
    for v_visit in select value from jsonb_array_elements(v_member->'visits') loop
      insert into public.apoc_visits as existing
        (guild_id, raid_id, character_key, joined_at, left_at)
      values (v_device.guild_id, v_raid_id, v_member->>'character_key',
              (v_visit->>'joined_at')::timestamptz, (v_visit->>'left_at')::timestamptz)
      on conflict on constraint apoc_visit_source_interval
      do update set left_at = excluded.left_at;
    end loop;
  end loop;

  insert into public.apoc_upload_receipts
    (guild_id, device_id, request_id, source_key, source_revision, payload_hash, captured_at, status)
  values (v_device.guild_id, v_device.id, p_request_id, p_source_key,
          p_source_revision, p_payload_hash, p_captured_at, 'accepted');
  insert into public.apoc_audit_events
    (guild_id, entity_type, entity_id, action, request_id)
  values (v_device.guild_id, 'upload', v_raid_id::text, 'accepted', p_request_id);

  upload_status := 'accepted'; guild_id := v_device.guild_id; raid_id := v_raid_id;
  return next;
end;
$$;

revoke all on function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  to service_role;

-- Exercise the write path with synthetic records. The nested exception block
-- rolls back all test rows, including receipts and audit events. Any failed
-- assertion aborts the migration.
do $synthetic$
declare
  v_user uuid;
  v_guild uuid;
  v_other_guild uuid;
  v_device uuid;
  v_raid uuid;
  v_digest text := md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text);
  v_request uuid := gen_random_uuid();
  v_status text;
  v_count integer;
  v_winner text;
  v_raid_data jsonb := '{"name":"Synthetic raid","run_id":"synthetic-run","created_at":"2026-09-17T14:00:00Z","closed_at":null}';
  v_drops jsonb := '[{"id":"synthetic-drop","item_id":123,"item_name":"Synthetic item","boss":"Synthetic boss","dropped_at":"2026-09-17T14:01:00Z","winner":"Source","award_type":"MS","awarded_at":"2026-09-17T14:02:00Z","award_note":""}]';
  v_members jsonb := '[{"character_key":"synthetic-player","name":"Synthetic player","class":"MAGE","raid_group":1,"present":true,"visits":[{"joined_at":"2026-09-17T14:00:00Z","left_at":null}]}]';
begin
  select u.id into v_user from auth.users as u limit 1;
  if v_user is null then return; end if;
  begin
    insert into public.apoc_guilds(name, realm, faction)
      values ('Synthetic upload test', 'Test realm', 'Horde') returning id into v_guild;
    insert into public.apoc_guilds(name, realm, faction)
      values ('Other synthetic guild', 'Test realm', 'Horde') returning id into v_other_guild;
    insert into public.apoc_devices(guild_id, label, token_digest, created_by)
      values (v_guild, 'Synthetic device', v_digest, v_user) returning id into v_device;

    select t.upload_status, t.raid_id into v_status, v_raid
      from public.ingest_apoc_raid(v_digest, v_request, 'synthetic-source', 1,
        repeat('a',64), '2026-09-17T14:03:00Z', v_raid_data, v_drops, v_members) as t;
    if v_status <> 'accepted' or v_raid is null then raise exception 'synthetic first upload failed'; end if;
    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, v_request, 'synthetic-source', 1,
        repeat('a',64), '2026-09-17T14:03:00Z', v_raid_data, v_drops, v_members) as t;
    if v_status <> 'duplicate' then raise exception 'synthetic replay test failed'; end if;
    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, gen_random_uuid(), 'synthetic-source', 1,
        repeat('a',64), '2026-09-17T14:03:00Z', v_raid_data, v_drops, v_members) as t;
    if v_status <> 'stale' then raise exception 'synthetic stale revision test failed'; end if;

    update public.apoc_drops as d set winner = 'Officer', award_type = 'OS',
      award_note = 'Synthetic correction' where d.guild_id = v_guild and d.raid_id = v_raid;
    insert into public.apoc_drop_corrections
      (guild_id, raid_id, drop_id, winner, award_type, award_note, reason, corrected_by)
      values (v_guild, v_raid, 'synthetic-drop', 'Officer', 'OS', 'Synthetic correction',
              'Synthetic test', v_user);
    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, gen_random_uuid(), 'synthetic-source', 2,
        repeat('b',64), '2026-09-17T14:04:00Z', v_raid_data, v_drops, v_members) as t;
    select d.winner into v_winner from public.apoc_drops as d
      where d.guild_id = v_guild and d.raid_id = v_raid and d.id = 'synthetic-drop';
    if v_status <> 'accepted' or v_winner <> 'Officer' then
      raise exception 'synthetic correction preservation test failed';
    end if;
    select count(*) into v_count from public.apoc_raids as r where r.guild_id = v_other_guild;
    if v_count <> 0 then raise exception 'synthetic guild isolation test failed'; end if;

    update public.apoc_devices as d set revoked_at = now()
      where d.guild_id = v_guild and d.id = v_device;
    select count(*) into v_count
      from public.ingest_apoc_raid(v_digest, gen_random_uuid(), 'synthetic-source', 3,
        repeat('c',64), '2026-09-17T14:05:00Z', v_raid_data, v_drops, v_members);
    if v_count <> 0 then raise exception 'synthetic revocation test failed'; end if;
    raise exception 'rollback synthetic upload test';
  exception when raise_exception then
    if sqlerrm <> 'rollback synthetic upload test' then raise; end if;
  end;
end;
$synthetic$;
