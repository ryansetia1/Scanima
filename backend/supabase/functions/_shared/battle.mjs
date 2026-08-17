import {
  catalogItem,
  isBattleItem,
  rewardRollFromSeed,
  tierFromWinRate,
  bitsForTier,
} from "./catalog.mjs";
import {
  ELEMENT_CYCLE,
  defenseElements,
  dualDefenderMultiplier,
  elementMultiplier,
  normalizeElement,
} from "./elements.mjs";

export { ELEMENT_CYCLE, elementMultiplier, normalizeElement };
export const BATTLE_ACTIONS = Object.freeze(["strike", "surge", "guard", "item"]);
export const RULES_VERSION = 2;
export const MOMENTUM_MAX = 3;
export const MOMENTUM_START = 3;
export const SURGE_COST = 1;
export const BATTLE_MAX_TURNS = 30;
export const LEVEL_CAP = 40;
export const EXP_PER_LEVEL = 5;
export const EXP_MAX = 860;
export const ADULT_LEVEL = 16;
export const EVOLVED_LEVEL = 36;
export const HUNGRY_NEED = 40;
export const DIRTY_NEED = 50;
export const HUNGRY_COMBAT_FLOOR = 0.6;
export const DIRTY_COMBAT_FLOOR = 0.7;
export const CARE_COMBAT_FLOOR = 0.5;

const STAT_KEYS = Object.freeze(["hp", "atk", "def", "spd", "special"]);

export function expToNextLevel(level) {
  const lv = clampInt(level, 1, LEVEL_CAP);
  return lv >= LEVEL_CAP ? 0 : EXP_PER_LEVEL * Math.ceil(lv / 5);
}

export function expForLevel(level) {
  const steps = clampInt(level, 1, LEVEL_CAP) - 1;
  const completeBands = Math.floor(steps / 5);
  const remainingSteps = steps % 5;
  return (
    (EXP_PER_LEVEL * 5 * completeBands * (completeBands + 1)) / 2
    + remainingSteps * EXP_PER_LEVEL * (completeBands + 1)
  );
}

export function levelFromExp(exp) {
  const value = Math.max(0, Math.trunc(Number(exp) || 0));
  for (let level = LEVEL_CAP; level > 1; level -= 1) {
    if (value >= expForLevel(level)) return level;
  }
  return 1;
}

export function battleExpYield(recipientLevel, opponentLevel, difficulty = "even") {
  const recipient = clampInt(recipientLevel, 1, LEVEL_CAP);
  const opponent = clampInt(opponentLevel, 1, LEVEL_CAP);
  const base = 1 + Math.ceil(opponent / 10);
  const underdog = Math.min(2, Math.floor(Math.max(0, opponent - recipient) / 5));
  const tier = ["tough", "formidable", "elite", "boss"].includes(difficulty) ? 1 : 0;
  return clampInt(base + underdog + tier, 1, 8);
}

export function formFromLevel(level) {
  const lv = clampInt(level, 1, LEVEL_CAP);
  if (lv >= EVOLVED_LEVEL) return "evolved";
  if (lv >= ADULT_LEVEL) return "adult";
  return "hatchling";
}

export function growthMultiplier(level) {
  const lv = clampInt(level, 1, LEVEL_CAP);
  let mult = 1 + 0.02 * (lv - 1);
  if (lv >= ADULT_LEVEL) mult += 0.15;
  if (lv >= EVOLVED_LEVEL) mult += 0.20;
  return mult;
}

export function stageMultipliers(stage, branch = "") {
  if (Number(stage) === 2) {
    return { hp: 1.4, atk: 1.4, def: 1.4, spd: 1.4, special: 1.4 };
  }
  if (Number(stage) === 3 && branch === "guardian") {
    return { hp: 1.9, atk: 1.5, def: 1.9, spd: 1.0, special: 1.0 };
  }
  if (Number(stage) === 3 && branch === "ravager") {
    return { hp: 1.0, atk: 1.9, def: 1.4, spd: 1.9, special: 1.0 };
  }
  return { hp: 1.0, atk: 1.0, def: 1.0, spd: 1.0, special: 1.0 };
}

export function hungerCombatMultiplier(hunger) {
  return meterCombatMultiplier(hunger, HUNGRY_NEED, HUNGRY_COMBAT_FLOOR);
}

export function hygieneCombatMultiplier(hygiene) {
  return meterCombatMultiplier(hygiene, DIRTY_NEED, DIRTY_COMBAT_FLOOR);
}

export function careCombatMultiplier(hunger, hygiene) {
  return Math.max(
    CARE_COMBAT_FLOOR,
    hungerCombatMultiplier(hunger) * hygieneCombatMultiplier(hygiene),
  );
}

function meterCombatMultiplier(value, need, floor) {
  const n = Number(value);
  if (!Number.isFinite(n) || n >= need) return 1;
  return floor + (1 - floor) * Math.max(0, n) / need;
}

function scaleCombatStats(stats, mult) {
  if (mult >= 1) return stats;
  return {
    max_hp: Math.max(1, Math.trunc(stats.max_hp * mult)),
    atk: Math.max(1, Math.trunc(stats.atk * mult)),
    def: Math.max(1, Math.trunc(stats.def * mult)),
    spd: Math.max(1, Math.trunc(stats.spd * mult)),
    special: Math.max(1, Math.trunc(stats.special * mult)),
  };
}

export function toBattleStats(baseStats, stage = 1, branch = "", level = 1) {
  const base = normalizeBaseStats(baseStats);
  // ponytail: stage multipliers idle until evolve art ships; level is the live growth path.
  const g = growthMultiplier(level);
  return {
    max_hp: Math.trunc(base.hp * 4 * g) + 20,
    atk: Math.trunc(base.atk * g),
    def: Math.trunc(base.def * g),
    spd: Math.trunc(base.spd * g),
    special: Math.trunc(base.special * g),
  };
}

export function normalizeBaseStats(baseStats, targetTotal = null) {
  const normalized = {};
  for (const key of STAT_KEYS) {
    normalized[key] = clampInt(baseStats?.[key], 10, 95, 50);
  }
  if (targetTotal === null) return normalized;

  const wanted = clampInt(targetTotal, 50, 475, 250);
  const current = STAT_KEYS.reduce((sum, key) => sum + normalized[key], 0);
  const scale = wanted / Math.max(1, current);
  for (const key of STAT_KEYS) {
    normalized[key] = clampInt(Math.round(normalized[key] * scale), 10, 95, 50);
  }
  return normalized;
}

export function baseStatTotal(baseStats) {
  const base = normalizeBaseStats(baseStats);
  return STAT_KEYS.reduce((sum, key) => sum + base[key], 0);
}

export function critChance(speed) {
  return clamp(Number(speed) / 400, 0.02, 0.25);
}

export function computeDamage({
  attack,
  defense,
  power,
  element = 1.0,
  crit = false,
  variance = 1.0,
  guarding = false,
}) {
  const mitigation = 100 / (100 + Math.max(0, Number(defense) || 0));
  const critical = crit ? 1.8 : 1.0;
  const guard = guarding ? 0.5 : 1.0;
  const raw =
    Math.max(0, Number(attack) || 0) *
    (Math.max(0, Number(power) || 0) / 50) *
    mitigation *
    Math.max(0, Number(element) || 0) *
    critical *
    clamp(Number(variance) || 1.0, 0.92, 1.08) *
    guard;
  return Math.max(1, Math.trunc(raw));
}

export function createBattleState({ player, bot, seed }) {
  return {
    status: "active",
    turn: 1,
    seed: String(seed ?? ""),
    rules_version: RULES_VERSION,
    player: createFighter(player),
    bot: createFighter(bot),
  };
}

// Sampai rules_version 1, idempotency_key ikut masuk ke seed turn. Key itu
// dipilih client, jadi pemain bisa mengaduknya sampai mendapat crit. Sejak
// versi 2 seed hanya bergantung pada nilai server. State lama tetap memakai
// formula lamanya supaya sesi yang sedang berjalan dan turn yang sudah
// tercatat di battle_turns tetap bisa direplay dengan hasil yang sama.
export function turnSeed(state, idempotencyKey = "") {
  const version = Math.trunc(Number(state?.rules_version) || 1);
  if (version >= 2) return `${state?.seed}:${state?.turn}`;
  return `${state?.seed}:${state?.turn}:${idempotencyKey}`;
}

// Care dinetralkan di dua sisi supaya tier mengukur matchup-nya, bukan isi
// meter saat ini. Tanpa ini Anima lapar+kotor terukur menang 0%, jatuh ke tier
// `formidable`, dan menelantarkan care menjadi cara menaikkan Bits.
function withFullCare(snapshot) {
  return { ...(snapshot ?? {}), hunger: 100, hygiene: 100 };
}

// Patokan tier adalah pemain yang kompeten: ia menekan Special ketika Special
// memang lebih besar terhadap pertahanan lawan ini. `chooseBotAction` bukan
// pengganti yang sah — memakainya untuk kedua sisi terukur menggeser tier di 30
// dari 38 matchup, sebab bot memilih Special 68% acak tanpa melihat elemen.
export function bestDuelAction(state) {
  const me = state.player;
  const foe = state.bot;
  if (me.momentum < SURGE_COST) {
    return me.hp / Math.max(1, me.max_hp) <= 0.35 ? "guard" : "strike";
  }
  const strike = computeDamage({
    attack: me.atk * (me.atk_mult || 1),
    defense: foe.def,
    power: 50,
    element: dualDefenderMultiplier(me.element, foe.element, foe.secondary_element),
  });
  const surge = computeDamage({
    attack: me.special * (me.special_mult || 1),
    defense: Math.trunc(foe.def * 0.5),
    power: 75,
    element: dualDefenderMultiplier(
      me.secondary_element || me.element,
      foe.element,
      foe.secondary_element,
    ),
  });
  return surge > strike ? "surge" : "strike";
}

// Kesulitan Duel diukur, bukan ditaksir. Combat power hanya menjumlahkan stat
// sementara hasil duel adalah damage dikali daya tahan, jadi tier lama memberi
// satu `even` yang isinya 38%–99% peluang menang dan membayar `formidable` 15
// Bits untuk duel yang dimenangkan 76%. Seed-nya konstan supaya matchup yang
// sama selalu mendapat tier yang sama, dan terukur lebih akurat daripada seed
// per-matchup (salah 6/38 versus 8/38 terhadap patokan 800 duel).
// ponytail: 64 duel = ~2 ms dan tidak pernah salah lebih dari satu tingkat;
// selisih win rate maksimum 11%, jadi matchup tepat di ambang bisa jatuh ke
// tetangganya. Naikkan runs kalau ambangnya nanti dipersempit.
export const DUEL_DIFFICULTY_RUNS = 64;

export function duelWinRate(player, bot, runs = DUEL_DIFFICULTY_RUNS) {
  const fighters = { player: withFullCare(player), bot: withFullCare(bot) };
  const total = Math.max(1, Math.trunc(runs));
  let wins = 0;
  for (let index = 0; index < total; index += 1) {
    const seed = `duel-difficulty:${index}`;
    let state = createBattleState({ ...fighters, seed });
    while (state.status === "active") {
      state = resolveTurn(state, bestDuelAction(state), `${seed}:${state.turn}`).state;
    }
    if (state.status === "won") wins += 1;
  }
  return wins / total;
}

export function battleRewardPreview(player, bot, seed) {
  const winRate = duelWinRate(player, bot);
  const tier = tierFromWinRate(winRate);
  const roll = rewardRollFromSeed(seed);
  return {
    tier,
    roll,
    bits: bitsForTier(tier, roll),
    bits_min: bitsForTier(tier, -1),
    bits_max: bitsForTier(tier, 1),
    win_rate: winRate,
  };
}

export function chooseBotAction(fighter, random) {
  const roll = random();
  const hpRatio = fighter.hp / Math.max(1, fighter.max_hp);
  if (hpRatio <= 0.4 && roll < 0.45) return "guard";
  if (fighter.momentum >= SURGE_COST && roll < 0.68) return "surge";
  return "strike";
}

export function resolveTurn(previousState, playerAction, idempotencyKey = "", itemId = "") {
  if (previousState?.status !== "active") throw battleError("BATTLE_FINISHED");
  if (!BATTLE_ACTIONS.includes(playerAction)) throw battleError("INVALID_ACTION");
  if (playerAction === "item") {
    if (previousState.player?.item_used) throw battleError("ITEM_ALREADY_USED");
    if (!isBattleItem(itemId)) throw battleError("INVALID_ITEM");
  }

  const state = structuredClone(previousState);
  const random = seededRandom(turnSeed(state, idempotencyKey));
  const botAction = chooseBotAction(state.bot, random);
  assertAffordable(state.player, playerAction);
  assertAffordable(state.bot, botAction);

  const actions = { player: playerAction, bot: botAction };
  const events = [];
  applyIntent(state.player, playerAction, itemId);
  applyIntent(state.bot, botAction);
  if (playerAction === "guard") events.push(guardEvent("player", state.player));
  if (playerAction === "item") events.push(itemEvent("player", state.player, itemId));
  if (botAction === "guard") events.push(guardEvent("bot", state.bot));

  const order = turnOrder(state.player, state.bot, random);
  for (const actorName of order) {
    const targetName = actorName === "player" ? "bot" : "player";
    const actor = state[actorName];
    const target = state[targetName];
    const action = actions[actorName];
    if (actor.hp <= 0 || target.hp <= 0 || action === "guard" || action === "item") continue;

    const crit = random() < critChance(actor.spd);
    const attackElement = action === "surge"
      ? (actor.secondary_element || actor.element)
      : actor.element;
    const targetDefenses = defenseElements(target.element, target.secondary_element);
    const elem = dualDefenderMultiplier(
      attackElement,
      target.element,
      target.secondary_element,
    );
    const attack = action === "surge"
      ? actor.special * (actor.special_mult || 1)
      : actor.atk * (actor.atk_mult || 1);
    const defense = action === "surge" ? Math.trunc(target.def * 0.5) : target.def;
    let damage = computeDamage({
      attack,
      defense,
      power: action === "surge" ? 75 : 50,
      element: elem,
      crit,
      variance: 0.92 + random() * 0.16,
      guarding: target.guarding,
    });
    damage = applyIncomingModifiers(target, damage);
    target.hp = Math.max(0, target.hp - damage);
    events.push({
      type: "attack",
      actor: actorName,
      target: targetName,
      action,
      damage,
      crit,
      attack_element: attackElement,
      defense_elements: targetDefenses,
      element_multiplier: elem,
      target_hp: target.hp,
    });
    if (target.hp === 0) events.push({ type: "knockout", actor: targetName });
  }

  state.player.guarding = false;
  state.bot.guarding = false;
  if (state.bot.hp === 0) state.status = "won";
  else if (state.player.hp === 0) state.status = "lost";

  // PP sengaja tidak pulih per turn. Battle terukur selesai sekitar empat turn,
  // jadi regen +1/turn membuat PP membeku di angka awalnya dan Special selalu
  // tersedia. Satu-satunya pemulihan adalah Guard, di applyIntent().
  state.turn += 1;

  if (state.status === "active" && state.turn > BATTLE_MAX_TURNS) {
    const playerRatio = state.player.hp / state.player.max_hp;
    const botRatio = state.bot.hp / state.bot.max_hp;
    state.status = playerRatio > botRatio ? "won" : "lost";
    events.push({ type: "timeout", winner: state.status === "won" ? "player" : "bot" });
  }

  if (state.status !== "active") {
    events.push({ type: "finished", result: state.status });
  }
  return { state, events, bot_action: botAction };
}

export function createFighter(input) {
  const grown = toBattleStats(
    input?.base_stats,
    input?.stage,
    input?.evolution_branch,
    input?.level,
  );
  const hunger = input?.hunger ?? input?.care?.hunger;
  const hygiene = input?.hygiene ?? input?.care?.hygiene;
  const stats = scaleCombatStats(grown, careCombatMultiplier(hunger, hygiene));
  return {
    ...stats,
    hp: stats.max_hp,
    momentum: MOMENTUM_START,
    momentum_max: MOMENTUM_MAX,
    guarding: false,
    atk_mult: 1,
    special_mult: 1,
    incoming_mult: 1,
    shield_charges: 0,
    item_used: false,
    item_id: "",
    element: normalizeElement(input?.element),
    secondary_element: input?.secondary_element
      ? normalizeElement(input.secondary_element, "")
      : "",
    species_key: String(input?.species_key ?? ""),
    color_bucket: String(input?.color_bucket ?? ""),
    stage: clampInt(input?.stage, 1, 3, 1),
    level: clampInt(input?.level, 1, LEVEL_CAP, 1),
    evolution_branch: String(input?.evolution_branch ?? ""),
  };
}

export function applyIntent(fighter, action, itemId = "") {
  if (action === "surge") fighter.momentum -= SURGE_COST;
  if (action === "guard") {
    fighter.momentum = Math.min(fighter.momentum_max || MOMENTUM_MAX, fighter.momentum + 1);
    fighter.guarding = true;
  }
  if (action === "item") applyBattleItem(fighter, itemId);
}

function applyBattleItem(fighter, itemId) {
  const item = catalogItem(itemId);
  if (!item || item.use_type !== "battle") throw battleError("INVALID_ITEM");
  fighter.item_used = true;
  fighter.item_id = item.id;
  const value = Number(item.effect_value) || 0;
  if (item.effect === "heal_hp_pct") {
    fighter.hp = Math.min(
      fighter.max_hp,
      fighter.hp + Math.trunc(fighter.max_hp * (value / 100)),
    );
  } else if (item.effect === "buff_atk") {
    fighter.atk_mult = 1 + value / 100;
  } else if (item.effect === "buff_special") {
    fighter.special_mult = 1 + value / 100;
  } else if (item.effect === "buff_guard") {
    fighter.incoming_mult = 1 - value / 100;
  } else if (item.effect === "buff_spd") {
    fighter.spd = Math.max(1, Math.trunc(fighter.spd * (1 + value / 100)));
  } else if (item.effect === "pp_boost") {
    fighter.momentum_max = Math.min(5, (fighter.momentum_max || MOMENTUM_MAX) + value);
    fighter.momentum = Math.min(fighter.momentum_max, fighter.momentum + value);
  } else if (item.effect === "phase_shield") {
    fighter.shield_charges = 1;
  }
}

export function applyIncomingModifiers(target, damage) {
  let next = Math.max(1, Math.trunc(damage * (target.incoming_mult || 1)));
  if ((target.shield_charges || 0) > 0) {
    next = Math.max(1, Math.trunc(next * 0.2));
    target.shield_charges -= 1;
  }
  return next;
}

export function assertAffordable(fighter, action) {
  if (action === "surge" && fighter.momentum < SURGE_COST) {
    throw battleError("NO_MOMENTUM");
  }
}

export function turnOrder(player, bot, random) {
  if (player.spd > bot.spd) return ["player", "bot"];
  if (bot.spd > player.spd) return ["bot", "player"];
  return random() < 0.5 ? ["player", "bot"] : ["bot", "player"];
}

export function guardEvent(actor, fighter) {
  return { type: "guard", actor, momentum: fighter.momentum };
}

export function itemEvent(actor, fighter, itemId) {
  const item = catalogItem(itemId);
  return {
    type: "item",
    actor,
    item_id: itemId,
    effect: item?.effect ?? "",
    effect_value: item?.effect_value ?? 0,
    hp: fighter.hp,
    momentum: fighter.momentum,
    momentum_max: fighter.momentum_max,
  };
}

export function battleError(code) {
  const error = new Error(code);
  error.code = code;
  return error;
}

export function seededRandom(seed) {
  let value = hashSeed(seed);
  return () => {
    value += 0x6d2b79f5;
    let mixed = value;
    mixed = Math.imul(mixed ^ (mixed >>> 15), mixed | 1);
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> 7), mixed | 61);
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296;
  };
}

function hashSeed(value) {
  let hash = 2166136261;
  for (const char of String(value)) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function clampInt(value, min, max, fallback) {
  const number = Number(value);
  return Math.trunc(clamp(Number.isFinite(number) ? number : fallback, min, max));
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
