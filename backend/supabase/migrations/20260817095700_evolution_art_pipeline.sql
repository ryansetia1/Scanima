-- Evolution art pipeline (feature-flagged, not live). Schema + service-role RPCs
-- only; no Core debit/refund on evolve.

insert into public.app_config (key, value)
values ('feature_evolution', 'false'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.app_config (key, value)
values ('evolution_prompt_version', '"v21"'::jsonb)
on conflict (key) do nothing;

alter table public.animas
  drop constraint if exists animas_status_dikenal;

alter table public.animas
  add constraint animas_status_dikenal
    check (status in ('incubating', 'ready', 'failed', 'evolving'));

alter table public.animas
  add column if not exists evolution_version smallint not null default 0,
  add column if not exists strike_effect_id text not null default '',
  add column if not exists surge_effect_id text not null default '';

alter table public.animas
  add constraint animas_evolution_version_nonnegative
    check (evolution_version >= 0);

alter table public.generations
  add column if not exists target_stage smallint,
  add column if not exists vision_started_at timestamptz,
  add column if not exists dispatch_started_at timestamptz;

alter table public.generations
  add constraint generations_target_stage_valid
    check (target_stage is null or target_stage between 1 and 3);

create unique index if not exists animas_one_evolving_per_owner_idx
  on public.animas (owner_id)
  where status = 'evolving';

create table if not exists public.anima_forms (
  anima_id           uuid not null references public.animas(id) on delete cascade,
  stage              smallint not null,
  sheet_path         text not null,
  manifest           jsonb not null,
  body_height_cm     integer not null,
  strike_name        text not null default '',
  surge_name         text not null default '',
  strike_effect_id   text not null default '',
  surge_effect_id    text not null default '',
  evolution_plan     jsonb,
  reference_path     text,
  generation_id      uuid references public.generations(id) on delete set null,
  created_at         timestamptz not null default now(),
  primary key (anima_id, stage),
  constraint anima_forms_stage_valid check (stage between 1 and 3),
  constraint anima_forms_height_valid check (body_height_cm between 20 and 2000)
);

create index if not exists anima_forms_generation_idx
  on public.anima_forms (generation_id)
  where generation_id is not null;

alter table public.anima_forms enable row level security;

revoke all on public.anima_forms from public, anon, authenticated;
grant all on public.anima_forms to service_role;

create or replace function public.queue_anima_form_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.sheet_path is not null and old.sheet_path <> '' then
    insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
    values ('anima_sheets', old.sheet_path, 'anima_form_deleted');
  end if;
  if old.reference_path is not null
     and old.reference_path <> ''
     and old.reference_path is distinct from old.sheet_path then
    insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
    values ('anima_sheets', old.reference_path, 'anima_form_reference_deleted');
  end if;
  return old;
end $$;

drop trigger if exists anima_form_cleanup_private_assets on public.anima_forms;
create trigger anima_form_cleanup_private_assets
before delete on public.anima_forms
for each row execute function public.queue_anima_form_cleanup();

revoke all on function public.queue_anima_form_cleanup()
  from public, anon, authenticated;
grant execute on function public.queue_anima_form_cleanup() to service_role;

drop policy if exists "hapus anima sendiri" on public.animas;

create policy "hapus anima sendiri" on public.animas
  for delete to authenticated
  using (
    (select auth.uid()) = owner_id
    and status <> 'evolving'
  );

create or replace function public._anima_in_active_combat(p_owner uuid, p_anima_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.battle_sessions s
     where s.owner_id = p_owner
       and s.player_anima_id = p_anima_id
       and s.status = 'active'
       and s.expires_at > now()
  )
  or exists (
    select 1
      from public.team_battle_sessions s
      join public.anima_team_members m
        on m.team_id = s.player_team_id
       and m.anima_id = p_anima_id
     where s.owner_id = p_owner
       and s.status = 'active'
       and s.expires_at > now()
  )
  or exists (
    select 1
      from public.team_battle_sessions s
     where s.owner_id = p_owner
       and s.status = 'active'
       and s.expires_at > now()
       and s.player_snapshot @> jsonb_build_array(jsonb_build_object('anima_id', p_anima_id::text))
  )
  or exists (
    select 1
      from public.expedition_runs r
      join public.anima_team_members m
        on m.team_id = r.team_id
       and m.anima_id = p_anima_id
     where r.owner_id = p_owner
       and r.status in ('checkpoint', 'active')
  )
  or exists (
    select 1
      from public.expedition_runs r
     where r.owner_id = p_owner
       and r.status in ('checkpoint', 'active')
       and r.party_state @> jsonb_build_array(jsonb_build_object('anima_id', p_anima_id::text))
  );
$$;

revoke all on function public._anima_in_active_combat(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public._anima_in_active_combat(uuid, uuid) to service_role;

create or replace function public.begin_evolution(
  p_owner uuid,
  p_anima_id uuid,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enabled boolean;
  v_anima public.animas;
  v_gen public.generations;
  v_target_stage smallint;
  v_min_exp integer;
begin
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  -- A kill switch blocks new spend, not status/resume for work already claimed.
  select * into v_gen
    from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_gen.anima_id is distinct from p_anima_id or v_gen.kind <> 'evolve' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into v_anima
      from public.animas
     where id = p_anima_id and owner_id = p_owner;
    if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_anima.id,
      'target_stage', v_gen.target_stage,
      'prior_stage', v_anima.stage,
      'sheet_path', v_anima.sheet_path,
      'manifest', v_anima.manifest,
      'replayed', true,
      'vision_result', v_gen.vision_result,
      'capture_metadata', jsonb_build_object(
        'species_key', v_anima.species_key,
        'color_bucket', v_anima.color_bucket,
        'subject_kind', v_anima.subject_kind,
        'element', v_anima.element,
        'secondary_element', v_anima.secondary_element,
        'body_height_cm', v_anima.body_height_cm,
        'strike_name', v_anima.strike_name,
        'surge_name', v_anima.surge_name,
        'strike_effect_id', v_anima.strike_effect_id,
        'surge_effect_id', v_anima.surge_effect_id
      )
    );
  end if;

  select coalesce((ac.value #>> '{}')::boolean, false) into v_enabled
    from public.app_config ac
   where ac.key = 'feature_evolution';
  if not coalesce(v_enabled, false) then
    raise exception 'FEATURE_DISABLED';
  end if;

  perform 1 from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  -- Self-heal a lost local intent/webhook before checking the one-active gate.
  -- Replicate cancels image jobs after 8 minutes; the wider final lease leaves
  -- time for signed webhook retries without blocking this owner forever.
  for v_gen in
    select g.*
      from public.generations g
      join public.animas a on a.id = g.anima_id
     where g.owner_id = p_owner
       and g.kind = 'evolve'
       and g.status in ('pending', 'running')
       and a.status = 'evolving'
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
     for update of g
  loop
    update public.generations
       set status = 'failed',
           error = 'EVOLUTION_STALE_RECOVERED',
           finished_at = coalesce(finished_at, now())
     where id = v_gen.id;
    update public.animas
       set status = 'ready'
     where id = v_gen.anima_id and status = 'evolving';
    insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
    values (
      'anima_sheets',
      format('%s/%s/evolution_refs/%s.png', v_gen.owner_id, v_gen.anima_id, v_gen.id),
      'evolution_stale_recovered'
    );
  end loop;

  update public.animas a
     set status = 'ready'
   where a.owner_id = p_owner
     and a.status = 'evolving'
     and not exists (
       select 1
         from public.generations g
        where g.anima_id = a.id
          and g.kind = 'evolve'
          and g.status in ('pending', 'running')
     );

  select * into v_anima
    from public.animas
   where id = p_anima_id and owner_id = p_owner
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;

  if v_anima.status = 'evolving' then
    raise exception 'EVOLUTION_IN_PROGRESS';
  end if;
  if v_anima.status <> 'ready' then
    raise exception 'ANIMA_NOT_READY';
  end if;
  if v_anima.sheet_path is null or v_anima.sheet_path = '' then
    raise exception 'ANIMA_NO_SHEET';
  end if;
  if v_anima.manifest is null or jsonb_typeof(v_anima.manifest) <> 'object' then
    raise exception 'ANIMA_NO_MANIFEST';
  end if;

  if exists (
    select 1 from public.animas a
     where a.owner_id = p_owner and a.status = 'evolving' and a.id <> p_anima_id
  ) then
    raise exception 'EVOLUTION_ALREADY_ACTIVE';
  end if;

  if public._anima_in_active_combat(p_owner, p_anima_id) then
    raise exception 'ANIMA_IN_ACTIVE_COMBAT';
  end if;

  if v_anima.stage >= 3 then
    raise exception 'EVOLUTION_MAX_STAGE';
  end if;

  v_target_stage := v_anima.stage + 1;
  v_min_exp := case v_target_stage
    when 2 then public.anima_exp_for_level(16)
    when 3 then public.anima_exp_for_level(36)
    else null
  end;
  if v_anima.care_score < v_min_exp then
    raise exception 'EVOLUTION_LEVEL_TOO_LOW';
  end if;

  begin
    update public.animas
       set status = 'evolving'
     where id = v_anima.id
    returning * into v_anima;
  exception
    when unique_violation then
      raise exception 'EVOLUTION_ALREADY_ACTIVE';
  end;

  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model,
     cost_usd_estimate, target_stage)
  values
    (p_owner, v_anima.id, p_key, 'evolve', 'pending', 'v21', 'pending', 0, v_target_stage)
  returning * into v_gen;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_anima.id,
    'target_stage', v_target_stage,
    'prior_stage', v_anima.stage,
    'sheet_path', v_anima.sheet_path,
    'manifest', v_anima.manifest,
    'replayed', false,
    'capture_metadata', jsonb_build_object(
      'species_key', v_anima.species_key,
      'color_bucket', v_anima.color_bucket,
      'subject_kind', v_anima.subject_kind,
      'element', v_anima.element,
      'secondary_element', v_anima.secondary_element,
      'body_height_cm', v_anima.body_height_cm,
      'strike_name', v_anima.strike_name,
      'surge_name', v_anima.surge_name,
      'strike_effect_id', v_anima.strike_effect_id,
      'surge_effect_id', v_anima.surge_effect_id
    )
  );
exception
  when unique_violation then
    select * into v_gen
      from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    if found then
      if v_gen.anima_id is distinct from p_anima_id or v_gen.kind <> 'evolve' then
        raise exception 'IDEMPOTENCY_CONFLICT';
      end if;
      select * into v_anima
        from public.animas
       where id = p_anima_id and owner_id = p_owner;
      return jsonb_build_object(
        'generation_id', v_gen.id,
        'anima_id', v_anima.id,
        'target_stage', v_gen.target_stage,
        'prior_stage', v_anima.stage,
        'sheet_path', v_anima.sheet_path,
        'manifest', v_anima.manifest,
        'replayed', true,
        'vision_result', v_gen.vision_result,
        'capture_metadata', jsonb_build_object(
          'species_key', v_anima.species_key,
          'color_bucket', v_anima.color_bucket,
          'subject_kind', v_anima.subject_kind,
          'element', v_anima.element,
          'secondary_element', v_anima.secondary_element,
          'body_height_cm', v_anima.body_height_cm,
          'strike_name', v_anima.strike_name,
          'surge_name', v_anima.surge_name,
          'strike_effect_id', v_anima.strike_effect_id,
          'surge_effect_id', v_anima.surge_effect_id
        )
      );
    end if;
    raise exception 'EVOLUTION_ALREADY_ACTIVE';
end $$;

create or replace function public.resume_evolution(
  p_owner uuid,
  p_anima_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anima public.animas;
  v_gen public.generations;
begin
  select * into v_anima
    from public.animas
   where id = p_anima_id
     and owner_id = p_owner
     and status = 'evolving';
  if not found then raise exception 'EVOLUTION_NOT_FOUND'; end if;

  select * into v_gen
    from public.generations
   where owner_id = p_owner
     and anima_id = p_anima_id
     and kind = 'evolve'
     and status in ('pending', 'running')
   order by created_at desc
   limit 1;
  if not found then
    update public.animas
       set status = 'ready'
     where id = v_anima.id and status = 'evolving';
    return jsonb_build_object(
      'anima_id', v_anima.id,
      'not_found', true
    );
  end if;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_anima.id,
    'target_stage', v_gen.target_stage,
    'prior_stage', v_anima.stage,
    'sheet_path', v_anima.sheet_path,
    'manifest', v_anima.manifest,
    'replayed', true,
    'vision_result', v_gen.vision_result,
    'capture_metadata', jsonb_build_object(
      'species_key', v_anima.species_key,
      'color_bucket', v_anima.color_bucket,
      'subject_kind', v_anima.subject_kind,
      'element', v_anima.element,
      'secondary_element', v_anima.secondary_element,
      'body_height_cm', v_anima.body_height_cm,
      'strike_name', v_anima.strike_name,
      'surge_name', v_anima.surge_name,
      'strike_effect_id', v_anima.strike_effect_id,
      'surge_effect_id', v_anima.surge_effect_id
    )
  );
end $$;

create or replace function public.reserve_evolution(
  p_owner uuid,
  p_gen_id uuid,
  p_plan jsonb,
  p_prompt_version text,
  p_model text,
  p_cost numeric
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_anima public.animas;
  v_cap numeric;
  v_spent numeric;
  v_store_plan boolean := p_plan is not null;
begin
  select * into v_gen
    from public.generations
   where id = p_gen_id and owner_id = p_owner
   for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'evolve' then raise exception 'GEN_KIND_MISMATCH'; end if;

  if v_gen.status in ('succeeded', 'failed') then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'status', v_gen.status,
      'replayed', true
    );
  end if;

  select * into v_anima
    from public.animas
   where id = v_gen.anima_id and owner_id = p_owner
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_anima.status <> 'evolving' then raise exception 'ANIMA_NOT_EVOLVING'; end if;

  if v_store_plan and v_gen.vision_result is not null then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'target_stage', v_gen.target_stage,
      'status', v_gen.status,
      'replayed', true
    );
  end if;
  if not v_store_plan and v_gen.vision_result is not null then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'target_stage', v_gen.target_stage,
      'status', v_gen.status,
      'plan_ready', true,
      'planning_claimed', false,
      'replayed', true
    );
  end if;
  if not v_store_plan and v_gen.vision_started_at is not null then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'target_stage', v_gen.target_stage,
      'status', v_gen.status,
      'planning', true,
      'planning_claimed', false,
      'replayed', true
    );
  end if;

  if coalesce(v_gen.cost_usd_estimate, 0) <= 0 then
    select (value #>> '{}')::numeric into v_cap
      from public.app_config
     where key = 'daily_spend_cap_usd'
       for update;
    if v_cap is not null then
      select coalesce(sum(cost_usd_estimate), 0) into v_spent
        from public.generations
       where created_at >= date_trunc('day', now())
         and cost_usd_estimate > 0
         and id <> p_gen_id;
      if v_spent + coalesce(p_cost, 0) > v_cap then raise exception 'SPEND_CAP'; end if;
    end if;
  end if;

  update public.generations
     set vision_result = case when v_store_plan then p_plan else vision_result end,
         prompt_version = coalesce(nullif(p_prompt_version, ''), prompt_version),
         model = coalesce(nullif(p_model, ''), model),
         vision_started_at = case
           when not v_store_plan and vision_started_at is null then now()
           else vision_started_at
         end,
         cost_usd_estimate = case
           when coalesce(cost_usd_estimate, 0) > 0 then cost_usd_estimate
           else coalesce(p_cost, 0)
         end
   where id = v_gen.id
  returning * into v_gen;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_gen.anima_id,
    'target_stage', v_gen.target_stage,
    'status', v_gen.status,
    'replayed', false,
    'pre_reserved', not v_store_plan,
    'planning_claimed', not v_store_plan
  );
end $$;

create or replace function public.claim_evolution_dispatch(
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
  select * into v_gen
    from public.generations
   where id = p_gen_id and owner_id = p_owner
   for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'evolve' then raise exception 'GEN_KIND_MISMATCH'; end if;

  if v_gen.status = 'succeeded' then
    return jsonb_build_object('generation_id', v_gen.id, 'status', 'succeeded', 'replayed', true);
  end if;
  if v_gen.status = 'failed' then
    return jsonb_build_object('generation_id', v_gen.id, 'status', 'failed', 'replayed', true);
  end if;
  if v_gen.vision_result is null then raise exception 'EVOLUTION_PLAN_MISSING'; end if;

  if v_gen.prediction_id is not null then
    if v_gen.dispatch_started_at <= now() - interval '20 minutes' then
      update public.animas
         set status = 'ready'
       where id = v_gen.anima_id and status = 'evolving';
      insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
      values (
        'anima_sheets',
        format('%s/%s/evolution_refs/%s.png', v_gen.owner_id, v_gen.anima_id, v_gen.id),
        'evolution_completion_timeout'
      );
      update public.generations
         set status = 'failed',
             error = 'GENERATION_COMPLETION_TIMEOUT',
             finished_at = coalesce(finished_at, now())
       where id = v_gen.id
      returning * into v_gen;
      return jsonb_build_object(
        'generation_id', v_gen.id,
        'status', 'failed',
        'timed_out', true
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
    update public.animas
       set status = 'ready'
     where id = v_gen.anima_id and status = 'evolving';
    insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
    values (
      'anima_sheets',
      format('%s/%s/evolution_refs/%s.png', v_gen.owner_id, v_gen.anima_id, v_gen.id),
      'evolution_dispatch_timeout'
    );
    update public.generations
       set status = 'failed',
           error = 'GENERATION_DISPATCH_TIMEOUT',
           finished_at = coalesce(finished_at, now())
     where id = v_gen.id
    returning * into v_gen;
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'status', 'failed',
      'timed_out', true
    );
  end if;

  update public.generations
     set status = 'running',
         dispatch_started_at = now()
   where id = v_gen.id;

  return jsonb_build_object('generation_id', v_gen.id, 'ready', true);
end $$;

create or replace function public.attach_evolution_prediction(
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

  select * into v_gen
    from public.generations
   where id = p_gen_id
   for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'evolve' then raise exception 'GEN_KIND_MISMATCH'; end if;

  if v_gen.status in ('succeeded', 'failed') then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'prediction_id', v_gen.prediction_id,
      'status', v_gen.status,
      'attached', false
    );
  end if;

  if v_gen.prediction_id is not null and v_gen.prediction_id <> p_prediction_id then
    raise exception 'PREDICTION_MISMATCH';
  end if;

  if v_gen.prediction_id is null then
    update public.generations
       set prediction_id = p_prediction_id,
           status = 'running'
     where id = p_gen_id
    returning * into v_gen;
  end if;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'prediction_id', v_gen.prediction_id,
    'attached', true
  );
end $$;

create or replace function public.commit_evolution(
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
  v_anima public.animas;
  v_plan jsonb;
  v_target_stage smallint;
  v_source_gen public.generations;
  v_source_plan jsonb;
begin
  select * into v_gen
    from public.generations
   where id = p_gen_id
   for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'evolve' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'failed' then raise exception 'EVOLUTION_ALREADY_FAILED'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'stage', (select stage from public.animas where id = v_gen.anima_id),
      'replayed', true
    );
  end if;
  if v_gen.vision_result is null then raise exception 'EVOLUTION_PLAN_MISSING'; end if;

  if p_sheet_path is null or btrim(p_sheet_path) = '' then
    raise exception 'EVOLUTION_SHEET_PATH_INVALID';
  end if;
  if p_manifest is null or jsonb_typeof(p_manifest) <> 'object' then
    raise exception 'EVOLUTION_MANIFEST_INVALID';
  end if;

  v_plan := v_gen.vision_result;
  if coalesce(v_plan->>'body_height_cm', '') !~ '^[0-9]+$' then
    raise exception 'EVOLUTION_PLAN_HEIGHT_INVALID';
  end if;
  if btrim(coalesce(v_plan->>'strike_name', '')) = ''
     or btrim(coalesce(v_plan->>'surge_name', '')) = ''
     or btrim(coalesce(v_plan->>'strike_effect_id', '')) = ''
     or btrim(coalesce(v_plan->>'surge_effect_id', '')) = '' then
    raise exception 'EVOLUTION_PLAN_MOVE_INVALID';
  end if;

  select * into v_anima
    from public.animas
   where id = v_gen.anima_id and owner_id = v_gen.owner_id
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_anima.status <> 'evolving' then raise exception 'ANIMA_NOT_EVOLVING'; end if;

  v_target_stage := v_gen.target_stage;
  if v_target_stage is null or v_target_stage <> v_anima.stage + 1 then
    raise exception 'EVOLUTION_STAGE_MISMATCH';
  end if;
  if (v_plan->>'body_height_cm')::integer
       not between greatest(20, least(2000, round(v_anima.body_height_cm * case
         when v_target_stage = 2 then 1.15 else 1.20 end)::integer))
       and greatest(20, least(2000, round(v_anima.body_height_cm * case
         when v_target_stage = 2 then 1.35 else 1.50 end)::integer)) then
    raise exception 'EVOLUTION_PLAN_HEIGHT_OUT_OF_RANGE';
  end if;
  if coalesce((p_manifest->>'stage')::integer, 0) <> v_target_stage
     or coalesce(p_manifest->>'prompt_version', '') <> v_gen.prompt_version then
    raise exception 'EVOLUTION_MANIFEST_MISMATCH';
  end if;
  if not (v_plan->>'strike_effect_id' = any(array[
       'armor_pierce', 'guard_break', 'drain', 'poison', 'burn', 'slow', 'armor_break'
     ]))
     or not (v_plan->>'surge_effect_id' = any(array[
       'barrier', 'guard_break', 'drain', 'burn', 'slow', 'armor_break'
     ]))
     or v_plan->>'strike_effect_id' = v_plan->>'surge_effect_id' then
    raise exception 'EVOLUTION_PLAN_EFFECT_INVALID';
  end if;
  if v_target_stage = 3 and (
    not (
      case coalesce(v_anima.strike_effect_id, '')
        when 'armor_pierce' then v_plan->>'strike_effect_id' in ('armor_pierce', 'guard_break')
        when 'guard_break' then v_plan->>'strike_effect_id' = 'guard_break'
        when 'drain' then v_plan->>'strike_effect_id' = 'drain'
        when 'poison' then v_plan->>'strike_effect_id' in ('poison', 'burn')
        when 'burn' then v_plan->>'strike_effect_id' = 'burn'
        when 'slow' then v_plan->>'strike_effect_id' in ('slow', 'armor_break')
        when 'armor_break' then v_plan->>'strike_effect_id' = 'armor_break'
        else false
      end
    )
    or not (
      case coalesce(v_anima.surge_effect_id, '')
        when 'barrier' then v_plan->>'surge_effect_id' = 'barrier'
        when 'guard_break' then v_plan->>'surge_effect_id' = 'guard_break'
        when 'drain' then v_plan->>'surge_effect_id' = 'drain'
        when 'burn' then v_plan->>'surge_effect_id' = 'burn'
        when 'slow' then v_plan->>'surge_effect_id' in ('slow', 'armor_break')
        when 'armor_break' then v_plan->>'surge_effect_id' = 'armor_break'
        else false
      end
    )
  ) then
    raise exception 'EVOLUTION_PLAN_EFFECT_NOT_UPGRADE';
  end if;

  select * into v_source_gen
    from public.generations g
   where g.anima_id = v_anima.id
     and g.status = 'succeeded'
     and (
       (v_anima.stage = 1 and g.kind = 'create')
       or (g.kind = 'evolve' and g.target_stage = v_anima.stage)
     )
   order by g.finished_at desc nulls last, g.created_at desc
   limit 1;

  v_source_plan := case when v_anima.stage = 1 then null else v_source_gen.vision_result end;

  insert into public.anima_forms (
    anima_id, stage, sheet_path, manifest, body_height_cm,
    strike_name, surge_name, strike_effect_id, surge_effect_id,
    evolution_plan, reference_path, generation_id
  ) values (
    v_anima.id, v_anima.stage, v_anima.sheet_path, v_anima.manifest, v_anima.body_height_cm,
    v_anima.strike_name, v_anima.surge_name, v_anima.strike_effect_id, v_anima.surge_effect_id,
    v_source_plan,
    format('%s/%s/evolution_refs/%s.png', v_gen.owner_id, v_gen.anima_id, v_gen.id),
    v_source_gen.id
  );

  update public.animas
     set stage = v_target_stage,
         status = 'ready',
         sheet_path = p_sheet_path,
         manifest = p_manifest,
         body_height_cm = greatest(20, least(2000, (v_plan->>'body_height_cm')::integer)),
         strike_name = left(btrim(coalesce(v_plan->>'strike_name', '')), 24),
         surge_name = left(btrim(coalesce(v_plan->>'surge_name', '')), 24),
         strike_effect_id = left(btrim(coalesce(v_plan->>'strike_effect_id', '')), 32),
         surge_effect_id = left(btrim(coalesce(v_plan->>'surge_effect_id', '')), 32),
         evolution_version = evolution_version + 1
   where id = v_anima.id
  returning * into v_anima;

  update public.generations
     set status = 'succeeded',
         finished_at = now()
   where id = v_gen.id;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_anima.id,
    'stage', v_anima.stage,
    'replayed', false
  );
end $$;

create or replace function public.fail_evolution(
  p_gen_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_anima public.animas;
begin
  select * into v_gen
    from public.generations
   where id = p_gen_id
   for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'evolve' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'succeeded' then raise exception 'ALREADY_SUCCEEDED'; end if;

  if v_gen.status = 'failed' then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'status', v_gen.status,
      'replayed', true
    );
  end if;

  if v_gen.anima_id is not null then
    select * into v_anima
      from public.animas
     where id = v_gen.anima_id
     for update;
    if found and v_anima.status = 'evolving' then
      update public.animas
         set status = 'ready'
       where id = v_anima.id;
    end if;
  end if;

  insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
  values (
    'anima_sheets',
    format('%s/%s/evolution_refs/%s.png', v_gen.owner_id, v_gen.anima_id, v_gen.id),
    'evolution_failed'
  );

  update public.generations
     set status = 'failed',
         error = left(coalesce(p_reason, error), 500),
         finished_at = coalesce(finished_at, now())
   where id = p_gen_id
  returning * into v_gen;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'anima_id', v_gen.anima_id,
    'status', v_gen.status
  );
end $$;

revoke all on function public.begin_evolution(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.resume_evolution(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.reserve_evolution(uuid, uuid, jsonb, text, text, numeric)
  from public, anon, authenticated;
revoke all on function public.claim_evolution_dispatch(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.attach_evolution_prediction(uuid, text)
  from public, anon, authenticated;
revoke all on function public.commit_evolution(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.fail_evolution(uuid, text)
  from public, anon, authenticated;

grant execute on function public.begin_evolution(uuid, uuid, text) to service_role;
grant execute on function public.resume_evolution(uuid, uuid) to service_role;
grant execute on function public.reserve_evolution(uuid, uuid, jsonb, text, text, numeric)
  to service_role;
grant execute on function public.claim_evolution_dispatch(uuid, uuid) to service_role;
grant execute on function public.attach_evolution_prediction(uuid, text) to service_role;
grant execute on function public.commit_evolution(uuid, text, jsonb) to service_role;
grant execute on function public.fail_evolution(uuid, text) to service_role;
