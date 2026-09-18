-- Apply after schema.draft.sql, ingestion.draft.sql, and admin-edits.sql.
-- Invitations are private server state. No browser role can read or write them.
begin;

create table public.apoc_invitations (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  email text not null check (char_length(email) between 3 and 254 and email = lower(btrim(email))),
  invited_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  unique (guild_id, email),
  check (expires_at > created_at)
);
create index apoc_invitations_pending_email on public.apoc_invitations(email, expires_at)
  where accepted_at is null;
alter table public.apoc_invitations enable row level security;
revoke all on public.apoc_invitations from public, anon, authenticated;
grant select, insert, update on public.apoc_invitations to service_role;

create function public.admin_apoc_prepare_invite(p_actor uuid, p_guild_id uuid, p_email text)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_email text := lower(btrim(p_email));
  v_id uuid;
begin
  if v_email is null or char_length(v_email) not between 3 and 254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return jsonb_build_object('status', 'invalid');
  end if;
  perform 1 from public.apoc_guilds where id = p_guild_id for update;
  if not found then return jsonb_build_object('status', 'forbidden'); end if;
  perform 1 from public.apoc_memberships m
    where m.guild_id = p_guild_id and m.user_id = p_actor
      and m.role = 'admin' and m.status = 'active' for share;
  if not found then return jsonb_build_object('status', 'forbidden'); end if;

  insert into public.apoc_invitations (guild_id, email, invited_by)
  values (p_guild_id, v_email, p_actor)
  on conflict (guild_id, email) do update set invited_by = excluded.invited_by,
    created_at = now(), expires_at = now() + interval '7 days', accepted_at = null
  returning id into v_id;
  insert into public.apoc_audit_events
    (guild_id, actor_user_id, entity_type, entity_id, action)
  values (p_guild_id, p_actor, 'membership', v_id::text, 'invitation_prepared');
  return jsonb_build_object('status', 'ok');
end;
$$;

create function public.claim_apoc_invitations(p_user_id uuid, p_email text)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_invite public.apoc_invitations%rowtype;
  v_added integer;
  v_joined integer := 0;
begin
  if p_user_id is null or p_email is null or char_length(p_email) not between 3 and 254 then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- The server passes only an email returned by Supabase Auth /user for this JWT.
  for v_invite in
    select * from public.apoc_invitations i
    where i.email = lower(btrim(p_email)) and i.accepted_at is null
      and i.expires_at > now()
    order by i.guild_id for update
  loop
    insert into public.apoc_memberships
      (guild_id, user_id, role, status, can_upload, can_edit)
    values (v_invite.guild_id, p_user_id, 'member', 'active', false, false)
    on conflict (guild_id, user_id) do nothing;
    get diagnostics v_added = row_count;
    update public.apoc_invitations set accepted_at = now() where id = v_invite.id;
    if v_added = 1 then
      v_joined := v_joined + 1;
      insert into public.apoc_audit_events
        (guild_id, actor_user_id, entity_type, entity_id, action)
      values (v_invite.guild_id, p_user_id, 'membership', p_user_id::text, 'joined_by_invitation');
    end if;
  end loop;
  return jsonb_build_object('status', 'ok', 'joined', v_joined);
end;
$$;

revoke all on function public.admin_apoc_prepare_invite(uuid,uuid,text),
  public.claim_apoc_invitations(uuid,text) from public, anon, authenticated;
grant execute on function public.admin_apoc_prepare_invite(uuid,uuid,text),
  public.claim_apoc_invitations(uuid,text) to service_role;

commit;
