// Evolution Plan extraction/validation and sprite prompt assembly.
// Shared by Edge Function and eval/selftest.

import { Image } from "imagescript";
import {
  normalizeMoveName,
  normalizeVfxPlan,
  VFX_FORMS,
  VFX_MOTIONS,
} from "./vision.mjs";
import { encodeImage } from "./png.mjs";
import {
  EFFECT_UPGRADES,
  EVOLUTION_EFFECT_IDS,
  STRIKE_EFFECT_IDS,
  SURGE_EFFECT_IDS,
  effectAllowed,
  evolvedEffectAllowed,
} from "./move_effects.mjs";

export {
  EFFECT_UPGRADES,
  EVOLUTION_EFFECT_IDS,
  STRIKE_EFFECT_IDS,
  SURGE_EFFECT_IDS,
} from "./move_effects.mjs";

const HEIGHT_BANDS = {
  2: { min: 1.15, max: 1.35 },
  3: { min: 1.20, max: 1.50 },
};

function clampHeight(cm) {
  return Math.max(20, Math.min(2000, Math.round(cm)));
}

function normalizeAnchors(raw) {
  return (Array.isArray(raw) ? raw : [])
    .map((value) => String(value ?? "").trim().replace(/\s+/g, " "))
    .filter(Boolean);
}

/** Crop the current Idle cell and flatten it onto exact chroma green. */
export async function buildEvolutionIdleReference(pngBuffer, manifest) {
  const decoded = await Image.decode(pngBuffer);
  const idle = manifest?.poses?.idle?.region;
  if (!Array.isArray(idle) || idle.length !== 4) {
    throw new Error("EVOLUTION_REFERENCE_IDLE_MISSING");
  }
  let [x, y, w, h] = idle.map((value) => Math.floor(Number(value)));
  if (![x, y, w, h].every(Number.isFinite)) {
    throw new Error("EVOLUTION_REFERENCE_REGION_INVALID");
  }
  x = Math.max(0, x);
  y = Math.max(0, y);
  w = Math.min(w, decoded.width - x);
  h = Math.min(h, decoded.height - y);
  if (w < 8 || h < 8) throw new Error("EVOLUTION_REFERENCE_REGION_INVALID");

  const cropped = decoded.crop(x, y, w, h);
  const reference = new Image(w, h);
  for (let offset = 0; offset < cropped.bitmap.length; offset += 4) {
    const alpha = cropped.bitmap[offset + 3] / 255;
    reference.bitmap[offset] = Math.round(cropped.bitmap[offset] * alpha);
    reference.bitmap[offset + 1] = Math.round(
      cropped.bitmap[offset + 1] * alpha + 255 * (1 - alpha),
    );
    reference.bitmap[offset + 2] = Math.round(cropped.bitmap[offset + 2] * alpha);
    reference.bitmap[offset + 3] = 255;
  }
  return await encodeImage(reference);
}

/**
 * Validate Evolution Plan JSON from Vision.
 * @param {unknown} raw
 * @param {object} opts
 * @param {number} opts.targetStage 2=Adult, 3=Evolved
 * @param {number} opts.priorHeightCm
 * @param {string} [opts.priorStrikeName]
 * @param {string} [opts.priorSurgeName]
 * @param {string} [opts.priorStrikeEffectId]
 * @param {string} [opts.priorSurgeEffectId]
 */
export function validateEvolutionPlan(raw, opts) {
  const issues = [];
  const plan = raw && typeof raw === "object" ? { ...raw } : {};

  const anchors = normalizeAnchors(plan.lineage_anchors);
  if (anchors.length !== 3) {
    issues.push("lineage_anchors harus tepat 3 entri non-kosong");
  } else {
    const distinct = new Set(anchors.map((a) => a.toLowerCase()));
    if (distinct.size !== 3) issues.push("lineage_anchors harus berbeda");
    plan.lineage_anchors = anchors;
  }

  const brief = String(plan.stage_brief ?? "").trim();
  if (!brief) issues.push("stage_brief kosong");
  else plan.stage_brief = brief.slice(0, 1200);

  if (plan.metamorphosis_notes != null) {
    plan.metamorphosis_notes = String(plan.metamorphosis_notes).trim().slice(0, 600) || null;
  }

  const priorHeight = Number(opts.priorHeightCm);
  if (!Number.isFinite(priorHeight) || priorHeight < 20) {
    throw new Error(`priorHeightCm tidak sah: ${opts.priorHeightCm}`);
  }

  const band = HEIGHT_BANDS[opts.targetStage];
  if (!band) throw new Error(`targetStage tidak sah: ${opts.targetStage}`);

  let height = Number(plan.body_height_cm);
  if (!Number.isInteger(height)) {
    issues.push("body_height_cm harus integer");
    height = clampHeight(priorHeight * ((band.min + band.max) / 2));
  }
  height = clampHeight(height);
  const minH = clampHeight(priorHeight * band.min);
  const maxH = clampHeight(priorHeight * band.max);
  if (height < priorHeight) {
    issues.push(`body_height_cm tidak boleh mengecil (${height} < ${priorHeight})`);
    height = minH;
  }
  if (height < minH || height > maxH) {
    issues.push(`body_height_cm di luar band stage ${opts.targetStage}: ${height} not in ${minH}..${maxH}`);
    height = Math.max(minH, Math.min(maxH, height));
  }
  plan.body_height_cm = height;

  const strike = normalizeMoveName(plan.strike_name);
  const surge = normalizeMoveName(plan.surge_name);
  if (!strike || strike.split(" ").length !== 2) issues.push("strike_name harus tepat dua kata");
  if (!surge || surge.split(" ").length !== 2) issues.push("surge_name harus tepat dua kata");
  if (strike && surge && strike.toLowerCase() === surge.toLowerCase()) {
    issues.push("strike_name dan surge_name tidak boleh sama");
  }
  const priorNames = [opts.priorStrikeName, opts.priorSurgeName]
    .map((name) => String(name ?? "").trim().toLowerCase())
    .filter(Boolean);
  if (strike && priorNames.includes(strike.toLowerCase())) {
    issues.push("strike_name harus baru untuk form ini");
  }
  if (surge && priorNames.includes(surge.toLowerCase())) {
    issues.push("surge_name harus baru untuk form ini");
  }
  plan.strike_name = strike;
  plan.surge_name = surge;

  const strikeFallback = {
    form: "arc",
    motion: "sweep",
    brief: "a compact object-faithful contact arc shaped by one structural anchor",
  };
  const surgeFallback = {
    form: "eruption",
    motion: "bloom",
    brief: "a larger object-faithful radial effect grown from the strongest anchor",
  };
  plan.strike_vfx = normalizeVfxPlan(plan.strike_vfx, strikeFallback);
  plan.surge_vfx = normalizeVfxPlan(plan.surge_vfx, surgeFallback);
  if (!VFX_FORMS.includes(plan.strike_vfx.form)) issues.push("strike_vfx form tidak sah");
  if (!VFX_MOTIONS.includes(plan.strike_vfx.motion)) issues.push("strike_vfx motion tidak sah");
  if (!VFX_FORMS.includes(plan.surge_vfx.form)) issues.push("surge_vfx form tidak sah");
  if (!VFX_MOTIONS.includes(plan.surge_vfx.motion)) issues.push("surge_vfx motion tidak sah");

  const strikeEffect = String(plan.strike_effect_id ?? "").trim();
  const surgeEffect = String(plan.surge_effect_id ?? "").trim();

  if (!STRIKE_EFFECT_IDS.includes(strikeEffect) && !SURGE_EFFECT_IDS.includes(strikeEffect)) {
    issues.push(`strike_effect_id tidak sah: ${strikeEffect}`);
  } else if (!effectAllowed("strike", strikeEffect)) {
    issues.push(`strike_effect_id tidak kompatibel dengan Attack: ${strikeEffect}`);
  } else if (opts.targetStage === 3 && !evolvedEffectAllowed("strike", strikeEffect, opts.priorStrikeEffectId)) {
    issues.push(`strike_effect_id bukan upgrade sah dari ${opts.priorStrikeEffectId}`);
  } else {
    plan.strike_effect_id = strikeEffect;
  }

  if (!SURGE_EFFECT_IDS.includes(surgeEffect)) {
    issues.push(`surge_effect_id tidak sah: ${surgeEffect}`);
  } else if (!effectAllowed("surge", surgeEffect)) {
    issues.push(`surge_effect_id tidak kompatibel dengan Special: ${surgeEffect}`);
  } else if (opts.targetStage === 3 && !evolvedEffectAllowed("surge", surgeEffect, opts.priorSurgeEffectId)) {
    issues.push(`surge_effect_id bukan upgrade sah dari ${opts.priorSurgeEffectId}`);
  } else {
    plan.surge_effect_id = surgeEffect;
  }

  if (strikeEffect && surgeEffect && strikeEffect === surgeEffect) {
    issues.push("strike_effect_id dan surge_effect_id harus berbeda");
  }

  if (issues.length) {
    throw new Error(issues.join("; "));
  }

  return { plan, issues };
}

/** Build Vision evolve system instruction (schema embedded like capture Vision). */
export function evolutionVisionInstruction(systemPrompt, schema) {
  return (
    `${systemPrompt}\n\n---\n\n## OUTPUT CONTRACT\n\n` +
    "Respond with a single JSON object and nothing else. No markdown fences, " +
    "no explanation before or after. It must conform to this schema:\n\n" +
    `${JSON.stringify(schema, null, 2)}\n`
  );
}

/**
 * Assemble sprite_sheet_evolve prompt from stored capture context + Plan.
 * @param {string} template
 * @param {object} plan validated Evolution Plan
 * @param {object} ctx species_key, object metadata from anima / capture
 */
export function assembleEvolvePrompt(template, plan, ctx = {}) {
  const anchorBullets = (plan.lineage_anchors ?? [])
    .map((feature) => `- ${feature}`)
    .join("\n");
  const stageName = plan.target_stage === 3 ? "Evolved" : "Adult";
  const out = template
    .replaceAll("{{stage_name}}", stageName)
    .replaceAll("{{evolution_brief}}", plan.stage_brief ?? "")
    .replaceAll("{{metamorphosis_notes}}", plan.metamorphosis_notes ?? "")
    .replaceAll("{{lineage_anchors_as_bullets}}", anchorBullets)
    .replaceAll("{{creature_brief}}", ctx.creature_brief ?? plan.stage_brief ?? "")
    .replaceAll(
      "{{signature_features_as_bullets}}",
      ctx.signature_features_as_bullets ?? anchorBullets,
    )
    .replaceAll("{{object_name}}", ctx.object_label ?? ctx.species_key ?? "unknown object")
    .replaceAll("{{surface_finish}}", ctx.surface_finish ?? "the object's visibly photographed material")
    .replaceAll("{{character_direction}}", ctx.character_direction ?? "object-led and visually neutral")
    .replaceAll("{{color_palette}}", ctx.color_palette ?? ctx.color_bucket ?? "object-derived palette")
    .replaceAll("{{personality}}", ctx.personality ?? "confident and evolved")
    .replaceAll("{{damage_hints_as_bullets}}", ctx.damage_hints_as_bullets ?? "- subtle wear faithful to the material")
    .replaceAll("{{strike_name}}", plan.strike_name ?? "a close-range strike")
    .replaceAll("{{surge_name}}", plan.surge_name ?? "a charged special burst")
    .replaceAll("{{strike_vfx_form}}", plan.strike_vfx?.form ?? "arc")
    .replaceAll("{{strike_vfx_motion}}", plan.strike_vfx?.motion ?? "sweep")
    .replaceAll("{{strike_vfx_brief}}", plan.strike_vfx?.brief ?? "a compact object-faithful contact effect")
    .replaceAll("{{surge_vfx_form}}", plan.surge_vfx?.form ?? "eruption")
    .replaceAll("{{surge_vfx_motion}}", plan.surge_vfx?.motion ?? "bloom")
    .replaceAll(
      "{{surge_vfx_brief}}",
      plan.surge_vfx?.brief ?? "a larger object-faithful radial effect",
    );

  const leftover = out.match(/\{\{[a-z_]+\}\}/g);
  if (leftover) throw new Error(`placeholder evolve belum terisi: ${leftover.join(", ")}`);
  return out;
}

/** Merge original capture Vision into image prompt context (never photo_path). */
export function buildEvolvePromptContext(captureVision, animaMeta = {}) {
  const v = captureVision && typeof captureVision === "object" ? captureVision : {};
  const meta = animaMeta && typeof animaMeta === "object" ? animaMeta : {};
  const features = Array.isArray(v.signature_features) ? v.signature_features : [];
  const damageHints = Array.isArray(v.damage_hints) ? v.damage_hints : [];
  const featureBullets = features.map((f) => `- ${String(f)}`).join("\n");
  const damageBullets = damageHints.length
    ? damageHints.map((hint) => `- ${String(hint)}`).join("\n")
    : "- subtle wear faithful to the material";

  return {
    species_key: meta.species_key ?? v.species_key,
    color_bucket: meta.color_bucket ?? v.color_bucket,
    object_label: v.object_label ?? meta.species_key ?? v.species_key ?? "unknown object",
    creature_brief: String(v.creature_brief ?? "").trim(),
    surface_finish: String(v.surface_finish ?? "").trim()
      || "the object's visibly photographed material",
    character_direction: String(v.character_direction ?? "").trim()
      || "object-led and visually neutral",
    color_palette: (Array.isArray(v.dominant_colors) ? v.dominant_colors : []).join(", ")
      || meta.color_bucket
      || v.color_bucket
      || "object-derived palette",
    personality: String(v.character_direction ?? "").trim()
      ? "expressive and faithful to the original capture"
      : "confident and evolved",
    signature_features_as_bullets: featureBullets,
    damage_hints_as_bullets: damageBullets,
  };
}

/** Webhook callback carries generation_id so prediction_id races can reconcile. */
export function evolutionWebhookUrl(baseUrl, generationId) {
  const url = new URL(baseUrl);
  url.searchParams.set("generation_id", generationId);
  return url.toString();
}

/** Transient finalize failures should 503 so Replicate retries; QA/postprocess should fail. */
export function evolutionFinalizeRetryable(message) {
  const msg = String(message ?? "");
  // Validation/RPC state errors are deterministic for the same paid output.
  // Retrying them only leaves the Anima evolving until the lease expires.
  if (/commit evolution gagal:\s*(EVOLUTION_|GEN_|ANIMA_|ALREADY_)/.test(msg)) {
    return false;
  }
  return msg.startsWith("EVOLUTION_TRANSIENT:")
    || msg.includes("unggah anima sheet gagal")
    || msg.includes("commit evolution gagal")
    || msg.includes("tandai generation succeeded gagal");
}

/** Self-check: validator rejects bad anchor count. */
export function _evolutionSelfCheck() {
  try {
    validateEvolutionPlan(
      {
        lineage_anchors: ["a", "b"],
        stage_brief: "x",
        body_height_cm: 140,
        strike_name: "A B",
        surge_name: "C D",
        strike_vfx: { form: "arc", motion: "sweep", brief: "x" },
        surge_vfx: { form: "ring", motion: "bloom", brief: "y" },
        strike_effect_id: "poison",
        surge_effect_id: "barrier",
      },
      { targetStage: 2, priorHeightCm: 100 },
    );
    throw new Error("validator should reject two anchors");
  } catch (e) {
    if (!String(e.message).includes("lineage_anchors")) throw e;
  }
}
