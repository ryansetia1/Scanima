// POST /shop { item_id, expected_price, idempotency_key }

import { adminClient, clientVersionGate, json } from "../_shared/supa.ts";

const ITEM_RE = /^[a-z][a-z0-9_]{1,62}$/;

const ERROR_STATUS: Record<string, number> = {
  INVALID_IDEMPOTENCY_KEY: 400,
  INVALID_ITEM: 400,
  IDEMPOTENCY_CONFLICT: 409,
  PRICE_CHANGED: 409,
  NO_BITS: 409,
  STACK_FULL: 409,
  NO_PROFILE: 404,
};

type ShopBody = {
  item_id?: unknown;
  expected_price?: unknown;
  idempotency_key?: unknown;
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

  let body: ShopBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const itemId = typeof body.item_id === "string" ? body.item_id : "";
  const price = typeof body.expected_price === "number" ? body.expected_price : NaN;
  const key = typeof body.idempotency_key === "string" ? body.idempotency_key : "";
  if (!ITEM_RE.test(itemId)) return json(400, { error: "INVALID_ITEM" });
  if (!Number.isInteger(price) || price <= 0) return json(400, { error: "PRICE_CHANGED" });
  if (!key || key.length > 128) return json(400, { error: "INVALID_IDEMPOTENCY_KEY" });

  const { data, error } = await db.rpc("purchase_catalog_item", {
    p_owner: ownerId,
    p_item_id: itemId,
    p_expected_price: price,
    p_key: key,
  });
  if (error) {
    const marker = Object.keys(ERROR_STATUS).find((candidate) => error.message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("purchase_catalog_item gagal", error);
    return json(500, { error: "pembelian gagal diproses" });
  }
  return json(200, data);
});
