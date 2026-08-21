-- Guided Anima Synthesis. Resonance is resolved before any paid model call;
-- successful rolls claim one private generation atomically with Core + Bits.

alter table public.generations
  drop constraint if exists generations_kind_dikenal;
alter table public.generations
  add constraint generations_kind_dikenal
    check (kind in ('create', 'evolve', 'synthesis'));

alter table public.animas
  add column if not exists synthesis_history jsonb;
alter table public.animas
  drop constraint if exists animas_synthesis_history_object;
alter table public.animas
  add constraint animas_synthesis_history_object
    check (synthesis_history is null or jsonb_typeof(synthesis_history) = 'object');

alter table public.atlas_forms
  add column if not exists synthesis_history jsonb;
alter table public.atlas_forms
  drop constraint if exists atlas_forms_synthesis_history_object;
alter table public.atlas_forms
  add constraint atlas_forms_synthesis_history_object
    check (synthesis_history is null or jsonb_typeof(synthesis_history) = 'object');

insert into public.app_config (key, value) values
  ('feature_synthesis', 'false'::jsonb),
  ('synthesis_prompt_version', '"v42"'::jsonb),
  ('synthesis_core_cost', '1'::jsonb),
  ('synthesis_bits_cost', '250'::jsonb),
  ('synthesis_min_level', '10'::jsonb),
  ('synthesis_energy_penalty', '10'::jsonb),
  ('synthesis_cooldown_seconds', '3600'::jsonb),
  ('synthesis_resonance_base', '40'::jsonb),
  ('synthesis_resonance_level_max', '20'::jsonb),
  ('synthesis_resonance_care_max', '20'::jsonb),
  ('synthesis_resonance_affinity_max', '15'::jsonb),
  ('synthesis_resonance_dominant_bonus', '10'::jsonb),
  ('synthesis_calibration_step', '5'::jsonb),
  ('synthesis_calibration_max', '20'::jsonb),
  ('synthesis_cost_usd_estimate', '0.073'::jsonb)
on conflict (key) do nothing;

create table public.anima_synthesis_slots (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null references public.profiles(id) on delete cascade,
  source_low_id         uuid not null,
  source_high_id        uuid not null,
  mode                  text not null,
  status                text not null default 'open',
  failure_count         integer not null default 0,
  cooldown_until        timestamptz,
  active_generation_id  uuid references public.generations(id) on delete set null,
  result_anima_id       uuid references public.animas(id) on delete set null,
  successful_resonance  smallint,
  source_a_snapshot     jsonb,
  source_b_snapshot     jsonb,
  reference_paths       jsonb,
  synthesis_plan        jsonb,
  succeeded_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint anima_synthesis_slot_pair_order check (
    source_low_id::text < source_high_id::text
  ),
  constraint anima_synthesis_slot_mode_valid check (
    mode in ('dominant_low', 'balanced', 'dominant_high')
  ),
  constraint anima_synthesis_slot_status_valid check (
    status in ('open', 'pending', 'succeeded')
  ),
  constraint anima_synthesis_slot_failures_nonnegative check (failure_count >= 0),
  constraint anima_synthesis_slot_resonance_valid check (
    successful_resonance is null or successful_resonance between 1 and 100
  ),
  constraint anima_synthesis_slot_unique unique (
    owner_id, source_low_id, source_high_id, mode
  )
);

create index anima_synthesis_slots_active_owner_idx
  on public.anima_synthesis_slots (owner_id, updated_at desc)
  where status = 'pending';

create unique index anima_synthesis_one_pending_per_owner_idx
  on public.anima_synthesis_slots (owner_id)
  where status = 'pending';

create table public.anima_synthesis_attempts (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references public.profiles(id) on delete cascade,
  slot_id           uuid not null references public.anima_synthesis_slots(id) on delete cascade,
  idempotency_key   text not null,
  source_a_id       uuid not null,
  source_b_id       uuid not null,
  source_a_stage    smallint not null,
  source_b_stage    smallint not null,
  requested_mode    text not null,
  resonance_chance smallint not null,
  resonance_roll   smallint not null,
  outcome           text not null,
  generation_id    uuid references public.generations(id) on delete set null,
  result_anima_id   uuid references public.animas(id) on delete set null,
  cooldown_until    timestamptz,
  created_at        timestamptz not null default now(),
  constraint anima_synthesis_attempt_key_unique unique (owner_id, idempotency_key),
  constraint anima_synthesis_attempt_sources_differ check (source_a_id <> source_b_id),
  constraint anima_synthesis_attempt_stages_valid check (
    source_a_stage between 1 and 3 and source_b_stage between 1 and 3
  ),
  constraint anima_synthesis_attempt_mode_valid check (
    requested_mode in ('dominant_a', 'balanced', 'dominant_b')
  ),
  constraint anima_synthesis_attempt_resonance_valid check (
    resonance_chance between 1 and 100 and resonance_roll between 1 and 100
  ),
  constraint anima_synthesis_attempt_outcome_valid check (
    outcome in ('failed', 'claimed')
  )
);

create index anima_synthesis_attempts_slot_recent_idx
  on public.anima_synthesis_attempts (slot_id, created_at desc);

create unique index quota_ledger_synthesis_bits_refund_once_idx
  on public.quota_ledger (ref_id)
  where reason = 'synthesis_bits_refund';

alter table public.anima_synthesis_slots enable row level security;
alter table public.anima_synthesis_attempts enable row level security;
revoke all on public.anima_synthesis_slots from public, anon, authenticated;
revoke all on public.anima_synthesis_attempts from public, anon, authenticated;
grant all on public.anima_synthesis_slots to service_role;
grant all on public.anima_synthesis_attempts to service_role;

create or replace function public.synthesis_resonance(
  p_level_a integer,
  p_level_b integer,
  p_care_a jsonb,
  p_care_b jsonb,
  p_stats_a jsonb,
  p_stats_b jsonb,
  p_element_a text,
  p_secondary_a text,
  p_element_b text,
  p_secondary_b text,
  p_mode text,
  p_failure_count integer,
  p_config jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_base integer := coalesce((p_config->>'base')::integer, 40);
  v_level_max integer := coalesce((p_config->>'level_max')::integer, 20);
  v_care_max integer := coalesce((p_config->>'care_max')::integer, 20);
  v_affinity_max integer := coalesce((p_config->>'affinity_max')::integer, 15);
  v_dominant_bonus integer := coalesce((p_config->>'dominant_bonus')::integer, 10);
  v_calibration_step integer := coalesce((p_config->>'calibration_step')::integer, 5);
  v_calibration_max integer := coalesce((p_config->>'calibration_max')::integer, 20);
  v_level_bonus integer;
  v_care_bonus integer;
  v_stat_bonus integer;
  v_element_bonus integer := 0;
  v_affinity_bonus integer;
  v_mode_bonus integer;
  v_calibration_bonus integer;
  v_total_a numeric;
  v_total_b numeric;
  v_distance numeric;
  v_similarity numeric;
  v_total integer;
begin
  if p_mode not in ('dominant_a', 'balanced', 'dominant_b') then
    raise exception 'SYNTHESIS_MODE_INVALID';
  end if;

  v_level_bonus := least(
    v_level_max,
    greatest(
      0,
      round(
        (
          greatest(0, least(40, coalesce(p_level_a, 1)) - 10)
          + greatest(0, least(40, coalesce(p_level_b, 1)) - 10)
        )::numeric / 60.0 * v_level_max
      )::integer
    )
  );

  v_care_bonus := least(
    v_care_max,
    greatest(
      0,
      round(
        (
          greatest(0, least(100, coalesce((p_care_a->>'hunger')::numeric, 0)))
          + greatest(0, least(100, coalesce((p_care_a->>'energy')::numeric, 0)))
          + greatest(0, least(100, coalesce((p_care_a->>'hygiene')::numeric, 0)))
          + greatest(0, least(100, coalesce((p_care_b->>'hunger')::numeric, 0)))
          + greatest(0, least(100, coalesce((p_care_b->>'energy')::numeric, 0)))
          + greatest(0, least(100, coalesce((p_care_b->>'hygiene')::numeric, 0)))
        ) / 600.0 * v_care_max
      )::integer
    )
  );

  v_total_a := greatest(
    1,
    coalesce((p_stats_a->>'hp')::numeric, 50)
    + coalesce((p_stats_a->>'atk')::numeric, 50)
    + coalesce((p_stats_a->>'def')::numeric, 50)
    + coalesce((p_stats_a->>'spd')::numeric, 50)
    + coalesce((p_stats_a->>'special')::numeric, 50)
  );
  v_total_b := greatest(
    1,
    coalesce((p_stats_b->>'hp')::numeric, 50)
    + coalesce((p_stats_b->>'atk')::numeric, 50)
    + coalesce((p_stats_b->>'def')::numeric, 50)
    + coalesce((p_stats_b->>'spd')::numeric, 50)
    + coalesce((p_stats_b->>'special')::numeric, 50)
  );
  v_distance :=
    abs(coalesce((p_stats_a->>'hp')::numeric, 50) / v_total_a
      - coalesce((p_stats_b->>'hp')::numeric, 50) / v_total_b)
    + abs(coalesce((p_stats_a->>'atk')::numeric, 50) / v_total_a
      - coalesce((p_stats_b->>'atk')::numeric, 50) / v_total_b)
    + abs(coalesce((p_stats_a->>'def')::numeric, 50) / v_total_a
      - coalesce((p_stats_b->>'def')::numeric, 50) / v_total_b)
    + abs(coalesce((p_stats_a->>'spd')::numeric, 50) / v_total_a
      - coalesce((p_stats_b->>'spd')::numeric, 50) / v_total_b)
    + abs(coalesce((p_stats_a->>'special')::numeric, 50) / v_total_a
      - coalesce((p_stats_b->>'special')::numeric, 50) / v_total_b);
  v_similarity := greatest(0, least(1, 1 - v_distance / 2.0));
  v_stat_bonus := round(v_similarity * least(10, v_affinity_max))::integer;

  if coalesce(nullif(p_element_a, ''), '__none__') in (
       coalesce(nullif(p_element_b, ''), '__other__'),
       coalesce(nullif(p_secondary_b, ''), '__other__')
     )
     or coalesce(nullif(p_secondary_a, ''), '__none__') in (
       coalesce(nullif(p_element_b, ''), '__other__'),
       coalesce(nullif(p_secondary_b, ''), '__other__')
     ) then
    v_element_bonus := least(5, greatest(0, v_affinity_max - v_stat_bonus));
  end if;
  v_affinity_bonus := least(v_affinity_max, v_stat_bonus + v_element_bonus);
  v_mode_bonus := case when p_mode = 'balanced' then 0 else v_dominant_bonus end;
  v_calibration_bonus := least(
    v_calibration_max,
    greatest(0, coalesce(p_failure_count, 0)) * v_calibration_step
  );
  v_total := least(
    100,
    greatest(
      1,
      v_base + v_level_bonus + v_care_bonus + v_affinity_bonus
      + v_mode_bonus + v_calibration_bonus
    )
  );

  return jsonb_build_object(
    'chance', v_total,
    'base', v_base,
    'level', v_level_bonus,
    'care', v_care_bonus,
    'affinity', v_affinity_bonus,
    'mode', v_mode_bonus,
    'calibration', v_calibration_bonus
  );
end $$;

revoke all on function public.synthesis_resonance(
  integer, integer, jsonb, jsonb, jsonb, jsonb,
  text, text, text, text, text, integer, jsonb
) from public, anon, authenticated;
grant execute on function public.synthesis_resonance(
  integer, integer, jsonb, jsonb, jsonb, jsonb,
  text, text, text, text, text, integer, jsonb
) to service_role;

create or replace function public.preview_synthesis(
  p_owner uuid,
  p_source_a uuid,
  p_source_a_stage smallint,
  p_source_b uuid,
  p_source_b_stage smallint,
  p_mode text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a public.animas;
  v_b public.animas;
  v_low uuid;
  v_high uuid;
  v_slot_mode text;
  v_slot public.anima_synthesis_slots;
  v_form_a jsonb;
  v_form_b jsonb;
  v_config jsonb;
  v_breakdown jsonb;
  v_min_level integer;
  v_core_cost integer;
  v_bits_cost integer;
  v_feature boolean;
begin
  if p_source_a = p_source_b then raise exception 'SYNTHESIS_SOURCES_SAME'; end if;
  if p_source_a_stage not between 1 and 3 or p_source_b_stage not between 1 and 3 then
    raise exception 'SYNTHESIS_FORM_INVALID';
  end if;
  if p_mode not in ('dominant_a', 'balanced', 'dominant_b') then
    raise exception 'SYNTHESIS_MODE_INVALID';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into v_feature
    from public.app_config where key = 'feature_synthesis';
  if not coalesce(v_feature, false) then raise exception 'FEATURE_DISABLED'; end if;
  select coalesce((value #>> '{}')::integer, 10) into v_min_level
    from public.app_config where key = 'synthesis_min_level';
  select coalesce((value #>> '{}')::integer, 1) into v_core_cost
    from public.app_config where key = 'synthesis_core_cost';
  select coalesce((value #>> '{}')::integer, 250) into v_bits_cost
    from public.app_config where key = 'synthesis_bits_cost';

  perform public.apply_care(p_owner, least(p_source_a::text, p_source_b::text)::uuid, 'sync');
  perform public.apply_care(p_owner, greatest(p_source_a::text, p_source_b::text)::uuid, 'sync');

  select * into v_a from public.animas
   where id = p_source_a and owner_id = p_owner;
  select * into v_b from public.animas
   where id = p_source_b and owner_id = p_owner;
  if v_a.id is null or v_b.id is null then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_a.status <> 'ready' or v_b.status <> 'ready' then raise exception 'ANIMA_NOT_READY'; end if;
  if v_a.dormant_since is not null or v_b.dormant_since is not null then
    raise exception 'ANIMA_DORMANT';
  end if;
  if public.anima_level_from_exp(v_a.care_score) < v_min_level
     or public.anima_level_from_exp(v_b.care_score) < v_min_level then
    raise exception 'SYNTHESIS_LEVEL_TOO_LOW';
  end if;
  -- Preview memakai gerbang yang sama dengan attempt. Tanpa baris ini, Anima
  -- yang sedang bertarung tetap memperlihatkan angka Resonance yang menjanjikan
  -- lalu ditolak saat tombolnya ditekan.
  if public._anima_in_active_combat(p_owner, v_a.id)
     or public._anima_in_active_combat(p_owner, v_b.id) then
    raise exception 'ANIMA_IN_ACTIVE_COMBAT';
  end if;

  if p_source_a_stage = v_a.stage then
    v_form_a := jsonb_build_object(
      'sheet_path', v_a.sheet_path, 'manifest', v_a.manifest,
      'body_height_cm', v_a.body_height_cm
    );
  else
    select jsonb_build_object(
      'sheet_path', f.sheet_path, 'manifest', f.manifest,
      'body_height_cm', f.body_height_cm
    ) into v_form_a
      from public.anima_forms f
     where f.anima_id = v_a.id and f.stage = p_source_a_stage;
  end if;
  if p_source_b_stage = v_b.stage then
    v_form_b := jsonb_build_object(
      'sheet_path', v_b.sheet_path, 'manifest', v_b.manifest,
      'body_height_cm', v_b.body_height_cm
    );
  else
    select jsonb_build_object(
      'sheet_path', f.sheet_path, 'manifest', f.manifest,
      'body_height_cm', f.body_height_cm
    ) into v_form_b
      from public.anima_forms f
     where f.anima_id = v_b.id and f.stage = p_source_b_stage;
  end if;
  if coalesce(v_form_a->>'sheet_path', '') = ''
     or jsonb_typeof(v_form_a->'manifest') <> 'object'
     or coalesce(v_form_b->>'sheet_path', '') = ''
     or jsonb_typeof(v_form_b->'manifest') <> 'object' then
    raise exception 'SYNTHESIS_FORM_LOCKED';
  end if;

  v_low := least(p_source_a::text, p_source_b::text)::uuid;
  v_high := greatest(p_source_a::text, p_source_b::text)::uuid;
  v_slot_mode := case p_mode
    when 'balanced' then 'balanced'
    when 'dominant_a' then case when p_source_a = v_low then 'dominant_low' else 'dominant_high' end
    else case when p_source_b = v_low then 'dominant_low' else 'dominant_high' end
  end;
  select * into v_slot
    from public.anima_synthesis_slots
   where owner_id = p_owner
     and source_low_id = v_low
     and source_high_id = v_high
     and mode = v_slot_mode;
  if found and v_slot.status = 'succeeded' then raise exception 'SYNTHESIS_MODE_USED'; end if;

  select jsonb_build_object(
    'base', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_base'), '40'),
    'level_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_level_max'), '20'),
    'care_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_care_max'), '20'),
    'affinity_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_affinity_max'), '15'),
    'dominant_bonus', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_dominant_bonus'), '10'),
    'calibration_step', coalesce(max(value #>> '{}') filter (where key = 'synthesis_calibration_step'), '5'),
    'calibration_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_calibration_max'), '20')
  ) into v_config
    from public.app_config
   where key like 'synthesis_resonance_%'
      or key in ('synthesis_calibration_step', 'synthesis_calibration_max');

  v_breakdown := public.synthesis_resonance(
    public.anima_level_from_exp(v_a.care_score),
    public.anima_level_from_exp(v_b.care_score),
    v_a.care, v_b.care, v_a.base_stats, v_b.base_stats,
    v_a.element, v_a.secondary_element, v_b.element, v_b.secondary_element,
    p_mode, coalesce(v_slot.failure_count, 0), v_config
  );

  return jsonb_build_object(
    'source_a', jsonb_build_object(
      'id', v_a.id, 'nickname', v_a.nickname, 'level', public.anima_level_from_exp(v_a.care_score),
      'selected_stage', p_source_a_stage, 'care', v_a.care, 'base_stats', v_a.base_stats,
      'element', v_a.element, 'secondary_element', v_a.secondary_element
    ),
    'source_b', jsonb_build_object(
      'id', v_b.id, 'nickname', v_b.nickname, 'level', public.anima_level_from_exp(v_b.care_score),
      'selected_stage', p_source_b_stage, 'care', v_b.care, 'base_stats', v_b.base_stats,
      'element', v_b.element, 'secondary_element', v_b.secondary_element
    ),
    'mode', p_mode,
    'breakdown', v_breakdown,
    'cost', jsonb_build_object('cores', v_core_cost, 'bits', v_bits_cost),
    'failure_count', coalesce(v_slot.failure_count, 0),
    'cooldown_until', v_slot.cooldown_until,
    'cooldown_active', coalesce(v_slot.cooldown_until > now(), false)
  );
end $$;

revoke all on function public.preview_synthesis(
  uuid, uuid, smallint, uuid, smallint, text
) from public, anon, authenticated;
grant execute on function public.preview_synthesis(
  uuid, uuid, smallint, uuid, smallint, text
) to service_role;

create or replace function public.attempt_synthesis(
  p_owner uuid,
  p_key text,
  p_source_a uuid,
  p_source_a_stage smallint,
  p_source_b uuid,
  p_source_b_stage smallint,
  p_mode text,
  p_prompt_version text,
  p_model text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.anima_synthesis_attempts;
  v_slot public.anima_synthesis_slots;
  v_a public.animas;
  v_b public.animas;
  v_form_a jsonb;
  v_form_b jsonb;
  v_low uuid;
  v_high uuid;
  v_slot_mode text;
  v_feature boolean;
  v_min_level integer;
  v_core_cost integer;
  v_bits_cost integer;
  v_energy_penalty numeric;
  v_cooldown_seconds integer;
  v_cost_usd numeric;
  v_cap numeric;
  v_spent numeric;
  v_config jsonb;
  v_breakdown jsonb;
  v_chance integer;
  v_roll integer;
  v_profile public.profiles;
  v_weight_a numeric;
  v_result_stats jsonb;
  v_result_id uuid := gen_random_uuid();
  v_gen_id uuid := gen_random_uuid();
  v_cooldown_until timestamptz;
  v_generation_status text;
  v_name_a text;
  v_name_b text;
  v_stale public.generations;
begin
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;
  if p_source_a = p_source_b then raise exception 'SYNTHESIS_SOURCES_SAME'; end if;
  if p_source_a_stage not between 1 and 3 or p_source_b_stage not between 1 and 3 then
    raise exception 'SYNTHESIS_FORM_INVALID';
  end if;
  if p_mode not in ('dominant_a', 'balanced', 'dominant_b') then
    raise exception 'SYNTHESIS_MODE_INVALID';
  end if;

  -- Serialize different keys for one owner before checking the one-active limit.
  -- The partial unique index remains the durable backstop for future callers.
  perform pg_advisory_xact_lock(hashtextextended('synthesis:' || p_owner::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text || ':' || p_key, 0));
  select * into v_existing
    from public.anima_synthesis_attempts
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_existing.source_a_id <> p_source_a
       or v_existing.source_b_id <> p_source_b
       or v_existing.source_a_stage <> p_source_a_stage
       or v_existing.source_b_stage <> p_source_b_stage
       or v_existing.requested_mode <> p_mode then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    if v_existing.generation_id is not null then
      select status into v_generation_status
        from public.generations where id = v_existing.generation_id;
    end if;
    return jsonb_build_object(
      'outcome', v_existing.outcome,
      'resonance_succeeded', v_existing.outcome = 'claimed',
      'chance', v_existing.resonance_chance,
      'roll', v_existing.resonance_roll,
      'generation_id', v_existing.generation_id,
      'result_anima_id', v_existing.result_anima_id,
      'generation_status', v_generation_status,
      'cooldown_until', v_existing.cooldown_until,
      'replayed', true
    );
  end if;

  select coalesce((value #>> '{}')::boolean, false) into v_feature
    from public.app_config where key = 'feature_synthesis';
  if not coalesce(v_feature, false) then raise exception 'FEATURE_DISABLED'; end if;
  select coalesce((value #>> '{}')::integer, 10) into v_min_level
    from public.app_config where key = 'synthesis_min_level';
  select coalesce((value #>> '{}')::integer, 1) into v_core_cost
    from public.app_config where key = 'synthesis_core_cost';
  select coalesce((value #>> '{}')::integer, 250) into v_bits_cost
    from public.app_config where key = 'synthesis_bits_cost';
  select coalesce((value #>> '{}')::numeric, 10) into v_energy_penalty
    from public.app_config where key = 'synthesis_energy_penalty';
  select coalesce((value #>> '{}')::integer, 3600) into v_cooldown_seconds
    from public.app_config where key = 'synthesis_cooldown_seconds';
  select coalesce((value #>> '{}')::numeric, 0.073) into v_cost_usd
    from public.app_config where key = 'synthesis_cost_usd_estimate';

  -- Consistent lock order prevents reversed Source pairs from deadlocking.
  perform public.apply_care(p_owner, least(p_source_a::text, p_source_b::text)::uuid, 'sync');
  perform public.apply_care(p_owner, greatest(p_source_a::text, p_source_b::text)::uuid, 'sync');

  select * into v_a from public.animas
   where id = p_source_a and owner_id = p_owner for update;
  select * into v_b from public.animas
   where id = p_source_b and owner_id = p_owner for update;
  if v_a.id is null or v_b.id is null then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_a.status <> 'ready' or v_b.status <> 'ready' then raise exception 'ANIMA_NOT_READY'; end if;
  if v_a.dormant_since is not null or v_b.dormant_since is not null then
    raise exception 'ANIMA_DORMANT';
  end if;
  if public.anima_level_from_exp(v_a.care_score) < v_min_level
     or public.anima_level_from_exp(v_b.care_score) < v_min_level then
    raise exception 'SYNTHESIS_LEVEL_TOO_LOW';
  end if;
  if public._anima_in_active_combat(p_owner, v_a.id)
     or public._anima_in_active_combat(p_owner, v_b.id) then
    raise exception 'ANIMA_IN_ACTIVE_COMBAT';
  end if;

  if p_source_a_stage = v_a.stage then
    v_form_a := jsonb_build_object(
      'sheet_path', v_a.sheet_path, 'manifest', v_a.manifest,
      'body_height_cm', v_a.body_height_cm
    );
  else
    select jsonb_build_object(
      'sheet_path', f.sheet_path, 'manifest', f.manifest,
      'body_height_cm', f.body_height_cm
    ) into v_form_a
      from public.anima_forms f
     where f.anima_id = v_a.id and f.stage = p_source_a_stage;
  end if;
  if p_source_b_stage = v_b.stage then
    v_form_b := jsonb_build_object(
      'sheet_path', v_b.sheet_path, 'manifest', v_b.manifest,
      'body_height_cm', v_b.body_height_cm
    );
  else
    select jsonb_build_object(
      'sheet_path', f.sheet_path, 'manifest', f.manifest,
      'body_height_cm', f.body_height_cm
    ) into v_form_b
      from public.anima_forms f
     where f.anima_id = v_b.id and f.stage = p_source_b_stage;
  end if;
  if coalesce(v_form_a->>'sheet_path', '') = ''
     or jsonb_typeof(v_form_a->'manifest') <> 'object'
     or coalesce(v_form_b->>'sheet_path', '') = ''
     or jsonb_typeof(v_form_b->'manifest') <> 'object' then
    raise exception 'SYNTHESIS_FORM_LOCKED';
  end if;

  select coalesce(
    nullif(g.vision_result->>'suggested_name', ''),
    initcap(replace(v_a.species_key, '_', ' '))
  ) into v_name_a
    from public.generations g
   where g.anima_id = v_a.id
     and g.status = 'succeeded'
     and (
       (p_source_a_stage = 1 and g.kind in ('create', 'synthesis'))
       or (g.kind = 'evolve' and g.target_stage = p_source_a_stage)
     )
   order by g.finished_at desc nulls last, g.created_at desc
   limit 1;
  v_name_a := left(coalesce(nullif(v_name_a, ''), 'Anima'), 48);

  select coalesce(
    nullif(g.vision_result->>'suggested_name', ''),
    initcap(replace(v_b.species_key, '_', ' '))
  ) into v_name_b
    from public.generations g
   where g.anima_id = v_b.id
     and g.status = 'succeeded'
     and (
       (p_source_b_stage = 1 and g.kind in ('create', 'synthesis'))
       or (g.kind = 'evolve' and g.target_stage = p_source_b_stage)
     )
   order by g.finished_at desc nulls last, g.created_at desc
   limit 1;
  v_name_b := left(coalesce(nullif(v_name_b, ''), 'Anima'), 48);

  -- Self-heal a lost intent before the one-active gate. A paid Synthesis whose
  -- client never resumed (uninstall, new device, cleared data) would otherwise
  -- hold this owner's only slot forever with the Core and Bits unrefunded, since
  -- the planning and dispatch leases only expire while that generation is being
  -- resumed. `fail_synthesis` owns the refund, the slot reset, and the reference
  -- cleanup, so the sweep stays a lease check. Leases mirror evolution: Replicate
  -- cancels image jobs after 8 minutes, and the widest window leaves room for
  -- signed webhook retries.
  for v_stale in
    select g.*
      from public.generations g
      join public.anima_synthesis_slots s on s.active_generation_id = g.id
     where g.owner_id = p_owner
       and g.kind = 'synthesis'
       and g.status in ('pending', 'running')
       and s.status = 'pending'
       and (
         (
           g.dispatch_started_at is null
           and coalesce(g.vision_started_at, g.created_at) <= now() - interval '3 minutes'
         )
         or (
           g.dispatch_started_at is not null
           and g.prediction_id is null
           and g.dispatch_started_at <= now() - interval '10 minutes'
         )
         or (
           g.prediction_id is not null
           and g.dispatch_started_at <= now() - interval '20 minutes'
         )
       )
  loop
    perform public.fail_synthesis(v_stale.id, 'SYNTHESIS_STALE_RECOVERED');
  end loop;

  if exists (
    select 1 from public.anima_synthesis_slots
     where owner_id = p_owner and status = 'pending'
  ) then
    raise exception 'SYNTHESIS_ALREADY_ACTIVE';
  end if;

  v_low := least(p_source_a::text, p_source_b::text)::uuid;
  v_high := greatest(p_source_a::text, p_source_b::text)::uuid;
  v_slot_mode := case p_mode
    when 'balanced' then 'balanced'
    when 'dominant_a' then case when p_source_a = v_low then 'dominant_low' else 'dominant_high' end
    else case when p_source_b = v_low then 'dominant_low' else 'dominant_high' end
  end;

  insert into public.anima_synthesis_slots (
    owner_id, source_low_id, source_high_id, mode
  ) values (
    p_owner, v_low, v_high, v_slot_mode
  )
  on conflict (owner_id, source_low_id, source_high_id, mode) do nothing;

  select * into v_slot
    from public.anima_synthesis_slots
   where owner_id = p_owner
     and source_low_id = v_low
     and source_high_id = v_high
     and mode = v_slot_mode
   for update;
  if v_slot.status = 'succeeded' then raise exception 'SYNTHESIS_MODE_USED'; end if;
  if v_slot.status = 'pending' then raise exception 'SYNTHESIS_IN_PROGRESS'; end if;
  if v_slot.cooldown_until is not null and v_slot.cooldown_until > now() then
    raise exception 'SYNTHESIS_COOLDOWN';
  end if;

  perform public._grant_weekly_core_if_eligible(p_owner);
  select * into v_profile from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_profile.genesis_cores < v_core_cost then raise exception 'NO_CORE'; end if;
  if v_profile.bits < v_bits_cost then raise exception 'NO_BITS'; end if;

  select (value #>> '{}')::numeric into v_cap
    from public.app_config where key = 'daily_spend_cap_usd' for update;
  if v_cap is not null then
    select coalesce(sum(cost_usd_estimate), 0) into v_spent
      from public.generations
     where created_at >= date_trunc('day', now()) and cost_usd_estimate > 0;
    if v_spent + v_cost_usd > v_cap then raise exception 'SPEND_CAP'; end if;
  end if;

  select jsonb_build_object(
    'base', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_base'), '40'),
    'level_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_level_max'), '20'),
    'care_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_care_max'), '20'),
    'affinity_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_affinity_max'), '15'),
    'dominant_bonus', coalesce(max(value #>> '{}') filter (where key = 'synthesis_resonance_dominant_bonus'), '10'),
    'calibration_step', coalesce(max(value #>> '{}') filter (where key = 'synthesis_calibration_step'), '5'),
    'calibration_max', coalesce(max(value #>> '{}') filter (where key = 'synthesis_calibration_max'), '20')
  ) into v_config
    from public.app_config
   where key like 'synthesis_resonance_%'
      or key in ('synthesis_calibration_step', 'synthesis_calibration_max');
  v_breakdown := public.synthesis_resonance(
    public.anima_level_from_exp(v_a.care_score),
    public.anima_level_from_exp(v_b.care_score),
    v_a.care, v_b.care, v_a.base_stats, v_b.base_stats,
    v_a.element, v_a.secondary_element, v_b.element, v_b.secondary_element,
    p_mode, v_slot.failure_count, v_config
  );
  v_chance := (v_breakdown->>'chance')::integer;
  v_roll := floor(random() * 100)::integer + 1;

  if v_roll > v_chance then
    v_cooldown_until := now() + make_interval(secs => v_cooldown_seconds);
    update public.animas
       set care = jsonb_set(
             care,
             '{energy}',
             to_jsonb(round(greatest(
               0,
               coalesce((care->>'energy')::numeric, 0) - v_energy_penalty
             ), 2)),
             true
           ),
           care_synced_at = now()
     where id in (v_a.id, v_b.id);
    update public.anima_synthesis_slots
       set failure_count = failure_count + 1,
           cooldown_until = v_cooldown_until,
           updated_at = now()
     where id = v_slot.id
    returning * into v_slot;
    insert into public.anima_synthesis_attempts (
      owner_id, slot_id, idempotency_key,
      source_a_id, source_b_id, source_a_stage, source_b_stage, requested_mode,
      resonance_chance, resonance_roll, outcome, cooldown_until
    ) values (
      p_owner, v_slot.id, p_key,
      p_source_a, p_source_b, p_source_a_stage, p_source_b_stage, p_mode,
      v_chance, v_roll, 'failed', v_cooldown_until
    );
    return jsonb_build_object(
      'outcome', 'failed',
      'resonance_succeeded', false,
      'chance', v_chance,
      'roll', v_roll,
      'breakdown', v_breakdown,
      'cooldown_until', v_cooldown_until,
      'failure_count', v_slot.failure_count,
      'calibration', least(
        coalesce((v_config->>'calibration_max')::integer, 20),
        v_slot.failure_count * coalesce((v_config->>'calibration_step')::integer, 5)
      ),
      'source_a_care', (select care from public.animas where id = v_a.id),
      'source_b_care', (select care from public.animas where id = v_b.id),
      'replayed', false
    );
  end if;

  v_weight_a := case p_mode
    when 'dominant_a' then 0.70
    when 'dominant_b' then 0.30
    else 0.50
  end;
  v_result_stats := jsonb_build_object(
    'hp', round(
      coalesce((v_a.base_stats->>'hp')::numeric, 50) * v_weight_a
      + coalesce((v_b.base_stats->>'hp')::numeric, 50) * (1 - v_weight_a)
    ),
    'atk', round(
      coalesce((v_a.base_stats->>'atk')::numeric, 50) * v_weight_a
      + coalesce((v_b.base_stats->>'atk')::numeric, 50) * (1 - v_weight_a)
    ),
    'def', round(
      coalesce((v_a.base_stats->>'def')::numeric, 50) * v_weight_a
      + coalesce((v_b.base_stats->>'def')::numeric, 50) * (1 - v_weight_a)
    ),
    'spd', round(
      coalesce((v_a.base_stats->>'spd')::numeric, 50) * v_weight_a
      + coalesce((v_b.base_stats->>'spd')::numeric, 50) * (1 - v_weight_a)
    ),
    'special', round(
      coalesce((v_a.base_stats->>'special')::numeric, 50) * v_weight_a
      + coalesce((v_b.base_stats->>'special')::numeric, 50) * (1 - v_weight_a)
    )
  );

  -- `generations` is unique on (owner_id, idempotency_key) across every kind, so
  -- a namespaced key that already exists must be refused before currency moves.
  -- The advisory lock above makes this check authoritative rather than a race.
  if exists (
    select 1 from public.generations
     where owner_id = p_owner and idempotency_key = 'synthesis:' || p_key
  ) then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;

  update public.profiles
     set genesis_cores = genesis_cores - v_core_cost,
         bits = bits - v_bits_cost
   where id = p_owner;

  insert into public.animas (
    id, owner_id, nickname, species_key, color_bucket, stage, status,
    subject_kind, element, secondary_element, typing_version,
    rarity, base_stats, care, body_height_cm, strike_name, surge_name
  ) values (
    v_result_id, p_owner, 'Synthesis', 'synthesis_pending', 'synthesis', 1, 'incubating',
    'object',
    case when v_weight_a >= 0.5 then v_a.element else v_b.element end,
    null, 2,
    greatest(1, least(5, round((v_a.rarity + v_b.rarity)::numeric / 2.0)::integer)),
    v_result_stats,
    '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
    greatest(20, least(2000, round(
      coalesce((v_form_a->>'body_height_cm')::numeric, v_a.body_height_cm) * v_weight_a
      + coalesce((v_form_b->>'body_height_cm')::numeric, v_b.body_height_cm) * (1 - v_weight_a)
    )::integer)),
    '', ''
  );

  insert into public.generations (
    id, owner_id, anima_id, idempotency_key, kind, status,
    prompt_version, model, cost_usd_estimate, vision_result
  ) values (
    v_gen_id, p_owner, v_result_id, 'synthesis:' || p_key, 'synthesis', 'pending',
    p_prompt_version, p_model, v_cost_usd, null
  );

  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
  values
    (p_owner, 'genesis_cores', -v_core_cost, 'synthesis', v_gen_id),
    (p_owner, 'bits', -v_bits_cost, 'synthesis_bits', v_gen_id);

  update public.anima_synthesis_slots
     set status = 'pending',
         cooldown_until = null,
         active_generation_id = v_gen_id,
         result_anima_id = v_result_id,
         successful_resonance = v_chance,
         source_a_snapshot = jsonb_build_object(
           'id', v_a.id, 'name', v_name_a, 'selected_stage', p_source_a_stage,
           'sheet_path', v_form_a->>'sheet_path', 'manifest', v_form_a->'manifest',
           'element', v_a.element, 'secondary_element', v_a.secondary_element,
           'base_stats', v_a.base_stats, 'rarity', v_a.rarity,
           'body_height_cm', v_form_a->'body_height_cm'
         ),
         source_b_snapshot = jsonb_build_object(
           'id', v_b.id, 'name', v_name_b, 'selected_stage', p_source_b_stage,
           'sheet_path', v_form_b->>'sheet_path', 'manifest', v_form_b->'manifest',
           'element', v_b.element, 'secondary_element', v_b.secondary_element,
           'base_stats', v_b.base_stats, 'rarity', v_b.rarity,
           'body_height_cm', v_form_b->'body_height_cm'
         ),
         reference_paths = null,
         synthesis_plan = null,
         updated_at = now()
   where id = v_slot.id
  returning * into v_slot;

  insert into public.anima_synthesis_attempts (
    owner_id, slot_id, idempotency_key,
    source_a_id, source_b_id, source_a_stage, source_b_stage, requested_mode,
    resonance_chance, resonance_roll, outcome, generation_id, result_anima_id
  ) values (
    p_owner, v_slot.id, p_key,
    p_source_a, p_source_b, p_source_a_stage, p_source_b_stage, p_mode,
    v_chance, v_roll, 'claimed', v_gen_id, v_result_id
  );

  return jsonb_build_object(
    'outcome', 'claimed',
    'resonance_succeeded', true,
    'chance', v_chance,
    'roll', v_roll,
    'breakdown', v_breakdown,
    'generation_id', v_gen_id,
    'result_anima_id', v_result_id,
    'generation_status', 'pending',
    'source_a', v_slot.source_a_snapshot,
    'source_b', v_slot.source_b_snapshot,
    'cost', jsonb_build_object('cores', v_core_cost, 'bits', v_bits_cost),
    'replayed', false
  );
end $$;

revoke all on function public.attempt_synthesis(
  uuid, text, uuid, smallint, uuid, smallint, text, text, text
) from public, anon, authenticated;
grant execute on function public.attempt_synthesis(
  uuid, text, uuid, smallint, uuid, smallint, text, text, text
) to service_role;

create or replace function public.claim_synthesis_planning(
  p_owner uuid,
  p_gen_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
begin
  select * into v_gen from public.generations
   where id = p_gen_id and owner_id = p_owner for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object('status', 'succeeded', 'replayed', true);
  end if;
  if v_gen.status = 'failed' then
    return jsonb_build_object('status', 'failed', 'replayed', true);
  end if;
  if v_gen.vision_result is not null then
    return jsonb_build_object('status', v_gen.status, 'plan_ready', true, 'replayed', true);
  end if;
  if v_gen.vision_started_at is not null then
    if v_gen.vision_started_at > now() - interval '3 minutes' then
      return jsonb_build_object('status', 'planning', 'planning', true, 'replayed', true);
    end if;
    perform public.fail_synthesis(v_gen.id, 'SYNTHESIS_PLAN_TIMEOUT');
    return jsonb_build_object('status', 'failed', 'timed_out', true);
  end if;
  update public.generations set vision_started_at = now() where id = v_gen.id;
  return jsonb_build_object('status', 'planning', 'planning_claimed', true);
end $$;

revoke all on function public.claim_synthesis_planning(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_synthesis_planning(uuid, uuid)
  to service_role;

create or replace function public.store_synthesis_references(
  p_owner uuid,
  p_gen_id uuid,
  p_reference_paths jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_slot public.anima_synthesis_slots;
begin
  if p_reference_paths is null or jsonb_typeof(p_reference_paths) <> 'object'
     or coalesce(p_reference_paths->>'source_a', '') = ''
     or coalesce(p_reference_paths->>'source_b', '') = '' then
    raise exception 'SYNTHESIS_REFERENCES_INVALID';
  end if;
  select * into v_gen from public.generations
   where id = p_gen_id and owner_id = p_owner for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status in ('failed', 'succeeded') then
    return jsonb_build_object('status', v_gen.status, 'replayed', true);
  end if;
  select * into v_slot from public.anima_synthesis_slots
   where active_generation_id = p_gen_id for update;
  if not found or v_slot.status <> 'pending' then raise exception 'SYNTHESIS_SLOT_MISSING'; end if;
  if v_slot.reference_paths is not null and v_slot.reference_paths <> p_reference_paths then
    raise exception 'SYNTHESIS_REFERENCE_MISMATCH';
  end if;
  update public.anima_synthesis_slots
     set source_a_snapshot = source_a_snapshot || jsonb_build_object(
           'thumbnail_path', p_reference_paths->>'source_a'
         ),
         source_b_snapshot = source_b_snapshot || jsonb_build_object(
           'thumbnail_path', p_reference_paths->>'source_b'
         ),
         reference_paths = p_reference_paths,
         updated_at = now()
   where id = v_slot.id;
  return jsonb_build_object(
    'generation_id', v_gen.id,
    'source_a', p_reference_paths->>'source_a',
    'source_b', p_reference_paths->>'source_b',
    'replayed', v_slot.reference_paths is not null
  );
end $$;

revoke all on function public.store_synthesis_references(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.store_synthesis_references(uuid, uuid, jsonb)
  to service_role;

create or replace function public._synthesis_stat_total(p_stats jsonb)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(coalesce((p_stats->>stat_key)::numeric, 50)), 0)
    from unnest(array['hp', 'atk', 'def', 'spd', 'special']) as stat_key;
$$;

revoke all on function public._synthesis_stat_total(jsonb)
  from public, anon, authenticated;
grant execute on function public._synthesis_stat_total(jsonb) to service_role;

create or replace function public.reserve_synthesis_plan(
  p_owner uuid,
  p_gen_id uuid,
  p_plan jsonb,
  p_reference_paths jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_slot public.anima_synthesis_slots;
  v_attempt public.anima_synthesis_attempts;
  v_history jsonb;
  v_weight_a numeric;
  v_budget integer;
begin
  if p_plan is null or jsonb_typeof(p_plan) <> 'object' then
    raise exception 'SYNTHESIS_PLAN_INVALID';
  end if;
  if p_reference_paths is null or jsonb_typeof(p_reference_paths) <> 'object'
     or coalesce(p_reference_paths->>'source_a', '') = ''
     or coalesce(p_reference_paths->>'source_b', '') = '' then
    raise exception 'SYNTHESIS_REFERENCES_INVALID';
  end if;

  select * into v_gen from public.generations
   where id = p_gen_id and owner_id = p_owner for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'failed' then raise exception 'SYNTHESIS_FAILED'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object('generation_id', v_gen.id, 'status', 'succeeded', 'replayed', true);
  end if;

  select * into v_slot from public.anima_synthesis_slots
   where active_generation_id = p_gen_id for update;
  if not found or v_slot.status <> 'pending' then raise exception 'SYNTHESIS_SLOT_MISSING'; end if;
  select * into v_attempt from public.anima_synthesis_attempts
   where generation_id = p_gen_id;
  if not found then raise exception 'SYNTHESIS_ATTEMPT_MISSING'; end if;

  if v_gen.vision_result is not null then
    if v_gen.vision_result <> p_plan then raise exception 'SYNTHESIS_PLAN_MISMATCH'; end if;
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'status', v_gen.status,
      'replayed', true
    );
  end if;

  -- The Edge Function already normalizes the plan, but the stat budget is the one
  -- number a buggy deploy could turn into a permanently overpowered Anima, so it
  -- is re-derived here from the snapshots the roll was priced against. Only an
  -- overshoot is rejected; landing under budget is not an exploit.
  v_weight_a := case v_attempt.requested_mode
    when 'dominant_a' then 0.70
    when 'dominant_b' then 0.30
    else 0.50
  end;
  v_budget := least(475, greatest(50, round(
    public._synthesis_stat_total(v_slot.source_a_snapshot->'base_stats') * v_weight_a
    + public._synthesis_stat_total(v_slot.source_b_snapshot->'base_stats') * (1 - v_weight_a)
  )::integer));
  if jsonb_typeof(p_plan->'base_stats') <> 'object'
     or exists (
       select 1 from unnest(array['hp', 'atk', 'def', 'spd', 'special']) as stat_key
        where coalesce((p_plan->'base_stats'->>stat_key)::numeric, -1) not between 10 and 95
     )
     or public._synthesis_stat_total(p_plan->'base_stats') > v_budget then
    raise exception 'SYNTHESIS_PLAN_STATS_INVALID';
  end if;

  update public.anima_synthesis_slots
     set source_a_snapshot = source_a_snapshot || jsonb_build_object(
           'thumbnail_path', p_reference_paths->>'source_a'
         ),
         source_b_snapshot = source_b_snapshot || jsonb_build_object(
           'thumbnail_path', p_reference_paths->>'source_b'
         ),
         reference_paths = p_reference_paths,
         synthesis_plan = p_plan,
         updated_at = now()
   where id = v_slot.id
  returning * into v_slot;

  v_history := jsonb_build_object(
    'mode', v_attempt.requested_mode,
    'resonance', v_attempt.resonance_chance,
    'created_at', v_attempt.created_at,
    'source_a', v_slot.source_a_snapshot - 'sheet_path' - 'manifest' - 'base_stats',
    'source_b', v_slot.source_b_snapshot - 'sheet_path' - 'manifest' - 'base_stats',
    'inheritance_summary', coalesce(p_plan->'inheritance_summary', '{}'::jsonb)
  );

  update public.generations
     set vision_result = p_plan,
         vision_started_at = coalesce(vision_started_at, now())
   where id = v_gen.id;

  update public.animas
     set nickname = left(coalesce(nullif(btrim(p_plan->>'suggested_name'), ''), 'Synthesis'), 32),
         species_key = left(coalesce(nullif(btrim(p_plan->>'species_key'), ''), 'synthesis_result'), 80),
         color_bucket = left(coalesce(nullif(btrim(p_plan->>'color_bucket'), ''), 'synthesis'), 40),
         subject_kind = case when p_plan->>'subject_kind' = 'animal' then 'animal' else 'object' end,
         element = p_plan->>'primary_element',
         secondary_element = nullif(p_plan->>'secondary_element', ''),
         rarity = greatest(1, least(5, coalesce((p_plan->>'rarity')::integer, 1))),
         base_stats = p_plan->'base_stats',
         body_height_cm = greatest(20, least(2000, coalesce((p_plan->>'body_height_cm')::integer, 120))),
         strike_name = left(coalesce(p_plan->>'strike_name', ''), 24),
         surge_name = left(coalesce(p_plan->>'surge_name', ''), 24),
         strike_effect_id = left(coalesce(p_plan->>'strike_effect_id', ''), 32),
         surge_effect_id = left(coalesce(p_plan->>'surge_effect_id', ''), 32),
         synthesis_history = v_history
   where id = v_gen.anima_id;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_gen.anima_id,
    'status', v_gen.status,
    'replayed', false
  );
end $$;

revoke all on function public.reserve_synthesis_plan(
  uuid, uuid, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.reserve_synthesis_plan(
  uuid, uuid, jsonb, jsonb
) to service_role;

create or replace function public.fail_synthesis(
  p_gen_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_slot public.anima_synthesis_slots;
  v_core_refund integer := 0;
  v_bits_refund integer := 0;
  v_path text;
begin
  select * into v_gen from public.generations where id = p_gen_id for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object('generation_id', v_gen.id, 'status', 'succeeded', 'replayed', true);
  end if;

  select * into v_slot from public.anima_synthesis_slots
   where active_generation_id = p_gen_id for update;

  if not exists (
    select 1 from public.quota_ledger
     where ref_id = p_gen_id and reason = 'refund'
  ) then
    select coalesce(-sum(delta), 0)::integer into v_core_refund
      from public.quota_ledger
     where ref_id = p_gen_id and currency = 'genesis_cores' and delta < 0;
    if v_core_refund > 0 then
      update public.profiles
         set genesis_cores = genesis_cores + v_core_refund
       where id = v_gen.owner_id;
      insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
      values (v_gen.owner_id, 'genesis_cores', v_core_refund, 'refund', p_gen_id);
    end if;
  end if;

  if not exists (
    select 1 from public.quota_ledger
     where ref_id = p_gen_id and reason = 'synthesis_bits_refund'
  ) then
    select coalesce(-sum(delta), 0)::integer into v_bits_refund
      from public.quota_ledger
     where ref_id = p_gen_id and currency = 'bits' and delta < 0;
    if v_bits_refund > 0 then
      update public.profiles
         set bits = bits + v_bits_refund
       where id = v_gen.owner_id;
      insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
      values (v_gen.owner_id, 'bits', v_bits_refund, 'synthesis_bits_refund', p_gen_id);
    end if;
  end if;

  update public.generations
     set status = 'failed',
         error = left(coalesce(p_reason, 'SYNTHESIS_FAILED'), 500),
         finished_at = coalesce(finished_at, now())
   where id = p_gen_id
  returning * into v_gen;
  update public.animas
     set status = 'failed',
         synthesis_history = null
   where id = v_gen.anima_id and status = 'incubating';

  if v_slot.id is not null then
    if v_slot.reference_paths is not null then
      for v_path in
        select value from jsonb_each_text(v_slot.reference_paths)
      loop
        if coalesce(v_path, '') <> '' then
          insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
          values ('anima_sheets', v_path, 'synthesis_failed');
        end if;
      end loop;
    end if;
    update public.anima_synthesis_slots
       set status = 'open',
           active_generation_id = null,
           result_anima_id = null,
           successful_resonance = null,
           reference_paths = null,
           synthesis_plan = null,
           updated_at = now()
     where id = v_slot.id;
  end if;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'status', 'failed',
    'core_refund', v_core_refund,
    'bits_refund', v_bits_refund
  );
end $$;

revoke all on function public.fail_synthesis(uuid, text)
  from public, anon, authenticated;
grant execute on function public.fail_synthesis(uuid, text) to service_role;

create or replace function public.claim_synthesis_dispatch(
  p_owner uuid,
  p_gen_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
begin
  select * into v_gen from public.generations
   where id = p_gen_id and owner_id = p_owner for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object('generation_id', v_gen.id, 'status', 'succeeded', 'replayed', true);
  end if;
  if v_gen.status = 'failed' then
    return jsonb_build_object('generation_id', v_gen.id, 'status', 'failed', 'replayed', true);
  end if;
  if v_gen.vision_result is null then raise exception 'SYNTHESIS_PLAN_MISSING'; end if;

  if v_gen.prediction_id is not null then
    if v_gen.dispatch_started_at <= now() - interval '20 minutes' then
      perform public.fail_synthesis(v_gen.id, 'GENERATION_COMPLETION_TIMEOUT');
      return jsonb_build_object(
        'generation_id', v_gen.id, 'status', 'failed', 'timed_out', true
      );
    end if;
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'prediction_id', v_gen.prediction_id,
      'replayed', true
    );
  end if;

  if v_gen.dispatch_started_at is not null then
    if v_gen.dispatch_started_at > now() - interval '10 minutes' then
      return jsonb_build_object('generation_id', v_gen.id, 'dispatching', true);
    end if;
    perform public.fail_synthesis(v_gen.id, 'GENERATION_DISPATCH_TIMEOUT');
    return jsonb_build_object(
      'generation_id', v_gen.id, 'status', 'failed', 'timed_out', true
    );
  end if;

  update public.generations
     set status = 'running', dispatch_started_at = now()
   where id = v_gen.id;
  return jsonb_build_object('generation_id', v_gen.id, 'ready', true);
end $$;

revoke all on function public.claim_synthesis_dispatch(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_synthesis_dispatch(uuid, uuid)
  to service_role;

create or replace function public.attach_synthesis_prediction(
  p_gen_id uuid,
  p_prediction_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
begin
  if p_prediction_id is null or length(btrim(p_prediction_id)) = 0 then
    raise exception 'INVALID_PREDICTION_ID';
  end if;
  select * into v_gen from public.generations where id = p_gen_id for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status in ('succeeded', 'failed') then
    return jsonb_build_object(
      'generation_id', v_gen.id, 'status', v_gen.status, 'attached', false
    );
  end if;
  if v_gen.prediction_id is not null and v_gen.prediction_id <> p_prediction_id then
    raise exception 'PREDICTION_MISMATCH';
  end if;
  update public.generations
     set prediction_id = coalesce(prediction_id, p_prediction_id),
         status = 'running'
   where id = p_gen_id
  returning * into v_gen;
  return jsonb_build_object(
    'generation_id', v_gen.id, 'prediction_id', v_gen.prediction_id, 'attached', true
  );
end $$;

revoke all on function public.attach_synthesis_prediction(uuid, text)
  from public, anon, authenticated;
grant execute on function public.attach_synthesis_prediction(uuid, text)
  to service_role;

create or replace function public.complete_synthesis(
  p_gen_id uuid,
  p_sheet_path text,
  p_manifest jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_slot public.anima_synthesis_slots;
begin
  if coalesce(p_sheet_path, '') = ''
     or p_manifest is null
     or jsonb_typeof(p_manifest) <> 'object' then
    raise exception 'SYNTHESIS_ART_INVALID';
  end if;
  select * into v_gen from public.generations where id = p_gen_id for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'synthesis' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'failed' then raise exception 'SYNTHESIS_FAILED'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object(
      'generation_id', v_gen.id, 'anima_id', v_gen.anima_id,
      'status', 'succeeded', 'replayed', true
    );
  end if;
  if v_gen.vision_result is null then raise exception 'SYNTHESIS_PLAN_MISSING'; end if;

  update public.animas
     set status = 'ready', sheet_path = p_sheet_path, manifest = p_manifest
   where id = v_gen.anima_id and owner_id = v_gen.owner_id;
  update public.generations
     set status = 'succeeded', finished_at = now(), error = null
   where id = v_gen.id
  returning * into v_gen;
  update public.anima_synthesis_slots
     set status = 'succeeded', succeeded_at = now(), updated_at = now()
   where active_generation_id = v_gen.id
  returning * into v_slot;
  if not found then raise exception 'SYNTHESIS_SLOT_MISSING'; end if;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_gen.anima_id,
    'status', 'succeeded',
    'slot_id', v_slot.id,
    'replayed', false
  );
end $$;

revoke all on function public.complete_synthesis(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_synthesis(uuid, text, jsonb)
  to service_role;

create or replace function public.guard_synthesis_source_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.anima_synthesis_slots
     where owner_id = old.owner_id
       and status = 'pending'
       and (source_low_id = old.id or source_high_id = old.id)
  ) then
    raise exception 'SYNTHESIS_SOURCE_LOCKED';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists animas_guard_pending_synthesis_delete on public.animas;
create trigger animas_guard_pending_synthesis_delete
before delete on public.animas
for each row execute function public.guard_synthesis_source_mutation();

drop trigger if exists animas_guard_pending_synthesis_evolve on public.animas;
create trigger animas_guard_pending_synthesis_evolve
before update of status on public.animas
for each row
when (new.status = 'evolving' and old.status is distinct from new.status)
execute function public.guard_synthesis_source_mutation();

revoke all on function public.guard_synthesis_source_mutation()
  from public, anon, authenticated;
grant execute on function public.guard_synthesis_source_mutation()
  to service_role;

create or replace function public.copy_synthesis_history_to_atlas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'ready' and new.synthesis_history is not null then
    update public.atlas_forms
       set synthesis_history = new.synthesis_history,
           updated_at = now()
     where anima_id = new.id and stage = new.stage;
  end if;
  return new;
end $$;

drop trigger if exists zz_anima_synthesis_history_to_atlas on public.animas;
create trigger zz_anima_synthesis_history_to_atlas
after insert or update of status, stage, synthesis_history on public.animas
for each row execute function public.copy_synthesis_history_to_atlas();

revoke all on function public.copy_synthesis_history_to_atlas()
  from public, anon, authenticated;
grant execute on function public.copy_synthesis_history_to_atlas()
  to service_role;
