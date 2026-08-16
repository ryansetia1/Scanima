-- Terminal turn responses are already immutable idempotency receipts. Reuse
-- their per-member EXP rows so resumed result screens match the fresh response
-- without adding a second reward copy that could drift.

create or replace function public.team_battle_session_payload(
  p_session public.team_battle_sessions
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_session.id,
    'player_team_id', p_session.player_team_id,
    'opponent_source', p_session.opponent_source,
    'player_snapshot', p_session.player_snapshot,
    'opponent_snapshot', p_session.opponent_snapshot,
    'state', p_session.state,
    'turn_number', p_session.turn_number,
    'version', p_session.version,
    'status', p_session.status,
    'created_at', p_session.created_at,
    'updated_at', p_session.updated_at,
    'expires_at', p_session.expires_at,
    'finished_at', p_session.finished_at,
    'item_used_id', p_session.item_used_id,
    'reward_tier', p_session.reward_tier,
    'reward_roll', p_session.reward_roll,
    'reward_bits', p_session.reward_bits,
    'last_reward', (
      select jsonb_build_object(
        'bits', reward.bits,
        'progression', reward.progression,
        'anima_exp', coalesce((
          select turn.response #> '{reward,anima_exp}'
            from public.team_battle_turns turn
           where turn.session_id = p_session.id
             and jsonb_typeof(turn.response #> '{reward,anima_exp}') = 'array'
           order by turn.turn_number desc
           limit 1
        ), '[]'::jsonb)
      )
        from public.team_battle_rewards reward
       where reward.session_id = p_session.id
    ),
    'daily_reward', public.team_battle_daily_reward_status(
      p_session.owner_id,
      p_session.id
    )
  )
$$;

create or replace function public.expedition_encounter_payload(
  p_encounter public.expedition_encounters
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_encounter.id,
    'run_id', p_encounter.run_id,
    'node_id', p_encounter.node_id,
    'kind', p_encounter.kind,
    'player_snapshot', p_encounter.player_snapshot,
    'opponent_snapshot', p_encounter.opponent_snapshot,
    'state', p_encounter.state,
    'turn_number', p_encounter.turn_number,
    'version', p_encounter.version,
    'status', p_encounter.status,
    'item_used_id', p_encounter.item_used_id,
    'supplies_reward', p_encounter.supplies_reward,
    'created_at', p_encounter.created_at,
    'updated_at', p_encounter.updated_at,
    'finished_at', p_encounter.finished_at,
    'expires_at', p_encounter.expires_at,
    'last_reward', (
      select jsonb_build_object(
        'progression', reward.progression,
        'supplies', reward.supplies,
        'anima_exp', coalesce((
          select turn.response #> '{reward,anima_exp}'
            from public.expedition_encounter_turns turn
           where turn.encounter_id = p_encounter.id
             and jsonb_typeof(turn.response #> '{reward,anima_exp}') = 'array'
           order by turn.turn_number desc
           limit 1
        ), '[]'::jsonb)
      )
        from public.expedition_encounter_rewards reward
       where reward.encounter_id = p_encounter.id
    ),
    'daily_reward', public.expedition_daily_reward_status(
      p_encounter.owner_id,
      p_encounter.id
    )
  )
$$;

revoke all on function public.team_battle_session_payload(public.team_battle_sessions)
  from public, anon, authenticated;
revoke all on function public.expedition_encounter_payload(public.expedition_encounters)
  from public, anon, authenticated;
grant execute on function public.team_battle_session_payload(public.team_battle_sessions)
  to service_role;
grant execute on function public.expedition_encounter_payload(public.expedition_encounters)
  to service_role;
