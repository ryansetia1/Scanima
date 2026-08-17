// POST /battle_anima
//
// Body: { operation: status|start|resume|turn|forfeit, ... }
// Combat runs in battle.mjs. Postgres alone commits turn order and rewards.

import { adminClient, clientVersionGate, json, syncProfileTimezone } from "../_shared/supa.ts";
import { signSheetUrl } from "../_shared/signed_roster.ts";
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
import { isFairRealOpponent, systemDuelBot } from "../_shared/duel_bot.mjs";

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
  secondary_element?: string | null;
  base_stats: Record<string, number>;
  body_height_cm?: number;
  care_score?: number;
  care?: { hunger?: number; hygiene?: number };
  strike_name?: string;
  surge_name?: string;
  sheet_path?: string;
  manifest?: unknown;
};

type ArtRow = {
  species_key: string;
  color_bucket: string;
  stage: number;
  sheet_path: string;
  manifest: unknown;
};

type GalleryBotRow = {
  id: string;
  anima_id: string;
  display_name: string;
  element: string;
  secondary_element?: string | null;
  stage: number;
  animas: AnimaRow & { sheet_path: string; manifest: unknown };
};

const SECONDARY_ELEMENT_FIELD = ", secondary_element";
const ANIMA_BATTLE_FIELDS =
  `id, owner_id, nickname, species_key, color_bucket, stage, element${SECONDARY_ELEMENT_FIELD}, base_stats, body_height_cm, care_score, care, strike_name, surge_name`;
const normalizeStats = normalizeBaseStats as unknown as (
  baseStats: unknown,
  targetTotal?: number | null,
) => Record<string, number>;

const db = adminClient();

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

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
  if (existing) return json(200, await withFreshBotArt(existing));

  const [{ data: player, error: playerError }, { data: galleryRows, error: galleryError }, { data: legacyBots, error: legacyError }, { data: artRows }] =
    await Promise.all([
      db
        .from("animas")
        .select(ANIMA_BATTLE_FIELDS + ", sheet_path, manifest")
        .eq("id", animaId)
        .eq("owner_id", ownerId)
        .maybeSingle(),
      db
        .from("gallery_entries")
        .select(
          "id, anima_id, display_name, element, secondary_element, stage, "
          + "animas!inner(" + ANIMA_BATTLE_FIELDS + ", sheet_path, manifest)",
        )
        .eq("published", true)
        .eq("moderation_status", "approved")
        .eq("auto_hidden", false)
        .neq("owner_id", ownerId)
        .limit(200),
      db
        .from("animas")
        .select(ANIMA_BATTLE_FIELDS + ", sheet_path, manifest")
        .neq("owner_id", ownerId)
        .eq("status", "ready")
        .limit(200),
      db.from("species_library").select("species_key, color_bucket, stage, sheet_path, manifest").limit(1000),
    ]);
  if (playerError) throw playerError;
  if (!player) throw new Error("ANIMA_NOT_FOUND");
  if (galleryError) throw galleryError;
  if (legacyError) throw legacyError;

  const playerRow = player as unknown as AnimaRow;
  const legacyCandidates = (legacyBots ?? []) as unknown as AnimaRow[];
  const artCandidates = (artRows ?? []) as unknown as ArtRow[];
  const artByKey = new Map(artCandidates.map((art) => [artKey(art), art]));
  const seed = crypto.randomUUID();
  const galleryCandidates = ((galleryRows ?? []) as unknown as GalleryBotRow[])
    .filter((row) => row.animas?.sheet_path && row.animas?.manifest);

  const playerArt = playerArtSource(playerRow, artCandidates);
  const playerSnapshot = snapshot(playerRow, playerArt, true);

  // Lawan sungguhan tetap diutamakan, tetapi hanya yang taksiran duelnya masih
  // seimbang. Pool ±15% total base stat saja tidak cukup: ia tidak melihat
  // Level, bentuk distribusi stat, maupun elemen, dan pada roster production
  // meloloskan duel 8% sekaligus duel 100%.
  let botSnapshot: Record<string, unknown> | null = null;
  let botAnimaId: string | null = null;

  const galleryPick = pickFairCandidate(
    seed,
    playerSnapshot,
    playerRow,
    galleryCandidates.map((entry) => ({ key: entry.id, animaId: entry.anima_id, row: entry.animas, entry })),
  );
  if (galleryPick) {
    try {
      botSnapshot = await gallerySnapshot(
        galleryPick.entry!,
        { ...galleryPick.row, base_stats: galleryPick.baseStats },
      );
      botAnimaId = galleryPick.animaId;
    } catch (error) {
      console.error("signed art bot Gallery gagal; mencoba legacy", error);
    }
  }

  if (!botSnapshot) {
    // ponytail: species_library hanya menandai bot legacy; bytes memakai salinan privat hasil migrasi.
    const legacyPick = pickFairCandidate(
      seed,
      playerSnapshot,
      playerRow,
      legacyCandidates
        .filter((row) => artByKey.has(artKey(row)) && row.sheet_path && row.manifest)
        .map((row) => ({ key: row.id, animaId: row.id, row })),
    );
    if (legacyPick) {
      botSnapshot = snapshot(
        { ...legacyPick.row, base_stats: legacyPick.baseStats },
        {
          species_key: legacyPick.row.species_key,
          color_bucket: legacyPick.row.color_bucket,
          stage: legacyPick.row.stage,
          sheet_path: legacyPick.row.sheet_path!,
          manifest: legacyPick.row.manifest,
        },
        false,
      );
      botAnimaId = legacyPick.animaId;
    }
  }

  if (!botSnapshot) {
    botSnapshot = systemDuelBot(playerSnapshot, seed) as Record<string, unknown>;
    botAnimaId = null;
  }

  const initialState = createBattleState({
    player: playerSnapshot,
    bot: botSnapshot,
    seed,
  });
  const reward = battleRewardPreview(playerSnapshot, botSnapshot, seed);

  const { data, error } = await db.rpc("start_battle", {
    p_owner: ownerId,
    p_player_anima_id: animaId,
    p_bot_anima_id: botAnimaId,
    p_player_snapshot: playerSnapshot,
    p_bot_snapshot: botSnapshot,
    p_initial_state: initialState,
    p_seed: seed,
    p_reward_tier: reward.tier,
    p_reward_roll: reward.roll,
    p_reward_bits: reward.bits,
  });
  if (error) throw error;
  return json(200, await withFreshBotArt(data));
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
  return json(200, await withFreshBotArt(data));
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

function snapshot(
  row: AnimaRow,
  art: ArtRow | null,
  includeName: boolean,
  displayName = "",
  sheetUrl = "",
): Record<string, unknown> {
  const result: Record<string, unknown> = {
    anima_id: row.id,
    species_key: row.species_key,
    color_bucket: row.color_bucket,
    stage: row.stage,
    level: levelFromExp(row.care_score),
    element: normalizeElement(row.element),
    base_stats: normalizeStats(row.base_stats),
    body_height_cm: Math.min(2000, Math.max(20, Math.trunc(Number(row.body_height_cm) || 120))),
    manifest: art?.manifest ?? {},
    strike_name: row.strike_name ?? "",
    surge_name: row.surge_name ?? "",
  };
  if (sheetUrl) {
    result.sheet_url = sheetUrl;
  } else {
    result.sheet_path = art?.sheet_path ?? "";
  }
  const secondary = readSecondaryElement(row);
  if (secondary) result.secondary_element = secondary;
  if (includeName) {
    result.name = row.nickname;
    result.hunger = Number(row.care?.hunger ?? 100);
    result.hygiene = Number(row.care?.hygiene ?? 100);
  } else if (displayName) {
    result.name = displayName;
  }
  return result;
}

async function gallerySnapshot(
  entry: GalleryBotRow,
  botRow: AnimaRow & { sheet_path: string; manifest: unknown },
): Promise<Record<string, unknown>> {
  const sheetUrl = await signSheetUrl(db, botRow.sheet_path);
  if (!sheetUrl) throw new Error("BOT_NOT_FOUND");
  return snapshot(
    botRow,
    {
      species_key: botRow.species_key,
      color_bucket: botRow.color_bucket,
      stage: botRow.stage,
      sheet_path: botRow.sheet_path,
      manifest: botRow.manifest,
    },
    false,
    entry.display_name,
    sheetUrl,
  );
}

async function withFreshBotArt(value: unknown): Promise<unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const session = value as Record<string, unknown>;
  const botSnapshot = session.bot_snapshot && typeof session.bot_snapshot === "object"
    ? { ...(session.bot_snapshot as Record<string, unknown>) }
    : {};
  // Lawan sistem tidak punya baris `animas`, dan art-nya digambar client dari
  // PlaceholderSheet. Menandatangani ulang di sini akan mencari UUID dari slug.
  if (botSnapshot.system_asset === "placeholder") return value;
  const botId = typeof session.bot_anima_id === "string"
    ? session.bot_anima_id
    : typeof botSnapshot.anima_id === "string"
    ? botSnapshot.anima_id
    : "";
  if (!botId) return value;

  const { data: bot, error: botError } = await db
    .from("animas")
    .select("sheet_path, manifest")
    .eq("id", botId)
    .maybeSingle();
  if (botError) throw botError;
  if (!bot?.sheet_path || !bot.manifest) throw new Error("BOT_NOT_FOUND");

  const sheetUrl = await signSheetUrl(db, bot.sheet_path);
  if (!sheetUrl) throw new Error("BOT_NOT_FOUND");

  delete botSnapshot.sheet_path;
  return {
    ...session,
    bot_snapshot: {
      ...botSnapshot,
      manifest: bot.manifest,
      sheet_url: sheetUrl,
    },
  };
}

function playerArtSource(
  row: AnimaRow & { sheet_path?: string; manifest?: unknown },
  artRows: ArtRow[],
): ArtRow | null {
  if (row.sheet_path && row.manifest) {
    return {
      species_key: row.species_key,
      color_bucket: row.color_bucket,
      stage: row.stage,
      sheet_path: row.sheet_path,
      manifest: row.manifest,
    };
  }
  const artByKey = new Map(artRows.map((art) => [artKey(art), art]));
  return artByKey.get(artKey(row)) ?? null;
}

type RealCandidate = {
  key: string;
  animaId: string;
  row: AnimaRow & { sheet_path?: string; manifest?: unknown };
  entry?: GalleryBotRow;
};

/**
 * Buang kandidat yang taksiran duelnya sudah miring, lalu pilih acak di antara
 * yang tersisa supaya lawannya tetap bervariasi antar-duel. Kesegaran stat
 * ditentukan dulu (pakai stat sendiri kalau total-nya dekat, kalau tidak
 * diskalakan ke total pemain), sebab yang dinilai harus stat yang benar-benar
 * dipakai di arena. Signed URL art hanya diambil untuk yang terpilih.
 */
function pickFairCandidate(
  seed: string,
  playerSnapshot: Record<string, unknown>,
  player: AnimaRow,
  candidates: RealCandidate[],
): (RealCandidate & { baseStats: Record<string, number> }) | null {
  const playerTotal = baseStatTotal(player.base_stats);
  const fair = candidates
    .map((candidate) => {
      const close = candidate.row.stage === player.stage &&
        Math.abs(baseStatTotal(candidate.row.base_stats) - playerTotal) <= playerTotal * 0.15;
      return {
        ...candidate,
        baseStats: close
          ? normalizeStats(candidate.row.base_stats)
          : normalizeStats(candidate.row.base_stats, playerTotal),
      };
    })
    .filter((candidate) =>
      isFairRealOpponent(playerSnapshot, {
        base_stats: candidate.baseStats,
        stage: candidate.row.stage,
        level: levelFromExp(candidate.row.care_score),
        element: normalizeElement(candidate.row.element),
        secondary_element: readSecondaryElement(candidate.row) ?? "",
      })
    );
  if (fair.length === 0) return null;
  fair.sort((left, right) => stableRank(`${seed}:${left.key}`) - stableRank(`${seed}:${right.key}`));
  return fair[0];
}

function readSecondaryElement(row: AnimaRow): string | null {
  if (typeof row.secondary_element !== "string") return null;
  const normalized = normalizeElement(row.secondary_element, "");
  return normalized || null;
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
