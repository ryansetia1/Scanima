import assert from "node:assert/strict";
import { access, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Image } from "imagescript";
import {
  approveChapter,
  readApprovalLedger,
  requireValidApproval,
} from "./approval.mjs";
import {
  postprocessChapterAnima,
  postprocessChapterZone,
  postprocessChromaGridSheet,
  renderTrophyArt,
} from "./assets.mjs";
import {
  BOSS_SEEKER_POSES,
  DESIGN_ACK_PREFIX,
  REVIEW_CONFIRM_PHRASE,
} from "./constants.mjs";
import { createContext, defaultChapterDir, loadChapterContext } from "./context.mjs";
import { designExecutionGate } from "./design.mjs";
import { chapterRoot, loadLocalAssetBytes, writeChapterOutputs } from "./io.mjs";
import {
  buildCompleteManifest,
  chapterSequence,
  manifestHash,
  sha256Hex,
} from "./manifest.mjs";
import {
  parseManualGenerationNotes,
  runManualIngest,
} from "./manual.mjs";
import {
  paidCostPreview,
  paidExecutionGate,
  parsePaidAcknowledgement,
  paidSlotSet,
} from "./paid.mjs";
import {
  activateChapter,
  assertActivationHash,
  isMissingPublicAssetError,
  publishChapter,
} from "./publish.mjs";
import { buildReviewPage } from "./review.mjs";
import { chapterPushPreview, notifyChapter } from "./notify.mjs";
import {
  assertAssetProvenance,
  assetMode,
  readAssetSources,
  withManualAssetSource,
  withReprocessedAssetSource,
} from "./provenance.mjs";
import { promptForSlot } from "./prompts.mjs";
import {
  ensureCostLedger,
  readCostLedger,
  recordDesignCostCall,
} from "./cost_ledger.mjs";
import {
  validateAnimaManifest,
  validateBrief,
  validateChapterDraft,
  validateDesign,
} from "./validate.mjs";
import { stableStringify } from "../../supabase/functions/_shared/legacy_typing.mjs";

function statBlock(seed) {
  return { hp: 48 + seed, atk: 50 + seed, def: 46 + seed, spd: 44 + seed, special: 49 + seed };
}

function paintRect(image, x, y, width, height, color = [30, 20, 50, 255]) {
  for (let row = y; row < y + height; row += 1) {
    for (let column = x; column < x + width; column += 1) {
      image.bitmap.set(color, (row * image.width + column) * 4);
    }
  }
}

async function manualGridFixture({ animaLeak = false, bossCrossing = false } = {}) {
  const image = new Image(1024, 1024);
  for (let offset = 0; offset < image.bitmap.length; offset += 4) {
    image.bitmap.set([0, 255, 0, 255], offset);
  }
  const cell = Math.floor(1024 / 3);
  for (let index = 0; index < 9; index += 1) {
    paintRect(
      image,
      (index % 3) * cell + 100,
      Math.floor(index / 3) * cell + 100,
      120,
      120,
    );
  }
  if (animaLeak) paintRect(image, cell - 24, 150, 5, 5);
  if (bossCrossing) paintRect(image, 250, 100, 220, 120);
  return image.encode();
}

function syntheticBrief() {
  return {
    slug: "clockwork-garden",
    content_version: 1,
    sequence: 99,
    theme: "clockwork botanical conservatory",
    title: "Clockwork Garden",
    description: "Gear vines and brass blooms in a synthetic greenhouse.",
    tone: "bright steampunk nature without franchise references",
    zones: ["Sprout Atrium", "Gear Greenhouse", "Brass Canopy"],
    cast_count: 9,
    boss_seeker: "The Horticulturist",
    trophy: "Garden Cog",
  };
}

function syntheticDesign() {
  const cast = [
    "garden-moss", "garden-vine", "garden-bloom", "garden-thorn", "garden-petal",
    "garden-root", "garden-sap", "garden-spore", "garden-queen",
  ].map((id, index) => ({
    id,
    name: `Garden ${id.split("-")[1]}`,
    species_key: id.replace(/-/g, "_"),
    color_bucket: ["moss", "vine", "bloom", "thorn", "petal", "root", "sap", "spore", "queen"][index],
    element: ["plant", "plant", "air", "toxin", "spark", "stone", "flow", "frost", "spark"][index],
    secondary_element: ["stone", "flow", "plant", "metal", "air", "stone", "plant", "air", "plant"][index],
    strike_name: "Gear Strike",
    surge_name: "Brass Surge",
    base_stats: statBlock(index),
    ...(id === "garden-queen" ? { special: true } : {}),
  }));
  return {
    schema_version: 1,
    map_seed: "clockwork-garden-v1",
    summary: {
      title: "Clockwork Garden",
      title_key: "EXPEDITION_CHAPTER_CLOCKWORK",
      description: "Explore the brass conservatory.",
      description_key: "EXPEDITION_CHAPTER_CLOCKWORK_DESC",
    },
    cast,
    zones: [
      {
        id: "zone-1",
        index: 1,
        title_key: "CLOCKWORK_ZONE_1",
        title: "Sprout Atrium — starter paths",
        battle_opponent_id: "garden-regular-1",
        elite_opponent_id: "garden-elite-1",
        battle_supplies: 3,
        elite_supplies: 5,
      },
      {
        id: "zone-2",
        index: 2,
        title_key: "CLOCKWORK_ZONE_2",
        title: "Gear Greenhouse — mid pressure",
        battle_opponent_id: "garden-elite-1",
        elite_opponent_id: "garden-elite-2",
        battle_supplies: 4,
        elite_supplies: 6,
      },
      {
        id: "zone-3",
        index: 3,
        title_key: "CLOCKWORK_ZONE_3",
        title: "Brass Canopy — boss gate",
        battle_opponent_id: "garden-elite-2",
        elite_opponent_id: "garden-boss",
        battle_supplies: 5,
        elite_supplies: 7,
      },
    ],
    opponents: [
      { id: "garden-regular-1", title_key: "CLOCKWORK_OPP_REG", roster: ["garden-moss", "garden-vine"] },
      { id: "garden-elite-1", title_key: "CLOCKWORK_OPP_ELITE", roster: ["garden-bloom", "garden-thorn", "garden-petal"] },
      { id: "garden-elite-2", title_key: "CLOCKWORK_OPP_MINI", roster: ["garden-root"] },
      {
        id: "garden-boss",
        title_key: "CLOCKWORK_OPP_BOSS",
        roster: ["garden-sap", "garden-spore", "garden-moss", "garden-queen"],
      },
    ],
    boss: { opponent_id: "garden-boss", supplies_reward: 8, title_key: "CLOCKWORK_BOSS" },
    boss_seeker: {
      id: "horticulturist",
      display_name: "The Horticulturist",
      title_key: "CLOCKWORK_BOSS_SEEKER",
      background_story:
        "She rebuilt a failed greenhouse as a clockwork nursery and now tests whether visiting teams can adapt without crushing its fragile ecosystem.",
      visual_direction: "An original adult woman botanist-engineer with an all-ages commanding silhouette.",
      sheet_filename: "horticulturist-seeker.png",
      portrait_pose: "profile",
      dialogue: {
        chapter_intro: "Welcome to my conservatory. Every gear here bites back.",
        boss_intro: "I tend these brass blooms. Your team wilts before my queen.",
        first_attack: "Command: press with moss line pressure.",
        first_special: "Command: unleash the brass tempest.",
        first_switch: "Command: rotate before they recover.",
        last_anima: "One Anima left? Finish this cleanly.",
        victory: "Well played. The gears rest tonight.",
        defeat: "Back to the atrium. Study the layout again.",
        rematch: "Again? Good. The garden never stops turning.",
      },
    },
    trophy: {
      slug: "clockwork-garden-trophy",
      display_name: "Garden Core",
      description: "A faceted Chapter Core proving you cleared the brass conservatory.",
      filename: "garden-trophy.png",
      metadata: {
        theme: "clockwork garden",
        chassis: "chapter_core_v3",
        vessel: "point_hex_vessel_v1",
        palette: ["brass", "forest green", "ivory", "charcoal"],
        silhouette_motif:
          "an octagonal envelope broken by two broad interlocking leaf lobes and one clipped gear corner",
        core_motif: "one abstract interlocking leaf-and-gear fold",
      },
    },
    minimum_build: { android: 0, ios: 0, desktop: 0 },
  };
}

async function writeSyntheticChapter(chapterDir) {
  const brief = syntheticBrief();
  const design = syntheticDesign();
  await mkdir(chapterDir, { recursive: true });
  await writeFile(join(chapterDir, "brief.json"), stableStringify(brief));
  await writeFile(join(chapterDir, "design.json"), stableStringify(design));
  return { brief, design };
}

function assertNoSugarworksLeak(value, label) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  assert.doesNotMatch(text, /the-sugarworks/i, `${label} must not leak Sugarworks paths`);
  assert.doesNotMatch(text, /sugarworks/i, `${label} must not leak Sugarworks ids`);
}

export async function runChapterFactorySelftest(repoRoot) {
  const defaultDir = defaultChapterDir(repoRoot);
  const ctx = await loadChapterContext(defaultDir);
  assert.equal(ctx.sequence, 1);
  assert.equal(ctx.brief.sequence, 1);
  validateBrief(ctx.brief);
  validateDesign(ctx.design, ctx.brief, ctx);
  const bossPrompt = await promptForSlot("boss_seeker", ctx);
  assert.match(bossPrompt, /twenty-three-year-old woman Confection Archive Curator/i);
  assert.match(bossPrompt, /youngest archive curator/i);
  assert.match(bossPrompt, /recognizable as a solid black shape/i);
  assert.match(bossPrompt, /four to six major flat colors/i);
  assert.match(bossPrompt, /zero or one command prop/i);
  assert.match(bossPrompt, /octagonal plum recipe folio/i);
  assert.match(bossPrompt, /Cells 1 through 8 keep the same three-quarter forward-left/i);
  assert.match(bossPrompt, /Cell 9 keeps that same three-quarter forward-left/i);
  assert.match(bossPrompt, /pupils turn to make direct eye contact with the player/i);
  assert.match(bossPrompt, /nose stays off-center and the shoulders stay diagonal/i);
  assert.match(bossPrompt, /not a request for a side-profile view/i);
  assert.doesNotMatch(bossPrompt, /whisk-baton|Graphic Commandant|mid-40s/i);
  const trophyPrompt = await promptForSlot("trophy", ctx);
  assert.match(trophyPrompt, /two-layer Chapter Core v3/i);
  assert.match(trophyPrompt, /point_hex_vessel_v1.*do not draw it/i);
  assert.match(trophyPrompt, /Sugarfold Core/i);
  assert.match(trophyPrompt, /shallow concave wrapper-pressure pinch/i);
  assert.match(trophyPrompt, /amber central lozenge structurally locked/i);
  assert.match(trophyPrompt, /never stamp a random\s+emblem or letter/i);
  assert.match(trophyPrompt, /No glass shell, orb, crystal container, outer frame/i);
  assert.doesNotMatch(trophyPrompt, /whisk|furnace|sprinkle/i);
  const zonePrompt = await promptForSlot("zone:1", ctx);
  assert.match(zonePrompt, /combat arena/i);
  assert.match(zonePrompt, /lower 22–26%/);
  assert.match(zonePrompt, /no liquid, rails, gutters, or chasms/i);
  assert.match(zonePrompt, /six to nine harmonized color groups/i);
  assert.match(zonePrompt, /Asymmetric open courtyard/i);
  assert.doesNotMatch(zonePrompt, /readable path lanes|route-like lanes/i);
  const highResolutionZone = new Image(1536, 1024);
  highResolutionZone.bitmap.fill(120);
  const processedZone = await postprocessChapterZone(await highResolutionZone.encode());
  const decodedZone = await Image.decode(processedZone.png);
  assert.deepEqual(
    [decodedZone.width, decodedZone.height],
    [1536, 864],
    "zone crop mempertahankan resolusi raw alih-alih turun ke 768×432",
  );
  const processedBoss = await postprocessChromaGridSheet(
    await manualGridFixture(),
    { poses: BOSS_SEEKER_POSES },
  );
  assert.deepEqual(processedBoss.manifest.frame_size, [300, 300]);
  assert.deepEqual(processedBoss.manifest.render_metrics, {
    reference_height_px: 120,
    reference_width_px: 120,
  });
  await assert.rejects(
    async () => postprocessChromaGridSheet(
      await manualGridFixture({ bossCrossing: true }),
      { poses: BOSS_SEEKER_POSES },
    ),
    /GRID_SEAM_VIOLATION/,
  );
  const missingPath = "expeditions/example/v2/animas/example/sheet.png";
  assert.equal(
    isMissingPublicAssetError(
      new Error(`VERIFY_DOWNLOAD_FAILED:${missingPath}:404`),
      missingPath,
    ),
    true,
  );
  assert.equal(
    isMissingPublicAssetError(
      new Error(
        `VERIFY_DOWNLOAD_FAILED:${missingPath}:400:`
        + '{"statusCode":"404","error":"not_found","code":"NoSuchKey"}',
      ),
      missingPath,
    ),
    true,
  );
  await assert.rejects(
    async () => postprocessChapterAnima(
      await manualGridFixture({ animaLeak: true }),
      ctx.design.cast[0],
    ),
    /sheet melanggar safe margin v12/,
  );
  const cleanedLeak = await postprocessChapterAnima(
    await manualGridFixture({ animaLeak: true }),
    ctx.design.cast[0],
    { cleanupIdleSeamLeaks: true },
  );
  assert.deepEqual(cleanedLeak.manifest.qa.seam_cleanup, {
    mode: "remove_detached_idle_components_v1",
    components: 1,
    pixels: 25,
  });

  // ponytail: baseline selalu procedural agar tidak bergantung pada slot working tree;
  // disk-source manual diuji terpisah lewat fixture temp di bawah.
  const { manifest, assets } = await buildCompleteManifest({ ctx });
  validateChapterDraft(manifest, ctx);
  const reviewPage = await buildReviewPage({ manifest, chapterDir: defaultDir, ctx });
  assert.match(reviewPage, /arena-stage/);
  assert.match(reviewPage, /arena-foot/);
  assert.match(reviewPage, /protected floor band/);
  assert.equal(manifest.trophy.metadata.chassis, "chapter_core_v3");
  assert.equal(manifest.trophy.metadata.vessel, "point_hex_vessel_v1");
  const reprocessedSource = withReprocessedAssetSource(
    { slots: { trophy: { source: "replicate", prediction_id: "prediction-1" } } },
    "trophy",
    "a".repeat(64),
  );
  assert.equal(reprocessedSource.slots.trophy.prediction_id, "prediction-1");
  assert.equal(reprocessedSource.slots.trophy.output_sha256, "a".repeat(64));
  assert.ok(reprocessedSource.slots.trophy.reprocessed_at);
  assert.deepEqual(
    parseManualGenerationNotes(
      "# Notes\n- Provider: ChatGPT image generation\n" +
      "- Generated by: Test Operator\n- Generated at: 2026-08-15 (UTC+7)\n",
    ),
    {
      provider: "ChatGPT image generation",
      operator: "Test Operator",
      generatedAt: "2026-08-15 (UTC+7)",
    },
  );
  const manualSource = withManualAssetSource({ slots: {} }, "anima:garden-moss", {
    provider: "ChatGPT image generation",
    operator: "Test Operator",
    generatedAt: "2026-08-15 (UTC+7)",
    inputPath: "manual_inbox/animas/garden-moss.png",
    inputHash: "b".repeat(64),
    outputHash: "c".repeat(64),
    notesHash: "d".repeat(64),
    postprocess: {
      mode: "remove_detached_idle_components_v1",
      components: 1,
      pixels: 25,
    },
  });
  assert.equal(manualSource.slots["anima:garden-moss"].source, "manual_chatgpt");
  assert.equal(manualSource.slots["anima:garden-moss"].prediction_id, undefined);
  assert.equal(manualSource.slots["anima:garden-moss"].input_sha256, "b".repeat(64));
  assert.equal(
    manualSource.slots["anima:garden-moss"].postprocess.mode,
    "remove_detached_idle_components_v1",
  );
  const compositeTrophy = await Image.decode(assets.trophy.png);
  assert.deepEqual([compositeTrophy.width, compositeTrophy.height], [512, 512]);
  assert.equal(compositeTrophy.bitmap[3], 0, "sudut Trophy tetap transparan");
  assert.ok(
    compositeTrophy.bitmap[(40 * 512 + 256) * 4 + 3] > 0,
    "canonical Vessel harus terlihat di titik atas hexagon",
  );
  assert.ok(
    compositeTrophy.bitmap[(256 * 512 + 256) * 4 + 3] > 0,
    "Inner Core harus terlihat di tengah Vessel",
  );
  const repeatedTrophy = await renderTrophyArt(ctx.design.trophy.slug);
  assert.equal(
    repeatedTrophy.hash,
    assets.trophy.hash,
    "composite PNG wajib byte-stable lintas reprocess Node",
  );
  assert.equal(manifest.sequence, 1);
  assert.equal(chapterSequence(manifest, ctx), 1);
  assert.equal(manifest.zones.length, 3);
  assert.equal(manifest.assets.entries.length, 14);
  const rectangularManifest = structuredClone(manifest.opponents[0].roster[0].manifest);
  rectangularManifest.frame_size = [329, 284];
  for (const pose of Object.values(rectangularManifest.poses)) {
    pose.region[2] = 329;
    pose.region[3] = 284;
  }
  assert.doesNotThrow(() => validateAnimaManifest(rectangularManifest, "rectangular"));
  rectangularManifest.poses.idle.region[2] = 328;
  assert.throws(
    () => validateAnimaManifest(rectangularManifest, "mismatch"),
    /harus sama dengan frame_size/,
  );
  const manifestHashes = new Map(
    manifest.assets.entries.map((entry) => [entry.path, entry.sha256]),
  );
  const pathForSlot = (slot) => {
    if (slot.startsWith("anima:")) return ctx.animaStoragePath(slot.slice("anima:".length));
    if (slot.startsWith("zone:")) return ctx.zoneStoragePath(Number(slot.slice("zone:".length)));
    if (slot === "boss_seeker") return ctx.bossStoragePath();
    return ctx.trophyStoragePath();
  };
  const completeSources = {
    slots: Object.fromEntries(ctx.imageSlots().map((slot, index) => [
      slot,
      {
        source: index % 2 === 0 ? "replicate" : "manual_chatgpt",
        output_sha256: manifestHashes.get(pathForSlot(slot)),
      },
    ])),
  };
  assert.equal(assetMode(ctx, completeSources), "production");
  assert.equal(assertAssetProvenance(ctx, manifest, completeSources), true);
  const mismatchedSources = structuredClone(completeSources);
  mismatchedSources.slots["zone:1"].output_sha256 = "0".repeat(64);
  assert.throws(
    () => assertAssetProvenance(ctx, manifest, mismatchedSources),
    /ASSET_PROVENANCE_HASH_MISMATCH:zone:1/,
  );
  const pushPreview = chapterPushPreview(manifest, {
    version_id: "00000000-0000-4000-8000-000000000001",
  });
  assert.equal(pushPreview.topic, "scanima-expedition-chapters");
  assert.equal(pushPreview.sends, 1);
  assert.doesNotThrow(() => assertActivationHash(
    { manifest_hash: manifest.manifest_hash },
    manifest,
  ));
  assert.throws(
    () => assertActivationHash({ manifest_hash: "0".repeat(64) }, manifest),
    /ACTIVATION_HASH_MISMATCH/,
  );
  assert.match(
    manifest.trophy.art_path,
    /^expeditions\/[a-z0-9][a-z0-9-]{2,47}\/trophy\//,
  );

  const hashTampered = structuredClone(manifest);
  hashTampered.manifest_hash = "0".repeat(64);
  assert.throws(() => validateChapterDraft(hashTampered, ctx), /manifest_hash tidak cocok/);
  const identityTampered = structuredClone(manifest);
  identityTampered.factory.slug = "other-chapter";
  assert.throws(() => validateChapterDraft(identityTampered, ctx), /slug\/sequence|manifest_hash/);
  assert.throws(
    () => validateBrief({ ...ctx.brief, slug: "../unsafe" }),
    /brief.slug tidak aman/,
  );

  assert.throws(
    () => validateDesign({
      ...ctx.design,
      summary: { ...ctx.design.summary, title: "Pokemon Candy Tour" },
    }, ctx.brief, ctx),
    /Istilah IP terlarang/,
  );

  await assert.rejects(
    () => approveChapter({
      chapterDir: "/tmp/unused",
      manifest,
      operator: "Bot",
      confirmReviewed: REVIEW_CONFIRM_PHRASE,
    }),
    /OPERATOR_INVALID|ENOENT/,
  );

  await assert.rejects(
    () => approveChapter({
      chapterDir: "/tmp/unused",
      manifest,
      operator: "Human Reviewer",
      confirmReviewed: "wrong phrase",
    }),
    /REVIEW_CONFIRM_REQUIRED/,
  );

  const tempDir = await mkdtemp(join(tmpdir(), "chapter-factory-"));
  try {
    await writeFile(join(tempDir, "brief.json"), stableStringify(ctx.brief));
    await writeFile(join(tempDir, "design.json"), stableStringify(ctx.design));
    await writeChapterOutputs(tempDir, { manifest, assets }, ctx);
    await ensureCostLedger(tempDir, ctx, paidCostPreview(ctx));
    await recordDesignCostCall(tempDir, ctx, { status: "failed", prediction_id: "p1" });
    await recordDesignCostCall(tempDir, ctx, { status: "succeeded", prediction_id: "p2" });
    assert.equal((await readCostLedger(tempDir)).design_call.completed.length, 2);
    await assert.rejects(
      () => ensureCostLedger(
        tempDir,
        { ...ctx, slug: "other-chapter" },
        paidCostPreview(ctx),
      ),
      /COST_LEDGER_IDENTITY_MISMATCH/,
    );
    const stored = JSON.parse(await readFile(join(tempDir, "chapter.manifest.json"), "utf8"));
    assert.equal(manifestHash(stored), manifest.manifest_hash);
    assert.equal(stored.sequence, 1);

    const firstAsset = manifest.assets.entries[0];
    const bytes = await loadLocalAssetBytes(tempDir, firstAsset.path, ctx);
    assert.equal(sha256Hex(bytes), firstAsset.sha256, "hash file byte harus cocok manifest");

    const tamperedBytes = Buffer.from(bytes);
    tamperedBytes[0] ^= 0xff;
    const rel = ctx.storageToLocalRel(firstAsset.path).replace(/^assets\//, "");
    await writeFile(join(tempDir, "assets", rel), tamperedBytes);
    await assert.rejects(
      () => publishChapter({ chapterDir: tempDir, manifest, apply: false }),
      /APPROVAL_MISSING/,
    );

    await approveChapter({
      chapterDir: tempDir,
      manifest,
      operator: "Selftest Reviewer",
      confirmReviewed: REVIEW_CONFIRM_PHRASE,
      allowSelftestOperator: true,
    });
    const ledger = await readApprovalLedger(tempDir);
    assert.equal(ledger.manifest_hash, manifest.manifest_hash);
    assert.equal(ledger.sequence, 1);
    await requireValidApproval({ chapterDir: tempDir, manifest });
    await writeFile(
      join(tempDir, "activation.ledger.json"),
      stableStringify({
        chapter_slug: ctx.slug,
        content_version: ctx.contentVersion,
        version_id: "00000000-0000-4000-8000-000000000001",
        manifest_hash: manifest.manifest_hash,
      }),
    );
    const notifyPreview = await notifyChapter({ chapterDir: tempDir, apply: false });
    assert.equal(notifyPreview.mode, "preview");
    assert.equal(notifyPreview.preview.topic, "scanima-expedition-chapters");
    await writeFile(
      join(tempDir, "activation.ledger.json"),
      stableStringify({
        chapter_slug: ctx.slug,
        content_version: ctx.contentVersion,
        version_id: "00000000-0000-4000-8000-000000000001",
        manifest_hash: "0".repeat(64),
      }),
    );
    await assert.rejects(
      () => notifyChapter({ chapterDir: tempDir, apply: false }),
      /PUSH_ACTIVATION_LEDGER_MISMATCH/,
    );

    await assert.rejects(
      () => publishChapter({ chapterDir: tempDir, manifest, apply: false }),
      /VERIFY_HASH_FAILED|TAMPER/,
    );

    await writeChapterOutputs(tempDir, { manifest, assets }, ctx);
    await approveChapter({
      chapterDir: tempDir,
      manifest,
      operator: "Selftest Reviewer",
      confirmReviewed: REVIEW_CONFIRM_PHRASE,
      allowSelftestOperator: true,
    });

    const publishPlan = await publishChapter({ chapterDir: tempDir, manifest, apply: false });
    assert.equal(publishPlan.mode, "dry-run");
    assert.equal(publishPlan.sequence, 1);
    assert.match(publishPlan.note ?? "", /Dry-run lokal/i);
    assert.equal(publishPlan.publishable, false);
    assert.equal(publishPlan.remote_ready, undefined);
    await assert.rejects(
      () => publishChapter({ chapterDir: tempDir, manifest, apply: true }),
      /PLACEHOLDER_ASSETS_NOT_PUBLISHABLE/,
    );

    const activatePlan = await activateChapter({ chapterDir: tempDir, manifest, apply: false });
    assert.equal(activatePlan.mode, "dry-run");
    assert.match(activatePlan.note ?? "", /Dry-run lokal/i);
    assert.equal(activatePlan.activatable, false);

    const badManifest = structuredClone(manifest);
    badManifest.summary.title = "Tampered Title";
    await assert.rejects(
      () => requireValidApproval({ chapterDir: tempDir, manifest: badManifest }),
      /APPROVAL_STALE/,
    );
    const sync = await writeChapterOutputs(
      tempDir,
      { manifest: badManifest, assets },
      ctx,
    );
    assert.equal(sync.removed, true, "rewrite berubah harus menghapus approval lama");
    await assert.rejects(
      () => access(join(tempDir, "approval.ledger.json")),
      /ENOENT/,
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }

  const repoChapterDir = chapterRoot(repoRoot);
  const repoCtx = await loadChapterContext(repoChapterDir);
  const repoManifest = (await buildCompleteManifest({ chapterDir: repoChapterDir, ctx: repoCtx })).manifest;
  const repoApproval = await readApprovalLedger(repoChapterDir);
  assert.equal(repoApproval.manifest_hash, repoManifest.manifest_hash);
  const repoPublishPlan = await publishChapter({
    chapterDir: repoChapterDir,
    manifest: repoManifest,
    apply: false,
  });
  assert.equal(repoPublishPlan.publishable, true);
  assert.equal(repoPublishPlan.asset_count, 14);

  const preview = paidCostPreview(ctx, [ctx.imageSlots()[0], "boss_seeker"]);
  assert.ok(preview.total_usd > 0);
  parsePaidAcknowledgement(preview.acknowledgement, preview);
  assert.throws(() => parsePaidAcknowledgement("wrong ack", preview), /PAID_ACK_REQUIRED/);
  assert.throws(() => paidSlotSet("anima:missing", ctx), /PAID_SLOT_INVALID/);

  const previewGate = paidExecutionGate({
    paid: true,
    apply: false,
    acknowledgement: preview.acknowledgement,
    slots: preview.slots,
    ctx,
  });
  assert.equal(previewGate.execute, false);

  const ackGate = paidExecutionGate({
    paid: true,
    apply: true,
    acknowledgement: "wrong",
    slots: preview.slots,
    ctx,
  });
  assert.equal(ackGate.execute, false);

  const readyGate = paidExecutionGate({
    paid: true,
    apply: true,
    acknowledgement: preview.acknowledgement,
    slots: preview.slots,
    ctx,
  });
  assert.equal(readyGate.execute, true);
  assert.equal(
    assetMode(ctx, {
      slots: Object.fromEntries(
        ctx.imageSlots().map((slot) => [slot, { source: "replicate" }]),
      ),
    }),
    "production",
  );

  const designGatePreview = designExecutionGate({ paid: false, apply: false, acknowledgement: "" });
  assert.equal(designGatePreview.execute, false);
  const designGateBadAck = designExecutionGate({ paid: true, apply: true, acknowledgement: "wrong" });
  assert.equal(designGateBadAck.execute, false);
  const designGateReady = designExecutionGate({ paid: true, apply: true, acknowledgement: DESIGN_ACK_PREFIX });
  assert.equal(designGateReady.execute, true);

  const reviewHtml = await readFile(join(repoChapterDir, "review.html"), "utf8").catch(() => "");
  if (reviewHtml) {
    assert.match(reviewHtml, /assets\/animas\/sugarworks-gumdrop\/sheet\.png/);
    assert.match(reviewHtml, /assets\/zones\/zone-1\.png/);
  }

  const syntheticDir = await mkdtemp(join(tmpdir(), "chapter-factory-synthetic-"));
  try {
    const { brief, design } = await writeSyntheticChapter(syntheticDir);
    const syntheticCtx = createContext(syntheticDir, brief, design);
    validateDesign(design, brief, syntheticCtx);
    const built = await buildCompleteManifest({ chapterDir: syntheticDir, ctx: syntheticCtx });
    validateChapterDraft(built.manifest, syntheticCtx);
    await writeChapterOutputs(syntheticDir, built, syntheticCtx);
    await mkdir(join(syntheticDir, "manual_inbox", "zones"), { recursive: true });
    await writeFile(
      join(syntheticDir, "manual_inbox", "zones", "zone-1.png"),
      built.assets.zones[0].png,
    );
    const notesText =
      "# Manual generation notes\n\n" +
      "- Provider: ChatGPT image generation\n" +
      "- Generated by: Test Operator\n" +
      "- Generated at: 2026-08-15 (UTC+7)\n";
    await writeFile(
      join(syntheticDir, "manual_inbox", "generation-notes.md"),
      notesText,
    );
    const manualPreview = await runManualIngest({
      chapterDir: syntheticDir,
      ctx: syntheticCtx,
      slots: "zone:1",
    });
    assert.equal(manualPreview.ok, true);
    assert.equal(manualPreview.written, false);
    assert.deepEqual(manualPreview.passed.map((entry) => entry.slot), ["zone:1"]);
    const manualApplied = await runManualIngest({
      chapterDir: syntheticDir,
      ctx: syntheticCtx,
      slots: "zone:1",
      apply: true,
    });
    assert.equal(manualApplied.ok, true);
    assert.equal(manualApplied.asset_mode, "mixed");
    const syntheticSources = await readAssetSources(syntheticDir);
    assert.equal(syntheticSources.slots["zone:1"].source, "manual_chatgpt");
    assert.equal(syntheticSources.slots["zone:1"].prediction_id, undefined);
    await mkdir(join(syntheticDir, "manual_inbox", "animas"), { recursive: true });
    await writeFile(
      join(syntheticDir, "manual_inbox", "animas", "zone-1.png"),
      built.assets.zones[0].png,
    );
    const ambiguous = await runManualIngest({
      chapterDir: syntheticDir,
      ctx: syntheticCtx,
      slots: "zone:1",
    });
    assert.equal(ambiguous.ok, false);
    assert.match(ambiguous.failed[0].error, /MANUAL_INPUT_AMBIGUOUS/);
    await rm(join(syntheticDir, "manual_inbox", "animas", "zone-1.png"));

    await writeFile(join(syntheticDir, "manual_inbox", "zones", "zone-1.png"), "not png");
    const invalidPng = await runManualIngest({
      chapterDir: syntheticDir,
      ctx: syntheticCtx,
      slots: "zone:1",
      apply: true,
    });
    assert.equal(invalidPng.ok, false);
    assert.match(invalidPng.failed[0].error, /MANUAL_INPUT_NOT_PNG/);
    assert.deepEqual(await readAssetSources(syntheticDir), syntheticSources);
    await writeFile(
      join(syntheticDir, "manual_inbox", "zones", "zone-1.png"),
      built.assets.zones[0].png,
    );

    await rm(join(syntheticDir, "manual_inbox", "generation-notes.md"));
    const missingNotes = await runManualIngest({
      chapterDir: syntheticDir,
      ctx: syntheticCtx,
      slots: "zone:1",
    });
    assert.equal(missingNotes.ok, false);
    assert.equal(missingNotes.failed.at(-1).slot, "generation-notes");
    await writeFile(join(syntheticDir, "manual_inbox", "generation-notes.md"), notesText);
    const html = await buildReviewPage({
      manifest: built.manifest,
      chapterDir: syntheticDir,
      ctx: syntheticCtx,
    });
    assertNoSugarworksLeak(built.manifest, "synthetic manifest");
    for (const entry of built.manifest.assets.entries) {
      assertNoSugarworksLeak(entry.path, "synthetic asset path");
      assert.match(entry.path, /^expeditions\/clockwork-garden\//);
    }
    assert.match(built.manifest.trophy.art_path, /^expeditions\/clockwork-garden\/trophy\//);
    assertNoSugarworksLeak(html, "synthetic review html");
    assert.match(html, /clockwork-garden/);
  } finally {
    await rm(syntheticDir, { recursive: true, force: true });
  }

  console.log("chapter_factory selftest: OK");
}
