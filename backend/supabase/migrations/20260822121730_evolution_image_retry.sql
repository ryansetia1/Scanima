-- Satu retry otomatis untuk kegagalan safety E005 milik GPT Image.
--
-- Prediction resmi yang berstatus failed tidak ditagih Replicate. Kita tetap
-- membatasi tepat dua attempt total supaya error provider lain tidak pernah
-- berubah menjadi loop generation.

alter table public.generations
  add column image_attempts smallint not null default 0
  check (image_attempts between 0 and 2);

update public.generations
   set image_attempts = 1
 where kind = 'evolve'
   and prediction_id is not null;

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
           image_attempts = greatest(image_attempts, 1),
           status = 'running'
     where id = p_gen_id
    returning * into v_gen;
  end if;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'prediction_id', v_gen.prediction_id,
    'image_attempts', v_gen.image_attempts,
    'attached', true
  );
end $$;

create or replace function public.replace_evolution_prediction(
  p_gen_id uuid,
  p_failed_prediction_id text,
  p_retry_prediction_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
begin
  if p_failed_prediction_id is null
     or length(btrim(p_failed_prediction_id)) = 0
     or p_retry_prediction_id is null
     or length(btrim(p_retry_prediction_id)) = 0
     or p_failed_prediction_id = p_retry_prediction_id then
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

  -- Webhook completed bisa dikirim ulang atau diproses paralel. Hanya callback
  -- yang masih memegang prediction aktif boleh menggantinya; prediction kedua
  -- dari callback duplikat dibatalkan oleh Edge Function.
  if v_gen.prediction_id <> p_failed_prediction_id then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'prediction_id', v_gen.prediction_id,
      'image_attempts', v_gen.image_attempts,
      'attached', false,
      'stale', true
    );
  end if;

  if v_gen.image_attempts >= 2 then
    return jsonb_build_object(
      'generation_id', v_gen.id,
      'prediction_id', v_gen.prediction_id,
      'image_attempts', v_gen.image_attempts,
      'attached', false,
      'exhausted', true
    );
  end if;

  update public.generations
     set prediction_id = p_retry_prediction_id,
         image_attempts = image_attempts + 1,
         status = 'running',
         error = null,
         finished_at = null
   where id = p_gen_id
  returning * into v_gen;

  return jsonb_build_object(
    'generation_id', v_gen.id,
    'prediction_id', v_gen.prediction_id,
    'image_attempts', v_gen.image_attempts,
    'attached', true
  );
end $$;

revoke all on function public.attach_evolution_prediction(uuid, text)
  from public, anon, authenticated;
revoke all on function public.replace_evolution_prediction(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.attach_evolution_prediction(uuid, text)
  to service_role;
grant execute on function public.replace_evolution_prediction(uuid, text, text)
  to service_role;
