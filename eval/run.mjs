#!/usr/bin/env node
// Harness evaluasi prompt Scanima: foto -> Vision LLM -> nano-banana-pro ->
// post-processing -> contact sheet HTML.
//
//   node eval/run.mjs --set smoke              # 5 foto, ~$0.40
//   node eval/run.mjs --set full               # 20 foto, ~$2,41
//   node eval/run.mjs --photo eval/photos/mouse.jpg
//   node eval/run.mjs --set smoke --dry-run    # gratis: cek foto & prompt saja
//   node eval/run.mjs --set smoke --vision-only  # gratis-ish: gate + stat saja
//
// SETIAP generation berbiaya nyata. Tidak ada retry otomatis di sini, dan itu
// disengaja: retry yang tidak diminta adalah cara paling mudah membakar uang.

import { readFile, writeFile, mkdir, access } from "node:fs/promises";
import { basename, extname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { Image } from "imagescript";
import { postprocessSheet, POSES } from "./postprocess.mjs";

const REPO = new URL("..", import.meta.url).pathname;
const COST_PER_IMAGE_USD = 0.134; // nano-banana-pro 1K/2K, per gambar
const VISION_MODEL = process.env.VISION_MODEL ?? "gemini-3.1-flash-lite";
const IMAGE_MODEL = process.env.IMAGE_MODEL ?? "google/nano-banana-pro";
const PHOTO_MAX_SIDE = 1024;
const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 180_000;

// ---------------------------------------------------------------- argumen

function parseArgs(argv) {
  const args = { set: null, photo: null, promptVersion: "v1", dryRun: false, visionOnly: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--set") args.set = argv[++i];
    else if (a === "--photo") args.photo = argv[++i];
    else if (a === "--prompt-version") args.promptVersion = argv[++i];
    else if (a === "--dry-run") args.dryRun = true;
    else if (a === "--vision-only") args.visionOnly = true;
    else if (a === "--help" || a === "-h") args.help = true;
    else throw new Error(`argumen tidak dikenal: ${a}`);
  }
  if (!args.set && !args.photo) args.set = "smoke"; // default aman, bukan full
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

function levenshtein(a, b) {
  const dp = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let prev = dp[0];
    dp[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const tmp = dp[j];
      dp[j] = Math.min(dp[j] + 1, dp[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
      prev = tmp;
    }
  }
  return dp[b.length];
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

// ---------------------------------------------------------------- Vision

async function callVision(photo, systemPrompt, schema) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY belum di-set (taruh di .env)");

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${VISION_MODEL}:generateContent`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts: [{ inline_data: { mime_type: photo.mime, data: photo.base64 } }] }],
      generationConfig: {
        temperature: 0.4,
        responseMimeType: "application/json",
        responseSchema: schema,
      },
    }),
  });

  if (!res.ok) throw new Error(`Vision ${res.status}: ${(await res.text()).slice(0, 500)}`);

  const body = await res.json();
  const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error(`Vision tidak mengembalikan teks: ${JSON.stringify(body).slice(0, 400)}`);
  return JSON.parse(text);
}

/**
 * Schema menjamin bentuk, bukan kewajaran isi. Pemeriksaan di sini menegakkan
 * hal-hal yang tidak bisa diungkapkan di responseSchema Gemini.
 */
export function validateVision(v, knownSpecies = []) {
  const issues = [];

  if (!v.safe || !v.is_object) {
    return { gate: "rejected", reason: v.reject_reason ?? "unknown", issues, vision: v };
  }

  if (!v.species_key || !/^[a-z]+(_[a-z]+){1,3}$/.test(v.species_key)) {
    issues.push(`species_key tidak sesuai format: ${JSON.stringify(v.species_key)}`);
  } else {
    // Normalisasi ke kunci yang sudah ada supaya typo tidak memecah cache.
    // Satu huruf beda berarti dua entri cache dan dua kali biaya generation.
    for (const known of knownSpecies) {
      if (known !== v.species_key && levenshtein(known, v.species_key) <= 2) {
        issues.push(`species_key '${v.species_key}' dinormalisasi ke '${known}'`);
        v.species_key = known;
        break;
      }
    }
  }

  if (v.stats) {
    const sum = Object.values(v.stats).reduce((a, b) => a + b, 0);
    if (sum < 200 || sum > 350) {
      const target = Math.min(350, Math.max(200, sum));
      const factor = target / sum;
      for (const k of Object.keys(v.stats)) {
        v.stats[k] = Math.max(10, Math.min(95, Math.round(v.stats[k] * factor)));
      }
      issues.push(`jumlah stat ${sum} di luar 200-350, diskalakan proporsional`);
    }
  } else {
    issues.push("stats kosong");
  }

  const vague = /^(unique|interesting|nice|cool|various|some)\b|qualities$|texture$/i;
  const feats = v.signature_features ?? [];
  if (feats.length < 2) issues.push("signature_features kurang dari 2");
  for (const f of feats) {
    if (vague.test(f.trim())) issues.push(`signature_feature kabur: "${f}"`);
  }

  return { gate: "passed", reason: null, issues, vision: v };
}

// ---------------------------------------------------------------- prompt

export function assemblePrompt(template, vision) {
  const bullets = (vision.signature_features ?? []).map((f) => `- ${f}`).join("\n");
  const out = template
    .replaceAll("{{creature_brief}}", vision.creature_brief ?? "")
    .replaceAll("{{signature_features_as_bullets}}", bullets);

  const leftover = out.match(/\{\{[a-z_]+\}\}/g);
  if (leftover) throw new Error(`placeholder belum terisi: ${leftover.join(", ")}`);
  return out;
}

// ---------------------------------------------------------------- Replicate

async function callReplicate(prompt, photo) {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN belum di-set (taruh di .env)");

  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };

  // Di eval lokal, foto dikirim sebagai data URI karena tidak ada Storage.
  // Produksi memakai signed URL dari Supabase (lihat doc 01): payload jadi
  // kecil dan foto tidak ikut tercatat di log request yang besar.
  const create = await fetch(`https://api.replicate.com/v1/models/${IMAGE_MODEL}/predictions`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      input: {
        prompt,
        image_input: [`data:${photo.mime};base64,${photo.base64}`],
        aspect_ratio: "1:1",
        resolution: "2K",
        output_format: "png",
        safety_filter_level: "block_only_high",
        allow_fallback_model: false,
      },
    }),
  });

  if (!create.ok) throw new Error(`Replicate create ${create.status}: ${(await create.text()).slice(0, 500)}`);
  let pred = await create.json();

  const started = Date.now();
  while (pred.status !== "succeeded" && pred.status !== "failed" && pred.status !== "canceled") {
    if (Date.now() - started > POLL_TIMEOUT_MS) throw new Error(`timeout setelah ${POLL_TIMEOUT_MS / 1000}s`);
    await sleep(POLL_INTERVAL_MS);
    const poll = await fetch(`https://api.replicate.com/v1/predictions/${pred.id}`, { headers });
    if (!poll.ok) throw new Error(`Replicate poll ${poll.status}`);
    pred = await poll.json();
  }

  if (pred.status !== "succeeded") throw new Error(`prediksi ${pred.status}: ${pred.error ?? "tanpa pesan"}`);

  // Skema output model ini satu string URI, bukan array.
  const url = Array.isArray(pred.output) ? pred.output[0] : pred.output;
  if (typeof url !== "string") throw new Error(`output tidak terduga: ${JSON.stringify(pred.output)}`);

  const png = await fetch(url);
  if (!png.ok) throw new Error(`gagal mengunduh hasil: ${png.status}`);

  return {
    png: new Uint8Array(await png.arrayBuffer()),
    seconds: Math.round((Date.now() - started) / 1000),
    predictionId: pred.id,
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
        ? POSES.map((p) => {
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
            ${r.vision?.stats ? `<div class="stats">${Object.entries(r.vision.stats)
              .map(([k, val]) => `<span>${k} <b>${val}</b></span>`).join("")}</div>` : ""}
            ${r.vision?.creature_brief ? `<p>${esc(r.vision.creature_brief)}</p>` : ""}
            ${r.issues?.length ? `<ul class="issues">${r.issues.map((i) => `<li>${esc(i)}</li>`).join("")}</ul>` : ""}
            ${r.manifest ? `<div class="qa">frame ${r.manifest.frame_size.join("x")}
              · sel ${r.manifest.qa.cells_detected}/4
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
  ${totals.generated} generation · biaya ~$${totals.costUsd.toFixed(2)} ·
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
  --prompt-version v1     versi prompt di backend/prompts/
  --dry-run               tidak memanggil API sama sekali
  --vision-only           panggil Vision saja, tanpa image generation`);
    return;
  }

  loadEnv();

  const pdir = join(REPO, "backend/prompts", args.promptVersion);
  const [systemPrompt, schemaRaw, template] = await Promise.all([
    readFile(join(pdir, "vision_system.md"), "utf8"),
    readFile(join(pdir, "vision_schema.json"), "utf8"),
    readFile(join(pdir, "sprite_sheet.md"), "utf8"),
  ]);
  const schema = JSON.parse(schemaRaw);

  let items;
  if (args.photo) {
    items = [{ file: basename(args.photo), path: args.photo }];
  } else {
    const sets = JSON.parse(await readFile(join(REPO, "eval/sets.json"), "utf8"));
    if (!sets[args.set]) throw new Error(`set '${args.set}' tidak ada di eval/sets.json`);
    items = sets[args.set].map((it) => ({ ...it, path: join(REPO, "eval/photos", it.file) }));
  }

  const missing = [];
  for (const it of items) {
    try {
      await access(it.path);
    } catch {
      missing.push(it.file);
    }
  }
  if (missing.length) {
    console.error(`\nFoto belum ada di eval/photos/:\n  ${missing.join("\n  ")}`);
    console.error("\nLihat eval/photos/README.md untuk daftar dan panduan pengambilan foto.");
    process.exit(1);
  }

  const willGenerate = items.filter((it) => !it.expect_reject).length;
  const estimate = willGenerate * COST_PER_IMAGE_USD;

  console.log(`set        : ${args.set ?? "single"} (${items.length} foto)`);
  console.log(`prompt     : ${args.promptVersion}`);
  console.log(`vision     : ${VISION_MODEL}`);
  console.log(`image      : ${IMAGE_MODEL}`);
  console.log(`perkiraan  : ${willGenerate} generation, ~$${estimate.toFixed(2)}`);
  if (args.dryRun) console.log("mode       : DRY RUN, tidak ada API dipanggil");
  else if (args.visionOnly) console.log("mode       : VISION ONLY, tanpa image generation");
  console.log("");

  if (args.dryRun) {
    // Verifikasi template bisa terisi tanpa placeholder tersisa, memakai data
    // Vision palsu. Gratis, dan menangkap template rusak sebelum bayar apa pun.
    const fake = {
      creature_brief: "Sebuah tubuh uji berbentuk kotak dengan dua mata di depan.",
      signature_features: ["tombol jadi mata", "kabel jadi ekor"],
    };
    assemblePrompt(template, fake);
    console.log(`template ${args.promptVersion} terisi tanpa placeholder sisa`);
    console.log(`semua ${items.length} foto ditemukan`);
    console.log("\ndry run: OK");
    return;
  }

  const outDir = join(REPO, "eval/results", args.promptVersion, args.set ?? "single");
  await mkdir(outDir, { recursive: true });

  const rows = [];
  const knownSpecies = [];
  const totals = { generated: 0, costUsd: 0, gateCorrect: 0, gateExpected: 0, fullSheets: 0 };

  for (const [i, item] of items.entries()) {
    const name = slug(item.file);
    const label = `[${i + 1}/${items.length}] ${item.file}`;
    const row = { file: item.file, tests: item.tests, status: "error", photoFile: `${name}.photo.jpg` };
    rows.push(row);

    try {
      const photo = await loadPhoto(item.path);
      await writeFile(join(outDir, `${name}.photo.jpg`), Buffer.from(photo.base64, "base64"));

      process.stdout.write(`${label} vision... `);
      const raw = await callVision(photo, systemPrompt, schema);
      const checked = validateVision(raw, knownSpecies);
      row.vision = checked.vision;
      row.issues = checked.issues;
      await writeFile(join(outDir, `${name}.vision.json`), JSON.stringify(checked, null, 2));

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

      const prompt = assemblePrompt(template, checked.vision);
      await writeFile(join(outDir, `${name}.prompt.txt`), prompt);

      process.stdout.write(`${label} generate... `);
      const gen = await callReplicate(prompt, photo);
      totals.generated++;
      totals.costUsd += COST_PER_IMAGE_USD;
      row.seconds = gen.seconds;
      await writeFile(join(outDir, `${name}.raw.png`), gen.png);

      const { png, manifest } = await postprocessSheet(gen.png, {
        speciesKey: checked.vision.species_key,
        colorBucket: checked.vision.color_bucket,
        promptVersion: args.promptVersion,
        sheetName: `${name}.png`,
      });
      await writeFile(join(outDir, `${name}.png`), png);
      await writeFile(join(outDir, `${name}.json`), JSON.stringify(manifest, null, 2));

      row.status = "ok";
      row.manifest = manifest;
      row.sheetFile = `${name}.png`;
      if (manifest.qa.cells_detected === POSES.length) totals.fullSheets++;

      console.log(
        `${gen.seconds}s · sel ${manifest.qa.cells_detected}/4` +
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
  console.log(`generation      : ${totals.generated}`);
  console.log(`biaya           : ~$${totals.costUsd.toFixed(2)}`);
  console.log(`gate benar      : ${totals.gateCorrect}/${totals.gateExpected}`);
  console.log(`sheet 4/4 sel   : ${totals.fullSheets}/${totals.generated}`);
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
