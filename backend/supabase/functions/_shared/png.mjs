// Encoder PNG bersama untuk Node dan Deno edge runtime.
//
// Alasannya terukur, bukan preferensi: encoder ImageScript menulis filter byte 0
// pada SETIAP scanline (`png/node.js`, `tmp[tmp_offset++] = 0`) dan default-nya
// zlib level 1. Diukur pada `food_sheet.png` 1024x1024, adaptive row filtering
// bernilai 15,17% sementara menaikkan deflate dari level CompressionStream ke
// zlib level 9 hanya 0,22% — jadi filter-nya yang penting, bukan level-nya.
// ImageScript juga menstempel tEXt `Creation Time` dari `Date.now()`, sehingga
// piksel yang sama menghasilkan byte berbeda setiap kali di-encode — merepotkan
// karena `sheet_path` adalah SHA-256 dari byte terenkode.
//
// Adaptive filtering TIDAK selalu menang, dan itu bukan teori: pada
// `point-hex-vessel.png` ia 21,67% lebih BESAR daripada filter 0 rata, karena
// gambar itu punya banyak baris yang identik dan LZ77 lebih untung mencocokkan
// baris utuh daripada mendapat byte residu yang dekat nol. Heuristik "jumlah
// selisih absolut terkecil" per baris tidak bisa melihat pencocokan antar-baris.
// Karena itu encoder ini mencoba kedua strategi lalu memakai yang lebih kecil,
// sehingga hasilnya tidak pernah lebih besar daripada encoder lama.
//
// Modul ini tidak mengimpor apa pun: hanya bitmap RGBA mentah masuk, byte PNG
// keluar. Deflate-nya memakai `CompressionStream`, satu API web standar yang ada
// di Node 18+ dan Deno, jadi tidak ada specifier `npm:` yang bisa gagal di edge
// runtime dan tidak ada entri baru di `import_map.json`.
//
// Seluruhnya lossless: piksel yang terlihat tidak pernah berubah. Satu-satunya
// piksel yang disentuh adalah yang alpha-nya benar-benar 0, dan RGB di bawah
// alpha 0 tidak pernah tergambar.
//
// ponytail: lossless saja — filter + deflate + RGB transparan dibersihkan.
// Plafonnya sekitar setengah dari yang bisa dicapai TinyPNG, karena TinyPNG
// melakukan kuantisasi palet dan itu mengubah piksel. Upgrade-nya: kuantisasi
// median-cut ke PNG indexed, tetapi baru setelah gate QA post-process
// (green_residue_ratio, integritas tepi alpha) diperluas untuk mengukurnya.

const PNG_SIGNATURE = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const BYTES_PER_PIXEL = 4;

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i += 1) {
    crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/**
 * Nolkan RGB di piksel yang alpha-nya 0. Mengubah bitmap di tempat, mengikuti
 * konvensi chromaKeyInPlace di postprocess.mjs.
 *
 * Ini bukan pembersihan kosmetik. `softenAlphaEdges` mengikis tepi yang
 * terkontaminasi dengan hanya menulis alpha 0 dan meninggalkan RGB hijaunya,
 * jadi cincin tepi menyimpan warna acak yang harus ikut dikompresi deflate
 * padahal tidak pernah terlihat.
 */
export function clearTransparentRgb(bitmap) {
  let cleared = 0;
  for (let i = 0; i < bitmap.length; i += BYTES_PER_PIXEL) {
    if (bitmap[i + 3] !== 0) continue;
    if (bitmap[i] === 0 && bitmap[i + 1] === 0 && bitmap[i + 2] === 0) continue;
    bitmap[i] = 0;
    bitmap[i + 1] = 0;
    bitmap[i + 2] = 0;
    cleared += 1;
  }
  return cleared;
}

function paethPredictor(a, b, c) {
  const p = a + b - c;
  const pa = p > a ? p - a : a - p;
  const pb = p > b ? p - b : b - p;
  const pc = p > c ? p - c : c - p;
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/**
 * Tulis satu baris terfilter ke `dest` dan kembalikan skornya. Skor memakai
 * heuristik baku libpng: jumlah nilai absolut byte hasil filter dibaca sebagai
 * signed, karena nilai yang dekat nol paling murah bagi deflate.
 */
function applyRowFilter(type, current, previous, dest, stride, bytesPerPixel) {
  let score = 0;
  for (let x = 0; x < stride; x += 1) {
    const left = x >= bytesPerPixel ? current[x - bytesPerPixel] : 0;
    const up = previous[x];
    const upLeft = x >= bytesPerPixel ? previous[x - bytesPerPixel] : 0;
    let value;
    switch (type) {
      case 1:
        value = current[x] - left;
        break;
      case 2:
        value = current[x] - up;
        break;
      case 3:
        value = current[x] - ((left + up) >> 1);
        break;
      case 4:
        value = current[x] - paethPredictor(left, up, upLeft);
        break;
      default:
        value = current[x];
    }
    const byte = value & 0xff;
    dest[x] = byte;
    score += byte < 128 ? byte : 256 - byte;
  }
  return score;
}

/**
 * Bangun blok scanline PNG. `adaptive` memilih filter terbaik per baris; matikan
 * untuk mendapat filter 0 rata seperti encoder lama, yang lebih kecil pada gambar
 * dengan banyak baris identik.
 */
export function filterScanlines(
  bitmap,
  width,
  height,
  { adaptive = true, bytesPerPixel = BYTES_PER_PIXEL } = {},
) {
  const stride = width * bytesPerPixel;
  const out = new Uint8Array((stride + 1) * height);
  const candidate = adaptive ? new Uint8Array(stride) : null;
  let previous = new Uint8Array(stride);
  for (let y = 0; y < height; y += 1) {
    const current = bitmap.subarray(y * stride, y * stride + stride);
    const rowStart = y * (stride + 1);
    if (!adaptive) {
      out.set(current, rowStart + 1);
      continue;
    }
    let bestType = 0;
    let bestScore = Infinity;
    for (let type = 0; type <= 4; type += 1) {
      const score = applyRowFilter(type, current, previous, candidate, stride, bytesPerPixel);
      if (score < bestScore) {
        bestScore = score;
        bestType = type;
      }
    }
    out[rowStart] = bestType;
    applyRowFilter(
      bestType,
      current,
      previous,
      out.subarray(rowStart + 1),
      stride,
      bytesPerPixel,
    );
    previous = current;
  }
  return out;
}

function pngChunk(type, body) {
  const chunk = new Uint8Array(12 + body.length);
  const view = new DataView(chunk.buffer);
  view.setUint32(0, body.length);
  for (let i = 0; i < 4; i += 1) chunk[4 + i] = type.charCodeAt(i);
  chunk.set(body, 8);
  view.setUint32(8 + body.length, crc32(chunk.subarray(4, 8 + body.length)));
  return chunk;
}

/**
 * Rangkai IHDR/IDAT/IEND. Tanpa chunk tEXt, jadi piksel yang sama selalu
 * menghasilkan byte yang sama di runtime yang sama.
 */
export function assemblePng(width, height, deflated, { colorType = 6 } = {}) {
  const ihdr = new Uint8Array(13);
  const header = new DataView(ihdr.buffer);
  header.setUint32(0, width);
  header.setUint32(4, height);
  ihdr.set([8, colorType, 0, 0, 0], 8);

  const chunks = [
    PNG_SIGNATURE,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflated),
    pngChunk("IEND", new Uint8Array(0)),
  ];
  const total = chunks.reduce((sum, part) => sum + part.length, 0);
  const png = new Uint8Array(total);
  let offset = 0;
  for (const part of chunks) {
    png.set(part, offset);
    offset += part.length;
  }
  return png;
}

export async function deflateBytes(bytes) {
  if (typeof CompressionStream !== "function") {
    throw new Error("PNG_DEFLATE_UNAVAILABLE");
  }
  const compressor = new CompressionStream("deflate");
  const writer = compressor.writable.getWriter();
  // Sengaja tidak di-await sebelum readable dibaca: writable dan readable satu
  // pipe, jadi menunggu write() selesai lebih dulu bisa menggantung pada input
  // yang lebih besar daripada buffer internalnya.
  const written = writer.write(bytes).then(() => writer.close());
  const deflated = new Uint8Array(await new Response(compressor.readable).arrayBuffer());
  await written;
  return deflated;
}

/**
 * Jalur encode kanonis. Terima bitmap RGBA mentah supaya modul ini tetap bebas
 * dependensi dan bisa dipakai dua runtime.
 *
 * Dua pass deflate, bukan satu, supaya hasilnya tidak pernah lebih besar daripada
 * filter 0 rata. Terukur 312 ms untuk satu reproses sheet 1024x1024 sebelum
 * perubahan ini; pass kedua menambah satu deflate lagi pada blok berukuran sama.
 *
 * ponytail: pilih strategi filter dengan mencoba keduanya, bukan memprediksinya.
 * Plafonnya dua kali kerja deflate — masih jauh di bawah batas CPU 2 detik Edge
 * Function. Upgrade kalau sheet melewati sekitar 4 megapiksel: putuskan lewat
 * satu deflate pada sampel baris, bukan pada seluruh gambar.
 */
export async function encodeOptimizedPng(bitmap, width, height) {
  clearTransparentRgb(bitmap);
  const [adaptive, flat] = await Promise.all([
    deflateBytes(filterScanlines(bitmap, width, height)),
    deflateBytes(filterScanlines(bitmap, width, height, { adaptive: false })),
  ]);
  return assemblePng(width, height, adaptive.length <= flat.length ? adaptive : flat);
}

/**
 * Encode gambar opak sebagai PNG RGB (color type 2), bukan RGBA.
 *
 * Reference Idle Evolution sudah diratakan ke chroma green dan alpha-nya selalu
 * 255. Mengirimnya sebagai RGBA membuat safety checker GPT Image gagal membaca
 * dimensi channel (`Unable to infer channel dimension format`) sebelum E005.
 * Membuang byte alpha yang konstan mempertahankan piksel tampak persis sama dan
 * memberi checker bentuk H×W×3 yang memang ia dukung.
 */
export async function encodeOpaqueRgbPng(bitmap, width, height) {
  const rgb = new Uint8Array(width * height * 3);
  for (let src = 0, dest = 0; src < bitmap.length; src += 4, dest += 3) {
    rgb[dest] = bitmap[src];
    rgb[dest + 1] = bitmap[src + 1];
    rgb[dest + 2] = bitmap[src + 2];
  }
  const [adaptive, flat] = await Promise.all([
    deflateBytes(filterScanlines(rgb, width, height, { bytesPerPixel: 3 })),
    deflateBytes(filterScanlines(rgb, width, height, {
      adaptive: false,
      bytesPerPixel: 3,
    })),
  ]);
  return assemblePng(
    width,
    height,
    adaptive.length <= flat.length ? adaptive : flat,
    { colorType: 2 },
  );
}

/** Bentuk yang nyaman untuk pemanggil yang sudah memegang Image ImageScript. */
export async function encodeImage(image) {
  return await encodeOptimizedPng(image.bitmap, image.width, image.height);
}
