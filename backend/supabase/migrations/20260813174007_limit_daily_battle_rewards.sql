-- Battle tetap boleh dimainkan setelah cap, tetapi hanya tiga kemenangan pertama
-- per akun per hari UTC yang memberi Bits, care_score, dan battle_wins. Ledger
-- yang sudah menjadi audit uang sekaligus menjadi counter; tidak ada state kedua
-- yang bisa drift. Semua keputusan tetap satu transaksi dengan commit turn.

insert into public.app_config (key, value)
values ('battle_rewarded_wins_per_day', '3'::jsonb)
on conflict (key) do update
set value = excluded.value,
    updated_at = now();

create or replace function public.battle_daily_reward_status(
  p_owner uuid,
  p_session_id uuid default null
) returns jsonb
language sql
stable
set search_path = ''
as $$
  with settings as (
    select greatest(
      0,
      least(
        100,
        coalesce(
          (
            select (value #>> '{}')::integer
              from public.app_config
             where key = 'battle_rewarded_wins_per_day'
          ),
          3
        )
      )
    ) as reward_limit
  ),
  boundary as (
    select
      date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' as starts_at,
      (
        date_trunc('day', now() at time zone 'UTC') + interval '1 day'
      ) at time zone 'UTC' as reset_at
  ),
  rewarded as (
    select count(*)::integer as wins
      from public.quota_ledger q
      cross join boundary b
     where q.owner_id = p_owner
       and q.currency = 'bits'
       and q.delta = 5
       and q.reason = 'battle_win'
       and q.created_at >= b.starts_at
       and q.created_at < b.reset_at
  )
  select jsonb_build_object(
    'earned', rewarded.wins,
    'limit', settings.reward_limit,
    'remaining', greatest(0, settings.reward_limit - rewarded.wins),
    'reset_at', boundary.reset_at,
    'rewarded', exists (
      select 1
        from public.quota_ledger q
       where p_session_id is not null
         and q.ref_id = p_session_id
         and q.currency = 'bits'
         and q.delta = 5
         and q.reason = 'battle_win'
    )
  )
    from settings, boundary, rewarded
$$;

revoke all on function public.battle_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.battle_daily_reward_status(uuid, uuid)
  to service_role;

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
    'finished_at', (p_session).finished_at,
    'daily_reward', public.battle_daily_reward_status(
      (p_session).owner_id,
      (p_session).id
    )
  )
$$;

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
  v_reward jsonb := jsonb_build_object(
    'bits', 0,
    'care_score', 0,
    'battle_wins', 0,
    'capped', false
  );
  v_reward_status jsonb;
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
    -- Satu akun hanya punya satu active session, tetapi profile lock tetap
    -- menjadikan check+ledger atomik bila invariant session berubah nanti.
    perform 1 from public.profiles where id = p_owner for update;
    if not found then raise exception 'NO_PROFILE'; end if;

    v_reward_status := public.battle_daily_reward_status(p_owner, v_session.id);
    if (v_reward_status->>'earned')::integer
       < (v_reward_status->>'limit')::integer then
      update public.profiles set bits = bits + 5 where id = p_owner;
      update public.animas
         set care_score = care_score + 4,
             battle_wins = battle_wins + 1
       where id = v_session.player_anima_id and owner_id = p_owner;
      insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
      values (p_owner, 'bits', 5, 'battle_win', v_session.id);
      v_reward := jsonb_build_object(
        'bits', 5,
        'care_score', 4,
        'battle_wins', 1,
        'capped', false
      );
    else
      v_reward := jsonb_build_object(
        'bits', 0,
        'care_score', 0,
        'battle_wins', 0,
        'capped', true
      );
    end if;

    -- rewarded_at berarti keputusan reward sudah final, termasuk practice win.
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
    (session_id, turn_number, idempotency_key, action, response)
  values
    (v_session.id, p_expected_turn, p_key, p_action, v_response);
  return v_response;
end $$;

-- CREATE OR REPLACE mempertahankan grant lama; ulangi pagar secara eksplisit
-- supaya migration ini aman dibaca sendiri.
revoke all on function public.battle_session_payload(public.battle_sessions)
  from public, anon, authenticated;
revoke all on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.battle_session_payload(public.battle_sessions)
  to service_role;
grant execute on function public.commit_battle_turn(
  uuid, uuid, integer, integer, text, text, jsonb, jsonb, text
) to service_role;
