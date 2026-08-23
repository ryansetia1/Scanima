"use server";

import { randomUUID } from "node:crypto";
import { getAccessToken } from "@/lib/session";
import { callAdminApi } from "@/lib/admin-api";
import type { DecideAction, DecideResult } from "@/lib/types";

/**
 * All mutation entry points for the console. Each generates its own fresh
 * idempotency key per invocation (one invocation = one staff click), and
 * each re-derives the access token server-side rather than trusting
 * anything proxy.ts or a client component claims about the session —
 * admin_moderation re-verifies the staff role again regardless.
 */

async function requireToken(): Promise<string> {
  const token = await getAccessToken();
  if (!token) {
    throw new Error("Your session expired. Please reload and sign in again.");
  }
  return token;
}

export async function decideCase(
  caseId: string,
  action: DecideAction,
  reasonCode: string,
  note: string,
): Promise<DecideResult> {
  const accessToken = await requireToken();
  return callAdminApi<DecideResult>(
    "decide",
    {
      case_id: caseId,
      action,
      reason_code: reasonCode,
      note: note.trim() || undefined,
      idempotency_key: randomUUID(),
    },
    accessToken,
  );
}

export async function restoreEntryAction(
  entryId: string,
  reasonCode: string,
  note: string,
): Promise<DecideResult> {
  const accessToken = await requireToken();
  return callAdminApi<DecideResult>(
    "restore_entry",
    {
      entry_id: entryId,
      reason_code: reasonCode,
      note: note.trim() || undefined,
      idempotency_key: randomUUID(),
    },
    accessToken,
  );
}

export async function sanctionSetAction(
  profileId: string,
  scope: "atlas_publish" | "atlas_report",
  reasonCode: string,
  note: string,
  expiresAt: string | null,
): Promise<{ sanction_id: string }> {
  const accessToken = await requireToken();
  return callAdminApi(
    "sanction_set",
    {
      profile_id: profileId,
      scope,
      reason_code: reasonCode,
      note: note.trim() || undefined,
      expires_at: expiresAt,
      idempotency_key: randomUUID(),
    },
    accessToken,
  );
}

export async function sanctionRevokeAction(
  sanctionId: string,
  reasonCode: string,
): Promise<{ ok: true }> {
  const accessToken = await requireToken();
  return callAdminApi(
    "sanction_revoke",
    {
      sanction_id: sanctionId,
      reason_code: reasonCode,
      idempotency_key: randomUUID(),
    },
    accessToken,
  );
}

export async function staffSetRoleAction(
  target: { targetUserId?: string; targetEmail?: string },
  role: "viewer" | "moderator" | "admin" | "revoked",
): Promise<{ ok: true; role: string }> {
  const accessToken = await requireToken();
  return callAdminApi(
    "staff_set_role",
    {
      target_user_id: target.targetUserId || undefined,
      target_email: target.targetEmail || undefined,
      role,
      idempotency_key: randomUUID(),
    },
    accessToken,
  );
}
