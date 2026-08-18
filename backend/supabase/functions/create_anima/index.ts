// POST /create_anima  { photo_path, idempotency_key, nickname?, capture_vibe? }
//
// Satu-satunya endpoint yang bisa membelanjakan uang, jadi urutannya bukan
// selera: yang murah dan bisa membatalkan berjalan lebih dulu, dan yang mahal
// hanya berjalan setelah tidak ada lagi alasan untuk menolak.
//
//   1. idempotency  — request yang sama dua kali tidak pernah membayar dua kali
//   2. scan charge  — pagar $0.003, atomik di Postgres
//   3. Vision       — gate keamanan + stat, ditunggu karena hasilnya menentukan
//                     apakah kita berhak mendebit Core
//   4. pustaka      — cache hit berarti art gratis, dan ini jalur yang paling
//                     sering menang begitu pustakanya terisi
//   5. Genesis Core — debit + baris generation dalam satu transaksi
//   6. Replicate    — dipicu lalu dilepas; webhook yang menyelesaikannya
//
// Foto TIDAK diunggah lewat endpoint ini. Client menulis langsung ke bucket
// `photos` dengan anon key-nya, dan yang membatasinya adalah policy Storage
// (folder harus namanya sendiri) plus batas ukuran dan mime milik bucket.
// Menulis endpoint penerbit signed URL berarti menulis ulang pagar yang sudah
// disediakan platform.

import { adminClient, clientVersionGate, json } from "../_shared/supa.ts";
import {
  assemblePrompt,
  extractJson,
  normalizeCaptureVibe,
  normalizeSuggestedName,
  promptMajor,
  spriteSheetTemplate,
  validateVision,
  visionInstruction,
} from "../_shared/vision.mjs";
import { biayaGambarUsd } from "../_shared/pricing.mjs";
import { jalankanPrediksi, mulaiGeneration } from "../_shared/replicate.ts";
import PROMPTS from "../_shared/prompts.generated.ts";

const MODEL_VISION = Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash";
const KUALITAS_GAMBAR = Deno.env.get("IMAGE_QUALITY") ?? "medium";
const STAGE_BAYI = 1;
const TTL_SIGNED_URL = 900; // detik; harus melebihi ~60s generation plus antrean
const CARE_AWAL = { hunger: 100, energy: 100, hygiene: 100, bond: 0 };
const db = adminClient();

function configBool(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value === "true";
  return false;
}

type Vision = {
  species_key: string;
  color_bucket: string;
  element: string;
  secondary_element?: string | null;
  subject_kind?: string;
  rarity: number;
  stats: Record<string, number>;
  body_height_cm?: number;
  suggested_name?: string;
  name_lineage_anchor?: string;
  name_quality?: Record<string, boolean>;
  name_roots?: Array<{ root: string; channel: string; evidence: string }>;
  strike_name?: string;
  surge_name?: string;
  strike_vfx?: { form: string; motion: string; brief: string };
  surge_vfx?: { form: string; motion: string; brief: string };
  creature_brief?: string;
  signature_features?: string[];
  surface_finish?: string;
  damage_hints?: string[];
  character_direction?: string;
  object_label?: string;
  dominant_colors?: string[];
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

  // Autentikasi sebelum apa pun yang lain: uid yang dipakai untuk mendebit
  // datang dari token, tidak pernah dari body.
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: errAuth } = await db.auth.getClaims(token);
  const uid = auth?.claims?.sub;
  if (errAuth || typeof uid !== "string") return json(401, { error: "token tidak sah" });

  let body: {
    photo_path?: string;
    idempotency_key?: string;
    nickname?: string;
    capture_vibe?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const photoPath = body.photo_path ?? "";
  const kunci = body.idempotency_key ?? "";
  if (!kunci || kunci.length > 128) return json(400, { error: "idempotency_key wajib, maks 128 char" });
  const requestedVibe = normalizeCaptureVibe(body.capture_vibe);
  if (requestedVibe == null) return json(400, { error: "INVALID_VIBE" });

  // Batas kepercayaan. Tanpa ini, pemain bisa menunjuk foto pemain lain, dan
  // signed URL yang kita terbitkan dengan service role akan menurutinya.
  if (!photoPath.startsWith(`${uid}/`) || photoPath.includes("..")) {
    return json(403, { error: "photo_path harus di dalam folder milik sendiri" });
  }

  // Model, versi prompt, dan rollout flags dibaca dari tabel supaya rollback
  // kualitas art tidak perlu deploy.
  const { data: konfigRows } = await db
    .from("app_config")
    .select("key, value")
    .in("key", [
      "image_model",
      "prompt_version",
      "feature_typing_v13",
      "feature_unique_generation",
      "feature_animals",
    ]);
  const konfig = Object.fromEntries((konfigRows ?? []).map((r) => [r.key, r.value]));
  let modelGambar = (konfig.image_model as string) ?? "openai/gpt-image-2";
  const versiPromptConfigured = (konfig.prompt_version as string) ?? "v7";
  const featureTypingV13 = configBool(konfig.feature_typing_v13);
  const featureUnique = configBool(konfig.feature_unique_generation);
  const featureAnimals = configBool(konfig.feature_animals);

  let versiPrompt = versiPromptConfigured;
  if (!featureTypingV13 && promptMajor(versiPrompt) >= 13) {
    versiPrompt = "v12";
  }
  let useV13 = promptMajor(versiPrompt) >= 13;
  let allowAnimals = featureAnimals && useV13;
  let useUniqueCapture = featureUnique && useV13;

  const promptBundle = PROMPTS as Record<
    string,
    {
      sprite_sheet: string;
      sprite_sheet_fauna?: string;
      vision_system: string;
      vision_schema: unknown;
      vibe_directions?: Record<string, { personality?: string; direction?: string }>;
    }
  >;
  let prompts = promptBundle[versiPrompt];
  if (!prompts) return json(500, { error: `versi prompt ${versiPrompt} tidak ada di bundel` });

  // ------------------------------------------------------------ idempotency
  const { data: lama } = await db
    .from("generations")
    .select("id, status, anima_id, prediction_id, vision_result, prompt_version, model, capture_vibe")
    .eq("owner_id", uid)
    .eq("idempotency_key", kunci)
    .maybeSingle();

  if (lama && (lama.prediction_id || lama.status !== "pending")) {
    return json(200, {
      idempoten: true,
      generation_id: lama.id,
      anima_id: lama.anima_id,
      status: lama.status,
    });
  }

  // Baris pending tanpa prediction_id berarti percobaan sebelumnya mati setelah
  // Core didebit tapi sebelum Replicate dipicu. Melanjutkannya, bukan memulai
  // dari nol, adalah satu-satunya cara pemain tidak kehilangan Core karena
  // jaringan kita yang putus. Hasil Vision-nya sudah dibayar dan tersimpan.
  //
  // ponytail: celah yang TIDAK ditutup adalah mati setelah Vision tapi sebelum
  // claim_genesis — tidak ada baris apa pun, jadi retry membayar Vision kedua
  // kali. Plafonnya $0.003 per kejadian; menutupnya butuh menyimpan hasil Vision
  // sebelum debit, yaitu satu tulisan tambahan di setiap request untuk melindungi
  // sepertigapuluh sen. Naikkan kalau log menunjukkan ini sering terjadi.
  const lanjutkan = Boolean(lama && !lama.prediction_id && lama.vision_result);
  let captureVibe = requestedVibe;
  if (lama) {
    captureVibe = normalizeCaptureVibe(lama.capture_vibe) ?? "natural";
  }
  if (lanjutkan) {
    // Request yang sudah mendebit Core harus dilanjutkan dengan kontrak model
    // dan prompt yang tercatat, walau operator mematikan flag untuk request baru.
    versiPrompt = lama!.prompt_version ?? versiPrompt;
    modelGambar = lama!.model ?? modelGambar;
    prompts = promptBundle[versiPrompt];
    if (!prompts) {
      return json(500, { error: `versi prompt pending ${versiPrompt} tidak ada di bundel` });
    }
    useV13 = promptMajor(versiPrompt) >= 13;
    allowAnimals = useV13;
    useUniqueCapture = useV13;
  }
  if (captureVibe !== "natural" && promptMajor(versiPrompt) < 31) {
    return json(409, { error: "VIBE_UNAVAILABLE" });
  }

  // ------------------------------------------------------------ signed URL
  const { data: signed, error: errSigned } = await db.storage
    .from("photos")
    .createSignedUrl(photoPath, TTL_SIGNED_URL);
  if (errSigned || !signed?.signedUrl) {
    return json(404, { error: `foto tidak bisa diakses: ${errSigned?.message ?? "tidak ada"}` });
  }
  const urlFoto = signed.signedUrl;

  // ------------------------------------------------------------ Vision
  let vision: Vision;
  if (lanjutkan) {
    vision = lama!.vision_result as Vision;
  } else {
    const { error: errKlaim } = await db.rpc("claim_scan_charge", { p_owner: uid });
    if (errKlaim) {
      if (errKlaim.message.includes("GUEST_SCAN_USED")) {
        await db.storage.from("photos").remove([photoPath]);
        return json(409, { error: "GUEST_SCAN_USED" });
      }
      const kode = errKlaim.message.includes("NO_SCAN_CHARGE") ? 402 : 500;
      return json(kode, { error: errKlaim.message.includes("NO_SCAN_CHARGE") ? "NO_SCAN_CHARGE" : errKlaim.message });
    }

    // species_key yang ada dikirim ke validator supaya typo satu huruf tidak
    // memecah cache — kecuali jalur capture privat yang sengaja unik per foto.
    const { data: spesiesAda } = useUniqueCapture
      ? { data: [] as { species_key: string }[] }
      : await db.from("species_library").select("species_key");
    const dikenal = [...new Set((spesiesAda ?? []).map((r) => r.species_key))];

    let mentah: unknown;
    try {
      mentah = await jalankanPrediksi(MODEL_VISION, {
        prompt: "Analyse the attached photograph now. Respond with the JSON object only.",
        images: [urlFoto],
        system_instruction: visionInstruction(prompts.vision_system, prompts.vision_schema),
        temperature: 0.4,
        top_p: 0.95,
        max_output_tokens: 4096,
        thinking_budget: 0,
        dynamic_thinking: false,
      });
    } catch (e) {
      await db.rpc("refund_scan_charge", { p_owner: uid, p_reason: "vision_error" });
      return json(502, { error: e instanceof Error ? e.message : String(e) });
    }

    let hasil: ReturnType<typeof validateVision>;
    try {
      hasil = validateVision(
        extractJson(mentah),
        dikenal,
        promptMajor(versiPrompt) >= 4,
        promptMajor(versiPrompt) >= 5,
        promptMajor(versiPrompt) >= 7,
        promptMajor(versiPrompt) >= 12,
        useV13,
        allowAnimals,
        useUniqueCapture,
        promptMajor(versiPrompt) >= 17,
        promptMajor(versiPrompt) >= 32,
        promptMajor(versiPrompt) >= 33,
        promptMajor(versiPrompt) === 35,
        promptMajor(versiPrompt) === 36,
        promptMajor(versiPrompt) === 37,
        promptMajor(versiPrompt) === 38,
        promptMajor(versiPrompt) >= 39,
      );
    } catch (e) {
      await db.rpc("refund_scan_charge", { p_owner: uid, p_reason: "vision_unparseable" });
      return json(502, { error: e instanceof Error ? e.message : String(e) });
    }

    // Gate menolak: foto wajah, dinding kosong, konten tidak aman. Charge-nya
    // dikembalikan — pemain tidak boleh dihukum karena mencoba.
    if (hasil.gate !== "passed") {
      await db.rpc("refund_scan_charge", { p_owner: uid, p_reason: "gate_rejected" });
      await db.storage.from("photos").remove([photoPath]);
      return json(200, { gate: "rejected", reason: hasil.reason });
    }
    vision = hasil.vision as Vision;
  }

  const generatedName = normalizeSuggestedName(vision.suggested_name, vision.species_key);
  const nickname = (body.nickname?.trim() || generatedName).slice(0, 32);

  // ------------------------------------------------------------ pustaka
  if (!lanjutkan && !useUniqueCapture) {
    const { data: cache } = await db
      .from("species_library")
      .select("sheet_path, manifest, prompt_version, times_reused")
      .eq("species_key", vision.species_key)
      .eq("color_bucket", vision.color_bucket)
      .eq("stage", STAGE_BAYI)
      .maybeSingle();

    if (cache) {
      const { data: hasil, error } = await db.rpc("record_cache_hit", {
        p_owner: uid,
        p_key: kunci,
        p_nickname: nickname,
        p_species: vision.species_key,
        p_color: vision.color_bucket,
        p_stage: STAGE_BAYI,
        p_element: vision.element,
        p_rarity: vision.rarity,
        p_stats: vision.stats,
        p_care: CARE_AWAL,
        p_vision: vision,
        p_prompt_version: cache.prompt_version,
      });
      if (error) {
        if (error.message.includes("GUEST_SCAN_USED")) {
          await db.rpc("refund_scan_charge", { p_owner: uid, p_reason: "guest_scan_used" });
          await db.storage.from("photos").remove([photoPath]);
          return json(409, { error: "GUEST_SCAN_USED" });
        }
        return json(500, { error: error.message });
      }

      // Foto sudah tidak diperlukan: tidak ada generation yang akan memakainya.
      await db.storage.from("photos").remove([photoPath]);

      return json(200, {
        cache_hit: true,
        generation_id: hasil.generation_id,
        anima_id: hasil.anima_id,
        status: "ready",
        sheet_path: cache.sheet_path,
        manifest: cache.manifest,
        vision,
      });
    }
  }

  // ------------------------------------------------------------ Genesis
  const biaya = biayaGambarUsd(modelGambar, KUALITAS_GAMBAR);
  let genId = lama?.id ?? null;
  let animaId = lama?.anima_id ?? null;

  if (!lanjutkan) {
    const claimParams = {
      p_owner: uid,
      p_key: kunci,
      p_nickname: nickname,
      p_species: vision.species_key,
      p_color: vision.color_bucket,
      p_stage: STAGE_BAYI,
      p_element: vision.element,
      p_rarity: vision.rarity,
      p_stats: vision.stats,
      p_care: CARE_AWAL,
      p_vision: vision,
      p_prompt_version: versiPrompt,
      p_model: modelGambar,
      p_cost: biaya,
      p_photo_path: photoPath,
    };

    const { data: gen, error } = useUniqueCapture
      ? await db.rpc("claim_capture", {
        ...claimParams,
        p_secondary_element: vision.secondary_element ?? null,
        p_subject_kind: vision.subject_kind ?? "object",
        p_capture_vibe: captureVibe,
      })
      : await db.rpc("claim_genesis", claimParams);

    if (error) {
      const msg = error.message;
      if (msg.includes("GUEST_SCAN_USED")) {
        await db.rpc("refund_scan_charge", { p_owner: uid, p_reason: "guest_scan_used" });
        await db.storage.from("photos").remove([photoPath]);
        return json(409, { error: "GUEST_SCAN_USED" });
      }
      // Spesies baru tapi tidak ada Core: hasil Vision sudah dibayar, jadi ia
      // disimpan sebagai Temuan Tertunda. Pemain bisa mengklaimnya nanti tanpa
      // memfoto ulang objek yang mungkin sudah tidak ada di dekatnya.
      if (msg.includes("NO_CORE")) {
        await db.from("pending_discoveries").upsert(
          {
            owner_id: uid,
            species_key: vision.species_key,
            color_bucket: vision.color_bucket,
            vision_result: vision,
          },
          { onConflict: "owner_id,species_key,color_bucket" },
        );
        return json(402, { error: "NO_CORE", pending: true, vision });
      }
      if (msg.includes("SPEND_CAP")) return json(503, { error: "SPEND_CAP" });
      return json(500, { error: msg });
    }

    genId = gen.generation_id;
    animaId = gen.anima_id;
  }

  // ------------------------------------------------------------ Replicate
  const prompt = assemblePrompt(
    spriteSheetTemplate(prompts, vision.subject_kind ?? "object"),
    vision,
    captureVibe,
    prompts.vibe_directions ?? null,
  );
  const input = modelGambar === "openai/gpt-image-2"
    ? {
      prompt,
      input_images: [urlFoto],
      aspect_ratio: "1024x1024",
      quality: KUALITAS_GAMBAR,
      number_of_images: 1,
      // Schema wrapper mencantumkan transparent, tetapi runtime model menolaknya
      // dengan invalid_value. Transparansi datang dari chroma key, bukan dari
      // model. Lihat CLAUDE.md.
      background: "opaque",
      output_format: "png",
      output_compression: 100,
      moderation: "auto",
    }
    : {
      prompt,
      image_input: [urlFoto],
      aspect_ratio: "1:1",
      resolution: "2K",
      output_format: "png",
      safety_filter_level: "block_only_high",
      allow_fallback_model: false,
    };

  try {
    const predId = await mulaiGeneration(
      modelGambar,
      input,
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/replicate_webhook`,
    );
    await db
      .from("generations")
      .update({ prediction_id: predId, status: "running" })
      .eq("id", genId);

    return json(202, {
      generation_id: genId,
      anima_id: animaId,
      status: "running",
      eta_seconds: 65,
      vision,
    });
  } catch (e) {
    // Core sudah didebit tapi tidak ada gambar yang akan datang. Refund di sini,
    // bukan menunggu webhook yang tidak akan pernah dipanggil.
    const alasan = e instanceof Error ? e.message : String(e);
    await db.rpc("refund_generation", { p_gen_id: genId, p_reason: alasan.slice(0, 500) });
    if (animaId) await db.from("animas").update({ status: "failed" }).eq("id", animaId);
    return json(502, { error: alasan });
  }
});
