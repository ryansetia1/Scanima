-- Tiered Anima progression, level-scaled Battle EXP, and bounded Expedition
-- progression. care_score remains the stored total EXP; Level is derived.

create or replace function public.anima_exp_to_next(p_level integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when greatest(1, least(40, coalesce(p_level, 1))) >= 40 then 0
    else 5 * ceil(greatest(1, least(40, coalesce(p_level, 1))) / 5.0)::integer
  end
$$;

create or replace function public.anima_exp_for_level(p_level integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  with progress as (
    select greatest(0, least(39, coalesce(p_level, 1) - 1)) as steps
  ), bands as (
    select steps, steps / 5 as complete_bands, steps % 5 as remaining_steps
      from progress
  )
  select (
    25 * complete_bands * (complete_bands + 1) / 2
    + remaining_steps * 5 * (complete_bands + 1)
  )::integer
  from bands
$$;

create or replace function public.anima_level_from_exp(p_exp integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce(max(level), 1)
    from generate_series(1, 40) as levels(level)
   where public.anima_exp_for_level(level) <= greatest(0, coalesce(p_exp, 0))
$$;

create or replace function public.anima_exp_clamped(p_exp integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select greatest(0, least(public.anima_exp_for_level(40), coalesce(p_exp, 0)))
$$;

create or replace function public.battle_exp_yield(
  p_recipient_level integer,
  p_opponent_level integer,
  p_difficulty text
) returns integer
language sql
immutable
set search_path = ''
as $$
  select greatest(1, least(8,
    1 + ceil(greatest(1, least(40, coalesce(p_opponent_level, 1))) / 10.0)::integer
    + least(2, greatest(
        0,
        greatest(1, least(40, coalesce(p_opponent_level, 1)))
          - greatest(1, least(40, coalesce(p_recipient_level, 1)))
      ) / 5)
    + case when p_difficulty in ('tough', 'formidable', 'elite', 'boss') then 1 else 0 end
  ))
$$;

revoke all on function public.anima_exp_to_next(integer)
  from public, anon, authenticated;
revoke all on function public.anima_exp_for_level(integer)
  from public, anon, authenticated;
revoke all on function public.anima_level_from_exp(integer)
  from public, anon, authenticated;
revoke all on function public.anima_exp_clamped(integer)
  from public, anon, authenticated;
revoke all on function public.battle_exp_yield(integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.anima_exp_to_next(integer) to service_role;
grant execute on function public.anima_exp_for_level(integer) to service_role;
grant execute on function public.anima_level_from_exp(integer) to service_role;
grant execute on function public.anima_exp_clamped(integer) to service_role;
grant execute on function public.battle_exp_yield(integer, integer, text) to service_role;

alter table public.animas
  add column sleep_exp_on date;

alter table public.expedition_encounter_rewards
  add column anima_exp_total integer not null default 0,
  add constraint expedition_reward_exp_nonnegative check (anima_exp_total >= 0);

alter table public.expedition_runs
  add column boss_exp_awarded_at timestamptz;

insert into public.app_config (key, value)
values ('expedition_daily_exp_budget', '30'::jsonb)
on conflict (key) do update set value = excluded.value;

-- Preserve the old Level and fractional 0..4 progress without turning this
-- administrative rebase into earned Seeker EXP.
alter table public.animas disable trigger animas_mirror_seeker_xp;
update public.animas
   set care_score = case
     when care_score >= 195 then public.anima_exp_for_level(40)
     else public.anima_exp_for_level(1 + greatest(0, care_score) / 5)
       + floor(
           (greatest(0, care_score) % 5)::numeric
           * public.anima_exp_to_next(1 + greatest(0, care_score) / 5)
           / 5.0
         )::integer
   end;
alter table public.animas enable trigger animas_mirror_seeker_xp;

create or replace function public.clamp_anima_care_score()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.care_score := public.anima_exp_clamped(new.care_score);
  return new;
end $$;

create trigger animas_clamp_care_score
before insert or update of care_score on public.animas
for each row execute function public.clamp_anima_care_score();

revoke all on function public.clamp_anima_care_score()
  from public, anon, authenticated;

-- Full sleep still restores Energy on every completed cycle, but only the first
-- six-hour cycle per local day grants EXP.
create or replace function public.apply_care(
  p_owner uuid,
  p_anima_id uuid,
  p_action text,
  p_key text default null,
  p_item_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anima              public.animas;
  v_event              public.care_events;
  v_event_id           uuid;
  v_replayed           bool := false;
  v_now                timestamptz := now();
  v_tz_offset          int := 0;
  v_today              date;
  v_elapsed_hours      double precision;
  v_effective_hours    double precision;
  v_sleep_hours        double precision;
  v_sleep_full_hours   double precision;
  v_hunger             double precision;
  v_energy             double precision;
  v_hygiene            double precision;
  v_pre_action_need     double precision;
  v_bits                int;
  v_bits_cost           int := 0;
  v_score_before        int;
  v_score_delta         int := 0;
  v_sleep_completed     bool := false;
  v_active_id           uuid;
  v_benched             bool := false;
  v_item                public.catalog_items;
begin
  if p_action not in ('sync', 'feed', 'clean', 'sleep', 'wake', 'play', 'summon', 'use_item') then
    raise exception 'UNKNOWN_ACTION';
  end if;

  if p_action <> 'sync' and (p_key is null or length(p_key) not between 1 and 128) then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  if p_action in ('feed', 'use_item') then
    if p_item_id is null or length(p_item_id) = 0 then
      raise exception 'INVALID_ITEM';
    end if;
  elsif p_item_id is not null then
    raise exception 'INVALID_ITEM';
  end if;

  if p_action <> 'sync' then
    begin
      insert into public.care_events (owner_id, anima_id, idempotency_key, action, catalog_item_id)
      values (p_owner, p_anima_id, p_key, p_action, p_item_id)
      returning * into v_event;
      v_event_id := v_event.id;
    exception
      when unique_violation then
        select * into v_event
          from public.care_events
         where owner_id = p_owner and idempotency_key = p_key;
        if not found
           or v_event.anima_id <> p_anima_id
           or v_event.action <> p_action
           or v_event.catalog_item_id is distinct from p_item_id then
          raise exception 'IDEMPOTENCY_CONFLICT';
        end if;
        v_event_id := v_event.id;
        v_replayed := true;
    end;
  end if;

  select * into v_anima
    from public.animas
   where id = p_anima_id and owner_id = p_owner
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_anima.status <> 'ready' then raise exception 'ANIMA_NOT_READY'; end if;

  select bits, active_anima_id, timezone_offset_minutes
    into v_bits, v_active_id, v_tz_offset
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  v_today := public.local_civil_date(v_now, coalesce(v_tz_offset, 0));

  if v_active_id is null then
    update public.profiles
       set active_anima_id = p_anima_id
     where id = p_owner;
    v_active_id := p_anima_id;
    update public.animas
       set sleep_started_at = coalesce(sleep_started_at, care_synced_at, v_now),
           sleep_energy_at_start = coalesce(
             sleep_energy_at_start,
             least(100.0, greatest(0.0, coalesce((care->>'energy')::double precision, 0.0)))
           )
     where owner_id = p_owner
       and status = 'ready'
       and id is distinct from p_anima_id
       and sleep_started_at is null;
  end if;

  v_benched := v_anima.id is distinct from v_active_id;

  v_hunger := greatest(0.0, least(100.0, coalesce((v_anima.care->>'hunger')::double precision, 0.0)));
  v_energy := greatest(0.0, least(100.0, coalesce((v_anima.care->>'energy')::double precision, 0.0)));
  v_hygiene := greatest(0.0, least(100.0, coalesce((v_anima.care->>'hygiene')::double precision, 0.0)));
  v_score_before := v_anima.care_score;

  if v_benched and v_anima.sleep_started_at is null then
    v_anima.sleep_started_at := coalesce(v_anima.care_synced_at, v_now);
    v_anima.sleep_energy_at_start := v_energy;
  end if;

  v_elapsed_hours := greatest(
    0.0,
    extract(epoch from (v_now - v_anima.care_synced_at)) / 3600.0
  );
  v_effective_hours := least(48.0, v_elapsed_hours);

  if v_benched then
    if v_hunger >= 40.0 then
      v_hunger := greatest(40.0, v_hunger - 1.0 * v_effective_hours);
    else
      v_hunger := greatest(0.0, v_hunger - 1.0 * v_effective_hours);
    end if;
    if v_hygiene >= 50.0 then
      v_hygiene := greatest(50.0, v_hygiene - 1.05 * v_effective_hours);
    else
      v_hygiene := greatest(0.0, v_hygiene - 1.05 * v_effective_hours);
    end if;
  else
    v_hunger := greatest(0.0, v_hunger - 4.0 * v_effective_hours);
    v_hygiene := greatest(0.0, v_hygiene - 4.2 * v_effective_hours);
  end if;

  if v_anima.sleep_started_at is null then
    v_energy := greatest(0.0, v_energy - 7.1 * v_effective_hours);
  else
    v_sleep_hours := greatest(
      0.0,
      extract(epoch from (v_now - v_anima.sleep_started_at)) / 3600.0
    );
    v_sleep_full_hours := case when v_benched then 3.0 else 6.0 end;
    v_energy := least(
      100.0,
      coalesce(v_anima.sleep_energy_at_start, v_energy)
      + (100.0 - coalesce(v_anima.sleep_energy_at_start, v_energy))
        * least(1.0, v_sleep_hours / v_sleep_full_hours)
    );
    if v_sleep_hours >= 6.0 and not v_benched then
      v_anima.sleep_started_at := null;
      v_anima.sleep_energy_at_start := null;
      if v_anima.sleep_exp_on is distinct from v_today then
        v_anima.care_score := v_anima.care_score + 5;
        v_anima.sleep_exp_on := v_today;
      end if;
      v_sleep_completed := true;
    end if;
  end if;

  if not v_benched
     and v_effective_hours >= 48.0
     and v_hunger <= 0.0
     and v_hygiene <= 0.0
     and v_anima.dormant_since is null then
    v_anima.dormant_since := v_now;
  end if;

  if not v_benched
     and p_action = 'sync'
     and v_hunger > 70.0
     and v_energy > 70.0
     and v_hygiene > 70.0
     and v_anima.well_cared_on is distinct from v_today then
    v_anima.care_score := v_anima.care_score + 8;
    v_anima.well_cared_on := v_today;
  end if;

  if not v_replayed then
    case p_action
      when 'feed' then
        select * into v_item
          from public.catalog_items
         where id = p_item_id and active and use_type = 'food';
        if not found then raise exception 'INVALID_ITEM'; end if;
        if v_hunger >= 99.5 then raise exception 'NEED_FULL'; end if;
        perform public._consume_inventory(p_owner, p_item_id);
        v_pre_action_need := v_hunger;
        v_hunger := least(100.0, v_hunger + v_item.effect_value);
        if v_pre_action_need < 40.0 and v_hunger >= 40.0 then
          v_anima.care_score := v_anima.care_score + 3;
        end if;

      when 'use_item' then
        select * into v_item
          from public.catalog_items
         where id = p_item_id and active and use_type = 'energy';
        if not found then raise exception 'INVALID_ITEM'; end if;
        if v_energy >= 99.5 then raise exception 'NEED_FULL'; end if;
        perform public._consume_inventory(p_owner, p_item_id);
        v_energy := least(100.0, v_energy + v_item.effect_value);

      when 'clean' then
        if v_hygiene >= 99.5 then raise exception 'NEED_FULL'; end if;
        v_pre_action_need := v_hygiene;
        v_hygiene := least(100.0, v_hygiene + 35.0);
        if v_pre_action_need < 50.0 then
          v_anima.care_score := v_anima.care_score + 3;
        end if;

      when 'play' then
        if v_energy < 5.0 then raise exception 'NO_ENERGY'; end if;
        v_energy := v_energy - 5.0;
        if v_anima.play_score_on is distinct from v_today then
          v_anima.play_score_on := v_today;
          v_anima.play_score_today := 0;
        end if;
        if v_anima.play_score_today < 5 then
          v_anima.play_score_today := v_anima.play_score_today + 1;
          v_anima.care_score := v_anima.care_score + 1;
        end if;

      when 'sleep' then
        if v_anima.sleep_started_at is not null then raise exception 'ALREADY_SLEEPING'; end if;
        v_anima.sleep_started_at := v_now;
        v_anima.sleep_energy_at_start := v_energy;

      when 'wake' then
        if not v_sleep_completed then
          if v_anima.sleep_started_at is null then raise exception 'NOT_SLEEPING'; end if;
          v_anima.sleep_started_at := null;
          v_anima.sleep_energy_at_start := null;
        end if;

      when 'summon' then
        if v_active_id is distinct from p_anima_id then
          update public.profiles
             set active_anima_id = p_anima_id
           where id = p_owner;
          update public.animas
             set sleep_started_at = coalesce(sleep_started_at, care_synced_at, v_now),
                 sleep_energy_at_start = coalesce(
                   sleep_energy_at_start,
                   least(100.0, greatest(0.0, coalesce((care->>'energy')::double precision, 0.0)))
                 )
           where owner_id = p_owner
             and status = 'ready'
             and id is distinct from p_anima_id
             and sleep_started_at is null;
          v_active_id := p_anima_id;
        end if;
        v_anima.sleep_started_at := null;
        v_anima.sleep_energy_at_start := null;
        v_benched := false;

      when 'sync' then
        null;
    end case;
  end if;

  if not v_benched
     and v_anima.dormant_since is not null
     and v_hunger >= 50.0
     and v_hygiene >= 50.0 then
    v_anima.dormant_since := null;
  end if;

  if v_bits_cost > 0 then
    update public.profiles
       set bits = bits - v_bits_cost
     where id = p_owner
    returning bits into v_bits;

    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (p_owner, 'bits', -v_bits_cost, p_action, v_event_id);
  end if;

  v_anima.care := jsonb_build_object(
    'hunger', round(v_hunger::numeric, 2),
    'energy', round(v_energy::numeric, 2),
    'hygiene', round(v_hygiene::numeric, 2),
    'bond', 0
  );
  v_anima.care_synced_at := v_now;

  update public.animas
     set care = v_anima.care,
         care_score = v_anima.care_score,
         care_synced_at = v_anima.care_synced_at,
         sleep_started_at = v_anima.sleep_started_at,
         sleep_energy_at_start = v_anima.sleep_energy_at_start,
         sleep_exp_on = v_anima.sleep_exp_on,
         well_cared_on = v_anima.well_cared_on,
         play_score_on = v_anima.play_score_on,
         play_score_today = v_anima.play_score_today,
         dormant_since = v_anima.dormant_since
   where id = v_anima.id
  returning * into v_anima;
  v_score_delta := v_anima.care_score - v_score_before;

  if p_action <> 'sync' and not v_replayed then
    update public.care_events
       set bits_spent = v_bits_cost,
           care_score_delta = v_score_delta
     where id = v_event_id;
  end if;

  return jsonb_build_object(
    'anima', to_jsonb(v_anima),
    'bits', v_bits,
    'replayed', v_replayed,
    'active_anima_id', v_active_id
  );
end $$;

revoke all on function public.apply_care(uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_care(uuid, uuid, text, text, text) to service_role;

create or replace function public.commit_battle_turn(
  p_owner uuid,
  p_session_id uuid,
  p_expected_turn integer,
  p_expected_version integer,
  p_key text,
  p_action text,
  p_state jsonb,
  p_events jsonb,
  p_bot_action text,
  p_item_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.battle_sessions;
  v_turn public.battle_turns;
  v_item public.catalog_items;
  v_response jsonb;
  v_reward jsonb := jsonb_build_object(
    'bits', 0,
    'care_score', 0,
    'battle_wins', 0,
    'capped', false,
    'progression_capped', false
  );
  v_reward_status jsonb;
  v_status text;
  v_payout integer := 0;
  v_exp integer := 0;
  v_score_before integer := 0;
  v_score_after integer := 0;
begin
  if p_action not in ('strike', 'surge', 'guard', 'item') then raise exception 'INVALID_ACTION'; end if;
  if p_action = 'item' and (p_item_id is null or length(p_item_id) = 0) then
    raise exception 'INVALID_ITEM';
  end if;
  if p_action <> 'item' and p_item_id is not null then raise exception 'INVALID_ITEM'; end if;
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
    if v_turn.turn_number <> p_expected_turn
       or v_turn.action <> p_action
       or v_turn.catalog_item_id is distinct from p_item_id then
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
      'events', jsonb_build_array(jsonb_build_object('type', 'finished', 'result', 'forfeited')),
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

  if p_action = 'item' then
    if v_session.item_used_id is not null then raise exception 'ITEM_ALREADY_USED'; end if;
    select * into v_item
      from public.catalog_items
     where id = p_item_id and active and use_type = 'battle';
    if not found then raise exception 'INVALID_ITEM'; end if;
    perform public._consume_inventory(p_owner, p_item_id);
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
         item_used_id = case when p_action = 'item' then p_item_id else item_used_id end,
         updated_at = now(),
         finished_at = case when v_status = 'active' then null else now() end
   where id = v_session.id
  returning * into v_session;

  if v_status = 'won' and v_session.rewarded_at is null then
    perform 1 from public.profiles where id = p_owner for update;
    if not found then raise exception 'NO_PROFILE'; end if;

    v_reward_status := public.battle_daily_reward_status(p_owner, v_session.id);
    v_payout := least(
      v_session.reward_bits,
      greatest(0, (v_reward_status->>'bits_remaining')::integer)
    );

    if (v_reward_status->>'remaining')::integer > 0 then
      v_exp := public.battle_exp_yield(
        coalesce((v_session.player_snapshot->>'level')::integer, 1),
        coalesce((v_session.bot_snapshot->>'level')::integer, 1),
        v_session.reward_tier
      );
      select care_score into v_score_before
        from public.animas
       where id = v_session.player_anima_id and owner_id = p_owner
       for update;
      if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;
      update public.animas
         set care_score = care_score + v_exp,
             battle_wins = battle_wins + 1
       where id = v_session.player_anima_id and owner_id = p_owner
      returning care_score into v_score_after;
      v_exp := v_score_after - v_score_before;

      if v_payout > 0 then
        update public.profiles set bits = bits + v_payout where id = p_owner;
        insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
        values (p_owner, 'bits', v_payout, 'battle_win', v_session.id);
      end if;
      v_reward := jsonb_build_object(
        'bits', v_payout,
        'care_score', v_exp,
        'battle_wins', 1,
        'capped', v_payout = 0,
        'progression_capped', false
      );
    elsif v_payout > 0 then
      update public.profiles set bits = bits + v_payout where id = p_owner;
      insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
      values (p_owner, 'bits', v_payout, 'battle_train', v_session.id);
      v_reward := jsonb_build_object(
        'bits', v_payout,
        'care_score', 0,
        'battle_wins', 0,
        'capped', false,
        'progression_capped', true
      );
    else
      v_reward := jsonb_build_object(
        'bits', 0,
        'care_score', 0,
        'battle_wins', 0,
        'capped', true,
        'progression_capped', true
      );
    end if;

    update public.battle_sessions
       set rewarded_at = now()
     where id = v_session.id
    returning * into v_session;
  end if;

  v_response := jsonb_build_object(
    'session', public.battle_session_payload(v_session),
    'events', p_events,
    'bot_action', p_bot_action,
    'reward', v_reward,
    'replayed', false
  );
  insert into public.battle_turns
    (session_id, turn_number, idempotency_key, action, catalog_item_id, response)
  values
    (v_session.id, p_expected_turn, p_key, p_action, p_item_id, v_response);
  return v_response;
end $$;

revoke all on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text, text
) from public, anon, authenticated;
grant execute on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text, text
) to service_role;

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

revoke all on function public.commit_team_battle_turn(
  uuid, uuid, integer, integer, text, text, smallint, text, jsonb, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.commit_team_battle_turn(
  uuid, uuid, integer, integer, text, text, smallint, text, jsonb, jsonb, jsonb
) to service_role;

create or replace function public.expedition_daily_reward_status(
  p_owner uuid,
  p_encounter_id uuid default null
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
         where key = 'expedition_rewarded_encounters_per_day'
      ), 3))) as reward_limit,
      greatest(0, least(500, coalesce((
        select (value #>> '{}')::integer from public.app_config
         where key = 'expedition_daily_exp_budget'
      ), 30))) as exp_limit
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
      count(*) filter (where reward.progression)::integer as encounters,
      coalesce(sum(reward.anima_exp_total) filter (where reward.progression), 0)::integer as exp
      from public.expedition_encounter_rewards reward
      cross join boundary
     where reward.owner_id = p_owner
       and reward.created_at >= boundary.starts_at
       and reward.created_at < boundary.reset_at
  )
  select jsonb_build_object(
    'earned', earned.encounters,
    'limit', settings.reward_limit,
    'remaining', greatest(0, settings.reward_limit - earned.encounters),
    'exp_earned', earned.exp,
    'exp_limit', settings.exp_limit,
    'exp_remaining', greatest(0, settings.exp_limit - earned.exp),
    'server_now', boundary.server_now,
    'reset_at', boundary.reset_at,
    'rewarded', exists (
      select 1 from public.expedition_encounter_rewards reward
       where p_encounter_id is not null
         and reward.owner_id = p_owner
         and reward.encounter_id = p_encounter_id
    ),
    'progression_rewarded', exists (
      select 1 from public.expedition_encounter_rewards reward
       where p_encounter_id is not null
         and reward.owner_id = p_owner
         and reward.encounter_id = p_encounter_id
         and reward.progression
    )
  )
  from settings, boundary, earned
$$;

revoke all on function public.expedition_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.expedition_daily_reward_status(uuid, uuid)
  to service_role;

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
  v_exp_total integer := 0;
  v_full_exp integer;
  v_active_exp integer;
  v_bench_exp integer;
  v_recipient_level integer;
  v_opponent_level integer;
  v_score_before integer;
  v_score_after integer;
  v_difficulty text;
  v_progression boolean := false;
  v_boss_reward boolean := false;
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
    v_boss_reward := v_encounter.kind = 'boss' and v_run.boss_exp_awarded_at is null;
    v_progression := v_boss_reward
      or (v_reward_status->>'exp_remaining')::integer > 0;

    if v_progression then
      select greatest(1, least(40, round(avg(
               coalesce((member->>'level')::integer, 1)
             ))::integer))
        into v_opponent_level
        from jsonb_array_elements(v_encounter.opponent_snapshot) member;
      v_difficulty := case
        when v_encounter.kind = 'boss' then 'boss'
        when v_encounter.kind = 'elite' then 'elite'
        else 'even'
      end;

      for v_member in select value from jsonb_array_elements(p_state #> '{player,roster}')
      loop
        v_anima_id := (v_member->>'anima_id')::uuid;
        select coalesce((snapshot->>'level')::integer, 1)
          into v_recipient_level
          from jsonb_array_elements(v_encounter.player_snapshot) snapshot
         where snapshot->>'anima_id' = v_anima_id::text;
        if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;

        v_full_exp := public.battle_exp_yield(
          v_recipient_level, v_opponent_level, v_difficulty
        );
        v_active_exp := (v_full_exp + 1) / 2;
        v_bench_exp := (v_full_exp + 3) / 4;
        v_exp := public.party_member_reward_exp(v_member, v_active_exp, v_bench_exp);

        select care_score into v_score_before
          from public.animas
         where id = v_anima_id and owner_id = p_owner
         for update;
        if not found then raise exception 'SNAPSHOT_MISMATCH'; end if;
        update public.animas set care_score = care_score + v_exp
         where id = v_anima_id and owner_id = p_owner
        returning care_score into v_score_after;
        v_exp := v_score_after - v_score_before;
        v_exp_total := v_exp_total + v_exp;

        v_exp_rows := v_exp_rows || jsonb_build_array(jsonb_build_object(
          'anima_id', v_anima_id,
          'exp', v_exp,
          'participated', coalesce((v_member->>'participated')::boolean, false)
        ));
      end loop;
    end if;

    insert into public.expedition_encounter_rewards (
      encounter_id, owner_id, progression, supplies, anima_exp_total
    ) values (
      v_encounter.id, p_owner, v_progression, v_encounter.supplies_reward, v_exp_total
    );
    if v_boss_reward then
      update public.expedition_runs
         set boss_exp_awarded_at = now()
       where id = v_run.id and boss_exp_awarded_at is null
      returning * into v_run;
      if not found then raise exception 'BOSS_EXP_ALREADY_AWARDED'; end if;
    end if;

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
          v_encounter.player_snapshot, p_state
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
          v_encounter.player_snapshot, p_state
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

revoke all on function public.commit_expedition_turn(
  uuid, uuid, integer, integer, text, text, smallint, text,
  jsonb, jsonb, jsonb, jsonb, boolean, boolean, jsonb, text
) from public, anon, authenticated;
grant execute on function public.commit_expedition_turn(
  uuid, uuid, integer, integer, text, text, smallint, text,
  jsonb, jsonb, jsonb, jsonb, boolean, boolean, jsonb, text
) to service_role;
