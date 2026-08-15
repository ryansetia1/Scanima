import {
  BATTLE_ACTIONS,
  SURGE_COST,
  applyIncomingModifiers,
  applyIntent,
  assertAffordable,
  battleError,
  chooseBotAction,
  computeDamage,
  createFighter,
  critChance,
  guardEvent,
  itemEvent,
  seededRandom,
  turnOrder,
} from "./battle.mjs";
import {
  bitsForTier,
  combatPower,
  rewardRollFromSeed,
  rewardTierFromRatio,
} from "./catalog.mjs";
import { defenseElements, dualDefenderMultiplier } from "./elements.mjs";

export const TEAM_ACTIONS = Object.freeze([...BATTLE_ACTIONS, "switch"]);
export const TEAM_MAX_TURNS = 60;

export function createTeamBattleState({ player, opponent, seed }) {
  return {
    status: "active",
    turn: 1,
    seed: String(seed ?? ""),
    player: createTeamParty(player, true),
    opponent: createTeamParty(opponent, false),
  };
}

export function teamCombatPower(roster) {
  if (!Array.isArray(roster) || roster.length === 0) return 0;
  return roster.reduce((sum, member) => sum + combatPower(createFighter(member)), 0);
}

export function teamRewardPreview(player, opponent, seed) {
  const ratio = teamCombatPower(opponent) / Math.max(1, teamCombatPower(player));
  const tier = rewardTierFromRatio(ratio);
  const roll = rewardRollFromSeed(seed);
  return {
    tier,
    roll,
    bits: bitsForTier(tier, roll),
    bits_min: bitsForTier(tier, -1),
    bits_max: bitsForTier(tier, 1),
    ratio,
  };
}

export function resolveTeamTurn(
  previousState,
  playerAction,
  idempotencyKey = "",
  itemId = "",
  switchToSlot = null,
) {
  if (previousState?.status !== "active") throw battleError("TEAM_BATTLE_FINISHED");
  if (!TEAM_ACTIONS.includes(playerAction)) throw battleError("INVALID_ACTION");

  const state = structuredClone(previousState);
  const random = seededRandom(`${state.seed}:${state.turn}:${idempotencyKey}`);
  const events = [];

  if (state.player.forced_switch) {
    if (playerAction !== "switch") throw battleError("FORCED_SWITCH_REQUIRED");
    switchParty(state.player, switchToSlot, "player", events, true);
    finishTurn(state, events);
    return { state, events, bot_action: null };
  }

  validatePlayerIntent(state.player, playerAction, itemId, switchToSlot);
  const botIntent = chooseOpponentIntent(state.opponent, random);

  const playerFighter = activeFighter(state.player);
  const opponentFighter = activeFighter(state.opponent);
  assertAffordable(playerFighter, playerAction);
  assertAffordable(opponentFighter, botIntent.action);

  if (playerAction === "switch") {
    switchParty(state.player, switchToSlot, "player", events, false);
  } else {
    applyIntent(activeFighter(state.player), playerAction, itemId);
    if (playerAction === "item") state.player.item_used = true;
  }

  if (botIntent.action === "switch") {
    switchParty(state.opponent, botIntent.switch_to_slot, "opponent", events, false);
  } else {
    applyIntent(activeFighter(state.opponent), botIntent.action);
  }

  const playerActive = activeFighter(state.player);
  const opponentActive = activeFighter(state.opponent);
  if (playerAction === "guard") {
    events.push({ ...guardEvent("player", playerActive), actor_slot: state.player.active_slot });
  }
  if (playerAction === "item") {
    events.push({ ...itemEvent("player", playerActive, itemId), actor_slot: state.player.active_slot });
  }
  if (botIntent.action === "guard") {
    events.push({ ...guardEvent("opponent", opponentActive), actor_slot: state.opponent.active_slot });
  }

  const actions = { player: playerAction, opponent: botIntent.action };
  const order = turnOrder(playerActive, opponentActive, random)
    .map((side) => side === "bot" ? "opponent" : side);
  for (const side of order) {
    const targetSide = side === "player" ? "opponent" : "player";
    const party = state[side];
    const targetParty = state[targetSide];
    const actor = activeFighter(party);
    const target = activeFighter(targetParty);
    const action = actions[side];
    if (actor.hp <= 0 || target.hp <= 0 || action === "guard" || action === "item" || action === "switch") {
      continue;
    }

    events.push(resolveAttack(side, targetSide, party, targetParty, action, random));
    if (target.hp === 0) {
      events.push({ type: "knockout", actor: targetSide, actor_slot: targetParty.active_slot });
      if (!hasLivingMember(targetParty)) {
        state.status = targetSide === "opponent" ? "won" : "lost";
      } else if (targetSide === "opponent") {
        switchParty(targetParty, firstLivingBenchSlot(targetParty), "opponent", events, true);
      } else {
        targetParty.forced_switch = true;
      }
      // Replacement enters safely; the fighter that was knocked out cannot
      // donate its remaining initiative to the new active member.
      break;
    }
  }

  finishTurn(state, events);
  return {
    state,
    events,
    bot_action: botIntent,
  };
}

export function createTeamParty(roster, player = false) {
  if (!Array.isArray(roster) || roster.length < 1 || roster.length > 4) {
    throw battleError("INVALID_TEAM_ROSTER");
  }
  const fighters = roster.map((member, slot) => {
    const fighter = createFighter(member);
    const savedHp = Number(member?.current_hp ?? member?.hp);
    if (Number.isFinite(savedHp)) {
      const previousMax = Number(member?.max_hp);
      let hp = Math.trunc(savedHp);
      if (
        hp > 0
        && Number.isFinite(previousMax)
        && previousMax > 0
        && fighter.max_hp > previousMax
      ) {
        hp += fighter.max_hp - previousMax;
      }
      fighter.hp = Math.max(0, Math.min(fighter.max_hp, hp));
    }
    return {
      ...fighter,
      anima_id: String(member?.anima_id ?? ""),
      name: String(member?.name ?? ""),
      strike_name: String(member?.strike_name ?? ""),
      surge_name: String(member?.surge_name ?? ""),
      slot,
      participated: false,
    };
  });
  const activeSlot = fighters.findIndex((fighter) => fighter.hp > 0);
  if (activeSlot < 0) throw battleError("INVALID_TEAM_ROSTER");
  if (player) fighters[activeSlot].participated = true;
  return {
    active_slot: activeSlot,
    forced_switch: false,
    item_used: false,
    roster: fighters,
  };
}

function validatePlayerIntent(party, action, itemId, switchToSlot) {
  if (action === "item") {
    if (party.item_used) throw battleError("ITEM_ALREADY_USED");
    if (!itemId) throw battleError("INVALID_ITEM");
  } else if (itemId) {
    throw battleError("INVALID_ITEM");
  }
  if (action === "switch") validateSwitchSlot(party, switchToSlot);
}

function chooseOpponentIntent(party, random) {
  const fighter = activeFighter(party);
  const bench = livingBenchSlots(party);
  if (bench.length > 0 && fighter.hp / Math.max(1, fighter.max_hp) <= 0.3 && random() < 0.35) {
    return { action: "switch", switch_to_slot: bench[Math.floor(random() * bench.length)] };
  }
  return { action: chooseBotAction(fighter, random), switch_to_slot: null };
}

function switchParty(party, slot, side, events, forced) {
  validateSwitchSlot(party, slot);
  const previous = party.active_slot;
  party.active_slot = slot;
  party.forced_switch = false;
  activeFighter(party).participated = true;
  events.push({
    type: "switch",
    actor: side,
    from_slot: previous,
    to_slot: slot,
    forced,
  });
}

function validateSwitchSlot(party, slot) {
  if (!Number.isInteger(slot) || slot < 0 || slot >= party.roster.length) {
    throw battleError("INVALID_SWITCH_SLOT");
  }
  if (slot === party.active_slot || party.roster[slot].hp <= 0) {
    throw battleError("INVALID_SWITCH_SLOT");
  }
}

function resolveAttack(actorSide, targetSide, party, targetParty, action, random) {
  const actor = activeFighter(party);
  const target = activeFighter(targetParty);
  const crit = random() < critChance(actor.spd);
  const attackElement = action === "surge"
    ? (actor.secondary_element || actor.element)
    : actor.element;
  const targetDefenses = defenseElements(target.element, target.secondary_element);
  const element = dualDefenderMultiplier(
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
    element,
    crit,
    variance: 0.92 + random() * 0.16,
    guarding: target.guarding,
  });
  damage = applyIncomingModifiers(target, damage);
  target.hp = Math.max(0, target.hp - damage);
  return {
    type: "attack",
    actor: actorSide,
    target: targetSide,
    actor_slot: party.active_slot,
    target_slot: targetParty.active_slot,
    action,
    damage,
    crit,
    attack_element: attackElement,
    defense_elements: targetDefenses,
    element_multiplier: element,
    target_hp: target.hp,
  };
}

function finishTurn(state, events) {
  for (const party of [state.player, state.opponent]) {
    for (const fighter of party.roster) fighter.guarding = false;
  }
  state.turn += 1;

  if (state.status === "active" && state.turn > TEAM_MAX_TURNS) {
    const playerRatio = remainingHpRatio(state.player);
    const opponentRatio = remainingHpRatio(state.opponent);
    state.status = Math.abs(playerRatio - opponentRatio) <= 1e-9
      ? "draw"
      : playerRatio > opponentRatio
      ? "won"
      : "lost";
    events.push({
      type: "timeout",
      winner: state.status === "draw" ? null : state.status === "won" ? "player" : "opponent",
    });
  }
  if (state.status !== "active") events.push({ type: "finished", result: state.status });
}

function remainingHpRatio(party) {
  const current = party.roster.reduce((sum, fighter) => sum + Math.max(0, fighter.hp), 0);
  const maximum = party.roster.reduce((sum, fighter) => sum + Math.max(1, fighter.max_hp), 0);
  return current / Math.max(1, maximum);
}

function activeFighter(party) {
  return party.roster[party.active_slot];
}

function livingBenchSlots(party) {
  return party.roster
    .filter((fighter) => fighter.slot !== party.active_slot && fighter.hp > 0)
    .map((fighter) => fighter.slot);
}

function firstLivingBenchSlot(party) {
  return livingBenchSlots(party)[0] ?? -1;
}

function hasLivingMember(party) {
  return party.roster.some((fighter) => fighter.hp > 0);
}
