// POST /gallery { operation: atlas_list|atlas_detail|publish|unpublish|report|my_status, ... }
// Legacy list/hide remain only so installed Gallery builds survive the Atlas rollout.

import { adminClient, clientVersionGate, json } from "../_shared/supa.ts";
import { normalizeSuggestedName } from "../_shared/vision.mjs";
import { signSheetUrl } from "../_shared/signed_roster.ts";
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
const OPERATIONS = new Set([
  "atlas_list",
  "atlas_detail",
  "list",
  "hide",
  "publish",
  "unpublish",
  "report",
  "my_status",
]);
const FILTERS = new Set(["all", "scanned", "expedition", "duel"]);
const LIST_LIMIT_DEFAULT = 24;
const LIST_LIMIT_MAX = 48;

const ERROR_STATUS: Record<string, number> = {
  FEATURE_DISABLED: 503,
  INVALID_ANIMA_ID: 400,
  INVALID_ENTRY_ID: 400,
  INVALID_FORM_ID: 400,
  INVALID_CHAPTER_ID: 400,
  INVALID_FILTER: 400,
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
  ATLAS_FORM_NOT_FOUND: 404,
};

type GalleryBody = {
  operation?: unknown;
  anima_id?: unknown;
  entry_id?: unknown;
  form_id?: unknown;
  filter?: unknown;
  chapter_id?: unknown;
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
    if (operation === "list") {
      return await listLegacyEntries(ownerId, body, await galleryFeatureEnabled());
    }
    const enabled = await featureEnabled();
    if (operation === "atlas_list") return await listAtlas(ownerId, body, enabled);
    if (operation === "atlas_detail") return await atlasDetail(ownerId, body, enabled);
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
    console.error("Anima Atlas gagal", error);
    return json(500, { error: "Anima Atlas gagal diproses" });
  }
});

async function featureEnabled(): Promise<boolean> {
  const { data } = await db.from("app_config").select("value").eq("key", "feature_atlas").maybeSingle();
  if (typeof data?.value === "boolean") return data.value;
  if (typeof data?.value === "string") return data.value === "true";
  return false;
}

async function galleryFeatureEnabled(): Promise<boolean> {
  const { data } = await db.from("app_config").select("value").eq("key", "feature_gallery").maybeSingle();
  if (typeof data?.value === "boolean") return data.value;
  if (typeof data?.value === "string") return data.value === "true";
  return false;
}

async function listLegacyEntries(
  ownerId: string,
  body: GalleryBody,
  enabled: boolean,
): Promise<Response> {
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

  const cursor = parseLegacyCursor(body.cursor);
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
  const hidden = new Set((hiddenRows ?? []).map((row) => String(row.entry_id)));
  const visible = ((rows ?? []) as Record<string, unknown>[])
    .filter((row) => !hidden.has(String(row.id)));
  const page = visible.slice(0, limit);
  const hasMore = visible.length > limit || ((rows ?? []).length > limit && page.length === limit);
  const entries = [];

  for (const row of page) {
    const thumbPath = typeof row.thumb_path === "string" ? row.thumb_path : "";
    let thumbUrl = "";
    if (thumbPath) {
      const { data: signed } = await db.storage
        .from("gallery_thumbs")
        .createSignedUrl(thumbPath, THUMB_SIGNED_TTL);
      thumbUrl = signed?.signedUrl ?? "";
    }
    entries.push({
      id: row.id,
      display_name: row.display_name,
      element: row.element,
      secondary_element: row.secondary_element ?? null,
      stage: row.stage,
      thumb_url: thumbUrl,
    });
  }

  const last = hasMore && page.length > 0 ? page[page.length - 1] : null;
  return json(200, {
    entries,
    next_cursor: last ? encodeLegacyCursor(String(last.published_at), String(last.id)) : null,
    feature_enabled: true,
  });
}

async function listAtlas(ownerId: string, body: GalleryBody, enabled: boolean): Promise<Response> {
  if (!enabled) {
    return json(200, { entries: [], chapters: [], next_cursor: null, feature_enabled: false });
  }

  const limit = parseLimit(body.limit);
  const filter = parseFilter(body.filter);
  const chapterId = body.chapter_id === undefined || body.chapter_id === null || body.chapter_id === ""
    ? null
    : asUuid(body.chapter_id, "chapter_id");
  const cursor = parseCursor(body.cursor);
  let query = db
    .from("seeker_atlas_discoveries")
    .select("*")
    .eq("owner_id", ownerId)
    .order("last_seen_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit + 1);
  if (filter !== "all") query = query.eq("discovery_source", filter);
  if (cursor) {
    query = query.or(
      `last_seen_at.lt.${cursor.last_seen_at},and(last_seen_at.eq.${cursor.last_seen_at},id.lt.${cursor.id})`,
    );
  }

  const [{ data: discoveryRows, error: discoveryError }, { data: chapterCatalog, error: catalogError }] =
    await Promise.all([
      query,
      db.rpc("expedition_chapter_catalog", { p_owner: ownerId }),
    ]);
  if (discoveryError) throw discoveryError;
  if (catalogError) throw catalogError;

  const rawDiscoveries = (discoveryRows ?? []) as Record<string, unknown>[];
  const pageDiscoveries = rawDiscoveries.slice(0, limit);
  const pageFormIds = pageDiscoveries.map((row) => String(row.form_id));
  const unlockedChapterIds = (Array.isArray(chapterCatalog) ? chapterCatalog : [])
    .filter((row) => row && typeof row === "object" && row.unlocked === true)
    .map((row) => String(row.id));
  const [{ data: pageForms, error: formsError }, { data: chapterRows, error: chapterError }] =
    await Promise.all([
      pageFormIds.length > 0
        ? db.from("atlas_forms").select("*").in("id", pageFormIds)
        : Promise.resolve({ data: [], error: null }),
      unlockedChapterIds.length > 0
        ? db
          .from("expedition_chapters")
          .select("id, slug, sequence")
          .in("id", unlockedChapterIds)
          .order("sequence")
        : Promise.resolve({ data: [], error: null }),
    ]);
  if (formsError) throw formsError;
  if (chapterError) throw chapterError;

  let activeQuery = db
    .from("atlas_forms")
    .select("*")
    .eq("source_kind", "expedition")
    .eq("catalog_active", true)
    .order("source_slug")
    .order("stage");
  activeQuery = unlockedChapterIds.length > 0
    ? activeQuery.in("chapter_id", unlockedChapterIds)
    : activeQuery.limit(0);
  const { data: activeForms, error: activeError } = await activeQuery.limit(200);
  if (activeError) throw activeError;

  const activeFormIds = (activeForms ?? []).map((row) => String(row.id));
  const { data: chapterDiscoveryRows, error: chapterDiscoveryError } = activeFormIds.length > 0
    ? await db
      .from("seeker_atlas_discoveries")
      .select("*")
      .eq("owner_id", ownerId)
      .in("form_id", activeFormIds)
    : { data: [], error: null };
  if (chapterDiscoveryError) throw chapterDiscoveryError;
  const discoveredChapterForms = new Set(
    (chapterDiscoveryRows ?? []).map((row) => String(row.form_id)),
  );

  const forms = new Map(
    ((pageForms ?? []) as Record<string, unknown>[]).map((form) => [String(form.id), form]),
  );
  const publicationIds = [...new Set(
    [...forms.values()]
      .map((form) => typeof form.publication_id === "string" ? form.publication_id : "")
      .filter(Boolean),
  )];
  const ownerIds = [...new Set(
    [...forms.values()]
      .map((form) => typeof form.owner_id === "string" ? form.owner_id : "")
      .filter(Boolean),
  )];
  const [{ data: publications, error: publicationError }, { data: profiles, error: profileError }] =
    await Promise.all([
      publicationIds.length > 0
        ? db
          .from("gallery_entries")
          .select("id, published, auto_hidden")
          .in("id", publicationIds)
        : Promise.resolve({ data: [], error: null }),
      ownerIds.length > 0
        ? db.from("profiles").select("id, seeker_name").in("id", ownerIds)
        : Promise.resolve({ data: [], error: null }),
    ]);
  if (publicationError) throw publicationError;
  if (profileError) throw profileError;
  const publicationById = new Map((publications ?? []).map((row) => [String(row.id), row]));
  const profileById = new Map((profiles ?? []).map((row) => [String(row.id), row]));

  const entries: Record<string, unknown>[] = [];
  for (const discovery of pageDiscoveries) {
    const form = forms.get(String(discovery.form_id));
    if (!form || (chapterId && form.chapter_id !== chapterId)) continue;
    if (form.source_kind === "player" && form.owner_id !== ownerId) {
      const publication = publicationById.get(String(form.publication_id));
      if (
        !publication?.published ||
        publication.auto_hidden ||
        form.moderation_status !== "approved"
      ) continue;
    }
    entries.push(await atlasCard(
      form,
      discovery,
      profileById.get(String(form.owner_id)),
      true,
    ));
  }

  // ponytail: chapter casts are capped at 200 active forms in the MVP. Player
  // discoveries remain cursor-paginated; add a catalog cursor if authored
  // chapter casts ever exceed that ceiling.
  if (!cursor && (filter === "all" || filter === "expedition")) {
    for (const form of (activeForms ?? []) as Record<string, unknown>[]) {
      if (chapterId && form.chapter_id !== chapterId) continue;
      if (discoveredChapterForms.has(String(form.id))) continue;
      entries.push(await atlasCard(form, null, null, false));
    }
  }

  const activeByChapter = new Map<string, number>();
  const discoveredByChapter = new Map<string, number>();
  for (const form of (activeForms ?? []) as Record<string, unknown>[]) {
    const id = String(form.chapter_id);
    activeByChapter.set(id, (activeByChapter.get(id) ?? 0) + 1);
    if (discoveredChapterForms.has(String(form.id))) {
      discoveredByChapter.set(id, (discoveredByChapter.get(id) ?? 0) + 1);
    }
  }
  const chapters = (chapterRows ?? []).map((row) => ({
    id: row.id,
    slug: row.slug,
    sequence: row.sequence,
    discovered: discoveredByChapter.get(String(row.id)) ?? 0,
    total: activeByChapter.get(String(row.id)) ?? 0,
  }));

  if (chapterId) {
    const discoveryByForm = new Map(
      ((chapterDiscoveryRows ?? []) as Record<string, unknown>[]).map((row) => [
        String(row.form_id),
        row,
      ]),
    );
    const chapterEntries: Record<string, unknown>[] = [];
    for (const form of (activeForms ?? []) as Record<string, unknown>[]) {
      if (form.chapter_id !== chapterId) continue;
      const discovery = discoveryByForm.get(String(form.id)) ?? null;
      chapterEntries.push(await atlasCard(form, discovery, null, discovery !== null));
    }
    return json(200, {
      entries: chapterEntries,
      chapters,
      next_cursor: null,
      feature_enabled: true,
    });
  }

  const last = pageDiscoveries[pageDiscoveries.length - 1];
  return json(200, {
    entries,
    chapters,
    next_cursor: rawDiscoveries.length > limit && last
      ? encodeCursor(String(last.last_seen_at), String(last.id))
      : null,
    feature_enabled: true,
  });
}

async function atlasDetail(ownerId: string, body: GalleryBody, enabled: boolean): Promise<Response> {
  if (!enabled) throw new Error("FEATURE_DISABLED");
  const formId = asUuid(body.form_id, "form_id");
  const [{ data: form, error: formError }, { data: discovery, error: discoveryError }] =
    await Promise.all([
      db.from("atlas_forms").select("*").eq("id", formId).maybeSingle(),
      db
        .from("seeker_atlas_discoveries")
        .select("*")
        .eq("owner_id", ownerId)
        .eq("form_id", formId)
        .maybeSingle(),
    ]);
  if (formError) throw formError;
  if (discoveryError) throw discoveryError;
  if (!form || !discovery) throw new Error("ATLAS_FORM_NOT_FOUND");

  let ownerName: string | null = null;
  let entryId: string | null = null;
  if (form.source_kind === "player" && form.owner_id !== ownerId) {
    const { data: publication, error } = await db
      .from("gallery_entries")
      .select("id, published, auto_hidden")
      .eq("id", form.publication_id)
      .maybeSingle();
    if (error) throw error;
    if (
      !publication?.published ||
      publication.auto_hidden ||
      form.moderation_status !== "approved"
    ) throw new Error("ATLAS_FORM_NOT_FOUND");
    entryId = publication.id;
    const { data: profile } = await db
      .from("profiles")
      .select("seeker_name")
      .eq("id", form.owner_id)
      .maybeSingle();
    ownerName = typeof profile?.seeker_name === "string" ? profile.seeker_name : "Seeker";
  }

  return json(200, {
    entry: {
      form_id: form.id,
      source_kind: form.source_kind,
      discovery_source: discovery.discovery_source,
      anima_id: form.owner_id === ownerId ? form.anima_id : null,
      entry_id: entryId,
      display_name: form.display_name,
      owner_name: ownerName,
      stage: form.stage,
      subject_kind: form.subject_kind,
      element: form.element,
      secondary_element: form.secondary_element,
      rarity: form.rarity,
      base_stats: form.base_stats,
      body_height_cm: form.body_height_cm,
      strike_name: form.strike_name,
      surge_name: form.surge_name,
      manifest: form.manifest,
      sheet_url: await atlasSheetUrl(form as Record<string, unknown>),
      first_seen_at: discovery.first_seen_at,
      last_seen_at: discovery.last_seen_at,
      encounter_count: discovery.encounter_count,
      level_at_first_seen: discovery.level_at_first_seen,
      level_at_last_seen: discovery.level_at_last_seen,
      can_report: form.source_kind === "player" && form.owner_id !== ownerId,
      can_view_collection: form.source_kind === "player" && form.owner_id === ownerId,
    },
    feature_enabled: true,
  });
}

async function atlasCard(
  form: Record<string, unknown>,
  discovery: Record<string, unknown> | null,
  profile: Record<string, unknown> | null | undefined,
  discovered: boolean,
): Promise<Record<string, unknown>> {
  const thumbPath = typeof form.thumb_path === "string" ? form.thumb_path : "";
  let thumbUrl = "";
  if (thumbPath) {
    const { data: signed } = await db.storage
      .from("gallery_thumbs")
      .createSignedUrl(thumbPath, THUMB_SIGNED_TTL);
    thumbUrl = signed?.signedUrl ?? "";
  }
  return {
    form_id: form.id,
    source_kind: form.source_kind,
    discovery_source: discovery?.discovery_source ?? null,
    discovered,
    anima_id: discovered && discovery?.discovery_source === "scanned" ? form.anima_id : null,
    entry_id: discovered && discovery?.discovery_source === "duel" ? form.publication_id : null,
    display_name: discovered ? form.display_name : "???",
    owner_name: discovered && discovery?.discovery_source === "duel"
      ? (typeof profile?.seeker_name === "string" ? profile.seeker_name : "Seeker")
      : null,
    stage: discovered ? form.stage : null,
    element: discovered ? form.element : null,
    secondary_element: discovered ? form.secondary_element : null,
    chapter_id: form.chapter_id,
    source_slug: form.source_slug,
    thumb_url: thumbUrl,
    sheet_url: await atlasSheetUrl(form),
    card_manifest: cardManifest(form.manifest),
    first_seen_at: discovery?.first_seen_at ?? null,
    last_seen_at: discovery?.last_seen_at ?? null,
    encounter_count: discovery?.encounter_count ?? 0,
  };
}

async function atlasSheetUrl(form: Record<string, unknown>): Promise<string> {
  const path = typeof form.sheet_path === "string" ? form.sheet_path : "";
  if (!path || path.includes("..")) return "";
  if (form.source_kind === "expedition") {
    const base = `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/chapter_assets/`;
    return `${base}${path.split("/").map(encodeURIComponent).join("/")}`;
  }
  return await signSheetUrl(db, path);
}

function cardManifest(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const manifest = value as Record<string, unknown>;
  const poses = manifest.poses && typeof manifest.poses === "object" && !Array.isArray(manifest.poses)
    ? manifest.poses as Record<string, unknown>
    : {};
  return {
    frame_size: manifest.frame_size ?? [],
    sheet_size: manifest.sheet_size ?? [],
    poses: { idle: poses.idle ?? {} },
    render_metrics: manifest.render_metrics ?? {},
  };
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

  const { data: formThumbRows, error: formThumbError } = await db
    .from("atlas_forms")
    .select("thumb_path")
    .eq("anima_id", animaId)
    .not("thumb_path", "is", null);
  if (formThumbError) throw formThumbError;
  const thumbPaths = [...new Set([
    entry.thumb_path,
    ...(formThumbRows ?? []).map((row) => row.thumb_path),
  ].filter((path): path is string => typeof path === "string" && path.length > 0))];
  const { error: updateError } = await db
    .from("gallery_entries")
    .update({ published: false, thumb_path: null, updated_at: new Date().toISOString() })
    .eq("id", entry.id);
  if (updateError) throw updateError;
  const { error: clearError } = await db
    .from("atlas_forms")
    .update({ thumb_path: null, updated_at: new Date().toISOString() })
    .eq("anima_id", animaId);
  if (clearError) throw clearError;

  await Promise.all(thumbPaths.map((path) => removeThumb(db, path)));
  return json(200, { unpublished: true, entry_id: entry.id });
}

async function reportEntry(ownerId: string, body: GalleryBody): Promise<Response> {
  const entryId = asUuid(body.entry_id, "entry_id");
  const { data: entry, error } = await db
    .from("gallery_entries")
    .select("id, owner_id, published, auto_hidden, report_count")
    .eq("id", entryId)
    .maybeSingle();
  if (error) throw error;
  if (!entry || !entry.published || entry.auto_hidden || entry.owner_id === ownerId) {
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
  const { data: entry, error: entryError } = await db
    .from("gallery_entries")
    .select("id")
    .eq("id", entryId)
    .eq("published", true)
    .eq("moderation_status", "approved")
    .eq("auto_hidden", false)
    .maybeSingle();
  if (entryError) throw entryError;
  if (!entry) throw new Error("GALLERY_ENTRY_NOT_FOUND");

  const { error: hideError } = await db.from("gallery_hidden").upsert({
    owner_id: ownerId,
    entry_id: entryId,
  }, { onConflict: "owner_id,entry_id", ignoreDuplicates: true });
  if (hideError) throw hideError;

  const { data: forms, error: formsError } = await db
    .from("atlas_forms")
    .select("id")
    .eq("publication_id", entryId);
  if (formsError) throw formsError;
  const formIds = (forms ?? []).map((row) => String(row.id));
  if (formIds.length > 0) {
    const { error: discoveryError } = await db
      .from("seeker_atlas_discoveries")
      .delete()
      .eq("owner_id", ownerId)
      .in("form_id", formIds);
    if (discoveryError) throw discoveryError;
  }

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

function parseFilter(value: unknown): string {
  if (value === undefined || value === null || value === "") return "all";
  if (typeof value !== "string" || !FILTERS.has(value)) throw new Error("INVALID_FILTER");
  return value;
}

function parseCursor(value: unknown): { last_seen_at: string; id: string } | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") throw new Error("INVALID_CURSOR");
  try {
    const decoded = JSON.parse(atob(value));
    if (
      typeof decoded?.last_seen_at !== "string" ||
      typeof decoded?.id !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(decoded.last_seen_at) ||
      !Number.isFinite(Date.parse(decoded.last_seen_at)) ||
      !UUID_RE.test(decoded.id)
    ) {
      throw new Error("INVALID_CURSOR");
    }
    return { last_seen_at: decoded.last_seen_at, id: decoded.id };
  } catch {
    throw new Error("INVALID_CURSOR");
  }
}

function encodeCursor(lastSeenAt: string, id: string): string {
  return btoa(JSON.stringify({ last_seen_at: lastSeenAt, id }));
}

function parseLegacyCursor(value: unknown): { published_at: string; id: string } | null {
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

function encodeLegacyCursor(publishedAt: string, id: string): string {
  return btoa(JSON.stringify({ published_at: publishedAt, id }));
}
