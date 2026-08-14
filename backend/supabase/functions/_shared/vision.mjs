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
export function extractJson(raw) {
  const text = Array.isArray(raw) ? raw.join("") : String(raw ?? "");
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = (fenced ? fenced[1] : text).trim();

  try {
    return JSON.parse(candidate);
  } catch {
    // Model kadang menambah kalimat pengantar meski dilarang. Ambil dari kurung
    // kurawal pertama sampai yang terakhir.
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start > -1 && end > start) {
      try {
        return JSON.parse(candidate.slice(start, end + 1));
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

  const vague = /^(unique|interesting|nice|cool|various|some)\b|qualities$|texture$/i;
  const feats = v.signature_features ?? [];
  if (feats.length < 2) issues.push("signature_features kurang dari 2");
  for (const f of feats) {
    if (vague.test(f.trim())) issues.push(`signature_feature kabur: "${f}"`);
  }

  if (v.suggested_name?.trim()) {
    const fallbackName = String(v.species_key ?? "Anima").split("_")[0] || "Anima";
    const normalizedName = normalizeSuggestedName(v.suggested_name, fallbackName);
    if (normalizedName !== v.suggested_name.trim()) {
      issues.push(`suggested_name '${v.suggested_name}' dinormalisasi ke '${normalizedName}'`);
      v.suggested_name = normalizedName;
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

export function assemblePrompt(template, vision) {
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
  const personality = personalities[dominantStat] ?? "curious, expressive, and slightly mischievous";
  const characterDirection = vision.character_direction?.trim()
    || "visually neutral and object-led, without forced gender coding";
  const colors = (vision.dominant_colors ?? []).join(", ") || vision.color_bucket || "object-derived palette";
  const out = template
    .replaceAll("{{creature_brief}}", vision.creature_brief ?? "")
    .replaceAll("{{signature_features_as_bullets}}", bullets)
    .replaceAll("{{object_name}}", vision.object_label ?? vision.species_key ?? "unknown object")
    .replaceAll("{{color_palette}}", colors)
    .replaceAll("{{personality}}", personality)
    .replaceAll("{{surface_finish}}", surface)
    .replaceAll("{{character_direction}}", characterDirection)
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
