-- Apply to the dedicated APOC Supabase project before publishing the website import UI.
-- The service-role-only function checks a fresh guild permission, then reuses the
-- same transactional ingest path as the bridge. No browser receives a device token.
create or replace function public.import_apoc_raid(
  p_actor uuid, p_guild_id uuid, p_export_guild text,
  p_request_id uuid, p_source_key text, p_source_revision bigint,
  p_payload_hash text, p_captured_at timestamptz,
  p_raid jsonb, p_drops jsonb, p_members jsonb
)
returns table(upload_status text, guild_id uuid, raid_id uuid)
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_digest text;
begin
  if p_actor is null or p_guild_id is null or p_export_guild is null or
     not exists (
       select 1 from public.apoc_memberships as m
        where m.guild_id = p_guild_id and m.user_id = p_actor and m.status = 'active'
          and (m.role = 'admin' or m.can_upload = true)
     ) or not exists (
       select 1 from public.apoc_guilds as g
        where g.id = p_guild_id and lower(g.name) = lower(p_export_guild)
     ) then
    upload_status := 'forbidden'; guild_id := p_guild_id; raid_id := null;
    return next; return;
  end if;

  -- Deterministic, non-redeemable pseudo-device for manual file receipts.
  -- The function is service_role-only and the digest is never returned.
  v_digest := md5('apoc-file-import:' || p_guild_id::text || ':' || p_actor::text) ||
              md5('apoc-file-import:v2:' || p_guild_id::text || ':' || p_actor::text);
  insert into public.apoc_devices(guild_id, label, token_digest, created_by)
  values (p_guild_id, 'Website file import', v_digest, p_actor)
  on conflict (guild_id, token_digest) do nothing;
  if exists (select 1 from public.apoc_devices as d where d.guild_id = p_guild_id
    and d.token_digest = v_digest and d.revoked_at is not null) then
    upload_status := 'forbidden'; guild_id := p_guild_id; raid_id := null;
    return next; return;
  end if;

  return query select r.upload_status, r.guild_id, r.raid_id
    from public.ingest_apoc_raid(v_digest, p_request_id, p_source_key,
      p_source_revision, p_payload_hash, p_captured_at, p_raid, p_drops, p_members) as r;
end;
$$;

revoke all on function public.import_apoc_raid(uuid,uuid,text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.import_apoc_raid(uuid,uuid,text,uuid,text,bigint,text,timestamptz,jsonb,jsonb,jsonb)
  to service_role;
