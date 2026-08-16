import { requireValidApproval } from "./approval.mjs";
import { loadChapterContext } from "./context.mjs";
import { loadLocalAssetBytes } from "./io.mjs";
import { chapterSequence, manifestHash, sha256Hex } from "./manifest.mjs";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  assertAssetProvenance,
  assetMode,
  readAssetSources,
} from "./provenance.mjs";

const BUCKET = "chapter_assets";

async function writePublishLedger(chapterDir, value) {
  await writeFile(join(chapterDir, "publish.ledger.json"), stableStringify(value));
}

function restEnv() {
  const baseUrl = process.env.SUPABASE_URL?.replace(/\/$/, "");
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!baseUrl || !serviceKey) return null;
  return { baseUrl, serviceKey };
}

function restHeaders(serviceKey, extra = {}) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

async function restFetch(baseUrl, path, serviceKey, init = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: restHeaders(serviceKey, init.headers),
  });
  const text = await response.text();
  let body = text;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    // keep text
  }
  if (!response.ok) {
    const renderedBody = typeof body === "string" ? body : JSON.stringify(body);
    const error = new Error(
      `REST ${init.method ?? "GET"} ${path} → ${response.status}: ${renderedBody.slice(0, 400)}`,
    );
    error.httpStatus = response.status;
    throw error;
  }
  return body;
}

async function uploadImmutableAsset(baseUrl, serviceKey, path, bytes) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  await restFetch(baseUrl, `/storage/v1/object/${BUCKET}/${encoded}`, serviceKey, {
    method: "POST",
    headers: {
      "Content-Type": "image/png",
      "x-upsert": "false",
    },
    body: bytes,
  });
}

async function deleteUploadedAsset(baseUrl, serviceKey, path) {
  await restFetch(baseUrl, `/storage/v1/object/${BUCKET}`, serviceKey, {
    method: "DELETE",
    body: JSON.stringify({ prefixes: [path] }),
  });
}

async function downloadPublicAsset(baseUrl, path) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${baseUrl}/storage/v1/object/public/${BUCKET}/${encoded}`);
  if (!response.ok) {
    throw new Error(`VERIFY_DOWNLOAD_FAILED:${path}:${response.status}:${await response.text()}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

export function isMissingPublicAssetError(error, path) {
  const message = String(error);
  return message.includes(`VERIFY_DOWNLOAD_FAILED:${path}:`)
    && (
      message.includes(`VERIFY_DOWNLOAD_FAILED:${path}:404`)
      || message.includes('"statusCode":"404"')
      || message.includes('"code":"NoSuchKey"')
    );
}

async function findChapterRow(baseUrl, serviceKey, slug) {
  const rows = await restFetch(
    baseUrl,
    `/rest/v1/expedition_chapters?slug=eq.${encodeURIComponent(slug)}&select=id,slug,sequence,status`,
    serviceKey,
  );
  return Array.isArray(rows) ? rows[0] ?? null : null;
}

async function findChapterVersion(baseUrl, serviceKey, chapterId, contentVersion) {
  const rows = await restFetch(
    baseUrl,
    `/rest/v1/expedition_chapter_versions?chapter_id=eq.${chapterId}&content_version=eq.${contentVersion}&select=id,active,published_at,manifest_hash`,
    serviceKey,
  );
  return Array.isArray(rows) ? rows[0] ?? null : null;
}

export function assertActivationHash(version, manifest) {
  if (version?.manifest_hash !== manifest?.manifest_hash) {
    throw new Error(
      `ACTIVATION_HASH_MISMATCH: remote=${version?.manifest_hash ?? "missing"} ` +
      `local=${manifest?.manifest_hash ?? "missing"}`,
    );
  }
}

function verifyFileHash(bytes, expectedHash, path) {
  const actual = sha256Hex(bytes);
  if (actual !== expectedHash) {
    throw new Error(`VERIFY_HASH_FAILED:${path}:${actual}!=${expectedHash}`);
  }
  return actual;
}

export async function publishChapter({
  chapterDir,
  manifest,
  apply = false,
}) {
  const ctx = await loadChapterContext(chapterDir);
  const approval = await requireValidApproval({ chapterDir, manifest });
  const brief = JSON.parse(await readFile(join(chapterDir, "brief.json"), "utf8"));
  const sequence = chapterSequence(manifest, ctx);
  const assetSources = await readAssetSources(chapterDir);
  const recordedAssetMode = assetMode(ctx, assetSources);
  if (manifest.factory?.mode !== recordedAssetMode) {
    throw new Error(
      `ASSET_PROVENANCE_MISMATCH: manifest=${manifest.factory?.mode ?? "missing"} ` +
      `ledger=${recordedAssetMode}`,
    );
  }
  if (recordedAssetMode === "production") {
    assertAssetProvenance(ctx, manifest, assetSources);
  }
  const plan = {
    mode: apply ? "apply" : "dry-run",
    bucket: BUCKET,
    chapter_slug: manifest.factory?.slug ?? brief.slug,
    content_version: manifest.content_version,
    manifest_hash: manifestHash(manifest),
    asset_count: manifest.assets.entries.length,
    asset_mode: manifest.factory?.mode ?? "unknown",
    publishable: manifest.factory?.mode === "production",
    sequence,
    approval,
  };

  for (const entry of manifest.assets.entries) {
    const bytes = await loadLocalAssetBytes(chapterDir, entry.path, ctx);
    verifyFileHash(bytes, entry.sha256, entry.path);
  }
  plan.uploads = manifest.assets.entries.map((entry) => ({
    path: entry.path,
    sha256: entry.sha256,
  }));

  if (!apply) {
    plan.note = plan.publishable
      ? "Dry-run lokal — tidak ada query remote"
      : "Dry-run lokal — asset procedural/mixed tidak boleh dipublish";
    return plan;
  }
  if (!plan.publishable) {
    throw new Error("PLACEHOLDER_ASSETS_NOT_PUBLISHABLE: generate dan review seluruh 14 slot");
  }

  const env = restEnv();
  if (!env) {
    throw new Error("PUBLISH_APPLY_REQUIRES_ENV: SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY wajib untuk --apply");
  }
  const chapterRow = await findChapterRow(env.baseUrl, env.serviceKey, plan.chapter_slug);
  if (chapterRow && Number(chapterRow.sequence) !== sequence) {
    throw new Error(`CHAPTER_SEQUENCE_CONFLICT:remote=${chapterRow.sequence} local=${sequence}`);
  }
  if (
    chapterRow
    && await findChapterVersion(
      env.baseUrl,
      env.serviceKey,
      chapterRow.id,
      manifest.content_version,
    )
  ) {
    throw new Error("CHAPTER_VERSION_EXISTS: tidak menimpa versi immutable");
  }

  const publishLedger = {
    chapter_slug: plan.chapter_slug,
    content_version: plan.content_version,
    manifest_hash: plan.manifest_hash,
    status: "uploading",
    started_at: new Date().toISOString(),
    uploads: [],
  };
  await writePublishLedger(chapterDir, publishLedger);

  const uploads = [];
  const createdPaths = [];
  try {
    for (const entry of manifest.assets.entries) {
      const bytes = await loadLocalAssetBytes(chapterDir, entry.path, ctx);
      let remoteBytes;
      try {
        remoteBytes = await downloadPublicAsset(env.baseUrl, entry.path);
        verifyFileHash(remoteBytes, entry.sha256, entry.path);
      } catch (error) {
        if (!isMissingPublicAssetError(error, entry.path)) throw error;
        await uploadImmutableAsset(env.baseUrl, env.serviceKey, entry.path, bytes);
        createdPaths.push(entry.path);
        remoteBytes = await downloadPublicAsset(env.baseUrl, entry.path);
      }
      verifyFileHash(remoteBytes, entry.sha256, entry.path);
      uploads.push({ path: entry.path, sha256: entry.sha256 });
      publishLedger.uploads = [...uploads];
      await writePublishLedger(chapterDir, publishLedger);
    }
  } catch (error) {
    const cleanupFailures = [];
    for (const path of createdPaths.reverse()) {
      try {
        await deleteUploadedAsset(env.baseUrl, env.serviceKey, path);
      } catch (cleanupError) {
        cleanupFailures.push(`${path}: ${String(cleanupError)}`);
      }
    }
    const suffix = cleanupFailures.length > 0
      ? `; cleanup manual wajib: ${cleanupFailures.join(" | ")}`
      : "; upload parsial sudah dibersihkan";
    publishLedger.status = cleanupFailures.length > 0 ? "cleanup_failed" : "failed";
    publishLedger.error = `${String(error)}${suffix}`.slice(0, 1000);
    await writePublishLedger(chapterDir, publishLedger);
    throw new Error(`PUBLISH_UPLOAD_FAILED: ${String(error)}${suffix}`);
  }

  const versionPayload = {
    content_version: manifest.content_version,
    schema_version: manifest.schema_version,
    minimum_build: manifest.minimum_build,
    manifest,
    manifest_hash: plan.manifest_hash,
    asset_prefix: manifest.assets.prefix,
    approved_at: approval.approved_at,
    published_at: new Date().toISOString(),
    active: false,
  };

  let staged;
  try {
    staged = await restFetch(
      env.baseUrl,
      "/rest/v1/rpc/stage_expedition_chapter_version",
      env.serviceKey,
      {
        method: "POST",
        body: JSON.stringify({
          p_slug: plan.chapter_slug,
          p_sequence: sequence,
          p_content_version: manifest.content_version,
          p_schema_version: manifest.schema_version,
          p_minimum_build: manifest.minimum_build,
          p_manifest: manifest,
          p_manifest_hash: plan.manifest_hash,
          p_asset_prefix: manifest.assets.prefix,
          p_approved_at: approval.approved_at,
          p_trophy_slug: manifest.trophy.slug,
          p_trophy_display_name: manifest.trophy.display_name,
          p_trophy_description: manifest.trophy.description,
          p_trophy_art_path: manifest.trophy.art_path,
          p_trophy_art_hash: manifest.trophy.art_hash,
          p_trophy_metadata: manifest.trophy.metadata ?? {},
        }),
      },
    );
  } catch (error) {
    if (Number(error?.httpStatus) >= 400 && Number(error?.httpStatus) < 500) {
      const cleanupFailures = [];
      for (const path of [...createdPaths].reverse()) {
        try {
          await deleteUploadedAsset(env.baseUrl, env.serviceKey, path);
        } catch (cleanupError) {
          cleanupFailures.push(`${path}: ${String(cleanupError)}`);
        }
      }
      if (cleanupFailures.length === 0) {
        publishLedger.status = "failed";
        publishLedger.error = String(error).slice(0, 1000);
        await writePublishLedger(chapterDir, publishLedger);
        throw new Error(`PUBLISH_STAGE_REJECTED: DB menolak staging; upload dibersihkan. ${String(error)}`);
      }
      publishLedger.status = "cleanup_failed";
      publishLedger.error = `${String(error)}; ${cleanupFailures.join(" | ")}`.slice(0, 1000);
      await writePublishLedger(chapterDir, publishLedger);
      throw new Error(
        `PUBLISH_STAGE_REJECTED: DB menolak staging; cleanup manual wajib: ` +
        `${cleanupFailures.join(" | ")}. ${String(error)}`,
      );
    }
    publishLedger.status = "uncertain";
    publishLedger.error = String(error).slice(0, 1000);
    await writePublishLedger(chapterDir, publishLedger);
    throw new Error(
      `PUBLISH_STAGE_UNCERTAIN: assets terverifikasi tetapi DB staging gagal/unknown; ` +
      `jangan regenerate atau retry sebelum memeriksa manifest ${plan.manifest_hash}. ${String(error)}`,
    );
  }

  publishLedger.status = "staged";
  publishLedger.version_id = staged.version_id;
  publishLedger.staged_at = new Date().toISOString();
  await writePublishLedger(chapterDir, publishLedger);
  return { ...plan, uploads, versionPayload, staged };
}

export async function activateChapter({
  chapterDir,
  manifest,
  apply = false,
}) {
  const ctx = await loadChapterContext(chapterDir);
  await requireValidApproval({ chapterDir, manifest });
  const assetSources = await readAssetSources(chapterDir);
  const recordedAssetMode = assetMode(ctx, assetSources);
  if (manifest.factory?.mode !== recordedAssetMode) {
    throw new Error(
      `ASSET_PROVENANCE_MISMATCH: manifest=${manifest.factory?.mode ?? "missing"} ` +
      `ledger=${recordedAssetMode}`,
    );
  }
  if (recordedAssetMode === "production") {
    assertAssetProvenance(ctx, manifest, assetSources);
  }
  const slug = manifest.factory?.slug ?? ctx.slug;
  const plan = {
    mode: apply ? "apply" : "dry-run",
    rpc: "activate_expedition_chapter_version",
    chapter_slug: slug,
    content_version: manifest.content_version,
    asset_mode: manifest.factory?.mode ?? "unknown",
    activatable: manifest.factory?.mode === "production",
  };

  if (!apply) {
    plan.note = plan.activatable
      ? "Dry-run lokal — tidak ada query remote"
      : "Dry-run lokal — asset procedural/mixed tidak boleh diaktifkan";
    return plan;
  }
  if (!plan.activatable) {
    throw new Error("PLACEHOLDER_ASSETS_NOT_ACTIVATABLE");
  }

  const env = restEnv();
  if (!env) {
    throw new Error("ACTIVATE_APPLY_REQUIRES_ENV: SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY wajib untuk --apply");
  }

  const chapterRow = await findChapterRow(env.baseUrl, env.serviceKey, slug);
  if (!chapterRow?.id) throw new Error("CHAPTER_NOT_STAGED");
  const version = await findChapterVersion(
    env.baseUrl,
    env.serviceKey,
    chapterRow.id,
    manifest.content_version,
  );
  if (!version?.id) throw new Error("CHAPTER_VERSION_NOT_STAGED");
  assertActivationHash(version, manifest);
  plan.version_id = version.id;

  await restFetch(env.baseUrl, "/rest/v1/rpc/activate_expedition_chapter_version", env.serviceKey, {
    method: "POST",
    body: JSON.stringify({
      p_chapter_id: chapterRow.id,
      p_content_version: manifest.content_version,
    }),
  });
  await writeFile(
    join(chapterDir, "activation.ledger.json"),
    stableStringify({
      chapter_slug: slug,
      content_version: manifest.content_version,
      chapter_id: chapterRow.id,
      version_id: version.id,
      manifest_hash: manifest.manifest_hash,
      activated_at: new Date().toISOString(),
    }),
  );
  return plan;
}
