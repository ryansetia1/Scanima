"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { decideCase, restoreEntryAction } from "@/lib/actions/moderation";
import { describeAdminApiError, AdminApiError } from "@/lib/admin-api";
import type { CaseStatus, DecideAction } from "@/lib/types";
import { formatDateTime, statusLabel } from "@/lib/ui";

const REASON_PRESETS = [
  "unsafe_content",
  "ip_character_match",
  "false_positive_correction",
  "report_upheld",
  "owner_appeal_valid",
  "other",
] as const;

const ACTIONS: { key: DecideAction; label: string; destructive: boolean; style: string }[] = [
  { key: "approve", label: "Approve", destructive: false, style: "deck-button-primary" },
  { key: "reject", label: "Reject", destructive: true, style: "deck-button-danger" },
  { key: "hide", label: "Hide", destructive: true, style: "deck-button-danger" },
  { key: "restore", label: "Restore", destructive: false, style: "deck-button-secondary" },
  { key: "escalate", label: "Escalate", destructive: false, style: "deck-button-secondary" },
  { key: "assign", label: "Assign to me", destructive: false, style: "deck-button-secondary" },
];

/** Confirm target: either a `decide` action on the current (open) case, or
 * the separate entry-scoped restore for a case that's already resolved. */
type ConfirmTarget = DecideAction | "restore_entry";

export function ActionPanel({
  caseId,
  entryId,
  status,
  resolvedAt,
}: {
  caseId: string;
  entryId: string;
  status: CaseStatus;
  resolvedAt: string | null;
}) {
  const router = useRouter();
  const [reasonPreset, setReasonPreset] = useState<string>(REASON_PRESETS[0]);
  const [customReason, setCustomReason] = useState("");
  const [note, setNote] = useState("");
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [confirmTarget, setConfirmTarget] = useState<ConfirmTarget | null>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);

  const reasonCode = (reasonPreset === "other" ? customReason : reasonPreset).trim();
  const reasonValid = reasonCode.length > 0 && reasonCode.length <= 64;
  const noteValid = note.length <= 500;
  const canSubmit = reasonValid && noteValid && !pending;

  function run(action: DecideAction) {
    setError(null);
    setSuccess(null);
    startTransition(async () => {
      try {
        const result = await decideCase(caseId, action, reasonCode, note);
        setSuccess(
          result.idempotent_replay
            ? "Already recorded — no duplicate action taken."
            : `Done: case is now ${result.case_status ?? action}.`,
        );
        router.refresh();
      } catch (err) {
        setError(err instanceof AdminApiError ? describeAdminApiError(err) : "Action failed. Please try again.");
      }
    });
  }

  function runRestoreEntry() {
    setError(null);
    setSuccess(null);
    startTransition(async () => {
      try {
        const result = await restoreEntryAction(entryId, reasonCode, note);
        setSuccess(
          result.idempotent_replay
            ? "Already recorded — no duplicate action taken."
            : "Done: entry restored and published again.",
        );
        router.refresh();
      } catch (err) {
        setError(err instanceof AdminApiError ? describeAdminApiError(err) : "Restore failed. Please try again.");
      }
    });
  }

  function requestConfirm(target: ConfirmTarget) {
    if (!canSubmit) return;
    setConfirmTarget(target);
    dialogRef.current?.showModal();
  }

  function handleDecideClick(action: DecideAction, destructive: boolean) {
    if (!canSubmit) return;
    if (destructive) {
      requestConfirm(action);
    } else {
      run(action);
    }
  }

  function confirmDestructive() {
    dialogRef.current?.close();
    if (confirmTarget === "restore_entry") {
      runRestoreEntry();
    } else if (confirmTarget) {
      run(confirmTarget);
    }
  }

  const reasonFields = (
    <>
      <label className="flex flex-col gap-1 text-xs text-deck-muted">
        Reason code
        <select
          value={reasonPreset}
          onChange={(e) => setReasonPreset(e.target.value)}
          className="deck-select"
        >
          {REASON_PRESETS.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </label>

      {reasonPreset === "other" ? (
        <label className="flex flex-col gap-1 text-xs text-deck-muted">
          Custom reason (max 64 chars)
          <input
            value={customReason}
            onChange={(e) => setCustomReason(e.target.value)}
            maxLength={64}
            className="deck-input"
            placeholder="short_snake_case_reason"
          />
        </label>
      ) : null}

      <label className="flex flex-col gap-1 text-xs text-deck-muted">
        Note (optional, max 500 chars)
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={500}
          rows={3}
          className="deck-input resize-none"
        />
      </label>

      {!reasonValid ? (
        <p className="text-xs text-deck-danger">A reason code is required before any action can be taken.</p>
      ) : null}
    </>
  );

  const pendingIndicator = pending ? (
    <span className="flex items-center gap-2 text-xs text-deck-muted">
      <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-deck-border border-t-deck-secondary" />
      Working…
    </span>
  ) : null;

  const dialog = (
    <dialog
      ref={dialogRef}
      className="rounded-lg border border-deck-border bg-deck-surface p-6 text-deck-text backdrop:bg-black/70"
    >
      <div className="flex max-w-xs flex-col gap-4">
        <p className="text-sm">
          Confirm{" "}
          <strong>{confirmTarget === "restore_entry" ? "restore" : confirmTarget}</strong>
          {confirmTarget === "restore_entry" ? " on this entry" : " on this case"}? This action is destructive
          and will be recorded in the audit log.
        </p>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={() => dialogRef.current?.close()} className="deck-button-secondary">
            Cancel
          </button>
          <button type="button" onClick={confirmDestructive} className="deck-button-danger">
            Confirm
          </button>
        </div>
      </div>
    </dialog>
  );

  // Approve/Reject/Hide/Escalate/Restore-the-case all require the case to
  // still be open — the backend rejects them with CASE_ALREADY_RESOLVED
  // otherwise. Showing the full six-button grid regardless of status used
  // to mean every button just failed with a confusing error once a case was
  // decided. Restoring an already-rejected/hidden ENTRY is still possible,
  // but through a different, entry-scoped operation that opens a fresh case.
  if (status !== "open") {
    return (
      <div className="sticky top-6 flex flex-col gap-4 rounded-lg border border-deck-border bg-deck-surface p-5">
        <h2 className="font-heading text-sm font-semibold text-deck-text">Case resolved</h2>
        <p className="text-sm text-deck-muted">
          This case is <span className="font-medium text-deck-text">{statusLabel(status)}</span>
          {resolvedAt ? ` as of ${formatDateTime(resolvedAt)}` : ""}. Approve, Reject, Hide, and Escalate only
          apply to an open case.
        </p>
        {status === "rejected" || status === "hidden" ? (
          <>
            {reasonFields}
            <button
              type="button"
              onClick={() => requestConfirm("restore_entry")}
              disabled={!canSubmit}
              className="deck-button-secondary"
            >
              Restore this entry
            </button>
            <p className="text-xs text-deck-muted">
              Opens a fresh case and immediately re-approves the entry — for when this decision turns out to
              have been wrong.
            </p>
          </>
        ) : null}
        {pendingIndicator}
        {error ? <p className="text-sm text-deck-danger">{error}</p> : null}
        {success ? <p className="text-sm text-deck-gold">{success}</p> : null}
        {dialog}
      </div>
    );
  }

  return (
    <div className="sticky top-6 flex flex-col gap-4 rounded-lg border border-deck-border bg-deck-surface p-5">
      <h2 className="font-heading text-sm font-semibold text-deck-text">Decide this case</h2>

      {reasonFields}

      <div className="grid grid-cols-2 gap-2">
        {ACTIONS.map(({ key, label, destructive, style }) => (
          <button
            key={key}
            type="button"
            onClick={() => handleDecideClick(key, destructive)}
            disabled={!canSubmit}
            className={style}
          >
            {label}
          </button>
        ))}
      </div>

      {pendingIndicator}
      {error ? <p className="text-sm text-deck-danger">{error}</p> : null}
      {success ? <p className="text-sm text-deck-gold">{success}</p> : null}
      {dialog}
    </div>
  );
}
