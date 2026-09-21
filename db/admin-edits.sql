-- Admin raid management. Kept separate from the original read-only foundation.
-- display_name survives bridge uploads; deleted_at hides a raid without deleting
-- its data. A separately confirmed purge removes an archived raid and leaves a
-- source-key tombstone so the live bridge cannot recreate it.
begin;

alter table public.apoc_raids
  add column if not exists display_name text check (char_length(display_name) between 1 and 300),
  add column if not exists deleted_at timestamptz;

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

alter table public.apoc_audit_events
  drop constraint apoc_audit_events_entity_type_check;
alter table public.apoc_audit_events
  add constraint apoc_audit_events_entity_type_check
  check (entity_type in ('device', 'pairing', 'upload', 'drop_correction', 'membership', 'raid'));

create or replace function public.admin_apoc_edit(
  p_actor uuid, p_guild_id uuid, p_raid_id uuid, p_action text, p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_raid public.apoc_raids%rowtype;
  v_drop public.apoc_drops%rowtype;
  v_name text;
  v_drop_id text;
  v_winner text;
  v_type text;
  v_note text;
  v_reason text;
begin
  -- The server checks Auth and membership too. Recheck under a row lock so a
  -- revoked admin cannot race a previously authorized request.
  perform 1 from public.apoc_memberships as m
    where m.guild_id = p_guild_id and m.user_id = p_actor
      and m.status = 'active' and m.role = 'admin' for share;
  if not found then return jsonb_build_object('status', 'forbidden'); end if;

  select * into v_raid from public.apoc_raids as r
    where r.guild_id = p_guild_id and r.id = p_raid_id for update;
  if not found then
    -- A retry after a lost response is safe: the tombstone proves this exact
    -- raid was already permanently deleted for the same guild.
    if p_action = 'purge_raid' and jsonb_typeof(p_payload) = 'object' and exists (
      select 1 from public.apoc_raid_tombstones as t
        where t.guild_id = p_guild_id and t.raid_id = p_raid_id
    ) then
      return jsonb_build_object('status', 'ok');
    end if;
    return jsonb_build_object('status', 'not_found');
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    return jsonb_build_object('status', 'invalid');
  end if;

  if p_action = 'purge_raid' then
    if v_raid.deleted_at is null then
      return jsonb_build_object('status', 'invalid');
    end if;
    v_name := coalesce(v_raid.display_name, v_raid.name);
    insert into public.apoc_raid_tombstones
      (guild_id, source_key, raid_id, deleted_at)
    values (p_guild_id, v_raid.source_key, p_raid_id, now())
    on conflict (guild_id, source_key) do update set
      raid_id = excluded.raid_id, deleted_at = excluded.deleted_at;
    insert into public.apoc_audit_events
      (guild_id, actor_user_id, entity_type, entity_id, action, reason)
    values (p_guild_id, p_actor, 'raid', p_raid_id::text, 'purged', v_name);
    delete from public.apoc_raids as r
      where r.guild_id = p_guild_id and r.id = p_raid_id and r.deleted_at is not null;
    return jsonb_build_object('status', 'ok', 'name', v_name);
  end if;

  if p_action = 'restore_raid' then
    if v_raid.deleted_at is not null then
      update public.apoc_raids as r set deleted_at = null, updated_at = now()
        where r.guild_id = p_guild_id and r.id = p_raid_id;
      insert into public.apoc_audit_events
        (guild_id, actor_user_id, entity_type, entity_id, action, reason)
      values (p_guild_id, p_actor, 'raid', p_raid_id::text, 'restored',
        coalesce(v_raid.display_name, v_raid.name));
    end if;
    return jsonb_build_object('status', 'ok', 'name', coalesce(v_raid.display_name, v_raid.name));
  end if;

  if v_raid.deleted_at is not null then
    return jsonb_build_object('status', 'not_found');
  end if;

  if p_action = 'rename_raid' then
    if jsonb_typeof(p_payload->'name') is distinct from 'string' then
      return jsonb_build_object('status', 'invalid');
    end if;
    v_name := btrim(p_payload->>'name');
    if char_length(v_name) not between 1 and 300 then
      return jsonb_build_object('status', 'invalid');
    end if;
    update public.apoc_raids as r set display_name = v_name, updated_at = now()
      where r.guild_id = p_guild_id and r.id = p_raid_id;
    insert into public.apoc_audit_events
      (guild_id, actor_user_id, entity_type, entity_id, action, reason)
    values (p_guild_id, p_actor, 'raid', p_raid_id::text, 'renamed',
      jsonb_build_object('previous', coalesce(v_raid.display_name, v_raid.name), 'new', v_name)::text);
    return jsonb_build_object('status', 'ok', 'name', v_name);

  elsif p_action = 'delete_raid' then
    update public.apoc_raids as r set deleted_at = now(), updated_at = now()
      where r.guild_id = p_guild_id and r.id = p_raid_id;
    insert into public.apoc_audit_events
      (guild_id, actor_user_id, entity_type, entity_id, action, reason)
    values (p_guild_id, p_actor, 'raid', p_raid_id::text, 'archived',
      coalesce(v_raid.display_name, v_raid.name));
    return jsonb_build_object('status', 'ok');

  elsif p_action = 'edit_drop' then
    if not (p_payload ?& array['dropId', 'winner', 'awardType', 'awardNote'])
       or jsonb_typeof(p_payload->'dropId') is distinct from 'string'
       or jsonb_typeof(p_payload->'awardNote') is distinct from 'string'
       or (jsonb_typeof(p_payload->'winner') not in ('string', 'null'))
       or (jsonb_typeof(p_payload->'awardType') not in ('string', 'null')) then
      return jsonb_build_object('status', 'invalid');
    end if;
    v_drop_id := p_payload->>'dropId';
    v_winner := nullif(btrim(p_payload->>'winner'), '');
    v_type := nullif(p_payload->>'awardType', '');
    v_note := p_payload->>'awardNote';
    if char_length(v_drop_id) not between 1 and 200
       or (v_winner is not null and char_length(v_winner) > 200)
       or char_length(v_note) > 2000
       or (v_type is not null and v_type not in ('MS', 'OS', 'DE', 'GB', 'UNKNOWN'))
       or (v_type is null and v_winner is not null)
       or (v_type in ('MS', 'OS') and v_winner is null) then
      return jsonb_build_object('status', 'invalid');
    end if;
    select * into v_drop from public.apoc_drops as d
      where d.guild_id = p_guild_id and d.raid_id = p_raid_id
        and d.id = v_drop_id and d.source_present for update;
    if not found then return jsonb_build_object('status', 'not_found'); end if;
    v_reason := jsonb_build_object('previous_winner', v_drop.winner,
      'previous_award_type', v_drop.award_type)::text;
    update public.apoc_drops as d set winner = v_winner, award_type = v_type,
      awarded_at = case when v_type is null then null else coalesce(v_drop.awarded_at, now()) end,
      award_note = v_note
      where d.guild_id = p_guild_id and d.raid_id = p_raid_id and d.id = v_drop_id;
    insert into public.apoc_drop_corrections
      (guild_id, raid_id, drop_id, winner, award_type, award_note, reason, corrected_by)
    values (p_guild_id, p_raid_id, v_drop_id, v_winner, v_type, v_note, v_reason, p_actor);
    insert into public.apoc_audit_events
      (guild_id, actor_user_id, entity_type, entity_id, action, reason)
    values (p_guild_id, p_actor, 'drop_correction', v_drop_id, 'updated', v_reason);
    return jsonb_build_object('status', 'ok');
  end if;

  return jsonb_build_object('status', 'invalid');
end;
$$;

revoke all on function public.admin_apoc_edit(uuid,uuid,uuid,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_apoc_edit(uuid,uuid,uuid,text,jsonb)
  to service_role;

commit;
