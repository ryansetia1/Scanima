export const ELEMENT_CYCLE = Object.freeze(["metal", "plant", "flow", "spark", "cloth", "stone"]);
export const BATTLE_ACTIONS = Object.freeze(["strike", "surge", "guard"]);
export const MOMENTUM_MAX = 3;
export const MOMENTUM_START = 3;
export const SURGE_COST = 1;
export const BATTLE_MAX_TURNS = 30;

const STAT_KEYS = Object.freeze(["hp", "atk", "def", "spd", "special"]);
const ELEMENT_ALIASES = Object.freeze({
  tech: "spark",
  electric: "spark",
  water: "flow",
  earth: "stone",
  nature: "plant",
  fire: "spark",
  air: "cloth",
});

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

export function toBattleStats(baseStats, stage = 1, branch = "") {
  const base = normalizeBaseStats(baseStats);
  const mult = stageMultipliers(stage, branch);
  return {
    max_hp: Math.trunc(base.hp * 4 * mult.hp) + 20,
    atk: Math.trunc(base.atk * mult.atk),
    def: Math.trunc(base.def * mult.def),
    spd: Math.trunc(base.spd * mult.spd),
    special: Math.trunc(base.special * mult.special),
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

export function elementMultiplier(attacker, defender) {
  const attackerIndex = ELEMENT_CYCLE.indexOf(normalizeElement(attacker, ""));
  const defenderIndex = ELEMENT_CYCLE.indexOf(normalizeElement(defender, ""));
  if (attackerIndex < 0 || defenderIndex < 0) return 1.0;
  if ((attackerIndex + 1) % ELEMENT_CYCLE.length === defenderIndex) return 1.5;
  if ((defenderIndex + 1) % ELEMENT_CYCLE.length === attackerIndex) return 0.67;
  return 1.0;
}

export function normalizeElement(element, fallback = "stone") {
  const value = String(element ?? "").toLowerCase();
  if (ELEMENT_CYCLE.includes(value)) return value;
  return ELEMENT_ALIASES[value] ?? fallback;
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
    player: createFighter(player),
    bot: createFighter(bot),
  };
}

export function chooseBotAction(fighter, random) {
  const roll = random();
  const hpRatio = fighter.hp / Math.max(1, fighter.max_hp);
  if (hpRatio <= 0.4 && roll < 0.45) return "guard";
  if (fighter.momentum >= SURGE_COST && roll < 0.68) return "surge";
  return "strike";
}

export function resolveTurn(previousState, playerAction, idempotencyKey = "") {
  if (previousState?.status !== "active") throw battleError("BATTLE_FINISHED");
  if (!BATTLE_ACTIONS.includes(playerAction)) throw battleError("INVALID_ACTION");

  const state = structuredClone(previousState);
  const random = seededRandom(`${state.seed}:${state.turn}:${idempotencyKey}`);
  const botAction = chooseBotAction(state.bot, random);
  assertAffordable(state.player, playerAction);
  assertAffordable(state.bot, botAction);

  const actions = { player: playerAction, bot: botAction };
  const events = [];
  applyIntent(state.player, playerAction);
  applyIntent(state.bot, botAction);
  if (playerAction === "guard") events.push(guardEvent("player", state.player));
  if (botAction === "guard") events.push(guardEvent("bot", state.bot));

  const order = turnOrder(state.player, state.bot, random);
  for (const actorName of order) {
    const targetName = actorName === "player" ? "bot" : "player";
    const actor = state[actorName];
    const target = state[targetName];
    const action = actions[actorName];
    if (actor.hp <= 0 || target.hp <= 0 || action === "guard") continue;

    const crit = random() < critChance(actor.spd);
    const elem = elementMultiplier(actor.element, target.element);
    const attack = action === "surge" ? actor.special : actor.atk;
    const defense = action === "surge" ? Math.trunc(target.def * 0.5) : target.def;
    const damage = computeDamage({
      attack,
      defense,
      power: action === "surge" ? 75 : 50,
      element: elem,
      crit,
      variance: 0.92 + random() * 0.16,
      guarding: target.guarding,
    });
    target.hp = Math.max(0, target.hp - damage);
    events.push({
      type: "attack",
      actor: actorName,
      target: targetName,
      action,
      damage,
      crit,
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

function createFighter(input) {
  const stats = toBattleStats(input?.base_stats, input?.stage, input?.evolution_branch);
  return {
    ...stats,
    hp: stats.max_hp,
    momentum: MOMENTUM_START,
    guarding: false,
    element: normalizeElement(input?.element),
    species_key: String(input?.species_key ?? ""),
    color_bucket: String(input?.color_bucket ?? ""),
    stage: clampInt(input?.stage, 1, 3, 1),
    evolution_branch: String(input?.evolution_branch ?? ""),
  };
}

function applyIntent(fighter, action) {
  if (action === "surge") fighter.momentum -= SURGE_COST;
  if (action === "guard") {
    fighter.momentum = Math.min(MOMENTUM_MAX, fighter.momentum + 1);
    fighter.guarding = true;
  }
}

function assertAffordable(fighter, action) {
  if (action === "surge" && fighter.momentum < SURGE_COST) {
    throw battleError("NO_MOMENTUM");
  }
}

function turnOrder(player, bot, random) {
  if (player.spd > bot.spd) return ["player", "bot"];
  if (bot.spd > player.spd) return ["bot", "player"];
  return random() < 0.5 ? ["player", "bot"] : ["bot", "player"];
}

function guardEvent(actor, fighter) {
  return { type: "guard", actor, momentum: fighter.momentum };
}

function battleError(code) {
  const error = new Error(code);
  error.code = code;
  return error;
}

function seededRandom(seed) {
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
