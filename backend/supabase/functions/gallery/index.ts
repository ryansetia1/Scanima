// POST /gallery { operation: list|publish|unpublish|report|hide|my_status, ... }

import { adminClient, clientVersionGate, json } from "../_shared/supa.ts";
import { normalizeSuggestedName } from "../_shared/vision.mjs";
import {
  BATTLE_SHEET_SIGNED_TTL,
  GALLERY_REPORT_AUTO_HIDE,
  THUMB_SIGNED_TTL,
  cropIdleThumb,
  hashSheetBytes,
  moderateSheetImage,
  removeThumb,
} from "../_shared/gallery.mjs";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OPERATIONS = new Set(["list", "publish", "unpublish", "report", "hide", "my_status"]);
const LIST_LIMIT_DEFAULT = 24;
const LIST_LIMIT_MAX = 48;

const ERROR_STATUS: Record<string, number> = {
  FEATURE_DISABLED: 503,
  INVALID_ANIMA_ID: 400,
  INVALID_ENTRY_ID: 400,
  INVALID_CURSOR: 400,
  INVALID_LIMIT: 400,
  ACCOUNT_STILL_ANONYMOUS: 409,
  GOOGLE_IDENTITY_REQUIRED: 409,
  ANIMA_NOT_FOUND: 404,
  ANIMA_NOT_READY: 409,
  ANIMA_NOT_OWNED: 403,
  ANIMA_NOT_TYPING_V2: 409,
  ANIMA_NO_ART: 409,
  GALLERY_ENTRY_NOT_FOUND: 404,
  GALLERY_MODERATION_REJECTED: 409,
  GALLERY_ALREADY_PUBLISHED: 409,
  GALLERY_NOT_PUBLISHED: 409,
  VISION_MODERATION_FAILED: 502,
};

type GalleryBody = {
  operation?: unknown;
  anima_id?: unknown;
  entry_id?: unknown;
  cursor?: unknown;
  limit?: unknown;
};

const db = adminClient();

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await db.auth.getClaims(token);
  const ownerId = auth?.claims?.sub;
  if (authError || typeof ownerId !== "string") return json(401, { error: "token tidak sah" });

  let body: GalleryBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const operation = typeof body.operation === "string" ? body.operation : "";
  if (!OPERATIONS.has(operation)) return json(400, { error: "operation tidak dikenal" });

  try {
    const enabled = await featureEnabled();
    if (operation === "list") return await listEntries(ownerId, body, enabled);
    if (operation === "my_status") return await myStatus(ownerId, body);
    if (!enabled) throw new Error("FEATURE_DISABLED");
    if (operation === "publish") return await publishEntry(ownerId, body);
    if (operation === "unpublish") return await unpublishEntry(ownerId, body);
    if (operation === "report") return await reportEntry(ownerId, body);
    if (operation === "hide") return await hideEntry(ownerId, body);
    return json(400, { error: "operation tidak dikenal" });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : String(error);
    const marker = Object.keys(ERROR_STATUS).find((candidate) => message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("gallery gagal", error);
    return json(500, { error: "gallery gagal diproses" });
  }
});

async function featureEnabled(): Promise<boolean> {
  const { data } = await db.from("app_config").select("value").eq("key", "feature_gallery").maybeSingle();
  if (typeof data?.value === "boolean") return data.value;
  if (typeof data?.value === "string") return data.value === "true";
  return false;
}

async function listEntries(ownerId: string, body: GalleryBody, enabled: boolean): Promise<Response> {
  if (!enabled) {
    return json(200, { entries: [], next_cursor: null, feature_enabled: false });
  }

  const limit = parseLimit(body.limit);
  let query = db
    .from("gallery_entries")
    .select("id, display_name, element, secondary_element, stage, thumb_path, published_at")
    .eq("published", true)
    .eq("moderation_status", "approved")
    .eq("auto_hidden", false)
    .order("published_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit + 1);

  const cursor = parseCursor(body.cursor);
  if (cursor) {
    query = query.or(
      `published_at.lt.${cursor.published_at},and(published_at.eq.${cursor.published_at},id.lt.${cursor.id})`,
    );
  }

  const { data: rows, error } = await query;
  if (error) throw error;

  const { data: hiddenRows } = await db
    .from("gallery_hidden")
    .select("entry_id")
    .eq("owner_id", ownerId);
  const hidden = new Set((hiddenRows ?? []).map((row) => row.entry_id as string));

  const visible = ((rows ?? []) as Record<string, unknown>[])
    .filter((row) => !hidden.has(String(row.id)));

  const page = visible.slice(0, limit);
  const hasMore = visible.length > limit || ((rows ?? []).length > limit && page.length === limit);
  let nextCursor: string | null = null;
  if (hasMore && page.length > 0) {
    const last = page[page.length - 1];
    nextCursor = encodeCursor(String(last.published_at), String(last.id));
  }

  const entries = [];
  for (const row of page) {
    const thumbPath = typeof row.thumb_path === "string" ? row.thumb_path : "";
    let thumb_url = "";
    if (thumbPath) {
      const { data: signed } = await db.storage
        .from("gallery_thumbs")
        .createSignedUrl(thumbPath, THUMB_SIGNED_TTL);
      thumb_url = signed?.signedUrl ?? "";
    }
    entries.push({
      id: row.id,
      display_name: row.display_name,
      element: row.element,
      secondary_element: row.secondary_element ?? null,
      stage: row.stage,
      thumb_url,
    });
  }

  return json(200, { entries, next_cursor: nextCursor, feature_enabled: true });
}

async function myStatus(ownerId: string, body: GalleryBody): Promise<Response> {
  const animaId = asUuid(body.anima_id, "anima_id");
  const { data: anima, error: animaError } = await db
    .from("animas")
    .select("id, owner_id, status, typing_version")
    .eq("id", animaId)
    .maybeSingle();
  if (animaError) throw animaError;
  if (!anima) throw new Error("ANIMA_NOT_FOUND");
  if (anima.owner_id !== ownerId) throw new Error("ANIMA_NOT_OWNED");

  const { data: entry } = await db
    .from("gallery_entries")
    .select("id, moderation_status, published, auto_hidden, published_at, updated_at")
    .eq("anima_id", animaId)
    .maybeSingle();

  const linked = await hasLinkedGoogle(ownerId);
  return json(200, {
    anima_id: animaId,
    ready: anima.status === "ready",
    typing_v2: (anima.typing_version ?? 1) >= 2,
    linked_google: linked,
    entry: entry
      ? {
        id: entry.id,
        moderation_status: entry.moderation_status,
        published: entry.published,
        auto_hidden: entry.auto_hidden,
        published_at: entry.published_at,
        updated_at: entry.updated_at,
      }
      : null,
  });
}

async function publishEntry(ownerId: string, body: GalleryBody): Promise<Response> {
  await requireLinkedGoogle(ownerId);
  const animaId = asUuid(body.anima_id, "anima_id");

  const { data: anima, error: animaError } = await db
    .from("animas")
    .select(
      "id, owner_id, status, typing_version, element, secondary_element, stage, sheet_path, manifest",
    )
    .eq("id", animaId)
    .maybeSingle();
  if (animaError) throw animaError;
  if (!anima) throw new Error("ANIMA_NOT_FOUND");
  if (anima.owner_id !== ownerId) throw new Error("ANIMA_NOT_OWNED");
  if (anima.status !== "ready") throw new Error("ANIMA_NOT_READY");
  if ((anima.typing_version ?? 1) < 2) throw new Error("ANIMA_NOT_TYPING_V2");
  if (!anima.sheet_path || !anima.manifest) throw new Error("ANIMA_NO_ART");

  const { data: generation } = await db
    .from("generations")
    .select("vision_result")
    .eq("anima_id", animaId)
    .eq("status", "succeeded")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const vision = generation?.vision_result && typeof generation.vision_result === "object"
    ? generation.vision_result as Record<string, unknown>
    : {};
  const displayName = normalizeSuggestedName(
    typeof vision.suggested_name === "string" ? vision.suggested_name : "",
    "Anima",
  );

  const { data: sheetBlob, error: dlError } = await db.storage
    .from("anima_sheets")
    .download(anima.sheet_path);
  if (dlError || !sheetBlob) throw new Error("ANIMA_NO_ART");
  const sheetBytes = new Uint8Array(await sheetBlob.arrayBuffer());
  const artHash = await hashSheetBytes(sheetBytes);

  let moderationStatus = "pending";
  let rejectReason: string | null = null;

  const { data: cachedMod } = await db
    .from("gallery_moderations")
    .select("status, reject_reason")
    .eq("art_hash", artHash)
    .maybeSingle();

  if (cachedMod) {
    moderationStatus = cachedMod.status === "approved" ? "approved" : "rejected";
    rejectReason = cachedMod.reject_reason ?? null;
  } else {
    const { data: signed } = await db.storage
      .from("anima_sheets")
      .createSignedUrl(anima.sheet_path, BATTLE_SHEET_SIGNED_TTL);
    if (!signed?.signedUrl) throw new Error("VISION_MODERATION_FAILED");

    let moderation;
    try {
      moderation = await moderateSheetImage(signed.signedUrl);
    } catch (e) {
      console.error("gallery moderation vision gagal", e);
      throw new Error("VISION_MODERATION_FAILED");
    }

    moderationStatus = moderation.safe ? "approved" : "rejected";
    rejectReason = moderation.reject_reason;
    const { error: modError } = await db.from("gallery_moderations").insert({
      art_hash: artHash,
      status: moderationStatus,
      reject_reason: rejectReason,
    });
    if (modError && !modError.message.includes("duplicate")) throw modError;
  }

  if (moderationStatus === "rejected") {
    const { data: priorEntry } = await db
      .from("gallery_entries")
      .select("thumb_path")
      .eq("anima_id", animaId)
      .maybeSingle();
    const { error: rejectedError } = await db.from("gallery_entries").upsert({
      owner_id: ownerId,
      anima_id: animaId,
      art_hash: artHash,
      display_name: displayName,
      element: anima.element,
      secondary_element: anima.secondary_element,
      stage: anima.stage,
      thumb_path: null,
      moderation_status: "rejected",
      published: false,
      auto_hidden: false,
      report_count: 0,
      published_at: null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "anima_id" });
    if (rejectedError) throw rejectedError;
    await removeThumb(db, priorEntry?.thumb_path ?? null);
    throw new Error("GALLERY_MODERATION_REJECTED");
  }

  const thumbBytes = await cropIdleThumb(sheetBytes, anima.manifest);
  const thumbPath = `${animaId}/${artHash.slice(0, 16)}.png`;
  const { error: thumbError } = await db.storage
    .from("gallery_thumbs")
    .upload(thumbPath, new Blob([thumbBytes], { type: "image/png" }), {
      contentType: "image/png",
      upsert: true,
    });
  if (thumbError) throw thumbError;

  const now = new Date().toISOString();
  const payload = {
    owner_id: ownerId,
    anima_id: animaId,
    art_hash: artHash,
    display_name: displayName,
    element: anima.element,
    secondary_element: anima.secondary_element,
    stage: anima.stage,
    thumb_path: thumbPath,
    moderation_status: "approved",
    published: true,
    auto_hidden: false,
    report_count: 0,
    published_at: now,
    updated_at: now,
  };

  const { data: existing } = await db
    .from("gallery_entries")
    .select("id, thumb_path, published")
    .eq("anima_id", animaId)
    .maybeSingle();

  if (existing) {
    if (existing.published && existing.thumb_path === thumbPath) {
      return json(200, {
        entry_id: existing.id,
        published: true,
        moderation_status: "approved",
        display_name: displayName,
      });
    }
    if (existing.thumb_path && existing.thumb_path !== thumbPath) {
      await removeThumb(db, existing.thumb_path);
    }
    const { data: updated, error: updateError } = await db
      .from("gallery_entries")
      .update(payload)
      .eq("id", existing.id)
      .select("id")
      .single();
    if (updateError) throw updateError;
    return json(200, {
      entry_id: updated.id,
      published: true,
      moderation_status: "approved",
      display_name: displayName,
    });
  }

  const { data: inserted, error: insertError } = await db
    .from("gallery_entries")
    .insert(payload)
    .select("id")
    .single();
  if (insertError) throw insertError;
  return json(200, {
    entry_id: inserted.id,
    published: true,
    moderation_status: "approved",
    display_name: displayName,
  });
}

async function unpublishEntry(ownerId: string, body: GalleryBody): Promise<Response> {
  const animaId = asUuid(body.anima_id, "anima_id");
  const { data: entry, error } = await db
    .from("gallery_entries")
    .select("id, owner_id, thumb_path, published")
    .eq("anima_id", animaId)
    .maybeSingle();
  if (error) throw error;
  if (!entry) throw new Error("GALLERY_NOT_PUBLISHED");
  if (entry.owner_id !== ownerId) throw new Error("ANIMA_NOT_OWNED");
  if (!entry.published) {
    return json(200, { unpublished: true, entry_id: entry.id });
  }

  const thumbPath = entry.thumb_path;
  const { error: updateError } = await db
    .from("gallery_entries")
    .update({ published: false, updated_at: new Date().toISOString() })
    .eq("id", entry.id);
  if (updateError) throw updateError;

  await removeThumb(db, thumbPath);
  return json(200, { unpublished: true, entry_id: entry.id });
}

async function reportEntry(ownerId: string, body: GalleryBody): Promise<Response> {
  const entryId = asUuid(body.entry_id, "entry_id");
  const { data: entry, error } = await db
    .from("gallery_entries")
    .select("id, published, moderation_status, auto_hidden, report_count")
    .eq("id", entryId)
    .maybeSingle();
  if (error) throw error;
  if (!entry || !entry.published || entry.moderation_status !== "approved") {
    throw new Error("GALLERY_ENTRY_NOT_FOUND");
  }

  const { error: reportError } = await db.from("gallery_reports").insert({
    entry_id: entryId,
    reporter_id: ownerId,
  });
  if (reportError && !reportError.message.includes("duplicate")) throw reportError;

  const { count } = await db
    .from("gallery_reports")
    .select("id", { count: "exact", head: true })
    .eq("entry_id", entryId);
  const reportCount = count ?? entry.report_count;
  let autoHidden = entry.auto_hidden;
  if (reportCount >= GALLERY_REPORT_AUTO_HIDE && !autoHidden) {
    autoHidden = true;
    await db.from("gallery_entries").update({
      auto_hidden: true,
      report_count: reportCount,
      updated_at: new Date().toISOString(),
    }).eq("id", entryId);
  } else if (reportCount !== entry.report_count) {
    await db.from("gallery_entries").update({
      report_count: reportCount,
      updated_at: new Date().toISOString(),
    }).eq("id", entryId);
  }

  return json(200, {
    reported: true,
    entry_id: entryId,
    auto_hidden: autoHidden,
    report_count: reportCount,
  });
}

async function hideEntry(ownerId: string, body: GalleryBody): Promise<Response> {
  const entryId = asUuid(body.entry_id, "entry_id");
  const { data: entry } = await db
    .from("gallery_entries")
    .select("id")
    .eq("id", entryId)
    .eq("published", true)
    .eq("moderation_status", "approved")
    .maybeSingle();
  if (!entry) throw new Error("GALLERY_ENTRY_NOT_FOUND");

  const { error } = await db.from("gallery_hidden").upsert({
    owner_id: ownerId,
    entry_id: entryId,
  }, { onConflict: "owner_id,entry_id", ignoreDuplicates: true });
  if (error) throw error;
  return json(200, { hidden: true, entry_id: entryId });
}

async function hasLinkedGoogle(ownerId: string): Promise<boolean> {
  const { data: userRow } = await db.auth.admin.getUserById(ownerId);
  if (userRow.user?.is_anonymous) return false;
  return (userRow.user?.identities ?? []).some((identity) => identity.provider === "google");
}

async function requireLinkedGoogle(ownerId: string): Promise<void> {
  const { data: userRow } = await db.auth.admin.getUserById(ownerId);
  if (userRow.user?.is_anonymous) throw new Error("ACCOUNT_STILL_ANONYMOUS");
  const hasGoogle = (userRow.user?.identities ?? []).some((identity) => identity.provider === "google");
  if (!hasGoogle) throw new Error("GOOGLE_IDENTITY_REQUIRED");
}

function asUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function parseLimit(value: unknown): number {
  if (value === undefined || value === null) return LIST_LIMIT_DEFAULT;
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > LIST_LIMIT_MAX) {
    throw new Error("INVALID_LIMIT");
  }
  return value;
}

function parseCursor(value: unknown): { published_at: string; id: string } | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") throw new Error("INVALID_CURSOR");
  try {
    const decoded = JSON.parse(atob(value));
    if (
      typeof decoded?.published_at !== "string" ||
      typeof decoded?.id !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(decoded.published_at) ||
      !Number.isFinite(Date.parse(decoded.published_at)) ||
      !UUID_RE.test(decoded.id)
    ) {
      throw new Error("INVALID_CURSOR");
    }
    return { published_at: decoded.published_at, id: decoded.id };
  } catch {
    throw new Error("INVALID_CURSOR");
  }
}

function encodeCursor(publishedAt: string, id: string): string {
  return btoa(JSON.stringify({ published_at: publishedAt, id }));
}
