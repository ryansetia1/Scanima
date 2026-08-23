import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client for Client Components: drives the Google OAuth (PKCE)
 * sign-in flow, and subscribes to postgres_changes for live queue/case
 * updates (see realtime-refresh.tsx). Holds the publishable anon key,
 * nothing else — every privileged read or write still goes through
 * admin_moderation. Realtime reads are gated by the staff-scoped RLS
 * policies in 20260823160255_atlas_moderation_realtime_rls.sql, not by
 * anything in this file.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
