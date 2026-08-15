import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { biayaGambarUsd } from "../../supabase/functions/_shared/pricing.mjs";
import { PAID_ACK_PREFIX } from "./constants.mjs";
import { loadChapterContext } from "./context.mjs";
import { writeChapterOutputs, writeRawAsset } from "./io.mjs";
import {
  applySlotToBundle,
  loadOrCreateAssetBundle,
  rebuildFromAssets,
} from "./manifest.mjs";
import {
  postprocessChapterAnima,
  postprocessChapterTrophy,
  postprocessChapterZone,
  postprocessChromaGridSheet,
} from "./assets.mjs";
import { BOSS_SEEKER_POSES } from "./constants.mjs";
import { promptForSlot } from "./prompts.mjs";
import { validateChapterDraft, validateDesign } from "./validate.mjs";
import { recordImageCostCall } from "./cost_ledger.mjs";
import {
  assetMode,
  readAssetSources,
  withGeneratedAssetSource,
  withReprocessedAssetSource,
  writeAssetSources,
} from "./provenance.mjs";

const IMAGE_MODEL = () => process.env.IMAGE_MODEL ?? "openai/gpt-image-2";
const IMAGE_QUALITY = () => process.env.IMAGE_QUALITY ?? "medium";
const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 180_000;

export function paidSlotSet(input, ctx) {
  const allowed = new Set(ctx.imageSlots());
  if (!input) return allowed;
  const slots = String(input)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  for (const slot of slots) {
    if (!allowed.has(slot)) throw new Error(`PAID_SLOT_INVALID:${slot}`);
  }
  return new Set(slots);
}

export function paidCostPreview(ctx, slots = null) {
  const selected = slots instanceof Set ? slots : paidSlotSet(slots, ctx);
  const unit = biayaGambarUsd(IMAGE_MODEL(), IMAGE_QUALITY());
  const count = selected.size;
  const total = Number((count * unit).toFixed(2));
  return {
    chapter_slug: ctx.slug,
    content_version: ctx.contentVersion,
    image_model: IMAGE_MODEL(),
    image_quality: IMAGE_QUALITY(),
    unit_usd: unit,
    image_calls: count,
    total_usd: total,
    acknowledgement: `${PAID_ACK_PREFIX}${total.toFixed(2)}`,
    slots: [...selected].sort(),
  };
}

export function parsePaidAcknowledgement(value, preview) {
  if (typeof value !== "string" || value.trim() !== preview.acknowledgement) {
    throw new Error(
      `PAID_ACK_REQUIRED: ketik persis "${preview.acknowledgement}" setelah melihat preview biaya`,
    );
  }
}

export function paidExecutionGate({ paid, apply, acknowledgement, slots, ctx }) {
  const preview = paidCostPreview(ctx, slots);
  if (!paid) {
    return { execute: false, preview, reason: "missing --paid" };
  }
  if (!apply) {
    return { execute: false, preview, reason: "missing --apply" };
  }
  try {
    parsePaidAcknowledgement(acknowledgement, preview);
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

async function runPrediction(model, input) {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN wajib untuk paid generation");
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const create = await fetch(`https://api.replicate.com/v1/models/${model}/predictions`, {
    method: "POST",
    headers,
    body: JSON.stringify({ input }),
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
  const url = Array.isArray(pred.output) ? pred.output[0] : pred.output;
  if (typeof url !== "string") {
    throw predictionError(`output tidak terduga: ${JSON.stringify(pred.output)}`, pred.id);
  }
  const png = await fetch(url);
  if (!png.ok) throw predictionError(`gagal mengunduh hasil: ${png.status}`, pred.id);
  return {
    bytes: new Uint8Array(await png.arrayBuffer()),
    model,
    predictionId: pred.id,
    seconds: Math.round((Date.now() - started) / 1000),
  };
}

function imageInput(prompt, slot) {
  const model = IMAGE_MODEL();
  if (model === "openai/gpt-image-2") {
    return {
      prompt,
      aspect_ratio: slot.startsWith("zone:") ? "16:9" : "1024x1024",
      quality: IMAGE_QUALITY(),
      number_of_images: 1,
      background: "opaque",
      output_format: "png",
      output_compression: 100,
      moderation: "auto",
    };
  }
  return {
    prompt,
    aspect_ratio: "1:1",
    output_format: "png",
  };
}

async function generateSlotAsset(chapterDir, slot, ctx) {
  const prompt = await promptForSlot(slot, ctx);
  const prediction = await runPrediction(IMAGE_MODEL(), imageInput(prompt, slot));
  const raw = prediction.bytes;
  const rawPath = await writeRawAsset(chapterDir, slot, raw);
  try {
    if (slot.startsWith("anima:")) {
      const cast = ctx.getCastMember(slot.slice("anima:".length));
      return {
        ...(await postprocessChapterAnima(raw, cast)),
        rawPath,
        prediction,
      };
    }
    if (slot === "boss_seeker") {
      return {
        ...(await postprocessChromaGridSheet(raw, {
          poses: BOSS_SEEKER_POSES,
          meta: { seeker_id: ctx.design.boss_seeker.id },
        })),
        rawPath,
        prediction,
      };
    }
    if (slot === "trophy") {
      return { ...(await postprocessChapterTrophy(raw)), rawPath, prediction };
    }
    if (slot.startsWith("zone:")) {
      return { ...(await postprocessChapterZone(raw)), rawPath, prediction };
    }
    throw new Error(`PAID_SLOT_INVALID:${slot}`);
  } catch (error) {
    error.predictionId = prediction.predictionId;
    error.rawPath = rawPath;
    throw error;
  }
}

export async function runPaidGeneration({
  chapterDir,
  ctx,
  slots,
  acknowledgement,
  paid = false,
  apply = false,
}) {
  const gate = paidExecutionGate({ paid, apply, acknowledgement, slots, ctx });
  if (!gate.execute) {
    return {
      ok: true,
      mode: "preview",
      preview: gate.preview,
      note: gate.reason,
    };
  }

  validateDesign(ctx.design, ctx.brief, ctx);
  const selected = paidSlotSet(slots, ctx);
  const bundle = await loadOrCreateAssetBundle(chapterDir, ctx);
  const preflight = await rebuildFromAssets(chapterDir, bundle, ctx, "mixed");
  validateChapterDraft(preflight.manifest, ctx);
  const generated = [];
  let sources = await readAssetSources(chapterDir);
  let finalManifest = null;
  for (const slot of [...selected].sort()) {
    let asset;
    try {
      asset = await generateSlotAsset(chapterDir, slot, ctx);
    } catch (error) {
      await recordImageCostCall(chapterDir, gate.preview, {
        slot,
        status: "failed",
        prediction_id: error?.predictionId ?? null,
        raw_path: error?.rawPath ?? null,
        estimated_usd: gate.preview.unit_usd,
        recorded_at: new Date().toISOString(),
        error: String(error instanceof Error ? error.message : error).slice(0, 300),
      });
      throw error;
    }
    applySlotToBundle(bundle, slot, asset);
    const nextSources = withGeneratedAssetSource(
      sources,
      slot,
      asset.prediction,
      asset.hash,
    );
    const rebuilt = await rebuildFromAssets(
      chapterDir,
      bundle,
      ctx,
      assetMode(ctx, nextSources),
    );
    validateChapterDraft(rebuilt.manifest, ctx);
    await writeChapterOutputs(chapterDir, rebuilt, ctx);
    await writeAssetSources(chapterDir, nextSources);
    sources = nextSources;
    finalManifest = rebuilt.manifest;
    generated.push({ slot, hash: asset.hash, raw_path: asset.rawPath });
    await recordImageCostCall(chapterDir, gate.preview, {
      slot,
      status: "succeeded",
      prediction_id: asset.prediction.predictionId,
      seconds: asset.prediction.seconds,
      estimated_usd: gate.preview.unit_usd,
      recorded_at: new Date().toISOString(),
    });
  }

  return {
    ok: true,
    mode: "apply",
    preview: gate.preview,
    generated,
    manifest_hash: finalManifest?.manifest_hash ?? null,
  };
}

export async function reprocessTrophy({ chapterDir, ctx, apply = false }) {
  validateDesign(ctx.design, ctx.brief, ctx);
  const raw = await readFile(join(chapterDir, "raw", "trophy.png"));
  const asset = await postprocessChapterTrophy(raw);
  if (!apply) {
    return { ok: true, mode: "preview", slot: "trophy", hash: asset.hash };
  }
  const bundle = await loadOrCreateAssetBundle(chapterDir, ctx);
  applySlotToBundle(bundle, "trophy", asset);
  const sources = await readAssetSources(chapterDir);
  const nextSources = withReprocessedAssetSource(sources, "trophy", asset.hash);
  const rebuilt = await rebuildFromAssets(
    chapterDir,
    bundle,
    ctx,
    assetMode(ctx, nextSources),
  );
  validateChapterDraft(rebuilt.manifest, ctx);
  await writeChapterOutputs(chapterDir, rebuilt, ctx);
  await writeAssetSources(chapterDir, nextSources);
  return {
    ok: true,
    mode: "apply",
    slot: "trophy",
    hash: asset.hash,
    manifest_hash: rebuilt.manifest.manifest_hash,
  };
}
