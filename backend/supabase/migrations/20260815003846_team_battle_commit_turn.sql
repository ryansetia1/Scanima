-- Reward receipt terpisah diperlukan karena progression win tetap harus
-- terhitung ketika Bits cap diset 0; quota_ledger melarang delta 0.
create table public.team_battle_rewards (
  session_id   uuid primary key references public.team_battle_sessions(id) on delete cascade,
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  progression boolean not null,
  bits         integer not null,
  created_at   timestamptz not null default now(),
  constraint team_battle_rewards_bits_valid check (bits between 0 and 16)
);

create index team_battle_rewards_owner_created_idx
  on public.team_battle_rewards (owner_id, created_at desc);

alter table public.team_battle_rewards enable row level security;
revoke all on public.team_battle_rewards from public, anon, authenticated;
grant all on public.team_battle_rewards to service_role;

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
  earned as (
    select
      count(*) filter (where r.progression)::integer as wins,
      coalesce(sum(r.bits), 0)::integer as bits
      from public.team_battle_rewards r
      cross join boundary b
     where r.owner_id = p_owner
       and r.created_at >= b.starts_at
       and r.created_at < b.reset_at
  )
  select jsonb_build_object(
    'earned', earned.wins,
    'limit', settings.reward_limit,
    'remaining', greatest(0, settings.reward_limit - earned.wins),
    'bits_earned', earned.bits,
    'bits_limit', settings.bits_limit,
    'bits_remaining', greatest(0, settings.bits_limit - earned.bits),
    'server_now', boundary.server_now,
    'reset_at', boundary.reset_at,
    'rewarded', exists (
      select 1 from public.team_battle_rewards r
       where p_session_id is not null
         and r.owner_id = p_owner
         and r.session_id = p_session_id
    ),
    'progression_rewarded', exists (
      select 1 from public.team_battle_rewards r
       where p_session_id is not null
         and r.owner_id = p_owner
         and r.session_id = p_session_id
         and r.progression
    )
  )
  from settings, boundary, earned
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
    'last_reward', (
      select jsonb_build_object(
        'bits', reward.bits,
        'progression', reward.progression
      )
        from public.team_battle_rewards reward
       where reward.session_id = p_session.id
    ),
    'daily_reward', public.team_battle_daily_reward_status(
      p_session.owner_id,
      p_session.id
    )
  )
$$;

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
    'bits', 0,
    'progression', false,
    'anima_exp', '[]'::jsonb,
    'capped', false
  );
  v_exp_rows jsonb := '[]'::jsonb;
  v_member jsonb;
  v_anima_id uuid;
  v_exp integer;
  v_active_exp integer;
  v_bench_exp integer;
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
  if p_action <> 'item' and p_item_id is not null then
    raise exception 'INVALID_ITEM';
  end if;
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

  if v_session.status <> 'active' then raise exception 'TEAM_BATTLE_FINISHED'; end if;
  if v_session.expires_at <= now() then
    update public.team_battle_sessions
       set status = 'forfeited', finished_at = now(), updated_at = now()
     where id = v_session.id
    returning * into v_session;
    return jsonb_build_object(
      'session', public.team_battle_session_payload(v_session),
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
    raise exception 'STALE_TEAM_BATTLE';
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
       select 1
         from jsonb_array_elements(
           (p_state #> '{player,roster}') || (p_state #> '{opponent,roster}')
         ) fighter
        where coalesce((fighter->>'hp')::integer, -1) < 0
           or coalesce((fighter->>'max_hp')::integer, 0) < 1
           or (fighter->>'hp')::integer > (fighter->>'max_hp')::integer
           or coalesce((fighter->>'momentum')::integer, -1) not between 0 and 5
           or coalesce((fighter->>'slot')::integer, -1) not between 0 and 3
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
      v_active_exp := greatest(0, least(100, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'team_battle_active_exp'
      ), 2)));
      v_bench_exp := greatest(0, least(v_active_exp, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'team_battle_bench_exp'
      ), 1)));
      v_winner_slot := (p_state #>> '{player,active_slot}')::integer;
      for v_member in select value from jsonb_array_elements(p_state #> '{player,roster}')
      loop
        v_anima_id := (v_member->>'anima_id')::uuid;
        v_exp := case when coalesce((v_member->>'participated')::boolean, false)
          then v_active_exp else v_bench_exp end;
        update public.animas
           set care_score = care_score + v_exp,
               battle_wins = battle_wins
                 + case when (v_member->>'slot')::integer = v_winner_slot
                     then 1 else 0 end
         where id = v_anima_id and owner_id = p_owner;
        if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;
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
        p_owner,
        'bits',
        v_payout,
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

create trigger team_battle_sessions_count_seeker_victory
after update of status on public.team_battle_sessions
for each row
when (old.status is distinct from 'won' and new.status = 'won')
execute function public.count_seeker_battle_victory();

revoke all on function public.team_battle_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.commit_team_battle_turn(
  uuid, uuid, integer, integer, text, text, smallint, text, jsonb, jsonb, jsonb
) from public, anon, authenticated;

grant execute on function public.team_battle_daily_reward_status(uuid, uuid)
  to service_role;
grant execute on function public.commit_team_battle_turn(
  uuid, uuid, integer, integer, text, text, smallint, text, jsonb, jsonb, jsonb
) to service_role;
