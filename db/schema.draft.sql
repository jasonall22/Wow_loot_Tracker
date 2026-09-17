-- DRAFT, NOT APPLIED. Run only in a NEW dedicated APOC test project first.
-- Register an actual migration with the Supabase CLI once database testing passes.
-- No account creation, invitations, device pairing, uploads or edits are enabled here.
-- Authenticated users receive SELECT only; no self-promotion or direct record writes.
begin;

create table public.apoc_guilds (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  realm text not null check (char_length(realm) between 1 and 100),
  faction text not null check (faction in ('Alliance', 'Horde')),
  created_at timestamptz not null default now()
);

create table public.apoc_memberships (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'officer', 'member')),
  status text not null default 'active' check (status in ('active', 'suspended', 'revoked')),
  can_upload boolean not null default false,
  can_edit boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (guild_id, user_id),
  constraint apoc_edit_requires_officer check (not can_edit or role in ('admin', 'officer'))
);
create index apoc_memberships_user_guild on public.apoc_memberships(user_id, guild_id);

create table public.apoc_raids (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  source_key text not null check (char_length(source_key) between 1 and 200),
  name text not null check (char_length(name) between 1 and 300),
  run_id text not null check (char_length(run_id) between 1 and 200),
  revision bigint not null default 0 check (revision >= 0),
  created_at timestamptz not null,
  closed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (guild_id, id),
  unique (guild_id, source_key),
  check (closed_at is null or closed_at >= created_at)
);
create index apoc_raids_archive on public.apoc_raids(guild_id, created_at desc, id);

create table public.apoc_drops (
  guild_id uuid not null,
  raid_id uuid not null,
  id text not null check (char_length(id) between 1 and 200),
  item_id integer check (item_id > 0),
  item_name text not null check (char_length(item_name) between 1 and 300),
  item_link text check (char_length(item_link) <= 1000),
  boss text not null default '' check (char_length(boss) <= 200),
  dropped_at timestamptz not null,
  winner text check (char_length(winner) between 1 and 200),
  award_type text check (award_type in ('MS', 'OS', 'DE', 'GB', 'UNKNOWN')),
  awarded_at timestamptz,
  award_note text check (char_length(award_note) <= 2000),
  primary key (guild_id, raid_id, id),
  foreign key (guild_id, raid_id) references public.apoc_raids(guild_id, id) on delete cascade,
  check ((award_type is null and awarded_at is null and winner is null) or
         (award_type is not null and awarded_at is not null))
);
create index apoc_drops_timeline on public.apoc_drops(guild_id, raid_id, dropped_at, id);

create table public.apoc_raid_members (
  guild_id uuid not null,
  raid_id uuid not null,
  character_key text not null check (char_length(character_key) between 1 and 200),
  name text not null check (char_length(name) between 1 and 200),
  class text not null default '' check (char_length(class) <= 30),
  raid_group smallint not null default 0 check (raid_group between 0 and 8),
  present boolean not null default false,
  primary key (guild_id, raid_id, character_key),
  foreign key (guild_id, raid_id) references public.apoc_raids(guild_id, id) on delete cascade
);

create table public.apoc_visits (
  guild_id uuid not null,
  raid_id uuid not null,
  character_key text not null,
  id uuid not null default gen_random_uuid(),
  joined_at timestamptz not null,
  left_at timestamptz,
  primary key (guild_id, id),
  foreign key (guild_id, raid_id, character_key)
    references public.apoc_raid_members(guild_id, raid_id, character_key) on delete cascade,
  check (left_at is null or left_at >= joined_at)
);
create index apoc_visits_member on public.apoc_visits(guild_id, raid_id, character_key);
create index apoc_visits_timeline on public.apoc_visits(guild_id, raid_id, joined_at, id);

-- Never mix officer-only comparison inputs/results into ordinary raid/drop JSON.
-- These are storage/access contracts; there is NO simulator in this foundation.
create table public.apoc_comparisons (
  guild_id uuid not null,
  raid_id uuid not null,
  drop_id text not null,
  id uuid not null default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending', 'insufficient_data', 'complete', 'failed')),
  observed_at timestamptz,
  result jsonb,
  updated_at timestamptz not null default now(),
  primary key (guild_id, id),
  foreign key (guild_id, raid_id, drop_id) references public.apoc_drops(guild_id, raid_id, id) on delete cascade,
  check (result is null or (jsonb_typeof(result) = 'object' and octet_length(result::text) <= 65536)),
  check (status <> 'complete' or (result is not null and observed_at is not null))
);
create index apoc_comparisons_drop on public.apoc_comparisons(guild_id, raid_id, drop_id);
create index apoc_comparisons_updated on public.apoc_comparisons(guild_id, raid_id, updated_at desc, id);

-- RLS without SECURITY DEFINER helpers: membership SELECT returns only one's own
-- rows, so membership lookups in the other policies cannot recurse or expose roles.
alter table public.apoc_guilds enable row level security;
alter table public.apoc_memberships enable row level security;
alter table public.apoc_raids enable row level security;
alter table public.apoc_drops enable row level security;
alter table public.apoc_raid_members enable row level security;
alter table public.apoc_visits enable row level security;
alter table public.apoc_comparisons enable row level security;

create policy apoc_own_membership on public.apoc_memberships for select to authenticated
  using (user_id = (select auth.uid()) and coalesce((select auth.jwt()->>'is_anonymous'), 'true') = 'false');

create policy apoc_guild_read on public.apoc_guilds for select to authenticated using (
  exists (select 1 from public.apoc_memberships m where m.guild_id = apoc_guilds.id
    and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy apoc_raid_read on public.apoc_raids for select to authenticated using (
  exists (select 1 from public.apoc_memberships m where m.guild_id = apoc_raids.guild_id
    and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy apoc_drop_read on public.apoc_drops for select to authenticated using (
  exists (select 1 from public.apoc_memberships m where m.guild_id = apoc_drops.guild_id
    and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy apoc_member_read on public.apoc_raid_members for select to authenticated using (
  exists (select 1 from public.apoc_memberships m where m.guild_id = apoc_raid_members.guild_id
    and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy apoc_visit_read on public.apoc_visits for select to authenticated using (
  exists (select 1 from public.apoc_memberships m where m.guild_id = apoc_visits.guild_id
    and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy apoc_comparison_officers on public.apoc_comparisons for select to authenticated using (
  exists (select 1 from public.apoc_memberships m where m.guild_id = apoc_comparisons.guild_id
    and m.user_id = (select auth.uid()) and m.status = 'active' and m.role in ('admin', 'officer'))
);

-- Explicit grants: do not depend on project creation date or default exposure.
revoke all on public.apoc_guilds, public.apoc_memberships, public.apoc_raids,
  public.apoc_drops, public.apoc_raid_members, public.apoc_visits,
  public.apoc_comparisons from public, anon, authenticated;
grant select on public.apoc_guilds, public.apoc_memberships, public.apoc_raids,
  public.apoc_drops, public.apoc_raid_members, public.apoc_visits,
  public.apoc_comparisons to authenticated;

commit;
