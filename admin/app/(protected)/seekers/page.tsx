import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { SeekerProfileResult, WhoAmI } from "@/lib/types";
import { SanctionPanel } from "./sanction-panel";

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function SeekersPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const profileId = first(sp.profile_id)?.trim();

  const accessToken = await requireAccessToken();
  const who = await callAdminApi<WhoAmI>("whoami", {}, accessToken).catch(() => null);
  const canManage = who?.role === "moderator" || who?.role === "admin";

  let profile: SeekerProfileResult | null = null;
  let errorMessage: string | null = null;

  if (profileId) {
    try {
      profile = await callAdminApi<SeekerProfileResult>("seeker_profile", { profile_id: profileId }, accessToken);
    } catch (err) {
      errorMessage = err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load this profile.";
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-lg font-semibold text-deck-text">Seekers</h1>
        <p className="text-sm text-deck-muted">
          Paste a profile UUID (e.g. copied from a case&apos;s entry owner) to look up their Atlas activity.
        </p>
      </div>

      <form method="get" className="flex items-end gap-3 rounded-lg border border-deck-border bg-deck-surface p-4">
        <label className="flex flex-1 flex-col gap-1 text-xs text-deck-muted">
          Profile ID
          <input
            name="profile_id"
            defaultValue={profileId ?? ""}
            placeholder="uuid"
            className="deck-input font-data text-xs"
          />
        </label>
        <button type="submit" className="deck-button-primary">
          Look up
        </button>
      </form>

      {errorMessage ? (
        <p className="rounded-md border border-deck-danger/40 bg-deck-danger/10 p-4 text-sm text-deck-danger">
          {errorMessage}
        </p>
      ) : null}

      {profile ? (
        <div className="grid grid-cols-2 gap-6">
          <div className="flex flex-col gap-6">
            <section className="deck-panel">
              <h2 className="font-heading text-sm font-semibold text-deck-text">
                {profile.profile.seeker_name ?? "Unnamed Seeker"}
              </h2>
              <p className="font-data text-xs text-deck-muted">{profile.profile.id}</p>
              <div className="mt-3 flex gap-6 text-sm">
                <span>
                  <span className="text-deck-gold">{profile.reports_upheld}</span>{" "}
                  <span className="text-deck-muted">reports upheld</span>
                </span>
                <span>
                  <span className="text-deck-muted">{profile.reports_dismissed}</span>{" "}
                  <span className="text-deck-muted">dismissed</span>
                </span>
              </div>
            </section>

            <section className="deck-panel flex flex-col gap-3">
              <h2 className="font-heading text-sm font-semibold text-deck-text">
                Publications ({profile.publications.length})
              </h2>
              {profile.publications.length === 0 ? (
                <p className="text-sm text-deck-muted">No published entries.</p>
              ) : (
                <ul className="flex flex-col gap-1 font-data text-xs text-deck-muted">
                  {profile.publications.map((p, i) => (
                    <li key={i} className="truncate rounded border border-deck-border p-2">
                      {JSON.stringify(p)}
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </div>

          <SanctionPanel profileId={profile.profile.id} sanctions={profile.sanctions} canManage={canManage} />
        </div>
      ) : null}
    </div>
  );
}
