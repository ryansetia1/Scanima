-- Chapter opponents use content slugs (sugarworks-gumdrop), not UUIDs.
-- start/commit previously cast opponent anima_id to uuid and 400'd every Battle node.

create or replace function public.expedition_roster_ids(p_roster jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    array_agg(member->>'anima_id' order by member->>'anima_id'),
    '{}'::text[]
  )
  from jsonb_array_elements(coalesce(p_roster, '[]'::jsonb)) member
  where coalesce(member->>'anima_id', '') <> '';
$$;

revoke all on function public.expedition_roster_ids(jsonb) from public, anon, authenticated;
grant execute on function public.expedition_roster_ids(jsonb) to service_role;
