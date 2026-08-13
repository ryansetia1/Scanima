// Parsing keluaran Vision, penegakan kewajaran isinya, dan perakitan prompt
// gambar. Satu file untuk dua runtime, alasannya sama dengan postprocess.mjs:
// yang diputuskan di sini menentukan apakah kita membayar $0.07 atau tidak, dan
// species_key yang bergeser satu huruf berarti dua entri cache untuk satu benda.
// Dua salinan berarti eval bisa lulus sementara produksi memakai aturan lain.

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

/**
 * Schema menjamin bentuk, bukan kewajaran isi. Pemeriksaan di sini menegakkan
 * hal-hal yang tidak bisa diungkapkan di responseSchema Gemini.
 */
export function validateVision(
  v,
  knownSpecies = [],
  requireMaterial = false,
  requireCharacter = false
) {
  const issues = [];

  if (!v.safe || !v.is_object) {
    return { gate: "rejected", reason: v.reject_reason ?? "unknown", issues, vision: v };
  }

  if (!v.species_key || !/^[a-z]+(_[a-z]+){1,3}$/.test(v.species_key)) {
    issues.push(`species_key tidak sesuai format: ${JSON.stringify(v.species_key)}`);
  } else {
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
    .replaceAll("{{damage_hints_as_bullets}}", damageBullets);

  const leftover = out.match(/\{\{[a-z_]+\}\}/g);
  if (leftover) throw new Error(`placeholder belum terisi: ${leftover.join(", ")}`);
  return out;
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
