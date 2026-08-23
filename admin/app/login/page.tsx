import { GoogleSignInButton } from "./google-sign-in-button";

export default function LoginPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6">
      <div className="flex w-full max-w-sm flex-col items-center gap-8 rounded-lg border border-deck-border bg-deck-surface p-10 text-center">
        <div className="flex flex-col items-center gap-2">
          <div className="h-10 w-10 rounded-md bg-deck-primary" aria-hidden="true" />
          <h1 className="font-heading text-xl font-semibold text-deck-text">
            Scanima Control Deck
          </h1>
          <p className="text-sm text-deck-muted">
            Staff moderation console. Sign-in is restricted to accounts
            granted access in <code className="font-data">staff_accounts</code>.
          </p>
        </div>
        <GoogleSignInButton />
      </div>
    </main>
  );
}
