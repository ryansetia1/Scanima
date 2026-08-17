import { readFile } from "node:fs/promises";
import { Image } from "imagescript";
import { encodeOptimizedPng } from "../../supabase/functions/_shared/png.mjs";

export const CHAPTER_CORE_CHASSIS = "chapter_core_v3";
export const CHAPTER_CORE_VESSEL = "point_hex_vessel_v1";
export const CHAPTER_CORE_SIZE = 512;

const VESSEL_URL = new URL("./static/point-hex-vessel.png", import.meta.url);
const RENDER_SCALE = 2;
const CENTER = CHAPTER_CORE_SIZE / 2;

const OUTER_POINTS = [
  [256, 24],
  [454, 140],
  [454, 372],
  [256, 488],
  [58, 372],
  [58, 140],
];

function scaledPoints(points) {
  return points.map(([x, y]) => [x * RENDER_SCALE, y * RENDER_SCALE]);
}

function insetPoints(points, factor) {
  return points.map(([x, y]) => [
    CENTER + (x - CENTER) * factor,
    CENTER + (y - CENTER) * factor,
  ]);
}

function pointInPolygon(x, y, points) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
    const [xi, yi] = points[i];
    const [xj, yj] = points[j];
    if (((yi > y) !== (yj > y)) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

function blendPixel(bitmap, width, x, y, color) {
  if (x < 0 || y < 0 || x >= width || y >= width) return;
  const offset = (y * width + x) * 4;
  const sourceAlpha = color[3] / 255;
  if (sourceAlpha <= 0) return;
  const destinationAlpha = bitmap[offset + 3] / 255;
  const outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha);
  if (outputAlpha <= 0) return;
  for (let channel = 0; channel < 3; channel += 1) {
    bitmap[offset + channel] = Math.round(
      (
        color[channel] * sourceAlpha +
        bitmap[offset + channel] * destinationAlpha * (1 - sourceAlpha)
      ) / outputAlpha,
    );
  }
  bitmap[offset + 3] = Math.round(outputAlpha * 255);
}

function fillPolygon(bitmap, width, points, color) {
  const minX = Math.max(0, Math.floor(Math.min(...points.map(([x]) => x))));
  const maxX = Math.min(width - 1, Math.ceil(Math.max(...points.map(([x]) => x))));
  const minY = Math.max(0, Math.floor(Math.min(...points.map(([, y]) => y))));
  const maxY = Math.min(width - 1, Math.ceil(Math.max(...points.map(([, y]) => y))));
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) {
      if (pointInPolygon(x + 0.5, y + 0.5, points)) {
        blendPixel(bitmap, width, x, y, color);
      }
    }
  }
}

function drawDisc(bitmap, width, cx, cy, radius, color) {
  const minX = Math.max(0, Math.floor(cx - radius));
  const maxX = Math.min(width - 1, Math.ceil(cx + radius));
  const minY = Math.max(0, Math.floor(cy - radius));
  const maxY = Math.min(width - 1, Math.ceil(cy + radius));
  const radiusSquared = radius * radius;
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= radiusSquared) {
        blendPixel(bitmap, width, x, y, color);
      }
    }
  }
}

function drawPolyline(bitmap, width, points, thickness, color) {
  for (let index = 0; index < points.length; index += 1) {
    const [startX, startY] = points[index];
    const [endX, endY] = points[(index + 1) % points.length];
    const distance = Math.hypot(endX - startX, endY - startY);
    const steps = Math.max(1, Math.ceil(distance));
    for (let step = 0; step <= steps; step += 1) {
      const mix = step / steps;
      drawDisc(
        bitmap,
        width,
        startX + (endX - startX) * mix,
        startY + (endY - startY) * mix,
        thickness / 2,
        color,
      );
    }
  }
}

function alphaBounds(image) {
  let minX = image.width;
  let minY = image.height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < image.height; y += 1) {
    for (let x = 0; x < image.width; x += 1) {
      if (image.bitmap[(y * image.width + x) * 4 + 3] < 8) continue;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }
  }
  if (maxX < minX || maxY < minY) throw new Error("CHAPTER_CORE_INNER_EMPTY");
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

function cropImage(image, bounds) {
  const cropped = new Image(bounds.width, bounds.height);
  cropped.bitmap.fill(0);
  for (let y = 0; y < bounds.height; y += 1) {
    const sourceOffset = ((bounds.y + y) * image.width + bounds.x) * 4;
    const destinationOffset = y * bounds.width * 4;
    cropped.bitmap.set(
      image.bitmap.subarray(sourceOffset, sourceOffset + bounds.width * 4),
      destinationOffset,
    );
  }
  return cropped;
}

function alphaComposite(destination, source, offsetX, offsetY) {
  for (let y = 0; y < source.height; y += 1) {
    for (let x = 0; x < source.width; x += 1) {
      const sourceOffset = (y * source.width + x) * 4;
      if (source.bitmap[sourceOffset + 3] === 0) continue;
      blendPixel(
        destination.bitmap,
        destination.width,
        offsetX + x,
        offsetY + y,
        source.bitmap.subarray(sourceOffset, sourceOffset + 4),
      );
    }
  }
}

/**
 * Encoder RGBA lossless untuk aset chapter. Perakitan chunk-nya sendiri sudah
 * dihapus: `_shared/png.mjs` melakukan hal yang sama plus adaptive row filtering,
 * dan encoder yang sama itu juga dipakai post-process production, jadi aset
 * chapter dan sheet Anima tidak lagi punya dua definisi "PNG optimal".
 */
export async function encodeRgbaPng(image) {
  return Buffer.from(await encodeOptimizedPng(image.bitmap, image.width, image.height));
}

export async function renderPointHexVesselOverlay() {
  const size = CHAPTER_CORE_SIZE * RENDER_SCALE;
  const image = new Image(size, size);
  image.bitmap.fill(0);
  const outer = scaledPoints(OUTER_POINTS);
  const inner = scaledPoints(insetPoints(OUTER_POINTS, 0.82));
  const facetColors = [
    [224, 247, 255, 88],
    [159, 215, 235, 78],
    [242, 251, 255, 104],
    [104, 164, 197, 72],
  ];

  fillPolygon(image.bitmap, size, outer, [176, 224, 241, 22]);
  for (let index = 0; index < outer.length; index += 1) {
    const next = (index + 1) % outer.length;
    fillPolygon(
      image.bitmap,
      size,
      [outer[index], outer[next], inner[next], inner[index]],
      facetColors[index % facetColors.length],
    );
  }
  fillPolygon(
    image.bitmap,
    size,
    scaledPoints([[118, 151], [143, 136], [291, 357], [269, 371]]),
    [255, 255, 255, 30],
  );
  drawPolyline(image.bitmap, size, outer, 6 * RENDER_SCALE, [17, 29, 54, 232]);
  drawPolyline(image.bitmap, size, inner, 3 * RENDER_SCALE, [37, 70, 99, 170]);
  return encodeRgbaPng(image.resize(CHAPTER_CORE_SIZE, CHAPTER_CORE_SIZE));
}

export async function composeChapterCore(innerPng) {
  const decoded = await Image.decode(innerPng);
  const bounds = alphaBounds(decoded);
  const cropped = cropImage(decoded, bounds);
  const maxInnerSize = 285;
  const scale = Math.min(maxInnerSize / cropped.width, maxInnerSize / cropped.height);
  const width = Math.max(1, Math.round(cropped.width * scale));
  const height = Math.max(1, Math.round(cropped.height * scale));
  const inner = cropped.resize(width, height);
  const vessel = await Image.decode(await readFile(VESSEL_URL));
  if (vessel.width !== CHAPTER_CORE_SIZE || vessel.height !== CHAPTER_CORE_SIZE) {
    throw new Error("CHAPTER_CORE_VESSEL_SIZE_INVALID");
  }
  const result = new Image(CHAPTER_CORE_SIZE, CHAPTER_CORE_SIZE);
  result.bitmap.fill(0);
  alphaComposite(
    result,
    inner,
    Math.round((CHAPTER_CORE_SIZE - width) / 2),
    Math.round((CHAPTER_CORE_SIZE - height) / 2),
  );
  alphaComposite(result, vessel, 0, 0);
  return encodeRgbaPng(result);
}
