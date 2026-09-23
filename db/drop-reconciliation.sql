-- Preserve removed loot for correction/audit history, but hide it from the
-- current raid view. The source snapshot controls whether a drop is present.
alter table public.apoc_drops
  add column if not exists source_present boolean not null default true,
  add column if not exists priority text not null default '' check (char_length(priority) <= 500),
  add column if not exists priority_note text not null default '' check (char_length(priority_note) <= 1000),
  add column if not exists roll_started_at timestamptz,
  add column if not exists roll_ends_at timestamptz,
  add column if not exists roll_closed boolean,
  add column if not exists roll_copy_count smallint check (roll_copy_count is null or roll_copy_count between 1 and 40),
  add column if not exists roll_entries text[] not null default '{}';

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
    select r.id, r.revision into v_raid_id, v_revision from public.apoc_raids as r
      where r.guild_id = v_device.guild_id and r.source_key = p_source_key for update;
    -- Repair rows left visible by the former append-only uploader. Never let
    -- a replay of an older revision change a newer raid's current view.
    if v_revision = p_source_revision then
      update public.apoc_drops as d set source_present = false
       where d.guild_id = v_device.guild_id and d.raid_id = v_raid_id
         and d.source_present and not exists (
           select 1 from jsonb_array_elements(p_drops) as submitted(value)
            where submitted.value->>'id' = d.id);
    end if;
    upload_status := 'duplicate'; guild_id := v_device.guild_id; raid_id := v_raid_id;
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
    select * into v_receipt from public.apoc_upload_receipts as r
      where r.guild_id = v_device.guild_id and r.request_id = p_request_id;
    if found then
      if v_receipt.source_key <> p_source_key or v_receipt.source_revision <> p_source_revision
         or v_receipt.payload_hash <> p_payload_hash then
        raise exception 'request id reused with different upload' using errcode = '22023';
      end if;
      if v_revision = p_source_revision then
        update public.apoc_drops as d set source_present = false
         where d.guild_id = v_device.guild_id and d.raid_id = v_raid_id
           and d.source_present and not exists (
             select 1 from jsonb_array_elements(p_drops) as submitted(value)
              where submitted.value->>'id' = d.id);
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
       winner, award_type, awarded_at, award_note, priority, priority_note,
       roll_started_at, roll_ends_at, roll_closed, roll_copy_count, roll_entries)
    values (v_device.guild_id, v_raid_id, v_drop->>'id', (v_drop->>'item_id')::integer,
            v_drop->>'item_name', v_drop->>'boss', (v_drop->>'dropped_at')::timestamptz,
            v_drop->>'winner', v_drop->>'award_type', (v_drop->>'awarded_at')::timestamptz,
            v_drop->>'award_note', coalesce(v_drop->>'priority', ''), coalesce(v_drop->>'priority_note', ''),
            (v_drop->'roll_data'->>'startedAt')::timestamptz, (v_drop->'roll_data'->>'endsAt')::timestamptz,
            (v_drop->'roll_data'->>'closed')::boolean, (v_drop->'roll_data'->>'copyCount')::smallint,
            case when v_drop->'roll_data' is null then '{}'::text[] else
              array(select entry.value::text from jsonb_array_elements(v_drop->'roll_data'->'entries') as entry(value)) end)
    on conflict on constraint apoc_drops_pkey do update set
      item_id = excluded.item_id, item_name = excluded.item_name,
      boss = excluded.boss, dropped_at = excluded.dropped_at, source_present = true,
      priority = excluded.priority, priority_note = excluded.priority_note,
      roll_started_at = excluded.roll_started_at, roll_ends_at = excluded.roll_ends_at,
      roll_closed = excluded.roll_closed, roll_copy_count = excluded.roll_copy_count, roll_entries = excluded.roll_entries,
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

  update public.apoc_drops as d set source_present = false
   where d.guild_id = v_device.guild_id and d.raid_id = v_raid_id
     and d.source_present and not exists (
       select 1 from jsonb_array_elements(p_drops) as submitted(value)
        where submitted.value->>'id' = d.id);

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

-- Prove add/remove/replay/reappearance and correction preservation. The
-- exception block discards every synthetic row before the migration commits.
do $synthetic$
declare
  v_user uuid;
  v_guild uuid;
  v_device uuid;
  v_digest text := md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text);
  v_request_1 uuid := gen_random_uuid();
  v_request_2 uuid := gen_random_uuid();
  v_raid_id uuid;
  v_status text;
  v_present boolean;
  v_winner text;
  v_count integer;
  v_raid jsonb := '{"name":"Synthetic raid","run_id":"synthetic-run","created_at":"2026-09-17T14:00:00Z","closed_at":null}';
  v_two jsonb := '[{"id":"kept","item_id":123,"item_name":"Kept item","boss":"Boss","dropped_at":"2026-09-17T14:01:00Z","winner":null,"award_type":null,"awarded_at":null,"award_note":""},{"id":"removed","item_id":124,"item_name":"Removed item","boss":"Boss","dropped_at":"2026-09-17T14:02:00Z","winner":"Source","award_type":"MS","awarded_at":"2026-09-17T14:03:00Z","award_note":""}]';
  v_one jsonb := '[{"id":"kept","item_id":123,"item_name":"Kept item","boss":"Boss","dropped_at":"2026-09-17T14:01:00Z","winner":null,"award_type":null,"awarded_at":null,"award_note":""}]';
begin
  select u.id into v_user from auth.users as u limit 1;
  if v_user is null then raise exception 'synthetic test needs one existing auth user'; end if;
  begin
    insert into public.apoc_guilds(name, realm, faction)
      values ('Synthetic drop reconciliation', 'Test realm', 'Horde') returning id into v_guild;
    insert into public.apoc_devices(guild_id, label, token_digest, created_by)
      values (v_guild, 'Synthetic device', v_digest, v_user) returning id into v_device;

    select t.upload_status, t.raid_id into v_status, v_raid_id
      from public.ingest_apoc_raid(v_digest, v_request_1, 'synthetic-source', 1,
        repeat('a',64), '2026-09-17T14:03:00Z', v_raid, v_two, '[]'::jsonb) as t;
    if v_status <> 'accepted' then raise exception 'initial synthetic upload failed'; end if;
    update public.apoc_drops as d set winner = 'Officer' where d.guild_id = v_guild and d.raid_id = v_raid_id and d.id = 'removed';
    insert into public.apoc_drop_corrections
      (guild_id, raid_id, drop_id, winner, reason, corrected_by)
      values (v_guild, v_raid_id, 'removed', 'Officer', 'Synthetic test', v_user);

    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, v_request_2, 'synthetic-source', 2,
        repeat('b',64), '2026-09-17T14:04:00Z', v_raid, v_one, '[]'::jsonb) as t;
    select d.source_present into v_present from public.apoc_drops as d
      where d.guild_id = v_guild and d.raid_id = v_raid_id and d.id = 'removed';
    select count(*) into v_count from public.apoc_drop_corrections as c
      where c.guild_id = v_guild and c.raid_id = v_raid_id and c.drop_id = 'removed';
    if v_status <> 'accepted' or v_present or v_count <> 1 then
      raise exception 'synthetic removal or correction preservation failed';
    end if;

    -- Emulate an old append-only upload, then retry that exact receipt.
    update public.apoc_drops as d set source_present = true
      where d.guild_id = v_guild and d.raid_id = v_raid_id and d.id = 'removed';
    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, v_request_2, 'synthetic-source', 2,
        repeat('b',64), '2026-09-17T14:04:00Z', v_raid, v_one, '[]'::jsonb) as t;
    select d.source_present into v_present from public.apoc_drops as d
      where d.guild_id = v_guild and d.raid_id = v_raid_id and d.id = 'removed';
    if v_status <> 'duplicate' or v_present then raise exception 'synthetic duplicate repair failed'; end if;

    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, v_request_1, 'synthetic-source', 1,
        repeat('a',64), '2026-09-17T14:03:00Z', v_raid, v_two, '[]'::jsonb) as t;
    select d.source_present into v_present from public.apoc_drops as d
      where d.guild_id = v_guild and d.raid_id = v_raid_id and d.id = 'removed';
    if v_status <> 'duplicate' or v_present then raise exception 'older replay changed current drops'; end if;

    select t.upload_status into v_status
      from public.ingest_apoc_raid(v_digest, gen_random_uuid(), 'synthetic-source', 3,
        repeat('c',64), '2026-09-17T14:05:00Z', v_raid, v_two, '[]'::jsonb) as t;
    select d.source_present, d.winner into v_present, v_winner from public.apoc_drops as d
      where d.guild_id = v_guild and d.raid_id = v_raid_id and d.id = 'removed';
    if v_status <> 'accepted' or not v_present or v_winner <> 'Officer' then
      raise exception 'synthetic reappearance or correction preservation failed';
    end if;
    raise exception 'rollback synthetic drop reconciliation';
  exception when raise_exception then
    if sqlerrm <> 'rollback synthetic drop reconciliation' then raise; end if;
  end;
end;
$synthetic$;
