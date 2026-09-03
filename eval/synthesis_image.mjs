#!/usr/bin/env node
// Single-shot Synthesis image eval. It reuses a stored, already-paid Plan and
// two existing Source sheets, so one invocation can make at most ONE paid image
// prediction and zero Vision predictions.

import { createHash } from "node:crypto";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { buildEvolutionIdleReference } from "../backend/supabase/functions/_shared/evolution.mjs";
import { postprocessSheet } from "../backend/supabase/functions/_shared/postprocess.mjs";
import { biayaGambarUsd } from "../backend/supabase/functions/_shared/pricing.mjs";
import { assembleSynthesisPrompt } from "../backend/supabase/functions/_shared/synthesis.mjs";
import { buildBundle } from "../backend/tools/bundle_prompts.mjs";
import { imageInputForModel, runPrediction } from "./run.mjs";

const REPO = new URL("..", import.meta.url).pathname;
const MODEL = process.env.IMAGE_MODEL ?? "openai/gpt-image-2";
const QUALITY = process.env.IMAGE_QUALITY ?? "medium";
const COST_ACK = `US$${biayaGambarUsd(MODEL, QUALITY).toFixed(2)}`;

function parseArgs(argv) {
  const args = {
    promptVersion: null,
    planFile: null,
    sourceASheet: null,
    sourceAManifest: null,
    sourceAName: null,
    sourceBSheet: null,
    sourceBManifest: null,
    sourceBName: null,
    mode: null,
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
    else if (arg === "--source-a-sheet") args.sourceASheet = argv[++i];
    else if (arg === "--source-a-manifest") args.sourceAManifest = argv[++i];
    else if (arg === "--source-a-name") args.sourceAName = argv[++i];
    else if (arg === "--source-b-sheet") args.sourceBSheet = argv[++i];
    else if (arg === "--source-b-manifest") args.sourceBManifest = argv[++i];
    else if (arg === "--source-b-name") args.sourceBName = argv[++i];
    else if (arg === "--mode") args.mode = argv[++i];
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
    console.log(`Single-shot Synthesis image eval

Wajib:
  --prompt-version v48
  --plan-file <json>
  --source-a-sheet <png> --source-a-manifest <json> --source-a-name <name>
  --source-b-sheet <png> --source-b-manifest <json> --source-b-name <name>
  --mode dominant_a|balanced|dominant_b

Mode:
  --dry-run
  --paid --apply '--ack=${COST_ACK}'`);
    return;
  }

  for (const [key, flag] of [
    ["promptVersion", "--prompt-version"],
    ["planFile", "--plan-file"],
    ["sourceASheet", "--source-a-sheet"],
    ["sourceAManifest", "--source-a-manifest"],
    ["sourceAName", "--source-a-name"],
    ["sourceBSheet", "--source-b-sheet"],
    ["sourceBManifest", "--source-b-manifest"],
    ["sourceBName", "--source-b-name"],
    ["mode", "--mode"],
  ]) required(args, key, flag);
  if (!["dominant_a", "balanced", "dominant_b"].includes(args.mode)) {
    throw new Error(`mode tidak sah: ${args.mode}`);
  }
  if (!args.dryRun && (!args.paid || !args.apply || args.ack !== COST_ACK)) {
    throw new Error(
      `PAID_ACK_REQUIRED: gunakan --paid --apply '--ack=${COST_ACK}' untuk tepat satu generation`,
    );
  }

  const outputDir = resolve(
    args.outputDir ?? join(REPO, "eval/results", args.promptVersion, "synthesis"),
  );
  await mkdir(outputDir, { recursive: true });
  const rawPath = join(outputDir, "chromquartz-grounding.raw.png");
  if (!args.dryRun) {
    await access(rawPath)
      .then(() => {
        throw new Error(`OUTPUT_ALREADY_EXISTS: ${rawPath}; hapus hanya jika operator menyetujui generation baru`);
      })
      .catch((error) => {
        if (error.code !== "ENOENT") throw error;
      });
  }

  const [planRaw, manifestA, manifestB, sheetA, sheetB, bundles] = await Promise.all([
    readFile(args.planFile, "utf8").then(JSON.parse),
    readFile(args.sourceAManifest, "utf8").then(JSON.parse),
    readFile(args.sourceBManifest, "utf8").then(JSON.parse),
    readFile(args.sourceASheet),
    readFile(args.sourceBSheet),
    buildBundle(),
  ]);
  const plan = planRaw.vision_result ?? planRaw.plan ?? planRaw;
  const template = bundles[args.promptVersion]?.sprite_sheet_synthesis;
  if (!template) throw new Error(`sprite_sheet_synthesis tidak ada untuk ${args.promptVersion}`);

  const prompt = assembleSynthesisPrompt(
    template,
    plan,
    { name: args.sourceAName },
    { name: args.sourceBName },
    args.mode,
  );
  if (/\{\{[^}]+\}\}/.test(prompt)) throw new Error("placeholder prompt Synthesis masih tersisa");

  const [referenceA, referenceB] = await Promise.all([
    buildEvolutionIdleReference(sheetA, manifestA),
    buildEvolutionIdleReference(sheetB, manifestB),
  ]);
  await Promise.all([
    writeFile(join(outputDir, "chromquartz-grounding.prompt.txt"), prompt),
    writeFile(join(outputDir, "source-a-reference.png"), referenceA),
    writeFile(join(outputDir, "source-b-reference.png"), referenceB),
  ]);

  if (args.dryRun) {
    console.log("dry run: OK");
    console.log(`prompt      : ${join(outputDir, "chromquartz-grounding.prompt.txt")}`);
    console.log("Replicate   : 0 panggilan");
    return;
  }

  const input = imageInputForModel(MODEL, prompt, dataUri(referenceA), QUALITY);
  if (input.input_images) input.input_images = [dataUri(referenceA), dataUri(referenceB)];
  else input.image_input = [dataUri(referenceA), dataUri(referenceB)];

  console.log(`Synthesis: tepat 1× ${MODEL} ${QUALITY}, estimated ${COST_ACK}`);
  const prediction = await runPrediction(MODEL, input);
  const url = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
  if (typeof url !== "string") {
    throw new Error(`output tidak terduga: ${JSON.stringify(prediction.output)}`);
  }
  const response = await fetch(url);
  if (!response.ok) throw new Error(`gagal mengunduh hasil: ${response.status}`);
  const raw = new Uint8Array(await response.arrayBuffer());
  await writeFile(rawPath, raw);

  const { png, manifest } = await postprocessSheet(raw, {
    speciesKey: plan.species_key,
    colorBucket: plan.color_bucket,
    stage: 1,
    promptVersion: args.promptVersion,
    kind: "synthesis",
    sheetName: "chromquartz-grounding.png",
    vfxMotion: {
      fx_strike: plan.strike_vfx?.motion,
      fx_surge: plan.surge_vfx?.motion,
    },
  });
  await Promise.all([
    writeFile(join(outputDir, "chromquartz-grounding.png"), png),
    writeFile(
      join(outputDir, "chromquartz-grounding.json"),
      JSON.stringify(manifest, null, 2),
    ),
    writeFile(
      join(outputDir, "chromquartz-grounding.source.json"),
      JSON.stringify({
        prediction_id: prediction.id,
        model: MODEL,
        quality: QUALITY,
        prompt_version: args.promptVersion,
        prompt_sha256: sha256(prompt),
        source_a: args.sourceAName,
        source_b: args.sourceBName,
        mode: args.mode,
        estimated_cost_usd: biayaGambarUsd(MODEL, QUALITY),
      }, null, 2),
    ),
  ]);
  console.log(`sel         : ${manifest.qa.cells_detected}/9`);
  console.log(`hasil       : ${join(outputDir, "chromquartz-grounding.png")}`);
  console.log(`Replicate   : 1 image generation, 0 Vision`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`\n${error.message}`);
    process.exit(1);
  });
}
