-- Inter-zone checkpoints now preserve HP and require one authoritative choice:
-- recover 50% max HP (including KO revival) or a temporary next-zone power-up.

alter table public.expedition_runs
  add column checkpoint_choice text,
  add column checkpoint_choice_pending boolean not null default false,
  add constraint expedition_runs_checkpoint_choice_valid
    check (checkpoint_choice is null or checkpoint_choice in ('recover', 'power_up')),
  add constraint expedition_runs_checkpoint_choice_pending_valid
    check (
      not checkpoint_choice_pending
      or (status = 'checkpoint' and zone > 1 and checkpoint_choice is null)
    );

alter table public.expedition_run_actions
  drop constraint expedition_run_action_operation_valid,
  add constraint expedition_run_action_operation_valid check (
    operation in (
      'start_run', 'start_zone', 'enter_node', 'choose_node_option',
      'checkpoint_choice', 'refresh_shop', 'abandon'
    )
  );

-- Existing open inter-zone checkpoints join the new flow instead of silently
-- receiving the old full heal.
update public.expedition_runs
   set checkpoint_choice_pending = true,
       checkpoint_choice = null
 where status = 'checkpoint' and zone > 1;

create or replace function public.prepare_expedition_checkpoint_choice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'active'
     and new.status = 'checkpoint'
     and new.zone = old.zone + 1 then
    new.checkpoint_choice := null;
    new.checkpoint_choice_pending := true;
  elsif new.status in ('complete', 'abandoned') then
    new.checkpoint_choice := null;
    new.checkpoint_choice_pending := false;
  end if;
  return new;
end $$;

drop trigger if exists expedition_runs_checkpoint_choice
  on public.expedition_runs;
create trigger expedition_runs_checkpoint_choice
before update on public.expedition_runs
for each row execute function public.prepare_expedition_checkpoint_choice();

create or replace function public.expedition_run_payload(p_run public.expedition_runs)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_run.id,
    'chapter_version_id', p_run.chapter_version_id,
    'team_id', p_run.team_id,
    'status', p_run.status,
    'zone', p_run.zone,
    'zone_attempt', p_run.zone_attempt,
    'version', p_run.version,
    'seed', p_run.seed,
    'zone_map', p_run.zone_map,
    'available_node_ids', p_run.available_node_ids,
    'current_node_id', p_run.current_node_id,
    'visited_node_ids', p_run.visited_node_ids,
    'nodes_completed', p_run.nodes_completed,
    'supplies', p_run.supplies,
    'boosts', p_run.boosts,
    'party_state', p_run.party_state,
    'pending_node', p_run.pending_node,
    'shop_refreshed', p_run.shop_refreshed,
    'checkpoint_choice', p_run.checkpoint_choice,
    'checkpoint_choice_pending', p_run.checkpoint_choice_pending,
    'daily_bits', public.expedition_daily_bits_status(
      p_run.owner_id,
      p_run.chapter_version_id
    ),
    'last_zone_reward', (
      select jsonb_build_object(
        'zone', reward.zone,
        'scheduled_bits', reward.scheduled_bits,
        'bits', reward.bits,
        'capped', reward.bits < reward.scheduled_bits
      )
        from public.expedition_zone_rewards reward
       where reward.run_id = p_run.id
       order by reward.zone desc
       limit 1
    ),
    'created_at', p_run.created_at,
    'updated_at', p_run.updated_at,
    'completed_at', p_run.completed_at,
    'abandoned_at', p_run.abandoned_at
  )
$$;

create or replace function public.commit_expedition_checkpoint_choice(
  p_owner uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_option_id text,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_action public.expedition_run_actions;
  v_party jsonb;
begin
  if p_option_id not in ('recover', 'power_up') then
    raise exception 'INVALID_EXPEDITION_CHECKPOINT_CHOICE';
  end if;
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id
       or v_action.operation <> 'checkpoint_choice' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;

  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  if v_run.status <> 'checkpoint' or not v_run.checkpoint_choice_pending then
    raise exception 'EXPEDITION_CHECKPOINT_CHOICE_UNAVAILABLE';
  end if;
  if v_run.version <> p_expected_version then raise exception 'STALE_EXPEDITION'; end if;
  if jsonb_typeof(v_run.party_state) <> 'array'
     or jsonb_array_length(v_run.party_state) <> 4
     or exists (
       select 1 from jsonb_array_elements(v_run.party_state) member
        where coalesce((member->>'max_hp')::integer, 0) < 1
           or coalesce(
             (member->>'hp')::integer,
             (member->>'current_hp')::integer,
             -1
           ) < 0
           or coalesce(
             (member->>'hp')::integer,
             (member->>'current_hp')::integer,
             -1
           ) > (member->>'max_hp')::integer
     ) then
    raise exception 'INVALID_EXPEDITION_STATE';
  end if;

  v_party := v_run.party_state;
  if p_option_id = 'recover' then
    select jsonb_agg(
      member.value || jsonb_build_object(
        'hp',
        least(
          (member.value->>'max_hp')::integer,
          coalesce(
            (member.value->>'hp')::integer,
            (member.value->>'current_hp')::integer,
            0
          ) + round((member.value->>'max_hp')::numeric * 0.5)::integer
        ),
        'current_hp',
        least(
          (member.value->>'max_hp')::integer,
          coalesce(
            (member.value->>'hp')::integer,
            (member.value->>'current_hp')::integer,
            0
          ) + round((member.value->>'max_hp')::numeric * 0.5)::integer
        )
      )
      order by member.ordinality
    ) into v_party
      from jsonb_array_elements(v_run.party_state)
      with ordinality as member(value, ordinality);
  end if;

  update public.expedition_runs set
    checkpoint_choice = p_option_id,
    checkpoint_choice_pending = false,
    party_state = v_party,
    version = version + 1,
    updated_at = now()
  where id = v_run.id returning * into v_run;

  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'checkpoint_choice',
    public.expedition_run_payload(v_run)
  );
  return public.expedition_run_payload(v_run);
end $$;

create or replace function public.start_expedition_zone(
  p_owner uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_team_id uuid,
  p_seed text,
  p_party_state jsonb,
  p_zone_map jsonb,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_team public.anima_teams;
  v_action public.expedition_run_actions;
  v_member_ids uuid[];
  v_party_ids uuid[];
begin
  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id or v_action.operation <> 'start_zone' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;
  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  if v_run.status <> 'checkpoint' then raise exception 'EXPEDITION_NOT_AT_CHECKPOINT'; end if;
  if v_run.version <> p_expected_version then raise exception 'STALE_EXPEDITION'; end if;
  if p_team_id <> v_run.team_id then raise exception 'EXPEDITION_TEAM_LOCKED'; end if;
  if v_run.checkpoint_choice_pending
     or (v_run.zone > 1 and v_run.checkpoint_choice is null) then
    raise exception 'EXPEDITION_CHECKPOINT_CHOICE_REQUIRED';
  end if;
  if p_seed is null or length(p_seed) not between 1 and 128
     or jsonb_typeof(p_zone_map) <> 'object'
     or jsonb_typeof(p_zone_map->'entry') <> 'array'
     or jsonb_typeof(p_zone_map->'nodes') <> 'array'
     or jsonb_typeof(p_party_state) <> 'array'
     or jsonb_array_length(p_party_state) <> 4 then
    raise exception 'INVALID_EXPEDITION_STATE';
  end if;

  select * into v_team from public.anima_teams
   where id = v_run.team_id and owner_id = p_owner and kind = 'expedition'
   for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;
  select array_agg(anima_id order by anima_id) into v_member_ids
    from public.anima_team_members where team_id = v_team.id;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_party_ids from jsonb_array_elements(p_party_state) member;
  if cardinality(v_member_ids) <> 4 or v_party_ids is distinct from v_member_ids then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  update public.expedition_runs set
    status = 'active',
    zone_attempt = zone_attempt + 1,
    version = version + 1,
    seed = p_seed,
    zone_map = p_zone_map,
    available_node_ids = p_zone_map->'entry',
    current_node_id = null,
    nodes_completed = 0,
    party_state = p_party_state,
    checkpoint_state = jsonb_build_object(
      'team_id', v_team.id,
      'party_state', p_party_state,
      'supplies', supplies,
      'boosts', boosts
    ),
    checkpoint_choice = null,
    checkpoint_choice_pending = false,
    pending_node = null,
    shop_refreshed = false,
    bits_refresh_spent = 0,
    shop_refresh_action_id = null,
    updated_at = now()
  where id = v_run.id returning * into v_run;
  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'start_zone',
    public.expedition_run_payload(v_run)
  );
  return public.expedition_run_payload(v_run);
end $$;

revoke all on function public.prepare_expedition_checkpoint_choice()
  from public, anon, authenticated;
revoke all on function public.expedition_run_payload(public.expedition_runs)
  from public, anon, authenticated;
revoke all on function public.commit_expedition_checkpoint_choice(
  uuid, uuid, integer, text, text
) from public, anon, authenticated;
revoke all on function public.start_expedition_zone(
  uuid, uuid, integer, uuid, text, jsonb, jsonb, text
) from public, anon, authenticated;

grant execute on function public.prepare_expedition_checkpoint_choice()
  to service_role;
grant execute on function public.expedition_run_payload(public.expedition_runs)
  to service_role;
grant execute on function public.commit_expedition_checkpoint_choice(
  uuid, uuid, integer, text, text
) to service_role;
grant execute on function public.start_expedition_zone(
  uuid, uuid, integer, uuid, text, jsonb, jsonb, text
) to service_role;
