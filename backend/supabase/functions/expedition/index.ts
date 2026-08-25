// POST /expedition
// Content: chapters | chapter | trophies | feature_trophies
// Run: save_team | start_run | checkpoint_choice | start_zone | resume |
//      enter_node | choose | refresh_shop | turn | forfeit | abandon

import { adminClient, clientVersionGate, corsPreflight, json, syncProfileTimezone } from "../_shared/supa.ts";
import {
  applyEncounterBoosts,
  applyNodeOption,
  findExpeditionNode,
  generateZoneMap,
  nextNodeIds,
  opponentRosterForEncounter,
  prepareExpeditionRoster,
  prepareExpeditionZoneRoster,
  publicBossSeeker,
  validateChapterManifest,
} from "../_shared/expedition.mjs";
import {
  createTeamBattleState,
  createTeamParty,
  resolveTeamTurn,
} from "../_shared/team_combat.mjs";
import {
  asSnapshotArray,
  teamSnapshotFromMembers,
} from "../_shared/team_snapshot.mjs";
import { withSignedRoster } from "../_shared/signed_roster.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COMBAT_ACTIONS = new Set(["strike", "surge", "guard", "item", "switch"]);
const LIFECYCLE_OPERATIONS = new Set([
  "chapter",
  "team",
  "save_team",
  "start_zone",
  "checkpoint_choice",
  "resume",
  "enter_node",
  "choose",
  "refresh_shop",
  "turn",
  "forfeit",
  "abandon",
  "ack_home_popup",
]);
const ERROR_STATUS: Record<string, number> = {
  FEATURE_DISABLED: 404,
  INVALID_CHAPTER_VERSION_ID: 400,
  INVALID_CHAPTER_IDS: 400,
  INVALID_TEAM_ID: 400,
  INVALID_RUN_ID: 400,
  INVALID_ENCOUNTER_ID: 400,
  INVALID_NODE_ID: 400,
  INVALID_OPTION_ID: 400,
  INVALID_TARGET_SLOT: 400,
  INVALID_EXPECTED_TURN: 400,
  INVALID_EXPECTED_VERSION: 400,
  INVALID_SWITCH_TO_SLOT: 400,
  INVALID_ACTION: 400,
  INVALID_ITEM: 400,
  INVALID_IDEMPOTENCY_KEY: 400,
  INVALID_EXPEDITION_NODE: 400,
  INVALID_EXPEDITION_CHOICE: 400,
  INVALID_EXPEDITION_STATE: 400,
  INVALID_EXPEDITION_PP: 400,
  INVALID_EXPEDITION_PROGRESS: 409,
  INVALID_EXPEDITION_MAP: 400,
  INVALID_TEAM_BATTLE_STATE: 409,
  INVALID_EVENTS: 400,
  TEAM_BATTLE_FINISHED: 409,
  INVALID_SEED: 400,
  PROFILE_NOT_FOUND: 404,
  INVALID_EXPEDITION_ENCOUNTER: 400,
  INVALID_CHAPTER_COMPLETION: 400,
  INVALID_EXPEDITION_CHECKPOINT: 400,
  INVALID_EXPEDITION_CHECKPOINT_CHOICE: 400,
  UNSUPPORTED_CHAPTER_SCHEMA: 409,
  UNSUPPORTED_CHAPTER_EFFECT: 409,
  CHAPTER_NOT_AVAILABLE: 404,
  CHAPTER_LOCKED: 409,
  TEAM_NOT_FOUND: 404,
  TEAM_REQUIRES_FOUR: 409,
  TEAM_MEMBER_UNAVAILABLE: 409,
  TEAM_MEMBER_LOW_ENERGY: 409,
  EXPEDITION_TEAM_LOCKED: 409,
  TEAM_ART_NOT_READY: 409,
  SNAPSHOT_MISMATCH: 409,
  COMBAT_ALREADY_ACTIVE: 409,
  EXPEDITION_RUN_NOT_FOUND: 404,
  EXPEDITION_ENCOUNTER_NOT_FOUND: 404,
  EXPEDITION_NOT_AT_CHECKPOINT: 409,
  EXPEDITION_CHECKPOINT_CHOICE_REQUIRED: 409,
  EXPEDITION_CHECKPOINT_CHOICE_UNAVAILABLE: 409,
  EXPEDITION_NODE_PENDING: 409,
  EXPEDITION_ENCOUNTER_FINISHED: 409,
  EXPEDITION_ENCOUNTER_EXPIRED: 409,
  STALE_EXPEDITION: 409,
  STALE_EXPEDITION_ENCOUNTER: 409,
  IDEMPOTENCY_CONFLICT: 409,
  FORCED_SWITCH_REQUIRED: 409,
  INVALID_SWITCH_SLOT: 409,
  NO_MOMENTUM: 409,
  NO_ITEM: 409,
  ITEM_ALREADY_USED: 409,
  NO_SUPPLIES: 409,
  NO_BITS: 409,
  EXPEDITION_SHOP_REFRESH_UNAVAILABLE: 409,
  TROPHY_NOT_OWNED: 409,
  INVALID_TROPHY_SELECTION: 400,
  TROPHY_NOT_CONFIGURED: 409,
  INVALID_ANNOUNCEMENT_SELECTION: 400,
};

type ExpeditionBody = {
  operation?: unknown;
  chapter_version_id?: unknown;
  team_id?: unknown;
  anima_ids?: unknown;
  run_id?: unknown;
  encounter_id?: unknown;
  node_id?: unknown;
  option_id?: unknown;
  target_slot?: unknown;
  trophy_ids?: unknown;
  chapter_ids?: unknown;
  action?: unknown;
  item_id?: unknown;
  switch_to_slot?: unknown;
  expected_turn?: unknown;
  expected_version?: unknown;
  idempotency_key?: unknown;
  timezone_offset_minutes?: unknown;
};

type TeamMemberRow = {
  slot: number;
  animas: Record<string, unknown>;
};

type TeamRow = {
  id: string;
  owner_id: string;
  kind: string;
  anima_team_members?: TeamMemberRow[];
};

type RunRow = {
  id: string;
  owner_id: string;
  chapter_version_id: string;
  team_id: string;
  status: string;
  zone: number;
  zone_attempt: number;
  version: number;
  seed: string;
  zone_map: Record<string, unknown> | null;
  available_node_ids: unknown[];
  current_node_id: string | null;
  nodes_completed: number;
  supplies: number;
  boosts: unknown[];
  party_state: Record<string, unknown>[];
  pending_node: Record<string, unknown> | null;
  checkpoint_choice: string | null;
  checkpoint_choice_pending: boolean;
};

type EncounterRow = {
  id: string;
  run_id: string;
  owner_id: string;
  node_id: string;
  kind: string;
  player_snapshot: Record<string, unknown>[];
  opponent_snapshot: Record<string, unknown>[];
  state: Record<string, unknown>;
  turn_number: number;
  version: number;
  status: string;
  expires_at: string;
};

type VersionRow = {
  id: string;
  chapter_id: string;
  asset_prefix: string;
  manifest: Record<string, unknown>;
  minimum_build: Record<string, unknown>;
};

const TEAM_FIELDS =
  "id, owner_id, kind, anima_team_members(slot, animas!inner("
  + "id, owner_id, nickname, species_key, color_bucket, stage, element, secondary_element, "
  + "base_stats, body_height_cm, care_score, care, sleep_started_at, dormant_since, status, "
  + "strike_name, surge_name, evolution_version, strike_effect_id, surge_effect_id, sheet_path, manifest))";

const db = adminClient();
let featureCache = false;
let featureCacheUntil = 0;

Deno.serve(async (req) => {
  const preflight = corsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await db.auth.getClaims(token);
  const ownerId = auth?.claims?.sub;
  if (authError || typeof ownerId !== "string") return json(401, { error: "token tidak sah" });

  let body: ExpeditionBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }
  const operation = typeof body.operation === "string" ? body.operation : "";
  if (!LIFECYCLE_OPERATIONS.has(operation) && !await expeditionEnabled()) {
    return json(404, { error: "FEATURE_DISABLED" });
  }
  await syncProfileTimezone(db, ownerId, body.timezone_offset_minutes);

  try {
    if (operation === "chapters") return await listChapters(ownerId);
    if (operation === "announcements") return await listAnnouncements(ownerId);
    if (operation === "ack_home_popup") return await ackHomePopup(ownerId, body);
    if (operation === "chapter") return await getChapter(ownerId, body, req);
    if (operation === "trophies") return await listTrophies(ownerId);
    if (operation === "feature_trophies") return await featureTrophies(ownerId, body);
    if (operation === "team") return await getTeam(ownerId);
    if (operation === "save_team") return await saveTeam(ownerId, body);
    if (operation === "start_run") return await startRun(ownerId, body, req);
    if (operation === "start_zone") return await startZone(ownerId, body);
    if (operation === "checkpoint_choice") return await chooseCheckpoint(ownerId, body);
    if (operation === "resume") return await resume(ownerId, body);
    if (operation === "enter_node") return await enterNode(ownerId, body);
    if (operation === "choose") return await chooseNodeOption(ownerId, body);
    if (operation === "refresh_shop") return await refreshShop(ownerId, body);
    if (operation === "turn") return await playTurn(ownerId, body);
    if (operation === "forfeit") return await forfeit(ownerId, body);
    if (operation === "abandon") return await abandon(ownerId, body);
    return json(400, { error: "operation tidak dikenal" });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : String(error);
    const marker = Object.keys(ERROR_STATUS).find((candidate) => message.includes(candidate));
    if (marker) return json(ERROR_STATUS[marker], { error: marker });
    console.error("expedition gagal", error);
    return json(500, { error: "Expedition gagal diproses" });
  }
});

async function listChapters(ownerId: string): Promise<Response> {
  const { data, error } = await db.rpc("expedition_chapter_catalog", { p_owner: ownerId });
  if (error) throw error;
  return json(200, {
    chapters: withPublicAssets(Array.isArray(data) ? data : []),
    asset_base_url: chapterAssetBaseUrl(),
  });
}

async function getChapter(ownerId: string, body: ExpeditionBody, req: Request): Promise<Response> {
  const versionId = asUuid(body.chapter_version_id, "chapter_version_id");
  const { data: catalog, error: catalogError } = await db.rpc("expedition_chapter_catalog", {
    p_owner: ownerId,
  });
  if (catalogError) throw catalogError;
  const entry = (Array.isArray(catalog) ? catalog : []).find((value) =>
    value && typeof value === "object" && value.version_id === versionId
  ) as Record<string, unknown> | undefined;
  if (!entry || entry.unlocked !== true) throw new Error(entry ? "CHAPTER_LOCKED" : "CHAPTER_NOT_AVAILABLE");
  const version = await loadVersion(versionId);
  const buildError = chapterBuildError(req, version.minimum_build);
  if (buildError) return buildError;
  const manifest = validateChapterManifest(version.manifest);
  const { data: announcements, error: receiptError } = await db.rpc(
    "mark_expedition_chapter_opened",
    { p_owner: ownerId, p_chapter_version_id: versionId },
  );
  if (receiptError) throw receiptError;
  return json(200, {
    ...entry,
    manifest: withManifestAssetUrls(manifest, version.asset_prefix),
    asset_base_url: chapterAssetBaseUrl(),
    announcements,
  });
}

async function listAnnouncements(ownerId: string): Promise<Response> {
  const { data, error } = await db.rpc("expedition_announcements_payload", {
    p_owner: ownerId,
  });
  if (error) throw error;
  return json(200, data ?? { unread: [], home_popup: [] });
}

async function ackHomePopup(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const chapterIds = asUuidArray(body.chapter_ids ?? [], "chapter_ids", null, 20);
  const { data, error } = await db.rpc("ack_expedition_home_popup", {
    p_owner: ownerId,
    p_chapter_ids: chapterIds,
  });
  if (error) throw error;
  return json(200, data ?? { unread: [], home_popup: [] });
}

async function saveTeam(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const animaIds = asUuidArray(body.anima_ids, "anima_ids", 4);
  const { data, error } = await db.rpc("save_anima_team", {
    p_owner: ownerId,
    p_kind: "expedition",
    p_anima_ids: animaIds,
  });
  if (error) throw error;
  return json(200, { team: stripPrivateTeamArt(data) });
}

async function getTeam(ownerId: string): Promise<Response> {
  const { data, error } = await db
    .from("anima_teams")
    .select(TEAM_FIELDS)
    .eq("owner_id", ownerId)
    .eq("kind", "expedition")
    .maybeSingle();
  if (error) throw error;
  return json(200, { team: stripPrivateTeamArt(data) });
}

async function startRun(ownerId: string, body: ExpeditionBody, req: Request): Promise<Response> {
  const versionId = asUuid(body.chapter_version_id, "chapter_version_id");
  const teamId = asUuid(body.team_id, "team_id");
  const key = asKey(body.idempotency_key);
  const [version, team] = await Promise.all([
    loadVersion(versionId),
    loadTeam(ownerId, teamId),
  ]);
  const buildError = chapterBuildError(req, version.minimum_build);
  if (buildError) return buildError;
  const playerSnapshot = teamSnapshot(team);
  const { data, error } = await db.rpc("start_expedition_run", {
    p_owner: ownerId,
    p_chapter_version_id: versionId,
    p_team_id: teamId,
    p_seed: crypto.randomUUID(),
    p_party_state: playerSnapshot,
    p_key: key,
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data }));
}

async function startZone(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const run = await loadRun(ownerId, asUuid(body.run_id, "run_id"));
  if (run.checkpoint_choice_pending || (run.zone > 1 && !run.checkpoint_choice)) {
    throw new Error("EXPEDITION_CHECKPOINT_CHOICE_REQUIRED");
  }
  const expectedVersion = asPositiveInteger(body.expected_version, "expected_version");
  const key = asKey(body.idempotency_key);
  const teamId = asUuid(body.team_id, "team_id");
  const [version, initialTeam] = await Promise.all([
    loadVersion(run.chapter_version_id),
    loadTeam(ownerId, teamId),
  ]);
  await syncTeamCare(ownerId, initialTeam);
  const team = await loadTeam(ownerId, teamId);
  const manifest = validateChapterManifest(version.manifest);
  const seed = crypto.randomUUID();
  const map = generateZoneMap(manifest, run.zone, run.zone_attempt + 1, seed);
  const prepared = prepareExpeditionZoneRoster(
    teamSnapshot(team),
    run.party_state,
    run.boosts,
    run.checkpoint_choice,
  );
  const fighters = createTeamParty(prepared, true).roster;
  const partyState = prepared.map((member, index) => ({
    ...member,
    hp: fighters[index].hp,
    current_hp: fighters[index].hp,
    max_hp: fighters[index].max_hp,
  }));
  const { data, error } = await db.rpc("start_expedition_zone", {
    p_owner: ownerId,
    p_run_id: run.id,
    p_expected_version: expectedVersion,
    p_team_id: teamId,
    p_seed: seed,
    p_party_state: partyState,
    p_zone_map: map,
    p_key: key,
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data }));
}

async function chooseCheckpoint(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const optionId = asTextId(body.option_id, "option_id");
  if (!["recover", "power_up"].includes(optionId)) {
    throw new Error("INVALID_EXPEDITION_CHECKPOINT_CHOICE");
  }
  const { data, error } = await db.rpc("commit_expedition_checkpoint_choice", {
    p_owner: ownerId,
    p_run_id: asUuid(body.run_id, "run_id"),
    p_expected_version: asPositiveInteger(body.expected_version, "expected_version"),
    p_option_id: optionId,
    p_key: asKey(body.idempotency_key),
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data }));
}

async function resume(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const runId = body.run_id === undefined || body.run_id === null
    ? null
    : asUuid(body.run_id, "run_id");
  let query = db
    .from("expedition_runs")
    .select("*")
    .eq("owner_id", ownerId);
  query = runId
    ? query.eq("id", runId)
    : query.in("status", ["checkpoint", "active"]).order("created_at", { ascending: false }).limit(1);
  const { data: rows, error } = await query;
  if (error) throw error;
  const run = Array.isArray(rows) ? rows[0] as RunRow | undefined : undefined;
  if (!run) return json(200, null);
  const encounter = await loadActiveEncounter(ownerId, run.id, false);
  if (encounter && Date.parse(encounter.expires_at) <= Date.now()) {
    const version = await loadVersion(run.chapter_version_id);
    const seed = crypto.randomUUID();
    const retryMap = generateZoneMap(
      validateChapterManifest(version.manifest),
      run.zone,
      run.zone_attempt + 1,
      seed,
    );
    const { data, error: resetError } = await db.rpc("forfeit_expedition_encounter", {
      p_owner: ownerId,
      p_encounter_id: encounter.id,
      p_retry_map: retryMap,
      p_retry_seed: seed,
    });
    if (resetError) throw resetError;
    return json(200, await withFreshExpeditionArt(data));
  }
  return json(200, await withFreshExpeditionArt({ run, encounter }));
}

async function enterNode(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const run = await loadRun(ownerId, asUuid(body.run_id, "run_id"));
  const expectedVersion = asPositiveInteger(body.expected_version, "expected_version");
  const key = asKey(body.idempotency_key);
  const nodeId = asTextId(body.node_id, "node_id");
  const node = findExpeditionNode(run.zone_map, nodeId);
  if (!node) throw new Error("INVALID_EXPEDITION_NODE");
  if (["battle", "elite", "boss"].includes(String(node.kind))) {
    return await startEncounter(ownerId, run, expectedVersion, node, key);
  }
  const { data, error } = await db.rpc("enter_expedition_node", {
    p_owner: ownerId,
    p_run_id: run.id,
    p_expected_version: expectedVersion,
    p_node: node,
    p_key: key,
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data }));
}

async function startEncounter(
  ownerId: string,
  run: RunRow,
  expectedVersion: number,
  node: Record<string, unknown>,
  key: string,
): Promise<Response> {
  const [version, team] = await Promise.all([
    loadVersion(run.chapter_version_id),
    loadTeam(ownerId, run.team_id),
  ]);
  const manifest = validateChapterManifest(version.manifest);
  const playerSnapshot = prepareExpeditionRoster(teamSnapshot(team), run.party_state, run.boosts);
  const opponentSnapshot = chapterRoster(
    opponentRosterForEncounter(manifest, node, run.zone),
    version.asset_prefix,
  );
  const seed = crypto.randomUUID();
  const initialState = applyEncounterBoosts(
    createTeamBattleState({
      player: playerSnapshot,
      opponent: opponentSnapshot,
      seed,
      encounterKind: String(node.kind),
      acePassive: node.kind === "boss" ? manifest.boss.ace_passive : null,
    }),
    run.boosts,
  );
  const { data, error } = await db.rpc("start_expedition_encounter", {
    p_owner: ownerId,
    p_run_id: run.id,
    p_expected_version: expectedVersion,
    p_node: node,
    p_player_snapshot: playerSnapshot,
    p_opponent_snapshot: opponentSnapshot,
    p_initial_state: initialState,
    p_seed: seed,
    p_supplies_reward: boundedInteger(node.supplies_reward, 0, 999, 2),
    p_key: key,
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt(data));
}

async function chooseNodeOption(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const run = await loadRun(ownerId, asUuid(body.run_id, "run_id"));
  const expectedVersion = asPositiveInteger(body.expected_version, "expected_version");
  const optionId = asTextId(body.option_id, "option_id");
  const targetSlot = body.target_slot === undefined || body.target_slot === null
    ? null
    : asSlot(body.target_slot, "target_slot");
  const node = run.pending_node;
  if (!node || !run.current_node_id) throw new Error("INVALID_EXPEDITION_CHOICE");
  const applied = applyNodeOption({
    partyState: run.party_state,
    supplies: run.supplies,
    boosts: run.boosts,
    node,
    optionId,
    targetSlot,
  });
  const next = nextNodeIds(run.zone_map, run.current_node_id);
  const checkpoint = run.zone < 3 && run.nodes_completed === 3 && next.length === 0;
  const { data, error } = await db.rpc("commit_expedition_choice", {
    p_owner: ownerId,
    p_run_id: run.id,
    p_expected_version: expectedVersion,
    p_node_id: run.current_node_id,
    p_option_id: optionId,
    p_party_state: applied.party_state,
    p_supplies: applied.supplies,
    p_boosts: applied.boosts,
    p_next_node_ids: next,
    p_checkpoint: checkpoint,
    p_key: asKey(body.idempotency_key),
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data, choice: applied.option }));
}

async function refreshShop(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const run = await loadRun(ownerId, asUuid(body.run_id, "run_id"));
  const expectedVersion = asPositiveInteger(body.expected_version, "expected_version");
  if (!run.pending_node || run.pending_node.kind !== "shop") {
    throw new Error("EXPEDITION_SHOP_REFRESH_UNAVAILABLE");
  }
  const version = await loadVersion(run.chapter_version_id);
  const manifest = validateChapterManifest(version.manifest);
  const pool = manifest.zones[run.zone - 1].node_pools.shop;
  const replacement = structuredClone(
    pool[(run.zone_attempt + run.nodes_completed + 1) % pool.length],
  );
  const refreshed = {
    ...run.pending_node,
    ...replacement,
    id: run.pending_node.id,
    kind: "shop",
    depth: run.pending_node.depth,
    next: run.pending_node.next,
  };
  const { data, error } = await db.rpc("refresh_expedition_shop", {
    p_owner: ownerId,
    p_run_id: run.id,
    p_expected_version: expectedVersion,
    p_node: refreshed,
    p_key: asKey(body.idempotency_key),
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data }));
}

async function playTurn(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const encounterId = asUuid(body.encounter_id, "encounter_id");
  const encounter = await loadEncounter(ownerId, encounterId);
  const expectedTurn = asPositiveInteger(body.expected_turn, "expected_turn");
  const expectedVersion = asPositiveInteger(body.expected_version, "expected_version");
  const action = typeof body.action === "string" ? body.action : "";
  if (!COMBAT_ACTIONS.has(action)) throw new Error("INVALID_ACTION");
  const switchToSlot = action === "switch" ? asSlot(body.switch_to_slot, "switch_to_slot") : null;
  const itemId = action === "item" && typeof body.item_id === "string" ? body.item_id : "";
  if (action === "item" && !itemId) throw new Error("INVALID_ITEM");
  if (action !== "item" && body.item_id !== undefined && body.item_id !== null) {
    throw new Error("INVALID_ITEM");
  }
  const key = asKey(body.idempotency_key);
  const { data: prior, error: priorError } = await db
    .from("expedition_encounter_turns")
    .select("turn_number, action, switch_to_slot, catalog_item_id, response")
    .eq("encounter_id", encounter.id)
    .eq("idempotency_key", key)
    .maybeSingle();
  if (priorError) throw priorError;
  if (prior) {
    if (
      prior.turn_number !== expectedTurn ||
      prior.action !== action ||
      prior.switch_to_slot !== switchToSlot ||
      prior.catalog_item_id !== (itemId || null)
    ) throw new Error("IDEMPOTENCY_CONFLICT");
    return json(200, await withFreshExpeditionArt({ ...prior.response, replayed: true }));
  }
  if (encounter.status !== "active") throw new Error("EXPEDITION_ENCOUNTER_FINISHED");
  if (Date.parse(encounter.expires_at) <= Date.now()) throw new Error("EXPEDITION_ENCOUNTER_EXPIRED");

  const resolution = resolveTeamTurn(
    encounter.state,
    action,
    key,
    itemId,
    switchToSlot,
  );
  const run = await loadRun(ownerId, encounter.run_id);
  const next = nextNodeIds(run.zone_map, encounter.node_id);
  const checkpoint = (
    resolution.state.status === "won" &&
    encounter.kind !== "boss" &&
    run.zone < 3 &&
    run.nodes_completed === 3 &&
    next.length === 0
  );
  const chapterComplete = resolution.state.status === "won" && encounter.kind === "boss";
  const retrySeed = crypto.randomUUID();
  const version = await loadVersion(run.chapter_version_id);
  const retryMap = ["lost", "draw"].includes(resolution.state.status)
    ? generateZoneMap(
      validateChapterManifest(version.manifest),
      run.zone,
      run.zone_attempt + 1,
      retrySeed,
    )
    : {};
  const { data, error } = await db.rpc("commit_expedition_turn", {
    p_owner: ownerId,
    p_encounter_id: encounter.id,
    p_expected_turn: expectedTurn,
    p_expected_version: expectedVersion,
    p_key: key,
    p_action: action,
    p_switch_to_slot: switchToSlot,
    p_item_id: itemId || null,
    p_state: resolution.state,
    p_events: resolution.events,
    p_bot_action: resolution.bot_action,
    p_next_node_ids: next,
    p_checkpoint: checkpoint,
    p_chapter_complete: chapterComplete,
    p_retry_map: retryMap,
    p_retry_seed: retrySeed,
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt(data));
}

async function forfeit(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const encounter = await loadEncounter(ownerId, asUuid(body.encounter_id, "encounter_id"));
  const run = await loadRun(ownerId, encounter.run_id);
  const version = await loadVersion(run.chapter_version_id);
  const seed = crypto.randomUUID();
  const retryMap = generateZoneMap(
    validateChapterManifest(version.manifest),
    run.zone,
    run.zone_attempt + 1,
    seed,
  );
  const { data, error } = await db.rpc("forfeit_expedition_encounter", {
    p_owner: ownerId,
    p_encounter_id: encounter.id,
    p_retry_map: retryMap,
    p_retry_seed: seed,
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt(data));
}

async function abandon(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const { data, error } = await db.rpc("abandon_expedition_run", {
    p_owner: ownerId,
    p_run_id: asUuid(body.run_id, "run_id"),
    p_key: asKey(body.idempotency_key),
  });
  if (error) throw error;
  return json(200, await withFreshExpeditionArt({ run: data }));
}

async function listTrophies(ownerId: string): Promise<Response> {
  const [{ data: owned, error: ownedError }, { data: featured, error: featuredError }] =
    await Promise.all([
      db
        .from("seeker_trophies")
        .select("earned_at, expedition_trophies(*)")
        .eq("owner_id", ownerId)
        .order("earned_at"),
      db
        .from("seeker_featured_trophies")
        .select("slot, expedition_trophies(*)")
        .eq("owner_id", ownerId)
        .order("slot"),
    ]);
  if (ownedError) throw ownedError;
  if (featuredError) throw featuredError;
  return json(200, {
    trophies: withPublicAssets(owned ?? []),
    featured: withPublicAssets(featured ?? []),
    asset_base_url: chapterAssetBaseUrl(),
  });
}

async function featureTrophies(ownerId: string, body: ExpeditionBody): Promise<Response> {
  const ids = asUuidArray(body.trophy_ids ?? [], "trophy_ids", null, 3);
  const { data, error } = await db.rpc("set_featured_trophies", {
    p_owner: ownerId,
    p_trophy_ids: ids,
  });
  if (error) throw error;
  return json(200, {
    featured: withPublicAssets(Array.isArray(data) ? data : []),
    asset_base_url: chapterAssetBaseUrl(),
  });
}

async function loadTeam(ownerId: string, teamId: string): Promise<TeamRow> {
  const { data, error } = await db
    .from("anima_teams")
    .select(TEAM_FIELDS)
    .eq("id", teamId)
    .eq("owner_id", ownerId)
    .eq("kind", "expedition")
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("TEAM_NOT_FOUND");
  const team = data as unknown as TeamRow;
  if ((team.anima_team_members ?? []).length !== 4) throw new Error("TEAM_REQUIRES_FOUR");
  return team;
}

async function syncTeamCare(ownerId: string, team: TeamRow): Promise<void> {
  await Promise.all((team.anima_team_members ?? []).map(async (member) => {
    const animaId = String(member.animas.id ?? "");
    if (!UUID_RE.test(animaId)) throw new Error("TEAM_MEMBER_UNAVAILABLE");
    const { error } = await db.rpc("apply_care", {
      p_owner: ownerId,
      p_anima_id: animaId,
      p_action: "sync",
      p_key: null,
      p_item_id: null,
    });
    if (error) throw error;
  }));
}

function teamSnapshot(team: TeamRow): Record<string, unknown>[] {
  return teamSnapshotFromMembers(team.anima_team_members ?? [], true) as Record<string, unknown>[];
}

async function loadRun(ownerId: string, runId: string): Promise<RunRow> {
  const { data, error } = await db
    .from("expedition_runs")
    .select("*")
    .eq("id", runId)
    .eq("owner_id", ownerId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("EXPEDITION_RUN_NOT_FOUND");
  return data as unknown as RunRow;
}

async function loadEncounter(ownerId: string, encounterId: string): Promise<EncounterRow> {
  const { data, error } = await db
    .from("expedition_encounters")
    .select("*")
    .eq("id", encounterId)
    .eq("owner_id", ownerId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("EXPEDITION_ENCOUNTER_NOT_FOUND");
  return data as unknown as EncounterRow;
}

async function loadActiveEncounter(
  ownerId: string,
  runId: string,
  required: boolean,
): Promise<EncounterRow | null> {
  const { data, error } = await db
    .from("expedition_encounters")
    .select("*")
    .eq("owner_id", ownerId)
    .eq("run_id", runId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  if (!data && required) throw new Error("EXPEDITION_ENCOUNTER_NOT_FOUND");
  return data as unknown as EncounterRow | null;
}

const versionMemo = new Map<string, VersionRow>();

async function loadVersion(versionId: string): Promise<VersionRow> {
  const cached = versionMemo.get(versionId);
  if (cached) return cached;
  const { data, error } = await db
    .from("expedition_chapter_versions")
    .select("id, chapter_id, asset_prefix, manifest, minimum_build")
    .eq("id", versionId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("CHAPTER_NOT_AVAILABLE");
  const row = data as unknown as VersionRow;
  versionMemo.set(versionId, row);
  return row;
}

async function withFreshExpeditionArt(value: unknown): Promise<unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const response = { ...(value as Record<string, unknown>) };
  if (response.run && typeof response.run === "object") {
    const run = { ...(response.run as Record<string, unknown>) };
    if (Array.isArray(run.party_state) && run.party_state.length > 0) {
      run.party_state = await withSignedRoster(db, run.party_state);
    }
    response.run = run;
  }
  if (response.encounter && typeof response.encounter === "object") {
    const encounter = { ...(response.encounter as Record<string, unknown>) };
    encounter.player_snapshot = await withSignedRoster(db, encounter.player_snapshot);
    encounter.opponent_snapshot = await withSignedRoster(db, encounter.opponent_snapshot);
    response.encounter = encounter;
  }
  const runRecord = response.run as Record<string, unknown> | undefined;
  const map = runRecord && typeof runRecord.zone_map === "object" && runRecord.zone_map
    ? runRecord.zone_map as Record<string, unknown>
    : null;
  const backgroundPath = typeof map?.background_path === "string" ? map.background_path : "";
  if (runRecord && backgroundPath && !backgroundPath.includes("..")) {
    const arenaUrl = chapterAssetUrl(backgroundPath);
    runRecord.arena_background_url = arenaUrl;
    if (response.encounter && typeof response.encounter === "object") {
      (response.encounter as Record<string, unknown>).arena_background_url = arenaUrl;
    }
  }
  const versionId = typeof runRecord?.chapter_version_id === "string"
    ? runRecord.chapter_version_id
    : "";
  if (versionId) {
    const version = await loadVersion(versionId);
    const seeker = publicBossSeeker(version.manifest);
    if (seeker) {
      const signed = withPublicAssets(seeker) as Record<string, unknown>;
      runRecord.boss_seeker = signed;
      if (response.encounter && typeof response.encounter === "object") {
        const encounter = response.encounter as Record<string, unknown>;
        encounter.boss_seeker = signed;
        encounter.zone_attempt = runRecord.zone_attempt ?? encounter.zone_attempt ?? 1;
      }
    }
  }
  const assetBase = chapterAssetBaseUrl();
  if (runRecord) runRecord.asset_base_url = assetBase;
  response.asset_base_url = assetBase;
  return response;
}

function chapterRoster(value: unknown, assetPrefix: string): Record<string, unknown>[] {
  const roster = asSnapshotArray(value) as Record<string, unknown>[] | null;
  if (!roster) throw new Error("INVALID_TEAM_SNAPSHOT");
  return roster.map((raw) => {
    const member = { ...raw };
    const path = typeof member.sheet_path === "string" ? member.sheet_path : "";
    if (!path.startsWith(assetPrefix) || path.includes("..")) throw new Error("TEAM_ART_NOT_READY");
    member.system_asset = "chapter";
    member.sheet_url = chapterAssetUrl(path);
    return member;
  });
}

function withManifestAssetUrls(
  manifest: Record<string, unknown>,
  assetPrefix: string,
): Record<string, unknown> {
  const result = structuredClone(manifest);
  if (Array.isArray(result.opponents)) {
    result.opponents = result.opponents.map((opponent) => ({
      ...opponent,
      roster: chapterRoster(opponent.roster, assetPrefix),
    }));
  }
  return withPublicAssets(result) as Record<string, unknown>;
}

function withPublicAssets(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(withPublicAssets);
  if (!value || typeof value !== "object") return value;
  const result: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    result[key] = withPublicAssets(child);
  }
  for (const field of ["art_path", "portrait_path", "background_path", "sheet_path"]) {
    if (typeof result[field] === "string" && !String(result[field]).includes("..")) {
      result[field.replace(/_path$/, "_url")] = chapterAssetUrl(String(result[field]));
    }
  }
  return result;
}

function stripPrivateTeamArt(value: unknown): unknown {
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

function chapterAssetBaseUrl(): string {
  return `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/chapter_assets/`;
}

function chapterAssetUrl(path: string): string {
  return `${chapterAssetBaseUrl()}${path.split("/").map(encodeURIComponent).join("/")}`;
}

function chapterBuildError(
  req: Request,
  minimumBuild: Record<string, unknown>,
): Response | null {
  const minimums = {
    android: Math.max(0, Number(minimumBuild?.android) || 0),
    ios: Math.max(0, Number(minimumBuild?.ios) || 0),
    desktop: Math.max(0, Number(minimumBuild?.desktop) || 0),
  };
  if (Math.max(...Object.values(minimums)) <= 0) return null;
  const platform = (req.headers.get("x-scanima-platform") ?? "").toLowerCase();
  const build = Number(req.headers.get("x-scanima-build") ?? "");
  if (
    !(platform in minimums) ||
    !Number.isInteger(build) ||
    build < minimums[platform as keyof typeof minimums]
  ) {
    return json(426, {
      error: "CHAPTER_REQUIRES_UPDATE",
      minimum_build: minimums,
    });
  }
  return null;
}

async function expeditionEnabled(): Promise<boolean> {
  const now = Date.now();
  if (now < featureCacheUntil) return featureCache;
  const { data, error } = await db
    .from("app_config")
    .select("value")
    .eq("key", "feature_expedition")
    .maybeSingle();
  if (error) throw error;
  featureCache = data?.value === true;
  featureCacheUntil = now + 30_000;
  return featureCache;
}

function asUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function asUuidArray(
  value: unknown,
  field: string,
  exactLength: number | null,
  maximumLength = exactLength ?? 0,
): string[] {
  if (
    !Array.isArray(value) ||
    (exactLength !== null && value.length !== exactLength) ||
    (exactLength === null && value.length > maximumLength)
  ) throw new Error(`INVALID_${field.toUpperCase()}`);
  const ids = value.map((entry) => asUuid(entry, field));
  if (new Set(ids).size !== ids.length) throw new Error(`INVALID_${field.toUpperCase()}`);
  return ids;
}

function asKey(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 128) {
    throw new Error("INVALID_IDEMPOTENCY_KEY");
  }
  return value;
}

function asPositiveInteger(value: unknown, field: string): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1) throw new Error(`INVALID_${field.toUpperCase()}`);
  return number;
}

function asSlot(value: unknown, field: string): number {
  const slot = Number(value);
  if (!Number.isInteger(slot) || slot < 0 || slot > 3) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return slot;
}

function asTextId(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^[a-zA-Z0-9][a-zA-Z0-9_-]{1,79}$/.test(value)) {
    throw new Error(`INVALID_${field.toUpperCase()}`);
  }
  return value;
}

function boundedInteger(value: unknown, minimum: number, maximum: number, fallback: number): number {
  const number = Number(value);
  return Number.isInteger(number)
    ? Math.max(minimum, Math.min(maximum, number))
    : fallback;
}
