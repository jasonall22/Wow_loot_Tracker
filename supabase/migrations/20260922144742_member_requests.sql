-- Apply after schema.draft.sql, ingestion.draft.sql, and member-admin.sql.
-- Self-registration creates no membership. Officers or admins must approve a
-- private request before the account receives the fixed Member role.
begin;

create table public.apoc_join_requests (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null check (char_length(email) between 3 and 254 and email = lower(btrim(email))),
  character_name text not null check (char_length(character_name) between 2 and 24),
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  unique (guild_id, user_id),
  check ((status = 'pending' and reviewed_at is null and reviewed_by is null) or
         (status <> 'pending' and reviewed_at is not null and reviewed_by is not null))
);
create index apoc_join_requests_pending on public.apoc_join_requests(guild_id, created_at, id)
  where status = 'pending';
alter table public.apoc_join_requests enable row level security;
revoke all on public.apoc_join_requests from public, anon, authenticated;
grant select, insert, update on public.apoc_join_requests to service_role;

create function public.create_apoc_join_request(
  p_user_id uuid, p_guild_id uuid, p_email text, p_character_name text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_email text := lower(btrim(p_email));
  v_character text := btrim(p_character_name);
  v_id uuid;
begin
  if p_user_id is null or p_guild_id is null or v_email is null or v_character is null
     or char_length(v_email) not between 3 and 254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or char_length(v_character) not between 2 and 24
     or v_character !~ '^[[:alpha:]][[:alpha:]''-]{1,23}$' then
    return jsonb_build_object('status', 'invalid');
  end if;
  perform 1 from public.apoc_guilds where id = p_guild_id;
  if not found then return jsonb_build_object('status', 'invalid'); end if;
  perform 1 from public.apoc_memberships where guild_id = p_guild_id and user_id = p_user_id;
  if found then return jsonb_build_object('status', 'already_member'); end if;

  insert into public.apoc_join_requests (guild_id, user_id, email, character_name)
  values (p_guild_id, p_user_id, v_email, v_character)
  on conflict (guild_id, user_id) do update set
    email = excluded.email, character_name = excluded.character_name,
    status = 'pending', created_at = now(), reviewed_at = null, reviewed_by = null
  returning id into v_id;
  insert into public.apoc_audit_events
    (guild_id, actor_user_id, entity_type, entity_id, action)
  values (p_guild_id, p_user_id, 'membership', v_id::text, 'account_requested');
  return jsonb_build_object('status', 'ok', 'request_id', v_id);
end;
$$;

create function public.review_apoc_join_requests(
  p_actor uuid, p_guild_id uuid, p_action text, p_request_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_request public.apoc_join_requests%rowtype;
begin
  perform 1 from public.apoc_memberships m
    where m.guild_id = p_guild_id and m.user_id = p_actor
      and m.role in ('admin', 'officer') and m.status = 'active' for share;
  if not found then return jsonb_build_object('status', 'forbidden'); end if;

  if p_action = 'list' then
    return jsonb_build_object('status', 'ok', 'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'user_id', r.user_id, 'email', r.email,
        'character_name', r.character_name, 'created_at', r.created_at
      ) order by r.created_at, r.id)
      from (select * from public.apoc_join_requests
        where guild_id = p_guild_id and status = 'pending'
        order by created_at, id limit 100) r
    ), '[]'::jsonb));
  end if;
  if p_action not in ('approve', 'deny') or p_request_id is null then
    return jsonb_build_object('status', 'invalid');
  end if;

  perform 1 from public.apoc_guilds where id = p_guild_id for update;
  select * into v_request from public.apoc_join_requests
    where id = p_request_id and guild_id = p_guild_id for update;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if v_request.status <> 'pending' then return jsonb_build_object('status', 'already_reviewed'); end if;

  if p_action = 'approve' then
    insert into public.apoc_memberships
      (guild_id, user_id, role, status, can_upload, can_edit)
    values (p_guild_id, v_request.user_id, 'member', 'active', false, false)
    on conflict (guild_id, user_id) do nothing;
  end if;
  update public.apoc_join_requests set status = case when p_action = 'approve' then 'approved' else 'denied' end,
    reviewed_at = now(), reviewed_by = p_actor where id = v_request.id;
  insert into public.apoc_audit_events
    (guild_id, actor_user_id, entity_type, entity_id, action, reason)
  values (p_guild_id, p_actor, 'membership', v_request.id::text,
    case when p_action = 'approve' then 'account_approved' else 'account_denied' end,
    jsonb_build_object('user_id', v_request.user_id, 'character_name', v_request.character_name)::text);
  return jsonb_build_object('status', 'ok');
end;
$$;

revoke all on function public.create_apoc_join_request(uuid,uuid,text,text),
  public.review_apoc_join_requests(uuid,uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.create_apoc_join_request(uuid,uuid,text,text),
  public.review_apoc_join_requests(uuid,uuid,text,uuid) to service_role;

commit;
