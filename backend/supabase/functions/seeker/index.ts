// Boundary tunggal untuk profil Seeker, upgrade Google, dan penghapusan akun.
// owner_id selalu berasal dari JWT terverifikasi, tidak pernah dari body.

import { adminClient, clientVersionGate, corsPreflight, json } from "../_shared/supa.ts";

const db = adminClient();
const OPERATIONS = new Set(["profile", "complete", "rename", "upgrade", "delete_account"]);
const ERROR_STATUS: Record<string, number> = {
  INVALID_SEEKER_NAME: 400,
  SEEKER_NAME_RESERVED: 400,
  INVALID_BIRTH_YEAR: 400,
  INVALID_GENDER: 400,
  SEEKER_PROFILE_INCOMPLETE: 409,
  SEEKER_PROFILE_COMPLETE: 409,
  SEEKER_NAME_TAKEN: 409,
  SEEKER_NAME_COOLDOWN: 409,
  ACCOUNT_STILL_ANONYMOUS: 409,
  GOOGLE_IDENTITY_REQUIRED: 409,
  AUTH_USER_NOT_FOUND: 404,
  NO_PROFILE: 404,
};

type SeekerBody = {
  operation?: unknown;
  seeker_name?: unknown;
  birth_year?: unknown;
  gender?: unknown;
  seeker_avatar?: unknown;
  confirmation?: unknown;
};

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

  let body: SeekerBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const operation = typeof body.operation === "string" ? body.operation : "";
  if (!OPERATIONS.has(operation)) return json(400, { error: "operation tidak dikenal" });

  try {
    if (operation === "profile") {
      const { data, error } = await db.rpc("seeker_profile_summary", { p_owner: ownerId });
      if (error) throw error;
      const summary = data && typeof data === "object"
        ? data as Record<string, unknown>
        : {};
      const currentConfig = summary.client_config && typeof summary.client_config === "object"
        ? summary.client_config as Record<string, unknown>
        : {};
      const { data: configRows, error: flagError } = await db
        .from("app_config")
        .select("key, value")
        .in("key", ["feature_evolution", "feature_synthesis", "synthesis_min_level"]);
      if (flagError) throw flagError;
      const appConfig = Object.fromEntries(
        (configRows ?? []).map((row) => [row.key, row.value]),
      );
      summary.client_config = {
        ...currentConfig,
        feature_evolution: appConfig.feature_evolution === true,
        feature_synthesis: appConfig.feature_synthesis === true,
        // Gerbang Level Source hidup di server; client hanya menirunya supaya
        // Anima yang pasti ditolak tidak muncul sebagai pilihan.
        synthesis_min_level: Number(appConfig.synthesis_min_level ?? 10),
      };
      return json(200, summary);
    }
    if (operation === "complete") {
      const seekerName = typeof body.seeker_name === "string" ? body.seeker_name : "";
      const birthYear = body.birth_year === null || body.birth_year === undefined
        ? null
        : Number(body.birth_year);
      const gender = body.gender === null || body.gender === undefined || body.gender === ""
        ? null
        : String(body.gender);
      if (!Number.isInteger(birthYear) && birthYear !== null) {
        return json(400, { error: "INVALID_BIRTH_YEAR" });
      }
      // Kosmetik dan opsional: null berarti pemain tidak menyentuh picker, dan
      // RPC memperlakukannya sebagai "biarkan apa adanya". Nilai di luar Seeker
      // Roster diabaikan di sana, bukan ditolak, supaya satu figur asing tidak
      // bisa menahan pemain di luar namanya sendiri.
      const avatar = typeof body.seeker_avatar === "string" && body.seeker_avatar !== ""
        ? body.seeker_avatar
        : null;
      return await rpc("complete_seeker_profile", {
        p_owner: ownerId,
        p_name: seekerName,
        p_birth_year: birthYear,
        p_gender: gender,
        p_avatar: avatar,
      });
    }
    if (operation === "rename") {
      return await rpc("rename_seeker", {
        p_owner: ownerId,
        p_name: typeof body.seeker_name === "string" ? body.seeker_name : "",
      });
    }
    if (operation === "upgrade") {
      return await rpc("upgrade_seeker_account", { p_owner: ownerId });
    }

    if (body.confirmation !== "DELETE") return json(400, { error: "DELETE_CONFIRMATION_REQUIRED" });
    const { data: userRow } = await db.auth.admin.getUserById(ownerId);
    if (userRow.user?.is_anonymous) throw new Error("ACCOUNT_STILL_ANONYMOUS");
    const { error } = await db.auth.admin.deleteUser(ownerId);
    if (error) throw error;
    return json(200, { deleted: true });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : String(error);
    const marker = Object.keys(ERROR_STATUS).find((candidate) => message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("operasi Seeker gagal", error);
    return json(500, { error: "seeker gagal diproses" });
  }
});

async function rpc(name: string, args: Record<string, unknown>): Promise<Response> {
  const { data, error } = await db.rpc(name, args);
  if (error) throw error;
  return json(200, data);
}
