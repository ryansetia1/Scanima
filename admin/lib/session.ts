import { redirect } from "next/navigation";
import { createClient } from "./supabase/server";

/** Returns the signed-in staff member's access token, or null if not signed in. */
export async function getAccessToken(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  return session?.access_token ?? null;
}

/** For use in Server Components/pages during render — redirects to /login if unauthenticated. */
export async function requireAccessToken(): Promise<string> {
  const token = await getAccessToken();
  if (!token) redirect("/login");
  return token;
}

/** The signed-in staff member's email, for display in the top bar. */
export async function getStaffEmail(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.email ?? null;
}
