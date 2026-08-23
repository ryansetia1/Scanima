import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Exchanges the PKCE code from Google/Supabase for a session cookie. The
// destination is always the fixed post-login route — never a caller-supplied
// path — so this can't become an open redirect.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(`${origin}/queue`);
    }
  }

  return NextResponse.redirect(`${origin}/login?error=auth_callback_failed`);
}
