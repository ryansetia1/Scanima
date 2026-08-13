-- Phase 3 Battle vertical slice. Postgres owns session ordering, idempotency,
-- and rewards; the shared battle.mjs module owns the combat formula itself.

alter table public.animas
  add column battle_wins integer not null default 0,
  add constraint animas_battle_wins_valid check (battle_wins >= 0);

create table public.battle_sessions (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  player_anima_id    uuid not null references public.animas(id) on delete restrict,
  bot_anima_id       uuid references public.animas(id) on delete set null,
  player_snapshot    jsonb not null,
  bot_snapshot       jsonb not null,
  state              jsonb not null,
  player_hp          integer not null,
  bot_hp             integer not null,
  player_momentum    smallint not null default 3,
  bot_momentum       smallint not null default 3,
  turn_number        integer not null default 1,
  rng_seed           text not null,
  status             text not null default 'active',
  version            integer not null default 1,
  rewarded_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  expires_at         timestamptz not null default (now() + interval '30 minutes'),
  finished_at        timestamptz,
  constraint battle_sessions_status_valid
    check (status in ('active', 'won', 'lost', 'forfeited')),
  constraint battle_sessions_hp_valid check (player_hp >= 0 and bot_hp >= 0),
  constraint battle_sessions_momentum_valid
    check (player_momentum between 0 and 5 and bot_momentum between 0 and 5),
  constraint battle_sessions_turn_valid check (turn_number >= 1),
  constraint battle_sessions_version_valid check (version >= 1),
  constraint battle_sessions_seed_valid check (length(rng_seed) between 1 and 128)
);

create unique index battle_sessions_one_active_owner_idx
  on public.battle_sessions(owner_id)
  where status = 'active';
create index battle_sessions_player_anima_idx
  on public.battle_sessions(player_anima_id);

create table public.battle_turns (
  id                 uuid primary key default gen_random_uuid(),
  session_id         uuid not null references public.battle_sessions(id) on delete cascade,
  turn_number        integer not null,
  idempotency_key    text not null,
  action             text not null,
  response           jsonb not null,
  created_at         timestamptz not null default now(),
  constraint battle_turns_turn_valid check (turn_number >= 1),
  constraint battle_turns_key_valid
    check (length(idempotency_key) between 1 and 128),
  constraint battle_turns_action_valid
    check (action in ('strike', 'surge', 'guard')),
  constraint battle_turns_session_turn_unique unique (session_id, turn_number),
  constraint battle_turns_session_key_unique unique (session_id, idempotency_key)
);

alter table public.battle_sessions enable row level security;
alter table public.battle_turns enable row level security;
revoke all on public.battle_sessions, public.battle_turns from anon, authenticated;
grant all on public.battle_sessions, public.battle_turns to service_role;

create or replace function public.battle_session_payload(
  p_session public.battle_sessions
) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', (p_session).id,
    'player_anima_id', (p_session).player_anima_id,
    'player_snapshot', (p_session).player_snapshot,
    'bot_snapshot', (p_session).bot_snapshot,
    'state', (p_session).state,
    'turn_number', (p_session).turn_number,
    'status', (p_session).status,
    'version', (p_session).version,
    'created_at', (p_session).created_at,
    'updated_at', (p_session).updated_at,
    'expires_at', (p_session).expires_at,
    'finished_at', (p_session).finished_at
  )
$$;

create or replace function public.start_battle(
  p_owner uuid,
  p_player_anima_id uuid,
  p_bot_anima_id uuid,
  p_player_snapshot jsonb,
  p_bot_snapshot jsonb,
  p_initial_state jsonb,
  p_seed text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.animas;
  v_bot public.animas;
  v_session public.battle_sessions;
begin
  if p_seed is null or length(p_seed) not between 1 and 128 then
    raise exception 'INVALID_SEED';
  end if;
  if p_initial_state->>'status' <> 'active'
     or coalesce((p_initial_state->>'turn')::integer, 0) <> 1 then
    raise exception 'INVALID_BATTLE_STATE';
  end if;

  -- Profil lock membuat dua start paralel berbaris sebelum partial unique index.
  perform 1 from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  update public.battle_sessions
     set status = 'forfeited', finished_at = now(), updated_at = now()
   where owner_id = p_owner and status = 'active' and expires_at <= now();

  select * into v_session
    from public.battle_sessions
   where owner_id = p_owner and status = 'active'
   order by created_at desc
   limit 1;
  if found then
    return public.battle_session_payload(v_session);
  end if;

  perform public.apply_care(p_owner, p_player_anima_id, 'sync', null);
  select * into v_player
    from public.animas
   where id = p_player_anima_id and owner_id = p_owner
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_player.status <> 'ready' then raise exception 'ANIMA_NOT_READY'; end if;
  if v_player.sleep_started_at is not null then raise exception 'ANIMA_SLEEPING'; end if;
  if v_player.dormant_since is not null then raise exception 'ANIMA_DORMANT'; end if;

  select * into v_bot
    from public.animas
   where id = p_bot_anima_id
     and owner_id <> p_owner
     and status = 'ready';
  if not found then raise exception 'BOT_NOT_FOUND'; end if;

  if p_player_snapshot->>'anima_id' is distinct from p_player_anima_id::text
     or p_bot_snapshot->>'anima_id' is distinct from p_bot_anima_id::text then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  insert into public.battle_sessions (
    owner_id, player_anima_id, bot_anima_id,
    player_snapshot, bot_snapshot, state,
    player_hp, bot_hp, player_momentum, bot_momentum,
    turn_number, rng_seed
  ) values (
    p_owner, p_player_anima_id, p_bot_anima_id,
    p_player_snapshot - 'owner_id',
    p_bot_snapshot - 'owner_id' - 'nickname',
    p_initial_state,
    (p_initial_state #>> '{player,hp}')::integer,
    (p_initial_state #>> '{bot,hp}')::integer,
    (p_initial_state #>> '{player,momentum}')::smallint,
    (p_initial_state #>> '{bot,momentum}')::smallint,
    1,
    p_seed
  )
  returning * into v_session;

  return public.battle_session_payload(v_session);
end $$;

create or replace function public.resume_battle(
  p_owner uuid,
  p_session_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.battle_sessions;
begin
  update public.battle_sessions
     set status = 'forfeited', finished_at = now(), updated_at = now()
   where owner_id = p_owner and status = 'active' and expires_at <= now();

  select * into v_session
    from public.battle_sessions
   where owner_id = p_owner
     and (
       (p_session_id is null and status = 'active')
       or (p_session_id is not null and id = p_session_id)
     )
   order by created_at desc
   limit 1;
  if not found then return null; end if;
  return public.battle_session_payload(v_session);
end $$;

create or replace function public.commit_battle_turn(
  p_owner uuid,
  p_session_id uuid,
  p_expected_turn integer,
  p_expected_version integer,
  p_key text,
  p_action text,
  p_state jsonb,
  p_events jsonb,
  p_bot_action text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.battle_sessions;
  v_turn public.battle_turns;
  v_response jsonb;
  v_reward jsonb := jsonb_build_object('bits', 0, 'care_score', 0, 'battle_wins', 0);
  v_status text;
begin
  if p_action not in ('strike', 'surge', 'guard') then raise exception 'INVALID_ACTION'; end if;
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;
  if jsonb_typeof(p_events) <> 'array' then raise exception 'INVALID_EVENTS'; end if;

  select * into v_session
    from public.battle_sessions
   where id = p_session_id and owner_id = p_owner
   for update;
  if not found then raise exception 'BATTLE_NOT_FOUND'; end if;

  select * into v_turn
    from public.battle_turns
   where session_id = p_session_id and idempotency_key = p_key;
  if found then
    if v_turn.turn_number <> p_expected_turn or v_turn.action <> p_action then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_turn.response || jsonb_build_object('replayed', true);
  end if;

  if v_session.status <> 'active' then raise exception 'BATTLE_FINISHED'; end if;
  if v_session.expires_at <= now() then
    update public.battle_sessions
       set status = 'forfeited', finished_at = now(), updated_at = now()
     where id = v_session.id
    returning * into v_session;
    return jsonb_build_object(
      'session', public.battle_session_payload(v_session),
      'events', jsonb_build_array(
        jsonb_build_object('type', 'finished', 'result', 'forfeited')
      ),
      'bot_action', null,
      'reward', v_reward,
      'replayed', false
    );
  end if;
  if v_session.turn_number <> p_expected_turn
     or v_session.version <> p_expected_version then
    raise exception 'STALE_BATTLE';
  end if;

  v_status := p_state->>'status';
  if v_status not in ('active', 'won', 'lost')
     or (p_state->>'turn')::integer <> p_expected_turn + 1
     or (p_state #>> '{player,hp}')::integer < 0
     or (p_state #>> '{bot,hp}')::integer < 0
     or (p_state #>> '{player,momentum}')::integer not between 0 and 5
     or (p_state #>> '{bot,momentum}')::integer not between 0 and 5 then
    raise exception 'INVALID_BATTLE_STATE';
  end if;

  update public.battle_sessions
     set state = p_state,
         player_hp = (p_state #>> '{player,hp}')::integer,
         bot_hp = (p_state #>> '{bot,hp}')::integer,
         player_momentum = (p_state #>> '{player,momentum}')::smallint,
         bot_momentum = (p_state #>> '{bot,momentum}')::smallint,
         turn_number = p_expected_turn + 1,
         version = version + 1,
         status = v_status,
         updated_at = now(),
         finished_at = case when v_status = 'active' then null else now() end
   where id = v_session.id
  returning * into v_session;

  if v_status = 'won' and v_session.rewarded_at is null then
    update public.profiles set bits = bits + 5 where id = p_owner;
    update public.animas
       set care_score = care_score + 4,
           battle_wins = battle_wins + 1
     where id = v_session.player_anima_id and owner_id = p_owner;
    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (p_owner, 'bits', 5, 'battle_win', v_session.id);
    update public.battle_sessions
       set rewarded_at = now()
     where id = v_session.id
    returning * into v_session;
    v_reward := jsonb_build_object('bits', 5, 'care_score', 4, 'battle_wins', 1);
  end if;

  v_response := jsonb_build_object(
    'session', public.battle_session_payload(v_session),
    'events', p_events,
    'bot_action', p_bot_action,
    'reward', v_reward,
    'replayed', false
  );
  insert into public.battle_turns
    (session_id, turn_number, idempotency_key, action, response)
  values
    (v_session.id, p_expected_turn, p_key, p_action, v_response);
  return v_response;
end $$;

create or replace function public.forfeit_battle(
  p_owner uuid,
  p_session_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.battle_sessions;
begin
  select * into v_session
    from public.battle_sessions
   where id = p_session_id and owner_id = p_owner
   for update;
  if not found then raise exception 'BATTLE_NOT_FOUND'; end if;
  if v_session.status <> 'active' then
    return public.battle_session_payload(v_session);
  end if;
  update public.battle_sessions
     set status = 'forfeited',
         state = jsonb_set(state, '{status}', '"forfeited"'::jsonb),
         updated_at = now(),
         finished_at = now()
   where id = v_session.id
  returning * into v_session;
  return public.battle_session_payload(v_session);
end $$;

revoke all on function public.battle_session_payload(public.battle_sessions)
  from public, anon, authenticated;
revoke all on function public.start_battle(uuid, uuid, uuid, jsonb, jsonb, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.resume_battle(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.forfeit_battle(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.battle_session_payload(public.battle_sessions)
  to service_role;
grant execute on function public.start_battle(uuid, uuid, uuid, jsonb, jsonb, jsonb, text)
  to service_role;
grant execute on function public.resume_battle(uuid, uuid)
  to service_role;
grant execute on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text
) to service_role;
grant execute on function public.forfeit_battle(uuid, uuid)
  to service_role;
