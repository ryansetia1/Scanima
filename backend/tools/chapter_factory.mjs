#!/usr/bin/env node
// Chapter Factory — pipeline developer-only untuk Expedition chapter.
//
//   node backend/tools/chapter_factory.mjs [--chapter-dir=path] [build|validate|review|design|...]
//
// Tidak ada endpoint player. Paid generation/design memanggil Replicate hanya dengan --paid --apply.

import { stableStringify } from "../supabase/functions/_shared/legacy_typing.mjs";
import { approveChapter } from "./chapter_factory/approval.mjs";
import {
  paidCostPreview,
  paidExecutionGate,
  reprocessTrophy,
  runPaidGeneration,
} from "./chapter_factory/paid.mjs";
import { ensureCostLedger } from "./chapter_factory/cost_ledger.mjs";
import { activateChapter, publishChapter } from "./chapter_factory/publish.mjs";
import {
  buildAndWriteChapter,
  chapterRoot,
  readStoredManifest,
} from "./chapter_factory/io.mjs";
import { loadChapterContext } from "./chapter_factory/context.mjs";
import { designCostPreview, designExecutionGate, runDesignCommand } from "./chapter_factory/design.mjs";
import { buildReviewPage } from "./chapter_factory/review.mjs";
import { runChapterFactorySelftest } from "./chapter_factory/selftest.mjs";
import { validateChapterDraft, validateDesign } from "./chapter_factory/validate.mjs";
import { notifyChapter } from "./chapter_factory/notify.mjs";
import { runManualIngest } from "./chapter_factory/manual.mjs";
import { writeFile } from "node:fs/promises";
import {
  DESIGN_ACK_PREFIX,
  PUSH_CONFIRM_PHRASE,
  REVIEW_CONFIRM_PHRASE,
} from "./chapter_factory/constants.mjs";

const REPO = new URL("../..", import.meta.url).pathname;

function usage() {
  console.error(`Chapter Factory — Expedition chapter pipeline (developer-only)

Usage:
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] build
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] validate
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] review
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] design [--paid] [--apply] --ack-cost='...'
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] approve --operator --confirm-reviewed
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] publish [--apply]
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] activate [--apply]
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] notify [--apply] --confirm-push='...'
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] generate [--paid] [--apply] --ack-cost='...' [--slots=...]
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] ingest-manual [--apply] [--slots=...] [--cleanup-seams=...]
  node backend/tools/chapter_factory.mjs [--chapter-dir=path] reprocess-trophy [--apply]
  node backend/tools/chapter_factory.mjs --selftest

Default --chapter-dir: backend/chapters/the-sugarworks/v1

Approve example:
  --operator="Ada Lovelace" --confirm-reviewed='${REVIEW_CONFIRM_PHRASE}'

Design paid example:
  --paid --apply --ack-cost='${DESIGN_ACK_PREFIX}'

Push apply confirmation:
  --apply --confirm-push='${PUSH_CONFIRM_PHRASE}'

Env publish/activate/notify --apply: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
Env notify --apply: FCM_PROJECT_ID, FCM_ACCESS_TOKEN
Env paid --apply: REPLICATE_API_TOKEN`);
}

function parseArgs(argv) {
  const args = {
    command: "build",
    chapterDir: null,
    apply: false,
    paid: false,
    ackCost: null,
    slots: null,
    cleanupSeams: null,
    operator: null,
    confirmReviewed: null,
    confirmPush: null,
    selftest: false,
    help: false,
  };
  const rest = argv.slice(2);
  if (rest.length === 0) return args;
  if (rest[0] === "--selftest") {
    args.selftest = true;
    return args;
  }
  if (rest[0] === "--help" || rest[0] === "-h") {
    args.help = true;
    return args;
  }
  let index = 0;
  if (rest[0].startsWith("--chapter-dir=")) {
    args.chapterDir = rest[0].slice("--chapter-dir=".length);
    index = 1;
  } else if (rest[0] === "--chapter-dir") {
    args.chapterDir = rest[1];
    index = 2;
  }
  if (index >= rest.length) return args;
  args.command = rest[index];
  for (let i = index + 1; i < rest.length; i += 1) {
    const token = rest[i];
    if (token === "--apply") args.apply = true;
    else if (token === "--paid") args.paid = true;
    else if (token.startsWith("--chapter-dir=")) args.chapterDir = token.slice("--chapter-dir=".length);
    else if (token === "--chapter-dir") args.chapterDir = rest[++i];
    else if (token.startsWith("--ack-cost=")) args.ackCost = token.slice("--ack-cost=".length);
    else if (token === "--ack-cost") args.ackCost = rest[++i];
    else if (token.startsWith("--slots=")) args.slots = token.slice("--slots=".length);
    else if (token === "--slots") args.slots = rest[++i];
    else if (token.startsWith("--cleanup-seams=")) {
      args.cleanupSeams = token.slice("--cleanup-seams=".length);
    } else if (token === "--cleanup-seams") args.cleanupSeams = rest[++i];
    else if (token.startsWith("--operator=")) args.operator = token.slice("--operator=".length);
    else if (token === "--operator") args.operator = rest[++i];
    else if (token.startsWith("--confirm-reviewed=")) {
      args.confirmReviewed = token.slice("--confirm-reviewed=".length);
    } else if (token === "--confirm-reviewed") args.confirmReviewed = rest[++i];
    else if (token.startsWith("--confirm-push=")) {
      args.confirmPush = token.slice("--confirm-push=".length);
    } else if (token === "--confirm-push") args.confirmPush = rest[++i];
    else throw new Error(`Argumen tidak dikenal: ${token}`);
  }
  return args;
}

function resolveChapterDir(args) {
  return args.chapterDir ?? chapterRoot(REPO);
}

async function loadManifestForCommand(chapterDir) {
  const ctx = await loadChapterContext(chapterDir);
  try {
    const manifest = await readStoredManifest(chapterDir);
    return { manifest, ctx };
  } catch {
    const built = await buildAndWriteChapter(chapterDir, ctx);
    return { manifest: built.manifest, ctx: built.ctx };
  }
}

async function commandBuild(chapterDir) {
  const ctx = await loadChapterContext(chapterDir);
  validateDesign(ctx.design, ctx.brief, ctx);
  console.error(`Chapter Factory: build gratis ${ctx.design.summary.title}…`);
  const built = await buildAndWriteChapter(chapterDir, ctx);
  await ensureCostLedger(chapterDir, ctx, paidCostPreview(ctx));
  if (built.approval?.removed) {
    console.error("Approval ledger lama dihapus karena hash/content berubah.");
  }
  console.error(`Selesai. Manifest hash ${built.manifest.manifest_hash}`);
  console.error(`Review: ${chapterDir}/review.html`);
  process.stdout.write(stableStringify({
    ok: true,
    command: "build",
    chapter_slug: ctx.slug,
    sequence: built.manifest.sequence,
    manifest_hash: built.manifest.manifest_hash,
    asset_count: built.manifest.assets.entries.length,
    approval: built.approval,
    review_html: `${chapterDir}/review.html`,
  }));
}

async function commandValidate(chapterDir) {
  const { manifest, ctx } = await loadManifestForCommand(chapterDir);
  validateChapterDraft(manifest, ctx);
  process.stdout.write(stableStringify({
    ok: true,
    command: "validate",
    chapter_slug: ctx.slug,
    sequence: manifest.sequence,
    manifest_hash: manifest.manifest_hash,
  }));
}

async function commandReview(chapterDir) {
  const { manifest, ctx } = await loadManifestForCommand(chapterDir);
  validateChapterDraft(manifest, ctx);
  const html = await buildReviewPage({ manifest, chapterDir, ctx });
  await writeFile(`${chapterDir}/review.html`, html, "utf8");
  process.stdout.write(stableStringify({ ok: true, command: "review", path: `${chapterDir}/review.html` }));
}

async function commandDesign(chapterDir, args) {
  const gate = designExecutionGate({
    paid: args.paid,
    apply: args.apply,
    acknowledgement: args.ackCost ?? "",
  });
  if (!gate.execute) {
    console.error(`Preview design: 1 Vision call ≈ $${gate.preview.planned_usd.toFixed(3)}`);
    console.error(`Acknowledgement: ${gate.preview.acknowledgement}`);
    console.error(`Butuh --paid --apply --ack-cost='${gate.preview.acknowledgement}' untuk menjalankan Replicate.`);
    process.stdout.write(stableStringify({
      ok: true,
      command: "design",
      mode: "preview",
      preview: gate.preview,
      note: gate.reason,
    }));
    return;
  }
  const result = await runDesignCommand({
    chapterDir,
    paid: args.paid,
    apply: args.apply,
    acknowledgement: args.ackCost ?? "",
  });
  process.stdout.write(stableStringify({ ok: true, command: "design", ...result }));
}

async function commandApprove(chapterDir, args) {
  const { manifest } = await loadManifestForCommand(chapterDir);
  const ledger = await approveChapter({
    chapterDir,
    manifest,
    operator: args.operator,
    confirmReviewed: args.confirmReviewed,
  });
  process.stdout.write(stableStringify({ ok: true, command: "approve", ledger }));
}

async function commandPublish(chapterDir, apply) {
  const { manifest, ctx } = await loadManifestForCommand(chapterDir);
  validateChapterDraft(manifest, ctx);
  const plan = await publishChapter({ chapterDir, manifest, apply });
  process.stdout.write(stableStringify({ ok: true, command: "publish", plan }));
}

async function commandActivate(chapterDir, apply) {
  const { manifest, ctx } = await loadManifestForCommand(chapterDir);
  validateChapterDraft(manifest, ctx);
  const plan = await activateChapter({ chapterDir, manifest, apply });
  process.stdout.write(stableStringify({ ok: true, command: "activate", plan }));
}

async function commandNotify(chapterDir, args) {
  const result = await notifyChapter({
    chapterDir,
    apply: args.apply,
    confirmation: args.confirmPush ?? "",
  });
  process.stdout.write(stableStringify({ ok: true, command: "notify", ...result }));
}

async function commandGenerate(chapterDir, args) {
  const ctx = await loadChapterContext(chapterDir);
  const gate = paidExecutionGate({
    paid: args.paid,
    apply: args.apply,
    acknowledgement: args.ackCost ?? "",
    slots: args.slots,
    ctx,
  });
  if (!gate.execute) {
    console.error(`Preview biaya: ${gate.preview.image_calls} call ≈ $${gate.preview.total_usd.toFixed(2)}`);
    console.error(`Acknowledgement: ${gate.preview.acknowledgement}`);
    console.error(`Butuh --paid --apply --ack-cost='${gate.preview.acknowledgement}' untuk menjalankan Replicate.`);
    process.stdout.write(stableStringify({
      ok: true,
      command: "generate",
      mode: "preview",
      preview: gate.preview,
      note: gate.reason,
    }));
    return;
  }
  const result = await runPaidGeneration({
    chapterDir,
    ctx,
    slots: args.slots,
    acknowledgement: args.ackCost ?? "",
    paid: args.paid,
    apply: args.apply,
  });
  process.stdout.write(stableStringify({ ok: true, command: "generate", ...result }));
}

async function commandReprocessTrophy(chapterDir, apply) {
  const ctx = await loadChapterContext(chapterDir);
  const result = await reprocessTrophy({ chapterDir, ctx, apply });
  process.stdout.write(stableStringify({ command: "reprocess-trophy", ...result }));
}

async function commandIngestManual(chapterDir, args) {
  const ctx = await loadChapterContext(chapterDir);
  const result = await runManualIngest({
    chapterDir,
    ctx,
    slots: args.slots,
    cleanupSeams: args.cleanupSeams,
    apply: args.apply,
  });
  process.stdout.write(stableStringify({ command: "ingest-manual", ...result }));
  if (!result.ok) process.exitCode = 1;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    usage();
    return;
  }
  if (args.selftest) {
    await runChapterFactorySelftest(REPO);
    return;
  }
  const chapterDir = resolveChapterDir(args);
  switch (args.command) {
    case "build":
      await commandBuild(chapterDir);
      break;
    case "validate":
      await commandValidate(chapterDir);
      break;
    case "review":
      await commandReview(chapterDir);
      break;
    case "design":
      await commandDesign(chapterDir, args);
      break;
    case "approve":
      await commandApprove(chapterDir, args);
      break;
    case "publish":
      await commandPublish(chapterDir, args.apply);
      break;
    case "activate":
      await commandActivate(chapterDir, args.apply);
      break;
    case "notify":
      await commandNotify(chapterDir, args);
      break;
    case "generate":
      await commandGenerate(chapterDir, args);
      break;
    case "ingest-manual":
      await commandIngestManual(chapterDir, args);
      break;
    case "reprocess-trophy":
      await commandReprocessTrophy(chapterDir, args.apply);
      break;
    default:
      throw new Error(`Perintah tidak dikenal: ${args.command}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
