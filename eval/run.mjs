#!/usr/bin/env node
// Harness evaluasi prompt Scanima: foto -> Vision LLM -> GPT Image 2 ->
// post-processing -> contact sheet HTML.
//
//   node eval/run.mjs --set smoke              # 5 foto, ~$0.23
//   node eval/run.mjs --set full               # 20 foto, ~$1.32
//   node eval/run.mjs --photo eval/photos/mouse.jpg
//   node eval/run.mjs --set smoke --dry-run    # gratis: cek foto & prompt saja
//   node eval/run.mjs --set smoke --vision-only  # murah: gate + stat saja
//   node eval/run.mjs --set smoke --reprocess  # gratis: susun ulang dari raw.png
//
// Kedua model berjalan lewat Replicate, jadi hanya butuh SATU kredensial:
// REPLICATE_API_TOKEN. Ini bukan cuma soal kenyamanan setup — di mode BYOK,
// pemain jadi cukup menempelkan satu token miliknya, bukan dua.
//
// SETIAP generation gambar berbiaya nyata. Tidak ada retry otomatis untuk
// gambar, dan itu disengaja: retry yang tidak diminta adalah cara paling mudah
// membakar uang. Panggilan Vision boleh diulang sekali karena harganya
// sekitar seperduapuluh tiga dari satu gambar.

import { readFile, writeFile, mkdir, access } from "node:fs/promises";
import { basename, extname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { Image } from "imagescript";
// Modul post-processing hidup di direktori Edge Function, bukan di sini, karena
// produksi yang memilikinya dan eval yang meminjam. Satu file untuk dua runtime;
// paritas keying dan slicing bukan sesuatu yang boleh bergantung pada dua salinan.
import { postprocessSheet, layoutForPrompt } from "../backend/supabase/functions/_shared/postprocess.mjs";
import {
  assemblePrompt,
  extractJson,
  normalizeCaptureVibe,
  promptMajor,
  spriteSheetTemplate,
  validateVision,
  visionInstruction,
} from "../backend/supabase/functions/_shared/vision.mjs";
import { BIAYA_VISION_USD, biayaGambarUsd } from "../backend/supabase/functions/_shared/pricing.mjs";

export { assemblePrompt, extractJson, validateVision };

const REPO = new URL("..", import.meta.url).pathname;
// Harus dibaca sebelum konstanta model di bawah dievaluasi. Sebelumnya loadEnv()
// baru dipanggil di main(), sehingga override VISION_MODEL/IMAGE_MODEL dari
// .env.local diam-diam tidak pernah memengaruhi konstanta top-level.
loadEnv();

const COST_PER_VISION_USD = BIAYA_VISION_USD;
const VISION_MODEL = process.env.VISION_MODEL ?? "google/gemini-2.5-flash";
const IMAGE_MODEL = process.env.IMAGE_MODEL ?? "openai/gpt-image-2";
const IMAGE_QUALITY = process.env.IMAGE_QUALITY ?? "medium";
const COST_PER_IMAGE_USD = biayaGambarUsd(IMAGE_MODEL, IMAGE_QUALITY);
const PHOTO_MAX_SIDE = 1024;
const POLL_INTERVAL_MS = 2000;
const VISION_POLL_MS = 700; // panggilan teks selesai dalam hitungan detik
const POLL_TIMEOUT_MS = 180_000;

// ---------------------------------------------------------------- argumen

function parseArgs(argv) {
  const args = {
    set: null,
    photo: null,
    promptVersion: "v7",
    vibe: "natural",
    visionFile: null,
    dryRun: false,
    visionOnly: false,
    reprocess: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--set") args.set = argv[++i];
    else if (a === "--photo") args.photo = argv[++i];
    else if (a === "--prompt-version") args.promptVersion = argv[++i];
    else if (a === "--vibe") args.vibe = argv[++i];
    else if (a === "--vision-file") args.visionFile = argv[++i];
    else if (a === "--dry-run") args.dryRun = true;
    else if (a === "--vision-only") args.visionOnly = true;
    else if (a === "--reprocess") args.reprocess = true;
    else if (a === "--help" || a === "-h") args.help = true;
    else throw new Error(`argumen tidak dikenal: ${a}`);
  }
  if (!args.set && !args.photo) args.set = "smoke"; // default aman, bukan full
  const vibe = normalizeCaptureVibe(args.vibe);
  if (vibe == null) throw new Error(`vibe tidak sah: ${args.vibe}`);
  args.vibe = vibe;
  return args;
}

// ---------------------------------------------------------------- utilitas

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const slug = (file) => basename(file, extname(file)).replace(/[^a-z0-9_-]/gi, "_");

function loadEnv() {
  for (const f of [".env", ".env.local"]) {
    try {
      process.loadEnvFile(join(REPO, f));
    } catch {
      // tidak ada file itu, tidak masalah
    }
  }
}

// ---------------------------------------------------------------- foto

async function loadPhoto(path) {
  const raw = await readFile(path);
  const img = await Image.decode(raw);

  // Resize di sisi client persis seperti yang dilakukan Godot sebelum upload:
  // menekan biaya token Vision dan ukuran payload, dan menjaga eval tetap
  // memakai input yang sama dengan produksi.
  const scale = PHOTO_MAX_SIDE / Math.max(img.width, img.height);
  const sized = scale < 1 ? img.resize(Math.round(img.width * scale), Math.round(img.height * scale)) : img;

  return { base64: Buffer.from(await sized.encodeJPEG(80)).toString("base64"), mime: "image/jpeg" };
}

// ---------------------------------------------------------------- Replicate

/**
 * Satu jalur untuk semua panggilan Replicate: buat prediksi, tunggu selesai.
 * Vision dan image generation memakai fungsi yang sama supaya penanganan error,
 * timeout, dan status hanya ada di satu tempat.
 */
async function runPrediction(model, input, pollMs = POLL_INTERVAL_MS) {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN belum di-set (taruh di .env)");

  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const create = await fetch(`https://api.replicate.com/v1/models/${model}/predictions`, {
    method: "POST",
    headers,
    body: JSON.stringify({ input }),
  });
  if (!create.ok) throw new Error(`${model} create ${create.status}: ${(await create.text()).slice(0, 500)}`);

  let pred = await create.json();
  const started = Date.now();
  while (pred.status !== "succeeded" && pred.status !== "failed" && pred.status !== "canceled") {
    if (Date.now() - started > POLL_TIMEOUT_MS) {
      throw new Error(`${model} timeout setelah ${POLL_TIMEOUT_MS / 1000}s`);
    }
    await sleep(pollMs);
    const poll = await fetch(`https://api.replicate.com/v1/predictions/${pred.id}`, { headers });
    if (!poll.ok) throw new Error(`${model} poll ${poll.status}`);
    pred = await poll.json();
  }

  if (pred.status !== "succeeded") throw new Error(`${model} ${pred.status}: ${pred.error ?? "tanpa pesan"}`);
  return { output: pred.output, seconds: Math.round((Date.now() - started) / 1000), id: pred.id };
}

// ---------------------------------------------------------------- Vision

async function callVision(photo, systemPrompt, schema) {
  const input = {
    prompt: "Analyse the attached photograph now. Respond with the JSON object only.",
    images: [`data:${photo.mime};base64,${photo.base64}`],
    system_instruction: visionInstruction(systemPrompt, schema),
    top_p: 0.95,
    max_output_tokens: 4096,
    // Tugas ini ekstraksi terstruktur, bukan penalaran berantai. Thinking
    // ditagih sebagai token output, jadi mematikannya menekan biaya sekaligus
    // latensi. dynamic_thinking disebut eksplisit karena kalau true ia
    // menimpa thinking_budget.
    thinking_budget: 0,
    dynamic_thinking: false,
  };

  // Satu percobaan ulang pada temperature 0 kalau JSON-nya rusak. Ini pengganti
  // yang jujur untuk response_schema yang tidak ada: biayanya ~$0.003, sekitar
  // sekitar seperduapuluh tiga harga satu gambar, jadi mengulang di sini tidak
  // melanggar aturan "jangan retry otomatis" yang berlaku untuk generation.
  let lastError;
  let attempts = 0;
  for (const temperature of [0.4, 0]) {
    const res = await runPrediction(VISION_MODEL, { ...input, temperature }, VISION_POLL_MS);
    attempts++;
    try {
      return { vision: extractJson(res.output), seconds: res.seconds, attempts };
    } catch (err) {
      lastError = err;
    }
  }
  lastError.attempts = attempts;
  throw lastError;
}

// ---------------------------------------------------------------- gambar

export function imageInputForModel(model, prompt, dataUri, quality = "medium") {
  if (model === "openai/gpt-image-2") {
    return {
      prompt,
      input_images: [dataUri],
      aspect_ratio: "1024x1024",
      quality,
      number_of_images: 1,
      // Schema wrapper mencantumkan transparent, tetapi runtime model
      // menolaknya dengan invalid_value. Chroma green tetap wajib.
      background: "opaque",
      output_format: "png",
      output_compression: 100,
      moderation: "auto",
    };
  }
  if (model === "google/nano-banana-2-lite") {
    return {
      prompt,
      image_input: [dataUri],
      aspect_ratio: "1:1",
      output_format: "png",
    };
  }
  return {
    prompt,
    image_input: [dataUri],
    aspect_ratio: "1:1",
    resolution: "2K",
    output_format: "png",
    safety_filter_level: "block_only_high",
    allow_fallback_model: false,
  };
}

async function callImageModel(prompt, photo) {
  // Di eval lokal, foto dikirim sebagai data URI karena tidak ada Storage.
  // Produksi memakai signed URL dari Supabase (lihat doc 01): payload jadi
  // kecil dan foto tidak ikut tercatat di log request yang besar.
  const dataUri = `data:${photo.mime};base64,${photo.base64}`;
  const input = imageInputForModel(IMAGE_MODEL, prompt, dataUri, IMAGE_QUALITY);
  const res = await runPrediction(IMAGE_MODEL, input);

  // Skema output model ini satu string URI, bukan array potongan seperti Vision.
  const url = Array.isArray(res.output) ? res.output[0] : res.output;
  if (typeof url !== "string") throw new Error(`output tidak terduga: ${JSON.stringify(res.output)}`);

  const png = await fetch(url);
  if (!png.ok) throw new Error(`gagal mengunduh hasil: ${png.status}`);

  return {
    png: new Uint8Array(await png.arrayBuffer()),
    seconds: res.seconds,
    predictionId: res.id,
  };
}

// ---------------------------------------------------------------- laporan

function contactSheetHtml(setName, promptVersion, rows, totals) {
  const esc = (s) => String(s ?? "").replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" })[c]);

  const cards = rows
    .map((r) => {
      const badge =
        r.status === "ok"
          ? '<span class="ok">OK</span>'
          : r.status === "rejected"
            ? `<span class="gate">GATE: ${esc(r.reason)}</span>`
            : `<span class="err">GAGAL</span>`;

      const poses = r.manifest
        ? layoutForPrompt(promptVersion).poses.map((p) => {
            const region = r.manifest.poses?.[p]?.region;
            if (!region) return `<div class="pose missing">${p}<br><small>hilang</small></div>`;
            const [x, y, w, h] = region;
            return `<div class="pose"><div class="crop" style="width:${w}px;height:${h}px;
              background-image:url('${r.sheetFile}');background-position:-${x}px -${y}px"></div>
              <small>${p}</small></div>`;
          }).join("")
        : "";

      return `<section>
        <header>${esc(r.file)} ${badge}
          <small>${esc(r.tests ?? "")}</small></header>
        <div class="body">
          <img class="photo" src="${r.photoFile}" alt="foto asli">
          <div class="poses">${poses}</div>
          <div class="meta">
            ${r.vision ? `<div><b>${esc(r.vision.suggested_name)}</b> — ${esc(r.vision.species_key)}
              / ${esc(r.vision.color_bucket)} / ${esc(r.vision.element)} / rarity ${esc(r.vision.rarity)}</div>` : ""}
            ${r.vision?.strike_name || r.vision?.surge_name ? `<div>moves: ${esc(r.vision.strike_name)} / ${esc(r.vision.surge_name)}</div>` : ""}
            ${r.vision?.stats ? `<div class="stats">${Object.entries(r.vision.stats)
              .map(([k, val]) => `<span>${k} <b>${val}</b></span>`).join("")}</div>` : ""}
            ${r.vision?.creature_brief ? `<p>${esc(r.vision.creature_brief)}</p>` : ""}
            ${r.issues?.length ? `<ul class="issues">${r.issues.map((i) => `<li>${esc(i)}</li>`).join("")}</ul>` : ""}
            ${r.manifest ? `<div class="qa">frame ${r.manifest.frame_size.join("x")}
              · sel ${r.manifest.qa.cells_detected}/${layoutForPrompt(promptVersion).poses.length}
              · residu hijau ${(r.manifest.qa.green_residue_ratio * 100).toFixed(3)}%
              · skala Idle/Attack ${(r.manifest.qa.standing_height_variance * 100).toFixed(1)}%
              ${r.seconds ? `· ${r.seconds}s` : ""}</div>` : ""}
            ${r.manifest?.qa.warnings?.length ? `<ul class="warn">${r.manifest.qa.warnings
              .map((w) => `<li>${esc(w)}</li>`).join("")}</ul>` : ""}
            ${r.error ? `<pre class="err">${esc(r.error)}</pre>` : ""}
            <label>True to Object <input type="range" min="1" max="5" value="3"></label>
            <label>Konsistensi gaya <input type="range" min="1" max="5" value="3"></label>
          </div>
        </div>
      </section>`;
    })
    .join("\n");

  return `<!doctype html><meta charset="utf-8">
<title>Scanima eval — ${esc(setName)} / ${esc(promptVersion)}</title>
<style>
  body{font:14px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:24px;background:#14161a;color:#e6e8ec}
  h1{font-size:20px;margin:0 0 4px}
  .totals{color:#9aa3b2;margin-bottom:24px}
  section{background:#1c1f26;border-radius:10px;margin-bottom:16px;overflow:hidden}
  header{padding:12px 16px;background:#22262f;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  header small{color:#8b94a5;font-weight:400}
  .body{display:flex;gap:16px;padding:16px;align-items:flex-start;flex-wrap:wrap}
  .photo{width:180px;border-radius:8px;background:#000}
  .poses{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap}
  .pose{text-align:center;color:#8b94a5}
  .crop{background-repeat:no-repeat;zoom:.42;
    background-color:#2a2f39;border-radius:4px;
    background-image:linear-gradient(45deg,#2a2f39 25%,#333947 25%,#333947 50%,#2a2f39 50%)}
  .pose.missing{padding:24px;background:#3a2226;border-radius:6px;color:#f0a0a8}
  .meta{flex:1;min-width:280px}
  .stats span{display:inline-block;margin-right:12px;color:#9aa3b2}
  .qa{color:#8b94a5;font-size:12px;margin-top:8px}
  .issues,.warn{margin:8px 0;padding-left:18px;font-size:12px}
  .issues{color:#e8c37a}.warn{color:#f0a0a8}
  .ok{background:#1f4535;color:#7fe0b0;padding:2px 8px;border-radius:99px;font-size:12px}
  .gate{background:#3a3520;color:#e8c37a;padding:2px 8px;border-radius:99px;font-size:12px}
  .err{background:#3a2226;color:#f0a0a8;padding:2px 8px;border-radius:99px;font-size:12px}
  pre.err{padding:10px;border-radius:6px;white-space:pre-wrap}
  label{display:block;color:#8b94a5;font-size:12px;margin-top:6px}
</style>
<h1>Scanima eval — set ${esc(setName)}, prompt ${esc(promptVersion)}</h1>
<div class="totals">
  ${totals.visionCalls} vision · ${totals.generated} generation ·
  biaya ~$${totals.costUsd.toFixed(3)} ·
  gate benar ${totals.gateCorrect}/${totals.gateExpected} ·
  sel lengkap ${totals.fullSheets}/${totals.generated} ·
  ${esc(new Date().toISOString())}
</div>
${cards}`;
}

// ---------------------------------------------------------------- main

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(`Scanima eval harness

  --set smoke|full        set foto (default: smoke)
  --photo <path>          jalankan satu foto saja
  --prompt-version v7     versi prompt di backend/prompts/ (default: v7)
  --vibe natural          capture vibe: natural|cute|brave|wild|sinister
  --vision-file <path>    pakai hasil Vision tersimpan, tanpa panggilan Vision baru
  --dry-run               tidak memanggil API sama sekali
  --vision-only           panggil Vision saja, tanpa image generation
  --reprocess             susun ulang sheet dari raw.png hasil run sebelumnya,
                          nol panggilan API, untuk menguji post-processing`);
    return;
  }

  const pdir = join(REPO, "backend/prompts", args.promptVersion);
  const [systemPrompt, schemaRaw, template, faunaTemplate] = await Promise.all([
    readFile(join(pdir, "vision_system.md"), "utf8"),
    readFile(join(pdir, "vision_schema.json"), "utf8"),
    readFile(join(pdir, "sprite_sheet.md"), "utf8"),
    readFile(join(pdir, "sprite_sheet_fauna.md"), "utf8").catch((error) => {
      if (error.code === "ENOENT") return null;
      throw error;
    }),
  ]);
  const vibeDirectionsRaw = await readFile(join(pdir, "vibe_directions.json"), "utf8").catch((error) => {
    if (error.code === "ENOENT") return null;
    throw error;
  });
  const vibeDirections = vibeDirectionsRaw ? JSON.parse(vibeDirectionsRaw) : null;
  const schema = JSON.parse(schemaRaw);
  const prompts = { sprite_sheet: template, sprite_sheet_fauna: faunaTemplate };
  const useV13 = promptMajor(args.promptVersion) >= 13;

  let items;
  if (args.photo) {
    items = [{ file: basename(args.photo), path: args.photo }];
  } else {
    const sets = JSON.parse(await readFile(join(REPO, "eval/sets.json"), "utf8"));
    if (!sets[args.set]) throw new Error(`set '${args.set}' tidak ada di eval/sets.json`);
    items = sets[args.set].map((it) => ({ ...it, path: join(REPO, "eval/photos", it.file) }));
  }

  const missing = [];
  if (!args.reprocess) {
    for (const it of items) {
      try {
        await access(it.path);
      } catch {
        missing.push(it.file);
      }
    }
  }
  if (missing.length) {
    console.error(`\nFoto belum ada di eval/photos/:\n  ${missing.join("\n  ")}`);
    console.error("\nLihat eval/photos/README.md untuk daftar dan panduan pengambilan foto.");
    process.exit(1);
  }

  const willGenerate = args.visionOnly || args.reprocess ? 0 : items.filter((it) => !it.expect_reject).length;
  const willVision = args.reprocess || args.visionFile ? 0 : items.length;
  const estimate = willGenerate * COST_PER_IMAGE_USD + willVision * COST_PER_VISION_USD;

  console.log(`set        : ${args.set ?? "single"} (${items.length} foto)`);
  console.log(`prompt     : ${args.promptVersion}`);
  console.log(`vibe       : ${args.vibe}`);
  console.log(`vision     : ${VISION_MODEL} (via Replicate)`);
  console.log(`image      : ${IMAGE_MODEL}`);
  console.log(
    `perkiraan  : ${willVision} vision + ${willGenerate} generation, ` +
      `~$${estimate.toFixed(3)}`
  );
  if (args.dryRun) console.log("mode       : DRY RUN, tidak ada API dipanggil");
  else if (args.reprocess) console.log("mode       : REPROSES dari raw.png, tidak ada API dipanggil");
  else if (args.visionOnly) console.log("mode       : VISION ONLY, tanpa image generation");
  console.log("");

  if (args.dryRun) {
    // Verifikasi template bisa terisi tanpa placeholder tersisa, memakai data
    // Vision palsu. Gratis, dan menangkap template rusak sebelum bayar apa pun.
    const fake = {
      creature_brief: "Sebuah tubuh uji berbentuk kotak dengan dua mata di depan.",
      signature_features: ["tombol jadi mata", "kabel jadi ekor"],
      strike_name: "Click Snap",
      surge_name: "Cable Lash",
    };
    assemblePrompt(template, fake, args.vibe, vibeDirections);
    if (faunaTemplate) assemblePrompt(faunaTemplate, fake, args.vibe, vibeDirections);
    console.log(
      `template ${args.promptVersion}${faunaTemplate ? " object + fauna" : ""} terisi tanpa placeholder sisa`
    );
    console.log(`semua ${items.length} foto ditemukan`);
    console.log("\ndry run: OK");
    return;
  }

  const outDir = join(REPO, "eval/results", args.promptVersion, args.set ?? "single");
  await mkdir(outDir, { recursive: true });

  const rows = [];
  const knownSpecies = [];
  const totals = {
    generated: 0,
    visionCalls: 0,
    visionRepaired: 0,
    costUsd: 0,
    gateCorrect: 0,
    gateExpected: 0,
    fullSheets: 0,
  };

  for (const [i, item] of items.entries()) {
    const base = slug(item.file);
    const name = args.vibe === "natural" ? base : `${base}-${args.vibe}`;
    const label = `[${i + 1}/${items.length}] ${item.file}${args.vibe === "natural" ? "" : ` (${args.vibe})`}`;
    const row = {
      file: item.file,
      tests: item.tests,
      vibe: args.vibe,
      status: "error",
      photoFile: `${base}.photo.jpg`,
    };
    rows.push(row);

    try {
      let photo = null;
      let checked;

      if (args.visionFile) {
        const stored = JSON.parse(await readFile(args.visionFile, "utf8"));
        checked = stored.vision ? stored : { gate: "passed", vision: stored, issues: [] };
        row.vision = checked.vision;
        row.issues = checked.issues ?? [];
        photo = await loadPhoto(item.path);
      } else if (args.reprocess) {
        // Vision dan gambarnya sudah dibayar di run sebelumnya, jadi yang diuji
        // ulang di sini hanya post-processing. vision.json dan prompt.txt asli
        // sengaja tidak ditimpa: keduanya adalah catatan run yang menghasilkan
        // raw.png ini, bukan catatan run hari ini.
        checked = JSON.parse(await readFile(join(outDir, `${base}.vision.json`), "utf8"));
        row.vision = checked.vision;
        row.issues = checked.issues ?? [];
      } else {
        photo = await loadPhoto(item.path);
        await writeFile(join(outDir, `${base}.photo.jpg`), Buffer.from(photo.base64, "base64"));

        process.stdout.write(`${label} vision... `);
        let seen;
        try {
          seen = await callVision(photo, systemPrompt, schema);
        } catch (err) {
          // Panggilan yang berhasil tapi JSON-nya rusak tetap ditagih, jadi tetap
          // dihitung. Gagal sebelum request terkirim (token hilang, HTTP error)
          // tidak menetapkan attempts dan memang tidak ditagih.
          totals.visionCalls += err.attempts ?? 0;
          totals.costUsd += (err.attempts ?? 0) * COST_PER_VISION_USD;
          throw err;
        }
        totals.visionCalls += seen.attempts;
        totals.costUsd += seen.attempts * COST_PER_VISION_USD;
        if (seen.attempts > 1) {
          totals.visionRepaired++;
          // Bukan fatal, tapi harus terlihat: kalau sering terjadi, prompt kontrak
          // output-nya yang perlu diperbaiki, bukan parser-nya.
          row.issues = ["JSON percobaan pertama rusak, diulang pada temperature 0"];
        }

        checked = validateVision(
          seen.vision,
          knownSpecies,
          promptMajor(args.promptVersion) >= 4,
          promptMajor(args.promptVersion) >= 5,
          promptMajor(args.promptVersion) >= 7,
          promptMajor(args.promptVersion) >= 12,
          useV13,
          useV13,
          useV13,
          promptMajor(args.promptVersion) >= 17,
          promptMajor(args.promptVersion) >= 32,
          promptMajor(args.promptVersion) >= 33,
          promptMajor(args.promptVersion) === 35,
          promptMajor(args.promptVersion) === 36,
          promptMajor(args.promptVersion) === 37,
          promptMajor(args.promptVersion) === 38,
          promptMajor(args.promptVersion) >= 39,
        );
        row.vision = checked.vision;
        row.issues = [...(row.issues ?? []), ...checked.issues];
        await writeFile(join(outDir, `${base}.vision.json`), JSON.stringify(checked, null, 2));
      }

      if (item.expect_reject) {
        totals.gateExpected++;
        if (checked.gate === "rejected" && checked.reason === item.expect_reject) {
          totals.gateCorrect++;
          row.status = "rejected";
          row.reason = checked.reason;
          console.log(`ditolak benar (${checked.reason})`);
        } else {
          row.status = "error";
          row.error = `GATE BOCOR: harus ditolak '${item.expect_reject}', hasilnya ${checked.gate} '${checked.reason ?? "-"}'`;
          console.log("GATE BOCOR");
        }
        continue;
      }

      if (checked.gate === "rejected") {
        row.status = "rejected";
        row.reason = checked.reason;
        console.log(`ditolak gate (${checked.reason}) — tidak ada generation`);
        continue;
      }

      if (checked.vision.species_key) knownSpecies.push(checked.vision.species_key);
      console.log(`${checked.vision.species_key} / ${checked.vision.element}`);

      if (args.visionOnly) {
        row.status = "ok";
        continue;
      }

      let gen;
      if (args.reprocess) {
        process.stdout.write(`${label} reproses... `);
        gen = { png: new Uint8Array(await readFile(join(outDir, `${name}.raw.png`))), seconds: 0 };
      } else {
        const prompt = assemblePrompt(
          spriteSheetTemplate(prompts, checked.vision.subject_kind),
          checked.vision,
          args.vibe,
          vibeDirections,
        );
        await writeFile(join(outDir, `${name}.prompt.txt`), prompt);

        process.stdout.write(`${label} generate... `);
        gen = await callImageModel(prompt, photo);
        totals.costUsd += COST_PER_IMAGE_USD;
        await writeFile(join(outDir, `${name}.raw.png`), gen.png);
      }
      totals.generated++;
      row.seconds = gen.seconds;

      const { png, manifest } = await postprocessSheet(gen.png, {
        speciesKey: checked.vision.species_key,
        colorBucket: checked.vision.color_bucket,
        promptVersion: args.promptVersion,
        kind: "create",
        sheetName: `${name}.png`,
        vfxMotion: {
          fx_strike: checked.vision.strike_vfx?.motion,
          fx_surge: checked.vision.surge_vfx?.motion,
        },
      });
      await writeFile(join(outDir, `${name}.png`), png);
      await writeFile(join(outDir, `${name}.json`), JSON.stringify(manifest, null, 2));

      row.status = "ok";
      row.manifest = manifest;
      row.sheetFile = `${name}.png`;
      if (manifest.qa.cells_detected === layoutForPrompt(args.promptVersion).poses.length) {
        totals.fullSheets++;
      }

      console.log(
        (gen.seconds ? `${gen.seconds}s · ` : "") +
          `sel ${manifest.qa.cells_detected}/${layoutForPrompt(args.promptVersion).poses.length}` +
          (manifest.qa.warnings.length ? ` · ${manifest.qa.warnings.join("; ")}` : "")
      );
    } catch (err) {
      row.error = err.message;
      console.log(`\n  GAGAL: ${err.message}`);
    }
  }

  // Berapa foto yang jatuh ke species_key sama. Ini proksi paling awal untuk
  // rasio cache hit, yang menentukan sehat atau tidaknya seluruh model biaya.
  const keys = rows.filter((r) => r.vision?.species_key).map((r) => r.vision.species_key);
  const unique = new Set(keys);

  await writeFile(
    join(outDir, "summary.json"),
    JSON.stringify({ set: args.set, promptVersion: args.promptVersion, totals, uniqueSpecies: [...unique], rows }, null, 2)
  );
  await writeFile(join(outDir, "index.html"), contactSheetHtml(args.set ?? "single", args.promptVersion, rows, totals));

  console.log(`\n${"-".repeat(58)}`);
  console.log(`vision          : ${totals.visionCalls} panggilan, ${totals.visionRepaired} perlu diulang`);
  console.log(`generation      : ${totals.generated}`);
  console.log(`biaya           : ~$${totals.costUsd.toFixed(3)}`);
  console.log(`gate benar      : ${totals.gateCorrect}/${totals.gateExpected}`);
  console.log(`sheet lengkap  : ${totals.fullSheets}/${totals.generated}`);
  console.log(`species unik    : ${unique.size} dari ${keys.length} foto`);
  const failed = rows.filter((r) => r.status === "error");
  if (failed.length) console.log(`gagal           : ${failed.map((r) => r.file).join(", ")}`);
  console.log(`\ncontact sheet   : ${join(outDir, "index.html")}`);
  console.log("Beri skor True to Object dan konsistensi gaya sambil melihatnya.");
}

// Hanya jalan kalau file ini yang dieksekusi, bukan saat selftest mengimpor
// validateVision dan assemblePrompt dari sini.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error(`\n${err.message}`);
    process.exit(1);
  });
}
