// POST /team_battle
// Body operation:
// teams | save_team | publish_defense | candidates | status |
// start | resume | turn | forfeit

import { adminClient, clientVersionGate, json, syncProfileTimezone } from "../_shared/supa.ts";
import {
  TEAM_ACTIONS,
  createTeamBattleState,
  resolveTeamTurn,
  teamRewardPreview,
} from "../_shared/team_combat.mjs";
import {
  asSnapshotArray,
  teamSnapshotFromMembers,
} from "../_shared/team_snapshot.mjs";
import { withSignedRoster } from "../_shared/signed_roster.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TEAM_KINDS = new Set(["team_battle", "defense"]);
const ACTIONS = new Set(TEAM_ACTIONS);
const ERROR_STATUS: Record<string, number> = {
  FEATURE_DISABLED: 404,
  INVALID_TEAM_KIND: 400,
  INVALID_ANIMA_IDS: 400,
  INVALID_TEAM_ID: 400,
  INVALID_CANDIDATE_ID: 400,
  INVALID_SESSION_ID: 400,
  INVALID_EXPECTED_TURN: 400,
  INVALID_EXPECTED_VERSION: 400,
  INVALID_SWITCH_TO_SLOT: 400,
  INVALID_ACTION: 400,
  INVALID_ITEM: 400,
  INVALID_IDEMPOTENCY_KEY: 400,
  INVALID_TEAM_SNAPSHOT: 400,
  INVALID_TEAM_CANDIDATES: 400,
  INVALID_TEAM_BATTLE_STATE: 400,
  INVALID_EVENTS: 400,
  INVALID_SEED: 400,
  SNAPSHOT_MISMATCH: 400,
  IDEMPOTENCY_CONFLICT: 409,
  STALE_TEAM_BATTLE: 409,
  TEAM_BATTLE_FINISHED: 409,
  FORCED_SWITCH_REQUIRED: 409,
  INVALID_SWITCH_SLOT: 409,
  NO_MOMENTUM: 409,
  NO_ITEM: 409,
  ITEM_ALREADY_USED: 409,
  TEAM_REQUIRES_FOUR: 409,
  TEAM_MEMBER_NOT_READY: 409,
  TEAM_MEMBER_UNAVAILABLE: 409,
  TEAM_MEMBER_SLEEPING: 409,
  TEAM_MEMBER_LOW_ENERGY: 409,
  TEAM_ART_NOT_READY: 409,
  TEAM_CANDIDATE_EXPIRED: 409,
  COMBAT_ALREADY_ACTIVE: 409,
  NO_TEAM_OPPONENT: 409,
  TEAM_NOT_FOUND: 404,
  TEAM_BATTLE_NOT_FOUND: 404,
  NO_PROFILE: 404,
};

type TeamBody = {
  operation?: unknown;
  kind?: unknown;
  anima_ids?: unknown;
  publish?: unknown;
  team_id?: unknown;
  candidate_id?: unknown;
  session_id?: unknown;
  action?: unknown;
  item_id?: unknown;
  switch_to_slot?: unknown;
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
  care?: { hunger?: number; energy?: number; hygiene?: number };
  sleep_started_at?: string | null;
  dormant_since?: string | null;
  status: string;
  strike_name?: string;
  surge_name?: string;
  evolution_version?: number;
  strike_effect_id?: string;
  surge_effect_id?: string;
  sheet_path?: string | null;
  manifest?: unknown;
};

type TeamMemberRow = {
  slot: number;
  animas: AnimaRow;
};

type TeamRow = {
  id: string;
  owner_id: string;
  kind: string;
  published: boolean;
  snapshot?: unknown;
  updated_at?: string;
  published_at?: string | null;
  anima_team_members?: TeamMemberRow[];
};

type CandidateSource = {
  source: "defense" | "system";
  source_id: string;
  opponent_team_id: string | null;
  snapshot: Record<string, unknown>[];
};

const TEAM_FIELDS =
  "id, owner_id, kind, published, snapshot, updated_at, published_at, "
  + "anima_team_members(slot, animas!inner("
  + "id, owner_id, nickname, species_key, color_bucket, stage, element, secondary_element, "
  + "base_stats, body_height_cm, care_score, care, sleep_started_at, dormant_since, status, "
  + "strike_name, surge_name, evolution_version, strike_effect_id, surge_effect_id, sheet_path, manifest))";
const db = adminClient();
let featureCache = false;
let featureCacheUntil = 0;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await db.auth.getClaims(token);
  const ownerId = auth?.claims?.sub;
  if (authError || typeof ownerId !== "string") return json(401, { error: "token tidak sah" });

  let body: TeamBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const operation = typeof body.operation === "string" ? body.operation : "";
  const lifecycleOperation = operation === "resume" || operation === "turn" || operation === "forfeit";
  if (!lifecycleOperation && !await teamBattleEnabled()) {
    return json(404, { error: "FEATURE_DISABLED" });
  }
  await syncProfileTimezone(db, ownerId, body.timezone_offset_minutes);
  try {
    if (operation === "teams") return await listTeams(ownerId);
    if (operation === "save_team") return await saveTeam(ownerId, body);
    if (operation === "publish_defense") return await publishDefense(ownerId, body);
    if (operation === "candidates") return await createCandidates(ownerId, body);
    if (operation === "status") return await teamStatus(ownerId, body);
    if (operation === "start") return await startTeamBattle(ownerId, body);
    if (operation === "resume") return await resumeTeamBattle(ownerId, body);
    if (operation === "turn") return await playTeamTurn(ownerId, body);
    if (operation === "forfeit") return await forfeitTeamBattle(ownerId, body);
    return json(400, { error: "operation tidak dikenal" });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : String(error);
    const marker = Object.keys(ERROR_STATUS).find((candidate) => message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("team_battle gagal", error);
    return json(500, { error: "Team Battle gagal diproses" });
  }
});

async function listTeams(ownerId: string): Promise<Response> {
  const { data, error } = await db
    .from("anima_teams")
    .select(TEAM_FIELDS)
    .eq("owner_id", ownerId)
    .order("kind");
  if (error) throw error;
  const teams = ((data ?? []) as unknown as TeamRow[]).map(publicTeam);
  return json(200, { teams });
}

async function saveTeam(ownerId: string, body: TeamBody): Promise<Response> {
  const kind = typeof body.kind === "string" ? body.kind : "";
  if (!TEAM_KINDS.has(kind)) throw new Error("INVALID_TEAM_KIND");
  const animaIds = asUuidArray(body.anima_ids, "anima_ids", 4);
  const { data, error } = await db.rpc("save_anima_team", {
    p_owner: ownerId,
    p_kind: kind,
    p_anima_ids: animaIds,
  });
  if (error) throw error;
  return json(200, { team: publicTeamPayload(data) });
}

async function publishDefense(ownerId: string, body: TeamBody): Promise<Response> {
  const publish = body.publish !== false;
  if (!publish) {
    const { data, error } = await db.rpc("publish_defense_team", {
      p_owner: ownerId,
      p_snapshot: [],
      p_publish: false,
    });
    if (error) throw error;
    return json(200, { team: publicTeamPayload(data) });
  }

  const team = await loadTeam(ownerId, null, "defense");
  const snapshot = teamSnapshot(team, false);
  const { data, error } = await db.rpc("publish_defense_team", {
    p_owner: ownerId,
    p_snapshot: snapshot,
    p_publish: true,
  });
  if (error) throw error;
  return json(200, { team: publicTeamPayload(data) });
}

async function createCandidates(ownerId: string, body: TeamBody): Promise<Response> {
  const teamId = body.team_id === undefined || body.team_id === null
    ? null
    : asUuid(body.team_id, "team_id");
  const playerTeam = await loadTeam(ownerId, teamId, "team_battle");
  const playerSnapshot = teamSnapshot(playerTeam, true);

  const [{ data: defenses, error: defenseError }, { data: systems, error: systemError }] =
    await Promise.all([
      db
        .from("anima_teams")
        .select("id, owner_id, snapshot")
        .eq("kind", "defense")
        .eq("published", true)
        .neq("owner_id", ownerId)
        .not("snapshot", "is", null)
        .limit(100),
      db
        .from("system_team_templates")
        .select("id, roster_snapshot")
        .eq("active", true)
        .limit(50),
    ]);
  if (defenseError) throw defenseError;
  if (systemError) throw systemError;

  const sources: CandidateSource[] = [];
  for (const row of defenses ?? []) {
    const snapshot = asSnapshotArray(row.snapshot);
    if (snapshot) {
      sources.push({
        source: "defense",
        source_id: row.id,
        opponent_team_id: row.id,
        snapshot,
      });
    }
  }
  for (const row of systems ?? []) {
    const snapshot = asSnapshotArray(row.roster_snapshot);
    if (snapshot) {
      sources.push({
        source: "system",
        source_id: row.id,
        opponent_team_id: null,
        snapshot,
      });
    }
  }
  if (sources.length === 0) throw new Error("NO_TEAM_OPPONENT");

  const seed = crypto.randomUUID();
  const targets = [0.9, 1.0, 1.15];
  const selected: Array<CandidateSource & { reward: ReturnType<typeof teamRewardPreview> }> = [];
  for (const target of targets) {
    const ranked = sources
      .filter((source) => !selected.some((picked) =>
        picked.source === source.source && picked.source_id === source.source_id
      ))
      .map((source) => ({
        ...source,
        reward: teamRewardPreview(playerSnapshot, source.snapshot, `${seed}:${source.source_id}`),
      }))
      .sort((left, right) =>
        Math.abs(left.reward.ratio - target) - Math.abs(right.reward.ratio - target)
      );
    if (ranked[0]) selected.push(ranked[0]);
  }
  if (selected.length === 0) throw new Error("NO_TEAM_OPPONENT");

  const rows = selected.map((candidate) => ({
    opponent_source: candidate.source,
    opponent_team_id: candidate.opponent_team_id,
    opponent_snapshot: candidate.snapshot,
    reward_tier: candidate.reward.tier,
    reward_roll: candidate.reward.roll,
    reward_bits: candidate.reward.bits,
  }));
  const { data: inserted, error: insertError } = await db.rpc(
    "replace_team_battle_candidates",
    {
      p_owner: ownerId,
      p_player_team_id: playerTeam.id,
      p_candidates: rows,
    },
  );
  if (insertError) throw insertError;
  const insertedRows = Array.isArray(inserted) ? inserted : [];

  const candidates = await Promise.all(insertedRows.map(async (candidate) => ({
    id: candidate.id,
    source: candidate.opponent_source,
    roster: await withSignedRoster(db, candidate.opponent_snapshot),
    reward_tier: candidate.reward_tier,
    reward_roll: candidate.reward_roll,
    reward_bits: candidate.reward_bits,
    expires_at: candidate.expires_at,
  })));
  return json(200, { team: publicTeam(playerTeam), candidates });
}

async function teamStatus(ownerId: string, body: TeamBody): Promise<Response> {
  const sessionId = body.session_id === undefined || body.session_id === null
    ? null
    : asUuid(body.session_id, "session_id");
  const { data, error } = await db.rpc("team_battle_daily_reward_status", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return json(200, data);
}

async function startTeamBattle(ownerId: string, body: TeamBody): Promise<Response> {
  const { data: existing, error: resumeError } = await db.rpc("resume_team_battle", {
    p_owner: ownerId,
    p_session_id: null,
  });
  if (resumeError) throw resumeError;
  if (existing) return json(200, await withFreshTeamArt(existing));

  const teamId = asUuid(body.team_id, "team_id");
  const candidateId = asUuid(body.candidate_id, "candidate_id");
  const [team, candidateResult] = await Promise.all([
    loadTeam(ownerId, teamId, "team_battle"),
    db
      .from("team_battle_candidates")
      .select("id, owner_id, player_team_id, opponent_snapshot, expires_at, consumed_at")
      .eq("id", candidateId)
      .eq("owner_id", ownerId)
      .maybeSingle(),
  ]);
  if (candidateResult.error) throw candidateResult.error;
  const candidate = candidateResult.data;
  if (
    !candidate ||
    candidate.player_team_id !== team.id ||
    candidate.consumed_at ||
    Date.parse(candidate.expires_at) <= Date.now()
  ) {
    throw new Error("TEAM_CANDIDATE_EXPIRED");
  }
  const opponentSnapshot = asSnapshotArray(candidate.opponent_snapshot);
  if (!opponentSnapshot) throw new Error("INVALID_TEAM_SNAPSHOT");

  const playerSnapshot = teamSnapshot(team, true);
  const seed = crypto.randomUUID();
  const initialState = createTeamBattleState({
    player: playerSnapshot,
    opponent: opponentSnapshot,
    seed,
  });
  const { data, error } = await db.rpc("start_team_battle", {
    p_owner: ownerId,
    p_player_team_id: team.id,
    p_candidate_id: candidateId,
    p_player_snapshot: playerSnapshot,
    p_initial_state: initialState,
    p_seed: seed,
  });
  if (error) throw error;
  return json(200, await withFreshTeamArt(data));
}

async function resumeTeamBattle(ownerId: string, body: TeamBody): Promise<Response> {
  const sessionId = body.session_id === undefined || body.session_id === null
    ? null
    : asUuid(body.session_id, "session_id");
  const { data, error } = await db.rpc("resume_team_battle", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  if (!data) throw new Error("TEAM_BATTLE_NOT_FOUND");
  return json(200, await withFreshTeamArt(data));
}

async function playTeamTurn(ownerId: string, body: TeamBody): Promise<Response> {
  const sessionId = asUuid(body.session_id, "session_id");
  const action = typeof body.action === "string" ? body.action : "";
  const itemId = typeof body.item_id === "string" ? body.item_id : "";
  const key = typeof body.idempotency_key === "string" ? body.idempotency_key : "";
  const expectedTurn = asPositiveInt(body.expected_turn, "expected_turn");
  const expectedVersion = asPositiveInt(body.expected_version, "expected_version");
  const switchToSlot = action === "switch"
    ? asSlot(body.switch_to_slot)
    : null;
  if (!ACTIONS.has(action)) throw new Error("INVALID_ACTION");
  if (action === "item" && !itemId) throw new Error("INVALID_ITEM");
  if (!key || key.length > 128) throw new Error("INVALID_IDEMPOTENCY_KEY");

  const { data: session, error: resumeError } = await db.rpc("resume_team_battle", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (resumeError) throw resumeError;
  if (!session) throw new Error("TEAM_BATTLE_NOT_FOUND");

  const { data: prior, error: priorError } = await db
    .from("team_battle_turns")
    .select("turn_number, action, switch_to_slot, catalog_item_id, response")
    .eq("session_id", sessionId)
    .eq("idempotency_key", key)
    .maybeSingle();
  if (priorError) throw priorError;
  if (prior) {
    if (
      prior.turn_number !== expectedTurn ||
      prior.action !== action ||
      prior.switch_to_slot !== switchToSlot ||
      (prior.catalog_item_id ?? "") !== (action === "item" ? itemId : "")
    ) {
      throw new Error("IDEMPOTENCY_CONFLICT");
    }
    return json(200, await withFreshTeamArtInResponse({
      ...prior.response,
      replayed: true,
    }));
  }

  if (session.status !== "active") throw new Error("TEAM_BATTLE_FINISHED");

  const result = resolveTeamTurn(session.state, action, key, itemId, switchToSlot);
  const { data, error } = await db.rpc("commit_team_battle_turn", {
    p_owner: ownerId,
    p_session_id: sessionId,
    p_expected_turn: expectedTurn,
    p_expected_version: expectedVersion,
    p_key: key,
    p_action: action,
    p_switch_to_slot: switchToSlot,
    p_item_id: action === "item" ? itemId : null,
    p_state: result.state,
    p_events: result.events,
    p_bot_action: result.bot_action,
  });
  if (error) throw error;
  return json(200, await withFreshTeamArtInResponse(data));
}

async function forfeitTeamBattle(ownerId: string, body: TeamBody): Promise<Response> {
  const sessionId = asUuid(body.session_id, "session_id");
  const { data, error } = await db.rpc("forfeit_team_battle", {
    p_owner: ownerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return json(200, await withFreshTeamArt(data));
}

async function loadTeam(ownerId: string, teamId: string | null, kind: string): Promise<TeamRow> {
  let query = db
    .from("anima_teams")
    .select(TEAM_FIELDS)
    .eq("owner_id", ownerId)
    .eq("kind", kind);
  if (teamId) query = query.eq("id", teamId);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("TEAM_NOT_FOUND");
  const team = data as unknown as TeamRow;
  if ((team.anima_team_members ?? []).length !== 4) throw new Error("TEAM_REQUIRES_FOUR");
  return team;
}

function teamSnapshot(team: TeamRow, includeName: boolean): Record<string, unknown>[] {
  return teamSnapshotFromMembers(
    team.anima_team_members ?? [],
    includeName,
  ) as Record<string, unknown>[];
}

function publicTeam(team: TeamRow): Record<string, unknown> {
  const members = [...(team.anima_team_members ?? [])]
    .sort((left, right) => left.slot - right.slot)
    .map((member) => ({
      slot: member.slot,
      anima_id: member.animas.id,
      nickname: member.animas.nickname,
      stage: member.animas.stage,
      element: member.animas.element,
      secondary_element: member.animas.secondary_element ?? null,
      base_stats: member.animas.base_stats,
      body_height_cm: member.animas.body_height_cm ?? 120,
      care_score: member.animas.care_score ?? 0,
      care: member.animas.care ?? {},
      sleep_started_at: member.animas.sleep_started_at ?? null,
      dormant_since: member.animas.dormant_since ?? null,
      status: member.animas.status,
    }));
  return {
    id: team.id,
    kind: team.kind,
    published: team.published,
    updated_at: team.updated_at ?? null,
    published_at: team.published_at ?? null,
    members,
  };
}

function publicTeamPayload(value: unknown): unknown {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const team = { ...(value as Record<string, unknown>) };
  if (Array.isArray(team.members)) {
    team.members = team.members.map((raw) => {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) return raw;
      const member = { ...(raw as Record<string, unknown>) };
      delete member.sheet_path;
      delete member.manifest;
      return member;
    });
  }
  return team;
}

async function withFreshTeamArtInResponse(value: unknown): Promise<unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const response = value as Record<string, unknown>;
  return {
    ...response,
    session: await withFreshTeamArt(response.session),
  };
}

async function withFreshTeamArt(value: unknown): Promise<unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const session = { ...(value as Record<string, unknown>) };
  session.player_snapshot = await withSignedRoster(db, session.player_snapshot);
  session.opponent_snapshot = await withSignedRoster(db, session.opponent_snapshot);
  return session;
}

function asUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function asUuidArray(value: unknown, field: string, length: number): string[] {
  if (!Array.isArray(value) || value.length !== length) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  const ids = value.map((entry) => asUuid(entry, field));
  if (new Set(ids).size !== length) throw new Error(`INVALID_${field.toUpperCase()}`);
  return ids;
}

function asPositiveInt(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function asSlot(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 3) {
    throw new Error("INVALID_SWITCH_TO_SLOT");
  }
  return value;
}

async function teamBattleEnabled(): Promise<boolean> {
  const now = Date.now();
  if (now < featureCacheUntil) return featureCache;
  const { data, error } = await db
    .from("app_config")
    .select("value")
    .eq("key", "feature_team_battle")
    .maybeSingle();
  if (error) throw error;
  featureCache = data?.value === true;
  featureCacheUntil = now + 30_000;
  return featureCache;
}
