-- Anima lapar (Hunger < 40, sama dengan pose Hungry) tidak boleh masuk
-- Battle atau Training. Pola yang sama dengan ANIMA_LOW_ENERGY.

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
  v_hunger numeric;
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

revoke all on function public.start_battle(
  uuid, uuid, uuid, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.start_battle(
  uuid, uuid, uuid, jsonb, jsonb, jsonb, text
) to service_role;
