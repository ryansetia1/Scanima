"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { sanctionSetAction, sanctionRevokeAction } from "@/lib/actions/moderation";
import { AdminApiError, describeAdminApiError } from "@/lib/admin-api";
import type { ProfileSanction } from "@/lib/types";
import { formatDateTime } from "@/lib/ui";

const REASON_PRESETS = [
  "unsafe_content",
  "ip_character_match",
  "false_positive_correction",
  "report_upheld",
  "owner_appeal_valid",
  "other",
] as const;

function ReasonField({
  value,
  onChange,
  custom,
  onCustomChange,
}: {
  value: string;
  onChange: (v: string) => void;
  custom: string;
  onCustomChange: (v: string) => void;
}) {
  return (
    <div className="flex flex-col gap-1">
      <select value={value} onChange={(e) => onChange(e.target.value)} className="deck-select">
        {REASON_PRESETS.map((p) => (
          <option key={p} value={p}>
            {p}
          </option>
        ))}
      </select>
      {value === "other" ? (
        <input
          value={custom}
          onChange={(e) => onCustomChange(e.target.value)}
          maxLength={64}
          placeholder="short_snake_case_reason"
          className="deck-input"
        />
      ) : null}
    </div>
  );
}

export function SanctionPanel({
  profileId,
  sanctions,
  canManage,
}: {
  profileId: string;
  sanctions: ProfileSanction[];
  canManage: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const [scope, setScope] = useState<"atlas_publish" | "atlas_report">("atlas_publish");
  const [reasonPreset, setReasonPreset] = useState<string>(REASON_PRESETS[0]);
  const [customReason, setCustomReason] = useState("");
  const [note, setNote] = useState("");
  const [expiresAt, setExpiresAt] = useState("");

  const reasonCode = (reasonPreset === "other" ? customReason : reasonPreset).trim();
  const canSet = canManage && reasonCode.length > 0 && reasonCode.length <= 64 && !pending;

  // Revoking an existing sanction has its own reason state — it must never
  // silently reuse whatever is currently sitting in the "set a new sanction"
  // form above, or the audit log records a revoke reason that has nothing to
  // do with why that specific sanction was actually lifted.
  const revokeDialogRef = useRef<HTMLDialogElement>(null);
  const [revokeTargetId, setRevokeTargetId] = useState<string | null>(null);
  const [revokeReasonPreset, setRevokeReasonPreset] = useState<string>(REASON_PRESETS[0]);
  const [revokeCustomReason, setRevokeCustomReason] = useState("");
  const revokeReasonCode = (
    revokeReasonPreset === "other" ? revokeCustomReason : revokeReasonPreset
  ).trim();
  const canRevoke = revokeReasonCode.length > 0 && revokeReasonCode.length <= 64 && !pending;

  function handleSet() {
    setError(null);
    startTransition(async () => {
      try {
        await sanctionSetAction(
          profileId,
          scope,
          reasonCode,
          note,
          expiresAt ? new Date(expiresAt).toISOString() : null,
        );
        setNote("");
        setExpiresAt("");
        router.refresh();
      } catch (err) {
        setError(err instanceof AdminApiError ? describeAdminApiError(err) : "Could not set sanction.");
      }
    });
  }

  function openRevokeDialog(sanctionId: string) {
    setRevokeTargetId(sanctionId);
    setRevokeReasonPreset(REASON_PRESETS[0]);
    setRevokeCustomReason("");
    revokeDialogRef.current?.showModal();
  }

  function confirmRevoke() {
    if (!revokeTargetId || !canRevoke) return;
    const sanctionId = revokeTargetId;
    const reason = revokeReasonCode;
    revokeDialogRef.current?.close();
    setRevokeTargetId(null);
    setError(null);
    startTransition(async () => {
      try {
        await sanctionRevokeAction(sanctionId, reason);
        router.refresh();
      } catch (err) {
        setError(err instanceof AdminApiError ? describeAdminApiError(err) : "Could not revoke sanction.");
      }
    });
  }

  return (
    <div className="deck-panel flex flex-col gap-4">
      <h2 className="font-heading text-sm font-semibold text-deck-text">Sanctions</h2>

      {sanctions.length === 0 ? (
        <p className="text-sm text-deck-muted">No sanction history for this profile.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {sanctions.map((s) => (
            <li key={s.id} className="rounded-md border border-deck-border p-3 text-sm">
              <div className="flex flex-wrap items-center gap-3">
                <span className="font-medium text-deck-text">{s.scope}</span>
                <span className="font-data text-xs text-deck-muted">{s.reason_code}</span>
                {s.revoked_at ? (
                  <span className="text-xs text-deck-muted">revoked {formatDateTime(s.revoked_at)}</span>
                ) : s.expires_at ? (
                  <span className="text-xs text-deck-gold">expires {formatDateTime(s.expires_at)}</span>
                ) : (
                  <span className="text-xs text-deck-danger">permanent</span>
                )}
                {canManage && !s.revoked_at ? (
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => openRevokeDialog(s.id)}
                    className="ml-auto text-xs text-deck-danger hover:underline disabled:opacity-50"
                  >
                    Revoke
                  </button>
                ) : null}
              </div>
              {s.note ? <p className="mt-1 text-xs text-deck-muted">{s.note}</p> : null}
            </li>
          ))}
        </ul>
      )}

      {canManage ? (
        <div className="flex flex-col gap-3 border-t border-deck-border pt-4">
          <h3 className="text-xs font-medium uppercase tracking-wide text-deck-muted">Set a new sanction</h3>
          <label className="flex flex-col gap-1 text-xs text-deck-muted">
            Scope
            <select value={scope} onChange={(e) => setScope(e.target.value as typeof scope)} className="deck-select">
              <option value="atlas_publish">atlas_publish</option>
              <option value="atlas_report">atlas_report</option>
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-deck-muted">
            Reason
            <ReasonField
              value={reasonPreset}
              onChange={setReasonPreset}
              custom={customReason}
              onCustomChange={setCustomReason}
            />
          </label>
          <label className="flex flex-col gap-1 text-xs text-deck-muted">
            Note (optional)
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={500}
              rows={2}
              className="deck-input resize-none"
            />
          </label>
          <label className="flex flex-col gap-1 text-xs text-deck-muted">
            Expires (optional — leave blank for permanent)
            <input
              type="date"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
              className="deck-input"
            />
          </label>
          <button type="button" onClick={handleSet} disabled={!canSet} className="deck-button-danger">
            Apply sanction
          </button>
        </div>
      ) : null}

      {error ? <p className="text-sm text-deck-danger">{error}</p> : null}

      <dialog
        ref={revokeDialogRef}
        className="rounded-lg border border-deck-border bg-deck-surface p-6 text-deck-text backdrop:bg-black/70"
      >
        <div className="flex w-72 flex-col gap-3">
          <p className="text-sm">Why is this sanction being revoked?</p>
          <ReasonField
            value={revokeReasonPreset}
            onChange={setRevokeReasonPreset}
            custom={revokeCustomReason}
            onCustomChange={setRevokeCustomReason}
          />
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => {
                revokeDialogRef.current?.close();
                setRevokeTargetId(null);
              }}
              className="deck-button-secondary"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={confirmRevoke}
              disabled={!canRevoke}
              className="deck-button-danger disabled:opacity-50"
            >
              Revoke
            </button>
          </div>
        </div>
      </dialog>
    </div>
  );
}
