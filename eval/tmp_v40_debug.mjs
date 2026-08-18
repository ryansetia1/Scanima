import { readFileSync } from "node:fs";

const src = readFileSync(
  "backend/supabase/functions/_shared/vision.mjs",
  "utf8",
);
const hash = src.match(/function nameHash[\s\S]*?\n}/)?.[0];
console.log(hash);

const mod = await import(
  "../backend/supabase/functions/_shared/vision.mjs"
);
const { deriveCuratedHybridSpeciesName } = mod;

const base = {
  subject_kind: "object",
  object_label: "running shoe",
  species_key: "shoe_mesh_runner",
  element: "air",
  secondary_element: null,
  creature_brief: "a sprinting mesh-shelled courier",
  signature_features: ["laced ridge", "waffle sole", "mesh flank"],
  stats: { hp: 40, atk: 45, def: 35, spd: 60, special: 30 },
  name_roots: [
    { root: "stride", channel: "motion", evidence: "long forward gait" },
    { root: "mesh", channel: "material", evidence: "woven upper" },
    { root: "arch", channel: "silhouette", evidence: "curved midsole" },
    { root: "eager", channel: "temperament", evidence: "leaning forward" },
    { root: "lattice", channel: "structure", evidence: "tread grid" },
    { root: "swift", channel: "motion", evidence: "raised heel" },
  ],
};

const anchors = new Set();
for (let index = 0; index < 12; index += 1) {
  const sample = structuredClone(base);
  sample.species_key = `dist_${index}`;
  const derived = deriveCuratedHybridSpeciesName(sample);
  anchors.add(derived.name_lineage_anchor);
  console.log(
    derived.name_lineage_anchor,
    "->",
    derived.suggested_name,
    derived.selected_name_root.cadence_family,
    derived.selected_name_root.structure_score,
  );
}
console.log("anchor unik:", [...anchors].join(" "));
