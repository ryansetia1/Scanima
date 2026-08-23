import Link from "next/link";
import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { AuditListResult } from "@/lib/types";
import { formatDateTime } from "@/lib/ui";

const PER_PAGE = 30;

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const targetType = first(sp.target_type);
  const actorId = first(sp.actor_id);
  const page = Math.max(1, Number(first(sp.page)) || 1);

  const accessToken = await requireAccessToken();

  let result: AuditListResult | null = null;
  let errorMessage: string | null = null;
  try {
    result = await callAdminApi<AuditListResult>(
      "audit_list",
      { target_type: targetType || undefined, actor_id: actorId || undefined, page, per_page: PER_PAGE },
      accessToken,
    );
  } catch (err) {
    errorMessage = err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load the audit log.";
  }

  const totalPages = result ? Math.max(1, Math.ceil(result.total / result.per_page)) : 1;

  function pageHref(target: number) {
    const params = new URLSearchParams();
    if (targetType) params.set("target_type", targetType);
    if (actorId) params.set("actor_id", actorId);
    params.set("page", String(target));
    return `/audit?${params.toString()}`;
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-lg font-semibold text-deck-text">Audit log</h1>
        <p className="text-sm text-deck-muted">
          {result ? `${result.total} entr${result.total === 1 ? "y" : "ies"}` : "—"}
        </p>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-4 rounded-lg border border-deck-border bg-deck-surface p-4">
        <label className="flex flex-col gap-1 text-xs text-deck-muted">
          Target type
          <input name="target_type" defaultValue={targetType ?? ""} placeholder="e.g. case" className="deck-input" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-deck-muted">
          Actor ID
          <input name="actor_id" defaultValue={actorId ?? ""} placeholder="uuid" className="deck-input font-data text-xs" />
        </label>
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
          {result.entries.length === 0 ? (
            <p className="text-sm text-deck-muted">No audit entries match this filter.</p>
          ) : (
            result.entries.map((e) => (
              <details key={e.id} className="rounded-md border border-deck-border bg-deck-surface p-3">
                <summary className="flex cursor-pointer flex-wrap items-center gap-3 text-sm">
                  <span className="font-medium text-deck-text">{e.action}</span>
                  <span className="text-xs text-deck-muted">{e.target_type}</span>
                  <span className="font-data text-xs text-deck-muted">{e.target_id}</span>
                  <span className="font-data text-xs text-deck-secondary">{e.actor_id}</span>
                  <span className="ml-auto text-xs text-deck-muted">{formatDateTime(e.created_at)}</span>
                </summary>
                <div className="mt-3 grid grid-cols-2 gap-3">
                  <div>
                    <p className="mb-1 text-xs uppercase tracking-wide text-deck-muted">Before</p>
                    <pre className="max-h-64 overflow-auto rounded bg-deck-bg p-2 font-data text-xs text-deck-muted">
                      {JSON.stringify(e.before, null, 2) ?? "null"}
                    </pre>
                  </div>
                  <div>
                    <p className="mb-1 text-xs uppercase tracking-wide text-deck-muted">After</p>
                    <pre className="max-h-64 overflow-auto rounded bg-deck-bg p-2 font-data text-xs text-deck-muted">
                      {JSON.stringify(e.after, null, 2) ?? "null"}
                    </pre>
                  </div>
                </div>
              </details>
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
