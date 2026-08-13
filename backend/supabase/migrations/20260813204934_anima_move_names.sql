-- Nama move unik per Anima, diisi Vision mulai prompt v7. Sheet lama dan Anima
-- lama tetap sah: default kosong, client jatuh ke copy Attack/Special.

alter table public.animas
  add column strike_name text not null default '',
  add column surge_name text not null default '';

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

  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, stage, status,
     element, rarity, base_stats, care, strike_name, surge_name)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'ready',
     p_element, least(5, greatest(1, p_rarity)), p_stats, p_care,
     left(btrim(coalesce(p_vision->>'strike_name', '')), 24),
     left(btrim(coalesce(p_vision->>'surge_name', '')), 24))
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
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

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
  select * into v_gen from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  select genesis_cores into v_cores from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_cores <= 0 then raise exception 'NO_CORE'; end if;

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
     element, rarity, base_stats, care, strike_name, surge_name)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'incubating',
     p_element, least(5, greatest(1, p_rarity)), p_stats, p_care,
     left(btrim(coalesce(p_vision->>'strike_name', '')), 24),
     left(btrim(coalesce(p_vision->>'surge_name', '')), 24))
  returning * into v_anima;

  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model,
     cost_usd_estimate, vision_result, photo_path)
  values
    (p_owner, v_anima.id, p_key, 'create', 'pending', p_prompt_version, p_model,
     p_cost, p_vision, p_photo_path)
  returning * into v_gen;

  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
  values (p_owner, 'genesis_cores', -1, 'genesis', v_gen.id);

  return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_anima.id);
exception
  when unique_violation then
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

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
