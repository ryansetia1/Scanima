// Vektor emas untuk paritas simulasi Godot <-> Deno.
//
// Client menjalankan resolver combat secara lokal supaya animasi mulai pada
// frame yang sama dengan tap dan sesi tetap jalan tanpa koneksi. Server tetap
// menghitung ulang turn yang sama dan hasilnya yang menang, jadi dua
// implementasi itu wajib memberi angka yang identik. File ini menggenerasi
// jawaban yang benar dari `.mjs` produksi; `game/tests/test_battle_sim_parity.gd`
// membandingkannya. Tidak ada panggilan API dan tidak ada biaya.
//
// Jalankan: node backend/tools/emit_sim_vectors.mjs --out /tmp/sim_vectors.json

import { writeFile } from "node:fs/promises";
import {
  RULES_VERSION,
  createBattleState,
  createFighter,
  resolveTurn,
  seededRandom,
  toBattleStats,
  battleExpYield,
  careCombatMultiplier,
  critChance,
  turnSeed,
} from "../supabase/functions/_shared/battle.mjs";
import {
  createTeamBattleState,
  resolveTeamTurn,
} from "../supabase/functions/_shared/team_combat.mjs";
import { CATALOG_ITEMS } from "../supabase/functions/_shared/catalog.mjs";
import { dualDefenderMultiplier, normalizeElement } from "../supabase/functions/_shared/elements.mjs";

const RNG_SEEDS = [
  "",
  "0",
  "a",
  "battle-seed:1",
  "9f8c2b1e-4d5a-4c3b-9e7f-1a2b3c4d5e6f:1",
  "9f8c2b1e-4d5a-4c3b-9e7f-1a2b3c4d5e6f:1:idem-key-0001",
  "team-seed:17",
  "zone:3:attempt:2:node:battle-a",
  ":::",
  "seed:999999",
];

function rngVectors() {
  return RNG_SEEDS.map((seed) => {
    // Ambil uint32 mentah, bukan hanya float, supaya perbandingan JSON eksak.
    const random = seededRandom(seed);
    const floats = [];
    for (let i = 0; i < 12; i += 1) floats.push(random());
    return { seed, floats, uints: floats.map((value) => Math.round(value * 4294967296)) };
  });
}

const FIGHTERS = {
  balanced: {
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    element: "metal",
    level: 1,
  },
  swift: {
    base_stats: { hp: 40, atk: 60, def: 35, spd: 90, special: 55 },
    element: "spark",
    secondary_element: "air",
    level: 12,
  },
  tanky: {
    base_stats: { hp: 90, atk: 35, def: 88, spd: 20, special: 40 },
    element: "stone",
    secondary_element: "metal",
    level: 20,
  },
  glassy: {
    base_stats: { hp: 12, atk: 95, def: 10, spd: 95, special: 95 },
    element: "glass",
    level: 40,
  },
  neglected: {
    base_stats: { hp: 55, atk: 55, def: 55, spd: 55, special: 55 },
    element: "plant",
    level: 9,
    hunger: 5,
    hygiene: 12,
  },
  nullCare: {
    base_stats: { hp: 55, atk: 55, def: 55, spd: 55, special: 55 },
    element: "flow",
    level: 9,
    care: { hunger: null, hygiene: null },
  },
  // Cukup kuat untuk menghabiskan tiga anggota reguler Boss dalam batas turn,
  // supaya jalur final_ace dan ace_passive benar-benar terekam.
  crusher: {
    base_stats: { hp: 95, atk: 95, def: 95, spd: 95, special: 95 },
    element: "spark",
    level: 40,
  },
  sparse: { element: "toxin" },
  bogusElement: {
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    element: "not-a-real-element",
    secondary_element: "definitely-not-real",
    level: 5,
  },
  adultEvolved: {
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    element: "metal",
    level: 16,
    stage: 2,
    evolution_version: 1,
    strike_effect_id: "armor_pierce",
    surge_effect_id: "barrier",
  },
  hatchlingPlain: {
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    element: "metal",
    level: 11,
    stage: 1,
    evolution_version: 1,
  },
  poisonTickVictim: {
    base_stats: { hp: 30, atk: 10, def: 10, spd: 10, special: 10 },
    element: "metal",
    level: 5,
    current_hp: 8,
  },
  poisonAdult: {
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    element: "toxin",
    level: 16,
    stage: 2,
    evolution_version: 1,
    strike_effect_id: "poison",
    surge_effect_id: "barrier",
  },
};

const DUEL_CASES = [
  { name: "mirror-strike", player: "balanced", bot: "balanced", seed: "duel-mirror",
    steps: [["strike"], ["strike"], ["strike"], ["strike"]] },
  { name: "speed-tie-order", player: "balanced", bot: "balanced", seed: "duel-tie-7",
    steps: [["strike"], ["guard"], ["strike"]] },
  { name: "surge-drains-pp", player: "swift", bot: "tanky", seed: "duel-surge",
    steps: [["surge"], ["surge"], ["surge"], ["surge"], ["guard"], ["surge"]] },
  { name: "guard-refills-pp", player: "tanky", bot: "swift", seed: "duel-guard",
    steps: [["guard"], ["guard"], ["strike"], ["surge"]] },
  { name: "dual-typing", player: "swift", bot: "tanky", seed: "duel-dual",
    steps: [["strike"], ["surge"], ["strike"]] },
  { name: "glass-cannon-ko", player: "glassy", bot: "glassy", seed: "duel-ko",
    steps: [["surge"], ["strike"], ["strike"], ["strike"], ["strike"]] },
  { name: "neglected-care-floor", player: "neglected", bot: "balanced", seed: "duel-care",
    steps: [["strike"], ["strike"]] },
  { name: "null-care-is-starving", player: "nullCare", bot: "balanced", seed: "duel-null",
    steps: [["strike"]] },
  { name: "sparse-input-defaults", player: "sparse", bot: "sparse", seed: "duel-sparse",
    steps: [["strike"], ["strike"]] },
  { name: "bogus-element-fallback", player: "bogusElement", bot: "balanced", seed: "duel-bogus",
    steps: [["strike"], ["surge"]] },
  { name: "invalid-action", player: "balanced", bot: "balanced", seed: "duel-invalid",
    steps: [["nonsense"]] },
  { name: "surge-without-pp", player: "balanced", bot: "balanced", seed: "duel-nopp",
    steps: [["surge"], ["surge"], ["surge"], ["surge"]] },
  { name: "effect-armor-pierce", player: "adultEvolved", bot: "tanky", seed: "duel-pierce",
    steps: [["strike"], ["strike"], ["strike"]] },
  { name: "effect-poison-tick", player: "poisonAdult", bot: "balanced", seed: "duel-poison",
    steps: [["strike"], ["guard"], ["strike"], ["guard"], ["strike"]] },
  { name: "effect-barrier", player: "adultEvolved", bot: "glassy", seed: "duel-barrier",
    steps: [["surge"], ["strike"], ["surge"]] },
  { name: "legacy-no-effects", player: "adultEvolved", bot: "hatchlingPlain", seed: "duel-legacy-fx",
    steps: [["strike"], ["strike"], ["strike"]] },
];

// Satu case per efek item Battle: masing-masing menyentuh cabang yang berbeda.
for (const item of CATALOG_ITEMS.filter((entry) => entry.use_type === "battle")) {
  DUEL_CASES.push({
    name: `item-${item.id}`,
    player: "balanced",
    bot: "tanky",
    seed: `duel-item-${item.id}`,
    steps: [["item", item.id], ["strike"], ["surge"], ["item", item.id]],
  });
}

function runDuel(testCase, rulesVersion) {
  let state = createBattleState({
    player: FIGHTERS[testCase.player],
    bot: FIGHTERS[testCase.bot],
    seed: testCase.seed,
    rules_version: rulesVersion,
  });
  if (rulesVersion === 1) delete state.rules_version;
  if (rulesVersion === 2) {
    state.rules_version = 2;
    state.player = createFighter(FIGHTERS[testCase.player], 2);
    state.bot = createFighter(FIGHTERS[testCase.bot], 2);
  }

  const initial = structuredClone(state);
  const steps = [];
  for (const [index, [action, itemId]] of testCase.steps.entries()) {
    const key = `${testCase.name}-key-${index}`;
    let outcome;
    try {
      outcome = resolveTurn(state, action, key, itemId ?? "");
    } catch (error) {
      steps.push({ action, item_id: itemId ?? "", key, error: error.code ?? String(error.message) });
      break;
    }
    steps.push({
      action,
      item_id: itemId ?? "",
      key,
      error: "",
      turn_seed: turnSeed(state, key),
      state: outcome.state,
      events: outcome.events,
      bot_action: outcome.bot_action,
    });
    state = outcome.state;
    if (state.status !== "active") break;
  }
  return { name: testCase.name, rules_version: rulesVersion, initial, steps };
}

const TEAM_ROSTERS = {
  squad: ["balanced", "swift", "tanky", "glassy"].map((key, slot) => ({
    ...FIGHTERS[key],
    anima_id: `player-${slot}`,
    name: `Player ${slot}`,
    strike_name: "Test Strike",
    surge_name: "Test Surge",
    body_height_cm: 90 + slot * 20,
  })),
  rivals: ["tanky", "balanced", "swift"].map((key, slot) => ({
    ...FIGHTERS[key],
    anima_id: `rival-${slot}`,
    name: `Rival ${slot}`,
    body_height_cm: 110,
  })),
  crushers: ["crusher", "crusher", "crusher", "crusher"].map((key, slot) => ({
    ...FIGHTERS[key],
    anima_id: `crusher-${slot}`,
    name: `Crusher ${slot}`,
    body_height_cm: 150,
  })),
  bossPack: ["balanced", "swift", "tanky", "glassy"].map((key, slot) => ({
    ...FIGHTERS[key],
    anima_id: `boss-${slot}`,
    name: `Boss ${slot}`,
    special: slot === 3,
    body_height_cm: 130,
  })),
};

const TEAM_CASES = [
  { name: "team-basic", player: "squad", opponent: "rivals", seed: "team-basic",
    steps: [["strike"], ["guard"], ["surge"], ["strike"]] },
  { name: "team-voluntary-switch", player: "squad", opponent: "rivals", seed: "team-switch",
    steps: [["switch", "", 2], ["strike"], ["switch", "", 0]] },
  { name: "team-invalid-switch", player: "squad", opponent: "rivals", seed: "team-bad-switch",
    steps: [["switch", "", 0]] },
  { name: "team-long-grind", player: "squad", opponent: "rivals", seed: "team-grind",
    steps: Array.from({ length: 24 }, () => ["strike"]) },
  { name: "boss-reserve-ace", player: "crushers", opponent: "bossPack", seed: "team-boss",
    kind: "boss",
    acePassive: { type: "bonus_pp", value: 2, name: "Overdrive", copy: "The ace surges." },
    steps: Array.from({ length: 30 }, () => ["strike"]) },
  { name: "boss-stat-boost-ace", player: "crushers", opponent: "bossPack", seed: "team-boss-stat",
    kind: "boss",
    acePassive: { type: "stat_boost", stat: "atk", value: 25, name: "Fury", copy: "Attack up." },
    steps: Array.from({ length: 30 }, () => ["strike"]) },
  { name: "boss-shield-ace", player: "crushers", opponent: "bossPack", seed: "team-boss-shield",
    kind: "boss",
    acePassive: { type: "one_hit_shield", name: "Bulwark", copy: "Absorbs a hit." },
    steps: Array.from({ length: 30 }, () => ["strike"]) },
  { name: "team-effect-poison", player: "squad", opponent: "rivals", seed: "team-poison",
    playerRoster: "poisonSquad",
    steps: [["strike"], ["strike"], ["guard"], ["strike"], ["strike"]] },
  { name: "team-status-ko", player: "squad", opponent: "rivals", seed: "team-status-ko-fixed",
    playerRoster: "poisonSquad",
    opponentRoster: "poisonVictims",
    steps: [["strike"]] },
];

const TEAM_ROSTER_ALIASES = {
  poisonSquad: [{
    ...FIGHTERS.poisonAdult,
    base_stats: { hp: 50, atk: 50, def: 50, spd: 99, special: 50 },
    element: "toxin",
    anima_id: "poison-0",
    name: "Poison 0",
    body_height_cm: 100,
  }, ...["balanced", "swift", "tanky"].map((key, slot) => ({
    ...FIGHTERS[key],
    anima_id: `poison-${slot + 1}`,
    name: `Poison ${slot + 1}`,
    body_height_cm: 110 + slot * 10,
  }))],
  poisonVictims: [{
    base_stats: { hp: 40, atk: 10, def: 10, spd: 10, special: 10 },
    element: "metal",
    level: 5,
    current_hp: 35,
    anima_id: "victim-0",
    name: "Victim",
    body_height_cm: 90,
  }, {
    ...FIGHTERS.balanced,
    base_stats: { hp: 50, atk: 10, def: 10, spd: 10, special: 10 },
    anima_id: "victim-1",
    name: "Bench",
    body_height_cm: 100,
  }],
};

function runTeam(testCase) {
  let state = createTeamBattleState({
    player: TEAM_ROSTER_ALIASES[testCase.playerRoster] ?? TEAM_ROSTERS[testCase.player],
    opponent: TEAM_ROSTER_ALIASES[testCase.opponentRoster] ?? TEAM_ROSTERS[testCase.opponent],
    seed: testCase.seed,
    encounterKind: testCase.kind ?? "",
    acePassive: testCase.acePassive ?? null,
  });
  const initial = structuredClone(state);
  const steps = [];
  for (const [index, [action, itemId, switchSlot]] of testCase.steps.entries()) {
    const key = `${testCase.name}-key-${index}`;
    // Forced switch sesudah KO menuntut aksi switch; ikuti supaya jalur itu
    // ikut terekam alih-alih berhenti di FORCED_SWITCH_REQUIRED.
    let effectiveAction = action;
    let effectiveSlot = switchSlot ?? null;
    if (state.player.forced_switch) {
      effectiveAction = "switch";
      effectiveSlot = state.player.roster.findIndex(
        (fighter) => fighter.hp > 0 && fighter.slot !== state.player.active_slot,
      );
      if (effectiveSlot < 0) break;
    }
    let outcome;
    try {
      outcome = resolveTeamTurn(state, effectiveAction, key, itemId ?? "", effectiveSlot);
    } catch (error) {
      steps.push({
        action: effectiveAction,
        item_id: itemId ?? "",
        switch_to_slot: effectiveSlot,
        key,
        error: error.code ?? String(error.message),
      });
      break;
    }
    steps.push({
      action: effectiveAction,
      item_id: itemId ?? "",
      switch_to_slot: effectiveSlot,
      key,
      error: "",
      state: outcome.state,
      events: outcome.events,
      bot_action: outcome.bot_action,
    });
    state = outcome.state;
    if (state.status !== "active") break;
  }
  return { name: testCase.name, initial, steps };
}

function scalarVectors() {
  const levels = [1, 2, 8, 15, 16, 17, 35, 36, 40, 99];
  return {
    rules_version: RULES_VERSION,
    to_battle_stats: levels.map((level) => ({
      level,
      base_stats: FIGHTERS.balanced.base_stats,
      stats: toBattleStats(FIGHTERS.balanced.base_stats, 1, "", level),
    })),
    care_multiplier: [
      [100, 100], [39, 100], [100, 49], [0, 0], [39, 49], [20, 25], [null, null],
    ].map(([hunger, hygiene]) => ({
      hunger,
      hygiene,
      value: careCombatMultiplier(hunger, hygiene),
    })),
    crit_chance: [0, 4, 8, 100, 400, 999].map((spd) => ({ spd, value: critChance(spd) })),
    exp_yield: [
      [1, 1, "even"], [1, 11, "even"], [40, 40, "tough"], [1, 40, "boss"], [20, 5, "favorable"],
    ].map(([recipient, opponent, difficulty]) => ({
      recipient,
      opponent,
      difficulty,
      value: battleExpYield(recipient, opponent, difficulty),
    })),
    element_normalize: [
      "metal", "METAL", " metal ", "water", "tech", "", "unknown", null,
    ].map((value) => ({
      input: value,
      with_stone: normalizeElement(value),
      with_empty: normalizeElement(value, ""),
    })),
    element_matchup: [
      ["metal", "plant", null], ["plant", "metal", null], ["metal", "metal", null],
      ["spark", "stone", "metal"], ["metal", "plant", "spark"], ["flow", "spark", "paper"],
      ["air", "stone", ""], ["sound", "glass", "ceramic"],
    ].map(([attacker, primary, secondary]) => ({
      attacker,
      primary,
      secondary,
      value: dualDefenderMultiplier(attacker, primary, secondary),
    })),
    // Input ikut dikirim supaya test Godot tidak perlu menyalin tabel ini.
    fighter_inputs: FIGHTERS,
    fighters: Object.fromEntries(
      Object.entries(FIGHTERS).map(([key, input]) => [key, createFighter(input)]),
    ),
  };
}

const vectors = {
  generated_by: "backend/tools/emit_sim_vectors.mjs",
  rules_version: RULES_VERSION,
  catalog: CATALOG_ITEMS.map((item) => ({ ...item })),
  rng: rngVectors(),
  scalars: scalarVectors(),
  duel: [
    ...DUEL_CASES.map((testCase) => runDuel(testCase, RULES_VERSION)),
    runDuel(DUEL_CASES[0], 1),
    runDuel(DUEL_CASES[2], 1),
    runDuel(DUEL_CASES.find((item) => item.name === "legacy-no-effects"), 2),
  ],
  team: TEAM_CASES.map(runTeam),
};

const outIdx = process.argv.indexOf("--out");
const outPath = outIdx > -1 && process.argv[outIdx + 1]
  ? process.argv[outIdx + 1]
  : "/tmp/scanima_sim_vectors.json";
await writeFile(outPath, JSON.stringify(vectors, null, 1));

const duelSteps = vectors.duel.reduce((sum, item) => sum + item.steps.length, 0);
const teamSteps = vectors.team.reduce((sum, item) => sum + item.steps.length, 0);
console.log(
  `vektor sim ditulis ke ${outPath} `
  + `(${vectors.rng.length} rng, ${vectors.duel.length} duel/${duelSteps} turn, `
  + `${vectors.team.length} team/${teamSteps} turn)`,
);
