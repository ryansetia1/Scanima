"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition, type ReactNode } from "react";
import type { CaseSource, CaseStatusFilter } from "@/lib/types";

const STATUSES: CaseStatusFilter[] = ["open", "approved", "rejected", "hidden", "all"];
const SOURCES: CaseSource[] = ["publish", "report", "appeal", "manual"];

export function QueueFilters({
  status,
  source,
  assignedStaffId,
}: {
  status: CaseStatusFilter;
  source: CaseSource | undefined;
  assignedStaffId: string | undefined;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [staffIdInput, setStaffIdInput] = useState(assignedStaffId ?? "");

  function navigate(next: { status?: string; source?: string; assignedStaffId?: string }) {
    const params = new URLSearchParams();
    params.set("status", next.status ?? status);
    const nextSource = next.source ?? source ?? "";
    if (nextSource) params.set("source", nextSource);
    const nextStaffId = next.assignedStaffId ?? assignedStaffId ?? "";
    if (nextStaffId) params.set("assigned_staff_id", nextStaffId);
    params.set("page", "1");
    startTransition(() => router.push(`/queue?${params.toString()}`));
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        navigate({ assignedStaffId: staffIdInput });
      }}
      className="flex flex-wrap items-end gap-4 rounded-lg border border-deck-border bg-deck-surface p-4"
    >
      <Field label="Status">
        <select
          value={status}
          onChange={(e) => navigate({ status: e.target.value })}
          className="deck-select"
        >
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </Field>
      <Field label="Source">
        <select
          value={source ?? ""}
          onChange={(e) => navigate({ source: e.target.value })}
          className="deck-select"
        >
          <option value="">all</option>
          {SOURCES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </Field>
      <Field label="Assigned staff ID">
        <input
          value={staffIdInput}
          onChange={(e) => setStaffIdInput(e.target.value)}
          placeholder="uuid"
          className="deck-input w-56 font-data text-xs"
        />
      </Field>
      <button type="submit" className="deck-button-primary">
        Apply
      </button>
      {isPending ? (
        <span className="flex items-center gap-2 text-xs text-deck-muted">
          <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-deck-border border-t-deck-secondary" />
          Updating…
        </span>
      ) : null}
    </form>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1 text-xs text-deck-muted">
      {label}
      {children}
    </label>
  );
}
