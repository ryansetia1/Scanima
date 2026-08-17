// POST /evolve_anima  { anima_id, idempotency_key, resume_only? }
//
// Private evolution art: no Core, no original photo. Vision + one image
// generation per request; webhook commits via commit_evolution.

import { adminClient, clientVersionGate, json } from "../_shared/supa.ts";
import { extractJson } from "../_shared/vision.mjs";
import {
  assembleEvolvePrompt,
  buildEvolvePromptContext,
  buildEvolutionIdleReference,
  evolutionVisionInstruction,
  evolutionWebhookUrl,
  validateEvolutionPlan,
} from "../_shared/evolution.mjs";
import { BIAYA_VISION_USD, biayaGambarUsd } from "../_shared/pricing.mjs";
import {
  dispatchDefinitelyNotStarted,
  jalankanPrediksi,
  mulaiGeneration,
} from "../_shared/replicate.ts";
import PROMPTS from "../_shared/prompts.generated.ts";

const MODEL_VISION = Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash";
const KUALITAS_GAMBAR = Deno.env.get("IMAGE_QUALITY") ?? "medium";
const TTL_SIGNED_URL = 900;
const EVOLUTION_CANCEL_AFTER = "8m";
const EVOLUTION_PLAN_LEASE_MS = 3 * 60 * 1000;
const db = adminClient();

function configString(value: unknown, fallback: string): string {
  if (typeof value === "string" && value.length > 0) return value;
  if (value && typeof value === "object" && "toString" in value) {
    const s = String(value).replace(/^"|"$/g, "");
    if (s) return s;
  }
  return fallback;
}

type BeginResult = {
  generation_id: string;
  anima_id: string;
  target_stage: number;
  prior_stage: number;
  sheet_path: string;
  manifest: Record<string, unknown>;
  replayed?: boolean;
  vision_result?: Record<string, unknown>;
  capture_metadata?: Record<string, unknown>;
};

async function fetchCaptureVision(animaId: string): Promise<Record<string, unknown> | null> {
  const { data } = await db
    .from("generations")
    .select("vision_result")
    .eq("anima_id", animaId)
    .eq("kind", "create")
    .eq("status", "succeeded")
    .order("finished_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const vr = data?.vision_result;
  return vr && typeof vr === "object" ? vr as Record<string, unknown> : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: errAuth } = await db.auth.getClaims(token);
  const uid = auth?.claims?.sub;
  if (errAuth || typeof uid !== "string") return json(401, { error: "token tidak sah" });

  let body: { anima_id?: string; idempotency_key?: string; resume_only?: boolean };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }

  const animaId = body.anima_id ?? "";
  const kunci = body.idempotency_key ?? "";
  if (!animaId) return json(400, { error: "anima_id wajib" });
  if (!kunci || kunci.length > 128) return json(400, { error: "idempotency_key wajib, maks 128 char" });

  const { data: konfigRows } = await db
    .from("app_config")
    .select("key, value")
    .in("key", ["image_model", "evolution_prompt_version"]);
  const konfig = Object.fromEntries((konfigRows ?? []).map((r) => [r.key, r.value]));

  const modelGambar = (konfig.image_model as string) ?? "openai/gpt-image-2";
  const versiPrompt = configString(konfig.evolution_prompt_version, "v21");
  const biaya = BIAYA_VISION_USD + biayaGambarUsd(modelGambar, KUALITAS_GAMBAR);

  const promptBundle = PROMPTS as Record<
    string,
    {
      sprite_sheet_evolve: string;
      vision_evolve_system?: string;
      vision_evolve_schema?: unknown;
    }
  >;
  const prompts = promptBundle[versiPrompt];
  if (!prompts?.sprite_sheet_evolve) {
    return json(500, { error: `versi evolution prompt ${versiPrompt} tidak ada di bundel` });
  }
  if (!prompts.vision_evolve_system || !prompts.vision_evolve_schema) {
    return json(500, { error: `vision evolve prompt ${versiPrompt} tidak lengkap di bundel` });
  }

  const resumeOnly = body.resume_only === true;
  const { data: beginRaw, error: errBegin } = resumeOnly
    ? await db.rpc("resume_evolution", {
      p_owner: uid,
      p_anima_id: animaId,
    })
    : await db.rpc("begin_evolution", {
      p_owner: uid,
      p_anima_id: animaId,
      p_key: kunci,
    });
  if (errBegin) {
    const msg = errBegin.message;
    if (msg.includes("EVOLUTION_NOT_FOUND")) return json(409, { error: "EVOLUTION_NOT_FOUND" });
    if (msg.includes("FEATURE_DISABLED")) return json(503, { error: "FEATURE_DISABLED" });
    if (msg.includes("EVOLUTION_LEVEL_TOO_LOW")) return json(409, { error: "EVOLUTION_LEVEL_TOO_LOW" });
    if (msg.includes("ANIMA_IN_ACTIVE_COMBAT")) return json(409, { error: "ANIMA_IN_ACTIVE_COMBAT" });
    if (msg.includes("EVOLUTION_ALREADY_ACTIVE") || msg.includes("EVOLUTION_IN_PROGRESS")) {
      return json(409, { error: msg.split("\n")[0] });
    }
    if (msg.includes("EVOLUTION_MAX_STAGE")) return json(409, { error: "EVOLUTION_MAX_STAGE" });
    if (msg.includes("ANIMA_NOT_FOUND")) return json(404, { error: "ANIMA_NOT_FOUND" });
    if (
      msg.includes("ANIMA_NOT_READY")
      || msg.includes("ANIMA_NO_SHEET")
      || msg.includes("ANIMA_NO_MANIFEST")
    ) {
      return json(409, { error: msg.split("\n")[0] });
    }
    return json(500, { error: msg });
  }
  if (
    !beginRaw
    || typeof beginRaw !== "object"
    || (beginRaw as Record<string, unknown>).not_found === true
  ) {
    return json(409, { error: "EVOLUTION_NOT_FOUND" });
  }

  const begin = beginRaw as BeginResult;
  const genId = begin.generation_id;
  const targetStage = begin.target_stage;
  const sheetPath = begin.sheet_path;

  const { data: genRow } = await db
    .from("generations")
    .select(
      "id, status, prediction_id, vision_result, vision_started_at, " +
        "dispatch_started_at, cost_usd_estimate",
    )
    .eq("id", genId)
    .maybeSingle();

  if (genRow?.status === "failed") {
    return json(409, {
      error: "EVOLUTION_FAILED",
      generation_id: genId,
      anima_id: begin.anima_id,
      status: "failed",
    });
  }

  if (genRow?.status === "succeeded") {
    return json(200, {
      idempoten: true,
      generation_id: genId,
      anima_id: begin.anima_id,
      status: "succeeded",
      target_stage: targetStage,
    });
  }

  if (genRow?.prediction_id) {
    const { data: completionClaim, error: errCompletion } = await db.rpc(
      "claim_evolution_dispatch",
      {
        p_owner: uid,
        p_gen_id: genId,
      },
    );
    if (errCompletion) return json(500, { error: errCompletion.message });
    const completion = completionClaim as Record<string, unknown>;
    if (completion.timed_out || completion.status === "failed") {
      return json(409, { error: "GENERATION_COMPLETION_TIMEOUT", generation_id: genId });
    }
    if (completion.status === "succeeded") {
      return json(200, {
        idempoten: true,
        generation_id: genId,
        anima_id: begin.anima_id,
        status: "succeeded",
        target_stage: targetStage,
      });
    }
    return json(200, {
      idempoten: true,
      generation_id: genId,
      anima_id: begin.anima_id,
      status: genRow.status,
      target_stage: targetStage,
    });
  }

  if (genRow?.dispatch_started_at) {
    const elapsedMs = Date.now() - new Date(String(genRow.dispatch_started_at)).getTime();
    if (elapsedMs < 10 * 60 * 1000) {
      return json(202, {
        generation_id: genId,
        anima_id: begin.anima_id,
        target_stage: targetStage,
        status: "dispatching",
      });
    }
    const { data: timeoutClaim, error: errTimeout } = await db.rpc("claim_evolution_dispatch", {
      p_owner: uid,
      p_gen_id: genId,
    });
    if ((timeoutClaim as Record<string, unknown> | null)?.timed_out) {
      return json(409, { error: "GENERATION_DISPATCH_TIMEOUT", generation_id: genId });
    }
    if (errTimeout) return json(500, { error: errTimeout.message });
  }

  const storedPlan = begin.vision_result ?? genRow?.vision_result;
  const hasStoredPlan = storedPlan && typeof storedPlan === "object";
  if (!hasStoredPlan && genRow?.vision_started_at) {
    const elapsedMs = Date.now() - new Date(String(genRow.vision_started_at)).getTime();
    if (elapsedMs < EVOLUTION_PLAN_LEASE_MS) {
      return json(202, {
        generation_id: genId,
        anima_id: begin.anima_id,
        target_stage: targetStage,
        status: "planning",
      });
    }
    await db.rpc("fail_evolution", {
      p_gen_id: genId,
      p_reason: "EVOLUTION_PLAN_TIMEOUT",
    });
    return json(409, { error: "EVOLUTION_PLAN_TIMEOUT", generation_id: genId });
  }

  const { data: signed, error: errSigned } = await db.storage
    .from("anima_sheets")
    .createSignedUrl(sheetPath, TTL_SIGNED_URL);
  if (errSigned || !signed?.signedUrl) {
    await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: "sheet_signed_url_failed" });
    return json(404, { error: "sheet tidak bisa diakses" });
  }

  const referencePath = `${uid}/${begin.anima_id}/evolution_refs/${genId}.png`;
  let referencePng: Uint8Array;
  try {
    const currentSheet = await fetch(signed.signedUrl);
    if (!currentSheet.ok) {
      throw new Error(`EVOLUTION_REFERENCE_DOWNLOAD_${currentSheet.status}`);
    }
    referencePng = await buildEvolutionIdleReference(
      new Uint8Array(await currentSheet.arrayBuffer()),
      begin.manifest,
    );
  } catch (e) {
    const alasan = e instanceof Error ? e.message : String(e);
    await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: alasan.slice(0, 500) });
    return json(422, { error: alasan });
  }

  const { error: errReferenceUpload } = await db.storage
    .from("anima_sheets")
    .upload(referencePath, referencePng, {
      contentType: "image/png",
      upsert: true,
    });
  if (errReferenceUpload) {
    await db.rpc("fail_evolution", {
      p_gen_id: genId,
      p_reason: `EVOLUTION_REFERENCE_UPLOAD: ${errReferenceUpload.message}`.slice(0, 500),
    });
    return json(500, { error: "evolution reference tidak bisa disimpan" });
  }
  const { data: referenceSigned, error: errReferenceSigned } = await db.storage
    .from("anima_sheets")
    .createSignedUrl(referencePath, TTL_SIGNED_URL);
  if (errReferenceSigned || !referenceSigned?.signedUrl) {
    await db.rpc("fail_evolution", {
      p_gen_id: genId,
      p_reason: "EVOLUTION_REFERENCE_SIGN_FAILED",
    });
    return json(500, { error: "evolution reference tidak bisa diakses" });
  }
  const referenceUrl = referenceSigned.signedUrl;

  let plan: Record<string, unknown>;
  if (hasStoredPlan) {
    plan = storedPlan as Record<string, unknown>;
  } else {
    const { data: preRaw, error: errPre } = await db.rpc("reserve_evolution", {
      p_owner: uid,
      p_gen_id: genId,
      p_plan: null,
      p_prompt_version: versiPrompt,
      p_model: modelGambar,
      p_cost: biaya,
    });
    if (errPre) {
      if (errPre.message.includes("SPEND_CAP")) {
        await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: "SPEND_CAP" });
        return json(503, { error: "SPEND_CAP" });
      }
      await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: errPre.message.slice(0, 500) });
      return json(500, { error: errPre.message });
    }
    const pre = (preRaw ?? {}) as Record<string, unknown>;
    if (!pre.planning_claimed) {
      return json(202, {
        generation_id: genId,
        anima_id: begin.anima_id,
        target_stage: targetStage,
        status: pre.plan_ready ? "planned" : "planning",
      });
    }

    const meta = begin.capture_metadata ?? {};
    const visionPrompt =
      `Target stage: ${targetStage} (${targetStage === 2 ? "Adult bridge" : "Evolved culmination"}).\n` +
      `Current height cm: ${meta.body_height_cm ?? "unknown"}.\n` +
      `Current moves: ${meta.strike_name ?? ""} / ${meta.surge_name ?? ""}.\n` +
      `Current effects: ${meta.strike_effect_id ?? ""} / ${meta.surge_effect_id ?? ""}.\n` +
      `Species: ${meta.species_key ?? ""}; element: ${meta.element ?? ""}.\n` +
      "Analyse the attached current sprite sheet and respond with the Evolution Plan JSON only.";

    let mentah: unknown;
    try {
      mentah = await jalankanPrediksi(MODEL_VISION, {
        prompt: visionPrompt,
        images: [referenceUrl],
        system_instruction: evolutionVisionInstruction(
          prompts.vision_evolve_system,
          prompts.vision_evolve_schema,
        ),
        temperature: 0.35,
        top_p: 0.95,
        max_output_tokens: 4096,
        thinking_budget: 0,
        dynamic_thinking: false,
      });
    } catch (e) {
      const alasan = e instanceof Error ? e.message : String(e);
      await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: alasan.slice(0, 500) });
      return json(502, { error: alasan });
    }

    try {
      const parsed = extractJson(mentah);
      const priorHeight = Number(meta.body_height_cm) || 120;
      const validated = validateEvolutionPlan(parsed, {
        targetStage,
        priorHeightCm: priorHeight,
        priorStrikeName: String(meta.strike_name ?? ""),
        priorSurgeName: String(meta.surge_name ?? ""),
        priorStrikeEffectId: String(meta.strike_effect_id ?? ""),
        priorSurgeEffectId: String(meta.surge_effect_id ?? ""),
      });
      plan = validated.plan;
    } catch (e) {
      const alasan = e instanceof Error ? e.message : String(e);
      await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: alasan.slice(0, 500) });
      return json(502, { error: alasan });
    }

    const { error: errReserve } = await db.rpc("reserve_evolution", {
      p_owner: uid,
      p_gen_id: genId,
      p_plan: plan,
      p_prompt_version: versiPrompt,
      p_model: modelGambar,
      p_cost: biaya,
    });
    if (errReserve) {
      if (errReserve.message.includes("SPEND_CAP")) {
        await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: "SPEND_CAP" });
        return json(503, { error: "SPEND_CAP" });
      }
      await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: errReserve.message.slice(0, 500) });
      return json(500, { error: errReserve.message });
    }
  }

  plan.target_stage = targetStage;
  const captureVision = await fetchCaptureVision(begin.anima_id);
  const ctx = buildEvolvePromptContext(captureVision, begin.capture_metadata ?? {});

  const prompt = assembleEvolvePrompt(prompts.sprite_sheet_evolve, plan, ctx);
  const input = modelGambar === "openai/gpt-image-2"
    ? {
      prompt,
      input_images: [referenceUrl],
      aspect_ratio: "1024x1024",
      quality: KUALITAS_GAMBAR,
      number_of_images: 1,
      background: "opaque",
      output_format: "png",
      output_compression: 100,
      moderation: "auto",
    }
    : {
      prompt,
      image_input: [referenceUrl],
      aspect_ratio: "1:1",
      resolution: "2K",
      output_format: "png",
      safety_filter_level: "block_only_high",
      allow_fallback_model: false,
    };

  const webhookBase = `${Deno.env.get("SUPABASE_URL")}/functions/v1/replicate_webhook`;
  const webhook = evolutionWebhookUrl(webhookBase, genId);

  const { data: dispatchClaim, error: errClaim } = await db.rpc("claim_evolution_dispatch", {
    p_owner: uid,
    p_gen_id: genId,
  });
  if (errClaim) {
    const msg = errClaim.message;
    if (msg.includes("GENERATION_DISPATCH_TIMEOUT")) {
      return json(409, { error: "GENERATION_DISPATCH_TIMEOUT", generation_id: genId });
    }
    return json(500, { error: msg });
  }
  const claim = dispatchClaim as Record<string, unknown>;
  if (claim.timed_out || claim.status === "failed") {
    return json(409, { error: "GENERATION_DISPATCH_TIMEOUT", generation_id: genId });
  }
  if (claim.dispatching || (claim.replayed && !claim.ready)) {
    return json(202, {
      generation_id: genId,
      anima_id: begin.anima_id,
      target_stage: targetStage,
      status: "dispatching",
    });
  }

  const dispatchBegan = Boolean(claim.ready);
  try {
    const predId = await mulaiGeneration(modelGambar, input, webhook, {
      cancelAfter: EVOLUTION_CANCEL_AFTER,
    });
    const { error: errAttach } = await db.rpc("attach_evolution_prediction", {
      p_gen_id: genId,
      p_prediction_id: predId,
    });
    if (errAttach) {
      if (dispatchBegan) {
        return json(202, {
          generation_id: genId,
          anima_id: begin.anima_id,
          target_stage: targetStage,
          status: "dispatching",
        });
      }
      return json(500, { error: errAttach.message });
    }

    return json(202, {
      generation_id: genId,
      anima_id: begin.anima_id,
      target_stage: targetStage,
      status: "running",
      eta_seconds: 65,
      plan,
    });
  } catch (e) {
    const alasan = e instanceof Error ? e.message : String(e);
    if (dispatchBegan && dispatchDefinitelyNotStarted(e)) {
      await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: alasan.slice(0, 500) });
      return json(502, { error: alasan });
    }
    if (dispatchBegan) {
      return json(202, {
        generation_id: genId,
        anima_id: begin.anima_id,
        target_stage: targetStage,
        status: "dispatching",
      });
    }
    await db.rpc("fail_evolution", { p_gen_id: genId, p_reason: alasan.slice(0, 500) });
    return json(502, { error: alasan });
  }
});
