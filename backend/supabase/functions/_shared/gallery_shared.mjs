// Bagian gallery yang aman di Node eval dan Edge Deno (tanpa Replicate).
import { Image } from "imagescript";
import { extractJson } from "./vision.mjs";

export const GALLERY_REPORT_AUTO_HIDE = 3;
export const THUMB_SIGNED_TTL = 300;
export const BATTLE_SHEET_SIGNED_TTL = 900;

/** Crop region Idle dari manifest post-process; fallback ke sel kiri-atas grid. */
export async function cropIdleThumb(pngBuffer, manifest) {
  const decoded = await Image.decode(pngBuffer);
  const poses = manifest?.poses && typeof manifest.poses === "object" ? manifest.poses : {};
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
  return await cropped.encode(1);
}

export function parseModeration(raw) {
  const data = extractJson(raw);
  const safe = data?.safe === true;
  const reason = typeof data?.reject_reason === "string"
    ? data.reject_reason.trim().slice(0, 240)
    : "";
  return { safe, reject_reason: safe ? null : (reason || "unsafe_content") };
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
    await queueStorageCleanup(db, "gallery_thumbs", thumbPath, "unpublish_thumb_failed");
  }
}
