import {
  deriveCuratedHybridSpeciesName,
} from "../backend/supabase/functions/_shared/vision.mjs";

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

const syllables = new Map();
const cadence = new Map();
const tails = new Map();
const names = [];
for (let index = 0; index < 400; index += 1) {
  const sample = structuredClone(base);
  sample.species_key = `dist_${index}`;
  sample.creature_brief = `${base.creature_brief} ${index}`;
  const derived = deriveCuratedHybridSpeciesName(sample);
  const name = derived.suggested_name;
  names.push(name);
  const count = (name.toLowerCase().match(/[aeiouy]+/g) ?? []).length;
  syllables.set(count, (syllables.get(count) ?? 0) + 1);
  const family = derived.selected_name_root.cadence_family;
  cadence.set(family, (cadence.get(family) ?? 0) + 1);
  const tail = name.slice(-3).toLowerCase();
  tails.set(tail, (tails.get(tail) ?? 0) + 1);
}

const top = [...tails.entries()].sort((a, b) => b[1] - a[1]);
console.log("suku kata:", [...syllables.entries()].sort());
console.log("cadence:", [...cadence.entries()].sort());
console.log("ekor terpadat:", top.slice(0, 5));
console.log("nama unik:", new Set(names).size, "dari", names.length);
console.log("contoh:", [...new Set(names)].slice(0, 24).join(", "));
