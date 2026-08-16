import { seededRandom } from "./battle.mjs";

export const EXPEDITION_SCHEMA_VERSION = 1;
export const EXPEDITION_SHOP_SKIP_OPTION_ID = "shop-skip";
export const EXPEDITION_CHECKPOINT_RECOVER_RATIO = 0.5;
export const EXPEDITION_CHECKPOINT_POWER_VALUE = 0.1;
export const EXPEDITION_NODE_KINDS = Object.freeze([
  "battle",
  "elite",
  "recovery",
  "cache",
  "shop",
  "mystery",
  "boss",
]);
export const EXPEDITION_EFFECT_TYPES = Object.freeze([
  "heal_party",
  "heal_target",
  "revive_target",
  "supplies",
  "stat_boost",
  "start_pp",
  "shop_discount",
]);
export const BOSS_SEEKER_TRIGGERS = Object.freeze([
  "chapter_intro",
  "boss_intro",
  "rematch",
  "first_attack",
  "first_special",
  "first_switch",
  "last_anima",
  "victory",
  "defeat",
]);
export const BOSS_SEEKER_POSES = Object.freeze([
  "intro_idle",
  "attack_command",
  "special_command",
  "switch_command",
  "concern_hit",
  "last_anima",
  "victory",
  "defeat",
  "profile",
]);

const NODE_KIND_SET = new Set(EXPEDITION_NODE_KINDS);
const EFFECT_SET = new Set(EXPEDITION_EFFECT_TYPES);
const STAT_SET = new Set(["max_hp", "atk", "def", "spd", "special"]);
const DEPTH_KINDS = Object.freeze([
  ["battle", "mystery"],
  ["battle", "recovery", "cache"],
  ["battle", "elite", "shop"],
  ["battle", "elite", "recovery", "cache"],
]);

export function validateChapterManifest(input) {
  if (!isObject(input) || Number(input.schema_version) !== EXPEDITION_SCHEMA_VERSION) {
    throw chapterError("UNSUPPORTED_CHAPTER_SCHEMA");
  }
  if (!Array.isArray(input.zones) || input.zones.length !== 3) {
    throw chapterError("INVALID_CHAPTER_ZONES");
  }
  if (!Array.isArray(input.opponents) || input.opponents.length < 4) {
    throw chapterError("INVALID_CHAPTER_OPPONENTS");
  }
  const opponentIds = new Set();
  for (const opponent of input.opponents) {
    if (!isObject(opponent) || !validId(opponent.id) || opponentIds.has(opponent.id)) {
      throw chapterError("INVALID_CHAPTER_OPPONENTS");
    }
    if (!Array.isArray(opponent.roster) || opponent.roster.length < 1 || opponent.roster.length > 4) {
      throw chapterError("INVALID_CHAPTER_OPPONENTS");
    }
    opponentIds.add(opponent.id);
  }
  input.zones.forEach((zone, index) => validateZone(zone, index + 1, opponentIds));
  if (
    !isObject(input.boss) ||
    !validId(input.boss.opponent_id) ||
    !opponentIds.has(input.boss.opponent_id)
  ) {
    throw chapterError("INVALID_CHAPTER_BOSS");
  }
  return structuredClone(input);
}

export function publicBossSeeker(manifestInput) {
  const seeker = isObject(manifestInput) && isObject(manifestInput.boss_seeker)
    ? manifestInput.boss_seeker
    : null;
  if (!seeker || !isObject(seeker.dialogue)) return null;
  const sheetPath = typeof seeker.sheet_path === "string" ? seeker.sheet_path.trim() : "";
  if (!sheetPath || sheetPath.includes("..")) return null;
  const dialogue = {};
  for (const trigger of BOSS_SEEKER_TRIGGERS) {
    const line = typeof seeker.dialogue[trigger] === "string"
      ? seeker.dialogue[trigger].trim()
      : "";
    if (line) dialogue[trigger] = line;
  }
  if (Object.keys(dialogue).length === 0) return null;
  const poses = Array.isArray(seeker.poses)
    ? seeker.poses.filter((pose) => BOSS_SEEKER_POSES.includes(pose))
    : [...BOSS_SEEKER_POSES];
  return {
    id: typeof seeker.id === "string" ? seeker.id : "",
    display_name: typeof seeker.display_name === "string" ? seeker.display_name : "",
    title_key: typeof seeker.title_key === "string" ? seeker.title_key : "",
    body_height_cm: Math.min(2000, Math.max(20, Math.trunc(Number(seeker.body_height_cm) || 170))),
    portrait_pose: typeof seeker.portrait_pose === "string" ? seeker.portrait_pose : "profile",
    dialogue,
    poses,
    sheet_path: sheetPath,
    manifest: isObject(seeker.manifest) ? seeker.manifest : {},
  };
}

export function attachBossSeeker(payload, manifestInput) {
  const seeker = publicBossSeeker(manifestInput);
  if (!seeker || !isObject(payload)) return payload;
  const next = { ...payload };
  if (isObject(next.run)) {
    next.run = { ...next.run, boss_seeker: seeker };
  }
  if (isObject(next.encounter)) {
    const zoneAttempt = Number(next.run?.zone_attempt) || Number(next.encounter.zone_attempt) || 1;
    next.encounter = {
      ...next.encounter,
      boss_seeker: seeker,
      zone_attempt: zoneAttempt,
    };
  }
  return next;
}

export function generateZoneMap(manifestInput, zoneNumber, attempt, seed) {
  const manifest = validateChapterManifest(manifestInput);
  const zoneIndex = Number(zoneNumber) - 1;
  if (!Number.isInteger(zoneIndex) || zoneIndex < 0 || zoneIndex >= 3) {
    throw chapterError("INVALID_EXPEDITION_ZONE");
  }
  const zone = manifest.zones[zoneIndex];
  const random = seededRandom(`${seed}:zone:${zoneNumber}:attempt:${attempt}`);
  const nodes = [];
  const layers = [];
  for (let depth = 0; depth < 4; depth += 1) {
    const layer = [];
    const kindChoices = DEPTH_KINDS[depth].filter((kind) => zone.node_pools[kind]?.length);
    if (kindChoices.length === 0) throw chapterError("INVALID_CHAPTER_NODE_POOL");
    for (let lane = 0; lane < 2; lane += 1) {
      const kind = kindChoices[Math.floor(random() * kindChoices.length)];
      const pool = zone.node_pools[kind];
      const template = structuredClone(pool[Math.floor(random() * pool.length)]);
      const id = `z${zoneNumber}-a${attempt}-d${depth + 1}-${lane + 1}`;
      const node = {
        ...template,
        id,
        kind,
        depth: depth + 1,
        next: [],
      };
      nodes.push(node);
      layer.push(id);
    }
    layers.push(layer);
  }
  for (let depth = 0; depth < layers.length - 1; depth += 1) {
    const next = layers[depth + 1];
    for (let lane = 0; lane < layers[depth].length; lane += 1) {
      const node = nodes.find((candidate) => candidate.id === layers[depth][lane]);
      node.next = random() < 0.5
        ? [...next]
        : [next[lane % next.length]];
    }
    for (const destination of next) {
      if (!layers[depth].some((source) => {
        const node = nodes.find((candidate) => candidate.id === source);
        return node.next.includes(destination);
      })) {
        const source = nodes.find((candidate) => candidate.id === layers[depth][0]);
        source.next.push(destination);
      }
    }
  }
  if (zoneNumber === 3) {
    const bossId = `z3-a${attempt}-boss`;
    nodes.push({
      id: bossId,
      kind: "boss",
      depth: 5,
      opponent_id: manifest.boss.opponent_id,
      supplies_reward: boundedInteger(manifest.boss.supplies_reward, 0, 999, 8),
      title_key: String(manifest.boss.title_key ?? "EXPEDITION_BOSS"),
      next: [],
    });
    for (const id of layers[3]) {
      nodes.find((candidate) => candidate.id === id).next = [bossId];
    }
  }
  return {
    schema_version: EXPEDITION_SCHEMA_VERSION,
    zone: zoneNumber,
    attempt,
    seed: String(seed),
    entry: layers[0],
    nodes,
    ...(typeof zone.background_path === "string" && zone.background_path
      && !zone.background_path.includes("..")
      ? { background_path: zone.background_path }
      : {}),
  };
}

export function findExpeditionNode(map, nodeId) {
  if (!isObject(map) || !Array.isArray(map.nodes)) return null;
  return map.nodes.find((node) => isObject(node) && node.id === nodeId) ?? null;
}

export function nextNodeIds(map, nodeId) {
  const node = findExpeditionNode(map, nodeId);
  return Array.isArray(node?.next) ? node.next.map(String) : [];
}

export function opponentForNode(manifestInput, node) {
  const manifest = validateChapterManifest(manifestInput);
  if (!isObject(node) || !["battle", "elite", "boss"].includes(node.kind)) {
    throw chapterError("INVALID_EXPEDITION_NODE");
  }
  const opponent = manifest.opponents.find((candidate) => candidate.id === node.opponent_id);
  if (!opponent) throw chapterError("EXPEDITION_OPPONENT_NOT_FOUND");
  return structuredClone(opponent);
}

export function prepareExpeditionZoneRoster(
  roster,
  partyState = [],
  boosts = [],
  checkpointChoice = null,
) {
  const hpOverlay = (Array.isArray(partyState) ? partyState : [])
    .filter(isObject)
    .map((member) => {
      const currentHp = member.hp ?? member.current_hp;
      return {
        anima_id: String(member.anima_id ?? ""),
        ...(currentHp == null ? {} : { hp: currentHp, current_hp: currentHp }),
        ...(member.max_hp == null ? {} : { max_hp: member.max_hp }),
      };
    });
  // ponytail: one global checkpoint tune is enough for the live chapter.
  // Move this into manifest policy only when two chapters need different values.
  const zoneBoosts = checkpointChoice === "power_up"
    ? ["atk", "def", "spd"].map((stat) => ({
      type: "stat_boost",
      stat,
      value: EXPEDITION_CHECKPOINT_POWER_VALUE,
    }))
    : [];
  return prepareExpeditionRoster(roster, hpOverlay, [
    ...(Array.isArray(boosts) ? boosts : []),
    ...zoneBoosts,
  ]);
}

export function prepareExpeditionRoster(roster, partyState = [], boosts = []) {
  if (!Array.isArray(roster) || roster.length !== 4) {
    throw chapterError("TEAM_REQUIRES_FOUR");
  }
  const savedById = new Map(
    (Array.isArray(partyState) ? partyState : [])
      .filter(isObject)
      .map((member) => [String(member.anima_id ?? ""), member]),
  );
  return roster.map((source) => {
    const saved = savedById.get(String(source?.anima_id ?? ""));
    const member = {
      ...structuredClone(source),
      sheet_path: source.sheet_path,
      sheet_url: source.sheet_url,
      manifest: source.manifest,
      name: source.name,
    };
    // Keep live Level/care from the team row. party_state only carries HP and
    // already-applied zone boosts; spreading it froze growth until the next zone.
    const useSavedBoosts = saved?.boosts_applied === true && isObject(saved.base_stats);
    const baseStats = {
      ...(useSavedBoosts
        ? saved.base_stats
        : (isObject(member.base_stats) ? member.base_stats : {})),
    };
    if (!useSavedBoosts) {
      for (const boost of Array.isArray(boosts) ? boosts : []) {
        if (!isObject(boost) || boost.type !== "stat_boost" || !STAT_SET.has(boost.stat)) continue;
        const key = boost.stat === "max_hp" ? "hp" : boost.stat;
        const current = Number(baseStats[key]) || 1;
        baseStats[key] = Math.max(1, Math.round(current * (1 + boundedNumber(boost.value, 0, 2, 0))));
      }
    }
    member.boosts_applied = true;
    member.base_stats = baseStats;
    const baseHp = Math.max(1, Number(baseStats.hp) || 1);
    const savedMax = Number(saved?.max_hp);
    const rawSavedHp = saved?.hp ?? saved?.current_hp;
    const savedHp = Number(rawSavedHp);
    const hasSavedHp = rawSavedHp != null && Number.isFinite(savedHp);
    const hasBattleMax = Number.isFinite(savedMax) && savedMax > baseHp;
    // startZone used to persist base_stats.hp as current_hp while max_hp was
    // already grown battle HP. That is an uninitialized stamp, not damage.
    if (hasBattleMax && savedHp === baseHp) {
      delete member.hp;
      delete member.current_hp;
      delete member.max_hp;
    } else if (hasSavedHp) {
      if (hasBattleMax) member.max_hp = savedMax;
      else delete member.max_hp;
      member.hp = Math.max(0, Math.trunc(savedHp));
      member.current_hp = member.hp;
    } else {
      delete member.hp;
      delete member.current_hp;
      delete member.max_hp;
    }
    return member;
  });
}

export function applyNodeOption({
  partyState,
  supplies,
  boosts,
  node,
  optionId,
  targetSlot = null,
}) {
  if (!isObject(node) || !Array.isArray(node.options)) {
    throw chapterError("INVALID_EXPEDITION_CHOICE");
  }
  if (node.kind === "shop" && optionId === EXPEDITION_SHOP_SKIP_OPTION_ID) {
    return {
      party_state: structuredClone(partyState),
      supplies: boundedInteger(supplies, 0, 999999, 0),
      boosts: structuredClone(Array.isArray(boosts) ? boosts : []).slice(0, 20),
      option: { id: EXPEDITION_SHOP_SKIP_OPTION_ID, skipped: true },
    };
  }
  const option = node.options.find((candidate) => isObject(candidate) && candidate.id === optionId);
  if (!option || !isObject(option.effect)) throw chapterError("INVALID_EXPEDITION_CHOICE");
  const discount = (Array.isArray(boosts) ? boosts : [])
    .filter((boost) => isObject(boost) && boost.type === "shop_discount")
    .reduce((sum, boost) => sum + boundedNumber(boost.value, 0, 0.75, 0), 0);
  const baseCost = boundedInteger(option.cost_supplies, 0, 999, 0);
  const cost = Math.max(0, Math.ceil(baseCost * (1 - Math.min(0.75, discount))));
  let nextSupplies = boundedInteger(supplies, 0, 999999, 0);
  if (nextSupplies < cost) throw chapterError("NO_SUPPLIES");
  nextSupplies -= cost;
  const nextParty = structuredClone(partyState);
  const nextBoosts = structuredClone(Array.isArray(boosts) ? boosts : []);
  applyEffect(option.effect, nextParty, nextBoosts, targetSlot, (delta) => {
    nextSupplies = Math.max(0, nextSupplies + delta);
  });
  return {
    party_state: nextParty,
    supplies: nextSupplies,
    boosts: nextBoosts.slice(0, 20),
    option: structuredClone(option),
  };
}

export function applyEncounterBoosts(stateInput, boosts = []) {
  const state = structuredClone(stateInput);
  const fighters = state?.player?.roster;
  if (!Array.isArray(fighters) || fighters.length !== 4) {
    throw chapterError("INVALID_EXPEDITION_STATE");
  }
  const extraPp = Math.min(
    2,
    (Array.isArray(boosts) ? boosts : [])
      .filter((boost) => isObject(boost) && boost.type === "start_pp")
      .reduce((sum, boost) => sum + boundedInteger(boost.value, 0, 2, 1), 0),
  );
  if (extraPp > 0) {
    for (const fighter of fighters) {
      fighter.momentum_max = Math.min(5, Number(fighter.momentum_max ?? 3) + extraPp);
      fighter.momentum = fighter.momentum_max;
    }
  }
  return state;
}

function validateZone(zone, zoneNumber, opponentIds) {
  if (!isObject(zone) || !isObject(zone.node_pools)) {
    throw chapterError("INVALID_CHAPTER_ZONES");
  }
  if (
    zone.bits_reward !== undefined
    && (
      typeof zone.bits_reward !== "number"
      || !Number.isInteger(zone.bits_reward)
      || zone.bits_reward < 0
      || zone.bits_reward > 200
    )
  ) {
    throw chapterError("INVALID_CHAPTER_ZONE_BITS");
  }
  for (const kind of EXPEDITION_NODE_KINDS) {
    if (kind === "boss") continue;
    const pool = zone.node_pools[kind];
    if (!Array.isArray(pool) || pool.length < 1 || pool.length > 20) {
      throw chapterError("INVALID_CHAPTER_NODE_POOL");
    }
    for (const template of pool) validateNodeTemplate(template, kind, zoneNumber, opponentIds);
  }
}

function validateNodeTemplate(template, kind, zoneNumber, opponentIds) {
  if (!isObject(template)) throw chapterError("INVALID_CHAPTER_NODE_POOL");
  if (["battle", "elite"].includes(kind)) {
    if (!opponentIds.has(template.opponent_id)) throw chapterError("INVALID_CHAPTER_OPPONENTS");
    return;
  }
  if (!Array.isArray(template.options) || template.options.length < 1 || template.options.length > 3) {
    throw chapterError("INVALID_CHAPTER_OPTIONS");
  }
  const optionIds = new Set();
  for (const option of template.options) {
    if (
      !isObject(option)
      || !validId(option.id)
      || option.id === EXPEDITION_SHOP_SKIP_OPTION_ID
      || optionIds.has(option.id)
    ) {
      throw chapterError("INVALID_CHAPTER_OPTIONS");
    }
    optionIds.add(option.id);
    validateEffect(option.effect, zoneNumber);
  }
}

function validateEffect(effect, zoneNumber) {
  if (!isObject(effect) || !EFFECT_SET.has(effect.type)) {
    throw chapterError("UNSUPPORTED_CHAPTER_EFFECT");
  }
  if (effect.type === "stat_boost" && !STAT_SET.has(effect.stat)) {
    throw chapterError("UNSUPPORTED_CHAPTER_EFFECT");
  }
  if (effect.type === "supplies" && boundedInteger(effect.value, -999, 999, 0) < 0) {
    throw chapterError("INVALID_CHAPTER_OPTIONS");
  }
  if (zoneNumber < 1 || zoneNumber > 3) throw chapterError("INVALID_CHAPTER_ZONES");
}

function applyEffect(effect, party, boosts, targetSlot, addSupplies) {
  validateEffect(effect, 1);
  if (effect.type === "supplies") {
    addSupplies(boundedInteger(effect.value, 0, 999, 0));
    return;
  }
  if (effect.type === "stat_boost") {
    if (!Array.isArray(party) || party.length !== 4) {
      throw chapterError("INVALID_EXPEDITION_STATE");
    }
    for (const member of party) {
      if (!isObject(member) || !isObject(member.base_stats)) {
        throw chapterError("INVALID_EXPEDITION_STATE");
      }
      const key = effect.stat === "max_hp" ? "hp" : effect.stat;
      const current = Number(member.base_stats[key]) || 1;
      const boosted = Math.max(
        1,
        Math.round(current * (1 + boundedNumber(effect.value, 0, 2, 0))),
      );
      member.base_stats[key] = boosted;
      if (key === "hp") {
        const oldMaximum = Math.max(1, Number(member.max_hp) || current);
        const oldHp = Math.max(0, Number(member.hp ?? member.current_hp) || 0);
        member.max_hp = boosted;
        member.hp = Math.min(boosted, oldHp + boosted - oldMaximum);
        member.current_hp = member.hp;
      }
    }
    boosts.push(structuredClone(effect));
    return;
  }
  if (["start_pp", "shop_discount"].includes(effect.type)) {
    boosts.push(structuredClone(effect));
    return;
  }
  if (!Array.isArray(party) || party.length !== 4) {
    throw chapterError("INVALID_EXPEDITION_STATE");
  }
  if (effect.type === "heal_party") {
    for (const member of party) healMember(member, effect, false);
    return;
  }
  if (!Number.isInteger(targetSlot) || targetSlot < 0 || targetSlot >= party.length) {
    throw chapterError("INVALID_TARGET_SLOT");
  }
  healMember(party[targetSlot], effect, effect.type === "revive_target");
}

function healMember(member, effect, revive) {
  if (!isObject(member)) throw chapterError("INVALID_EXPEDITION_STATE");
  const maximum = Math.max(1, Number(member.max_hp) || 1);
  const current = Math.max(0, Number(member.hp) || 0);
  if (revive && current > 0) throw chapterError("INVALID_TARGET_SLOT");
  if (!revive && current <= 0) return;
  const amount = Math.max(
    1,
    boundedInteger(effect.value, 0, 999999, 0) ||
      Math.round(maximum * boundedNumber(effect.ratio, 0, 1, 0.25)),
  );
  member.hp = Math.min(maximum, (revive ? 0 : current) + amount);
  member.current_hp = member.hp;
}

function boundedInteger(value, minimum, maximum, fallback) {
  const number = Number(value);
  return Number.isInteger(number)
    ? Math.max(minimum, Math.min(maximum, number))
    : fallback;
}

function boundedNumber(value, minimum, maximum, fallback) {
  const number = Number(value);
  return Number.isFinite(number)
    ? Math.max(minimum, Math.min(maximum, number))
    : fallback;
}

function validId(value) {
  return typeof value === "string" && /^[a-z0-9][a-z0-9_-]{1,47}$/.test(value);
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function chapterError(message) {
  const error = new Error(message);
  error.code = message;
  return error;
}
