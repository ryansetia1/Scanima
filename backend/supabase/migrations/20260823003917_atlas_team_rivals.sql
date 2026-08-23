alter table public.team_battle_candidates
  drop constraint team_battle_candidates_source_valid;
alter table public.team_battle_candidates
  add constraint team_battle_candidates_source_valid
  check (opponent_source in ('atlas', 'defense', 'system'));

alter table public.team_battle_sessions
  drop constraint team_battle_sessions_source_valid;
alter table public.team_battle_sessions
  add constraint team_battle_sessions_source_valid
  check (opponent_source in ('atlas', 'defense', 'system'));

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
     where candidate->>'opponent_source' not in ('atlas', 'defense', 'system')
        or jsonb_typeof(candidate->'opponent_snapshot') <> 'array'
        or jsonb_array_length(candidate->'opponent_snapshot') <> (
          select count(*)
            from public.anima_team_members member
           where member.team_id = v_team.id
        )
        or (
          candidate->>'opponent_source' in ('atlas', 'system')
          and nullif(candidate->>'opponent_team_id', '') is not null
        )
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

revoke all on function public.replace_team_battle_candidates(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.replace_team_battle_candidates(uuid, uuid, jsonb)
  to service_role;
