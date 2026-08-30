import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { normalizeElement } from "../../supabase/functions/_shared/elements.mjs";
import { normalizeBaseStats } from "../../supabase/functions/_shared/battle.mjs";
import { BOSS_SEEKER_POSES, DEFAULT_CHAPTER_REL, DIALOGUE_TRIGGERS } from "./constants.mjs";

export function defaultChapterDir(repoRoot) {
  return join(repoRoot, DEFAULT_CHAPTER_REL);
}

export async function loadBrief(chapterDir) {
  return JSON.parse(await readFile(join(chapterDir, "brief.json"), "utf8"));
}

export async function loadDesign(chapterDir) {
  return JSON.parse(await readFile(join(chapterDir, "design.json"), "utf8"));
}

export function createContext(chapterDir, brief, design) {
  const slug = String(brief.slug);
  const contentVersion = Number(brief.content_version);
  const assetSourceVersion = brief.asset_source_version == null
    ? contentVersion
    : Number(brief.asset_source_version);
  const sequence = Number(brief.sequence);
  const assetPrefix = `expeditions/${slug}/v${assetSourceVersion}/`;
  const trophyPrefix = `expeditions/${slug}/trophy/`;

  const cast = Array.isArray(design?.cast) ? design.cast : [];
  const zones = Array.isArray(design?.zones) ? design.zones : [];
  const castById = new Map(cast.map((entry) => [entry.id, entry]));

  return {
    chapterDir,
    brief,
    design,
    slug,
    contentVersion,
    assetSourceVersion,
    sequence,
    assetPrefix,
    trophyPrefix,
    mapSeed: String(design.map_seed ?? `${slug}-v${contentVersion}`),
    castById,
    animaStoragePath(id) {
      return `${assetPrefix}animas/${id}/sheet.png`;
    },
    zoneStoragePath(index) {
      return `${assetPrefix}zones/zone-${index}.png`;
    },
    bossStoragePath() {
      return `${assetPrefix}boss/${design.boss_seeker.sheet_filename}`;
    },
    trophyStoragePath() {
      return `${trophyPrefix}${design.trophy.filename}`;
    },
    bossLocalFilename() {
      return design.boss_seeker.sheet_filename;
    },
    trophyLocalFilename() {
      return design.trophy.filename;
    },
    storageToLocalRel(storagePath) {
      if (storagePath.startsWith(assetPrefix)) {
        return `assets/${storagePath.slice(assetPrefix.length)}`;
      }
      if (storagePath.startsWith(trophyPrefix)) {
        return `assets/trophy/${storagePath.slice(trophyPrefix.length)}`;
      }
      throw new Error(`ASSET_PATH_INVALID:${storagePath}`);
    },
    localAssetAbs(storagePath) {
      const rel = this.storageToLocalRel(storagePath);
      if (rel.includes("..")) throw new Error(`ASSET_PATH_UNSAFE:${storagePath}`);
      return join(chapterDir, rel);
    },
    imageSlots() {
      const slots = cast.map((entry) => `anima:${entry.id}`);
      for (const zone of zones) slots.push(`zone:${zone.index}`);
      slots.push("boss_seeker", "trophy");
      return Object.freeze(slots);
    },
    getCastMember(animaId) {
      const member = castById.get(animaId);
      if (!member) throw new Error(`ANIMA_CAST_MISSING:${animaId}`);
      return member;
    },
  };
}

export async function loadChapterContext(chapterDir) {
  const brief = await loadBrief(chapterDir);
  const design = await loadDesign(chapterDir);
  return createContext(chapterDir, brief, design);
}

function optionPools(zoneIndex) {
  const boost = zoneIndex === 1 ? 0.08 : zoneIndex === 2 ? 0.12 : 0.15;
  return {
    recovery: [{
      title_key: "EXPEDITION_RECOVERY",
      options: [{ id: "heal-party", effect: { type: "heal_party", ratio: 0.25 } }],
    }],
    cache: [{
      title_key: "EXPEDITION_CACHE",
      options: [{
        id: "power-up",
        effect: { type: "stat_boost", stat: "atk", value: boost },
      }],
    }],
    shop: [{
      title_key: "EXPEDITION_SHOP",
      options: [{
        id: "shop-heal",
        cost_supplies: 2,
        effect: { type: "heal_party", ratio: 0.25 },
      }],
    }],
    mystery: [{
      title_key: "EXPEDITION_MYSTERY",
      options: [{ id: "supply-cache", effect: { type: "supplies", value: 2 + zoneIndex } }],
    }],
  };
}

export function rosterMember(ctx, animaId, level = 12) {
  const source = ctx.getCastMember(animaId);
  const stats = normalizeBaseStats(source.base_stats);
  return {
    anima_id: source.id,
    species_key: source.species_key,
    color_bucket: source.color_bucket,
    stage: 2,
    level,
    ...(ctx.contentVersion >= 2 ? { body_height_cm: Number(source.body_height_cm || 120) } : {}),
    element: normalizeElement(source.element),
    secondary_element: normalizeElement(source.secondary_element, ""),
    base_stats: stats,
    hunger: 100,
    hygiene: 100,
    strike_name: source.strike_name,
    surge_name: source.surge_name,
    name: source.name,
    ...(source.special ? { special: true } : {}),
  };
}

export function buildGameplayManifest(ctx) {
  const { design, brief } = ctx;
  const zones = design.zones.map((zone) => ({
    id: zone.id,
    title_key: zone.title_key,
    ...(zone.bits_reward === undefined ? {} : { bits_reward: Number(zone.bits_reward) }),
    background_path: ctx.zoneStoragePath(zone.index),
    node_pools: {
      battle: [{ opponent_id: zone.battle_opponent_id, supplies_reward: zone.battle_supplies }],
      elite: [{ opponent_id: zone.elite_opponent_id, supplies_reward: zone.elite_supplies }],
      ...optionPools(zone.index),
    },
  }));
  const opponents = design.opponents.map((opponent) => ({
    id: opponent.id,
    title_key: opponent.title_key,
    roster: opponent.roster.map((animaId) => rosterMember(ctx, animaId, opponent.level ?? 12)),
  }));
  return {
    schema_version: 1,
    content_version: brief.content_version,
    sequence: brief.sequence,
    minimum_build: design.minimum_build ?? { android: 0, ios: 0, desktop: 0 },
    summary: design.summary,
    zones,
    opponents,
    boss: { ...design.boss },
    boss_seeker: {
      id: design.boss_seeker.id,
      display_name: design.boss_seeker.display_name,
      title_key: design.boss_seeker.title_key,
      sheet_path: ctx.bossStoragePath(),
      ...(ctx.contentVersion >= 2
        ? { body_height_cm: Number(design.boss_seeker.body_height_cm || 170) }
        : {}),
      portrait_pose: design.boss_seeker.portrait_pose ?? "profile",
      poses: BOSS_SEEKER_POSES,
      dialogue: design.boss_seeker.dialogue,
    },
    trophy: {
      slug: design.trophy.slug,
      display_name: design.trophy.display_name,
      description: design.trophy.description,
      art_path: ctx.trophyStoragePath(),
      metadata: {
        chapter_slug: brief.slug,
        ...(design.trophy.metadata ?? {}),
      },
    },
  };
}

export function chapterSequence(manifest, ctx) {
  const fromManifest = Number(manifest?.sequence ?? manifest?.factory?.sequence);
  if (Number.isInteger(fromManifest) && fromManifest >= 1) return fromManifest;
  return ctx?.sequence ?? Number(manifest?.content_version);
}
