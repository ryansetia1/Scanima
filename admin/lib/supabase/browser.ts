import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client for Client Components. Only used to drive the Google
 * OAuth (PKCE) sign-in flow — holds the publishable anon key, nothing else.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
