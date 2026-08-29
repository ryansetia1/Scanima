// Penilaian arah hadap sprite sheet, pure logic. Nol panggilan jaringan — sama
// seperti vision.mjs, hanya perakitan prompt, parsing, dan keputusan. Dipakai
// dua runtime (Deno webhook, Node eval), lihat CLAUDE.md _shared/.
//
// Kontrak yang ditegakkan (backend/prompts/v41/sprite_sheet.md — HORIZONTAL
// FACING LOCK): setiap sel karakter wajib menghadap canvas-left. Modul ini
// tidak memutuskan flip sendirian — dua pass independen harus setuju, lihat
// decideFacingFlips.

import { LAYOUT_3X3 } from "./postprocess.mjs";
import { extractJson, visionInstruction } from "./vision.mjs";

const ROW_NAMES = ["top", "middle", "bottom"];
const COL_NAMES = ["left", "middle", "right"];

/** pose -> nama posisi grid ("idle" -> "top_left", …), diturunkan dari
 * LAYOUT_3X3 supaya tidak diketik ulang dan tidak bisa menyimpang. */
export const FACING_GRID = Object.fromEntries(
  LAYOUT_3X3.poses.map((pose) => {
    const [col, row] = LAYOUT_3X3.quadrant[pose];
    return [pose, `${ROW_NAMES[row]}_${COL_NAMES[col]}`];
  }),
);

const GRID_TO_POSE = Object.fromEntries(
  Object.entries(FACING_GRID).map(([pose, grid]) => [grid, pose]),
);

const CHARACTER_POSES = new Set([
  "idle", "attack", "sleep", "happy", "hungry", "dirty", "defeated",
]);
const VFX_MOTION_AUDITABLE = new Set(["projectile", "sweep"]);

/** Sel yang boleh dinilai: 7 sel karakter selalu, fx_strike/fx_surge hanya
 * kalau motion-nya punya arah (projectile/sweep) — impact/bloom directionless. */
export function auditableCells(layout, vfxMotion = {}) {
  return layout.poses.filter((pose) => {
    if (CHARACTER_POSES.has(pose)) return true;
    if (pose === "fx_strike" || pose === "fx_surge") {
      return VFX_MOTION_AUDITABLE.has(vfxMotion?.[pose]);
    }
    return false;
  });
}

/** Sama pola dengan visionInstruction(): schema disisipkan ke system
 * instruction karena wrapper Gemini Replicate tidak punya response_schema. */
export function facingInstruction(promptText, schema) {
  return visionInstruction(promptText, schema);
}

/** Parse jawaban Vision (keyed by grid position) jadi verdict per pose,
 * dibatasi ke `allowed`. Pakai extractJson() yang sudah ada, jangan menulis
 * parser JSON kedua. */
export function parseFacingVerdict(raw, allowed) {
  const parsed = extractJson(raw);
  const allowedSet = new Set(allowed);
  const verdict = {};
  for (const [gridPosition, value] of Object.entries(parsed ?? {})) {
    if (value !== "left" && value !== "right" && value !== "unclear") continue;
    const pose = GRID_TO_POSE[gridPosition];
    if (!pose || !allowedSet.has(pose)) continue;
    verdict[pose] = value;
  }
  return verdict;
}

/**
 * PURE. Flip hanya kalau kedua pass menjawab "right" untuk pose yang sama.
 * `unclear` di pass mana pun, atau pass2 absen (null), berarti tidak di-flip.
 */
export function decideFacingFlips(pass1, pass2, allowed) {
  const flipped = [];
  let anyPass1Right = false;
  for (const pose of allowed) {
    if (pass1[pose] !== "right") continue;
    anyPass1Right = true;
    if (pass2 && pass2[pose] === "right") flipped.push(pose);
  }
  const status = !anyPass1Right ? "clean" : flipped.length > 0 ? "applied" : "unconfirmed";
  return {
    flipped,
    record: { status, flipped, pass1, pass2: pass2 ?? null, reason: null },
  };
}
