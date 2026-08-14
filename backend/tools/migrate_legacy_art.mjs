#!/usr/bin/env node
// Legacy shared art → per-anima private sheets + canonical typing v2.
//
//   node backend/tools/migrate_legacy_art.mjs                 # dry-run audit (default)
//   node backend/tools/migrate_legacy_art.mjs --apply         # copy bytes + patch animas
//   node backend/tools/migrate_legacy_art.mjs --make-legacy-private
//   node backend/tools/migrate_legacy_art.mjs --selftest      # in-memory fixtures, no env
//
// Service role boundary: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required for live modes.
// Never calls Vision or image generation.

import { writeFile } from "node:fs/promises";
import {
  LEGACY_SHEETS_BUCKET,
  PRIVATE_SHEETS_BUCKET,
  auditReportText,
  buildAuditReport,
  verifyBytesMatchBasename,
} from "../supabase/functions/_shared/legacy_art_migration.mjs";
import {
  inferCanonicalLegacyTyping,
  stableStringify,
} from "../supabase/functions/_shared/legacy_typing.mjs";

const PAGE_SIZE = 200;
const ANIMA_SELECT = [
  "id", "owner_id", "species_key", "color_bucket", "stage", "status", "element",
  "subject_kind", "secondary_element", "typing_version", "sheet_path", "manifest",
].join(",");

function usage() {
  console.error(`Usage:
  node backend/tools/migrate_legacy_art.mjs [--apply] [--report <path>] [--make-legacy-private] [--selftest]

Defaults to dry-run audit on stdout. --apply mutates Storage + animas idempotently.
--make-legacy-private sets bucket "${LEGACY_SHEETS_BUCKET}" public=false only when audit
proves every ready Anima already has private art.`);
}

function parseArgs(argv) {
  const flags = {
    apply: false,
    makeLegacyPrivate: false,
    selftest: false,
    reportPath: null,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--apply") flags.apply = true;
    else if (arg === "--make-legacy-private") flags.makeLegacyPrivate = true;
    else if (arg === "--selftest") flags.selftest = true;
    else if (arg === "--report") {
      flags.reportPath = argv[i + 1];
      if (!flags.reportPath) throw new Error("--report requires a path");
      i += 1;
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (flags.apply && flags.makeLegacyPrivate) {
    throw new Error("--apply and --make-legacy-private are mutually exclusive");
  }
  return flags;
}

function requireEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} wajib diset untuk mode live`);
  return value;
}

function restHeaders(serviceKey, preferCount = false) {
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
  if (preferCount) headers.Prefer = "count=exact";
  return headers;
}

async function fetchPage(baseUrl, path, serviceKey, { rangeFrom, rangeTo } = {}) {
  const headers = restHeaders(serviceKey, true);
  if (rangeFrom != null && rangeTo != null) {
    headers.Range = `${rangeFrom}-${rangeTo}`;
  }
  const res = await fetch(`${baseUrl}${path}`, { headers });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`GET ${path} → ${res.status}: ${body.slice(0, 400)}`);
  }
  const contentRange = res.headers.get("content-range");
  const total = contentRange?.includes("/")
    ? Number(contentRange.split("/")[1])
    : null;
  return { rows: await res.json(), total };
}

async function fetchAll(baseUrl, path, serviceKey) {
  const all = [];
  let offset = 0;
  let total = null;
  while (true) {
    const { rows, total: reportedTotal } = await fetchPage(
      baseUrl,
      `${path}${path.includes("?") ? "&" : "?"}limit=${PAGE_SIZE}&offset=${offset}`,
      serviceKey,
      { rangeFrom: offset, rangeTo: offset + PAGE_SIZE - 1 },
    );
    if (total == null && reportedTotal != null) total = reportedTotal;
    all.push(...rows);
    if (!rows.length || rows.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
    if (total != null && offset >= total) break;
  }
  return all;
}

async function loadDataset(baseUrl, serviceKey) {
  const [animas, libraryRows, generations] = await Promise.all([
    fetchAll(baseUrl, `/rest/v1/animas?select=${ANIMA_SELECT}&status=eq.ready&order=id.asc`, serviceKey),
    fetchAll(
      baseUrl,
      "/rest/v1/species_library?select=species_key,color_bucket,stage,sheet_path,manifest,prompt_version&order=species_key.asc",
      serviceKey,
    ),
    fetchAll(
      baseUrl,
      "/rest/v1/generations?select=id,anima_id,vision_result,created_at&status=in.(succeeded,cache_hit)&order=created_at.desc",
      serviceKey,
    ),
  ]);
  return { animas, libraryRows, generations };
}

async function downloadLegacySheet(baseUrl, serviceKey, librarySheetPath) {
  const res = await fetch(
    `${baseUrl}/storage/v1/object/authenticated/${LEGACY_SHEETS_BUCKET}/${encodeURIComponent(librarySheetPath).replace(/%2F/g, "/")}`,
    { headers: restHeaders(serviceKey) },
  );
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`DOWNLOAD_FAILED:${librarySheetPath}:${res.status}:${body.slice(0, 200)}`);
  }
  return new Uint8Array(await res.arrayBuffer());
}

async function uploadPrivateSheet(baseUrl, serviceKey, targetPath, bytes) {
  const res = await fetch(
    `${baseUrl}/storage/v1/object/${PRIVATE_SHEETS_BUCKET}/${targetPath}`,
    {
      method: "POST",
      headers: {
        ...restHeaders(serviceKey),
        "Content-Type": "image/png",
        "x-upsert": "true",
      },
      body: bytes,
    },
  );
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`UPLOAD_FAILED:${targetPath}:${res.status}:${body.slice(0, 200)}`);
  }
}

async function patchAnima(baseUrl, serviceKey, animaId, patch) {
  const res = await fetch(
    `${baseUrl}/rest/v1/animas?id=eq.${animaId}`,
    {
      method: "PATCH",
      headers: {
        ...restHeaders(serviceKey),
        Prefer: "return=minimal",
      },
      body: JSON.stringify(patch),
    },
  );
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`PATCH_FAILED:${animaId}:${res.status}:${body.slice(0, 200)}`);
  }
}

async function setLegacyBucketPrivate(baseUrl, serviceKey) {
  const res = await fetch(`${baseUrl}/storage/v1/bucket/${LEGACY_SHEETS_BUCKET}`, {
    method: "PUT",
    headers: restHeaders(serviceKey),
    body: JSON.stringify({ public: false, id: LEGACY_SHEETS_BUCKET, name: LEGACY_SHEETS_BUCKET }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`BUCKET_PRIVATE_FAILED:${res.status}:${body.slice(0, 200)}`);
  }
}

async function applyMigration(baseUrl, serviceKey, report) {
  const failures = [];
  for (const row of report.rows) {
    if (row.status !== "pending") continue;
    if (row.apply?.idempotent_skip) continue;

    const { apply } = row;
    if (!apply?.patch || !apply.upload || !row.source?.library_sheet_path) {
      failures.push({ anima_id: row.anima_id, error: "INCOMPLETE_PLAN" });
      continue;
    }

    try {
      const bytes = await downloadLegacySheet(baseUrl, serviceKey, row.source.library_sheet_path);
      const basename = apply.patch.manifest?.sheet ?? row.source.library_manifest_sheet;
      const verify = verifyBytesMatchBasename(bytes, basename);
      if (!verify.ok) {
        throw new Error(`${verify.reason}:${verify.expectedPrefix}:${verify.actual}`);
      }
      await uploadPrivateSheet(baseUrl, serviceKey, apply.patch.sheet_path, bytes);
      await patchAnima(baseUrl, serviceKey, row.anima_id, apply.patch);
    } catch (error) {
      failures.push({
        anima_id: row.anima_id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  if (failures.length) {
    const err = new Error(`APPLY_ABORTED:${failures.length} failures`);
    err.failures = failures;
    throw err;
  }
}

function selftestFixtures() {
  const owner = "11111111-1111-4111-8111-111111111111";
  const animaCeramic = "22222222-2222-4222-8222-222222222222";
  const animaMouse = "33333333-3333-4333-8333-333333333333";
  const animaBook = "44444444-4444-4444-8444-444444444444";
  const animaDone = "55555555-5555-4555-8555-555555555555";

  const libraryRows = [
    {
      species_key: "mug_ceramic_handled",
      color_bucket: "neutral_light",
      stage: 1,
      sheet_path: "abc123def4567890.png",
      manifest: { sheet: "abc123def4567890.png", poses: {} },
      prompt_version: "v12",
    },
    {
      species_key: "mouse_plastic",
      color_bucket: "gray",
      stage: 1,
      sheet_path: "mousehash0000001.png",
      manifest: { sheet: "mousehash0000001.png", poses: {} },
      prompt_version: "v12",
    },
    {
      species_key: "book_paper",
      color_bucket: "brown",
      stage: 1,
      sheet_path: "bookhash00000001.png",
      manifest: { sheet: "bookhash00000001.png", poses: {} },
      prompt_version: "v7",
    },
  ];

  const animas = [
    {
      id: animaCeramic,
      owner_id: owner,
      species_key: "mug_ceramic_handled",
      color_bucket: "neutral_light",
      stage: 1,
      status: "ready",
      element: "flow",
      subject_kind: "object",
      typing_version: 1,
      sheet_path: null,
      manifest: null,
    },
    {
      id: animaMouse,
      owner_id: owner,
      species_key: "mouse_plastic",
      color_bucket: "gray",
      stage: 1,
      status: "ready",
      element: "tech",
      subject_kind: "object",
      typing_version: 1,
      sheet_path: null,
      manifest: null,
    },
    {
      id: animaBook,
      owner_id: owner,
      species_key: "book_paper",
      color_bucket: "brown",
      stage: 1,
      status: "ready",
      element: "cloth",
      subject_kind: "object",
      typing_version: 1,
      sheet_path: null,
      manifest: null,
    },
    {
      id: animaDone,
      owner_id: owner,
      species_key: "mug_ceramic_handled",
      color_bucket: "neutral_light",
      stage: 1,
      status: "ready",
      element: "ceramic",
      secondary_element: "flow",
      subject_kind: "object",
      typing_version: 2,
      sheet_path: `${owner}/${animaDone}/abc123def4567890.png`,
      manifest: { sheet: "abc123def4567890.png", poses: {} },
    },
  ];

  const generations = [
    {
      id: "gen-ceramic",
      anima_id: animaCeramic,
      created_at: "2026-08-01T00:00:00Z",
      vision_result: {
        object_label: "ceramic mug",
        species_key: "mug_ceramic_handled",
        surface_finish: "smooth glazed ceramic",
        signature_features: ["handle tail", "open rim crown"],
      },
    },
    {
      id: "gen-mouse",
      anima_id: animaMouse,
      created_at: "2026-08-01T00:00:00Z",
      vision_result: {
        object_label: "wired computer mouse",
        species_key: "mouse_plastic",
        surface_finish: "smooth molded plastic",
        signature_features: ["usb cable tail", "click buttons"],
      },
    },
    {
      id: "gen-book",
      anima_id: animaBook,
      created_at: "2026-08-01T00:00:00Z",
      vision_result: {
        object_label: "hardcover notebook",
        species_key: "book_paper",
        surface_finish: "cardboard cover",
        signature_features: ["spine hinge", "page edges"],
      },
    },
  ];

  return { animas, libraryRows, generations, owner, animaCeramic, animaMouse, animaBook, animaDone };
}

function runSelftest() {
  const assert = (cond, msg) => {
    if (!cond) throw new Error(`selftest failed: ${msg}`);
  };

  const ceramic = inferCanonicalLegacyTyping({
    existingElement: "flow",
    vision: { object_label: "ceramic mug", surface_finish: "glazed ceramic" },
  });
  assert(ceramic.element === "ceramic", "mug → ceramic");
  assert(ceramic.secondary_element === "flow", "legacy flow → secondary on ceramic");

  const mouse = inferCanonicalLegacyTyping({
    existingElement: "tech",
    vision: { object_label: "wired computer mouse", species_key: "mouse_plastic" },
  });
  assert(mouse.element === "plastic", "computer mouse → plastic");
  assert(mouse.secondary_element === "spark", "legacy tech → spark secondary");

  const book = inferCanonicalLegacyTyping({
    existingElement: "cloth",
    vision: { object_label: "hardcover notebook", surface_finish: "cardboard" },
  });
  assert(book.element === "paper", "notebook → paper, not cloth");

  const ambiguous = inferCanonicalLegacyTyping({
    existingElement: "stone",
    vision: { object_label: "mysterious artifact", species_key: "artifact_unknown" },
  });
  assert(ambiguous.element === "stone", "ambiguous keeps normalized legacy");
  assert(ambiguous.reason === "legacy:ambiguous", "ambiguous reason tag");

  const animal = inferCanonicalLegacyTyping({
    existingElement: "plant",
    subjectKind: "animal",
    vision: { object_label: "tabby cat", subject_kind: "animal" },
  });
  assert(animal.element === "fauna", "animal → fauna");

  const fixtures = selftestFixtures();
  const report = buildAuditReport({
    animas: fixtures.animas,
    libraryRows: fixtures.libraryRows,
    generations: fixtures.generations,
    mode: "dry_run",
  });

  assert(report.summary.total_ready === 4, "four ready animas");
  assert(report.summary.pending === 3, "three pending migrations");
  assert(report.summary.already_migrated === 1, "one already migrated");
  assert(report.summary.ready_for_legacy_private === false, "cutover blocked with pending");

  const ceramicRow = report.rows.find((row) => row.anima_id === fixtures.animaCeramic);
  assert(
    ceramicRow.source.target_sheet_path === `${fixtures.owner}/${fixtures.animaCeramic}/abc123def4567890.png`,
    "private path uses owner/anima/basename",
  );
  assert(ceramicRow.apply.patch.manifest.sheet === "abc123def4567890.png", "manifest basename preserved");

  const doneOnly = buildAuditReport({
    animas: [fixtures.animas.find((row) => row.id === fixtures.animaDone)],
    libraryRows: fixtures.libraryRows,
    generations: fixtures.generations,
    mode: "audit",
  });
  assert(doneOnly.summary.ready_for_legacy_private === true, "all-private audit allows cutover");

  const textA = auditReportText(report);
  const textB = auditReportText(buildAuditReport({
    animas: fixtures.animas,
    libraryRows: fixtures.libraryRows,
    generations: fixtures.generations,
    mode: "dry_run",
  }));
  assert(textA === textB, "audit report must be deterministic");

  console.log("migrate_legacy_art selftest: OK");
}

async function main() {
  const flags = parseArgs(process.argv);
  if (flags.selftest) {
    runSelftest();
    return;
  }

  const baseUrl = requireEnv("SUPABASE_URL").replace(/\/$/, "");
  const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

  const dataset = await loadDataset(baseUrl, serviceKey);
  const mode = flags.apply ? "apply" : flags.makeLegacyPrivate ? "audit" : "dry_run";
  const report = buildAuditReport({ ...dataset, mode });
  const text = auditReportText(report);

  if (flags.reportPath) {
    await writeFile(flags.reportPath, text, "utf8");
  }
  process.stdout.write(text);

  if (flags.makeLegacyPrivate) {
    if (!report.summary.ready_for_legacy_private) {
      throw new Error(
        "REFUSE_LEGACY_PRIVATE: audit shows ready animas without private art or pending/errors remain",
      );
    }
    await setLegacyBucketPrivate(baseUrl, serviceKey);
    console.error(`bucket ${LEGACY_SHEETS_BUCKET} set public=false`);
    return;
  }

  if (flags.apply) {
    if (report.summary.errors > 0) {
      throw new Error("REFUSE_APPLY: audit contains errors — fix data before --apply");
    }
    await applyMigration(baseUrl, serviceKey, report);
    console.error(`applied ${report.summary.pending} pending migration(s)`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  if (error.failures) {
    console.error(stableStringify({ failures: error.failures }));
  }
  process.exit(1);
});
