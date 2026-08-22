import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { extractJson, VISION_THINKING } from "../../supabase/functions/_shared/vision.mjs";
import { BIAYA_VISION_USD } from "../../supabase/functions/_shared/pricing.mjs";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";
import { DESIGN_ACK_PREFIX, VISION_MODEL_DEFAULT } from "./constants.mjs";
import { createContext, loadBrief } from "./context.mjs";
import { recordDesignCostCall } from "./cost_ledger.mjs";
import { validateBrief, validateDesign } from "./validate.mjs";

const PROMPT_DIR = new URL("../../prompts/chapter_factory/", import.meta.url).pathname;
const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 120_000;

export function designCostPreview() {
  return {
    vision_model: process.env.VISION_MODEL ?? VISION_MODEL_DEFAULT,
    planned_usd: BIAYA_VISION_USD,
    acknowledgement: DESIGN_ACK_PREFIX,
  };
}

export function parseDesignAcknowledgement(value) {
  if (typeof value !== "string" || value.trim() !== DESIGN_ACK_PREFIX) {
    throw new Error(
      `DESIGN_ACK_REQUIRED: ketik persis "${DESIGN_ACK_PREFIX}" setelah melihat preview biaya`,
    );
  }
}

export function designExecutionGate({ paid, apply, acknowledgement }) {
  const preview = designCostPreview();
  if (!paid) return { execute: false, preview, reason: "missing --paid" };
  if (!apply) return { execute: false, preview, reason: "missing --apply" };
  try {
    parseDesignAcknowledgement(acknowledgement);
  } catch (error) {
    return { execute: false, preview, reason: error instanceof Error ? error.message : String(error) };
  }
  return { execute: true, preview, reason: "ready" };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function predictionError(message, predictionId) {
  const error = new Error(message);
  error.predictionId = predictionId;
  return error;
}

async function runVisionPrediction(model, systemInstruction, userPrompt) {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN wajib untuk paid design");
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const create = await fetch(`https://api.replicate.com/v1/models/${model}/predictions`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      input: {
        prompt: userPrompt,
        system_instruction: systemInstruction,
        temperature: 0.2,
        top_p: 0.9,
        max_output_tokens: 8192,
        ...VISION_THINKING,
      },
    }),
  });
  if (!create.ok) {
    throw new Error(`${model} create ${create.status}: ${(await create.text()).slice(0, 500)}`);
  }
  let pred = await create.json();
  const started = Date.now();
  while (!["succeeded", "failed", "canceled"].includes(pred.status)) {
    if (Date.now() - started > POLL_TIMEOUT_MS) {
      throw predictionError(`${model} timeout setelah ${POLL_TIMEOUT_MS / 1000}s`, pred.id);
    }
    await sleep(POLL_INTERVAL_MS);
    const poll = await fetch(`https://api.replicate.com/v1/predictions/${pred.id}`, { headers });
    if (!poll.ok) throw predictionError(`${model} poll ${poll.status}`, pred.id);
    pred = await poll.json();
  }
  if (pred.status !== "succeeded") {
    throw predictionError(`${model} ${pred.status}: ${pred.error ?? "tanpa pesan"}`, pred.id);
  }
  return {
    output: pred.output,
    model,
    predictionId: pred.id,
    seconds: Math.round((Date.now() - started) / 1000),
  };
}

async function readDesignSystemPrompt() {
  return readFile(join(PROMPT_DIR, "design_system.md"), "utf8");
}

function buildUserPrompt(brief) {
  return `Theme brief JSON:\n${stableStringify(brief)}\n\nReturn one complete chapter design JSON object only.`;
}

export async function runDesignCommand({
  chapterDir,
  paid = false,
  apply = false,
  acknowledgement = "",
}) {
  const gate = designExecutionGate({ paid, apply, acknowledgement });
  if (!gate.execute) {
    return {
      ok: true,
      mode: "preview",
      preview: gate.preview,
      note: gate.reason,
    };
  }

  const brief = await loadBrief(chapterDir);
  validateBrief(brief);
  const systemInstruction = await readDesignSystemPrompt();
  const userPrompt = buildUserPrompt(brief);
  const model = gate.preview.vision_model;
  let prediction = null;
  let rawPath = null;
  try {
    prediction = await runVisionPrediction(model, systemInstruction, userPrompt);
    const rawOutput = Array.isArray(prediction.output)
      ? prediction.output.join("")
      : String(prediction.output ?? "");
    const rawDir = join(chapterDir, "raw");
    await mkdir(rawDir, { recursive: true });
    rawPath = join(rawDir, `design_${prediction.predictionId}.txt`);
    await writeFile(rawPath, rawOutput, "utf8");

    const design = extractJson(prediction.output);
    const ctx = createContext(chapterDir, brief, design);
    validateDesign(design, brief, ctx);

    await writeFile(join(chapterDir, "design.json"), stableStringify(design));
    await recordDesignCostCall(chapterDir, ctx, {
      status: "succeeded",
      prediction_id: prediction.predictionId,
      model: prediction.model,
      raw_path: rawPath,
      estimated_usd: BIAYA_VISION_USD,
      seconds: prediction.seconds,
      recorded_at: new Date().toISOString(),
    });

    return {
      ok: true,
      mode: "apply",
      preview: gate.preview,
      cast_count: design.cast.length,
      zone_count: design.zones.length,
      opponent_count: design.opponents.length,
    };
  } catch (error) {
    const ctx = {
      slug: brief.slug,
      contentVersion: Number(brief.content_version),
      imageSlots: () => Array(14).fill(null),
    };
    await recordDesignCostCall(chapterDir, ctx, {
      status: "failed",
      prediction_id: prediction?.predictionId ?? error?.predictionId ?? null,
      model,
      raw_path: rawPath,
      estimated_usd: BIAYA_VISION_USD,
      recorded_at: new Date().toISOString(),
      error: String(error instanceof Error ? error.message : error).slice(0, 300),
    });
    throw error;
  }
}
