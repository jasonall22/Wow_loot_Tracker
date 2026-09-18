-- Apply after schema.draft.sql and admin-edits.sql in the dedicated project.
-- The browser never receives direct membership writes or an Auth admin key.
begin;

create or replace function public.admin_apoc_members(
  p_actor uuid, p_guild_id uuid, p_action text,
  p_target uuid default null, p_role text default null,
  p_status text default null, p_can_upload boolean default null,
  p_can_edit boolean default null
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_target public.apoc_memberships%rowtype;
begin
  -- Serializes role changes for this guild, including two simultaneous attempts
  -- to remove different administrators.
  perform 1 from public.apoc_guilds where id = p_guild_id for update;
  if not found then return jsonb_build_object('status', 'forbidden'); end if;
  perform 1 from public.apoc_memberships m
    where m.guild_id = p_guild_id and m.user_id = p_actor
      and m.role = 'admin' and m.status = 'active' for share;
  if not found then return jsonb_build_object('status', 'forbidden'); end if;

  if p_action = 'list' then
    return jsonb_build_object('status', 'ok', 'members',
      coalesce((select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'role', m.role,
        'status', m.status, 'can_upload', m.can_upload,
        'can_edit', m.can_edit) order by m.user_id)
        from public.apoc_memberships m
        where m.guild_id = p_guild_id), '[]'::jsonb));
  end if;

  if p_action is distinct from 'update' or p_target is null
     or p_role is null or p_role not in ('admin', 'officer', 'member')
     or p_status is null or p_status not in ('active', 'suspended', 'revoked')
     or p_can_upload is null or p_can_edit is null
     or (p_can_edit and p_role = 'member') then
    return jsonb_build_object('status', 'invalid');
  end if;
  select * into v_target from public.apoc_memberships m
    where m.guild_id = p_guild_id and m.user_id = p_target for update;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if v_target.role = 'admin' and v_target.status = 'active'
     and (p_role <> 'admin' or p_status <> 'active')
     and (select count(*) from public.apoc_memberships m
       where m.guild_id = p_guild_id and m.role = 'admin' and m.status = 'active') <= 1 then
    return jsonb_build_object('status', 'last_admin');
  end if;
  update public.apoc_memberships m
    set role = p_role, status = p_status,
        can_upload = p_can_upload, can_edit = p_can_edit
    where m.guild_id = p_guild_id and m.user_id = p_target;
  insert into public.apoc_audit_events
    (guild_id, actor_user_id, entity_type, entity_id, action, reason)
  values (p_guild_id, p_actor, 'membership', p_target::text, 'updated',
    jsonb_build_object('previous', jsonb_build_object('role', v_target.role,
      'status', v_target.status, 'can_upload', v_target.can_upload,
      'can_edit', v_target.can_edit), 'new', jsonb_build_object('role', p_role,
      'status', p_status, 'can_upload', p_can_upload,
      'can_edit', p_can_edit))::text);
  return jsonb_build_object('status', 'ok');
end;
$$;

revoke all on function public.admin_apoc_members(uuid,uuid,text,uuid,text,text,boolean,boolean)
  from public, anon, authenticated;
grant execute on function public.admin_apoc_members(uuid,uuid,text,uuid,text,text,boolean,boolean)
  to service_role;

commit;
