import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";
import { PUSH_CONFIRM_PHRASE } from "./constants.mjs";
import { requireValidApproval } from "./approval.mjs";

const FCM_TOPIC = "scanima-expedition-chapters";

function supabaseEnv() {
  const baseUrl = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !serviceKey) throw new Error("SUPABASE_PUBLISH_ENV_MISSING");
  return { baseUrl: baseUrl.replace(/\/+$/, ""), serviceKey };
}

async function rpc(baseUrl, serviceKey, name, body) {
  const response = await fetch(`${baseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  let value = text;
  try {
    value = text ? JSON.parse(text) : null;
  } catch {
    // Keep the bounded response text in the error below.
  }
  if (!response.ok) {
    throw new Error(`RPC ${name} → ${response.status}: ${String(text).slice(0, 400)}`);
  }
  return value;
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function writePushLedger(chapterDir, value) {
  await writeFile(join(chapterDir, "push.ledger.json"), stableStringify(value));
}

export function chapterPushPreview(manifest, activation) {
  return {
    chapter_slug: manifest.factory.slug,
    content_version: manifest.content_version,
    chapter_version_id: activation.version_id,
    topic: FCM_TOPIC,
    title: `New Expedition: ${manifest.summary.title}`,
    body: manifest.summary.description,
    sends: 1,
  };
}

export async function notifyChapter({
  chapterDir,
  apply = false,
  confirmation = "",
}) {
  const manifest = await readJson(join(chapterDir, "chapter.manifest.json"));
  const approval = await requireValidApproval({ chapterDir, manifest });
  let activation;
  try {
    activation = await readJson(join(chapterDir, "activation.ledger.json"));
  } catch (error) {
    if (error?.code === "ENOENT") {
      throw new Error("PUSH_REQUIRES_ACTIVATION: jalankan activate --apply lebih dulu");
    }
    throw error;
  }
  const preview = chapterPushPreview(manifest, activation);
  if (
    activation.chapter_slug !== manifest.factory.slug
    || Number(activation.content_version) !== Number(manifest.content_version)
    || activation.manifest_hash !== manifest.manifest_hash
    || !activation.version_id
  ) {
    throw new Error("PUSH_ACTIVATION_LEDGER_MISMATCH");
  }
  if (!apply) {
    return {
      ok: true,
      mode: "preview",
      preview,
      required_confirmation: PUSH_CONFIRM_PHRASE,
    };
  }
  if (confirmation !== PUSH_CONFIRM_PHRASE) {
    throw new Error(`PUSH_CONFIRMATION_REQUIRED: --confirm-push='${PUSH_CONFIRM_PHRASE}'`);
  }

  const projectId = process.env.FCM_PROJECT_ID;
  const accessToken = process.env.FCM_ACCESS_TOKEN;
  if (!projectId || !accessToken) throw new Error("FCM_PUSH_ENV_MISSING");
  const env = supabaseEnv();
  const claimed = await rpc(
    env.baseUrl,
    env.serviceKey,
    "claim_expedition_chapter_push",
    { p_chapter_version_id: activation.version_id },
  );
  const ledger = {
    ...preview,
    manifest_hash: manifest.manifest_hash,
    approved_at: approval.approved_at,
    status: "claimed",
    claimed_at: new Date().toISOString(),
  };
  await writePushLedger(chapterDir, ledger);

  let response;
  try {
    response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            topic: FCM_TOPIC,
            notification: {
              title: preview.title,
              body: preview.body,
            },
            data: {
              type: "expedition_chapter",
              slug: String(claimed.slug),
              content_version: String(claimed.content_version),
            },
          },
        }),
      },
    );
  } catch (error) {
    await rpc(env.baseUrl, env.serviceKey, "finish_expedition_chapter_push", {
      p_chapter_version_id: activation.version_id,
      p_status: "uncertain",
      p_message_id: null,
      p_error: String(error),
    });
    ledger.status = "uncertain";
    ledger.error = String(error).slice(0, 500);
    await writePushLedger(chapterDir, ledger);
    throw new Error(`CHAPTER_PUSH_UNCERTAIN: jangan retry otomatis. ${String(error)}`);
  }

  const responseText = await response.text();
  if (!response.ok) {
    await rpc(env.baseUrl, env.serviceKey, "finish_expedition_chapter_push", {
      p_chapter_version_id: activation.version_id,
      p_status: "failed",
      p_message_id: null,
      p_error: `FCM ${response.status}: ${responseText.slice(0, 300)}`,
    });
    ledger.status = "failed";
    ledger.error = `FCM ${response.status}: ${responseText.slice(0, 300)}`;
    await writePushLedger(chapterDir, ledger);
    throw new Error(`CHAPTER_PUSH_REJECTED: FCM ${response.status}`);
  }

  let fcm;
  try {
    fcm = responseText ? JSON.parse(responseText) : {};
  } catch {
    fcm = {};
  }
  const messageId = String(fcm.name ?? "");
  if (!messageId) {
    await rpc(env.baseUrl, env.serviceKey, "finish_expedition_chapter_push", {
      p_chapter_version_id: activation.version_id,
      p_status: "uncertain",
      p_message_id: null,
      p_error: "FCM success response tidak membawa message name",
    });
    ledger.status = "uncertain";
    ledger.error = "FCM success response tidak membawa message name";
    await writePushLedger(chapterDir, ledger);
    throw new Error("CHAPTER_PUSH_UNCERTAIN: FCM response tanpa message name");
  }

  try {
    await rpc(env.baseUrl, env.serviceKey, "finish_expedition_chapter_push", {
      p_chapter_version_id: activation.version_id,
      p_status: "sent",
      p_message_id: messageId,
      p_error: null,
    });
  } catch (error) {
    ledger.status = "uncertain";
    ledger.message_id = messageId;
    ledger.error = String(error).slice(0, 500);
    await writePushLedger(chapterDir, ledger);
    throw new Error(`CHAPTER_PUSH_RECEIPT_UNCERTAIN: push mungkin terkirim; jangan retry. ${String(error)}`);
  }

  ledger.status = "sent";
  ledger.message_id = messageId;
  ledger.sent_at = new Date().toISOString();
  await writePushLedger(chapterDir, ledger);
  return { ok: true, mode: "apply", ...ledger };
}
