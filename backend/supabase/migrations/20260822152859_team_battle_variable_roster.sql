-- Team Battle and Defense accept 2-4 Anima. Expedition remains exactly 4.
-- Existing four-member sessions stay valid and finish under the same resolver.

alter table public.team_battle_sessions
  drop constraint team_battle_sessions_snapshots_valid;
alter table public.team_battle_sessions
  add constraint team_battle_sessions_snapshots_valid check (
    jsonb_typeof(player_snapshot) = 'array'
    and jsonb_array_length(player_snapshot) between 2 and 4
    and jsonb_typeof(opponent_snapshot) = 'array'
    and jsonb_array_length(opponent_snapshot) between 1 and 4
  );

create or replace function public.save_anima_team(
  p_owner uuid,
  p_kind text,
  p_anima_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.anima_teams;
  v_count integer;
  v_team_size integer;
begin
  if p_kind not in ('team_battle', 'expedition', 'defense') then
    raise exception 'INVALID_TEAM_KIND';
  end if;
  v_team_size := coalesce(cardinality(p_anima_ids), 0);
  if p_kind = 'expedition' then
    if v_team_size <> 4
       or (select count(distinct id) from unnest(p_anima_ids) as id) <> 4 then
      raise exception 'TEAM_REQUIRES_FOUR';
    end if;
  elsif v_team_size not between 2 and 4
        or (select count(distinct id) from unnest(p_anima_ids) as id) <> v_team_size then
    raise exception 'TEAM_REQUIRES_TWO_TO_FOUR';
  end if;

  perform 1
    from public.animas
   where owner_id = p_owner and id = any(p_anima_ids)
   for update;
  select count(*) into v_count
    from public.animas
   where owner_id = p_owner
     and id = any(p_anima_ids)
     and status = 'ready';
  if v_count <> v_team_size then raise exception 'TEAM_MEMBER_NOT_READY'; end if;

  insert into public.anima_teams (owner_id, kind)
  values (p_owner, p_kind)
  on conflict (owner_id, kind) do update
    set published = false,
        snapshot = null,
        published_at = null,
        updated_at = now()
  returning * into v_team;

  delete from public.team_battle_candidates
   where player_team_id = v_team.id or opponent_team_id = v_team.id;
  delete from public.anima_team_members where team_id = v_team.id;
  insert into public.anima_team_members (team_id, slot, anima_id)
  select v_team.id, ordinality - 1, anima_id
    from unnest(p_anima_ids) with ordinality as roster(anima_id, ordinality);

  select * into v_team from public.anima_teams where id = v_team.id;
  return public.anima_team_payload(v_team);
end $$;

create or replace function public.publish_defense_team(
  p_owner uuid,
  p_snapshot jsonb,
  p_publish boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.anima_teams;
  v_member_ids uuid[];
  v_snapshot_ids uuid[];
  v_clean_snapshot jsonb;
begin
  select * into v_team
    from public.anima_teams
   where owner_id = p_owner and kind = 'defense'
   for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;

  if not coalesce(p_publish, false) then
    delete from public.team_battle_candidates where opponent_team_id = v_team.id;
    update public.anima_teams
       set published = false,
           snapshot = null,
           published_at = null,
           updated_at = now()
     where id = v_team.id
    returning * into v_team;
    return public.anima_team_payload(v_team);
  end if;

  if jsonb_typeof(p_snapshot) <> 'array'
     or jsonb_array_length(p_snapshot) not between 2 and 4
     or exists (
       select 1
         from jsonb_array_elements(p_snapshot) member
        where jsonb_typeof(member->'anima_id') <> 'string'
           or (member->>'anima_id') !~
              '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
     ) then
    raise exception 'INVALID_TEAM_SNAPSHOT';
  end if;

  select array_agg(anima_id order by anima_id) into v_member_ids
    from public.anima_team_members
   where team_id = v_team.id;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid),
         jsonb_agg(member - 'owner_id' - 'nickname' - 'sheet_url')
    into v_snapshot_ids, v_clean_snapshot
    from jsonb_array_elements(p_snapshot) member;
  if cardinality(v_member_ids) not between 2 and 4
     or v_snapshot_ids is distinct from v_member_ids then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  delete from public.team_battle_candidates where opponent_team_id = v_team.id;
  update public.anima_teams
     set published = true,
         snapshot = v_clean_snapshot,
         published_at = now(),
         updated_at = now()
   where id = v_team.id
  returning * into v_team;
  return public.anima_team_payload(v_team);
end $$;

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
     or jsonb_array_length(p_player_snapshot) not between 2 and 4 then
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
  if cardinality(v_member_ids) not between 2 and 4
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

create or replace function public.commit_team_battle_turn(
  p_owner uuid,
  p_session_id uuid,
  p_expected_turn integer,
  p_expected_version integer,
  p_key text,
  p_action text,
  p_switch_to_slot smallint,
  p_item_id text,
  p_state jsonb,
  p_events jsonb,
  p_bot_action jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.team_battle_sessions;
  v_turn public.team_battle_turns;
  v_item public.catalog_items;
  v_status text;
  v_response jsonb;
  v_reward_status jsonb;
  v_reward jsonb := jsonb_build_object(
    'bits', 0, 'progression', false, 'anima_exp', '[]'::jsonb, 'capped', false
  );
  v_exp_rows jsonb := '[]'::jsonb;
  v_member jsonb;
  v_anima_id uuid;
  v_exp integer;
  v_full_exp integer;
  v_active_exp integer;
  v_bench_exp integer;
  v_recipient_level integer;
  v_opponent_level integer;
  v_score_before integer;
  v_score_after integer;
  v_winner_slot integer;
  v_payout integer := 0;
  v_progression boolean := false;
  v_snapshot_ids uuid[];
  v_state_ids uuid[];
begin
  if p_action not in ('strike', 'surge', 'guard', 'item', 'switch') then
    raise exception 'INVALID_ACTION';
  end if;
  if p_action = 'switch' and p_switch_to_slot not between 0 and 3 then
    raise exception 'INVALID_SWITCH_SLOT';
  end if;
  if p_action <> 'switch' and p_switch_to_slot is not null then
    raise exception 'INVALID_SWITCH_SLOT';
  end if;
  if p_action = 'item' and (p_item_id is null or length(p_item_id) = 0) then
    raise exception 'INVALID_ITEM';
  end if;
  if p_action <> 'item' and p_item_id is not null then raise exception 'INVALID_ITEM'; end if;
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;
  if jsonb_typeof(p_events) <> 'array' then raise exception 'INVALID_EVENTS'; end if;

  select * into v_session
    from public.team_battle_sessions
   where id = p_session_id and owner_id = p_owner
   for update;
  if not found then raise exception 'TEAM_BATTLE_NOT_FOUND'; end if;

  select * into v_turn
    from public.team_battle_turns
   where session_id = p_session_id and idempotency_key = p_key;
  if found then
    if v_turn.turn_number <> p_expected_turn
       or v_turn.action <> p_action
       or v_turn.switch_to_slot is distinct from p_switch_to_slot
       or v_turn.catalog_item_id is distinct from p_item_id then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_turn.response || jsonb_build_object('replayed', true);
  end if;

  if p_action = 'switch'
     and p_switch_to_slot >= jsonb_array_length(v_session.player_snapshot) then
    raise exception 'INVALID_SWITCH_SLOT';
  end if;
  if v_session.status <> 'active' then raise exception 'TEAM_BATTLE_FINISHED'; end if;
  if v_session.expires_at <= now() then
    update public.team_battle_sessions
       set status = 'forfeited', finished_at = now(), updated_at = now()
     where id = v_session.id
    returning * into v_session;
    return jsonb_build_object(
      'session', public.team_battle_session_payload(v_session),
      'events', jsonb_build_array(jsonb_build_object('type', 'finished', 'result', 'forfeited')),
      'bot_action', null,
      'reward', v_reward,
      'replayed', false
    );
  end if;
  if v_session.turn_number <> p_expected_turn
     or v_session.version <> p_expected_version then
    raise exception 'STALE_TEAM_BATTLE';
  end if;

  v_status := p_state->>'status';
  if v_status not in ('active', 'won', 'lost', 'draw')
     or coalesce((p_state->>'turn')::integer, 0) <> p_expected_turn + 1
     or jsonb_typeof(p_state #> '{player,roster}') <> 'array'
     or jsonb_array_length(p_state #> '{player,roster}') not between 2 and 4
     or jsonb_typeof(p_state #> '{opponent,roster}') <> 'array'
     or jsonb_array_length(p_state #> '{opponent,roster}') not between 1 and 4
     or coalesce((p_state #>> '{player,active_slot}')::integer, -1)
          not between 0 and jsonb_array_length(p_state #> '{player,roster}') - 1
     or coalesce((p_state #>> '{opponent,active_slot}')::integer, -1)
          not between 0 and jsonb_array_length(p_state #> '{opponent,roster}') - 1
     or exists (
       select 1
         from jsonb_array_elements(
           (p_state #> '{player,roster}') || (p_state #> '{opponent,roster}')
         ) fighter
        where coalesce((fighter->>'hp')::integer, -1) < 0
           or coalesce((fighter->>'max_hp')::integer, 0) < 1
           or (fighter->>'hp')::integer > (fighter->>'max_hp')::integer
           or coalesce((fighter->>'momentum')::integer, -1) not between 0 and 5
           or coalesce((fighter->>'slot')::integer, -1) not between 0 and 3
     )
     or exists (
       select 1 from jsonb_array_elements(p_state #> '{player,roster}') fighter
        where coalesce((fighter->>'slot')::integer, -1)
              not between 0 and jsonb_array_length(p_state #> '{player,roster}') - 1
     )
     or exists (
       select 1 from jsonb_array_elements(p_state #> '{opponent,roster}') fighter
        where coalesce((fighter->>'slot')::integer, -1)
              not between 0 and jsonb_array_length(p_state #> '{opponent,roster}') - 1
     ) then
    raise exception 'INVALID_TEAM_BATTLE_STATE';
  end if;

  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_snapshot_ids
    from jsonb_array_elements(v_session.player_snapshot) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_state_ids
    from jsonb_array_elements(p_state #> '{player,roster}') member;
  if v_state_ids is distinct from v_snapshot_ids then raise exception 'SNAPSHOT_MISMATCH'; end if;

  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_snapshot_ids
    from jsonb_array_elements(v_session.opponent_snapshot) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_state_ids
    from jsonb_array_elements(p_state #> '{opponent,roster}') member;
  if v_state_ids is distinct from v_snapshot_ids then raise exception 'SNAPSHOT_MISMATCH'; end if;

  if p_action = 'item' then
    if v_session.item_used_id is not null then raise exception 'ITEM_ALREADY_USED'; end if;
    select * into v_item
      from public.catalog_items
     where id = p_item_id and active and use_type = 'battle';
    if not found then raise exception 'INVALID_ITEM'; end if;
    perform public._consume_inventory(p_owner, p_item_id);
  end if;

  update public.team_battle_sessions
     set state = p_state,
         turn_number = p_expected_turn + 1,
         version = version + 1,
         status = v_status,
         item_used_id = case when p_action = 'item' then p_item_id else item_used_id end,
         updated_at = now(),
         finished_at = case when v_status = 'active' then null else now() end
   where id = v_session.id
  returning * into v_session;

  if v_status = 'won' and v_session.rewarded_at is null then
    perform 1 from public.profiles where id = p_owner for update;
    if not found then raise exception 'NO_PROFILE'; end if;
    v_reward_status := public.team_battle_daily_reward_status(p_owner, v_session.id);
    v_payout := least(
      v_session.reward_bits,
      greatest(0, (v_reward_status->>'bits_remaining')::integer)
    );
    v_progression := (v_reward_status->>'remaining')::integer > 0;

    if v_progression then
      select greatest(1, least(40, round(avg(
               coalesce((member->>'level')::integer, 1)
             ))::integer))
        into v_opponent_level
        from jsonb_array_elements(v_session.opponent_snapshot) member;
      v_winner_slot := (p_state #>> '{player,active_slot}')::integer;

      for v_member in select value from jsonb_array_elements(p_state #> '{player,roster}')
      loop
        v_anima_id := (v_member->>'anima_id')::uuid;
        select coalesce((snapshot->>'level')::integer, 1)
          into v_recipient_level
          from jsonb_array_elements(v_session.player_snapshot) snapshot
         where snapshot->>'anima_id' = v_anima_id::text;
        if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;

        v_full_exp := public.battle_exp_yield(
          v_recipient_level, v_opponent_level, v_session.reward_tier
        );
        v_active_exp := (v_full_exp + 1) / 2;
        v_bench_exp := (v_full_exp + 3) / 4;
        v_exp := public.party_member_reward_exp(v_member, v_active_exp, v_bench_exp);

        select care_score into v_score_before
          from public.animas
         where id = v_anima_id and owner_id = p_owner
         for update;
        if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;
        update public.animas
           set care_score = care_score + v_exp,
               battle_wins = battle_wins
                 + case when (v_member->>'slot')::integer = v_winner_slot
                     then 1 else 0 end
         where id = v_anima_id and owner_id = p_owner
        returning care_score into v_score_after;
        v_exp := v_score_after - v_score_before;

        v_exp_rows := v_exp_rows || jsonb_build_array(jsonb_build_object(
          'anima_id', v_anima_id,
          'exp', v_exp,
          'participated', coalesce((v_member->>'participated')::boolean, false)
        ));
      end loop;
    end if;

    if v_payout > 0 then
      update public.profiles set bits = bits + v_payout where id = p_owner;
      insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
      values (
        p_owner, 'bits', v_payout,
        case when v_progression then 'team_battle_win' else 'team_battle_train' end,
        v_session.id
      );
    end if;
    insert into public.team_battle_rewards (session_id, owner_id, progression, bits)
    values (v_session.id, p_owner, v_progression, v_payout);

    v_reward := jsonb_build_object(
      'bits', v_payout,
      'progression', v_progression,
      'anima_exp', v_exp_rows,
      'capped', not v_progression and v_payout = 0
    );
    update public.team_battle_sessions
       set rewarded_at = now()
     where id = v_session.id
    returning * into v_session;
  end if;

  v_response := jsonb_build_object(
    'session', public.team_battle_session_payload(v_session),
    'events', p_events,
    'bot_action', p_bot_action,
    'reward', v_reward,
    'replayed', false
  );
  insert into public.team_battle_turns (
    session_id, turn_number, idempotency_key, action,
    switch_to_slot, catalog_item_id, response
  ) values (
    v_session.id, p_expected_turn, p_key, p_action,
    p_switch_to_slot, p_item_id, v_response
  );
  return v_response;
end $$;

revoke all on function public.save_anima_team(uuid, text, uuid[])
  from public, anon, authenticated;
revoke all on function public.publish_defense_team(uuid, jsonb, boolean)
  from public, anon, authenticated;
revoke all on function public.start_team_battle(uuid, uuid, uuid, jsonb, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.commit_team_battle_turn(
  uuid, uuid, integer, integer, text, text, smallint, text, jsonb, jsonb, jsonb
) from public, anon, authenticated;

grant execute on function public.save_anima_team(uuid, text, uuid[]) to service_role;
grant execute on function public.publish_defense_team(uuid, jsonb, boolean) to service_role;
grant execute on function public.start_team_battle(uuid, uuid, uuid, jsonb, jsonb, text)
  to service_role;
grant execute on function public.commit_team_battle_turn(
  uuid, uuid, integer, integer, text, text, smallint, text, jsonb, jsonb, jsonb
) to service_role;
