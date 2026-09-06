// DEV TEST MODE — remove this file and its expedition/index.ts call sites to
// fully retire Test Boss Seeker.
import { createTeamBattleState, resolveTeamTurn } from "./team_combat.mjs";

export function createBossPractice({
  chapterVersionId,
  playerSnapshot,
  opponentSnapshot,
  acePassive,
  backgroundPath,
  seed,
}) {
  if (!validRoster(playerSnapshot) || !validRoster(opponentSnapshot)) {
    throw new Error("TEAM_REQUIRES_FOUR");
  }
  const id = `practice-boss-${crypto.randomUUID()}`;
  const state = createTeamBattleState({
    player: playerSnapshot,
    opponent: opponentSnapshot,
    seed,
    encounterKind: "boss",
    acePassive,
  });
  return {
    practice: true,
    run: {
      id,
      chapter_version_id: String(chapterVersionId),
      team_id: "",
      status: "active",
      zone: 3,
      zone_attempt: 1,
      version: 1,
      zone_map: {
        schema_version: 1,
        zone: 3,
        attempt: 1,
        seed: String(seed),
        nodes: [],
        ...(typeof backgroundPath === "string" && backgroundPath && !backgroundPath.includes("..")
          ? { background_path: backgroundPath }
          : {}),
      },
      available_node_ids: [],
      visited_node_ids: [],
      current_node_id: "practice-boss",
      nodes_completed: 0,
      supplies: 0,
      boosts: [],
      party_state: structuredClone(playerSnapshot),
      pending_node: null,
      checkpoint_choice: null,
      checkpoint_choice_pending: false,
      practice: true,
    },
    encounter: {
      id,
      run_id: id,
      node_id: "practice-boss",
      kind: "boss",
      player_snapshot: structuredClone(playerSnapshot),
      opponent_snapshot: structuredClone(opponentSnapshot),
      state,
      turn_number: 1,
      version: 1,
      status: "active",
      practice: true,
    },
  };
}

export function resolveBossPracticeTurn({
  encounter: input,
  expectedTurn,
  expectedVersion,
  action,
  idempotencyKey,
  itemId = "",
  switchToSlot = null,
}) {
  const encounter = practiceEncounter(input);
  if (
    encounter.turn_number !== expectedTurn ||
    encounter.version !== expectedVersion ||
    Number(encounter.state.turn) !== expectedTurn
  ) {
    throw new Error("STALE_EXPEDITION_ENCOUNTER");
  }
  const resolution = resolveTeamTurn(
    encounter.state,
    action,
    idempotencyKey,
    itemId,
    switchToSlot,
  );
  const next = {
    ...encounter,
    state: resolution.state,
    turn_number: Number(resolution.state.turn),
    version: encounter.version + 1,
    status: String(resolution.state.status),
  };
  if (next.status !== "active") {
    next.last_reward = {
      practice: true,
      bits: 0,
      clear_bits: 0,
      supplies: 0,
      anima_exp: [],
    };
  }
  return {
    encounter: next,
    events: resolution.events,
    bot_action: resolution.bot_action,
    reward: next.last_reward ?? {},
    practice: true,
  };
}

function practiceEncounter(value) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    value.practice !== true ||
    value.kind !== "boss" ||
    value.status !== "active" ||
    !validRoster(value.player_snapshot) ||
    !validRoster(value.opponent_snapshot) ||
    !value.state ||
    typeof value.state !== "object" ||
    !validParty(value.state.player) ||
    !validParty(value.state.opponent) ||
    !Number.isInteger(value.turn_number) ||
    !Number.isInteger(value.version)
  ) {
    throw new Error("INVALID_EXPEDITION_ENCOUNTER");
  }
  // ponytail: staff-only, zero-persistence practice round-trips combat state
  // through the client. If this ever opens beyond staff, sign the state first.
  return structuredClone(value);
}

function validRoster(value) {
  return Array.isArray(value) &&
    value.length === 4 &&
    value.every((member) =>
      member &&
      typeof member === "object" &&
      !Array.isArray(member) &&
      typeof member.anima_id === "string" &&
      member.anima_id.length > 0
    );
}

function validParty(value) {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Array.isArray(value.roster) &&
    value.roster.length === 4;
}
