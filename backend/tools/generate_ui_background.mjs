import { createHash } from "node:crypto";
import {
  access,
  mkdir,
  readFile,
  rename,
  writeFile,
} from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Image } from "imagescript";
import { encodeImage } from "../supabase/functions/_shared/png.mjs";

const ROOT = fileURLToPath(new URL("../..", import.meta.url));
const PROMPT_DIR = join(ROOT, "backend", "prompts", "ui_backgrounds");
const PROVENANCE_DIR = join(ROOT, "backend", "generated", "ui_backgrounds");
const RAW_DIR = join(PROVENANCE_DIR, "raw");
const OUTPUT_DIR = join(ROOT, "game", "assets", "backgrounds");
const MODEL = "openai/gpt-image-2";
const QUALITY = "medium";
const DEFAULT_ASPECT_RATIO = "9:16";
const DEFAULT_TARGET_WIDTH = 720;
const DEFAULT_TARGET_HEIGHT = 1602;
const LANDSCAPE_ASPECT_RATIO = "16:9";
const LANDSCAPE_TARGET_WIDTH = 1600;
const LANDSCAPE_TARGET_HEIGHT = 900;
const POLL_MS = 2000;
const POLL_TIMEOUT_MS = 180_000;
const COST_ACK = "US$0.07";

const SLOTS = Object.freeze({
  home: {
    prompt: "home.md",
    output: "home_background.png",
  },
  duel: {
    prompt: "duel.md",
    output: "duel_background.png",
    reference: "game/assets/backgrounds/duel_background.png",
    snapshotReference: "backend/generated/ui_backgrounds/references/duel_pre_reframe.png",
  },
  team_battle: {
    prompt: "team_battle.md",
    output: "team_battle_background.png",
    reference: "game/assets/backgrounds/team_battle_background.png",
    snapshotReference: "backend/generated/ui_backgrounds/references/team_battle_pre_reframe.png",
  },
  home_landscape: {
    prompt: "home_landscape.md",
    output: "home_landscape_background.png",
    reference: "game/assets/backgrounds/home_background.png",
    aspectRatio: LANDSCAPE_ASPECT_RATIO,
    targetWidth: LANDSCAPE_TARGET_WIDTH,
    targetHeight: LANDSCAPE_TARGET_HEIGHT,
  },
  home_day_landscape: {
    prompt: "home_day_landscape.md",
    output: "home_day_landscape_background.png",
    reference: "game/assets/backgrounds/home_landscape_background.png",
    aspectRatio: LANDSCAPE_ASPECT_RATIO,
    targetWidth: LANDSCAPE_TARGET_WIDTH,
    targetHeight: LANDSCAPE_TARGET_HEIGHT,
  },
  duel_landscape: {
    prompt: "duel_landscape.md",
    output: "duel_landscape_background.png",
    reference: "game/assets/backgrounds/duel_background.png",
    aspectRatio: LANDSCAPE_ASPECT_RATIO,
    targetWidth: LANDSCAPE_TARGET_WIDTH,
    targetHeight: LANDSCAPE_TARGET_HEIGHT,
  },
  duel_day_landscape: {
    prompt: "duel_day_landscape.md",
    output: "duel_day_landscape_background.png",
    reference: "game/assets/backgrounds/duel_landscape_background.png",
    aspectRatio: LANDSCAPE_ASPECT_RATIO,
    targetWidth: LANDSCAPE_TARGET_WIDTH,
    targetHeight: LANDSCAPE_TARGET_HEIGHT,
  },
  team_battle_landscape: {
    prompt: "team_battle_landscape.md",
    output: "team_battle_landscape_background.png",
    reference: "game/assets/backgrounds/team_battle_background.png",
    aspectRatio: LANDSCAPE_ASPECT_RATIO,
    targetWidth: LANDSCAPE_TARGET_WIDTH,
    targetHeight: LANDSCAPE_TARGET_HEIGHT,
  },
  expedition_sugarworks_map: {
    prompt: "expedition_sugarworks_map.md",
    output: "expedition_sugarworks_map_background.png",
  },
  home_day: {
    prompt: "home_day.md",
    output: "home_day_background.png",
    reference: "game/assets/backgrounds/home_background.png",
  },
  duel_day: {
    prompt: "duel_day.md",
    output: "duel_day_background.png",
    reference: "game/assets/backgrounds/duel_background.png",
  },
  expedition_sugarworks_top_view: {
    prompt: "expedition_sugarworks_top_view.md",
    output: "expedition_sugarworks_top_view_background.png",
  },
});

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
      // Optional local files; the explicit environment still wins.
    }
  }
}

function predictionOutputUrl(prediction) {
  const output = Array.isArray(prediction.output)
    ? prediction.output[0]
    : prediction.output;
  return typeof output === "string" ? output : null;
}

async function pollPrediction(token, prediction, sourcePath, source) {
  const headers = { authorization: `Bearer ${token}` };
  const started = Date.now();
  let current = prediction;
  while (!["succeeded", "failed", "canceled"].includes(current.status)) {
    if (Date.now() - started > POLL_TIMEOUT_MS) {
      throw new Error(
        `PREDICTION_STILL_RUNNING:${current.id}; jalankan slot yang sama untuk melanjutkan polling`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    const response = await fetch(
      current.urls?.get ?? `https://api.replicate.com/v1/predictions/${current.id}`,
      { headers },
    );
    if (!response.ok) {
      throw new Error(`PREDICTION_POLL_${response.status}:${current.id}`);
    }
    current = await response.json();
    source.status = current.status;
    source.updated_at = new Date().toISOString();
    await writeJsonAtomic(sourcePath, source);
  }
  return current;
}

async function createPrediction(token, prompt, aspectRatio, reference = null) {
  const input = {
    prompt,
    aspect_ratio: aspectRatio,
    quality: QUALITY,
    number_of_images: 1,
    background: "opaque",
    output_format: "png",
    output_compression: 100,
    moderation: "auto",
  };
  if (reference) {
    input.input_images = [`data:image/png;base64,${Buffer.from(reference).toString("base64")}`];
  }
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
        input,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`${MODEL} create ${response.status}: ${(await response.text()).slice(0, 500)}`);
  }
  return await response.json();
}

async function downloadAndProcess(url, rawPath, outputPath, targetWidth, targetHeight) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`OUTPUT_DOWNLOAD_${response.status}`);
  const raw = new Uint8Array(await response.arrayBuffer());
  const decoded = await Image.decode(raw);
  const targetRatio = targetWidth / targetHeight;
  const sourceRatio = decoded.width / decoded.height;
  const cropWidth = sourceRatio > targetRatio
    ? Math.round(decoded.height * targetRatio)
    : decoded.width;
  const cropHeight = sourceRatio > targetRatio
    ? decoded.height
    : Math.round(decoded.width / targetRatio);
  if ((cropWidth * cropHeight) / (decoded.width * decoded.height) < 0.75) {
    throw new Error(`SOURCE_ASPECT_INVALID:${decoded.width}x${decoded.height}`);
  }
  const cropped = decoded.crop(
    Math.floor((decoded.width - cropWidth) / 2),
    Math.floor((decoded.height - cropHeight) / 2),
    cropWidth,
    cropHeight,
  );
  const finalImage = cropped.resize(targetWidth, targetHeight);
  const output = await encodeImage(finalImage);
  await mkdir(dirname(rawPath), { recursive: true });
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(rawPath, raw);
  await writeFile(outputPath, output);
  return {
    raw_sha256: sha256(raw),
    output_sha256: sha256(output),
    source_dimensions: [decoded.width, decoded.height],
    output_dimensions: [finalImage.width, finalImage.height],
  };
}

async function generate(slot) {
  // ponytail: exactly one paid slot per process. Bulk generation is
  // intentionally unsupported so a failed image cannot silently spend again.
  const definition = SLOTS[slot];
  if (!definition) throw new Error(`SLOT_INVALID:${slot}`);
  const args = new Set(process.argv.slice(2));
  if (!args.has("--paid") || !args.has("--apply") || !args.has(`--ack=${COST_ACK}`)) {
    throw new Error(
      `PAID_ACK_REQUIRED: gunakan --paid --apply "--ack=${COST_ACK}" untuk satu ${MODEL} ${QUALITY}`,
    );
  }
  loadEnv();
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN belum di-set");

  const promptPath = join(PROMPT_DIR, definition.prompt);
  const prompt = await readFile(promptPath, "utf8");
  const promptHash = sha256(prompt);
  const sourcePath = join(PROVENANCE_DIR, `${slot}.json`);
  let source = await readJson(sourcePath);
  let referencePath = definition.reference ?? null;
  let reference = null;
  if (definition.snapshotReference) {
    const snapshotPath = join(ROOT, definition.snapshotReference);
    if (!(await exists(snapshotPath))) {
      if (source) throw new Error(`REFERENCE_SNAPSHOT_MISSING:${snapshotPath}`);
      const original = await readFile(join(ROOT, definition.reference));
      await mkdir(dirname(snapshotPath), { recursive: true });
      await writeFile(snapshotPath, original);
    }
    referencePath = definition.snapshotReference;
    reference = await readFile(snapshotPath);
  } else if (definition.reference) {
    reference = await readFile(join(ROOT, definition.reference));
  }
  const aspectRatio = definition.aspectRatio ?? DEFAULT_ASPECT_RATIO;
  const targetWidth = definition.targetWidth ?? DEFAULT_TARGET_WIDTH;
  const targetHeight = definition.targetHeight ?? DEFAULT_TARGET_HEIGHT;
  const referenceHash = reference ? sha256(reference) : null;
  const rawPath = join(RAW_DIR, `${slot}.png`);
  const outputPath = join(OUTPUT_DIR, definition.output);

  if (source && source.prompt_sha256 !== promptHash) {
    throw new Error(`PROMPT_CHANGED_WITH_EXISTING_PREDICTION:${sourcePath}`);
  }
  if (source && (source.reference_sha256 ?? null) !== referenceHash) {
    throw new Error(`REFERENCE_CHANGED_WITH_EXISTING_PREDICTION:${sourcePath}`);
  }
  if (source?.status === "failed" || source?.status === "canceled") {
    throw new Error(`NO_AUTO_RETRY:${source.prediction_id}:${source.status}`);
  }
  if (source?.status === "succeeded" && await exists(outputPath)) {
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
    console.log(`${slot}: 1× ${MODEL} ${QUALITY}, estimated ${COST_ACK}`);
    prediction = await createPrediction(token, prompt, aspectRatio, reference);
    source = {
      slot,
      status: prediction.status,
      prediction_id: prediction.id,
      model: MODEL,
      quality: QUALITY,
      aspect_ratio: aspectRatio,
      prompt_path: `backend/prompts/ui_backgrounds/${definition.prompt}`,
      prompt_sha256: promptHash,
      reference_path: referencePath,
      reference_sha256: referenceHash,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    await writeJsonAtomic(sourcePath, source);
  }

  prediction = await pollPrediction(token, prediction, sourcePath, source);
  source.status = prediction.status;
  source.output_url = predictionOutputUrl(prediction);
  source.updated_at = new Date().toISOString();
  await writeJsonAtomic(sourcePath, source);
  if (prediction.status !== "succeeded") {
    throw new Error(`${MODEL} ${prediction.status}: ${prediction.error ?? "tanpa pesan"}`);
  }
  if (!source.output_url) throw new Error(`OUTPUT_INVALID:${JSON.stringify(prediction.output)}`);

  const processed = await downloadAndProcess(
    source.output_url,
    rawPath,
    outputPath,
    targetWidth,
    targetHeight,
  );
  source = {
    ...source,
    ...processed,
    raw_path: `backend/generated/ui_backgrounds/raw/${slot}.png`,
    output_path: `game/assets/backgrounds/${definition.output}`,
    seconds: Math.round((Date.now() - started) / 1000),
    completed_at: new Date().toISOString(),
  };
  delete source.output_url;
  await writeJsonAtomic(sourcePath, source);
  console.log(`${slot}: wrote ${source.output_path} (${processed.output_sha256})`);
}

async function check() {
  const failures = [];
  for (const [slot, definition] of Object.entries(SLOTS)) {
    const sourcePath = join(PROVENANCE_DIR, `${slot}.json`);
    const outputPath = join(OUTPUT_DIR, definition.output);
    try {
      const source = await readJson(sourcePath);
      if (source?.status !== "succeeded") throw new Error("provenance is not succeeded");
      const prompt = await readFile(join(PROMPT_DIR, definition.prompt));
      if (sha256(prompt) !== source.prompt_sha256) throw new Error("prompt hash mismatch");
      if (source.reference_path) {
        const reference = await readFile(join(ROOT, source.reference_path));
        if (sha256(reference) !== source.reference_sha256) {
          throw new Error("reference hash mismatch");
        }
      }
      const output = await readFile(outputPath);
      const image = await Image.decode(output);
      const targetWidth = definition.targetWidth ?? DEFAULT_TARGET_WIDTH;
      const targetHeight = definition.targetHeight ?? DEFAULT_TARGET_HEIGHT;
      if (image.width !== targetWidth || image.height !== targetHeight) {
        throw new Error(`dimensions ${image.width}x${image.height}`);
      }
      if (sha256(output) !== source.output_sha256) throw new Error("output hash mismatch");
    } catch (error) {
      failures.push(`${slot}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  if (failures.length > 0) throw new Error(`UI_BACKGROUND_CHECK_FAILED\n${failures.join("\n")}`);
  const count = Object.keys(SLOTS).length;
  console.log(`ui backgrounds: ${count}/${count} valid`);
}

const args = process.argv.slice(2);
if (args.includes("--check")) {
  await check();
} else {
  const slot = args.find((arg) => !arg.startsWith("--"));
  if (!slot) throw new Error(`slot wajib: ${Object.keys(SLOTS).join(", ")}`);
  await generate(slot);
}
