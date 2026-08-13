-- battle_win adalah identitas semantik satu rewarded win. Jangan ikat counter
-- ke nominal 5 Bits: balancing reward di masa depan tidak boleh membuka cap.
-- server_now memberi client durasi reset tanpa mempercayai jam device.
create or replace function public.battle_daily_reward_status(
  p_owner uuid,
  p_session_id uuid default null
) returns jsonb
language sql
stable
set search_path = ''
as $$
  with settings as (
    select greatest(
      0,
      least(
        100,
        coalesce(
          (
            select (value #>> '{}')::integer
              from public.app_config
             where key = 'battle_rewarded_wins_per_day'
          ),
          3
        )
      )
    ) as reward_limit
  ),
  boundary as (
    select
      now() as server_now,
      date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' as starts_at,
      (
        date_trunc('day', now() at time zone 'UTC') + interval '1 day'
      ) at time zone 'UTC' as reset_at
  ),
  rewarded as (
    select count(*)::integer as wins
      from public.quota_ledger q
      cross join boundary b
     where q.owner_id = p_owner
       and q.reason = 'battle_win'
       and q.created_at >= b.starts_at
       and q.created_at < b.reset_at
  )
  select jsonb_build_object(
    'earned', rewarded.wins,
    'limit', settings.reward_limit,
    'remaining', greatest(0, settings.reward_limit - rewarded.wins),
    'server_now', boundary.server_now,
    'reset_at', boundary.reset_at,
    'rewarded', exists (
      select 1
        from public.quota_ledger q
       where p_session_id is not null
         and q.owner_id = p_owner
         and q.ref_id = p_session_id
         and q.reason = 'battle_win'
    )
  )
    from settings, boundary, rewarded
$$;

revoke all on function public.battle_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.battle_daily_reward_status(uuid, uuid)
  to service_role;
