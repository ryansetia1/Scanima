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
  DEFAULTS,
  isKeyColor,
  findBBox,
  heightMetrics,
  postprocessSheet,
} from "../backend/supabase/functions/_shared/postprocess.mjs";
import {
  validateVision,
  assemblePrompt,
  extractJson,
} from "../backend/supabase/functions/_shared/vision.mjs";

const SIZE = DEFAULTS.workSize; // 1024, jadi tidak ada resize yang mengaburkan assert
const HALF = SIZE / 2;
const PAD = DEFAULTS.framePadding;

const GREEN = [0, 255, 0];
const FILLS = {
  idle: [220, 40, 40],
  attack: [40, 80, 230],
  sleep: [150, 60, 200],
  defeated: [240, 150, 30],
};

function setPx(bitmap, x, y, [r, g, b], a = 255) {
  const o = (y * SIZE + x) * 4;
  bitmap[o] = r;
  bitmap[o + 1] = g;
  bitmap[o + 2] = b;
  bitmap[o + 3] = a;
}

/** Blob = persegi berisi warna, dikelilingi outline putih 3px seperti di prompt. */
function drawBlob(bitmap, x, y, w, h, fill) {
  for (let yy = y - 3; yy < y + h + 3; yy++) {
    for (let xx = x - 3; xx < x + w + 3; xx++) {
      if (xx < 0 || yy < 0 || xx >= SIZE || yy >= SIZE) continue;
      const inside = xx >= x && xx < x + w && yy >= y && yy < y + h;
      setPx(bitmap, xx, yy, inside ? fill : [255, 255, 255]);
    }
  }
}

async function buildSheet(blobs) {
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
    drawBlob(img.bitmap, col * HALF + spec.x, row * HALF + spec.y, spec.w, spec.h, FILLS[pose]);
  }
  return await img.encode();
}

// Blob dengan outline: bbox nyata = ukuran blob + 3px outline di tiap sisi.
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
    suggested_name: "Mugmon",
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
  const config = await readFile(new URL("../backend/supabase/config.toml", import.meta.url), "utf8");
  const careConfig = config.split("[functions.care_anima]")[1]?.split("\n[")[0] ?? "";
  assert.ok(care.includes(".auth.getClaims("), "care_anima harus memverifikasi JWT lewat getClaims");
  assert.ok(!care.includes(".auth.getUser("), "care_anima tidak boleh mengembalikan round-trip getUser");
  assert.match(careConfig, /verify_jwt\s*=\s*true/, "gateway JWT care_anima harus tetap aktif");
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

// Menulis sheet hasil pipeline ke folder, untuk dibaca sisi Godot. Ini yang
// menutup kontrak antara Node dan Godot tanpa memanggil API berbayar:
//
//   node eval/selftest.mjs --emit /tmp/scanima_e2e
//   godot --headless --path game --script res://tests/test_sprite_slicing.gd \
//       -- --manifest=/tmp/scanima_e2e/manifest.json
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
