import { notFound } from "next/navigation";
import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { CaseDetailResult, WhoAmI } from "@/lib/types";
import { categoryLabel, categoryTextColor, formatDateTime } from "@/lib/ui";
import { ActionPanel } from "./action-panel";

export default async function CaseDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const accessToken = await requireAccessToken();

  let detail: CaseDetailResult;
  let who: WhoAmI | null = null;
  try {
    [detail, who] = await Promise.all([
      callAdminApi<CaseDetailResult>("case_detail", { case_id: id }, accessToken),
      callAdminApi<WhoAmI>("whoami", {}, accessToken).catch(() => null),
    ]);
  } catch (err) {
    if (err instanceof AdminApiError && err.code === "CASE_NOT_FOUND") notFound();
    return (
      <p className="rounded-md border border-deck-danger/40 bg-deck-danger/10 p-4 text-sm text-deck-danger">
        {err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load this case."}
      </p>
    );
  }

  const canDecide = who?.role === "moderator" || who?.role === "admin";
  const caseRow = detail.case;
  const entry = detail.entry;

  return (
    <div className="grid grid-cols-[1fr_320px] gap-6">
      <div className="flex flex-col gap-6">
        <div>
          <h1 className="font-heading text-lg font-semibold text-deck-text">
            Case <span className="font-data text-base text-deck-muted">{id}</span>
          </h1>
          <p className={`text-sm font-medium ${categoryTextColor(caseRow.category ?? null)}`}>
            {categoryLabel(caseRow.category ?? null)} · status {String(caseRow.status ?? "unknown")} ·
            source {String(caseRow.source ?? "unknown")}
          </p>
        </div>

        <section className="deck-panel flex gap-4">
          <Figure label="Idle thumb" src={entry.thumb_url ?? null} />
          <Figure label="Full sheet" src={entry.sheet_url ?? null} wide />
        </section>

        <section className="deck-panel flex flex-col gap-3">
          <h2 className="font-heading text-sm font-semibold text-deck-text">Automated findings</h2>
          {detail.runs.length === 0 ? (
            <p className="text-sm text-deck-muted">No automated moderation runs recorded for this art hash.</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {detail.runs.map((run, i) => (
                <li key={i} className="rounded-md border border-deck-border p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-3">
                    <span className="rounded-full border border-deck-border px-2 py-0.5 text-xs text-deck-muted">
                      pass {run.pass}
                    </span>
                    <span className="font-medium text-deck-text">{run.decision}</span>
                    <span className={categoryTextColor(run.category)}>{categoryLabel(run.category)}</span>
                    {run.confidence ? (
                      <span className="text-xs text-deck-muted">confidence: {run.confidence}</span>
                    ) : null}
                    <span className="ml-auto text-xs text-deck-muted">{formatDateTime(run.created_at)}</span>
                  </div>
                  {run.reason_code ? (
                    <p className="mt-1 font-data text-xs text-deck-muted">reason: {run.reason_code}</p>
                  ) : null}
                  {run.evidence?.matched_name ? (
                    <p className="mt-1 text-xs text-deck-secondary">
                      matched name: {String(run.evidence.matched_name)}
                    </p>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="deck-panel flex flex-col gap-3">
          <h2 className="font-heading text-sm font-semibold text-deck-text">
            Report history ({detail.reports.length})
          </h2>
          {detail.reports.length === 0 ? (
            <p className="text-sm text-deck-muted">No reports on this entry.</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {detail.reports.map((r, i) => (
                <li key={i} className="rounded-md border border-deck-border p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-3">
                    <span className="font-medium text-deck-text">{r.category}</span>
                    <span className="text-xs text-deck-muted">{r.resolution_state}</span>
                    <span className="ml-auto text-xs text-deck-muted">{formatDateTime(r.created_at)}</span>
                  </div>
                  {r.note ? <p className="mt-1 text-xs text-deck-muted">{r.note}</p> : null}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="deck-panel flex flex-col gap-3">
          <h2 className="font-heading text-sm font-semibold text-deck-text">
            Prior decisions ({detail.decisions.length})
          </h2>
          {detail.decisions.length === 0 ? (
            <p className="text-sm text-deck-muted">No staff decisions recorded yet.</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {detail.decisions.map((d, i) => (
                <li key={i} className="rounded-md border border-deck-border p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-3">
                    <span className="font-medium text-deck-text">{d.action}</span>
                    <span className="font-data text-xs text-deck-muted">{d.staff_id}</span>
                    <span className="ml-auto text-xs text-deck-muted">{formatDateTime(d.created_at)}</span>
                  </div>
                  <p className="mt-1 font-data text-xs text-deck-muted">reason: {d.reason_code}</p>
                  {d.note ? <p className="mt-1 text-xs text-deck-muted">{d.note}</p> : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      <div>
        {canDecide ? (
          <ActionPanel caseId={id} />
        ) : (
          <div className="deck-panel text-sm text-deck-muted">
            Your role ({who?.role ?? "unknown"}) can view this case but cannot take action on it.
          </div>
        )}
      </div>
    </div>
  );
}

function Figure({ label, src, wide }: { label: string; src?: string | null; wide?: boolean }) {
  return (
    <div className={`flex flex-col gap-2 ${wide ? "flex-1" : ""}`}>
      <span className="text-xs text-deck-muted">{label}</span>
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt={label} className="max-h-96 w-full rounded-md border border-deck-border object-contain" />
      ) : (
        <div className="flex h-40 w-full items-center justify-center rounded-md border border-deck-border bg-deck-bg text-xs text-deck-muted">
          No image available
        </div>
      )}
    </div>
  );
}
