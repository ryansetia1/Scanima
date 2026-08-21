// Webhook Replicate. Satu-satunya jalur yang mengubah generation menjadi Anima
// yang menetas, dan satu-satunya jalur yang mengembalikan Genesis Core saat model
// gagal.
//
// verify_jwt harus false untuk fungsi ini: Replicate tidak memegang JWT Supabase.
// Yang menggantikannya adalah tanda tangan webhook, dan itu wajib — lihat
// _shared/webhook_signature.ts.

import { adminClient, json } from "../_shared/supa.ts";
import { verifikasiTandaTangan } from "../_shared/webhook_signature.ts";
import { finalizeSheet } from "../_shared/finalize_sheet.ts";
import { evolutionFinalizeRetryable } from "../_shared/evolution.mjs";
import { rahasiaWebhook } from "../_shared/replicate.ts";

// Payload yang lolos tanda tangan pun tidak boleh menentukan dari mana kita
// mengunduh. Kalau suatu hari secret-nya bocor, penyerang masih tidak bisa
// menyuntikkan gambar dari host miliknya sendiri ke pustaka art bersama.
const HOST_DIIZINKAN = ["replicate.delivery", "replicate.com"];

function hostDiizinkan(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return HOST_DIIZINKAN.some((h) => host === h || host.endsWith(`.${h}`));
  } catch {
    return false;
  }
}

function ambilUrlKeluaran(output: unknown): string | null {
  if (typeof output === "string") return output;
  if (Array.isArray(output)) {
    const pertama = output.find((o) => typeof o === "string");
    return typeof pertama === "string" ? pertama : null;
  }
  return null;
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
  animas?: unknown;
};

async function muatGeneration(
  db: ReturnType<typeof adminClient>,
  predictionId: string,
  generationIdCallback: string | null,
): Promise<{ gen: GenRow | null; mismatch?: boolean }> {
  const { data: byPred, error: errPred } = await db
    .from("generations")
    .select(
      "id, owner_id, anima_id, kind, target_stage, status, prompt_version, photo_path, " +
        "vision_result, prediction_id, " +
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
        "vision_result, prediction_id, " +
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
        "vision_result, prediction_id, " +
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

  let payload: { id?: string; status?: string; output?: unknown; error?: unknown };
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

  const unduh = await fetch(urlKeluaran!);
  if (!unduh.ok) {
    // Sengaja 503, bukan refund: gagal mengunduh belum berarti model gagal, dan
    // gambarnya sudah dibayar. Biarkan Replicate mencoba lagi.
    return json(503, { error: `unduh keluaran gagal: ${unduh.status}` });
  }
  const rawPng = new Uint8Array(await unduh.arrayBuffer());

  try {
    const hasil = await finalizeSheet(db, gen, anima!, rawPng);
    return json(200, {
      sheet: hasil.sheetPath,
      sel: hasil.manifest.qa.cells_detected,
      ms_postprocess: hasil.msPostprocess,
    });
  } catch (e) {
    const alasan = e instanceof Error ? e.message : String(e);
    if (isEvolve) {
      if (evolutionFinalizeRetryable(alasan)) {
        return json(503, { error: alasan, transient: true });
      }
      const { error } = await db.rpc("fail_evolution", {
        p_gen_id: gen.id,
        p_reason: alasan.slice(0, 500),
      });
      if (error) return json(503, { error: error.message });
      return json(200, { evolution_gagal: true, alasan });
    }
    if (isSynthesis) {
      if (evolutionFinalizeRetryable(alasan)) {
        return json(503, { error: alasan, transient: true });
      }
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
