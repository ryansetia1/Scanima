import type { ReactNode } from "react";
import { requireAccessToken, getStaffEmail } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { WhoAmI } from "@/lib/types";
import { signOutAction } from "@/lib/actions/auth";
import { Nav } from "./_components/nav";
import { Topbar } from "./_components/topbar";

// The REAL authorization boundary. proxy.ts only refreshes the session
// cookie and redirects optimistically when there is no session at all — it
// cannot see staff role, because that lives server-side in `staff_accounts`.
// Every render of every protected page goes through `whoami` here first.
export default async function ProtectedLayout({ children }: { children: ReactNode }) {
  const accessToken = await requireAccessToken();
  const email = await getStaffEmail();

  let who: WhoAmI;
  try {
    who = await callAdminApi<WhoAmI>("whoami", {}, accessToken);
  } catch (err) {
    if (err instanceof AdminApiError && err.code === "STAFF_FORBIDDEN") {
      return <AccessRestricted email={email} />;
    }
    if (err instanceof AdminApiError && err.code === "UNAUTHENTICATED") {
      return <AccessRestricted email={email} message="Your session expired. Please sign in again." />;
    }
    return (
      <AccessRestricted
        email={email}
        message={err instanceof AdminApiError ? describeAdminApiError(err) : "Could not reach the moderation service."}
        title="Something went wrong"
      />
    );
  }

  return (
    <div className="grid min-h-screen grid-cols-[220px_1fr] grid-rows-[56px_1fr]">
      <div className="col-span-2 row-start-1">
        <Topbar email={email} role={who.role} />
      </div>
      <aside className="row-start-2 border-r border-deck-border bg-deck-surface">
        <Nav role={who.role} />
      </aside>
      <main className="row-start-2 overflow-y-auto p-6">{children}</main>
    </div>
  );
}

function AccessRestricted({
  email,
  message,
  title = "Access restricted",
}: {
  email: string | null;
  message?: string;
  title?: string;
}) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6 text-center">
      <div className="flex w-full max-w-md flex-col items-center gap-4 rounded-lg border border-deck-border bg-deck-surface p-10">
        <h1 className="font-heading text-lg font-semibold text-deck-text">{title}</h1>
        <p className="text-sm text-deck-muted">
          {message ??
            `${email ?? "This account"} is signed in but is not listed in staff_accounts. Ask an admin to grant access.`}
        </p>
        <form action={signOutAction}>
          <button
            type="submit"
            className="rounded-md border border-deck-border px-4 py-2 text-sm text-deck-text transition-colors hover:border-deck-danger hover:text-deck-danger"
          >
            Sign out
          </button>
        </form>
      </div>
    </main>
  );
}
