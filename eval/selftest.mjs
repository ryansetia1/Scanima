// Pemeriksaan post-processing tanpa memanggil API sama sekali.
//
// Sheet sintetis dibuat dengan blob yang sengaja TIDAK di tengah kuadran dan
// berukuran berbeda-beda, karena justru itu kondisi yang membedakan slicing
// content-aware dari pembagian grid buta. Pembagian 1024/2 akan memotong blob
// yang menempel ke tepi kuadran, dan test ini akan menangkapnya.
//
// Jalankan: node eval/selftest.mjs

import assert from "node:assert/strict";
import { Image } from "imagescript";
import {
  POSES,
  POSE_QUADRANT,
  LAYOUT_3X3,
  DEFAULTS,
  isKeyColor,
  isCatalogKeyVapor,
  findBBox,
  heightMetrics,
  postprocessSheet,
  stripWhiteKeylineFromRgba,
} from "../backend/supabase/functions/_shared/postprocess.mjs";
import {
  validateVision,
  assemblePrompt,
  extractJson,
  normalizeSuggestedName,
  normalizeMoveName,
  promptMajor,
  spriteSheetTemplate,
} from "../backend/supabase/functions/_shared/vision.mjs";
import { biayaGambarUsd } from "../backend/supabase/functions/_shared/pricing.mjs";
import {
  ELEMENT_ALIASES,
  ELEMENT_CYCLE,
  ELEMENT_ROSTER,
  ELEMENT_STRENGTHS,
  MATCHUP_NEUTRAL,
  MATCHUP_STRONG,
  MATCHUP_WEAK,
  dualDefenderMultiplier,
  normalizeElement,
  singleMatchup,
} from "../backend/supabase/functions/_shared/elements.mjs";
import {
  MOMENTUM_MAX,
  MOMENTUM_START,
  RULES_VERSION,
  SURGE_COST,
  turnSeed,
  baseStatTotal,
  battleExpYield,
  battleRewardPreview,
  computeDamage,
  createBattleState,
  critChance,
  elementMultiplier,
  normalizeBaseStats,
  resolveTurn,
  toBattleStats,
  hungerCombatMultiplier,
  hygieneCombatMultiplier,
  careCombatMultiplier,
  EXP_MAX,
  expForLevel,
  expToNextLevel,
  levelFromExp,
  growthMultiplier,
  formFromLevel,
  BATTLE_MAX_TURNS,
  LEVEL_CAP,
  HUNGRY_NEED,
  DIRTY_NEED,
  HUNGRY_COMBAT_FLOOR,
  DIRTY_COMBAT_FLOOR,
  CARE_COMBAT_FLOOR,
} from "../backend/supabase/functions/_shared/battle.mjs";
import {
  BATTLE_BITS_CAP,
  CATALOG_ITEMS,
  REWARD_TIERS,
  STARTER_BITS,
  bitsForTier,
  catalogItem,
  rewardTierFromRatio,
} from "../backend/supabase/functions/_shared/catalog.mjs";
import {
  TEAM_MAX_TURNS,
  createTeamBattleState,
  resolveTeamTurn,
  teamCombatPower,
  teamRewardPreview,
} from "../backend/supabase/functions/_shared/team_combat.mjs";
import {
  applyEncounterBoosts,
  applyNodeOption,
  attachBossSeeker,
  EXPEDITION_SHOP_SKIP_OPTION_ID,
  findExpeditionNode,
  generateZoneMap,
  nextNodeIds,
  opponentForNode,
  opponentRosterForEncounter,
  prepareExpeditionRoster,
  prepareExpeditionZoneRoster,
  publicBossSeeker,
  validateChapterManifest,
} from "../backend/supabase/functions/_shared/expedition.mjs";
import { imageInputForModel } from "./run.mjs";

const SIZE = DEFAULTS.workSize; // 1024, jadi tidak ada resize yang mengaburkan assert
const HALF = SIZE / 2;
const PAD = DEFAULTS.framePadding;

const GREEN = [0, 255, 0];
const DARK_OUTLINE = [24, 31, 42];
const OUTLINE_PX = 3;
const KEYLINE_PX = 3;
const FILLS = {
  idle: [220, 40, 40],
  attack: [40, 80, 230],
  sleep: [150, 60, 200],
  defeated: [240, 150, 30],
  happy: [230, 180, 40],
  hungry: [180, 90, 40],
  dirty: [90, 140, 70],
  fx_strike: [255, 220, 80],
  fx_surge: [80, 200, 255],
};

function setPx(bitmap, x, y, [r, g, b], a = 255) {
  const o = (y * SIZE + x) * 4;
  bitmap[o] = r;
  bitmap[o + 1] = g;
  bitmap[o + 2] = b;
  bitmap[o + 3] = a;
}

/** Blob realistis: badan -> dark line art 3px -> matte putih 3px. */
function drawBlob(bitmap, x, y, w, h, fill) {
  const edge = OUTLINE_PX + KEYLINE_PX;
  for (let yy = y - edge; yy < y + h + edge; yy++) {
    for (let xx = x - edge; xx < x + w + edge; xx++) {
      if (xx < 0 || yy < 0 || xx >= SIZE || yy >= SIZE) continue;
      const inside = xx >= x && xx < x + w && yy >= y && yy < y + h;
      const inOutline =
        xx >= x - OUTLINE_PX &&
        xx < x + w + OUTLINE_PX &&
        yy >= y - OUTLINE_PX &&
        yy < y + h + OUTLINE_PX;
      setPx(bitmap, xx, yy, inside ? fill : inOutline ? DARK_OUTLINE : [255, 255, 255]);
    }
  }
}

async function buildSheet(blobs, layout = { grid: 2, quadrant: POSE_QUADRANT }) {
  const img = new Image(SIZE, SIZE);
  for (let i = 0; i < SIZE * SIZE; i++) {
    const o = i * 4;
    img.bitmap[o] = GREEN[0];
    img.bitmap[o + 1] = GREEN[1];
    img.bitmap[o + 2] = GREEN[2];
    img.bitmap[o + 3] = 255;
  }
  const cell = Math.floor(SIZE / layout.grid);
  for (const [pose, spec] of Object.entries(blobs)) {
    const [col, row] = layout.quadrant[pose];
    drawBlob(img.bitmap, col * cell + spec.x, row * cell + spec.y, spec.w, spec.h, FILLS[pose]);
  }
  return await img.encode();
}

// Matte putih dibuang; bbox nyata menyisakan dark outline 3px di tiap sisi.
const outer = (spec) => ({ w: spec.w + 6, h: spec.h + 6 });

// ---------------------------------------------------------------------------

console.log("1. isKeyColor memisahkan background dari warna sah");
{
  assert.ok(isKeyColor(0, 255, 0), "hijau murni #00FF00 harus jadi kunci");
  assert.ok(isKeyColor(2, 253, 5), "hijau hasil kompresi model tetap kunci");
  assert.ok(isKeyColor(0, 200, 0), "hijau murni agak gelap tetap kunci");
  assert.ok(!isKeyColor(255, 255, 255), "putih bukan kunci, ini warna keyline");
  assert.ok(!isKeyColor(0, 0, 0), "hitam bukan kunci, ini line art");
  assert.ok(!isKeyColor(120, 140, 125), "abu kehijauan bukan kunci (sat rendah)");
  assert.ok(!isKeyColor(0, 255, 255), "cyan bukan kunci");
  assert.ok(!isKeyColor(255, 255, 0), "kuning bukan kunci");
  assert.ok(!isCatalogKeyVapor(60, 160, 70), "hijau daun bukan uap katalog");
  assert.ok(isCatalogKeyVapor(47, 242, 41), "steam neon sat 0,83 adalah uap katalog");
  assert.ok(isCatalogKeyVapor(121, 238, 98), "steam campur putih tetap uap katalog");
  assert.ok(isCatalogKeyVapor(177, 231, 3), "percikan chartreuse skewer adalah uap katalog");
}

console.log("2. REGRESI: tubuh Anima hijau tidak boleh ikut terhapus");
{
  // Ini kegagalan yang paling mungkin merusak game tanpa terlihat di sheet uji
  // biasa: Anima berelemen plant (tanaman, buah, daun) berwarna hijau, dan
  // resep chroma key standar dengan satMin 0,3 akan melubangi tubuhnya.
  const greensYangHarusSelamat = [
    [60, 160, 70, "hijau daun"],
    [34, 139, 34, "forest green"],
    [110, 190, 120, "hijau pupus"],
    [30, 90, 40, "hijau gelap bayangan"],
    [150, 200, 120, "hijau kekuningan"],
    [90, 140, 95, "hijau redup"],
  ];
  for (const [r, g, b, nama] of greensYangHarusSelamat) {
    assert.ok(!isKeyColor(r, g, b), `${nama} rgb(${r},${g},${b}) tidak boleh terhapus`);
  }
}

console.log("2b. keyline putih dikupas, tubuh putih selamat, dan rollback tersedia");
{
  const spec = { x: 120, y: 120, w: 120, h: 160 };
  const img = new Image(SIZE, SIZE);
  for (let i = 0; i < SIZE * SIZE; i++) {
    const o = i * 4;
    img.bitmap[o] = GREEN[0];
    img.bitmap[o + 1] = GREEN[1];
    img.bitmap[o + 2] = GREEN[2];
    img.bitmap[o + 3] = 255;
  }
  drawBlob(img.bitmap, spec.x, spec.y, spec.w, spec.h, [245, 245, 245]);
  const source = await img.encode();

  const stripped = await postprocessSheet(source, {});
  assert.ok(stripped.manifest.qa.white_keyline_pixels_stripped > 0, "matte putih harus terdeteksi");
  const strippedOut = await Image.decode(stripped.png);
  const [sx, sy, sw, sh] = stripped.manifest.poses.idle.region;
  const strippedBox = findBBox(strippedOut.bitmap, strippedOut.width, [sx, sy, sw, sh]);
  assert.equal(strippedBox.w, spec.w + OUTLINE_PX * 2, "yang tersisa badan + dark outline");
  assert.equal(strippedBox.h, spec.h + OUTLINE_PX * 2, "tinggi dark outline tetap utuh");
  let whiteBodyPixels = 0;
  for (let i = 0; i < strippedOut.bitmap.length; i += 4) {
    if (
      strippedOut.bitmap[i + 3] > DEFAULTS.alphaThreshold &&
      strippedOut.bitmap[i] >= 240 &&
      strippedOut.bitmap[i + 1] >= 240 &&
      strippedOut.bitmap[i + 2] >= 240
    ) {
      whiteBodyPixels++;
    }
  }
  assert.ok(whiteBodyPixels >= spec.w * spec.h, "badan putih di balik dark outline tidak boleh bolong");

  const kept = await postprocessSheet(source, {}, { ...DEFAULTS, stripWhiteKeyline: false });
  assert.equal(kept.manifest.qa.white_keyline_pixels_stripped, 0, "flag false harus menjadi rollback");
  const keptOut = await Image.decode(kept.png);
  const [kx, ky, kw, kh] = kept.manifest.poses.idle.region;
  const keptBox = findBBox(keptOut.bitmap, keptOut.width, [kx, ky, kw, kh]);
  assert.equal(
    keptBox.w,
    spec.w + (OUTLINE_PX + KEYLINE_PX) * 2,
    "rollback mempertahankan keyline lama"
  );

  const migrated = await stripWhiteKeylineFromRgba(kept.png);
  assert.ok(migrated.pixelsStripped > 0, "sheet RGBA lama harus bisa direproses tanpa raw hijau");
  assert.deepEqual(migrated.size, [keptOut.width, keptOut.height], "migrasi tidak mengubah grid manifest");
  const migratedOut = await Image.decode(migrated.png);
  const migratedBox = findBBox(migratedOut.bitmap, migratedOut.width, [kx, ky, kw, kh]);
  assert.equal(migratedBox.w, spec.w + OUTLINE_PX * 2, "migrasi RGBA menyisakan dark outline");
}

console.log("3. findBBox menemukan kotak rapat");
{
  const w = 20;
  const bm = new Uint8Array(w * 10 * 4);
  const put = (x, y) => (bm[(y * w + x) * 4 + 3] = 255);
  put(5, 3);
  put(8, 6);
  const bb = findBBox(bm, w, [0, 0, w, 10]);
  assert.deepEqual(bb, { x: 5, y: 3, w: 4, h: 4 });
  assert.equal(findBBox(bm, w, [12, 0, 8, 10]), null, "wilayah kosong harus null");
}

console.log("4. sheet lengkap 4 pose, blob off-center dan beda ukuran");
const blobs = {
  // Sengaja menempel dekat tepi kuadran: pembagian grid buta akan memotongnya.
  idle: { x: 8, y: 40, w: 240, h: 380 },
  attack: { x: 190, y: 52, w: 300, h: 368 },
  sleep: { x: 40, y: 300, w: 340, h: 190 },
  defeated: { x: 150, y: 260, w: 280, h: 230 },
};
{
  const { png, manifest } = await postprocessSheet(await buildSheet(blobs), {
    speciesKey: "selftest_synthetic_blob",
    colorBucket: "multicolor",
    promptVersion: "selftest",
    sheetName: "selftest.png",
  });

  assert.equal(manifest.qa.cells_detected, 4, "keempat sel harus terdeteksi");
  assert.deepEqual(manifest.qa.cells_rejected, {}, "tidak boleh ada sel ditolak");
  assert.equal(manifest.qa.green_residue_ratio, 0, "tidak boleh ada hijau tersisa");
  assert.deepEqual(manifest.qa.warnings, [], "sheet bersih tidak boleh memberi peringatan");

  // frame_size = bbox terbesar + padding di dua sisi
  const maxW = Math.max(...POSES.map((p) => outer(blobs[p]).w));
  const maxH = Math.max(...POSES.map((p) => outer(blobs[p]).h));
  assert.deepEqual(manifest.frame_size, [maxW + PAD * 2, maxH + PAD * 2]);
  assert.deepEqual(manifest.sheet_size, [(maxW + PAD * 2) * 2, (maxH + PAD * 2) * 2]);

  const [fw, fh] = manifest.frame_size;

  // Inilah properti yang mencegah sprite tersentak: keempat region identik ukuran
  for (const pose of POSES) {
    const [, , w, h] = manifest.poses[pose].region;
    assert.equal(w, fw, `lebar region ${pose} harus seragam`);
    assert.equal(h, fh, `tinggi region ${pose} harus seragam`);
  }

  // Region menempati kuadran yang benar di sheet keluaran
  for (const pose of POSES) {
    const [col, row] = POSE_QUADRANT[pose];
    assert.deepEqual(manifest.poses[pose].region, [col * fw, row * fh, fw, fh], `region ${pose} salah`);
  }

  // Isi tiap region: tidak terpotong, rata bawah, rata tengah horizontal
  const out = await Image.decode(png);
  for (const pose of POSES) {
    const [rx, ry] = manifest.poses[pose].region;
    const bb = findBBox(out.bitmap, out.width, [rx, ry, fw, fh]);
    const want = outer(blobs[pose]);

    assert.equal(bb.w, want.w, `${pose}: lebar isi berubah, kemungkinan terpotong`);
    assert.equal(bb.h, want.h, `${pose}: tinggi isi berubah, kemungkinan terpotong`);

    const bottomGap = ry + fh - (bb.y + bb.h);
    assert.equal(bottomGap, PAD, `${pose}: tidak rata bawah, garis tanah bergeser`);

    const leftGap = bb.x - rx;
    assert.equal(leftGap, Math.floor((fw - want.w) / 2), `${pose}: tidak rata tengah horizontal`);
  }

  // Semua pose punya jangkar identik: bottom-center frame. Ini yang bikin
  // AnimatedSprite2D dengan satu offset tetap sinkron di keempat pose.
  const anchors = POSES.map((pose) => {
    const [rx, ry] = manifest.poses[pose].region;
    const bb = findBBox(out.bitmap, out.width, [rx, ry, fw, fh]);
    return [Math.round(bb.x + bb.w / 2 - rx), bb.y + bb.h - ry];
  });
  for (const a of anchors) assert.deepEqual(a, anchors[0], "jangkar antar pose harus sama");
}

console.log("4b. anggota tubuh yang melewati garis tengah tidak terpotong");
{
  // Reproduksi bug sheet sungguhan: pose Attack di kanan mengulurkan tangan
  // 51px ke kuadran kiri. Crop 512x512 lama membuang tangan itu. Komponen tubuh
  // masih tersambung dan mayoritas berada di kanan, jadi seluruhnya harus tetap
  // dimiliki Attack.
  const crossing = {
    ...blobs,
    attack: { x: -48, y: 52, w: 300, h: 368 },
  };
  const { png, manifest } = await postprocessSheet(await buildSheet(crossing), {});
  assert.equal(manifest.qa.cells_detected, 4);
  assert.ok(
    manifest.qa.pose_ownership.attack.cross_boundary_pixels > 0,
    "test harus benar-benar punya piksel Attack di kuadran kiri"
  );

  const out = await Image.decode(png);
  const [fw, fh] = manifest.frame_size;
  const [rx, ry] = manifest.poses.attack.region;
  const bb = findBBox(out.bitmap, out.width, [rx, ry, fw, fh]);
  assert.equal(bb.w, outer(crossing.attack).w, "tangan melewati seam tidak boleh mengurangi lebar");
  assert.equal(bb.h, outer(crossing.attack).h, "tinggi Attack tidak boleh berubah");

  // Warna biru Attack tidak boleh bocor ke frame Idle walaupun sumbernya masuk
  // kuadran kiri; inilah alasan blit memakai ownership mask, bukan bbox longgar.
  const [ix, iy] = manifest.poses.idle.region;
  let blueInIdle = 0;
  for (let y = iy; y < iy + fh; y++) {
    for (let x = ix; x < ix + fw; x++) {
      const i = (y * out.width + x) * 4;
      if (out.bitmap[i] === FILLS.attack[0] && out.bitmap[i + 1] === FILLS.attack[1]) {
        blueInIdle++;
      }
    }
  }
  assert.equal(blueInIdle, 0, "piksel pose tetangga tidak boleh ikut tercopy");
}

console.log("4c. pose lebar dengan efek TIDAK dianggap keying gagal, blok padat IYA");
{
  // Bug nyata dari Smoke Set v2: pose Attack punya speed line dan percikan yang
  // terpisah dari tubuh, sehingga bbox gabungannya mengisi 96% kuadran padahal
  // hanya 42% isinya opak. Penjaga yang mengukur luas bbox terhadap kuadran
  // menolaknya sebagai "keying gagal" dan sheet kehilangan satu pose.
  const img = await Image.decode(await buildSheet(blobs));
  const AX = HALF; // kolom kanan, baris atas = kuadran Attack
  drawBlob(img.bitmap, AX + 2, 6, 14, 14, FILLS.attack); // percikan dekat seam
  drawBlob(img.bitmap, SIZE - 24, HALF - 30, 14, 14, FILLS.attack); // percikan sudut

  const { manifest } = await postprocessSheet(await img.encode(), {});
  const bb = { w: manifest.frame_size[0] - PAD * 2, h: manifest.frame_size[1] - PAD * 2 };
  assert.ok(
    (bb.w * bb.h) / (HALF * HALF) > DEFAULTS.maxCellFillRatio,
    `test harus benar-benar melewati ambang lama: ${(bb.w * bb.h) / (HALF * HALF)}`
  );
  assert.equal(manifest.qa.cells_detected, 4, "pose berpercikan tetap harus dihitung");
  assert.deepEqual(manifest.qa.cells_rejected, {}, "tidak ada yang boleh ditolak di sini");

  // Sisi lain dari penjaga yang sama harus tetap hidup: satu kuadran yang
  // seluruhnya opak berarti latarnya tidak ter-key, dan itu wajib ditolak.
  const solid = await Image.decode(await buildSheet({ idle: blobs.idle, attack: blobs.attack, sleep: blobs.sleep }));
  for (let y = HALF; y < SIZE; y++) {
    for (let x = HALF; x < SIZE; x++) setPx(solid.bitmap, x, y, [40, 44, 52]);
  }
  const blocked = await postprocessSheet(await solid.encode(), {});
  assert.equal(blocked.manifest.qa.cells_detected, 3, "blok padat tidak boleh dianggap sprite");
  assert.match(blocked.manifest.qa.cells_rejected.defeated ?? "", /padat|keying gagal/);
}

console.log("5. sel hilang terdeteksi, bukan diam-diam lolos");
{
  const partial = { ...blobs };
  delete partial.defeated;
  const { manifest } = await postprocessSheet(await buildSheet(partial), {});
  assert.equal(manifest.qa.cells_detected, 3);
  assert.equal(manifest.poses.defeated, undefined, "pose hilang tidak boleh dikarang");
  assert.ok(
    manifest.qa.warnings.some((w) => w.includes("3/4")),
    "harus ada peringatan sel hilang"
  );
}

console.log("6. label teks kecil tidak dianggap sprite");
{
  const withLabel = { ...blobs, defeated: { x: 180, y: 400, w: 90, h: 14 } };
  const { manifest } = await postprocessSheet(await buildSheet(withLabel), {});
  assert.equal(manifest.poses.defeated, undefined, "coretan tipis harus ditolak");
  assert.match(manifest.qa.cells_rejected.defeated ?? "", /kecil|ambang/);
}

console.log("7. model membesarkan pose Attack -> peringatan skala");
{
  const inflated = { ...blobs, attack: { x: 60, y: 20, w: 380, h: 470 } };
  const { manifest } = await postprocessSheet(await buildSheet(inflated), {});
  assert.ok(
    manifest.qa.warnings.some((w) => w.includes("Idle vs Attack")),
    `harus memperingatkan skala, dapat: ${JSON.stringify(manifest.qa.warnings)}`
  );
}

console.log("8. pose sleep pendek TIDAK dianggap masalah skala");
{
  // Ini regresi yang penting: pose meringkuk memang jauh lebih pendek daripada
  // pose berdiri, jadi metrik varians antar keempat pose akan memberi alarm
  // palsu terus-menerus. Yang diukur harus Idle vs Attack saja.
  const crouched = { ...blobs, sleep: { x: 40, y: 380, w: 330, h: 110 } };
  const { manifest } = await postprocessSheet(await buildSheet(crouched), {});
  assert.deepEqual(manifest.qa.warnings, [], "sleep pendek itu normal, jangan diperingatkan");
  assert.ok(manifest.qa.standing_height_variance <= 0.15);
}

console.log("9. sleep lebih tinggi dari idle -> curiga skala berubah");
{
  const wrong = { ...blobs, sleep: { x: 40, y: 30, w: 300, h: 460 } };
  const { manifest } = await postprocessSheet(await buildSheet(wrong), {});
  assert.ok(
    manifest.qa.warnings.some((w) => w.includes("sleep")),
    "sleep yang lebih tinggi dari idle harus dicurigai"
  );
}

console.log("10. background bukan hijau -> gagal keras, bukan sheet rusak");
{
  const img = new Image(SIZE, SIZE);
  for (let i = 0; i < SIZE * SIZE; i++) {
    const o = i * 4;
    img.bitmap[o] = 255;
    img.bitmap[o + 1] = 255;
    img.bitmap[o + 2] = 255;
    img.bitmap[o + 3] = 255;
  }
  const whitePng = await img.encode();
  await assert.rejects(
    () => postprocessSheet(whitePng, {}),
    /background bukan hijau/,
    "harus menolak dengan pesan yang menyebut penyebabnya"
  );
}

console.log("11. REGRESI end-to-end: Anima hijau tetap utuh di atas latar hijau");
{
  // Kasus nyata yang paling mudah lolos dari pengujian: foto tanaman jadi Anima
  // berelemen plant yang tubuhnya hijau, di atas background hijau. Kalau ambang
  // keying terlalu longgar, tubuhnya bolong dan bbox-nya mengecil.
  const leafy = { idle: [60, 160, 70], attack: [34, 139, 34], sleep: [110, 190, 120], defeated: [90, 140, 95] };
  const img = new Image(SIZE, SIZE);
  for (let i = 0; i < SIZE * SIZE; i++) {
    const o = i * 4;
    img.bitmap[o] = GREEN[0];
    img.bitmap[o + 1] = GREEN[1];
    img.bitmap[o + 2] = GREEN[2];
    img.bitmap[o + 3] = 255;
  }
  for (const [pose, spec] of Object.entries(blobs)) {
    const [col, row] = POSE_QUADRANT[pose];
    drawBlob(img.bitmap, col * HALF + spec.x, row * HALF + spec.y, spec.w, spec.h, leafy[pose]);
  }

  const { png, manifest } = await postprocessSheet(await img.encode(), {});
  assert.equal(manifest.qa.cells_detected, 4, "Anima hijau harus tetap terdeteksi keempatnya");
  assert.deepEqual(manifest.qa.warnings, [], "tubuh hijau bukan residu background");

  const out = await Image.decode(png);
  const [fw, fh] = manifest.frame_size;
  for (const pose of POSES) {
    const [rx, ry] = manifest.poses[pose].region;
    const bb = findBBox(out.bitmap, out.width, [rx, ry, fw, fh]);
    assert.equal(bb.w, outer(blobs[pose]).w, `${pose}: tubuh hijau terpotong`);
    assert.equal(bb.h, outer(blobs[pose]).h, `${pose}: tubuh hijau terpotong`);
  }
}

console.log("12. heightMetrics aman saat pose tidak lengkap");
{
  const m = heightMetrics({ idle: { h: 100 } });
  assert.equal(m.standingVariance, 0, "tanpa attack, varians tidak bisa dihitung");
  assert.deepEqual(m.tooTall, []);
}

console.log("13. halo hijau di cincin tepi dierosi, tubuh hijau yang sah tidak");
{
  // Dua sisi dari satu keputusan, jadi diuji berpasangan. Halo yang terukur di
  // sheet sungguhan adalah piksel CAMPURAN putih+hijau di cincin 1px: 99,7% dari
  // piksel kehijauan yang lolos keying menempel tepat di tepi transparan.
  // Melonggarkan ambang saturasi akan menghapusnya sekaligus melubangi Anima
  // plant, jadi yang dipakai adalah kedekatan ke transparan.

  // Menggambar blob dengan tepi anti-alias: satu cincin campuran di luar isi.
  function drawAntialiased(bitmap, x, y, w, h, fill, edge) {
    for (let yy = y - 1; yy < y + h + 1; yy++) {
      for (let xx = x - 1; xx < x + w + 1; xx++) {
        if (xx < 0 || yy < 0 || xx >= SIZE || yy >= SIZE) continue;
        const inside = xx >= x && xx < x + w && yy >= y && yy < y + h;
        setPx(bitmap, xx, yy, inside ? fill : edge);
      }
    }
  }

  async function sheetWith(fill, edge) {
    const img = new Image(SIZE, SIZE);
    for (let i = 0; i < SIZE * SIZE; i++) {
      const o = i * 4;
      img.bitmap[o] = GREEN[0];
      img.bitmap[o + 1] = GREEN[1];
      img.bitmap[o + 2] = GREEN[2];
      img.bitmap[o + 3] = 255;
    }
    for (const [pose, spec] of Object.entries(blobs)) {
      const [col, row] = POSE_QUADRANT[pose];
      drawAntialiased(img.bitmap, col * HALF + spec.x, row * HALF + spec.y, spec.w, spec.h, fill, edge);
    }
    return await postprocessSheet(await img.encode(), {});
  }

  // (a) Halo: badan gelap, cincin tepi campuran putih+hijau seperti rgb(128,255,128)
  // yang saturasinya 0,5 sehingga lolos keying utama.
  const halo = await sheetWith([40, 40, 48], [128, 255, 128]);
  assert.equal(halo.manifest.qa.green_residue_ratio, 0, "cincin campuran harus hilang, bukan jadi halo");
  assert.deepEqual(halo.manifest.qa.warnings, [], "tanpa halo, tidak ada peringatan residu");

  const haloOut = await Image.decode(halo.png);
  const [hw, hh] = halo.manifest.frame_size;
  for (const pose of POSES) {
    const [rx, ry] = halo.manifest.poses[pose].region;
    const bb = findBBox(haloOut.bitmap, haloOut.width, [rx, ry, hw, hh]);
    // Cincin ikut terbuang, jadi yang tersisa persis ukuran isi blob.
    assert.equal(bb.w, blobs[pose].w, `${pose}: bbox harus menyusut ke isi, bukan menyertakan halo`);
    assert.equal(bb.h, blobs[pose].h, `${pose}: bbox harus menyusut ke isi, bukan menyertakan halo`);
  }

  // (b) Hijau daun yang didokumentasikan HARUS utuh, bahkan tanpa keyline putih
  // yang melindunginya. Saturasi rgb(60,160,70) adalah 0,63, jauh di bawah
  // satMin 0,8 pada RESIDUE_OPTS, jadi erosi tidak boleh menyentuhnya sama sekali.
  const leaf = await sheetWith([60, 160, 70], [60, 160, 70]);
  const leafOut = await Image.decode(leaf.png);
  const [lw, lh] = leaf.manifest.frame_size;
  for (const pose of POSES) {
    const [rx, ry] = leaf.manifest.poses[pose].region;
    const bb = findBBox(leafOut.bitmap, leafOut.width, [rx, ry, lw, lh]);
    assert.equal(bb.w, blobs[pose].w + 2, `${pose}: tubuh hijau daun tidak boleh terkikis`);
    assert.equal(bb.h, blobs[pose].h + 2, `${pose}: tubuh hijau daun tidak boleh terkikis`);
  }

  // (c) Batas jujur dari pendekatan ini: tubuh hijau yang SANGAT terang (g >= 220)
  // ikut terkikis 1px di tepi, karena pada channel hijau ia tidak bisa dibedakan
  // dari campuran background. Pitanya sempit dan disengaja; yang wajib dijamin
  // adalah erosinya berhenti setelah satu piksel, bukan menggerus terus.
  const vivid = [80, 240, 80]; // saturasi 0,67 jadi lolos keying, tapi g=240
  const vividSheet = await sheetWith(vivid, vivid);
  const vividOut = await Image.decode(vividSheet.png);
  const [vw, vh] = vividSheet.manifest.frame_size;
  for (const pose of POSES) {
    const [rx, ry] = vividSheet.manifest.poses[pose].region;
    const bb = findBBox(vividOut.bitmap, vividOut.width, [rx, ry, vw, vh]);
    assert.equal(bb.w, blobs[pose].w, `${pose}: erosi hijau pekat harus berhenti di 1px`);
    assert.equal(bb.h, blobs[pose].h, `${pose}: erosi hijau pekat harus berhenti di 1px`);
  }
}

console.log("14. validateVision menegakkan yang tidak bisa dijamin schema");
{
  const base = () => ({
    safe: true,
    is_object: true,
    species_key: "mug_ceramic_handled",
    color_bucket: "neutral_light",
    element: "flow",
    rarity: 1,
    stats: { hp: 50, atk: 30, def: 60, spd: 40, special: 35 },
    creature_brief: "x",
    signature_features: ["gagang jadi lengan", "bibir keramik di kepala"],
    surface_finish: "smooth glazed ceramic",
    damage_hints: ["retak glasir pendek", "satu sisi bibir terkelupas"],
    character_direction: "soft, friendly, and visually neutral",
    suggested_name: "Mugra",
  });

  // Gate tertutup: tidak ada gunanya memeriksa sisa isi
  const rejected = validateVision({ safe: false, is_object: true, reject_reason: "human_face" });
  assert.equal(rejected.gate, "rejected");
  assert.equal(rejected.reason, "human_face");

  const clean = validateVision(base(), [], true);
  assert.equal(clean.gate, "passed");
  assert.deepEqual(clean.issues, [], `sample bersih tidak boleh punya isu: ${clean.issues}`);

  const legacy = base();
  delete legacy.surface_finish;
  delete legacy.damage_hints;
  assert.deepEqual(validateVision(legacy, []).issues, [], "payload v1-v3 tetap sah tanpa field v4");

  // Jumlah stat di luar 200-350 diskalakan, bukan ditolak
  const weak = base();
  weak.stats = { hp: 10, atk: 10, def: 10, spd: 10, special: 10 };
  const scaled = validateVision(weak, [], true);
  const sum = Object.values(scaled.vision.stats).reduce((a, b) => a + b, 0);
  assert.ok(sum >= 195 && sum <= 210, `jumlah stat harus diskalakan ke ~200, dapat ${sum}`);
  assert.ok(scaled.issues.some((i) => i.includes("diskalakan")));

  // Typo species_key dinormalisasi ke kunci yang sudah ada. Tanpa ini, satu
  // huruf beda berarti cache miss dan satu generation dibayar dua kali.
  const typo = base();
  typo.species_key = "mug_ceramic_handles";
  const fixed = validateVision(typo, ["mug_ceramic_handled"], true);
  assert.equal(fixed.vision.species_key, "mug_ceramic_handled", "typo harus dinormalisasi");

  // Tapi spesies yang benar-benar beda jangan digabung
  const other = base();
  other.species_key = "shoe_fabric_sneaker";
  const kept = validateVision(other, ["mug_ceramic_handled"], true);
  assert.equal(kept.vision.species_key, "shoe_fabric_sneaker", "spesies beda jangan digabung");

  const badKey = base();
  badKey.species_key = "Mug Ceramic";
  assert.ok(validateVision(badKey, [], true).issues.some((i) => i.includes("format")));

  const vagueFeat = base();
  vagueFeat.signature_features = ["interesting texture", "unique qualities"];
  assert.equal(validateVision(vagueFeat, [], true).issues.filter((i) => i.includes("kabur")).length, 2);

  const franchiseSuffix = base();
  franchiseSuffix.suggested_name = "Mugmon";
  const renamed = validateVision(franchiseSuffix, [], true);
  assert.equal(renamed.vision.suggested_name, "Mugra", "nama generated tidak boleh berakhiran -mon");
  assert.ok(renamed.issues.some((i) => i.includes("dinormalisasi")));
  assert.equal(normalizeSuggestedName("Sporelet"), "Sporelet", "nama yang sudah aman tidak boleh berubah");
}

console.log("15. assemblePrompt tidak pernah mengirim placeholder ke model");
{
  const filled = assemblePrompt(
    "A {{creature_brief}} B\n{{signature_features_as_bullets}}\n" +
      "{{object_name}}\n{{color_palette}}\n{{personality}}",
    {
      creature_brief: "tubuh kotak",
      signature_features: ["tombol jadi mata", "kabel jadi ekor"],
      object_label: "computer mouse",
      dominant_colors: ["#111111", "#444444"],
      stats: { hp: 40, atk: 35, def: 45, spd: 65, special: 80 },
    }
  );
  assert.ok(filled.includes("A tubuh kotak B"));
  assert.ok(filled.includes("- tombol jadi mata\n- kabel jadi ekor"));
  assert.ok(filled.includes("computer mouse"));
  assert.ok(filled.includes("#111111, #444444"));
  assert.ok(filled.includes("clever, strange, mischievous"), "personality harus mengikuti stat tertinggi");
  assert.ok(!filled.includes("{{"));

  // Placeholder yang lupa diisi harus gagal keras: mengirimnya ke model berarti
  // membayar ~$0.07 untuk gambar yang isinya instruksi mentah.
  assert.throws(
    () => assemblePrompt("{{creature_brief}} {{stage_name}}", { creature_brief: "x", signature_features: [] }),
    /stage_name/
  );
}

console.log("16. extractJson menggantikan jaminan response_schema yang tidak ada");
{
  // Wrapper Gemini di Replicate tidak punya parameter response_schema, jadi
  // JSON valid tidak lagi dijamin API. Semua bentuk keluaran yang wajar harus
  // bisa diurai di sini, kalau tidak satu kalimat pengantar dari model membuat
  // seluruh foto gagal setelah biayanya sudah terbayar.
  const want = { safe: true, species_key: "mug_ceramic_handled" };

  assert.deepEqual(extractJson(JSON.stringify(want)), want, "JSON polos");

  // Output wrapper datang sebagai array potongan string yang harus disambung
  assert.deepEqual(extractJson(['{"safe": true, ', '"species_key": "mug_ceramic_handled"}']), want, "array potongan");

  assert.deepEqual(
    extractJson("```json\n" + JSON.stringify(want) + "\n```"),
    want,
    "dibungkus fence markdown"
  );
  assert.deepEqual(extractJson("```\n" + JSON.stringify(want) + "\n```"), want, "fence tanpa label");

  assert.deepEqual(
    extractJson(`Here is the analysis:\n${JSON.stringify(want)}\nHope this helps!`),
    want,
    "diapit kalimat pengantar dan penutup"
  );

  // Nested object tidak boleh terpotong oleh pencarian kurawal terakhir
  const nested = { safe: true, stats: { hp: 50, atk: 30 } };
  assert.deepEqual(extractJson(`blah ${JSON.stringify(nested)} blah`), nested, "object bersarang");

  for (const bad of ["", "   ", "maaf, saya tidak bisa membantu", "{ ini bukan json }", null]) {
    assert.throws(() => extractJson(bad), /tidak mengembalikan JSON/, `harus menolak: ${JSON.stringify(bad)}`);
  }
}

console.log("17. bundel prompt Edge Function cocok dengan file sumbernya");
{
  // Edge Function memakai prompts.generated.ts, eval memakai backend/prompts/
  // langsung. Kalau keduanya menyimpang, art produksi berbeda dari art yang
  // sudah kita setujui di Smoke Set dan tidak ada yang memberi tahu. Ini
  // pemeriksaan gratis yang menggantikan disiplin mengingat.
  const { buildBundle, renderModule } = await import("../backend/tools/bundle_prompts.mjs");
  const { readFile } = await import("node:fs/promises");
  const jalur = new URL("../backend/supabase/functions/_shared/prompts.generated.ts", import.meta.url);

  const seharusnya = renderModule(await buildBundle());
  const sekarang = await readFile(jalur, "utf8");
  assert.equal(
    sekarang,
    seharusnya,
    "prompts.generated.ts basi, jalankan: node backend/tools/bundle_prompts.mjs"
  );

  // Bundel yang mutakhir tapi kosong tetap lolos perbandingan di atas.
  const bundel = await buildBundle();
  assert.ok(bundel.v3?.sprite_sheet.includes("{{creature_brief}}"), "v3 sprite_sheet ikut terbundel");
  assert.ok(bundel.v3?.vision_schema?.properties?.species_key, "v3 vision_schema terparse");
  assert.ok(bundel.v4?.vision_schema?.properties?.surface_finish, "v4 surface_finish ikut terbundel");
  assert.ok(bundel.v4?.vision_schema?.properties?.damage_hints, "v4 damage_hints ikut terbundel");
  assert.ok(bundel.v5?.vision_schema?.properties?.character_direction, "v5 character_direction ikut terbundel");
  assert.ok(bundel.v7?.vision_schema?.properties?.strike_name, "v7 strike_name ikut terbundel");
  assert.ok(bundel.v7?.sprite_sheet.includes("3x3"), "v7 sprite_sheet 3x3 ikut terbundel");
  assert.ok(
    bundel.v8?.sprite_sheet.includes("Left-column cells (Idle, Happy, Damaged)"),
    "v8 facing lock kolom kiri ikut terbundel"
  );
  assert.ok(
    bundel.v9?.sprite_sheet.includes("NEGATIVE SPACE — MUST REMAIN BACKGROUND"),
    "v9 negative-space lock ikut terbundel"
  );
  assert.ok(
    bundel.v10?.sprite_sheet.includes("WHITE IS NOT A GENERIC ACCENT"),
    "v10 white-accent lock ikut terbundel"
  );
  assert.ok(
    bundel.v11?.sprite_sheet.includes("EDGES — DARK CONTOUR DIRECTLY AGAINST GREEN"),
    "v11 borderless dark-contour lock ikut terbundel"
  );
  assert.ok(
    bundel.v12?.sprite_sheet.includes("VFX DIVERSITY CONTRACT"),
    "v12 VFX diversity + safe-envelope lock ikut terbundel"
  );
  assert.ok(
    bundel.v13?.vision_schema?.properties?.subject_kind,
    "v13 subject_kind ikut terbundel"
  );
  assert.ok(
    bundel.v13?.vision_schema?.properties?.secondary_element,
    "v13 secondary_element ikut terbundel"
  );
  assert.ok(
    bundel.v13?.sprite_sheet_fauna?.includes("Show **fatigue and"),
    "v13 sprite_sheet_fauna ikut terbundel"
  );
  assert.ok(
    bundel.v14?.sprite_sheet_fauna?.includes("SCANIMA MONSTERIZATION FLOOR"),
    "v14 monsterization floor fauna ikut terbundel"
  );
  assert.equal(bundel.v14?.sprite_sheet, bundel.v13?.sprite_sheet, "v14 tidak mengubah prompt object");
  assert.ok(
    bundel.v15?.sprite_sheet_fauna?.includes("MANDATORY MONSTER IDENTITY LAYER"),
    "v15 monster identity layer fauna ikut terbundel"
  );
  assert.equal(bundel.v15?.sprite_sheet, bundel.v13?.sprite_sheet, "v15 tidak mengubah prompt object");
  for (const prompt of [
    bundel.v16?.sprite_sheet,
    bundel.v16?.sprite_sheet_fauna,
    bundel.v16?.sprite_sheet_evolve,
  ]) {
    assert.ok(prompt?.includes("EYE GAZE LOCK"), "v16 gaze lock ikut terbundel di semua jalur");
    assert.ok(prompt?.includes("ONE shared target in open"));
    assert.match(prompt, /Never look\s+at the viewer/);
    assert.ok(prompt?.includes("Sleep keeps every eye fully closed"));
  }
  assert.equal(bundel.v19?.sprite_sheet, bundel.v18?.sprite_sheet, "v19 tidak mengubah prompt object");
  assert.equal(bundel.v19?.sprite_sheet_fauna, bundel.v18?.sprite_sheet_fauna, "v19 tidak mengubah prompt fauna");
  assert.ok(
    bundel.v19?.vision_system.includes("hug-and-carry doll"),
    "v19 memakai floor boneka gendong untuk benda genggam kecil"
  );
}

console.log("18. resize foto di device tidak melampaui apa yang diuji Smoke Set");
{
  // scan_flow.gd mengecilkan foto kamera sebelum diunggah. Kalau angkanya naik
  // di atas foto terbesar di eval/photos/, produksi memberi Vision gambar yang
  // belum pernah diuji — dan yang bisa bergeser bukan cuma stat: species_key
  // yang berubah memecah dedup cache, sehingga scan yang seharusnya gratis
  // membayar $0.07. Konstanta di GDScript dan foto uji di Node tidak punya
  // tempat lain untuk bertemu selain di sini.
  const { readFile, readdir } = await import("node:fs/promises");
  const gd = await readFile(new URL("../game/scripts/scan_flow.gd", import.meta.url), "utf8");
  const cocok = gd.match(/const FOTO_MAX_PX\s*:?=\s*(\d+)/);
  assert.ok(cocok, "FOTO_MAX_PX tidak ditemukan di scan_flow.gd");
  const maxPx = Number(cocok[1]);

  const dir = new URL("./photos/", import.meta.url);
  const fotos = (await readdir(dir)).filter((f) => /\.(jpe?g|png)$/i.test(f));
  assert.ok(fotos.length > 0, "eval/photos/ kosong, tidak ada yang bisa dibandingkan");

  let terbesar = 0;
  for (const f of fotos) {
    const img = await Image.decode(await readFile(new URL(f, dir)));
    terbesar = Math.max(terbesar, img.width, img.height);
  }
  assert.ok(
    maxPx <= terbesar,
    `FOTO_MAX_PX=${maxPx} melampaui foto eval terbesar (${terbesar} px). Turunkan ` +
      "konstantanya, atau jalankan ulang Smoke Set dengan foto seukuran itu dulu."
  );
}

console.log("19. tidak ada kredensial mahal di sumber client Godot");
{
  // Kriteria lama "verifikasi dengan strings pada APK" terukur TIDAK BISA GAGAL:
  // pack Godot terkompresi, jadi string kontrol yang jelas ada di backend.gd pun
  // memberi nol hit pada APK jadi. Uji yang selalu lulus lebih buruk daripada
  // tidak ada uji, sebab ia memberi rasa aman. Yang bisa gagal adalah memeriksa
  // sumbernya: apa pun yang tidak ada di game/ tidak mungkin ada di APK.
  //
  // Yang dijaga: REPLICATE_API_TOKEN (r8_) dan service role key tidak boleh
  // ikut ke build. KEY_PUBLISHABLE sengaja TIDAK dilarang — ia memang ikut, dan
  // yang membatasi akses adalah RLS, bukan kerahasiaannya.
  const { readFile, readdir } = await import("node:fs/promises");
  const terlarang = [
    [/r8_[A-Za-z0-9]{20}/, "token Replicate"],
    [/sbp_[A-Za-z0-9]{20}/, "PAT Supabase"],
    [/service_role/, "service role key"],
    [/sb_secret_/, "secret key Supabase"],
  ];

  // addons/ dan android/ dilewati: milik pihak ketiga dan artefak build.
  const akar = new URL("../game/", import.meta.url);
  const berkas = [];
  const jelajah = async (dir) => {
    for (const e of await readdir(dir, { withFileTypes: true })) {
      if (e.isDirectory()) {
        if (["addons", "android", ".godot"].includes(e.name)) continue;
        await jelajah(new URL(`${e.name}/`, dir));
      } else if (/\.(gd|tscn|cfg|gdshader|json)$/.test(e.name)) {
        berkas.push(new URL(e.name, dir));
      }
    }
  };
  await jelajah(akar);
  assert.ok(berkas.length > 5, `hanya ${berkas.length} berkas terpindai, penjelajahannya salah`);

  for (const f of berkas) {
    const isi = await readFile(f, "utf8");
    for (const [pola, nama] of terlarang) {
      assert.ok(
        !pola.test(isi),
        `${nama} ditemukan di ${f.pathname.split("/game/")[1]}. Kredensial ini tidak ` +
          "boleh ikut ke APK; ia hanya hidup di Edge Function secrets."
      );
    }
  }

  // care_anima menguasai transaksi Bits lewat service role. getClaims tetap
  // memverifikasi JWT, tetapi memakai JWKS cache alih-alih round-trip getUser
  // pada setiap tap. Pagar platform harus tetap hidup bersama optimasi ini.
  const care = await readFile(
    new URL("../backend/supabase/functions/care_anima/index.ts", import.meta.url),
    "utf8"
  );
  const authFlow = await readFile(new URL("../game/scripts/auth_flow.gd", import.meta.url), "utf8");
  const config = await readFile(new URL("../backend/supabase/config.toml", import.meta.url), "utf8");
  const careConfig = config.split("[functions.care_anima]")[1]?.split("\n[")[0] ?? "";
  assert.ok(
    config.includes('site_url = "scanima://auth/callback"'),
    "Site URL Auth mobile harus kembali ke aplikasi, bukan localhost"
  );
  assert.ok(
    config.includes('"scanima://auth/callback**"'),
    "allow-list OAuth harus menerima query state acak pada callback aplikasi"
  );
  assert.ok(
    !authFlow.includes("OAUTH_ALREADY_PENDING") &&
      authFlow.includes("GameState.cancel_oauth()"),
    "tap Sign in berikutnya harus mengganti intent OAuth yang browsernya tidak kembali"
  );
  assert.ok(
    authFlow.includes('auth_failed.emit("OAUTH_UPGRADE_PENDING")'),
    "link tidak boleh mengumumkan sukses kalau grant starter belum tersimpan"
  );
  assert.ok(care.includes('ACTIONS = new Set(["sync", "feed", "clean", "sleep", "wake", "play", "summon", "use_item"])'),
    "care_anima harus menerima summon dan use_item");
  assert.ok(!care.includes(".auth.getUser("), "care_anima tidak boleh mengembalikan round-trip getUser");
  assert.match(careConfig, /verify_jwt\s*=\s*true/, "gateway JWT care_anima harus tetap aktif");
  assert.ok(
    care.includes("syncProfileTimezone"),
    "care_anima harus menyimpan offset zona sebelum apply_care"
  );
}

console.log("20. prompt v4 tidak mengarang logo atau damage cyborg");
{
  const { readFile } = await import("node:fs/promises");
  const template = await readFile(new URL("../backend/prompts/v4/sprite_sheet.md", import.meta.url), "utf8");
  const stats = { hp: 50, atk: 40, def: 60, spd: 45, special: 55 };

  assert.ok(template.includes("Never invent a replacement mark"), "v4 wajib memilih permukaan polos");
  assert.ok(
    !template.includes("invented simple geometric marking of your own"),
    "instruksi v3 yang melahirkan logo semu tidak boleh kembali"
  );

  const mug = assemblePrompt(template, {
    object_label: "ceramic mug",
    creature_brief: "rounded mug creature with handle arm",
    signature_features: ["curved handle becomes one arm", "open rim crowns the head"],
    surface_finish: "smooth glazed ceramic",
    damage_hints: ["two short glaze cracks", "one chipped rim", "exposed wire bundle"],
    dominant_colors: ["#eeeeee"],
    stats,
  });
  assert.ok(mug.includes("- two short glaze cracks\n- one chipped rim"));
  assert.ok(!mug.includes("- exposed wire bundle"), "mug tanpa wire anchor tidak boleh mendapat damage kabel");

  const filteredMug = assemblePrompt(template, {
    object_label: "ceramic mug",
    creature_brief: "rounded mug creature with handle arm",
    signature_features: ["curved handle becomes one arm", "open rim crowns the head"],
    surface_finish: "smooth glazed ceramic",
    damage_hints: ["one short glaze crack", "exposed electronic component"],
    dominant_colors: ["#eeeeee"],
    stats,
  });
  assert.ok(!filteredMug.includes("- exposed electronic component"));
  assert.equal(
    filteredMug.match(/^- /gm)?.length,
    4,
    "dua signature feature + dua damage bullet harus tetap ada sesudah filter"
  );

  const plant = assemblePrompt(template, {
    object_label: "potted plant",
    creature_brief: "leafy creature growing from a round pot body",
    signature_features: ["five broad leaves form the crown", "clay pot becomes the torso"],
    surface_finish: "living waxy leaves and terracotta",
    damage_hints: ["one torn leaf edge", "one bruised leaf tip", "exposed circuit"],
    dominant_colors: ["#3f7f42", "#a35d35"],
    stats,
  });
  assert.ok(plant.includes("- one torn leaf edge\n- one bruised leaf tip"));
  assert.ok(!plant.includes("- exposed circuit"), "tanaman tidak boleh mendapat damage elektronik");

  const mouse = assemblePrompt(template, {
    object_label: "wired computer mouse",
    creature_brief: "low domed mouse-shell creature",
    signature_features: ["two click buttons become eyes", "USB cable becomes a segmented tail"],
    surface_finish: "smooth molded plastic and rubber",
    damage_hints: ["scuffed plastic shell", "slightly frayed cable sheath"],
    dominant_colors: ["#222222"],
    stats,
  });
  assert.ok(mouse.includes("- slightly frayed cable sheath"), "kabel nyata tetap boleh rusak seperti kabel");
  const keyboard = assemblePrompt(template, {
    object_label: "mechanical keyboard",
    creature_brief: "wide keyboard creature with keycap scales",
    signature_features: ["black keys become armored scales", "mechanical dial becomes one eye"],
    surface_finish: "matte molded plastic keycaps",
    damage_hints: ["one broken key at the corner", "scuffed plastic frame"],
    dominant_colors: ["#222222"],
    stats,
  });
  assert.ok(keyboard.includes("- one broken key at the corner"), "plural keys harus mengizinkan damage key");
  const specialMouse = assemblePrompt(template, {
    object_label: "wired computer mouse",
    creature_brief: "low domed mouse-shell creature",
    signature_features: ["two click buttons become eyes", "USB cable becomes a segmented tail"],
    surface_finish: "smooth molded plastic and rubber",
    damage_hints: ["scuffed plastic shell", "slightly frayed cable sheath"],
    dominant_colors: ["#222222"],
    stats: { hp: 30, atk: 30, def: 40, spd: 50, special: 90 },
  });
  assert.ok(specialMouse.includes("hidden functional energy"));
  assert.ok(!specialMouse.includes("hidden technical energy"));
  assert.ok(!mug.includes("{{") && !plant.includes("{{") && !mouse.includes("{{"));
}

console.log("21. prompt v5 mengikuti karakter dan body plan objek");
{
  const { readFile } = await import("node:fs/promises");
  const template = await readFile(new URL("../backend/prompts/v5/sprite_sheet.md", import.meta.url), "utf8");
  const evolve = await readFile(new URL("../backend/prompts/v5/sprite_sheet_evolve.md", import.meta.url), "utf8");
  const vision = await readFile(new URL("../backend/prompts/v5/vision_system.md", import.meta.url), "utf8");
  const createAnima = await readFile(
    new URL("../backend/supabase/functions/create_anima/index.ts", import.meta.url),
    "utf8"
  );

  assert.ok(
    /Zero arms,\s+zero\s+legs,\s+or neither is fully valid/.test(template),
    "v5 tidak boleh memaksakan tangan atau kaki"
  );
  assert.ok(
    /whether arms and legs exist,\s+and how many of each/.test(vision),
    "Vision harus membuat keputusan limb plan eksplisit"
  );
  assert.ok(
    /A limbless earlier form\s+stays\s+limbless/.test(evolve),
    "evolusi tidak boleh menumbuhkan anggota tubuh generik"
  );
  assert.ok(
    vision.includes("Never end the name") && vision.includes("with `mon`"),
    "Vision v5 harus melarang suffix -mon secara eksplisit"
  );
  assert.ok(!vision.includes("Mugmon"), "contoh nama v5 tidak boleh mengajari pola Digimon");
  assert.ok(
    createAnima.includes("normalizeSuggestedName(vision.suggested_name"),
    "resume generation lama juga harus menormalkan suggested_name sebelum disimpan"
  );

  const idle = template.split("TOP LEFT — IDLE")[1]?.split("TOP RIGHT — BATTLE")[0] ?? "";
  assert.ok(idle.includes("calm, open, non-angry"), "Idle v5 harus tenang dan tidak marah");
  assert.ok(idle.includes("Never use a fierce glare"), "Idle v5 harus melarang fierce glare secara eksplisit");

  const sample = {
    object_label: "rounded perfume bottle",
    creature_brief: "a floating bottle creature with no arms or legs",
    character_direction: "elegant, softly feminine, and composed",
    signature_features: ["rounded glass body remains the torso", "cap becomes a small crown"],
    surface_finish: "smooth translucent glass",
    damage_hints: ["one hairline crack", "one tiny chipped edge"],
    dominant_colors: ["#d9b7d8"],
    stats: { hp: 30, atk: 80, def: 35, spd: 50, special: 65 },
  };
  const filled = assemblePrompt(template, sample);
  assert.ok(filled.includes(sample.character_direction), "character_direction harus sampai ke prompt gambar");
  assert.ok(
    filled.includes("without looking angry at rest"),
    "personality ATK v5 tidak boleh membuat Idle marah"
  );
  assert.ok(
    !filled.includes("bold, fierce, confrontational"),
    "personality lama yang fierce tidak boleh bocor ke v5"
  );
  assert.ok(!filled.includes("{{"), "semua placeholder v5 harus terisi");

  const missingCharacter = { ...sample, safe: true, is_object: true, species_key: "bottle_glass_rounded" };
  delete missingCharacter.character_direction;
  assert.ok(
    validateVision(missingCharacter, [], true, true).issues.includes("character_direction kosong"),
    "validator v5 harus menandai character_direction yang hilang"
  );

  const neutralFallback = assemblePrompt(template, missingCharacter);
  assert.ok(
    neutralFallback.includes("visually neutral and object-led"),
    "fallback aman harus netral, bukan menebak gender"
  );
}

console.log("21b. prompt v6 mengunci arah hadap ke kiri di semua pose");
{
  const { readFile } = await import("node:fs/promises");
  const template = await readFile(new URL("../backend/prompts/v6/sprite_sheet.md", import.meta.url), "utf8");
  const evolve = await readFile(
    new URL("../backend/prompts/v6/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const visionV5 = await readFile(new URL("../backend/prompts/v5/vision_system.md", import.meta.url), "utf8");
  const visionV6 = await readFile(new URL("../backend/prompts/v6/vision_system.md", import.meta.url), "utf8");
  const schemaV5 = await readFile(new URL("../backend/prompts/v5/vision_schema.json", import.meta.url), "utf8");
  const schemaV6 = await readFile(new URL("../backend/prompts/v6/vision_schema.json", import.meta.url), "utf8");
  const createAnima = await readFile(
    new URL("../backend/supabase/functions/create_anima/index.ts", import.meta.url),
    "utf8"
  );
  const evalRunner = await readFile(new URL("./run.mjs", import.meta.url), "utf8");

  assert.equal(visionV6, visionV5, "v6 tidak boleh mengubah Vision atau species cache key");
  assert.equal(schemaV6, schemaV5, "v6 tidak boleh mengubah kontrak output Vision");
  for (const prompt of [template, evolve]) {
    assert.ok(prompt.includes("HORIZONTAL FACING LOCK — BATTLE CONTRACT"));
    assert.ok(prompt.includes("In EVERY cell"), "facing lock wajib berlaku ke empat pose");
    assert.ok(prompt.includes("canvas-left (the viewer's left)"), "arah wajib tidak ambigu");
    assert.ok(prompt.includes("Never mirror, flip, turn around"), "mirror per-cell wajib dilarang");
    assert.ok(prompt.includes("must attack toward canvas-left"), "vektor Attack wajib ke kiri");
    assert.ok(
      prompt.includes("client mirrors the complete sheet"),
      "prompt harus menjelaskan kontrak flip client"
    );
  }
  assert.ok(
    createAnima.includes("promptMajor(versiPrompt) >= 5"),
    "runtime production harus memvalidasi field presentation v6 seperti v5"
  );
  assert.ok(
    evalRunner.includes("promptMajor(args.promptVersion) >= 5"),
    "eval harus memvalidasi v6 dengan kontrak yang sama"
  );
}

console.log("22. adapter nano-banana-2-lite mengikuti schema dan harga Replicate");
{
  const input = imageInputForModel(
    "google/nano-banana-2-lite",
    "draw one sheet",
    "data:image/jpeg;base64,dGVzdA=="
  );
  assert.deepEqual(input, {
    prompt: "draw one sheet",
    image_input: ["data:image/jpeg;base64,dGVzdA=="],
    aspect_ratio: "1:1",
    output_format: "png",
  });
  assert.equal(biayaGambarUsd("google/nano-banana-2-lite"), 0.034);
}

console.log("23. battle server deterministik, idempoten, dan mengikuti ekonomi");
{
  const base = { hp: 50, atk: 50, def: 50, spd: 50, special: 50 };
  assert.deepEqual(toBattleStats(base), {
    max_hp: 220,
    atk: 50,
    def: 50,
    spd: 50,
    special: 50,
  });
  assert.equal(levelFromExp(0), 1);
  assert.equal(levelFromExp(4), 1);
  assert.equal(levelFromExp(5), 2);
  assert.equal(expToNextLevel(1), 5);
  assert.equal(expToNextLevel(5), 5);
  assert.equal(expToNextLevel(6), 10);
  assert.equal(expToNextLevel(39), 40);
  assert.equal(expToNextLevel(40), 0);
  assert.equal(expForLevel(16), 150);
  assert.equal(expForLevel(36), 700);
  assert.equal(expForLevel(40), EXP_MAX);
  assert.equal(levelFromExp(149), 15);
  assert.equal(levelFromExp(150), 16);
  assert.equal(levelFromExp(699), 35);
  assert.equal(levelFromExp(700), 36);
  assert.equal(levelFromExp(859), 39);
  assert.equal(levelFromExp(860), 40);
  assert.equal(levelFromExp(999), 40);
  assert.equal(battleExpYield(1, 1, "even"), 2);
  assert.equal(battleExpYield(1, 11, "even"), 5);
  assert.equal(battleExpYield(40, 40, "tough"), 6);
  assert.equal(battleExpYield(1, 40, "boss"), 8);
  assert.equal(formFromLevel(1), "hatchling");
  assert.equal(formFromLevel(16), "adult");
  assert.equal(formFromLevel(36), "evolved");
  assert.equal(growthMultiplier(1), 1);
  assert.equal(Number(growthMultiplier(16).toFixed(2)), 1.45);
  assert.ok(Math.abs(growthMultiplier(36) - 2.05) < 1e-9);
  assert.deepEqual(toBattleStats(base, 1, "", 16), {
    max_hp: 310,
    atk: 72,
    def: 72,
    spd: 72,
    special: 72,
  });
  assert.deepEqual(toBattleStats(base, 1, "", 36), {
    max_hp: 430,
    atk: 102,
    def: 102,
    spd: 102,
    special: 102,
  });
  for (const element of ELEMENT_ROSTER) {
    const strengths = ELEMENT_STRENGTHS[element];
    assert.equal(strengths?.length, 2, `${element} harus punya tepat 2 keunggulan`);
    for (const target of strengths) {
      assert.ok(ELEMENT_ROSTER.includes(target), `${element}→${target} harus ada di roster`);
      assert.equal(singleMatchup(element, target), MATCHUP_STRONG);
      assert.equal(elementMultiplier(element, target), MATCHUP_STRONG);
    }
    const weaknesses = ELEMENT_ROSTER.filter((other) => ELEMENT_STRENGTHS[other]?.includes(element));
    assert.equal(weaknesses.length, 2, `${element} harus punya tepat 2 kelemahan`);
    for (const source of weaknesses) {
      assert.equal(singleMatchup(element, source), MATCHUP_WEAK);
    }
  }
  for (const element of ELEMENT_ROSTER) {
    for (const target of ELEMENT_STRENGTHS[element]) {
      assert.notEqual(
        singleMatchup(target, element),
        MATCHUP_STRONG,
        `${element}↔${target} tidak boleh saling kuat`
      );
    }
  }
  for (let index = 0; index < ELEMENT_CYCLE.length; index++) {
    const attacker = ELEMENT_CYCLE[index];
    const strongAgainst = ELEMENT_CYCLE[(index + 1) % ELEMENT_CYCLE.length];
    assert.equal(singleMatchup(attacker, strongAgainst), MATCHUP_STRONG, `siklus lama ${attacker}→${strongAgainst}`);
  }
  assert.equal(singleMatchup("plant", "air"), MATCHUP_STRONG);
  assert.equal(singleMatchup("plant", "fauna"), MATCHUP_WEAK);
  assert.equal(dualDefenderMultiplier("plant", "fauna", "air"), MATCHUP_NEUTRAL, "kuat+lemah dual defender netral");
  assert.equal(dualDefenderMultiplier("metal", "plant", "wood"), MATCHUP_STRONG, "dua weakness tidak ditumpuk");
  assert.equal(dualDefenderMultiplier("metal", "stone", "spark"), MATCHUP_WEAK, "dua resist tidak ditumpuk");
  assert.equal(elementMultiplier("unknown", "metal"), MATCHUP_NEUTRAL);
  assert.equal(normalizeElement("water"), "flow");
  assert.equal(normalizeElement("fire"), "flame");
  assert.equal(critChance(1), 0.02);
  assert.equal(critChance(200), 0.25);

  const normalDamage = computeDamage({
    attack: 50,
    defense: 50,
    power: 50,
    variance: 1,
  });
  const surgeDamage = computeDamage({
    attack: 50,
    defense: 25,
    power: 75,
    variance: 1,
  });
  assert.equal(normalDamage, 33);
  assert.ok(surgeDamage > normalDamage, "Surge dengan DEF pierce harus lebih keras");
  assert.equal(
    computeDamage({ attack: 1, defense: 9999, power: 1, variance: 0.92 }),
    1,
    "DEF tinggi tidak boleh membuat damage nol"
  );
  assert.equal(
    computeDamage({ attack: 50, defense: 50, power: 50, variance: 1, guarding: true }),
    16,
    "Guard membelah damage masuk"
  );
  assert.ok(Math.ceil(220 / normalDamage) >= 6 && Math.ceil(220 / normalDamage) <= 10);

  const scaled = normalizeBaseStats({ hp: 30, atk: 40, def: 50, spd: 60, special: 70 }, 300);
  assert.ok(Math.abs(baseStatTotal(scaled) - 300) <= 3, "bot dinormalisasi dekat power pemain");

  const player = {
    species_key: "player",
    color_bucket: "blue",
    stage: 1,
    element: "metal",
    base_stats: { hp: 50, atk: 95, def: 50, spd: 95, special: 50 },
  };
  const bot = {
    species_key: "bot",
    color_bucket: "green",
    stage: 1,
    element: "plant",
    base_stats: { hp: 10, atk: 95, def: 10, spd: 10, special: 95 },
  };
  const initial = createBattleState({ player, bot, seed: "battle-selftest" });
  assert.equal(initial.player.level, 1);
  assert.equal(initial.player.max_hp, 220);

  const grown = createBattleState({
    player: { ...player, base_stats: base, level: 16 },
    bot: { ...bot, base_stats: base, level: 1 },
    seed: "level-growth",
  });
  assert.equal(grown.player.level, 16);
  assert.equal(grown.player.max_hp, 310);
  assert.equal(grown.player.atk, 72);
  assert.equal(grown.bot.max_hp, 220);
  assert.equal(hungerCombatMultiplier(40), 1);
  assert.equal(hungerCombatMultiplier(20), 0.8);
  assert.equal(hungerCombatMultiplier(0), 0.6);
  assert.equal(hygieneCombatMultiplier(50), 1);
  assert.equal(hygieneCombatMultiplier(0), 0.7);
  assert.equal(careCombatMultiplier(0, 0), 0.5);
  const hungry = createBattleState({
    player: { ...player, base_stats: base, hunger: 20 },
    bot: { ...bot, base_stats: base },
    seed: "hungry-penalty",
  });
  assert.equal(hungry.player.max_hp, 176);
  assert.equal(hungry.player.atk, 40);
  assert.equal(hungry.player.hp, 176);
  assert.equal(hungry.bot.max_hp, 220);
  const starving = createBattleState({
    player: { ...player, base_stats: base, hunger: 0 },
    bot: { ...bot, base_stats: base },
    seed: "starving-penalty",
  });
  assert.equal(starving.player.max_hp, 132);
  const dirty = createBattleState({
    player: { ...player, base_stats: base, hygiene: 0 },
    bot: { ...bot, base_stats: base },
    seed: "dirty-penalty",
  });
  assert.equal(dirty.player.max_hp, 154);
  const previewFed = battleRewardPreview(
    { base_stats: base, level: 1 },
    { base_stats: base, level: 1 },
    "hungry-bits",
  );
  const previewHungry = battleRewardPreview(
    { base_stats: base, level: 1, hunger: 0 },
    { base_stats: base, level: 1 },
    "hungry-bits",
  );
  assert.equal(previewHungry.bits, previewFed.bits, "lapar tidak boleh menaikkan Bits");

  const first = resolveTurn(initial, "strike", "turn-key");
  const retry = resolveTurn(initial, "strike", "turn-key");
  assert.deepEqual(retry, first, "retry key sama harus memberi event log identik");
  assert.equal(first.state.status, "won");
  const strikeHit = first.events.find((event) => event.type === "attack" && event.actor === "player");
  assert.equal(strikeHit?.attack_element, "metal");
  assert.deepEqual(strikeHit?.defense_elements, ["plant"]);
  assert.equal(strikeHit?.element_multiplier, MATCHUP_STRONG);
  assert.ok(
    !first.events.some((event) => event.type === "attack" && event.actor === "bot"),
    "aktor yang KO sebelum giliran tidak boleh menyerang"
  );

  const dualAttacker = createBattleState({
    player: {
      ...player,
      element: "flow",
      secondary_element: "spark",
      base_stats: { hp: 50, atk: 50, def: 50, spd: 95, special: 95 },
    },
    bot: {
      ...bot,
      element: "cloth",
      base_stats: { hp: 50, atk: 10, def: 10, spd: 10, special: 10 },
    },
    seed: "dual-elements",
  });
  const strikeTurn = resolveTurn(dualAttacker, "strike", "dual-strike");
  const strikeEvent = strikeTurn.events.find((event) => event.type === "attack" && event.actor === "player");
  assert.equal(strikeEvent?.action, "strike");
  assert.equal(strikeEvent?.attack_element, "flow");
  assert.deepEqual(strikeEvent?.defense_elements, ["cloth"]);
  assert.equal(strikeEvent?.element_multiplier, MATCHUP_NEUTRAL);

  const surgeTurn = resolveTurn(dualAttacker, "surge", "dual-surge");
  const surgeEvent = surgeTurn.events.find((event) => event.type === "attack" && event.actor === "player");
  assert.equal(surgeEvent?.action, "surge");
  assert.equal(surgeEvent?.attack_element, "spark");
  assert.equal(surgeEvent?.element_multiplier, MATCHUP_STRONG, "spark kuat terhadap cloth");

  const cancelDefender = createBattleState({
    player: {
      ...player,
      element: "plant",
      base_stats: { hp: 50, atk: 50, def: 50, spd: 95, special: 50 },
    },
    bot: {
      ...bot,
      element: "fauna",
      secondary_element: "air",
      base_stats: { hp: 200, atk: 10, def: 10, spd: 10, special: 10 },
    },
    seed: "dual-defense",
  });
  const cancelTurn = resolveTurn(cancelDefender, "strike", "dual-defense");
  const cancelEvent = cancelTurn.events.find((event) => event.type === "attack" && event.actor === "player");
  assert.deepEqual(cancelEvent?.defense_elements, ["fauna", "air"]);
  assert.equal(cancelEvent?.element_multiplier, MATCHUP_NEUTRAL);

  const slowerPlayer = createBattleState({
    player: { ...player, base_stats: { ...base, spd: 20 } },
    bot: { ...bot, base_stats: { ...base, spd: 45 } },
    seed: "speed-order",
  });
  const speedOrdered = resolveTurn(slowerPlayer, "strike", "speed-key");
  assert.equal(
    speedOrdered.events.find((event) => event.type === "attack")?.actor,
    "bot",
    "fighter dengan SPD lebih tinggi harus bergerak dulu"
  );

  const guardState = createBattleState({ player: { ...player, base_stats: base }, bot, seed: "guard" });
  const guarded = resolveTurn(guardState, "guard", "guard-key");
  assert.equal(guarded.state.player.momentum, MOMENTUM_MAX, "Guard tunduk cap PP");

  // PP adalah budget per battle, bukan meter yang mengisi sendiri: satu Special
  // memakan tepat SURGE_COST dan turn berikutnya tidak mengembalikannya. Kalau
  // regen per-turn kembali, battle empat turn membuat PP tidak pernah mengekang.
  const budget = createBattleState({ player: { ...player, base_stats: base }, bot, seed: "budget" });
  const spent = resolveTurn(budget, "surge", "budget-key");
  assert.equal(
    spent.state.player.momentum,
    MOMENTUM_START - SURGE_COST,
    "Special memakan PP tanpa regen per turn"
  );
  budget.player.momentum = SURGE_COST;
  assert.doesNotThrow(
    () => resolveTurn(budget, "surge", "last-pp"),
    "PP tepat sebesar biayanya masih boleh Special"
  );
  budget.player.momentum = 0;
  assert.throws(() => resolveTurn(budget, "surge", "no-momentum"), /NO_MOMENTUM/);
  const refilled = resolveTurn(budget, "guard", "guard-refill");
  assert.equal(refilled.state.player.momentum, 1, "Guard adalah satu-satunya pemulih PP");

  const { readFile } = await import("node:fs/promises");
  const battleEdge = await readFile(
    new URL("../backend/supabase/functions/battle_anima/index.ts", import.meta.url),
    "utf8"
  );
  const tieredExpMigration = await readFile(
    new URL(
      "../backend/supabase/migrations/20260816200507_tiered_exp_and_battle_rewards.sql",
      import.meta.url
    ),
    "utf8"
  );
  assert.match(
    tieredExpMigration,
    /disable trigger animas_mirror_seeker_xp[\s\S]*update public\.animas[\s\S]*enable trigger animas_mirror_seeker_xp/,
    "rebase EXP harus mencegah Seeker EXP administratif"
  );
  assert.ok(
    tieredExpMigration.includes("v_anima.sleep_exp_on is distinct from v_today"),
    "Sleep EXP harus dibatasi sekali per Anima per hari lokal"
  );
  assert.ok(
    tieredExpMigration.includes("v_session.reward_tier")
      && tieredExpMigration.includes("v_encounter.kind = 'boss' and v_run.boss_exp_awarded_at is null"),
    "reward Battle harus memakai tier snapshot dan Boss Expedition sekali per run"
  );
  assert.match(battleEdge, /ANIMA_LOW_ENERGY:\s*409/, "Energy rendah harus menjadi conflict");
  assert.match(battleEdge, /ANIMA_HUNGRY:\s*409/, "Anima lapar harus menjadi conflict");
  assert.ok(
    battleEdge.includes('"message" in error'),
    "error RPC PostgREST berbentuk object tetap harus terbaca oleh mapper"
  );
  assert.match(
    battleEdge,
    /level:\s*levelFromExp\(row\.care_score\)/,
    "snapshot Battle harus membawa level dari care_score"
  );
	assert.ok(
		battleEdge.includes("strike_name: row.strike_name"),
		"snapshot Battle harus membawa nama move unik"
	);
	assert.match(
		battleEdge,
		/ANIMA_BATTLE_FIELDS[\s\S]*strike_name, surge_name/,
		"start Battle harus membaca kolom nama move, bukan hanya menulisnya ke snapshot kosong"
	);
  assert.ok(
    battleEdge.includes("syncProfileTimezone"),
    "battle_anima harus menyimpan offset zona sebelum status/start"
  );
  assert.match(
    battleEdge,
    /SECONDARY_ELEMENT_FIELD\s*=\s*", secondary_element"/,
    "start Battle harus membaca secondary_element setelah migration foundation"
  );
  assert.match(
    battleEdge,
    /readSecondaryElement/,
    "snapshot Battle siap membaca secondary_element saat kolom live"
  );
  assert.match(
    battleEdge,
    /gallery_entries/,
    "bot Battle harus memprioritaskan gallery published"
  );
  assert.match(
    battleEdge,
    /pickLegacyBot/,
    "bot Battle harus fallback legacy species_library saat gallery kosong"
  );
  assert.match(
    battleEdge,
    /sheet_url/,
    "snapshot bot gallery harus membawa signed sheet_url, bukan path privat"
  );
  assert.match(
    battleEdge,
    /async function startBattle[\s\S]*withFreshBotArt\(existing\)[\s\S]*withFreshBotArt\(data\)/,
    "start/resume existing Battle harus menyegarkan signed art bot"
  );
  assert.match(
    battleEdge,
    /async function resumeBattle[\s\S]*withFreshBotArt\(data\)/,
    "resume Battle harus menyegarkan signed art bot yang kedaluwarsa"
  );
  assert.match(
    battleEdge,
    /withFreshBotArt[\s\S]*signSheetUrl\(db, bot\.sheet_path\)/,
    "art bot fallback harus ditandatangani dari salinan privat per-Anima"
  );
  const signedRoster = await readFile(
    new URL("../backend/supabase/functions/_shared/signed_roster.ts", import.meta.url),
    "utf8"
  );
  assert.match(
    signedRoster,
    /\.from\("anima_sheets"\)[\s\S]*createSignedUrl\(path, BATTLE_SHEET_SIGNED_TTL\)/,
    "signSheetUrl harus menandatangani bucket privat anima_sheets"
  );
  assert.match(
    signedRoster,
    /hit\.expires_at - now > SIGN_REFRESH_MARGIN_MS/,
    "cache signed URL harus menandatangani ulang sebelum masa berlakunya menipis"
  );
  assert.match(
    battleEdge,
    /typeof botSnapshot\.anima_id === "string"/,
    "refresh art harus membaca ID bot dari snapshot karena payload publik menyembunyikan FK session"
  );
  assert.match(
    battleEdge,
    /artByKey\.has\(artKey\(candidate\)\) && candidate\.sheet_path && candidate\.manifest/,
    "fallback legacy hanya boleh memakai kandidat yang sudah punya salinan art privat"
  );
}

console.log("23a. Team Battle roster, switch, KO, dan EXP participation");
{
  const member = (id, stats = {}) => ({
    anima_id: id,
    name: id,
    species_key: id,
    color_bucket: "blue",
    stage: 1,
    level: 1,
    element: "metal",
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50, ...stats },
  });
  const player = [
    member("p0", { atk: 95, spd: 95 }),
    member("p1"),
    member("p2"),
    member("p3"),
  ];
  const opponent = [
    member("o0", { hp: 10, def: 10, spd: 10 }),
    member("o1", { hp: 10, def: 10, spd: 10 }),
    member("o2", { hp: 10, def: 10, spd: 10 }),
    member("o3", { hp: 10, def: 10, spd: 10 }),
  ];
  const initial = createTeamBattleState({ player, opponent, seed: "team-selftest" });
  assert.equal(initial.player.roster.length, 4);
  assert.equal(initial.player.roster[0].participated, true);
  assert.equal(initial.player.roster[1].participated, false);
  assert.ok(teamCombatPower(player) > 0);
  assert.deepEqual(
    teamRewardPreview(player, opponent, "reward"),
    teamRewardPreview(player, opponent, "reward"),
    "preview reward team harus deterministik",
  );

  const switched = resolveTeamTurn(initial, "switch", "switch-key", "", 1);
  assert.equal(switched.state.player.active_slot, 1);
  assert.equal(switched.state.player.roster[1].participated, true);
  assert.ok(
    switched.events.some((event) =>
      event.type === "switch" && event.actor === "player" && event.forced === false
    ),
    "switch sukarela harus tercatat dan memakan turn",
  );
  assert.deepEqual(
    resolveTeamTurn(initial, "switch", "switch-key", "", 1),
    switched,
    "resolver Team harus deterministik untuk replay key sama",
  );
  assert.throws(
    () => resolveTeamTurn(initial, "switch", "bad-switch", "", 0),
    /INVALID_SWITCH_SLOT/,
  );

  const knockout = resolveTeamTurn(initial, "strike", "knockout-key");
  assert.equal(knockout.state.opponent.active_slot, 1);
  assert.ok(
    knockout.events.some((event) =>
      event.type === "switch" && event.actor === "opponent" && event.forced === true
    ),
    "opponent KO harus auto-switch gratis",
  );
  assert.ok(
    !knockout.events.some((event) => event.type === "attack" && event.actor === "opponent"),
    "replacement tidak boleh mewarisi initiative fighter yang KO",
  );

  const fragile = [
    member("f0", { hp: 10, def: 10, atk: 10, spd: 10 }),
    member("f1"),
    member("f2"),
    member("f3"),
  ];
  const striker = [member("s0", { atk: 95, spd: 95 }), member("s1")];
  const forcedState = createTeamBattleState({
    player: fragile,
    opponent: striker,
    seed: "forced-switch",
  });
  const playerKnockedOut = resolveTeamTurn(forcedState, "strike", "player-ko");
  assert.equal(playerKnockedOut.state.player.forced_switch, true);
  const forcedSwitch = resolveTeamTurn(
    playerKnockedOut.state,
    "switch",
    "forced-switch-key",
    "",
    1,
  );
  assert.equal(forcedSwitch.state.player.active_slot, 1);
  assert.ok(
    !forcedSwitch.events.some((event) => event.type === "attack"),
    "forced switch gratis tidak boleh memberi opponent serangan tambahan",
  );

  const soloOpponent = createTeamBattleState({
    player,
    opponent: [member("solo", { hp: 10, def: 10, spd: 10 })],
    seed: "solo-opponent",
  });
  const partyWipe = resolveTeamTurn(soloOpponent, "strike", "party-wipe");
  assert.equal(partyWipe.state.status, "won", "1-member opponent harus selesai saat KO");

  const itemState = createTeamBattleState({
    player: player.map((entry) => ({ ...entry, base_stats: { ...entry.base_stats, hp: 95 } })),
    opponent,
    seed: "team-item",
  });
  const usedItem = resolveTeamTurn(itemState, "item", "item-key", "vital_patch");
  assert.equal(usedItem.state.player.item_used, true);
  assert.throws(
    () => resolveTeamTurn(usedItem.state, "item", "second-item", "vital_patch"),
    /ITEM_ALREADY_USED/,
    "satu item berlaku untuk seluruh encounter, bukan per fighter",
  );

  const bossOpponent = [
    { ...member("ace", { hp: 30, atk: 65, special: 70 }), special: true },
    member("regular-1", { hp: 10, def: 10, spd: 10 }),
    member("regular-2", { hp: 10, def: 10, spd: 10 }),
    member("regular-3", { hp: 10, def: 10, spd: 10 }),
  ];
  const bossState = createTeamBattleState({
    player,
    opponent: bossOpponent,
    seed: "boss-ace",
    encounterKind: "boss",
    acePassive: {
      type: "bonus_pp",
      value: 1,
      name: "Final Confection",
      copy: "Cotton enters with +1 PP.",
    },
  });
  assert.equal(bossState.opponent.active_slot, 1, "ace tidak boleh menjadi starter Boss");
  const lowRegularState = structuredClone(bossState);
  lowRegularState.opponent.roster[1].hp = Math.floor(
    lowRegularState.opponent.roster[1].max_hp * 0.2,
  );
  lowRegularState.opponent.roster[2].hp = 0;
  lowRegularState.opponent.roster[3].hp = 0;
  const lowRegularTurn = resolveTeamTurn(
    lowRegularState,
    "guard",
    "ace-low-hp-2",
  );
  assert.equal(
    lowRegularTurn.state.opponent.active_slot,
    1,
    "Boss tidak boleh switch sukarela ke ace saat reguler aktif masih hidup",
  );
  assert.ok(
    !lowRegularTurn.events.some((event) =>
      event.type === "switch" && event.actor === "opponent" && event.to_slot === 0
    ),
    "ace hanya boleh masuk lewat forced switch setelah reguler terakhir KO",
  );
  const firstRegular = resolveTeamTurn(bossState, "strike", "ace-ko-1");
  const secondRegular = resolveTeamTurn(firstRegular.state, "strike", "ace-ko-2");
  assert.notEqual(firstRegular.state.opponent.active_slot, 0, "ace tetap di-reserve saat reguler hidup");
  assert.notEqual(secondRegular.state.opponent.active_slot, 0, "ace tetap di-reserve sampai reguler terakhir");
  const finalAce = resolveTeamTurn(secondRegular.state, "strike", "ace-ko-3");
  assert.equal(finalAce.state.opponent.active_slot, 0, "switch terakhir wajib memilih ace");
  assert.deepEqual(
    finalAce.events.map((event) => event.type).filter((type) =>
      ["final_ace", "switch", "ace_passive"].includes(type)
    ),
    ["final_ace", "switch", "ace_passive"],
    "event final ace harus pose cue, switch, lalu passive",
  );
  assert.equal(finalAce.state.opponent.roster[0].momentum, 4);
  assert.equal(finalAce.state.opponent.roster[0].momentum_max, 4);
  assert.equal(finalAce.state.opponent.roster[0].ace_passive_applied, true);
  assert.deepEqual(
    resolveTeamTurn(secondRegular.state, "strike", "ace-ko-3"),
    finalAce,
    "final ace dan passive harus deterministik saat replay",
  );
  const ordinaryTeam = createTeamBattleState({
    player,
    opponent: bossOpponent,
    seed: "ordinary-special",
  });
  assert.equal(ordinaryTeam.opponent.active_slot, 0, "Team Battle biasa tidak memakai reserve ace");
  assert.equal(ordinaryTeam.opponent.reserve_ace, false);

  const { readFile } = await import("node:fs/promises");
  const teamEdge = await readFile(
    new URL("../backend/supabase/functions/team_battle/index.ts", import.meta.url),
    "utf8",
  );
  const teamTurnHandler = teamEdge.slice(teamEdge.indexOf("async function playTeamTurn"));
  assert.ok(
    teamTurnHandler.indexOf('db.rpc("resume_team_battle"') <
      teamTurnHandler.indexOf('.from("team_battle_turns")'),
    "replay lookup Team harus memverifikasi owner session lebih dulu",
  );
  assert.ok(!teamEdge.includes("body.owner_id"), "owner Team harus selalu turun dari JWT");
  assert.ok(
    teamEdge.includes('"feature_team_battle"') && teamEdge.includes('"FEATURE_DISABLED"'),
    "feature flag Team harus ditegakkan server-side",
  );
  assert.ok(
    teamEdge.includes("!lifecycleOperation && !await teamBattleEnabled()") &&
      teamEdge.includes('operation === "resume"') &&
      teamEdge.includes('operation === "turn"') &&
      teamEdge.includes('operation === "forfeit"'),
    "feature rollback tidak boleh mengunci session Team yang sudah aktif",
  );
  assert.ok(
    teamEdge.includes('"replace_team_battle_candidates"'),
    "refresh rival harus replace atomik lewat RPC",
  );
  const signedRoster = await readFile(
    new URL("../backend/supabase/functions/_shared/signed_roster.ts", import.meta.url),
    "utf8",
  );
  assert.ok(
    signedRoster.includes('member.system_asset === "placeholder"'),
    "fresh database harus bisa memakai system team tanpa Storage art",
  );
  const teamConfig = await readFile(
    new URL("../backend/supabase/config.toml", import.meta.url),
    "utf8",
  );
  assert.match(teamConfig, /\[functions\.team_battle\][\s\S]*verify_jwt = true/);
}

console.log("23b. Expedition manifest, map, persistent HP, dan effect allowlist");
{
  const roster = (prefix) => Array.from({ length: 4 }, (_, index) => ({
    anima_id: `${prefix}-${index}`,
    name: `${prefix}-${index}`,
    stage: 1,
    level: 1,
    element: "food",
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
  }));
  const opponents = Array.from({ length: 4 }, (_, index) => ({
    id: `candy-${index}`,
    roster: roster(`candy-${index}`),
  }));
  const optionPools = {
    recovery: [{
      title_key: "RECOVERY",
      options: [{ id: "heal", effect: { type: "heal_party", ratio: 0.25 } }],
    }],
    cache: [{
      title_key: "CACHE",
      options: [{
        id: "power",
        effect: { type: "stat_boost", stat: "atk", value: 0.1 },
      }],
    }],
    shop: [{
      title_key: "SHOP",
      options: [{
        id: "shop-heal",
        cost_supplies: 2,
        effect: { type: "heal_party", ratio: 0.25 },
      }],
    }],
    mystery: [{
      title_key: "MYSTERY",
      options: [{ id: "supply", effect: { type: "supplies", value: 2 } }],
    }],
  };
  const zone = (index) => ({
    id: `zone-${index}`,
    background_path: `expeditions/demo/v1/zones/zone-${index}.png`,
    node_pools: {
      battle: [{ opponent_id: "candy-0", supplies_reward: 2 }],
      elite: [{ opponent_id: "candy-1", supplies_reward: 4 }],
      ...optionPools,
    },
  });
  const manifest = {
    schema_version: 1,
    summary: { title: "The Sugarworks" },
    zones: [zone(1), zone(2), zone(3)],
    opponents,
    boss: {
      opponent_id: "candy-3",
      supplies_reward: 8,
      title_key: "CANDY_BOSS",
    },
  };
  assert.equal(validateChapterManifest(manifest).zones.length, 3);
  assert.throws(
    () => validateChapterManifest({
      ...manifest,
      zones: [{ ...zone(1), node_pools: { ...zone(1).node_pools, mystery: [{
        options: [{ id: "bad", effect: { type: "arbitrary_script" } }],
      }] } }, zone(2), zone(3)],
    }),
    /UNSUPPORTED_CHAPTER_EFFECT/,
    "manifest tidak boleh mengarang effect runtime baru",
  );
  assert.throws(
    () => validateChapterManifest({
      ...manifest,
      zones: [{ ...zone(1), node_pools: { ...zone(1).node_pools, shop: [{
        options: [{
          id: EXPEDITION_SHOP_SKIP_OPTION_ID,
          effect: { type: "supplies", value: 1 },
        }],
      }] } }, zone(2), zone(3)],
    }),
    /INVALID_CHAPTER_OPTIONS/,
    "manifest tidak boleh memakai ID wire yang dicadangkan untuk Skip Shop",
  );
  const map = generateZoneMap(manifest, 3, 1, "sugar-seed");
  assert.deepEqual(
    map,
    generateZoneMap(manifest, 3, 1, "sugar-seed"),
    "map Expedition harus deterministik untuk seed + attempt sama",
  );
  assert.equal(map.background_path, "expeditions/demo/v1/zones/zone-3.png");
  assert.equal(map.nodes.length, 9, "empat layer bercabang plus satu Boss");
  assert.equal(findExpeditionNode(map, map.entry[0]).depth, 1);
  const fourthLayer = map.nodes.find((node) => node.depth === 4);
  assert.equal(
    findExpeditionNode(map, nextNodeIds(map, fourthLayer.id)[0]).kind,
    "boss",
    "zona ketiga harus mengarah ke Boss sesudah empat node",
  );
  assert.equal(opponentForNode(manifest, {
    kind: "boss",
    opponent_id: "candy-3",
  }).roster.length, 4);
  const manifestWithAce = structuredClone(manifest);
  manifestWithAce.opponents[3].roster[3].special = true;
  manifestWithAce.zones[2].node_pools.elite = [{
    opponent_id: "candy-3",
    supplies_reward: 7,
  }];
  const eliteRoster = opponentRosterForEncounter(manifestWithAce, {
    kind: "elite",
    opponent_id: "candy-3",
  }, 3);
  assert.equal(eliteRoster.length, 4, "elite pengganti ace tetap membawa roster penuh");
  assert.ok(
    eliteRoster.every((member) => member.special !== true),
    "Battle dan Elite tidak boleh memunculkan Anima special Boss",
  );
  assert.equal(
    eliteRoster[3].anima_id,
    "candy-0-0",
    "ace Elite diganti deterministik dari pool Battle zona yang sama",
  );
  assert.equal(
    opponentRosterForEncounter(manifestWithAce, {
      kind: "boss",
      opponent_id: "candy-3",
    }, 3)[3].special,
    true,
    "Boss tetap membawa ace untuk final_ace server-authoritative",
  );

  const fresh = createTeamBattleState({
    player: prepareExpeditionRoster(roster("player"), []),
    opponent: opponents[0].roster,
    seed: "fresh-hp",
  });
  assert.ok(
    fresh.player.roster.every((fighter) => fighter.hp === fighter.max_hp),
    "zona pertama harus mulai dengan HP penuh",
  );
  assert.equal(
    fresh.player.roster[0].max_hp,
    toBattleStats({ hp: 50, atk: 50, def: 50, spd: 50, special: 50 }, 1, "", 1).max_hp,
    "max HP zona baru memakai rumus Battle, bukan base_stats.hp",
  );
  const stamped = createTeamBattleState({
    player: prepareExpeditionRoster(
      roster("player"),
      roster("player").map((member) => ({
        anima_id: member.anima_id,
        hp: 50,
        max_hp: 220,
      })),
    ),
    opponent: opponents[0].roster,
    seed: "stamped-hp",
  });
  assert.ok(
    stamped.player.roster.every((fighter) => fighter.hp === fighter.max_hp),
    "HP yang tercatat sebagai base_stats.hp plus max Battle adalah stamp startZone, bukan damage",
  );
  const persistent = prepareExpeditionRoster(
    roster("player"),
    [
      { anima_id: "player-0", hp: 0 },
      { anima_id: "player-1", hp: 17 },
      { anima_id: "player-2", hp: 50 },
      { anima_id: "player-3", hp: 50 },
    ],
    [{ type: "stat_boost", stat: "atk", value: 0.1 }],
  );
  const encounter = createTeamBattleState({
    player: persistent,
    opponent: opponents[0].roster,
    seed: "persistent-hp",
  });
  assert.equal(encounter.player.active_slot, 1, "encounter baru melewati fighter yang masih KO");
  assert.equal(encounter.player.roster[1].hp, 17, "HP harus bertahan antar-node dalam zona");
  assert.equal(encounter.player.roster[0].participated, false);
  assert.equal(encounter.player.roster[1].participated, true);
  assert.ok(persistent[0].base_stats.atk > 50, "boost run diterapkan sebelum snapshot encounter");
  assert.ok(
    encounter.player.roster[2].max_hp > 50,
    "max HP Battle tidak boleh jatuh ke base_stats.hp",
  );
  const checkpointParty = encounter.player.roster.map((fighter, index) => ({
    anima_id: `player-${index}`,
    hp: index === 0 ? 0 : Math.max(1, fighter.max_hp - 80),
    current_hp: index === 0 ? 0 : Math.max(1, fighter.max_hp - 80),
    max_hp: fighter.max_hp,
    boosts_applied: true,
    base_stats: { hp: 50, atk: 80, def: 80, spd: 80, special: 50 },
  }));
  const poweredZone = createTeamBattleState({
    player: prepareExpeditionZoneRoster(
      roster("player"),
      checkpointParty,
      [],
      "power_up",
    ),
    opponent: opponents[0].roster,
    seed: "checkpoint-power",
  });
  assert.equal(poweredZone.player.roster[0].hp, 0, "Power Up tidak boleh membangunkan KO");
  assert.equal(
    poweredZone.player.roster[1].hp,
    checkpointParty[1].hp,
    "Start zona berikutnya harus mempertahankan HP checkpoint",
  );
  assert.ok(
    poweredZone.player.roster[1].atk > fresh.player.roster[1].atk
    && poweredZone.player.roster[1].def > fresh.player.roster[1].def
    && poweredZone.player.roster[1].spd > fresh.player.roster[1].spd,
    "Power Up memberi +10% Attack, Guard, dan Speed untuk zona berikutnya",
  );
  const expiredPower = createTeamBattleState({
    player: prepareExpeditionZoneRoster(
      roster("player"),
      poweredZone.player.roster,
      [],
      "recover",
    ),
    opponent: opponents[0].roster,
    seed: "checkpoint-power-expired",
  });
  assert.equal(
    expiredPower.player.roster[1].atk,
    fresh.player.roster[1].atk,
    "Power Up checkpoint harus kedaluwarsa pada zona berikutnya",
  );

  const levelOne = toBattleStats(
    { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    1,
    "",
    1,
  );
  const levelTwo = toBattleStats(
    { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    1,
    "",
    2,
  );
  const grownRoster = roster("player").map((member, index) => (
    index <= 1 ? { ...member, level: 2, care_score: 5 } : { ...member, care_score: 0 }
  ));
  const savedStats = { hp: 50, atk: 50, def: 50, spd: 50, special: 50 };
  const grown = prepareExpeditionRoster(
    grownRoster,
    [
      {
        anima_id: "player-0",
        hp: levelOne.max_hp,
        max_hp: levelOne.max_hp,
        level: 1,
        atk: 1,
        boosts_applied: true,
        base_stats: savedStats,
      },
      {
        anima_id: "player-1",
        hp: 17,
        max_hp: levelOne.max_hp,
        level: 1,
        atk: 1,
        boosts_applied: true,
        base_stats: savedStats,
      },
      {
        anima_id: "player-2",
        hp: 0,
        max_hp: levelOne.max_hp,
        level: 1,
        boosts_applied: true,
        base_stats: savedStats,
      },
      {
        anima_id: "player-3",
        hp: levelOne.max_hp,
        max_hp: levelOne.max_hp,
        level: 1,
        boosts_applied: true,
        base_stats: savedStats,
      },
    ],
  );
  assert.equal(grown[0].level, 2, "party_state tidak boleh membekukan Level setelah EXP");
  assert.equal(grown[1].level, 2, "fighter yang terluka tetap memakai Level live");
  const grownFight = createTeamBattleState({
    player: grown,
    opponent: opponents[0].roster,
    seed: "grown-level",
  });
  assert.equal(grownFight.player.roster[1].atk, levelTwo.atk);
  assert.equal(grownFight.player.roster[1].max_hp, levelTwo.max_hp);
  assert.equal(
    grownFight.player.roster[1].hp,
    17 + (levelTwo.max_hp - levelOne.max_hp),
    "naik Level menambah sisa HP sebesar kenaikan max HP",
  );
  assert.equal(grownFight.player.roster[2].hp, 0, "KO tidak bangkit dari Level Up");
  assert.equal(
    grownFight.player.roster[0].hp,
    levelTwo.max_hp,
    "HP penuh mengikuti max HP Level baru",
  );

  const healed = applyNodeOption({
    partyState: encounter.player.roster.map((fighter, index) => ({
      ...persistent[index],
      ...fighter,
    })),
    supplies: 3,
    boosts: [],
    node: optionPools.shop[0],
    optionId: "shop-heal",
  });
  assert.equal(healed.supplies, 1, "Shop Expedition memakai Supplies");
  assert.ok(healed.party_state[1].hp > 17, "Recovery/Shop mengubah HP persisten");
  const skipBoosts = [{ type: "shop_discount", value: 0.25 }];
  const skippedShop = applyNodeOption({
    partyState: healed.party_state,
    supplies: healed.supplies,
    boosts: skipBoosts,
    node: { ...optionPools.shop[0], kind: "shop" },
    optionId: EXPEDITION_SHOP_SKIP_OPTION_ID,
  });
  assert.deepEqual(skippedShop.party_state, healed.party_state, "skip Shop menjaga HP");
  assert.equal(skippedShop.supplies, healed.supplies, "skip Shop tidak memakai Tokens");
  assert.deepEqual(skippedShop.boosts, skipBoosts, "skip Shop menjaga boost");
  assert.equal(skippedShop.option.skipped, true, "skip Shop dicatat sebagai no-purchase choice");
  assert.throws(
    () => applyNodeOption({
      partyState: healed.party_state,
      supplies: healed.supplies,
      boosts: skipBoosts,
      node: { ...optionPools.shop[0], kind: "recovery" },
      optionId: EXPEDITION_SHOP_SKIP_OPTION_ID,
    }),
    /INVALID_EXPEDITION_CHOICE/,
    "choice skip hanya sah di node Shop",
  );
  const boosted = applyNodeOption({
    partyState: healed.party_state,
    supplies: 5,
    boosts: [{ type: "shop_discount", value: 0.5 }],
    node: {
      options: [{
        id: "boost",
        cost_supplies: 3,
        effect: { type: "stat_boost", stat: "max_hp", value: 0.2 },
      }],
    },
    optionId: "boost",
  });
  assert.equal(boosted.supplies, 3, "diskon Shop harus menurunkan biaya Supplies");
  assert.equal(boosted.party_state[1].max_hp, 60, "boost max HP berlaku pada zona aktif");
  const ppState = applyEncounterBoosts(encounter, [
    { type: "start_pp", value: 1 },
    { type: "start_pp", value: 1 },
  ]);
  assert.equal(ppState.player.roster[0].momentum, 5, "boost PP diterapkan per encounter");
  assert.equal(ppState.player.roster[0].momentum_max, 5, "bonus PP dibatasi dua");

  const { readFile } = await import("node:fs/promises");
  const koExpSql = await readFile(
    new URL("../backend/supabase/migrations/20260815191450_deny_ko_party_exp.sql", import.meta.url),
    "utf8",
  );
  assert.match(
    koExpSql,
    /when coalesce\(\(p_member->>'hp'\)::integer, 0\) <= 0 then 0/,
    "anggota KO tidak boleh mendapat EXP Team/Expedition",
  );
  const expeditionEdge = await readFile(
    new URL("../backend/supabase/functions/expedition/index.ts", import.meta.url),
    "utf8",
  );
  const expeditionTurn = expeditionEdge.slice(expeditionEdge.indexOf("async function playTurn"));
  assert.ok(!expeditionEdge.includes("body.owner_id"), "owner Expedition harus turun dari JWT");
  assert.ok(
    expeditionEdge.includes('"feature_expedition"') &&
      expeditionEdge.includes('"ack_home_popup"') &&
      expeditionEdge.includes('"start_zone"') &&
      expeditionEdge.includes('"checkpoint_choice"') &&
      expeditionEdge.includes('"refresh_shop"'),
    "flag Expedition harus menutup start baru tanpa mengunci lifecycle run lama",
  );
  assert.ok(
    !expeditionEdge.includes("announcementsEnabled") &&
      !expeditionEdge.includes('"feature_chapter_push"'),
    "announcement in-app tidak boleh bergantung pada flag push OS",
  );
  assert.ok(
    expeditionEdge.includes("chapterBuildError") &&
      expeditionEdge.includes('"x-scanima-build"'),
    "minimum build chapter harus dipagari di server",
  );
  assert.ok(
    expeditionTurn.indexOf("loadEncounter(ownerId, encounterId)") <
      expeditionTurn.indexOf('.from("expedition_encounter_turns")'),
    "replay turn Expedition harus memverifikasi owner encounter lebih dulu",
  );
  assert.ok(
    !expeditionEdge.includes("REPLICATE_API_TOKEN") &&
      !expeditionEdge.includes("IMAGE_MODEL"),
    "runtime Expedition tidak boleh memanggil model",
  );
  assert.ok(
    expeditionEdge.includes("arena_background_url") &&
      expeditionEdge.includes("background_path"),
    "arena Expedition harus menerima URL art zona dari zone_map",
  );
  const expeditionConfig = await readFile(
    new URL("../backend/supabase/config.toml", import.meta.url),
    "utf8",
  );
  const expeditionRpcs = await readFile(
    new URL(
      "../backend/supabase/migrations/20260815013028_expedition_rpcs.sql",
      import.meta.url,
    ),
    "utf8",
  );
  const expeditionEncounterRpcs = await readFile(
    new URL(
      "../backend/supabase/migrations/20260815013155_expedition_encounter_rpcs.sql",
      import.meta.url,
    ),
    "utf8",
  );
  const expeditionAnnouncements = await readFile(
    new URL(
      "../backend/supabase/migrations/20260815023934_chapter_announcements.sql",
      import.meta.url,
    ),
    "utf8",
  );
  assert.ok(
    expeditionRpcs.includes("v_next_party_ids is distinct from v_party_ids") &&
      expeditionRpcs.includes("status = 'forfeited'"),
    "choice dan abandon Expedition harus menjaga roster serta encounter aktif",
  );
  assert.ok(
    expeditionEncounterRpcs.indexOf("for update;") <
      expeditionEncounterRpcs.indexOf("expedition_daily_reward_status(p_owner"),
    "cap progression Expedition harus dibaca setelah profile row lock",
  );
  assert.ok(
    expeditionAnnouncements.includes("version.published_at > profile.created_at") &&
      expeditionAnnouncements.includes("receipt.chapter_opened_at is null") &&
      expeditionAnnouncements.includes("home_popup_seen_at = coalesce") &&
      expeditionAnnouncements.includes("revoke all on function"),
    "announcement harus one-time per akun, idempoten, dan service-role-only",
  );
  assert.match(
    expeditionConfig,
    /\[functions\.expedition\][\s\S]*verify_jwt = true/,
    "Expedition wajib melewati JWT gateway",
  );
  const seekerManifest = {
    ...manifest,
    boss_seeker: {
      id: "confectioner",
      display_name: "The Confectioner",
      portrait_pose: "profile",
      sheet_path: "expeditions/demo/v1/boss/seeker.png",
      poses: ["intro_idle", "profile"],
      dialogue: {
        chapter_intro: "Welcome to the archive.",
        boss_intro: "Show me your formula.",
      },
      manifest: { version: 1, frame_size: [300, 300], poses: {} },
    },
  };
  const seeker = publicBossSeeker(seekerManifest);
  assert.equal(seeker.display_name, "The Confectioner");
  assert.equal(seeker.sheet_path, "expeditions/demo/v1/boss/seeker.png");
  assert.equal(seeker.dialogue.boss_intro, "Show me your formula.");
  assert.equal(publicBossSeeker(manifest), null, "chapter tanpa seeker tidak boleh mengarang payload");
  assert.equal(
    publicBossSeeker({
      boss_seeker: {
        dialogue: { boss_intro: "x" },
        sheet_path: "../escape.png",
      },
    }),
    null,
    "sheet_path seeker tidak boleh keluar prefix",
  );
  const attached = attachBossSeeker({
    run: { id: "run-1", zone_attempt: 2 },
    encounter: { id: "enc-1", kind: "boss" },
  }, seekerManifest);
  assert.equal(attached.run.boss_seeker.id, "confectioner");
  assert.equal(attached.encounter.zone_attempt, 2);
  assert.ok(
    expeditionEdge.includes("publicBossSeeker") &&
      expeditionEdge.includes("sheet_path") &&
      expeditionEdge.includes("boss_seeker"),
    "payload Expedition harus menandatangani sheet Boss Seeker",
  );
}

console.log("23c. gallery moderation + thumb crop");
{
  const { cropIdleThumb, parseModeration } = await import(
    "../backend/supabase/functions/_shared/gallery_shared.mjs"
  );
  const { postprocessSheet, LAYOUT_3X3 } = await import(
    "../backend/supabase/functions/_shared/postprocess.mjs"
  );
  const blobs3 = {
    idle: { x: 8, y: 30, w: 150, h: 240 },
    attack: { x: 16, y: 28, w: 170, h: 232 },
    sleep: { x: 12, y: 170, w: 190, h: 110 },
    happy: { x: 10, y: 32, w: 148, h: 236 },
    hungry: { x: 14, y: 40, w: 144, h: 220 },
    dirty: { x: 12, y: 36, w: 146, h: 228 },
    defeated: { x: 18, y: 130, w: 160, h: 150 },
    fx_strike: { x: 90, y: 180, w: 80, h: 60 },
    fx_surge: { x: 80, y: 160, w: 100, h: 80 },
  };
  const sheet = await postprocessSheet(await buildSheet(blobs3, LAYOUT_3X3), {
    speciesKey: "gallery_thumb",
    promptVersion: "v12",
  });
  const thumb = await cropIdleThumb(sheet.png, sheet.manifest);
  assert.ok(thumb.length > 256, "thumb gallery harus non-kosong");
  const safe = parseModeration('{"safe": true}');
  assert.equal(safe.safe, true);
  const unsafe = parseModeration('{"safe": false, "reject_reason": "human"}');
  assert.equal(unsafe.safe, false);
  assert.equal(unsafe.reject_reason, "human");
}

console.log("23c. gallery edge function kontrak");
{
  const { readFile } = await import("node:fs/promises");
  const galleryEdge = await readFile(
    new URL("../backend/supabase/functions/gallery/index.ts", import.meta.url),
    "utf8",
  );
  for (const op of ["list", "publish", "unpublish", "report", "hide", "my_status"]) {
    assert.ok(galleryEdge.includes(`"${op}"`), `gallery operation ${op} harus ada`);
  }
  assert.match(galleryEdge, /feature_gallery/, "gallery harus menghormati feature flag");
  assert.match(galleryEdge, /GOOGLE_IDENTITY_REQUIRED|requireLinkedGoogle/, "publish gallery harus linked Google");
  assert.match(
    galleryEdge,
    /select\("id, display_name/,
    "list gallery hanya mengekspos metadata publik",
  );
}

console.log("24. sheet v7 3x3 sembilan sel");
{
  const blobs3 = {
    idle: { x: 8, y: 30, w: 150, h: 240 },
    attack: { x: 16, y: 28, w: 170, h: 232 },
    sleep: { x: 12, y: 170, w: 190, h: 110 },
    happy: { x: 10, y: 32, w: 148, h: 236 },
    hungry: { x: 14, y: 40, w: 144, h: 220 },
    dirty: { x: 12, y: 36, w: 146, h: 228 },
    defeated: { x: 18, y: 130, w: 160, h: 150 },
    fx_strike: { x: 90, y: 180, w: 80, h: 60 },
    fx_surge: { x: 80, y: 160, w: 100, h: 80 },
  };
  const { png, manifest } = await postprocessSheet(await buildSheet(blobs3, LAYOUT_3X3), {
    speciesKey: "selftest_grid3",
    promptVersion: "v7",
    sheetName: "grid3.png",
  });
  assert.equal(manifest.qa.cells_detected, 9, "sembilan sel harus terdeteksi");
  assert.deepEqual(manifest.qa.cells_rejected, {}, "tidak boleh ada sel 3x3 ditolak");
  const [fw, fh] = manifest.frame_size;
  assert.deepEqual(manifest.sheet_size, [fw * 3, fh * 3], "sheet keluaran harus 3x3 frame");
  for (const pose of LAYOUT_3X3.poses) {
    const [col, row] = LAYOUT_3X3.quadrant[pose];
    assert.deepEqual(
      manifest.poses[pose].region,
      [col * fw, row * fh, fw, fh],
      `region ${pose} salah di grid 3x3`
    );
  }
  const out = await Image.decode(png);
  for (const pose of LAYOUT_3X3.poses) {
    const [rx, ry] = manifest.poses[pose].region;
    const bb = findBBox(out.bitmap, out.width, [rx, ry, fw, fh]);
    const want = outer(blobs3[pose]);
    assert.equal(bb.w, want.w, `${pose}: lebar 3x3 berubah`);
    assert.equal(bb.h, want.h, `${pose}: tinggi 3x3 berubah`);
    assert.equal(ry + fh - (bb.y + bb.h), PAD, `${pose}: 3x3 tidak rata bawah`);
  }

  const v12 = await postprocessSheet(await buildSheet(blobs3, LAYOUT_3X3), {
    speciesKey: "selftest_grid3_v12",
    promptVersion: "v12",
    vfxMotion: { fx_strike: "sweep", fx_surge: "bloom" },
  });
  assert.equal(v12.manifest.qa.seam_margin.passed, true, "sheet v12 yang rapi harus lolos seam gate");
  assert.equal(v12.manifest.poses.fx_strike.motion, "sweep");
  assert.equal(v12.manifest.poses.fx_surge.motion, "bloom");

  const leaked = await Image.decode(await buildSheet(blobs3, LAYOUT_3X3));
  const cell = Math.floor(SIZE / 3);
  drawBlob(
    leaked.bitmap,
    cell - 36,
    cell - 34,
    18,
    18,
    FILLS.attack
  );
  const leakedPng = await leaked.encode();
  await assert.rejects(
    () => postprocessSheet(leakedPng, {
      speciesKey: "selftest_grid3_leak",
      promptVersion: "v12",
    }),
    /safe margin v12.*idle:detached_idle_seam_fragment/,
    "fragmen Attack yang jatuh ke margin Idle wajib menolak sheet v12"
  );
}

console.log("25. prompt v7 3x3 plus nama move, species_key tidak berubah");
{
  const { readFile } = await import("node:fs/promises");
  const template = await readFile(new URL("../backend/prompts/v7/sprite_sheet.md", import.meta.url), "utf8");
  const evolve = await readFile(
    new URL("../backend/prompts/v7/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const vision = await readFile(new URL("../backend/prompts/v7/vision_system.md", import.meta.url), "utf8");
  const schema = JSON.parse(
    await readFile(new URL("../backend/prompts/v7/vision_schema.json", import.meta.url), "utf8")
  );
  const createAnima = await readFile(
    new URL("../backend/supabase/functions/create_anima/index.ts", import.meta.url),
    "utf8"
  );
  const evalRunner = await readFile(new URL("./run.mjs", import.meta.url), "utf8");
  const postprocess = await readFile(
    new URL("../backend/supabase/functions/_shared/postprocess.mjs", import.meta.url),
    "utf8"
  );

  assert.ok(template.includes("EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT"));
  assert.ok(evolve.includes("EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT"));
  assert.ok(template.includes("BOTTOM CENTER — STRIKE EFFECT"));
  assert.ok(template.includes("{{strike_name}}") && template.includes("{{surge_name}}"));
  assert.ok(vision.includes("`strike_name`:") && vision.includes("`surge_name`:"));
  assert.ok(schema.properties.strike_name && schema.properties.surge_name);
  assert.equal(promptMajor("v7"), 7);
  assert.equal(promptMajor("v3"), 3);
  assert.equal(normalizeMoveName("Rim Toss"), "Rim Toss");
  assert.equal(normalizeMoveName("Thunder Rim Toss Combo"), "Thunder Rim");
  assert.equal(normalizeMoveName("d-pad jab extra"), "D-pad Jab");
  assert.equal(normalizeMoveName("Shellmon"), "Shell");
  assert.ok(vision.includes("Exactly two short"), "v7 meminta nama move dua kata");
  assert.ok(
    createAnima.includes("promptMajor(versiPrompt) >= 7"),
    "production harus meminta nama move mulai v7"
  );
  assert.ok(
    createAnima.includes('?? "v7"'),
    "fallback create_anima harus v7 kalau app_config kosong"
  );
  assert.ok(
    evalRunner.includes('promptVersion: "v7"'),
    "eval default harus mengikuti production v7"
  );
  assert.ok(
    evalRunner.includes("promptMajor(args.promptVersion) >= 7"),
    "eval harus meminta nama move mulai v7"
  );
  assert.ok(postprocess.includes("LAYOUT_3X3"), "slicer v7 harus 3x3 tanpa merusak 2x2");

  const filled = assemblePrompt(template, {
    object_label: "handheld console",
    creature_brief: "a pocket console creature",
    character_direction: "compact, playful, and object-led",
    signature_features: ["d-pad becomes a face plate", "shoulder buttons become ears"],
    surface_finish: "painted plastic shell",
    damage_hints: ["scuffed shoulder button", "hairline crack on the shell"],
    strike_name: "D-Pad Jab",
    surge_name: "Pocket Beam",
    dominant_colors: ["#c45a4a"],
    stats: { hp: 40, atk: 55, def: 50, spd: 60, special: 70 },
  });
  assert.ok(filled.includes("D-Pad Jab") && filled.includes("Pocket Beam"));
  assert.ok(!filled.includes("{{"));

  const missingMoves = {
    safe: true,
    is_object: true,
    species_key: "console_plastic_handheld",
    stats: { hp: 40, atk: 55, def: 50, spd: 60, special: 70 },
    signature_features: ["d-pad becomes a face plate", "shoulder buttons become ears"],
    surface_finish: "painted plastic",
    damage_hints: ["scuff", "crack"],
    character_direction: "compact",
    creature_brief: "a pocket console creature",
  };
  const checked = validateVision(missingMoves, [], true, true, true);
  assert.ok(checked.issues.includes("strike_name kosong"));
  assert.ok(checked.issues.includes("surge_name kosong"));
}

console.log("26. prompt v8 mengunci kolom kiri agar tidak menoleh ke tengah sheet");
{
  const { readFile } = await import("node:fs/promises");
  const template = await readFile(new URL("../backend/prompts/v8/sprite_sheet.md", import.meta.url), "utf8");
  const evolve = await readFile(
    new URL("../backend/prompts/v8/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const visionV7 = await readFile(new URL("../backend/prompts/v7/vision_system.md", import.meta.url), "utf8");
  const visionV8 = await readFile(new URL("../backend/prompts/v8/vision_system.md", import.meta.url), "utf8");
  const templateV9 = await readFile(new URL("../backend/prompts/v9/sprite_sheet.md", import.meta.url), "utf8");
  const evolveV9 = await readFile(
    new URL("../backend/prompts/v9/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const visionV9 = await readFile(new URL("../backend/prompts/v9/vision_system.md", import.meta.url), "utf8");
  const templateV10 = await readFile(new URL("../backend/prompts/v10/sprite_sheet.md", import.meta.url), "utf8");
  const evolveV10 = await readFile(
    new URL("../backend/prompts/v10/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const visionV10 = await readFile(new URL("../backend/prompts/v10/vision_system.md", import.meta.url), "utf8");
  const templateV11 = await readFile(new URL("../backend/prompts/v11/sprite_sheet.md", import.meta.url), "utf8");
  const evolveV11 = await readFile(
    new URL("../backend/prompts/v11/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const visionV11 = await readFile(new URL("../backend/prompts/v11/vision_system.md", import.meta.url), "utf8");
  const templateV12 = await readFile(new URL("../backend/prompts/v12/sprite_sheet.md", import.meta.url), "utf8");
  const evolveV12 = await readFile(
    new URL("../backend/prompts/v12/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const visionV12 = await readFile(new URL("../backend/prompts/v12/vision_system.md", import.meta.url), "utf8");
  const schemaV7 = await readFile(new URL("../backend/prompts/v7/vision_schema.json", import.meta.url), "utf8");
  const schemaV8 = await readFile(new URL("../backend/prompts/v8/vision_schema.json", import.meta.url), "utf8");
  const schemaV9 = await readFile(new URL("../backend/prompts/v9/vision_schema.json", import.meta.url), "utf8");
  const schemaV10 = await readFile(new URL("../backend/prompts/v10/vision_schema.json", import.meta.url), "utf8");
  const schemaV11 = await readFile(new URL("../backend/prompts/v11/vision_schema.json", import.meta.url), "utf8");
  const schemaV12 = JSON.parse(
    await readFile(new URL("../backend/prompts/v12/vision_schema.json", import.meta.url), "utf8")
  );
  const createAnima = await readFile(
    new URL("../backend/supabase/functions/create_anima/index.ts", import.meta.url),
    "utf8"
  );
  const evalRunner = await readFile(new URL("./run.mjs", import.meta.url), "utf8");

  assert.equal(visionV8, visionV7, "v8 tidak boleh mengubah Vision atau species cache key");
  assert.equal(schemaV8, schemaV7, "v8 tidak boleh mengubah kontrak output Vision");
  assert.equal(visionV9, visionV7, "v9 tidak boleh mengubah Vision atau species cache key");
  assert.equal(schemaV9, schemaV7, "v9 tidak boleh mengubah kontrak output Vision");
  assert.equal(visionV10, visionV7, "v10 tidak boleh mengubah Vision atau species cache key");
  assert.equal(schemaV10, schemaV7, "v10 tidak boleh mengubah kontrak output Vision");
  assert.equal(visionV11, visionV7, "v11 tidak boleh mengubah Vision atau species cache key");
  assert.equal(schemaV11, schemaV7, "v11 tidak boleh mengubah kontrak output Vision");
  assert.equal(promptMajor("v8"), 8);
  assert.equal(promptMajor("v9"), 9);
  assert.equal(promptMajor("v10"), 10);
  assert.equal(promptMajor("v11"), 11);
  assert.equal(promptMajor("v12"), 12);
  for (const prompt of [template, evolve]) {
    assert.ok(prompt.includes("HORIZONTAL FACING LOCK — BATTLE CONTRACT"));
    assert.ok(
      prompt.includes("independent animation frame of ONE character"),
      "v8 wajib menolak komposisi grup yang membuat sel menoleh ke dalam"
    );
    assert.ok(
      prompt.includes("Left-column cells (Idle, Happy, Damaged)"),
      "v8 wajib menyebut kolom kiri sebagai risiko tertinggi"
    );
    assert.ok(
      prompt.includes("Whichever flank is nearer the camera"),
      "v8 wajib mengunci sisi yang dekat ke kamera"
    );
    assert.ok(!prompt.includes("delighted tilt"), "tilt Happy tidak boleh dibaca sebagai yaw");
    assert.ok(
      /TOP LEFT — IDLE[\s\S]{0,400}still facing canvas-left/.test(prompt),
      "Idle wajib mengulang canvas-left di instruksi sel"
    );
    assert.ok(
      /MIDDLE LEFT — HAPPY[\s\S]{0,500}still facing canvas-left/.test(prompt),
      "Happy wajib mengulang canvas-left di instruksi sel"
    );
  }
  for (const prompt of [templateV9, evolveV9]) {
    assert.ok(prompt.includes("NEGATIVE SPACE — MUST REMAIN BACKGROUND"));
    assert.ok(
      /must show the exact\s+chroma background #00FF00/.test(prompt),
      "v9 wajib membuat lubang internal ikut chroma key"
    );
    assert.ok(
      prompt.includes("never across or inside an opening"),
      "v9 wajib melarang keyline putih di negative space"
    );
  }
  for (const prompt of [templateV10, evolveV10]) {
    assert.ok(prompt.includes("WHITE IS NOT A GENERIC ACCENT"));
    assert.ok(
      /each\s+fenestration is a literal hole through the leaf/.test(prompt),
      "v10 wajib menyebut fenestrasi daun secara eksplisit"
    );
    assert.ok(
      /Never draw\s+the white keyline around internal holes/.test(prompt),
      "v10 wajib membatasi matte ke outline terluar"
    );
  }
  for (const prompt of [templateV11, evolveV11]) {
    assert.ok(prompt.includes("EDGES — DARK CONTOUR DIRECTLY AGAINST GREEN"));
    assert.ok(
      /Do NOT draw any white or off-white keyline/.test(prompt),
      "v11 wajib melarang matte putih di seluruh sheet"
    );
    assert.ok(
      !prompt.includes("White keyline around") && !prompt.includes("technical outer keyline"),
      "v11 tidak boleh menyisakan instruksi positif white keyline"
    );
  }
  for (const prompt of [templateV12, evolveV12]) {
    assert.ok(prompt.includes("VFX DIVERSITY CONTRACT"));
    assert.ok(prompt.includes("12% safe envelope"));
    assert.ok(prompt.includes("motion lines") && prompt.includes("tiny debris"));
    assert.ok(prompt.includes("{{strike_vfx_brief}}") && prompt.includes("{{surge_vfx_motion}}"));
    assert.ok(
      /Never default to a round\s+fireball/.test(prompt),
      "v12 wajib melarang default fireball tanpa melarang aksen Battle"
    );
  }
  assert.ok(visionV12.includes("Battle-effect plan"));
  assert.ok(schemaV12.properties.strike_vfx && schemaV12.properties.surge_vfx);
  const vfxChecked = validateVision({
    safe: true,
    is_object: true,
    reject_reason: null,
    species_key: "shoe_fabric_running",
    stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
    signature_features: ["tread sole", "long lace"],
    suggested_name: "Treadra",
    surface_finish: "woven fabric and rubber",
    damage_hints: ["frayed lace", "scuffed sole"],
    character_direction: "agile",
    strike_name: "Tread Snap",
    surge_name: "Lace Cyclone",
    strike_vfx: { form: "stamp", motion: "impact", brief: "A tread stamp snaps on target." },
    surge_vfx: { form: "tether", motion: "sweep", brief: "A lace tether sweeps across target." },
  }, [], true, true, true, true);
  assert.deepEqual(vfxChecked.issues, []);
  assert.equal(vfxChecked.vision.strike_vfx.motion, "impact");
  assert.equal(vfxChecked.vision.surge_vfx.motion, "sweep");
  assert.ok(!assemblePrompt(templateV12, vfxChecked.vision).includes("{{"));
  assert.ok(
    createAnima.includes('?? "v7"'),
    "fallback production tetap v7 sampai v8 dipromosikan"
  );
  assert.ok(
    evalRunner.includes('promptVersion: "v7"'),
    "eval default tetap v7 sampai v8 dipromosikan"
  );
}

console.log("27. katalog, reward tier, item Battle, dan sheet toko");
{
  assert.equal(STARTER_BITS, 50);
  assert.equal(BATTLE_BITS_CAP, 100);
  assert.equal(CATALOG_ITEMS.length, 18);
  assert.equal(CATALOG_ITEMS.filter((item) => item.use_type === "food").length, 9);
  assert.deepEqual(
    CATALOG_ITEMS.filter((item) => item.use_type === "food").map((item) => item.price),
    [1, 2, 2, 3, 4, 5, 6, 8, 10]
  );
  assert.equal(CATALOG_ITEMS.filter((item) => item.use_type === "energy").length, 2);
  assert.equal(CATALOG_ITEMS.filter((item) => item.use_type === "battle").length, 7);
  assert.equal(rewardTierFromRatio(0.94), "favorable");
  assert.equal(rewardTierFromRatio(0.95), "even");
  assert.equal(rewardTierFromRatio(1.04), "even");
  assert.equal(rewardTierFromRatio(1.05), "tough");
  assert.equal(rewardTierFromRatio(1.09), "tough");
  assert.equal(rewardTierFromRatio(1.1), "formidable");
  assert.equal(bitsForTier("favorable", -1), 5);
  assert.equal(bitsForTier("even", 0), 8);
  assert.equal(bitsForTier("tough", 1), 12);
  assert.equal(bitsForTier("formidable", 1), 16);

  const twin = {
    species_key: "twin",
    color_bucket: "blue",
    stage: 1,
    element: "metal",
    base_stats: { hp: 50, atk: 50, def: 50, spd: 50, special: 50 },
  };
  const evenPreview = battleRewardPreview(twin, twin, "reward-seed");
  assert.equal(evenPreview.tier, "even");
  assert.equal(evenPreview.bits, bitsForTier("even", evenPreview.roll));
  assert.deepEqual(battleRewardPreview(twin, twin, "reward-seed"), evenPreview);

  const weak = { ...twin, species_key: "weak", base_stats: { hp: 10, atk: 10, def: 10, spd: 10, special: 10 } };
  const strong = { ...twin, species_key: "strong", base_stats: { hp: 95, atk: 95, def: 95, spd: 95, special: 95 } };
  assert.equal(battleRewardPreview(strong, weak, "fav").tier, "favorable");
  assert.equal(battleRewardPreview(weak, strong, "form").tier, "formidable");

  const fighter = {
    species_key: "item-player",
    color_bucket: "blue",
    stage: 1,
    element: "metal",
    base_stats: { hp: 50, atk: 50, def: 50, spd: 20, special: 50 },
  };
  const rival = {
    species_key: "item-bot",
    color_bucket: "green",
    stage: 1,
    element: "plant",
    base_stats: { hp: 50, atk: 80, def: 50, spd: 50, special: 50 },
  };

  const hurt = createBattleState({ player: fighter, bot: rival, seed: "heal" });
  hurt.player.hp = 100;
  const healed = resolveTurn(hurt, "item", "heal-key", "vital_patch");
  assert.equal(healed.events[0]?.type, "item");
  assert.equal(healed.events[0].effect, "heal_hp_pct");
  assert.equal(healed.events[0].effect_value, 30);
  assert.equal(healed.events[0].hp, 100 + Math.trunc(hurt.player.max_hp * 0.3));
  assert.throws(() => resolveTurn(healed.state, "item", "second", "vital_patch"), /ITEM_ALREADY_USED/);

  const power = resolveTurn(
    createBattleState({ player: fighter, bot: rival, seed: "atk" }),
    "item",
    "atk-key",
    "power_chip"
  );
  assert.equal(power.state.player.atk_mult, 1.35);

  const lens = resolveTurn(
    createBattleState({ player: fighter, bot: rival, seed: "spec" }),
    "item",
    "spec-key",
    "surge_lens"
  );
  assert.equal(lens.state.player.special_mult, 1.35);

  const aegis = resolveTurn(
    createBattleState({ player: fighter, bot: rival, seed: "guard-item" }),
    "item",
    "aegis-key",
    "aegis_plate"
  );
  assert.equal(aegis.state.player.incoming_mult, 0.75);

  const coiled = resolveTurn(
    createBattleState({
      player: { ...fighter, base_stats: { ...fighter.base_stats, spd: 40 } },
      bot: rival,
      seed: "spd",
    }),
    "item",
    "coil-key",
    "tempo_coil"
  );
  assert.equal(coiled.state.player.spd, Math.trunc(40 * 1.4));
  const afterCoil = resolveTurn(coiled.state, "strike", "after-coil");
  assert.equal(
    afterCoil.events.find((event) => event.type === "attack")?.actor,
    "player",
    "Tempo Coil harus membalik initiative sebelum serangan"
  );

  const capsule = resolveTurn(
    createBattleState({ player: fighter, bot: rival, seed: "pp" }),
    "item",
    "pp-key",
    "pp_capsule"
  );
  assert.equal(capsule.state.player.momentum_max, 5);
  assert.equal(capsule.state.player.momentum, 5);
  assert.equal(catalogItem("pp_capsule").effect_value, 2);

  const strikeState = createBattleState({ player: fighter, bot: rival, seed: "shield-cmp" });
  const shieldState = createBattleState({ player: fighter, bot: rival, seed: "shield-cmp" });
  const struck = resolveTurn(strikeState, "strike", "same-key");
  const shielded = resolveTurn(shieldState, "item", "same-key", "phase_shield");
  const botStrike = struck.events.find((event) => event.type === "attack" && event.actor === "bot");
  const botShielded = shielded.events.find((event) => event.type === "attack" && event.actor === "bot");
  assert.equal(shielded.events[0]?.type, "item");
  assert.ok(botStrike && botShielded, "bot tetap menyerang saat pemain memakai item");
  assert.equal(botShielded.damage, Math.max(1, Math.trunc(botStrike.damage * 0.2)));
  assert.equal(shielded.state.player.shield_charges, 0);

  assert.throws(() => resolveTurn(createBattleState({ player: fighter, bot: rival, seed: "food" }), "item", "bad", "byte_berry"), /INVALID_ITEM/);

  const { readFile } = await import("node:fs/promises");
  for (const name of ["food_sheet.png", "item_sheet.png"]) {
    const png = await readFile(new URL(`../game/assets/catalog/${name}`, import.meta.url));
    const img = await Image.decode(png);
    assert.equal(img.width, 1024, `${name} harus 1024 lebar`);
    assert.equal(img.height, 1024, `${name} harus 1024 tinggi`);
    const cell = Math.floor(1024 / 3);
    for (let index = 0; index < 9; index += 1) {
      const col = index % 3;
      const row = Math.trunc(index / 3);
      let filled = 0;
      let vapor = 0;
      for (let y = 0; y < cell; y += 1) {
        for (let x = 0; x < cell; x += 1) {
          const o = ((row * cell + y) * img.width + (col * cell + x)) * 4;
          const r = img.bitmap[o];
          const g = img.bitmap[o + 1];
          const b = img.bitmap[o + 2];
          const a = img.bitmap[o + 3];
          if (a > 0 && !isKeyColor(r, g, b)) filled += 1;
          if (a > 0 && isCatalogKeyVapor(r, g, b)) vapor += 1;
        }
      }
      assert.ok(filled > 200, `${name} sel ${index} harus berisi ikon`);
      if (name === "food_sheet.png") {
        assert.ok(vapor < 80, `${name} sel ${index} tidak boleh menyisakan uap green-screen (${vapor})`);
      }
    }
  }
}

// Menulis sheet hasil pipeline ke folder, untuk dibaca sisi Godot. Ini yang
// menutup kontrak antara Node dan Godot tanpa memanggil API berbayar:
//
//   node eval/selftest.mjs --emit /tmp/scanima_e2e
//   godot --headless --path game --script res://tests/test_sprite_slicing.gd \
//       -- --manifest=/tmp/scanima_e2e/manifest.json
console.log("28. Vision v13 typing, fauna v14/v15, facing/gaze v16, dan capture privat");
{
  const { readFile } = await import("node:fs/promises");
  const visionV13 = await readFile(new URL("../backend/prompts/v13/vision_system.md", import.meta.url), "utf8");
  const schemaV13Source = await readFile(
    new URL("../backend/prompts/v13/vision_schema.json", import.meta.url),
    "utf8"
  );
  const schemaV13 = JSON.parse(schemaV13Source);
  const templateV13 = await readFile(new URL("../backend/prompts/v13/sprite_sheet.md", import.meta.url), "utf8");
  const evolveV13 = await readFile(
    new URL("../backend/prompts/v13/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const faunaV13 = await readFile(new URL("../backend/prompts/v13/sprite_sheet_fauna.md", import.meta.url), "utf8");
  const visionV14 = await readFile(new URL("../backend/prompts/v14/vision_system.md", import.meta.url), "utf8");
  const schemaV14Source = await readFile(
    new URL("../backend/prompts/v14/vision_schema.json", import.meta.url),
    "utf8"
  );
  const templateV14 = await readFile(new URL("../backend/prompts/v14/sprite_sheet.md", import.meta.url), "utf8");
  const evolveV14 = await readFile(
    new URL("../backend/prompts/v14/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const faunaV14 = await readFile(new URL("../backend/prompts/v14/sprite_sheet_fauna.md", import.meta.url), "utf8");
  const faunaV15 = await readFile(new URL("../backend/prompts/v15/sprite_sheet_fauna.md", import.meta.url), "utf8");
  const visionV16 = await readFile(new URL("../backend/prompts/v16/vision_system.md", import.meta.url), "utf8");
  const schemaV16Source = await readFile(
    new URL("../backend/prompts/v16/vision_schema.json", import.meta.url),
    "utf8"
  );
  const templateV16 = await readFile(new URL("../backend/prompts/v16/sprite_sheet.md", import.meta.url), "utf8");
  const faunaV16 = await readFile(new URL("../backend/prompts/v16/sprite_sheet_fauna.md", import.meta.url), "utf8");
  const evolveV16 = await readFile(
    new URL("../backend/prompts/v16/sprite_sheet_evolve.md", import.meta.url),
    "utf8"
  );
  const chapterAnimaPrompt = await readFile(
    new URL("../backend/prompts/chapter_factory/anima_sheet.md", import.meta.url),
    "utf8"
  );
  const chapterZonePrompt = await readFile(
    new URL("../backend/prompts/chapter_factory/zone_art.md", import.meta.url),
    "utf8"
  );
  const manualChapterGuide = await readFile(
    new URL("../docs/10-manual-chapter-assets.md", import.meta.url),
    "utf8"
  );
  const createAnima = await readFile(
    new URL("../backend/supabase/functions/create_anima/index.ts", import.meta.url),
    "utf8"
  );
  const evalRun = await readFile(new URL("./run.mjs", import.meta.url), "utf8");
  const finalizeSheet = await readFile(
    new URL("../backend/supabase/functions/_shared/finalize_sheet.ts", import.meta.url),
    "utf8"
  );

  assert.equal(promptMajor("v13"), 13);
  assert.equal(promptMajor("v14"), 14);
  assert.equal(promptMajor("v15"), 15);
  assert.equal(promptMajor("v16"), 16);
  assert.ok(schemaV13.properties.subject_kind);
  assert.ok(schemaV13.properties.secondary_element);
  assert.equal(schemaV13.properties.element.enum.length, 18);
  assert.ok(visionV13.includes("subject_kind"));
  assert.ok(visionV13.includes("animal_distress"));
  assert.ok(faunaV13.includes("Show **fatigue and"));
  assert.ok(/BOTTOM LEFT — DAMAGED[\s\S]{0,400}Never.*blood/.test(faunaV13));
  assert.ok(templateV13.includes("VFX DIVERSITY CONTRACT"));
  assert.equal(visionV14, visionV13, "v14 tidak mengubah Vision");
  assert.equal(schemaV14Source, schemaV13Source, "v14 tidak mengubah schema Vision");
  assert.equal(templateV14, templateV13, "v14 tidak mengubah prompt object");
  assert.equal(evolveV14, evolveV13, "v14 tidak mengubah prompt evolve");
  assert.ok(faunaV14.includes("SCANIMA MONSTERIZATION FLOOR"));
  assert.ok(faunaV14.includes("PRESERVE RECOGNITION, NOT REALISM"));
  assert.ok(faunaV14.includes("FINAL SILENT STYLE CHECK"));
  assert.ok(faunaV14.includes("Idle cannot be mistaken for a realistic wildlife or pet illustration"));
  assert.ok(!faunaV14.includes("anatomy-led proportions faithful"));
  assert.ok(/BOTTOM LEFT — DAMAGED[\s\S]{0,400}Never.*blood/.test(faunaV14));
  assert.ok(faunaV15.includes("MANDATORY MONSTER IDENTITY LAYER"));
  assert.ok(faunaV15.includes("PROPORTION BREAK"));
  assert.ok(faunaV15.includes("LANDMARK EVOLUTION"));
  assert.ok(faunaV15.includes("ORIGINAL ORGANIC MOTIF"));
  assert.ok(faunaV15.includes("with only anime eyes, cleaner linework, extra"));
  assert.ok(faunaV15.includes("Chroma green is a transport color only"));
  assert.ok(/BOTTOM LEFT — DAMAGED[\s\S]{0,400}Never.*blood/.test(faunaV15));
  assert.equal(visionV16, visionV13, "v16 tidak mengubah Vision");
  assert.equal(schemaV16Source, schemaV13Source, "v16 tidak mengubah schema Vision");
  for (const prompt of [templateV16, faunaV16, evolveV16]) {
    assert.ok(prompt.includes("HORIZONTAL FACING LOCK — HOME AND BATTLE CONTRACT"));
    assert.ok(prompt.includes("EYE GAZE LOCK"));
    assert.ok(prompt.includes("ONE shared target in open"));
    assert.match(prompt, /Never look\s+at the viewer/);
    assert.ok(prompt.includes("Sleep keeps every eye fully closed"));
    assert.ok(prompt.includes("client mirrors the complete sheet"));
    assert.ok(prompt.includes("VFX DIVERSITY CONTRACT"));
    assert.ok(prompt.includes("12% safe envelope"));
    assert.ok(prompt.includes("BACKGROUND — TECHNICAL TRANSPORT LAYER"));
    assert.ok(prompt.includes("EDGES — DARK CONTOUR DIRECTLY AGAINST GREEN"));
    assert.ok(/TOP LEFT — IDLE[\s\S]{0,400}canvas-left/.test(prompt));
    assert.ok(/MIDDLE LEFT — HAPPY[\s\S]{0,500}canvas-left/.test(prompt));
    assert.ok(/BOTTOM LEFT — DAMAGED[\s\S]{0,500}canvas-left/.test(prompt));
  }
  assert.ok(faunaV16.includes("MANDATORY MONSTER IDENTITY LAYER"));
  assert.ok(chapterAnimaPrompt.includes("both pupils focus on the same canvas-left target"));
  assert.ok(
    /Expedition\s+combat arena/.test(chapterZonePrompt),
    "prompt zona Replicate wajib memakai backdrop Battle, bukan peta node"
  );
  assert.ok(
    chapterZonePrompt.includes("lower 22–26% is one continuous solid floor"),
    "prompt zona wajib mengunci pita lantai tempur"
  );
  assert.ok(
    chapterZonePrompt.includes("no liquid, lava, syrup, rails, gutters, chasms"),
    "prompt zona wajib menolak hazard di bawah kaki"
  );
  assert.doesNotMatch(
    chapterZonePrompt,
    /route-like lanes|readable path lanes|node map/i,
    "prompt zona tidak boleh kembali ke wording peta node"
  );
  const manualZoneTemplate =
    manualChapterGuide.match(/### Template zone[\s\S]*?(?=### Template Trophy)/)?.[0] ?? "";
  assert.ok(
    manualZoneTemplate.includes("Expedition combat arena"),
    "template zona manual wajib memakai backdrop Battle"
  );
  assert.ok(
    manualZoneTemplate.includes("lower 22–26% is one continuous solid floor"),
    "template zona manual wajib mengunci pita lantai"
  );
  assert.doesNotMatch(
    manualZoneTemplate,
    /route-like lanes|readable path lanes/i,
    "template zona manual tidak boleh meminta lane peta"
  );
  const manualSugarworksZones =
    manualChapterGuide.match(/### 10\. Zone 1[\s\S]*?(?=### 13\. Boss Seeker)/)?.[0] ?? "";
  assert.ok(
    manualSugarworksZones.includes("continuous solid floor"),
    "Gumdrop Yard wajib punya lantai padat"
  );
  assert.ok(
    manualSugarworksZones.includes("caramel-slab work floor"),
    "Caramel Foundry wajib punya lantai kerja padat"
  );
  assert.ok(
    manualSugarworksZones.includes("broad peppermint-stone"),
    "Peppermint Furnace wajib punya forecourt padat"
  );
  assert.doesNotMatch(
    manualSugarworksZones,
    /route-like lanes|narrow syrup runnels/i,
    "prompt zona Sugarworks tidak boleh meminta got atau lane peta"
  );
  assert.equal(
    manualChapterGuide.match(/Every open-eye pose/g)?.length,
    9,
    "sembilan prompt manual Anima wajib mengulang gaze lock lokal"
  );
  assert.ok(
    manualChapterGuide.includes("recognizable as a solid black silhouette"),
    "manual Boss Seeker lock wajib silhouette-first"
  );
  assert.ok(
    manualChapterGuide.includes("never make every Boss Seeker a young"),
    "manual Boss Seeker lock wajib menuntut variasi antar-chapter"
  );
  const manualConfectionerPrompt =
    manualChapterGuide.match(/### 13\. Boss Seeker[\s\S]*?(?=### 14\.)/)?.[0] ?? "";
  assert.ok(
    manualConfectionerPrompt.includes("youngest archive curator"),
    "prompt Confectioner wajib membawa background Curator"
  );
  assert.ok(
    manualConfectionerPrompt.includes("octagonal dark-plum recipe folio"),
    "prompt Confectioner wajib memakai folio, bukan alat dapur"
  );
  assert.ok(
    manualConfectionerPrompt.includes("cells 1 through 8 keep the exact same three-quarter"),
    "delapan pose penuh Confectioner wajib memakai angle lock yang sama"
  );
  assert.ok(
    manualConfectionerPrompt.includes("both eyes remain visible while only the pupils turn"),
    "portrait dialog Confectioner wajib menatap pemain tanpa mengubah angle"
  );
  assert.ok(
    /front-facing\s+passport portrait/.test(manualConfectionerPrompt),
    "nama pose Profile tidak boleh dibaca sebagai side profile atau front-facing penuh"
  );
  assert.doesNotMatch(
    manualConfectionerPrompt,
    /whisk-baton|Graphic Commandant|mid-40s/i,
    "prompt Confectioner tidak boleh membawa desain lama"
  );
  const manualSugarworksCorePrompt =
    manualChapterGuide.match(/### 14\. Trophy[\s\S]*?(?=## Lokasi file)/)?.[0] ?? "";
  assert.ok(
    manualSugarworksCorePrompt.includes("two-layer Chapter Core v3 grammar"),
    "Trophy manual wajib memakai sistem dua lapis Chapter Core"
  );
  assert.ok(
    /Generate\s+the Inner Core only/.test(manualSugarworksCorePrompt),
    "model manual tidak boleh menggambar ulang canonical Vessel"
  );
  assert.ok(
    manualSugarworksCorePrompt.includes("point-top Hexagonal Vessel"),
    "prompt wajib menjelaskan canonical Vessel ditambahkan sesudah generation"
  );
  assert.ok(
    manualSugarworksCorePrompt.includes("broad shallow concave"),
    "Sugarfold Core wajib punya silhouette motif chapter-specific"
  );
  assert.ok(
    manualSugarworksCorePrompt.includes("eight to ten large"),
    "Sugarfold Core wajib sederhana dan bounded"
  );
  assert.ok(
    manualSugarworksCorePrompt.includes("not one continuous ribbon, letter"),
    "internal construction tidak boleh kembali menjadi huruf S"
  );
  assert.ok(
    manualSugarworksCorePrompt.includes("No glass shell, orb, crystal"),
    "Inner Core tidak boleh menggambar ulang Vessel atau artifact scene"
  );

  const objectVision = {
    safe: true,
    is_object: true,
    subject_kind: "object",
    reject_reason: null,
    species_key: "mug_ceramic_handled",
    color_bucket: "neutral_light",
    element: "ceramic",
    secondary_element: "flow",
    rarity: 1,
    stats: { hp: 50, atk: 30, def: 60, spd: 40, special: 35 },
    creature_brief: "A floating mug creature with a handle tail and rim crown.",
    signature_features: ["handle tail-fin", "open rim crown"],
    surface_finish: "smooth glazed ceramic",
    damage_hints: ["hairline glaze crack", "small rim chip"],
    character_direction: "soft and friendly",
    suggested_name: "Mugra",
    strike_name: "Rim Toss",
    surge_name: "Glaze Burst",
    strike_vfx: { form: "arc", motion: "sweep", brief: "A glazed crescent sweeps across target." },
    surge_vfx: { form: "ring", motion: "bloom", brief: "Glaze rings bloom from the target." },
  };
  const typed = validateVision(objectVision, [], true, true, true, true, true, true, true);
  assert.equal(typed.gate, "passed");
  assert.equal(typed.vision.element, "ceramic");
  assert.equal(typed.vision.secondary_element, "flow");

  const animalVision = {
    ...objectVision,
    species_key: "cat_feline_tabby",
    element: "plant",
    secondary_element: null,
    subject_kind: "animal",
    object_label: "tabby cat",
    surface_finish: "short tabby fur",
    damage_hints: ["drooped ear", "dull ruffled fur"],
  };
  const animalFixed = validateVision(animalVision, [], true, true, true, true, true, true, true);
  assert.equal(animalFixed.vision.element, "fauna", "hewan wajib dinormalisasi ke fauna");

  const blockedAnimal = validateVision(animalVision, [], true, true, true, true, true, false, true);
  assert.equal(blockedAnimal.gate, "rejected");
  assert.equal(blockedAnimal.reason, "live_animal");

  const bundel = await (await import("../backend/tools/bundle_prompts.mjs")).buildBundle();
  assert.equal(spriteSheetTemplate(bundel.v13, "animal"), bundel.v13.sprite_sheet_fauna);
  assert.equal(spriteSheetTemplate(bundel.v13, "object"), bundel.v13.sprite_sheet);
  assert.ok(!assemblePrompt(bundel.v13.sprite_sheet_fauna, animalFixed.vision).includes("{{"));
  assert.equal(spriteSheetTemplate(bundel.v14, "animal"), bundel.v14.sprite_sheet_fauna);
  assert.equal(spriteSheetTemplate(bundel.v14, "object"), bundel.v14.sprite_sheet);
  assert.ok(!assemblePrompt(bundel.v14.sprite_sheet_fauna, animalFixed.vision).includes("{{"));
  assert.equal(spriteSheetTemplate(bundel.v15, "animal"), bundel.v15.sprite_sheet_fauna);
  assert.equal(spriteSheetTemplate(bundel.v15, "object"), bundel.v15.sprite_sheet);
  assert.equal(bundel.v15.vision_system, bundel.v13.vision_system, "v15 tidak mengubah Vision");
  assert.deepEqual(bundel.v15.vision_schema, bundel.v13.vision_schema, "v15 tidak mengubah schema Vision");
  assert.equal(bundel.v15.sprite_sheet_evolve, bundel.v13.sprite_sheet_evolve, "v15 tidak mengubah prompt evolve");
  assert.ok(!assemblePrompt(bundel.v15.sprite_sheet_fauna, animalFixed.vision).includes("{{"));
  assert.equal(spriteSheetTemplate(bundel.v16, "animal"), bundel.v16.sprite_sheet_fauna);
  assert.equal(spriteSheetTemplate(bundel.v16, "object"), bundel.v16.sprite_sheet);
  assert.equal(bundel.v16.vision_system, bundel.v15.vision_system, "v16 tidak mengubah Vision");
  assert.deepEqual(bundel.v16.vision_schema, bundel.v15.vision_schema, "v16 tidak mengubah schema Vision");
  assert.ok(!assemblePrompt(bundel.v16.sprite_sheet, typed.vision).includes("{{"));
  assert.ok(!assemblePrompt(bundel.v16.sprite_sheet_fauna, animalFixed.vision).includes("{{"));

  assert.ok(createAnima.includes("feature_unique_generation"));
  assert.ok(createAnima.includes("claim_capture"));
  assert.ok(createAnima.includes("spriteSheetTemplate"));
  assert.ok(createAnima.includes("useUniqueCapture"));
  assert.ok(
    evalRun.includes("spriteSheetTemplate(prompts, checked.vision.subject_kind)"),
    "eval memilih template object/fauna dari subject_kind"
  );
  assert.ok(
    /validateVision\([\s\S]{0,500}useV13,\s+useV13,\s+useV13,/.test(evalRun),
    "eval v13+ mengizinkan fauna dan melewati dedup species"
  );
  assert.ok(finalizeSheet.includes("anima_sheets"));
  assert.ok(finalizeSheet.includes("typing_version"));
  assert.ok(finalizeSheet.includes("isPrivateCapture"));
}

console.log("29. Legacy typing inference + privatization audit planner");
{
  const {
    inferCanonicalLegacyTyping,
    gatherLegacyTypingCorpus,
    stableStringify,
  } = await import("../backend/supabase/functions/_shared/legacy_typing.mjs");
  const {
    buildAuditReport,
    auditReportText,
    privateSheetPath,
    isAlreadyMigrated,
  } = await import("../backend/supabase/functions/_shared/legacy_art_migration.mjs");

  const mug = inferCanonicalLegacyTyping({
    existingElement: "flow",
    vision: {
      object_label: "ceramic mug",
      species_key: "mug_ceramic_handled",
      surface_finish: "smooth glazed ceramic",
    },
  });
  assert.equal(mug.element, "ceramic");
  assert.equal(mug.secondary_element, "flow");

  const mouse = inferCanonicalLegacyTyping({
    existingElement: "tech",
    vision: {
      object_label: "wired computer mouse",
      species_key: "mouse_plastic",
      surface_finish: "molded plastic",
    },
  });
  assert.equal(mouse.element, "plastic");
  assert.equal(mouse.secondary_element, "spark");

  const book = inferCanonicalLegacyTyping({
    existingElement: "cloth",
    vision: {
      object_label: "hardcover notebook",
      surface_finish: "cardboard cover",
    },
  });
  assert.equal(book.element, "paper");
  assert.equal(book.secondary_element, null, "cloth legacy tidak boleh tetap primary/secondary");

  const unknown = inferCanonicalLegacyTyping({
    existingElement: "stone",
    vision: { object_label: "mysterious relic", species_key: "relic_unknown" },
  });
  assert.equal(unknown.element, "stone");
  assert.equal(unknown.reason, "legacy:ambiguous");

  assert.ok(
    gatherLegacyTypingCorpus({ species_key: "mouse_plastic", object_label: "computer mouse" })
      .includes("mouse plastic"),
    "corpus harus menggabungkan species_key dan object_label",
  );

  const owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const animaId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  assert.equal(
    privateSheetPath(owner, animaId, "deadbeefcafebabe.png"),
    `${owner}/${animaId}/deadbeefcafebabe.png`,
  );

  const report = buildAuditReport({
    animas: [{
      id: animaId,
      owner_id: owner,
      species_key: "mug_ceramic_handled",
      color_bucket: "gray",
      stage: 1,
      status: "ready",
      element: "flow",
      typing_version: 1,
      sheet_path: null,
    }],
    libraryRows: [{
      species_key: "mug_ceramic_handled",
      color_bucket: "gray",
      stage: 1,
      sheet_path: "deadbeefcafebabe.png",
      manifest: { sheet: "deadbeefcafebabe.png", poses: {} },
    }],
    generations: [{
      id: "gen-1",
      anima_id: animaId,
      created_at: "2026-08-15T00:00:00Z",
      vision_result: { object_label: "ceramic mug", surface_finish: "glazed ceramic" },
    }],
  });
  assert.equal(report.summary.pending, 1);
  assert.equal(report.rows[0].canonical.element, "ceramic");
  assert.equal(report.rows[0].source.target_sheet_path, `${owner}/${animaId}/deadbeefcafebabe.png`);

  const migrated = {
    id: animaId,
    owner_id: owner,
    species_key: "mug_ceramic_handled",
    color_bucket: "gray",
    stage: 1,
    status: "ready",
    element: "ceramic",
    secondary_element: "flow",
    typing_version: 2,
    sheet_path: `${owner}/${animaId}/deadbeefcafebabe.png`,
  };
  assert.ok(isAlreadyMigrated(migrated));
  const doneReport = buildAuditReport({
    animas: [migrated],
    libraryRows: [],
    generations: [],
    mode: "audit",
  });
  assert.equal(doneReport.summary.ready_for_legacy_private, true);

  const textOnce = auditReportText(report);
  const textTwice = auditReportText(buildAuditReport({
    animas: report.rows.map((row) => ({
      id: row.anima_id,
      owner_id: row.owner_id,
      species_key: row.species_key,
      color_bucket: row.color_bucket,
      stage: row.stage,
      status: "ready",
      element: row.legacy.element,
      typing_version: row.legacy.typing_version,
      sheet_path: row.legacy.sheet_path,
    })),
    libraryRows: [{
      species_key: "mug_ceramic_handled",
      color_bucket: "gray",
      stage: 1,
      sheet_path: "deadbeefcafebabe.png",
      manifest: { sheet: "deadbeefcafebabe.png", poses: {} },
    }],
    generations: [{
      id: "gen-1",
      anima_id: animaId,
      created_at: "2026-08-15T00:00:00Z",
      vision_result: { object_label: "ceramic mug", surface_finish: "glazed ceramic" },
    }],
  }));
  assert.equal(textOnce, textTwice, "audit report harus deterministik");

  assert.ok(stableStringify({ b: 1, a: 2 }).includes('"a"'));
}

console.log("30. helper _shared berklien selalu dipanggil dengan client-nya");
{
  // Deploy Edge Function tidak melakukan type check, jadi argumen yang hilang
  // hanya terlihat sebagai kegagalan runtime di tangan pemain. Terukur: satu
  // `withSignedRoster(candidate.opponent_snapshot)` tanpa `db` membuat setiap
  // "Find New Rivals" menjawab INVALID_TEAM_SNAPSHOT, sebab snapshot-nya masuk
  // ke parameter client dan parameter value menjadi undefined.
  //
  // ponytail: pemindai sumber, bukan type checker. Plafon: hanya helper yang
  // parameter pertamanya SupabaseClient; ganti dengan `deno check` begitu Deno
  // tersedia di mesin build.
  const { readFile, readdir } = await import("node:fs/promises");
  const functionsDir = new URL("../backend/supabase/functions/", import.meta.url);
  const sources = [];
  const walk = async (dir) => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) await walk(new URL(`${entry.name}/`, dir));
      else if (/\.(ts|mjs)$/.test(entry.name)) sources.push(new URL(entry.name, dir));
    }
  };
  await walk(functionsDir);
  assert.ok(sources.length > 10, `hanya ${sources.length} sumber terpindai, penjelajahannya salah`);

  const bodies = new Map();
  for (const file of sources) bodies.set(file, await readFile(file, "utf8"));

  const clientFirst = new Set();
  for (const [file, body] of bodies) {
    if (!file.pathname.includes("/_shared/")) continue;
    for (const match of body.matchAll(
      /export\s+(?:async\s+)?function\s+(\w+)\(\s*\n?\s*\w+\s*:\s*SupabaseClient/g
    )) {
      clientFirst.add(match[1]);
    }
  }
  assert.ok(
    clientFirst.has("withSignedRoster") && clientFirst.size >= 3,
    `helper berklien tidak terdeteksi: ${[...clientFirst].join(", ")}`
  );

  for (const [file, body] of bodies) {
    if (file.pathname.includes("/_shared/")) continue;
    for (const name of clientFirst) {
      for (const match of body.matchAll(new RegExp(`\\b${name}\\(([^,)]*)[,)]`, "g"))) {
        const first = match[1].trim();
        assert.match(
          first,
          /^(db|client|admin)\b/,
          `${name}() di ${file.pathname.split("/functions/")[1]} harus menerima client ` +
            `Supabase di argumen pertama, bukan "${first}"`
        );
      }
    }
  }
}

console.log("31. idempotency_key tidak lagi menggerakkan RNG turn");
{
  // Sebelum rules_version 2, seed turn adalah `seed:turn:idempotency_key` dan
  // key itu dipilih client. Pemain bisa mengaduk key sampai crit-nya keluar.
  // Sesi lama tetap wajib memakai formula lamanya, karena battle_turns sudah
  // menyimpan response yang dihitung dengan seed itu.
  const fighter = {
    base_stats: { hp: 60, atk: 55, def: 45, spd: 50, special: 55 },
    element: "metal",
    level: 8,
  };
  const fresh = createBattleState({ player: fighter, bot: fighter, seed: "rng-gate" });
  assert.equal(fresh.rules_version, RULES_VERSION);
  assert.equal(turnSeed(fresh, "apa-pun"), "rng-gate:1");

  const a = resolveTurn(fresh, "strike", "key-aaaaaaaa");
  const b = resolveTurn(fresh, "strike", "key-zzzzzzzz");
  assert.deepEqual(a.state, b.state, "dua key berbeda harus memberi state identik");
  assert.deepEqual(a.events, b.events, "dua key berbeda harus memberi events identik");
  assert.equal(a.bot_action, b.bot_action);

  const legacy = { ...structuredClone(fresh) };
  delete legacy.rules_version;
  assert.equal(turnSeed(legacy, "key-aaaaaaaa"), "rng-gate:1:key-aaaaaaaa");
  const legacyA = resolveTurn(legacy, "strike", "key-aaaaaaaa");
  const legacyB = resolveTurn(legacy, "strike", "key-zzzzzzzz");
  assert.notDeepEqual(
    legacyA.events,
    legacyB.events,
    "state lama harus tetap memakai formula lama supaya replay-nya cocok"
  );

  const roster = [{ ...fighter, anima_id: "a", name: "A" }, { ...fighter, anima_id: "b", name: "B" }];
  const team = createTeamBattleState({ player: roster, opponent: roster, seed: "team-rng-gate" });
  assert.equal(team.rules_version, RULES_VERSION);
  assert.deepEqual(
    resolveTeamTurn(team, "strike", "key-aaaaaaaa").events,
    resolveTeamTurn(team, "strike", "key-zzzzzzzz").events,
    "Team Battle juga tidak boleh menggerakkan RNG dari key client"
  );
}

console.log("32. konstanta simulasi client tidak boleh menyimpang dari _shared");
{
  // Client menjalankan resolver yang sama secara lokal supaya animasi mulai di
  // frame yang sama dengan tap. `test_battle_sim_parity.gd` membuktikan
  // perilakunya identik, tetapi test itu butuh Godot. Pemindai ini menangkap
  // konstanta yang diubah di satu sisi saja pada gate Node yang gratis.
  //
  // ponytail: pemindai teks, bukan parser GDScript. Plafon: hanya const skalar
  // dan tiga tabel elemen; perilaku selengkapnya dijaga vektor paritas.
  const { readFile } = await import("node:fs/promises");
  const gdSource = async (path) =>
    readFile(new URL(`../game/scripts/${path}`, import.meta.url), "utf8");

  const scalarConst = (body, name) => {
    const match = body.match(
      new RegExp(`^const\\s+${name}\\s*(?::\\s*\\w+\\s*)?:?=\\s*(-?[\\d.]+)\\s*$`, "m")
    );
    assert.ok(match, `const ${name} tidak ditemukan di sumber GDScript`);
    return Number(match[1]);
  };

  const battleSim = await gdSource("sim/battle_sim.gd");
  const teamSim = await gdSource("sim/team_sim.gd");
  const elementRules = await gdSource("sim/element_rules.gd");

  const expectedScalars = [
    [battleSim, "RULES_VERSION", RULES_VERSION],
    [battleSim, "MOMENTUM_MAX", MOMENTUM_MAX],
    [battleSim, "MOMENTUM_START", MOMENTUM_START],
    [battleSim, "SURGE_COST", SURGE_COST],
    [battleSim, "BATTLE_MAX_TURNS", BATTLE_MAX_TURNS],
    [battleSim, "LEVEL_CAP", LEVEL_CAP],
    [battleSim, "HUNGRY_NEED", HUNGRY_NEED],
    [battleSim, "DIRTY_NEED", DIRTY_NEED],
    [battleSim, "HUNGRY_COMBAT_FLOOR", HUNGRY_COMBAT_FLOOR],
    [battleSim, "DIRTY_COMBAT_FLOOR", DIRTY_COMBAT_FLOOR],
    [battleSim, "CARE_COMBAT_FLOOR", CARE_COMBAT_FLOOR],
    [battleSim, "CRIT_MULTIPLIER", 1.8],
    [battleSim, "GUARD_MULTIPLIER", 0.5],
    [battleSim, "STRIKE_POWER", 50],
    [battleSim, "SURGE_POWER", 75],
    [battleSim, "VARIANCE_MIN", 0.92],
    [battleSim, "VARIANCE_SPAN", 0.16],
    [teamSim, "TEAM_MAX_TURNS", TEAM_MAX_TURNS],
    [elementRules, "MATCHUP_STRONG", MATCHUP_STRONG],
    [elementRules, "MATCHUP_WEAK", MATCHUP_WEAK],
    [elementRules, "MATCHUP_NEUTRAL", MATCHUP_NEUTRAL],
  ];
  for (const [body, name, expected] of expectedScalars) {
    assert.equal(scalarConst(body, name), expected, `const GDScript ${name} berbeda dari _shared`);
  }

  // Tiga tabel elemen: satu-satunya data yang benar-benar disalin ke client.
  const roster = [
    ...elementRules
      .slice(elementRules.indexOf("const ROSTER"), elementRules.indexOf("const ALIASES"))
      .matchAll(/"(\w+)"/g),
  ].map((match) => match[1]);
  assert.deepEqual(roster, [...ELEMENT_ROSTER], "ROSTER GDScript berbeda dari ELEMENT_ROSTER");

  const aliasBlock = elementRules.slice(
    elementRules.indexOf("const ALIASES"),
    elementRules.indexOf("const STRENGTHS")
  );
  const aliases = Object.fromEntries(
    [...aliasBlock.matchAll(/"(\w+)":\s*"(\w+)"/g)].map((match) => [match[1], match[2]])
  );
  assert.deepEqual(aliases, { ...ELEMENT_ALIASES }, "ALIASES GDScript berbeda dari _shared");

  const strengthBlock = elementRules.slice(
    elementRules.indexOf("const STRENGTHS"),
    elementRules.indexOf("const MATCHUP_STRONG")
  );
  const strengths = Object.fromEntries(
    [...strengthBlock.matchAll(/"(\w+)":\s*\[([^\]]*)\]/g)].map((match) => [
      match[1],
      [...match[2].matchAll(/"(\w+)"/g)].map((inner) => inner[1]),
    ])
  );
  assert.deepEqual(
    strengths,
    JSON.parse(JSON.stringify(ELEMENT_STRENGTHS)),
    "STRENGTHS GDScript berbeda dari ELEMENT_STRENGTHS"
  );

  const rewardBits = Object.fromEntries(
    [
      ...battleSim
        .slice(battleSim.indexOf("const REWARD_TIER_BITS"))
        .split("\n")[0]
        .matchAll(/"(\w+)":\s*(\d+)/g),
    ].map((match) => [match[1], Number(match[2])])
  );
  assert.deepEqual(
    rewardBits,
    Object.fromEntries(Object.entries(REWARD_TIERS).map(([tier, spec]) => [tier, spec.bits])),
    "REWARD_TIER_BITS GDScript berbeda dari REWARD_TIERS"
  );
}

const emitIdx = process.argv.indexOf("--emit");
if (emitIdx > -1 && process.argv[emitIdx + 1]) {
  const { mkdir, writeFile } = await import("node:fs/promises");
  const { join } = await import("node:path");
  const dir = process.argv[emitIdx + 1];
  await mkdir(dir, { recursive: true });

  const { png, manifest } = await postprocessSheet(await buildSheet(blobs), {
    speciesKey: "selftest_synthetic_blob",
    colorBucket: "multicolor",
    promptVersion: "selftest",
    sheetName: "sheet.png",
  });
  await writeFile(join(dir, "sheet.png"), png);
  await writeFile(join(dir, "manifest.json"), JSON.stringify(manifest, null, 2));
  console.log(`\nsheet uji ditulis ke ${dir}`);
}

console.log("\nselftest: OK");
