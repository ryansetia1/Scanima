#!/usr/bin/env node
/**
 * Free local alpha analysis for Anima grounding diagnosis.
 * Usage: node .scratch/anima-grounding/measure_grounding.mjs
 *
 * Measures how much of a creature's silhouette actually touches the floor line
 * the engine plants it on, and how far its other support points hang above it.
 *
 * The metric this script USED to report -- "foot spread" = max-min over the
 * lowest opaque pixel of every column -- is gone on purpose. It measured the
 * total range of the silhouette's lower boundary, so an upward-curving tail or
 * a raised snout counted as a hanging foot: Sunhound scored 74% and the biped
 * console control scored 44%, neither of which has any leg spread at all.
 */
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { Image } from "imagescript";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");
const OUT = "/tmp/anima-grounding";
const ALPHA_MIN = 0.12; // matches AnimaPresenter.OPAQUE_ALPHA_MIN
const MAGENTA = Image.rgbaToColor(255, 0, 255, 255);

/** Columns this close to the bbox bottom count as touching the floor. */
const CONTACT_TOLERANCE_PX = 8;
/** Depth beyond this fraction of body height is a tail/ear/snout, not a limb. */
const LIMB_DEPTH_LIMIT = 0.4;

// Home lobby scaling, mirrored from scan_flow.gd stage_scale_for().
const HOME_ART_HEIGHT = 1602.0;
const HOME_BODY_SPAN_RATIO = 0.23;
const HOME_BODY_SPAN_MIN_RATIO = 0.12;
const HOME_BODY_SPAN_MAX_RATIO = 0.42;
const HOME_BODY_HEIGHT_CURVE = 0.62;
const BODY_HEIGHT_REFERENCE_CM = 120.0;

const GODOT_USERDATA = join(
  homedir(),
  "Library/Application Support/Godot/app_userdata/Scanima/animas",
);

/**
 * The live collection, read from the sprite cache the running game wrote, so
 * these are byte-identical to what production serves. Cache layout is
 * `v6_<anima_id>_1/<sheet_hash>.png`; some entries predate the cached manifest,
 * so the idle region is derived instead: sheets are always a 3x3 grid with idle
 * top-left, and `render_metrics.reference_height_px` is by definition the idle
 * bbox height (verified equal on both specimens that ship a manifest).
 * `body_height_cm` and the owner's verdict are not in the manifest.
 */
const LIVE = [
  { id: "chromquartz", pv: "v45 synthesis", cm: 131, verdict: "rejected",
    dir: "v6_e85e253a-a055-40ab-9920-7f5698d5bac8_1", sheet: "fd185eeb96bcdfa9.png",
    label: "Chromquartz (synthesis, long-bodied object) — owner: WORST" },
  // Not in the sprite cache; pulled read-only with:
  //   supabase storage cp --experimental --linked \
  //     "ss:///anima_sheets/<owner>/<anima>/<hash>.png" /tmp/...
  { id: "stridarc", pv: "v41 capture", cm: 55, verdict: "rejected",
    path: "/tmp/anima-grounding-prod/stridarc.png",
    label: "Stridarc (capture, RC truck) — owner: BAD, balancing on one wheel" },
  { id: "gearbit-racer", pv: "v43 synthesis", cm: 85, verdict: "marginal",
    dir: "v6_9394e4b9-fdc2-4649-9b04-e46d32acf629_1", sheet: "5bf34b8a8bb97982.png",
    label: "Gearbit Racer (synthesis, long-bodied object)" },
  { id: "chromvein", pv: "v41 capture", cm: 150, verdict: "unrated",
    dir: "v6_b8eba06c-decc-4366-a0d0-be2be6703877_1", sheet: "0c5dde260cf15761.png",
    label: "Chromvein (capture, car — long-bodied object)" },
  { id: "drowake", pv: "v41 evolve", cm: 225, verdict: "unrated",
    dir: "v6_19949c2e-5d3d-41f6-9b02-4f0740b1cace_1", sheet: "d631d8d11c465627.png",
    label: "Drowake (evolve, upright bottle)" },
  { id: "mugingot", pv: "v41 evolve", cm: 117, verdict: "unrated",
    dir: "v6_a20bb2f0-e063-4b7c-8bab-bfaf261400b8_1", sheet: "9b12a1edeee6ebf8.png",
    label: "Mugingot (evolve, upright mug)" },
  { id: "sunhound", pv: "v28 evolve", cm: 95, verdict: "accepted",
    dir: "v6_2168d17e-440d-4ba3-9004-5104800c6722_1", sheet: "e00fd07ce6ff888b.png",
    label: "Sunhound (evolve, quadruped dog) — owner: ACCEPTABLE" },
  { id: "veridian", pv: "v26 evolve", cm: 180, verdict: "unrated",
    dir: "v6_c80ddef5-533d-4f36-9f26-7f449981e996_1", sheet: "9f349a2de81bdf95.png",
    label: "Veridian (evolve, long-bodied plant)" },
  { id: "playtron", pv: "v7 capture", cm: 50, verdict: "unrated",
    dir: "v6_99b04a1c-07be-4753-be04-ae68183817e6_1", sheet: "f90cc06d9a5af16a.png",
    label: "Playtron (capture, compact console)" },
];

const SPECIMENS = LIVE.map((a) => ({
  id: a.id,
  label: `${a.label} [${a.pv}]`,
  verdict: a.verdict,
  bodyHeightCm: a.cm,
  sheet: a.path ?? join(GODOT_USERDATA, a.dir, a.sheet),
  absolute: true,
  deriveGrid: true,
}));

function resolve(spec, key) {
  return spec.absolute ? spec[key] : join(ROOT, spec[key]);
}

function regionRect(manifest, pose) {
  const entry = manifest.poses?.[pose];
  if (!entry?.region) return null;
  const [x, y, w, h] = entry.region;
  return { x, y, w, h };
}

/** Lowest opaque row per column, -1 where the column is empty. */
function columnLowestY(image) {
  const { width, height } = image;
  const lows = new Int32Array(width).fill(-1);
  for (let x = 0; x < width; x++) {
    for (let y = height - 1; y >= 0; y--) {
      if ((image.getPixelAt(x + 1, y + 1) & 0xff) / 255 >= ALPHA_MIN) {
        lows[x] = y;
        break;
      }
    }
  }
  return lows;
}

function topOpaqueRow(image) {
  const { width, height } = image;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if ((image.getPixelAt(x + 1, y + 1) & 0xff) / 255 >= ALPHA_MIN) return y;
    }
  }
  return -1;
}

/** Contiguous column runs whose depth from the floor is within tolerance. */
function contactRuns(depths, tolerance) {
  const runs = [];
  let start = -1;
  for (let x = 0; x <= depths.length; x++) {
    const touching = x < depths.length && depths[x] !== null && depths[x] <= tolerance;
    if (touching && start < 0) start = x;
    if (!touching && start >= 0) {
      runs.push({ x0: start, x1: x - 1, columns: x - start });
      start = -1;
    }
  }
  return runs.sort((a, b) => b.columns - a.columns);
}

/**
 * Support points = local minima of the bottom profile shallow enough to be a
 * limb. ponytail: a fixed ±12px window with a 25px merge, not skeleton
 * inference. Ceiling: it can merge two paws that overlap in x within 25px;
 * upgrade to connected-component labelling on the alpha mask if that matters.
 */
function supportPoints(depths, bodyH) {
  const window = 12;
  const limit = bodyH * LIMB_DEPTH_LIMIT;
  const raw = [];
  for (let x = 0; x < depths.length; x++) {
    const d = depths[x];
    if (d === null || d > limit) continue;
    let isMin = true;
    for (let k = Math.max(0, x - window); k <= Math.min(depths.length - 1, x + window); k++) {
      if (depths[k] !== null && depths[k] < d) {
        isMin = false;
        break;
      }
    }
    if (isMin) raw.push({ x, depth: d });
  }
  const merged = [];
  for (const point of raw) {
    const last = merged[merged.length - 1];
    if (last && point.x - last.x <= 25) {
      if (point.depth < last.depth) last.depth = point.depth;
      last.x = point.x;
      continue;
    }
    merged.push({ ...point });
  }
  return merged;
}

/** Home lobby on-screen height, mirroring scan_flow.gd stage_scale_for(). */
function homeDisplayScale(bodyHeightCm, referenceHeightPx) {
  const ratio = Math.min(Math.max(bodyHeightCm, 20), 2000) / BODY_HEIGHT_REFERENCE_CM;
  const raw = HOME_ART_HEIGHT * HOME_BODY_SPAN_RATIO * Math.pow(ratio, HOME_BODY_HEIGHT_CURVE);
  const target = Math.min(
    Math.max(raw, HOME_ART_HEIGHT * HOME_BODY_SPAN_MIN_RATIO),
    HOME_ART_HEIGHT * HOME_BODY_SPAN_MAX_RATIO,
  );
  return { target, scale: target / referenceHeightPx };
}

/** Idle cell: from the manifest when present, else the top-left grid third. */
async function idleCell(spec) {
  const sheet = await Image.decode(readFileSync(resolve(spec, "sheet")));
  if (spec.deriveGrid) {
    return {
      cell: sheet.clone().crop(0, 0, Math.floor(sheet.width / 3), Math.floor(sheet.height / 3)),
      manifest: {},
    };
  }
  const manifest = JSON.parse(readFileSync(resolve(spec, "manifest"), "utf8"));
  const region = regionRect(manifest, "idle");
  if (!region) return null;
  return { cell: sheet.clone().crop(region.x, region.y, region.w, region.h), manifest };
}

async function measureIdle(spec) {
  const loaded = await idleCell(spec);
  if (!loaded) return null;
  const { cell, manifest } = loaded;

  const lows = columnLowestY(cell);
  const occupied = [...lows].map((v, x) => [x, v]).filter(([, v]) => v >= 0);
  if (occupied.length === 0) return null;
  const floorY = Math.max(...occupied.map(([, v]) => v));
  const topY = topOpaqueRow(cell);
  const bodyH = floorY - topY + 1;
  const bboxW = occupied[occupied.length - 1][0] - occupied[0][0] + 1;

  const depths = [...lows].map((v) => (v < 0 ? null : floorY - v));
  const touching = occupied.filter(([x]) => depths[x] <= CONTACT_TOLERANCE_PX).length;
  const runs = contactRuns(depths, CONTACT_TOLERANCE_PX);
  const supports = supportPoints(depths, bodyH);
  const deepestSupport = supports.length
    ? Math.max(...supports.map((s) => s.depth))
    : 0;
  // The discriminator: is there a SECOND support near the floor, or is the
  // creature balancing on one? Depth of the deepest support is not enough --
  // the accepted biped control hangs a non-limb feature 33% of its body height
  // while still standing on a planted pair.
  const byDepth = supports.map((s) => s.depth).sort((a, b) => a - b);
  const secondSupportGap = byDepth.length > 1 ? byDepth[1] : bodyH;

  const refH = manifest.render_metrics?.reference_height_px ?? bodyH;
  const home = homeDisplayScale(spec.bodyHeightCm, refH);

  return {
    id: spec.id,
    label: spec.label,
    owner_verdict: spec.verdict,
    prompt_version: manifest.prompt_version ?? null,
    species_key: manifest.species_key ?? null,
    body_height_cm: spec.bodyHeightCm,
    reference_height_px: refH,
    bbox: { w: bboxW, h: bodyH, floor_y: floorY },

    // Metric 1 — how much of the silhouette actually stands on the floor line.
    contact_columns: touching,
    occupied_columns: occupied.length,
    contact_fraction: Number((touching / occupied.length).toFixed(3)),

    // Metric 2 — how far the other support points hang above that line.
    support_points: supports.map((s) => ({
      x: s.x,
      depth_px: s.depth,
      depth_pct_body: Number(((s.depth / bodyH) * 100).toFixed(1)),
    })),
    deepest_support_px: deepestSupport,
    deepest_support_pct_body: Number(((deepestSupport / bodyH) * 100).toFixed(1)),

    // Metric 2b — distance from the floor to the SECOND-nearest support. This
    // is the one that tracks the owner's accept/reject calls.
    second_support_gap_px: secondSupportGap,
    second_support_gap_pct_body: Number(((secondSupportGap / bodyH) * 100).toFixed(1)),

    // Metric 3 — is one support carrying the whole creature?
    dominant_run_columns: runs[0]?.columns ?? 0,
    dominant_run_share_of_contact: touching
      ? Number(((runs[0]?.columns ?? 0) / touching).toFixed(3))
      : 0,
    contact_run_count: runs.length,

    // What the player actually sees in the Home lobby.
    home_display_height_px: Number(home.target.toFixed(1)),
    home_display_scale: Number(home.scale.toFixed(3)),
    deepest_support_onscreen_px: Number((deepestSupport * home.scale).toFixed(1)),
    second_support_gap_onscreen_px: Number((secondSupportGap * home.scale).toFixed(1)),
  };
}

async function main() {
  mkdirSync(OUT, { recursive: true });
  const report = { alphaThreshold: ALPHA_MIN, contactTolerancePx: CONTACT_TOLERANCE_PX, specimens: [] };

  for (const spec of SPECIMENS) {
    const measured = await measureIdle(spec);
    if (!measured) continue;
    report.specimens.push(measured);

    const { cell } = await idleCell(spec);
    const bg = new Image(cell.width, cell.height);
    bg.fill(MAGENTA);
    bg.composite(cell, 0, 0);
    writeFileSync(join(OUT, `${spec.id}-idle.png`), await bg.encode());
  }

  writeFileSync(join(OUT, "measurements.json"), JSON.stringify(report, null, 2));

  const head = (s) => `${s.owner_verdict.toUpperCase().padEnd(9)} ${s.id}`.padEnd(38);
  console.log("\nidle pose, alpha >= 0.12, contact tolerance 8px\n");
  for (const s of report.specimens) {
    console.log(head(s));
    console.log(
      `  bbox ${s.bbox.w}x${s.bbox.h}  contact ${s.contact_columns}/${s.occupied_columns}` +
        ` = ${(s.contact_fraction * 100).toFixed(1)}% of silhouette width`,
    );
    console.log(
      `  supports ${s.support_points.length}  deepest hang ${s.deepest_support_px}px` +
        ` = ${s.deepest_support_pct_body}% of body`,
    );
    console.log(
      `  SECOND support sits ${s.second_support_gap_px}px above floor` +
        ` = ${s.second_support_gap_pct_body}% of body` +
        ` -> ${s.second_support_gap_onscreen_px}px on screen`,
    );
    console.log(
      `  dominant contact run ${s.dominant_run_columns} cols =` +
        ` ${(s.dominant_run_share_of_contact * 100).toFixed(1)}% of all contact` +
        ` (${s.contact_run_count} runs)`,
    );
    console.log(
      `  Home: shows at ${s.home_display_height_px}px (scale ${s.home_display_scale}x)` +
        ` -> hang reads as ${s.deepest_support_onscreen_px}px on screen`,
    );
    console.log(
      `  support depths (% body): ${s.support_points.map((p) => p.depth_pct_body).join(", ")}\n`,
    );
  }
  console.log(`json: ${join(OUT, "measurements.json")}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
