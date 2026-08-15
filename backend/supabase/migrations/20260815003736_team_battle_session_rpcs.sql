-- Session lifecycle Team Battle. State dibuat resolver JS, tetapi Postgres
-- memverifikasi roster, eligibility, Energy, candidate, dan cross-mode lock.

create or replace function public.team_battle_daily_reward_status(
  p_owner uuid,
  p_session_id uuid default null
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with settings as (
    select
      greatest(0, least(20, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'team_battle_rewarded_wins_per_day'
      ), 2))) as reward_limit,
      greatest(0, least(1000, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'team_battle_bits_per_day'
      ), 40))) as bits_limit
  ),
  zone as (
    select coalesce((
      select timezone_offset_minutes from public.profiles where id = p_owner
    ), 0) as offset_minutes
  ),
  boundary as (
    select
      now() as server_now,
      public.local_day_start(now(), zone.offset_minutes) as starts_at,
      public.local_day_start(now(), zone.offset_minutes) + interval '1 day' as reset_at
    from zone
  ),
  rewarded as (
    select count(*)::integer as wins
      from public.quota_ledger q
      cross join boundary b
     where q.owner_id = p_owner
       and q.reason = 'team_battle_win'
       and q.created_at >= b.starts_at
       and q.created_at < b.reset_at
  ),
  bits as (
    select coalesce(sum(q.delta), 0)::integer as earned
      from public.quota_ledger q
      cross join boundary b
     where q.owner_id = p_owner
       and q.currency = 'bits'
       and q.reason in ('team_battle_win', 'team_battle_train')
       and q.created_at >= b.starts_at
       and q.created_at < b.reset_at
  )
  select jsonb_build_object(
    'earned', rewarded.wins,
    'limit', settings.reward_limit,
    'remaining', greatest(0, settings.reward_limit - rewarded.wins),
    'bits_earned', bits.earned,
    'bits_limit', settings.bits_limit,
    'bits_remaining', greatest(0, settings.bits_limit - bits.earned),
    'server_now', boundary.server_now,
    'reset_at', boundary.reset_at,
    'rewarded', exists (
      select 1 from public.quota_ledger q
       where p_session_id is not null
         and q.owner_id = p_owner
         and q.ref_id = p_session_id
         and q.reason in ('team_battle_win', 'team_battle_train')
    ),
    'progression_rewarded', exists (
      select 1 from public.quota_ledger q
       where p_session_id is not null
         and q.owner_id = p_owner
         and q.ref_id = p_session_id
         and q.reason = 'team_battle_win'
    )
  )
  from settings, boundary, rewarded, bits
$$;

create or replace function public.team_battle_session_payload(
  p_session public.team_battle_sessions
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_session.id,
    'player_team_id', p_session.player_team_id,
    'opponent_source', p_session.opponent_source,
    'player_snapshot', p_session.player_snapshot,
    'opponent_snapshot', p_session.opponent_snapshot,
    'state', p_session.state,
    'turn_number', p_session.turn_number,
    'version', p_session.version,
    'status', p_session.status,
    'created_at', p_session.created_at,
    'updated_at', p_session.updated_at,
    'expires_at', p_session.expires_at,
    'finished_at', p_session.finished_at,
    'item_used_id', p_session.item_used_id,
    'reward_tier', p_session.reward_tier,
    'reward_roll', p_session.reward_roll,
    'reward_bits', p_session.reward_bits,
    'daily_reward', public.team_battle_daily_reward_status(
      p_session.owner_id,
      p_session.id
    )
  )
$$;

create or replace function public.start_team_battle(
  p_owner uuid,
  p_player_team_id uuid,
  p_candidate_id uuid,
  p_player_snapshot jsonb,
  p_initial_state jsonb,
  p_seed text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.anima_teams;
  v_candidate public.team_battle_candidates;
  v_session public.team_battle_sessions;
  v_member record;
  v_energy numeric;
  v_energy_cost integer;
  v_active_anima_id uuid;
  v_sleep_started_at timestamptz;
  v_member_ids uuid[];
  v_snapshot_ids uuid[];
  v_state_player_ids uuid[];
  v_state_opponent_ids uuid[];
  v_opponent_ids uuid[];
begin
  if p_seed is null or length(p_seed) not between 1 and 128 then
    raise exception 'INVALID_SEED';
  end if;
  if p_initial_state->>'status' <> 'active'
     or coalesce((p_initial_state->>'turn')::integer, 0) <> 1 then
    raise exception 'INVALID_TEAM_BATTLE_STATE';
  end if;
  if jsonb_typeof(p_player_snapshot) <> 'array'
     or jsonb_array_length(p_player_snapshot) <> 4 then
    raise exception 'INVALID_TEAM_SNAPSHOT';
  end if;

  select active_anima_id into v_active_anima_id
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  update public.team_battle_sessions
     set status = 'forfeited', finished_at = now(), updated_at = now()
   where owner_id = p_owner and status = 'active' and expires_at <= now();
  select * into v_session
    from public.team_battle_sessions
   where owner_id = p_owner and status = 'active'
   order by created_at desc
   limit 1;
  if found then return public.team_battle_session_payload(v_session); end if;

  select * into v_team
    from public.anima_teams
   where id = p_player_team_id
     and owner_id = p_owner
     and kind = 'team_battle'
   for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;

  select * into v_candidate
    from public.team_battle_candidates
   where id = p_candidate_id
     and owner_id = p_owner
     and player_team_id = p_player_team_id
     and consumed_at is null
     and expires_at > now()
   for update;
  if not found then raise exception 'TEAM_CANDIDATE_EXPIRED'; end if;

  select array_agg(anima_id order by anima_id) into v_member_ids
    from public.anima_team_members where team_id = v_team.id;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_snapshot_ids from jsonb_array_elements(p_player_snapshot) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_state_player_ids
    from jsonb_array_elements(p_initial_state #> '{player,roster}') member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_opponent_ids
    from jsonb_array_elements(v_candidate.opponent_snapshot) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_state_opponent_ids
    from jsonb_array_elements(p_initial_state #> '{opponent,roster}') member;
  if cardinality(v_member_ids) <> 4
     or v_snapshot_ids is distinct from v_member_ids
     or v_state_player_ids is distinct from v_member_ids
     or v_state_opponent_ids is distinct from v_opponent_ids then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  v_energy_cost := greatest(0, least(100, coalesce((
    select (value #>> '{}')::integer from public.app_config
     where key = 'team_battle_energy_per_member'
  ), 10)));

  for v_member in
    select a.id
      from public.anima_team_members m
      join public.animas a on a.id = m.anima_id
     where m.team_id = v_team.id
     order by m.slot
  loop
    perform public.apply_care(p_owner, v_member.id, 'sync', null);
    select coalesce((care->>'energy')::numeric, 0), sleep_started_at
      into v_energy, v_sleep_started_at
      from public.animas
     where id = v_member.id
       and owner_id = p_owner
       and status = 'ready'
       and dormant_since is null
     for update;
    if not found then raise exception 'TEAM_MEMBER_UNAVAILABLE'; end if;
    if v_member.id = v_active_anima_id and v_sleep_started_at is not null then
      raise exception 'TEAM_MEMBER_SLEEPING';
    end if;
    if v_energy < v_energy_cost then raise exception 'TEAM_MEMBER_LOW_ENERGY'; end if;
    update public.animas
       set care = jsonb_set(
         care,
         '{energy}',
         to_jsonb(round(v_energy - v_energy_cost, 2))
       )
     where id = v_member.id;
  end loop;

  insert into public.team_battle_sessions (
    owner_id, player_team_id, opponent_source, opponent_team_id,
    player_snapshot, opponent_snapshot, state, rng_seed,
    reward_tier, reward_roll, reward_bits
  ) values (
    p_owner, v_team.id, v_candidate.opponent_source, v_candidate.opponent_team_id,
    p_player_snapshot, v_candidate.opponent_snapshot, p_initial_state, p_seed,
    v_candidate.reward_tier, v_candidate.reward_roll, v_candidate.reward_bits
  )
  returning * into v_session;

  update public.team_battle_candidates
     set consumed_at = now()
   where id = v_candidate.id;
  return public.team_battle_session_payload(v_session);
end $$;

create or replace function public.resume_team_battle(
  p_owner uuid,
  p_session_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.team_battle_sessions;
begin
  update public.team_battle_sessions
     set status = 'forfeited', finished_at = now(), updated_at = now()
   where owner_id = p_owner and status = 'active' and expires_at <= now();

  select * into v_session
    from public.team_battle_sessions
   where owner_id = p_owner
     and (p_session_id is null or id = p_session_id)
     and (p_session_id is not null or status = 'active')
   order by created_at desc
   limit 1;
  if not found then return null; end if;
  return public.team_battle_session_payload(v_session);
end $$;

create or replace function public.forfeit_team_battle(
  p_owner uuid,
  p_session_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.team_battle_sessions;
begin
  select * into v_session
    from public.team_battle_sessions
   where id = p_session_id and owner_id = p_owner
   for update;
  if not found then raise exception 'TEAM_BATTLE_NOT_FOUND'; end if;
  if v_session.status = 'active' then
    update public.team_battle_sessions
       set status = 'forfeited', finished_at = now(), updated_at = now()
     where id = v_session.id
    returning * into v_session;
  end if;
  return public.team_battle_session_payload(v_session);
end $$;

revoke all on function public.team_battle_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.team_battle_session_payload(public.team_battle_sessions)
  from public, anon, authenticated;
revoke all on function public.start_team_battle(uuid, uuid, uuid, jsonb, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.resume_team_battle(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.forfeit_team_battle(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.team_battle_daily_reward_status(uuid, uuid)
  to service_role;
grant execute on function public.team_battle_session_payload(public.team_battle_sessions)
  to service_role;
grant execute on function public.start_team_battle(uuid, uuid, uuid, jsonb, jsonb, text)
  to service_role;
grant execute on function public.resume_team_battle(uuid, uuid)
  to service_role;
grant execute on function public.forfeit_team_battle(uuid, uuid)
  to service_role;
