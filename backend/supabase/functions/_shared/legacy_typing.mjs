// Deterministic retyping legacy animas → roster 18 (typing_version 2).
// Pure: vision_result + existing element only — never calls Vision/generation.

import { ELEMENT_ROSTER, normalizeElement, isRosterElement } from "./elements.mjs";

const ROSTER_SET = new Set(ELEMENT_ROSTER);

/** @typedef {"object"|"animal"} SubjectKind */
/** @typedef {import("./elements.mjs").ELEMENT_ROSTER[number]} RosterElement */

/**
 * @typedef {object} LegacyTypingInput
 * @property {Record<string, unknown>} [vision]
 * @property {string} [existingElement]
 * @property {SubjectKind|null} [subjectKind]
 * @property {boolean|null} [isObject]
 */

/**
 * @typedef {object} CanonicalLegacyTyping
 * @property {SubjectKind} subject_kind
 * @property {RosterElement} element
 * @property {RosterElement|null} secondary_element
 * @property {2} typing_version
 * @property {string} reason
 */

const ANIMAL_WORDS = [
  "cat", "dog", "bird", "fish", "snake", "hamster", "rabbit", "turtle", "lizard",
  "insect", "spider", "frog", "horse", "cow", "pig", "sheep", "goat", "duck",
  "chicken", "parrot", "ferret", "gecko", "tabby", "feline", "canine", "puppy",
  "kitten", "animal", "pet", "paw", "whisker", "feather", "hoof", "beak",
];

const TECH_MOUSE = [
  /\bcomputer mouse\b/,
  /\bwired mouse\b/,
  /\bwireless mouse\b/,
  /\bgaming mouse\b/,
  /\busb mouse\b/,
  /\boptical mouse\b/,
  /\bmouse pad\b/,
  /\bmousepad\b/,
  /mouse_plastic/,
  /mouse_pad/,
  /keyboard_/,
  /controller_/,
  /gamepad_/,
];

const MATERIAL_RULES = [
  {
    element: "ceramic",
    reason: "material:ceramic",
    patterns: [
      /\bceramic\b/,
      /\bporcelain\b/,
      /\bmug\b/,
      /\bteacup\b/,
      /\bcrockery\b/,
      /\bglazed\b/,
      /ceramic_/,
      /mug_/,
      /porcelain_/,
    ],
  },
  {
    element: "paper",
    reason: "material:paper",
    patterns: [
      /\bbook\b/,
      /\bnotebook\b/,
      /\bpaperback\b/,
      /\bcardboard\b/,
      /\bpaper\b/,
      /\bjournal\b/,
      /\bnotepad\b/,
      /\benvelope\b/,
      /\bmagazine\b/,
      /\bpage\b/,
      /book_/,
      /paper_/,
      /cardboard_/,
    ],
  },
  {
    element: "plastic",
    reason: "material:plastic_tech",
    patterns: [
      /\bkeyboard\b/,
      /\bkeycap\b/,
      /\bgamepad\b/,
      /\bcontroller\b/,
      /\bhandheld console\b/,
      /\bgame console\b/,
      /\bjoystick\b/,
      /\bwebcam\b/,
      /\bheadset\b/,
      /\belectronic\b/,
      /\busb\b/,
      /\bmolded plastic\b/,
      /\babs plastic\b/,
      /keyboard_/,
      /controller_/,
      /gamepad_/,
      /console_/,
    ],
  },
  {
    element: "food",
    reason: "material:food",
    patterns: [
      /\bfood\b/,
      /\bsnack\b/,
      /\bfruit\b/,
      /\bbread\b/,
      /\bcake\b/,
      /\bcandy\b/,
      /\bmeat\b/,
      /\bvegetable\b/,
      /\bmeal\b/,
      /food_/,
    ],
  },
  {
    element: "plant",
    reason: "material:plant",
    patterns: [
      /\bplant\b/,
      /\bleaf\b/,
      /\bleaves\b/,
      /\bpotted\b/,
      /\bsucculent\b/,
      /\bcactus\b/,
      /\bfern\b/,
      /\bmonstera\b/,
      /\bflower\b/,
      /\bbonsai\b/,
      /plant_/,
      /monstera_/,
    ],
  },
  {
    element: "wood",
    reason: "material:wood",
    patterns: [
      /\bwooden\b/,
      /\bwood\b/,
      /\btimber\b/,
      /\bbamboo\b/,
      /wood_/,
    ],
  },
  {
    element: "glass",
    reason: "material:glass",
    patterns: [
      /\bglass\b/,
      /\bcrystal\b/,
      /glass_/,
    ],
  },
  {
    element: "metal",
    reason: "material:metal",
    patterns: [
      /\bmetal\b/,
      /\bsteel\b/,
      /\biron\b/,
      /\bcopper\b/,
      /\bbrass\b/,
      /\baluminum\b/,
      /\baluminium\b/,
      /\bchrome\b/,
      /metal_/,
    ],
  },
  {
    element: "cloth",
    reason: "material:cloth",
    patterns: [
      /\bcloth\b/,
      /\bfabric\b/,
      /\btextile\b/,
      /\bplush\b/,
      /\bstuffed\b/,
      /\bcotton\b/,
      /\bdenim\b/,
      /cloth_/,
      /fabric_/,
      /plush_/,
    ],
  },
  {
    element: "stone",
    reason: "material:stone",
    patterns: [
      /\bstone\b/,
      /\brock\b/,
      /\bmarble\b/,
      /\bgranite\b/,
      /\bpebble\b/,
      /\bconcrete\b/,
      /stone_/,
    ],
  },
];

function asString(value) {
  return String(value ?? "").trim();
}

function listStrings(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => asString(item)).filter(Boolean);
}

/** @param {Record<string, unknown>} vision */
export function gatherLegacyTypingCorpus(vision) {
  const parts = [
    asString(vision.object_label),
    asString(vision.species_key).replace(/_/g, " "),
    asString(vision.surface_finish),
    ...listStrings(vision.signature_features),
    ...listStrings(vision.damage_hints),
  ].filter(Boolean);
  return parts.join(" ").toLowerCase();
}

function isTechMouseContext(corpus, vision) {
  const species = asString(vision.species_key).toLowerCase();
  if (TECH_MOUSE.some((re) => re.test(corpus) || re.test(species))) return true;
  if (/\bmouse\b/.test(corpus) && /\b(plastic|usb|cable|click|scroll|sensor)\b/.test(corpus)) {
    return true;
  }
  return false;
}

/** @param {Record<string, unknown>} vision @param {SubjectKind|null} explicit */
export function inferLegacySubjectKind(vision, explicit = null) {
  const kind = asString(explicit ?? vision.subject_kind).toLowerCase();
  if (kind === "animal") return "animal";
  if (kind === "object") return "object";

  const corpus = gatherLegacyTypingCorpus(vision);
  if (isTechMouseContext(corpus, vision)) return "object";

  if (ANIMAL_WORDS.some((word) => new RegExp(`\\b${word}\\b`).test(corpus))) {
    return "animal";
  }
  return "object";
}

/** @param {string} corpus @param {Record<string, unknown>} vision */
function matchMaterial(corpus, vision) {
  if (/\bmouse\b/.test(corpus) && isTechMouseContext(corpus, vision)) {
    return { element: "plastic", reason: "material:plastic_tech" };
  }

  for (const rule of MATERIAL_RULES) {
    if (rule.element === "plastic") {
      const techHit = rule.patterns.some((re) => re.test(corpus));
      const species = asString(vision.species_key).toLowerCase();
      const speciesHit = rule.patterns.some((re) => re.test(species));
      if (techHit || speciesHit) return { element: rule.element, reason: rule.reason };
      continue;
    }
    if (rule.patterns.some((re) => re.test(corpus))) {
      return { element: rule.element, reason: rule.reason };
    }
  }
  return null;
}

function legacySecondaryForPrimary(primary, legacyPrimary) {
  if (primary === "ceramic" && legacyPrimary === "flow") return "flow";
  if (primary === "plastic" && legacyPrimary === "spark") return "spark";
  return null;
}

function normalizedLegacyPrimary(existingElement) {
  const normalized = normalizeElement(existingElement, "");
  if (normalized && ROSTER_SET.has(normalized)) return normalized;
  return normalizeElement(existingElement, "stone");
}

/**
 * @param {LegacyTypingInput} input
 * @returns {CanonicalLegacyTyping}
 */
export function inferCanonicalLegacyTyping(input) {
  const vision = input.vision && typeof input.vision === "object" ? input.vision : {};
  const legacyPrimary = normalizedLegacyPrimary(input.existingElement);
  const subject_kind = inferLegacySubjectKind(vision, input.subjectKind ?? null);

  if (subject_kind === "animal") {
    return {
      subject_kind: "animal",
      element: "fauna",
      secondary_element: null,
      typing_version: 2,
      reason: "subject:animal",
    };
  }

  const corpus = gatherLegacyTypingCorpus(vision);
  const material = matchMaterial(corpus, vision);

  let element;
  let reason;
  if (material) {
    element = /** @type {RosterElement} */ (material.element);
    reason = material.reason;
  } else if (isRosterElement(legacyPrimary)) {
    element = /** @type {RosterElement} */ (legacyPrimary);
    reason = "legacy:ambiguous";
  } else {
    element = /** @type {RosterElement} */ (normalizeElement(legacyPrimary, "stone"));
    reason = "legacy:normalized";
  }

  const secondary_element = legacySecondaryForPrimary(element, legacyPrimary);

  return {
    subject_kind: "object",
    element,
    secondary_element,
    typing_version: 2,
    reason,
  };
}

export function stableSortKeys(value) {
  if (Array.isArray(value)) return value.map((item) => stableSortKeys(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stableSortKeys(value[key])]),
    );
  }
  return value;
}

export function stableStringify(value) {
  return `${JSON.stringify(stableSortKeys(value), null, 2)}\n`;
}
