-- apply_care inventory-backed (food_id / use_item).

drop function if exists public.apply_care(uuid, uuid, text, text);

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

  v_hunger := greatest(0.0, v_hunger - 10.0 * v_effective_hours);
  v_hygiene := greatest(0.0, v_hygiene - 4.2 * v_effective_hours);

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
      v_anima.care_score := v_anima.care_score + 5;
      v_sleep_completed := true;
    end if;
  end if;

  if v_effective_hours >= 48.0
     and v_hunger <= 0.0
     and v_hygiene <= 0.0
     and v_anima.dormant_since is null then
    v_anima.dormant_since := v_now;
  end if;

  if p_action = 'sync'
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
        if v_bits < 5 then raise exception 'NO_BITS'; end if;
        v_pre_action_need := v_hygiene;
        v_hygiene := least(100.0, v_hygiene + 35.0);
        v_bits_cost := 5;
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
    'bond', 0
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
    'replayed', v_replayed,
    'active_anima_id', v_active_id
  );
end $$;

revoke all on function public.apply_care(uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_care(uuid, uuid, text, text, text) to service_role;
