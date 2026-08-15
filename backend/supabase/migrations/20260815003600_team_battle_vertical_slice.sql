-- Team Battle: roster tersimpan, Defense opt-in, candidate singkat, session,
-- dan replay turn. Seluruh tabel tertutup; client hanya lewat Edge Function.

create table public.anima_teams (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  kind          text not null,
  published     boolean not null default false,
  snapshot      jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  published_at timestamptz,
  constraint anima_teams_kind_valid
    check (kind in ('team_battle', 'expedition', 'defense')),
  constraint anima_teams_publish_only_defense
    check (not published or kind = 'defense'),
  constraint anima_teams_snapshot_array
    check (snapshot is null or jsonb_typeof(snapshot) = 'array'),
  constraint anima_teams_owner_kind_unique unique (owner_id, kind)
);

create table public.anima_team_members (
  team_id    uuid not null references public.anima_teams(id) on delete cascade,
  slot       smallint not null,
  anima_id   uuid not null references public.animas(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, slot),
  constraint anima_team_members_slot_valid check (slot between 0 and 3),
  constraint anima_team_members_unique_anima unique (team_id, anima_id)
);

create index anima_team_members_anima_idx
  on public.anima_team_members (anima_id);

create table public.system_team_templates (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique,
  display_name    text not null,
  roster_snapshot jsonb not null,
  active          boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint system_team_templates_slug_valid
    check (slug ~ '^[a-z0-9][a-z0-9_-]{2,47}$'),
  constraint system_team_templates_name_len
    check (char_length(display_name) between 1 and 32),
  constraint system_team_templates_roster_valid
    check (
      jsonb_typeof(roster_snapshot) = 'array'
      and jsonb_array_length(roster_snapshot) between 1 and 4
    )
);

-- Placeholder lokal membuat mode tetap bisa dimulai sebelum ada Defense opt-in.
-- Chapter Factory menggantinya dengan roster/art authored sebelum rollout luas.
insert into public.system_team_templates (
  slug, display_name, roster_snapshot, active
) values (
  'starter-sentinels',
  'Starter Sentinels',
  '[
    {
      "anima_id":"10000000-0000-4000-8000-000000000001",
      "name":"Byte Scout","species_key":"system_byte_scout","color_bucket":"cyan",
      "stage":1,"level":4,"element":"spark",
      "base_stats":{"hp":46,"atk":52,"def":42,"spd":64,"special":46},
      "hunger":100,"hygiene":100,"strike_name":"Pixel Jab","surge_name":"Static Arc",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"10000000-0000-4000-8000-000000000002",
      "name":"Moss Guard","species_key":"system_moss_guard","color_bucket":"green",
      "stage":1,"level":4,"element":"plant",
      "base_stats":{"hp":58,"atk":42,"def":64,"spd":38,"special":48},
      "hunger":100,"hygiene":100,"strike_name":"Vine Tap","surge_name":"Briar Wall",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"10000000-0000-4000-8000-000000000003",
      "name":"Pebble Dash","species_key":"system_pebble_dash","color_bucket":"gray",
      "stage":1,"level":4,"element":"stone",
      "base_stats":{"hp":52,"atk":50,"def":56,"spd":44,"special":48},
      "hunger":100,"hygiene":100,"strike_name":"Rock Knock","surge_name":"Quake Pop",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"10000000-0000-4000-8000-000000000004",
      "name":"Paper Kite","species_key":"system_paper_kite","color_bucket":"white",
      "stage":1,"level":4,"element":"paper","secondary_element":"air",
      "base_stats":{"hp":40,"atk":44,"def":38,"spd":72,"special":56},
      "hunger":100,"hygiene":100,"strike_name":"Fold Slash","surge_name":"Gale Script",
      "system_asset":"placeholder","manifest":{}
    }
  ]'::jsonb,
  true
);

create table public.team_battle_candidates (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references public.profiles(id) on delete cascade,
  player_team_id    uuid not null references public.anima_teams(id) on delete cascade,
  opponent_source   text not null,
  opponent_team_id  uuid references public.anima_teams(id) on delete set null,
  opponent_snapshot jsonb not null,
  reward_tier       text not null,
  reward_roll       smallint not null,
  reward_bits       integer not null,
  created_at        timestamptz not null default now(),
  expires_at        timestamptz not null default (now() + interval '10 minutes'),
  consumed_at       timestamptz,
  constraint team_battle_candidates_source_valid
    check (opponent_source in ('defense', 'system')),
  constraint team_battle_candidates_snapshot_valid
    check (
      jsonb_typeof(opponent_snapshot) = 'array'
      and jsonb_array_length(opponent_snapshot) between 1 and 4
    ),
  constraint team_battle_candidates_tier_valid
    check (reward_tier in ('favorable', 'even', 'tough', 'formidable')),
  constraint team_battle_candidates_roll_valid check (reward_roll between -1 and 1),
  constraint team_battle_candidates_bits_valid check (reward_bits between 5 and 16)
);

create index team_battle_candidates_owner_expiry_idx
  on public.team_battle_candidates (owner_id, expires_at desc);

create table public.team_battle_sessions (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references public.profiles(id) on delete cascade,
  player_team_id    uuid not null references public.anima_teams(id),
  opponent_source   text not null,
  opponent_team_id  uuid references public.anima_teams(id) on delete set null,
  player_snapshot   jsonb not null,
  opponent_snapshot jsonb not null,
  state             jsonb not null,
  turn_number       integer not null default 1,
  version           integer not null default 1,
  status            text not null default 'active',
  rng_seed          text not null,
  reward_tier       text not null,
  reward_roll       smallint not null,
  reward_bits       integer not null,
  item_used_id      text references public.catalog_items(id),
  rewarded_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  finished_at       timestamptz,
  expires_at        timestamptz not null default (now() + interval '60 minutes'),
  constraint team_battle_sessions_source_valid
    check (opponent_source in ('defense', 'system')),
  constraint team_battle_sessions_status_valid
    check (status in ('active', 'won', 'lost', 'draw', 'forfeited')),
  constraint team_battle_sessions_turn_positive check (turn_number >= 1),
  constraint team_battle_sessions_version_positive check (version >= 1),
  constraint team_battle_sessions_snapshots_valid
    check (
      jsonb_typeof(player_snapshot) = 'array'
      and jsonb_array_length(player_snapshot) = 4
      and jsonb_typeof(opponent_snapshot) = 'array'
      and jsonb_array_length(opponent_snapshot) between 1 and 4
    ),
  constraint team_battle_sessions_tier_valid
    check (reward_tier in ('favorable', 'even', 'tough', 'formidable')),
  constraint team_battle_sessions_roll_valid check (reward_roll between -1 and 1),
  constraint team_battle_sessions_bits_valid check (reward_bits between 5 and 16)
);

create unique index team_battle_one_active_per_owner
  on public.team_battle_sessions (owner_id)
  where status = 'active';

create index team_battle_sessions_owner_created_idx
  on public.team_battle_sessions (owner_id, created_at desc);

create table public.team_battle_turns (
  id               bigserial primary key,
  session_id       uuid not null references public.team_battle_sessions(id) on delete cascade,
  turn_number      integer not null,
  idempotency_key  text not null,
  action           text not null,
  switch_to_slot   smallint,
  catalog_item_id  text references public.catalog_items(id),
  response         jsonb not null,
  created_at       timestamptz not null default now(),
  constraint team_battle_turns_action_valid
    check (action in ('strike', 'surge', 'guard', 'item', 'switch')),
  constraint team_battle_turns_switch_valid
    check (
      (action = 'switch' and switch_to_slot between 0 and 3 and catalog_item_id is null)
      or (action = 'item' and switch_to_slot is null and catalog_item_id is not null)
      or (action in ('strike', 'surge', 'guard')
          and switch_to_slot is null and catalog_item_id is null)
    ),
  constraint team_battle_turns_turn_key_unique unique (session_id, turn_number),
  constraint team_battle_turns_idempotency_unique unique (session_id, idempotency_key)
);

create index team_battle_turns_session_idx
  on public.team_battle_turns (session_id, turn_number);

create or replace function public.invalidate_anima_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.anima_teams
     set published = false,
         snapshot = null,
         published_at = null,
         updated_at = now()
   where id = old.team_id;
  delete from public.team_battle_candidates
   where player_team_id = old.team_id or opponent_team_id = old.team_id;
  return old;
end $$;

create trigger anima_team_member_removed_invalidate
after delete on public.anima_team_members
for each row execute function public.invalidate_anima_team();

create or replace function public.mark_profile_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleting text := current_setting('scanima.deleting_profiles', true);
begin
  perform set_config(
    'scanima.deleting_profiles',
    concat_ws(',', nullif(v_deleting, ''), old.id::text),
    true
  );
  return old;
end $$;

create trigger profiles_mark_account_deletion
before delete on public.profiles
for each row execute function public.mark_profile_deletion();

create or replace function public.guard_active_team_anima_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Delete Account owns the whole cascade and must win over encounter locks.
  if old.owner_id::text = any(string_to_array(
    current_setting('scanima.deleting_profiles', true),
    ','
  )) then
    return old;
  end if;
  if exists (
    select 1
      from public.team_battle_sessions s
     where s.status = 'active'
       and s.expires_at > now()
       and (
         s.player_snapshot @> jsonb_build_array(
           jsonb_build_object('anima_id', old.id::text)
         )
         or s.opponent_snapshot @> jsonb_build_array(
           jsonb_build_object('anima_id', old.id::text)
         )
       )
  ) then
    raise exception 'ANIMA_IN_ACTIVE_COMBAT';
  end if;
  return old;
end $$;

create trigger animas_block_active_team_delete
before delete on public.animas
for each row execute function public.guard_active_team_anima_delete();

-- Satu owner tidak boleh membuat Duel dan Team session aktif secara bersamaan.
-- ponytail: advisory lock per-owner cukup selama semua mode memasang trigger ini;
-- kalau mode combat menjadi lintas database, ganti dengan combat lease table.
create or replace function public.guard_single_active_combat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'active' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text, 0));

  if tg_table_name = 'battle_sessions' and exists (
    select 1 from public.team_battle_sessions
     where owner_id = new.owner_id and status = 'active' and expires_at > now()
  ) then
    raise exception 'COMBAT_ALREADY_ACTIVE';
  end if;
  if tg_table_name = 'team_battle_sessions' and exists (
    select 1 from public.battle_sessions
     where owner_id = new.owner_id and status = 'active' and expires_at > now()
  ) then
    raise exception 'COMBAT_ALREADY_ACTIVE';
  end if;
  return new;
end $$;

create trigger battle_sessions_single_active_combat
before insert on public.battle_sessions
for each row execute function public.guard_single_active_combat();

create trigger team_battle_sessions_single_active_combat
before insert on public.team_battle_sessions
for each row execute function public.guard_single_active_combat();

alter table public.anima_teams enable row level security;
alter table public.anima_team_members enable row level security;
alter table public.system_team_templates enable row level security;
alter table public.team_battle_candidates enable row level security;
alter table public.team_battle_sessions enable row level security;
alter table public.team_battle_turns enable row level security;

revoke all on public.anima_teams from public, anon, authenticated;
revoke all on public.anima_team_members from public, anon, authenticated;
revoke all on public.system_team_templates from public, anon, authenticated;
revoke all on public.team_battle_candidates from public, anon, authenticated;
revoke all on public.team_battle_sessions from public, anon, authenticated;
revoke all on public.team_battle_turns from public, anon, authenticated;
revoke all on sequence public.team_battle_turns_id_seq
  from public, anon, authenticated;
revoke all on function public.guard_single_active_combat()
  from public, anon, authenticated;
revoke all on function public.invalidate_anima_team()
  from public, anon, authenticated;
revoke all on function public.mark_profile_deletion()
  from public, anon, authenticated;
revoke all on function public.guard_active_team_anima_delete()
  from public, anon, authenticated;

grant all on public.anima_teams to service_role;
grant all on public.anima_team_members to service_role;
grant all on public.system_team_templates to service_role;
grant all on public.team_battle_candidates to service_role;
grant all on public.team_battle_sessions to service_role;
grant all on public.team_battle_turns to service_role;
grant usage, select on sequence public.team_battle_turns_id_seq to service_role;
grant execute on function public.guard_single_active_combat() to service_role;
grant execute on function public.invalidate_anima_team() to service_role;
grant execute on function public.mark_profile_deletion() to service_role;
grant execute on function public.guard_active_team_anima_delete() to service_role;
