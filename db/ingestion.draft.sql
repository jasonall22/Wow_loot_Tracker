-- DRAFT, NOT APPLIED. Review and test in a disposable APOC database first.
-- These tables are server-side ingestion state. They are not exposed to clients.
begin;

create table public.apoc_devices (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  label text not null check (char_length(label) between 1 and 100),
  token_digest text not null check (token_digest ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (guild_id, id),
  unique (guild_id, token_digest),
  check (revoked_at is null or revoked_at >= created_at)
);

create table public.apoc_pairing_challenges (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  challenge_digest text not null check (challenge_digest ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  device_id uuid,
  primary key (guild_id, id),
  unique (challenge_digest),
  foreign key (guild_id, device_id) references public.apoc_devices(guild_id, id),
  check (expires_at > created_at),
  check (consumed_at is null or consumed_at >= created_at)
);
create index apoc_pairing_expiry on public.apoc_pairing_challenges(expires_at) where consumed_at is null;

create table public.apoc_upload_receipts (
  guild_id uuid not null,
  id uuid not null default gen_random_uuid(),
  device_id uuid not null,
  request_id uuid not null,
  source_key text not null check (char_length(source_key) between 1 and 200),
  source_revision bigint not null check (source_revision >= 0),
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  captured_at timestamptz not null,
  received_at timestamptz not null default now(),
  status text not null check (status in ('accepted', 'duplicate', 'stale', 'rejected')),
  primary key (guild_id, id),
  unique (guild_id, request_id),
  unique (guild_id, source_key, source_revision, payload_hash),
  foreign key (guild_id, device_id) references public.apoc_devices(guild_id, id)
);
create index apoc_upload_source on public.apoc_upload_receipts(guild_id, source_key, source_revision desc);

create table public.apoc_drop_corrections (
  guild_id uuid not null,
  raid_id uuid not null,
  drop_id text not null,
  id uuid not null default gen_random_uuid(),
  winner text check (char_length(winner) between 1 and 200),
  award_type text check (award_type in ('MS', 'OS', 'DE', 'GB', 'UNKNOWN')),
  award_note text check (char_length(award_note) <= 2000),
  reason text not null check (char_length(reason) between 1 and 2000),
  corrected_by uuid not null references auth.users(id),
  corrected_at timestamptz not null default now(),
  primary key (guild_id, id),
  foreign key (guild_id, raid_id, drop_id)
    references public.apoc_drops(guild_id, raid_id, id) on delete cascade,
  check (award_type is not null or winner is not null or award_note is not null)
);
create index apoc_drop_corrections_target on public.apoc_drop_corrections(guild_id, raid_id, drop_id, corrected_at desc);

create table public.apoc_audit_events (
  guild_id uuid not null references public.apoc_guilds(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  actor_user_id uuid references auth.users(id),
  entity_type text not null check (entity_type in ('device', 'pairing', 'upload', 'drop_correction', 'membership')),
  entity_id text not null check (char_length(entity_id) between 1 and 200),
  action text not null check (char_length(action) between 1 and 100),
  reason text check (char_length(reason) <= 2000),
  request_id uuid,
  occurred_at timestamptz not null default now(),
  primary key (guild_id, id)
);
create index apoc_audit_timeline on public.apoc_audit_events(guild_id, occurred_at desc, id);

-- Ingestion state is never directly readable or writable by browser roles.
alter table public.apoc_devices enable row level security;
alter table public.apoc_pairing_challenges enable row level security;
alter table public.apoc_upload_receipts enable row level security;
alter table public.apoc_drop_corrections enable row level security;
alter table public.apoc_audit_events enable row level security;

revoke all on public.apoc_devices, public.apoc_pairing_challenges, public.apoc_upload_receipts,
  public.apoc_drop_corrections, public.apoc_audit_events from public, anon, authenticated;

commit;
