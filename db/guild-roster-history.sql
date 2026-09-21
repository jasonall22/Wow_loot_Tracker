-- Complete in-game guild roster snapshots are authoritative for current/former
-- membership. Raid attendance alone never creates a guild character.
begin;

create table public.apoc_guild_characters (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  character_key text not null check (char_length(character_key) between 1 and 200),
  name text not null check (char_length(name) between 1 and 200),
  class text not null default '' check (char_length(class) <= 30),
  rank_name text not null default '' check (char_length(rank_name) <= 100),
  rank_index smallint not null check (rank_index between 0 and 99),
  is_current boolean not null default true,
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  left_at timestamptz,
  primary key (guild_id, character_key),
  check (last_seen_at >= first_seen_at),
  check ((is_current and left_at is null) or (not is_current and left_at is not null))
);

create index apoc_guild_characters_status_name
  on public.apoc_guild_characters(guild_id, is_current, name, character_key);

create table public.apoc_guild_roster_state (
  guild_id uuid primary key references public.apoc_guilds(id) on delete cascade,
  captured_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.apoc_guild_characters enable row level security;
alter table public.apoc_guild_roster_state enable row level security;

create policy apoc_guild_character_read on public.apoc_guild_characters
for select to authenticated using (
  exists (
    select 1 from public.apoc_memberships as membership
    where membership.guild_id = apoc_guild_characters.guild_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  )
);

revoke all on public.apoc_guild_characters, public.apoc_guild_roster_state
  from public, anon, authenticated;
grant select on public.apoc_guild_characters to authenticated;
grant all on public.apoc_guild_characters, public.apoc_guild_roster_state to service_role;

create or replace function public.sync_apoc_guild_roster(
  p_guild_id uuid,
  p_captured_at timestamptz,
  p_members jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_previous timestamptz;
  v_count integer;
  v_current integer;
  v_former integer;
begin
  if p_guild_id is null or p_captured_at is null or p_captured_at > now() + interval '1 day' or
     jsonb_typeof(p_members) <> 'array' then
    raise exception 'invalid guild roster snapshot' using errcode = '22023';
  end if;

  v_count := jsonb_array_length(p_members);
  if v_count < 1 or v_count > 1000 then
    raise exception 'invalid guild roster size' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_members) as item(value)
    where jsonb_typeof(value) <> 'object'
       or (select count(*) from jsonb_object_keys(value)) <> 5
       or not (value ?& array['character_key', 'name', 'class', 'rank_name', 'rank_index'])
       or jsonb_typeof(value->'character_key') <> 'string'
       or jsonb_typeof(value->'name') <> 'string'
       or jsonb_typeof(value->'class') <> 'string'
       or jsonb_typeof(value->'rank_name') <> 'string'
       or jsonb_typeof(value->'rank_index') <> 'number'
       or char_length(value->>'character_key') not between 1 and 200
       or char_length(value->>'name') not between 1 and 200
       or btrim(value->>'name') <> value->>'name'
       or value->>'character_key' <> lower(value->>'name')
       or char_length(value->>'class') > 30
       or char_length(value->>'rank_name') > 100
       or not (case when (value->>'rank_index') ~ '^[0-9]{1,2}$'
                    then (value->>'rank_index')::integer between 0 and 99 else false end)
  ) then
    raise exception 'invalid guild roster member' using errcode = '22023';
  end if;

  if (select count(distinct value->>'character_key') from jsonb_array_elements(p_members) as item(value)) <> v_count then
    raise exception 'duplicate guild roster member' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('apoc-guild-roster:' || p_guild_id::text, 0));
  select state.captured_at into v_previous
  from public.apoc_guild_roster_state as state
  where state.guild_id = p_guild_id;

  if found and v_previous >= p_captured_at then
    return jsonb_build_object('status', 'stale', 'capturedAt', v_previous);
  end if;

  update public.apoc_guild_characters as character
  set is_current = false, left_at = p_captured_at
  where character.guild_id = p_guild_id
    and character.is_current
    and not exists (
      select 1 from jsonb_array_elements(p_members) as item(value)
      where value->>'character_key' = character.character_key
    );

  insert into public.apoc_guild_characters (
    guild_id, character_key, name, class, rank_name, rank_index,
    is_current, first_seen_at, last_seen_at, left_at
  )
  select p_guild_id, value->>'character_key', value->>'name', value->>'class',
    value->>'rank_name', (value->>'rank_index')::smallint,
    true, p_captured_at, p_captured_at, null
  from jsonb_array_elements(p_members) as item(value)
  on conflict (guild_id, character_key) do update
  set name = excluded.name,
      class = excluded.class,
      rank_name = excluded.rank_name,
      rank_index = excluded.rank_index,
      is_current = true,
      last_seen_at = excluded.last_seen_at,
      left_at = null;

  insert into public.apoc_guild_roster_state(guild_id, captured_at, updated_at)
  values (p_guild_id, p_captured_at, now())
  on conflict (guild_id) do update
  set captured_at = excluded.captured_at, updated_at = excluded.updated_at;

  select count(*) filter (where is_current), count(*) filter (where not is_current)
    into v_current, v_former
  from public.apoc_guild_characters
  where guild_id = p_guild_id;

  return jsonb_build_object('status', 'ok', 'current', v_current, 'former', v_former);
end;
$$;

revoke all on function public.sync_apoc_guild_roster(uuid,timestamptz,jsonb)
  from public, anon, authenticated;
grant execute on function public.sync_apoc_guild_roster(uuid,timestamptz,jsonb)
  to service_role;

notify pgrst, 'reload schema';
commit;
