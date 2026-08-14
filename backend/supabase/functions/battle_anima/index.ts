// POST /battle_anima
//
// Body: { operation: status|start|resume|turn|forfeit, ... }
// Combat runs in battle.mjs. Postgres alone commits turn order and rewards.

import { adminClient, json, syncProfileTimezone } from "../_shared/supa.ts";
import {
  BATTLE_ACTIONS,
  baseStatTotal,
  battleRewardPreview,
  createBattleState,
  levelFromExp,
  normalizeBaseStats,
  normalizeElement,
  resolveTurn,
} from "../_shared/battle.mjs";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACTIONS = new Set(BATTLE_ACTIONS);
const ERROR_STATUS: Record<string, number> = {
  INVALID_ANIMA_ID: 400,
  INVALID_SESSION_ID: 400,
  INVALID_EXPECTED_TURN: 400,
  INVALID_EXPECTED_VERSION: 400,
  INVALID_ACTION: 400,
  INVALID_BATTLE_STATE: 400,
  INVALID_EVENTS: 400,
  INVALID_IDEMPOTENCY_KEY: 400,
  INVALID_SEED: 400,
  SNAPSHOT_MISMATCH: 400,
  IDEMPOTENCY_CONFLICT: 409,
  STALE_BATTLE: 409,
  BATTLE_FINISHED: 409,
  BATTLE_EXPIRED: 409,
  ANIMA_NOT_READY: 409,
  ANIMA_SLEEPING: 409,
  ANIMA_DORMANT: 409,
  ANIMA_LOW_ENERGY: 409,
  ANIMA_HUNGRY: 409,
  NO_MOMENTUM: 409,
  NO_ITEM: 409,
  INVALID_ITEM: 400,
  ITEM_ALREADY_USED: 409,
  NO_BATTLE_OPPONENT: 409,
  ANIMA_NOT_FOUND: 404,
  BOT_NOT_FOUND: 404,
  BATTLE_NOT_FOUND: 404,
  NO_PROFILE: 404,
};

type BattleBody = {
  operation?: unknown;
  anima_id?: unknown;
  session_id?: unknown;
  action?: unknown;
  item_id?: unknown;
  expected_turn?: unknown;
  expected_version?: unknown;
  idempotency_key?: unknown;
  timezone_offset_minutes?: unknown;
};

type AnimaRow = {
  id: string;
  owner_id: string;
  nickname: string;
  species_key: string;
  color_bucket: string;
  stage: number;
  element: string;
  base_stats: Record<string, number>;
  care_score?: number;
  strike_name?: string;
  surge_name?: string;
};

type ArtRow = {
  species_key: string;
  color_bucket: string;
  stage: number;
  sheet_path: string;
  manifest: unknown;
};

const ANIMA_BATTLE_FIELDS =
  "id, owner_id, nickname, species_key, color_bucket, stage, element, base_stats, care_score, strike_name, surge_name";

const db = adminClient();

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await db.auth.getClaims(token);
  const ownerId = auth?.claims?.sub;
  if (authError || typeof ownerId !== "string") return json(401, { error: "token tidak sah" });

  let body: BattleBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const operation = typeof body.operation === "string" ? body.operation : "";
  await syncProfileTimezone(db, ownerId, body.timezone_offset_minutes);
  try {
    if (operation === "status") return await battleStatus(ownerId, body);
    if (operation === "start") return await startBattle(ownerId, body);
    if (operation === "resume") return await resumeBattle(ownerId, body);
    if (operation === "turn") return await playTurn(ownerId, body);
    if (operation === "forfeit") return await forfeitBattle(ownerId, body);
    return json(400, { error: "operation tidak dikenal" });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : String(error);
    const marker = Object.keys(ERROR_STATUS).find((candidate) => message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("battle_anima gagal", error);
    return json(500, { error: "battle gagal diproses" });
  }
});

async function battleStatus(ownerId: string, body: BattleBody): Promise<Response> {
  const sessionId = body.session_id === undefined || body.session_id === null
    ? null
    : asUuid(body.session_id, "session_id");
  const { data, error } = await db.rpc("battle_daily_reward_status", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return json(200, data);
}

async function startBattle(ownerId: string, body: BattleBody): Promise<Response> {
  const animaId = asUuid(body.anima_id, "anima_id");

  const { data: existing, error: resumeError } = await db.rpc("resume_battle", {
    p_owner: ownerId,
    p_session_id: null,
  });
  if (resumeError) throw resumeError;
  if (existing) return json(200, existing);

  const [{ data: player, error: playerError }, { data: candidates, error: candidateError }, { data: artRows }] =
    await Promise.all([
      db
        .from("animas")
        .select(ANIMA_BATTLE_FIELDS)
        .eq("id", animaId)
        .eq("owner_id", ownerId)
        .maybeSingle(),
      db
        .from("animas")
        .select(ANIMA_BATTLE_FIELDS)
        .neq("owner_id", ownerId)
        .eq("status", "ready")
        .limit(200),
      db.from("species_library").select("species_key, color_bucket, stage, sheet_path, manifest").limit(1000),
    ]);
  if (playerError) throw playerError;
  if (!player) throw new Error("ANIMA_NOT_FOUND");
  if (candidateError) throw candidateError;

  const artByKey = new Map(
    ((artRows ?? []) as ArtRow[]).map((art) => [artKey(art), art]),
  );
  const eligible = ((candidates ?? []) as AnimaRow[]).filter((candidate) =>
    artByKey.has(artKey(candidate))
  );
  if (eligible.length === 0) throw new Error("NO_BATTLE_OPPONENT");

  const seed = crypto.randomUUID();
  const playerTotal = baseStatTotal(player.base_stats);
  const close = eligible.filter((candidate) =>
    candidate.stage === player.stage &&
    Math.abs(baseStatTotal(candidate.base_stats) - playerTotal) <= playerTotal * 0.15
  );
  const pool = close.length > 0 ? close : eligible;
  pool.sort((left, right) => stableRank(`${seed}:${left.id}`) - stableRank(`${seed}:${right.id}`));
  const bot = pool[0];
  const botBaseStats = close.length > 0
    ? normalizeBaseStats(bot.base_stats)
    : normalizeBaseStats(bot.base_stats, playerTotal);
  const playerSnapshot = snapshot(player as AnimaRow, artByKey.get(artKey(player)) ?? null, true);
  const botSnapshot = snapshot(
    { ...bot, base_stats: botBaseStats },
    artByKey.get(artKey(bot)) ?? null,
    false,
  );
  const initialState = createBattleState({
    player: playerSnapshot,
    bot: botSnapshot,
    seed,
  });
  const reward = battleRewardPreview(playerSnapshot, botSnapshot, seed);

  const { data, error } = await db.rpc("start_battle", {
    p_owner: ownerId,
    p_player_anima_id: animaId,
    p_bot_anima_id: bot.id,
    p_player_snapshot: playerSnapshot,
    p_bot_snapshot: botSnapshot,
    p_initial_state: initialState,
    p_seed: seed,
    p_reward_tier: reward.tier,
    p_reward_roll: reward.roll,
    p_reward_bits: reward.bits,
  });
  if (error) throw error;
  return json(200, data);
}

async function resumeBattle(ownerId: string, body: BattleBody): Promise<Response> {
  const sessionId = body.session_id === undefined || body.session_id === null
    ? null
    : asUuid(body.session_id, "session_id");
  const { data, error } = await db.rpc("resume_battle", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  if (!data) throw new Error("BATTLE_NOT_FOUND");
  return json(200, data);
}

async function playTurn(ownerId: string, body: BattleBody): Promise<Response> {
  const sessionId = asUuid(body.session_id, "session_id");
  const action = typeof body.action === "string" ? body.action : "";
  const itemId = typeof body.item_id === "string" ? body.item_id : "";
  const key = typeof body.idempotency_key === "string" ? body.idempotency_key : "";
  const expectedTurn = asPositiveInt(body.expected_turn, "expected_turn");
  const expectedVersion = asPositiveInt(body.expected_version, "expected_version");
  if (!ACTIONS.has(action)) throw new Error("INVALID_ACTION");
  if (action === "item" && !itemId) throw new Error("INVALID_ITEM");
  if (!key || key.length > 128) throw new Error("INVALID_IDEMPOTENCY_KEY");

  const { data: session, error: resumeError } = await db.rpc("resume_battle", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (resumeError) throw resumeError;
  if (!session) throw new Error("BATTLE_NOT_FOUND");

  const { data: prior, error: priorError } = await db
    .from("battle_turns")
    .select("turn_number, action, catalog_item_id, response")
    .eq("session_id", sessionId)
    .eq("idempotency_key", key)
    .maybeSingle();
  if (priorError) throw priorError;
  if (prior) {
    if (
      prior.turn_number !== expectedTurn ||
      prior.action !== action ||
      (prior.catalog_item_id ?? "") !== (action === "item" ? itemId : "")
    ) {
      throw new Error("IDEMPOTENCY_CONFLICT");
    }
    return json(200, { ...prior.response, replayed: true });
  }
  if (session.status !== "active") throw new Error("BATTLE_FINISHED");

  const result = resolveTurn(session.state, action, key, itemId);
  const payload: Record<string, unknown> = {
    p_owner: ownerId,
    p_session_id: sessionId,
    p_expected_turn: expectedTurn,
    p_expected_version: expectedVersion,
    p_key: key,
    p_action: action,
    p_state: result.state,
    p_events: result.events,
    p_bot_action: result.bot_action,
  };
  if (action === "item") payload.p_item_id = itemId;
  const { data, error } = await db.rpc("commit_battle_turn", payload);
  if (error) throw error;
  return json(200, data);
}

async function forfeitBattle(ownerId: string, body: BattleBody): Promise<Response> {
  const sessionId = asUuid(body.session_id, "session_id");
  const { data, error } = await db.rpc("forfeit_battle", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return json(200, data);
}

function snapshot(row: AnimaRow, art: ArtRow | null, includeName: boolean): Record<string, unknown> {
  const result: Record<string, unknown> = {
    anima_id: row.id,
    species_key: row.species_key,
    color_bucket: row.color_bucket,
    stage: row.stage,
    level: levelFromExp(row.care_score),
    element: normalizeElement(row.element),
    base_stats: normalizeBaseStats(row.base_stats),
    sheet_path: art?.sheet_path ?? "",
    manifest: art?.manifest ?? {},
    strike_name: row.strike_name ?? "",
    surge_name: row.surge_name ?? "",
  };
  if (includeName) result.name = row.nickname;
  return result;
}

function artKey(row: Pick<AnimaRow, "species_key" | "color_bucket" | "stage">): string {
  return `${row.species_key}:${row.color_bucket}:${row.stage}`;
}

function asUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) throw new Error(`INVALID_${field.toUpperCase()}`);
  return value;
}

function asPositiveInt(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function stableRank(value: string): number {
  let hash = 2166136261;
  for (const char of value) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}
