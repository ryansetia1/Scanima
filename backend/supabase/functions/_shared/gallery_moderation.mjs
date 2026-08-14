// Moderation Vision sekali per art_hash. Hanya untuk Edge runtime.
import { jalankanPrediksi } from "./replicate.ts";
import { parseModeration } from "./gallery_shared.mjs";

const MODEL_VISION = Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash";

const MODERATION_SCHEMA = {
  type: "object",
  required: ["safe"],
  properties: {
    safe: { type: "boolean" },
    reject_reason: { type: "string", nullable: true },
  },
};

const MODERATION_SYSTEM = `You moderate Anima creature sprite sheets for a public art gallery.
The image is a cartoon cel-shaded creature on a green screen background.

Respond with JSON only matching this schema:
${JSON.stringify(MODERATION_SCHEMA)}

Set safe:false if ANY of these appear in the sprite art:
- Human faces, bodies, or recognizable people
- Nudity, sexual content, gore, blood, or open wounds
- Hate symbols, drug paraphernalia, or realistic weapons aimed at people
- Text slurs or explicit language

Cartoon monsters derived from safe everyday objects or non-human animals are safe.
No prose outside JSON.`;

/** Satu panggilan Vision; tidak ada retry otomatis. */
export async function moderateSheetImage(signedUrl) {
  const raw = await jalankanPrediksi(MODEL_VISION, {
    prompt: "Moderate the attached sprite sheet for public gallery safety. JSON only.",
    images: [signedUrl],
    system_instruction: MODERATION_SYSTEM,
    temperature: 0.2,
    top_p: 0.9,
    max_output_tokens: 512,
    thinking_budget: 0,
    dynamic_thinking: false,
  }, 45_000);
  return parseModeration(raw);
}
