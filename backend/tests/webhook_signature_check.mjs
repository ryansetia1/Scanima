#!/usr/bin/env node
// Pemeriksaan verifikasi tanda tangan webhook. Hal terkecil yang gagal kalau
// pagar ini rusak:
//
//   node backend/tests/webhook_signature_check.mjs
//
// Kenapa ini yang diberi test dan bukan bagian lain dari webhook: fungsi ini satu
// -satunya yang memisahkan Replicate dari siapa pun yang tahu URL kita, dan mode
// gagalnya diam. Verifier yang salah menangani base64 atau salah menyusun string
// yang ditandatangani akan MENERIMA semua kiriman, dan tidak ada gejala sampai
// ada gambar asing di species_library yang di-share seluruh pemain.
//
// Modul aslinya .ts untuk Deno, tapi ia hanya memakai crypto.subtle, atob, dan
// TextEncoder — tiga-tiganya ada di Node, jadi bisa diuji tanpa memasang Deno.
// Node 23+ menanggalkan tipe sendiri saat mengimpor .ts.

import assert from "node:assert/strict";
import { verifikasiTandaTangan } from "../supabase/functions/_shared/webhook_signature.ts";

const RAHASIA_B64 = "c2NhbmltYS11ammtdWppLXJhaGFzaWEtMzJieXRl"; // 32 byte acak, hanya untuk uji
const SECRET = `whsec_${RAHASIA_B64}`;
const ID = "msg_2abcDEF";
const BODY = JSON.stringify({ id: "pred_123", status: "succeeded", output: "https://replicate.delivery/x.png" });

function base64KeBytes(b64) {
  const biner = atob(b64);
  return Uint8Array.from(biner, (c) => c.charCodeAt(0));
}

async function tandaTangani(id, timestamp, body, rahasiaB64 = RAHASIA_B64) {
  const key = await crypto.subtle.importKey(
    "raw",
    base64KeBytes(rahasiaB64),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const tanda = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${timestamp}.${body}`));
  return btoa(String.fromCharCode(...new Uint8Array(tanda)));
}

const sekarang = () => Math.floor(Date.now() / 1000);

function header(id, timestamp, signature) {
  return new Headers({
    "webhook-id": id,
    "webhook-timestamp": String(timestamp),
    "webhook-signature": signature,
  });
}

let n = 0;
async function uji(nama, fn) {
  await fn();
  console.log(`${++n}. ${nama}`);
}

// Yang paling mudah terlewat: test yang hanya memeriksa penolakan bisa lulus
// dengan verifier yang menolak SEMUANYA, dan itu berarti tidak ada webhook sah
// yang pernah diproses. Jadi jalur sah diuji lebih dulu.
await uji("kiriman sah diterima", async () => {
  const ts = sekarang();
  const sig = await tandaTangani(ID, ts, BODY);
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v1,${sig}`), BODY, SECRET), true);
});

await uji("prefiks whsec_ opsional, nilainya sama", async () => {
  const ts = sekarang();
  const sig = await tandaTangani(ID, ts, BODY);
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v1,${sig}`), BODY, RAHASIA_B64), true);
});

await uji("body diubah satu byte -> ditolak", async () => {
  const ts = sekarang();
  const sig = await tandaTangani(ID, ts, BODY);
  const dirusak = BODY.replace("pred_123", "pred_124");
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v1,${sig}`), dirusak, SECRET), false);
});

await uji("rahasia salah -> ditolak", async () => {
  const ts = sekarang();
  const lain = btoa("rahasia-lain-yang-panjangnya-32byte").slice(0, 44);
  const sig = await tandaTangani(ID, ts, BODY, lain);
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v1,${sig}`), BODY, SECRET), false);
});

await uji("id ikut ditandatangani, jadi id lain -> ditolak", async () => {
  const ts = sekarang();
  const sig = await tandaTangani(ID, ts, BODY);
  assert.equal(await verifikasiTandaTangan(header("msg_lain", ts, `v1,${sig}`), BODY, SECRET), false);
});

await uji("kiriman lama tidak bisa diputar ulang", async () => {
  const ts = sekarang() - 301; // toleransinya 300 detik
  const sig = await tandaTangani(ID, ts, BODY);
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v1,${sig}`), BODY, SECRET), false);
});

await uji("timestamp masa depan yang jauh juga ditolak", async () => {
  const ts = sekarang() + 3600;
  const sig = await tandaTangani(ID, ts, BODY);
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v1,${sig}`), BODY, SECRET), false);
});

await uji("timestamp bukan angka tidak lolos lewat NaN", async () => {
  const sig = await tandaTangani(ID, "kemarin", BODY);
  assert.equal(await verifikasiTandaTangan(header(ID, "kemarin", `v1,${sig}`), BODY, SECRET), false);
});

await uji("header hilang -> ditolak, bukan error", async () => {
  const ts = sekarang();
  const sig = await tandaTangani(ID, ts, BODY);
  for (const kurang of ["webhook-id", "webhook-timestamp", "webhook-signature"]) {
    const h = header(ID, ts, `v1,${sig}`);
    h.delete(kurang);
    assert.equal(await verifikasiTandaTangan(h, BODY, SECRET), false, `tanpa ${kurang}`);
  }
});

await uji("versi selain v1 diabaikan", async () => {
  const ts = sekarang();
  const sig = await tandaTangani(ID, ts, BODY);
  assert.equal(await verifikasiTandaTangan(header(ID, ts, `v2,${sig}`), BODY, SECRET), false);
});

await uji("rotasi rahasia: satu tanda tangan cocok di antara beberapa", async () => {
  const ts = sekarang();
  const sahKita = await tandaTangani(ID, ts, BODY);
  const lain = await tandaTangani(ID, ts, BODY, btoa("kunci-lama-yang-sudah-dirotasi--").slice(0, 44));
  assert.equal(
    await verifikasiTandaTangan(header(ID, ts, `v1,${lain} v1,${sahKita}`), BODY, SECRET),
    true,
    "yang cocok ada di posisi kedua",
  );
});

await uji("tanda tangan rusak tidak melempar dan tidak meloloskan", async () => {
  const ts = sekarang();
  for (const buruk of ["v1,bukan-base64!!!", "v1,", "sampah", "", "v1"]) {
    assert.equal(await verifikasiTandaTangan(header(ID, ts, buruk), BODY, SECRET), false, `sig: ${buruk}`);
  }
});

console.log("\nwebhook_signature: OK");
