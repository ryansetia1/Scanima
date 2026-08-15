-- Compare chapter opponent rosters as text slugs, not UUIDs.
-- Player anima_id casts stay uuid.

create or replace function public.start_expedition_encounter(
  p_owner uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_node jsonb,
  p_player_snapshot jsonb,
  p_opponent_snapshot jsonb,
  p_initial_state jsonb,
  p_seed text,
  p_supplies_reward integer,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_encounter public.expedition_encounters;
  v_action public.expedition_run_actions;
  v_node_id text := p_node->>'id';
  v_kind text := p_node->>'kind';
  v_party_ids uuid[];
  v_snapshot_ids uuid[];
  v_state_ids uuid[];
begin
  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id or v_action.operation <> 'enter_node' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into v_encounter from public.expedition_encounters
     where run_id = p_run_id and node_id = v_node_id;
    return jsonb_build_object(
      'run', v_action.response,
      'encounter', public.expedition_encounter_payload(v_encounter),
      'replayed', true
    );
  end if;

  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  select * into v_encounter from public.expedition_encounters
   where run_id = p_run_id and status = 'active'
   order by created_at desc limit 1;
  if found then return jsonb_build_object(
    'run', public.expedition_run_payload(v_run),
    'encounter', public.expedition_encounter_payload(v_encounter)
  ); end if;
  if v_run.status <> 'active' or v_run.pending_node is not null
     or v_run.version <> p_expected_version then
    raise exception 'STALE_EXPEDITION';
  end if;
  if v_kind not in ('battle', 'elite', 'boss')
     or v_node_id is null
     or not (v_run.available_node_ids ? v_node_id)
     or not exists (
       select 1 from jsonb_array_elements(v_run.zone_map->'nodes') node
        where node->>'id' = v_node_id and node = p_node
     )
     or jsonb_typeof(p_player_snapshot) <> 'array'
     or jsonb_array_length(p_player_snapshot) <> 4
     or jsonb_typeof(p_opponent_snapshot) <> 'array'
     or jsonb_array_length(p_opponent_snapshot) not between 1 and 4
     or p_initial_state->>'status' <> 'active'
     or coalesce((p_initial_state->>'turn')::integer, 0) <> 1
     or jsonb_typeof(p_initial_state #> '{player,roster}') <> 'array'
     or jsonb_array_length(p_initial_state #> '{player,roster}') <> 4
     or jsonb_typeof(p_initial_state #> '{opponent,roster}') <> 'array'
     or jsonb_array_length(p_initial_state #> '{opponent,roster}') not between 1 and 4
     or p_supplies_reward < 0
     or p_seed is null or length(p_seed) not between 1 and 128 then
    raise exception 'INVALID_EXPEDITION_ENCOUNTER';
  end if;

  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_party_ids from jsonb_array_elements(v_run.party_state) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_snapshot_ids from jsonb_array_elements(p_player_snapshot) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_state_ids
    from jsonb_array_elements(p_initial_state #> '{player,roster}') member;
  if v_party_ids is distinct from v_snapshot_ids
     or v_party_ids is distinct from v_state_ids then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;
  if public.expedition_roster_ids(p_opponent_snapshot)
     is distinct from public.expedition_roster_ids(p_initial_state #> '{opponent,roster}')
  then raise exception 'SNAPSHOT_MISMATCH'; end if;
  if exists (
       select 1 from jsonb_array_elements(p_initial_state #> '{player,roster}') member
        where coalesce((member->>'momentum_max')::integer, 0) not between 3 and 5
           or coalesce((member->>'momentum')::integer, -1)
                <> (member->>'momentum_max')::integer
     ) or exists (
       select 1 from jsonb_array_elements(p_initial_state #> '{opponent,roster}') member
        where coalesce((member->>'momentum_max')::integer, 0) <> 3
           or coalesce((member->>'momentum')::integer, -1) <> 3
     ) then raise exception 'INVALID_EXPEDITION_PP'; end if;

  update public.expedition_runs set
    current_node_id = v_node_id,
    available_node_ids = '[]'::jsonb,
    pending_node = p_node,
    version = version + 1,
    updated_at = now()
  where id = v_run.id returning * into v_run;
  insert into public.expedition_encounters (
    run_id, owner_id, node_id, kind, player_snapshot, opponent_snapshot,
    state, rng_seed, supplies_reward
  ) values (
    v_run.id, p_owner, v_node_id, v_kind, p_player_snapshot, p_opponent_snapshot,
    p_initial_state, p_seed, p_supplies_reward
  ) returning * into v_encounter;
  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'enter_node',
    public.expedition_run_payload(v_run)
  );
  return jsonb_build_object(
    'run', public.expedition_run_payload(v_run),
    'encounter', public.expedition_encounter_payload(v_encounter),
    'replayed', false
  );
end $$;

create or replace function public.commit_expedition_turn(
  p_owner uuid,
  p_encounter_id uuid,
  p_expected_turn integer,
  p_expected_version integer,
  p_key text,
  p_action text,
  p_switch_to_slot smallint,
  p_item_id text,
  p_state jsonb,
  p_events jsonb,
  p_bot_action jsonb,
  p_next_node_ids jsonb,
  p_checkpoint boolean,
  p_chapter_complete boolean,
  p_retry_map jsonb,
  p_retry_seed text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_encounter public.expedition_encounters;
  v_turn public.expedition_encounter_turns;
  v_run public.expedition_runs;
  v_item public.catalog_items;
  v_status text;
  v_response jsonb;
  v_reward_status jsonb;
  v_reward jsonb := jsonb_build_object(
    'progression', false, 'supplies', 0, 'anima_exp', '[]'::jsonb
  );
  v_exp_rows jsonb := '[]'::jsonb;
  v_member jsonb;
  v_anima_id uuid;
  v_exp integer;
  v_active_exp integer;
  v_bench_exp integer;
  v_progression boolean := false;
  v_snapshot_ids uuid[];
  v_state_ids uuid[];
  v_chapter_id uuid;
  v_trophy public.expedition_trophies;
  v_first_clear boolean := false;
  v_clear_bits integer := 0;
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
  if jsonb_typeof(p_events) <> 'array'
     or jsonb_typeof(p_next_node_ids) <> 'array' then
    raise exception 'INVALID_EVENTS';
  end if;

  select * into v_encounter from public.expedition_encounters
   where id = p_encounter_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_ENCOUNTER_NOT_FOUND'; end if;
  select * into v_turn from public.expedition_encounter_turns
   where encounter_id = p_encounter_id and idempotency_key = p_key;
  if found then
    if v_turn.turn_number <> p_expected_turn
       or v_turn.action <> p_action
       or v_turn.switch_to_slot is distinct from p_switch_to_slot
       or v_turn.catalog_item_id is distinct from p_item_id then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_turn.response || jsonb_build_object('replayed', true);
  end if;
  if v_encounter.status <> 'active' then raise exception 'EXPEDITION_ENCOUNTER_FINISHED'; end if;
  if v_encounter.expires_at <= now() then raise exception 'EXPEDITION_ENCOUNTER_EXPIRED'; end if;
  if v_encounter.turn_number <> p_expected_turn
     or v_encounter.version <> p_expected_version then
    raise exception 'STALE_EXPEDITION_ENCOUNTER';
  end if;

  v_status := p_state->>'status';
  if v_status not in ('active', 'won', 'lost', 'draw')
     or coalesce((p_state->>'turn')::integer, 0) <> p_expected_turn + 1
     or jsonb_typeof(p_state #> '{player,roster}') <> 'array'
     or jsonb_array_length(p_state #> '{player,roster}') <> 4
     or jsonb_typeof(p_state #> '{opponent,roster}') <> 'array'
     or jsonb_array_length(p_state #> '{opponent,roster}') not between 1 and 4
     or coalesce((p_state #>> '{player,active_slot}')::integer, -1) not between 0 and 3
     or coalesce((p_state #>> '{opponent,active_slot}')::integer, -1)
          not between 0 and jsonb_array_length(p_state #> '{opponent,roster}') - 1
     or exists (
       select 1 from jsonb_array_elements(
         (p_state #> '{player,roster}') || (p_state #> '{opponent,roster}')
       ) fighter
       where coalesce((fighter->>'hp')::integer, -1) < 0
          or coalesce((fighter->>'max_hp')::integer, 0) < 1
          or (fighter->>'hp')::integer > (fighter->>'max_hp')::integer
     ) then raise exception 'INVALID_TEAM_BATTLE_STATE'; end if;

  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_snapshot_ids
    from jsonb_array_elements(v_encounter.player_snapshot) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_state_ids from jsonb_array_elements(p_state #> '{player,roster}') member;
  if v_state_ids is distinct from v_snapshot_ids then raise exception 'SNAPSHOT_MISMATCH'; end if;
  if public.expedition_roster_ids(v_encounter.opponent_snapshot)
     is distinct from public.expedition_roster_ids(p_state #> '{opponent,roster}')
  then raise exception 'SNAPSHOT_MISMATCH'; end if;

  if p_action = 'item' then
    if v_encounter.item_used_id is not null then raise exception 'ITEM_ALREADY_USED'; end if;
    select * into v_item from public.catalog_items
     where id = p_item_id and active and use_type = 'battle';
    if not found then raise exception 'INVALID_ITEM'; end if;
    perform public._consume_inventory(p_owner, p_item_id);
  end if;

  update public.expedition_encounters set
    state = p_state,
    turn_number = p_expected_turn + 1,
    version = version + 1,
    status = v_status,
    item_used_id = case when p_action = 'item' then p_item_id else item_used_id end,
    updated_at = now(),
    finished_at = case when v_status = 'active' then null else now() end
  where id = v_encounter.id returning * into v_encounter;
  select * into v_run from public.expedition_runs
   where id = v_encounter.run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  if v_status = 'won' and (
       p_next_node_ids <> coalesce(v_run.pending_node->'next', '[]'::jsonb)
       or p_chapter_complete is distinct from (
         v_encounter.kind = 'boss' and v_run.zone = 3
       )
       or p_checkpoint is distinct from (
         not p_chapter_complete
         and v_run.zone < 3
         and jsonb_array_length(coalesce(v_run.pending_node->'next', '[]'::jsonb)) = 0
         and v_run.nodes_completed = 3
       )
     ) then raise exception 'INVALID_EXPEDITION_PROGRESS'; end if;

  if v_status = 'won' and v_encounter.rewarded_at is null then
    perform 1 from public.profiles where id = p_owner for update;
    if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
    v_reward_status := public.expedition_daily_reward_status(p_owner, v_encounter.id);
    v_progression := (v_reward_status->>'remaining')::integer > 0;
    if v_progression then
      v_active_exp := greatest(0, least(100, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'expedition_active_exp'
      ), 2)));
      v_bench_exp := greatest(0, least(v_active_exp, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'expedition_bench_exp'
      ), 1)));
      for v_member in select value from jsonb_array_elements(p_state #> '{player,roster}')
      loop
        v_anima_id := (v_member->>'anima_id')::uuid;
        v_exp := case when coalesce((v_member->>'participated')::boolean, false)
          then v_active_exp else v_bench_exp end;
        update public.animas set care_score = care_score + v_exp
         where id = v_anima_id and owner_id = p_owner;
        if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;
        v_exp_rows := v_exp_rows || jsonb_build_array(jsonb_build_object(
          'anima_id', v_anima_id,
          'exp', v_exp,
          'participated', coalesce((v_member->>'participated')::boolean, false)
        ));
      end loop;
    end if;
    insert into public.expedition_encounter_rewards (
      encounter_id, owner_id, progression, supplies
    ) values (
      v_encounter.id, p_owner, v_progression, v_encounter.supplies_reward
    );
    v_reward := jsonb_build_object(
      'progression', v_progression,
      'supplies', v_encounter.supplies_reward,
      'anima_exp', v_exp_rows
    );
    update public.expedition_encounters set rewarded_at = now()
     where id = v_encounter.id returning * into v_encounter;

    if p_chapter_complete then
      if v_encounter.kind <> 'boss' or v_run.zone <> 3 then
        raise exception 'INVALID_CHAPTER_COMPLETION';
      end if;
      select version.chapter_id into v_chapter_id
        from public.expedition_chapter_versions version
       where version.id = v_run.chapter_version_id;
      select first_cleared_at is null into v_first_clear
        from public.expedition_progress
       where owner_id = p_owner and chapter_id = v_chapter_id
       for update;
      update public.expedition_progress set
        first_cleared_at = coalesce(first_cleared_at, now()),
        clear_count = clear_count + 1,
        best_run_at = now()
      where owner_id = p_owner and chapter_id = v_chapter_id;
      if v_first_clear then
        select * into v_trophy from public.expedition_trophies
         where chapter_id = v_chapter_id;
        if not found then raise exception 'TROPHY_NOT_CONFIGURED'; end if;
        insert into public.seeker_trophies (owner_id, trophy_id, run_id)
        values (p_owner, v_trophy.id, v_run.id) on conflict do nothing;
        v_clear_bits := greatest(0, least(1000, coalesce((
          select (value #>> '{}')::integer from public.app_config
           where key = 'expedition_first_clear_bits'
        ), 25)));
        if v_clear_bits > 0 then
          perform 1 from public.profiles where id = p_owner for update;
          update public.profiles set bits = bits + v_clear_bits where id = p_owner;
          insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
          values (p_owner, 'bits', v_clear_bits, 'expedition_clear', v_run.id);
        end if;
        insert into public.expedition_progress (owner_id, chapter_id)
        select p_owner, next_chapter.id
          from public.expedition_chapters current_chapter
          join public.expedition_chapters next_chapter
            on next_chapter.sequence = current_chapter.sequence + 1
         where current_chapter.id = v_chapter_id
        on conflict do nothing;
      end if;
      update public.expedition_runs set
        status = 'complete',
        version = version + 1,
        party_state = public.expedition_party_after_encounter(
          v_encounter.player_snapshot,
          p_state
        ),
        supplies = supplies + v_encounter.supplies_reward,
        current_node_id = null,
        pending_node = null,
        available_node_ids = '[]'::jsonb,
        completed_at = now(),
        updated_at = now()
      where id = v_run.id returning * into v_run;
      v_reward := v_reward || jsonb_build_object(
        'first_clear', v_first_clear,
        'clear_bits', v_clear_bits,
        'trophy', case when v_first_clear then to_jsonb(v_trophy) else null end
      );
    else
      if p_checkpoint and v_run.nodes_completed <> 3 then
        raise exception 'INVALID_EXPEDITION_CHECKPOINT';
      end if;
      update public.expedition_runs set
        status = case when p_checkpoint then 'checkpoint' else status end,
        zone = case when p_checkpoint then least(3, zone + 1) else zone end,
        version = version + 1,
        nodes_completed = nodes_completed + 1,
        party_state = public.expedition_party_after_encounter(
          v_encounter.player_snapshot,
          p_state
        ),
        supplies = supplies + v_encounter.supplies_reward,
        available_node_ids = case when p_checkpoint then '[]'::jsonb else p_next_node_ids end,
        current_node_id = null,
        pending_node = null,
        zone_map = case when p_checkpoint then null else zone_map end,
        updated_at = now()
      where id = v_run.id returning * into v_run;
    end if;
  elsif v_status in ('lost', 'draw') then
    v_run := public.reset_expedition_zone(v_run, p_retry_map, p_retry_seed);
  end if;

  v_response := jsonb_build_object(
    'run', public.expedition_run_payload(v_run),
    'encounter', public.expedition_encounter_payload(v_encounter),
    'events', p_events,
    'bot_action', p_bot_action,
    'reward', v_reward,
    'replayed', false
  );
  insert into public.expedition_encounter_turns (
    encounter_id, turn_number, idempotency_key, action,
    switch_to_slot, catalog_item_id, response
  ) values (
    v_encounter.id, p_expected_turn, p_key, p_action,
    p_switch_to_slot, p_item_id, v_response
  );
  return v_response;
end $$;

