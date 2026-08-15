-- Expedition pays Energy once when the chapter run is created. Zone starts
-- only advance the already-paid run, and the four-member roster stays locked
-- until the run is completed or abandoned.
update public.app_config
set value = '30'::jsonb
where key = 'expedition_energy_per_member';

create or replace function public.start_expedition_run(
  p_owner uuid,
  p_chapter_version_id uuid,
  p_team_id uuid,
  p_seed text,
  p_party_state jsonb,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.expedition_chapter_versions;
  v_chapter public.expedition_chapters;
  v_run public.expedition_runs;
  v_team public.anima_teams;
  v_action public.expedition_run_actions;
  v_member record;
  v_member_ids uuid[];
  v_party_ids uuid[];
  v_energy numeric;
  v_energy_cost integer;
begin
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;
  if p_seed is null or length(p_seed) not between 1 and 128 then
    raise exception 'INVALID_SEED';
  end if;
  if jsonb_typeof(p_party_state) <> 'array'
     or jsonb_array_length(p_party_state) <> 4 then
    raise exception 'INVALID_TEAM_SNAPSHOT';
  end if;

  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.operation <> 'start_run' then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text, 0));
  select * into v_run from public.expedition_runs
   where owner_id = p_owner and status in ('checkpoint', 'active')
   order by created_at desc limit 1;
  if found then
    insert into public.expedition_run_actions (
      idempotency_key, run_id, owner_id, operation, response
    ) values (
      p_key, v_run.id, p_owner, 'start_run',
      public.expedition_run_payload(v_run)
    );
    return public.expedition_run_payload(v_run)
      || jsonb_build_object('replayed', true);
  end if;

  select * into v_version
    from public.expedition_chapter_versions
   where id = p_chapter_version_id and active and published_at is not null;
  if not found then raise exception 'CHAPTER_NOT_AVAILABLE'; end if;
  select * into v_chapter from public.expedition_chapters
   where id = v_version.chapter_id and status = 'published';
  if not found then raise exception 'CHAPTER_NOT_AVAILABLE'; end if;
  if v_chapter.sequence > 1 and not exists (
    select 1
      from public.expedition_progress progress
      join public.expedition_chapters chapter on chapter.id = progress.chapter_id
     where progress.owner_id = p_owner
       and progress.first_cleared_at is not null
       and chapter.sequence = v_chapter.sequence - 1
  ) then raise exception 'CHAPTER_LOCKED'; end if;

  select * into v_team from public.anima_teams
   where id = p_team_id and owner_id = p_owner and kind = 'expedition'
   for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;
  select array_agg(anima_id order by anima_id) into v_member_ids
    from public.anima_team_members where team_id = v_team.id;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid)
    into v_party_ids from jsonb_array_elements(p_party_state) member;
  if cardinality(v_member_ids) <> 4 or v_party_ids is distinct from v_member_ids then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  v_energy_cost := greatest(0, least(100, coalesce((
    select (value #>> '{}')::integer from public.app_config
     where key = 'expedition_energy_per_member'
  ), 30)));
  for v_member in
    select anima.id
      from public.anima_team_members member
      join public.animas anima on anima.id = member.anima_id
     where member.team_id = v_team.id order by member.slot
  loop
    perform public.apply_care(p_owner, v_member.id, 'sync', null);
    select coalesce((care->>'energy')::numeric, 0) into v_energy
      from public.animas
     where id = v_member.id and owner_id = p_owner
       and status = 'ready' and dormant_since is null
     for update;
    if not found then raise exception 'TEAM_MEMBER_UNAVAILABLE'; end if;
    if v_energy < v_energy_cost then raise exception 'TEAM_MEMBER_LOW_ENERGY'; end if;
    update public.animas set care = jsonb_set(
      care, '{energy}', to_jsonb(round(v_energy - v_energy_cost, 2))
    ) where id = v_member.id;
  end loop;

  insert into public.expedition_progress (owner_id, chapter_id)
  values (p_owner, v_chapter.id) on conflict do nothing;
  insert into public.expedition_runs (
    owner_id, chapter_version_id, team_id, seed, party_state
  ) values (
    p_owner, v_version.id, v_team.id, p_seed, p_party_state
  ) returning * into v_run;
  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'start_run',
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

create or replace function public.guard_active_expedition_team_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid := case when tg_op = 'INSERT' then new.team_id else old.team_id end;
  v_owner uuid;
begin
  select owner_id into v_owner from public.anima_teams
   where id = v_team_id and kind = 'expedition';
  if not found then return case when tg_op = 'DELETE' then old else new end; end if;
  if v_owner::text = any(string_to_array(
    current_setting('scanima.deleting_profiles', true),
    ','
  )) then return case when tg_op = 'DELETE' then old else new end; end if;
  if exists (
    select 1 from public.expedition_runs
     where owner_id = v_owner and team_id = v_team_id
       and status in ('checkpoint', 'active')
  ) then raise exception 'EXPEDITION_TEAM_LOCKED'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create or replace function public.guard_active_team_anima_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.owner_id::text = any(string_to_array(
    current_setting('scanima.deleting_profiles', true),
    ','
  )) then return old; end if;
  if exists (
    select 1 from public.team_battle_sessions s
     where s.status = 'active'
       and s.expires_at > now()
       and (
         s.player_snapshot @> jsonb_build_array(jsonb_build_object('anima_id', old.id::text))
         or s.opponent_snapshot @> jsonb_build_array(jsonb_build_object('anima_id', old.id::text))
       )
  ) or exists (
    select 1 from public.expedition_runs r
     where r.owner_id = old.owner_id
       and r.status in ('checkpoint', 'active')
       and r.party_state @> jsonb_build_array(jsonb_build_object('anima_id', old.id::text))
  ) then
    raise exception 'ANIMA_IN_ACTIVE_COMBAT';
  end if;
  return old;
end $$;

revoke all on function public.start_expedition_run(uuid, uuid, uuid, text, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.start_expedition_zone(
  uuid, uuid, integer, uuid, text, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.guard_active_expedition_team_change()
  from public, anon, authenticated;
revoke all on function public.guard_active_team_anima_delete()
  from public, anon, authenticated;

grant execute on function public.start_expedition_run(uuid, uuid, uuid, text, jsonb, text)
  to service_role;
grant execute on function public.start_expedition_zone(
  uuid, uuid, integer, uuid, text, jsonb, jsonb, text
) to service_role;
grant execute on function public.guard_active_expedition_team_change()
  to service_role;
grant execute on function public.guard_active_team_anima_delete()
  to service_role;
