-- Qualify the challenge row during redemption. The RETURNS TABLE output
-- parameter guild_id otherwise conflicts with the table column in UPDATE.
create or replace function public.consume_apoc_pairing_challenge(
  p_challenge_digest text,
  p_label text,
  p_token_digest text
)
returns table (device_id uuid, guild_id uuid)
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  challenge public.apoc_pairing_challenges%rowtype;
  new_device uuid;
begin
  if p_challenge_digest !~ '^[a-f0-9]{64}$' or p_token_digest !~ '^[a-f0-9]{64}$'
     or p_label is null or char_length(p_label) not between 1 and 100 then
    raise exception 'invalid pairing input' using errcode = '22023';
  end if;

  select * into challenge
    from public.apoc_pairing_challenges
   where challenge_digest = p_challenge_digest
     and consumed_at is null
     and expires_at > now()
   for update;
  if not found then return; end if;

  insert into public.apoc_devices(guild_id, label, token_digest, created_by)
  values (challenge.guild_id, p_label, p_token_digest, challenge.created_by)
  returning id into new_device;

  update public.apoc_pairing_challenges as c
     set consumed_at = now(), device_id = new_device
   where c.guild_id = challenge.guild_id and c.id = challenge.id;

  insert into public.apoc_audit_events(guild_id, actor_user_id, entity_type, entity_id, action, reason)
  values (challenge.guild_id, challenge.created_by, 'pairing', challenge.id::text, 'consumed', 'Companion device paired');

  device_id := new_device;
  guild_id := challenge.guild_id;
  return next;
end;
$$;

revoke all on function public.consume_apoc_pairing_challenge(text, text, text) from public, anon, authenticated;
grant execute on function public.consume_apoc_pairing_challenge(text, text, text) to service_role;
