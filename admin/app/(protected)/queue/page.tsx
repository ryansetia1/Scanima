import Link from "next/link";
import type { ReactNode } from "react";
import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { CaseSource, CaseStatusFilter, QueueListResult } from "@/lib/types";
import { ageBorderColor, categoryLabel, categoryTextColor, formatRelativeAge } from "@/lib/ui";

const STATUSES: CaseStatusFilter[] = ["open", "approved", "rejected", "hidden", "all"];
const SOURCES: CaseSource[] = ["publish", "report", "appeal", "manual"];
const PER_PAGE = 24;

type SearchParams = Record<string, string | string[] | undefined>;

function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function QueuePage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const status = (first(sp.status) as CaseStatusFilter | undefined) ?? "open";
  const source = first(sp.source) as CaseSource | undefined;
  const assignedStaffId = first(sp.assigned_staff_id);
  const page = Math.max(1, Number(first(sp.page)) || 1);

  const accessToken = await requireAccessToken();

  let result: QueueListResult | null = null;
  let errorMessage: string | null = null;
  try {
    result = await callAdminApi<QueueListResult>(
      "queue_list",
      {
        status,
        source: source || undefined,
        assigned_staff_id: assignedStaffId || undefined,
        page,
        per_page: PER_PAGE,
      },
      accessToken,
    );
  } catch (err) {
    errorMessage = err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load the queue.";
  }

  const totalPages = result ? Math.max(1, Math.ceil(result.total / result.per_page)) : 1;

  function pageHref(target: number) {
    const params = new URLSearchParams();
    params.set("status", status);
    if (source) params.set("source", source);
    if (assignedStaffId) params.set("assigned_staff_id", assignedStaffId);
    params.set("page", String(target));
    return `/queue?${params.toString()}`;
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-lg font-semibold text-deck-text">Moderation queue</h1>
        <p className="text-sm text-deck-muted">
          {result ? `${result.total} case${result.total === 1 ? "" : "s"}` : "—"}
        </p>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-4 rounded-lg border border-deck-border bg-deck-surface p-4">
        <Field label="Status">
          <select name="status" defaultValue={status} className="deck-select">
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Source">
          <select name="source" defaultValue={source ?? ""} className="deck-select">
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
            name="assigned_staff_id"
            defaultValue={assignedStaffId ?? ""}
            placeholder="uuid"
            className="deck-input w-56 font-data text-xs"
          />
        </Field>
        <button type="submit" className="deck-button-primary">
          Apply
        </button>
      </form>

      {errorMessage ? (
        <p className="rounded-md border border-deck-danger/40 bg-deck-danger/10 p-4 text-sm text-deck-danger">
          {errorMessage}
        </p>
      ) : null}

      {result ? (
        <div className="flex flex-col gap-2">
          {result.cases.length === 0 ? (
            <p className="text-sm text-deck-muted">No cases match this filter.</p>
          ) : (
            result.cases.map((c) => (
              <Link
                key={c.case_id}
                href={`/cases/${c.case_id}`}
                className={`flex items-center gap-4 rounded-md border border-deck-border border-l-4 bg-deck-surface p-3 transition-colors hover:bg-deck-surface-raised ${ageBorderColor(c.created_at)}`}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={c.thumb_url ?? undefined}
                  alt=""
                  className="h-12 w-12 rounded bg-deck-bg object-cover"
                />
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-sm font-medium text-deck-text">
                    {c.entry_display_name ?? "Untitled entry"}
                  </span>
                  <span className="font-data text-xs text-deck-muted">{c.entry_id}</span>
                </div>
                <span className="text-xs uppercase tracking-wide text-deck-muted">{c.source}</span>
                <span className={`text-xs font-medium ${categoryTextColor(c.category)}`}>
                  {categoryLabel(c.category)}
                </span>
                {c.entry_report_count > 0 ? (
                  <span className="rounded-full border border-deck-border px-2 py-0.5 text-xs text-deck-muted">
                    {c.entry_report_count} report{c.entry_report_count === 1 ? "" : "s"}
                  </span>
                ) : null}
                <span className="w-16 text-right text-xs text-deck-muted">
                  {formatRelativeAge(c.created_at)}
                </span>
              </Link>
            ))
          )}

          {totalPages > 1 ? (
            <div className="mt-2 flex items-center justify-between text-sm text-deck-muted">
              <Link
                href={pageHref(Math.max(1, page - 1))}
                aria-disabled={page <= 1}
                className={page <= 1 ? "pointer-events-none opacity-40" : "hover:text-deck-text"}
              >
                ← Previous
              </Link>
              <span>
                Page {page} of {totalPages}
              </span>
              <Link
                href={pageHref(Math.min(totalPages, page + 1))}
                aria-disabled={page >= totalPages}
                className={page >= totalPages ? "pointer-events-none opacity-40" : "hover:text-deck-text"}
              >
                Next →
              </Link>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
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
