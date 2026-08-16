-- Canonical in-world height drives visual Battle scale. It is server-owned and
-- independent from source-photo dimensions or sprite-cell pixel fill.

alter table public.animas
  add column body_height_cm integer not null default 120,
  add constraint animas_body_height_cm_valid
    check (body_height_cm between 20 and 2000);

-- Seven ready production Anima reviewed from their source silhouette and art.
update public.animas
set body_height_cm = case id
  when 'a20bb2f0-e063-4b7c-8bab-bfaf261400b8'::uuid then 85   -- Mugshots
  when '19949c2e-5d3d-41f6-9b02-4f0740b1cace'::uuid then 210 -- Hydron
  when '594fe414-e404-4db5-82d7-d6f1c7fee1a5'::uuid then 110 -- Deckon
  when '99b04a1c-07be-4753-be04-ae68183817e6'::uuid then 95  -- Playtron
  when 'c80ddef5-533d-4f36-9f26-7f449981e996'::uuid then 260 -- Veridian
  when '1b5a7be0-55a2-45a9-889e-1ae5bf8f0c77'::uuid then 90  -- klasik
  when '2168d17e-440d-4ba3-9004-5104800c6722'::uuid then 140 -- Sunhound
  else body_height_cm
end
where id in (
  'a20bb2f0-e063-4b7c-8bab-bfaf261400b8'::uuid,
  '19949c2e-5d3d-41f6-9b02-4f0740b1cace'::uuid,
  '594fe414-e404-4db5-82d7-d6f1c7fee1a5'::uuid,
  '99b04a1c-07be-4753-be04-ae68183817e6'::uuid,
  'c80ddef5-533d-4f36-9f26-7f449981e996'::uuid,
  '1b5a7be0-55a2-45a9-889e-1ae5bf8f0c77'::uuid,
  '2168d17e-440d-4ba3-9004-5104800c6722'::uuid
);

create or replace function public.claim_capture(
  p_owner             uuid,
  p_key               text,
  p_nickname          text,
  p_species           text,
  p_color             text,
  p_stage             smallint,
  p_element           text,
  p_secondary_element text,
  p_subject_kind      text,
  p_rarity            int,
  p_stats             jsonb,
  p_care              jsonb,
  p_vision            jsonb,
  p_prompt_version    text,
  p_model             text,
  p_cost              numeric,
  p_photo_path        text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_anima public.animas;
  v_cores int;
  v_guest_used timestamptz;
  v_is_anonymous boolean;
  v_cap numeric;
  v_spent numeric;
  v_body_height_cm integer;
begin
  select * into v_gen
    from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  perform public._grant_weekly_core_if_eligible(p_owner);

  select p.genesis_cores, p.guest_scan_used_at, coalesce(u.is_anonymous, false)
    into v_cores, v_guest_used, v_is_anonymous
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = p_owner
   for update of p;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_is_anonymous and v_guest_used is not null then raise exception 'GUEST_SCAN_USED'; end if;
  if v_cores <= 0 then raise exception 'NO_CORE'; end if;

  select (value #>> '{}')::numeric into v_cap
    from public.app_config where key = 'daily_spend_cap_usd';
  if v_cap is not null then
    select coalesce(sum(cost_usd_estimate), 0) into v_spent
      from public.generations
     where created_at >= date_trunc('day', now()) and cost_usd_estimate > 0;
    if v_spent + p_cost > v_cap then raise exception 'SPEND_CAP'; end if;
  end if;

  v_body_height_cm := case
    when coalesce(p_vision->>'body_height_cm', '') ~ '^[0-9]+$'
      then least(2000, greatest(20, (p_vision->>'body_height_cm')::integer))
    else 120
  end;

  update public.profiles
     set genesis_cores = genesis_cores - 1,
         guest_scan_used_at = case when v_is_anonymous then now() else guest_scan_used_at end
   where id = p_owner;

  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, stage, status,
     subject_kind, element, secondary_element, typing_version,
     rarity, base_stats, care, body_height_cm, strike_name, surge_name)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'incubating',
     p_subject_kind, p_element, p_secondary_element, 2,
     least(5, greatest(1, p_rarity)), p_stats, p_care, v_body_height_cm,
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
    select * into v_gen
      from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

revoke all on function public.claim_capture(
  uuid, text, text, text, text, smallint, text, text, text, int, jsonb, jsonb,
  jsonb, text, text, numeric, text
) from public, anon, authenticated;
grant execute on function public.claim_capture(
  uuid, text, text, text, text, smallint, text, text, text, int, jsonb, jsonb,
  jsonb, text, text, numeric, text
) to service_role;
