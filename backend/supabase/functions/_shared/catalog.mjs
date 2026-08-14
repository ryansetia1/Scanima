// Katalog makanan/item v1. Sumber display + efek Battle. Harga di Postgres
// adalah otoritas pembelian; file ini harus identik dengan seed migrasi.

export const INVENTORY_STACK_MAX = 999;
export const STARTER_BITS = 50;
export const BATTLE_BITS_CAP = 100;
export const BATTLE_PROGRESSION_WINS = 3;
export const CARE_SCORE_WIN = 4;

export const REWARD_TIERS = Object.freeze({
  favorable: { maxRatio: 0.95, bits: 6 },
  even: { maxRatio: 1.05, bits: 8 },
  tough: { maxRatio: 1.1, bits: 11 },
  formidable: { maxRatio: Infinity, bits: 15 },
});

export const CATALOG_ITEMS = Object.freeze([
  food("byte_berry", 0, 2, 10),
  food("moon_biscuit", 1, 3, 15),
  food("moss_wrap", 2, 4, 20),
  food("spark_skewer", 3, 5, 25),
  food("prism_jelly", 4, 7, 35),
  food("ember_noodles", 5, 9, 45),
  food("cloud_curry", 6, 12, 60),
  food("star_bento", 7, 15, 75),
  food("nova_feast", 8, 20, 100),
  item("pulse_cell", 0, 8, "energy", "energy", 20),
  item("reactor_pack", 1, 18, "energy", "energy", 50),
  item("vital_patch", 2, 14, "battle", "heal_hp_pct", 30),
  item("power_chip", 3, 12, "battle", "buff_atk", 35),
  item("surge_lens", 4, 12, "battle", "buff_special", 35),
  item("aegis_plate", 5, 14, "battle", "buff_guard", 25),
  item("tempo_coil", 6, 10, "battle", "buff_spd", 40),
  item("pp_capsule", 7, 14, "battle", "pp_boost", 2),
  item("phase_shield", 8, 10, "battle", "phase_shield", 80),
]);

export const CATALOG_BY_ID = Object.freeze(
  Object.fromEntries(CATALOG_ITEMS.map((entry) => [entry.id, entry])),
);

export function catalogItem(id) {
  return CATALOG_BY_ID[String(id ?? "")] ?? null;
}

export function isFood(id) {
  return catalogItem(id)?.use_type === "food";
}

export function isEnergyItem(id) {
  return catalogItem(id)?.use_type === "energy";
}

export function isBattleItem(id) {
  return catalogItem(id)?.use_type === "battle";
}

export function combatPower(stats) {
  return (
    Number(stats?.max_hp || 0) / 4 +
    Number(stats?.atk || 0) +
    Number(stats?.special || 0) +
    Number(stats?.def || 0) +
    Number(stats?.spd || 0)
  );
}

export function rewardTierFromRatio(ratio) {
  const value = Number(ratio);
  if (!Number.isFinite(value) || value < REWARD_TIERS.favorable.maxRatio) return "favorable";
  if (value < REWARD_TIERS.even.maxRatio) return "even";
  if (value < REWARD_TIERS.tough.maxRatio) return "tough";
  return "formidable";
}

export function rewardRollFromSeed(seed) {
  const unit = hashUnit(`${seed}:reward`);
  if (unit < 1 / 3) return -1;
  if (unit < 2 / 3) return 0;
  return 1;
}

export function bitsForTier(tier, roll = 0) {
  const base = REWARD_TIERS[tier]?.bits ?? REWARD_TIERS.even.bits;
  return Math.max(5, base + clampInt(roll, -1, 1));
}

function food(id, spriteIndex, price, hunger) {
  return Object.freeze({
    id,
    kind: "food",
    use_type: "food",
    name_key: `CATALOG_${id.toUpperCase()}`,
    price,
    effect: "hunger",
    effect_value: hunger,
    sprite_sheet: "food",
    sprite_index: spriteIndex,
  });
}

function item(id, spriteIndex, price, useType, effect, value) {
  return Object.freeze({
    id,
    kind: "item",
    use_type: useType,
    name_key: `CATALOG_${id.toUpperCase()}`,
    price,
    effect,
    effect_value: value,
    sprite_sheet: "item",
    sprite_index: spriteIndex,
  });
}

function hashUnit(value) {
  let hash = 2166136261;
  for (const char of String(value)) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) / 4294967296;
}

function clampInt(value, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.min(max, Math.max(min, Math.trunc(number)));
}
