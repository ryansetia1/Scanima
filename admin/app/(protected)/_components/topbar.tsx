import { LogOut } from "lucide-react";
import { signOutAction } from "@/lib/actions/auth";
import type { StaffRole } from "@/lib/types";

export function Topbar({ email, role }: { email: string | null; role: StaffRole }) {
  return (
    <header className="flex h-14 items-center justify-between border-b border-deck-border px-6">
      <p className="font-heading text-sm font-semibold tracking-wide text-deck-text">
        Scanima Control Deck
      </p>
      <div className="flex items-center gap-4 text-sm">
        <span className="text-deck-muted">{email ?? "Unknown staff"}</span>
        <span className="rounded-full border border-deck-border px-2 py-0.5 text-xs uppercase tracking-wide text-deck-secondary">
          {role}
        </span>
        <form action={signOutAction}>
          <button
            type="submit"
            className="flex items-center gap-1.5 text-deck-muted transition-colors hover:text-deck-danger"
          >
            <LogOut size={14} aria-hidden="true" />
            Sign out
          </button>
        </form>
      </div>
    </header>
  );
}
