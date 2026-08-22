import { baseStatTotal, normalizeBaseStats } from "./battle.mjs";
import { ELEMENT_ROSTER, isRosterElement, normalizeElement } from "./elements.mjs";
import { STRIKE_EFFECT_IDS, SURGE_EFFECT_IDS } from "./move_effects.mjs";
import {
  deriveMorphemeSpeciesName,
  deriveNameLineageAnchor,
  normalizeSuggestedName,
} from "./vision.mjs";

export const SYNTHESIS_MODES = Object.freeze([
  "dominant_a",
  "balanced",
  "dominant_b",
]);

export const SYNTHESIS_STAT_KEYS = Object.freeze([
  "hp",
  "atk",
  "def",
  "spd",
  "special",
]);

export const SYNTHESIS_STAT_CHOICES = Object.freeze([
  "source_a",
  "source_b",
  "blend",
  "remix_up",
  "remix_down",
]);

const HEIGHT_SCALES = Object.freeze({
  smaller: 0.85,
  weighted: 1,
  larger: 1.15,
});

const ELEMENT_EFFECTS = Object.freeze({
  metal: ["armor_pierce", "barrier"],
  wood: ["guard_break", "drain"],
  stone: ["armor_break", "barrier"],
  ceramic: ["guard_break", "barrier"],
  glass: ["armor_pierce", "slow"],
  plastic: ["guard_break", "barrier"],
  cloth: ["slow", "barrier"],
  paper: ["armor_pierce", "slow"],
  plant: ["drain", "barrier"],
  food: ["drain", "barrier"],
  fauna: ["guard_break", "drain"],
  flow: ["armor_break", "barrier"],
  spark: ["armor_pierce", "slow"],
  flame: ["burn", "barrier"],
  frost: ["slow", "barrier"],
  air: ["armor_pierce", "slow"],
  toxin: ["poison", "drain"],
  sound: ["guard_break", "barrier"],
});

const VFX_MOTIONS = new Set(["projectile", "sweep", "impact", "bloom"]);

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.round(n)));
}

function asShortString(value, field, max = 160) {
  const text = String(value ?? "").trim();
  if (!text) throw new Error(`${field} wajib`);
  // ponytail: prose Planner yang valid dipotong di trust boundary, bukan
  // menggagalkan Synthesis berbayar. Plafon: field enum/struktur tetap strict;
  // naikkan ke schema-native output jika model Replicate kelak mengeksposnya.
  return text.slice(0, max);
}

function asShortStringArray(value, field, min = 1, max = 5) {
  if (!Array.isArray(value)) throw new Error(`${field} wajib berupa array`);
  const out = value
    .map((entry) => String(entry ?? "").trim())
    .filter(Boolean)
    .slice(0, max)
    .map((entry) => entry.slice(0, 120));
  if (out.length < min) throw new Error(`${field} kurang lengkap`);
  return out;
}

function modeWeight(mode) {
  if (mode === "dominant_a") return 0.7;
  if (mode === "dominant_b") return 0.3;
  return 0.5;
}

function sourceHeight(source) {
  return clampInt(source?.body_height_cm, 20, 2000, 120);
}

function safeMoveName(value, fallback) {
  const name = String(value ?? "").trim().replace(/\s+/g, " ").slice(0, 24);
  if (!/^[A-Za-z][A-Za-z' -]{1,23}$/.test(name)) return fallback;
  return name;
}

function exactBudget(stats, targetTotal) {
  const target = clampInt(targetTotal, 50, 475, 250);
  const out = normalizeBaseStats(stats, target);
  let difference = target - SYNTHESIS_STAT_KEYS.reduce((sum, key) => sum + out[key], 0);
  let pass = 0;
  while (difference !== 0 && pass < 500) {
    const direction = difference > 0 ? 1 : -1;
    let changed = false;
    for (const key of SYNTHESIS_STAT_KEYS) {
      if (difference === 0) break;
      const next = out[key] + direction;
      if (next < 10 || next > 95) continue;
      out[key] = next;
      difference -= direction;
      changed = true;
    }
    if (!changed) break;
    pass += 1;
  }
  return out;
}

function statCandidate(kind, a, b, weightA) {
  const blend = Math.round(a * weightA + b * (1 - weightA));
  const remixDelta = Math.max(3, Math.round(Math.abs(a - b) * 0.2));
  if (kind === "source_a") return a;
  if (kind === "source_b") return b;
  if (kind === "remix_up") return blend + remixDelta;
  if (kind === "remix_down") return blend - remixDelta;
  return blend;
}

function effectPair(primary, secondary) {
  const strikePreferred = ELEMENT_EFFECTS[primary]?.[0] ?? "armor_pierce";
  const surgeElement = secondary || primary;
  const surgePreferred = ELEMENT_EFFECTS[surgeElement]?.[1] ?? "barrier";
  const strike = STRIKE_EFFECT_IDS.includes(strikePreferred)
    ? strikePreferred
    : STRIKE_EFFECT_IDS[0];
  let surge = SURGE_EFFECT_IDS.includes(surgePreferred)
    ? surgePreferred
    : SURGE_EFFECT_IDS[0];
  if (surge === strike) {
    surge = SURGE_EFFECT_IDS.find((candidate) => candidate !== strike) ?? "barrier";
  }
  return { strike, surge };
}

function normalizedVfx(value, field, fallbackMotion) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${field} wajib berupa object`);
  }
  const motion = String(value.motion ?? "").trim().toLowerCase();
  return {
    form: asShortString(value.form, `${field}.form`, 48),
    motion: VFX_MOTIONS.has(motion) ? motion : fallbackMotion,
    brief: asShortString(value.brief, `${field}.brief`, 160),
  };
}

function safeLineageAnchor(name) {
  try {
    return deriveNameLineageAnchor(name);
  } catch {
    return "synth";
  }
}

function uniqueSuggestedName(value, takenNames = []) {
  const base = normalizeSuggestedName(value, "Synthera").slice(0, 24);
  const taken = new Set(takenNames.map((name) => String(name ?? "").trim().toLowerCase()));
  if (!taken.has(base.toLowerCase())) return base;
  const alternatives = ["Nova", "Flux", "Arc", "Vera"];
  for (const suffix of alternatives) {
    const candidate = `${base.slice(0, Math.max(2, 24 - suffix.length))}${suffix}`;
    if (!taken.has(candidate.toLowerCase())) return candidate;
  }
  return base;
}

function resolveSynthesisSpeciesName(raw, namingVision, takenNames = []) {
  const reservedName = String(raw.suggested_name ?? "").trim();
  // Plan yang sudah di-reserve membawa species_key server. Replay tidak boleh
  // merakit ulang nama — takenNames sudah memuat nama Result yang baru dicetak.
  if (
    String(raw.species_key ?? "").startsWith("synthesis_")
    && reservedName
  ) {
    return {
      suggested_name: reservedName.slice(0, 24),
      name_lineage_anchor: raw.name_lineage_anchor
        || safeLineageAnchor(reservedName),
      selected_name_root: raw.selected_name_root,
      name_roots: Array.isArray(raw.name_roots) ? raw.name_roots : undefined,
    };
  }
  if (Array.isArray(raw.name_roots) && raw.name_roots.length === 6) {
    const generated = deriveMorphemeSpeciesName(
      { ...namingVision, name_roots: raw.name_roots },
      takenNames,
    );
    return { ...generated, name_roots: raw.name_roots };
  }
  if (reservedName) {
    const suggestedName = uniqueSuggestedName(reservedName, takenNames);
    return {
      suggested_name: suggestedName,
      name_lineage_anchor: safeLineageAnchor(suggestedName),
    };
  }
  return deriveMorphemeSpeciesName(namingVision, takenNames);
}

function speciesKeyFromName(name) {
  const slug = String(name ?? "")
    .toLowerCase()
    .replace(/[^a-z]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40);
  return `synthesis_${slug || "result"}`;
}

export function synthesisVisionInstruction(systemPrompt, schema) {
  return `${systemPrompt.trim()}\n\nReturn JSON matching this schema exactly:\n${
    JSON.stringify(schema)
  }\nDo not wrap the JSON in markdown fences. Write name_roots last.`;
}

export function validateSynthesisPlan(raw, opts = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("Synthesis Plan wajib berupa object");
  }
  const mode = String(opts.mode ?? "").trim();
  if (!SYNTHESIS_MODES.includes(mode)) throw new Error("mode Synthesis tidak sah");

  const sourceA = opts.sourceA ?? {};
  const sourceB = opts.sourceB ?? {};
  const statsA = normalizeBaseStats(sourceA.base_stats);
  const statsB = normalizeBaseStats(sourceB.base_stats);
  const weightA = modeWeight(mode);
  const choices = raw.stat_choices;
  if (!choices || typeof choices !== "object" || Array.isArray(choices)) {
    throw new Error("stat_choices wajib berupa object");
  }

  const candidateStats = {};
  const normalizedChoices = {};
  for (const key of SYNTHESIS_STAT_KEYS) {
    const choice = String(choices[key] ?? "").trim();
    if (!SYNTHESIS_STAT_CHOICES.includes(choice)) {
      throw new Error(`stat_choices.${key} tidak sah`);
    }
    normalizedChoices[key] = choice;
    candidateStats[key] = statCandidate(choice, statsA[key], statsB[key], weightA);
  }
  const targetTotal = Math.round(
    baseStatTotal(statsA) * weightA + baseStatTotal(statsB) * (1 - weightA),
  );
  const baseStats = exactBudget(candidateStats, targetTotal);

  const primary = normalizeElement(raw.primary_element, "");
  const secondaryRaw = String(raw.secondary_element ?? "").trim();
  const secondary = secondaryRaw ? normalizeElement(secondaryRaw, "") : "";
  if (!isRosterElement(primary)) throw new Error("primary_element tidak sah");
  if (secondaryRaw && !isRosterElement(secondary)) {
    throw new Error("secondary_element tidak sah");
  }
  if (secondary && secondary === primary) {
    throw new Error("secondary_element tidak boleh sama dengan primary");
  }

  const inheritance = raw.inheritance_summary;
  if (!inheritance || typeof inheritance !== "object" || Array.isArray(inheritance)) {
    throw new Error("inheritance_summary wajib berupa object");
  }
  const heightScale = String(raw.height_scale ?? "").trim();
  if (!(heightScale in HEIGHT_SCALES)) throw new Error("height_scale tidak sah");
  const weightedHeight = sourceHeight(sourceA) * weightA + sourceHeight(sourceB) * (1 - weightA);
  const effects = effectPair(primary, secondary);
  const generatedName = resolveSynthesisSpeciesName(raw, {
    element: primary,
    secondary_element: secondary || null,
    subject_kind: raw.subject_kind === "animal" ? "animal" : "object",
    creature_brief: String(raw.creature_brief ?? ""),
    signature_features: Array.isArray(raw.signature_features)
      ? raw.signature_features
      : [],
    species_key: `synthesis_${primary}_${secondary || "none"}`,
  }, opts.ownerNames ?? []);
  const suggestedName = generatedName.suggested_name;

  const plan = {
    suggested_name: suggestedName,
    name_lineage_anchor: generatedName.name_lineage_anchor,
    selected_name_root: generatedName.selected_name_root,
    name_roots: generatedName.name_roots,
    species_key: speciesKeyFromName(suggestedName),
    color_bucket: String(raw.color_bucket ?? "synthesis")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 40) || "synthesis",
    subject_kind: raw.subject_kind === "animal" ? "animal" : "object",
    primary_element: primary,
    secondary_element: secondary || null,
    rarity: clampInt(
      (Number(sourceA.rarity) + Number(sourceB.rarity)) / 2,
      1,
      5,
      1,
    ),
    base_stats: baseStats,
    stat_budget: targetTotal,
    stat_choices: normalizedChoices,
    stat_archetype: asShortString(raw.stat_archetype, "stat_archetype", 80),
    body_height_cm: clampInt(
      weightedHeight * HEIGHT_SCALES[heightScale],
      20,
      2000,
      120,
    ),
    height_scale: heightScale,
    creature_brief: asShortString(raw.creature_brief, "creature_brief", 320),
    body_plan: asShortString(raw.body_plan, "body_plan", 180),
    surface_finish: asShortString(raw.surface_finish, "surface_finish", 160),
    character_direction: asShortString(
      raw.character_direction,
      "character_direction",
      160,
    ),
    signature_features: asShortStringArray(
      raw.signature_features,
      "signature_features",
      mode === "balanced" ? 4 : 3,
      6,
    ),
    inheritance_summary: {
      source_a: asShortString(inheritance.source_a, "inheritance_summary.source_a", 180),
      source_b: asShortString(inheritance.source_b, "inheritance_summary.source_b", 180),
      coherence: asShortString(inheritance.coherence, "inheritance_summary.coherence", 180),
    },
    strike_name: safeMoveName(raw.strike_name, "Resonant Strike"),
    surge_name: safeMoveName(raw.surge_name, "Synthesis Burst"),
    strike_effect_id: effects.strike,
    surge_effect_id: effects.surge,
    strike_vfx: normalizedVfx(raw.strike_vfx, "strike_vfx", "sweep"),
    surge_vfx: normalizedVfx(raw.surge_vfx, "surge_vfx", "bloom"),
  };

  if (!ELEMENT_ROSTER.includes(plan.primary_element)) {
    throw new Error("primary_element di luar roster");
  }
  if (plan.secondary_element && !ELEMENT_ROSTER.includes(plan.secondary_element)) {
    throw new Error("secondary_element di luar roster");
  }
  if (SYNTHESIS_STAT_KEYS.reduce((sum, key) => sum + plan.base_stats[key], 0) !== targetTotal) {
    throw new Error("stat budget Synthesis tidak ternormalisasi");
  }
  return { plan };
}

export function assembleSynthesisPrompt(template, plan, sourceA, sourceB, mode) {
  const modeLabel = mode === "dominant_a"
    ? "Source A dominant (70/30)"
    : mode === "dominant_b"
    ? "Source B dominant (30/70)"
    : "Balanced (50/50)";
  return template
    .replaceAll("{{mode}}", modeLabel)
    .replaceAll("{{source_a_name}}", String(sourceA?.name ?? "Source A"))
    .replaceAll("{{source_b_name}}", String(sourceB?.name ?? "Source B"))
    .replaceAll("{{creature_brief}}", plan.creature_brief)
    .replaceAll(
      "{{signature_features_as_bullets}}",
      plan.signature_features.map((feature) => `- ${feature}`).join("\n"),
    )
    .replaceAll("{{body_plan}}", plan.body_plan)
    .replaceAll("{{surface_finish}}", plan.surface_finish)
    .replaceAll("{{character_direction}}", plan.character_direction)
    .replaceAll(
      "{{element_identity}}",
      plan.secondary_element
        ? `${plan.primary_element} / ${plan.secondary_element}`
        : plan.primary_element,
    )
    .replaceAll("{{strike_name}}", plan.strike_name)
    .replaceAll("{{surge_name}}", plan.surge_name)
    .replaceAll("{{strike_vfx}}", JSON.stringify(plan.strike_vfx))
    .replaceAll("{{surge_vfx}}", JSON.stringify(plan.surge_vfx));
}

export function synthesisWebhookUrl(baseUrl, generationId) {
  const url = new URL(baseUrl);
  url.searchParams.set("generation_id", generationId);
  return url.toString();
}
