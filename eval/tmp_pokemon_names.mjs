import { readFileSync } from "node:fs";
import {
  nameIsSafeForPlayers,
  NAME_STRUCTURE_FLOOR,
  nameStructureScore,
} from "../backend/supabase/functions/_shared/vision.mjs";

const res = await fetch(
  "https://pokeapi.co/api/v2/pokemon-species?limit=2000",
);
const { results } = await res.json();
const names = results.map((item) => item.name);

const words = new Set(
  readFileSync("/usr/share/dict/words", "utf8")
    .split("\n")
    .map((word) => word.trim().toLowerCase())
    .filter((word) => word.length >= 3),
);

const plain = (name) => name.replace(/[^a-z]/g, "");
const syllables = (name) => (plain(name).match(/[aeiouy]+/g) ?? []).length;

const exactWords = names.filter((name) => words.has(plain(name)));

// Kata kamus >=4 huruf yang muncul utuh di dalam nama: ini persis yang aturan
// prompt kita larang sebagai "transparent English compound".
const embedded = [];
for (const name of names) {
  const flat = plain(name);
  const hits = [];
  for (let start = 0; start < flat.length; start += 1) {
    for (let end = flat.length; end - start >= 4; end -= 1) {
      const piece = flat.slice(start, end);
      if (words.has(piece)) {
        hits.push(piece);
        break;
      }
    }
  }
  if (hits.length) embedded.push({ name, hits: [...new Set(hits)] });
}

const scored = names.map((name) => ({
  name,
  score: nameStructureScore(plain(name)),
  syllables: syllables(name),
  length: plain(name).length,
}));
const passes = scored.filter((item) => item.score >= NAME_STRUCTURE_FLOOR);
const unsafe = names.filter((name) => !nameIsSafeForPlayers(plain(name)));

const histogram = (values) => {
  const map = new Map();
  for (const value of values) map.set(value, (map.get(value) ?? 0) + 1);
  return [...map.entries()].sort((a, b) => a[0] - b[0]);
};

console.log("total spesies:", names.length);
console.log(
  `kata kamus utuh: ${exactWords.length} (${
    (exactWords.length / names.length * 100).toFixed(1)
  }%)`,
);
console.log("  contoh:", exactWords.slice(0, 40).join(", "));
console.log(
  `memuat kata kamus >=4 huruf: ${embedded.length} (${
    (embedded.length / names.length * 100).toFixed(1)
  }%)`,
);
console.log(
  "  contoh:",
  embedded.slice(0, 18).map((item) => `${item.name}[${item.hits.join("/")}]`)
    .join(", "),
);
console.log(
  `lolos lantai struktur kita (>=${NAME_STRUCTURE_FLOOR}): ${passes.length} (${
    (passes.length / names.length * 100).toFixed(1)
  }%)`,
);
console.log("suku kata:", histogram(scored.map((item) => item.syllables)));
console.log("panjang:", histogram(scored.map((item) => item.length)));
console.log("kena gerbang stem terlarang kita:", unsafe.join(", ") || "nol");

const famous = [
  "ditto",
  "golem",
  "electrode",
  "persian",
  "slowpoke",
  "magneton",
  "dragonair",
  "kadabra",
  "hitmonlee",
  "hitmonchan",
  "kangaskhan",
  "onix",
  "mew",
  "muk",
  "seel",
  "tauros",
  "jynx",
  "roselia",
  "klink",
  "pikachu",
  "eevee",
  "snorlax",
  "gengar",
  "magikarp",
];
console.log("\nnama terkenal terhadap gerbang kita:");
for (const name of famous) {
  const flat = plain(name);
  const score = nameStructureScore(flat);
  console.log(
    `  ${name.padEnd(11)} huruf ${String(flat.length).padStart(2)}`,
    `suku ${syllables(name)}`,
    `skor ${String(score).padStart(2)}`,
    score >= NAME_STRUCTURE_FLOOR ? "LOLOS" : "DITOLAK",
    words.has(flat) ? "(kata kamus)" : "",
  );
}
