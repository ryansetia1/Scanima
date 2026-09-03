#!/usr/bin/env node
// Membundel backend/prompts/<versi>/ menjadi satu modul TypeScript yang bisa
// diimpor Edge Function.
//
//   node backend/tools/bundle_prompts.mjs           # tulis ulang bundel
//   node backend/tools/bundle_prompts.mjs --check   # gagal kalau bundel basi
//
// Kenapa ada langkah build sama sekali, padahal aturannya prompt hidup sebagai
// file teks: Deno di Edge Function TIDAK bisa membaca file pendamping yang
// dideploy lewat MCP — Deno.readTextFile() gagal walau file-nya disertakan.
// Menyalin isi prompt ke dalam kode adalah jawaban yang lebih buruk, karena
// salinan itu akan menyimpang dari file yang dipakai eval, dan divergensinya
// baru terlihat saat art produksi berbeda dari art yang sudah kita setujui.
// Jadi: satu sumber di git, satu artefak turunan, dan satu pemeriksaan di
// selftest yang gagal kalau keduanya tidak cocok.
//
// ponytail: bundel diregenerasi manual, bukan lewat hook pre-commit. Plafonnya
// adalah kelupaan; yang menangkapnya adalah `npm run selftest` (gratis, selalu
// dijalankan sebelum apa pun yang berbiaya). Kalau ini pernah lolos ke produksi
// sekali saja, naikkan ke pre-commit hook.

import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const REPO = new URL("../..", import.meta.url).pathname;
const DIR_PROMPT = join(REPO, "backend/prompts");
const KELUARAN = join(REPO, "backend/supabase/functions/_shared/prompts.generated.ts");

// Hanya berkas yang dibutuhkan runtime. vision_schema.json ikut karena ia
// disisipkan ke system_instruction, bukan dikirim sebagai parameter API.
const BERKAS = {
  vision_system: "vision_system.md",
  vision_schema: "vision_schema.json",
  vision_evolve_system: "vision_evolve_system.md",
  vision_evolve_schema: "vision_evolve_schema.json",
  vision_synthesis_system: "vision_synthesis_system.md",
  vision_synthesis_schema: "vision_synthesis_schema.json",
  sprite_sheet: "sprite_sheet.md",
  sprite_sheet_evolve: "sprite_sheet_evolve.md",
  sprite_sheet_synthesis: "sprite_sheet_synthesis.md",
  sprite_sheet_fauna: "sprite_sheet_fauna.md",
  vibe_directions: "vibe_directions.json",
  facing_audit: "facing_audit.md",
  facing_audit_schema: "facing_audit_schema.json",
};

const OPSIONAL = new Set([
  "sprite_sheet_fauna",
  "vision_evolve_system",
  "vision_evolve_schema",
  "vision_synthesis_system",
  "vision_synthesis_schema",
  "sprite_sheet_synthesis",
  "vibe_directions",
  "facing_audit",
  "facing_audit_schema",
]);
const CAPTURE_KEYS = new Set([
  "vision_system",
  "vision_schema",
  "sprite_sheet",
  "sprite_sheet_fauna",
  "vibe_directions",
  "facing_audit",
  "facing_audit_schema",
]);
const CAPTURE_SPRITE_KEYS = new Set(["sprite_sheet", "sprite_sheet_fauna"]);
const LOCAL_CAPTURE_SPRITE_VERSIONS = new Set(["v46", "v47"]);
const CAPTURE_SPRITE_PARENT = new Map([["v48", "v47"]]);
const EVOLVE_KEYS = new Set([
  "vision_evolve_system",
  "vision_evolve_schema",
  "sprite_sheet_evolve",
]);
// ponytail: v24–v30 hanya mengubah evolusi; reuse source capture v20 daripada
// menambah empat salinan byte-identik. Tambahkan versi ke map hanya jika seluruh
// capture contract memang tetap v20.
const CAPTURE_PARENT = new Map([
  ["v24", "v20"],
  ["v25", "v20"],
  ["v26", "v20"],
  ["v27", "v20"],
  ["v28", "v20"],
  ["v29", "v20"],
  ["v30", "v20"],
]);
// v31 mengubah capture saja; evolve production tetap v30.
const EVOLVE_PARENT = new Map([
  ["v31", "v30"],
  ["v42", "v41"],
  ["v43", "v41"],
  ["v44", "v41"],
  ["v45", "v41"],
  ["v46", "v41"],
  ["v48", "v47"],
]);
// v42–v45 hanya mengubah Synthesis; capture/evolve tetap byte-identik v41.
CAPTURE_PARENT.set("v42", "v41");
CAPTURE_PARENT.set("v43", "v41");
CAPTURE_PARENT.set("v44", "v41");
CAPTURE_PARENT.set("v45", "v41");
// v46 memakai fondasi capture v41, tetapi memiliki sprite object/fauna sendiri.
// Pengecualian lokalnya ditangani CAPTURE_SPRITE_KEYS saat memilih parent.
CAPTURE_PARENT.set("v46", "v41");
CAPTURE_PARENT.set("v47", "v41");
CAPTURE_PARENT.set("v48", "v41");
// v43–v45 mengubah planner saja; prompt sheet berbayar tetap persis v42.
const SYNTHESIS_SHEET_PARENT = new Map([
  ["v43", "v42"],
  ["v44", "v42"],
  ["v45", "v42"],
]);
// v46–v48 mengubah sheet Synthesis saja; planner/schema production tetap v45.
const SYNTHESIS_PLANNER_PARENT = new Map([
  ["v46", "v45"],
  ["v47", "v45"],
  ["v48", "v45"],
]);

export async function buildBundle() {
  const versi = (await readdir(DIR_PROMPT, { withFileTypes: true }))
    .filter((d) => d.isDirectory() && /^v\d+$/.test(d.name))
    .map((d) => d.name)
    .sort();

  const bundel = {};
  for (const v of versi) {
    bundel[v] = {};
    for (const [kunci, berkas] of Object.entries(BERKAS)) {
      const captureSpriteParent = CAPTURE_SPRITE_KEYS.has(kunci)
        ? CAPTURE_SPRITE_PARENT.get(v)
        : null;
      const inheritsCapture = CAPTURE_KEYS.has(kunci)
        && !captureSpriteParent
        && !(LOCAL_CAPTURE_SPRITE_VERSIONS.has(v) && CAPTURE_SPRITE_KEYS.has(kunci));
      const parent = captureSpriteParent
        ?? (inheritsCapture
          ? CAPTURE_PARENT.get(v)
        : EVOLVE_KEYS.has(kunci)
          ? EVOLVE_PARENT.get(v)
          : kunci === "sprite_sheet_synthesis"
            ? SYNTHESIS_SHEET_PARENT.get(v)
            : kunci === "vision_synthesis_system" || kunci === "vision_synthesis_schema"
              ? SYNTHESIS_PLANNER_PARENT.get(v)
              : null);
      const jalur = join(DIR_PROMPT, parent ?? v, berkas);
      let isi;
      try {
        isi = await readFile(jalur, "utf8");
      } catch (e) {
        if (OPSIONAL.has(kunci)) continue;
        throw e;
      }
      // Skema di-parse di sini supaya berkas rusak gagal saat build, bukan saat
      // pemain menunggu Anima-nya.
      bundel[v][kunci] = berkas.endsWith(".json") ? JSON.parse(isi) : isi;
    }
  }
  return bundel;
}

export function renderModule(bundel) {
  return (
    "// DIHASILKAN OTOMATIS oleh backend/tools/bundle_prompts.mjs — jangan diedit.\n" +
    "// Sumbernya backend/prompts/<versi>/. Ubah di sana, lalu jalankan:\n" +
    "//   node backend/tools/bundle_prompts.mjs\n" +
    "// npm run selftest gagal kalau berkas ini tidak cocok dengan sumbernya.\n" +
    `export default ${JSON.stringify(bundel, null, 2)} as const;\n`
  );
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split("/").pop())) {
  const modul = renderModule(await buildBundle());
  if (process.argv.includes("--check")) {
    const adaSekarang = await readFile(KELUARAN, "utf8").catch(() => "");
    if (adaSekarang !== modul) {
      console.error("prompts.generated.ts basi, jalankan: node backend/tools/bundle_prompts.mjs");
      process.exit(1);
    }
    console.log("bundel prompt mutakhir");
  } else {
    await writeFile(KELUARAN, modul);
    const versi = Object.keys(await buildBundle());
    console.log(`bundel prompt ditulis: ${versi.join(", ")} -> ${KELUARAN}`);
  }
}
