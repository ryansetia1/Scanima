-- Player-selected visual Vibe is art-only. Persist it on the generation row so
-- resume/replay cannot change the look after Core is claimed. Anima rows stay
-- unchanged: Vibe is not a Collection/Profile trait.

alter table public.generations
  add column capture_vibe text not null default 'natural',
  add constraint generations_capture_vibe_valid
    check (capture_vibe in ('natural', 'cute', 'brave', 'wild', 'sinister'));

drop function if exists public.claim_capture(
  uuid, text, text, text, text, smallint, text, text, text, int, jsonb, jsonb,
  jsonb, text, text, numeric, text
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
  p_photo_path        text,
  p_capture_vibe      text default 'natural'
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
  v_vibe text;
begin
  select * into v_gen
    from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  v_vibe := lower(btrim(coalesce(p_capture_vibe, 'natural')));
  if v_vibe not in ('natural', 'cute', 'brave', 'wild', 'sinister') then
    raise exception 'INVALID_VIBE';
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
     cost_usd_estimate, vision_result, photo_path, capture_vibe)
  values
    (p_owner, v_anima.id, p_key, 'create', 'pending', p_prompt_version, p_model,
     p_cost, p_vision, p_photo_path, v_vibe)
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
  jsonb, text, text, numeric, text, text
) from public, anon, authenticated;
grant execute on function public.claim_capture(
  uuid, text, text, text, text, smallint, text, text, text, int, jsonb, jsonb,
  jsonb, text, text, numeric, text, text
) to service_role;
