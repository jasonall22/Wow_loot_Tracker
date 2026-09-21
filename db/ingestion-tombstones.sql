-- Keep permanently deleted raid source keys from being recreated by a live
-- bridge upload. Run after the latest ingest_apoc_raid migration.
begin;

create table if not exists public.apoc_raid_tombstones (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  source_key text not null check (char_length(source_key) between 1 and 200),
  raid_id uuid not null,
  deleted_at timestamptz not null default now(),
  primary key (guild_id, source_key),
  unique (guild_id, raid_id)
);
alter table public.apoc_raid_tombstones enable row level security;
revoke all on public.apoc_raid_tombstones from public, anon, authenticated;
grant select, insert, update, delete on public.apoc_raid_tombstones to service_role;

-- Preserve the current ingestion implementation as the core exactly once.
-- The public RPC name becomes a small guard that rejects tombstoned sources.
do $rename$
begin
  if to_regprocedure('public.ingest_apoc_raid_core(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)') is null then
    alter function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
      rename to ingest_apoc_raid_core;
  end if;
end;
$rename$;

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

  -- Retain the request-id mismatch protection even for a deleted source.
  select * into v_receipt from public.apoc_upload_receipts as r
    where r.guild_id = v_device.guild_id and r.request_id = p_request_id;
  if found and (v_receipt.source_key <> p_source_key
       or v_receipt.source_revision <> p_source_revision
       or v_receipt.payload_hash <> p_payload_hash) then
    raise exception 'request id reused with different upload' using errcode = '22023';
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
    -- Duplicate is intentionally a successful bridge response. It tells old
    -- and new bridge clients to stop retrying without recreating the raid.
    upload_status := 'duplicate';
    guild_id := v_device.guild_id;
    raid_id := null;
    return next;
    return;
  end if;

  return query
    select core.upload_status, core.guild_id, core.raid_id
      from public.ingest_apoc_raid_core(
        p_token_digest, p_request_id, p_source_key, p_source_revision,
        p_payload_hash, p_captured_at, p_raid, p_drops, p_members
      ) as core;
end;
$$;

revoke all on function public.ingest_apoc_raid_core(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_apoc_raid_core(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  to service_role;
revoke all on function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_apoc_raid(text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  to service_role;

commit;
