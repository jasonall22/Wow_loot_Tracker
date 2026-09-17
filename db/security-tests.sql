-- NOT YET RUN. Execute after schema.draft.sql, only in a dedicated disposable
-- APOC test database, as postgres. This seeds SYNTHETIC users/raids temporarily.
-- Success rolls back everything. On an error, explicitly ROLLBACK before retrying.
-- Does not prove Auth, PostgREST, Realtime, or Vercel integration; test those too.
begin;

insert into auth.users(id) values
 ('10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-000000000002'),
 ('10000000-0000-4000-8000-000000000003'),
 ('10000000-0000-4000-8000-000000000004'),
 ('10000000-0000-4000-8000-000000000005'),
 ('10000000-0000-4000-8000-000000000006');

insert into public.apoc_guilds(id,name,realm,faction) values
 ('20000000-0000-4000-8000-000000000001','SYNTHETIC A','Test realm','Horde'),
 ('20000000-0000-4000-8000-000000000002','SYNTHETIC B','Test realm','Horde');
insert into public.apoc_memberships(guild_id,user_id,role,status,can_upload) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','admin','active',false),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','officer','active',false),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','member','active',false),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','member','active',true),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000005','admin','active',false),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000006','admin','revoked',true);
insert into public.apoc_raids(guild_id,id,source_key,name,run_id,created_at) values
 ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','test-a','TEST A','test-a','2026-09-01T00:00:00Z'),
 ('20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','test-b','TEST B','test-b','2026-09-01T00:00:00Z');
insert into public.apoc_drops(guild_id,raid_id,id,item_name,boss,dropped_at)
 select guild_id,id,'drop-1','SYNTHETIC item','SYNTHETIC boss',created_at from public.apoc_raids
 where source_key in ('test-a','test-b');
insert into public.apoc_raid_members(guild_id,raid_id,character_key,name,present)
 select guild_id,id,'synthetic-testrealm','Synthetic-Testrealm',true from public.apoc_raids
 where source_key in ('test-a','test-b');
insert into public.apoc_visits(guild_id,raid_id,character_key,joined_at)
 select guild_id,id,'synthetic-testrealm',created_at from public.apoc_raids where source_key in ('test-a','test-b');
insert into public.apoc_comparisons(guild_id,raid_id,drop_id,status)
 select guild_id,id,'drop-1','insufficient_data' from public.apoc_raids where source_key in ('test-a','test-b');

-- Assert structural cross-guild isolation even for privileged ingestion.
do $$
begin
  begin
    insert into public.apoc_drops(guild_id,raid_id,id,item_name,dropped_at) values
      ('20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001','bad-link','Bad',now());
    raise exception 'FAIL: cross-guild foreign key was accepted';
  exception when foreign_key_violation then null;
  end;
end $$;

set local role authenticated;
do $$
declare
  subject uuid;
  role_case integer;
  expected_guild uuid;
  expected_count integer;
  expected_comparisons integer;
begin
  for role_case in 1..6 loop
    subject := ('10000000-0000-4000-8000-' || lpad(role_case::text,12,'0'))::uuid;
    expected_guild := case when role_case = 5 then '20000000-0000-4000-8000-000000000002'::uuid
                          else '20000000-0000-4000-8000-000000000001'::uuid end;
    expected_count := case when role_case = 6 then 0 else 1 end;
    expected_comparisons := case when role_case in (1,2,5) then 1 else 0 end;
    perform set_config('request.jwt.claim.sub',subject::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',subject,'role','authenticated',
      'is_anonymous',false,'user_metadata',jsonb_build_object('role','admin'))::text,true);

    if (select count(*) from public.apoc_memberships) <> 1 or
       exists(select 1 from public.apoc_memberships where user_id <> subject) then
      raise exception 'FAIL: membership disclosure, case %', role_case;
    end if;
    if (select count(*) from public.apoc_guilds) <> expected_count or
       exists(select 1 from public.apoc_guilds where id <> expected_guild) then
      raise exception 'FAIL: guild visibility, case %', role_case;
    end if;
    if (select count(*) from public.apoc_raids) <> expected_count or
       exists(select 1 from public.apoc_raids where guild_id <> expected_guild) then
      raise exception 'FAIL: raid isolation, case %', role_case;
    end if;
    if (select count(*) from public.apoc_drops) <> expected_count or
       (select count(*) from public.apoc_raid_members) <> expected_count or
       (select count(*) from public.apoc_visits) <> expected_count then
      raise exception 'FAIL: child visibility, case %', role_case;
    end if;
    if (select count(*) from public.apoc_comparisons) <> expected_comparisons or
       exists(select 1 from public.apoc_comparisons where guild_id <> expected_guild) then
      raise exception 'FAIL: comparison disclosure, case %', role_case;
    end if;
    begin
      update public.apoc_memberships set role = 'admin' where user_id = subject;
      raise exception 'FAIL: direct membership write allowed';
    exception when insufficient_privilege then null;
    end;
    begin
      delete from public.apoc_raids where guild_id = expected_guild;
      raise exception 'FAIL: direct raid deletion allowed';
    exception when insufficient_privilege then null;
    end;
  end loop;
  -- Even an accidentally provisioned anonymous identity with a membership fails.
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  perform set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}',true);
  if exists(select 1 from public.apoc_guilds) or exists(select 1 from public.apoc_comparisons) then
    raise exception 'FAIL: anonymous account inherited membership access';
  end if;
end $$;

-- Next statement must reflect demotion even with an unchanged JWT.
reset role;
update public.apoc_memberships set role='member' where user_id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
do $$ begin
  if exists(select 1 from public.apoc_comparisons) then raise exception 'FAIL: demoted officer retained comparisons'; end if;
  if (select count(*) from public.apoc_raids) <> 1 then raise exception 'FAIL: demoted member lost ordinary access'; end if;
end $$;

reset role;
update public.apoc_memberships set status='revoked' where user_id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
  if exists(select 1 from public.apoc_raids) then raise exception 'FAIL: revoked user retained raids'; end if;
end $$;

reset role;
set local role anon;
do $$ begin
  begin
    perform 1 from public.apoc_raids;
    raise exception 'FAIL: public role has table access';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
rollback;
select 'PASS: synthetic RLS checks completed and fixtures rolled back' as result;
