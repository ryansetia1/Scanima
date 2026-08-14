// Membuat dua sheet katalog 3×3. Default: gambar lokal ImageScript, NOL API.
// `--replicate` memanggil GPT Image 2 medium sekali per sheet (~$0.10 total)
// dan WAJIB flag eksplisit; tidak ada retry.
// `--rekey` mengulang chroma key + buang uap neon pada PNG yang sudah ada, NOL API.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Image } from "imagescript";
import { CATALOG_ITEMS } from "../backend/supabase/functions/_shared/catalog.mjs";
import { isCatalogKeyVapor, isKeyColor, softenAlphaEdges } from "../backend/supabase/functions/_shared/postprocess.mjs";
import { biayaGambarUsd } from "../backend/supabase/functions/_shared/pricing.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = join(ROOT, "game/assets/catalog");
const SIZE = 1024;
const CELL = SIZE / 3;
const GREEN = [0, 255, 0, 255];
const IMAGE_MODEL = "openai/gpt-image-2";
const IMAGE_QUALITY = "medium";
const POLL_MS = 2000;
const POLL_TIMEOUT_MS = 180_000;

loadEnv();

const FOOD_COLORS = [
  [220, 40, 70], [240, 210, 150], [70, 150, 80], [255, 170, 50], [180, 90, 220],
  [255, 110, 40], [250, 240, 210], [40, 90, 70], [255, 215, 70],
];
const ITEM_COLORS = [
  [40, 210, 255], [90, 70, 255], [255, 80, 110], [255, 70, 70], [180, 90, 255],
  [80, 140, 255], [40, 230, 200], [255, 200, 60], [220, 240, 255],
];

async function main() {
  if (process.argv.includes("--replicate")) {
    await generatePaidSheets();
    return;
  }
  if (process.argv.includes("--rekey")) {
    await rekeyExisting();
    return;
  }
  await mkdir(OUT_DIR, { recursive: true });
  const food = CATALOG_ITEMS.filter((item) => item.kind === "food");
  const items = CATALOG_ITEMS.filter((item) => item.kind === "item");
  await writeSheet(join(OUT_DIR, "food_sheet.png"), food, FOOD_COLORS, "food");
  await writeSheet(join(OUT_DIR, "item_sheet.png"), items, ITEM_COLORS, "item");
  console.log("catalog sheets written to", OUT_DIR);
}

function loadEnv() {
  for (const name of [".env", ".env.local"]) {
    try {
      process.loadEnvFile(join(ROOT, name));
    } catch {
      // file optional
    }
  }
}

async function generatePaidSheets() {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN belum di-set (taruh di .env.local)");
  const cost = 2 * biayaGambarUsd(IMAGE_MODEL, IMAGE_QUALITY);
  console.log(`catalog art --replicate: 2× ${IMAGE_MODEL} ${IMAGE_QUALITY}, ~$${cost.toFixed(2)}`);
  await mkdir(OUT_DIR, { recursive: true });
  const jobs = [
    ["food_sheet.png", join(ROOT, "backend/prompts/catalog/food_sheet.md")],
    ["item_sheet.png", join(ROOT, "backend/prompts/catalog/item_sheet.md")],
  ];
  for (const [name, promptPath] of jobs) {
    const prompt = await readFile(promptPath, "utf8");
    const png = await generateOnce(prompt);
    const img = await Image.decode(png);
    if (img.width !== SIZE || img.height !== SIZE) {
      throw new Error(`${name} ukuran ${img.width}×${img.height}, bukan 1024×1024`);
    }
    keyGreen(img);
    await writeFile(join(OUT_DIR, name), await img.encode());
    console.log("wrote", name);
  }
}

async function generateOnce(prompt) {
  const token = process.env.REPLICATE_API_TOKEN;
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const create = await fetch(`https://api.replicate.com/v1/models/${IMAGE_MODEL}/predictions`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      input: {
        prompt,
        aspect_ratio: "1024x1024",
        quality: IMAGE_QUALITY,
        number_of_images: 1,
        background: "opaque",
        output_format: "png",
        output_compression: 100,
        moderation: "auto",
      },
    }),
  });
  if (!create.ok) {
    throw new Error(`${IMAGE_MODEL} create ${create.status}: ${(await create.text()).slice(0, 500)}`);
  }
  let pred = await create.json();
  const started = Date.now();
  while (pred.status !== "succeeded" && pred.status !== "failed" && pred.status !== "canceled") {
    if (Date.now() - started > POLL_TIMEOUT_MS) {
      throw new Error(`${IMAGE_MODEL} timeout setelah ${POLL_TIMEOUT_MS / 1000}s`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    const poll = await fetch(`https://api.replicate.com/v1/predictions/${pred.id}`, { headers });
    if (!poll.ok) throw new Error(`${IMAGE_MODEL} poll ${poll.status}`);
    pred = await poll.json();
  }
  if (pred.status !== "succeeded") {
    throw new Error(`${IMAGE_MODEL} ${pred.status}: ${pred.error ?? "tanpa pesan"}`);
  }
  const url = Array.isArray(pred.output) ? pred.output[0] : pred.output;
  if (typeof url !== "string") throw new Error(`output tidak terduga: ${JSON.stringify(pred.output)}`);
  const png = await fetch(url);
  if (!png.ok) throw new Error(`gagal mengunduh hasil: ${png.status}`);
  return new Uint8Array(await png.arrayBuffer());
}

async function writeSheet(path, entries, palette, kind) {
  const img = new Image(SIZE, SIZE);
  img.fill(GREEN);
  for (const entry of entries) {
    const col = entry.sprite_index % 3;
    const row = Math.trunc(entry.sprite_index / 3);
    const cx = Math.round(col * CELL + CELL / 2);
    const cy = Math.round(row * CELL + CELL / 2);
    const color = palette[entry.sprite_index] ?? [255, 255, 255];
    paintIcon(img, cx, cy, color, kind, entry.sprite_index);
  }
  keyGreen(img);
  await writeFile(path, await img.encode());
}

function paintIcon(img, cx, cy, color, kind, index) {
  const [r, g, b] = color;
  const outline = [12, 20, 48];
  if (kind === "food") {
    fillCircle(img, cx, cy + 8, 78, outline);
    fillCircle(img, cx, cy, 70, [r, g, b]);
    fillCircle(img, cx - 22, cy - 18, 18, [255, 255, 255]);
    if (index % 2 === 0) fillCircle(img, cx, cy - 62, 22, [40, 160, 70]);
    else fillRect(img, cx - 10, cy - 88, 20, 36, [90, 50, 30]);
    return;
  }
  fillRect(img, cx - 70, cy - 54, 140, 108, outline);
  fillRect(img, cx - 62, cy - 46, 124, 92, [r, g, b]);
  fillRect(img, cx - 36, cy - 18, 72, 28, [255, 255, 255]);
  fillCircle(img, cx + 40, cy - 28, 14, [255, 230, 90]);
}

function fillCircle(img, cx, cy, radius, color) {
  const rr = radius * radius;
  for (let y = -radius; y <= radius; y += 1) {
    for (let x = -radius; x <= radius; x += 1) {
      if (x * x + y * y <= rr) put(img, cx + x, cy + y, color);
    }
  }
}

function fillRect(img, x, y, w, h, color) {
  for (let yy = 0; yy < h; yy += 1) {
    for (let xx = 0; xx < w; xx += 1) put(img, x + xx, y + yy, color);
  }
}

function put(img, x, y, color) {
  const px = Math.round(x);
  const py = Math.round(y);
  if (px < 0 || py < 0 || px >= SIZE || py >= SIZE) return;
  const o = (py * SIZE + px) * 4;
  img.bitmap[o] = color[0];
  img.bitmap[o + 1] = color[1];
  img.bitmap[o + 2] = color[2];
  img.bitmap[o + 3] = color[3] ?? 255;
}

async function rekeyExisting() {
  await mkdir(OUT_DIR, { recursive: true });
  for (const name of ["food_sheet.png", "item_sheet.png"]) {
    const path = join(OUT_DIR, name);
    const img = await Image.decode(await readFile(path));
    if (img.width !== SIZE || img.height !== SIZE) {
      throw new Error(`${name} ukuran ${img.width}×${img.height}, bukan 1024×1024`);
    }
    keyGreen(img);
    await writeFile(path, await img.encode());
    console.log("rekeyed", name);
  }
}

function isLooseCatalogLime(r, g, b) {
  if (!(g > r + 10 && g > b + 10)) return false;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  if (max === 0 || delta === 0) return false;
  const v = max / 255;
  const s = delta / max;
  let hue;
  if (max === r) hue = 60 * (((g - b) / delta) % 6);
  else if (max === g) hue = 60 * ((b - r) / delta + 2);
  else hue = 60 * ((r - g) / delta + 4);
  if (hue < 0) hue += 360;
  return hue >= 70 && hue <= 140 && s >= 0.4 && v >= 0.28;
}

function keyGreen(img) {
  const bitmap = img.bitmap;
  const n = SIZE * SIZE;
  const drop = new Uint8Array(n);
  for (let i = 0; i < n; i += 1) {
    const o = i * 4;
    if (bitmap[o + 3] < 8) continue;
    if (
      isKeyColor(bitmap[o], bitmap[o + 1], bitmap[o + 2])
      || isCatalogKeyVapor(bitmap[o], bitmap[o + 1], bitmap[o + 2])
    ) {
      drop[i] = 1;
    }
  }
  const next = Uint8Array.from(drop);
  for (let i = 0; i < n; i += 1) {
    if (drop[i] || bitmap[i * 4 + 3] < 8) continue;
    const x = i % SIZE;
    const y = (i / SIZE) | 0;
    const near = (
      (x > 0 && drop[i - 1])
      || (x < SIZE - 1 && drop[i + 1])
      || (y > 0 && drop[i - SIZE])
      || (y < SIZE - 1 && drop[i + SIZE])
    );
    if (!near) continue;
    if (isLooseCatalogLime(bitmap[i * 4], bitmap[i * 4 + 1], bitmap[i * 4 + 2])) {
      next[i] = 1;
    }
  }
  for (let i = 0; i < n; i += 1) {
    if (!next[i]) continue;
    const o = i * 4;
    bitmap[o] = 0;
    bitmap[o + 1] = 0;
    bitmap[o + 2] = 0;
    bitmap[o + 3] = 0;
  }
  softenAlphaEdges(bitmap, SIZE, SIZE);
}

await main();
