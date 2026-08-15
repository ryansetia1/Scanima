-- Expedition catalog, run/checkpoint transitions, non-combat node choices,
-- Shop refresh/refund, and Trophy showcase.

create or replace function public.expedition_chapter_catalog(p_owner uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', chapter.id,
    'slug', chapter.slug,
    'sequence', chapter.sequence,
    'version_id', version.id,
    'content_version', version.content_version,
    'schema_version', version.schema_version,
    'minimum_build', version.minimum_build,
    'manifest_hash', version.manifest_hash,
    'asset_prefix', version.asset_prefix,
    'summary', version.manifest->'summary',
    'unlocked', (
      chapter.sequence = 1
      or exists (
        select 1
          from public.expedition_progress previous_progress
          join public.expedition_chapters previous_chapter
            on previous_chapter.id = previous_progress.chapter_id
         where previous_progress.owner_id = p_owner
           and previous_progress.first_cleared_at is not null
           and previous_chapter.sequence = chapter.sequence - 1
      )
    ),
    'first_cleared_at', progress.first_cleared_at,
    'clear_count', coalesce(progress.clear_count, 0),
    'trophy', case when trophy.id is null then null else jsonb_build_object(
      'id', trophy.id,
      'slug', trophy.slug,
      'display_name', trophy.display_name,
      'description', trophy.description,
      'art_path', trophy.art_path,
      'art_hash', trophy.art_hash,
      'metadata', trophy.metadata,
      'earned_at', owned.earned_at
    ) end
  ) order by chapter.sequence), '[]'::jsonb)
  from public.expedition_chapters chapter
  join public.expedition_chapter_versions version
    on version.chapter_id = chapter.id and version.active
  left join public.expedition_progress progress
    on progress.owner_id = p_owner and progress.chapter_id = chapter.id
  left join public.expedition_trophies trophy on trophy.chapter_id = chapter.id
  left join public.seeker_trophies owned
    on owned.owner_id = p_owner and owned.trophy_id = trophy.id
  where chapter.status = 'published'
$$;

create or replace function public.expedition_daily_reward_status(
  p_owner uuid,
  p_encounter_id uuid default null
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with settings as (
    select greatest(0, least(20, coalesce((
      select (value #>> '{}')::integer from public.app_config
       where key = 'expedition_rewarded_encounters_per_day'
    ), 3))) as reward_limit
  ),
  zone as (
    select coalesce((
      select timezone_offset_minutes from public.profiles where id = p_owner
    ), 0) as offset_minutes
  ),
  boundary as (
    select
      now() as server_now,
      public.local_day_start(now(), zone.offset_minutes) as starts_at,
      public.local_day_start(now(), zone.offset_minutes) + interval '1 day' as reset_at
    from zone
  ),
  earned as (
    select count(*) filter (where reward.progression)::integer as encounters
      from public.expedition_encounter_rewards reward
      cross join boundary
     where reward.owner_id = p_owner
       and reward.created_at >= boundary.starts_at
       and reward.created_at < boundary.reset_at
  )
  select jsonb_build_object(
    'earned', earned.encounters,
    'limit', settings.reward_limit,
    'remaining', greatest(0, settings.reward_limit - earned.encounters),
    'server_now', boundary.server_now,
    'reset_at', boundary.reset_at,
    'rewarded', exists (
      select 1 from public.expedition_encounter_rewards reward
       where p_encounter_id is not null
         and reward.owner_id = p_owner
         and reward.encounter_id = p_encounter_id
    ),
    'progression_rewarded', exists (
      select 1 from public.expedition_encounter_rewards reward
       where p_encounter_id is not null
         and reward.owner_id = p_owner
         and reward.encounter_id = p_encounter_id
         and reward.progression
    )
  )
  from settings, boundary, earned
$$;

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
    'nodes_completed', p_run.nodes_completed,
    'supplies', p_run.supplies,
    'boosts', p_run.boosts,
    'party_state', p_run.party_state,
    'pending_node', p_run.pending_node,
    'shop_refreshed', p_run.shop_refreshed,
    'created_at', p_run.created_at,
    'updated_at', p_run.updated_at,
    'completed_at', p_run.completed_at,
    'abandoned_at', p_run.abandoned_at
  )
$$;

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
  v_member_ids uuid[];
  v_party_ids uuid[];
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
  v_member record;
  v_member_ids uuid[];
  v_party_ids uuid[];
  v_energy numeric;
  v_energy_cost integer;
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
  if p_seed is null or length(p_seed) not between 1 and 128
     or jsonb_typeof(p_zone_map) <> 'object'
     or jsonb_typeof(p_zone_map->'entry') <> 'array'
     or jsonb_typeof(p_zone_map->'nodes') <> 'array'
     or jsonb_typeof(p_party_state) <> 'array'
     or jsonb_array_length(p_party_state) <> 4 then
    raise exception 'INVALID_EXPEDITION_STATE';
  end if;

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
  ), 10)));
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

  update public.expedition_runs set
    team_id = v_team.id,
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

create or replace function public.enter_expedition_node(
  p_owner uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_node jsonb,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_action public.expedition_run_actions;
  v_node_id text := p_node->>'id';
begin
  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id or v_action.operation <> 'enter_node' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;
  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  if v_run.status <> 'active' or v_run.pending_node is not null then
    raise exception 'EXPEDITION_NODE_PENDING';
  end if;
  if v_run.version <> p_expected_version then raise exception 'STALE_EXPEDITION'; end if;
  if jsonb_typeof(p_node) <> 'object' or v_node_id is null
     or not (v_run.available_node_ids ? v_node_id)
     or not exists (
       select 1 from jsonb_array_elements(v_run.zone_map->'nodes') node
        where node->>'id' = v_node_id and node = p_node
     ) then raise exception 'INVALID_EXPEDITION_NODE'; end if;

  update public.expedition_runs set
    current_node_id = v_node_id,
    available_node_ids = '[]'::jsonb,
    pending_node = p_node,
    version = version + 1,
    updated_at = now()
  where id = v_run.id returning * into v_run;
  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'enter_node',
    public.expedition_run_payload(v_run)
  );
  return public.expedition_run_payload(v_run);
end $$;

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
  if v_run.status <> 'active'
     or v_run.version <> p_expected_version
     or v_run.current_node_id is distinct from p_node_id
     or v_run.pending_node is null
     or not exists (
       select 1 from jsonb_array_elements(v_run.pending_node->'options') option
        where option->>'id' = p_option_id
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

create or replace function public.refresh_expedition_shop(
  p_owner uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_node jsonb,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_action public.expedition_run_actions;
  v_cost integer;
begin
  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id or v_action.operation <> 'refresh_shop' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;
  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  if v_run.status <> 'active' or v_run.version <> p_expected_version
     or v_run.shop_refreshed or v_run.pending_node->>'kind' <> 'shop'
     or jsonb_typeof(p_node) <> 'object'
     or p_node->>'id' is distinct from v_run.current_node_id then
    raise exception 'EXPEDITION_SHOP_REFRESH_UNAVAILABLE';
  end if;
  v_cost := greatest(0, least(100, coalesce((
    select (value #>> '{}')::integer from public.app_config
     where key = 'expedition_shop_refresh_bits'
  ), 3)));
  perform 1 from public.profiles where id = p_owner and bits >= v_cost for update;
  if not found then raise exception 'NO_BITS'; end if;

  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (p_key, v_run.id, p_owner, 'refresh_shop', '{}'::jsonb)
  returning * into v_action;
  if v_cost > 0 then
    update public.profiles set bits = bits - v_cost where id = p_owner;
    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (p_owner, 'bits', -v_cost, 'expedition_shop', v_action.id);
  end if;
  update public.expedition_runs set
    pending_node = p_node,
    shop_refreshed = true,
    bits_refresh_spent = v_cost,
    shop_refresh_action_id = v_action.id,
    version = version + 1,
    updated_at = now()
  where id = v_run.id returning * into v_run;
  update public.expedition_run_actions
     set response = public.expedition_run_payload(v_run)
   where id = v_action.id;
  return public.expedition_run_payload(v_run);
end $$;

create or replace function public.abandon_expedition_run(
  p_owner uuid,
  p_run_id uuid,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.expedition_runs;
  v_action public.expedition_run_actions;
begin
  select * into v_action from public.expedition_run_actions
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    if v_action.run_id <> p_run_id or v_action.operation <> 'abandon' then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_action.response || jsonb_build_object('replayed', true);
  end if;
  select * into v_run from public.expedition_runs
   where id = p_run_id and owner_id = p_owner for update;
  if not found then raise exception 'EXPEDITION_RUN_NOT_FOUND'; end if;
  if v_run.status in ('complete', 'abandoned') then
    return public.expedition_run_payload(v_run);
  end if;
  update public.expedition_encounters set
    status = 'forfeited',
    finished_at = now(),
    updated_at = now()
  where run_id = v_run.id and status = 'active';
  perform 1 from public.profiles where id = p_owner for update;
  if v_run.bits_refresh_spent > 0 and v_run.shop_refresh_action_id is not null
     and not exists (
       select 1 from public.quota_ledger
        where reason = 'expedition_refund' and ref_id = v_run.shop_refresh_action_id
     ) then
    update public.profiles
       set bits = bits + v_run.bits_refresh_spent where id = p_owner;
    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (
      p_owner, 'bits', v_run.bits_refresh_spent,
      'expedition_refund', v_run.shop_refresh_action_id
    );
  end if;
  update public.expedition_runs set
    status = 'abandoned',
    version = version + 1,
    abandoned_at = now(),
    updated_at = now()
  where id = v_run.id returning * into v_run;
  insert into public.expedition_run_actions (
    idempotency_key, run_id, owner_id, operation, response
  ) values (
    p_key, v_run.id, p_owner, 'abandon',
    public.expedition_run_payload(v_run)
  );
  return public.expedition_run_payload(v_run);
end $$;

create or replace function public.set_featured_trophies(
  p_owner uuid,
  p_trophy_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_result jsonb;
begin
  if cardinality(p_trophy_ids) > 3
     or (select count(distinct id) from unnest(p_trophy_ids) id)
          <> cardinality(p_trophy_ids) then
    raise exception 'INVALID_TROPHY_SELECTION';
  end if;
  select count(*) into v_count from public.seeker_trophies
   where owner_id = p_owner and trophy_id = any(p_trophy_ids);
  if v_count <> cardinality(p_trophy_ids) then raise exception 'TROPHY_NOT_OWNED'; end if;
  delete from public.seeker_featured_trophies where owner_id = p_owner;
  insert into public.seeker_featured_trophies (owner_id, slot, trophy_id)
  select p_owner, ordinality - 1, trophy_id
    from unnest(p_trophy_ids) with ordinality selected(trophy_id, ordinality);
  select coalesce(jsonb_agg(jsonb_build_object(
    'slot', featured.slot,
    'id', trophy.id,
    'slug', trophy.slug,
    'display_name', trophy.display_name,
    'description', trophy.description,
    'art_path', trophy.art_path,
    'art_hash', trophy.art_hash,
    'metadata', trophy.metadata,
    'earned_at', owned.earned_at
  ) order by featured.slot), '[]'::jsonb)
  into v_result
  from public.seeker_featured_trophies featured
  join public.expedition_trophies trophy on trophy.id = featured.trophy_id
  join public.seeker_trophies owned
    on owned.owner_id = featured.owner_id and owned.trophy_id = featured.trophy_id
  where featured.owner_id = p_owner;
  return v_result;
end $$;

revoke all on function public.expedition_chapter_catalog(uuid)
  from public, anon, authenticated;
revoke all on function public.expedition_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.expedition_run_payload(public.expedition_runs)
  from public, anon, authenticated;
revoke all on function public.start_expedition_run(uuid, uuid, uuid, text, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.start_expedition_zone(
  uuid, uuid, integer, uuid, text, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.enter_expedition_node(
  uuid, uuid, integer, jsonb, text
) from public, anon, authenticated;
revoke all on function public.commit_expedition_choice(
  uuid, uuid, integer, text, text, jsonb, integer, jsonb, jsonb, boolean, text
) from public, anon, authenticated;
revoke all on function public.refresh_expedition_shop(
  uuid, uuid, integer, jsonb, text
) from public, anon, authenticated;
revoke all on function public.abandon_expedition_run(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.set_featured_trophies(uuid, uuid[])
  from public, anon, authenticated;

grant execute on function public.expedition_chapter_catalog(uuid) to service_role;
grant execute on function public.expedition_daily_reward_status(uuid, uuid)
  to service_role;
grant execute on function public.expedition_run_payload(public.expedition_runs)
  to service_role;
grant execute on function public.start_expedition_run(uuid, uuid, uuid, text, jsonb, text)
  to service_role;
grant execute on function public.start_expedition_zone(
  uuid, uuid, integer, uuid, text, jsonb, jsonb, text
) to service_role;
grant execute on function public.enter_expedition_node(
  uuid, uuid, integer, jsonb, text
) to service_role;
grant execute on function public.commit_expedition_choice(
  uuid, uuid, integer, text, text, jsonb, integer, jsonb, jsonb, boolean, text
) to service_role;
grant execute on function public.refresh_expedition_shop(
  uuid, uuid, integer, jsonb, text
) to service_role;
grant execute on function public.abandon_expedition_run(uuid, uuid, text)
  to service_role;
grant execute on function public.set_featured_trophies(uuid, uuid[])
  to service_role;
