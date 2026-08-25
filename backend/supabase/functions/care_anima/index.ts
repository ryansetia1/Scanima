// POST /care_anima { anima_id, action, idempotency_key? }
//
// Semua aturan care hidup di satu transaksi Postgres. Edge Function ini hanya
// memverifikasi identitas dari JWT, memvalidasi bentuk request, lalu meneruskan
// uid tersebut ke RPC service-role. Client tidak pernah boleh memilih owner_id.

import { adminClient, clientVersionGate, corsPreflight, json, syncProfileTimezone } from "../_shared/supa.ts";

const ACTIONS = new Set(["sync", "feed", "clean", "sleep", "wake", "play", "summon", "use_item"]);
const MUTATING = new Set(["feed", "clean", "sleep", "wake", "play", "summon", "use_item"]);
const ITEM_RE = /^[a-z][a-z0-9_]{1,62}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ERROR_STATUS: Record<string, number> = {
  UNKNOWN_ACTION: 400,
  INVALID_IDEMPOTENCY_KEY: 400,
  IDEMPOTENCY_CONFLICT: 409,
  ANIMA_NOT_FOUND: 404,
  ANIMA_NOT_READY: 409,
  NO_PROFILE: 404,
  NO_BITS: 409,
  NO_ITEM: 409,
  NO_ENERGY: 409,
  INVALID_ITEM: 400,
  PRICE_CHANGED: 409,
  STACK_FULL: 409,
  BOND_FULL: 409,
  NEED_FULL: 409,
  ALREADY_SLEEPING: 409,
  NOT_SLEEPING: 409,
};

type CareBody = {
  anima_id?: unknown;
  action?: unknown;
  idempotency_key?: unknown;
  item_id?: unknown;
  timezone_offset_minutes?: unknown;
};

// Satu client per isolate mempertahankan cache JWKS getClaims() pada request hangat.
const db = adminClient();

Deno.serve(async (req) => {
  const preflight = corsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await db.auth.getClaims(token);
  const ownerId = auth?.claims?.sub;
  if (authError || typeof ownerId !== "string") return json(401, { error: "token tidak sah" });

  let body: CareBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const animaId = typeof body.anima_id === "string" ? body.anima_id : "";
  const action = typeof body.action === "string" ? body.action : "";
  const key = typeof body.idempotency_key === "string" ? body.idempotency_key : null;
  const itemId = typeof body.item_id === "string" ? body.item_id : "";

  if (!UUID_RE.test(animaId)) return json(400, { error: "anima_id tidak sah" });
  if (!ACTIONS.has(action)) return json(400, { error: "action tidak dikenal" });
  if (MUTATING.has(action) && (!key || key.length > 128)) {
    return json(400, { error: "idempotency_key wajib, maks 128 char" });
  }
  if ((action === "feed" || action === "use_item") && !ITEM_RE.test(itemId)) {
    return json(400, { error: "INVALID_ITEM" });
  }

  await syncProfileTimezone(db, ownerId, body.timezone_offset_minutes);

  const payload: Record<string, unknown> = {
    p_owner: ownerId,
    p_anima_id: animaId,
    p_action: action,
    p_key: key,
  };
  if (action === "feed" || action === "use_item") payload.p_item_id = itemId;

  const { data, error } = await db.rpc("apply_care", payload);

  if (error) {
    const marker = Object.keys(ERROR_STATUS).find((candidate) => error.message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("apply_care gagal", error);
    return json(500, { error: "care gagal diproses" });
  }

  return json(200, data);
});
