import { requireAccessToken } from "@/lib/session";
import { callAdminApi, AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { StaffRow, WhoAmI } from "@/lib/types";
import { formatDateTime } from "@/lib/ui";
import { StaffRoleForm } from "./staff-role-form";

export default async function StaffPage() {
  const accessToken = await requireAccessToken();

  // UX-only gate — the real one is inside admin_moderation, which requires
  // role == admin for both staff_list and staff_set_role and returns 403
  // regardless of what this page renders.
  const who = await callAdminApi<WhoAmI>("whoami", {}, accessToken).catch(() => null);
  if (who?.role !== "admin") {
    return (
      <p className="deck-panel text-sm text-deck-muted">
        Staff management requires the admin role. Your role is {who?.role ?? "unknown"}.
      </p>
    );
  }

  let staff: StaffRow[] = [];
  let errorMessage: string | null = null;
  try {
    const result = await callAdminApi<{ staff: StaffRow[] }>("staff_list", {}, accessToken);
    staff = result.staff;
  } catch (err) {
    errorMessage = err instanceof AdminApiError ? describeAdminApiError(err) : "Could not load staff list.";
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-lg font-semibold text-deck-text">Staff</h1>
        <p className="text-sm text-deck-muted">Grant or revoke Control Deck access.</p>
      </div>

      <StaffRoleForm />

      {errorMessage ? (
        <p className="rounded-md border border-deck-danger/40 bg-deck-danger/10 p-4 text-sm text-deck-danger">
          {errorMessage}
        </p>
      ) : (
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-deck-border text-left text-xs text-deck-muted">
              <th className="py-2 pr-4">Email</th>
              <th className="py-2 pr-4">Role</th>
              <th className="py-2 pr-4">User ID</th>
              <th className="py-2 pr-4">Granted by</th>
              <th className="py-2 pr-4">Updated</th>
            </tr>
          </thead>
          <tbody>
            {staff.map((s) => (
              <tr key={s.user_id} className="border-b border-deck-border/50">
                <td className="py-2 pr-4">{s.email}</td>
                <td className="py-2 pr-4">
                  <span className="rounded-full border border-deck-border px-2 py-0.5 text-xs uppercase text-deck-secondary">
                    {s.role}
                  </span>
                </td>
                <td className="py-2 pr-4 font-data text-xs text-deck-muted">{s.user_id}</td>
                <td className="py-2 pr-4 font-data text-xs text-deck-muted">{s.granted_by ?? "—"}</td>
                <td className="py-2 pr-4 text-xs text-deck-muted">{formatDateTime(s.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
