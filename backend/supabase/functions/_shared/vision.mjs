// Parsing keluaran Vision, penegakan kewajaran isinya, dan perakitan prompt
// gambar. Satu file untuk dua runtime, alasannya sama dengan postprocess.mjs:
// yang diputuskan di sini menentukan apakah kita membayar $0.07 atau tidak, dan
// species_key yang bergeser satu huruf berarti dua entri cache untuk satu benda.
// Dua salinan berarti eval bisa lulus sementara produksi memakai aturan lain.

import {
  isRosterElement,
  normalizeElement,
} from "./elements.mjs";

function levenshtein(a, b) {
  const dp = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let prev = dp[0];
    dp[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const tmp = dp[j];
      dp[j] = Math.min(dp[j] + 1, dp[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
      prev = tmp;
    }
  }
  return dp[b.length];
}

/**
 * Mengambil JSON dari keluaran model teks.
 *
 * Wrapper Gemini di Replicate TIDAK punya parameter `response_schema`, jadi
 * jaminan "selalu JSON valid" yang diberikan structured output Gemini langsung
 * tidak tersedia di sini. Konsekuensinya harus ditangani di kode, bukan
 * diharapkan dari model: keluaran bisa dibungkus ```json, bisa diawali kalimat
 * pengantar, dan datang sebagai array potongan string yang harus disambung
 * (skema output wrapper-nya iterator dengan display "concatenate").
 */
function stripJsonTrailingCommas(value) {
  let out = "";
  let inString = false;
  let escaped = false;
  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (inString) {
      out += char;
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === "\"") inString = false;
      continue;
    }
    if (char === "\"") {
      inString = true;
      out += char;
      continue;
    }
    if (char === ",") {
      let next = index + 1;
      while (next < value.length && /\s/.test(value[next])) next += 1;
      if (value[next] === "}" || value[next] === "]") continue;
    }
    out += char;
  }
  return out;
}

function parseJsonCandidate(value) {
  try {
    return JSON.parse(value);
  } catch {
    const repaired = stripJsonTrailingCommas(value);
    if (repaired !== value) return JSON.parse(repaired);
    throw new Error("invalid JSON");
  }
}

function unwrapMarkdownFence(text) {
  const closed = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (closed) return closed[1];
  const opened = text.match(/```(?:json)?\s*([\s\S]*)$/i);
  return opened ? opened[1] : text;
}

function scanJsonClosers(value) {
  let inString = false;
  let escaped = false;
  const stack = [];
  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === "\"") inString = false;
      continue;
    }
    if (char === "\"") inString = true;
    else if (char === "{") stack.push("}");
    else if (char === "[") stack.push("]");
    else if ((char === "}" || char === "]") && stack[stack.length - 1] === char) {
      stack.pop();
    }
  }
  return { inString, stack };
}

function dropIncompleteJsonTail(value) {
  return value
    .replace(/,\s*$/, "")
    .replace(/,\s*\{\s*$/, "")
    .replace(/,\s*\[\s*$/, "")
    .replace(/,\s*"[^"\\]*(?:\\.[^"\\]*)*"\s*:\s*$/, "")
    .replace(/,\s*"[^"\\]*(?:\\.[^"\\]*)*"\s*$/, "");
}

function closeTruncatedJson(value) {
  const start = value.indexOf("{");
  if (start < 0) return value;
  let text = value.slice(start);
  let state = scanJsonClosers(text);
  if (state.inString) {
    text += "\"";
    state = scanJsonClosers(text);
  }
  text = dropIncompleteJsonTail(text);
  state = scanJsonClosers(text);
  while (state.stack.length) text += state.stack.pop();
  return text;
}

export function extractJson(raw) {
  const text = Array.isArray(raw) ? raw.join("") : String(raw ?? "");
  // ponytail: Gemini kadang menutup string lalu menulis + "lanjutan", atau
  // membuka ```json lalu kehabisan output sebelum pagar/kurung tertutup.
  // Plafon: recovery struktural, bukan mengisi field yang tidak sempat ditulis.
  const candidate = unwrapMarkdownFence(text).trim().replace(/"\s*\+\s*"/g, "");

  try {
    return parseJsonCandidate(candidate);
  } catch {
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start > -1 && end > start) {
      try {
        return parseJsonCandidate(candidate.slice(start, end + 1));
      } catch {
        // jatuh ke penutup JSON terpotong
      }
    }
    if (start > -1) {
      try {
        return parseJsonCandidate(closeTruncatedJson(candidate));
      } catch {
        // jatuh ke error di bawah
      }
    }
  }

  throw new Error(`Vision tidak mengembalikan JSON yang bisa diparse: ${candidate.slice(0, 300) || "(kosong)"}`);
}

export function promptMajor(version) {
  const n = Number(String(version ?? "").replace(/^v/i, ""));
  return Number.isFinite(n) ? n : 0;
}

export function normalizeSuggestedName(name, fallback = "Anima") {
  const candidate = String(name ?? "").trim().slice(0, 24);
  if (!candidate) return fallback;
  if (!/mon$/i.test(candidate)) return candidate;

  const stem = candidate.slice(0, -3).trim();
  return stem.length >= 2 ? `${stem}ra`.slice(0, 24) : fallback;
}

export function normalizeNameLineageAnchor(anchor) {
  return String(anchor ?? "").trim().toLowerCase();
}

export function validateNameLineageAnchor(anchor, suggestedName, requirePronounceable = false) {
  const normalizedAnchor = normalizeNameLineageAnchor(anchor);
  if (
    !/^[a-z]{3,5}$/.test(normalizedAnchor)
    || !/[aeiou]/.test(normalizedAnchor)
    || (requirePronounceable && /[b-df-hj-np-tv-z]{3}/.test(normalizedAnchor))
  ) {
    throw new Error(`name_lineage_anchor tidak sah: ${JSON.stringify(anchor)}`);
  }
  if (!String(suggestedName ?? "").toLowerCase().includes(normalizedAnchor)) {
    throw new Error(
      `name_lineage_anchor '${normalizedAnchor}' tidak ada di suggested_name '${suggestedName}'`,
    );
  }
  return normalizedAnchor;
}

export function deriveNameLineageAnchor(
  suggestedName,
  proposedAnchor = "",
  requirePronounceable = false,
) {
  const letters = String(suggestedName ?? "").toLowerCase().replace(/[^a-z]/g, "");
  const proposed = normalizeNameLineageAnchor(proposedAnchor);
  const candidates = [];
  for (let length = 3; length <= 5; length += 1) {
    for (let start = 0; start + length <= letters.length; start += 1) {
      const value = letters.slice(start, start + length);
      if (!/[aeiou]/.test(value)) continue;
      if (requirePronounceable && /[b-df-hj-np-tv-z]{3}/.test(value)) continue;
      candidates.push({
        value,
        distance: proposed ? levenshtein(value, proposed) : 0,
        lengthDelta: proposed ? Math.abs(value.length - proposed.length) : 0,
        start,
      });
    }
  }
  candidates.sort((a, b) =>
    a.distance - b.distance
    || a.lengthDelta - b.lengthDelta
    || a.start - b.start
    || b.value.length - a.value.length
  );
  if (!candidates.length) {
    throw new Error(`suggested_name tidak punya anchor 3–5 huruf yang sah: '${suggestedName}'`);
  }
  return candidates[0].value;
}

export const NAME_QUALITY_KEYS = [
  "invented_word",
  "source_identity_hidden",
  "creature_species_read",
  "grounded_in_two_visual_cues",
  "not_product_or_brand_read",
  "lineage_ready",
];

const NAME_TONE_ONSETS = {
  hp: ["b", "br", "l", "m", "n", "r", "v", "gr"],
  atk: ["d", "dr", "g", "k", "kr", "t", "tr", "z"],
  def: ["b", "d", "g", "k", "m", "r", "st", "vr"],
  spd: ["f", "l", "r", "s", "sh", "v", "z", "sk"],
  special: ["gl", "l", "n", "r", "th", "v", "z", "vr"],
};
const NAME_SIMPLE_ONSETS = ["b", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"];
const NAME_VOWELS = ["a", "e", "i", "o", "u"];
const NAME_CODAS = ["l", "n", "r", "s", "m", "v", "k", "d"];

function nameHash(value) {
  let hash = 2166136261;
  for (const char of String(value ?? "")) {
    hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
  }
  return hash >>> 0;
}

function nameRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function namePick(values, random) {
  return values[Math.floor(random() * values.length)];
}

function nameOnset(random, previous, values = NAME_SIMPLE_ONSETS) {
  const available = values.filter((value) => value[0] !== previous);
  return namePick(available.length ? available : values, random);
}

function nameSyllable(random, previous, withCoda = false) {
  const onset = nameOnset(random, previous);
  const vowel = namePick(NAME_VOWELS, random);
  const coda = withCoda ? namePick(["", ...NAME_CODAS], random) : "";
  return `${onset}${vowel}${coda}`;
}

function nameTone(stats) {
  const order = ["hp", "atk", "def", "spd", "special"];
  return order.reduce((best, key) =>
    Number(stats?.[key] ?? 0) > Number(stats?.[best] ?? 0) ? key : best
  , "hp");
}

function titleSpeciesName(value) {
  return value.charAt(0).toUpperCase() + value.slice(1).toLowerCase();
}

/**
 * V36: nama tidak lagi dipercaya dari self-review model. Vision hanya memasok
 * ciri visual; fonologi dipilih deterministik dari ciri itu tanpa call kedua.
 */
export function deriveDeterministicSpeciesName(vision) {
  const tone = nameTone(vision?.stats);
  const seedText = [
    vision?.species_key,
    vision?.subject_kind,
    vision?.element,
    vision?.secondary_element,
    tone,
    vision?.creature_brief,
    ...(Array.isArray(vision?.signature_features) ? vision.signature_features : []),
  ].join("|").toLowerCase();
  const random = nameRandom(nameHash(seedText));
  const onset = namePick(NAME_TONE_ONSETS[tone], random);
  const vowel = namePick(NAME_VOWELS, random);
  const anchor = `${onset}${vowel}${namePick(NAME_CODAS, random)}`;
  const middle = nameSyllable(random, anchor.at(-1));
  const ending = nameSyllable(random, middle.at(-1), true);
  return {
    suggested_name: titleSpeciesName(`${anchor}${middle}${ending}`),
    name_lineage_anchor: anchor,
  };
}

export function deriveDeterministicEvolutionName(anchor, plan, targetStage) {
  const normalizedAnchor = normalizeNameLineageAnchor(anchor);
  if (!/^[a-z]{3,5}$/.test(normalizedAnchor) || !/[aeiou]/.test(normalizedAnchor)) {
    throw new Error(`name_lineage_anchor deterministic tidak sah: '${anchor}'`);
  }
  const seedText = [
    normalizedAnchor,
    targetStage,
    plan?.transformation_archetype,
    plan?.stage_brief,
    plan?.body_height_cm,
    plan?.mobility_contract?.locomotion_mode,
    plan?.silhouette_break_contract?.new_contour_read,
    plan?.kind_noun,
  ].join("|").toLowerCase();
  const random = nameRandom(nameHash(seedText));
  const middle = nameSyllable(random, normalizedAnchor.at(-1));
  const bridge = Number(targetStage) >= 3
    ? nameSyllable(random, middle.at(-1))
    : "";
  const previous = (bridge || middle).at(-1);
  const ending = nameSyllable(random, previous, true);
  return titleSpeciesName(`${normalizedAnchor}${middle}${bridge}${ending}`);
}

export const NAME_ROOT_CHANNELS = [
  "silhouette",
  "material",
  "motion",
  "temperament",
  "structure",
];

const HYBRID_CAPTURE_SUFFIXES = {
  hp: ["uma", "oro", "elia", "una", "ava", "omi"],
  atk: ["ara", "avor", "eka", "ira", "ora", "yra"],
  def: ["odon", "orin", "arum", "etha", "ulen", "ora"],
  spd: ["iri", "iva", "elo", "ari", "yra", "une"],
  special: ["une", "elia", "yra", "ora", "ion", "avi"],
};
const HYBRID_ADULT_SUFFIXES = ["arin", "eron", "ivar", "ora", "une", "elis", "avor", "yra"];
const HYBRID_EVOLVED_SUFFIXES = ["arion", "athor", "elyra", "urion", "ovar", "endra", "aveth", "oryn"];

export function joinNameRoot(root, suffix) {
  const joinedSuffix = /[aeiou]$/.test(root) && /^[aeiou]/.test(suffix)
    ? suffix.slice(1)
    : suffix;
  return titleSpeciesName(`${root}${joinedSuffix}`);
}

function sourceIdentityTokens(vision) {
  return [
    vision?.object_label,
    vision?.species_key,
  ].join(" ").toLowerCase().split(/[^a-z]+/).filter((token) => token.length >= 3);
}

/**
 * `allowClusters` ada karena v41 memang meminta morfem terbaca yang dikliping
 * dari kata bermakna, dan klipingnya sering berakhir klaster: `cindr` dari
 * cinder, `umbr` dari umbra, `strid` dari stride. Aturan tiga-konsonan v37
 * membuang ketiganya, jadi tiga dari enam subjek dry run jatuh ke fallback
 * fonotaktik — termasuk head `cindr` milik Cindrusk yang sudah disetujui
 * operator. V37 tetap ketat supaya provenance-nya reproducible.
 */
/**
 * `skipInvalid` membuang entri buruk alih-alih membatalkan seluruh array. Paid eval
 * v41 mengukur biayanya: satu `wyrm` tanpa vokal, satu `stride` enam huruf, dan satu
 * channel `sound` di luar allowlist membuang lima akar sehat bersamanya, lalu lima
 * dari sembilan Anima memakai fonotaktik v36 yang justru sudah ditolak operator.
 * Ranking model tetap dihormati: yang dipakai adalah entri sah pertama.
 */
function normalizeNameRoots(vision, allowClusters = false, skipInvalid = false) {
  const raw = Array.isArray(vision?.name_roots) ? vision.name_roots : [];
  if (raw.length !== 6) {
    throw new Error("name_roots v37 harus tepat 6 kandidat");
  }
  const identityTokens = sourceIdentityTokens(vision);
  const rejected = [];
  const roots = [];
  raw.forEach((item, index) => {
    const root = normalizeNameLineageAnchor(item?.root);
    const channel = String(item?.channel ?? "").trim().toLowerCase();
    const evidence = String(item?.evidence ?? "").trim();
    let problem = "";
    if (
      !/^[a-z]{3,5}$/.test(root)
      || !/[aeiou]/.test(root)
      || (!allowClusters && /[b-df-hj-np-tv-z]{3}/.test(root))
    ) {
      problem = `name_roots[${index}].root tidak sah: '${root}'`;
    } else if (!NAME_ROOT_CHANNELS.includes(channel)) {
      problem = `name_roots[${index}].channel tidak sah: '${channel}'`;
    } else if (!evidence) {
      problem = `name_roots[${index}].evidence kosong`;
    }
    if (problem) {
      if (!skipInvalid) throw new Error(problem);
      rejected.push(problem);
      return;
    }
    const copiesIdentity = identityTokens.some((token) =>
      token === root || (root.length >= 4 && token.includes(root))
    );
    roots.push({ root, channel, evidence, copiesIdentity });
  });
  if (new Set(roots.map((item) => item.root)).size !== roots.length) {
    throw new Error("name_roots v37 harus enam akar berbeda");
  }
  if (!skipInvalid && new Set(roots.map((item) => item.channel)).size < 4) {
    throw new Error("name_roots v37 harus mencakup minimal empat visual channel");
  }
  const valid = roots.filter((item) => !item.copiesIdentity);
  if (!valid.length) {
    throw new Error("name_roots v37 seluruhnya menyalin identitas sumber");
  }
  if (rejected.length) valid[0].rejected_roots = rejected;
  return valid;
}

/**
 * V37: model mengusulkan akar semantik, server memiliki final word formation.
 * Urutan kandidat adalah ranking model; validator membuang salinan source label.
 */
export function deriveHybridSpeciesName(vision) {
  const candidate = normalizeNameRoots(vision)[0];
  const tone = nameTone(vision?.stats);
  const suffixes = HYBRID_CAPTURE_SUFFIXES[tone];
  const seed = nameHash([
    vision?.species_key,
    vision?.element,
    vision?.secondary_element,
    candidate.root,
    candidate.channel,
    candidate.evidence,
  ].join("|").toLowerCase());
  const suffix = suffixes[seed % suffixes.length];
  return {
    suggested_name: joinNameRoot(candidate.root, suffix),
    name_lineage_anchor: candidate.root,
    selected_name_root: candidate,
  };
}

export function deriveHybridEvolutionName(anchor, plan, targetStage) {
  const normalizedAnchor = normalizeNameLineageAnchor(anchor);
  if (!/^[a-z]{3,5}$/.test(normalizedAnchor) || !/[aeiou]/.test(normalizedAnchor)) {
    throw new Error(`name_lineage_anchor hybrid tidak sah: '${anchor}'`);
  }
  const suffixes = Number(targetStage) >= 3
    ? HYBRID_EVOLVED_SUFFIXES
    : HYBRID_ADULT_SUFFIXES;
  const seed = nameHash([
    normalizedAnchor,
    targetStage,
    plan?.transformation_archetype,
    plan?.stage_brief,
    plan?.mobility_contract?.locomotion_mode,
    plan?.silhouette_break_contract?.new_contour_read,
  ].join("|").toLowerCase());
  return joinNameRoot(normalizedAnchor, suffixes[seed % suffixes.length]);
}

/**
 * V40: satu gerbang leksikal deterministik di atas kandidat yang sudah dibentuk.
 * Paid eval v39 mengirim `Kurvesun` — `kurv` vulgar dalam bahasa Ceko, Slovakia,
 * Hungaria, Serbia, Kroasia, dan Polandia — dan substring itu tidak ada di anchor
 * maupun di ending; ia lahir dari sambungannya. Jadi gerbangnya harus berjalan
 * atas kata jadi, bukan atas potongan-potongannya.
 * ponytail: daftar manual yang dibekukan, bukan clearance leksikal. Plafonnya
 * nama proper yang sah secara struktur (Doralis) dan bahasa di luar daftar;
 * upgrade = dataset profanity berlisensi atau satu review call terpisah.
 */
const NAME_FORBIDDEN_STEMS = Object.freeze([
  "anal", "anus", "cock", "cunt", "dick", "fagg", "fuck", "fuk", "kunt",
  "nigg", "negr", "chink", "penis", "porn", "rape", "sex", "shit", "slut",
  "tits", "turd", "vagin", "whore", "nazi", "hitler", "jihad",
  "blyat", "chuj", "fasz", "huj", "jeba", "jebi", "kurac", "kurv", "kurw",
  "mudak", "picka", "picsa", "pierdol", "pizd",
  "caralh", "cazzo", "kanker", "merda", "merde", "mierd", "puta", "puto",
  "schei", "fotze", "stronz",
]);

export function nameIsSafeForPlayers(word) {
  const lower = String(word ?? "").toLowerCase();
  return !NAME_FORBIDDEN_STEMS.some((stem) => lower.includes(stem));
}

export const NAME_CADENCE_FAMILIES = ["closed", "hard", "liquid", "open"];

const TRANSFORMED_ONSETS = {
  labial: ["b", "br", "f", "m", "p", "v"],
  coronal: ["d", "l", "n", "r", "s", "t", "tr", "z"],
  velar: ["g", "gr", "k", "kr", "v", "z"],
};
const TRANSFORMED_CODAS = {
  silhouette: ["l", "r", "n", "sk"],
  material: ["m", "n", "l", "d", "th"],
  motion: ["r", "v", "s", "n", "x"],
  temperament: ["l", "n", "r", "m"],
  structure: ["k", "d", "r", "n", "l"],
};
const BALANCED_CAPTURE_CADENCES = [
  ["en", "or", "is", "un", "eth", "yn"],
  ["ak", "orn", "esk", "ard", "oth", "ik"],
  ["el", "orin", "urel", "aris", "eron", "il"],
  ["a", "ia", "une", "ari", "ora", "umi"],
];
const BALANCED_ADULT_CADENCES = [
  ["en", "oris", "un", "eth", "ir", "yn"],
  ["ak", "orn", "esk", "ard", "oth", "ik"],
  ["el", "orin", "urel", "aris", "eron", "il"],
  ["a", "ia", "une", "ari", "ora", "umi"],
];
const BALANCED_EVOLVED_CADENCES = [
  ["arion", "endor", "uris", "aveth", "oryn", "ul"],
  ["athor", "ardek", "ornak", "eskor", "othis", "ikran"],
  ["elyra", "urion", "urelis", "arisel", "erovar", "ilora"],
  ["ara", "oria", "avune", "endari", "elora", "arumi"],
];

function transformedOnsetFamily(firstLetter) {
  if (/[bmpfv]/.test(firstLetter)) return "labial";
  if (/[tdnszlr]/.test(firstLetter)) return "coronal";
  return "velar";
}

function normalizeSemanticSeeds(vision) {
  const raw = Array.isArray(vision?.name_roots) ? vision.name_roots : [];
  if (raw.length !== 6) {
    throw new Error("name_roots v38 harus tepat 6 semantic seed");
  }
  const identityTokens = sourceIdentityTokens(vision);
  const seeds = raw.map((item, index) => {
    const root = String(item?.root ?? "").toLowerCase().replace(/[^a-z]/g, "");
    const channel = String(item?.channel ?? "").trim().toLowerCase();
    const evidence = String(item?.evidence ?? "").trim();
    if (root.length < 3 || root.length > 8 || !/[aeiouy]/.test(root)) {
      throw new Error(`name_roots[${index}].root seed tidak sah: '${root}'`);
    }
    if (!NAME_ROOT_CHANNELS.includes(channel)) {
      throw new Error(`name_roots[${index}].channel tidak sah: '${channel}'`);
    }
    if (!evidence) throw new Error(`name_roots[${index}].evidence kosong`);
    const copiesIdentity = identityTokens.some((token) =>
      token === root || (root.length >= 4 && token.includes(root))
    );
    return { root, channel, evidence, copiesIdentity };
  });
  if (new Set(seeds.map((item) => item.root)).size !== seeds.length) {
    throw new Error("name_roots v38 harus enam seed berbeda");
  }
  if (new Set(seeds.map((item) => item.channel)).size < 4) {
    throw new Error("name_roots v38 harus mencakup minimal empat visual channel");
  }
  const valid = seeds.filter((item) => !item.copiesIdentity);
  if (!valid.length) {
    throw new Error("name_roots v38 seluruhnya menyalin identitas sumber");
  }
  return valid;
}

function transformSemanticRoot(candidate, vision, requireSafeAnchor = false) {
  const seed = nameHash([
    vision?.species_key,
    vision?.element,
    vision?.secondary_element,
    candidate.root,
    candidate.channel,
    candidate.evidence,
  ].join("|").toLowerCase());
  const onsetPool = TRANSFORMED_ONSETS[
    transformedOnsetFamily(candidate.root.charAt(0))
  ];
  const shiftedOnsets = onsetPool.filter((onset) =>
    onset.charAt(0) !== candidate.root.charAt(0)
  );
  const onset = shiftedOnsets[seed % shiftedOnsets.length];
  const sourceVowel = candidate.root.match(/[aeiouy]/)?.[0] ?? "a";
  const vowelIndex = NAME_VOWELS.indexOf(sourceVowel === "y" ? "i" : sourceVowel);
  const vowel = NAME_VOWELS[
    (vowelIndex + 1 + ((seed >>> 4) % 4)) % NAME_VOWELS.length
  ];
  const codas = TRANSFORMED_CODAS[candidate.channel];
  // Anchor bertahan sepanjang lineage, jadi anchor yang tidak aman tidak dapat
  // diperbaiki saat seleksi kata. Ruangnya kecil dan tertutup — onset × vowel ×
  // coda — dan `sex` serta `fuk` benar-benar dapat dirakit di dalamnya.
  const usable = requireSafeAnchor
    ? codas.filter((coda) => nameIsSafeForPlayers(`${onset}${vowel}${coda}`))
    : codas;
  const pool = usable.length ? usable : codas;
  return `${onset}${vowel}${pool[(seed >>> 8) % pool.length]}`;
}

export function deriveTransformedHybridSpeciesName(vision) {
  const candidate = normalizeSemanticSeeds(vision)[0];
  const anchor = transformSemanticRoot(candidate, vision);
  const seed = nameHash([
    vision?.species_key,
    vision?.subject_kind,
    vision?.element,
    vision?.secondary_element,
    vision?.creature_brief,
    ...(
      Array.isArray(vision?.signature_features)
        ? vision.signature_features
        : []
    ),
  ].join("|").toLowerCase());
  const familyIndex = seed % NAME_CADENCE_FAMILIES.length;
  const suffixes = BALANCED_CAPTURE_CADENCES[familyIndex];
  const suffix = suffixes[(seed >>> 8) % suffixes.length];
  return {
    suggested_name: joinNameRoot(anchor, suffix),
    name_lineage_anchor: anchor,
    selected_name_root: {
      ...candidate,
      transformed_anchor: anchor,
      cadence_family: NAME_CADENCE_FAMILIES[familyIndex],
    },
  };
}

// Anchor selalu berakhir konsonan, jadi tiap keluarga cukup memasok akhiran dua
// suku kata langsung. Urutan keluarga mengikuti NAME_CADENCE_FAMILIES.
// `relis`/`ralis` dibuang sesudah paid eval v39: keduanya membentuk `-alis` yang
// menghasilkan Dorralis (satu huruf dari nama orang Doralis) sekaligus ekor kembar
// pada dua dari enam nama.
const CADENCE_CAPTURE_ENDINGS = [
  ["deren", "tesin", "kaleth", "moran", "vesun", "tirin", "nadel", "suren"],
  ["dakar", "tegok", "karesk", "dorak", "vagard", "tikoth", "gadek", "kurak"],
  ["lorin", "relum", "narel", "loran", "ruvel", "lirel", "ralorn", "veloran"],
  ["mara", "vela", "nora", "dira", "luma", "sava", "tira", "gora"],
];
// Pokémon memakai dua suku kata sesering tiga — Ditto, Gengar, Snorlax, Pidgeot —
// jadi tiap keluarga juga memasok akhiran satu suku kata. Tanpa ini lantai
// struktur membuat dua suku kata mustahil, dan enam nama paid eval v39 semuanya
// tiga suku kata bukan karena kebetulan. Stage lanjut sengaja tidak memakai tabel
// ini: Hatchling pendek yang tumbuh panjang adalah eskalasi yang benar.
const CADENCE_CAPTURE_SHORT_ENDINGS = [
  ["eth", "ish", "oth", "uns", "enn", "yss"],
  ["ark", "esk", "okt", "ock", "ekt", "arg"],
  ["arl", "oel", "url", "ial", "eal", "orl"],
  ["ia", "ea", "oa", "ua", "eia", "oia"],
];
const CADENCE_ADULT_ENDINGS = [
  ["deroth", "tesar", "kalen", "morun", "vesir", "tiran", "nadeth", "surek"],
  ["dakor", "tegark", "karosk", "dorag", "vagurd", "tikark", "gadok", "kurog"],
  ["lorien", "relmar", "narune", "lorath", "ruvelan", "lirion", "ralnor", "veluris"],
  ["marae", "velua", "noria", "dirae", "lumia", "savora", "tirua", "gorae"],
];
const CADENCE_EVOLVED_ENDINGS = [
  ["derathon", "tesarim", "kalendor", "moruneth", "vesirak", "tiranok", "nadethir", "surekar"],
  ["dakoran", "tegarnok", "karoskar", "doragorn", "vagurdek", "tikarnoth", "gadokar", "kurogan"],
  ["lorienne", "relmaris", "narunel", "lorathiel", "ruvelaris", "lirionel", "ralnoris", "velurian"],
  ["maraea", "veluara", "noriaka", "diraeva", "lumiara", "savorea", "tiruana", "goraeva"],
];

function nameSyllableCount(word) {
  return (word.match(/[aeiouy]+/g) ?? []).length;
}

function hasRepeatedBigram(word) {
  for (let index = 0; index + 2 <= word.length; index += 1) {
    if (word.indexOf(word.slice(index, index + 2), index + 1) !== -1) return true;
  }
  return false;
}

/**
 * V39: penalti struktural deterministik. Empat dari lima reject v38 punya cacat
 * yang terukur di sini tanpa dictionary, model call, atau lookup eksternal:
 * pendek/sedikit suku kata (Kuka, Vororn, Zoskesk), rantai CV terbuka tanpa
 * coda (Bomari), dan bigram berulang (Vororn "or", Zoskesk "sk").
 * ponytail: ini mengecilkan permukaan collision, bukan clearance trademark.
 * Plafonnya nama proper yang sah secara struktur (Daxorin); upgrade butuh bukti
 * independen dari model yang mengarangnya, bukan penalti tambahan.
 */
export function nameStructureScore(word, identityTokens = []) {
  const lower = String(word ?? "").toLowerCase();
  let score = 0;
  if (lower.length < 6) score -= 3;
  else if (lower.length <= 12) score += 1;
  else score -= 2;
  // V39 memberi lantai pada tiga suku kata, dan itu bias yang saya pasang sendiri
  // tepat setelah membuang bias rima: dua suku kata jadi mustahil, jadi keenam
  // nama paid eval berbentuk sama. Cacat sebenarnya pada Kuka/Vororn/Zoskesk
  // adalah panjang dan bigram berulang, bukan jumlah suku katanya.
  const syllables = nameSyllableCount(lower);
  if (syllables < 2) score -= 3;
  else if (syllables <= 4) score += 1;
  else score -= 2;
  // Rantai CV tunggal tanpa satu pun klaster atau coda (Bomari) adalah bentuk
  // kata paling umum lintas bahasa, jadi paling sering sudah dipakai. Klaster
  // seperti "rn" pada Dornara sudah cukup membedakannya.
  if (/^([^aeiouy][aeiouy])+$/.test(lower)) score -= 2;
  if (hasRepeatedBigram(lower)) score -= 2;
  // Penalti tiga konsonan beruntun dibuang di v41 karena terukur salah sasaran:
  // ia tidak menyala pada satu pun reject v38 (Kuka, Vororn, Zoskesk, Bomari),
  // tetapi ia satu-satunya sebab Velastra ("str") dan Cindrusk ("ndr") — dua nama
  // Sugarworks yang disetujui operator — jatuh di bawah lantai. Klaster di seam
  // dua morfem terbaca memang dapat diucapkan; Kingdra "ngdr" dan Sandshrew
  // "ndshr" hidup dengan bentuk yang sama.
  if (identityTokens.some((token) => token.length >= 4 && lower.includes(token))) {
    score -= 4;
  }
  if (/mon$/.test(lower)) score -= 5;
  return score;
}

export const NAME_STRUCTURE_FLOOR = 1;

/**
 * Skor dipakai sebagai gerbang, bukan fungsi objektif. Memilih skor tertinggi
 * terukur selalu konvergen ke satu optimum struktural yang sama — 151/200
 * fixture berakhir `-rin` — yaitu bias rima yang justru sedang diperbaiki. Jadi:
 * buang yang tidak aman, buang yang di bawah lantai, lalu pilih di antara sisanya
 * memakai hash identitas visual supaya variasinya kembali.
 */
function selectCadenceName(
  anchor,
  endingFamilies,
  seed,
  identityTokens,
  shortFamilies,
) {
  const scored = [];
  for (let family = 0; family < NAME_CADENCE_FAMILIES.length; family += 1) {
    const endings = shortFamilies
      ? [...endingFamilies[family], ...shortFamilies[family]]
      : endingFamilies[family];
    for (const ending of endings) {
      const name = joinNameRoot(anchor, ending);
      scored.push({
        name,
        score: nameStructureScore(name, identityTokens),
        cadence_family: NAME_CADENCE_FAMILIES[family],
      });
    }
  }
  const safe = scored.filter((item) => nameIsSafeForPlayers(item.name));
  const pool = safe.length ? safe : scored;
  const accepted = pool.filter((item) => item.score >= NAME_STRUCTURE_FLOOR);
  if (!accepted.length) {
    return pool.reduce((best, item) => (item.score > best.score ? item : best));
  }
  // Bit terendah nameHash bukan pengacak: FNV-1a mengalikan dengan bilangan
  // ganjil, jadi bit 0 hasilnya XOR paritas seluruh karakter input. Dua field
  // berkorelasi — misalnya species_key dan creature_brief yang membawa token
  // sama — saling membatalkan dan membekukan `seed % 4` pada dua keluarga saja.
  // Terukur: 400 fixture hanya menghasilkan hard dan open. Bit atas sudah lewat
  // carry perkalian, jadi ia bercampur.
  const preferred = NAME_CADENCE_FAMILIES[
    (seed >>> 24) % NAME_CADENCE_FAMILIES.length
  ];
  const family = accepted.filter((item) => item.cadence_family === preferred);
  const chosen = family.length ? family : accepted;
  return chosen[(seed >>> 8) % chosen.length];
}

/**
 * V39: satu kandidat deterministik ternyata tidak cukup — ia dipakai apa adanya
 * walau strukturnya lemah. Anchor semantik tetap dari Vision; server membangun
 * banyak kandidat, membuang yang tidak aman dan yang di bawah lantai struktur,
 * lalu memilih di antara sisanya. V40 menambah akhiran satu suku kata sehingga
 * dua dan tiga suku kata bersaing di kolam yang sama.
 */
export function deriveCuratedHybridSpeciesName(vision) {
  // Terukur pada paid eval v39: satu foto gagal seluruhnya karena model hanya
  // memasok tiga visual channel. Penamaan tidak boleh membakar Core, jadi seed
  // yang tidak terpakai jatuh ke fonotaktik deterministik dan tetap lewat
  // gerbang struktur yang sama.
  let candidate;
  try {
    candidate = normalizeSemanticSeeds(vision)[0];
  } catch (error) {
    candidate = {
      root: deriveDeterministicSpeciesName(vision).name_lineage_anchor,
      channel: "structure",
      evidence: "seed fallback",
      copiesIdentity: false,
      seed_fallback: String(error.message ?? error),
    };
  }
  const anchor = transformSemanticRoot(candidate, vision, true);
  const seed = nameHash([
    vision?.species_key,
    vision?.subject_kind,
    vision?.element,
    vision?.secondary_element,
    vision?.creature_brief,
    ...(
      Array.isArray(vision?.signature_features)
        ? vision.signature_features
        : []
    ),
  ].join("|").toLowerCase());
  const chosen = selectCadenceName(
    anchor,
    CADENCE_CAPTURE_ENDINGS,
    seed,
    sourceIdentityTokens(vision),
    CADENCE_CAPTURE_SHORT_ENDINGS,
  );
  return {
    suggested_name: chosen.name,
    name_lineage_anchor: anchor,
    selected_name_root: {
      ...candidate,
      transformed_anchor: anchor,
      cadence_family: chosen.cadence_family,
      structure_score: chosen.score,
    },
  };
}

export function deriveCuratedHybridEvolutionName(anchor, plan, targetStage) {
  const normalizedAnchor = normalizeNameLineageAnchor(anchor);
  if (!/^[a-z]{3,5}$/.test(normalizedAnchor) || !/[aeiou]/.test(normalizedAnchor)) {
    throw new Error(`name_lineage_anchor curated hybrid tidak sah: '${anchor}'`);
  }
  const seed = nameHash([
    normalizedAnchor,
    targetStage,
    plan?.transformation_archetype,
    plan?.stage_brief,
    plan?.mobility_contract?.locomotion_mode,
    plan?.silhouette_break_contract?.new_contour_read,
  ].join("|").toLowerCase());
  const endings = Number(targetStage) >= 3
    ? CADENCE_EVOLVED_ENDINGS
    : CADENCE_ADULT_ENDINGS;
  return selectCadenceName(normalizedAnchor, endings, seed, []).name;
}

export function deriveTransformedHybridEvolutionName(anchor, plan, targetStage) {
  const normalizedAnchor = normalizeNameLineageAnchor(anchor);
  if (!/^[a-z]{3,5}$/.test(normalizedAnchor) || !/[aeiou]/.test(normalizedAnchor)) {
    throw new Error(`name_lineage_anchor transformed hybrid tidak sah: '${anchor}'`);
  }
  const seed = nameHash([
    normalizedAnchor,
    targetStage,
    plan?.transformation_archetype,
    plan?.stage_brief,
    plan?.mobility_contract?.locomotion_mode,
    plan?.silhouette_break_contract?.new_contour_read,
  ].join("|").toLowerCase());
  const familyIndex = seed % NAME_CADENCE_FAMILIES.length;
  const families = Number(targetStage) >= 3
    ? BALANCED_EVOLVED_CADENCES
    : BALANCED_ADULT_CADENCES;
  const suffixes = families[familyIndex];
  return joinNameRoot(
    normalizedAnchor,
    suffixes[(seed >>> 8) % suffixes.length],
  );
}

/**
 * V41 membalik premis v32–v40. Enam mekanisme berbeda mengejar keunikan leksikal
 * dan semuanya mendarat di 0/6–3/6. Riset 1025 nama Pokémon
 * (`docs/pokemon-name-research.html`) menunjukkan targetnya salah: 76,6% nama
 * Pokémon memuat kata kamus utuh >=4 huruf, 2,5% adalah kata kamus, Dragonair
 * memakai nama maskapai aktif, dan Kadabra bertahan 20 tahun litigasi tanpa
 * berganti nama. Ishihara bahkan menguji ke orang Amerika bahwa Bulbasaur
 * *terbaca* sebagai bulb + saurus.
 *
 * Yang terukur di sisi kita: ketujuh nama reject v32–v39 yang tanpa morfem
 * (Aerisyn, Zimnuzem, Basgutun, Daxorin, Kurvesun, Dorralis, Vurralis) semuanya
 * lolos gerbang lama, sementara Velastra dan Cindrusk — dua nama Sugarworks yang
 * disetujui operator — justru ditolak. Kata yang bisa diucapkan tanpa morfem
 * apa pun tidak punya pilihan selain terbaca sebagai nama orang.
 *
 * Jadi akar Vision tidak lagi dirusak menjadi anchor tak dikenal, dan
 * lanjutannya morfem bermakna, bukan sufiks fonetik.
 */
const MORPHEME_ELEMENT_FAMILIES = Object.freeze({
  metal: "mineral",
  stone: "mineral",
  ceramic: "mineral",
  glass: "mineral",
  wood: "verdant",
  plant: "verdant",
  food: "verdant",
  flow: "tidal",
  frost: "tidal",
  flame: "ember",
  spark: "ember",
  plastic: "drape",
  cloth: "drape",
  paper: "drape",
  fauna: "feral",
  toxin: "feral",
  air: "zephyr",
  sound: "zephyr",
});

// Kesembilan tail Sugarworks yang disetujui operator ada di tabel ini — lith dan
// elisk (mineral), mire (tidal), lume (ember), husk dan coil (drape), adon
// (feral), spin dan astra (zephyr) — dan selftest merakit ulang kesembilan nama
// itu dari head + tail lewat `joinNameRoot` yang sama. Kalau tabelnya bergeser
// sampai Noxcoil atau Ambermire tidak bisa dibentuk lagi, itu regresi.
// Setiap keluarga wajib menyimpan minimal dua tail berawal vokal. Head berkoda
// dua konsonan seperti `curv` membuat seluruh tail berawal konsonan berbiaya seam
// 3, jadi mineral yang hanya punya `elisk` terukur mengunci 100/100 fixture pada
// `Curvelisk`.
// Setiap keluarga menyimpan campuran satu dan dua suku kata. Itu satu-satunya
// tuas panjang nama yang benar-benar dimiliki server: head datang dari Vision,
// jadi head satu suku kata + tail satu suku kata adalah satu-satunya jalan ke
// nama dua suku kata seperti Noxcoil dan Pralith.
export const MORPHEME_CAPTURE_TAILS = Object.freeze({
  mineral: [
    "lith", "crag", "shard", "forge", "spire", "elisk", "onyx", "ingot",
    "slate", "vein", "quartz", "ore",
  ],
  verdant: [
    "frond", "thorn", "bloom", "root", "vine", "grove", "arbor", "acanth",
    "sap", "bark", "husk", "seed",
  ],
  tidal: [
    "mire", "rime", "tide", "brine", "drift", "eddy", "abyss", "silt",
    "wake", "foam", "murk", "shoal",
  ],
  ember: [
    "ember", "pyre", "cinder", "blaze", "volt", "lume", "arc", "ignis",
    "coal", "flare", "soot", "kiln",
  ],
  // Plastic, cloth, dan paper berbagi keluarga ini, jadi morfem yang hanya benar
  // untuk tekstil (yarn, twill, eider) dibuang: `Pixlyarn` terukur pada konsol
  // plastik. Yang tersisa membaca sebagai lipatan/lembar/cangkang mana pun.
  drape: [
    "weave", "fold", "shroud", "quill", "seam", "husk", "usk", "coil", "arc",
    "knot", "hem", "sheath", "ridge",
  ],
  feral: [
    "fang", "maw", "talon", "pelt", "venom", "adon", "ursa", "spur",
    "howl", "gnaw", "prowl", "sting",
  ],
  zephyr: [
    "gale", "echo", "chime", "plume", "whorl", "spin", "astra",
    "gust", "hush", "veer", "drone",
  ],
});

// Pokémon tidak memanjangkan nama tiap stage — Charmander/Charmeleon/Charizard
// sama panjang, Bulbasaur justru menyusut ke Ivysaur — jadi eskalasinya ada di
// makna morfemnya, bukan di jumlah hurufnya.
//
// Kedua tabel ini sengaja **form-neutral**: nol bagian tubuh. Versi pertama
// memuat `horn`, `mane`, `antler`, dan `crest`, lalu terukur memberi `-horn`
// kepada lampu minyak yang Plan-nya tidak pernah menyebut tanduk — kesalahan
// yang tidak bisa dimaafkan pemain karena namanya menjanjikan anatomi yang tidak
// ada di sprite-nya. Morfem anatomi sekarang hanya boleh datang dari Plan itu
// sendiri lewat `planFeatureTails()`, dan tabel di bawah adalah jalan keluar
// terakhir yang selalu benar apa pun bentuk tubuhnya.
// Dua tail berawal vokal wajib ada di setiap tabel stage. Head berkoda klaster
// seperti `cindr` membuat seluruh tail berawal konsonan berbiaya seam 4, jadi
// tanpa jalan keluar vokal ia terpaksa memakai `Cindrward` yang tersandung.
export const MORPHEME_ADULT_TAILS = Object.freeze([
  "ward",
  "kin",
  "brood",
  "elder",
  // Head berkoda klaster seperti `cindr` masih berbiaya seam 4 di depan konsonan
  // apa pun, jadi kolam ini tetap butuh jalan keluar berawal vokal.
  "adon",
  "bastion",
]);
// Morfem gelar wajib pendek. Terukur: `monolith` dan `paragon` di atas head lima
// huruf melewati 12 karakter dan dijatuhkan lantai struktur, sehingga kolam yang
// benar-benar diterima menyusut ke tiga entri dan sembilan lineage kembali
// berima `-aegis` — persis keluhan operator terhadap `-gos`/`-korax`/`-egis`.
// Pokémon sendiri memakai gelar pendek yang bertabrakan dengan kata nyata —
// Nidoking, Slowking, Charizard — jadi `king` dan `zard` sah di sini, dan
// keduanya satu suku kata sehingga Evolved tidak wajib memanjang.
export const MORPHEME_EVOLVED_TAILS = Object.freeze([
  "sovran",
  "titan",
  "zenith",
  "astral",
  "aegis",
  "apex",
  "aeon",
  "aether",
  "king",
  "zard",
  "myth",
  "doom",
]);

/**
 * Morfem anatomi yang jujur: kunci di kiri hanya dipakai kalau Plan benar-benar
 * menyebut salah satu kata di kanan. Urutannya deterministik, dan yang cocok
 * menjadi kolam preferensi — jadi dua Anima dengan Plan berbeda mendapat ekor
 * berbeda, yang sekalian membubarkan rima Evolved.
 */
const MORPHEME_PLAN_FEATURES = Object.freeze([
  ["antler", ["antler"]],
  ["horn", ["horn"]],
  ["crest", ["crest", "crown", "diadem"]],
  ["mane", ["mane", "ruff", "fringe"]],
  ["maw", ["maw", "jaw", "fang", "tusk"]],
  ["talon", ["talon", "claw"]],
  ["coil", ["coil", "serpentine", "sinuous", "undulat"]],
  ["carapace", ["carapace", "armor", "armour", "plated", "plating"]],
  ["husk", ["husk", "shell", "chitin"]],
  ["spine", ["spine", "spike", "quill", "barb"]],
  ["pinion", ["wing", "pinion", "sail"]],
  ["frond", ["frond", "leaf", "foliage", "petal"]],
  ["tendril", ["tendril", "vine", "root", "creeper"]],
  ["mantle", ["mantle", "cloak", "shroud", "cape", "drape"]],
  ["spire", ["spire", "tower", "column", "pillar"]],
  ["crag", ["crag", "boulder", "stone", "rock"]],
]);

export const MORPHEME_PLAN_FEATURE_TAILS = Object.freeze(
  MORPHEME_PLAN_FEATURES.map(([tail]) => tail),
);

/**
 * Morfem yang menjanjikan bagian tubuh. `-horn` cuma contoh yang paling terlihat;
 * `-coil` pada konsol, `-pelt` pada naga bersisik, dan `-thorn` pada Monstera
 * tanpa duri adalah janji yang sama. Di stage evolusi keseluruhan kelas ini hanya
 * boleh lolos kalau Plan-nya sendiri yang menyebutkannya, sebab Plan adalah
 * dokumen authoritative tentang tubuh barunya. Capture memakai gerbang yang sama
 * atas `signature_features`, kecuali morfem permukaan di bawah.
 */
export const MORPHEME_BODY_TAILS = new Set([
  ...MORPHEME_PLAN_FEATURE_TAILS,
  "thorn",
  "bloom",
  "acanth",
  "spur",
  "plume",
  "quill",
  "shroud",
  "root",
  "vine",
  "pelt",
  "fang",
  // `usk` cuma potongan elisi dari `husk`, jadi ia menjanjikan hal yang sama.
  "usk",
]);

/**
 * Cangkang adalah satu-satunya pengecualian: setiap objek punya kulit luar, dan
 * `Cindrusk` dibangun tepat begitu. Bulu, karapas, dan mantel tidak ikut — bulu
 * pada naga bersisik (`Dracopelt`, terukur) adalah janji yang sama dengan tanduk
 * pada Anima tanpa tanduk. Stage evolusi tetap memakai gerbang penuh.
 */
const MORPHEME_SURFACE_TAILS = new Set(["husk", "usk"]);

function featureTailsFromText(parts) {
  const text = parts
    .flat()
    .map((value) => String(value ?? ""))
    .join(" ")
    .toLowerCase();
  return MORPHEME_PLAN_FEATURES
    .filter(([, words]) => words.some((word) => text.includes(word)))
    .map(([tail]) => tail);
}

function planFeatureTails(plan) {
  return featureTailsFromText([
    plan?.stage_brief,
    plan?.transformation_archetype,
    plan?.mobility_contract?.locomotion_mode,
    plan?.mobility_contract?.support_read,
    plan?.silhouette_break_contract?.new_contour_read,
    Array.isArray(plan?.shape_budget_contract?.primary_shapes)
      ? plan.shape_budget_contract.primary_shapes
      : [],
  ]);
}

/**
 * Capture tidak punya Evolution Plan, tetapi ia punya `signature_features` dan
 * `creature_brief` — sumber yang sama baiknya. Tanpa ini `Fenesthorn` terukur
 * pada Monstera tanpa duri: aturan anatomi hanya berlaku di stage evolusi
 * sementara capture bebas menjanjikan apa pun.
 */
function captureFeatureTails(vision) {
  return featureTailsFromText([
    vision?.creature_brief,
    vision?.object_label,
    vision?.species_key,
    vision?.surface_finish,
    Array.isArray(vision?.signature_features) ? vision.signature_features : [],
    Array.isArray(vision?.damage_hints) ? vision.damage_hints : [],
  ]);
}

export const MORPHEME_CAPTURE_POOL = Object.freeze(
  Object.values(MORPHEME_CAPTURE_TAILS).flat(),
);

function morphemeFamily(element) {
  return MORPHEME_ELEMENT_FAMILIES[normalizeElement(element, "stone")]
    ?? "mineral";
}

/**
 * Yang membuat nama dua morfem sulit dibaca bukan klaster di mana pun, tetapi
 * klaster yang benar-benar lahir di sambungannya. Terukur pada kesembilan nama
 * Sugarworks yang disetujui operator, biaya seam-nya selalu <= 2: `nox|coil` 2,
 * `rime|spin` 2, `amber|mire` 2, sementara `cindr|usk` dan `dusk|adon` justru 0
 * karena tail-nya mulai vokal dan coda head tidak bertemu konsonan apa pun.
 * Dry run v41 menghasilkan `cindr|volt` (4) dan `glaz|shard` (3) yang tersandung
 * dibaca. Karena hanya sambungannya yang dihitung, aturan ini hidup di sini dan
 * bukan sebagai penalti global di `nameStructureScore` — versi global itulah yang
 * tadi menjatuhkan Velastra dan Cindrusk.
 */
function morphemeSeamOk(head, tail) {
  const elided = /[aeiou]$/.test(head) && /^[aeiou]/.test(tail);
  const joinedTail = elided ? tail.slice(1) : tail;
  // Pokémon berhenti di sekitar sepuluh huruf (Crabominable dua belas), dan batas
  // ini menggantikan seluruh fungsi skor yang dulu menjaga panjang — sekalian
  // memberi nama dua suku kata jalan masuk yang tidak ia punya sebelumnya.
  if (head.length + joinedTail.length > 12) return false;
  // Elisi yang menyisakan potongan terlalu pendek menghapus morfemnya: `elisk`
  // masih terbaca sebagai `lisk` (Nimbelisk), sedangkan `usk` tinggal `sk`.
  if (joinedTail.length < 3) return false;
  // Elisi yang menyisakan vokal kedua hanya memindahkan tumpukannya: `glide` +
  // `aeon` menjadi `Glideeon`. Kesembilan nama Sugarworks tidak memakai elisi
  // sama sekali, jadi aturan ini tidak menyentuh satu pun di antaranya.
  // Potongan elisi harus tetap berupa suku kata: satu konsonan lalu vokal. `elisk`
  // menjadi `lisk` (Nimbelisk) dan `adon` menjadi `don`, tetapi `elder` menjadi
  // `lder` yang tidak bisa diucapkan — terukur sebagai `Dracolder`.
  if (elided && !/^[^aeiou][aeiou]/.test(joinedTail)) return false;
  const onset = (joinedTail.match(/^[^aeiou]*/) ?? [""])[0].length;
  if (!onset) return true;
  // `y` di ujung head berbunyi vokal — `cozy` tidak berkoda `zy`. Tanpa ini
  // Cozyweave, Cozyfold, dan Cozyseam semuanya tertolak dan seluruh head
  // berakhiran y terpaksa memakai satu-satunya tail berawal vokal.
  const coda = (head.match(/[^aeiouy]*$/) ?? [""])[0].length;
  // Batasnya tiga, bukan dua. Dua terukur mengunci setiap head berkoda ganda
  // (`dash`, `dusk`) pada tail berawal vokal, dan tail berawal vokal selalu dua
  // suku kata — itulah sebabnya sembilan nama terakhir semuanya tiga suku kata.
  // Tiga membuka `Dashcoil` dan `Duskfang`; `Cindrvolt` tetap tertutup di empat.
  return coda + onset <= 3;
}

/**
 * Nama adalah placeholder — pemain boleh me-rename kapan pun — jadi aturannya
 * tinggal tiga: tidak kasar, sambungannya bisa dibaca, dan tidak mengulang
 * morfem head-nya. Lantai skor, seleksi 32 kandidat, dan tiga tingkat fallback
 * v39–v41 sudah dibuang: justru gerbang-gerbang itu yang menyusutkan kolam
 * sampai sembilan nama berturut-turut berakhir tiga suku kata dengan ekor yang
 * berulang. Kolam lebar + satu pilihan hash memberi variasi lebih banyak dengan
 * kode lebih sedikit; sesekali ada nama kaku, dan pemain bisa menggantinya.
 */
/**
 * FNV-1a sendiri tidak cukup tersebar untuk dipakai langsung sebagai indeks:
 * `seed % 4` terukur memilih hanya dua dari empat cadence family di v40, dan
 * `seed >>> 8` terukur memberi ekor Adult yang sama pada tiga dari enam Anima.
 * Keduanya adalah tebakan tentang bit mana yang aman. Finalizer lowbias32 ini
 * mengaduk seluruh 32 bit sekali, sehingga indeks apa pun boleh memakai modulo
 * apa adanya. Deterministik, jadi Anima yang sama tetap mendapat nama yang sama.
 */
function mixNameSeed(seed) {
  let x = seed >>> 0;
  x ^= x >>> 16;
  x = Math.imul(x, 0x7feb352d);
  x ^= x >>> 15;
  x = Math.imul(x, 0x846ca68b);
  x ^= x >>> 16;
  return x >>> 0;
}

function selectMorphemeName(head, tails, seed, takenNames = []) {
  const taken = new Set(takenNames.filter(Boolean).map((name) =>
    String(name).toLowerCase()
  ));
  const build = (strictSeam) =>
    [...new Set(tails)]
      // `lume` + `lume` menggagap, jadi ekor yang mengulang head dibuang.
      .filter((tail) => !head.startsWith(tail) && !tail.startsWith(head))
      .map((tail) => ({ tail, name: joinNameRoot(head, tail) }))
      .filter(({ name, tail }) =>
        nameIsSafeForPlayers(name) && (!strictSeam || morphemeSeamOk(head, tail))
      );
  // Head tanpa satu pun seam terbaca tetap harus mendapat nama; yang tidak aman
  // tidak pernah dilonggarkan.
  const pool = build(true).length ? build(true) : build(false);
  // Menghindari nama stage sebelumnya bersifat usaha terbaik, bukan gerbang:
  // Plan yang hanya menyebut satu anatomi pernah membuat kolamnya habis dan
  // derivasi melempar, dan evolusi berbayar tidak boleh gagal karena nama.
  const fresh = pool.filter((item) => !taken.has(item.name.toLowerCase()));
  const usable = fresh.length ? fresh : pool;
  if (!usable.length) {
    throw new Error(`morfem aman tidak tersedia untuk head '${head}'`);
  }
  return usable[mixNameSeed(seed) % usable.length];
}

/**
 * `takenNames` adalah nama yang sudah dipakai koleksi pemilik. Dedup-nya usaha
 * terbaik dengan alasan yang sama seperti di evolusi: kolam morfem satu head
 * bisa habis, dan menggagalkan capture berbayar demi keunikan nama adalah
 * pertukaran yang salah — nama kembar bisa di-rename pemain, $0.07 tidak.
 */
export function deriveMorphemeSpeciesName(vision, takenNames = []) {
  // Pagar v39 yang dipertahankan: penamaan tidak boleh menggagalkan capture
  // berbayar. Akar yang tidak terpakai jatuh ke fonotaktik deterministik dan
  // tetap melewati gerbang morfem yang sama.
  let candidate;
  try {
    candidate = normalizeNameRoots(vision, true, true)[0];
  } catch (error) {
    candidate = {
      root: deriveDeterministicSpeciesName(vision).name_lineage_anchor,
      channel: "structure",
      evidence: "root fallback",
      copiesIdentity: false,
      root_fallback: String(error.message ?? error),
    };
  }
  const family = morphemeFamily(vision?.element);
  const seed = nameHash([
    vision?.species_key,
    vision?.subject_kind,
    vision?.element,
    vision?.secondary_element,
    vision?.creature_brief,
    ...(
      Array.isArray(vision?.signature_features) ? vision.signature_features : []
    ),
  ].join("|").toLowerCase());
  // Morfem bagian tubuh hanya boleh dipakai kalau Vision benar-benar melihatnya:
  // `-thorn` pada Monstera tanpa duri adalah janji yang sama dengan `-horn` pada
  // Anima tanpa tanduk. Pengurangannya bisa mengosongkan keluarga tipis, jadi
  // keluarga penuh tetap jadi jaring terakhir.
  const seen = captureFeatureTails(vision);
  const family_tails = MORPHEME_CAPTURE_TAILS[family].filter((tail) =>
    !MORPHEME_BODY_TAILS.has(tail) || MORPHEME_SURFACE_TAILS.has(tail) ||
    seen.includes(tail)
  );
  const chosen = selectMorphemeName(
    candidate.root,
    family_tails.length ? family_tails : MORPHEME_CAPTURE_TAILS[family],
    seed,
    takenNames,
  );
  return {
    suggested_name: chosen.name,
    name_lineage_anchor: candidate.root,
    selected_name_root: {
      ...candidate,
      element_family: family,
      morpheme_tail: chosen.tail,
    },
  };
}

export function deriveMorphemeEvolutionName(
  anchor,
  plan,
  targetStage,
  element,
  takenNames = [],
) {
  const normalizedAnchor = normalizeNameLineageAnchor(anchor);
  if (!/^[a-z]{3,5}$/.test(normalizedAnchor) || !/[aeiou]/.test(normalizedAnchor)) {
    throw new Error(`name_lineage_anchor morfem tidak sah: '${anchor}'`);
  }
  const seed = nameHash([
    normalizedAnchor,
    targetStage,
    plan?.transformation_archetype,
    plan?.stage_brief,
    plan?.mobility_contract?.locomotion_mode,
    plan?.silhouette_break_contract?.new_contour_read,
  ].join("|").toLowerCase());
  const stageTails = Number(targetStage) >= 3
    ? MORPHEME_EVOLVED_TAILS
    : MORPHEME_ADULT_TAILS;
  // Aturan anatomi bersifat **negatif**: morfem bagian tubuh hanya boleh muncul
  // kalau Plan memang menyebutnya, sebab `-horn` pada Anima tanpa tanduk adalah
  // janji yang pemain lihat bersebelahan dengan sprite-nya. Ia bukan aturan
  // positif — memaksa anatomi menang membuat Plan bersatu fitur mengunci setiap
  // Adult pada morfem yang sama, terukur `Glidhusk`/`Celerhusk`/`Glazehusk`.
  // Jadi anatomi ikut ke kolam, bukan menggantikan kolamnya.
  const tails = [
    ...planFeatureTails(plan),
    ...stageTails,
    ...MORPHEME_CAPTURE_TAILS[morphemeFamily(element)]
      .filter((tail) => !MORPHEME_BODY_TAILS.has(tail)),
  ];
  return selectMorphemeName(normalizedAnchor, tails, seed, takenNames).name;
}

export function normalizeMoveName(name, fallback = "") {
  const words = String(name ?? "")
    .trim()
    .replace(/\s+/g, " ")
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1));
  const candidate = words.join(" ").slice(0, 24);
  if (!candidate) return fallback;
  if (/mon$/i.test(candidate.replace(/\s/g, ""))) {
    const stem = candidate.replace(/\s*mon$/i, "").trim();
    return stem.length >= 2 ? stem.slice(0, 24) : fallback;
  }
  return candidate;
}

export const VFX_MOTIONS = ["projectile", "sweep", "impact", "bloom"];
export const VFX_FORMS = [
  "arc", "beam", "trail", "wave", "eruption", "ring",
  "scatter", "tether", "stamp", "cloud", "shatter", "growth",
];

export function normalizeVfxPlan(value, fallback) {
  const raw = value && typeof value === "object" ? value : {};
  const form = VFX_FORMS.includes(raw.form) ? raw.form : fallback.form;
  const motion = VFX_MOTIONS.includes(raw.motion) ? raw.motion : fallback.motion;
  const brief = String(raw.brief ?? "").trim().replace(/\s+/g, " ").slice(0, 240)
    || fallback.brief;
  return { form, motion, brief };
}

/**
 * Schema menjamin bentuk, bukan kewajaran isi. Pemeriksaan di sini menegakkan
 * hal-hal yang tidak bisa diungkapkan di responseSchema Gemini.
 */
export function validateVision(
  v,
  knownSpecies = [],
  requireMaterial = false,
  requireCharacter = false,
  requireMoves = false,
  requireVfx = false,
  requireTypingV13 = false,
  allowAnimals = false,
  skipSpeciesDedup = false,
  requireBodyHeight = false,
  requireNameLineage = false,
  requirePronounceableNameLineage = false,
  requireNameQuality = false,
  requireDeterministicName = false,
  requireHybridName = false,
  requireTransformedHybridName = false,
  requireCuratedHybridName = false,
  requireMorphemeName = false,
  takenNames = [],
) {
  const issues = [];

  if (!v.safe || !v.is_object) {
    return { gate: "rejected", reason: v.reject_reason ?? "unknown", issues, vision: v };
  }

  if (requireTypingV13) {
    const kind = String(v.subject_kind ?? "").trim().toLowerCase();
    if (kind !== "object" && kind !== "animal") {
      throw new Error(`subject_kind tidak sah: ${JSON.stringify(v.subject_kind)}`);
    } else {
      v.subject_kind = kind;
    }
    if (kind === "animal" && !allowAnimals) {
      return { gate: "rejected", reason: "live_animal", issues, vision: v };
    }
  }

  if (!v.species_key || !/^[a-z]+(_[a-z]+){1,3}$/.test(v.species_key)) {
    issues.push(`species_key tidak sesuai format: ${JSON.stringify(v.species_key)}`);
  } else if (!skipSpeciesDedup) {
    // Normalisasi ke kunci yang sudah ada supaya typo tidak memecah cache.
    // Satu huruf beda berarti dua entri cache dan dua kali biaya generation.
    for (const known of knownSpecies) {
      if (known !== v.species_key && levenshtein(known, v.species_key) <= 2) {
        issues.push(`species_key '${v.species_key}' dinormalisasi ke '${known}'`);
        v.species_key = known;
        break;
      }
    }
  }

  if (requireTypingV13) {
    const primary = normalizeElement(v.element, "");
    if (!isRosterElement(primary)) {
      throw new Error(`element di luar roster v13: ${JSON.stringify(v.element)}`);
    } else {
      v.element = primary;
    }

    const rawSecondary = v.secondary_element;
    if (rawSecondary == null || String(rawSecondary).trim() === "") {
      v.secondary_element = null;
    } else {
      const secondary = normalizeElement(rawSecondary, "");
      if (!isRosterElement(secondary)) {
        issues.push(`secondary_element di luar roster v13: ${JSON.stringify(rawSecondary)}`);
      } else if (secondary === v.element) {
        issues.push("secondary_element tidak boleh sama dengan element");
        v.secondary_element = null;
      } else {
        v.secondary_element = secondary;
      }
    }

    if (v.subject_kind === "animal" && v.element !== "fauna") {
      issues.push("hewan wajib element primary fauna");
      v.element = "fauna";
    }
  }

  if (v.stats) {
    const sum = Object.values(v.stats).reduce((a, b) => a + b, 0);
    if (sum < 200 || sum > 350) {
      const target = Math.min(350, Math.max(200, sum));
      const factor = target / sum;
      for (const k of Object.keys(v.stats)) {
        v.stats[k] = Math.max(10, Math.min(95, Math.round(v.stats[k] * factor)));
      }
      issues.push(`jumlah stat ${sum} di luar 200-350, diskalakan proporsional`);
    }
  } else {
    issues.push("stats kosong");
  }

  if (requireBodyHeight) {
    const height = Number(v.body_height_cm);
    if (!Number.isInteger(height) || height < 20 || height > 2000) {
      throw new Error(`body_height_cm tidak sah: ${JSON.stringify(v.body_height_cm)}`);
    }
    v.body_height_cm = height;
  }

  const vague = /^(unique|interesting|nice|cool|various|some)\b|qualities$|texture$/i;
  const feats = v.signature_features ?? [];
  if (feats.length < 2) issues.push("signature_features kurang dari 2");
  for (const f of feats) {
    if (vague.test(f.trim())) issues.push(`signature_feature kabur: "${f}"`);
  }

  if (requireMorphemeName) {
    const generatedName = deriveMorphemeSpeciesName(v, takenNames);
    v.suggested_name = generatedName.suggested_name;
    v.name_lineage_anchor = generatedName.name_lineage_anchor;
    v.selected_name_root = generatedName.selected_name_root;
    delete v.name_quality;
  } else if (requireCuratedHybridName) {
    const generatedName = deriveCuratedHybridSpeciesName(v);
    v.suggested_name = generatedName.suggested_name;
    v.name_lineage_anchor = generatedName.name_lineage_anchor;
    v.selected_name_root = generatedName.selected_name_root;
    delete v.name_quality;
  } else if (requireTransformedHybridName) {
    const generatedName = deriveTransformedHybridSpeciesName(v);
    v.suggested_name = generatedName.suggested_name;
    v.name_lineage_anchor = generatedName.name_lineage_anchor;
    v.selected_name_root = generatedName.selected_name_root;
    delete v.name_quality;
  } else if (requireHybridName) {
    const generatedName = deriveHybridSpeciesName(v);
    v.suggested_name = generatedName.suggested_name;
    v.name_lineage_anchor = generatedName.name_lineage_anchor;
    v.selected_name_root = generatedName.selected_name_root;
    delete v.name_quality;
  } else if (requireDeterministicName) {
    const generatedName = deriveDeterministicSpeciesName(v);
    v.suggested_name = generatedName.suggested_name;
    v.name_lineage_anchor = generatedName.name_lineage_anchor;
    delete v.name_quality;
  }
  if (requireNameLineage) {
    // Aturan "pronounceable" v33 menolak tiga konsonan beruntun, dan itu akan
    // diam-diam mengganti anchor morfem v41 seperti `cindr` — head milik Cindrusk
    // yang disetujui operator — dengan potongan lain. Anchor v41 datang dari
    // validator morfem server, jadi pagar itu tidak berlaku di jalur ini.
    const pronounceableAnchor = requirePronounceableNameLineage
      && !requireMorphemeName;
    const normalizedName = normalizeSuggestedName(v.suggested_name, "");
    if (!normalizedName) throw new Error("suggested_name wajib untuk name lineage");
    v.suggested_name = normalizedName;
    try {
      v.name_lineage_anchor = validateNameLineageAnchor(
        v.name_lineage_anchor,
        normalizedName,
        pronounceableAnchor,
      );
    } catch {
      const derived = deriveNameLineageAnchor(
        normalizedName,
        v.name_lineage_anchor,
        pronounceableAnchor,
      );
      issues.push(
        `name_lineage_anchor '${v.name_lineage_anchor ?? ""}' dinormalisasi ke '${derived}'`,
      );
      v.name_lineage_anchor = derived;
    }
  } else if (v.suggested_name?.trim()) {
    const fallbackName = String(v.species_key ?? "Anima").split("_")[0] || "Anima";
    const normalizedName = normalizeSuggestedName(v.suggested_name, fallbackName);
    if (normalizedName !== v.suggested_name.trim()) {
      issues.push(`suggested_name '${v.suggested_name}' dinormalisasi ke '${normalizedName}'`);
      v.suggested_name = normalizedName;
    }
  }
  if (requireNameQuality) {
    if (!v.name_quality || typeof v.name_quality !== "object" || Array.isArray(v.name_quality)) {
      throw new Error("name_quality wajib untuk name lineage v35");
    }
    for (const key of NAME_QUALITY_KEYS) {
      if (v.name_quality[key] !== true) {
        throw new Error(`name_quality.${key} wajib true`);
      }
    }
  }

  // Field material baru mulai v4. v1-v3 sengaja tidak punya keduanya, jadi
  // jangan membuat output prompt lama tampak rusak hanya karena helper-nya
  // dipakai bersama. Begitu salah satu hadir, kontrak v4 harus lengkap.
  if (requireMaterial) {
    if (!v.surface_finish?.trim()) issues.push("surface_finish kosong");
    if ((v.damage_hints ?? []).length < 2) issues.push("damage_hints kurang dari 2");
  }
  if (requireCharacter && !v.character_direction?.trim()) {
    issues.push("character_direction kosong");
  }
  if (requireMoves) {
    const strike = normalizeMoveName(v.strike_name);
    const surge = normalizeMoveName(v.surge_name);
    if (!strike) issues.push("strike_name kosong");
    else if (strike !== String(v.strike_name ?? "").trim()) {
      issues.push(`strike_name '${v.strike_name}' dinormalisasi ke '${strike}'`);
    }
    if (!surge) issues.push("surge_name kosong");
    else if (surge !== String(v.surge_name ?? "").trim()) {
      issues.push(`surge_name '${v.surge_name}' dinormalisasi ke '${surge}'`);
    }
    if (strike && surge && strike.toLowerCase() === surge.toLowerCase()) {
      issues.push("strike_name dan surge_name tidak boleh sama");
    }
    v.strike_name = strike;
    v.surge_name = surge;
  }
  if (requireVfx) {
    const strikeFallback = {
      form: "arc",
      motion: "sweep",
      brief: "a compact object-faithful contact arc shaped by one photographed structural feature",
    };
    const surgeFallback = {
      form: "eruption",
      motion: "bloom",
      brief: "a larger object-faithful radial effect grown from the material and strongest structural feature",
    };
    const strike = normalizeVfxPlan(v.strike_vfx, strikeFallback);
    const surge = normalizeVfxPlan(v.surge_vfx, surgeFallback);
    if (!v.strike_vfx?.brief?.trim()) issues.push("strike_vfx brief kosong");
    if (!VFX_FORMS.includes(v.strike_vfx?.form)) issues.push("strike_vfx form tidak sah");
    if (!VFX_MOTIONS.includes(v.strike_vfx?.motion)) issues.push("strike_vfx motion tidak sah");
    if (!v.surge_vfx?.brief?.trim()) issues.push("surge_vfx brief kosong");
    if (!VFX_FORMS.includes(v.surge_vfx?.form)) issues.push("surge_vfx form tidak sah");
    if (!VFX_MOTIONS.includes(v.surge_vfx?.motion)) issues.push("surge_vfx motion tidak sah");
    if (strike.form === surge.form) {
      issues.push(`strike_vfx dan surge_vfx tidak boleh sama-sama ${strike.form}`);
      surge.form = surgeFallback.form === strike.form ? "ring" : surgeFallback.form;
    }
    if (strike.motion === surge.motion) {
      issues.push(`strike_vfx dan surge_vfx tidak boleh sama-sama ${strike.motion}`);
      surge.motion = surgeFallback.motion === strike.motion ? "impact" : surgeFallback.motion;
    }
    v.strike_vfx = strike;
    v.surge_vfx = surge;
  }

  return { gate: "passed", reason: null, issues, vision: v };
}

export const CAPTURE_VIBES = Object.freeze(["natural", "cute", "brave", "wild", "sinister"]);

/** Client lama / field kosong = Natural. Nilai di luar allowlist = null. */
export function normalizeCaptureVibe(value) {
  if (value == null || value === "") return "natural";
  if (typeof value !== "string") return null;
  const slug = value.trim().toLowerCase();
  return CAPTURE_VIBES.includes(slug) ? slug : null;
}

export function assemblePrompt(template, vision, vibe = "natural", vibeDirections = null) {
  const features = vision.signature_features ?? [];
  const bullets = features.map((f) => `- ${f}`).join("\n");
  const technicalTokens = new Set([
    "cable", "cord", "wire", "circuit", "gear", "key", "screen", "plug",
    "component", "joint", "skeleton", "machine", "machinery",
  ]);
  const aliases = {
    cables: "cable", cords: "cord", wires: "wire", circuits: "circuit",
    gears: "gear", keys: "key", screens: "screen", plugs: "plug",
    components: "component", joints: "joint", skeletons: "skeleton",
    machines: "machine", machinery: "machine", mechanical: "machine",
  };
  const canonical = (token) => aliases[token] ?? token;
  const featureTokens = new Set(
    (features.join(" ").toLowerCase().match(/[a-z]+/g) ?? []).map(canonical)
  );
  const damageHints = (vision.damage_hints ?? []).filter((hint) => {
    const tokens = (hint.toLowerCase().match(/[a-z]+/g) ?? []).map(canonical);
    return !tokens.some((token) => technicalTokens.has(token) && !featureTokens.has(token));
  });
  const surface = vision.surface_finish?.trim() || "the object's visibly photographed material";
  if (damageHints.length < 2) {
    damageHints.push(`one small localized sign of damage that physically fits ${surface}`);
  }
  if (damageHints.length < 2) {
    damageHints.push("one second distinct low-severity material change, with no invented internal machinery");
  }
  const damageBullets = damageHints.map((hint) => `- ${hint}`).join("\n");
  const stats = vision.stats ?? {};
  const dominantStat = Object.entries(stats).sort((a, b) => b[1] - a[1])[0]?.[0];
  const materialAware = template.includes("{{surface_finish}}");
  const characterAware = template.includes("{{character_direction}}");
  const personalities = {
    hp: "sturdy, calm, dependable, and hard to intimidate",
    atk: characterAware
      ? "bold, spirited, direct, and eager to prove its strength without looking angry at rest"
      : "bold, fierce, confrontational, and eager to prove its strength",
    def: "stoic, protective, stubborn, and quietly confident",
    spd: "agile, impatient, competitive, and playfully restless",
    special: materialAware
      ? "clever, strange, mischievous, and charged with hidden functional energy"
      : "clever, strange, mischievous, and charged with hidden technical energy",
  };
  const captureVibe = normalizeCaptureVibe(vibe) ?? "natural";
  const vibeLock = vibeDirections?.[captureVibe] ?? vibeDirections?.natural ?? null;
  const personality = (
    captureVibe !== "natural"
    && typeof vibeLock?.personality === "string"
    && vibeLock.personality.trim()
      ? vibeLock.personality.trim()
      : personalities[dominantStat] ?? "curious, expressive, and slightly mischievous"
  );
  const characterDirection = vision.character_direction?.trim()
    || "visually neutral and object-led, without forced gender coding";
  const vibeDirection = typeof vibeLock?.direction === "string" ? vibeLock.direction.trim() : "";
  const colors = (vision.dominant_colors ?? []).join(", ") || vision.color_bucket || "object-derived palette";
  const out = template
    .replaceAll("{{creature_brief}}", vision.creature_brief ?? "")
    .replaceAll("{{signature_features_as_bullets}}", bullets)
    .replaceAll("{{object_name}}", vision.object_label ?? vision.species_key ?? "unknown object")
    .replaceAll("{{color_palette}}", colors)
    .replaceAll("{{personality}}", personality)
    .replaceAll("{{surface_finish}}", surface)
    .replaceAll("{{character_direction}}", characterDirection)
    .replaceAll("{{vibe_direction}}", vibeDirection)
    .replaceAll("{{damage_hints_as_bullets}}", damageBullets)
    .replaceAll("{{strike_name}}", vision.strike_name?.trim() || "a close-range strike")
    .replaceAll("{{surge_name}}", vision.surge_name?.trim() || "a charged special burst")
    .replaceAll("{{strike_vfx_form}}", vision.strike_vfx?.form || "arc")
    .replaceAll("{{strike_vfx_motion}}", vision.strike_vfx?.motion || "sweep")
    .replaceAll(
      "{{strike_vfx_brief}}",
      vision.strike_vfx?.brief || "a compact object-faithful contact effect"
    )
    .replaceAll("{{surge_vfx_form}}", vision.surge_vfx?.form || "eruption")
    .replaceAll("{{surge_vfx_motion}}", vision.surge_vfx?.motion || "bloom")
    .replaceAll(
      "{{surge_vfx_brief}}",
      vision.surge_vfx?.brief || "a larger object-faithful radial effect"
    );

  const leftover = out.match(/\{\{[a-z_]+\}\}/g);
  if (leftover) throw new Error(`placeholder belum terisi: ${leftover.join(", ")}`);
  return out;
}

/** Pilih template sheet object vs fauna bila versi prompt menyediakan keduanya. */
export function spriteSheetTemplate(prompts, subjectKind = "object") {
  if (subjectKind === "animal" && prompts.sprite_sheet_fauna) {
    return prompts.sprite_sheet_fauna;
  }
  return prompts.sprite_sheet;
}

/**
 * Kontrak keluaran yang disisipkan ke system_instruction. Skema tetap dipakai,
 * tapi sebagai bagian dari instruksi, bukan sebagai parameter API: menyertakan
 * kontraknya secara literal jauh lebih efektif daripada mendeskripsikannya
 * dalam prosa, dan wrapper-nya tidak punya response_schema.
 */
export function visionInstruction(systemPrompt, schema) {
  return (
    `${systemPrompt}\n\n---\n\n## OUTPUT CONTRACT\n\n` +
    "Respond with a single JSON object and nothing else. No markdown fences, " +
    "no explanation before or after. It must conform to this schema:\n\n" +
    `${JSON.stringify(schema, null, 2)}\n`
  );
}
