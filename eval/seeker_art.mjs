// Empat Seeker Sheet placeholder untuk Seeker Roster, digambar lokal. NOL API.
//
//   node eval/seeker_art.mjs
//
// Sengaja tidak ada mode berbayar di sini. Art final adalah tiket terpisah yang
// dijalankan paling akhir — satu generation per figur, tanpa retry — supaya
// picker, Profile, dan penempatan arena sudah terbukti benar dengan placeholder
// sebelum satu sen pun dibelanjakan.
//
// Kontrak sheet-nya milik SeekerSheet dan tidak boleh bergeser di sini: 1024×1024,
// grid 3×3 sel 341px, jendela capture 300px per sel, sembilan pose dengan nama
// yang sama seperti Boss Seeker, chroma green yang lalu dikeying.

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Image } from "imagescript";
import { isKeyColor, softenAlphaEdges } from "../backend/supabase/functions/_shared/postprocess.mjs";
import { encodeImage } from "../backend/supabase/functions/_shared/png.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = join(ROOT, "game/assets/seekers");
const SIZE = 1024;
const CELL = 341;
const GREEN = [0, 255, 0, 255];
const BASELINE = CELL - 14;

// Urutan sel adalah SeekerSheet.KNOWN_POSES dibaca baris demi baris, sama
// dengan manifest Boss Seeker chapter. Tiap pose punya gerak tangan dan tinggi
// badan yang berbeda supaya pemetaan pose yang tertukar terlihat mata, bukan
// hanya terbaca sebagai sembilan kotak yang mirip.
//
// Sudut tangan dihitung dari lurus ke bawah, memutar ke arah canvas-left: 0
// menggantung, 90 lurus ke depan, 180 lurus ke atas, negatif ke belakang.
const POSES = [
  { name: "intro_idle", arms: [14, -10], legs: 1.0, torso: 1.0, spread: 30, lean: 0 },
  { name: "attack_command", arms: [92, 26], legs: 0.98, torso: 1.0, spread: 44, lean: 7 },
  { name: "special_command", arms: [168, -80], legs: 1.0, torso: 1.0, spread: 34, lean: 0 },
  { name: "switch_command", arms: [48, 118], legs: 0.99, torso: 1.0, spread: 36, lean: 3 },
  { name: "concern_hit", arms: [-42, -58], legs: 0.9, torso: 0.96, spread: 26, lean: -12 },
  { name: "last_anima", arms: [176, -12], legs: 1.03, torso: 1.0, spread: 32, lean: 0 },
  { name: "victory", arms: [150, -150], legs: 0.95, torso: 1.0, spread: 12, lean: 0 },
  { name: "defeat", arms: [24, -18], legs: 0.44, torso: 0.86, spread: 22, lean: 15 },
  { name: "profile", bust: true },
];

// Empat figur roster. Yang androgini adalah default dan digambar dengan tingkat
// detail yang sama seperti tiga lainnya — ia anggota roster yang dipilih, bukan
// siluet sisa (ADR-0001).
const FIGURES = [
  {
    slug: "androgynous",
    legs: 112,
    torso: 96,
    head: 27,
    shoulder: 66,
    hip: 52,
    hair: "bob",
    body: [86, 196, 214],
    shade: [46, 132, 156],
    accent: [248, 214, 122],
    skin: [232, 194, 168],
  },
  {
    slug: "masculine",
    legs: 118,
    torso: 100,
    head: 28,
    shoulder: 84,
    hip: 58,
    hair: "crop",
    body: [104, 116, 226],
    shade: [58, 66, 158],
    accent: [252, 186, 96],
    skin: [214, 166, 132],
  },
  {
    slug: "feminine",
    legs: 110,
    torso: 92,
    head: 26,
    shoulder: 56,
    hip: 44,
    hair: "long",
    skirt: 74,
    body: [222, 104, 178],
    shade: [150, 52, 118],
    accent: [250, 226, 158],
    skin: [240, 202, 176],
  },
  {
    slug: "automaton",
    legs: 116,
    torso: 98,
    head: 25,
    shoulder: 76,
    hip: 56,
    hair: "none",
    visor: true,
    body: [178, 186, 202],
    shade: [104, 114, 134],
    accent: [252, 166, 62],
    skin: [148, 158, 176],
  },
];

const OUTLINE = [22, 26, 40];

async function main() {
  await mkdir(OUT_DIR, { recursive: true });
  for (const figure of FIGURES) {
    const img = new Image(SIZE, SIZE);
    img.fill(GREEN);
    POSES.forEach((pose, index) => {
      drawCell(img, (index % 3) * CELL, Math.trunc(index / 3) * CELL, figure, pose, index);
    });
    keyGreen(img);
    await writeFile(join(OUT_DIR, `${figure.slug}.png`), await encodeImage(img));
    console.log("wrote", `${figure.slug}.png`);
  }
  console.log("seeker roster placeholders written to", OUT_DIR);
}

function drawCell(img, ox, oy, figure, pose, index) {
  if (pose.bust) {
    drawBust(img, ox, oy, figure, index);
    return;
  }
  const legs = Math.round(figure.legs * pose.legs);
  const torso = Math.round(figure.torso * pose.torso);
  const cx = ox + CELL / 2;
  const hipY = oy + BASELINE - legs;
  const shoulderY = hipY - torso;
  const leanX = cx - pose.lean;

  // Kaki lebih dulu, lalu badan, lalu tangan depan: outline tiap bagian ikut
  // digambar tepat sebelum isinya supaya cel line-nya tidak saling menimpa.
  for (const side of [-1, 1]) {
    const footX = cx + (side * pose.spread) / 2;
    strokeLine(img, cx + (side * figure.hip) / 4, hipY, footX, oy + BASELINE, 20, OUTLINE);
    strokeLine(img, cx + (side * figure.hip) / 4, hipY, footX, oy + BASELINE, 14, figure.shade);
  }
  drawArm(img, leanX + figure.shoulder / 2, shoulderY + 10, pose.arms[1], figure, 78);
  if (figure.skirt) {
    trapezoid(img, cx, hipY - 26, figure.hip + 10, hipY + 30, figure.skirt + 8, OUTLINE);
    trapezoid(img, cx, hipY - 22, figure.hip + 2, hipY + 26, figure.skirt, figure.body);
  }
  trapezoid(img, leanX, shoulderY - 4, figure.shoulder + 9, hipY + 4, figure.hip + 9, OUTLINE, cx);
  trapezoid(img, leanX, shoulderY, figure.shoulder, hipY, figure.hip, figure.body, cx);
  drawChestPips(img, leanX, shoulderY + 26, index, figure);
  drawArm(img, leanX - figure.shoulder / 2, shoulderY + 10, pose.arms[0], figure, 78);
  drawHead(img, leanX - pose.lean, shoulderY - figure.head - 8, figure, figure.head, 1);
}

function drawBust(img, ox, oy, figure, index) {
  const cx = ox + CELL / 2;
  const shoulderY = oy + 176;
  const scale = 1.85;
  trapezoid(img, cx, shoulderY - 4, figure.shoulder * scale + 10, oy + BASELINE, figure.shoulder * scale + 34, OUTLINE);
  trapezoid(img, cx, shoulderY, figure.shoulder * scale, oy + BASELINE, figure.shoulder * scale + 24, figure.body);
  drawChestPips(img, cx, shoulderY + 44, index, figure);
  drawHead(img, cx, shoulderY - figure.head * scale - 10, figure, Math.round(figure.head * scale), scale);
}

function drawHead(img, cx, cy, figure, radius, scale) {
  if (figure.visor) {
    fillRect(img, cx - radius - 4, cy - radius - 2, radius * 2 + 8, radius * 2 + 8, OUTLINE);
    fillRect(img, cx - radius, cy - radius + 2, radius * 2, radius * 2, figure.skin);
    fillRect(img, cx - radius + 3, cy - 4, radius * 2 - 10, Math.max(6, radius / 2), OUTLINE);
    fillRect(img, cx - radius + 5, cy - 2, radius - 2, Math.max(3, radius / 4), figure.accent);
    strokeLine(img, cx + 2, cy - radius - 2, cx + 2, cy - radius - 8 - radius / 2, 7, OUTLINE);
    strokeLine(img, cx + 2, cy - radius - 2, cx + 2, cy - radius - 8 - radius / 2, 4, figure.shade);
    fillCircle(img, cx + 2, cy - radius - 10 - radius / 2, 7, OUTLINE);
    fillCircle(img, cx + 2, cy - radius - 10 - radius / 2, 5, figure.accent);
    return;
  }
  if (figure.hair === "long") {
    fillCircle(img, cx, cy + radius / 3, radius + 12, OUTLINE);
    fillCircle(img, cx, cy + radius / 3, radius + 8, figure.shade);
  }
  fillCircle(img, cx, cy, radius + 4, OUTLINE);
  fillCircle(img, cx, cy, radius, figure.skin);
  // Rambut sebagai tutup di atas kepala, bukan lingkaran penuh, supaya wajahnya
  // tetap terlihat dan arah hadap terbaca.
  const cap = figure.hair === "crop" ? radius - 6 : radius - 2;
  fillCircle(img, cx, cy - 6, radius, figure.shade);
  fillRect(img, cx - radius, cy - 2, radius * 2, radius, figure.skin);
  fillCircle(img, cx - 2, cy + 2, cap, figure.skin);
  const eye = Math.max(3, Math.round(4 * scale));
  fillRect(img, cx - radius / 2 - eye, cy + 2, eye, eye + 1, OUTLINE);
  fillRect(img, cx + radius / 6, cy + 2, eye, eye + 1, OUTLINE);
}

function drawArm(img, sx, sy, degrees, figure, length) {
  const radians = (degrees * Math.PI) / 180;
  const hx = sx - Math.sin(radians) * length;
  const hy = sy + Math.cos(radians) * length;
  strokeLine(img, sx, sy, hx, hy, 20, OUTLINE);
  strokeLine(img, sx, sy, hx, hy, 14, figure.body);
  fillCircle(img, hx, hy, 11, OUTLINE);
  fillCircle(img, hx, hy, 8, figure.skin);
}

// Penanda indeks pose dibaca manusia, dan sengaja duduk DI DALAM badan: taruh
// di margin sel dan ia akan ikut ke dalam bbox opak, lalu render_metrics milik
// intro_idle — dasar skala arena — mengukur pip, bukan tinggi badan.
function drawChestPips(img, cx, cy, index, figure) {
  const count = index + 1;
  for (let i = 0; i < count; i += 1) {
    const row = Math.trunc(i / 5);
    const col = i % 5;
    const wide = Math.min(count, 5);
    const x = cx - (wide * 9) / 2 + col * 9;
    fillRect(img, x, cy + row * 9, 6, 6, figure.accent);
  }
}

function trapezoid(img, cx, topY, topWidth, bottomY, bottomWidth, color, clampCx = null) {
  const height = Math.max(1, Math.round(bottomY - topY));
  for (let i = 0; i <= height; i += 1) {
    const t = i / height;
    const width = topWidth + (bottomWidth - topWidth) * t;
    // Badan yang membungkuk memiringkan bahu, tetapi pinggulnya tetap di atas
    // kaki: pusat tiap baris di-interpolasi dari bahu ke pinggul.
    const center = clampCx === null ? cx : cx + (clampCx - cx) * t;
    fillRect(img, center - width / 2, topY + i, width, 1, color);
  }
}

function strokeLine(img, x0, y0, x1, y1, thickness, color) {
  const steps = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0)));
  for (let i = 0; i <= steps; i += 1) {
    const t = i / steps;
    fillCircle(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, thickness / 2, color);
  }
}

function fillCircle(img, cx, cy, radius, color) {
  const r = Math.max(1, Math.round(radius));
  const rr = r * r;
  for (let y = -r; y <= r; y += 1) {
    for (let x = -r; x <= r; x += 1) {
      if (x * x + y * y <= rr) put(img, cx + x, cy + y, color);
    }
  }
}

function fillRect(img, x, y, w, h, color) {
  for (let yy = 0; yy < Math.round(h); yy += 1) {
    for (let xx = 0; xx < Math.round(w); xx += 1) put(img, x + xx, y + yy, color);
  }
}

function put(img, x, y, color) {
  const px = Math.round(x);
  const py = Math.round(y);
  if (px < 0 || py < 0 || px >= SIZE || py >= SIZE) return;
  const o = (py * SIZE + px) * 4;
  img.bitmap[o] = color[0];
  img.bitmap[o + 1] = color[1];
  img.bitmap[o + 2] = color[2];
  img.bitmap[o + 3] = color[3] ?? 255;
}

function keyGreen(img) {
  const bitmap = img.bitmap;
  for (let i = 0; i < SIZE * SIZE; i += 1) {
    const o = i * 4;
    if (bitmap[o + 3] < 8) continue;
    if (!isKeyColor(bitmap[o], bitmap[o + 1], bitmap[o + 2])) continue;
    bitmap[o] = 0;
    bitmap[o + 1] = 0;
    bitmap[o + 2] = 0;
    bitmap[o + 3] = 0;
  }
  softenAlphaEdges(bitmap, SIZE, SIZE);
}

await main();
