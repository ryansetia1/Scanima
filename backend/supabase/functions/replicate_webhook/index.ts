// Webhook Replicate. Satu-satunya jalur yang mengubah generation menjadi Anima
// yang menetas, dan satu-satunya jalur yang mengembalikan Genesis Core saat model
// gagal.
//
// verify_jwt harus false untuk fungsi ini: Replicate tidak memegang JWT Supabase.
// Yang menggantikannya adalah tanda tangan webhook, dan itu wajib — lihat
// _shared/webhook_signature.ts.

import { adminClient, json } from "../_shared/supa.ts";
import { verifikasiTandaTangan } from "../_shared/webhook_signature.ts";
import { finalizeSheet, type FacingAuditResult } from "../_shared/finalize_sheet.ts";
import { layoutForPrompt } from "../_shared/postprocess.mjs";
import {
  FACING_GRID,
  auditableCells,
  decideFacingFlips,
  facingInstruction,
  parseFacingVerdict,
} from "../_shared/facing_audit.mjs";
import { VISION_THINKING } from "../_shared/vision.mjs";
import PROMPTS from "../_shared/prompts.generated.ts";
import {
  evolutionFinalizeRetryable,
  evolutionImageSafetyRetryable,
  evolutionImageSafetyRetryInput,
  evolutionWebhookUrl,
} from "../_shared/evolution.mjs";
import {
  batalkanPrediksi,
  jalankanPrediksi,
  mulaiGeneration,
  rahasiaWebhook,
} from "../_shared/replicate.ts";

const MODEL_VISION = Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash";

function configBool(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value === "true";
  return false;
}

// Payload yang lolos tanda tangan pun tidak boleh menentukan dari mana kita
// mengunduh. Kalau suatu hari secret-nya bocor, penyerang masih tidak bisa
// menyuntikkan gambar dari host miliknya sendiri ke pustaka art bersama.
const HOST_DIIZINKAN = ["replicate.delivery", "replicate.com"];
const EVOLUTION_CANCEL_AFTER = "8m";

function hostDiizinkan(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return HOST_DIIZINKAN.some((h) => host === h || host.endsWith(`.${h}`));
  } catch {
    return false;
  }
}

// Biaya generation terkunci saat prediksi selesai, jadi membuang gambarnya
// bersama kegagalan post-processing berarti membayar dua kali untuk satu Anima.
// Raw yang disimpan membuat perbaikan pipeline bisa diproses ulang gratis — dua
// bug 22 Agustus 2026 (thinking budget dan keyline stripper) masing-masing
// menghanguskan satu sheet berbayar yang sebenarnya masih utuh di memori sini.
// Gagal menyimpan tidak boleh membatalkan penandaan gagal; ia hanya dicatat.
//
// ponytail: satu objek per generation gagal, tanpa TTL. Plafon ~1,3 MB per
// kegagalan; pasang lifecycle rule di bucket kalau kegagalan pernah rutin.
async function simpanRawGagal(
  db: ReturnType<typeof adminClient>,
  genId: string,
  rawPng: Uint8Array,
): Promise<void> {
  const { error } = await db.storage
    .from("anima_sheets")
    .upload(`failed_raw/${genId}.png`, new Blob([rawPng], { type: "image/png" }), {
      contentType: "image/png",
      upsert: true,
    });
  if (error) console.error("simpan raw gagal", genId, error.message);
}

function ambilUrlKeluaran(output: unknown): string | null {
  if (typeof output === "string") return output;
  if (Array.isArray(output)) {
    const pertama = output.find((o) => typeof o === "string");
    return typeof pertama === "string" ? pertama : null;
  }
  return null;
}

async function featureFacingAuditOn(db: ReturnType<typeof adminClient>): Promise<boolean> {
  const { data } = await db
    .from("app_config")
    .select("value")
    .eq("key", "feature_facing_audit")
    .maybeSingle();
  return configBool(data?.value);
}

const promptBundleFacing = PROMPTS as Record<
  string,
  { facing_audit?: string; facing_audit_schema?: unknown }
>;

/**
 * Dua pass independen menilai arah hadap; flip hanya kalau keduanya setuju.
 * Fail-open selalu — setiap kegagalan menghasilkan flipped: [] dan status yang
 * menjelaskan sebabnya. Sheet berbayar tidak pernah gagal karena audit ini.
 */
async function auditFacing(
  url: string,
  gen: GenRow,
  featureOn: boolean,
): Promise<FacingAuditResult> {
  if (!featureOn) {
    return {
      flipped: [],
      record: { status: "skipped", flipped: [], pass1: {}, pass2: null, reason: "feature_flag_off" },
    };
  }
  const prompts = promptBundleFacing[gen.prompt_version];
  if (!prompts?.facing_audit || !prompts.facing_audit_schema) {
    return {
      flipped: [],
      record: { status: "unavailable", flipped: [], pass1: {}, pass2: null, reason: "prompt_absent" },
    };
  }

  try {
    const vision = gen.vision_result as
      | { strike_vfx?: { motion?: string }; surge_vfx?: { motion?: string } }
      | null;
    const layout = layoutForPrompt(gen.prompt_version);
    const allowed = auditableCells(layout, {
      fx_strike: vision?.strike_vfx?.motion,
      fx_surge: vision?.surge_vfx?.motion,
    });
    const systemInstruction = facingInstruction(prompts.facing_audit, prompts.facing_audit_schema);

    const raw1 = await jalankanPrediksi(MODEL_VISION, {
      prompt: `Judge facing for grid positions: ${allowed.map((p) => FACING_GRID[p]).join(", ")}. ` +
        "Respond with the JSON object only.",
      images: [url],
      system_instruction: systemInstruction,
      temperature: 0.2,
      top_p: 0.9,
      max_output_tokens: 512,
      ...VISION_THINKING,
    }, 45_000);
    const pass1 = parseFacingVerdict(raw1, allowed);

    const flaggedPass1 = allowed.filter((pose) => pass1[pose] === "right");
    let pass2: Record<string, string> | null = null;
    if (flaggedPass1.length > 0) {
      const raw2 = await jalankanPrediksi(MODEL_VISION, {
        prompt: "Give your independent second opinion on grid positions: " +
          `${flaggedPass1.map((p) => FACING_GRID[p]).join(", ")}. Respond with the JSON object only.`,
        images: [url],
        system_instruction: systemInstruction,
        temperature: 0.45,
        top_p: 0.9,
        max_output_tokens: 512,
        ...VISION_THINKING,
      }, 45_000);
      pass2 = parseFacingVerdict(raw2, flaggedPass1);
    }

    return decideFacingFlips(pass1, pass2, allowed);
  } catch (e) {
    const reason = `vision_error: ${e instanceof Error ? e.message : String(e)}`;
    return {
      flipped: [],
      record: { status: "unavailable", flipped: [], pass1: {}, pass2: null, reason },
    };
  }
}

type GenRow = {
  id: string;
  owner_id: string;
  anima_id: string | null;
  kind?: string;
  target_stage?: number | null;
  status: string;
  prompt_version: string;
  photo_path: string | null;
  vision_result?: unknown;
  prediction_id?: string | null;
  model?: string | null;
  image_attempts?: number | null;
  animas?: unknown;
};

async function batalkanYatim(predictionId: string): Promise<void> {
  try {
    await batalkanPrediksi(predictionId);
  } catch (e) {
    console.error(
      "batalkan retry Evolution yatim",
      predictionId,
      e instanceof Error ? e.message : String(e),
    );
  }
}

/**
 * Satu redraw untuk safety false-positive E005, tanpa mengulang Vision.
 *
 * Prediction resmi yang `failed` tidak ditagih Replicate. Input retry memakai
 * allowlist + family-safe suffix, dan RPC swap menjaga dua callback paralel
 * tidak bisa menempelkan dua prediction ke generation yang sama.
 */
async function cobaRetrySafetyEvolution(
  db: ReturnType<typeof adminClient>,
  gen: GenRow,
  failedPredictionId: string,
  rawInput: unknown,
): Promise<boolean> {
  if (
    gen.model !== "openai/gpt-image-2"
    || Number(gen.image_attempts ?? 1) >= 2
  ) return false;
  const input = evolutionImageSafetyRetryInput(rawInput);
  if (!input) return false;

  const base = `${Deno.env.get("SUPABASE_URL")}/functions/v1/replicate_webhook`;
  const webhook = evolutionWebhookUrl(base, gen.id);
  const retryPredictionId = await mulaiGeneration(gen.model, input, webhook, {
    cancelAfter: EVOLUTION_CANCEL_AFTER,
  });
  const { data, error } = await db.rpc("replace_evolution_prediction", {
    p_gen_id: gen.id,
    p_failed_prediction_id: failedPredictionId,
    p_retry_prediction_id: retryPredictionId,
  });
  if (error) {
    await batalkanYatim(retryPredictionId);
    throw new Error(`attach retry Evolution gagal: ${error.message}`);
  }
  const result = (data ?? {}) as Record<string, unknown>;
  if (!result.attached) {
    await batalkanYatim(retryPredictionId);
    // Callback duplikat kalah balapan terhadap retry yang sudah aktif. Ia tetap
    // dianggap tertangani supaya prediction lama tidak menjatuhkan evolution.
    return Boolean(result.stale);
  }
  return true;
}

async function muatGeneration(
  db: ReturnType<typeof adminClient>,
  predictionId: string,
  generationIdCallback: string | null,
): Promise<{ gen: GenRow | null; mismatch?: boolean }> {
  const { data: byPred, error: errPred } = await db
    .from("generations")
    .select(
      "id, owner_id, anima_id, kind, target_stage, status, prompt_version, photo_path, " +
        "vision_result, prediction_id, model, image_attempts, " +
        "animas(id, species_key, color_bucket, stage, sheet_path, typing_version)",
    )
    .eq("prediction_id", predictionId)
    .maybeSingle();
  if (errPred) throw new Error(errPred.message);
  if (byPred) return { gen: byPred as GenRow };

  if (!generationIdCallback) return { gen: null };

  const { data: byCallback, error: errCb } = await db
    .from("generations")
    .select(
      "id, owner_id, anima_id, kind, target_stage, status, prompt_version, photo_path, " +
        "vision_result, prediction_id, model, image_attempts, " +
        "animas(id, species_key, color_bucket, stage, sheet_path, typing_version)",
    )
    .eq("id", generationIdCallback)
    .maybeSingle();
  if (errCb) throw new Error(errCb.message);
  if (!byCallback) return { gen: null };

  const row = byCallback as GenRow;
  if (row.kind !== "evolve" && row.kind !== "synthesis") return { gen: null };
  if (row.prediction_id && row.prediction_id !== predictionId) {
    return { gen: null, mismatch: true };
  }

  const attachRpc = row.kind === "synthesis"
    ? "attach_synthesis_prediction"
    : "attach_evolution_prediction";
  const { error: errAttach } = await db.rpc(attachRpc, {
    p_gen_id: row.id,
    p_prediction_id: predictionId,
  });
  if (errAttach) {
    if (errAttach.message.includes("PREDICTION_MISMATCH")) {
      return { gen: null, mismatch: true };
    }
    throw new Error(errAttach.message);
  }

  const { data: refreshed, error: errRefresh } = await db
    .from("generations")
    .select(
      "id, owner_id, anima_id, kind, target_stage, status, prompt_version, photo_path, " +
      "vision_result, prediction_id, model, image_attempts, " +
        "animas(id, species_key, color_bucket, stage, sheet_path, typing_version)",
    )
    .eq("id", row.id)
    .maybeSingle();
  if (errRefresh) throw new Error(errRefresh.message);
  return { gen: refreshed as GenRow | null };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });

  // Rahasianya diambil dari Replicate memakai token yang sudah kita punya, bukan
  // dipasang sebagai secret kedua: satu kredensial lebih sedikit berarti satu
  // langkah setup yang tidak bisa terlupakan.
  //
  // Gagal tertutup. Mode "lewati verifikasi kalau rahasianya tidak ada" adalah
  // pintu belakang yang selalu ikut ke produksi, dan yang lewat di pintu itu bisa
  // menulis ke pustaka art yang di-share semua pemain.
  let secret: string;
  try {
    secret = await rahasiaWebhook();
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }

  const body = await req.text();
  if (!(await verifikasiTandaTangan(req.headers, body, secret))) {
    return json(401, { error: "tanda tangan webhook tidak sah" });
  }

  let payload: {
    id?: string;
    status?: string;
    output?: unknown;
    error?: unknown;
    input?: unknown;
  };
  try {
    payload = JSON.parse(body);
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const predictionId = payload.id;
  if (!predictionId) return json(400, { error: "payload tanpa id prediksi" });

  const generationIdCallback = new URL(req.url).searchParams.get("generation_id");

  const db = adminClient();
  let gen: GenRow | null;
  try {
    const loaded = await muatGeneration(db, predictionId, generationIdCallback);
    if (loaded.mismatch) {
      return json(409, { error: "PREDICTION_MISMATCH", prediction: predictionId });
    }
    gen = loaded.gen;
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }

  if (!gen) {
    // Balapan yang nyata: webhook bisa tiba sebelum create_anima / evolve_anima
    // selesai menulis prediction_id. Untuk status terminal, 503 meminta Replicate
    // mencoba lagi; 200 akan membuang kejadiannya dan meninggalkan Anima menetas
    // selamanya.
    const terminal = ["succeeded", "failed", "canceled"].includes(payload.status ?? "");
    return json(terminal ? 503 : 200, { ditunda: terminal, prediction: predictionId });
  }

  // Webhook dikirim ulang saat kita membalas 5xx, dan status non-terminal juga
  // dikirim. Keduanya harus tidak berefek di sini.
  if (gen.status === "succeeded" || gen.status === "failed") {
    return json(200, { sudah: gen.status });
  }
  if (!["succeeded", "failed", "canceled"].includes(payload.status ?? "")) {
    return json(200, { diabaikan: payload.status ?? null });
  }

  const anima = Array.isArray(gen.animas) ? gen.animas[0] : gen.animas;
  const isEvolve = gen.kind === "evolve";
  const isSynthesis = gen.kind === "synthesis";
  const urlKeluaran = payload.status === "succeeded" ? ambilUrlKeluaran(payload.output) : null;

  const alasanGagal = payload.status !== "succeeded"
    ? String(payload.error ?? payload.status)
    : !urlKeluaran || !hostDiizinkan(urlKeluaran)
    ? `keluaran tidak dipercaya: ${urlKeluaran ?? "kosong"}`
    : !anima
    ? "generation tanpa anima, spesies tidak diketahui"
    : null;

  if (alasanGagal) {
    if (isEvolve) {
      if (
        payload.status === "failed"
        && evolutionImageSafetyRetryable(alasanGagal)
      ) {
        try {
          if (await cobaRetrySafetyEvolution(db, gen, predictionId, payload.input)) {
            return json(200, {
              evolution_retry: true,
              alasan: alasanGagal,
            });
          }
        } catch (e) {
          // Gagal dispatch/attach belum membuktikan retry tidak diterima.
          // Balas 503 agar webhook lama dicoba lagi, bukan menandai terminal dan
          // membuka kesempatan pemain memicu job berbayar kedua secara manual.
          return json(503, {
            error: e instanceof Error ? e.message : String(e),
            retry_dispatch: true,
          });
        }
      }
      const { error } = await db.rpc("fail_evolution", {
        p_gen_id: gen.id,
        p_reason: alasanGagal.slice(0, 500),
      });
      if (error) return json(503, { error: error.message });
      return json(200, { evolution_gagal: true, alasan: alasanGagal });
    }
    if (isSynthesis) {
      const { error } = await db.rpc("fail_synthesis", {
        p_gen_id: gen.id,
        p_reason: alasanGagal.slice(0, 500),
      });
      if (error) return json(503, { error: error.message });
      return json(200, { synthesis_gagal: true, alasan: alasanGagal });
    }
    const { error } = await db.rpc("refund_generation", {
      p_gen_id: gen.id,
      p_reason: alasanGagal.slice(0, 500),
    });
    if (error) return json(500, { error: error.message });
    if (gen.anima_id) {
      await db.from("animas").update({ status: "failed" }).eq("id", gen.anima_id);
    }
    return json(200, { direfund: true, alasan: alasanGagal });
  }

  const facingOn = await featureFacingAuditOn(db);
  const [unduh, facing] = await Promise.all([
    fetch(urlKeluaran!),
    auditFacing(urlKeluaran!, gen, facingOn),
  ]);
  if (!unduh.ok) {
    // Sengaja 503, bukan refund: gagal mengunduh belum berarti model gagal, dan
    // gambarnya sudah dibayar. Biarkan Replicate mencoba lagi.
    return json(503, { error: `unduh keluaran gagal: ${unduh.status}` });
  }
  const rawPng = new Uint8Array(await unduh.arrayBuffer());

  try {
    const hasil = await finalizeSheet(db, gen, anima!, rawPng, facing);
    return json(200, {
      sheet: hasil.sheetPath,
      sel: hasil.manifest.qa.cells_detected,
      ms_postprocess: hasil.msPostprocess,
    });
  } catch (e) {
    const alasan = e instanceof Error ? e.message : String(e);
    // Raw hanya disimpan untuk kegagalan terminal. Yang transient akan dikirim
    // ulang Replicate berikut gambarnya, jadi menyimpannya di sini cuma
    // meninggalkan objek yatim saat percobaan berikutnya berhasil.
    if ((isEvolve || isSynthesis) && evolutionFinalizeRetryable(alasan)) {
      return json(503, { error: alasan, transient: true });
    }
    await simpanRawGagal(db, gen.id, rawPng);
    if (isEvolve) {
      const { error } = await db.rpc("fail_evolution", {
        p_gen_id: gen.id,
        p_reason: alasan.slice(0, 500),
      });
      if (error) return json(503, { error: error.message });
      return json(200, { evolution_gagal: true, alasan });
    }
    if (isSynthesis) {
      const { error } = await db.rpc("fail_synthesis", {
        p_gen_id: gen.id,
        p_reason: alasan.slice(0, 500),
      });
      if (error) return json(503, { error: error.message });
      return json(200, { synthesis_gagal: true, alasan });
    }
    await db.rpc("refund_generation", { p_gen_id: gen.id, p_reason: alasan.slice(0, 500) });
    if (gen.anima_id) {
      await db.from("animas").update({ status: "failed" }).eq("id", gen.anima_id);
    }
    return json(200, { direfund: true, alasan });
  }
});
