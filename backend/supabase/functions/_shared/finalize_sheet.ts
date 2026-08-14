// Langkah terakhir Genesis: PNG mentah dari model menjadi sheet RGBA yang siap
// dipakai Godot, plus baris pustaka dan Anima yang menetas.
//
// Dipisahkan dari handler webhook dengan sengaja. Handler bertanggung jawab atas
// hal-hal yang berhubungan dengan dunia luar — tanda tangan, host yang diizinkan,
// unduhan — sementara fungsi ini bekerja pada byte yang sudah ada di tangan. Itu
// yang membuatnya bisa diuji dengan sheet asli yang sudah kita bayar, tanpa
// memalsukan tanda tangan Replicate dan tanpa satu pun panggilan API berbiaya.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { postprocessSheet } from "./postprocess.mjs";
import { sha256Hex } from "./supa.ts";

export type BarisGeneration = {
  id: string;
  owner_id: string;
  anima_id: string | null;
  prompt_version: string;
  photo_path: string | null;
  vision_result?: {
    strike_vfx?: { motion?: string };
    surge_vfx?: { motion?: string };
  } | null;
};

export type BarisAnima = {
  id: string;
  species_key: string;
  color_bucket: string;
  stage: number;
};

export async function finalizeSheet(
  db: SupabaseClient,
  gen: BarisGeneration,
  anima: BarisAnima,
  rawPng: Uint8Array,
) {
  const t0 = Date.now();
  const { png, manifest } = await postprocessSheet(rawPng, {
    speciesKey: anima.species_key,
    colorBucket: anima.color_bucket,
    stage: anima.stage,
    promptVersion: gen.prompt_version,
    vfxMotion: {
      fx_strike: gen.vision_result?.strike_vfx?.motion,
      fx_surge: gen.vision_result?.surge_vfx?.motion,
    },
  });
  const msPostprocess = Date.now() - t0;

  // Nama berbasis hash isi, bukan uuid: re-run webhook yang sama tidak menumpuk
  // file baru, dan dua sheet yang identik byte-per-byte menunjuk objek yang sama.
  const hash = await sha256Hex(png);
  const sheetPath = `${hash.slice(0, 16)}.png`;
  manifest.sheet = sheetPath;

  const { error: errUnggah } = await db.storage
    .from("sheets")
    .upload(sheetPath, new Blob([png], { type: "image/png" }), {
      contentType: "image/png",
      upsert: true,
    });
  if (errUnggah) throw new Error(`unggah sheet gagal: ${errUnggah.message}`);

  // Pemain lain bisa sudah membuat baris ini lebih dulu, misalnya dua Genesis
  // paralel untuk spesies dan warna yang sama. Yang duluan yang dipakai: menimpa
  // art yang sudah dipegang pemain lain akan mengubah Anima mereka di belakang
  // punggung mereka.
  const { error: errPustaka } = await db.from("species_library").upsert(
    {
      species_key: anima.species_key,
      color_bucket: anima.color_bucket,
      stage: anima.stage,
      sheet_path: sheetPath,
      manifest,
      prompt_version: gen.prompt_version,
    },
    { onConflict: "species_key,color_bucket,stage", ignoreDuplicates: true },
  );
  if (errPustaka) throw new Error(`isi pustaka spesies gagal: ${errPustaka.message}`);

  if (gen.anima_id) {
    const { error } = await db.from("animas").update({ status: "ready" }).eq("id", gen.anima_id);
    if (error) throw new Error(`tandai anima ready gagal: ${error.message}`);
  }

  const { error: errGen } = await db
    .from("generations")
    .update({ status: "succeeded", finished_at: new Date().toISOString() })
    .eq("id", gen.id);
  if (errGen) throw new Error(`tandai generation succeeded gagal: ${errGen.message}`);

  // Foto mentah pemain dihapus begitu tidak dibutuhkan lagi. Kegagalan menghapus
  // dicatat tapi tidak membatalkan hatch yang sudah berhasil: Anima-nya sudah
  // ada dan sheet-nya sudah terunggah, sementara foto yang tertinggal adalah
  // masalah kebersihan yang bisa dibereskan belakangan.
  if (gen.photo_path) {
    const { error } = await db.storage.from("photos").remove([gen.photo_path]);
    if (error) console.error(`gagal menghapus foto mentah ${gen.photo_path}: ${error.message}`);
  }

  return { sheetPath, manifest, msPostprocess };
}
