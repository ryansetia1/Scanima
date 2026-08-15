import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";

export const ASSET_SOURCE_FILENAME = "asset.sources.json";
const PRODUCTION_SOURCES = new Set(["replicate", "manual_chatgpt"]);

export function isProductionAssetSource(source) {
  return PRODUCTION_SOURCES.has(source);
}

export async function readAssetSources(chapterDir) {
  try {
    const value = JSON.parse(await readFile(join(chapterDir, ASSET_SOURCE_FILENAME), "utf8"));
    return value && typeof value === "object" && value.slots && typeof value.slots === "object"
      ? value
      : { slots: {} };
  } catch {
    return { slots: {} };
  }
}

export function assetMode(ctx, sources) {
  const slots = ctx.imageSlots();
  const recorded = slots.filter((slot) =>
    isProductionAssetSource(sources.slots?.[slot]?.source)
  ).length;
  if (recorded === slots.length) return "production";
  return recorded === 0 ? "procedural" : "mixed";
}

export function withGeneratedAssetSource(sources, slot, prediction, hash) {
  return {
    slots: {
      ...(sources.slots ?? {}),
      [slot]: {
        source: "replicate",
        prediction_id: prediction.predictionId,
        model: prediction.model,
        output_sha256: hash,
        generated_at: new Date().toISOString(),
      },
    },
  };
}

export function withReprocessedAssetSource(sources, slot, hash) {
  const existing = sources.slots?.[slot];
  if (!existing) throw new Error(`ASSET_SOURCE_MISSING:${slot}`);
  return {
    slots: {
      ...(sources.slots ?? {}),
      [slot]: {
        ...existing,
        output_sha256: hash,
        reprocessed_at: new Date().toISOString(),
      },
    },
  };
}

export function withManualAssetSource(sources, slot, {
  provider,
  operator,
  generatedAt,
  inputPath,
  inputHash,
  outputHash,
  notesHash,
  postprocess = null,
}) {
  const existing = sources.slots?.[slot];
  if (
    existing?.source === "manual_chatgpt" &&
    existing.input_sha256 === inputHash &&
    existing.output_sha256 === outputHash &&
    existing.notes_sha256 === notesHash &&
    JSON.stringify(existing.postprocess ?? null) === JSON.stringify(postprocess)
  ) {
    return sources;
  }
  const regenerationHistory = [...(existing?.regeneration_history ?? [])];
  if (
    existing?.source === "manual_chatgpt" &&
    existing.input_sha256 &&
    existing.input_sha256 !== inputHash
  ) {
    regenerationHistory.push({
      input_sha256: existing.input_sha256,
      output_sha256: existing.output_sha256,
      ingested_at: existing.ingested_at,
    });
  }
  return {
    slots: {
      ...(sources.slots ?? {}),
      [slot]: {
        source: "manual_chatgpt",
        provider,
        operator,
        generated_at: generatedAt,
        input_path: inputPath,
        input_sha256: inputHash,
        output_sha256: outputHash,
        notes_sha256: notesHash,
        ingested_at: new Date().toISOString(),
        regeneration_history: regenerationHistory,
        ...(postprocess ? { postprocess } : {}),
      },
    },
  };
}

function storagePathForSlot(ctx, slot) {
  if (slot.startsWith("anima:")) return ctx.animaStoragePath(slot.slice("anima:".length));
  if (slot.startsWith("zone:")) return ctx.zoneStoragePath(Number(slot.slice("zone:".length)));
  if (slot === "boss_seeker") return ctx.bossStoragePath();
  if (slot === "trophy") return ctx.trophyStoragePath();
  throw new Error(`ASSET_SLOT_INVALID:${slot}`);
}

export function assertAssetProvenance(ctx, manifest, sources) {
  const hashes = new Map(
    (manifest.assets?.entries ?? []).map((entry) => [entry.path, entry.sha256]),
  );
  for (const slot of ctx.imageSlots()) {
    const source = sources.slots?.[slot];
    if (!isProductionAssetSource(source?.source)) {
      throw new Error(`ASSET_PROVENANCE_MISSING:${slot}`);
    }
    const path = storagePathForSlot(ctx, slot);
    if (hashes.get(path) !== source.output_sha256) {
      throw new Error(`ASSET_PROVENANCE_HASH_MISMATCH:${slot}`);
    }
  }
  return true;
}

export async function writeAssetSources(chapterDir, sources) {
  await writeFile(join(chapterDir, ASSET_SOURCE_FILENAME), stableStringify(sources));
  return sources;
}
