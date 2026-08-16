-- Chapter-tuned Expedition Bits are granted exactly once when a zone clears.
-- The daily budget is per stable chapter (not version) and uses the same local
-- civil-day boundary as Duel and Team Battle. Published manifests without
-- zones[].bits_reward remain valid and mint no repeatable Bits.

alter table public.expedition_runs
  add column visited_node_ids jsonb not null default '[]'::jsonb;

alter table public.expedition_runs
  add constraint expedition_runs_visited_array
  check (jsonb_typeof(visited_node_ids) = 'array');

create table public.expedition_zone_rewards (
  id                 uuid primary key default gen_random_uuid(),
  run_id             uuid not null references public.expedition_runs(id) on delete cascade,
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  chapter_id         uuid not null references public.expedition_chapters(id) on delete cascade,
  chapter_version_id uuid not null references public.expedition_chapter_versions(id)
                            on delete restrict,
  zone               smallint not null,
  scheduled_bits     integer not null,
  bits               integer not null,
  created_at         timestamptz not null default now(),
  constraint expedition_zone_rewards_zone_valid check (zone between 1 and 3),
  constraint expedition_zone_rewards_scheduled_valid check (scheduled_bits between 0 and 200),
  constraint expedition_zone_rewards_bits_valid check (
    bits between 0 and scheduled_bits
  ),
  unique (run_id, zone)
);

create index expedition_zone_rewards_owner_chapter_created_idx
  on public.expedition_zone_rewards (owner_id, chapter_id, created_at desc);

create unique index quota_ledger_expedition_zone_unique
  on public.quota_ledger (ref_id)
  where reason = 'expedition_zone';

alter table public.expedition_zone_rewards enable row level security;
revoke all on public.expedition_zone_rewards from public, anon, authenticated;
grant all on public.expedition_zone_rewards to service_role;

create or replace function public.expedition_daily_bits_status(
  p_owner uuid,
  p_chapter_version_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with chapter as (
    select
      version.chapter_id,
      coalesce((
        select sum(
          case
            when jsonb_typeof(zone.value->'bits_reward') = 'number'
              then greatest(0, least(200, (zone.value->>'bits_reward')::integer))
            else 0
          end
        )::integer
          from jsonb_array_elements(
            case
              when jsonb_typeof(version.manifest->'zones') = 'array'
                then version.manifest->'zones'
              else '[]'::jsonb
            end
          ) zone
      ), 0) as bits_limit
      from public.expedition_chapter_versions version
     where version.id = p_chapter_version_id
  ),
  player_zone as (
    select coalesce((
      select timezone_offset_minutes
        from public.profiles
       where id = p_owner
    ), 0) as offset_minutes
  ),
  boundary as (
    select
      now() as server_now,
      public.local_day_start(now(), player_zone.offset_minutes) as starts_at,
      public.local_day_start(now(), player_zone.offset_minutes) + interval '1 day' as reset_at
      from player_zone
  ),
  earned as (
    select coalesce(sum(reward.bits), 0)::integer as bits
      from public.expedition_zone_rewards reward
      cross join chapter
      cross join boundary
     where reward.owner_id = p_owner
       and reward.chapter_id = chapter.chapter_id
       and reward.created_at >= boundary.starts_at
       and reward.created_at < boundary.reset_at
  )
  select jsonb_build_object(
    'chapter_id', chapter.chapter_id,
    'bits_earned', earned.bits,
    'bits_limit', chapter.bits_limit,
    'bits_remaining', greatest(0, chapter.bits_limit - earned.bits),
    'server_now', boundary.server_now,
    'reset_at', boundary.reset_at
  )
    from chapter, boundary, earned
$$;

create or replace function public.award_expedition_zone_bits(
  p_run public.expedition_runs,
  p_zone smallint
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chapter_id uuid;
  v_scheduled integer := 0;
  v_status jsonb;
  v_payout integer := 0;
  v_receipt public.expedition_zone_rewards;
begin
  if p_zone not between 1 and 3 then
    raise exception 'INVALID_EXPEDITION_ZONE';
  end if;

  select
    version.chapter_id,
    case
      when jsonb_typeof(
        version.manifest #> array['zones', (p_zone - 1)::text, 'bits_reward']
      ) = 'number'
        then greatest(0, least(200, (
          version.manifest #>> array['zones', (p_zone - 1)::text, 'bits_reward']
        )::integer))
      else 0
    end
    into v_chapter_id, v_scheduled
    from public.expedition_chapter_versions version
   where version.id = p_run.chapter_version_id;
  if not found then raise exception 'CHAPTER_NOT_AVAILABLE'; end if;

  perform 1 from public.profiles where id = p_run.owner_id for update;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;

  select * into v_receipt
    from public.expedition_zone_rewards
   where run_id = p_run.id and zone = p_zone;
  if found then
    return jsonb_build_object(
      'zone', v_receipt.zone,
      'scheduled_bits', v_receipt.scheduled_bits,
      'bits', v_receipt.bits,
      'capped', v_receipt.bits < v_receipt.scheduled_bits,
      'daily_bits', public.expedition_daily_bits_status(
        p_run.owner_id,
        p_run.chapter_version_id
      )
    );
  end if;

  v_status := public.expedition_daily_bits_status(
    p_run.owner_id,
    p_run.chapter_version_id
  );
  if v_status is null then raise exception 'CHAPTER_NOT_AVAILABLE'; end if;
  v_payout := least(
    v_scheduled,
    greatest(0, coalesce((v_status->>'bits_remaining')::integer, 0))
  );

  -- Legacy manifests have no repeatable Zone reward and leave no zero receipt.
  if v_scheduled = 0 then
    return jsonb_build_object(
      'zone', p_zone,
      'scheduled_bits', 0,
      'bits', 0,
      'capped', false,
      'daily_bits', v_status
    );
  end if;

  insert into public.expedition_zone_rewards (
    run_id,
    owner_id,
    chapter_id,
    chapter_version_id,
    zone,
    scheduled_bits,
    bits
  ) values (
    p_run.id,
    p_run.owner_id,
    v_chapter_id,
    p_run.chapter_version_id,
    p_zone,
    v_scheduled,
    v_payout
  )
  returning * into v_receipt;

  if v_payout > 0 then
    update public.profiles
       set bits = bits + v_payout
     where id = p_run.owner_id;
    insert into public.quota_ledger (
      owner_id,
      currency,
      delta,
      reason,
      ref_id
    ) values (
      p_run.owner_id,
      'bits',
      v_payout,
      'expedition_zone',
      v_receipt.id
    );
  end if;

  return jsonb_build_object(
    'zone', v_receipt.zone,
    'scheduled_bits', v_receipt.scheduled_bits,
    'bits', v_receipt.bits,
    'capped', v_receipt.bits < v_receipt.scheduled_bits,
    'daily_bits', public.expedition_daily_bits_status(
      p_run.owner_id,
      p_run.chapter_version_id
    )
  );
end $$;

create or replace function public.apply_expedition_run_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_completed boolean;
  v_zone_cleared boolean;
begin
  -- This trigger is the sole writer for route history.
  new.visited_node_ids := old.visited_node_ids;

  if new.zone_attempt > old.zone_attempt and new.nodes_completed = 0 then
    new.visited_node_ids := '[]'::jsonb;
    return new;
  end if;

  v_completed := old.current_node_id is not null
    and old.pending_node is not null
    and new.pending_node is null
    and new.zone_attempt = old.zone_attempt
    and (
      new.nodes_completed = old.nodes_completed + 1
      or (
        old.pending_node->>'kind' = 'boss'
        and old.zone = 3
        and new.status = 'complete'
      )
    );
  if not v_completed then return new; end if;

  if not (new.visited_node_ids ? old.current_node_id) then
    new.visited_node_ids := new.visited_node_ids
      || jsonb_build_array(old.current_node_id);
  end if;

  v_zone_cleared := (
    new.status = 'checkpoint'
    and old.zone < 3
    and old.nodes_completed = 3
    and new.zone = old.zone + 1
  ) or (
    new.status = 'complete'
    and old.zone = 3
    and old.pending_node->>'kind' = 'boss'
  );
  if v_zone_cleared then
    perform public.award_expedition_zone_bits(old, old.zone);
  end if;
  return new;
end $$;

drop trigger if exists expedition_runs_completion_reward
  on public.expedition_runs;
create trigger expedition_runs_completion_reward
before update on public.expedition_runs
for each row execute function public.apply_expedition_run_completion();

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

revoke all on function public.expedition_daily_bits_status(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.award_expedition_zone_bits(
  public.expedition_runs,
  smallint
) from public, anon, authenticated;
revoke all on function public.apply_expedition_run_completion()
  from public, anon, authenticated;
revoke all on function public.expedition_run_payload(public.expedition_runs)
  from public, anon, authenticated;

grant execute on function public.expedition_daily_bits_status(uuid, uuid)
  to service_role;
grant execute on function public.award_expedition_zone_bits(
  public.expedition_runs,
  smallint
) to service_role;
grant execute on function public.expedition_run_payload(public.expedition_runs)
  to service_role;
