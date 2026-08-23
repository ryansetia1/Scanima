// Staff authorization for admin_moderation. Deno-only (admin edge function
// only consumer); see docs/designs/2026-08-23-atlas-moderation-admin.md.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ROLE_RANK: Record<string, number> = { viewer: 1, moderator: 2, admin: 3 };

export class StaffAuthError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

/** verify_jwt=true membuktikan caller punya sesi Supabase sah; ini hanya
 * mendekode payload yang gateway sudah verifikasi, sama seperti gallery. */
export function verifiedSubject(req: Request): string {
  const jwt = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const payload = jwt.split(".")[1] ?? "";
  if (!payload) return "";
  try {
    const base64 = payload.replaceAll("-", "+").replaceAll("_", "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const claims = JSON.parse(atob(padded));
    return typeof claims.sub === "string" && UUID_RE.test(claims.sub)
      ? claims.sub
      : "";
  } catch {
    return "";
  }
}

/** Gerbang staff yang sebenarnya. Role SATU-SATUNYA sumber kebenaran adalah
 * staff_accounts, dikunci ke auth.users.id terverifikasi — tidak pernah dari
 * metadata pengguna atau email claim JWT. Setiap RPC privileged yang dipanggil
 * sesudah ini MASIH memverifikasi ulang role via moderation_require_role
 * (defense-in-depth, menutup celah TOCTOU antara cek ini dan RPC-nya). */
export async function requireStaff(
  db: SupabaseClient,
  req: Request,
  minRole: "viewer" | "moderator" | "admin" = "viewer",
): Promise<{ userId: string; role: string }> {
  const userId = verifiedSubject(req);
  if (!userId) throw new StaffAuthError("UNAUTHENTICATED", 401);

  const { data, error } = await db
    .from("staff_accounts")
    .select("role")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new StaffAuthError("STAFF_FORBIDDEN", 403);

  const rank = ROLE_RANK[data.role] ?? 0;
  if (rank < ROLE_RANK[minRole]) throw new StaffAuthError("STAFF_FORBIDDEN", 403);
  return { userId, role: data.role };
}
