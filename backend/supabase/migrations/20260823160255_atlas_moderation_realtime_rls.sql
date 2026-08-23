-- Staff-scoped read policies enabling Supabase Realtime for the admin
-- console (Queue and Case Detail live updates, no manual refresh). These are
-- the FIRST real RLS policies on any Atlas Moderation Admin table — before
-- this, every table was zero-policy default-deny with all access routed
-- through admin_moderation's service-role client. Realtime's
-- postgres_changes feed respects RLS exactly like REST does, so it needs an
-- actual SELECT policy to deliver anything.
--
-- This changes nothing about how WRITES work: every mutation still
-- exclusively goes through the SECURITY DEFINER RPCs in
-- 20260823080000_atlas_moderation_v2_schema.sql. This migration only grants
-- read-only access, scoped to staff_accounts membership, for exactly the
-- three tables the admin app subscribes to for live updates.
--
-- Anonymous and regular player sessions are also `authenticated` in
-- Supabase (anonymous sign-in still issues an authenticated JWT, just with
-- is_anonymous=true) -- the policy below applies to every such session, but
-- is_staff() evaluates false for anyone without a staff_accounts row, so a
-- player session still sees zero rows. Nothing is exposed to non-staff.

create or replace function public.is_staff(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.staff_accounts where user_id = p_user_id);
$$;

revoke all on function public.is_staff(uuid) from public, anon, authenticated;
grant execute on function public.is_staff(uuid) to authenticated, service_role;

-- RLS policies only take effect once the role also has the base table
-- GRANT; these three tables had it revoked entirely in the prior migration.
-- Granting SELECT here is safe because the policy below still gates rows to
-- staff only -- a non-staff authenticated session gets the grant but every
-- row is filtered out.
grant select on public.moderation_cases to authenticated;
grant select on public.moderation_decisions to authenticated;
grant select on public.gallery_reports to authenticated;

create policy staff_can_read_moderation_cases
  on public.moderation_cases for select
  to authenticated
  using (public.is_staff(auth.uid()));

create policy staff_can_read_moderation_decisions
  on public.moderation_decisions for select
  to authenticated
  using (public.is_staff(auth.uid()));

create policy staff_can_read_gallery_reports
  on public.gallery_reports for select
  to authenticated
  using (public.is_staff(auth.uid()));

alter publication supabase_realtime add table public.moderation_cases;
alter publication supabase_realtime add table public.moderation_decisions;
alter publication supabase_realtime add table public.gallery_reports;
