#!/usr/bin/env node
// Art final Seeker Roster: satu Seeker Sheet berbayar per figur.
//
//   node backend/tools/generate_seeker_art.mjs <slug> --paid --apply "--ack=US$0.07"
//   node backend/tools/generate_seeker_art.mjs --reprocess <slug> [--apply]  # nol API
//   node backend/tools/generate_seeker_art.mjs --check                        # nol API
//
// Placeholder-nya digambar `eval/seeker_art.mjs` dengan biaya nol dan sudah
// membuktikan picker, Profile, dan ketiga arena; yang di sini menggantinya
// sekali. Tepat satu slug per proses dan tanpa retry otomatis: kalau satu figur
// gagal, jalankan ulang figur itu secara eksplisit. Membungkus keempatnya dalam
// loop adalah cara termudah membayar dua kali untuk satu kesalahan.
//
// Raw disimpan SEBELUM post-processing, seperti `anima_sheets/failed_raw/` di
// produksi: biaya terkunci saat Replicate menjawab, jadi sheet yang ditolak
// keying/slicing harus bisa diproses ulang tanpa membayar generation kedua.

import { createHash } from "node:crypto";
import { access, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Image } from "imagescript";
import { biayaGambarUsd } from "../supabase/functions/_shared/pricing.mjs";
import { postprocessChromaGridSheet } from "./chapter_factory/assets.mjs";
// Kontrak sembilan pose yang sama dipakai Boss Seeker chapter dan Seeker Avatar
// pemain; nama konstantanya wire lama, daftarnya satu supaya tidak ada salinan
// kedua yang bisa bergeser sendiri.
import { BOSS_SEEKER_POSES as SEEKER_SHEET_POSES } from "./chapter_factory/constants.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PROMPT_DIR = join(ROOT, "backend", "prompts", "seekers");
const PROVENANCE_DIR = join(ROOT, "backend", "generated", "seekers");
const RAW_DIR = join(PROVENANCE_DIR, "raw");
const OUTPUT_DIR = join(ROOT, "game", "assets", "seekers");
const MODEL = "openai/gpt-image-2";
const QUALITY = "medium";
const PROMPT_VERSION = "seekers/v1";
const POLL_MS = 2000;
const POLL_TIMEOUT_MS = 180_000;
const COST_ACK = `US$${biayaGambarUsd(MODEL, QUALITY).toFixed(2)}`;

// Urutannya sama dengan SeekerRoster.SLUGS, dan figur default lebih dulu supaya
// yang paling banyak dilihat pemain juga yang pertama diperiksa mata.
const SLUGS = ["androgynous", "masculine", "feminine", "automaton"];

// Satu tempat, karena preview dan penulisan HARUS memproses dengan aturan yang
// sama — kalau tidak, hash preview tidak pernah cocok dengan yang di-commit.
function processOptions(slug) {
  return {
    poses: SEEKER_SHEET_POSES,
    promptVersion: PROMPT_VERSION,
    meta: { seeker_avatar: slug },
    alignCells: true,
    despill: true,
  };
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function writeJsonAtomic(path, value) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`);
  await rename(temporary, path);
}

async function readJson(path) {
  if (!(await exists(path))) return null;
  return JSON.parse(await readFile(path, "utf8"));
}

function loadEnv() {
  for (const name of [".env", ".env.local"]) {
    try {
      process.loadEnvFile(join(ROOT, name));
    } catch {
      // Berkas lokal opsional; environment eksplisit tetap menang.
    }
  }
}

// Kontrak sheet dan arah visual per figur dua berkas terpisah supaya keempat
// figur tidak bisa perlahan berbeda kontrak — yang di-hash provenance adalah
// prompt gabungan yang benar-benar dikirim.
async function composePrompt(slug) {
  const template = await readFile(join(PROMPT_DIR, "roster_sheet.md"), "utf8");
  const figure = await readFile(join(PROMPT_DIR, "figures", `${slug}.md`), "utf8");
  return `${template.trim()}\n\n${figure.trim()}\n`;
}

function paths(slug) {
  return {
    source: join(PROVENANCE_DIR, `${slug}.json`),
    raw: join(RAW_DIR, `${slug}.png`),
    output: join(OUTPUT_DIR, `${slug}.png`),
  };
}

async function pollPrediction(token, prediction, sourcePath, source) {
  const headers = { authorization: `Bearer ${token}` };
  const started = Date.now();
  let current = prediction;
  while (!["succeeded", "failed", "canceled"].includes(current.status)) {
    if (Date.now() - started > POLL_TIMEOUT_MS) {
      throw new Error(
        `PREDICTION_STILL_RUNNING:${current.id}; jalankan slug yang sama untuk melanjutkan polling`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    const response = await fetch(
      current.urls?.get ?? `https://api.replicate.com/v1/predictions/${current.id}`,
      { headers },
    );
    if (!response.ok) throw new Error(`PREDICTION_POLL_${response.status}:${current.id}`);
    current = await response.json();
    source.status = current.status;
    source.updated_at = new Date().toISOString();
    await writeJsonAtomic(sourcePath, source);
  }
  return current;
}

async function createPrediction(token, prompt) {
  const response = await fetch(
    `https://api.replicate.com/v1/models/${MODEL}/predictions`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "Cancel-After": "3m",
      },
      body: JSON.stringify({
        input: {
          prompt,
          aspect_ratio: "1024x1024",
          quality: QUALITY,
          number_of_images: 1,
          background: "opaque",
          output_format: "png",
          output_compression: 100,
          moderation: "auto",
        },
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`${MODEL} create ${response.status}: ${(await response.text()).slice(0, 500)}`);
  }
  return await response.json();
}

async function writeProcessed(slug, raw, source, sourcePath) {
  const { output } = paths(slug);
  const asset = await postprocessChromaGridSheet(raw, processOptions(slug));
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, asset.png);
  const image = await Image.decode(asset.png);
  const next = {
    ...source,
    output_path: `game/assets/seekers/${slug}.png`,
    output_sha256: asset.hash,
    output_dimensions: [image.width, image.height],
    render_metrics: asset.manifest.render_metrics ?? null,
    capture_overlap: asset.manifest.qa?.capture_overlap ?? null,
    cell_alignment: asset.manifest.qa?.cell_alignment ?? null,
    spill_stripped: asset.manifest.qa?.spill_stripped ?? null,
    completed_at: new Date().toISOString(),
  };
  delete next.output_url;
  await writeJsonAtomic(sourcePath, next);
  console.log(`${slug}: wrote ${next.output_path} (${asset.hash})`);
  return next;
}

async function generate(slug) {
  // ponytail: tepat satu slug berbayar per proses. Generation massal sengaja
  // tidak didukung supaya satu gambar yang gagal tidak bisa diam-diam
  // membelanjakan tiga lagi bersamanya.
  if (!SLUGS.includes(slug)) throw new Error(`SLUG_INVALID:${slug}; pilih ${SLUGS.join(", ")}`);
  const args = new Set(process.argv.slice(2));
  if (!args.has("--paid") || !args.has("--apply") || !args.has(`--ack=${COST_ACK}`)) {
    throw new Error(
      `PAID_ACK_REQUIRED: gunakan --paid --apply "--ack=${COST_ACK}" untuk satu ${MODEL} ${QUALITY}`,
    );
  }
  loadEnv();
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN belum di-set");

  const prompt = await composePrompt(slug);
  const promptHash = sha256(prompt);
  const { source: sourcePath, raw: rawPath, output: outputPath } = paths(slug);
  let source = await readJson(sourcePath);

  if (source && source.prompt_sha256 !== promptHash) {
    throw new Error(`PROMPT_CHANGED_WITH_EXISTING_PREDICTION:${sourcePath}`);
  }
  if (source?.status === "failed" || source?.status === "canceled") {
    throw new Error(`NO_AUTO_RETRY:${source.prediction_id}:${source.status}`);
  }
  if (source?.status === "succeeded" && (await exists(outputPath)) && source.output_sha256) {
    throw new Error(`ALREADY_GENERATED:${outputPath}`);
  }

  let prediction;
  const started = Date.now();
  if (source?.prediction_id) {
    const response = await fetch(
      `https://api.replicate.com/v1/predictions/${source.prediction_id}`,
      { headers: { authorization: `Bearer ${token}` } },
    );
    if (!response.ok) throw new Error(`PREDICTION_RESUME_${response.status}`);
    prediction = await response.json();
  } else {
    console.log(`${slug}: 1× ${MODEL} ${QUALITY}, estimated ${COST_ACK}`);
    prediction = await createPrediction(token, prompt);
    source = {
      slug,
      status: prediction.status,
      prediction_id: prediction.id,
      model: MODEL,
      quality: QUALITY,
      prompt_version: PROMPT_VERSION,
      prompt_paths: [
        "backend/prompts/seekers/roster_sheet.md",
        `backend/prompts/seekers/figures/${slug}.md`,
      ],
      prompt_sha256: promptHash,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    await writeJsonAtomic(sourcePath, source);
  }

  prediction = await pollPrediction(token, prediction, sourcePath, source);
  source.status = prediction.status;
  source.updated_at = new Date().toISOString();
  await writeJsonAtomic(sourcePath, source);
  if (prediction.status !== "succeeded") {
    throw new Error(`${MODEL} ${prediction.status}: ${prediction.error ?? "tanpa pesan"}`);
  }
  const url = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
  if (typeof url !== "string") {
    throw new Error(`OUTPUT_INVALID:${JSON.stringify(prediction.output)}`);
  }
  const download = await fetch(url);
  if (!download.ok) throw new Error(`OUTPUT_DOWNLOAD_${download.status}`);
  const raw = new Uint8Array(await download.arrayBuffer());
  await mkdir(dirname(rawPath), { recursive: true });
  await writeFile(rawPath, raw);
  source = {
    ...source,
    raw_path: `backend/generated/seekers/raw/${slug}.png`,
    raw_sha256: sha256(raw),
    seconds: Math.round((Date.now() - started) / 1000),
  };
  await writeJsonAtomic(sourcePath, source);
  await writeProcessed(slug, raw, source, sourcePath);
}

// Post-processing keying/slicing bisa menolak sheet yang sudah dibayar. Raw-nya
// tersimpan, jadi perbaikan pipeline diverifikasi ulang di sini dengan nol
// panggilan API — pola yang sama dengan `eval/run.mjs --reprocess`.
async function reprocess(slug, apply) {
  if (!SLUGS.includes(slug)) throw new Error(`SLUG_INVALID:${slug}; pilih ${SLUGS.join(", ")}`);
  const { source: sourcePath, raw: rawPath } = paths(slug);
  const source = await readJson(sourcePath);
  if (!source) throw new Error(`PROVENANCE_MISSING:${sourcePath}`);
  const raw = await readFile(rawPath);
  if (sha256(raw) !== source.raw_sha256) throw new Error(`RAW_HASH_MISMATCH:${rawPath}`);
  if (!apply) {
    const asset = await postprocessChromaGridSheet(raw, processOptions(slug));
    console.log(`${slug}: preview ${asset.hash}; tambahkan --apply untuk menulisnya`);
    return;
  }
  await writeProcessed(slug, raw, source, sourcePath);
}

// Pemeriksaan gratis yang dijalankan `npm run selftest`: art berbayar yang
// ter-commit benar-benar keluaran prediction yang tercatat. Tanpa ini, satu
// `node eval/seeker_art.mjs` bisa mengembalikan placeholder ke dalam build dan
// tidak ada yang merah sampai pemain melihatnya.
async function check() {
  const failures = [];
  for (const slug of SLUGS) {
    const { source: sourcePath, output: outputPath } = paths(slug);
    try {
      const source = await readJson(sourcePath);
      if (source?.status !== "succeeded") throw new Error("provenance is not succeeded");
      if (sha256(await composePrompt(slug)) !== source.prompt_sha256) {
        throw new Error("prompt hash mismatch");
      }
      const output = await readFile(outputPath);
      if (sha256(output) !== source.output_sha256) throw new Error("output hash mismatch");
      const image = await Image.decode(output);
      if (image.width !== 1024 || image.height !== 1024) {
        throw new Error(`dimensions ${image.width}x${image.height}`);
      }
    } catch (error) {
      failures.push(`${slug}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  if (failures.length > 0) throw new Error(`SEEKER_ART_CHECK_FAILED\n${failures.join("\n")}`);
  console.log(`seeker roster art: ${SLUGS.length}/${SLUGS.length} valid`);
}

const argv = process.argv.slice(2);
if (argv.includes("--check")) {
  await check();
} else if (argv.includes("--reprocess")) {
  const slug = argv.find((value) => !value.startsWith("--"));
  if (!slug) throw new Error(`slug wajib: ${SLUGS.join(", ")}`);
  await reprocess(slug, argv.includes("--apply"));
} else {
  const slug = argv.find((value) => !value.startsWith("--"));
  if (!slug) throw new Error(`slug wajib: ${SLUGS.join(", ")}`);
  await generate(slug);
}
