"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { decideCase } from "@/lib/actions/moderation";
import { describeAdminApiError, AdminApiError } from "@/lib/admin-api";
import type { DecideAction } from "@/lib/types";

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

export function ActionPanel({ caseId }: { caseId: string }) {
  const router = useRouter();
  const [reasonPreset, setReasonPreset] = useState<string>(REASON_PRESETS[0]);
  const [customReason, setCustomReason] = useState("");
  const [note, setNote] = useState("");
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [confirmKey, setConfirmKey] = useState<DecideAction | null>(null);
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

  function handleClick(action: DecideAction, destructive: boolean) {
    if (!canSubmit) return;
    if (destructive) {
      setConfirmKey(action);
      dialogRef.current?.showModal();
    } else {
      run(action);
    }
  }

  function confirmDestructive() {
    dialogRef.current?.close();
    if (confirmKey) run(confirmKey);
  }

  return (
    <div className="sticky top-6 flex flex-col gap-4 rounded-lg border border-deck-border bg-deck-surface p-5">
      <h2 className="font-heading text-sm font-semibold text-deck-text">Decide this case</h2>

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

      <div className="grid grid-cols-2 gap-2">
        {ACTIONS.map(({ key, label, destructive, style }) => (
          <button
            key={key}
            type="button"
            onClick={() => handleClick(key, destructive)}
            disabled={!canSubmit}
            className={style}
          >
            {label}
          </button>
        ))}
      </div>

      {error ? <p className="text-sm text-deck-danger">{error}</p> : null}
      {success ? <p className="text-sm text-deck-gold">{success}</p> : null}

      <dialog
        ref={dialogRef}
        className="rounded-lg border border-deck-border bg-deck-surface p-6 text-deck-text backdrop:bg-black/70"
      >
        <div className="flex max-w-xs flex-col gap-4">
          <p className="text-sm">
            Confirm <strong>{confirmKey}</strong> on this case? This action is destructive and will be recorded
            in the audit log.
          </p>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => dialogRef.current?.close()} className="deck-button-secondary">
              Cancel
            </button>
            <button type="button" onClick={confirmDestructive} className="deck-button-danger">
              Confirm {confirmKey}
            </button>
          </div>
        </div>
      </dialog>
    </div>
  );
}
