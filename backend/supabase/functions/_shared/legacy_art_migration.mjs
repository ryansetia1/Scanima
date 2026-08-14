// Pure planner/audit for legacy shared art → per-anima private sheets.
// No network, no Storage — consumed by backend/tools/migrate_legacy_art.mjs.

import { createHash } from "node:crypto";
import { inferCanonicalLegacyTyping, stableSortKeys, stableStringify } from "./legacy_typing.mjs";

export const LEGACY_SHEETS_BUCKET = "sheets";
export const PRIVATE_SHEETS_BUCKET = "anima_sheets";
export const AUDIT_REPORT_VERSION = 1;

/**
 * @typedef {object} AnimaRow
 * @property {string} id
 * @property {string} owner_id
 * @property {string} species_key
 * @property {string} color_bucket
 * @property {number} stage
 * @property {string} status
 * @property {string} element
 * @property {string|null} [subject_kind]
 * @property {string|null} [secondary_element]
 * @property {number|null} [typing_version]
 * @property {string|null} [sheet_path]
 * @property {Record<string, unknown>|null} [manifest]
 */

/**
 * @typedef {object} LibraryRow
 * @property {string} species_key
 * @property {string} color_bucket
 * @property {number} stage
 * @property {string} sheet_path
 * @property {Record<string, unknown>} manifest
 * @property {string} [prompt_version]
 */

/**
 * @typedef {object} GenerationRow
 * @property {string} id
 * @property {string|null} anima_id
 * @property {Record<string, unknown>|null} vision_result
 * @property {string} created_at
 */

export function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function sheetBasename(libraryRow) {
  const manifestSheet = libraryRow?.manifest?.sheet;
  if (typeof manifestSheet === "string" && manifestSheet.trim()) {
    return manifestSheet.trim();
  }
  const path = String(libraryRow?.sheet_path ?? "").trim();
  if (!path) return "";
  const parts = path.split("/");
  return parts[parts.length - 1];
}

export function privateSheetPath(ownerId, animaId, basename) {
  const base = String(basename ?? "").trim();
  if (!base) throw new Error("MISSING_SHEET_BASENAME");
  if (base.includes("/")) throw new Error("INVALID_SHEET_BASENAME");
  return `${ownerId}/${animaId}/${base}`;
}

export function libraryLookupKey(anima) {
  return `${anima.species_key}\0${anima.color_bucket}\0${anima.stage}`;
}

/** @param {Map<string, LibraryRow>} libraryByKey */
export function findLibraryRow(anima, libraryByKey) {
  return libraryByKey.get(libraryLookupKey(anima)) ?? null;
}

/** @param {Map<string, GenerationRow>} latestGenerationByAnima */
export function findLatestGeneration(animaId, latestGenerationByAnima) {
  return latestGenerationByAnima.get(animaId) ?? null;
}

export function isAlreadyMigrated(anima) {
  return (anima.typing_version ?? 1) >= 2
    && typeof anima.sheet_path === "string"
    && anima.sheet_path.includes("/");
}

export function manifestForPrivateCopy(libraryRow, basename) {
  const manifest = structuredClone(libraryRow.manifest ?? {});
  manifest.sheet = basename;
  return manifest;
}

export function patchWouldChange(anima, target) {
  const current = {
    subject_kind: anima.subject_kind ?? "object",
    element: anima.element,
    secondary_element: anima.secondary_element ?? null,
    typing_version: anima.typing_version ?? 1,
    sheet_path: anima.sheet_path ?? null,
  };
  return (
    current.subject_kind !== target.subject_kind
    || current.element !== target.element
    || current.secondary_element !== target.secondary_element
    || current.typing_version !== target.typing_version
    || current.sheet_path !== target.sheet_path
  );
}

/**
 * @param {object} params
 * @param {AnimaRow} params.anima
 * @param {LibraryRow|null} params.library
 * @param {GenerationRow|null} params.generation
 */
export function buildMigrationEntry({ anima, library, generation }) {
  const errors = [];

  if (anima.status !== "ready") {
    return {
      anima_id: anima.id,
      owner_id: anima.owner_id,
      status: "skipped",
      errors: ["ANIMA_NOT_READY"],
    };
  }

  if (isAlreadyMigrated(anima)) {
    return {
      anima_id: anima.id,
      owner_id: anima.owner_id,
      status: "already_migrated",
      sheet_path: anima.sheet_path,
      typing_version: anima.typing_version ?? 2,
      errors: [],
    };
  }

  if (!library) {
    errors.push("MISSING_LIBRARY_ROW");
  }

  const basename = library ? sheetBasename(library) : "";
  if (library && !basename) errors.push("MISSING_LIBRARY_BASENAME");

  const vision = generation?.vision_result ?? {};
  const canonical = inferCanonicalLegacyTyping({
    vision,
    existingElement: anima.element,
    subjectKind: anima.subject_kind ?? null,
  });

  let target_sheet_path = null;
  if (basename && !errors.length) {
    try {
      target_sheet_path = privateSheetPath(anima.owner_id, anima.id, basename);
    } catch (error) {
      errors.push(error instanceof Error ? error.message : "INVALID_TARGET_PATH");
    }
  }

  const entry = {
    anima_id: anima.id,
    owner_id: anima.owner_id,
    species_key: anima.species_key,
    color_bucket: anima.color_bucket,
    stage: anima.stage,
    status: errors.length ? "error" : "pending",
    legacy: {
      element: anima.element,
      subject_kind: anima.subject_kind ?? "object",
      typing_version: anima.typing_version ?? 1,
      sheet_path: anima.sheet_path ?? null,
    },
    canonical,
    source: {
      library_sheet_path: library?.sheet_path ?? null,
      library_manifest_sheet: library?.manifest?.sheet ?? null,
      library_bucket: LEGACY_SHEETS_BUCKET,
      target_bucket: PRIVATE_SHEETS_BUCKET,
      target_sheet_path,
      generation_id: generation?.id ?? null,
    },
    errors,
  };

  if (entry.status === "pending") {
    entry.apply = {
      download: `${LEGACY_SHEETS_BUCKET}/${library.sheet_path}`,
      upload: `${PRIVATE_SHEETS_BUCKET}/${target_sheet_path}`,
      patch: {
        subject_kind: canonical.subject_kind,
        element: canonical.element,
        secondary_element: canonical.secondary_element,
        typing_version: canonical.typing_version,
        sheet_path: target_sheet_path,
        manifest: manifestForPrivateCopy(library, basename),
      },
      idempotent_skip: !patchWouldChange(anima, {
        ...canonical,
        sheet_path: target_sheet_path,
      }) && anima.sheet_path === target_sheet_path,
    };
  }

  return entry;
}

/** @param {GenerationRow[]} generations */
export function indexLatestGenerations(generations) {
  const byAnima = new Map();
  for (const row of generations) {
    if (!row.anima_id) continue;
    const prev = byAnima.get(row.anima_id);
    if (!prev || String(row.created_at) > String(prev.created_at)) {
      byAnima.set(row.anima_id, row);
    }
  }
  return byAnima;
}

/** @param {LibraryRow[]} libraryRows */
export function indexLibrary(libraryRows) {
  const map = new Map();
  for (const row of libraryRows) {
    map.set(`${row.species_key}\0${row.color_bucket}\0${row.stage}`, row);
  }
  return map;
}

/**
 * @param {object} params
 * @param {AnimaRow[]} params.animas
 * @param {LibraryRow[]} params.libraryRows
 * @param {GenerationRow[]} params.generations
 * @param {"dry_run"|"apply"|"audit"} [params.mode]
 */
export function buildAuditReport({ animas, libraryRows, generations, mode = "dry_run" }) {
  const libraryByKey = indexLibrary(libraryRows);
  const latestGenerationByAnima = indexLatestGenerations(generations);

  const readyAnimas = animas
    .filter((row) => row.status === "ready")
    .sort((a, b) => a.id.localeCompare(b.id));

  const rows = readyAnimas.map((anima) => buildMigrationEntry({
    anima,
    library: findLibraryRow(anima, libraryByKey),
    generation: findLatestGeneration(anima.id, latestGenerationByAnima),
  }));

  const summary = {
    total_ready: readyAnimas.length,
    already_migrated: rows.filter((row) => row.status === "already_migrated").length,
    pending: rows.filter((row) => row.status === "pending").length,
    errors: rows.filter((row) => row.status === "error").length,
    skipped: rows.filter((row) => row.status === "skipped").length,
    ready_for_legacy_private: false,
  };

  // Bucket cutover only when every ready row already owns private art — no pending/errors.
  summary.ready_for_legacy_private = readyAnimas.length > 0
    && rows.every((row) => row.status === "already_migrated")
    && summary.pending === 0
    && summary.errors === 0;

  return stableSortKeys({
    version: AUDIT_REPORT_VERSION,
    mode,
    buckets: {
      legacy_public: LEGACY_SHEETS_BUCKET,
      private: PRIVATE_SHEETS_BUCKET,
    },
    summary,
    rows,
  });
}

export function auditReportText(report) {
  return stableStringify(report);
}

export function verifyBytesMatchBasename(bytes, basename) {
  const expectedPrefix = String(basename).replace(/\.png$/i, "");
  if (!/^[a-f0-9]{16}$/.test(expectedPrefix)) {
    return { ok: true, skipped: true };
  }
  const hash = sha256Hex(bytes);
  if (!hash.startsWith(expectedPrefix)) {
    return { ok: false, reason: "HASH_PREFIX_MISMATCH", expectedPrefix, actual: hash.slice(0, 16) };
  }
  return { ok: true, hash };
}
