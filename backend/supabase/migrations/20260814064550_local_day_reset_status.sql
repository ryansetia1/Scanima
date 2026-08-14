-- Hadiah Battle memakai 00:00 sipil di offset profil. EXECUTE helper/zona
-- dicabut dari client di file ini; apply_care menyusul di migrasi berikutnya.

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
  zone as (
    select coalesce(
      (
        select timezone_offset_minutes
          from public.profiles
         where id = p_owner
      ),
      0
    ) as offset_minutes
  ),
  boundary as (
    select
      now() as server_now,
      public.local_day_start(now(), zone.offset_minutes) as starts_at,
      public.local_day_start(now(), zone.offset_minutes) + interval '1 day' as reset_at
    from zone
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

revoke all on function public.local_civil_date(timestamptz, int)
  from public, anon, authenticated;
revoke all on function public.local_day_start(timestamptz, int)
  from public, anon, authenticated;
revoke all on function public.set_profile_timezone(uuid, int)
  from public, anon, authenticated;
revoke all on function public.battle_daily_reward_status(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.local_civil_date(timestamptz, int) to service_role;
grant execute on function public.local_day_start(timestamptz, int) to service_role;
grant execute on function public.set_profile_timezone(uuid, int) to service_role;
grant execute on function public.battle_daily_reward_status(uuid, uuid) to service_role;
