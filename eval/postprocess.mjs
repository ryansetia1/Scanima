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
  // Background hijau selalu jadi mayoritas sheet. Kalau yang ter-key jauh di
  // bawah ini, latarnya bukan hijau dan sheet harus ditolak, bukan diproses.
  minKeyedRatio: 0.15,
  maxCellFillRatio: 0.95, // bbox seluas kuadran = keying gagal, bukan sprite
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
 * Haluskan tepi alpha supaya keying tidak meninggalkan gerigi.
 *
 * Hanya piksel yang SUDAH bagian sprite yang alpha-nya diturunkan. Piksel
 * transparan tidak pernah diberi alpha, karena itu berarti mengarang coverage
 * yang tidak digambar model: sprite jadi melebar 1px dan bbox ikut melebar,
 * yang berujung pada frame_size yang tidak bisa diprediksi.
 * Interior dibiarkan utuh supaya sprite tidak jadi buram.
 */
export function softenAlphaEdges(bitmap, width, height, opts = DEFAULTS) {
  const original = new Uint8Array(bitmap.length / 4);
  for (let i = 0, p = 0; i < bitmap.length; i += 4, p++) original[p] = bitmap[i + 3];

  let softened = 0;
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
      if (hasClear) {
        bitmap[p * 4 + 3] = Math.round(sum / 9);
        softened++;
      }
    }
  }
  return softened;
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

// Sedikit lebih longgar dari keying, hanya untuk menangkap hijau nyaris murni
// yang lolos. Celahnya sengaja tipis, bukan longgar: hijau pekat seperti forest
// green rgb(34,139,34) adalah warna tubuh Anima yang sah, dan metrik berbasis
// warna tidak punya cara membedakannya dari sisa background.
const RESIDUE_OPTS = { ...DEFAULTS, satMin: 0.8, valMin: 0.45, hueTolerance: 24 };

/**
 * Rasio piksel hijau nyaris murni yang masih opak setelah keying.
 *
 * Batas yang harus dipahami: metrik ini menangkap background yang gagal ter-key,
 * TAPI TIDAK menangkap fringe hijau yang sudah membaur di tepi sprite, karena
 * piksel baur punya saturasi rendah dan tidak bisa dibedakan dari warna tubuh
 * lewat warna saja. Mendeteksi fringe butuh kedekatan ke piksel transparan, dan
 * itu ditunda bersama despill. Pelindung utama terhadap kegagalan besar bukan
 * metrik ini melainkan minKeyedRatio.
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

function blit(srcBitmap, srcW, src, dstBitmap, dstW, destX, destY) {
  for (let y = 0; y < src.h; y++) {
    const srcStart = ((src.y + y) * srcW + src.x) * 4;
    const dstStart = ((destY + y) * dstW + destX) * 4;
    dstBitmap.set(srcBitmap.subarray(srcStart, srcStart + src.w * 4), dstStart);
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

  // Cari bbox per kuadran, bukan membagi sheet jadi empat secara buta. Model
  // tidak selalu menaruh subjek di tengah sel, dan pembagian buta memotongnya.
  const halfW = Math.floor(width / 2);
  const halfH = Math.floor(height / 2);
  const quadrantArea = halfW * halfH;
  const bboxes = {};
  const rejected = {};

  for (const pose of POSES) {
    const [col, row] = POSE_QUADRANT[pose];
    const bb = findBBox(bitmap, width, [col * halfW, row * halfH, halfW, halfH], opts.alphaThreshold);
    if (!bb) {
      rejected[pose] = "kosong";
      continue;
    }
    if (bb.w < opts.minCellSide || bb.h < opts.minCellSide) {
      rejected[pose] = `terlalu kecil ${bb.w}x${bb.h}`;
      continue;
    }
    const fill = (bb.w * bb.h) / quadrantArea;
    if (fill < opts.minCellAreaRatio) {
      rejected[pose] = "area di bawah ambang";
      continue;
    }
    // Prompt meminta margin lebar di tiap sel, jadi bbox yang mengisi hampir
    // seluruh kuadran berarti keying gagal atau sel-selnya menyatu.
    if (fill > opts.maxCellFillRatio) {
      rejected[pose] = `mengisi ${Math.round(fill * 100)}% kuadran, keying gagal`;
      continue;
    }
    bboxes[pose] = bb;
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
    blit(bitmap, width, pl.src, out.bitmap, plan.sheetW, pl.destX, pl.destY);
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
      keyed_pixel_ratio: Number((keyedPixels / (bitmap.length / 4)).toFixed(4)),
      source_size: [decoded.width, decoded.height],
      // ponytail: belum ada despill. Plafon: halo hijau tipis di tepi kalau
      // white keyline dari prompt gagal muncul. Pantau green_residue_ratio;
      // kalau tembus 0,01 tambahkan despill terbatas pada pita 2px di tepi.
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
