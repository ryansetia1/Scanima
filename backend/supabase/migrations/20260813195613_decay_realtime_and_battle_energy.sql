-- Grace 8 jam di-reset setiap sync, jadi pemain yang buka app <8 jam sekali
-- tidak pernah kehilangan Hunger/Hygiene. Decay sekarang = jam sejak snapshot
-- terakhir, tetap di-cap 48 jam. Battle/Train memotong 20 Energy pada start
-- baru; resume session aktif tidak memotong lagi.
create or replace function public.apply_care(
  p_owner uuid,
  p_anima_id uuid,
  p_action text,
  p_key text default null
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
  v_today              date := (now() at time zone 'UTC')::date;
  v_elapsed_hours      double precision;
  v_effective_hours    double precision;
  v_sleep_hours        double precision;
  v_hunger             double precision;
  v_energy             double precision;
  v_hygiene            double precision;
  v_bond               double precision;
  v_pre_action_need     double precision;
  v_bits                int;
  v_bits_cost           int := 0;
  v_score_before        int;
  v_score_delta         int := 0;
  v_sleep_completed     bool := false;
begin
  if p_action not in ('sync', 'feed', 'clean', 'sleep', 'wake', 'play') then
    raise exception 'UNKNOWN_ACTION';
  end if;

  if p_action <> 'sync' and (p_key is null or length(p_key) not between 1 and 128) then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  if p_action <> 'sync' then
    begin
      insert into public.care_events (owner_id, anima_id, idempotency_key, action)
      values (p_owner, p_anima_id, p_key, p_action)
      returning * into v_event;
      v_event_id := v_event.id;
    exception
      when unique_violation then
        select * into v_event
          from public.care_events
         where owner_id = p_owner and idempotency_key = p_key;
        if not found
           or v_event.anima_id <> p_anima_id
           or v_event.action <> p_action then
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

  select bits into v_bits
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  v_hunger := greatest(0.0, least(100.0, coalesce((v_anima.care->>'hunger')::double precision, 0.0)));
  v_energy := greatest(0.0, least(100.0, coalesce((v_anima.care->>'energy')::double precision, 0.0)));
  v_hygiene := greatest(0.0, least(100.0, coalesce((v_anima.care->>'hygiene')::double precision, 0.0)));
  v_bond := greatest(0.0, least(100.0, coalesce((v_anima.care->>'bond')::double precision, 0.0)));
  v_score_before := v_anima.care_score;

  -- Tidak ada Timer/cron. Setiap sync/action menghitung selisih sejak snapshot
  -- server terakhir. Cap 48 jam: pergi dua hari atau dua minggu hasilnya sama.
  v_elapsed_hours := greatest(
    0.0,
    extract(epoch from (v_now - v_anima.care_synced_at)) / 3600.0
  );
  v_effective_hours := least(48.0, v_elapsed_hours);

  v_hunger := greatest(0.0, v_hunger - 10.0 * v_effective_hours);
  v_hygiene := greatest(0.0, v_hygiene - 4.2 * v_effective_hours);

  if v_anima.sleep_started_at is null then
    v_energy := greatest(0.0, v_energy - 7.1 * v_effective_hours);
  else
    v_sleep_hours := greatest(
      0.0,
      extract(epoch from (v_now - v_anima.sleep_started_at)) / 3600.0
    );
    v_energy := least(
      100.0,
      coalesce(v_anima.sleep_energy_at_start, v_energy)
      + (100.0 - coalesce(v_anima.sleep_energy_at_start, v_energy))
        * least(1.0, v_sleep_hours / 6.0)
    );
    if v_sleep_hours >= 6.0 then
      v_anima.sleep_started_at := null;
      v_anima.sleep_energy_at_start := null;
      v_anima.care_score := v_anima.care_score + 5;
      v_sleep_completed := true;
    end if;
  end if;

  if v_hunger <= 0.0 and v_hygiene <= 0.0 then
    v_bond := greatest(0.0, v_bond - 2.0 * v_effective_hours);
  end if;

  if v_effective_hours >= 48.0
     and v_hunger <= 0.0
     and v_hygiene <= 0.0
     and v_anima.dormant_since is null then
    v_anima.dormant_since := v_now;
    v_anima.care_score := 0;
  end if;

  if p_action = 'sync'
     and v_hunger > 70.0
     and v_energy > 70.0
     and v_hygiene > 70.0
     and v_bond > 70.0
     and v_anima.well_cared_on is distinct from v_today then
    v_anima.care_score := v_anima.care_score + 8;
    v_anima.well_cared_on := v_today;
  end if;

  if not v_replayed then
    case p_action
      when 'feed' then
        if v_hunger >= 100.0 then raise exception 'NEED_FULL'; end if;
        if v_bits < 5 then raise exception 'NO_BITS'; end if;
        v_pre_action_need := v_hunger;
        v_hunger := least(100.0, v_hunger + 35.0);
        v_bond := least(100.0, v_bond + 3.0);
        v_bits_cost := 5;
        if v_pre_action_need < 40.0 then
          v_anima.care_score := v_anima.care_score + 3;
        end if;

      when 'clean' then
        if v_hygiene >= 100.0 then raise exception 'NEED_FULL'; end if;
        if v_bits < 5 then raise exception 'NO_BITS'; end if;
        v_pre_action_need := v_hygiene;
        v_hygiene := least(100.0, v_hygiene + 35.0);
        v_bond := least(100.0, v_bond + 3.0);
        v_bits_cost := 5;
        if v_pre_action_need < 50.0 then
          v_anima.care_score := v_anima.care_score + 3;
        end if;

      when 'play' then
        if v_bond >= 100.0 then raise exception 'BOND_FULL'; end if;
        if v_energy < 5.0 then raise exception 'NO_ENERGY'; end if;
        v_energy := v_energy - 5.0;
        v_bond := least(100.0, v_bond + 8.0);
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

      when 'sync' then
        null;
    end case;
  end if;

  if v_anima.dormant_since is not null and v_hunger >= 50.0 and v_hygiene >= 50.0 then
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

  v_score_delta := v_anima.care_score - v_score_before;
  v_anima.care := jsonb_build_object(
    'hunger', round(v_hunger::numeric, 2),
    'energy', round(v_energy::numeric, 2),
    'hygiene', round(v_hygiene::numeric, 2),
    'bond', round(v_bond::numeric, 2)
  );
  v_anima.care_synced_at := v_now;

  update public.animas
     set care = v_anima.care,
         care_score = v_anima.care_score,
         care_synced_at = v_anima.care_synced_at,
         sleep_started_at = v_anima.sleep_started_at,
         sleep_energy_at_start = v_anima.sleep_energy_at_start,
         well_cared_on = v_anima.well_cared_on,
         play_score_on = v_anima.play_score_on,
         play_score_today = v_anima.play_score_today,
         dormant_since = v_anima.dormant_since
   where id = v_anima.id
  returning * into v_anima;

  if p_action <> 'sync' and not v_replayed then
    update public.care_events
       set bits_spent = v_bits_cost,
           care_score_delta = v_score_delta
     where id = v_event_id;
  end if;

  return jsonb_build_object(
    'anima', to_jsonb(v_anima),
    'bits', v_bits,
    'replayed', v_replayed
  );
end $$;

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
  v_energy numeric;
begin
  if p_seed is null or length(p_seed) not between 1 and 128 then
    raise exception 'INVALID_SEED';
  end if;
  if p_initial_state->>'status' <> 'active'
     or coalesce((p_initial_state->>'turn')::integer, 0) <> 1 then
    raise exception 'INVALID_BATTLE_STATE';
  end if;

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
  v_energy := coalesce((v_player.care->>'energy')::numeric, 0);
  if v_energy < 20 then
    raise exception 'ANIMA_LOW_ENERGY';
  end if;

  update public.animas
     set care = jsonb_set(care, '{energy}', to_jsonb(round(v_energy - 20, 2)))
   where id = v_player.id;

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

revoke all on function public.apply_care(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_care(uuid, uuid, text, text)
  to service_role;

revoke all on function public.start_battle(
  uuid, uuid, uuid, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.start_battle(
  uuid, uuid, uuid, jsonb, jsonb, jsonb, text
) to service_role;
