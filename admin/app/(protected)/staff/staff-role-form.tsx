"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { staffSetRoleAction } from "@/lib/actions/moderation";
import { AdminApiError, describeAdminApiError } from "@/lib/admin-api";

const ROLES = ["viewer", "moderator", "admin", "revoked"] as const;

export function StaffRoleForm() {
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [role, setRole] = useState<(typeof ROLES)[number]>("viewer");
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const isEmail = identifier.includes("@");
  const canSubmit = identifier.trim().length > 0 && !pending;

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setError(null);
    setSuccess(null);
    startTransition(async () => {
      try {
        await staffSetRoleAction(
          isEmail ? { targetEmail: identifier.trim() } : { targetUserId: identifier.trim() },
          role,
        );
        setSuccess(`${identifier} is now ${role}.`);
        setIdentifier("");
        router.refresh();
      } catch (err) {
        setError(err instanceof AdminApiError ? describeAdminApiError(err) : "Could not update role.");
      }
    });
  }

  return (
    <form onSubmit={handleSubmit} className="deck-panel flex flex-wrap items-end gap-4">
      <label className="flex flex-col gap-1 text-xs text-deck-muted">
        Email or user ID
        <input
          value={identifier}
          onChange={(e) => setIdentifier(e.target.value)}
          placeholder="staff@example.com or uuid"
          className="deck-input w-64 font-data text-xs"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs text-deck-muted">
        Role
        <select value={role} onChange={(e) => setRole(e.target.value as typeof role)} className="deck-select">
          {ROLES.map((r) => (
            <option key={r} value={r}>
              {r}
            </option>
          ))}
        </select>
      </label>
      <button type="submit" disabled={!canSubmit} className="deck-button-primary">
        Save
      </button>
      {error ? <p className="text-sm text-deck-danger">{error}</p> : null}
      {success ? <p className="text-sm text-deck-gold">{success}</p> : null}
    </form>
  );
}
