// POST /synthesize_anima
// { operation: preview|attempt|resume|history, ... }
//
// Resonance is rolled atomically in Postgres before this function invokes
// Vision or image generation. A technical failure refunds Core + Bits and
// reopens the pair/mode slot.

import { adminClient, clientVersionGate, json } from "../_shared/supa.ts";
import { extractJson } from "../_shared/vision.mjs";
import { buildEvolutionIdleReference } from "../_shared/evolution.mjs";
import { cropIdleThumb } from "../_shared/gallery_shared.mjs";
import {
  assembleSynthesisPrompt,
  synthesisVisionInstruction,
  synthesisWebhookUrl,
  validateSynthesisPlan,
} from "../_shared/synthesis.mjs";
import {
  dispatchDefinitelyNotStarted,
  jalankanPrediksi,
  mulaiGeneration,
} from "../_shared/replicate.ts";
import PROMPTS from "../_shared/prompts.generated.ts";

const MODEL_VISION = Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash";
const IMAGE_QUALITY = Deno.env.get("IMAGE_QUALITY") ?? "medium";
const SIGNED_URL_TTL = 900;
const SYNTHESIS_CANCEL_AFTER = "8m";
const db = adminClient();

type Body = {
  operation?: string;
  idempotency_key?: string;
  source_a_id?: string;
  source_a_stage?: number;
  source_b_id?: string;
  source_b_stage?: number;
  mode?: string;
  result_anima_id?: string;
};

type SourceSnapshot = {
  id: string;
  name: string;
  selected_stage: number;
  sheet_path: string;
  manifest: Record<string, unknown>;
  element: string;
  secondary_element?: string | null;
  base_stats: Record<string, number>;
  body_height_cm: number;
  rarity?: number;
};

type SlotRow = {
  id: string;
  status: string;
  active_generation_id?: string | null;
  result_anima_id?: string | null;
  source_a_snapshot: SourceSnapshot;
  source_b_snapshot: SourceSnapshot;
  reference_paths?: Record<string, string> | null;
  synthesis_plan?: Record<string, unknown> | null;
};

function configString(value: unknown, fallback: string): string {
  if (typeof value === "string" && value.length > 0) return value;
  if (value && typeof value === "object" && "toString" in value) {
    const text = String(value).replace(/^"|"$/g, "");
    if (text) return text;
  }
  return fallback;
}

function synthesisError(status: number, error: unknown): Response {
  const message = error instanceof Error ? error.message : String(error);
  const known = [
    "FEATURE_DISABLED",
    "SYNTHESIS_SOURCES_SAME",
    "SYNTHESIS_FORM_INVALID",
    "SYNTHESIS_STAGE_MISMATCH",
    "SYNTHESIS_MODE_INVALID",
    "SYNTHESIS_FORM_LOCKED",
    "SYNTHESIS_LEVEL_TOO_LOW",
    "SYNTHESIS_MODE_USED",
    "SYNTHESIS_COOLDOWN",
    "SYNTHESIS_ALREADY_ACTIVE",
    "SYNTHESIS_IN_PROGRESS",
    "SYNTHESIS_SOURCE_LOCKED",
    "ANIMA_NOT_FOUND",
    "ANIMA_NOT_READY",
    "ANIMA_DORMANT",
    "ANIMA_IN_ACTIVE_COMBAT",
    "NO_CORE",
    "NO_BITS",
    "SPEND_CAP",
    "IDEMPOTENCY_CONFLICT",
  ].find((code) => message.includes(code));
  return json(known ? status : 500, { error: known ?? message });
}

async function signedUrl(path: string): Promise<string> {
  const { data, error } = await db.storage
    .from("anima_sheets")
    .createSignedUrl(path, SIGNED_URL_TTL);
  if (error || !data?.signedUrl) {
    throw new Error(`SYNTHESIS_REFERENCE_SIGN_FAILED: ${error?.message ?? path}`);
  }
  return data.signedUrl;
}

async function loadSlot(generationId: string): Promise<SlotRow> {
  const { data, error } = await db
    .from("anima_synthesis_slots")
    .select(
      "id, status, active_generation_id, result_anima_id, source_a_snapshot, source_b_snapshot, reference_paths, synthesis_plan",
    )
    .eq("active_generation_id", generationId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("SYNTHESIS_SLOT_MISSING");
  return data as SlotRow;
}

async function downloadSourceBytes(slot: SlotRow): Promise<{
  sourceA: SourceSnapshot;
  sourceB: SourceSnapshot;
  bytesA: Uint8Array;
  bytesB: Uint8Array;
}> {
  const sourceA = slot.source_a_snapshot;
  const sourceB = slot.source_b_snapshot;
  if (!sourceA?.sheet_path || !sourceB?.sheet_path) {
    throw new Error("SYNTHESIS_SOURCE_SHEET_MISSING");
  }
  const [sourceUrlA, sourceUrlB] = await Promise.all([
    signedUrl(sourceA.sheet_path),
    signedUrl(sourceB.sheet_path),
  ]);
  const [downloadA, downloadB] = await Promise.all([fetch(sourceUrlA), fetch(sourceUrlB)]);
  if (!downloadA.ok || !downloadB.ok) {
    throw new Error(
      `SYNTHESIS_REFERENCE_DOWNLOAD_${downloadA.status}_${downloadB.status}`,
    );
  }
  const [bufferA, bufferB] = await Promise.all([
    downloadA.arrayBuffer(),
    downloadB.arrayBuffer(),
  ]);
  return {
    sourceA,
    sourceB,
    bytesA: new Uint8Array(bufferA),
    bytesB: new Uint8Array(bufferB),
  };
}

async function ensureReferences(
  uid: string,
  generationId: string,
  resultAnimaId: string,
  slot: SlotRow,
): Promise<{
  paths: Record<string, string>;
  urls: Record<string, string>;
}> {
  const storedHistoryA = String(slot.reference_paths?.source_a ?? "");
  const storedHistoryB = String(slot.reference_paths?.source_b ?? "");
  const storedModelA = String(
    slot.reference_paths?.model_source_a ?? storedHistoryA,
  );
  const storedModelB = String(
    slot.reference_paths?.model_source_b ?? storedHistoryB,
  );
  if (storedHistoryA && storedHistoryB && storedModelA && storedModelB) {
    const [urlA, urlB] = await Promise.all([
      signedUrl(storedModelA),
      signedUrl(storedModelB),
    ]);
    return {
      paths: {
        ...(slot.reference_paths ?? {}),
        source_a: storedHistoryA,
        source_b: storedHistoryB,
      },
      urls: { source_a: urlA, source_b: urlB },
    };
  }

  const { sourceA, sourceB, bytesA, bytesB } = await downloadSourceBytes(slot);
  const [modelA, modelB, historyA, historyB] = await Promise.all([
    buildEvolutionIdleReference(bytesA, sourceA.manifest),
    buildEvolutionIdleReference(bytesB, sourceB.manifest),
    cropIdleThumb(bytesA, sourceA.manifest),
    cropIdleThumb(bytesB, sourceB.manifest),
  ]);

  const base = `${uid}/${resultAnimaId}/synthesis_refs/${generationId}`;
  const paths = {
    source_a: `${base}_a_history.png`,
    source_b: `${base}_b_history.png`,
    model_source_a: `${base}_a.png`,
    model_source_b: `${base}_b.png`,
  };
  const uploads = await Promise.all([
    db.storage.from("anima_sheets").upload(paths.source_a, historyA, {
      contentType: "image/png",
      upsert: true,
    }),
    db.storage.from("anima_sheets").upload(paths.source_b, historyB, {
      contentType: "image/png",
      upsert: true,
    }),
    db.storage.from("anima_sheets").upload(paths.model_source_a, modelA, {
      contentType: "image/png",
      upsert: true,
    }),
    db.storage.from("anima_sheets").upload(paths.model_source_b, modelB, {
      contentType: "image/png",
      upsert: true,
    }),
  ]);
  const uploadError = uploads.find((upload) => upload.error)?.error;
  if (uploadError) {
    await db.storage.from("anima_sheets").remove(Object.values(paths));
    throw new Error(
      `SYNTHESIS_REFERENCE_UPLOAD: ${uploadError.message}`,
    );
  }
  const { error: storeError } = await db.rpc("store_synthesis_references", {
    p_owner: uid,
    p_gen_id: generationId,
    p_reference_paths: paths,
  });
  if (storeError) {
    await db.storage.from("anima_sheets").remove(Object.values(paths));
    throw new Error(storeError.message);
  }
  const [urlA, urlB] = await Promise.all([
    signedUrl(paths.model_source_a),
    signedUrl(paths.model_source_b),
  ]);
  return {
    paths,
    urls: { source_a: urlA, source_b: urlB },
  };
}

async function ensureTransparentHistoryReferences(
  uid: string,
  resultAnimaId: string,
  history: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const { data, error } = await db
    .from("anima_synthesis_slots")
    .select(
      "id, status, active_generation_id, result_anima_id, source_a_snapshot, source_b_snapshot, reference_paths",
    )
    .eq("owner_id", uid)
    .eq("result_anima_id", resultAnimaId)
    .eq("status", "succeeded")
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("SYNTHESIS_SLOT_MISSING");
  const slot = data as SlotRow;
  const refs = slot.reference_paths ?? {};
  if (refs.model_source_a && refs.model_source_b) return history;

  const legacyA = String(refs.source_a ?? "");
  const legacyB = String(refs.source_b ?? "");
  const generationId = String(slot.active_generation_id ?? "");
  if (!legacyA || !legacyB || !generationId) {
    throw new Error("SYNTHESIS_REFERENCES_INVALID");
  }

  const { sourceA, sourceB, bytesA, bytesB } = await downloadSourceBytes(slot);
  const [historyA, historyB] = await Promise.all([
    cropIdleThumb(bytesA, sourceA.manifest),
    cropIdleThumb(bytesB, sourceB.manifest),
  ]);
  const base = `${uid}/${resultAnimaId}/synthesis_refs/${generationId}`;
  const paths = {
    ...refs,
    source_a: `${base}_a_history.png`,
    source_b: `${base}_b_history.png`,
    model_source_a: legacyA,
    model_source_b: legacyB,
  };
  const uploads = await Promise.all([
    db.storage.from("anima_sheets").upload(paths.source_a, historyA, {
      contentType: "image/png",
      upsert: true,
    }),
    db.storage.from("anima_sheets").upload(paths.source_b, historyB, {
      contentType: "image/png",
      upsert: true,
    }),
  ]);
  const uploadError = uploads.find((upload) => upload.error)?.error;
  if (uploadError) {
    throw new Error(`SYNTHESIS_HISTORY_UPLOAD: ${uploadError.message}`);
  }
  const { error: storeError } = await db.rpc(
    "store_synthesis_history_references",
    {
      p_owner: uid,
      p_result_anima_id: resultAnimaId,
      p_reference_paths: paths,
    },
  );
  if (storeError) throw new Error(storeError.message);

  const output = structuredClone(history);
  for (const [key, path] of [
    ["source_a", paths.source_a],
    ["source_b", paths.source_b],
  ]) {
    const source = output[key];
    if (source && typeof source === "object") {
      (source as Record<string, unknown>).thumbnail_path = path;
    }
  }
  return output;
}

async function historyResponse(uid: string, resultAnimaId: string): Promise<Response> {
  if (!resultAnimaId) return json(400, { error: "result_anima_id wajib" });
  const { data, error } = await db
    .from("animas")
    .select("id, synthesis_history")
    .eq("id", resultAnimaId)
    .eq("owner_id", uid)
    .maybeSingle();
  if (error) return json(500, { error: error.message });
  if (!data) return json(404, { error: "ANIMA_NOT_FOUND" });
  const history = data.synthesis_history;
  if (!history || typeof history !== "object") {
    return json(200, { history: null });
  }
  const output = await ensureTransparentHistoryReferences(
    uid,
    resultAnimaId,
    structuredClone(history) as Record<string, unknown>,
  );
  for (const key of ["source_a", "source_b"]) {
    const source = output[key];
    if (!source || typeof source !== "object") continue;
    const path = String((source as Record<string, unknown>).thumbnail_path ?? "");
    if (!path) continue;
    (source as Record<string, unknown>).thumbnail_url = await signedUrl(path);
    delete (source as Record<string, unknown>).thumbnail_path;
  }
  return json(200, { history: output });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  const versionError = await clientVersionGate(req, db);
  if (versionError) return versionError;

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await db.auth.getClaims(token);
  const uid = auth?.claims?.sub;
  if (authError || typeof uid !== "string") {
    return json(401, { error: "token tidak sah" });
  }

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body bukan JSON" });
  }
  const operation = String(body.operation ?? "preview");
  if (operation === "history") {
    try {
      return await historyResponse(uid, String(body.result_anima_id ?? ""));
    } catch (error) {
      return synthesisError(409, error);
    }
  }

  const sourceAId = String(body.source_a_id ?? "");
  const sourceBId = String(body.source_b_id ?? "");
  const sourceAStage = Math.trunc(Number(body.source_a_stage) || 0);
  const sourceBStage = Math.trunc(Number(body.source_b_stage) || 0);
  const mode = String(body.mode ?? "");
  if (!sourceAId || !sourceBId) {
    return json(400, { error: "dua Source Anima wajib" });
  }
  if (![1, 2, 3].includes(sourceAStage) || ![1, 2, 3].includes(sourceBStage)) {
    return json(400, { error: "stage Source tidak sah" });
  }

  if (operation === "preview") {
    const { data, error } = await db.rpc("preview_synthesis", {
      p_owner: uid,
      p_source_a: sourceAId,
      p_source_a_stage: sourceAStage,
      p_source_b: sourceBId,
      p_source_b_stage: sourceBStage,
      p_mode: mode,
    });
    if (error) return synthesisError(409, error.message);
    return json(200, data);
  }
  if (!["attempt", "resume"].includes(operation)) {
    return json(400, { error: "operation tidak dikenal" });
  }

  const key = String(body.idempotency_key ?? "");
  if (!key || key.length > 128) {
    return json(400, { error: "idempotency_key wajib, maks 128 char" });
  }

  const { data: configRows, error: configError } = await db
    .from("app_config")
    .select("key, value")
    .in("key", ["image_model", "synthesis_prompt_version"]);
  if (configError) return json(500, { error: configError.message });
  const config = Object.fromEntries((configRows ?? []).map((row) => [row.key, row.value]));
  const imageModel = configString(config.image_model, "openai/gpt-image-2");
  const promptVersion = configString(config.synthesis_prompt_version, "v42");
  const promptBundle = PROMPTS as Record<
    string,
    {
      vision_synthesis_system?: string;
      vision_synthesis_schema?: unknown;
      sprite_sheet_synthesis?: string;
    }
  >;
  const prompts = promptBundle[promptVersion];
  if (
    !prompts?.vision_synthesis_system
    || !prompts.vision_synthesis_schema
    || !prompts.sprite_sheet_synthesis
  ) {
    return json(500, { error: `prompt Synthesis ${promptVersion} tidak lengkap` });
  }

  const { data: attemptRaw, error: attemptError } = await db.rpc("attempt_synthesis", {
    p_owner: uid,
    p_key: key,
    p_source_a: sourceAId,
    p_source_a_stage: sourceAStage,
    p_source_b: sourceBId,
    p_source_b_stage: sourceBStage,
    p_mode: mode,
    p_prompt_version: promptVersion,
    p_model: imageModel,
  });
  if (attemptError) return synthesisError(409, attemptError.message);
  const attempt = attemptRaw as Record<string, unknown>;
  if (attempt.resonance_succeeded !== true) {
    return json(200, attempt);
  }

  const generationId = String(attempt.generation_id ?? "");
  const resultAnimaId = String(attempt.result_anima_id ?? "");
  if (!generationId || !resultAnimaId) {
    await db.rpc("fail_synthesis", {
      p_gen_id: generationId,
      p_reason: "SYNTHESIS_RESULT_MISSING",
    });
    return json(500, { error: "SYNTHESIS_RESULT_MISSING" });
  }
  if (attempt.generation_status === "succeeded") {
    return json(200, {
      ...attempt,
      status: "succeeded",
    });
  }
  if (attempt.generation_status === "failed") {
    return json(409, {
      error: "SYNTHESIS_FAILED",
      generation_id: generationId,
      result_anima_id: resultAnimaId,
    });
  }

  let slot: SlotRow;
  let references: { paths: Record<string, string>; urls: Record<string, string> };
  try {
    slot = await loadSlot(generationId);
    references = await ensureReferences(uid, generationId, resultAnimaId, slot);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    await db.rpc("fail_synthesis", {
      p_gen_id: generationId,
      p_reason: reason.slice(0, 500),
    });
    return json(502, { error: reason, generation_id: generationId });
  }

  const { data: generation, error: generationError } = await db
    .from("generations")
    .select("status, prediction_id, vision_result, dispatch_started_at")
    .eq("id", generationId)
    .maybeSingle();
  if (generationError) return json(500, { error: generationError.message });
  if (generation?.status === "succeeded") {
    return json(200, {
      generation_id: generationId,
      result_anima_id: resultAnimaId,
      status: "succeeded",
      idempoten: true,
    });
  }
  if (generation?.status === "failed") {
    return json(409, { error: "SYNTHESIS_FAILED", generation_id: generationId });
  }

  let plan: Record<string, unknown>;
  const sourceA = slot.source_a_snapshot;
  const sourceB = slot.source_b_snapshot;
  // Nama seluruh koleksi, sama seperti Evolve: yang menabrak adalah nama yang
  // dipakai, bukan `suggested_name` yang terkubur di dalam vision_result. Satu
  // kolom teks per Anima juga jauh lebih ringan daripada menarik setiap plan.
  // Kegagalan query dibiarkan lewat — dedup adalah usaha terbaik, dan Synthesis
  // ini sudah membayar Core dan Bits.
  const { data: ownerAnimas } = await db
    .from("animas")
    .select("nickname")
    .eq("owner_id", uid);
  const validationOptions = {
    mode,
    sourceA,
    sourceB,
    ownerNames: (ownerAnimas ?? []).map((row) => String(row.nickname ?? "")),
  };

  if (generation?.vision_result && typeof generation.vision_result === "object") {
    try {
      plan = validateSynthesisPlan(generation.vision_result, validationOptions).plan;
    } catch (error) {
      const reason = `SYNTHESIS_STORED_PLAN_INVALID: ${
        error instanceof Error ? error.message : String(error)
      }`;
      await db.rpc("fail_synthesis", {
        p_gen_id: generationId,
        p_reason: reason.slice(0, 500),
      });
      return json(409, { error: "SYNTHESIS_STORED_PLAN_INVALID" });
    }
  } else {
    const { data: planningRaw, error: planningError } = await db.rpc(
      "claim_synthesis_planning",
      { p_owner: uid, p_gen_id: generationId },
    );
    if (planningError) return synthesisError(409, planningError.message);
    const planning = planningRaw as Record<string, unknown>;
    if (planning.status === "failed" || planning.timed_out) {
      return json(409, { error: "SYNTHESIS_PLAN_TIMEOUT", generation_id: generationId });
    }
    if (!planning.planning_claimed) {
      return json(202, {
        generation_id: generationId,
        result_anima_id: resultAnimaId,
        status: planning.plan_ready ? "planned" : "planning",
      });
    }

    const visionPrompt =
      `Inheritance mode: ${mode}.\n`
      + `Source A metadata: ${
        JSON.stringify({
          name: sourceA.name,
          selected_stage: sourceA.selected_stage,
          element: sourceA.element,
          secondary_element: sourceA.secondary_element,
          base_stats: sourceA.base_stats,
          body_height_cm: sourceA.body_height_cm,
        })
      }\n`
      + `Source B metadata: ${
        JSON.stringify({
          name: sourceB.name,
          selected_stage: sourceB.selected_stage,
          element: sourceB.element,
          secondary_element: sourceB.secondary_element,
          base_stats: sourceB.base_stats,
          body_height_cm: sourceB.body_height_cm,
        })
      }\n`
      + "Analyse both attached Idle references. Return the Synthesis Plan JSON only.";
    try {
      const raw = await jalankanPrediksi(MODEL_VISION, {
        prompt: visionPrompt,
        images: [references.urls.source_a, references.urls.source_b],
        system_instruction: synthesisVisionInstruction(
          prompts.vision_synthesis_system,
          prompts.vision_synthesis_schema,
        ),
        temperature: 0.35,
        top_p: 0.95,
        max_output_tokens: 4096,
        thinking_budget: 0,
        dynamic_thinking: false,
      });
      plan = validateSynthesisPlan(extractJson(raw), validationOptions).plan;
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      await db.rpc("fail_synthesis", {
        p_gen_id: generationId,
        p_reason: reason.slice(0, 500),
      });
      return json(502, { error: reason, generation_id: generationId });
    }

    const { error: reserveError } = await db.rpc("reserve_synthesis_plan", {
      p_owner: uid,
      p_gen_id: generationId,
      p_plan: plan,
      p_reference_paths: references.paths,
    });
    if (reserveError) {
      await db.rpc("fail_synthesis", {
        p_gen_id: generationId,
        p_reason: reserveError.message.slice(0, 500),
      });
      return json(500, { error: reserveError.message });
    }
  }

  const imagePrompt = assembleSynthesisPrompt(
    prompts.sprite_sheet_synthesis,
    plan,
    sourceA,
    sourceB,
    mode,
  );
  const imageInput = imageModel === "openai/gpt-image-2"
    ? {
      prompt: imagePrompt,
      input_images: [references.urls.source_a, references.urls.source_b],
      aspect_ratio: "1024x1024",
      quality: IMAGE_QUALITY,
      number_of_images: 1,
      background: "opaque",
      output_format: "png",
      output_compression: 100,
      moderation: "auto",
    }
    : {
      prompt: imagePrompt,
      image_input: [references.urls.source_a, references.urls.source_b],
      aspect_ratio: "1:1",
      resolution: "2K",
      output_format: "png",
      safety_filter_level: "block_only_high",
      allow_fallback_model: false,
    };

  const { data: dispatchRaw, error: dispatchError } = await db.rpc(
    "claim_synthesis_dispatch",
    { p_owner: uid, p_gen_id: generationId },
  );
  if (dispatchError) return synthesisError(409, dispatchError.message);
  const dispatch = dispatchRaw as Record<string, unknown>;
  if (dispatch.status === "succeeded") {
    return json(200, {
      generation_id: generationId,
      result_anima_id: resultAnimaId,
      status: "succeeded",
      idempoten: true,
    });
  }
  if (dispatch.status === "failed" || dispatch.timed_out) {
    return json(409, {
      error: "SYNTHESIS_FAILED",
      generation_id: generationId,
    });
  }
  if (dispatch.prediction_id || dispatch.dispatching || !dispatch.ready) {
    return json(202, {
      generation_id: generationId,
      result_anima_id: resultAnimaId,
      status: dispatch.prediction_id ? "running" : "dispatching",
      idempoten: true,
    });
  }

  const webhookBase = `${Deno.env.get("SUPABASE_URL")}/functions/v1/replicate_webhook`;
  const webhook = synthesisWebhookUrl(webhookBase, generationId);
  try {
    const predictionId = await mulaiGeneration(imageModel, imageInput, webhook, {
      cancelAfter: SYNTHESIS_CANCEL_AFTER,
    });
    const { error: attachError } = await db.rpc("attach_synthesis_prediction", {
      p_gen_id: generationId,
      p_prediction_id: predictionId,
    });
    if (attachError) {
      return json(202, {
        generation_id: generationId,
        result_anima_id: resultAnimaId,
        status: "dispatching",
      });
    }
    return json(202, {
      generation_id: generationId,
      result_anima_id: resultAnimaId,
      status: "running",
      eta_seconds: 65,
      plan,
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    if (dispatchDefinitelyNotStarted(error)) {
      await db.rpc("fail_synthesis", {
        p_gen_id: generationId,
        p_reason: reason.slice(0, 500),
      });
      return json(502, { error: reason });
    }
    return json(202, {
      generation_id: generationId,
      result_anima_id: resultAnimaId,
      status: "dispatching",
    });
  }
});
