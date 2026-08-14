export const ELEMENT_ROSTER = Object.freeze([
  "metal",
  "wood",
  "stone",
  "ceramic",
  "glass",
  "plastic",
  "cloth",
  "paper",
  "plant",
  "food",
  "fauna",
  "flow",
  "spark",
  "flame",
  "frost",
  "air",
  "toxin",
  "sound",
]);

/** Legacy six-type cycle kept for callers that still import ELEMENT_CYCLE. */
export const ELEMENT_CYCLE = Object.freeze(["metal", "plant", "flow", "spark", "cloth", "stone"]);

export const ELEMENT_STRENGTHS = Object.freeze({
  metal: ["plant", "wood"],
  wood: ["spark", "sound"],
  stone: ["metal", "ceramic"],
  ceramic: ["toxin", "flame"],
  glass: ["toxin", "air"],
  plastic: ["flow", "glass"],
  cloth: ["stone", "sound"],
  paper: ["food", "stone"],
  plant: ["flow", "air"],
  food: ["fauna", "frost"],
  fauna: ["plant", "cloth"],
  flow: ["spark", "paper"],
  spark: ["cloth", "metal"],
  flame: ["wood", "frost"],
  frost: ["fauna", "plastic"],
  air: ["flame", "paper"],
  toxin: ["food", "plastic"],
  sound: ["glass", "ceramic"],
});

export const ELEMENT_ALIASES = Object.freeze({
  tech: "spark",
  electric: "spark",
  electricity: "spark",
  water: "flow",
  earth: "stone",
  nature: "plant",
  fire: "flame",
  ice: "frost",
  wind: "air",
  poison: "toxin",
  organic: "food",
  animal: "fauna",
  beast: "fauna",
  fabric: "cloth",
  textile: "cloth",
});

export const MATCHUP_STRONG = 1.5;
export const MATCHUP_WEAK = 0.67;
export const MATCHUP_NEUTRAL = 1.0;

const ROSTER_SET = new Set(ELEMENT_ROSTER);

export function normalizeElement(element, fallback = "stone") {
  const value = String(element ?? "").trim().toLowerCase();
  if (ROSTER_SET.has(value)) return value;
  const aliased = ELEMENT_ALIASES[value];
  if (aliased && ROSTER_SET.has(aliased)) return aliased;
  return fallback;
}

export function isRosterElement(element) {
  return ROSTER_SET.has(normalizeElement(element, ""));
}

export function strengthsOf(element) {
  const key = normalizeElement(element, "");
  return key ? [...(ELEMENT_STRENGTHS[key] ?? [])] : [];
}

export function singleMatchup(attacker, defender) {
  const atk = normalizeElement(attacker, "");
  const def = normalizeElement(defender, "");
  if (!atk || !def) return MATCHUP_NEUTRAL;
  if (ELEMENT_STRENGTHS[atk]?.includes(def)) return MATCHUP_STRONG;
  if (ELEMENT_STRENGTHS[def]?.includes(atk)) return MATCHUP_WEAK;
  return MATCHUP_NEUTRAL;
}

export function defenseElements(primary, secondary = null) {
  const elements = [];
  const primaryNorm = normalizeElement(primary, "");
  if (primaryNorm) elements.push(primaryNorm);
  const secondaryNorm = normalizeElement(secondary, "");
  if (secondaryNorm && secondaryNorm !== primaryNorm) elements.push(secondaryNorm);
  return elements;
}

export function dualDefenderMultiplier(attacker, primary, secondary = null) {
  const defenses = defenseElements(primary, secondary);
  if (defenses.length <= 1) {
    return singleMatchup(attacker, defenses[0] ?? "");
  }

  const matchups = defenses.map((defense) => singleMatchup(attacker, defense));
  const hasStrong = matchups.some((value) => value > MATCHUP_NEUTRAL);
  const hasWeak = matchups.some((value) => value < MATCHUP_NEUTRAL);
  if (hasStrong && hasWeak) return MATCHUP_NEUTRAL;
  if (hasStrong) return MATCHUP_STRONG;
  if (hasWeak) return MATCHUP_WEAK;
  return MATCHUP_NEUTRAL;
}

/** Single-defender wrapper kept for legacy imports from battle.mjs. */
export function elementMultiplier(attacker, defender) {
  return singleMatchup(attacker, defender);
}
