-- Trail Shop is optional: players may leave without buying an item. The
-- reserved shop-skip choice advances the route but cannot mutate HP, Tokens,
-- or boosts.

create or replace function public.commit_expedition_choice(
  p_owner uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_node_id text,
  p_option_id text,
  p_party_state jsonb,
  p_supplies integer,
  p_boosts jsonb,
  p_next_node_ids jsonb,
  p_checkpoint boolean,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_action public.expedition_run_actions;
  v_expected_next jsonb;
  v_party_ids uuid[];
  v_next_party_ids uuid[];
  v_is_shop_skip boolean;
begin
  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id or v_action.operation <> 'choose_node_option' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;
  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  v_is_shop_skip := v_run.pending_node->>'kind' = 'shop'
    and p_option_id = 'shop-skip';
  if v_run.status <> 'active'
     or v_run.version <> p_expected_version
     or v_run.current_node_id is distinct from p_node_id
     or v_run.pending_node is null
     or (
       not v_is_shop_skip
       and not exists (
         select 1 from jsonb_array_elements(v_run.pending_node->'options') option
          where option->>'id' = p_option_id
       )
     ) then raise exception 'INVALID_EXPEDITION_CHOICE'; end if;
  v_expected_next := coalesce(v_run.pending_node->'next', '[]'::jsonb);
  if jsonb_typeof(p_party_state) <> 'array' or jsonb_array_length(p_party_state) <> 4
     or p_supplies < 0 or jsonb_typeof(p_boosts) <> 'array'
     or jsonb_array_length(p_boosts) > 20
     or jsonb_typeof(p_next_node_ids) <> 'array'
     or p_next_node_ids <> v_expected_next
     or p_checkpoint is distinct from (
       v_run.zone < 3
       and jsonb_array_length(v_expected_next) = 0
       and v_run.nodes_completed = 3
     )
     or (
       v_is_shop_skip
       and (
         p_party_state is distinct from v_run.party_state
         or p_supplies is distinct from v_run.supplies
         or p_boosts is distinct from v_run.boosts
       )
     ) then
    raise exception 'INVALID_EXPEDITION_STATE';
  end if;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_party_ids from jsonb_array_elements(v_run.party_state) member;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_next_party_ids from jsonb_array_elements(p_party_state) member;
  if v_next_party_ids is distinct from v_party_ids or exists (
    select 1 from jsonb_array_elements(p_party_state) member
     where coalesce((member->>'hp')::integer, -1) < 0
        or coalesce((member->>'max_hp')::integer, 0) < 1
        or (member->>'hp')::integer > (member->>'max_hp')::integer
  ) then raise exception 'SNAPSHOT_MISMATCH'; end if;

  update public.expedition_runs set
    status = case when p_checkpoint then 'checkpoint' else status end,
    zone = case when p_checkpoint then least(3, zone + 1) else zone end,
    nodes_completed = nodes_completed + 1,
    version = version + 1,
    party_state = p_party_state,
    supplies = p_supplies,
    boosts = p_boosts,
    available_node_ids = case when p_checkpoint then '[]'::jsonb else p_next_node_ids end,
    current_node_id = null,
    pending_node = null,
    zone_map = case when p_checkpoint then null else zone_map end,
    updated_at = now()
  where id = v_run.id returning * into v_run;
  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'choose_node_option',
    public.expedition_run_payload(v_run)
  );
  return public.expedition_run_payload(v_run);
end $$;

revoke all on function public.commit_expedition_choice(
  uuid, uuid, integer, text, text, jsonb, integer, jsonb, jsonb, boolean, text
) from public, anon, authenticated;
grant execute on function public.commit_expedition_choice(
  uuid, uuid, integer, text, text, jsonb, integer, jsonb, jsonb, boolean, text
) to service_role;
