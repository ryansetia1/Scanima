import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Supabase client for Server Components / Server Actions / Route Handlers.
 * Holds only the publishable anon key — used solely for Auth (reading the
 * signed-in session) so we can forward the access token to admin_moderation.
 * Never used for direct table access; RLS default-denies everything anyway.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Called from a Server Component render — cookies are read-only
            // there. proxy.ts refreshes the session cookie on navigation.
          }
        },
      },
    },
  );
}
