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
  v_result record;
  v_same_revision boolean := false;
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
  if found and (v_receipt.source_key <> p_source_key
       or v_receipt.source_revision <> p_source_revision
       or v_receipt.payload_hash <> p_payload_hash) then
    raise exception 'request id reused with different upload' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.apoc_raids as r
      where r.guild_id = v_device.guild_id and r.source_key = p_source_key
  ) and exists (
    select 1 from public.apoc_upload_receipts as r
      where r.guild_id = v_device.guild_id and r.source_key = p_source_key
  ) then
    insert into public.apoc_raid_tombstones(guild_id, source_key, raid_id, deleted_at)
    values (v_device.guild_id, p_source_key, gen_random_uuid(), now())
    on conflict on constraint apoc_raid_tombstones_pkey do nothing;
  end if;

  if exists (
    select 1 from public.apoc_raid_tombstones as t
      where t.guild_id = v_device.guild_id and t.source_key = p_source_key
  ) then
    insert into public.apoc_upload_receipts
      (guild_id, device_id, request_id, source_key, source_revision,
       payload_hash, captured_at, status)
    values (v_device.guild_id, v_device.id, p_request_id, p_source_key,
      p_source_revision, p_payload_hash, p_captured_at, 'rejected')
    on conflict do nothing;
    upload_status := 'duplicate'; guild_id := v_device.guild_id; raid_id := null;
    return next; return;
  end if;

  select * into v_result
    from public.ingest_apoc_raid_core(
      p_token_digest, p_request_id, p_source_key, p_source_revision,
      p_payload_hash, p_captured_at, p_raid, p_drops, p_members
    );
  if not found then return; end if;

  select exists (
    select 1 from public.apoc_raids as r
     where r.guild_id = v_result.guild_id and r.id = v_result.raid_id
       and r.revision = p_source_revision
  ) into v_same_revision;

  if v_same_revision then
    update public.apoc_drops as d
       set priority = coalesce(submitted.value->>'priority', ''),
           priority_note = coalesce(submitted.value->>'priority_note', ''),
           roll_started_at = (submitted.value->'roll_data'->>'startedAt')::timestamptz,
           roll_ends_at = (submitted.value->'roll_data'->>'endsAt')::timestamptz,
           roll_closed = (submitted.value->'roll_data'->>'closed')::boolean,
           roll_copy_count = (submitted.value->'roll_data'->>'copyCount')::smallint,
           roll_entries = case when submitted.value->'roll_data' is null then '{}'::text[] else
             array(select entry.value::text from jsonb_array_elements(submitted.value->'roll_data'->'entries') as entry(value)) end
      from jsonb_array_elements(p_drops) as submitted(value)
     where d.guild_id = v_result.guild_id and d.raid_id = v_result.raid_id
       and d.id = submitted.value->>'id';
    if v_result.upload_status = 'stale' then v_result.upload_status := 'duplicate'; end if;
  end if;

  upload_status := v_result.upload_status;
  guild_id := v_result.guild_id;
  raid_id := v_result.raid_id;
  return next;
end;
$$;

revoke all on function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  to service_role;
