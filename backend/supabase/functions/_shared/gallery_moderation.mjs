// Moderation Vision sekali (v1) atau dua pass (v2) per art_hash. Hanya untuk
// Edge runtime (bergantung ./replicate.ts). v1 tetap utuh sebagai jalur
// rollback feature_atlas_moderation_v2; lihat
// docs/designs/2026-08-23-atlas-moderation-admin.md. Parsing/decision table-nya
// murni dan hidup di gallery_shared.mjs supaya bisa diuji dari Node tanpa
// Replicate — re-exported di sini untuk pemanggil yang sudah memuat modul ini.
import { jalankanPrediksi } from "./replicate.ts";
import { parseModeration, parseModerationPass, moderationPassDecision } from "./gallery_shared.mjs";
import { VISION_THINKING } from "./vision.mjs";

export { moderationPassDecision, parseModerationPass };

const MODEL_VISION = Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash";
export const MODERATION_POLICY_VERSION = "v2";

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
- A specific nameable character, mascot, or creature design from an existing
  commercial franchise, game, anime, or film

Cartoon monsters derived from safe everyday objects or non-human animals are safe.
No prose outside JSON.`;

/** Satu panggilan Vision; tidak ada retry otomatis. Jalur v1, dipertahankan
 * sebagai rollback selama feature_atlas_moderation_v2=false. */
export async function moderateSheetImage(signedUrl) {
  const raw = await jalankanPrediksi(MODEL_VISION, {
    prompt: "Moderate the attached sprite sheet for public gallery safety. JSON only.",
    images: [signedUrl],
    system_instruction: MODERATION_SYSTEM,
    temperature: 0.2,
    top_p: 0.9,
    max_output_tokens: 512,
    ...VISION_THINKING,
  }, 45_000);
  return parseModeration(raw);
}

// --- v2: structured, two-pass moderation ------------------------------------

const PASS_CATEGORIES = ["none", "sexual", "gore", "hate", "ip_character"];

const PASS_SCHEMA = {
  type: "object",
  required: ["category", "confidence"],
  properties: {
    category: { type: "string", enum: PASS_CATEGORIES },
    confidence: { type: "string", enum: ["high", "low"] },
    matched_name: { type: "string", nullable: true },
    reason: { type: "string" },
  },
};

const PASS1_SYSTEM = `You moderate Anima creature sprite sheets for a public art gallery.
The image is a cartoon cel-shaded creature on a green screen background.

Respond with JSON only matching this schema:
${JSON.stringify(PASS_SCHEMA)}

category rules:
- "sexual", "gore", or "hate": nudity, sexual content, blood/open wounds,
  hate symbols, drug paraphernalia, realistic weapons aimed at people, text
  slurs, or explicit language appear in the sprite art.
- "ip_character": the design looks like it could be a specific nameable
  character, mascot, or creature from an existing commercial franchise, game,
  anime, or film — even if you are not fully certain. Use confidence "low"
  for any suspicion that isn't a slam-dunk match; a second independent pass
  will double-check every "ip_character" flag, so do not withhold it just
  because you're unsure.
- "none": a cartoon monster derived from a safe everyday object or a
  non-human animal, with no concerning resemblance.

Set matched_name to the specific franchise character name if category is
"ip_character" and you can name one, otherwise null. reason is one short
internal note, never shown to players. No prose outside JSON.`;

const PASS2_SYSTEM = `You are the SECOND, independent opinion on whether this Anima creature
sprite sheet resembles a specific existing commercial franchise character. A
first pass already flagged possible resemblance — look carefully and decide
for yourself; do not assume the first pass was right.

Respond with JSON only matching this schema:
${JSON.stringify(PASS_SCHEMA)}

- Only use category "ip_character" if you can name the SPECIFIC franchise
  character (matched_name) this design is clearly derived from. A generic
  resemblance ("looks like a mascot", "reminds me of a well-known creature
  design style") without a concrete nameable match is NOT enough — use
  category "none" instead.
- Use confidence "high" only when matched_name names a real, specific,
  well-known character and the resemblance is concrete and unmistakable.
- Use confidence "low" if you suspect a match but cannot name one specific
  character with confidence — this still counts as unresolved.
- "sexual"/"gore"/"hate" are out of scope for this pass (pass one already
  handles those); only report one here if you see something pass one could
  plausibly have missed.
No prose outside JSON.`;

/** Satu panggilan Vision per pass. Suhu naik sedikit di pass 2 supaya opini
 * kedua benar-benar independen, bukan mengulang jawaban pass 1 — pola yang
 * sama dengan resample Evolution plan (CLAUDE.md). Dipanggil paling banyak
 * dua kali per art_hash, tidak pernah tiga. */
export async function moderateSheetPass(signedUrl, pass) {
  const raw = await jalankanPrediksi(MODEL_VISION, {
    prompt: pass === 1
      ? "Moderate the attached sprite sheet for public gallery safety. JSON only."
      : "Give your independent second opinion on the attached sprite sheet. JSON only.",
    images: [signedUrl],
    system_instruction: pass === 1 ? PASS1_SYSTEM : PASS2_SYSTEM,
    temperature: pass === 1 ? 0.2 : 0.4,
    top_p: 0.9,
    max_output_tokens: 512,
    ...VISION_THINKING,
  }, 45_000);
  return { ...parseModerationPass(raw, pass), model: MODEL_VISION };
}
