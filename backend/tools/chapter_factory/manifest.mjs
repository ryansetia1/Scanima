import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { generateZoneMap } from "../../supabase/functions/_shared/expedition.mjs";
import { stableSortKeys, stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";
import { buildGameplayManifest, chapterSequence as seqFromContext } from "./context.mjs";
import {
  renderAnimaSheet,
  renderBossSeekerSheet,
  renderTrophyArt,
  renderZoneArt,
  sha256Hex,
} from "./assets.mjs";
import { assetMode, readAssetSources } from "./provenance.mjs";

export { sha256Hex };

export function chapterSequence(manifest = null, ctx = null) {
  return seqFromContext(manifest, ctx);
}

export function canonicalManifestBody(manifest) {
  const clone = structuredClone(manifest);
  delete clone.qa;
  delete clone.manifest_hash;
  return stableSortKeys(clone);
}

export function manifestHash(manifest) {
  const body = canonicalManifestBody(manifest);
  return createHash("sha256").update(stableStringify(body)).digest("hex");
}

export function attachAssetPaths(manifest, assetRecords, ctx) {
  const byAnima = new Map(
    assetRecords.animas.map((entry) => [entry.id, entry]),
  );
  for (const opponent of manifest.opponents) {
    for (const member of opponent.roster) {
      const asset = byAnima.get(member.anima_id);
      if (!asset) throw new Error(`ASSET_MISSING:${member.anima_id}`);
      member.sheet_path = asset.sheet_path;
      member.manifest = asset.manifest;
    }
  }
  manifest.boss_seeker.sheet_hash = assetRecords.boss.hash;
  manifest.boss_seeker.manifest = assetRecords.boss.manifest;
  manifest.trophy.art_hash = assetRecords.trophy.hash;
  for (const [index, zone] of manifest.zones.entries()) {
    zone.background_hash = assetRecords.zones[index].hash;
  }
  manifest.assets = {
    prefix: ctx.assetPrefix,
    entries: [
      ...assetRecords.animas.map((entry) => ({
        kind: "anima_sheet",
        path: entry.sheet_path,
        sha256: entry.hash,
      })),
      ...assetRecords.zones.map((entry) => ({
        kind: "zone_art",
        path: entry.path,
        sha256: entry.hash,
      })),
      {
        kind: "boss_seeker_sheet",
        path: assetRecords.boss.path,
        sha256: assetRecords.boss.hash,
      },
      {
        kind: "trophy_art",
        path: manifest.trophy.art_path,
        sha256: assetRecords.trophy.hash,
      },
    ],
  };
  return manifest;
}

export async function buildAssetBundleProcedural(ctx) {
  const animas = [];
  for (const cast of ctx.design.cast) {
    const rendered = await renderAnimaSheet(cast);
    const sheetPath = ctx.animaStoragePath(cast.id);
    animas.push({
      id: cast.id,
      sheet_path: sheetPath,
      manifest_path: `${ctx.assetPrefix}animas/${cast.id}/manifest.json`,
      png: rendered.png,
      manifest: rendered.manifest,
      hash: rendered.hash,
    });
  }
  const zones = [];
  for (const zone of ctx.design.zones) {
    const rendered = await renderZoneArt(zone.id);
    const path = ctx.zoneStoragePath(zone.index);
    zones.push({
      path,
      png: rendered.png,
      hash: rendered.hash,
    });
  }
  const bossRendered = await renderBossSeekerSheet(ctx.design.boss_seeker.id);
  const boss = {
    path: ctx.bossStoragePath(),
    png: bossRendered.png,
    manifest: bossRendered.manifest,
    hash: bossRendered.hash,
  };
  const trophyRendered = await renderTrophyArt(ctx.design.trophy.slug);
  const trophy = {
    path: ctx.trophyStoragePath(),
    png: trophyRendered.png,
    hash: trophyRendered.hash,
  };
  return { animas, zones, boss, trophy };
}

export function applySlotToBundle(bundle, slot, asset) {
  if (slot.startsWith("anima:")) {
    const id = slot.slice("anima:".length);
    const index = bundle.animas.findIndex((entry) => entry.id === id);
    if (index < 0) throw new Error(`BUNDLE_ANIMA_MISSING:${id}`);
    bundle.animas[index] = {
      ...bundle.animas[index],
      png: asset.png,
      manifest: asset.manifest,
      hash: asset.hash,
    };
    return;
  }
  if (slot.startsWith("zone:")) {
    const index = Number(slot.slice("zone:".length)) - 1;
    if (!bundle.zones[index]) throw new Error(`BUNDLE_ZONE_MISSING:${slot}`);
    bundle.zones[index] = {
      ...bundle.zones[index],
      png: asset.png,
      hash: asset.hash,
    };
    return;
  }
  if (slot === "boss_seeker") {
    bundle.boss = {
      ...bundle.boss,
      png: asset.png,
      manifest: asset.manifest,
      hash: asset.hash,
    };
    return;
  }
  if (slot === "trophy") {
    bundle.trophy = {
      ...bundle.trophy,
      png: asset.png,
      hash: asset.hash,
    };
    return;
  }
  throw new Error(`ASSET_SLOT_INVALID:${slot}`);
}

export async function loadAssetBundleFromDisk(chapterDir, ctx) {
  const root = join(chapterDir, "assets");
  const readHashed = async (path) => {
    const png = await readFile(path);
    return { png, hash: sha256Hex(png) };
  };
  const animas = [];
  for (const cast of ctx.design.cast) {
    const base = join(root, "animas", cast.id);
    const sheet = await readHashed(join(base, "sheet.png"));
    const manifest = JSON.parse(await readFile(join(base, "manifest.json"), "utf8"));
    animas.push({
      id: cast.id,
      sheet_path: ctx.animaStoragePath(cast.id),
      manifest_path: `${ctx.assetPrefix}animas/${cast.id}/manifest.json`,
      ...sheet,
      manifest,
    });
  }
  const zones = [];
  for (const zone of ctx.design.zones) {
    const path = ctx.zoneStoragePath(zone.index);
    zones.push({
      path,
      ...(await readHashed(join(root, "zones", `zone-${zone.index}.png`))),
    });
  }
  const bossFile = ctx.bossLocalFilename();
  const bossSheet = await readHashed(join(root, "boss", bossFile));
  const boss = {
    path: ctx.bossStoragePath(),
    ...bossSheet,
    manifest: JSON.parse(await readFile(join(root, "boss", "manifest.json"), "utf8")),
  };
  const trophyFile = ctx.trophyLocalFilename();
  const trophySheet = await readHashed(join(root, "trophy", trophyFile));
  const trophy = {
    path: ctx.trophyStoragePath(),
    ...trophySheet,
  };
  return { animas, zones, boss, trophy };
}

export async function loadOrCreateAssetBundle(chapterDir, ctx) {
  try {
    return await loadAssetBundleFromDisk(chapterDir, ctx);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    return buildAssetBundleProcedural(ctx);
  }
}

export function finalizeManifest(manifest, ctx, { mode = "procedural" } = {}) {
  manifest.factory = {
    slug: ctx.slug,
    content_version: ctx.contentVersion,
    sequence: chapterSequence(manifest, ctx),
    asset_prefix: ctx.assetPrefix,
    mode,
    prompt_version: "chapter_factory/v1",
    generated_at: new Date(0).toISOString(),
  };
  manifest.manifest_hash = manifestHash(manifest);
  manifest.qa = {
    map_seed: ctx.mapSeed,
    map_previews: ctx.design.zones.map((zone) =>
      generateZoneMap(manifest, zone.index, 1, ctx.mapSeed),
    ),
  };
  return manifest;
}

export async function buildCompleteManifest({ chapterDir = null, ctx }) {
  let assets;
  let mode = "procedural";
  if (chapterDir) {
    try {
      assets = await loadAssetBundleFromDisk(chapterDir, ctx);
      mode = assetMode(ctx, await readAssetSources(chapterDir));
    } catch {
      assets = await buildAssetBundleProcedural(ctx);
    }
  } else {
    assets = await buildAssetBundleProcedural(ctx);
  }
  const manifest = attachAssetPaths(buildGameplayManifest(ctx), assets, ctx);
  finalizeManifest(manifest, ctx, { mode });
  return { manifest, assets };
}

export function assetHashLedger(manifest) {
  const ledger = {};
  for (const entry of manifest.assets.entries) {
    ledger[entry.path] = entry.sha256;
  }
  return ledger;
}

export function stableManifestText(manifest) {
  return stableStringify(canonicalManifestBody(manifest));
}

export async function rebuildFromAssets(chapterDir, assets, ctx, mode = "mixed") {
  const manifest = attachAssetPaths(buildGameplayManifest(ctx), assets, ctx);
  finalizeManifest(manifest, ctx, { mode });
  return { manifest, assets };
}
