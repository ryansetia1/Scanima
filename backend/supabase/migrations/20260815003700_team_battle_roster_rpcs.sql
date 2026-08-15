-- Team roster disimpan atomik dan Defense publish selalu memakai snapshot
-- server-built yang anggotanya cocok dengan roster saat ini.

create or replace function public.anima_team_payload(p_team public.anima_teams)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_team.id,
    'kind', p_team.kind,
    'published', p_team.published,
    'published_at', p_team.published_at,
    'updated_at', p_team.updated_at,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot', m.slot,
        'anima_id', a.id,
        'nickname', a.nickname,
        'stage', a.stage,
        'element', a.element,
        'secondary_element', a.secondary_element,
        'base_stats', a.base_stats,
        'care_score', a.care_score,
        'care', a.care,
        'sleep_started_at', a.sleep_started_at,
        'dormant_since', a.dormant_since,
        'status', a.status,
        'strike_name', a.strike_name,
        'surge_name', a.surge_name,
        'sheet_path', a.sheet_path,
        'manifest', a.manifest
      ) order by m.slot)
      from public.anima_team_members m
      join public.animas a on a.id = m.anima_id
      where m.team_id = p_team.id
    ), '[]'::jsonb)
  )
$$;

create or replace function public.save_anima_team(
  p_owner uuid,
  p_kind text,
  p_anima_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.anima_teams;
  v_count integer;
begin
  if p_kind not in ('team_battle', 'expedition', 'defense') then
    raise exception 'INVALID_TEAM_KIND';
  end if;
  if cardinality(p_anima_ids) <> 4
     or (select count(distinct id) from unnest(p_anima_ids) as id) <> 4 then
    raise exception 'TEAM_REQUIRES_FOUR';
  end if;

  perform 1
    from public.animas
   where owner_id = p_owner and id = any(p_anima_ids)
   for update;
  select count(*) into v_count
    from public.animas
   where owner_id = p_owner
     and id = any(p_anima_ids)
     and status = 'ready';
  if v_count <> 4 then raise exception 'TEAM_MEMBER_NOT_READY'; end if;

  insert into public.anima_teams (owner_id, kind)
  values (p_owner, p_kind)
  on conflict (owner_id, kind) do update
    set published = false,
        snapshot = null,
        published_at = null,
        updated_at = now()
  returning * into v_team;

  delete from public.team_battle_candidates
   where player_team_id = v_team.id or opponent_team_id = v_team.id;
  delete from public.anima_team_members where team_id = v_team.id;
  insert into public.anima_team_members (team_id, slot, anima_id)
  select v_team.id, ordinality - 1, anima_id
    from unnest(p_anima_ids) with ordinality as roster(anima_id, ordinality);

  select * into v_team from public.anima_teams where id = v_team.id;
  return public.anima_team_payload(v_team);
end $$;

create or replace function public.publish_defense_team(
  p_owner uuid,
  p_snapshot jsonb,
  p_publish boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.anima_teams;
  v_member_ids uuid[];
  v_snapshot_ids uuid[];
  v_clean_snapshot jsonb;
begin
  select * into v_team
    from public.anima_teams
   where owner_id = p_owner and kind = 'defense'
   for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;

  if not coalesce(p_publish, false) then
    delete from public.team_battle_candidates where opponent_team_id = v_team.id;
    update public.anima_teams
       set published = false,
           snapshot = null,
           published_at = null,
           updated_at = now()
     where id = v_team.id
    returning * into v_team;
    return public.anima_team_payload(v_team);
  end if;

  if jsonb_typeof(p_snapshot) <> 'array'
     or jsonb_array_length(p_snapshot) <> 4
     or exists (
       select 1
         from jsonb_array_elements(p_snapshot) member
        where jsonb_typeof(member->'anima_id') <> 'string'
           or (member->>'anima_id') !~
              '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
     ) then
    raise exception 'INVALID_TEAM_SNAPSHOT';
  end if;

  select array_agg(anima_id order by anima_id) into v_member_ids
    from public.anima_team_members
   where team_id = v_team.id;
  select array_agg((member->>'anima_id')::uuid order by (member->>'anima_id')::uuid),
         jsonb_agg(member - 'owner_id' - 'nickname' - 'sheet_url')
    into v_snapshot_ids, v_clean_snapshot
    from jsonb_array_elements(p_snapshot) member;
  if cardinality(v_member_ids) <> 4 or v_snapshot_ids is distinct from v_member_ids then
    raise exception 'SNAPSHOT_MISMATCH';
  end if;

  delete from public.team_battle_candidates where opponent_team_id = v_team.id;
  update public.anima_teams
     set published = true,
         snapshot = v_clean_snapshot,
         published_at = now(),
         updated_at = now()
   where id = v_team.id
  returning * into v_team;
  return public.anima_team_payload(v_team);
end $$;

create or replace function public.replace_team_battle_candidates(
  p_owner uuid,
  p_player_team_id uuid,
  p_candidates jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.anima_teams;
  v_result jsonb;
begin
  if jsonb_typeof(p_candidates) <> 'array'
     or jsonb_array_length(p_candidates) not between 1 and 3 then
    raise exception 'INVALID_TEAM_CANDIDATES';
  end if;
  select * into v_team
    from public.anima_teams
   where id = p_player_team_id
     and owner_id = p_owner
     and kind = 'team_battle'
   for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;
  if exists (
    select 1
      from jsonb_array_elements(p_candidates) candidate
     where candidate->>'opponent_source' not in ('defense', 'system')
        or jsonb_typeof(candidate->'opponent_snapshot') <> 'array'
        or jsonb_array_length(candidate->'opponent_snapshot') not between 1 and 4
  ) then
    raise exception 'INVALID_TEAM_CANDIDATES';
  end if;
  if exists (
    select 1
      from jsonb_array_elements(p_candidates) candidate
     where candidate->>'opponent_source' = 'defense'
       and not exists (
         select 1 from public.anima_teams defense
          where defense.id = (candidate->>'opponent_team_id')::uuid
            and defense.kind = 'defense'
            and defense.published
            and defense.owner_id <> p_owner
       )
  ) then
    raise exception 'TEAM_CANDIDATE_EXPIRED';
  end if;

  delete from public.team_battle_candidates
   where owner_id = p_owner and consumed_at is null;
  with inserted as (
    insert into public.team_battle_candidates (
      owner_id, player_team_id, opponent_source, opponent_team_id,
      opponent_snapshot, reward_tier, reward_roll, reward_bits
    )
    select
      p_owner,
      v_team.id,
      candidate->>'opponent_source',
      nullif(candidate->>'opponent_team_id', '')::uuid,
      candidate->'opponent_snapshot',
      candidate->>'reward_tier',
      (candidate->>'reward_roll')::smallint,
      (candidate->>'reward_bits')::integer
      from jsonb_array_elements(p_candidates) candidate
    returning *
  )
  select coalesce(jsonb_agg(
    to_jsonb(inserted) - 'owner_id' - 'player_team_id' - 'opponent_team_id'
    order by created_at, id
  ), '[]'::jsonb)
  into v_result
  from inserted;
  return v_result;
end $$;

revoke all on function public.anima_team_payload(public.anima_teams)
  from public, anon, authenticated;
revoke all on function public.save_anima_team(uuid, text, uuid[])
  from public, anon, authenticated;
revoke all on function public.publish_defense_team(uuid, jsonb, boolean)
  from public, anon, authenticated;
revoke all on function public.replace_team_battle_candidates(uuid, uuid, jsonb)
  from public, anon, authenticated;

grant execute on function public.anima_team_payload(public.anima_teams)
  to service_role;
grant execute on function public.save_anima_team(uuid, text, uuid[])
  to service_role;
grant execute on function public.publish_defense_team(uuid, jsonb, boolean)
  to service_role;
grant execute on function public.replace_team_battle_candidates(uuid, uuid, jsonb)
  to service_role;
