-- Expedition run/checkpoint and encounter state. Runs may wait at checkpoints
-- while Duel/Team Battle happens; only an active encounter owns the combat lock.

create table public.expedition_runs (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null references public.profiles(id) on delete cascade,
  chapter_version_id   uuid not null references public.expedition_chapter_versions(id)
                           on delete restrict,
  team_id              uuid not null references public.anima_teams(id) on delete cascade,
  status               text not null default 'checkpoint',
  zone                 smallint not null default 1,
  zone_attempt         integer not null default 0,
  version              integer not null default 1,
  seed                 text not null,
  zone_map             jsonb,
  available_node_ids   jsonb not null default '[]'::jsonb,
  current_node_id      text,
  nodes_completed      smallint not null default 0,
  supplies             integer not null default 0,
  boosts               jsonb not null default '[]'::jsonb,
  party_state          jsonb not null default '[]'::jsonb,
  checkpoint_state     jsonb not null default '{}'::jsonb,
  pending_node         jsonb,
  shop_refreshed       boolean not null default false,
  bits_refresh_spent   integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  completed_at         timestamptz,
  abandoned_at         timestamptz,
  constraint expedition_runs_status_valid
    check (status in ('checkpoint', 'active', 'complete', 'abandoned')),
  constraint expedition_runs_zone_valid check (zone between 1 and 3),
  constraint expedition_runs_attempt_nonnegative check (zone_attempt >= 0),
  constraint expedition_runs_version_positive check (version >= 1),
  constraint expedition_runs_seed_valid check (length(seed) between 1 and 128),
  constraint expedition_runs_map_object
    check (zone_map is null or jsonb_typeof(zone_map) = 'object'),
  constraint expedition_runs_available_array
    check (jsonb_typeof(available_node_ids) = 'array'),
  constraint expedition_runs_nodes_valid check (nodes_completed between 0 and 4),
  constraint expedition_runs_supplies_nonnegative check (supplies >= 0),
  constraint expedition_runs_boosts_array check (jsonb_typeof(boosts) = 'array'),
  constraint expedition_runs_party_array check (jsonb_typeof(party_state) = 'array'),
  constraint expedition_runs_checkpoint_object
    check (jsonb_typeof(checkpoint_state) = 'object'),
  constraint expedition_runs_pending_object
    check (pending_node is null or jsonb_typeof(pending_node) = 'object'),
  constraint expedition_runs_refresh_nonnegative check (bits_refresh_spent >= 0)
);

create unique index expedition_one_open_run_per_owner
  on public.expedition_runs (owner_id)
  where status in ('checkpoint', 'active');

create index expedition_runs_owner_created_idx
  on public.expedition_runs (owner_id, created_at desc);

alter table public.seeker_trophies
  add constraint seeker_trophies_run_fk
  foreign key (run_id) references public.expedition_runs(id) on delete set null;

create table public.expedition_encounters (
  id                uuid primary key default gen_random_uuid(),
  run_id            uuid not null references public.expedition_runs(id) on delete cascade,
  owner_id          uuid not null references public.profiles(id) on delete cascade,
  node_id           text not null,
  kind              text not null,
  player_snapshot   jsonb not null,
  opponent_snapshot jsonb not null,
  state             jsonb not null,
  turn_number       integer not null default 1,
  version           integer not null default 1,
  status            text not null default 'active',
  rng_seed          text not null,
  item_used_id      text references public.catalog_items(id),
  supplies_reward   integer not null default 0,
  rewarded_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  finished_at       timestamptz,
  expires_at        timestamptz not null default (now() + interval '60 minutes'),
  constraint expedition_encounters_node_valid check (length(node_id) between 1 and 80),
  constraint expedition_encounters_kind_valid check (kind in ('battle', 'elite', 'boss')),
  constraint expedition_encounters_status_valid
    check (status in ('active', 'won', 'lost', 'draw', 'forfeited')),
  constraint expedition_encounters_turn_positive check (turn_number >= 1),
  constraint expedition_encounters_version_positive check (version >= 1),
  constraint expedition_encounters_snapshots_valid check (
    jsonb_typeof(player_snapshot) = 'array'
    and jsonb_array_length(player_snapshot) = 4
    and jsonb_typeof(opponent_snapshot) = 'array'
    and jsonb_array_length(opponent_snapshot) between 1 and 4
  ),
  constraint expedition_encounters_state_object check (jsonb_typeof(state) = 'object'),
  constraint expedition_encounters_seed_valid check (length(rng_seed) between 1 and 128),
  constraint expedition_encounters_supplies_nonnegative check (supplies_reward >= 0),
  unique (run_id, node_id)
);

create unique index expedition_one_active_encounter_per_owner
  on public.expedition_encounters (owner_id)
  where status = 'active';

create index expedition_encounters_run_created_idx
  on public.expedition_encounters (run_id, created_at desc);

create table public.expedition_encounter_turns (
  id               bigserial primary key,
  encounter_id     uuid not null references public.expedition_encounters(id)
                       on delete cascade,
  turn_number      integer not null,
  idempotency_key  text not null,
  action           text not null,
  switch_to_slot   smallint,
  catalog_item_id  text references public.catalog_items(id),
  response         jsonb not null,
  created_at       timestamptz not null default now(),
  constraint expedition_turn_action_valid
    check (action in ('strike', 'surge', 'guard', 'item', 'switch')),
  constraint expedition_turn_shape_valid check (
    (action = 'switch' and switch_to_slot between 0 and 3 and catalog_item_id is null)
    or (action = 'item' and switch_to_slot is null and catalog_item_id is not null)
    or (action in ('strike', 'surge', 'guard')
        and switch_to_slot is null and catalog_item_id is null)
  ),
  unique (encounter_id, turn_number),
  unique (encounter_id, idempotency_key)
);

create index expedition_turns_encounter_idx
  on public.expedition_encounter_turns (encounter_id, turn_number);

create table public.expedition_encounter_rewards (
  encounter_id uuid primary key references public.expedition_encounters(id)
                 on delete cascade,
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  progression boolean not null,
  supplies    integer not null,
  created_at  timestamptz not null default now(),
  constraint expedition_reward_supplies_nonnegative check (supplies >= 0)
);

create index expedition_rewards_owner_created_idx
  on public.expedition_encounter_rewards (owner_id, created_at desc);

create table public.expedition_run_actions (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key text not null,
  run_id          uuid not null references public.expedition_runs(id) on delete cascade,
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  operation       text not null,
  response        jsonb not null,
  created_at      timestamptz not null default now(),
  unique (owner_id, idempotency_key),
  constraint expedition_run_action_key_valid
    check (length(idempotency_key) between 1 and 128),
  constraint expedition_run_action_operation_valid check (
    operation in (
      'start_run', 'start_zone', 'enter_node', 'choose_node_option',
      'refresh_shop', 'abandon'
    )
  )
);

alter table public.expedition_runs
  add column shop_refresh_action_id uuid
  references public.expedition_run_actions(id) on delete set null;

create unique index quota_ledger_expedition_shop_unique
  on public.quota_ledger (ref_id) where reason = 'expedition_shop';

create unique index quota_ledger_expedition_refund_unique
  on public.quota_ledger (ref_id) where reason = 'expedition_refund';

create unique index quota_ledger_expedition_clear_unique
  on public.quota_ledger (ref_id) where reason = 'expedition_clear';

create or replace function public.guard_single_active_combat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'active' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text, 0));

  if tg_table_name <> 'battle_sessions' and exists (
    select 1 from public.battle_sessions
     where owner_id = new.owner_id and status = 'active' and expires_at > now()
  ) then raise exception 'COMBAT_ALREADY_ACTIVE'; end if;
  if tg_table_name <> 'team_battle_sessions' and exists (
    select 1 from public.team_battle_sessions
     where owner_id = new.owner_id and status = 'active' and expires_at > now()
  ) then raise exception 'COMBAT_ALREADY_ACTIVE'; end if;
  if tg_table_name <> 'expedition_encounters' and exists (
    select 1 from public.expedition_encounters
     where owner_id = new.owner_id and status = 'active' and expires_at > now()
  ) then raise exception 'COMBAT_ALREADY_ACTIVE'; end if;
  return new;
end $$;

create trigger expedition_encounters_single_active_combat
before insert on public.expedition_encounters
for each row execute function public.guard_single_active_combat();

create or replace function public.guard_active_expedition_team_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid := case when tg_op = 'INSERT' then new.team_id else old.team_id end;
  v_owner uuid;
begin
  select owner_id into v_owner from public.anima_teams
   where id = v_team_id and kind = 'expedition';
  if not found then return case when tg_op = 'DELETE' then old else new end; end if;
  if v_owner::text = any(string_to_array(
    current_setting('scanima.deleting_profiles', true),
    ','
  )) then return case when tg_op = 'DELETE' then old else new end; end if;
  if exists (
    select 1 from public.expedition_runs
     where owner_id = v_owner and team_id = v_team_id and status = 'active'
  ) then raise exception 'EXPEDITION_TEAM_LOCKED'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger anima_team_members_lock_active_expedition
before insert or update or delete on public.anima_team_members
for each row execute function public.guard_active_expedition_team_change();

create or replace function public.guard_active_team_anima_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.owner_id::text = any(string_to_array(
    current_setting('scanima.deleting_profiles', true),
    ','
  )) then return old; end if;
  if exists (
    select 1 from public.team_battle_sessions s
     where s.status = 'active'
       and s.expires_at > now()
       and (
         s.player_snapshot @> jsonb_build_array(jsonb_build_object('anima_id', old.id::text))
         or s.opponent_snapshot @> jsonb_build_array(jsonb_build_object('anima_id', old.id::text))
       )
  ) or exists (
    select 1 from public.expedition_runs r
     where r.owner_id = old.owner_id
       and r.status = 'active'
       and r.party_state @> jsonb_build_array(jsonb_build_object('anima_id', old.id::text))
  ) then
    raise exception 'ANIMA_IN_ACTIVE_COMBAT';
  end if;
  return old;
end $$;

alter table public.expedition_runs enable row level security;
alter table public.expedition_encounters enable row level security;
alter table public.expedition_encounter_turns enable row level security;
alter table public.expedition_encounter_rewards enable row level security;
alter table public.expedition_run_actions enable row level security;

revoke all on public.expedition_runs from public, anon, authenticated;
revoke all on public.expedition_encounters from public, anon, authenticated;
revoke all on public.expedition_encounter_turns from public, anon, authenticated;
revoke all on public.expedition_encounter_rewards from public, anon, authenticated;
revoke all on public.expedition_run_actions from public, anon, authenticated;
revoke all on sequence public.expedition_encounter_turns_id_seq
  from public, anon, authenticated;
revoke all on function public.guard_active_expedition_team_change()
  from public, anon, authenticated;

grant all on public.expedition_runs to service_role;
grant all on public.expedition_encounters to service_role;
grant all on public.expedition_encounter_turns to service_role;
grant all on public.expedition_encounter_rewards to service_role;
grant all on public.expedition_run_actions to service_role;
grant usage, select on sequence public.expedition_encounter_turns_id_seq
  to service_role;
grant execute on function public.guard_active_expedition_team_change()
  to service_role;
