-- commit_battle_turn: item + Bits cap terpisah dari progression.

drop function if exists public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text
);

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
begin
  if p_action not in ('strike', 'surge', 'guard', 'item') then raise exception 'INVALID_ACTION'; end if;
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
      update public.animas
         set care_score = care_score + 4,
             battle_wins = battle_wins + 1
       where id = v_session.player_anima_id and owner_id = p_owner;
      if v_payout > 0 then
        update public.profiles set bits = bits + v_payout where id = p_owner;
        insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
        values (p_owner, 'bits', v_payout, 'battle_win', v_session.id);
      end if;
      v_reward := jsonb_build_object(
        'bits', v_payout,
        'care_score', 4,
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

revoke all on function public.battle_session_payload(public.battle_sessions)
  from public, anon, authenticated;
revoke all on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text, text
) from public, anon, authenticated;
grant execute on function public.battle_session_payload(public.battle_sessions)
  to service_role;
grant execute on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text, text
) to service_role;
