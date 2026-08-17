-- Evolution player-live: v29 prompts, feature on, default evolution_version=1,
-- and per-Anima locked sheets that skip Replicate at the ritual.

update public.app_config
   set value = 'true'::jsonb
 where key = 'feature_evolution';

update public.app_config
   set value = '"v29"'::jsonb
 where key = 'evolution_prompt_version';

alter table public.animas
  alter column evolution_version set default 1;

update public.animas
   set evolution_version = 1
 where evolution_version = 0;

create table if not exists public.anima_evolution_locks (
  anima_id uuid not null references public.animas(id) on delete cascade,
  target_stage smallint not null,
  sheet_path text not null,
  manifest jsonb not null,
  evolution_plan jsonb not null,
  prompt_version text not null,
  created_at timestamptz not null default now(),
  primary key (anima_id, target_stage),
  constraint anima_evolution_locks_stage_valid check (target_stage in (2, 3)),
  constraint anima_evolution_locks_sheet_present check (btrim(sheet_path) <> ''),
  constraint anima_evolution_locks_prompt_present check (btrim(prompt_version) <> '')
);

alter table public.anima_evolution_locks enable row level security;

revoke all on public.anima_evolution_locks from public, anon, authenticated;
grant all on public.anima_evolution_locks to service_role;

create or replace function public.apply_evolution_lock(
  p_owner uuid,
  p_gen_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_lock public.anima_evolution_locks;
  v_commit jsonb;
begin
  select * into v_gen
    from public.generations
   where id = p_gen_id and owner_id = p_owner
   for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.kind <> 'evolve' then raise exception 'GEN_KIND_MISMATCH'; end if;
  if v_gen.status = 'failed' then raise exception 'EVOLUTION_ALREADY_FAILED'; end if;
  if v_gen.status = 'succeeded' then
    return jsonb_build_object(
      'locked', true,
      'replayed', true,
      'generation_id', v_gen.id,
      'anima_id', v_gen.anima_id,
      'stage', (select stage from public.animas where id = v_gen.anima_id)
    );
  end if;
  if v_gen.prediction_id is not null then
    return jsonb_build_object('locked', false, 'generation_id', v_gen.id);
  end if;

  select * into v_lock
    from public.anima_evolution_locks
   where anima_id = v_gen.anima_id
     and target_stage = v_gen.target_stage;
  if not found then
    return jsonb_build_object('locked', false, 'generation_id', v_gen.id);
  end if;

  update public.generations
     set vision_result = v_lock.evolution_plan,
         prompt_version = v_lock.prompt_version,
         model = 'locked',
         cost_usd_estimate = 0
   where id = v_gen.id;

  v_commit := public.commit_evolution(
    p_gen_id,
    v_lock.sheet_path,
    v_lock.manifest
  );
  return jsonb_build_object(
    'locked', true,
    'replayed', coalesce((v_commit->>'replayed')::boolean, false),
    'generation_id', v_gen.id,
    'anima_id', v_gen.anima_id,
    'stage', coalesce((v_commit->>'stage')::integer, v_lock.target_stage)
  );
end $$;

revoke all on function public.apply_evolution_lock(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.apply_evolution_lock(uuid, uuid) to service_role;
