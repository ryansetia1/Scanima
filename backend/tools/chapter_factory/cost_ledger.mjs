import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  BIAYA_VISION_USD,
  biayaGambarUsd,
} from "../../supabase/functions/_shared/pricing.mjs";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";

export const COST_LEDGER_FILENAME = "cost.ledger.json";

export function defaultCostLedger(ctx, imagePreview) {
  return {
    chapter_slug: ctx.slug,
    content_version: ctx.contentVersion,
    design_call: {
      planned_usd: BIAYA_VISION_USD,
      completed: [],
    },
    image_calls: {
      image_model: imagePreview.image_model,
      image_quality: imagePreview.image_quality,
      planned_calls: imagePreview.image_calls,
      unit_usd: imagePreview.unit_usd,
      cost_ceiling_usd: imagePreview.total_usd,
      completed: [],
    },
  };
}

export async function readCostLedger(chapterDir) {
  try {
    return JSON.parse(await readFile(join(chapterDir, COST_LEDGER_FILENAME), "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw new Error(`COST_LEDGER_INVALID: ${String(error)}`);
  }
}

function assertLedgerIdentity(ledger, slug, contentVersion) {
  if (
    ledger.chapter_slug !== slug
    || Number(ledger.content_version) !== Number(contentVersion)
  ) {
    throw new Error(
      `COST_LEDGER_IDENTITY_MISMATCH: ledger=${ledger.chapter_slug}/v${ledger.content_version} ` +
      `chapter=${slug}/v${contentVersion}`,
    );
  }
}

export async function writeCostLedger(chapterDir, ledger) {
  await writeFile(join(chapterDir, COST_LEDGER_FILENAME), stableStringify(ledger));
  return ledger;
}

export async function ensureCostLedger(chapterDir, ctx, imagePreview) {
  const existing = await readCostLedger(chapterDir);
  if (existing) {
    assertLedgerIdentity(existing, ctx.slug, ctx.contentVersion);
    if (!Array.isArray(existing.design_call?.completed)) {
      existing.design_call = {
        ...existing.design_call,
        completed: existing.design_call?.completed
          ? [existing.design_call.completed]
          : [],
      };
      return writeCostLedger(chapterDir, existing);
    }
    return existing;
  }
  return writeCostLedger(chapterDir, defaultCostLedger(ctx, imagePreview));
}

export async function recordImageCostCall(chapterDir, preview, call) {
  const ledger = (await readCostLedger(chapterDir)) ?? defaultCostLedger({ slug: preview.chapter_slug, contentVersion: preview.content_version }, preview);
  assertLedgerIdentity(ledger, preview.chapter_slug, preview.content_version);
  ledger.image_calls.image_model = preview.image_model;
  ledger.image_calls.image_quality = preview.image_quality;
  ledger.image_calls.cost_ceiling_usd = Math.max(
    Number(ledger.image_calls.cost_ceiling_usd) || 0,
    preview.total_usd,
  );
  ledger.image_calls.completed = Array.isArray(ledger.image_calls.completed)
    ? ledger.image_calls.completed
    : [];
  ledger.image_calls.completed.push(call);
  return writeCostLedger(chapterDir, ledger);
}

export async function recordDesignCostCall(chapterDir, ctx, call) {
  const imageModel = process.env.IMAGE_MODEL ?? "openai/gpt-image-2";
  const imageQuality = process.env.IMAGE_QUALITY ?? "medium";
  const imageUnit = biayaGambarUsd(imageModel, imageQuality);
  const ledger = (await readCostLedger(chapterDir)) ?? defaultCostLedger(ctx, {
    image_model: imageModel,
    image_quality: imageQuality,
    image_calls: ctx.imageSlots().length,
    unit_usd: imageUnit,
    total_usd: ctx.imageSlots().length * imageUnit,
  });
  assertLedgerIdentity(ledger, ctx.slug, ctx.contentVersion);
  const completed = Array.isArray(ledger.design_call?.completed)
    ? ledger.design_call.completed
    : ledger.design_call?.completed
      ? [ledger.design_call.completed]
      : [];
  ledger.design_call = {
    ...ledger.design_call,
    planned_usd: BIAYA_VISION_USD,
    completed: [...completed, call],
  };
  return writeCostLedger(chapterDir, ledger);
}
