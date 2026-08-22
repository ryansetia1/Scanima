create or replace function public.store_synthesis_history_references(
  p_owner uuid,
  p_result_anima_id uuid,
  p_reference_paths jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anima public.animas;
  v_slot public.anima_synthesis_slots;
  v_paths jsonb;
  v_history jsonb;
  v_history_a text;
  v_history_b text;
  v_model_a text;
  v_model_b text;
  v_owner_prefix text := p_owner::text || '/';
begin
  if p_reference_paths is null
     or jsonb_typeof(p_reference_paths) <> 'object' then
    raise exception 'SYNTHESIS_REFERENCES_INVALID';
  end if;

  v_history_a := coalesce(p_reference_paths->>'source_a', '');
  v_history_b := coalesce(p_reference_paths->>'source_b', '');
  v_model_a := coalesce(p_reference_paths->>'model_source_a', '');
  v_model_b := coalesce(p_reference_paths->>'model_source_b', '');
  if v_history_a = '' or v_history_b = '' or v_model_a = '' or v_model_b = ''
     or left(v_history_a, length(v_owner_prefix)) <> v_owner_prefix
     or left(v_history_b, length(v_owner_prefix)) <> v_owner_prefix
     or left(v_model_a, length(v_owner_prefix)) <> v_owner_prefix
     or left(v_model_b, length(v_owner_prefix)) <> v_owner_prefix then
    raise exception 'SYNTHESIS_REFERENCES_INVALID';
  end if;

  select * into v_anima
    from public.animas
   where id = p_result_anima_id
     and owner_id = p_owner
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_anima.synthesis_history is null
     or jsonb_typeof(v_anima.synthesis_history) <> 'object' then
    raise exception 'SYNTHESIS_HISTORY_MISSING';
  end if;

  select * into v_slot
    from public.anima_synthesis_slots
   where owner_id = p_owner
     and result_anima_id = p_result_anima_id
     and status = 'succeeded'
   for update;
  if not found then raise exception 'SYNTHESIS_SLOT_MISSING'; end if;

  v_paths := coalesce(v_slot.reference_paths, '{}'::jsonb) || p_reference_paths;
  update public.anima_synthesis_slots
     set source_a_snapshot = source_a_snapshot || jsonb_build_object(
           'thumbnail_path', v_history_a
         ),
         source_b_snapshot = source_b_snapshot || jsonb_build_object(
           'thumbnail_path', v_history_b
         ),
         reference_paths = v_paths,
         updated_at = now()
   where id = v_slot.id;

  v_history := jsonb_set(
    jsonb_set(
      v_anima.synthesis_history,
      '{source_a,thumbnail_path}',
      to_jsonb(v_history_a),
      true
    ),
    '{source_b,thumbnail_path}',
    to_jsonb(v_history_b),
    true
  );
  update public.animas
     set synthesis_history = v_history
   where id = v_anima.id;

  return jsonb_build_object(
    'result_anima_id', v_anima.id,
    'reference_paths', v_paths,
    'replayed',
      coalesce(v_slot.reference_paths->>'model_source_a', '') = v_model_a
      and coalesce(v_slot.reference_paths->>'source_a', '') = v_history_a
  );
end $$;

revoke all on function public.store_synthesis_history_references(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.store_synthesis_history_references(uuid, uuid, jsonb)
  to service_role;
