// Langkah terakhir Genesis / Evolution: PNG mentah dari model menjadi sheet RGBA
// yang siap dipakai Godot, plus baris pustaka atau art privat per Anima.
//
// Dipisahkan dari handler webhook dengan sengaja. Handler bertanggung jawab atas
// hal-hal yang berhubungan dengan dunia luar — tanda tangan, host yang diizinkan,
// unduhan — sementara fungsi ini bekerja pada byte yang sudah ada di tangan.
//
// Evolution memakai commit_evolution (bukan refund_generation); create tetap
// memakai refund_generation saat webhook gagal.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { postprocessSheet } from "./postprocess.mjs";
import { sha256Hex } from "./supa.ts";

export type BarisGeneration = {
  id: string;
  owner_id: string;
  anima_id: string | null;
  kind?: string;
  target_stage?: number | null;
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
  sheet_path?: string | null;
  typing_version?: number;
};

export async function finalizeSheet(
  db: SupabaseClient,
  gen: BarisGeneration,
  anima: BarisAnima,
  rawPng: Uint8Array,
) {
  const isEvolve = gen.kind === "evolve";
  const postStage = isEvolve ? (gen.target_stage ?? anima.stage) : anima.stage;

  const t0 = Date.now();
  const { png, manifest } = await postprocessSheet(rawPng, {
    speciesKey: anima.species_key,
    colorBucket: anima.color_bucket,
    stage: postStage,
    promptVersion: gen.prompt_version,
    kind: gen.kind ?? "create",
    vfxMotion: {
      fx_strike: gen.vision_result?.strike_vfx?.motion,
      fx_surge: gen.vision_result?.surge_vfx?.motion,
    },
  });
  const msPostprocess = Date.now() - t0;

  const hash = await sha256Hex(png);
  const isPrivateCapture = isEvolve || (anima.typing_version ?? 1) >= 2;
  const sheetName = `${hash.slice(0, 16)}.png`;
  manifest.sheet = sheetName;

  let sheetPath: string;
  if (isPrivateCapture) {
    sheetPath = `${gen.owner_id}/${anima.id}/${sheetName}`;

    const { error: errUnggah } = await db.storage
      .from("anima_sheets")
      .upload(sheetPath, new Blob([png], { type: "image/png" }), {
        contentType: "image/png",
        upsert: true,
      });
    if (errUnggah) throw new Error(`unggah anima sheet gagal: ${errUnggah.message}`);

    if (isEvolve) {
      const { error } = await db.rpc("commit_evolution", {
        p_gen_id: gen.id,
        p_sheet_path: sheetPath,
        p_manifest: manifest,
      });
      if (error) {
        if (sheetPath !== anima.sheet_path) {
          const { error: cleanupError } = await db.storage
            .from("anima_sheets")
            .remove([sheetPath]);
          if (cleanupError) {
            console.error(`gagal membersihkan sheet evolusi ${sheetPath}: ${cleanupError.message}`);
          }
        }
        throw new Error(`commit evolution gagal: ${error.message}`);
      }
    } else if (gen.anima_id) {
      const { error } = await db.from("animas").update({
        status: "ready",
        sheet_path: sheetPath,
        manifest,
      }).eq("id", gen.anima_id);
      if (error) throw new Error(`tandai anima ready gagal: ${error.message}`);
    }
  } else {
    sheetPath = sheetName;

    const { error: errUnggah } = await db.storage
      .from("sheets")
      .upload(sheetPath, new Blob([png], { type: "image/png" }), {
        contentType: "image/png",
        upsert: true,
      });
    if (errUnggah) throw new Error(`unggah sheet gagal: ${errUnggah.message}`);

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
  }

  if (!isEvolve) {
    const { error: errGen } = await db
      .from("generations")
      .update({ status: "succeeded", finished_at: new Date().toISOString() })
      .eq("id", gen.id);
    if (errGen) throw new Error(`tandai generation succeeded gagal: ${errGen.message}`);
  }

  if (gen.photo_path) {
    const { error } = await db.storage.from("photos").remove([gen.photo_path]);
    if (error) console.error(`gagal menghapus foto mentah ${gen.photo_path}: ${error.message}`);
  }

  return { sheetPath, manifest, msPostprocess, privateCapture: isPrivateCapture, evolved: isEvolve };
}
