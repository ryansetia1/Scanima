// Post-processing sprite sheet: chroma key, slicing content-aware, manifest.
//
// Ditulis sebagai modul murni tanpa I/O jaringan supaya bisa diuji dengan sheet
// sintetis (lihat selftest.mjs) dan supaya port ke Supabase Edge Function nanti
// tinggal ganti pembacaan file. ImageScript dipilih justru karena jalan di Node
// dan Deno, jadi port itu benar-benar copy-paste.
//
// Urutan sengaja: downscale DULU, baru keying. Alasannya bukan kualitas
// (keying di resolusi penuh sedikit lebih bersih) tapi paritas dengan Edge
// Function, yang punya batas CPU dan hanya sanggup 1 juta piksel, bukan 4,2
// juta. Eval yang tidak memakai urutan produksi tidak memprediksi produksi.

import { Image } from "imagescript";

export const POSES = ["idle", "attack", "sleep", "defeated"];

// Kuadran asal tiap pose, harus cocok dengan blok LAYOUT di sprite_sheet.md.
export const POSE_QUADRANT = {
  idle: [0, 0],
  attack: [1, 0],
  sleep: [0, 1],
  defeated: [1, 1],
};

export const DEFAULTS = {
  workSize: 1024, // sisi sheet setelah downscale
  keyHue: 120, // derajat, hijau #00FF00
  hueTolerance: 22, // derajat
  // Ambang saturasi dan value sengaja TINGGI, bukan 0,3 seperti resep chroma
  // key pada umumnya. Alasannya spesifik untuk game ini: Anima berelemen plant
  // (tanaman, buah, daun) berwarna hijau, dan hijau daun seperti rgb(60,160,70)
  // punya saturasi 0,63 sehingga akan ikut terhapus dan melubangi tubuhnya.
  // Background #00FF00 punya saturasi ~1,0, jadi ambang 0,85 memisahkan
  // keduanya dengan bersih. Lihat test "hijau daun selamat" di selftest.mjs.
  satMin: 0.85,
  valMin: 0.5,
  alphaThreshold: 8, // di bawah ini dianggap kosong saat cari bbox
  framePadding: 6, // margin transparan di sekeliling sprite di sheet keluaran
  minCellAreaRatio: 0.01, // bbox di bawah 1% area kuadran dianggap sel kosong
  minCellSide: 16,
  // Komponen lebih kecil dari ini dianggap noise anti-alias. Nilainya sengaja
  // kecil: Z tidur, motion line, dan debris tipis tetap harus ikut sprite.
  minComponentPixels: 4,
  // Background hijau selalu jadi mayoritas sheet. Kalau yang ter-key jauh di
  // bawah ini, latarnya bukan hijau dan sheet harus ditolak, bukan diproses.
  minKeyedRatio: 0.15,
  // Bbox yang TERISI padat = keying gagal, bukan sprite. Diukur terhadap isi
  // bbox, bukan terhadap luas kuadran: pose Attack dengan speed line dan
  // percikan sah-sah saja punya bbox seluas kuadran.
  maxCellFillRatio: 0.95,
};

/**
 * Apakah piksel ini warna kunci (hijau chroma)?
 * Memakai HSV, bukan jarak RGB: hue hijau sangat khas, sementara jarak RGB akan
 * ikut memakan hijau yang sah di tubuh Anima berelemen plant.
 */
export function isKeyColor(r, g, b, o = DEFAULTS) {
  const max = Math.max(r, g, b);
  if (max === 0) return false;

  const v = max / 255;
  if (v < o.valMin) return false;

  const min = Math.min(r, g, b);
  const delta = max - min;
  const s = delta / max;
  if (s < o.satMin) return false;

  // Hue hanya dihitung setelah sat/val lolos, supaya jalur mahal jarang dipakai
  let hue;
  if (max === r) hue = 60 * (((g - b) / delta) % 6);
  else if (max === g) hue = 60 * ((b - r) / delta + 2);
  else hue = 60 * ((r - g) / delta + 4);
  if (hue < 0) hue += 360;

  // Hue melingkar: tanpa ini, hijau di sekitar 0/360 lolos dari filter
  let dist = Math.abs(hue - o.keyHue);
  if (dist > 180) dist = 360 - dist;

  return dist <= o.hueTolerance;
}

// Sedikit lebih longgar dari keying, hanya untuk menangkap hijau nyaris murni
// yang lolos. Celahnya sengaja tipis, bukan longgar: hijau pekat seperti forest
// green rgb(34,139,34) adalah warna tubuh Anima yang sah, dan warna sendirian
// tidak punya cara membedakannya dari sisa background.
const RESIDUE_OPTS = { ...DEFAULTS, satMin: 0.8, valMin: 0.45, hueTolerance: 24 };

/**
 * Apakah piksel di cincin tepi ini terkontaminasi background hijau?
 *
 * Saturasi adalah ukuran yang SALAH untuk pertanyaan ini. Campuran keyline putih
 * dengan background `#00FF00` selalu berbentuk `(t, 255, t)`: channel hijau
 * tersangkut di 255 sementara merah dan biru turun bersama. Piksel seperti
 * rgb(128,255,128) karena itu punya saturasi 0,5 — di bawah ambang keying mana
 * pun yang masih aman bagi Anima plant — padahal ia jelas-jelas separuh
 * background dan itulah halo yang terlihat di layar.
 *
 * Yang membedakannya dari warna tubuh yang sah adalah betapa tinggi channel
 * hijaunya, bukan seberapa jenuh warnanya. Hijau daun rgb(60,160,70) punya
 * g=160 dan tidak tersentuh. Syarat dominasi memisahkan putih (g=255 tapi
 * r=b=255) supaya keyline-nya sendiri tidak ikut terkikis.
 */
const EDGE_GREEN_MIN = 220; // g di bawah ini bukan campuran #00FF00
const EDGE_GREEN_DOMINANCE = 20; // di bawah ini warnanya putih/abu, bukan hijau

export function isKeyContaminatedEdge(r, g, b) {
  return g >= EDGE_GREEN_MIN && g - Math.max(r, b) >= EDGE_GREEN_DOMINANCE;
}

/** Nolkan alpha di piksel berwarna kunci. Mengubah bitmap di tempat. */
export function chromaKeyInPlace(bitmap, opts = DEFAULTS) {
  let keyed = 0;
  for (let i = 0; i < bitmap.length; i += 4) {
    if (isKeyColor(bitmap[i], bitmap[i + 1], bitmap[i + 2], opts)) {
      bitmap[i] = 0;
      bitmap[i + 1] = 0;
      bitmap[i + 2] = 0;
      bitmap[i + 3] = 0;
      keyed++;
    }
  }
  return keyed;
}

/**
 * Haluskan tepi alpha supaya keying tidak meninggalkan gerigi, dan buang sisa
 * hijau di cincin tepi itu.
 *
 * Hanya piksel yang SUDAH bagian sprite yang alpha-nya diturunkan. Piksel
 * transparan tidak pernah diberi alpha, karena itu berarti mengarang coverage
 * yang tidak digambar model: sprite jadi melebar 1px dan bbox ikut melebar,
 * yang berujung pada frame_size yang tidak bisa diprediksi.
 * Interior dibiarkan utuh supaya sprite tidak jadi buram.
 *
 * Erosi hijau di cincin tepi memperbaiki halo yang terukur di sheet sungguhan:
 * pada run smoke pertama, 99,7% piksel kehijauan yang lolos keying berada tepat
 * 1px dari piksel transparan. Ia bukan background yang gagal terhapus melainkan
 * campuran keyline putih dengan background hijau, dari rgb(37,227,38) yang
 * hampir hijau murni sampai rgb(219,255,220) yang hampir putih.
 *
 * Melonggarkan ambang saturasi adalah perbaikan yang SALAH untuk ini: ambang itu
 * yang menjaga tubuh Anima berelemen plant tetap utuh, dan campuran di tengah
 * seperti rgb(128,255,128) toh cuma bersaturasi 0,5 sehingga tetap lolos.
 * Dua hal lain yang membedakan halo dari warna tubuh yang sah: kedekatannya ke
 * piksel transparan, dan channel hijau yang tersangkut di dekat 255 milik
 * background. Lihat isKeyContaminatedEdge.
 */
export function softenAlphaEdges(bitmap, width, height, opts = DEFAULTS) {
  const original = new Uint8Array(bitmap.length / 4);
  for (let i = 0, p = 0; i < bitmap.length; i += 4, p++) original[p] = bitmap[i + 3];

  let softened = 0;
  let eroded = 0;
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const p = y * width + x;
      if (original[p] <= opts.alphaThreshold) continue; // jangan tumbuh keluar

      let sum = 0;
      let hasClear = false;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const a = original[p + dy * width + dx];
          sum += a;
          if (a <= opts.alphaThreshold) hasClear = true;
        }
      }
      if (!hasClear) continue;

      const i = p * 4;
      if (isKeyContaminatedEdge(bitmap[i], bitmap[i + 1], bitmap[i + 2])) {
        bitmap[i + 3] = 0;
        eroded++;
      } else {
        bitmap[i + 3] = Math.round(sum / 9);
        softened++;
      }
    }
  }
  return { softened, eroded };
}

/** Bounding box rapat dari piksel tak-transparan di dalam rect. */
export function findBBox(bitmap, width, rect, alphaThreshold = DEFAULTS.alphaThreshold) {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  const [rx, ry, rw, rh] = rect;
  for (let y = ry; y < ry + rh; y++) {
    for (let x = rx; x < rx + rw; x++) {
      if (bitmap[(y * width + x) * 4 + 3] > alphaThreshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (minX === Infinity) return null;
  return { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
}

/**
 * Segmentasikan sheet menjadi empat pose berdasarkan komponen piksel yang
 * tersambung, bukan berdasarkan crop kuadran keras.
 *
 * Model kadang mengulurkan tangan, kabel, atau action pose beberapa puluh
 * piksel melewati garis tengah 2x2. findBBox() yang dibatasi kuadran memotong
 * bagian itu walaupun masih tersambung jelas ke tubuh pose di sebelah kanan.
 *
 * Setiap komponen alpha 8-connected diberikan ke kuadran yang memuat piksel
 * terbanyak dari komponen tersebut. Karena kepemilikan disimpan per piksel,
 * bbox satu pose boleh masuk ke kuadran tetangga tanpa ikut menyalin monster
 * tetangganya yang kebetulan berada di dalam persegi bbox yang sama.
 */
export function segmentPosePixels(bitmap, width, height, opts = DEFAULTS) {
  const pixelCount = width * height;
  const visited = new Uint8Array(pixelCount);
  const owners = new Uint8Array(pixelCount);
  owners.fill(255); // 0..3 = indeks POSES, 255 = background/noise

  // Satu queue dialokasikan sekali dan dipakai ulang untuk semua komponen.
  // Int32Array 1 juta piksel = 4 MB; lebih aman daripada Array<number> yang
  // bisa membengkak puluhan MB di Edge Function.
  const queue = new Int32Array(pixelCount);
  const boxes = Array(POSES.length).fill(null);
  const opaquePixels = new Uint32Array(POSES.length);
  const crossBoundaryPixels = new Uint32Array(POSES.length);
  const halfW = Math.floor(width / 2);
  const halfH = Math.floor(height / 2);

  for (let seed = 0; seed < pixelCount; seed++) {
    if (visited[seed] || bitmap[seed * 4 + 3] <= opts.alphaThreshold) continue;

    let start = 0;
    let end = 1;
    queue[0] = seed;
    visited[seed] = 1;
    const quadrantCounts = new Uint32Array(POSES.length);
    let minX = width;
    let minY = height;
    let maxX = -1;
    let maxY = -1;

    while (start < end) {
      const p = queue[start++];
      const x = p % width;
      const y = Math.floor(p / width);
      quadrantCounts[(y >= halfH ? 2 : 0) + (x >= halfW ? 1 : 0)]++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      for (let dy = -1; dy <= 1; dy++) {
        const ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          const np = ny * width + nx;
          if (visited[np] || bitmap[np * 4 + 3] <= opts.alphaThreshold) continue;
          visited[np] = 1;
          queue[end++] = np;
        }
      }
    }

    if (end < opts.minComponentPixels) continue;

    let owner = 0;
    for (let q = 1; q < POSES.length; q++) {
      if (quadrantCounts[q] > quadrantCounts[owner]) owner = q;
    }

    const ownQuadrantPixels = quadrantCounts[owner];
    opaquePixels[owner] += end;
    crossBoundaryPixels[owner] += end - ownQuadrantPixels;
    for (let i = 0; i < end; i++) owners[queue[i]] = owner;

    const component = { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
    const current = boxes[owner];
    if (!current) {
      boxes[owner] = component;
    } else {
      const x0 = Math.min(current.x, component.x);
      const y0 = Math.min(current.y, component.y);
      const x1 = Math.max(current.x + current.w, component.x + component.w);
      const y1 = Math.max(current.y + current.h, component.y + component.h);
      boxes[owner] = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }
  }

  const bboxes = {};
  const ownership = {};
  for (let i = 0; i < POSES.length; i++) {
    if (boxes[i]) bboxes[POSES[i]] = boxes[i];
    ownership[POSES[i]] = {
      opaque_pixels: opaquePixels[i],
      cross_boundary_pixels: crossBoundaryPixels[i],
    };
  }
  return { bboxes, owners, ownership };
}

/**
 * Rasio piksel hijau nyaris murni yang masih opak setelah keying.
 *
 * Yang harus dipahami saat membaca angkanya: cincin 1px terluar sudah dierosi
 * oleh softenAlphaEdges, jadi halo setipis satu piksel tidak akan muncul di sini.
 * Yang masih dilaporkan justru dua kasus yang lebih layak dialarmkan: hijau
 * nyaris murni di INTERIOR sprite, yang berarti model menggambar background di
 * tengah tubuh, dan fringe yang lebih tebal dari 1px, yang berarti keyline putih
 * gagal muncul sehingga hijau membaur jauh ke dalam.
 *
 * Predikatnya sengaja berbeda dari predikat erosi: yang ini berbasis saturasi
 * supaya tetap konservatif di interior, tempat warna tubuh yang sah tinggal.
 *
 * Pelindung utama terhadap kegagalan besar tetap minKeyedRatio, bukan metrik ini.
 */
export function greenResidueRatio(bitmap) {
  let opaque = 0;
  let greenish = 0;
  for (let i = 0; i < bitmap.length; i += 4) {
    if (bitmap[i + 3] <= DEFAULTS.alphaThreshold) continue;
    opaque++;
    if (isKeyColor(bitmap[i], bitmap[i + 1], bitmap[i + 2], RESIDUE_OPTS)) greenish++;
  }
  return opaque === 0 ? 1 : greenish / opaque;
}

/**
 * Susun sheet keluaran: tiap pose ditempel ke sel berukuran seragam, rata bawah
 * dan rata tengah horizontal.
 *
 * Ukuran frame seragam itu wajib, bukan kosmetik: AnimatedSprite2D hanya punya
 * satu properti `offset` untuk seluruh animasi, jadi region berukuran berbeda
 * membuat sprite tersentak berpindah tiap ganti pose, dan tidak ada cara
 * memperbaikinya di sisi client tanpa node pembungkus per frame.
 *
 * Jangkarnya bottom-center bbox, yaitu titik tumpu di tanah. Keempat pose jadi
 * berdiri di garis tanah yang sama, termasuk pose sleep dan defeated yang
 * memang lebih rendah.
 */
export function planFrames(bboxes, opts = DEFAULTS) {
  const present = POSES.filter((p) => bboxes[p]);
  if (present.length === 0) throw new Error("tidak ada satu pun bbox terdeteksi");

  const maxW = Math.max(...present.map((p) => bboxes[p].w));
  const maxH = Math.max(...present.map((p) => bboxes[p].h));
  const frameW = maxW + opts.framePadding * 2;
  const frameH = maxH + opts.framePadding * 2;

  const placements = {};
  for (const pose of present) {
    const [col, row] = POSE_QUADRANT[pose];
    const bb = bboxes[pose];
    placements[pose] = {
      src: bb,
      region: [col * frameW, row * frameH, frameW, frameH],
      destX: col * frameW + Math.floor((frameW - bb.w) / 2),
      destY: row * frameH + (frameH - opts.framePadding - bb.h),
    };
  }

  return { frameW, frameH, sheetW: frameW * 2, sheetH: frameH * 2, placements };
}

/** Salin hanya piksel yang memang dimiliki pose ini, bukan isi bbox tetangga. */
function blitOwned(srcBitmap, srcW, src, owners, owner, dstBitmap, dstW, destX, destY) {
  for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
      const srcPixel = (src.y + y) * srcW + src.x + x;
      if (owners[srcPixel] !== owner) continue;
      const srcOffset = srcPixel * 4;
      const dstOffset = ((destY + y) * dstW + destX + x) * 4;
      dstBitmap.set(srcBitmap.subarray(srcOffset, srcOffset + 4), dstOffset);
    }
  }
}

/**
 * Pipeline penuh: PNG mentah dari Replicate -> PNG RGBA rapi + manifest.
 *
 * @param {Uint8Array} pngBuffer PNG mentah, background hijau, opak
 * @param {object} meta { speciesKey, colorBucket, stage, promptVersion }
 * @returns {Promise<{ png: Uint8Array, manifest: object }>}
 */
export async function postprocessSheet(pngBuffer, meta = {}, opts = DEFAULTS) {
  const decoded = await Image.decode(pngBuffer);

  const work =
    decoded.width === opts.workSize && decoded.height === opts.workSize
      ? decoded
      : decoded.resize(opts.workSize, opts.workSize);

  const bitmap = work.bitmap;
  const { width, height } = work;

  const keyedPixels = chromaKeyInPlace(bitmap, opts);
  const keyedRatio = keyedPixels / (bitmap.length / 4);

  // Pagar wajib: kalau hampir tidak ada yang ter-key, background-nya bukan hijau
  // dan sisa pipeline akan menghasilkan empat "sprite" palsu seukuran kuadran
  // penuh, bukan error. Kegagalan sunyi seperti itu jauh lebih mahal daripada
  // gagal keras di sini, karena sheet sampahnya masuk cache dan dipakai
  // semua pemain yang men-scan spesies yang sama.
  if (keyedRatio < opts.minKeyedRatio) {
    throw new Error(
      `background bukan hijau #00FF00: hanya ${(keyedRatio * 100).toFixed(1)}% piksel ter-key. ` +
        "Model kemungkinan mengembalikan latar putih, hitam, atau checkerboard. " +
        "Sheet ini tidak boleh dipakai."
    );
  }

  softenAlphaEdges(bitmap, width, height, opts);

  // Segmentasi komponen terhubung membiarkan anggota tubuh melewati garis tengah
  // tanpa ikut mencopy monster tetangga. Kuadran hanya menentukan pose pemilik,
  // bukan menjadi batas crop.
  const halfW = Math.floor(width / 2);
  const halfH = Math.floor(height / 2);
  const quadrantArea = halfW * halfH;
  const segmented = segmentPosePixels(bitmap, width, height, opts);
  const bboxes = segmented.bboxes;
  const rejected = {};

  for (const pose of POSES) {
    const bb = bboxes[pose];
    if (!bb) {
      rejected[pose] = "kosong";
      continue;
    }
    if (bb.w < opts.minCellSide || bb.h < opts.minCellSide) {
      rejected[pose] = `terlalu kecil ${bb.w}x${bb.h}`;
      delete bboxes[pose];
      continue;
    }
    const area = (bb.w * bb.h) / quadrantArea;
    if (area < opts.minCellAreaRatio) {
      rejected[pose] = "area di bawah ambang";
      delete bboxes[pose];
      continue;
    }
    // Keying yang gagal menyisakan kuadran yang SEKALIGUS seluas kuadran dan
    // terisi penuh. Kedua syarat wajib ada, karena masing-masing sendirian
    // menolak sprite yang sah: pose Attack dengan speed line dan percikan
    // punya bbox 96% kuadran padahal cuma 42% opak, sementara sprite yang
    // silhouette-nya memang kotak padat mengisi bbox-nya sampai ~100% tapi
    // bbox itu jauh lebih kecil dari kuadran.
    const density = segmented.ownership[pose].opaque_pixels / (bb.w * bb.h);
    if (area > opts.maxCellFillRatio && density > opts.maxCellFillRatio) {
      rejected[pose] = `kuadran terisi penuh dan padat ${Math.round(density * 100)}%, keying gagal`;
      delete bboxes[pose];
      continue;
    }
  }

  const detected = Object.keys(bboxes);
  if (detected.length === 0) {
    throw new Error(
      `keying menghasilkan sheet kosong: ${keyedPixels} piksel ter-key dari ${bitmap.length / 4}. ` +
        "Kemungkinan background bukan hijau #00FF00."
    );
  }

  const plan = planFrames(bboxes, opts);

  const out = new Image(plan.sheetW, plan.sheetH);
  out.bitmap.fill(0);
  for (const pose of detected) {
    const pl = plan.placements[pose];
    blitOwned(
      bitmap,
      width,
      pl.src,
      segmented.owners,
      POSES.indexOf(pose),
      out.bitmap,
      plan.sheetW,
      pl.destX,
      pl.destY
    );
  }

  const metrics = heightMetrics(bboxes);

  const poses = {};
  for (const pose of detected) poses[pose] = { region: plan.placements[pose].region };

  const manifest = {
    version: 1,
    sheet: meta.sheetName ?? null,
    sheet_size: [plan.sheetW, plan.sheetH],
    frame_size: [plan.frameW, plan.frameH],
    species_key: meta.speciesKey ?? null,
    color_bucket: meta.colorBucket ?? null,
    stage: meta.stage ?? 1,
    prompt_version: meta.promptVersion ?? null,
    poses,
    qa: {
      cells_detected: detected.length,
      cells_rejected: rejected,
      green_residue_ratio: Number(greenResidueRatio(out.bitmap).toFixed(5)),
      standing_height_variance: metrics.standingVariance,
      bbox_heights: metrics.heights,
      pose_ownership: segmented.ownership,
      keyed_pixel_ratio: Number((keyedPixels / (bitmap.length / 4)).toFixed(4)),
      source_size: [decoded.width, decoded.height],
      // ponytail: erosi hijau hanya di cincin 1px terluar, bukan despill penuh.
      // Plafon: fringe yang lebih tebal dari 1px tetap lolos, dan itu terjadi
      // kalau white keyline dari prompt gagal muncul sehingga hijau membaur jauh
      // ke dalam tubuh. Pantau green_residue_ratio; kalau tembus 0,005 naikkan
      // erosinya jadi pita 2px, atau tambahkan despill (tarik channel hijau ke
      // max(r,b)) yang mempertahankan silhouette dengan harga tepi keabuan.
      warnings: buildWarnings(detected, metrics, out.bitmap),
    },
  };

  return { png: await out.encode(), manifest };
}

/**
 * Konsistensi skala hanya sah diukur antar pose yang posturnya sebanding.
 *
 * Membandingkan tinggi bbox keempat pose adalah metrik yang salah: kreatur yang
 * meringkuk tidur MEMANG jauh lebih pendek daripada yang berdiri, jadi metrik
 * itu akan terus memberi alarm palsu pada sheet yang sempurna. Yang benar-benar
 * menandakan model mengubah skala adalah selisih antara Idle dan Attack, karena
 * keduanya berdiri penuh.
 */
export function heightMetrics(bboxes) {
  const heights = {};
  for (const pose of POSES) if (bboxes[pose]) heights[pose] = bboxes[pose].h;

  let standingVariance = 0;
  if (bboxes.idle && bboxes.attack) {
    const hi = Math.max(bboxes.idle.h, bboxes.attack.h);
    const lo = Math.min(bboxes.idle.h, bboxes.attack.h);
    standingVariance = Number(((hi - lo) / hi).toFixed(3));
  }

  // Arah juga penting: pose meringkuk yang lebih TINGGI dari pose berdiri
  // hampir pasti berarti model membesarkan kreaturnya, bukan menidurkannya.
  const tooTall = [];
  if (bboxes.idle) {
    for (const pose of ["sleep", "defeated"]) {
      if (bboxes[pose] && bboxes[pose].h > bboxes.idle.h * 1.1) tooTall.push(pose);
    }
  }

  return { heights, standingVariance, tooTall };
}

function buildWarnings(detected, metrics, bitmap) {
  const warnings = [];
  if (detected.length < POSES.length) warnings.push(`hanya ${detected.length}/4 sel terdeteksi`);
  if (metrics.standingVariance > 0.15) {
    warnings.push(`skala Idle vs Attack beda ${Math.round(metrics.standingVariance * 100)}%`);
  }
  for (const pose of metrics.tooTall) warnings.push(`pose ${pose} lebih tinggi dari idle`);
  const residue = greenResidueRatio(bitmap);
  if (residue > 0.001) warnings.push(`residu hijau ${(residue * 100).toFixed(2)}%`);
  return warnings;
}
