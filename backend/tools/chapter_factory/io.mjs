import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { stableSortKeys, stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";
import { syncApprovalLedger } from "./approval.mjs";
import { defaultChapterDir, loadChapterContext } from "./context.mjs";
import { buildCompleteManifest } from "./manifest.mjs";
import { buildReviewPage } from "./review.mjs";
import { validateChapterDraft } from "./validate.mjs";

export function chapterRoot(repoRoot) {
  return defaultChapterDir(repoRoot);
}

export function assetsDir(chapterDir) {
  return join(chapterDir, "assets");
}

export async function writeAssetTree(chapterDir, bundle, ctx) {
  const root = assetsDir(chapterDir);
  for (const anima of bundle.animas) {
    const base = join(root, "animas", anima.id);
    await mkdir(base, { recursive: true });
    await writeFile(join(base, "sheet.png"), anima.png);
    await writeFile(join(base, "manifest.json"), stableStringify(anima.manifest));
  }
  await mkdir(join(root, "zones"), { recursive: true });
  for (const [index, zone] of bundle.zones.entries()) {
    const zoneMeta = ctx.design.zones[index];
    await writeFile(join(root, "zones", `zone-${zoneMeta.index}.png`), zone.png);
  }
  await mkdir(join(root, "boss"), { recursive: true });
  await writeFile(join(root, "boss", ctx.bossLocalFilename()), bundle.boss.png);
  await writeFile(join(root, "boss", "manifest.json"), stableStringify(bundle.boss.manifest));
  await mkdir(join(root, "trophy"), { recursive: true });
  await writeFile(join(root, "trophy", ctx.trophyLocalFilename()), bundle.trophy.png);
}

export async function writeChapterOutputs(chapterDir, { manifest, assets }, ctx) {
  await mkdir(chapterDir, { recursive: true });
  await writeAssetTree(chapterDir, assets, ctx);
  await writeFile(join(chapterDir, "chapter.manifest.json"), stableStringify(stableSortKeys(manifest)));
  await writeFile(join(chapterDir, "review.html"), await buildReviewPage({ manifest, chapterDir, ctx }));
  for (const [index, map] of (manifest.qa?.map_previews ?? []).entries()) {
    await writeFile(join(chapterDir, `map-zone-${index + 1}.json`), stableStringify(map));
  }
  return syncApprovalLedger(chapterDir, manifest);
}

export async function readStoredManifest(chapterDir) {
  const raw = await readFile(join(chapterDir, "chapter.manifest.json"), "utf8");
  return JSON.parse(raw);
}

export async function loadLocalAssetBytes(chapterDir, storagePath, ctx) {
  const relative = ctx.storageToLocalRel(storagePath).replace(/^assets\//, "");
  if (relative.includes("..")) throw new Error(`ASSET_PATH_INVALID:${storagePath}`);
  return readFile(join(assetsDir(chapterDir), relative));
}

export async function buildAndWriteChapter(chapterDir, ctx = null) {
  const context = ctx ?? await loadChapterContext(chapterDir);
  const built = await buildCompleteManifest({ chapterDir, ctx: context });
  validateChapterDraft(built.manifest, context);
  const approval = await writeChapterOutputs(chapterDir, built, context);
  return { ...built, ctx: context, approval };
}

export async function writeRawAsset(chapterDir, slot, bytes) {
  const safeName = String(slot).replace(/[^a-z0-9_-]+/gi, "_");
  const root = join(chapterDir, "raw");
  await mkdir(root, { recursive: true });
  const path = join(root, `${safeName}.png`);
  await writeFile(path, bytes);
  return path;
}
