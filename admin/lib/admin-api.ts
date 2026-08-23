/**
 * The ONLY way this app talks to privileged data. Every call re-verifies the
 * caller's staff role server-side inside admin_moderation — this client is a
 * thin, typed wrapper around that single POST endpoint. Never call Postgres
 * directly from admin/; there are no player/staff RLS policies to allow it.
 */
export class AdminApiError extends Error {
  code: string;
  status: number;

  constructor(code: string, status: number, message?: string) {
    super(message ?? code);
    this.name = "AdminApiError";
    this.code = code;
    this.status = status;
  }
}

export async function callAdminApi<T = unknown>(
  operation: string,
  params: Record<string, unknown>,
  accessToken: string,
): Promise<T> {
  const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/admin_moderation`;

  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ operation, ...params }),
      cache: "no-store",
    });
  } catch {
    throw new AdminApiError("NETWORK_ERROR", 0, "Could not reach admin_moderation.");
  }

  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    throw new AdminApiError(
      typeof body?.error === "string" ? body.error : "UNKNOWN_ERROR",
      res.status,
      typeof body?.message === "string" ? body.message : undefined,
    );
  }

  return body as T;
}

/** Human-readable fallback copy for error codes the UI should render, not crash on. */
export function describeAdminApiError(err: AdminApiError): string {
  switch (err.code) {
    case "UNAUTHENTICATED":
      return "Your session expired. Please sign in again.";
    case "STAFF_FORBIDDEN":
      return "This account is not authorized for the Control Deck.";
    case "CASE_NOT_FOUND":
      return "That case no longer exists.";
    case "ENTRY_NOT_FOUND":
      return "That entry or profile could not be found.";
    case "SANCTION_NOT_FOUND":
      return "That sanction no longer exists.";
    case "STAFF_NOT_FOUND":
      return "That staff account could not be found.";
    case "CASE_ALREADY_RESOLVED":
      return "This case was already resolved by someone else.";
    case "SANCTION_ALREADY_REVOKED":
      return "This sanction was already revoked.";
    case "CANNOT_REVOKE_SELF":
      return "You cannot revoke your own staff access here.";
    case "NETWORK_ERROR":
      return "Could not reach the moderation service. Check your connection and try again.";
    default:
      if (err.code.startsWith("INVALID_")) {
        return `Invalid request: ${err.code}.`;
      }
      return err.message || "Something went wrong.";
  }
}
