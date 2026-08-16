import { createHash } from "node:crypto";
import { Image } from "imagescript";
import {
  DEFAULTS,
  LAYOUT_3X3,
  chromaKeyInPlace,
  layoutForPrompt,
  postprocessSheet,
  segmentPosePixels,
  softenAlphaEdges,
} from "../../supabase/functions/_shared/postprocess.mjs";
import { BOSS_SEEKER_POSES } from "./constants.mjs";
import { composeChapterCore, encodeRgbaPng } from "./core_vessel.mjs";

export function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function hashColor(seed) {
  let state = 0;
  for (let i = 0; i < seed.length; i += 1) state = (state * 31 + seed.charCodeAt(i)) >>> 0;
  const hue = state % 360;
  const sat = 0.55 + ((state >> 8) % 30) / 100;
  const val = 0.62 + ((state >> 16) % 25) / 100;
  return hsvToRgb(hue, sat, val);
}

function hsvToRgb(h, s, v) {
  const c = v * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = v - c;
  let r = 0; let g = 0; let b = 0;
  if (h < 60) [r, g, b] = [c, x, 0];
  else if (h < 120) [r, g, b] = [x, c, 0];
  else if (h < 180) [r, g, b] = [0, c, x];
  else if (h < 240) [r, g, b] = [0, x, c];
  else if (h < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  return [
    Math.round((r + m) * 255),
    Math.round((g + m) * 255),
    Math.round((b + m) * 255),
    255,
  ];
}

function fillRect(bitmap, width, x, y, w, h, color) {
  for (let row = y; row < y + h; row += 1) {
    for (let col = x; col < x + w; col += 1) {
      const offset = (row * width + col) * 4;
      bitmap.set(color, offset);
    }
  }
}

function drawBlob(bitmap, width, cx, cy, radius, color) {
  for (let y = cy - radius; y <= cy + radius; y += 1) {
    for (let x = cx - radius; x <= cx + radius; x += 1) {
      if (x < 0 || y < 0 || x >= width || y >= width) continue;
      const dx = x - cx;
      const dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) {
        fillRect(bitmap, width, x, y, 1, 1, color);
      }
    }
  }
}

export function buildGridManifest({
  sheetSize,
  frameSize,
  poses,
  meta = {},
  referenceHeightPx = null,
  referenceWidthPx = null,
}) {
  const regions = {};
  const grid = 3;
  const cellW = Math.floor(sheetSize / grid);
  const cellH = Math.floor(sheetSize / grid);
  for (let index = 0; index < poses.length; index += 1) {
    const pose = poses[index];
    const col = index % grid;
    const row = Math.floor(index / grid);
    regions[pose] = {
      region: [col * cellW, row * cellH, frameSize, frameSize],
    };
  }
  return {
    version: 1,
    sheet_size: [sheetSize, sheetSize],
    frame_size: [frameSize, frameSize],
    ...meta,
    poses: regions,
    ...(Number(referenceHeightPx) > 0
      ? {
        render_metrics: {
          reference_height_px: Math.round(Number(referenceHeightPx)),
          reference_width_px: Math.round(Number(referenceWidthPx) || frameSize),
        },
      }
      : {}),
    qa: {
      mode: "procedural",
      cells_detected: poses.length,
    },
  };
}

function capturedBBoxSize(bbox, poseIndex, sheetSize, frameSize) {
  if (!bbox || poseIndex < 0) return null;
  const cellSize = Math.floor(sheetSize / 3);
  const captureX = (poseIndex % 3) * cellSize;
  const captureY = Math.floor(poseIndex / 3) * cellSize;
  const x0 = Math.max(bbox.x, captureX);
  const y0 = Math.max(bbox.y, captureY);
  const x1 = Math.min(bbox.x + bbox.w, captureX + frameSize);
  const y1 = Math.min(bbox.y + bbox.h, captureY + frameSize);
  return {
    w: Math.max(0, x1 - x0),
    h: Math.max(0, y1 - y0),
  };
}

function hashFile(png) {
  return sha256Hex(png);
}

function auditGridCaptureOverlap(components, poses, sheetSize, frameSize) {
  const cellSize = Math.floor(sheetSize / 3);
  const regions = poses.map((pose, index) => ({
    pose,
    x: (index % 3) * cellSize,
    y: Math.floor(index / 3) * cellSize,
    w: frameSize,
    h: frameSize,
  }));
  const violations = [];
  for (const component of components) {
    if (component.pixels < DEFAULTS.minSeamLeakPixels) continue;
    const box = component.bbox;
    for (const region of regions) {
      if (region.pose === component.pose) continue;
      const overlaps = (
        box.x < region.x + region.w &&
        box.x + box.w > region.x &&
        box.y < region.y + region.h &&
        box.y + box.h > region.y
      );
      if (overlaps) {
        violations.push({
          pose: component.pose,
          leaks_into: region.pose,
          pixels: component.pixels,
          bbox: box,
        });
        break;
      }
    }
  }
  return { passed: violations.length === 0, violations };
}

export async function postprocessChapterAnima(rawPng, cast, {
  cleanupIdleSeamLeaks = false,
} = {}) {
  const processed = await postprocessSheet(rawPng, {
    speciesKey: cast.species_key,
    colorBucket: cast.color_bucket,
    stage: 2,
    promptVersion: "v12",
  }, cleanupIdleSeamLeaks ? { ...DEFAULTS, removeIdleSeamLeaks: true } : DEFAULTS);
  const png = encodeRgbaPng(await Image.decode(processed.png));
  const { manifest } = processed;
  const layout = layoutForPrompt("v12");
  const detected = Object.keys(manifest.poses ?? {});
  if (detected.length !== layout.poses.length) {
    throw new Error(
      `ANIMA_SHEET_INCOMPLETE:${cast.id}:${detected.length}/${layout.poses.length}`,
    );
  }
  return { png, manifest, hash: hashFile(png) };
}

export async function postprocessChromaGridSheet(rawPng, {
  poses,
  promptVersion = "chapter_factory/v1",
  meta = {},
}) {
  const decoded = await Image.decode(rawPng);
  const work = decoded.width === 1024 && decoded.height === 1024
    ? decoded
    : decoded.resize(1024, 1024);
  const keyed = chromaKeyInPlace(work.bitmap, DEFAULTS);
  if (keyed / (work.bitmap.length / 4) < DEFAULTS.minKeyedRatio) {
    throw new Error("GRID_BACKGROUND_NOT_CHROMA_GREEN");
  }
  softenAlphaEdges(work.bitmap, work.width, work.height, DEFAULTS);
  const layout = {
    grid: 3,
    poses,
    quadrant: Object.fromEntries(
      poses.map((pose, index) => [pose, [index % 3, Math.floor(index / 3)]]),
    ),
  };
  const segmented = segmentPosePixels(
    work.bitmap,
    work.width,
    work.height,
    DEFAULTS,
    layout,
  );
  const missing = poses.filter((pose) => !segmented.bboxes[pose]);
  if (missing.length > 0) throw new Error(`GRID_CELLS_MISSING:${missing.join(",")}`);
  const frameSize = 300;
  const seamAudit = auditGridCaptureOverlap(
    segmented.components,
    poses,
    work.width,
    frameSize,
  );
  if (!seamAudit.passed) {
    const summary = seamAudit.violations
      .map((entry) => `${entry.pose}->${entry.leaks_into}:${entry.pixels}px`)
      .join(", ");
    throw new Error(`GRID_SEAM_VIOLATION:${summary}`);
  }
  const png = encodeRgbaPng(work);
  const referencePose = segmented.bboxes.intro_idle ? "intro_idle" : "idle";
  const referenceSize = capturedBBoxSize(
    segmented.bboxes[referencePose],
    poses.indexOf(referencePose),
    work.width,
    frameSize,
  );
  const manifest = buildGridManifest({
    sheetSize: 1024,
    frameSize,
    poses,
    meta: { prompt_version: promptVersion, ...meta },
    referenceHeightPx: referenceSize?.h,
    referenceWidthPx: referenceSize?.w,
  });
  manifest.qa.mode = "chroma_grid";
  manifest.qa.capture_overlap = seamAudit;
  return { png, manifest, hash: hashFile(png) };
}

export async function postprocessChapterZone(rawPng) {
  const decoded = await Image.decode(rawPng);
  const targetRatio = 16 / 9;
  const sourceRatio = decoded.width / decoded.height;
  const width = sourceRatio > targetRatio
    ? Math.round(decoded.height * targetRatio)
    : decoded.width;
  const height = sourceRatio > targetRatio
    ? decoded.height
    : Math.round(decoded.width / targetRatio);
  if ((width * height) / (decoded.width * decoded.height) < 0.75) {
    throw new Error(`ZONE_ASPECT_INVALID:${decoded.width}x${decoded.height}`);
  }
  const cropped = decoded.crop(
    Math.floor((decoded.width - width) / 2),
    Math.floor((decoded.height - height) / 2),
    width,
    height,
  );
  const work = cropped.width === 768 && cropped.height === 432
    ? cropped
    : cropped.resize(768, 432);
  const png = encodeRgbaPng(work);
  return { png, hash: hashFile(png), manifest: null };
}

export async function postprocessChapterTrophy(rawPng) {
  const decoded = await Image.decode(rawPng);
  const work = decoded.width === 512 && decoded.height === 512
    ? decoded
    : decoded.resize(512, 512);
  const keyed = chromaKeyInPlace(work.bitmap, DEFAULTS);
  if (keyed / (work.bitmap.length / 4) < DEFAULTS.minKeyedRatio) {
    throw new Error("TROPHY_BACKGROUND_NOT_CHROMA_GREEN");
  }
  softenAlphaEdges(work.bitmap, work.width, work.height, DEFAULTS);
  const png = await composeChapterCore(await work.encode());
  return { png, hash: hashFile(png) };
}

export async function renderAnimaSheet(cast) {
  const animaId = typeof cast === "string" ? cast : cast.id;
  const sheetSize = 1024;
  const frameSize = 320;
  const image = new Image(sheetSize, sheetSize);
  image.bitmap.fill(0);
  const [r, g, b, a] = hashColor(animaId);
  const accent = [Math.min(255, r + 30), Math.min(255, g + 20), Math.min(255, b + 10), a];
  const grid = 3;
  const cellW = Math.floor(sheetSize / grid);
  const cellH = Math.floor(sheetSize / grid);
  for (let index = 0; index < LAYOUT_3X3.poses.length; index += 1) {
    const col = index % grid;
    const row = Math.floor(index / grid);
    const cx = col * cellW + Math.floor(cellW / 2);
    const cy = row * cellH + Math.floor(cellH / 2);
    const radius = 70 + (index % 3) * 8;
    drawBlob(image.bitmap, sheetSize, cx, cy, radius, [r, g, b, a]);
    drawBlob(image.bitmap, sheetSize, cx - 18, cy - 24, 12, accent);
    drawBlob(image.bitmap, sheetSize, cx + 18, cy - 24, 12, accent);
  }
  const png = await image.encode();
  const manifest = buildGridManifest({
    sheetSize,
    frameSize,
    poses: LAYOUT_3X3.poses,
    meta: {
      species_key: (typeof cast === "object" ? cast.species_key : animaId.replace(/-/g, "_")),
      color_bucket: typeof cast === "object" ? cast.color_bucket : "procedural",
      stage: 2,
      prompt_version: "chapter_factory/v1",
    },
  });
  return { png, manifest, hash: hashFile(png) };
}

export async function renderBossSeekerSheet(seekerId) {
  const sheetSize = 1024;
  const frameSize = 300;
  const image = new Image(sheetSize, sheetSize);
  image.bitmap.fill(0);
  const [r, g, b, a] = hashColor(`${seekerId}:boss`);
  const grid = 3;
  const cellW = Math.floor(sheetSize / grid);
  const cellH = Math.floor(sheetSize / grid);
  for (let index = 0; index < BOSS_SEEKER_POSES.length; index += 1) {
    const col = index % grid;
    const row = Math.floor(index / grid);
    const cx = col * cellW + Math.floor(cellW / 2);
    const cy = row * cellH + Math.floor(cellH / 2);
    drawBlob(image.bitmap, sheetSize, cx, cy, 88, [r, g, b, a]);
    fillRect(image.bitmap, sheetSize, cx - 40, cy + 40, 80, 8, [40, 30, 20, 255]);
  }
  const png = await image.encode();
  const manifest = buildGridManifest({
    sheetSize,
    frameSize,
    poses: BOSS_SEEKER_POSES,
    meta: {
      seeker_id: seekerId,
      prompt_version: "chapter_factory/v1",
    },
  });
  return { png, manifest, hash: hashFile(png) };
}

export async function renderZoneArt(zoneId) {
  const width = 768;
  const height = 432;
  const image = new Image(width, height);
  const [r, g, b] = hashColor(`${zoneId}:zone`);
  for (let y = 0; y < height; y += 1) {
    const mix = y / height;
    const color = [
      Math.round(r * (1 - mix * 0.35)),
      Math.round(g * (1 - mix * 0.25)),
      Math.round(b * (1 - mix * 0.15)),
      255,
    ];
    fillRect(image.bitmap, width, 0, y, width, 1, color);
  }
  for (let lane = 0; lane < 4; lane += 1) {
    fillRect(image.bitmap, width, 40 + lane * 170, 80, 120, 8, [255, 255, 255, 80]);
  }
  const png = await image.encode();
  return { png, hash: hashFile(png) };
}

export async function renderTrophyArt(trophySlug) {
  const size = 512;
  const image = new Image(size, size);
  image.bitmap.fill(0);
  const [r, g, b, a] = hashColor(`${trophySlug}:trophy`);
  drawBlob(image.bitmap, size, size / 2, size / 2, 180, [r, g, b, a]);
  drawBlob(image.bitmap, size, size / 2, size / 2 - 40, 70, [255, 230, 120, 255]);
  const png = await composeChapterCore(await image.encode());
  return { png, hash: hashFile(png) };
}

export async function imageDimensions(png) {
  const decoded = await Image.decode(png);
  return { width: decoded.width, height: decoded.height };
}
