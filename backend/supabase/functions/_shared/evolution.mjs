// Evolution Plan extraction/validation and sprite prompt assembly.
// Shared by Edge Function and eval/selftest.

import { Image } from "imagescript";
import {
  deriveDeterministicEvolutionName,
  deriveCuratedHybridEvolutionName,
  deriveHybridEvolutionName,
  deriveMorphemeEvolutionName,
  deriveNameLineageAnchor,
  deriveTransformedHybridEvolutionName,
  normalizeNameLineageAnchor,
  normalizeMoveName,
  normalizeSuggestedName,
  normalizeVfxPlan,
  validateNameLineageAnchor,
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

export const EVOLUTION_ARCHETYPES = Object.freeze([
  "breakout",
  "unfolding",
  "inversion",
  "rooted_to_mobile",
  "shell_shedding",
  "mass_redistribution",
]);

export const SILHOUETTE_DIMENSIONS = Object.freeze([
  "dominant_mass",
  "posture",
  "outer_contour",
  "locomotion_or_body_plan",
]);

export const EVOLUTION_IDENTITY_DOMAINS = Object.freeze([
  "face_expression",
  "sensory",
  "structural_motif",
  "surface_signature",
  "motion_language",
]);

export const EVOLUTION_AURA_COLORS = Object.freeze([
  "gold",
  "amber",
  "orange",
  "crimson",
  "rose",
  "magenta",
  "violet",
  "indigo",
  "blue",
  "pale_cyan",
]);

export const EVOLUTION_PRESENCE_CHANNELS = Object.freeze([
  "silhouette_line",
  "proportion",
  "posture",
  "negative_space",
  "motion_language",
  "shape_distribution",
  "focal_motif",
]);

const EVOLUTION_SHAPE_ROLES = Object.freeze(["dominant", "support", "counterbalance"]);
const EVOLUTION_SIMPLIFICATION_ACTIONS = Object.freeze(["merge", "enlarge", "omit"]);
const EVOLUTION_REPETITION_POLICIES = Object.freeze([
  "none",
  "single_cluster",
  "broad_grouped_pattern",
]);

const FORBIDDEN_CHROMA_WORDS =
  /\b(?:green|lime|chartreuse|emerald|verdant|yellow[- ]green|neon[- ]green|electric[- ]green)\b/i;
const CHARACTER_AURA_WORDS =
  /\b(?:aura|halo|corona|glow(?:s|ed|ing)?|luminous|radiant|particles?)\b|\b(?:orbiting|surrounding|external)\s+(?:energy|glow|particles?)\b/i;
const OVERDETAIL_WORDS =
  /\b(?:intricate|ornate|micro[- ]detail(?:ed)?|deeply textured|multi[- ]tiered|densely detailed|highly detailed|more numerous)\b/i;

function clampHeight(cm) {
  return Math.max(20, Math.min(2000, Math.round(cm)));
}

function normalizeAnchors(raw) {
  return (Array.isArray(raw) ? raw : [])
    .map((value) => String(value ?? "").trim().replace(/\s+/g, " "))
    .filter(Boolean);
}

function normalizedText(value, maxLength = 800) {
  return String(value ?? "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function normalizeIdentityInvariant(raw) {
  const item = raw && typeof raw === "object" ? raw : {};
  const invariant = {
    identity_id: normalizedText(item.identity_id, 64).toLowerCase(),
    domain: normalizedText(item.domain, 32).toLowerCase(),
    source_truth: normalizedText(item.source_truth, 320),
    identity_role: normalizedText(item.identity_role, 240),
    current_expression: normalizedText(item.current_expression, 320),
    evolved_policy: normalizedText(item.evolved_policy, 24).toLowerCase(),
    realization_mode: normalizedText(item.realization_mode, 24).toLowerCase(),
    visible_lineage_evidence: normalizedText(item.visible_lineage_evidence, 320),
  };
  const maturationPath = normalizedText(item.maturation_path, 360);
  if (maturationPath) invariant.maturation_path = maturationPath;
  return invariant;
}

function semanticText(value) {
  return normalizedText(value, 800).toLowerCase().replace(/[.!?;:,]+$/g, "");
}

function tracesLineageAnchor(derivedFrom, sourceFeature) {
  const derived = semanticText(derivedFrom);
  const source = semanticText(sourceFeature);
  if (!derived || !source) return false;
  if (derived === source) return true;
  const derivedTokens = derived.split(/\s+/).filter(Boolean);
  const sourceTokens = source.split(/\s+/).filter(Boolean);
  if (derivedTokens.length >= 2 && derivedTokens.every((token) => sourceTokens.includes(token))) {
    return true;
  }
  if (sourceTokens.length >= 2 && sourceTokens.every((token) => derivedTokens.includes(token))) {
    return true;
  }
  return false;
}

function requestsForbiddenVisual(value, pattern) {
  const text = semanticText(value)
    .replace(
      /\b(?:no|without|never|zero|free of)\s+(?:an?\s+)?(?:aura|halo|corona|glow(?:s|ed|ing)?|luminous light|radiant light|particles?|external glow|surrounding energy|orbiting energy|intricate detail|ornate detail|micro[- ]detail)\b/g,
      "",
    )
    .replace(
      /\b(?:does not|do not|must not)\s+(?:have|use|show|render|add)\s+(?:an?\s+)?(?:aura|halo|corona|glow(?:s|ed|ing)?|luminous light|radiant light|particles?|external glow|surrounding energy|orbiting energy|intricate detail|ornate detail|micro[- ]detail)\b/g,
      "",
    );
  return pattern.test(text);
}

const IMMOBILE_RESULT_WORDS =
  /\b(?:immobile|planted|pedestal|stump|fixed in place|locked to (?:the )?ground|rooted to|fused to|subtle shifts?|future mobility|cannot move|unmovable|interwoven|interweave)\b|root[-_ ]mass|root[-_ ]mound/i;

function requestsImmobileResult(value) {
  const denied = semanticText(value)
    .replace(
      /\b(?:without|never|not|no longer)\s+(?:becoming|being|remaining|a\s+)?(?:an?\s+)?(?:fused\s+)?(?:immobile|stationary|planted|rooted|pedestal|stump|root mound|root mass|fixed(?: in place)?)\b/g,
      "",
    )
    .replace(/\b(?:never|not|without|no longer)\s+fused(?:\s+to(?:\s+(?:the\s+)?ground)?)?\b/g, "");
  return IMMOBILE_RESULT_WORDS.test(denied);
}

function deniesVisibleDescendant(value) {
  const text = semanticText(value);
  return /\b(?:is|are|becomes?|became|remains?|stays?|now)\s+(?:fully\s+)?(?:hidden|lost|removed|absent|invisible|implied|concealed|covered)\b/i.test(text)
    || /\b(?:hidden|lost|removed|concealed|covered)\s+(?:beneath|behind|inside|under)\b/i.test(text)
    || /\bno longer\s+(?:visible|present|readable|recognizable)\b/i.test(text)
    || /\b(?:disappears?|vanishes?)\b/i.test(text);
}

function validateV23IdentityPlan(plan, opts, issues) {
  const invariants = (Array.isArray(plan.identity_invariants) ? plan.identity_invariants : [])
    .map(normalizeIdentityInvariant);
  if (invariants.length < 2 || invariants.length > 4) {
    issues.push("identity_invariants v23 harus 2–4 entri");
  }

  const ids = new Set(invariants.map((item) => item.identity_id));
  if (
    invariants.some((item) => !/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/.test(item.identity_id))
  ) {
    issues.push("identity_id harus slug snake_case unik");
  }
  if (ids.size !== invariants.length) issues.push("identity_id harus berbeda");
  if (invariants.some((item) => !EVOLUTION_IDENTITY_DOMAINS.includes(item.domain))) {
    issues.push("domain identity_invariants tidak sah");
  }
  if (
    invariants.some((item) =>
      !item.source_truth
      || !item.identity_role
      || !item.current_expression
      || !item.visible_lineage_evidence
    )
  ) {
    issues.push("identity_invariants harus punya source truth, role, expression, dan evidence");
  }
  if (
    Number(opts.contractVersion ?? 21) >= 24
    && invariants.some((item) => !item.maturation_path)
  ) {
    issues.push("Identity Invariants v24 harus punya maturation_path");
  }
  if (
    invariants.some((item) => !["preserve", "may_transfigure"].includes(item.evolved_policy))
  ) {
    issues.push("evolved_policy harus preserve atau may_transfigure");
  }
  if (
    invariants.some((item) => !["preserve", "transfigure"].includes(item.realization_mode))
  ) {
    issues.push("realization_mode harus preserve atau transfigure");
  }

  const flexibleCount = invariants.filter(
    (item) => item.evolved_policy === "may_transfigure",
  ).length;
  if (flexibleCount > 1) issues.push("maksimal satu Identity Invariant boleh may_transfigure");
  if (flexibleCount === 1 && invariants.length < 3) {
    issues.push("may_transfigure membutuhkan minimal tiga Identity Invariants");
  }

  if (opts.targetStage === 2) {
    if (invariants.some((item) => item.realization_mode !== "preserve")) {
      issues.push("Adult harus preserve seluruh Identity Invariants");
    }
    plan.identity_invariants = invariants;
    return;
  }

  if (opts.targetStage !== 3) {
    plan.identity_invariants = invariants;
    return;
  }

  const prior = (Array.isArray(opts.priorIdentityInvariants)
    ? opts.priorIdentityInvariants
    : []).map(normalizeIdentityInvariant);
  const priorIds = new Set(prior.map((item) => item.identity_id));
  if (prior.length < 2 || prior.length > 4 || priorIds.size !== prior.length) {
    issues.push("Evolved v23 membutuhkan prior Identity Invariants Adult yang sah");
    plan.identity_invariants = invariants;
    return;
  }

  const currentById = new Map(invariants.map((item) => [item.identity_id, item]));
  if (
    invariants.length !== prior.length
    || prior.some((item) => !currentById.has(item.identity_id))
  ) {
    issues.push("Evolved harus mewarisi ID set Identity Invariants Adult");
    plan.identity_invariants = invariants;
    return;
  }

  const canonical = prior.map((priorItem) => currentById.get(priorItem.identity_id));
  for (let index = 0; index < prior.length; index += 1) {
    const before = prior[index];
    const current = canonical[index];
    if (
      current.domain !== before.domain
      || current.evolved_policy !== before.evolved_policy
      || semanticText(current.source_truth) !== semanticText(before.source_truth)
      || semanticText(current.identity_role) !== semanticText(before.identity_role)
      || (
        Number(opts.contractVersion ?? 21) >= 24
        && semanticText(current.maturation_path) !== semanticText(before.maturation_path)
      )
    ) {
      issues.push(`Identity Invariant terkunci berubah: ${before.identity_id}`);
    }
  }

  const transfigured = canonical.filter((item) => item.realization_mode === "transfigure");
  if (transfigured.length > 1) {
    issues.push("Evolved maksimal mentransfigurasi satu Identity Invariant");
  }
  if (transfigured.some((item) => item.evolved_policy !== "may_transfigure")) {
    issues.push("transfigure hanya sah untuk Identity Invariant may_transfigure");
  }
  if (canonical.filter((item) => item.realization_mode === "preserve").length < 2) {
    issues.push("Evolved harus preserve minimal dua Identity Invariants");
  }

  const priorHasFaceRead = prior.some(
    (item) => item.domain === "face_expression" || item.domain === "sensory",
  );
  const preservesFaceRead = canonical.some(
    (item) =>
      (item.domain === "face_expression" || item.domain === "sensory")
      && item.realization_mode === "preserve",
  );
  if (priorHasFaceRead && !preservesFaceRead) {
    issues.push("Evolved harus preserve minimal satu identity read wajah atau sensory");
  }

  if (
    transfigured.some((item) =>
      deniesVisibleDescendant(item.current_expression)
      || deniesVisibleDescendant(item.visible_lineage_evidence)
    )
  ) {
    issues.push("transfigure harus punya turunan visual yang terlihat, bukan hilang atau tersirat");
  }
  plan.identity_invariants = canonical;
}

function validateV24MaturityPresencePlan(plan, opts, issues) {
  const rawMaturity = plan.maturity_contract && typeof plan.maturity_contract === "object"
    ? plan.maturity_contract
    : {};
  const maturity = {
    target_read: normalizedText(rawMaturity.target_read, 24).toLowerCase(),
    facial_maturation: normalizedText(rawMaturity.facial_maturation, 480),
    body_maturation: normalizedText(rawMaturity.body_maturation, 480),
    posture_maturation: normalizedText(rawMaturity.posture_maturation, 480),
    preserved_personality: normalizedText(rawMaturity.preserved_personality, 360),
    stage_delta: normalizedText(rawMaturity.stage_delta, 480),
  };
  const expectedRead = opts.targetStage === 3 ? "apex" : "adult";
  if (maturity.target_read !== expectedRead) {
    issues.push(`maturity_contract.target_read stage ${opts.targetStage} harus ${expectedRead}`);
  }
  if (
    [
      maturity.facial_maturation,
      maturity.body_maturation,
      maturity.posture_maturation,
      maturity.preserved_personality,
      maturity.stage_delta,
    ].some((value) => value.length < 12)
  ) {
    issues.push("maturity_contract v24 harus menjelaskan wajah, tubuh, postur, personality, dan stage delta");
  }
  plan.maturity_contract = maturity;

  const rawPresence = plan.presence_contract && typeof plan.presence_contract === "object"
    ? plan.presence_contract
    : {};
  const auraPalette = [
    ...new Set(
      (Array.isArray(rawPresence.aura_palette) ? rawPresence.aura_palette : [])
        .map((value) => normalizedText(value, 24).toLowerCase().replace(/\s+/g, "_"))
        .filter(Boolean),
    ),
  ];
  const grandeurCues = (
    Array.isArray(rawPresence.grandeur_cues) ? rawPresence.grandeur_cues : []
  )
    .map((value) => normalizedText(value, 240))
    .filter(Boolean);
  const presence = {
    presence_tier: normalizedText(rawPresence.presence_tier, 24).toLowerCase(),
    power_center: normalizedText(rawPresence.power_center, 480),
    mass_hierarchy: normalizedText(rawPresence.mass_hierarchy, 480),
    authority_pose: normalizedText(rawPresence.authority_pose, 480),
    aura_architecture: normalizedText(rawPresence.aura_architecture, 480),
    aura_palette: auraPalette,
    grandeur_cues: grandeurCues,
    reliability_cue: normalizedText(rawPresence.reliability_cue, 360),
  };
  const expectedTier = opts.targetStage === 3 ? "apex" : "developing";
  if (presence.presence_tier !== expectedTier) {
    issues.push(`presence_contract.presence_tier stage ${opts.targetStage} harus ${expectedTier}`);
  }
  if (
    [
      presence.power_center,
      presence.mass_hierarchy,
      presence.authority_pose,
      presence.aura_architecture,
      presence.reliability_cue,
    ].some((value) => value.length < 12)
  ) {
    issues.push("presence_contract v24 harus menjelaskan power center, mass hierarchy, pose, aura, dan reliability");
  }
  if (
    auraPalette.length < 1
    || auraPalette.length > 2
    || auraPalette.some((color) => !EVOLUTION_AURA_COLORS.includes(color))
  ) {
    issues.push("aura_palette harus 1–2 warna non-green dari allowlist v24");
  }
  if (
    grandeurCues.length < 2
    || grandeurCues.length > 4
    || new Set(grandeurCues.map((cue) => cue.toLowerCase())).size !== grandeurCues.length
  ) {
    issues.push("grandeur_cues harus 2–4 entri berbeda");
  }
  if (FORBIDDEN_CHROMA_WORDS.test(presence.aura_architecture)) {
    issues.push("aura_architecture tidak boleh meminta warna green/near-chroma");
  }

  const paletteLabels = auraPalette.map((color) => color.replaceAll("_", " "));
  for (const [field, value] of [
    ["strike_vfx.brief", plan.strike_vfx?.brief],
    ["surge_vfx.brief", plan.surge_vfx?.brief],
  ]) {
    const brief = normalizedText(value, 500).toLowerCase().replaceAll("_", " ");
    if (FORBIDDEN_CHROMA_WORDS.test(brief)) {
      issues.push(`${field} tidak boleh meminta warna green/near-chroma`);
    }
    if (paletteLabels.length && !paletteLabels.some((color) => brief.includes(color))) {
      issues.push(`${field} harus menyebut warna dari aura_palette v24`);
    }
  }
  plan.presence_contract = presence;
}

function validateV25ShapeClarityPlan(plan, opts, issues) {
  const rawShape = plan.shape_budget_contract && typeof plan.shape_budget_contract === "object"
    ? plan.shape_budget_contract
    : {};
  const primaryShapes = (
    Array.isArray(rawShape.primary_shapes) ? rawShape.primary_shapes : []
  ).map((raw) => {
    const item = raw && typeof raw === "object" ? raw : {};
    return {
      shape_id: normalizedText(item.shape_id, 64).toLowerCase(),
      source_basis: normalizedText(item.source_basis, 320),
      stage_expression: normalizedText(item.stage_expression, 360),
      visual_role: normalizedText(item.visual_role, 24).toLowerCase(),
    };
  });
  if (primaryShapes.length < 2 || primaryShapes.length > 3) {
    issues.push("primary_shapes v25 harus 2–3 entri");
  }
  const shapeIds = new Set(primaryShapes.map((item) => item.shape_id));
  if (
    primaryShapes.some((item) => !/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/.test(item.shape_id))
    || shapeIds.size !== primaryShapes.length
  ) {
    issues.push("shape_id v25 harus slug snake_case unik");
  }
  if (
    primaryShapes.some((item) =>
      item.source_basis.length < 12
      || item.stage_expression.length < 12
      || !EVOLUTION_SHAPE_ROLES.includes(item.visual_role)
    )
  ) {
    issues.push("primary_shapes v25 harus punya source, expression, dan visual_role sah");
  }
  if (primaryShapes.filter((item) => item.visual_role === "dominant").length !== 1) {
    issues.push("primary_shapes v25 harus punya tepat satu dominant read");
  }

  const rawMotif = rawShape.dominant_motif && typeof rawShape.dominant_motif === "object"
    ? rawShape.dominant_motif
    : {};
  const dominantMotif = {
    source_basis: normalizedText(rawMotif.source_basis, 320),
    stage_expression: normalizedText(rawMotif.stage_expression, 360),
  };
  if (dominantMotif.source_basis.length < 12 || dominantMotif.stage_expression.length < 12) {
    issues.push("dominant_motif v25 harus punya source dan stage expression");
  }

  const rawFocal = (
    rawShape.identity_focal_structure
    && typeof rawShape.identity_focal_structure === "object"
  ) ? rawShape.identity_focal_structure : {};
  const identityFocal = {
    source_read: normalizedText(rawFocal.source_read, 360),
    preserved_semantics: normalizedText(rawFocal.preserved_semantics, 360),
    proportion_maturation: normalizedText(rawFocal.proportion_maturation, 480),
    stage_expression: normalizedText(rawFocal.stage_expression, 480),
  };
  if (Object.values(identityFocal).some((value) => value.length < 12)) {
    issues.push("identity_focal_structure v25 harus lengkap dan anatomy-agnostic");
  }

  const simplificationActions = (
    Array.isArray(rawShape.simplification_actions) ? rawShape.simplification_actions : []
  ).map((raw) => {
    const item = raw && typeof raw === "object" ? raw : {};
    return {
      source_detail: normalizedText(item.source_detail, 280),
      action: normalizedText(item.action, 24).toLowerCase(),
      result: normalizedText(item.result, 360),
    };
  });
  const simplificationSources = new Set(
    simplificationActions.map((item) => semanticText(item.source_detail)),
  );
  if (
    simplificationActions.length < 2
    || simplificationActions.length > 4
    || simplificationSources.size !== simplificationActions.length
    || simplificationActions.some((item) =>
      item.source_detail.length < 4
      || item.result.length < 12
      || !EVOLUTION_SIMPLIFICATION_ACTIONS.includes(item.action)
    )
  ) {
    issues.push("simplification_actions v25 harus 2–4 source berbeda dengan aksi merge/enlarge/omit");
  }

  const detailZones = (
    Array.isArray(rawShape.detail_zones) ? rawShape.detail_zones : []
  ).map((raw) => {
    const item = raw && typeof raw === "object" ? raw : {};
    return {
      zone: normalizedText(item.zone, 180),
      purpose: normalizedText(item.purpose, 280),
    };
  });
  if (
    detailZones.length > 1
    || detailZones.some((item) => item.zone.length < 6 || item.purpose.length < 12)
  ) {
    issues.push("detail_zones v25 maksimal satu focal zone yang konkret");
  }

  const quietZones = (Array.isArray(rawShape.quiet_zones) ? rawShape.quiet_zones : [])
    .map((value) => normalizedText(value, 180))
    .filter(Boolean);
  if (
    quietZones.length < 2
    || quietZones.length > 4
    || new Set(quietZones.map(semanticText)).size !== quietZones.length
  ) {
    issues.push("quiet_zones v25 harus 2–4 area berbeda");
  }

  const repetitionPolicy = normalizedText(rawShape.repetition_policy, 32).toLowerCase();
  if (!EVOLUTION_REPETITION_POLICIES.includes(repetitionPolicy)) {
    issues.push("repetition_policy v25 tidak sah");
  }

  if (opts.targetStage === 3) {
    const priorShape = opts.priorShapeBudgetContract
      && typeof opts.priorShapeBudgetContract === "object"
      ? opts.priorShapeBudgetContract
      : null;
    const priorDetailCount = Array.isArray(priorShape?.detail_zones)
      ? priorShape.detail_zones.length
      : -1;
    if (!priorShape || priorDetailCount < 0) {
      issues.push("Evolved v25 membutuhkan prior Shape Budget Adult");
    } else if (detailZones.length > priorDetailCount) {
      issues.push("Evolved v25 tidak boleh menambah detail zone dari Adult");
    }
  }

  plan.shape_budget_contract = {
    primary_shapes: primaryShapes,
    dominant_motif: dominantMotif,
    identity_focal_structure: identityFocal,
    simplification_actions: simplificationActions,
    detail_zones: detailZones,
    quiet_zones: quietZones,
    repetition_policy: repetitionPolicy,
  };

  const rawMaturity = plan.maturity_contract && typeof plan.maturity_contract === "object"
    ? plan.maturity_contract
    : {};
  const maturity = {
    target_read: normalizedText(rawMaturity.target_read, 24).toLowerCase(),
    identity_focal_maturation: normalizedText(rawMaturity.identity_focal_maturation, 480),
    proportion_delta: normalizedText(rawMaturity.proportion_delta, 480),
    body_maturation: normalizedText(rawMaturity.body_maturation, 480),
    posture_maturation: normalizedText(rawMaturity.posture_maturation, 480),
    preserved_personality: normalizedText(rawMaturity.preserved_personality, 360),
    stage_delta: normalizedText(rawMaturity.stage_delta, 480),
  };
  const expectedRead = opts.targetStage === 3 ? "apex" : "adult";
  if (maturity.target_read !== expectedRead) {
    issues.push(`maturity_contract.target_read stage ${opts.targetStage} harus ${expectedRead}`);
  }
  if (
    [
      maturity.identity_focal_maturation,
      maturity.proportion_delta,
      maturity.body_maturation,
      maturity.posture_maturation,
      maturity.preserved_personality,
      maturity.stage_delta,
    ].some((value) => value.length < 12)
  ) {
    issues.push("maturity_contract v25 harus menjelaskan focal, proporsi, tubuh, postur, personality, dan delta");
  }
  plan.maturity_contract = maturity;

  const rawPresence = plan.presence_contract && typeof plan.presence_contract === "object"
    ? plan.presence_contract
    : {};
  const channels = (Array.isArray(rawPresence.presence_channels)
    ? rawPresence.presence_channels
    : [])
    .map((value) => normalizedText(value, 32).toLowerCase())
    .filter(Boolean);
  const evidence = (Array.isArray(rawPresence.channel_evidence)
    ? rawPresence.channel_evidence
    : []).map((raw) => {
    const item = raw && typeof raw === "object" ? raw : {};
    return {
      channel: normalizedText(item.channel, 32).toLowerCase(),
      drawable_evidence: normalizedText(item.drawable_evidence, 480),
    };
  });
  const presence = {
    presence_tier: normalizedText(rawPresence.presence_tier, 24).toLowerCase(),
    apex_thesis: normalizedText(rawPresence.apex_thesis, 480),
    presence_channels: [...new Set(channels)],
    channel_evidence: evidence,
    shape_hierarchy: normalizedText(rawPresence.shape_hierarchy, 480),
    authority_pose: normalizedText(rawPresence.authority_pose, 480),
    reliability_cue: normalizedText(rawPresence.reliability_cue, 360),
  };
  const expectedTier = opts.targetStage === 3 ? "apex" : "developing";
  if (presence.presence_tier !== expectedTier) {
    issues.push(`presence_contract.presence_tier stage ${opts.targetStage} harus ${expectedTier}`);
  }
  if (
    presence.apex_thesis.length < 20
    || presence.shape_hierarchy.length < 12
    || presence.authority_pose.length < 12
    || presence.reliability_cue.length < 12
  ) {
    issues.push("presence_contract v25 harus menjelaskan thesis, shape hierarchy, pose, dan reliability");
  }
  if (
    channels.length !== 2
    || presence.presence_channels.length !== 2
    || presence.presence_channels.some((channel) => !EVOLUTION_PRESENCE_CHANNELS.includes(channel))
  ) {
    issues.push("presence_channels v25 harus tepat dua channel sah dan berbeda");
  }
  const evidenceChannels = new Set(evidence.map((item) => item.channel));
  if (
    evidence.length !== 2
    || evidenceChannels.size !== 2
    || evidence.some((item) =>
      !presence.presence_channels.includes(item.channel)
      || item.drawable_evidence.length < 12
    )
    || presence.presence_channels.some((channel) => !evidenceChannels.has(channel))
  ) {
    issues.push("channel_evidence v25 harus membuktikan tepat dua presence channel");
  }
  if (
    Object.hasOwn(rawPresence, "aura_architecture")
    || Object.hasOwn(rawPresence, "aura_palette")
    || Object.hasOwn(plan, "aura_architecture")
    || Object.hasOwn(plan, "aura_palette")
  ) {
    issues.push("v25 melarang aura pada character design");
  }
  const characterDesignText = [
    plan.stage_brief,
    plan.metamorphosis_notes,
    plan.metamorphosis_thesis,
    plan.dominant_mass_shift,
    plan.posture_change,
    plan.outer_contour_change,
    plan.locomotion_or_body_plan_change,
    dominantMotif.stage_expression,
    identityFocal.stage_expression,
    ...primaryShapes.map((item) => item.stage_expression),
    ...simplificationActions.map((item) => item.result),
    ...detailZones.flatMap((item) => [item.zone, item.purpose]),
    ...quietZones,
    ...((Array.isArray(plan.lineage_anchors) ? plan.lineage_anchors : [])
      .map((item) => item?.next_expression)),
    ...((Array.isArray(plan.derived_anatomy) ? plan.derived_anatomy : [])
      .map((item) => item?.new_part)),
    ...((Array.isArray(plan.identity_invariants) ? plan.identity_invariants : [])
      .flatMap((item) => [
        item?.maturation_path,
        item?.current_expression,
        item?.visible_lineage_evidence,
      ])),
    ...Object.values(maturity),
    presence.apex_thesis,
    ...evidence.map((item) => item.drawable_evidence),
    presence.shape_hierarchy,
    presence.authority_pose,
    presence.reliability_cue,
    plan.height_change_rationale,
  ].join(" ");
  if (requestsForbiddenVisual(characterDesignText, CHARACTER_AURA_WORDS)) {
    issues.push("v25 melarang aura/glow/particles/external energy pada character cells");
  }
  if (requestsForbiddenVisual(characterDesignText, OVERDETAIL_WORDS)) {
    issues.push("v25 melarang over-detail sebagai arah character design");
  }
  plan.presence_contract = presence;

  const vfxPalette = [
    ...new Set(
      (Array.isArray(plan.vfx_palette) ? plan.vfx_palette : [])
        .map((value) => normalizedText(value, 24).toLowerCase().replace(/\s+/g, "_"))
        .filter(Boolean),
    ),
  ];
  if (
    vfxPalette.length < 1
    || vfxPalette.length > 2
    || vfxPalette.some((color) => !EVOLUTION_AURA_COLORS.includes(color))
  ) {
    issues.push("vfx_palette harus 1–2 warna non-green dari allowlist v25");
  }
  const paletteLabels = vfxPalette.map((color) => color.replaceAll("_", " "));
  for (const [field, value] of [
    ["strike_vfx.brief", plan.strike_vfx?.brief],
    ["surge_vfx.brief", plan.surge_vfx?.brief],
  ]) {
    const brief = normalizedText(value, 500).toLowerCase().replaceAll("_", " ");
    if (FORBIDDEN_CHROMA_WORDS.test(brief)) {
      issues.push(`${field} tidak boleh meminta warna green/near-chroma`);
    }
    if (paletteLabels.length && !paletteLabels.some((color) => brief.includes(color))) {
      issues.push(`${field} harus menyebut warna dari vfx_palette v25`);
    }
  }
  plan.vfx_palette = vfxPalette;

  const heightRationale = normalizedText(plan.height_change_rationale, 480);
  if (heightRationale.length < 12) {
    issues.push("height_change_rationale v25 harus menjelaskan perubahan body archetype");
  }
  plan.height_change_rationale = heightRationale;
}

function validateV26MobilityPlan(plan, issues) {
  const raw = plan.mobility_contract && typeof plan.mobility_contract === "object"
    ? plan.mobility_contract
    : {};
  const mobility = {
    locomotion_mode: normalizedText(raw.locomotion_mode, 240),
    source_derivation: normalizedText(raw.source_derivation, 360),
    support_geometry: normalizedText(raw.support_geometry, 360),
    movement_read: normalizedText(raw.movement_read, 360),
    idle_stability: normalizedText(raw.idle_stability, 360),
    battle_mobility: normalizedText(raw.battle_mobility, 360),
  };
  if (
    mobility.locomotion_mode.length < 4
    || [
      mobility.source_derivation,
      mobility.support_geometry,
      mobility.movement_read,
      mobility.idle_stability,
      mobility.battle_mobility,
    ].some((value) => value.length < 12)
  ) {
    issues.push("mobility_contract v26 harus menjelaskan locomotion, derivation, support, read, idle, dan battle");
  }
  const resultText = [
    mobility.locomotion_mode,
    mobility.support_geometry,
    mobility.movement_read,
    mobility.idle_stability,
    mobility.battle_mobility,
  ].join(" ");
  if (requestsImmobileResult(resultText)) {
    issues.push("mobility_contract v26 tidak boleh menghasilkan tubuh terpatri/immobile");
  }
  const changed = Array.isArray(plan.changed_dimensions) ? plan.changed_dimensions : [];
  if (!changed.includes("locomotion_or_body_plan")) {
    issues.push("v26 wajib mengubah locomotion_or_body_plan");
  }
  if (requestsForbiddenVisual(resultText, CHARACTER_AURA_WORDS)) {
    issues.push("v26 melarang aura/glow sebagai locomotion");
  }
  plan.mobility_contract = mobility;
}

const FACE_AGE_READ = { 2: "adolescent", 3: "mature" };
const COPIED_JUVENILE_FACE =
  /\b(?:same (?:large )?eyes|unchanged eyes|keep the large|identical eyes|copy the (?:adult|hatchling) eyes)\b/i;

function validateV27FaceAgePlan(plan, opts, issues) {
  const raw = plan.face_age_contract && typeof plan.face_age_contract === "object"
    ? plan.face_age_contract
    : {};
  const expected = FACE_AGE_READ[opts.targetStage];
  const faceAge = {
    age_read: normalizedText(raw.age_read, 24).toLowerCase(),
    eye_to_face_ratio: normalizedText(raw.eye_to_face_ratio, 360),
    eye_construction: normalizedText(raw.eye_construction, 360),
    craniofacial_mass: normalizedText(raw.craniofacial_mass, 360),
    mouth_to_eye_relationship: normalizedText(raw.mouth_to_eye_relationship, 360),
    prior_copy_forbidden: normalizedText(raw.prior_copy_forbidden, 360),
  };
  if (!expected || faceAge.age_read !== expected) {
    issues.push(`face_age_contract.age_read v27 harus ${expected}`);
  }
  if ([
    faceAge.eye_to_face_ratio,
    faceAge.eye_construction,
    faceAge.craniofacial_mass,
    faceAge.mouth_to_eye_relationship,
    faceAge.prior_copy_forbidden,
  ].some((value) => value.length < 12)) {
    issues.push("face_age_contract v27 harus menjelaskan ratio, construction, mass, mouth, dan prior copy");
  }
  const resultText = [
    faceAge.eye_to_face_ratio,
    faceAge.eye_construction,
    faceAge.prior_copy_forbidden,
  ].join(" ");
  if (COPIED_JUVENILE_FACE.test(resultText)) {
    issues.push("face_age_contract v27 tidak boleh menyalin grafis mata stage sebelumnya");
  }
  plan.face_age_contract = faceAge;
}

const LEG_WALK_GAIT =
  /\b(?:walk(?:ing|s|er)?|stride|striding|step(?:s|ping)?|trot|stomp|shuffle|quadruped|biped|pillar[-_ ]?(?:legs?|stride)|root(?:ed)?[-_ ]?(?:walk|limbs?))\b/i;
const COPIED_WALKER_SILHOUETTE =
  /\b(?:same (?:four|4|walking)?[- ]?(?:legs?|walker|stance)|unchanged (?:silhouette|stance|gait)|keep the (?:adult )?(?:walker|quadruped|legs?))\b/i;
const COPIED_OUTLINE =
  /\b(?:same (?:silhouette|outline|contour)|unchanged (?:silhouette|outline|contour)|keep the (?:current|adult) (?:outline|silhouette|contour)|more decorated copy)\b/i;
const CATEGORY_ESCAPE =
  /\b(?:serpent|serpentine|snake|eel|worm|slug|ooze|limbless coil)\b/i;

function usesLegWalkGait(value) {
  return LEG_WALK_GAIT.test(semanticText(value));
}

function kindNounToken(value) {
  return normalizedText(value, 32).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function validateV28SilhouetteBreakPlan(plan, opts, issues) {
  const raw = plan.silhouette_break_contract && typeof plan.silhouette_break_contract === "object"
    ? plan.silhouette_break_contract
    : {};
  const silhouetteBreak = {
    prior_silhouette_read: normalizedText(raw.prior_silhouette_read, 360),
    forbidden_copy: normalizedText(raw.forbidden_copy, 360),
    new_contour_read: normalizedText(raw.new_contour_read, 360),
    topology_change: normalizedText(raw.topology_change, 360),
  };
  if ([
    silhouetteBreak.prior_silhouette_read,
    silhouetteBreak.forbidden_copy,
    silhouetteBreak.new_contour_read,
    silhouetteBreak.topology_change,
  ].some((value) => value.length < 12)) {
    issues.push("silhouette_break_contract v28 harus menjelaskan prior, forbidden copy, contour baru, dan topology");
  }
  if (COPIED_WALKER_SILHOUETTE.test([
    silhouetteBreak.new_contour_read,
    silhouetteBreak.topology_change,
  ].join(" "))) {
    issues.push("silhouette_break_contract v28 tidak boleh menyalin siluet walker stage sebelumnya");
  }
  if (opts.targetStage === 3 && usesLegWalkGait(opts.priorLocomotionMode)) {
    const nextGait = [
      plan.mobility_contract?.locomotion_mode,
      plan.mobility_contract?.support_geometry,
    ].join(" ");
    if (usesLegWalkGait(nextGait)) {
      issues.push("Evolved v28 tidak boleh menyalin gait kaki Adult");
    }
  }
  plan.silhouette_break_contract = silhouetteBreak;
}

function validateV29SilhouetteBreakPlan(plan, opts, issues) {
  const raw = plan.silhouette_break_contract && typeof plan.silhouette_break_contract === "object"
    ? plan.silhouette_break_contract
    : {};
  const kindNoun = kindNounToken(raw.kind_noun);
  const silhouetteBreak = {
    kind_noun: kindNoun,
    source_kind_read: normalizedText(raw.source_kind_read, 360),
    continued_kind_read: normalizedText(raw.continued_kind_read, 360),
    prior_silhouette_read: normalizedText(raw.prior_silhouette_read, 360),
    forbidden_copy: normalizedText(raw.forbidden_copy, 360),
    new_contour_read: normalizedText(raw.new_contour_read, 360),
    topology_change: normalizedText(raw.topology_change, 360),
  };
  if (kindNoun.length < 3) {
    issues.push("silhouette_break_contract v29 butuh kind_noun dari subjek sumber");
  }
  if ([
    silhouetteBreak.source_kind_read,
    silhouetteBreak.continued_kind_read,
    silhouetteBreak.prior_silhouette_read,
    silhouetteBreak.forbidden_copy,
    silhouetteBreak.new_contour_read,
    silhouetteBreak.topology_change,
  ].some((value) => value.length < 12)) {
    issues.push("silhouette_break_contract v29 harus menjelaskan kind, prior, forbidden copy, contour baru, dan perubahan");
  }
  if (kindNoun.length >= 3) {
    const kindNeedle = new RegExp(`\\b${kindNoun.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i");
    if (!kindNeedle.test(silhouetteBreak.source_kind_read)
      || !kindNeedle.test(silhouetteBreak.continued_kind_read)) {
      issues.push("silhouette_break_contract v29 harus mengulang kind_noun di source dan continued kind");
    }
  }
  if (COPIED_OUTLINE.test([
    silhouetteBreak.new_contour_read,
    silhouetteBreak.topology_change,
  ].join(" "))) {
    issues.push("silhouette_break_contract v29 tidak boleh menyalin outline 96 px stage sebelumnya");
  }
  const kindText = [
    silhouetteBreak.kind_noun,
    silhouetteBreak.source_kind_read,
  ].join(" ");
  const nextText = [
    silhouetteBreak.continued_kind_read,
    silhouetteBreak.new_contour_read,
  ].join(" ");
  if (CATEGORY_ESCAPE.test(nextText) && !CATEGORY_ESCAPE.test(kindText)) {
    issues.push("silhouette_break_contract v29 tidak boleh ganti kategori subjek");
  }
  plan.silhouette_break_contract = silhouetteBreak;
}

function validateV30NamePlan(plan, opts, issues) {
  const name = normalizeSuggestedName(plan.suggested_name, "");
  if (!name) {
    issues.push("suggested_name wajib untuk form evolusi");
    return;
  }
  const prior = normalizeSuggestedName(opts.priorSuggestedName, "").toLowerCase();
  if (prior && name.toLowerCase() === prior) {
    issues.push("suggested_name harus baru untuk form ini");
  }
  plan.suggested_name = name;
}

function validateV32NamePlan(plan, opts, issues) {
  validateV30NamePlan(plan, opts, issues);
  if (!plan.suggested_name) return;

  let anchor;
  try {
    anchor = validateNameLineageAnchor(
      plan.name_lineage_anchor,
      plan.suggested_name,
    );
  } catch (error) {
    issues.push(error instanceof Error ? error.message : String(error));
    return;
  }

  const authoritative = normalizeNameLineageAnchor(
    opts.authoritativeNameLineageAnchor,
  );
  if (authoritative) {
    if (anchor !== authoritative) {
      issues.push(
        `name_lineage_anchor harus tetap '${authoritative}', bukan '${anchor}'`,
      );
    }
  } else {
    const legacyName = normalizeSuggestedName(
      opts.legacyLineageSuggestedName,
      "",
    ).toLowerCase();
    if (!legacyName) {
      issues.push("legacy lineage name wajib untuk menetapkan anchor v32");
    } else if (!legacyName.includes(anchor)) {
      issues.push(
        `anchor legacy '${anchor}' tidak ada di lineage name '${legacyName}'`,
      );
    }
  }
  plan.name_lineage_anchor = anchor;
}

function validateV22SilhouettePlan(plan, opts, issues) {
  const anchors = (Array.isArray(plan.lineage_anchors) ? plan.lineage_anchors : [])
    .map((raw) => {
      const anchor = raw && typeof raw === "object" ? raw : {};
      return {
        source_feature: normalizedText(anchor.source_feature, 180),
        next_expression: normalizedText(anchor.next_expression, 240),
        mode: normalizedText(anchor.mode, 16).toLowerCase(),
      };
    });
  if (anchors.length !== 3) {
    issues.push("lineage_anchors v22 harus tepat 3 entri");
  } else {
    const distinct = new Set(anchors.map((anchor) => anchor.source_feature.toLowerCase()));
    if (anchors.some((anchor) => !anchor.source_feature || !anchor.next_expression)) {
      issues.push("lineage_anchors v22 harus punya source_feature dan next_expression");
    }
    if (distinct.size !== 3) issues.push("source_feature lineage_anchors harus berbeda");
    if (anchors.some((anchor) => !["retain", "transform"].includes(anchor.mode))) {
      issues.push("mode lineage_anchors harus retain atau transform");
    }
    if (anchors.filter((anchor) => anchor.mode === "transform").length < 2) {
      issues.push("lineage_anchors v22 butuh minimal 2 mode transform");
    }
    if (
      anchors.some((anchor) =>
        anchor.source_feature
        && anchor.source_feature.toLowerCase() === anchor.next_expression.toLowerCase()
      )
    ) {
      issues.push("next_expression harus mengubah fungsi atau ekspresi source_feature");
    }
    plan.lineage_anchors = anchors;
  }

  const archetype = normalizedText(plan.transformation_archetype, 40);
  if (!EVOLUTION_ARCHETYPES.includes(archetype)) {
    issues.push(`transformation_archetype tidak sah: ${archetype}`);
  } else {
    plan.transformation_archetype = archetype;
  }
  const priorArchetype = normalizedText(opts.priorTransformationArchetype, 40);
  if (
    opts.targetStage === 3
    && priorArchetype
    && priorArchetype !== "unknown"
    && archetype === priorArchetype
  ) {
    issues.push(`Evolved tidak boleh mengulang archetype Adult: ${archetype}`);
  }

  const thesis = normalizedText(plan.metamorphosis_thesis, 500);
  if (thesis.length < 20) issues.push("metamorphosis_thesis terlalu pendek");
  else plan.metamorphosis_thesis = thesis;

  const rawDimensions = Array.isArray(plan.changed_dimensions) ? plan.changed_dimensions : [];
  const dimensions = rawDimensions.map((value) => normalizedText(value, 40)).filter(Boolean);
  const uniqueDimensions = [...new Set(dimensions)];
  if (
    uniqueDimensions.length < 2
    || uniqueDimensions.length > 4
    || uniqueDimensions.some((value) => !SILHOUETTE_DIMENSIONS.includes(value))
  ) {
    issues.push("changed_dimensions harus 2–4 dimensi siluet sah dan berbeda");
  } else {
    plan.changed_dimensions = uniqueDimensions;
  }

  for (const field of [
    "dominant_mass_shift",
    "posture_change",
    "outer_contour_change",
    "locomotion_or_body_plan_change",
  ]) {
    const value = normalizedText(plan[field], 600);
    if (value.length < 12) issues.push(`${field} terlalu pendek`);
    else plan[field] = value;
  }

  const anatomy = (Array.isArray(plan.derived_anatomy) ? plan.derived_anatomy : [])
    .map((raw) => {
      const item = raw && typeof raw === "object" ? raw : {};
      return {
        new_part: normalizedText(item.new_part, 160),
        derived_from: normalizedText(item.derived_from, 180),
        source_anchor_index: Number(item.source_anchor_index),
      };
    });
  if (!Array.isArray(plan.derived_anatomy) || anatomy.length > 4) {
    issues.push("derived_anatomy harus array dengan maksimal 4 entri");
  } else if (anatomy.some((item) => !item.new_part || !item.derived_from)) {
    issues.push("derived_anatomy harus menautkan new_part ke derived_from");
  } else if (
    anatomy.some((item) => {
      const anchor = anchors[item.source_anchor_index - 1];
      return !Number.isInteger(item.source_anchor_index)
        || !anchor
        || anchor.mode !== "transform"
        || !tracesLineageAnchor(item.derived_from, anchor.source_feature);
    })
  ) {
    issues.push("derived_anatomy harus menunjuk source_anchor_index transform yang sama dengan derived_from");
  } else {
    plan.derived_anatomy = anatomy;
  }
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
 * @param {number} [opts.contractVersion] 21=legacy, 22=Silhouette Delta,
 * 23=Identity, 24=Maturity, 25=Clarity, 26=Mobility, 27=Face age,
 * 28=walker exile, 29=kind lock + contour delta, 30=name lineage,
 * 32=validated anchor, 36=deterministic, 37=hybrid root, 38=transformed root,
 * 39=transformed root + scored candidate selection.
 * @param {string} [opts.priorTransformationArchetype]
 * @param {unknown[]} [opts.priorIdentityInvariants]
 * @param {object} [opts.priorShapeBudgetContract]
 * @param {string} [opts.priorSuggestedName]
 * @param {string} [opts.authoritativeNameLineageAnchor]
 * @param {string} [opts.captureElement] elemen primary Anima; v41 memakainya
 * supaya Adult melanjut ke keluarga materialnya sendiri.
 * @param {string} [opts.legacyLineageSuggestedName]
 */
export function validateEvolutionPlan(raw, opts) {
  const issues = [];
  const plan = raw && typeof raw === "object" ? { ...raw } : {};
  const contractVersion = Number(opts.contractVersion ?? 21);

  if (contractVersion >= 22) {
    validateV22SilhouettePlan(plan, opts, issues);
  } else {
    const anchors = normalizeAnchors(plan.lineage_anchors);
    if (anchors.length !== 3) {
      issues.push("lineage_anchors harus tepat 3 entri non-kosong");
    } else {
      const distinct = new Set(anchors.map((a) => a.toLowerCase()));
      if (distinct.size !== 3) issues.push("lineage_anchors harus berbeda");
      plan.lineage_anchors = anchors;
    }
  }
  if (contractVersion >= 23) validateV23IdentityPlan(plan, opts, issues);

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

  const band = contractVersion >= 25 && opts.targetStage === 3
    ? { min: 0.75, max: 1.50 }
    : HEIGHT_BANDS[opts.targetStage];
  if (!band) throw new Error(`targetStage tidak sah: ${opts.targetStage}`);

  let height = Number(plan.body_height_cm);
  if (!Number.isInteger(height)) {
    issues.push("body_height_cm harus integer");
    height = clampHeight(priorHeight * ((band.min + band.max) / 2));
  }
  height = clampHeight(height);
  const minH = clampHeight(priorHeight * band.min);
  const maxH = clampHeight(priorHeight * band.max);
  if (height < priorHeight && !(contractVersion >= 25 && opts.targetStage === 3)) {
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
  if (contractVersion === 24) validateV24MaturityPresencePlan(plan, opts, issues);
  else if (contractVersion >= 25) validateV25ShapeClarityPlan(plan, opts, issues);
  if (contractVersion >= 26) validateV26MobilityPlan(plan, issues);
  if (contractVersion >= 27) validateV27FaceAgePlan(plan, opts, issues);
  if (contractVersion === 28) validateV28SilhouetteBreakPlan(plan, opts, issues);
  if (contractVersion >= 29) validateV29SilhouetteBreakPlan(plan, opts, issues);
  if (contractVersion >= 36) {
    const anchor = normalizeNameLineageAnchor(opts.authoritativeNameLineageAnchor)
      || deriveNameLineageAnchor(
        opts.legacyLineageSuggestedName,
        plan.name_lineage_anchor,
        true,
      );
    plan.name_lineage_anchor = anchor;
    const deriveName = contractVersion >= 41
      ? deriveMorphemeEvolutionName
      : contractVersion >= 39
      ? deriveCuratedHybridEvolutionName
      : contractVersion >= 38
      ? deriveTransformedHybridEvolutionName
      : contractVersion >= 37
      ? deriveHybridEvolutionName
      : deriveDeterministicEvolutionName;
    plan.suggested_name = deriveName(
      anchor,
      plan,
      opts.targetStage,
      opts.captureElement,
      [
        opts.priorSuggestedName,
        opts.legacyLineageSuggestedName,
        // Rename sesudah Evolve terisi nama ini, jadi kembar di koleksi yang
        // sama datang dari sini juga — bukan hanya dari nama stage sebelumnya.
        ...(Array.isArray(opts.ownerNames) ? opts.ownerNames : []),
      ],
    );
    validateV32NamePlan(plan, opts, issues);
  } else if (contractVersion >= 32) validateV32NamePlan(plan, opts, issues);
  else if (contractVersion >= 30) validateV30NamePlan(plan, opts, issues);

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
  const anchors = Array.isArray(plan.lineage_anchors) ? plan.lineage_anchors : [];
  const anchorBullets = anchors
    .map((anchor) => {
      const feature = anchor && typeof anchor === "object" ? anchor.source_feature : anchor;
      return `- ${normalizedText(feature, 180)}`;
    })
    .join("\n");
  const anchorTransformations = anchors
    .map((anchor) => {
      if (!anchor || typeof anchor !== "object") return `- retain: ${normalizedText(anchor, 180)}`;
      return `- ${normalizedText(anchor.mode, 16)}: ${
        normalizedText(anchor.source_feature, 180)
      } → ${normalizedText(anchor.next_expression, 240)}`;
    })
    .join("\n");
  const changedDimensions = (Array.isArray(plan.changed_dimensions) ? plan.changed_dimensions : [])
    .map((dimension) => `- ${normalizedText(dimension, 40)}`)
    .join("\n");
  const derivedAnatomy = (Array.isArray(plan.derived_anatomy) ? plan.derived_anatomy : [])
    .map((item) =>
      `- ${normalizedText(item?.new_part, 160)} ← ${
        normalizedText(item?.derived_from, 180)
      }`
    )
    .join("\n") || "- No new anatomy; transform mass, posture, contour, or existing body plan only.";
  const identityInvariants = (
    Array.isArray(plan.identity_invariants) ? plan.identity_invariants : []
  )
    .map((item) => {
      const invariant = normalizeIdentityInvariant(item);
      return `- [${invariant.realization_mode}] ${invariant.identity_id} (${invariant.domain})\n`
        + `  Source truth: ${invariant.source_truth}\n`
        + `  Identity role: ${invariant.identity_role}\n`
        + (invariant.maturation_path
          ? `  Maturation path: ${invariant.maturation_path}\n`
          : "")
        + `  This stage: ${invariant.current_expression}\n`
        + `  Visible lineage evidence: ${invariant.visible_lineage_evidence}`;
    })
    .join("\n");
  const maturity = plan.maturity_contract ?? {};
  const presence = plan.presence_contract ?? {};
  const shapeBudget = plan.shape_budget_contract ?? {};
  const primaryShapes = (
    Array.isArray(shapeBudget.primary_shapes) ? shapeBudget.primary_shapes : []
  )
    .map((item) =>
      `- [${normalizedText(item?.visual_role, 24)}] ${normalizedText(item?.shape_id, 64)}\n`
      + `  Source: ${normalizedText(item?.source_basis, 320)}\n`
      + `  This stage: ${normalizedText(item?.stage_expression, 360)}`
    )
    .join("\n");
  const dominantMotif = shapeBudget.dominant_motif ?? {};
  const identityFocal = shapeBudget.identity_focal_structure ?? {};
  const simplificationActions = (
    Array.isArray(shapeBudget.simplification_actions)
      ? shapeBudget.simplification_actions
      : []
  )
    .map((item) =>
      `- ${normalizedText(item?.action, 24)}: ${normalizedText(item?.source_detail, 280)}`
      + ` → ${normalizedText(item?.result, 360)}`
    )
    .join("\n");
  const detailZones = (Array.isArray(shapeBudget.detail_zones) ? shapeBudget.detail_zones : [])
    .map((item) =>
      `- ${normalizedText(item?.zone, 180)}: ${normalizedText(item?.purpose, 280)}`
    )
    .join("\n") || "- None; keep all non-focal surfaces quiet.";
  const quietZones = (Array.isArray(shapeBudget.quiet_zones) ? shapeBudget.quiet_zones : [])
    .map((zone) => `- ${normalizedText(zone, 180)}`)
    .join("\n");
  const presenceChannels = (
    Array.isArray(presence.presence_channels) ? presence.presence_channels : []
  )
    .map((channel) => `- ${normalizedText(channel, 32)}`)
    .join("\n");
  const channelEvidence = (
    Array.isArray(presence.channel_evidence) ? presence.channel_evidence : []
  )
    .map((item) =>
      `- ${normalizedText(item?.channel, 32)}: ${normalizedText(item?.drawable_evidence, 480)}`
    )
    .join("\n");
  const grandeurCues = (Array.isArray(presence.grandeur_cues) ? presence.grandeur_cues : [])
    .map((cue) => `- ${normalizedText(cue, 240)}`)
    .join("\n");
  const auraPalette = (Array.isArray(presence.aura_palette) ? presence.aura_palette : [])
    .map((color) => normalizedText(color, 24).replaceAll("_", " "))
    .join(", ");
  const vfxPalette = (Array.isArray(plan.vfx_palette) ? plan.vfx_palette : [])
    .map((color) => normalizedText(color, 24).replaceAll("_", " "))
    .join(", ");
  const mobility = plan.mobility_contract ?? {};
  const stageName = plan.target_stage === 3 ? "Evolved" : "Adult";
  const out = template
    .replaceAll("{{stage_name}}", stageName)
    .replaceAll("{{evolution_brief}}", plan.stage_brief ?? "")
    .replaceAll("{{metamorphosis_notes}}", plan.metamorphosis_notes ?? "")
    .replaceAll("{{lineage_anchors_as_bullets}}", anchorBullets)
    .replaceAll("{{anchor_transformations_as_bullets}}", anchorTransformations)
    .replaceAll("{{transformation_archetype}}", plan.transformation_archetype ?? "mass_redistribution")
    .replaceAll("{{metamorphosis_thesis}}", plan.metamorphosis_thesis ?? plan.stage_brief ?? "")
    .replaceAll("{{changed_dimensions_as_bullets}}", changedDimensions)
    .replaceAll("{{dominant_mass_shift}}", plan.dominant_mass_shift ?? "")
    .replaceAll("{{posture_change}}", plan.posture_change ?? "")
    .replaceAll("{{outer_contour_change}}", plan.outer_contour_change ?? "")
    .replaceAll(
      "{{locomotion_or_body_plan_change}}",
      plan.locomotion_or_body_plan_change ?? "",
    )
    .replaceAll("{{derived_anatomy_as_bullets}}", derivedAnatomy)
    .replaceAll("{{identity_invariants_as_bullets}}", identityInvariants)
    .replaceAll("{{primary_shapes_as_bullets}}", primaryShapes)
    .replaceAll("{{dominant_motif_source}}", dominantMotif.source_basis ?? "")
    .replaceAll("{{dominant_motif_expression}}", dominantMotif.stage_expression ?? "")
    .replaceAll("{{identity_focal_source}}", identityFocal.source_read ?? "")
    .replaceAll("{{identity_focal_semantics}}", identityFocal.preserved_semantics ?? "")
    .replaceAll("{{identity_focal_proportion}}", identityFocal.proportion_maturation ?? "")
    .replaceAll("{{identity_focal_expression}}", identityFocal.stage_expression ?? "")
    .replaceAll("{{simplification_actions_as_bullets}}", simplificationActions)
    .replaceAll("{{detail_zones_as_bullets}}", detailZones)
    .replaceAll("{{quiet_zones_as_bullets}}", quietZones)
    .replaceAll("{{repetition_policy}}", shapeBudget.repetition_policy ?? "")
    .replaceAll("{{maturity_target_read}}", maturity.target_read ?? "")
    .replaceAll("{{facial_maturation}}", maturity.facial_maturation ?? "")
    .replaceAll("{{identity_focal_maturation}}", maturity.identity_focal_maturation ?? "")
    .replaceAll("{{proportion_delta}}", maturity.proportion_delta ?? "")
    .replaceAll("{{body_maturation}}", maturity.body_maturation ?? "")
    .replaceAll("{{posture_maturation}}", maturity.posture_maturation ?? "")
    .replaceAll("{{preserved_personality}}", maturity.preserved_personality ?? "")
    .replaceAll("{{maturity_stage_delta}}", maturity.stage_delta ?? "")
    .replaceAll("{{presence_tier}}", presence.presence_tier ?? "")
    .replaceAll("{{apex_thesis}}", presence.apex_thesis ?? "")
    .replaceAll("{{presence_channels_as_bullets}}", presenceChannels)
    .replaceAll("{{channel_evidence_as_bullets}}", channelEvidence)
    .replaceAll("{{shape_hierarchy}}", presence.shape_hierarchy ?? "")
    .replaceAll("{{power_center}}", presence.power_center ?? "")
    .replaceAll("{{mass_hierarchy}}", presence.mass_hierarchy ?? "")
    .replaceAll("{{authority_pose}}", presence.authority_pose ?? "")
    .replaceAll("{{aura_architecture}}", presence.aura_architecture ?? "")
    .replaceAll("{{aura_palette}}", auraPalette)
    .replaceAll("{{vfx_palette}}", vfxPalette)
    .replaceAll("{{grandeur_cues_as_bullets}}", grandeurCues)
    .replaceAll("{{reliability_cue}}", presence.reliability_cue ?? "")
    .replaceAll("{{locomotion_mode}}", mobility.locomotion_mode ?? "")
    .replaceAll("{{mobility_source_derivation}}", mobility.source_derivation ?? "")
    .replaceAll("{{support_geometry}}", mobility.support_geometry ?? "")
    .replaceAll("{{movement_read}}", mobility.movement_read ?? "")
    .replaceAll("{{idle_stability}}", mobility.idle_stability ?? "")
    .replaceAll("{{battle_mobility}}", mobility.battle_mobility ?? "")
    .replaceAll("{{face_age_read}}", plan.face_age_contract?.age_read ?? "")
    .replaceAll("{{eye_to_face_ratio}}", plan.face_age_contract?.eye_to_face_ratio ?? "")
    .replaceAll("{{eye_construction}}", plan.face_age_contract?.eye_construction ?? "")
    .replaceAll("{{craniofacial_mass}}", plan.face_age_contract?.craniofacial_mass ?? "")
    .replaceAll("{{mouth_to_eye_relationship}}", plan.face_age_contract?.mouth_to_eye_relationship ?? "")
    .replaceAll("{{prior_copy_forbidden}}", plan.face_age_contract?.prior_copy_forbidden ?? "")
    .replaceAll("{{kind_noun}}", plan.silhouette_break_contract?.kind_noun ?? "")
    .replaceAll("{{source_kind_read}}", plan.silhouette_break_contract?.source_kind_read ?? "")
    .replaceAll("{{continued_kind_read}}", plan.silhouette_break_contract?.continued_kind_read ?? "")
    .replaceAll("{{prior_silhouette_read}}", plan.silhouette_break_contract?.prior_silhouette_read ?? "")
    .replaceAll("{{forbidden_silhouette_copy}}", plan.silhouette_break_contract?.forbidden_copy ?? "")
    .replaceAll("{{new_contour_read}}", plan.silhouette_break_contract?.new_contour_read ?? "")
    .replaceAll("{{topology_change}}", plan.silhouette_break_contract?.topology_change ?? "")
    .replaceAll("{{height_change_rationale}}", plan.height_change_rationale ?? "")
    .replaceAll("{{creature_brief}}", ctx.creature_brief || plan.stage_brief || "")
    .replaceAll(
      "{{signature_features_as_bullets}}",
      ctx.signature_features_as_bullets || anchorBullets,
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

/** Adult Plan summary for Evolved Vision. Full essays make Gemini stop mid-JSON. */
export function compactPriorEvolutionDesign(priorPlan) {
  if (!priorPlan || typeof priorPlan !== "object") return null;
  const invariants = (Array.isArray(priorPlan.identity_invariants)
    ? priorPlan.identity_invariants
    : []
  ).map((item) => ({
    identity_id: item?.identity_id,
    domain: item?.domain,
    evolved_policy: item?.evolved_policy,
    realization_mode: item?.realization_mode,
    source_truth: item?.source_truth,
    identity_role: item?.identity_role,
    maturation_path: item?.maturation_path,
  }));
  const budget = priorPlan.shape_budget_contract && typeof priorPlan.shape_budget_contract === "object"
    ? priorPlan.shape_budget_contract
    : {};
  const mobility = priorPlan.mobility_contract && typeof priorPlan.mobility_contract === "object"
    ? priorPlan.mobility_contract
    : null;
  const maturity = priorPlan.maturity_contract && typeof priorPlan.maturity_contract === "object"
    ? priorPlan.maturity_contract
    : null;
  const presence = priorPlan.presence_contract && typeof priorPlan.presence_contract === "object"
    ? priorPlan.presence_contract
    : null;
  return {
    transformation_archetype: priorPlan.transformation_archetype ?? "",
    identity_invariants: invariants,
    shape_budget_contract: {
      primary_shapes: (Array.isArray(budget.primary_shapes) ? budget.primary_shapes : []).map((shape) => ({
        shape_id: shape?.shape_id,
        visual_role: shape?.visual_role,
      })),
      detail_zones: Array.isArray(budget.detail_zones) ? budget.detail_zones : [],
    },
    mobility_contract: mobility && {
      locomotion_mode: mobility.locomotion_mode ?? "",
      support_geometry: mobility.support_geometry ?? "",
    },
    maturity_contract: maturity && { target_read: maturity.target_read ?? "" },
    presence_contract: presence && {
      apex_thesis: presence.apex_thesis ?? "",
      presence_channels: Array.isArray(presence.presence_channels) ? presence.presence_channels : [],
    },
    face_age_contract: priorPlan.face_age_contract && typeof priorPlan.face_age_contract === "object"
      ? { age_read: priorPlan.face_age_contract.age_read ?? "" }
      : null,
    silhouette_break_contract: priorPlan.silhouette_break_contract
      && typeof priorPlan.silhouette_break_contract === "object"
      ? {
        kind_noun: priorPlan.silhouette_break_contract.kind_noun ?? "",
        source_kind_read: priorPlan.silhouette_break_contract.source_kind_read ?? "",
        continued_kind_read: priorPlan.silhouette_break_contract.continued_kind_read ?? "",
        prior_silhouette_read: priorPlan.silhouette_break_contract.prior_silhouette_read ?? "",
        forbidden_copy: priorPlan.silhouette_break_contract.forbidden_copy ?? "",
      }
      : null,
  };
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

/** Plafon percobaan Evolution Plan, termasuk percobaan pertama. */
export const EVOLUTION_PLAN_MAX_ATTEMPTS = 3;
/**
 * Percobaan baru tidak boleh dimulai lewat batas ini.
 *
 * Client memberi 90 detik (`TIMEOUT_FUNGSI_SEC`), satu siklus penuh terukur 26
 * detik, dan satu panggilan Vision ~19 detik. Percobaan yang dimulai sesudah
 * 50 detik berisiko selesai setelah client menyerah, dan pemain akan melihat
 * kegagalan transport padahal server masih bekerja dengan benar.
 */
export const EVOLUTION_PLAN_RESAMPLE_DEADLINE_MS = 50_000;

/**
 * Boleh menyampel ulang Plan yang ditolak validator?
 *
 * Plan berharga $0,003 sementara gambarnya ~$0,05, jadi sampel kedua adalah
 * cara termurah melawan variansi model — yang membatasi di sini waktu, bukan
 * uang. `attempt` adalah jumlah percobaan yang SUDAH dijalankan.
 */
export function evolutionPlanResampleAllowed(attempt, elapsedMs) {
  return attempt < EVOLUTION_PLAN_MAX_ATTEMPTS
    && elapsedMs < EVOLUTION_PLAN_RESAMPLE_DEADLINE_MS;
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
