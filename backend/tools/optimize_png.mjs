#!/usr/bin/env node
// Re-encode PNG yang sudah ter-commit lewat encoder kanonis di
// `functions/_shared/png.mjs`. Nol panggilan API dan nol perubahan piksel yang
// terlihat: hanya filter scanline, level deflate, dan RGB di bawah alpha 0.
//
//   node backend/tools/optimize_png.mjs            # preview, tidak menulis
//   node backend/tools/optimize_png.mjs --apply    # tulis ulang di tempat
//   node backend/tools/optimize_png.mjs --check    # exit 1 kalau masih bisa kecil
//   node backend/tools/optimize_png.mjs [--apply] <path...>
//
// Preview sebagai default mengikuti `chapter_factory.mjs ingest-manual`.
//
// TARGETS sengaja pendek. Isi `backend/chapters/<slug>/v<n>/` TIDAK boleh masuk:
// `assets/` adalah binary immutable yang hash-nya tercatat di manifest terpublish
// dan ledger activation, sedangkan `raw/` serta `manual_inbox/` adalah provenance
// input/output hash. Mengecilkan byte-nya akan memutus verifikasi hash yang
// justru menjadi alasan folder itu ada. Chapter berikutnya sudah lahir optimal
// karena Chapter Factory memakai encoder yang sama.

import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";
import { Image } from "imagescript";
import { encodeImage } from "../supabase/functions/_shared/png.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

export const COMMITTED_PNG_TARGETS = [
  "game/assets/catalog/food_sheet.png",
  "game/assets/catalog/item_sheet.png",
  "game/assets/seekers/androgynous.png",
  "game/assets/seekers/masculine.png",
  "game/assets/seekers/feminine.png",
  "game/assets/seekers/automaton.png",
  "backend/tools/chapter_factory/static/point-hex-vessel.png",
];

/**
 * Bandingkan hanya piksel yang benar-benar tergambar. RGB di bawah alpha 0 boleh
 * berubah — itu justru salah satu penghematannya — tetapi alpha dan warna yang
 * terlihat harus identik byte demi byte.
 */
function visibleDrift(before, after) {
  if (before.length !== after.length) return before.length;
  let drift = 0;
  for (let i = 0; i < before.length; i += 4) {
    if (before[i + 3] !== after[i + 3]) {
      drift += 1;
      continue;
    }
    if (before[i + 3] === 0) continue;
    if (
      before[i] !== after[i] ||
      before[i + 1] !== after[i + 1] ||
      before[i + 2] !== after[i + 2]
    ) {
      drift += 1;
    }
  }
  return drift;
}

export async function optimizePngFile(path, { apply = false } = {}) {
  const original = await readFile(path);
  const decoded = await Image.decode(original);
  const before = Uint8Array.from(decoded.bitmap);

  const optimized = await encodeImage(decoded);
  const roundTrip = await Image.decode(optimized);
  const drift = visibleDrift(before, roundTrip.bitmap);
  const saved = original.length - optimized.length;

  if (drift > 0) {
    return { path, drift, saved: 0, before: original.length, after: original.length, written: false };
  }
  const written = apply && saved > 0;
  if (written) await writeFile(path, optimized);
  return {
    path,
    drift: 0,
    saved: saved > 0 ? saved : 0,
    before: original.length,
    after: saved > 0 ? optimized.length : original.length,
    written,
  };
}

function formatKilobytes(bytes) {
  return `${(bytes / 1024).toFixed(1)} KB`;
}

async function main() {
  const argv = process.argv.slice(2);
  const apply = argv.includes("--apply");
  const check = argv.includes("--check");
  const explicit = argv.filter((value) => !value.startsWith("--"));
  const targets = explicit.length > 0
    ? explicit
    : COMMITTED_PNG_TARGETS.map((entry) => join(ROOT, entry));

  let before = 0;
  let after = 0;
  let shrinkable = 0;
  let broken = 0;

  for (const path of targets) {
    const result = await optimizePngFile(path, { apply });
    before += result.before;
    after += result.after;
    if (result.drift > 0) broken += 1;
    if (result.saved > 0) shrinkable += 1;
    const label = relative(ROOT, path);
    if (result.drift > 0) {
      console.log(`  ${label}: DITOLAK, ${result.drift} piksel terlihat berubah`);
    } else if (result.saved === 0) {
      console.log(`  ${label}: sudah optimal (${formatKilobytes(result.before)})`);
    } else {
      const verb = result.written ? "ditulis" : "bisa";
      const percent = ((100 * result.saved) / result.before).toFixed(1);
      console.log(
        `  ${label}: ${verb} ${formatKilobytes(result.before)} -> ` +
          `${formatKilobytes(result.after)} (-${percent}%)`,
      );
    }
  }

  const savedTotal = before - after;
  console.log(
    `\n${targets.length} berkas: ${formatKilobytes(before)} -> ${formatKilobytes(after)} ` +
      `(-${formatKilobytes(savedTotal)})`,
  );
  if (broken > 0) {
    console.error("optimize_png: ada berkas yang tidak lossless, tidak ada yang ditulis");
    process.exit(1);
  }
  if (check && shrinkable > 0) {
    console.error(
      `optimize_png: ${shrinkable} berkas masih bisa dikecilkan. ` +
        "Jalankan `node backend/tools/optimize_png.mjs --apply`.",
    );
    process.exit(1);
  }
  if (!apply && !check && shrinkable > 0) {
    console.log("Preview saja. Tambahkan --apply untuk menulisnya.");
  }
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
