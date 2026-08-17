-- Lawan Duel bikinan sistem. Matchmaking lama hanya menyaring stage dan total
-- base stat ±15%, sehingga duel ber-label `even` terukur berkisar 8% sampai
-- 100% peluang menang. Ketika tidak ada Anima pemain lain yang taksiran duelnya
-- masih seimbang, Edge Function merakit lawan yang mencerminkan Level pemain.
--
-- Lawan itu sengaja TIDAK punya baris `animas`: ia snapshot murni, art-nya
-- digambar client dari PlaceholderSheet, dan tidak ada pemilik yang bisa
-- diserang balik. `battle_sessions.bot_anima_id` sudah nullable sejak awal, jadi
-- yang perlu berubah hanya dua pagar di start_battle.
--
-- Pagar tetap ketat: bot_anima_id null hanya sah kalau snapshot benar-benar
-- menandai dirinya lawan sistem, dan snapshot pemain tetap wajib cocok dengan
-- Anima yang dipertaruhkan.

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

  update public.animas
     set care = jsonb_set(care, '{energy}', to_jsonb(round(v_energy - 20, 2)))
   where id = v_player.id;

  if p_player_snapshot->>'anima_id' is distinct from p_player_anima_id::text then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  if p_bot_anima_id is null then
    -- Lawan sistem: tidak ada baris animas yang bisa diverifikasi, jadi yang
    -- diperiksa adalah penandanya sendiri plus identitas slug yang dipakai
    -- client untuk memilih art placeholder.
    if p_bot_snapshot->>'system_asset' is distinct from 'placeholder' then
      raise exception 'BOT_NOT_FOUND';
    end if;
    if coalesce(p_bot_snapshot->>'anima_id', '') = '' then
      raise exception 'SNAPSHOT_MISMATCH';
    end if;
  else
    select * into v_bot
      from public.animas
     where id = p_bot_anima_id
       and owner_id <> p_owner
       and status = 'ready';
    if not found then raise exception 'BOT_NOT_FOUND'; end if;

    if p_bot_snapshot->>'anima_id' is distinct from p_bot_anima_id::text then
      raise exception 'SNAPSHOT_MISMATCH';
    end if;
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
