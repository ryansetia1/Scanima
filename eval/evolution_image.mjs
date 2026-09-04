#!/usr/bin/env node
// Single-shot Sunhound Adult Evolution image eval. It reuses the approved v28
// Plan and Hatchling Idle reference, so one invocation can make at most ONE
// paid image prediction and zero Vision predictions.

import { createHash } from "node:crypto";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  assembleEvolvePrompt,
  buildEvolvePromptContext,
  validateEvolutionPlan,
} from "../backend/supabase/functions/_shared/evolution.mjs";
import { postprocessSheet } from "../backend/supabase/functions/_shared/postprocess.mjs";
import { biayaGambarUsd } from "../backend/supabase/functions/_shared/pricing.mjs";
import { buildBundle } from "../backend/tools/bundle_prompts.mjs";
import { imageInputForModel, runPrediction } from "./run.mjs";

const REPO = new URL("..", import.meta.url).pathname;
const MODEL = process.env.IMAGE_MODEL ?? "openai/gpt-image-2";
const QUALITY = process.env.IMAGE_QUALITY ?? "medium";
const COST_ACK = `US$${biayaGambarUsd(MODEL, QUALITY).toFixed(2)}`;
const SPECIES_KEY = "dog_canine_retriever_standing";
const COLOR_BUCKET = "warm_yellow";

const SUNHOUND_CAPTURE = {
  object_label: "Golden Retriever dog",
  surface_finish: "Soft, dense, golden double coat with feathering",
  creature_brief:
    "A quadrupedal golden-coated companion with floppy ears, a feathered tail, and an alert watchful face.",
  character_direction: "Loyal, intelligent, and gentle with a watchful, alert posture.",
  signature_features: [
    "Long feathered tail",
    "Expressive floppy ears",
    "Dense double coat",
    "Strong athletic build",
  ],
  dominant_colors: ["golden yellow", "cream", "warm brown"],
  species_key: SPECIES_KEY,
  color_bucket: COLOR_BUCKET,
  damage_hints: ["Ruffled and dull fur", "Slightly tired eyes", "Dusty paws"],
};

function parseArgs(argv) {
  const args = {
    promptVersion: null,
    planFile: null,
    referenceImage: null,
    outputDir: null,
    dryRun: false,
    paid: false,
    apply: false,
    ack: null,
  };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--prompt-version") args.promptVersion = argv[++i];
    else if (arg === "--plan-file") args.planFile = argv[++i];
    else if (arg === "--reference-image") args.referenceImage = argv[++i];
    else if (arg === "--output-dir") args.outputDir = argv[++i];
    else if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--paid") args.paid = true;
    else if (arg === "--apply") args.apply = true;
    else if (arg.startsWith("--ack=")) args.ack = arg.slice("--ack=".length);
    else if (arg === "--help" || arg === "-h") args.help = true;
    else throw new Error(`argumen tidak dikenal: ${arg}`);
  }
  return args;
}

function required(args, key, flag) {
  if (!args[key]) throw new Error(`${flag} wajib`);
}

function dataUri(bytes) {
  return `data:image/png;base64,${Buffer.from(bytes).toString("base64")}`;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(`Single-shot Sunhound Adult Evolution image eval

Wajib:
  --prompt-version <version>
  --plan-file <approved-plan.json>
  --reference-image <hatchling-idle-reference.png>

Mode:
  --dry-run
  --paid --apply '--ack=${COST_ACK}'`);
    return;
  }

  for (const [key, flag] of [
    ["promptVersion", "--prompt-version"],
    ["planFile", "--plan-file"],
    ["referenceImage", "--reference-image"],
  ]) required(args, key, flag);
  if (!args.dryRun && (!args.paid || !args.apply || args.ack !== COST_ACK)) {
    throw new Error(
      `PAID_ACK_REQUIRED: gunakan --paid --apply '--ack=${COST_ACK}' untuk tepat satu generation`,
    );
  }

  const outputDir = resolve(
    args.outputDir ?? join(REPO, "eval/results", args.promptVersion, "evolution"),
  );
  await mkdir(outputDir, { recursive: true });
  const rawPath = join(outputDir, "sunhound-adult-grounding.raw.png");
  if (!args.dryRun) {
    await access(rawPath)
      .then(() => {
        throw new Error(`OUTPUT_ALREADY_EXISTS: ${rawPath}; hapus hanya jika operator menyetujui generation baru`);
      })
      .catch((error) => {
        if (error.code !== "ENOENT") throw error;
      });
  }

  const [planRaw, reference, bundles] = await Promise.all([
    readFile(args.planFile, "utf8").then(JSON.parse),
    readFile(args.referenceImage),
    buildBundle(),
  ]);
  const plan = validateEvolutionPlan(planRaw.plan ?? planRaw, {
    targetStage: 2,
    priorHeightCm: 75,
    contractVersion: 28,
    priorStrikeName: "Swift Bite",
    priorSurgeName: "Radiant Aura",
  }).plan;
  plan.target_stage = 2;
  const template = bundles[args.promptVersion]?.sprite_sheet_evolve;
  if (!template) throw new Error(`sprite_sheet_evolve tidak ada untuk ${args.promptVersion}`);
  const prompt = assembleEvolvePrompt(
    template,
    plan,
    buildEvolvePromptContext(SUNHOUND_CAPTURE, {
      species_key: SPECIES_KEY,
      color_bucket: COLOR_BUCKET,
    }),
  );
  if (/\{\{[^}]+\}\}/.test(prompt)) throw new Error("placeholder prompt Evolution masih tersisa");
  await writeFile(join(outputDir, "sunhound-adult-grounding.prompt.txt"), prompt);

  if (args.dryRun) {
    console.log("dry run: OK");
    console.log(`prompt      : ${join(outputDir, "sunhound-adult-grounding.prompt.txt")}`);
    console.log("Replicate   : 0 panggilan");
    return;
  }

  console.log(`Evolution: tepat 1× ${MODEL} ${QUALITY}, estimated ${COST_ACK}`);
  const prediction = await runPrediction(
    MODEL,
    imageInputForModel(MODEL, prompt, dataUri(reference), QUALITY),
  );
  const url = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
  if (typeof url !== "string") {
    throw new Error(`output tidak terduga: ${JSON.stringify(prediction.output)}`);
  }
  const response = await fetch(url);
  if (!response.ok) throw new Error(`gagal mengunduh hasil: ${response.status}`);
  const raw = new Uint8Array(await response.arrayBuffer());
  await writeFile(rawPath, raw);

  const { png, manifest } = await postprocessSheet(raw, {
    speciesKey: SPECIES_KEY,
    colorBucket: COLOR_BUCKET,
    stage: 2,
    promptVersion: args.promptVersion,
    sheetName: "sunhound-adult-grounding.png",
    vfxMotion: {
      fx_strike: plan.strike_vfx?.motion,
      fx_surge: plan.surge_vfx?.motion,
    },
  });
  await Promise.all([
    writeFile(join(outputDir, "sunhound-adult-grounding.png"), png),
    writeFile(
      join(outputDir, "sunhound-adult-grounding.json"),
      JSON.stringify(manifest, null, 2),
    ),
    writeFile(
      join(outputDir, "sunhound-adult-grounding.source.json"),
      JSON.stringify({
        prediction_id: prediction.id,
        model: MODEL,
        quality: QUALITY,
        prompt_version: args.promptVersion,
        prompt_sha256: sha256(prompt),
        source_plan: args.planFile,
        source_reference: args.referenceImage,
        estimated_cost_usd: biayaGambarUsd(MODEL, QUALITY),
      }, null, 2),
    ),
  ]);
  console.log(`sel         : ${manifest.qa.cells_detected}/9`);
  console.log(`hasil       : ${join(outputDir, "sunhound-adult-grounding.png")}`);
  console.log("Replicate   : 1 image generation, 0 Vision");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`\n${error.message}`);
    process.exit(1);
  });
}
