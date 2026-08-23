// Bagian gallery yang aman di Node eval dan Edge Deno (tanpa Replicate).
import { Image } from "imagescript";
import { extractJson } from "./vision.mjs";
import { encodeImage } from "./png.mjs";
export {
  BATTLE_SHEET_SIGNED_TTL,
  GALLERY_REPORT_AUTO_HIDE,
  THUMB_SIGNED_TTL,
} from "./gallery_constants.mjs";

/** Crop region Idle dari manifest post-process; fallback ke sel kiri-atas grid. */
export async function cropIdleThumb(pngBuffer, manifest) {
  const decoded = await Image.decode(pngBuffer);
  const poses = manifest?.poses && typeof manifest.poses === "object"
    ? manifest.poses
    : {};
  const idle = poses.idle?.region;
  let x = 0;
  let y = 0;
  let w = Math.floor(decoded.width / 3);
  let h = Math.floor(decoded.height / 3);
  if (Array.isArray(idle) && idle.length === 4) {
    [x, y, w, h] = idle.map((n) => Math.max(0, Math.floor(Number(n) || 0)));
  }
  w = Math.min(w, decoded.width - x);
  h = Math.min(h, decoded.height - y);
  if (w < 8 || h < 8) throw new Error("THUMB_REGION_INVALID");
  const cropped = decoded.crop(x, y, w, h);
  return await encodeImage(cropped);
}

export function parseModeration(raw) {
  const data = extractJson(raw);
  const safe = data?.safe === true;
  const reason = typeof data?.reject_reason === "string"
    ? data.reject_reason.trim().slice(0, 240)
    : "";
  return { safe, reject_reason: safe ? null : (reason || "unsafe_content") };
}

const MODERATION_PASS_CATEGORIES = ["none", "sexual", "gore", "hate", "ip_character"];

/** Fail-closed: JSON yang tidak bisa diparse atau category di luar enum TIDAK
 * PERNAH jatuh ke "none" (approve diam-diam). Ia jatuh ke "ip_character"/low,
 * yang selalu berujung pass 2 (dari pass 1) atau manual case (dari pass 2) —
 * tidak pernah publish tanpa keputusan yang valid. */
export function parseModerationPass(raw, pass) {
  const data = extractJson(raw);
  const validCategory = typeof data?.category === "string" &&
    MODERATION_PASS_CATEGORIES.includes(data.category);
  const category = validCategory ? data.category : "ip_character";
  const confidence = validCategory && data?.confidence === "high" ? "high" : "low";
  const matchedName = typeof data?.matched_name === "string" && data.matched_name.trim()
    ? data.matched_name.trim().slice(0, 120)
    : null;
  const reason = typeof data?.reason === "string" ? data.reason.trim().slice(0, 200) : "";
  return {
    category,
    confidence,
    matched_name: matchedName,
    reason_code: reason || (validCategory ? `${category}_flagged` : "moderation_parse_failed"),
    pass,
  };
}

/** approve | reject | uncertain untuk satu hasil pass. Kategori
 * sexual/gore/hate selalu final di pass 1 (hard safety tidak pernah dapat
 * opini kedua). ip_character selalu ke pass 2 dari pass 1; di pass 2 ia final
 * hanya kalau confidence high DAN ada matched_name konkret — generic
 * suspicion tetap uncertain -> manual case, tidak pernah hard reject. */
export function moderationPassDecision(pass, result) {
  if (result.category === "none") return "approve";
  if (pass === 1) {
    return result.category === "ip_character" ? "uncertain" : "reject";
  }
  if (result.category === "ip_character") {
    return result.confidence === "high" && result.matched_name ? "reject" : "uncertain";
  }
  return "reject";
}

export async function queueStorageCleanup(db, bucketId, objectPath, reason) {
  const { error } = await db.from("storage_cleanup_queue").insert({
    bucket_id: bucketId,
    object_path: objectPath,
    reason,
  });
  if (error) console.error("storage_cleanup_queue insert gagal", error);
}

export async function removeThumb(db, thumbPath) {
  if (!thumbPath) return;
  const { error } = await db.storage.from("gallery_thumbs").remove([thumbPath]);
  if (error) {
    await queueStorageCleanup(
      db,
      "gallery_thumbs",
      thumbPath,
      "unpublish_thumb_failed",
    );
  }
}
