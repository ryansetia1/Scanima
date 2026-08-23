import Link from "next/link";
import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { ReportsListResult } from "@/lib/types";
import { formatDateTime } from "@/lib/ui";

const CATEGORIES = ["character", "sexual", "gore", "hate", "other"];
const RESOLUTION_STATES = ["pending", "upheld", "dismissed"];
const PER_PAGE = 24;

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const category = first(sp.category);
  const resolutionState = first(sp.resolution_state);
  const entryId = first(sp.entry_id);
  const page = Math.max(1, Number(first(sp.page)) || 1);

  const accessToken = await requireAccessToken();

  let result: ReportsListResult | null = null;
  let errorMessage: string | null = null;
  try {
    result = await callAdminApi<ReportsListResult>(
      "reports_list",
      {
        entry_id: entryId || undefined,
        category: category || undefined,
        resolution_state: resolutionState || undefined,
        page,
        per_page: PER_PAGE,
      },
      accessToken,
    );
  } catch (err) {
    errorMessage = err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load reports.";
  }

  const totalPages = result ? Math.max(1, Math.ceil(result.total / result.per_page)) : 1;

  function pageHref(target: number) {
    const params = new URLSearchParams();
    if (entryId) params.set("entry_id", entryId);
    if (category) params.set("category", category);
    if (resolutionState) params.set("resolution_state", resolutionState);
    params.set("page", String(target));
    return `/reports?${params.toString()}`;
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-lg font-semibold text-deck-text">Reports</h1>
        <p className="text-sm text-deck-muted">
          {result ? `${result.total} report${result.total === 1 ? "" : "s"}` : "—"}
        </p>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-4 rounded-lg border border-deck-border bg-deck-surface p-4">
        <label className="flex flex-col gap-1 text-xs text-deck-muted">
          Entry ID
          <input name="entry_id" defaultValue={entryId ?? ""} placeholder="uuid" className="deck-input w-56 font-data text-xs" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-deck-muted">
          Category
          <select name="category" defaultValue={category ?? ""} className="deck-select">
            <option value="">all</option>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-deck-muted">
          Resolution
          <select name="resolution_state" defaultValue={resolutionState ?? ""} className="deck-select">
            <option value="">all</option>
            {RESOLUTION_STATES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
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
          {result.reports.length === 0 ? (
            <p className="text-sm text-deck-muted">No reports match this filter.</p>
          ) : (
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-deck-border text-left text-xs text-deck-muted">
                  <th className="py-2 pr-4">Entry</th>
                  <th className="py-2 pr-4">Category</th>
                  <th className="py-2 pr-4">Resolution</th>
                  <th className="py-2 pr-4">Note</th>
                  <th className="py-2 pr-4">Reported</th>
                </tr>
              </thead>
              <tbody>
                {result.reports.map((r, i) => (
                  <tr key={i} className="border-b border-deck-border/50">
                    <td className="py-2 pr-4">
                      <Link href={`/reports?entry_id=${r.entry_id}`} className="font-data text-xs text-deck-secondary hover:underline">
                        {r.entry_id}
                      </Link>
                    </td>
                    <td className="py-2 pr-4">{r.category}</td>
                    <td className="py-2 pr-4 text-deck-muted">{r.resolution_state}</td>
                    <td className="py-2 pr-4 text-deck-muted">{r.note ?? "—"}</td>
                    <td className="py-2 pr-4 text-xs text-deck-muted">{formatDateTime(r.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
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
