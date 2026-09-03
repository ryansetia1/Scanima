#!/usr/bin/env node
// Free visual/numeric comparison for bounded grounding generations.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { Image } from "imagescript";
import { measureIdleGrounding } from "../../backend/supabase/functions/_shared/postprocess.mjs";

const ROOT = new URL("../..", import.meta.url).pathname;
const OUT = "/tmp/anima-grounding";
const CACHE = join(homedir(), "Library/Application Support/Godot/app_userdata/Scanima/animas");
const VERSION = process.argv[2] ?? "v46";
const BG = Image.rgbaToColor(35, 39, 48, 255);
const IDLE_BG = Image.rgbaToColor(255, 0, 255, 255);
if (!/^v\d+$/.test(VERSION)) throw new Error(`versi tidak sah: ${VERSION}`);

const CASES = [
  {
    id: "object",
    beforeSheet: join(ROOT, "eval/results/v41/single/scanima_stock_vehicle.png"),
    beforeManifest: join(ROOT, "eval/results/v41/single/scanima_stock_vehicle.json"),
    afterSheet: join(ROOT, `eval/results/${VERSION}/single/scanima_stock_vehicle_photo.png`),
    afterManifest: join(ROOT, `eval/results/${VERSION}/single/scanima_stock_vehicle_photo.json`),
  },
  {
    id: "fauna",
    beforeSheet: join(ROOT, "eval/results/v15/single/scanima-v15-golden-retriever.png"),
    beforeManifest: join(ROOT, "eval/results/v15/single/scanima-v15-golden-retriever.json"),
    afterSheet: join(ROOT, `eval/results/${VERSION}/single/scanima-v15-golden-retriever_photo.png`),
    afterManifest: join(ROOT, `eval/results/${VERSION}/single/scanima-v15-golden-retriever_photo.json`),
  },
  {
    id: "synthesis",
    beforeSheet: join(
      CACHE,
      "v6_e85e253a-a055-40ab-9920-7f5698d5bac8_1/fd185eeb96bcdfa9.png",
    ),
    beforeManifest: join(
      CACHE,
      "v6_e85e253a-a055-40ab-9920-7f5698d5bac8_1/manifest.json",
    ),
    afterSheet: join(ROOT, `eval/results/${VERSION}/synthesis/chromquartz-grounding.png`),
    afterManifest: join(ROOT, `eval/results/${VERSION}/synthesis/chromquartz-grounding.json`),
  },
];
if (VERSION === "v48") {
  CASES.splice(0, 2);
  CASES.push({
    id: "synthesis-v47",
    beforeSheet: join(ROOT, "eval/results/v47/synthesis/chromquartz-grounding.png"),
    beforeManifest: join(ROOT, "eval/results/v47/synthesis/chromquartz-grounding.json"),
    afterSheet: join(ROOT, "eval/results/v48/synthesis/chromquartz-grounding.png"),
    afterManifest: join(ROOT, "eval/results/v48/synthesis/chromquartz-grounding.json"),
  });
}
if (VERSION === "v47") {
  CASES.push({
    id: "evolution",
    beforeSheet: join(ROOT, "eval/results/evolution-sunhound-adult-v28-approved/adult.png"),
    beforeManifest: join(ROOT, "eval/results/evolution-sunhound-adult-v28-approved/manifest.json"),
    afterSheet: join(ROOT, "eval/results/v47/evolution/sunhound-adult-grounding.png"),
    afterManifest: join(ROOT, "eval/results/v47/evolution/sunhound-adult-grounding.json"),
  });
}

function fit(image, maxWidth, maxHeight) {
  const scale = Math.min(maxWidth / image.width, maxHeight / image.height);
  return image.resize(
    Math.max(1, Math.round(image.width * scale)),
    Math.max(1, Math.round(image.height * scale)),
  );
}

function onBackground(image, color) {
  const out = new Image(image.width, image.height);
  out.fill(color);
  out.composite(image, 0, 0);
  return out;
}

function floorRow(image) {
  for (let y = image.height - 1; y >= 0; y--) {
    for (let x = 0; x < image.width; x++) {
      if (image.bitmap[(y * image.width + x) * 4 + 3] >= 30) return y;
    }
  }
  return image.height - 1;
}

function floorOverlay(image) {
  const out = onBackground(image, IDLE_BG);
  const y = floorRow(image);
  for (let x = 0; x < out.width; x++) {
    const offset = (y * out.width + x) * 4;
    out.bitmap[offset] = 255;
    out.bitmap[offset + 1] = 230;
    out.bitmap[offset + 2] = 0;
    out.bitmap[offset + 3] = 255;
  }
  return out;
}

async function loadSide(sheetPath, manifestPath) {
  const [sheet, manifest] = await Promise.all([
    readFile(sheetPath).then(Image.decode),
    readFile(manifestPath, "utf8").then(JSON.parse),
  ]);
  const region = manifest.poses.idle.region;
  const [x, y, w, h] = region;
  const idle = sheet.clone().crop(x, y, w, h);
  const measured = measureIdleGrounding(sheet.bitmap, sheet.width, region);
  return { sheet, manifest, idle, measured };
}

async function comparisonImage(before, after) {
  const gap = 24;
  const panelWidth = 540;
  const sheetHeight = 480;
  const idleHeight = 300;
  const beforeSheet = fit(onBackground(before.sheet, BG), panelWidth, sheetHeight);
  const afterSheet = fit(onBackground(after.sheet, BG), panelWidth, sheetHeight);
  const beforeIdle = fit(floorOverlay(before.idle), panelWidth, idleHeight);
  const afterIdle = fit(floorOverlay(after.idle), panelWidth, idleHeight);
  const topHeight = Math.max(beforeSheet.height, afterSheet.height);
  const bottomHeight = Math.max(beforeIdle.height, afterIdle.height);
  const out = new Image(panelWidth * 2 + gap, topHeight + gap + bottomHeight);
  out.fill(BG);
  out.composite(beforeSheet, Math.floor((panelWidth - beforeSheet.width) / 2), 0);
  out.composite(afterSheet, panelWidth + gap + Math.floor((panelWidth - afterSheet.width) / 2), 0);
  out.composite(beforeIdle, Math.floor((panelWidth - beforeIdle.width) / 2), topHeight + gap);
  out.composite(
    afterIdle,
    panelWidth + gap + Math.floor((panelWidth - afterIdle.width) / 2),
    topHeight + gap,
  );
  return out;
}

async function main() {
  await mkdir(OUT, { recursive: true });
  const report = {};
  for (const specimen of CASES) {
    const [before, after] = await Promise.all([
      loadSide(specimen.beforeSheet, specimen.beforeManifest),
      loadSide(specimen.afterSheet, specimen.afterManifest),
    ]);
    report[specimen.id] = {
      before: before.measured,
      after: after.measured,
      after_warnings: after.manifest.qa.warnings,
    };
    const image = await comparisonImage(before, after);
    await writeFile(join(OUT, `${VERSION}-${specimen.id}-before-after.png`), await image.encode());
  }
  await writeFile(join(OUT, `${VERSION}-comparison-metrics.json`), JSON.stringify(report, null, 2));
  for (const [id, value] of Object.entries(report)) {
    const summary = (side) => {
      const ratio = side.second_shallow_minimum_gap_ratio;
      return `contact ${(side.contact_fraction * 100).toFixed(1)}%, second ${ratio == null ? "—" : `${(ratio * 100).toFixed(1)}%`}`;
    };
    console.log(`${id}: ${summary(value.before)} -> ${summary(value.after)}`);
    if (value.after_warnings.length) console.log(`  warnings: ${value.after_warnings.join("; ")}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
