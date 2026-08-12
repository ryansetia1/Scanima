-- Dua jalur akhir dari create_anima, masing-masing satu transaksi.
--
-- Sebelumnya claim_generation hanya mendebit Core dan membuat baris generation,
-- lalu Edge Function menyusul membuat anima dan mengisi photo_path lewat dua
-- panggilan terpisah. Yang lolos di celah antar-panggilan itu bukan sebaris data
-- melainkan satu Genesis Core: kalau fungsi mati setelah debit dan sebelum anima
-- dibuat, pemain kehilangan Core dan tidak mendapat apa pun, dan tidak ada
-- pemeriksaan yang bisa membedakannya dari generation yang sah sedang menunggu.
--
-- claim_generation dihapus, bukan dibiarkan menganggur di samping penggantinya.
-- Dua fungsi yang dua-duanya bisa mendebit Core berarti dua tempat yang harus
-- benar, dan yang menganggur adalah yang tidak pernah diuji lagi. Kebutuhan
-- evolusi (debit tanpa membuat anima baru) ditangani saat evolusi dibangun di
-- Phase 4, dengan bentuk yang sesuai kebutuhan nyatanya saat itu.

drop function if exists public.claim_generation(uuid, text, text, text, text, numeric);

-- Cache hit: art sudah ada di pustaka, jadi tidak ada Core yang didebit dan tidak
-- ada panggilan gambar. Tetap dicatat sebagai baris generation supaya rasio cache
-- hit bisa diukur — angka itu yang menentukan apakah model biaya kita bertahan.
create or replace function public.record_cache_hit(
  p_owner          uuid,
  p_key            text,
  p_nickname       text,
  p_species        text,
  p_color          text,
  p_stage          smallint,
  p_element        text,
  p_rarity         int,
  p_stats          jsonb,
  p_care           jsonb,
  p_vision         jsonb,
  p_prompt_version text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen   public.generations;
  v_anima public.animas;
begin
  select * into v_gen from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  -- rarity dari Vision di-clamp, tidak divalidasi lalu ditolak: hasil Vision-nya
  -- sudah dibayar, dan menggagalkan seluruh request karena model menulis 7
  -- berarti membuang uang yang sudah keluar demi kerapian nilai.
  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, stage, status,
     element, rarity, base_stats, care)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'ready',
     p_element, least(5, greatest(1, p_rarity)), p_stats, p_care)
  returning * into v_anima;

  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model,
     cost_usd_estimate, vision_result, finished_at)
  values
    (p_owner, v_anima.id, p_key, 'create', 'cache_hit', p_prompt_version, 'cache',
     0, p_vision, now())
  returning * into v_gen;

  update public.species_library
     set times_reused = times_reused + 1
   where species_key = p_species and color_bucket = p_color and stage = p_stage;

  return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_anima.id);
exception
  when unique_violation then
    -- Dua request paralel dengan idempotency_key sama. Yang kalah dibatalkan
    -- seluruhnya, termasuk anima yang sudah dibuatnya, lalu membaca pemenang.
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

-- Genesis: spesies baru, tidak ada di pustaka, jadi satu sheet ~$0.07 akan
-- dipanggil. Debit Core, baris generation, baris anima, dan ledger terjadi
-- bersama atau tidak terjadi sama sekali.
create or replace function public.claim_genesis(
  p_owner          uuid,
  p_key            text,
  p_nickname       text,
  p_species        text,
  p_color          text,
  p_stage          smallint,
  p_element        text,
  p_rarity         int,
  p_stats          jsonb,
  p_care           jsonb,
  p_vision         jsonb,
  p_prompt_version text,
  p_model          text,
  p_cost           numeric,
  p_photo_path     text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen   public.generations;
  v_anima public.animas;
  v_cores int;
  v_cap   numeric;
  v_spent numeric;
begin
  -- Idempotency lebih dulu: request yang sama dua kali mengembalikan baris yang
  -- sama alih-alih mendebit dua kali. Inilah yang membuat retry jaringan tidak
  -- pernah berarti double charge.
  select * into v_gen from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  select genesis_cores into v_cores from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_cores <= 0 then raise exception 'NO_CORE'; end if;

  -- Sakelar biaya harian diperiksa DI DALAM transaksi yang memegang lock baris
  -- profil, bukan di Edge Function sebelum memanggil. Membacanya di luar
  -- meninggalkan celah antara pembacaan dan debit, dan yang lolos di celah itu
  -- satu panggilan generation berbayar. Cap-nya global: tagihannya milik kita.
  select (value #>> '{}')::numeric into v_cap
    from public.app_config where key = 'daily_spend_cap_usd';
  if v_cap is not null then
    select coalesce(sum(cost_usd_estimate), 0) into v_spent
      from public.generations
     where created_at >= date_trunc('day', now()) and cost_usd_estimate > 0;
    if v_spent + p_cost > v_cap then raise exception 'SPEND_CAP'; end if;
  end if;

  update public.profiles set genesis_cores = genesis_cores - 1 where id = p_owner;

  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, stage, status,
     element, rarity, base_stats, care)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'incubating',
     p_element, least(5, greatest(1, p_rarity)), p_stats, p_care)
  returning * into v_anima;

  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model,
     cost_usd_estimate, vision_result, photo_path)
  values
    (p_owner, v_anima.id, p_key, 'create', 'pending', p_prompt_version, p_model,
     p_cost, p_vision, p_photo_path)
  returning * into v_gen;

  -- Ledger ditulis setelah generation ada supaya ref_id bisa diisi. Itu yang
  -- memungkinkan refund_generation membuktikan debitnya memang pernah terjadi,
  -- bukan menebaknya dari status.
  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
  values (p_owner, 'genesis_cores', -1, 'genesis', v_gen.id);

  return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_anima.id);
exception
  when unique_violation then
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

-- SECURITY DEFINER di schema public otomatis mendapat EXECUTE dari PUBLIC. Tanpa
-- revoke ini, claim_genesis menjadi endpoint /rest/v1/rpc yang bisa dipanggil
-- siapa pun dengan anon key — dan ia membuat anima serta baris generation atas
-- nama uid mana pun yang disebut penelepon.
revoke all on function public.record_cache_hit(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.claim_genesis(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text, text, numeric, text
) from public, anon, authenticated;

grant execute on function public.record_cache_hit(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text
) to service_role;
grant execute on function public.claim_genesis(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text, text, numeric, text
) to service_role;
