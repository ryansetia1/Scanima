// Klien service role dan pembungkus respons. Dipakai semua fungsi.
//
// SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY disuntikkan otomatis oleh platform,
// jadi keduanya bukan secret yang perlu kita pasang. Yang perlu dipasang manual
// hanya REPLICATE_API_TOKEN dan REPLICATE_WEBHOOK_SECRET.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL atau SUPABASE_SERVICE_ROLE_KEY tidak tersedia");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
