// POST /admin_moderation { operation, ... }
// Staff-only surface for the Atlas Moderation Admin console (admin/). Every
// operation re-verifies the caller's role from staff_accounts — never from
// user_metadata or an email claim — and every privileged RPC it calls
// re-checks the role again server-side (moderation_require_role) as
// defense-in-depth. See docs/designs/2026-08-23-atlas-moderation-admin.md.
import { adminClient, corsPreflight, json } from "../_shared/supa.ts";
import { requireStaff, StaffAuthError } from "../_shared/admin_auth.ts";
import { THUMB_SIGNED_TTL } from "../_shared/gallery_constants.mjs";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const OPERATIONS = new Set([
  "whoami",
  "queue_list",
  "case_detail",
  "reports_list",
  "decide",
  "restore_entry",
  "sanction_set",
  "sanction_revoke",
  "sanctions_list",
  "seeker_profile",
  "staff_list",
  "staff_set_role",
  "audit_list",
  "analytics",
]);

const CASE_STATUSES = new Set(["open", "approved", "rejected", "hidden", "all"]);
const CASE_SOURCES = new Set(["publish", "report", "appeal", "manual"]);
const DECISION_ACTIONS = new Set([
  "approve",
  "reject",
  "hide",
  "restore",
  "escalate",
  "assign",
]);
const SANCTION_SCOPES = new Set(["atlas_publish", "atlas_report"]);

const ERROR_STATUS: Record<string, number> = {
  UNAUTHENTICATED: 401,
  STAFF_FORBIDDEN: 403,
  INVALID_CASE_ID: 400,
  INVALID_ENTRY_ID: 400,
  INVALID_ASSIGNED_STAFF_ID: 400,
  INVALID_PROFILE_ID: 400,
  INVALID_SANCTION_ID: 400,
  INVALID_TARGET_USER_ID: 400,
  INVALID_ACTION: 400,
  INVALID_SCOPE: 400,
  INVALID_ROLE: 400,
  INVALID_IDEMPOTENCY_KEY: 400,
  INVALID_REASON_CODE: 400,
  INVALID_STATUS: 400,
  INVALID_SOURCE: 400,
  INVALID_PAGE: 400,
  CASE_NOT_FOUND: 404,
  ENTRY_NOT_FOUND: 404,
  SANCTION_NOT_FOUND: 404,
  STAFF_NOT_FOUND: 404,
  CASE_ALREADY_RESOLVED: 409,
  SANCTION_ALREADY_REVOKED: 409,
  CANNOT_REVOKE_SELF: 409,
  THUMB_REQUIRED: 409,
};

// deno-lint-ignore no-explicit-any
type Body = Record<string, any>;

const db = adminClient();

Deno.serve(async (req) => {
  const preflight = corsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json(405, { error: "hanya POST" });

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const operation = typeof body.operation === "string" ? body.operation : "";
  if (!OPERATIONS.has(operation)) {
    return json(400, { error: "operation tidak dikenal" });
  }

  try {
    if (operation === "whoami") {
      const staff = await requireStaff(db, req, "viewer");
      return json(200, { user_id: staff.userId, role: staff.role });
    }
    if (operation === "queue_list") {
      await requireStaff(db, req, "viewer");
      return await queueList(body);
    }
    if (operation === "case_detail") {
      await requireStaff(db, req, "viewer");
      return await caseDetail(body);
    }
    if (operation === "reports_list") {
      await requireStaff(db, req, "viewer");
      return await reportsList(body);
    }
    if (operation === "decide") {
      const staff = await requireStaff(db, req, "moderator");
      return await decide(staff.userId, body);
    }
    if (operation === "restore_entry") {
      const staff = await requireStaff(db, req, "moderator");
      return await restoreEntry(staff.userId, body);
    }
    if (operation === "sanction_set") {
      const staff = await requireStaff(db, req, "moderator");
      return await sanctionSet(staff.userId, body);
    }
    if (operation === "sanction_revoke") {
      const staff = await requireStaff(db, req, "moderator");
      return await sanctionRevoke(staff.userId, body);
    }
    if (operation === "sanctions_list") {
      await requireStaff(db, req, "viewer");
      return await sanctionsList(body);
    }
    if (operation === "seeker_profile") {
      await requireStaff(db, req, "viewer");
      return await seekerProfile(body);
    }
    if (operation === "staff_list") {
      await requireStaff(db, req, "admin");
      return await staffList();
    }
    if (operation === "staff_set_role") {
      const staff = await requireStaff(db, req, "admin");
      return await staffSetRole(staff.userId, body);
    }
    if (operation === "audit_list") {
      await requireStaff(db, req, "viewer");
      return await auditList(body);
    }
    if (operation === "analytics") {
      await requireStaff(db, req, "viewer");
      return await analytics(body);
    }
    return json(400, { error: "operation tidak dikenal" });
  } catch (error) {
    if (error instanceof StaffAuthError) {
      return json(error.status, { error: error.message });
    }
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String((error as { message: unknown }).message)
      : String(error);
    const marker = Object.keys(ERROR_STATUS).find((candidate) =>
      message.includes(candidate)
    );
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("admin_moderation gagal", error);
    return json(500, { error: "admin_moderation gagal diproses" });
  }
});

async function queueList(body: Body): Promise<Response> {
  const status = parseCaseStatus(body.status, "open");
  const source = body.source === undefined || body.source === null || body.source === ""
    ? null
    : parseCaseSource(body.source);
  const assignedStaffId = body.assigned_staff_id
    ? asUuid(body.assigned_staff_id, "assigned_staff_id")
    : null;
  const { page, perPage } = parsePage(body);

  let query = db
    .from("moderation_cases")
    .select(
      "id, entry_id, art_hash, source, status, category, confidence, assigned_staff_id, opened_reason_code, created_at, updated_at, resolved_at, gallery_entries!moderation_cases_entry_id_fkey(id, anima_id, owner_id, display_name, thumb_path, report_count)",
      { count: "exact" },
    )
    .order("created_at", { ascending: true })
    .range((page - 1) * perPage, page * perPage - 1);

  if (status !== "all") query = query.eq("status", status);
  if (source) query = query.eq("source", source);
  if (assignedStaffId) query = query.eq("assigned_staff_id", assignedStaffId);

  const { data, error, count } = await query;
  if (error) throw error;

  const thumbPaths = (data ?? [])
    .map((row) => asRecord(row.gallery_entries).thumb_path)
    .filter((path): path is string => typeof path === "string" && path.length > 0);
  const thumbUrls = await signThumbUrls(thumbPaths);

  // A case with no persisted thumbnail (rejected outright, or an open
  // publish-sourced case) still gets a read-only preview cropped from its
  // full sheet, so the queue stays visually scannable instead of showing a
  // blank tile for exactly the cases staff most need to look at.
  const rows = data ?? [];
  const previews = await previewIdleThumbsFor(rows.map((row) => {
    const entry = asRecord(row.gallery_entries);
    const thumbPath = typeof entry.thumb_path === "string" ? entry.thumb_path : "";
    if (thumbPath) return null;
    return typeof entry.anima_id === "string" ? entry.anima_id : null;
  }));
  const cases = rows.map((row, index) => {
    const entry = asRecord(row.gallery_entries);
    const thumbPath = typeof entry.thumb_path === "string" ? entry.thumb_path : "";
    const thumbUrl = thumbPath
      ? (thumbUrls.get(thumbPath) ?? "")
      : previews[index];
    return {
      case_id: row.id,
      entry_id: row.entry_id,
      art_hash: row.art_hash,
      source: row.source,
      status: row.status,
      category: row.category,
      confidence: row.confidence,
      assigned_staff_id: row.assigned_staff_id,
      opened_reason_code: row.opened_reason_code,
      created_at: row.created_at,
      updated_at: row.updated_at,
      resolved_at: row.resolved_at,
      entry_owner_id: entry.owner_id ?? null,
      entry_display_name: entry.display_name ?? null,
      entry_report_count: entry.report_count ?? 0,
      thumb_url: thumbUrl,
    };
  });

  return json(200, { cases, page, per_page: perPage, total: count ?? cases.length });
}

async function caseDetail(body: Body): Promise<Response> {
  const caseId = asUuid(body.case_id, "case_id");
  const { data: moderationCase, error: caseError } = await db
    .from("moderation_cases")
    .select("*")
    .eq("id", caseId)
    .maybeSingle();
  if (caseError) throw caseError;
  if (!moderationCase) throw new Error("CASE_NOT_FOUND");

  const [
    { data: entry, error: entryError },
    { data: runs, error: runsError },
    { data: reports, error: reportsError },
    { data: decisions, error: decisionsError },
  ] = await Promise.all([
    db.from("gallery_entries").select("*").eq("id", moderationCase.entry_id).maybeSingle(),
    db.from("gallery_moderation_runs").select("*").eq("art_hash", moderationCase.art_hash)
      .order("created_at", { ascending: true }),
    db.from("gallery_reports").select("*").eq("entry_id", moderationCase.entry_id)
      .eq("art_hash", moderationCase.art_hash).order("created_at", { ascending: true }),
    db.from("moderation_decisions").select("*").eq("case_id", caseId)
      .order("created_at", { ascending: true }),
  ]);
  if (entryError) throw entryError;
  if (runsError) throw runsError;
  if (reportsError) throw reportsError;
  if (decisionsError) throw decisionsError;
  if (!entry) throw new Error("ENTRY_NOT_FOUND");

  const [thumbUrl, sheetUrl] = await Promise.all([
    entry.thumb_path
      ? signThumbUrl(entry.thumb_path)
      : previewIdleThumbDataUri(entry.anima_id),
    signAnimaSheetByEntry(entry),
  ]);

  return json(200, {
    case: moderationCase,
    entry: { ...entry, thumb_url: thumbUrl, sheet_url: sheetUrl },
    runs: runs ?? [],
    reports: reports ?? [],
    decisions: decisions ?? [],
  });
}

async function reportsList(body: Body): Promise<Response> {
  const entryId = body.entry_id ? asUuid(body.entry_id, "entry_id") : null;
  const category = body.category ? String(body.category) : null;
  const resolutionState = body.resolution_state ? String(body.resolution_state) : null;
  const { page, perPage } = parsePage(body);

  let query = db
    .from("gallery_reports")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range((page - 1) * perPage, page * perPage - 1);
  if (entryId) query = query.eq("entry_id", entryId);
  if (category) query = query.eq("category", category);
  if (resolutionState) query = query.eq("resolution_state", resolutionState);

  const { data, error, count } = await query;
  if (error) throw error;
  return json(200, { reports: data ?? [], page, per_page: perPage, total: count ?? 0 });
}

async function decide(staffId: string, body: Body): Promise<Response> {
  const caseId = asUuid(body.case_id, "case_id");
  const action = parseDecisionAction(body.action);
  const reasonCode = parseReasonCode(body.reason_code);
  const note = parseNote(body.note);
  const idempotencyKey = parseIdempotencyKey(body.idempotency_key);

  const thumbPath = action === "approve" || action === "restore"
    ? await ensureEntryThumb(caseId)
    : null;

  const { data, error } = await db.rpc("moderation_decide_case", {
    p_case_id: caseId,
    p_staff_id: staffId,
    p_action: action,
    p_reason_code: reasonCode,
    p_note: note,
    p_idempotency_key: idempotencyKey,
    p_thumb_path: thumbPath,
  });
  if (error) throw error;
  return json(200, data ?? { ok: true });
}

// A case opened from a pass-2-uncertain publish attempt never went through
// gallery/index.ts's thumb crop+upload — that path returns into "pending"
// before reaching it (see resolveModerationV2 in gallery/index.ts). Approving
// such a case here must generate the thumbnail itself, or
// moderation_decide_case's THUMB_REQUIRED guard rejects the approve rather
// than publishing an entry with no image. An entry that already has a
// thumb_path (e.g. a restore-sourced approve) is left untouched.
async function ensureEntryThumb(caseId: string): Promise<string | null> {
  const { data: moderationCase, error: caseError } = await db
    .from("moderation_cases")
    .select("entry_id, art_hash")
    .eq("id", caseId)
    .maybeSingle();
  if (caseError) throw caseError;
  if (!moderationCase) return null;

  const { data: entry, error: entryError } = await db
    .from("gallery_entries")
    .select("thumb_path, anima_id")
    .eq("id", moderationCase.entry_id)
    .maybeSingle();
  if (entryError) throw entryError;
  if (!entry || entry.thumb_path) return null;

  const { data: anima, error: animaError } = await db
    .from("animas")
    .select("sheet_path, manifest")
    .eq("id", entry.anima_id)
    .maybeSingle();
  if (animaError) throw animaError;
  if (!anima?.sheet_path || !anima?.manifest) return null;

  const { data: sheetBlob, error: dlError } = await db.storage
    .from("anima_sheets")
    .download(anima.sheet_path);
  if (dlError || !sheetBlob) return null;
  const sheetBytes = new Uint8Array(await sheetBlob.arrayBuffer());

  const { cropIdleThumb } = await import("../_shared/gallery_shared.mjs");
  const thumbBytes = await cropIdleThumb(sheetBytes, anima.manifest);
  const thumbPath = `${entry.anima_id}/${moderationCase.art_hash.slice(0, 16)}.png`;
  const { error: uploadError } = await db.storage
    .from("gallery_thumbs")
    .upload(thumbPath, new Blob([thumbBytes], { type: "image/png" }), {
      contentType: "image/png",
      upsert: true,
    });
  if (uploadError) throw uploadError;
  return thumbPath;
}

// Read-only preview for an entry that never got a persisted thumbnail —
// rejected outright, or still an open publish-sourced case. Crops the same
// idle region from the full sheet but returns it as a data URI instead of
// writing to gallery_thumbs, since this entry may never be approved and
// shouldn't leave a storage artifact just for staff to look at it.
// Each preview downloads and decodes a whole sheet, then base64-inlines it, so
// a Seeker with a long publication list could turn one page load into dozens of
// full-sheet fetches. Rows past the budget come back with an empty url and the
// UI's existing placeholder; staff can still open the case to see the art.
const PREVIEW_THUMB_BUDGET = 12;

/** Runs the previews in small batches so one page cannot fan out unbounded. */
async function previewIdleThumbsFor(
  animaIds: (string | null)[],
): Promise<string[]> {
  const out: string[] = new Array(animaIds.length).fill("");
  let spent = 0;
  for (let i = 0; i < animaIds.length; i += 4) {
    const slice = animaIds.slice(i, i + 4);
    const resolved = await Promise.all(slice.map(async (animaId, offset) => {
      if (!animaId || spent >= PREVIEW_THUMB_BUDGET) return "";
      spent += 1;
      return [offset, await previewIdleThumbDataUri(animaId)] as const;
    }));
    for (const entry of resolved) {
      if (Array.isArray(entry)) out[i + entry[0]] = entry[1];
    }
  }
  return out;
}


async function previewIdleThumbDataUri(animaId: string): Promise<string> {
  const { data: anima, error: animaError } = await db
    .from("animas")
    .select("sheet_path, manifest")
    .eq("id", animaId)
    .maybeSingle();
  // Fail soft: this is a decorative preview and the UI already renders a
  // placeholder for an empty url. Throwing here 500'd the entire Seekers page
  // over one unreadable row.
  if (animaError) {
    console.error("previewIdleThumbDataUri lookup gagal", animaError);
    return "";
  }
  if (!anima?.sheet_path || !anima?.manifest) return "";

  const { data: sheetBlob, error: dlError } = await db.storage
    .from("anima_sheets")
    .download(anima.sheet_path);
  if (dlError || !sheetBlob) return "";
  const sheetBytes = new Uint8Array(await sheetBlob.arrayBuffer());

  try {
    const { cropIdleThumb } = await import("../_shared/gallery_shared.mjs");
    const thumbBytes: Uint8Array = await cropIdleThumb(sheetBytes, anima.manifest);
    let binary = "";
    for (const byte of thumbBytes) binary += String.fromCharCode(byte);
    return `data:image/png;base64,${btoa(binary)}`;
  } catch (e) {
    console.error("previewIdleThumbDataUri crop gagal", e);
    return "";
  }
}

async function restoreEntry(staffId: string, body: Body): Promise<Response> {
  // For an entry that is hidden/rejected with no open case (legacy pre-v2
  // rows, or a case a prior decision already resolved) — opens a fresh
  // manual case and immediately resolves it as restore, so every restore
  // still leaves a decision + audit trail, never a silent direct write.
  const entryId = asUuid(body.entry_id, "entry_id");
  const reasonCode = parseReasonCode(body.reason_code);
  const note = parseNote(body.note);
  const idempotencyKey = parseIdempotencyKey(body.idempotency_key);

  const { data: entry, error: entryError } = await db
    .from("gallery_entries")
    .select("id, art_hash")
    .eq("id", entryId)
    .maybeSingle();
  if (entryError) throw entryError;
  if (!entry) throw new Error("ENTRY_NOT_FOUND");

  const { data: caseId, error: caseError } = await db.rpc(
    "moderation_open_case_for_entry",
    {
      p_entry_id: entryId,
      p_art_hash: entry.art_hash,
      p_source: "manual",
      p_category: null,
      p_confidence: null,
      p_reason_code: reasonCode,
    },
  );
  if (caseError) throw caseError;

  const thumbPath = await ensureEntryThumb(caseId);

  const { data, error } = await db.rpc("moderation_decide_case", {
    p_case_id: caseId,
    p_staff_id: staffId,
    p_action: "restore",
    p_reason_code: reasonCode,
    p_note: note,
    p_idempotency_key: idempotencyKey,
    p_thumb_path: thumbPath,
  });
  if (error) throw error;
  return json(200, data ?? { ok: true });
}

async function sanctionSet(staffId: string, body: Body): Promise<Response> {
  const profileId = asUuid(body.profile_id, "profile_id");
  const scope = parseSanctionScope(body.scope);
  const reasonCode = parseReasonCode(body.reason_code);
  const note = parseNote(body.note);
  const idempotencyKey = parseIdempotencyKey(body.idempotency_key);
  const expiresAt = body.expires_at ? parseTimestamp(body.expires_at) : null;

  const { data: sanctionId, error } = await db.rpc("moderation_set_sanction", {
    p_profile_id: profileId,
    p_staff_id: staffId,
    p_scope: scope,
    p_reason_code: reasonCode,
    p_note: note,
    p_expires_at: expiresAt,
    p_idempotency_key: idempotencyKey,
  });
  if (error) throw error;
  return json(200, { sanction_id: sanctionId });
}

async function sanctionRevoke(staffId: string, body: Body): Promise<Response> {
  const sanctionId = asUuid(body.sanction_id, "sanction_id");
  const reasonCode = parseReasonCode(body.reason_code);
  const idempotencyKey = parseIdempotencyKey(body.idempotency_key);

  const { data, error } = await db.rpc("moderation_revoke_sanction", {
    p_sanction_id: sanctionId,
    p_staff_id: staffId,
    p_reason_code: reasonCode,
    p_idempotency_key: idempotencyKey,
  });
  if (error) throw error;
  return json(200, data ?? { ok: true });
}

async function sanctionsList(body: Body): Promise<Response> {
  const profileId = asUuid(body.profile_id, "profile_id");
  const { data, error } = await db
    .from("profile_sanctions")
    .select("*")
    .eq("profile_id", profileId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return json(200, { sanctions: data ?? [] });
}

async function seekerProfile(body: Body): Promise<Response> {
  const profileId = asUuid(body.profile_id, "profile_id");
  const [
    { data: profile, error: profileError },
    { data: publications, error: publicationsError },
    { data: sanctions, error: sanctionsError },
  ] = await Promise.all([
    db.from("profiles").select("id, seeker_name").eq("id", profileId).maybeSingle(),
    db.from("gallery_entries")
      .select("id, anima_id, thumb_path, display_name, moderation_status, published, auto_hidden, report_count, published_at")
      .eq("owner_id", profileId)
      .order("published_at", { ascending: false, nullsFirst: false }),
    db.from("profile_sanctions").select("*").eq("profile_id", profileId)
      .order("created_at", { ascending: false }),
  ]);
  if (profileError) throw profileError;
  if (!profile) throw new Error("ENTRY_NOT_FOUND");
  if (publicationsError) throw publicationsError;
  if (sanctionsError) throw sanctionsError;

  const entryIds = (publications ?? []).map((row) => row.id);
  let reportsUpheld = 0;
  let reportsDismissed = 0;
  if (entryIds.length > 0) {
    const [{ count: upheldCount, error: upheldError }, { count: dismissedCount, error: dismissedError }] =
      await Promise.all([
        db.from("gallery_reports").select("id", { count: "exact", head: true })
          .eq("resolution_state", "upheld").in("entry_id", entryIds),
        db.from("gallery_reports").select("id", { count: "exact", head: true })
          .eq("resolution_state", "dismissed").in("entry_id", entryIds),
      ]);
    if (upheldError) throw upheldError;
    if (dismissedError) throw dismissedError;
    reportsUpheld = upheldCount ?? 0;
    reportsDismissed = dismissedCount ?? 0;
  }

  const publicationRows = publications ?? [];
  const publicationPreviews = await previewIdleThumbsFor(
    publicationRows.map((row) => (row.thumb_path ? null : row.anima_id ?? null)),
  );
  const publicationsWithThumbs = await Promise.all(
    publicationRows.map(async (row, index) => ({
      ...row,
      thumb_url: row.thumb_path
        ? await signThumbUrl(row.thumb_path)
        : publicationPreviews[index],
    })),
  );

  return json(200, {
    profile,
    publications: publicationsWithThumbs,
    sanctions: sanctions ?? [],
    reports_upheld: reportsUpheld,
    reports_dismissed: reportsDismissed,
  });
}

async function staffList(): Promise<Response> {
  const { data, error } = await db
    .from("staff_accounts")
    .select("*")
    .order("created_at", { ascending: true });
  if (error) throw error;

  // ponytail: staff_accounts is a handful of rows in practice (internal
  // team), so an N+1 admin lookup for email is fine here — this is not a
  // hot path and never runs on a player-facing request.
  const staff = await Promise.all(
    (data ?? []).map(async (row) => {
      const { data: userRow } = await db.auth.admin.getUserById(row.user_id);
      return {
        user_id: row.user_id,
        role: row.role,
        email: userRow.user?.email ?? null,
        granted_by: row.granted_by,
        created_at: row.created_at,
        updated_at: row.updated_at,
      };
    }),
  );
  return json(200, { staff });
}

async function staffSetRole(staffId: string, body: Body): Promise<Response> {
  const targetUserId = body.target_user_id
    ? asUuid(body.target_user_id, "target_user_id")
    : await resolveUserIdByEmail(body.target_email);
  const role = parseStaffRole(body.role);
  const idempotencyKey = parseIdempotencyKey(body.idempotency_key);

  const { data, error } = await db.rpc("admin_set_staff_role", {
    p_target_user_id: targetUserId,
    p_role: role,
    p_staff_id: staffId,
    p_idempotency_key: idempotencyKey,
  });
  if (error) throw error;
  return json(200, data ?? { ok: true });
}

async function auditList(body: Body): Promise<Response> {
  const targetType = body.target_type ? String(body.target_type) : null;
  const actorId = body.actor_id ? asUuid(body.actor_id, "actor_id") : null;
  const { page, perPage } = parsePage(body);

  let query = db
    .from("admin_audit_log")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range((page - 1) * perPage, page * perPage - 1);
  if (targetType) query = query.eq("target_type", targetType);
  if (actorId) query = query.eq("actor_id", actorId);

  const { data, error, count } = await query;
  if (error) throw error;
  return json(200, { entries: data ?? [], page, per_page: perPage, total: count ?? 0 });
}

async function analytics(body: Body): Promise<Response> {
  const sinceDays = Number.isFinite(Number(body.since_days)) ? Number(body.since_days) : 30;
  const clampedDays = Math.min(Math.max(sinceDays, 1), 365);
  const since = new Date(Date.now() - clampedDays * 24 * 60 * 60 * 1000).toISOString();

  const { data, error } = await db.rpc("moderation_analytics_summary", { p_since: since });
  if (error) throw error;
  return json(200, data ?? {});
}

// --- helpers -----------------------------------------------------------

async function resolveUserIdByEmail(email: unknown): Promise<string> {
  if (typeof email !== "string" || !email.includes("@")) {
    throw new Error("INVALID_TARGET_USER_ID");
  }
  // ponytail: bounded to 5 pages (1000 users). Staff onboarding is rare and
  // manual; a real user-search endpoint is overkill for this volume. Upgrade
  // to a proper lookup if the player base outgrows this ceiling.
  const normalized = email.trim().toLowerCase();
  for (let page = 1; page <= 5; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const match = data.users.find((user) => user.email?.toLowerCase() === normalized);
    if (match) return match.id;
    if (data.users.length < 200) break;
  }
  throw new Error("INVALID_TARGET_USER_ID");
}

async function signThumbUrl(path: string): Promise<string> {
  if (!path) return "";
  const { data, error } = await db.storage.from("gallery_thumbs").createSignedUrl(
    path,
    THUMB_SIGNED_TTL,
  );
  if (error) return "";
  return data?.signedUrl ?? "";
}

async function signThumbUrls(paths: string[]): Promise<Map<string, string>> {
  const unique = [...new Set(paths.filter(Boolean))];
  const result = new Map<string, string>();
  if (unique.length === 0) return result;
  const { data, error } = await db.storage.from("gallery_thumbs").createSignedUrls(
    unique,
    THUMB_SIGNED_TTL,
  );
  if (error) return result;
  for (const [index, item] of (data ?? []).entries()) {
    const path = typeof item.path === "string" ? item.path : unique[index];
    if (path && item.signedUrl) result.set(path, item.signedUrl);
  }
  return result;
}

// deno-lint-ignore no-explicit-any
async function signAnimaSheetByEntry(entry: any): Promise<string> {
  const { data: anima } = await db.from("animas").select("sheet_path").eq(
    "id",
    entry.anima_id,
  ).maybeSingle();
  const path = typeof anima?.sheet_path === "string" ? anima.sheet_path : "";
  if (!path) return "";
  const { signSheetUrl } = await import("../_shared/signed_roster.ts");
  return await signSheetUrl(db, path);
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function asUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function parsePage(body: Body): { page: number; perPage: number } {
  const page = body.page === undefined || body.page === null ? 1 : Number(body.page);
  const perPage = body.per_page === undefined || body.per_page === null
    ? 24
    : Number(body.per_page);
  if (!Number.isInteger(page) || page < 1) throw new Error("INVALID_PAGE");
  if (!Number.isInteger(perPage) || perPage < 1 || perPage > 100) {
    throw new Error("INVALID_PAGE");
  }
  return { page, perPage };
}

function parseCaseStatus(value: unknown, fallback: string): string {
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value !== "string" || !CASE_STATUSES.has(value)) {
    throw new Error("INVALID_STATUS");
  }
  return value;
}

function parseCaseSource(value: unknown): string {
  if (typeof value !== "string" || !CASE_SOURCES.has(value)) {
    throw new Error("INVALID_SOURCE");
  }
  return value;
}

function parseDecisionAction(value: unknown): string {
  if (typeof value !== "string" || !DECISION_ACTIONS.has(value)) {
    throw new Error("INVALID_ACTION");
  }
  return value;
}

function parseSanctionScope(value: unknown): string {
  if (typeof value !== "string" || !SANCTION_SCOPES.has(value)) {
    throw new Error("INVALID_SCOPE");
  }
  return value;
}

function parseStaffRole(value: unknown): string {
  if (
    typeof value !== "string" ||
    !["viewer", "moderator", "admin", "revoked"].includes(value)
  ) {
    throw new Error("INVALID_ROLE");
  }
  return value;
}

function parseReasonCode(value: unknown): string {
  if (typeof value !== "string" || !value.trim() || value.length > 64) {
    throw new Error("INVALID_REASON_CODE");
  }
  return value.trim();
}

function parseNote(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") return null;
  return value.trim().slice(0, 500) || null;
}

function parseIdempotencyKey(value: unknown): string {
  if (typeof value !== "string" || !value.trim() || value.length > 128) {
    throw new Error("INVALID_IDEMPOTENCY_KEY");
  }
  return value.trim();
}

function parseTimestamp(value: unknown): string {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    throw new Error("INVALID_STATUS");
  }
  return new Date(value).toISOString();
}
