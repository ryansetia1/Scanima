import {
  levelFromExp,
  normalizeBaseStats,
  normalizeElement,
} from "./battle.mjs";

export function teamSnapshotFromMembers(
  members,
  includeName = true,
  minMembers = 4,
  maxMembers = minMembers,
) {
  if (
    !Array.isArray(members) ||
    members.length < minMembers ||
    members.length > maxMembers
  ) {
    throw new Error(
      minMembers === 4 && maxMembers === 4
        ? "TEAM_REQUIRES_FOUR"
        : "TEAM_REQUIRES_TWO_TO_FOUR",
    );
  }
  return [...members]
    .sort((left, right) => Number(left.slot) - Number(right.slot))
    .map((member) => snapshotAnima(member.animas ?? member, includeName));
}

export function snapshotAnima(row, includeName = true) {
  if (!row || typeof row !== "object") throw new Error("TEAM_MEMBER_UNAVAILABLE");
  if (!row.sheet_path || !row.manifest) throw new Error("TEAM_ART_NOT_READY");
  const result = {
    anima_id: String(row.id ?? row.anima_id ?? ""),
    species_key: String(row.species_key ?? ""),
    color_bucket: String(row.color_bucket ?? ""),
    stage: Number(row.stage) || 1,
    care_score: Math.max(0, Math.trunc(Number(row.care_score) || 0)),
    level: levelFromExp(row.care_score),
    element: normalizeElement(row.element),
    base_stats: normalizeBaseStats(row.base_stats),
    body_height_cm: Math.min(2000, Math.max(20, Math.trunc(Number(row.body_height_cm) || 120))),
    hunger: Number(row.care?.hunger ?? row.hunger ?? 100),
    hygiene: Number(row.care?.hygiene ?? row.hygiene ?? 100),
    strike_name: String(row.strike_name ?? ""),
    surge_name: String(row.surge_name ?? ""),
    evolution_version: Math.max(0, Math.trunc(Number(row.evolution_version ?? row.animas?.evolution_version) || 0)),
    strike_effect_id: String(row.strike_effect_id ?? row.animas?.strike_effect_id ?? ""),
    surge_effect_id: String(row.surge_effect_id ?? row.animas?.surge_effect_id ?? ""),
    sheet_path: String(row.sheet_path),
    manifest: row.manifest,
    name: includeName ? String(row.nickname ?? row.name ?? "Anima") : "Anima",
  };
  if (row.secondary_element) {
    const secondary = normalizeElement(row.secondary_element, "");
    if (secondary) result.secondary_element = secondary;
  }
  return result;
}

export function asSnapshotArray(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 4) return null;
  if (value.some((member) =>
    !member || typeof member !== "object" || Array.isArray(member) ||
    typeof member.anima_id !== "string"
  )) {
    return null;
  }
  return value;
}
