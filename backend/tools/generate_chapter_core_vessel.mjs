#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { Image } from "imagescript";
import { renderPointHexVesselOverlay } from "./chapter_factory/core_vessel.mjs";

const sha256Hex = (bytes) => createHash("sha256").update(bytes).digest("hex");

const targetUrl = new URL(
  "./chapter_factory/static/point-hex-vessel.png",
  import.meta.url,
);
const target = fileURLToPath(targetUrl);
const expected = await renderPointHexVesselOverlay();

if (process.argv.includes("--check")) {
  const stored = await readFile(target);
  const [storedImage, expectedImage] = await Promise.all([
    Image.decode(stored),
    Image.decode(expected),
  ]);
  if (
    storedImage.width !== expectedImage.width ||
    storedImage.height !== expectedImage.height ||
    !Buffer.from(storedImage.bitmap).equals(Buffer.from(expectedImage.bitmap))
  ) {
    throw new Error("CHAPTER_CORE_VESSEL_STALE");
  }
  console.log(`chapter_core_vessel: OK ${sha256Hex(stored)}`);
} else {
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, expected);
  console.log(`chapter_core_vessel: wrote ${target} ${sha256Hex(expected)}`);
}
