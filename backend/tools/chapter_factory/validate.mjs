import { validateChapterManifest, EXPEDITION_EFFECT_TYPES } from "../../supabase/functions/_shared/expedition.mjs";
import { normalizeElement, isRosterElement } from "../../supabase/functions/_shared/elements.mjs";
import { normalizeBaseStats } from "../../supabase/functions/_shared/battle.mjs";
import { LAYOUT_3X3 } from "../../supabase/functions/_shared/postprocess.mjs";
import {
  BOSS_SEEKER_POSES,
  DIALOGUE_TRIGGERS,
  IP_BLOCKLIST,
  SAFE_ID,
  SAFE_SLUG,
  SAFE_SPECIES_KEY,
} from "./constants.mjs";
import { CHAPTER_CORE_CHASSIS, CHAPTER_CORE_VESSEL } from "./core_vessel.mjs";
import { buildGameplayManifest } from "./context.mjs";
import { manifestHash } from "./manifest.mjs";

const STAT_KEYS = ["hp", "atk", "def", "spd", "special"];
const EFFECT_SET = new Set(EXPEDITION_EFFECT_TYPES);
const MOVE_NAME = /^[A-Z][a-z]+ [A-Z][a-z]+$/;
const SAFE_FILENAME = /^[a-z0-9][a-z0-9_-]{0,62}\.png$/;
const BODY_HEIGHT_MIN_CM = 20;
const BODY_HEIGHT_MAX_CM = 2000;
const ACE_PASSIVE_TYPES = new Set(["bonus_pp", "stat_boost", "one_hit_shield"]);
const ACE_PASSIVE_STATS = new Set(["atk", "def", "spd", "special"]);

export function scanIpTerms(value, path = "root") {
  const hits = [];
  if (typeof value === "string") {
    for (const pattern of IP_BLOCKLIST) {
      if (pattern.test(value)) hits.push({ path, term: pattern.source });
    }
    return hits;
  }
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      hits.push(...scanIpTerms(value[index], `${path}[${index}]`));
    }
    return hits;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      hits.push(...scanIpTerms(child, `${path}.${key}`));
    }
  }
  return hits;
}

function validationError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function assertSafeId(value, label) {
  if (typeof value !== "string" || !SAFE_ID.test(value)) {
    throw validationError("INVALID_DESIGN_ID", `${label}: id tidak aman`);
  }
}

function assertMoveName(value, label) {
  if (typeof value !== "string" || !MOVE_NAME.test(value.trim())) {
    throw validationError("INVALID_MOVE_NAME", `${label}: strike/surge harus dua kata Title Case`);
  }
}

function assertBodyHeight(value, label) {
  const height = Number(value);
  if (!Number.isInteger(height) || height < BODY_HEIGHT_MIN_CM || height > BODY_HEIGHT_MAX_CM) {
    throw validationError(
      "INVALID_BODY_HEIGHT",
      `${label}: body_height_cm harus integer ${BODY_HEIGHT_MIN_CM}-${BODY_HEIGHT_MAX_CM}`,
    );
  }
}

function assertAcePassive(value, label) {
  if (!value || typeof value !== "object" || !ACE_PASSIVE_TYPES.has(value.type)) {
    throw validationError("INVALID_ACE_PASSIVE", `${label}: ace_passive type tidak didukung`);
  }
  if (
    typeof value.name !== "string"
    || value.name.trim().length < 2
    || typeof value.copy !== "string"
    || value.copy.trim().length < 2
  ) {
    throw validationError("INVALID_ACE_PASSIVE", `${label}: name/copy ace_passive wajib`);
  }
  if (
    value.type === "bonus_pp"
    && (!Number.isInteger(Number(value.value)) || Number(value.value) < 1 || Number(value.value) > 2)
  ) {
    throw validationError("INVALID_ACE_PASSIVE", `${label}: bonus_pp harus 1-2`);
  }
  if (
    value.type === "stat_boost"
    && (
      !ACE_PASSIVE_STATS.has(value.stat)
      || !Number.isInteger(Number(value.value))
      || Number(value.value) < 1
      || Number(value.value) > 25
    )
  ) {
    throw validationError("INVALID_ACE_PASSIVE", `${label}: stat_boost harus stat valid dan 1-25%`);
  }
}

function castPower(member) {
  const stats = normalizeBaseStats(member?.base_stats);
  return STAT_KEYS.reduce((sum, key) => sum + Number(stats[key] ?? 0), 0);
}

export function validateBrief(brief) {
  if (!brief || typeof brief !== "object" || Array.isArray(brief)) {
    throw validationError("INVALID_BRIEF", "brief.json bukan object");
  }
  if (!SAFE_SLUG.test(String(brief.slug ?? ""))) {
    throw validationError("INVALID_BRIEF", "brief.slug tidak aman");
  }
  if (
    !Number.isInteger(Number(brief.sequence))
    || Number(brief.sequence) < 1
    || !Number.isInteger(Number(brief.content_version))
    || Number(brief.content_version) < 1
  ) {
    throw validationError("INVALID_BRIEF", "sequence/content_version harus integer positif");
  }
  for (const field of ["theme", "title", "description", "tone", "boss_seeker", "trophy"]) {
    if (typeof brief[field] !== "string" || brief[field].trim().length < 2) {
      throw validationError("INVALID_BRIEF", `brief.${field} wajib`);
    }
  }
  if (
    !Array.isArray(brief.zones)
    || brief.zones.length !== 3
    || brief.zones.some((zone) => typeof zone !== "string" || zone.trim().length < 2)
    || Number(brief.cast_count) !== 9
  ) {
    throw validationError("INVALID_BRIEF", "brief harus meminta tepat 3 zone dan 9 Anima");
  }
  const ipHits = scanIpTerms(brief);
  if (ipHits.length > 0) {
    throw validationError("IP_TERM_REJECTED", "brief memuat istilah IP terlarang");
  }
  return brief;
}

export function validateDesign(design, brief, ctx = null) {
  validateBrief(brief);
  if (!design || typeof design !== "object" || Array.isArray(design)) {
    throw validationError("INVALID_DESIGN", "design.json bukan object");
  }
  if (Number(design.schema_version) !== 1) {
    throw validationError("INVALID_DESIGN_SCHEMA", "schema_version harus 1");
  }
  const ipHits = scanIpTerms(design);
  if (ipHits.length > 0) {
    throw validationError(
      "IP_TERM_REJECTED",
      `Istilah IP terlarang: ${ipHits.map((hit) => `${hit.path}~${hit.term}`).join(", ")}`,
    );
  }
  if (!Array.isArray(design.cast) || design.cast.length !== 9) {
    throw validationError("INVALID_DESIGN_CAST", "cast harus tepat 9 Anima");
  }
  const castIds = new Set();
  const requireBodyHeight = Number(brief.content_version) >= 2;
  for (const [index, member] of design.cast.entries()) {
    assertSafeId(member?.id, `cast[${index}].id`);
    if (castIds.has(member.id)) {
      throw validationError("INVALID_DESIGN_CAST", `cast id duplikat: ${member.id}`);
    }
    castIds.add(member.id);
    if (typeof member.name !== "string" || member.name.length < 2) {
      throw validationError("INVALID_DESIGN_CAST", `${member.id}: name wajib`);
    }
    if (typeof member.species_key !== "string" || !SAFE_SPECIES_KEY.test(member.species_key)) {
      throw validationError("INVALID_DESIGN_CAST", `${member.id}: species_key tidak aman`);
    }
    if (!isRosterElement(normalizeElement(member.element, ""))) {
      throw validationError("INVALID_DESIGN_CAST", `${member.id}: element invalid`);
    }
    if (member.secondary_element && !isRosterElement(normalizeElement(member.secondary_element, ""))) {
      throw validationError("INVALID_DESIGN_CAST", `${member.id}: secondary_element invalid`);
    }
    assertMoveName(member.strike_name, `${member.id}.strike_name`);
    assertMoveName(member.surge_name, `${member.id}.surge_name`);
    const stats = normalizeBaseStats(member.base_stats);
    for (const key of STAT_KEYS) {
      const value = Number(stats[key]);
      if (!Number.isFinite(value) || value < 1 || value > 999) {
        throw validationError("INVALID_DESIGN_CAST", `${member.id}: stat ${key} di luar batas`);
      }
    }
    if (requireBodyHeight) assertBodyHeight(member.body_height_cm, member.id);
  }
  const specialCount = design.cast.filter((entry) => entry.special === true).length;
  if (specialCount !== 1) {
    throw validationError("INVALID_DESIGN_CAST", "cast harus punya tepat 1 Anima special");
  }
  if (!Array.isArray(design.zones) || design.zones.length !== 3) {
    throw validationError("INVALID_DESIGN_ZONES", "zones harus tepat 3");
  }
  const zoneIds = new Set();
  const zoneIndexes = new Set();
  for (const zone of design.zones) {
    assertSafeId(zone?.id, "zone.id");
    if (zoneIds.has(zone.id)) throw validationError("INVALID_DESIGN_ZONES", `zone duplikat: ${zone.id}`);
    zoneIds.add(zone.id);
    const index = Number(zone.index);
    if (!Number.isInteger(index) || index < 1 || index > 3) {
      throw validationError("INVALID_DESIGN_ZONES", `${zone.id}: index harus 1–3`);
    }
    if (zoneIndexes.has(index)) {
      throw validationError("INVALID_DESIGN_ZONES", `zone index duplikat: ${index}`);
    }
    zoneIndexes.add(index);
    if (typeof zone.title_key !== "string" || zone.title_key.length < 3) {
      throw validationError("INVALID_DESIGN_ZONES", `${zone.id}: title_key wajib`);
    }
  }
  if (!Array.isArray(design.opponents) || design.opponents.length < 4) {
    throw validationError("INVALID_DESIGN_OPPONENTS", "opponents minimal 4");
  }
  const opponentIds = new Set();
  for (const opponent of design.opponents) {
    assertSafeId(opponent?.id, "opponent.id");
    if (opponentIds.has(opponent.id)) {
      throw validationError("INVALID_DESIGN_OPPONENTS", `opponent duplikat: ${opponent.id}`);
    }
    opponentIds.add(opponent.id);
    if (!Array.isArray(opponent.roster) || opponent.roster.length < 1 || opponent.roster.length > 4) {
      throw validationError("INVALID_DESIGN_OPPONENTS", `${opponent.id}: roster 1–4`);
    }
    if (new Set(opponent.roster).size !== opponent.roster.length) {
      throw validationError("INVALID_DESIGN_OPPONENTS", `${opponent.id}: roster tidak boleh duplikat`);
    }
    for (const animaId of opponent.roster) {
      if (!castIds.has(animaId)) {
        throw validationError("INVALID_DESIGN_OPPONENTS", `${opponent.id}: roster memakai ${animaId} tidak ada di cast`);
      }
    }
  }
  if (!design.boss || !opponentIds.has(design.boss.opponent_id)) {
    throw validationError("INVALID_DESIGN_BOSS", "boss.opponent_id harus merujuk opponent valid");
  }
  const bossOpponent = design.opponents.find((entry) => entry.id === design.boss.opponent_id);
  if (!bossOpponent || bossOpponent.roster.length !== 4) {
    throw validationError("INVALID_DESIGN_BOSS", "boss roster harus 4 Anima");
  }
  const bossSpecials = bossOpponent.roster.filter((id) => design.cast.find((c) => c.id === id)?.special);
  if (bossSpecials.length !== 1) {
    throw validationError("INVALID_DESIGN_BOSS", "boss roster harus punya tepat 1 Anima special");
  }
  const bossRegulars = bossOpponent.roster.filter((id) => !design.cast.find((c) => c.id === id)?.special);
  if (bossRegulars.length !== 3) {
    throw validationError("INVALID_DESIGN_BOSS", "boss roster harus punya tepat 3 Anima reguler");
  }
  const ace = design.cast.find((entry) => entry.id === bossSpecials[0]);
  const regularPower = Math.max(
    ...bossRegulars.map((id) => castPower(design.cast.find((entry) => entry.id === id))),
  );
  if (castPower(ace) < regularPower) {
    throw validationError("INVALID_DESIGN_BOSS", "Anima special tidak boleh lebih lemah dari reguler");
  }
  if (Number(brief.content_version) >= 2) assertAcePassive(design.boss.ace_passive, "boss");
  for (const zone of design.zones) {
    if (!opponentIds.has(zone.battle_opponent_id) || !opponentIds.has(zone.elite_opponent_id)) {
      throw validationError("INVALID_DESIGN_ZONES", `${zone.id}: opponent zone tidak valid`);
    }
  }
  const seeker = design.boss_seeker;
  if (!seeker || typeof seeker !== "object") {
    throw validationError("INVALID_DESIGN_BOSS_SEEKER", "boss_seeker wajib");
  }
  assertSafeId(seeker.id, "boss_seeker.id");
  if (typeof seeker.display_name !== "string" || seeker.display_name.length < 2) {
    throw validationError("INVALID_DESIGN_BOSS_SEEKER", "boss_seeker.display_name wajib");
  }
  if (
    typeof seeker.background_story !== "string" ||
    seeker.background_story.length < 40 ||
    seeker.background_story.length > 600
  ) {
    throw validationError(
      "INVALID_DESIGN_BOSS_SEEKER",
      "boss_seeker.background_story wajib 40-600 karakter",
    );
  }
  if (
    typeof seeker.visual_direction !== "string" ||
    seeker.visual_direction.length < 40 ||
    seeker.visual_direction.length > 1200
  ) {
    throw validationError(
      "INVALID_DESIGN_BOSS_SEEKER",
      "boss_seeker.visual_direction wajib 40-1200 karakter",
    );
  }
  if (!SAFE_FILENAME.test(seeker.sheet_filename ?? "")) {
    throw validationError("INVALID_DESIGN_BOSS_SEEKER", "boss_seeker.sheet_filename tidak aman");
  }
  if (requireBodyHeight) assertBodyHeight(seeker.body_height_cm, "boss_seeker");
  if (!BOSS_SEEKER_POSES.includes(seeker.portrait_pose)) {
    throw validationError("INVALID_DESIGN_BOSS_SEEKER", "portrait_pose harus pose Boss Seeker valid");
  }
  if (!seeker.dialogue || typeof seeker.dialogue !== "object") {
    throw validationError("INVALID_DESIGN_DIALOGUE", "boss_seeker.dialogue wajib");
  }
  for (const trigger of DIALOGUE_TRIGGERS) {
    if (typeof seeker.dialogue[trigger] !== "string" || seeker.dialogue[trigger].length < 1) {
      throw validationError("INVALID_DESIGN_DIALOGUE", `dialogue.${trigger} wajib`);
    }
  }
  const trophy = design.trophy;
  if (!trophy || typeof trophy !== "object") {
    throw validationError("INVALID_DESIGN_TROPHY", "trophy wajib");
  }
  assertSafeId(trophy.slug, "trophy.slug");
  if (typeof trophy.display_name !== "string" || !trophy.display_name.endsWith(" Core")) {
    throw validationError("INVALID_DESIGN_TROPHY", "trophy.display_name harus berakhir dengan Core");
  }
  if (trophy.metadata?.chassis !== CHAPTER_CORE_CHASSIS) {
    throw validationError(
      "INVALID_DESIGN_TROPHY",
      `trophy.metadata.chassis harus ${CHAPTER_CORE_CHASSIS}`,
    );
  }
  if (trophy.metadata?.vessel !== CHAPTER_CORE_VESSEL) {
    throw validationError(
      "INVALID_DESIGN_TROPHY",
      `trophy.metadata.vessel harus ${CHAPTER_CORE_VESSEL}`,
    );
  }
  if (
    !Array.isArray(trophy.metadata?.palette) ||
    trophy.metadata.palette.length < 4 ||
    trophy.metadata.palette.length > 5 ||
    trophy.metadata.palette.some((color) => typeof color !== "string" || color.length < 2)
  ) {
    throw validationError("INVALID_DESIGN_TROPHY", "trophy.metadata.palette wajib 4-5 warna");
  }
  if (
    typeof trophy.metadata?.silhouette_motif !== "string" ||
    trophy.metadata.silhouette_motif.length < 20 ||
    trophy.metadata.silhouette_motif.length > 300
  ) {
    throw validationError(
      "INVALID_DESIGN_TROPHY",
      "trophy.metadata.silhouette_motif wajib 20-300 karakter",
    );
  }
  if (
    typeof trophy.metadata?.core_motif !== "string" ||
    trophy.metadata.core_motif.length < 10 ||
    trophy.metadata.core_motif.length > 240
  ) {
    throw validationError("INVALID_DESIGN_TROPHY", "trophy.metadata.core_motif wajib 10-240 karakter");
  }
  if (!SAFE_FILENAME.test(trophy.filename ?? "")) {
    throw validationError("INVALID_DESIGN_TROPHY", "trophy.filename tidak aman");
  }
  if (brief?.slug && !trophy.slug.startsWith(String(brief.slug))) {
    throw validationError("INVALID_DESIGN_TROPHY", "trophy.slug harus memakai prefix chapter slug");
  }
  if (!design.summary?.title || !design.summary?.description) {
    throw validationError("INVALID_DESIGN_SUMMARY", "summary.title/description wajib");
  }
  // Gameplay manifest derived from design must pass expedition rules (effects, zones, etc.)
  if (ctx) {
    const gameplay = buildGameplayManifest(ctx);
    validateChapterManifest(gameplay);
    validateEffectAllowlist(gameplay);
  }
  return design;
}

function validateEffectAllowlist(manifest) {
  for (const zone of manifest.zones) {
    for (const [poolKind, pools] of Object.entries(zone.node_pools ?? {})) {
      if (!Array.isArray(pools)) continue;
      for (const pool of pools) {
        for (const option of pool.options ?? []) {
          const effect = option.effect;
          if (!effect || !EFFECT_SET.has(effect.type)) {
            throw validationError("INVALID_EFFECT", `${zone.id}/${poolKind}: effect type tidak di allowlist`);
          }
        }
      }
    }
  }
}

export function validateAnimaManifest(manifest, label) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw validationError("INVALID_ANIMA_MANIFEST", `${label}: manifest bukan object`);
  }
  if (Number(manifest.version) !== 1) {
    throw validationError("INVALID_ANIMA_MANIFEST", `${label}: version harus 1`);
  }
  const poses = manifest.poses;
  if (!poses || typeof poses !== "object") {
    throw validationError("INVALID_ANIMA_MANIFEST", `${label}: poses wajib ada`);
  }
  for (const required of LAYOUT_3X3.poses) {
    const region = poses[required]?.region;
    if (!Array.isArray(region) || region.length !== 4) {
      throw validationError("INVALID_ANIMA_MANIFEST", `${label}: pose ${required} region invalid`);
    }
  }
  const frame = manifest.frame_size;
  const sheet = manifest.sheet_size;
  if (!Array.isArray(frame) || frame.length !== 2 || !Array.isArray(sheet) || sheet.length !== 2) {
    throw validationError("INVALID_ANIMA_MANIFEST", `${label}: sheet/frame size invalid`);
  }
  if (frame.some((value) => !Number.isInteger(value) || value <= 0)) {
    throw validationError("INVALID_ANIMA_MANIFEST", `${label}: frame size invalid`);
  }
  if (
    manifest.render_metrics != null
    && (!Number.isInteger(Number(manifest.render_metrics.reference_height_px))
      || Number(manifest.render_metrics.reference_height_px) <= 0)
  ) {
    throw validationError("INVALID_ANIMA_MANIFEST", `${label}: render_metrics.reference_height_px invalid`);
  }
  for (const required of LAYOUT_3X3.poses) {
    const region = poses[required].region;
    if (region[2] !== frame[0] || region[3] !== frame[1]) {
      throw validationError(
        "INVALID_ANIMA_MANIFEST",
        `${label}: pose ${required} harus sama dengan frame_size`,
      );
    }
  }
}

export function validateBossSeekerManifest(manifest) {
  if (!manifest || typeof manifest !== "object") {
    throw validationError("INVALID_BOSS_MANIFEST", "boss seeker manifest invalid");
  }
  for (const pose of BOSS_SEEKER_POSES) {
    const region = manifest.poses?.[pose]?.region;
    if (!Array.isArray(region) || region.length !== 4) {
      throw validationError("INVALID_BOSS_MANIFEST", `pose ${pose} region invalid`);
    }
  }
  if (
    manifest.render_metrics != null
    && (!Number.isInteger(Number(manifest.render_metrics.reference_height_px))
      || Number(manifest.render_metrics.reference_height_px) <= 0)
  ) {
    throw validationError("INVALID_BOSS_MANIFEST", "boss seeker reference_height_px invalid");
  }
}

export function validateRosterMember(member, label) {
  if (!member || typeof member !== "object") {
    throw validationError("INVALID_ROSTER", `${label}: member invalid`);
  }
  if (!isRosterElement(normalizeElement(member.element, ""))) {
    throw validationError("INVALID_ROSTER", `${label}: element invalid`);
  }
  if (member.secondary_element && !isRosterElement(normalizeElement(member.secondary_element, ""))) {
    throw validationError("INVALID_ROSTER", `${label}: secondary element invalid`);
  }
  const stats = normalizeBaseStats(member.base_stats);
  for (const key of STAT_KEYS) {
    const value = Number(stats[key]);
    if (!Number.isFinite(value) || value < 1 || value > 999) {
      throw validationError("INVALID_ROSTER", `${label}: stat ${key} di luar batas`);
    }
  }
  if (!member.sheet_path || typeof member.sheet_path !== "string") {
    throw validationError("INVALID_ROSTER", `${label}: sheet_path wajib`);
  }
  if (!member.manifest) {
    throw validationError("INVALID_ROSTER", `${label}: manifest wajib`);
  }
  validateAnimaManifest(member.manifest, label);
}

export function validateChapterDraft(manifest, ctx) {
  if (!ctx) throw validationError("INVALID_CONTEXT", "chapter context wajib");
  validateDesign(ctx.design, ctx.brief, ctx);
  const ipHits = scanIpTerms(manifest);
  if (ipHits.length > 0) {
    throw validationError(
      "IP_TERM_REJECTED",
      `Istilah IP terlarang: ${ipHits.map((hit) => `${hit.path}~${hit.term}`).join(", ")}`,
    );
  }
  validateChapterManifest(manifest);
  validateEffectAllowlist(manifest);
  if (!manifest.summary?.title || typeof manifest.summary.title !== "string") {
    throw validationError("INVALID_CHAPTER_SUMMARY", "summary.title wajib");
  }
  if (!manifest.summary?.description || typeof manifest.summary.description !== "string") {
    throw validationError("INVALID_CHAPTER_SUMMARY", "summary.description wajib");
  }
  if (
    Number(manifest.sequence) !== ctx.sequence
    || Number(manifest.content_version) !== ctx.contentVersion
    || manifest.factory?.slug !== ctx.slug
    || manifest.assets?.prefix !== ctx.assetPrefix
  ) {
    throw validationError("INVALID_CHAPTER_IDENTITY", "slug/sequence/version/prefix tidak cocok brief");
  }
  if (!["procedural", "mixed", "production"].includes(manifest.factory?.mode)) {
    throw validationError("INVALID_CHAPTER_IDENTITY", "factory.mode tidak valid");
  }
  if (!manifest.boss_seeker?.sheet_path) {
    throw validationError("INVALID_BOSS_SEEKER", "boss_seeker.sheet_path wajib");
  }
  validateBossSeekerManifest(manifest.boss_seeker.manifest);
  const requireBodyHeight = Number(manifest.content_version) >= 2;
  if (requireBodyHeight) {
    assertBodyHeight(manifest.boss_seeker.body_height_cm, "boss_seeker");
    if (!manifest.boss_seeker.manifest?.render_metrics?.reference_height_px) {
      throw validationError("INVALID_BOSS_MANIFEST", "boss seeker render_metrics wajib");
    }
  }
  const dialogue = manifest.boss_seeker.dialogue;
  if (!dialogue || typeof dialogue !== "object") {
    throw validationError("INVALID_BOSS_DIALOGUE", "boss_seeker.dialogue wajib");
  }
  for (const trigger of DIALOGUE_TRIGGERS) {
    if (typeof dialogue[trigger] !== "string" || dialogue[trigger].length < 1) {
      throw validationError("INVALID_BOSS_DIALOGUE", `dialogue.${trigger} wajib`);
    }
  }
  if (!manifest.trophy?.art_path || !manifest.trophy?.slug) {
    throw validationError("INVALID_TROPHY", "trophy metadata wajib");
  }
  for (const opponent of manifest.opponents) {
    for (const [index, member] of opponent.roster.entries()) {
      validateRosterMember(member, `${opponent.id}[${index}]`);
      if (requireBodyHeight) {
        assertBodyHeight(member.body_height_cm, `${opponent.id}[${index}]`);
        if (!member.manifest?.render_metrics?.reference_height_px) {
          throw validationError("INVALID_ANIMA_MANIFEST", `${opponent.id}[${index}]: render_metrics wajib`);
        }
      }
    }
  }
  const boss = manifest.opponents.find((entry) => entry.id === manifest.boss.opponent_id);
  if (!boss || boss.roster.length !== 4) {
    throw validationError("INVALID_BOSS_ROSTER", "boss roster harus 4 Anima");
  }
  const specials = boss.roster.filter((member) => member.special === true);
  if (specials.length !== 1) {
    throw validationError("INVALID_BOSS_ROSTER", "boss roster harus punya tepat 1 Anima special");
  }
  const regulars = boss.roster.filter((member) => member.special !== true);
  if (castPower(specials[0]) < Math.max(...regulars.map(castPower))) {
    throw validationError("INVALID_BOSS_ROSTER", "Anima special tidak boleh lebih lemah dari reguler");
  }
  if (requireBodyHeight) assertAcePassive(manifest.boss.ace_passive, "boss");
  for (const zone of manifest.zones) {
    if (!zone.background_path?.startsWith(ctx.assetPrefix)) {
      throw validationError("INVALID_ZONE_ART", `${zone.id} background_path tidak cocok prefix`);
    }
  }
  const expectedAssetCount = ctx.design.cast.length + ctx.design.zones.length + 2;
  if (!Array.isArray(manifest.assets?.entries) || manifest.assets.entries.length !== expectedAssetCount) {
    throw validationError("INVALID_ASSET_LEDGER", "asset ledger tidak lengkap");
  }
  const expectedKinds = {
    anima_sheet: ctx.design.cast.length,
    zone_art: ctx.design.zones.length,
    boss_seeker_sheet: 1,
    trophy_art: 1,
  };
  const seenPaths = new Set();
  const kindCounts = {};
  for (const entry of manifest.assets.entries) {
    const expectedPrefix = entry?.kind === "trophy_art" ? ctx.trophyPrefix : ctx.assetPrefix;
    if (
      !entry
      || typeof entry.path !== "string"
      || !entry.path.startsWith(expectedPrefix)
      || entry.path.includes("..")
      || seenPaths.has(entry.path)
      || !/^[0-9a-f]{64}$/.test(String(entry.sha256 ?? ""))
    ) {
      throw validationError("INVALID_ASSET_LEDGER", "path/hash asset tidak aman atau duplikat");
    }
    seenPaths.add(entry.path);
    kindCounts[entry.kind] = (kindCounts[entry.kind] ?? 0) + 1;
  }
  for (const [kind, count] of Object.entries(expectedKinds)) {
    if (kindCounts[kind] !== count) {
      throw validationError("INVALID_ASSET_LEDGER", `jumlah ${kind} harus ${count}`);
    }
  }
  if (
    !seenPaths.has(manifest.boss_seeker.sheet_path)
    || !seenPaths.has(manifest.trophy.art_path)
    || manifest.zones.some((zone) => !seenPaths.has(zone.background_path))
    || manifest.opponents.some((opponent) =>
      opponent.roster.some((member) => !seenPaths.has(member.sheet_path))
    )
  ) {
    throw validationError("INVALID_ASSET_LEDGER", "referensi asset tidak tercatat di ledger");
  }
  if (manifest.manifest_hash) {
    const computed = manifestHash(manifest);
    if (computed !== manifest.manifest_hash) {
      throw validationError("MANIFEST_HASH_MISMATCH", "manifest_hash tidak cocok isi manifest");
    }
  }
  return manifest;
}
