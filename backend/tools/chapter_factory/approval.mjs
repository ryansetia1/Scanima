import { access, readFile, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";
import { REVIEW_CONFIRM_PHRASE } from "./constants.mjs";
import { loadChapterContext } from "./context.mjs";
import { assetHashLedger, manifestHash } from "./manifest.mjs";
import { validateChapterDraft } from "./validate.mjs";

export const APPROVAL_FILENAME = "approval.ledger.json";

export async function readApprovalLedger(chapterDir) {
  const raw = await readFile(join(chapterDir, APPROVAL_FILENAME), "utf8");
  return JSON.parse(raw);
}

export async function writeApprovalLedger(chapterDir, ledger) {
  await writeFile(join(chapterDir, APPROVAL_FILENAME), stableStringify(ledger));
}

export async function removeApprovalLedger(chapterDir) {
  try {
    await unlink(join(chapterDir, APPROVAL_FILENAME));
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

export function parseReviewConfirmation(value) {
  if (typeof value !== "string" || value.trim() !== REVIEW_CONFIRM_PHRASE) {
    throw new Error(
      `REVIEW_CONFIRM_REQUIRED: ketik persis "${REVIEW_CONFIRM_PHRASE}" setelah review visual manual`,
    );
  }
}

export function parseOperator(value) {
  const operator = typeof value === "string" ? value.trim() : "";
  if (!operator || operator.length < 2 || operator.length > 64) {
    throw new Error("OPERATOR_REQUIRED: --operator wajib (2–64 karakter, identitas reviewer manusia)");
  }
  if (operator === "chapter-factory" || operator === "selftest") {
    throw new Error("OPERATOR_INVALID: jangan pakai identitas otomatis; gunakan nama operator manusia");
  }
  return operator;
}

export async function approveChapter({
  chapterDir,
  manifest,
  operator,
  confirmReviewed,
  allowSelftestOperator = false,
}) {
  parseReviewConfirmation(confirmReviewed);
  const approvedBy = allowSelftestOperator
    ? String(operator ?? "selftest-temp")
    : parseOperator(operator);
  const ctx = await loadChapterContext(chapterDir);
  validateChapterDraft(manifest, ctx);
  const computedHash = manifestHash(manifest);
  if (computedHash !== manifest.manifest_hash) {
    throw new Error("MANIFEST_HASH_MISMATCH: manifest_hash tidak cocok isi saat ini");
  }
  const ledger = {
    chapter_slug: manifest.factory?.slug ?? ctx.slug,
    content_version: manifest.content_version,
    sequence: manifest.sequence ?? manifest.factory?.sequence,
    manifest_hash: computedHash,
    asset_hashes: assetHashLedger(manifest),
    approved_at: new Date().toISOString(),
    approved_by: approvedBy,
    review_confirmed: true,
    notes: "Manual visual review confirmed by operator",
  };
  await writeApprovalLedger(chapterDir, ledger);
  return ledger;
}

export async function requireValidApproval({ chapterDir, manifest }) {
  let ledger;
  try {
    ledger = await readApprovalLedger(chapterDir);
  } catch {
    throw new Error("APPROVAL_MISSING: review visual + approve manual wajib sebelum publish");
  }
  if (ledger.review_confirmed !== true) {
    throw new Error("APPROVAL_INVALID: ledger tidak memuat konfirmasi review manual");
  }
  if (
    ledger.chapter_slug !== manifest.factory?.slug
    || Number(ledger.content_version) !== Number(manifest.content_version)
    || Number(ledger.sequence) !== Number(manifest.sequence)
    || typeof ledger.approved_by !== "string"
    || ledger.approved_by.length < 2
  ) {
    throw new Error("APPROVAL_INVALID: identitas chapter/operator tidak cocok");
  }
  const computedHash = manifestHash(manifest);
  if (ledger.manifest_hash !== computedHash) {
    throw new Error("APPROVAL_STALE: ledger tidak cocok manifest saat ini");
  }
  const currentAssets = assetHashLedger(manifest);
  for (const [path, hash] of Object.entries(currentAssets)) {
    if (ledger.asset_hashes[path] !== hash) {
      throw new Error(`APPROVAL_STALE: hash asset berubah untuk ${path}`);
    }
  }
  return ledger;
}

export async function syncApprovalLedger(chapterDir, manifest) {
  try {
    await access(join(chapterDir, APPROVAL_FILENAME));
  } catch {
    return { removed: false, reason: "missing" };
  }
  try {
    await requireValidApproval({ chapterDir, manifest });
    return { removed: false, reason: "still_valid" };
  } catch {
    await removeApprovalLedger(chapterDir);
    return { removed: true, reason: "stale" };
  }
}
