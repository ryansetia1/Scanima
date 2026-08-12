// Verifikasi tanda tangan webhook Replicate (format standard-webhooks).
//
// Ini batas kepercayaan, jadi bukan tempat untuk berhemat. Webhook palsu yang
// lolos bisa menandai generation sebagai berhasil dengan URL gambar pilihan
// penyerang, dan gambar itu masuk ke species_library yang DI-SHARE semua pemain.
// Jadi kerusakannya bukan satu Anima, melainkan pustaka art yang teracuni.
//
// Perbandingan hash-nya diserahkan ke crypto.subtle.verify, bukan ditulis sendiri
// dengan ===, supaya waktunya tidak bergantung pada isi tanda tangan.

const TOLERANSI_DETIK = 300;

function base64KeBytes(b64: string): Uint8Array {
  const biner = atob(b64);
  const out = new Uint8Array(biner.length);
  for (let i = 0; i < biner.length; i++) out[i] = biner.charCodeAt(i);
  return out;
}

export async function verifikasiTandaTangan(
  headers: Headers,
  body: string,
  secret: string,
): Promise<boolean> {
  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signature = headers.get("webhook-signature");
  if (!id || !timestamp || !signature) return false;

  // Tanpa pemeriksaan ini, satu webhook sah yang pernah terekam bisa diputar ulang
  // kapan saja, dan tiap pengulangan adalah satu upaya menulis ulang status
  // generation.
  const umur = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(umur) || umur > TOLERANSI_DETIK) return false;

  const rahasia = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  const key = await crypto.subtle.importKey(
    "raw",
    base64KeBytes(rahasia),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const data = new TextEncoder().encode(`${id}.${timestamp}.${body}`);

  // Header bisa memuat beberapa tanda tangan dipisah spasi, misalnya saat secret
  // sedang dirotasi. Cukup satu yang cocok.
  for (const bagian of signature.split(" ")) {
    const [versi, b64] = bagian.split(",");
    if (versi !== "v1" || !b64) continue;
    try {
      if (await crypto.subtle.verify("HMAC", key, base64KeBytes(b64), data)) return true;
    } catch {
      // tanda tangan yang tidak bisa didekode bukan alasan menerima yang lain
    }
  }
  return false;
}
