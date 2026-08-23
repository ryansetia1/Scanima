import Link from "next/link";
import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { AnalyticsResult } from "@/lib/types";
import { formatSeconds } from "@/lib/ui";

const PRESETS = [7, 30, 90];

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function AnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const sinceDays = Math.min(365, Math.max(1, Number(first(sp.since_days)) || 30));

  const accessToken = await requireAccessToken();

  let result: AnalyticsResult | null = null;
  let errorMessage: string | null = null;
  try {
    result = await callAdminApi<AnalyticsResult>("analytics", { since_days: sinceDays }, accessToken);
  } catch (err) {
    errorMessage = err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load analytics.";
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-lg font-semibold text-deck-text">Analytics</h1>
        <p className="text-sm text-deck-muted">Since {result?.since ?? "—"}</p>
      </div>

      <div className="flex gap-2">
        {PRESETS.map((d) => (
          <Link
            key={d}
            href={`/analytics?since_days=${d}`}
            className={`rounded-md border px-3 py-1.5 text-sm ${
              d === sinceDays
                ? "border-deck-primary bg-deck-primary/20 text-deck-text"
                : "border-deck-border text-deck-muted hover:text-deck-text"
            }`}
          >
            {d}d
          </Link>
        ))}
      </div>

      {errorMessage ? (
        <p className="rounded-md border border-deck-danger/40 bg-deck-danger/10 p-4 text-sm text-deck-danger">
          {errorMessage}
        </p>
      ) : null}

      {result ? (
        <div className="flex flex-col gap-6">
          <div className="grid grid-cols-4 gap-4">
            <Stat label="Open cases" value={result.open_cases} />
            <Stat label="Oldest open case" value={formatSeconds(result.oldest_open_case_age_seconds)} />
            <Stat label="Avg time to decision" value={formatSeconds(result.avg_time_to_decision_seconds)} />
            <Stat label="Active sanctions" value={result.active_sanctions} />
          </div>

          <div className="grid grid-cols-2 gap-6">
            <BreakdownTable title="Decisions by action" data={result.decisions_by_action} />
            <BreakdownTable title="Pass outcomes" data={result.pass_outcomes} />
            <BreakdownTable title="Manual case outcomes" data={result.manual_outcomes} />
            <BreakdownTable title="Report states" data={result.report_states} />
          </div>

          <div className="deck-panel flex gap-8 text-sm">
            <span>
              <span className="text-deck-muted">Appeals: </span>
              <span className="text-deck-text">{result.appeal_total}</span>
            </span>
            <span>
              <span className="text-deck-muted">Appeals approved: </span>
              <span className="text-deck-gold">{result.appeal_approved}</span>
            </span>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="deck-panel">
      <p className="text-xs uppercase tracking-wide text-deck-muted">{label}</p>
      <p className="mt-1 font-heading text-2xl font-semibold text-deck-text">{value}</p>
    </div>
  );
}

function BreakdownTable({ title, data }: { title: string; data: Record<string, number> }) {
  const entries = Object.entries(data);
  const max = Math.max(1, ...entries.map(([, v]) => v));
  return (
    <div className="deck-panel">
      <h2 className="font-heading text-sm font-semibold text-deck-text">{title}</h2>
      {entries.length === 0 ? (
        <p className="mt-2 text-sm text-deck-muted">No data.</p>
      ) : (
        <ul className="mt-3 flex flex-col gap-2">
          {entries.map(([key, value]) => (
            <li key={key} className="flex items-center gap-3 text-sm">
              <span className="w-32 truncate text-deck-muted">{key}</span>
              <div className="h-2 flex-1 rounded-full bg-deck-bg">
                <div
                  className="h-2 rounded-full bg-deck-secondary"
                  style={{ width: `${(value / max) * 100}%` }}
                />
              </div>
              <span className="w-8 text-right text-deck-text">{value}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
