"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/browser";

export function GoogleSignInButton() {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleClick() {
    setPending(true);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });
    if (error) {
      setError(error.message);
      setPending(false);
    }
    // On success the browser navigates away to Google — nothing else to do.
  }

  return (
    <div className="flex flex-col items-center gap-3">
      <button
        type="button"
        onClick={handleClick}
        disabled={pending}
        className="flex items-center gap-3 rounded-md bg-deck-primary px-5 py-2.5 font-medium text-white transition-colors hover:bg-deck-primary-hover disabled:cursor-not-allowed disabled:opacity-60"
      >
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path
            fill="currentColor"
            d="M12 11v2.8h6.5c-.3 1.6-2.2 4.7-6.5 4.7-3.9 0-7.1-3.2-7.1-7.2s3.2-7.2 7.1-7.2c2.2 0 3.7.9 4.6 1.7l2.5-2.4C17.4 1.6 15 .6 12 .6 5.9.6 1 5.5 1 11.3S5.9 22 12 22c6.9 0 10.6-4.8 10.6-11.4 0-.9-.1-1.5-.2-2.1H12z"
          />
        </svg>
        {pending ? "Redirecting…" : "Sign in with Google"}
      </button>
      {error ? <p className="text-sm text-deck-danger">{error}</p> : null}
    </div>
  );
}
