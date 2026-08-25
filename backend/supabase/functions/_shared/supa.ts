// Klien service role dan pembungkus respons. Dipakai semua fungsi.
//
// SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY disuntikkan otomatis oleh platform,
// jadi keduanya bukan secret yang perlu kita pasang. Yang perlu dipasang manual
// hanya REPLICATE_API_TOKEN dan REPLICATE_WEBHOOK_SECRET.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const CLIENT_PLATFORMS = new Set(["android", "ios", "desktop"]);
let minClientCache: Record<string, number> | null = null;
let minClientCacheUntil = 0;

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL atau SUPABASE_SERVICE_ROLE_KEY tidak tersedia");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function timezoneOffsetMinutes(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value)) return null;
  if (value < -840 || value > 840) return null;
  return value;
}

export async function syncProfileTimezone(
  db: SupabaseClient,
  ownerId: string,
  value: unknown,
): Promise<void> {
  const offset = timezoneOffsetMinutes(value);
  if (offset === null) return;
  const { error } = await db.rpc("set_profile_timezone", {
    p_owner: ownerId,
    p_offset_minutes: offset,
  });
  if (error) console.error("set_profile_timezone gagal", error);
}

export async function clientVersionGate(
  req: Request,
  db: SupabaseClient,
): Promise<Response | null> {
  const now = Date.now();
  if (!minClientCache || now >= minClientCacheUntil) {
    const { data, error } = await db
      .from("app_config")
      .select("value")
      .eq("key", "min_client_version")
      .maybeSingle();
    if (error) {
      // Config failure must not brick every authenticated operation.
      console.error("min_client_version gagal dibaca", error);
      return null;
    }
    const raw = data?.value && typeof data.value === "object"
      ? data.value as Record<string, unknown>
      : {};
    minClientCache = {
      android: Math.max(0, Number(raw.android) || 0),
      ios: Math.max(0, Number(raw.ios) || 0),
      desktop: Math.max(0, Number(raw.desktop) || 0),
    };
    minClientCacheUntil = now + 30_000;
  }

  const minimums = minClientCache;
  if (!minimums || Math.max(...Object.values(minimums)) <= 0) return null;

  const platform = (req.headers.get("x-scanima-platform") ?? "").toLowerCase();
  const buildText = req.headers.get("x-scanima-build") ?? "";
  const build = Number(buildText);
  if (
    !CLIENT_PLATFORMS.has(platform) ||
    !Number.isInteger(build) ||
    build < (minimums[platform] ?? 0)
  ) {
    return json(426, {
      error: "CLIENT_OUTDATED",
      min_client_version: minimums,
    });
  }
  return null;
}

// Browser (web export) preflights every POST with a non-simple Content-Type.
// Native mobile clients skip CORS entirely, so this went unnoticed until web.
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-scanima-build, x-scanima-platform",
};

export function corsPreflight(req: Request): Response | null {
  return req.method === "OPTIONS" ? new Response(null, { status: 204, headers: CORS_HEADERS }) : null;
}

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

export async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(data).buffer);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
