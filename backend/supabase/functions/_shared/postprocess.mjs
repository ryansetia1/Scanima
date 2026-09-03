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
import { promptMajor } from "./vision.mjs";
import { encodeImage } from "./png.mjs";

export const LAYOUT_2X2 = {
  grid: 2,
  poses: ["idle", "attack", "sleep", "defeated"],
  quadrant: {
    idle: [0, 0],
    attack: [1, 0],
    sleep: [0, 1],
    defeated: [1, 1],
  },
};

export const LAYOUT_3X3 = {
  grid: 3,
  poses: [
    "idle", "attack", "sleep",
    "happy", "hungry", "dirty",
    "defeated", "fx_strike", "fx_surge",
  ],
  quadrant: {
    idle: [0, 0],
    attack: [1, 0],
    sleep: [2, 0],
    happy: [0, 1],
    hungry: [1, 1],
    dirty: [2, 1],
    defeated: [0, 2],
    fx_strike: [1, 2],
    fx_surge: [2, 2],
  },
};

export function layoutForPrompt(version) {
  return promptMajor(version) >= 7 ? LAYOUT_3X3 : LAYOUT_2X2;
}

// Alias 2x2 untuk selftest lama dan import yang sudah ada.
export const POSES = LAYOUT_2X2.poses;
export const POSE_QUADRANT = LAYOUT_2X2.quadrant;

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
  // Keyline putih tetap diminta ke model sebagai matte pemisah dari green
  // screen, lalu dikupas di backend agar tidak menjadi bagian visual Anima.
  // Ubah flag ini ke false untuk rollback tanpa mengubah prompt atau algoritma.
  stripWhiteKeyline: true,
  whiteKeylineMaxDepth: 6, // prompt meminta 3–5px; satu piksel ekstra untuk AA
  whiteKeylineMinChannel: 200,
  whiteKeylineMaxSpread: 55,
  minCellAreaRatio: 0.01, // bbox di bawah 1% area kuadran dianggap sel kosong
  minCellSide: 16,
  // Komponen lebih kecil dari ini dianggap noise anti-alias. Nilainya sengaja
  // kecil: Z tidur, motion line, dan debris tipis tetap harus ikut sprite.
  minComponentPixels: 4,
  // v26 melarang detached mark di character cells selain maksimal dua Z Sleep.
  // Noise anti-alias kecil tetap diabaikan.
  minDetachedCharacterPixels: 16,
  // Batas atas fragmen yang boleh DIHAPUS saat menyelamatkan sheet berbayar,
  // relatif terhadap badan pose itu. Bintik melayang aman dibuang; potongan
  // besar berarti segmentasi atau keying yang rusak, dan mengirim setengah
  // monster jauh lebih mahal daripada gagal keras. Kasus nyata terbesar yang
  // pernah tercatat 115px terhadap badan ~30.000px, yaitu 0,4%.
  maxRepairableFragmentRatio: 0.05,
  // v12 mengizinkan aksen Battle terlepas, tetapi semuanya wajib tinggal di
  // safe envelope selnya. Audit hanya menolak komponen sekunder dekat seam;
  // ia tidak menebak lalu memindahkan piksel ke pose lain.
  seamMarginRatio: 0.12,
  minSeamLeakPixels: 16,
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

/**
 * Uap/percikan neon di sheet katalog yang lolos isKeyColor.
 * Steam GPT Image sering rgb(47,242,41) sat 0,83 — di bawah satMin 0,85 —
 * jadi kelihatan green-screen. Daun makanan (val rendah / sat sedang) aman.
 * Jangan dipakai di sheet Anima: itu jalur plant.
 */
export function isCatalogKeyVapor(r, g, b) {
  if (g < 180) return false;
  const max = Math.max(r, g, b);
  const v = max / 255;
  if (v < 0.72) return false;
  const min = Math.min(r, g, b);
  const delta = max - min;
  if (delta === 0) return false;
  const s = delta / max;
  let hue;
  if (max === r) hue = 60 * (((g - b) / delta) % 6);
  else if (max === g) hue = 60 * ((b - r) / delta + 2);
  else hue = 60 * ((r - g) / delta + 4);
  if (hue < 0) hue += 360;
  const chroma = hue >= 100 && hue <= 135 && s >= 0.60;
  const spark = hue >= 65 && hue < 100 && s >= 0.85 && b <= 40 && v >= 0.75;
  const spill = g >= 200 && v >= 0.82 && hue >= 95 && hue <= 130 && (g - r) >= 50;
  return chroma || spark || spill;
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

/**
 * Cerminkan piksel kiri-kanan di dalam satu sel grid. Involutif: flip dua kali
 * mengembalikan byte yang identik. Dipanggil sebelum chromaKeyInPlace supaya
 * bbox, ownership, dan blit di bawahnya menghitung angka yang sudah benar
 * sejak awal — lihat facing_audit.mjs untuk siapa yang memutuskan flip mana.
 */
export function flipQuadrantInPlace(bitmap, width, height, quadrant, grid) {
  const [col, row] = quadrant;
  const cellW = Math.floor(width / grid);
  const cellH = Math.floor(height / grid);
  const left = col * cellW;
  const top = row * cellH;
  const right = col === grid - 1 ? width : (col + 1) * cellW;
  const bottom = row === grid - 1 ? height : (row + 1) * cellH;
  const cellWidth = right - left;

  for (let y = top; y < bottom; y++) {
    for (let x = 0; x < Math.floor(cellWidth / 2); x++) {
      const a = (y * width + left + x) * 4;
      const b = (y * width + right - 1 - x) * 4;
      for (let c = 0; c < 4; c++) {
        const tmp = bitmap[a + c];
        bitmap[a + c] = bitmap[b + c];
        bitmap[b + c] = tmp;
      }
    }
  }
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

/** Putih/off-white yang boleh dianggap matte, bukan semua piksel putih gambar. */
export function isWhiteKeylineColor(r, g, b, opts = DEFAULTS) {
  const min = Math.min(r, g, b);
  const max = Math.max(r, g, b);
  return min >= opts.whiteKeylineMinChannel && max - min <= opts.whiteKeylineMaxSpread;
}

/**
 * Nolkan alpha piksel bermatte yang TERSAMBUNG ke transparansi, dengan
 * kedalaman terbatas.
 *
 * Sambungan itu yang membuat pengupasan ini aman: warna sendirian tidak bisa
 * membedakan matte dari warna tubuh yang sah, tetapi matte selalu bersambung ke
 * luar sementara warna tubuh dipagari art di sekelilingnya. Batas kedalaman
 * adalah pagar kedua untuk kalau pagar art itu bocor satu piksel.
 */
function stripConnectedToTransparency(bitmap, width, height, isMatte, alphaThreshold, maxDepth) {
  if (maxDepth <= 0) return 0;

  const pixelCount = width * height;
  const depths = new Uint8Array(pixelCount);
  const queue = new Int32Array(pixelCount);
  let start = 0;
  let end = 0;

  // Seed = piksel matte yang langsung menyentuh transparansi.
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const p = y * width + x;
      const i = p * 4;
      if (bitmap[i + 3] <= alphaThreshold || !isMatte(bitmap[i], bitmap[i + 1], bitmap[i + 2])) {
        continue;
      }

      let touchesClear = false;
      for (let dy = -1; dy <= 1 && !touchesClear; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = x + dx;
          const ny = y + dy;
          if (
            nx < 0 ||
            ny < 0 ||
            nx >= width ||
            ny >= height ||
            bitmap[(ny * width + nx) * 4 + 3] <= alphaThreshold
          ) {
            touchesClear = true;
            break;
          }
        }
      }
      if (!touchesClear) continue;
      depths[p] = 1;
      queue[end++] = p;
    }
  }

  while (start < end) {
    const p = queue[start++];
    const depth = depths[p];
    if (depth >= maxDepth) continue;
    const x = p % width;
    const y = Math.floor(p / width);

    for (let dy = -1; dy <= 1; dy++) {
      const ny = y + dy;
      if (ny < 0 || ny >= height) continue;
      for (let dx = -1; dx <= 1; dx++) {
        if (dx === 0 && dy === 0) continue;
        const nx = x + dx;
        if (nx < 0 || nx >= width) continue;
        const np = ny * width + nx;
        if (depths[np] !== 0) continue;
        const ni = np * 4;
        if (
          bitmap[ni + 3] <= alphaThreshold ||
          !isMatte(bitmap[ni], bitmap[ni + 1], bitmap[ni + 2])
        ) {
          continue;
        }
        depths[np] = depth + 1;
        queue[end++] = np;
      }
    }
  }

  for (let q = 0; q < end; q++) {
    const i = queue[q] * 4;
    bitmap[i] = 0;
    bitmap[i + 1] = 0;
    bitmap[i + 2] = 0;
    bitmap[i + 3] = 0;
  }
  return end;
}

/**
 * Kupas hanya matte putih yang tersambung ke transparansi, dengan kedalaman
 * terbatas. Dark line art yang diminta prompt menjadi pagar alami sehingga
 * badan Anima putih tetap utuh.
 */
export function stripWhiteKeylineInPlace(bitmap, width, height, opts = DEFAULTS) {
  if (!opts.stripWhiteKeyline) return 0;
  // ponytail: flood dibatasi 6px, bukan segmentasi matte penuh. Kalau model
  // mulai menggambar keyline lebih tebal, naikkan depth setelah eval visual.
  return stripConnectedToTransparency(
    bitmap,
    width,
    height,
    (r, g, b) => isWhiteKeylineColor(r, g, b, opts),
    opts.alphaThreshold,
    Math.max(0, Math.floor(opts.whiteKeylineMaxDepth)),
  );
}

/**
 * Background `#00FF00` yang DITEDUHKAN oleh figurnya sendiri.
 *
 * `isKeyColor` disetel untuk hijau murni, dan `isKeyContaminatedEdge` untuk
 * campurannya dengan keyline PUTIH — bentuknya `(t, 255, t)`, jadi ambang
 * `g >= 220` cukup. Tidak ada yang menangkap campuran hijau dengan art GELAP:
 * navy rgb(30,50,90) yang berbaur `#00FF00` mendarat di sekitar rgb(10,110,48),
 * yaitu hue masih hijau tapi value 0,43 dan g jauh di bawah 220. Terukur di
 * keempat sheet roster: garis 1px kehijauan di tepi potong bust, dan celah
 * mantel yang teduh sampai rgb(83,208,71).
 *
 * Yang membedakannya dari kain hijau yang sah adalah hue, bukan saturasi:
 * teal rgb(11,105,66) milik figur androgynous ada di hue 155° dan tidak
 * tersentuh, sementara seluruh sisa background terukur di 114°–136°.
 *
 * Jangan dipakai di sheet Anima: itu jalur plant, dan daun teduh memang tinggal
 * di pita hue yang sama.
 */
export function isSeekerKeySpill(r, g, b) {
  if (g - Math.max(r, b) < 15) return false;
  const max = Math.max(r, g, b);
  if (max === 0) return false;
  const v = max / 255;
  if (v < 0.25) return false;
  const min = Math.min(r, g, b);
  const delta = max - min;
  const s = delta / max;
  if (s < 0.4) return false;
  let hue;
  if (max === r) hue = 60 * (((g - b) / delta) % 6);
  else if (max === g) hue = 60 * ((b - r) / delta + 2);
  else hue = 60 * ((r - g) / delta + 4);
  if (hue < 0) hue += 360;
  return hue >= 95 && hue <= 145;
}

/** Sisa background hijau teduh yang tersambung ke transparansi. Seeker saja. */
export function stripSeekerSpillInPlace(bitmap, width, height, opts = DEFAULTS) {
  // ponytail: flood dibatasi 12px. Terukur 8px pada sheet terburuk (automaton,
  // celah mantel); sisanya headroom. Kalau figur baru butuh lebih, ukur dulu —
  // pita hue-nya sempit, jadi kedalaman besar berarti ada kain hijau yang
  // bersambung ke luar dan itu harus dilihat mata, bukan dinaikkan diam-diam.
  return stripConnectedToTransparency(
    bitmap,
    width,
    height,
    isSeekerKeySpill,
    opts.alphaThreshold,
    12,
  );
}

/** Reproses sheet RGBA lama tanpa membutuhkan raw green-screen dari model. */
export async function stripWhiteKeylineFromRgba(pngBuffer, opts = DEFAULTS) {
  const image = await Image.decode(pngBuffer);
  const pixelsStripped = stripWhiteKeylineInPlace(
    image.bitmap,
    image.width,
    image.height,
    opts
  );
  if (pixelsStripped > 0) softenAlphaEdges(image.bitmap, image.width, image.height, opts);
  return {
    png: await encodeImage(image),
    pixelsStripped,
    size: [image.width, image.height],
  };
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
export function segmentPosePixels(bitmap, width, height, opts = DEFAULTS, layout = LAYOUT_2X2) {
  const pixelCount = width * height;
  const visited = new Uint8Array(pixelCount);
  const owners = new Uint8Array(pixelCount);
  owners.fill(255); // 0..n = indeks pose, 255 = background/noise

  // Satu queue dialokasikan sekali dan dipakai ulang untuk semua komponen.
  // Int32Array 1 juta piksel = 4 MB; lebih aman daripada Array<number> yang
  // bisa membengkak puluhan MB di Edge Function.
  const queue = new Int32Array(pixelCount);
  const poseCount = layout.poses.length;
  const grid = layout.grid;
  const cellW = Math.floor(width / grid);
  const cellH = Math.floor(height / grid);
  const boxes = Array(poseCount).fill(null);
  const opaquePixels = new Uint32Array(poseCount);
  const crossBoundaryPixels = new Uint32Array(poseCount);
  const components = [];

  for (let seed = 0; seed < pixelCount; seed++) {
    if (visited[seed] || bitmap[seed * 4 + 3] <= opts.alphaThreshold) continue;

    let start = 0;
    let end = 1;
    queue[0] = seed;
    visited[seed] = 1;
    const quadrantCounts = new Uint32Array(poseCount);
    let minX = width;
    let minY = height;
    let maxX = -1;
    let maxY = -1;

    while (start < end) {
      const p = queue[start++];
      const x = p % width;
      const y = Math.floor(p / width);
      const col = Math.min(grid - 1, Math.floor(x / cellW));
      const row = Math.min(grid - 1, Math.floor(y / cellH));
      quadrantCounts[row * grid + col]++;
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
    for (let q = 1; q < poseCount; q++) {
      if (quadrantCounts[q] > quadrantCounts[owner]) owner = q;
    }

    const ownQuadrantPixels = quadrantCounts[owner];
    opaquePixels[owner] += end;
    crossBoundaryPixels[owner] += end - ownQuadrantPixels;
    for (let i = 0; i < end; i++) owners[queue[i]] = owner;

    const component = { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
    components.push({
      owner,
      pose: layout.poses[owner],
      seed,
      pixels: end,
      foreign_pixels: end - ownQuadrantPixels,
      bbox: component,
    });
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
  for (let i = 0; i < poseCount; i++) {
    const pose = layout.poses[i];
    if (boxes[i]) bboxes[pose] = boxes[i];
    ownership[pose] = {
      opaque_pixels: opaquePixels[i],
      cross_boundary_pixels: crossBoundaryPixels[i],
    };
  }
  return { bboxes, owners, ownership, components };
}

function touchesInternalSeam(component, width, height, layout, opts) {
  const [col, row] = layout.quadrant[component.pose];
  const cellW = Math.floor(width / layout.grid);
  const cellH = Math.floor(height / layout.grid);
  const left = col * cellW;
  const top = row * cellH;
  const right = col === layout.grid - 1 ? width : (col + 1) * cellW;
  const bottom = row === layout.grid - 1 ? height : (row + 1) * cellH;
  const marginX = Math.round((right - left) * opts.seamMarginRatio);
  const marginY = Math.round((bottom - top) * opts.seamMarginRatio);
  const box = component.bbox;
  const boxRight = box.x + box.w;
  const boxBottom = box.y + box.h;
  return (
    (col > 0 && box.x < left + marginX)
    || (col < layout.grid - 1 && boxRight > right - marginX)
    || (row > 0 && box.y < top + marginY)
    || (row < layout.grid - 1 && boxBottom > bottom - marginY)
  );
}

/**
 * Menolak fragmen terlepas yang jatuh ke sel tetangga tanpa mengubah piksel.
 *
 * Hanya Idle yang aman diaudit keras: prompt melarang efek di sana. Pose lain
 * memang boleh membawa spark, debris, Z, bau, kotoran, dan fragmen VFX, sehingga
 * piksel saja tidak cukup untuk membedakan aksen sah dari kebocoran. Komponen
 * tersambung tetap ditangani ownership mask seperti sebelumnya.
 */
export function auditSourceGridSeams(components, width, height, layout, opts = DEFAULTS) {
  const largestByOwner = new Map();
  for (const component of components) {
    const current = largestByOwner.get(component.owner);
    if (!current || component.pixels > current.pixels) largestByOwner.set(component.owner, component);
  }

  const violations = [];

  for (const component of components) {
    const primary = largestByOwner.get(component.owner);
    if (
      component.pose !== "idle"
      || primary === component
      || component.pixels < opts.minSeamLeakPixels
      || !touchesInternalSeam(component, width, height, layout, opts)
    ) {
      continue;
    }
    violations.push({
      pose: component.pose,
      kind: "detached_idle_seam_fragment",
      seed: component.seed,
      pixels: component.pixels,
      bbox: component.bbox,
    });
  }

  return {
    passed: violations.length === 0,
    ratio: opts.seamMarginRatio,
    violations,
  };
}

export function auditDetachedCharacterComponents(components, opts = DEFAULTS) {
  const poses = ["idle", "attack", "sleep", "happy", "hungry", "dirty", "defeated"];
  const minPixels = opts.minDetachedCharacterPixels ?? DEFAULTS.minDetachedCharacterPixels;
  const violations = [];
  for (const pose of poses) {
    const parts = components
      .filter((component) => component.pose === pose && component.pixels >= minPixels)
      .sort((a, b) => b.pixels - a.pixels);
    if (parts.length === 0) continue;
    const allowedDetached = pose === "sleep" ? 2 : 0;
    for (const component of parts.slice(1 + allowedDetached)) {
      violations.push({
        pose,
        pixels: component.pixels,
        bbox: component.bbox,
        seed: component.seed,
        body_pixels: parts[0].pixels,
      });
    }
  }
  return { passed: violations.length === 0, violations };
}

function clearAlphaComponent(bitmap, width, height, seed, alphaThreshold) {
  if (bitmap[seed * 4 + 3] <= alphaThreshold) return 0;
  const queue = new Int32Array(width * height);
  let start = 0;
  let end = 1;
  let cleared = 0;
  queue[0] = seed;
  bitmap.set([0, 0, 0, 0], seed * 4);
  while (start < end) {
    const pixel = queue[start++];
    cleared++;
    const x = pixel % width;
    const y = Math.floor(pixel / width);
    for (let dy = -1; dy <= 1; dy++) {
      const nextY = y + dy;
      if (nextY < 0 || nextY >= height) continue;
      for (let dx = -1; dx <= 1; dx++) {
        if (dx === 0 && dy === 0) continue;
        const nextX = x + dx;
        if (nextX < 0 || nextX >= width) continue;
        const next = nextY * width + nextX;
        if (bitmap[next * 4 + 3] <= alphaThreshold) continue;
        bitmap.set([0, 0, 0, 0], next * 4);
        queue[end++] = next;
      }
    }
  }
  return cleared;
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
export function planFrames(bboxes, opts = DEFAULTS, layout = LAYOUT_2X2) {
  const present = layout.poses.filter((p) => bboxes[p]);
  if (present.length === 0) throw new Error("tidak ada satu pun bbox terdeteksi");

  const maxW = Math.max(...present.map((p) => bboxes[p].w));
  const maxH = Math.max(...present.map((p) => bboxes[p].h));
  const frameW = maxW + opts.framePadding * 2;
  const frameH = maxH + opts.framePadding * 2;

  const placements = {};
  for (const pose of present) {
    const [col, row] = layout.quadrant[pose];
    const bb = bboxes[pose];
    placements[pose] = {
      src: bb,
      region: [col * frameW, row * frameH, frameW, frameH],
      destX: col * frameW + Math.floor((frameW - bb.w) / 2),
      destY: row * frameH + (frameH - opts.framePadding - bb.h),
    };
  }

  return {
    frameW,
    frameH,
    sheetW: frameW * layout.grid,
    sheetH: frameH * layout.grid,
    placements,
  };
}

/** Salin hanya piksel yang memang dimiliki pose ini, bukan isi bbox tetangga. */
export function blitOwned(srcBitmap, srcW, src, owners, owner, dstBitmap, dstW, destX, destY) {
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

function shouldAuditDetachedCharacters(meta) {
  if (meta.kind === "create") return false;
  if (meta.kind === "evolve") return true;
  const major = promptMajor(meta.promptVersion);
  return major >= 26 && major < 31;
}

/**
 * Produksi memperbaiki cacat kosmetik; eval yang menghakimi art.
 *
 * Uang generation sudah terkunci saat Replicate menjawab, jadi menolak sheet di
 * post-processing tidak memperbaiki art apa pun — ia hanya menghapus aset yang
 * sudah dibayar dan memaksa pemain membayar lagi. Yang pantas menolak adalah
 * `eval/run.mjs`, tempat penilaian sebuah prompt version memang murah dan
 * informatif. Karena itu sejak v31 bintik melayang dan bocoran seam dibuang lalu
 * dicatat di `manifest.qa`, bukan dilempar. Versi lama sengaja tetap ketat
 * supaya penilaian art yang sudah tercatat tidak berubah surut.
 */
function shouldRepairDetachedArtifacts(meta, opts) {
  if (opts.removeIdleSeamLeaks === true) return true;
  if (opts.removeIdleSeamLeaks === false) return false;
  return promptMajor(meta.promptVersion) >= 31;
}

/**
 * Stripper matte hanya untuk prompt yang benar-benar MEMINTA keyline putih.
 *
 * Sampai v10 prompt menyuruh model menggambar keyline solid 3–5px, dan stripper
 * mengupasnya sampai bertemu dark line art. Sejak v11 prompt melarangnya, jadi
 * putih yang menyentuh transparansi bukan lagi matte melainkan art: Z tidur yang
 * diminta sel Sleep, dan semprotan air di sel fx. Keduanya tidak punya dark core
 * untuk menghentikan pengupasan, jadi stripper melahapnya sampai tinggal remah —
 * pada sheet Adult Hydron terukur 1.076px art terhapus, 727px di antaranya
 * semprotan fx_strike, dan dua Z 218px/146px pecah menjadi delapan remah yang
 * lalu menabrak `auditDetachedCharacterComponents`. Residu hijau tidak berubah
 * (0,00365 -> 0,00364), jadi mematikannya tidak menukar apa pun.
 *
 * Sheet tanpa `promptVersion` dianggap lama dan tetap dikupas.
 */
function shouldStripWhiteKeyline(meta, opts) {
  if (opts.stripWhiteKeyline === false) return false;
  return promptMajor(meta.promptVersion) < 11;
}

/**
 * Pipeline penuh: PNG mentah dari Replicate -> PNG RGBA rapi + manifest.
 *
 * @param {Uint8Array} pngBuffer PNG mentah, background hijau, opak
 * @param {object} meta { speciesKey, colorBucket, stage, promptVersion, vfxMotion, kind }
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

  // Layout dibutuhkan di sini (bukan hanya di segmentasi di bawah) supaya
  // flip pose bisa jalan sebelum chromaKeyInPlace, tepat sesudah decode+resize.
  const layout = layoutForPrompt(meta.promptVersion);
  for (const pose of meta.flipPoses ?? []) {
    if (!layout.quadrant[pose]) continue;
    flipQuadrantInPlace(bitmap, width, height, layout.quadrant[pose], layout.grid);
  }

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
  const whiteKeylinePixelsStripped = shouldStripWhiteKeyline(meta, opts)
    ? stripWhiteKeylineInPlace(bitmap, width, height, opts)
    : 0;
  // Pengupasan membuka dark line art sebagai tepi baru; haluskan sekali agar
  // outline tidak bergerigi. Tanpa piksel terkelupas, jangan proses tepi dua kali.
  if (whiteKeylinePixelsStripped > 0) softenAlphaEdges(bitmap, width, height, opts);

  // Segmentasi komponen terhubung membiarkan anggota tubuh melewati garis sel
  // tanpa ikut mencopy monster tetangga. Sel grid hanya menentukan pose pemilik,
  // bukan menjadi batas crop.
  const cellW = Math.floor(width / layout.grid);
  const cellH = Math.floor(height / layout.grid);
  const quadrantArea = cellW * cellH;
  let segmented = segmentPosePixels(bitmap, width, height, opts, layout);
  let seamAudit = promptMajor(meta.promptVersion) >= 12
    ? auditSourceGridSeams(segmented.components, width, height, layout, opts)
    : null;
  let seamCleanup = null;
  if (seamAudit && !seamAudit.passed && shouldRepairDetachedArtifacts(meta, opts)) {
    let pixels = 0;
    for (const violation of seamAudit.violations) {
      pixels += clearAlphaComponent(
        bitmap,
        width,
        height,
        violation.seed,
        opts.alphaThreshold,
      );
    }
    seamCleanup = {
      mode: "remove_detached_idle_components_v1",
      components: seamAudit.violations.length,
      pixels,
    };
    segmented = segmentPosePixels(bitmap, width, height, opts, layout);
    seamAudit = auditSourceGridSeams(segmented.components, width, height, layout, opts);
  }
  if (seamAudit && !seamAudit.passed) {
    const summary = seamAudit.violations
      .map((v) => `${v.pose}:${v.kind}:${v.pixels}px`)
      .join(", ");
    throw new Error(`sheet melanggar safe margin v12: ${summary}`);
  }
  let detachedCharacterAudit = shouldAuditDetachedCharacters(meta)
    ? auditDetachedCharacterComponents(segmented.components, opts)
    : null;
  let detachedCleanup = null;
  if (
    detachedCharacterAudit
    && !detachedCharacterAudit.passed
    && shouldRepairDetachedArtifacts(meta, opts)
  ) {
    // Semua atau tidak sama sekali: satu fragmen besar berarti sheet-nya memang
    // rusak, dan menghapus sisanya hanya akan menyamarkan kerusakan itu.
    const repairable = detachedCharacterAudit.violations.every(
      (item) => item.pixels <= item.body_pixels * opts.maxRepairableFragmentRatio,
    );
    if (repairable) {
      let pixels = 0;
      for (const item of detachedCharacterAudit.violations) {
        pixels += clearAlphaComponent(bitmap, width, height, item.seed, opts.alphaThreshold);
      }
      detachedCleanup = {
        mode: "remove_detached_character_fragments_v1",
        components: detachedCharacterAudit.violations.length,
        pixels,
      };
      segmented = segmentPosePixels(bitmap, width, height, opts, layout);
      detachedCharacterAudit = auditDetachedCharacterComponents(segmented.components, opts);
    }
  }
  if (detachedCharacterAudit && !detachedCharacterAudit.passed) {
    const summary = detachedCharacterAudit.violations
      .map((item) => `${item.pose}:${item.pixels}px`)
      .join(", ");
    throw new Error(`sheet v26 punya detached character components: ${summary}`);
  }
  const bboxes = segmented.bboxes;
  const rejected = {};

  for (const pose of layout.poses) {
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

  const plan = planFrames(bboxes, opts, layout);

  const out = new Image(plan.sheetW, plan.sheetH);
  out.bitmap.fill(0);
  for (const pose of detected) {
    const pl = plan.placements[pose];
    blitOwned(
      bitmap,
      width,
      pl.src,
      segmented.owners,
      layout.poses.indexOf(pose),
      out.bitmap,
      plan.sheetW,
      pl.destX,
      pl.destY
    );
  }

  const metrics = heightMetrics(bboxes, layout);

  const poses = {};
  for (const pose of detected) {
    poses[pose] = { region: plan.placements[pose].region };
    if (
      pose.startsWith("fx_")
      && ["projectile", "sweep", "impact", "bloom"].includes(meta.vfxMotion?.[pose])
    ) {
      poses[pose].motion = meta.vfxMotion[pose];
    }
  }

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
    render_metrics: {
      reference_height_px: metrics.heights.idle ?? metrics.heights.intro_idle ?? 1,
      reference_width_px: bboxes.idle?.w ?? bboxes.intro_idle?.w ?? plan.frameW,
    },
    qa: {
      cells_detected: detected.length,
      cells_rejected: rejected,
      green_residue_ratio: Number(greenResidueRatio(out.bitmap).toFixed(5)),
      standing_height_variance: metrics.standingVariance,
      bbox_heights: metrics.heights,
      pose_ownership: segmented.ownership,
      keyed_pixel_ratio: Number((keyedPixels / (bitmap.length / 4)).toFixed(4)),
      white_keyline_pixels_stripped: whiteKeylinePixelsStripped,
      ...(seamAudit ? { seam_margin: seamAudit } : {}),
      ...(seamCleanup ? { seam_cleanup: seamCleanup } : {}),
      ...(detachedCharacterAudit ? { detached_character: detachedCharacterAudit } : {}),
      ...(detachedCleanup ? { detached_cleanup: detachedCleanup } : {}),
      source_size: [decoded.width, decoded.height],
      // ponytail: erosi hijau hanya di cincin 1px terluar, bukan despill penuh.
      // Plafon: fringe yang lebih tebal dari 1px tetap lolos, dan itu terjadi
      // kalau white keyline dari prompt gagal muncul sehingga hijau membaur jauh
      // ke dalam tubuh. Pantau green_residue_ratio; kalau tembus 0,005 naikkan
      // erosinya jadi pita 2px, atau tambahkan despill (tarik channel hijau ke
      // max(r,b)) yang mempertahankan silhouette dengan harga tepi keabuan.
      warnings: buildWarnings(detected, metrics, out.bitmap, layout),
    },
  };

  return { png: await encodeImage(out), manifest };
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
export function heightMetrics(bboxes, layout = LAYOUT_2X2) {
  const heights = {};
  for (const pose of layout.poses) if (bboxes[pose]) heights[pose] = bboxes[pose].h;

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

function buildWarnings(detected, metrics, bitmap, layout = LAYOUT_2X2) {
  const warnings = [];
  if (detected.length < layout.poses.length) {
    warnings.push(`hanya ${detected.length}/${layout.poses.length} sel terdeteksi`);
  }
  if (metrics.standingVariance > 0.15) {
    warnings.push(`skala Idle vs Attack beda ${Math.round(metrics.standingVariance * 100)}%`);
  }
  for (const pose of metrics.tooTall) warnings.push(`pose ${pose} lebih tinggi dari idle`);
  const residue = greenResidueRatio(bitmap);
  if (residue > 0.001) warnings.push(`residu hijau ${(residue * 100).toFixed(2)}%`);
  return warnings;
}
