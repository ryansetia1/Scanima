-- Synthesis always uses each Source Anima's current committed form.
-- Keep the public RPC signatures stable so old clients are rejected by the
-- database instead of being trusted to choose a valid historical form.

alter function public.preview_synthesis(
  uuid, uuid, smallint, uuid, smallint, text
) rename to preview_synthesis_unrestricted_v1;

revoke all on function public.preview_synthesis_unrestricted_v1(
  uuid, uuid, smallint, uuid, smallint, text
) from public, anon, authenticated, service_role;

create function public.preview_synthesis(
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
  v_source record;
  v_source_a_stage smallint;
  v_source_b_stage smallint;
begin
  -- Lock in canonical order so a form cannot change between this guard and
  -- the legacy implementation's snapshot, including for reversed Source pairs.
  for v_source in
    select id, stage
      from public.animas
     where owner_id = p_owner
       and id in (p_source_a, p_source_b)
     order by id
     for update
  loop
    if v_source.id = p_source_a then
      v_source_a_stage := v_source.stage;
    end if;
    if v_source.id = p_source_b then
      v_source_b_stage := v_source.stage;
    end if;
  end loop;

  if (v_source_a_stage is not null and p_source_a_stage is distinct from v_source_a_stage)
     or (v_source_b_stage is not null and p_source_b_stage is distinct from v_source_b_stage) then
    raise exception 'SYNTHESIS_STAGE_MISMATCH';
  end if;

  return public.preview_synthesis_unrestricted_v1(
    p_owner,
    p_source_a,
    p_source_a_stage,
    p_source_b,
    p_source_b_stage,
    p_mode
  );
end $$;

revoke all on function public.preview_synthesis(
  uuid, uuid, smallint, uuid, smallint, text
) from public, anon, authenticated;
grant execute on function public.preview_synthesis(
  uuid, uuid, smallint, uuid, smallint, text
) to service_role;

alter function public.attempt_synthesis(
  uuid, text, uuid, smallint, uuid, smallint, text, text, text
) rename to attempt_synthesis_unrestricted_v1;

revoke all on function public.attempt_synthesis_unrestricted_v1(
  uuid, text, uuid, smallint, uuid, smallint, text, text, text
) from public, anon, authenticated, service_role;

create function public.attempt_synthesis(
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
  v_source record;
  v_source_a_stage smallint;
  v_source_b_stage smallint;
begin
  -- Paid/idempotent replays must remain valid even if a Source evolves after
  -- the original claim. The legacy implementation still verifies the payload.
  if exists (
    select 1
      from public.anima_synthesis_attempts
     where owner_id = p_owner
       and idempotency_key = p_key
  ) then
    return public.attempt_synthesis_unrestricted_v1(
      p_owner,
      p_key,
      p_source_a,
      p_source_a_stage,
      p_source_b,
      p_source_b_stage,
      p_mode,
      p_prompt_version,
      p_model
    );
  end if;

  for v_source in
    select id, stage
      from public.animas
     where owner_id = p_owner
       and id in (p_source_a, p_source_b)
     order by id
     for update
  loop
    if v_source.id = p_source_a then
      v_source_a_stage := v_source.stage;
    end if;
    if v_source.id = p_source_b then
      v_source_b_stage := v_source.stage;
    end if;
  end loop;

  if (v_source_a_stage is not null and p_source_a_stage is distinct from v_source_a_stage)
     or (v_source_b_stage is not null and p_source_b_stage is distinct from v_source_b_stage) then
    raise exception 'SYNTHESIS_STAGE_MISMATCH';
  end if;

  return public.attempt_synthesis_unrestricted_v1(
    p_owner,
    p_key,
    p_source_a,
    p_source_a_stage,
    p_source_b,
    p_source_b_stage,
    p_mode,
    p_prompt_version,
    p_model
  );
end $$;

revoke all on function public.attempt_synthesis(
  uuid, text, uuid, smallint, uuid, smallint, text, text, text
) from public, anon, authenticated;
grant execute on function public.attempt_synthesis(
  uuid, text, uuid, smallint, uuid, smallint, text, text, text
) to service_role;
