// Canonical move-effect catalog and deterministic combat helpers.
// Shared by evolution validation, battle.mjs, team_combat.mjs, and selftest.

export const EVOLUTION_EFFECT_IDS = Object.freeze([
  "armor_pierce",
  "guard_break",
  "drain",
  "barrier",
  "poison",
  "burn",
  "slow",
  "armor_break",
]);

export const STRIKE_EFFECT_IDS = Object.freeze([
  "armor_pierce",
  "guard_break",
  "drain",
  "poison",
  "burn",
  "slow",
  "armor_break",
]);

export const SURGE_EFFECT_IDS = Object.freeze([
  "barrier",
  "guard_break",
  "drain",
  "burn",
  "slow",
  "armor_break",
]);

/** Evolved may retain or upgrade prior effect families. */
export const EFFECT_UPGRADES = Object.freeze({
  "": [...EVOLUTION_EFFECT_IDS],
  armor_pierce: ["armor_pierce", "guard_break"],
  guard_break: ["guard_break"],
  drain: ["drain"],
  barrier: ["barrier"],
  poison: ["poison", "burn"],
  burn: ["burn"],
  slow: ["slow", "armor_break"],
  armor_break: ["armor_break"],
});

/** Committed form power; calibrated via duelWinRate sweeps in selftest. */
export const ADULT_FORM_MULT = 1.06;
export const EVOLVED_FORM_MULT = 1.18;

/** Team reward preview: +4% combat power per effect (Adult), +6% (Evolved). */
export const ADULT_EFFECT_POWER_BONUS = 0.04;
export const EVOLVED_EFFECT_POWER_BONUS = 0.06;

const PERSISTENT_EFFECTS = new Set(["poison", "burn", "slow", "armor_break"]);
const TICK_EFFECTS = new Set(["poison", "burn"]);

const EFFECT_DEFAULTS = Object.freeze({
  armor_pierce: { kind: "immediate", target: "foe_def" },
  guard_break: { kind: "immediate", target: "foe_guard" },
  drain: { kind: "immediate", target: "self_heal" },
  barrier: { kind: "immediate", target: "self_barrier" },
  poison: { kind: "persistent", ticks: 3, pct: true },
  burn: { kind: "persistent", ticks: 2, pct: true },
  slow: { kind: "persistent", ticks: 3, stat: "spd" },
  armor_break: { kind: "persistent", ticks: 3, stat: "def" },
});

export function normalizeEffectId(value) {
  const id = String(value ?? "").trim();
  return EVOLUTION_EFFECT_IDS.includes(id) ? id : "";
}

export function effectAllowed(action, id) {
  const allow = action === "strike" ? STRIKE_EFFECT_IDS : SURGE_EFFECT_IDS;
  return allow.includes(id);
}

export function evolvedEffectAllowed(action, id, priorId) {
  if (!effectAllowed(action, id)) return false;
  const upgrades = EFFECT_UPGRADES[priorId ?? ""] ?? EVOLUTION_EFFECT_IDS;
  return upgrades.includes(id);
}

export function usesEvolutionCombat(rulesVersion, evolutionVersion) {
  return Math.trunc(Number(rulesVersion) || 0) >= 3
    && Math.trunc(Number(evolutionVersion) || 0) >= 1;
}

export function formMultiplier(stage) {
  const s = Math.trunc(Number(stage) || 1);
  if (s >= 3) return EVOLVED_FORM_MULT;
  if (s >= 2) return ADULT_FORM_MULT;
  return 1;
}

/** Adult 20% strengths; Evolved 30%. */
export function effectStrength(stage) {
  return Math.trunc(Number(stage) || 1) >= 3 ? 0.30 : 0.20;
}

export function effectIdForAction(fighter, action) {
  if (action === "strike") return normalizeEffectId(fighter?.strike_effect_id);
  if (action === "surge") return normalizeEffectId(fighter?.surge_effect_id);
  return "";
}

export function shouldApplyEffects(rulesVersion, fighter) {
  return usesEvolutionCombat(rulesVersion, fighter?.evolution_version);
}

export function hasEvolutionEffects(rulesVersion, fighter) {
  return shouldApplyEffects(rulesVersion, fighter)
    && Boolean(
      effectIdForAction(fighter, "strike")
      || effectIdForAction(fighter, "surge"),
    );
}

/** Status/barrier state machine is active for all fighters once rules v3 is live. */
export function effectsCombatActive(rulesVersion) {
  return Math.trunc(Number(rulesVersion) || 0) >= 3;
}

/** Small fixed bonus for team reward preview when effects are committed. */
export function effectPowerBonus(fighter, rulesVersion = 3) {
  if (!shouldApplyEffects(rulesVersion, fighter)) return 0;
  const stage = Math.trunc(Number(fighter?.stage) || 1);
  const rate = stage >= 3 ? EVOLVED_EFFECT_POWER_BONUS : ADULT_EFFECT_POWER_BONUS;
  let count = 0;
  if (effectIdForAction(fighter, "strike")) count += 1;
  if (effectIdForAction(fighter, "surge")) count += 1;
  return count * rate;
}

export function createEffectState() {
  return {
    statuses: {},
    barrier: null,
  };
}

export function attachEffectFields(fighter, input = {}, rulesVersion = 3) {
  fighter.strike_effect_id = normalizeEffectId(input?.strike_effect_id);
  fighter.surge_effect_id = normalizeEffectId(input?.surge_effect_id);
  fighter.evolution_version = Math.max(0, Math.trunc(Number(input?.evolution_version) || 0));
  if (!fighter.statuses || typeof fighter.statuses !== "object") {
    fighter.statuses = {};
  }
  if (fighter.barrier === undefined) fighter.barrier = null;
  if (!shouldApplyEffects(rulesVersion, fighter)) {
    fighter.statuses = {};
    fighter.barrier = null;
  }
  return fighter;
}

export function effectiveSpd(fighter) {
  const base = Math.max(1, Math.trunc(Number(fighter?.spd) || 1));
  const slow = fighter?.statuses?.slow;
  if (!slow) return base;
  const strength = Number(slow.strength) || 0;
  return Math.max(1, Math.trunc(base * (1 - strength)));
}

export function effectiveDef(fighter) {
  const base = Math.max(0, Math.trunc(Number(fighter?.def) || 0));
  const breakStatus = fighter?.statuses?.armor_break;
  if (!breakStatus) return base;
  const strength = Number(breakStatus.strength) || 0;
  return Math.max(0, Math.trunc(base * (1 - strength)));
}

function statusTurns(effectId, stage) {
  if (!EFFECT_DEFAULTS[effectId]) return 0;
  if (effectId === "burn") return Math.trunc(Number(stage) || 1) >= 3 ? 3 : 2;
  if (effectId === "poison" || effectId === "slow" || effectId === "armor_break") return 3;
  return 0;
}

function barrierOwnerTurns(stage) {
  return Math.trunc(Number(stage) || 1) >= 3 ? 3 : 2;
}

function refreshStatus(fighter, effectId, stage) {
  const strength = effectStrength(stage);
  const turns = statusTurns(effectId, stage);
  if (!turns) return;
  fighter.statuses[effectId] = { remaining_turns: turns, strength };
}

function moveEffectEvent(side, targetSide, effectId, extra = {}) {
  return {
    type: "move_effect",
    actor: side,
    target: targetSide,
    effect_id: effectId,
    ...extra,
  };
}

function statusTickEvent(side, effectId, amount, remainingTurns, targetHp, slot = null) {
  const event = {
    type: "status_tick",
    actor: side,
    target: side,
    effect_id: effectId,
    amount,
    remaining_turns: remainingTurns,
    target_hp: targetHp,
  };
  if (slot !== null && slot !== undefined) event.actor_slot = slot;
  return event;
}

function statusExpiredEvent(side, effectId, slot = null) {
  const event = {
    type: "status_expired",
    actor: side,
    target: side,
    effect_id: effectId,
  };
  if (slot !== null && slot !== undefined) event.actor_slot = slot;
  return event;
}

/**
 * Pre-damage modifiers for pierce, guard break, and effective defense.
 * Effect events are collected in effectEvents (not appended to caller events).
 */
export function preDamageModifiers({
  actor,
  target,
  action,
  rulesVersion,
  effectEvents = [],
  actorSide,
  targetSide,
  actorSlot = null,
  targetSlot = null,
}) {
  let defense = action === "surge"
    ? Math.trunc(effectiveDef(target) * 0.5)
    : effectiveDef(target);
  let guarding = Boolean(target.guarding);
  if (!shouldApplyEffects(rulesVersion, actor)) {
    return { defense, guarding };
  }

  const effectId = effectIdForAction(actor, action);
  if (!effectId) return { defense, guarding };

  const stage = Math.trunc(Number(actor.stage) || 1);
  const strength = effectStrength(stage);
  const slotExtra = {
    ...(actorSlot !== null ? { actor_slot: actorSlot } : {}),
    ...(targetSlot !== null ? { target_slot: targetSlot } : {}),
  };

  if (effectId === "armor_pierce") {
    defense = Math.max(0, Math.trunc(defense * (1 - strength)));
    effectEvents.push(moveEffectEvent(actorSide, targetSide, effectId, {
      amount: strength,
      ...slotExtra,
    }));
  }

  if (effectId === "guard_break" && guarding) {
    guarding = false;
    target.guarding = false;
    effectEvents.push(moveEffectEvent(actorSide, targetSide, effectId, {
      amount: strength,
      ...slotExtra,
    }));
  }

  return { defense, guarding };
}

/** Barrier on defender reduces one incoming hit. */
export function applyBarrierToDamage(
  target,
  damage,
  rulesVersion,
  effectEvents,
  targetSide,
  targetSlot = null,
) {
  if (!shouldApplyEffects(rulesVersion, target) || !target.barrier) {
    return damage;
  }
  const barrier = target.barrier;
  if ((barrier.uses_remaining ?? 0) <= 0) return damage;

  const reduction = Number(barrier.reduction) || 0;
  const next = Math.max(1, Math.trunc(damage * (1 - reduction)));
  barrier.uses_remaining = 0;
  effectEvents.push(moveEffectEvent(targetSide, targetSide, "barrier", {
    amount: reduction,
    target_hp: Math.max(0, Math.trunc(Number(target.hp) || 0) - next),
    ...(targetSlot !== null ? { actor_slot: targetSlot, target_slot: targetSlot } : {}),
  }));
  target.barrier = null;
  return next;
}

/** Post-damage move effects: drain heal, barrier grant, persistent debuffs. */
export function applyPostMoveEffects({
  actor,
  target,
  action,
  damage,
  rulesVersion,
  effectEvents = [],
  actorSide,
  targetSide,
  actorSlot = null,
  targetSlot = null,
}) {
  if (!shouldApplyEffects(rulesVersion, actor)) return;

  const effectId = effectIdForAction(actor, action);
  if (!effectId) return;

  const stage = Math.trunc(Number(actor.stage) || 1);
  const strength = effectStrength(stage);
  const slotExtra = {
    ...(actorSlot !== null ? { actor_slot: actorSlot } : {}),
    ...(targetSlot !== null ? { target_slot: targetSlot } : {}),
  };

  if (effectId === "drain" && damage > 0) {
    const heal = Math.max(1, Math.trunc(damage * strength));
    actor.hp = Math.min(actor.max_hp, Math.trunc(Number(actor.hp) || 0) + heal);
    effectEvents.push(moveEffectEvent(actorSide, actorSide, effectId, {
      amount: heal,
      target_hp: actor.hp,
      ...(actorSlot !== null ? { actor_slot: actorSlot } : {}),
    }));
  }

  if (effectId === "barrier") {
    const turns = barrierOwnerTurns(stage);
    actor.barrier = {
      reduction: strength,
      uses_remaining: 1,
      owner_turns_remaining: turns,
      just_applied: true,
    };
    effectEvents.push(moveEffectEvent(actorSide, actorSide, effectId, {
      amount: strength,
      remaining_turns: turns,
      ...(actorSlot !== null ? { actor_slot: actorSlot } : {}),
    }));
  }

  if (PERSISTENT_EFFECTS.has(effectId) && Math.trunc(Number(target.hp) || 0) > 0) {
    refreshStatus(target, effectId, stage);
    effectEvents.push(moveEffectEvent(actorSide, targetSide, effectId, {
      amount: strength,
      remaining_turns: statusTurns(effectId, stage),
      ...slotExtra,
    }));
  }
}

/** Count down barrier owner turns when the owner acted this turn. */
export function tickBarrierOwnerTurn(fighter, rulesVersion, events, side, slot = null) {
  if (!shouldApplyEffects(rulesVersion, fighter) || !fighter.barrier) return;
  if (fighter.barrier.just_applied) {
    fighter.barrier.just_applied = false;
    return;
  }
  const remaining = Math.trunc(Number(fighter.barrier.owner_turns_remaining) || 0);
  if (remaining <= 0) {
    fighter.barrier = null;
    return;
  }
  fighter.barrier.owner_turns_remaining = remaining - 1;
  if (fighter.barrier.owner_turns_remaining <= 0) {
    fighter.barrier = null;
    events.push(statusExpiredEvent(side, "barrier", slot));
  }
}

/**
 * End-of-turn status ticks and expiry for one fighter.
 * Returns true when a tick reduced HP from >0 to 0.
 */
export function tickFighterStatuses(fighter, rulesVersion, events, side, slot = null) {
  if (!effectsCombatActive(rulesVersion)) {
    fighter.statuses = {};
    return false;
  }
  if (Math.trunc(Number(fighter.hp) || 0) <= 0) return false;

  let koFromTick = false;
  const statuses = fighter.statuses ?? {};
  for (const effectId of Object.keys(statuses)) {
    const status = statuses[effectId];
    if (!status) continue;

    if (TICK_EFFECTS.has(effectId)) {
      const pct = Number(status.strength) || 0;
      const tick = Math.max(1, Math.trunc(fighter.max_hp * pct));
      const hpBefore = Math.trunc(Number(fighter.hp) || 0);
      fighter.hp = Math.max(0, hpBefore - tick);
      if (hpBefore > 0 && fighter.hp === 0) koFromTick = true;
      events.push(statusTickEvent(side, effectId, tick, status.remaining_turns, fighter.hp, slot));
    }

    status.remaining_turns = Math.trunc(Number(status.remaining_turns) || 0) - 1;
    if (status.remaining_turns <= 0) {
      delete statuses[effectId];
      events.push(statusExpiredEvent(side, effectId, slot));
    }
  }
  fighter.statuses = statuses;
  return koFromTick;
}

/** Deterministic action score for effect-aware duel/team AI (no RNG). */
export function scoreActionValue({
  actor,
  target,
  action,
  rulesVersion,
  computeDamage,
  applyIncomingModifiers,
  dualDefenderMultiplier,
}) {
  // Scoring is a preview. Guard break and phase shield consume state during a
  // real hit, so never let action selection mutate the authoritative fighter.
  const previewTarget = structuredClone(target);
  const attackElement = action === "surge"
    ? (actor.secondary_element || actor.element)
    : actor.element;
  const elem = dualDefenderMultiplier(
    attackElement,
    previewTarget.element,
    previewTarget.secondary_element,
  );
  const attack = action === "surge"
    ? actor.special * (actor.special_mult || 1)
    : actor.atk * (actor.atk_mult || 1);
  const { defense, guarding } = preDamageModifiers({
    actor,
    target: previewTarget,
    action,
    rulesVersion,
    effectEvents: [],
    actorSide: "player",
    targetSide: "bot",
  });
  let damage = computeDamage({
    attack,
    defense,
    power: action === "surge" ? 75 : 50,
    element: elem,
    crit: false,
    variance: 1.0,
    guarding,
  });
  if (previewTarget.barrier?.uses_remaining > 0) {
    const reduction = Number(previewTarget.barrier.reduction) || 0;
    damage = Math.max(1, Math.trunc(damage * (1 - reduction)));
  }
  damage = applyIncomingModifiers(previewTarget, damage);

  let score = damage;
  if (!shouldApplyEffects(rulesVersion, actor)) return score;

  const effectId = effectIdForAction(actor, action);
  const stage = Math.trunc(Number(actor.stage) || 1);
  const strength = effectStrength(stage);

  if (effectId === "drain" && damage > 0) {
    const heal = Math.max(1, Math.trunc(damage * strength));
    const missing = Math.max(0, actor.max_hp - Math.trunc(Number(actor.hp) || 0));
    score += Math.min(heal, missing) * 0.5;
  }
  if (effectId === "barrier") {
    const hpRatio = Math.trunc(Number(actor.hp) || 0) / Math.max(1, actor.max_hp);
    score += hpRatio <= 0.5 ? 8 : 3;
  }
  if (PERSISTENT_EFFECTS.has(effectId) && Math.trunc(Number(previewTarget.hp) || 0) > damage) {
    score += strength * Math.trunc(Number(previewTarget.max_hp) || 1) * 0.15;
  }
  if (effectId === "slow" || effectId === "armor_break") {
    score += strength * 10;
  }
  return score;
}

/** Self-check: refresh-not-stack and unknown-id no-op. */
export function _moveEffectsSelfCheck() {
  const fighter = {
    max_hp: 100,
    hp: 100,
    spd: 50,
    def: 50,
    stage: 2,
    evolution_version: 1,
    statuses: {},
  };
  refreshStatus(fighter, "poison", 2);
  const first = fighter.statuses.poison.remaining_turns;
  refreshStatus(fighter, "poison", 2);
  if (fighter.statuses.poison.remaining_turns !== first) {
    throw new Error("poison should refresh, not stack");
  }
  if (normalizeEffectId("nope") !== "") throw new Error("unknown effect should no-op");
}
