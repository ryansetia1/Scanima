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

export function atlasRosterSources(entries, teamSize, seed, maxSources = 24) {
  if (!Array.isArray(entries) || teamSize < 2 || teamSize > 4) return [];
  const pool = entries
    .filter((entry) =>
      entry && typeof entry === "object" &&
      typeof entry.source_id === "string" &&
      typeof entry.owner_id === "string" &&
      entry.snapshot && typeof entry.snapshot === "object"
    )
    .sort((left, right) =>
      stableRank(`${seed}:${left.source_id}`) -
      stableRank(`${seed}:${right.source_id}`)
    );
  if (pool.length < teamSize) return [];

  const rosters = [];
  const seen = new Set();
  for (let start = 0; start < pool.length && rosters.length < maxSources; start++) {
    const selected = [];
    const selectedIds = new Set();
    const owners = new Set();
    for (let offset = 0; offset < pool.length && selected.length < teamSize; offset++) {
      const entry = pool[(start + offset) % pool.length];
      if (selectedIds.has(entry.source_id) || owners.has(entry.owner_id)) continue;
      selected.push(entry);
      selectedIds.add(entry.source_id);
      owners.add(entry.owner_id);
    }
    for (let offset = 0; offset < pool.length && selected.length < teamSize; offset++) {
      const entry = pool[(start + offset) % pool.length];
      if (selectedIds.has(entry.source_id)) continue;
      selected.push(entry);
      selectedIds.add(entry.source_id);
    }
    if (selected.length !== teamSize) continue;
    const signature = selected.map((entry) => entry.source_id).sort().join(":");
    if (seen.has(signature)) continue;
    seen.add(signature);
    rosters.push({
      source_id: `atlas:${signature}`,
      snapshot: selected.map((entry) => entry.snapshot),
    });
  }
  return rosters;
}

function stableRank(value) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash = Math.imul(hash ^ value.charCodeAt(index), 16777619);
  }
  return hash >>> 0;
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
