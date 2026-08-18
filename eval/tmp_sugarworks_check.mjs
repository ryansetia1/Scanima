import { readFileSync } from "node:fs";
import {
  NAME_STRUCTURE_FLOOR,
  nameStructureScore,
} from "../backend/supabase/functions/_shared/vision.mjs";

const words = new Set(
  readFileSync("/usr/share/dict/words", "utf8")
    .split("\n")
    .map((word) => word.trim().toLowerCase())
    .filter((word) => word.length >= 4),
);

const embeddedWords = (name) => {
  const flat = name.toLowerCase();
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
  return [...new Set(hits)];
};

const sets = {
  "Sugarworks v6 (disukai operator)": [
    "Gellume",
    "Velastra",
    "Noxcoil",
    "Cindrusk",
    "Rimespin",
    "Pralith",
    "Duskadon",
    "Ambermire",
    "Nimbelisk",
  ],
  "v32-v39 (ditolak)": [
    "ClickGlide",
    "Muggleton",
    "Wyrmscale",
    "Cursora",
    "Dracovent",
    "Aerisyn",
    "Vectron",
    "Zimnuzem",
    "Basgutun",
    "Glidora",
    "Folialia",
    "Kuka",
    "Bomari",
    "Daxorin",
    "Kurvesun",
    "Dorralis",
    "Vurralis",
    "Diskurak",
  ],
};

for (const [label, names] of Object.entries(sets)) {
  let withWord = 0;
  let passes = 0;
  console.log(`\n${label}`);
  for (const name of names) {
    const hits = embeddedWords(name);
    const score = nameStructureScore(name.toLowerCase());
    if (hits.length) withWord += 1;
    if (score >= NAME_STRUCTURE_FLOOR) passes += 1;
    console.log(
      `  ${name.padEnd(11)} skor ${String(score).padStart(2)}`,
      (score >= NAME_STRUCTURE_FLOOR ? "LOLOS" : "TOLAK").padEnd(6),
      hits.length ? `morfem terbaca: ${hits.join("/")}` : "tanpa morfem terbaca",
    );
  }
  console.log(
    `  -> morfem terbaca ${withWord}/${names.length}`,
    `| lolos gerbang kita ${passes}/${names.length}`,
  );
}
