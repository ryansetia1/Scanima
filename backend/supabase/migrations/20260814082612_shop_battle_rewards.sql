-- Reward Battle: progression tetap 3 kemenangan; Bits memakai cap nominal harian.

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
    ) as reward_limit,
    greatest(
      0,
      least(
        1000,
        coalesce(
          (
            select (value #>> '{}')::integer
              from public.app_config
             where key = 'battle_bits_per_day'
          ),
          100
        )
      )
    ) as bits_limit
  ),
  zone as (
    select coalesce(
      (
        select timezone_offset_minutes
          from public.profiles
         where id = p_owner
      ),
      0
    ) as offset_minutes
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
       and q.reason = 'battle_win'
       and q.created_at >= b.starts_at
       and q.created_at < b.reset_at
  ),
  bits as (
    select coalesce(sum(q.delta), 0)::integer as earned
      from public.quota_ledger q
      cross join boundary b
     where q.owner_id = p_owner
       and q.currency = 'bits'
       and q.reason in ('battle_win', 'battle_train')
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
      select 1
        from public.quota_ledger q
       where p_session_id is not null
         and q.owner_id = p_owner
         and q.ref_id = p_session_id
         and q.reason in ('battle_win', 'battle_train')
    ),
    'progression_rewarded', exists (
      select 1
        from public.quota_ledger q
       where p_session_id is not null
         and q.owner_id = p_owner
         and q.ref_id = p_session_id
         and q.reason = 'battle_win'
    )
  )
    from settings, boundary, rewarded, bits
$$;

revoke all on function public.battle_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.battle_daily_reward_status(uuid, uuid) to service_role;

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
    'item_used_id', (p_session).item_used_id,
    'reward_tier', (p_session).reward_tier,
    'reward_roll', (p_session).reward_roll,
    'reward_bits', (p_session).reward_bits,
    'daily_reward', public.battle_daily_reward_status(
      (p_session).owner_id,
      (p_session).id
    )
  )
$$;

drop function if exists public.start_battle(uuid, uuid, uuid, jsonb, jsonb, jsonb, text);

create or replace function public.start_battle(
  p_owner uuid,
  p_player_anima_id uuid,
  p_bot_anima_id uuid,
  p_player_snapshot jsonb,
  p_bot_snapshot jsonb,
  p_initial_state jsonb,
  p_seed text,
  p_reward_tier text default 'even',
  p_reward_roll smallint default 0,
  p_reward_bits integer default 8
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
  v_hunger numeric;
  v_tier text := coalesce(p_reward_tier, 'even');
  v_roll smallint := coalesce(p_reward_roll, 0);
  v_bits integer := coalesce(p_reward_bits, 8);
begin
  if p_seed is null or length(p_seed) not between 1 and 128 then
    raise exception 'INVALID_SEED';
  end if;
  if p_initial_state->>'status' <> 'active'
     or coalesce((p_initial_state->>'turn')::integer, 0) <> 1 then
    raise exception 'INVALID_BATTLE_STATE';
  end if;
  if v_tier not in ('favorable', 'even', 'tough', 'formidable') then
    v_tier := 'even';
  end if;
  if v_roll < -1 or v_roll > 1 then v_roll := 0; end if;
  if v_bits < 5 or v_bits > 16 then v_bits := 8; end if;

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
  v_hunger := coalesce((v_player.care->>'hunger')::numeric, 0);
  if v_hunger < 40 then
    raise exception 'ANIMA_HUNGRY';
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
    turn_number, rng_seed, reward_tier, reward_roll, reward_bits
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
    p_seed,
    v_tier,
    v_roll,
    v_bits
  )
  returning * into v_session;

  return public.battle_session_payload(v_session);
end $$;

revoke all on function public.start_battle(
  uuid, uuid, uuid, jsonb, jsonb, jsonb, text, text, smallint, integer
) from public, anon, authenticated;
grant execute on function public.start_battle(
  uuid, uuid, uuid, jsonb, jsonb, jsonb, text, text, smallint, integer
) to service_role;
