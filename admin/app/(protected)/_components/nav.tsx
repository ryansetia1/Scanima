import Link from "next/link";
import {
  ListChecks,
  Flag,
  Users,
  BarChart3,
  ScrollText,
  ShieldCheck,
} from "lucide-react";
import type { StaffRole } from "@/lib/types";

const ITEMS = [
  { href: "/queue", label: "Queue", icon: ListChecks },
  { href: "/reports", label: "Reports", icon: Flag },
  { href: "/seekers", label: "Seekers", icon: Users },
  { href: "/analytics", label: "Analytics", icon: BarChart3 },
  { href: "/audit", label: "Audit", icon: ScrollText },
] as const;

export function Nav({ role }: { role: StaffRole }) {
  return (
    <nav aria-label="Primary" className="flex flex-col gap-1 p-3">
      {ITEMS.map(({ href, label, icon: Icon }) => (
        <Link
          key={href}
          href={href}
          className="flex items-center gap-3 rounded-md px-3 py-2 text-sm text-deck-muted transition-colors hover:bg-deck-surface-raised hover:text-deck-text"
        >
          <Icon size={16} aria-hidden="true" />
          {label}
        </Link>
      ))}
      {role === "admin" ? (
        <Link
          href="/staff"
          className="flex items-center gap-3 rounded-md px-3 py-2 text-sm text-deck-muted transition-colors hover:bg-deck-surface-raised hover:text-deck-text"
        >
          <ShieldCheck size={16} aria-hidden="true" />
          Staff
        </Link>
      ) : null}
    </nav>
  );
}
