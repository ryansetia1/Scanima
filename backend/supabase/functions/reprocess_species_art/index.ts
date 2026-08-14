// Tool migrasi sementara untuk mengupas keyline putih dari species_library lama.
// Deploy hanya dengan verify_jwt=false + ART_MIGRATION_TOKEN acak, jalankan,
// lalu hapus fungsi dan secret-nya. PNG lama sengaja tidak dihapus agar rollback.

import { adminClient, json, sha256Hex } from "../_shared/supa.ts";
import { stripWhiteKeylineFromRgba } from "../_shared/postprocess.mjs";

type ArtRow = {
  species_key: string;
  color_bucket: string;
  stage: number;
  sheet_path: string;
  manifest: unknown;
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? structuredClone(value as Record<string, unknown>)
    : {};
}

function authorized(req: Request): boolean {
  const expected = Deno.env.get("ART_MIGRATION_TOKEN");
  return Boolean(expected) && req.headers.get("authorization") === `Bearer ${expected}`;
}

function migrationState(row: ArtRow) {
  const manifest = record(row.manifest);
  const qa = record(manifest.qa);
  return {
    manifest,
    qa,
    previous: typeof qa.white_keyline_previous_sheet_path === "string"
      ? qa.white_keyline_previous_sheet_path
      : "",
    alreadyBorderless: Number(qa.white_keyline_pixels_stripped ?? 0) > 0,
  };
}

async function processRow(row: ArtRow, apply: boolean) {
  const state = migrationState(row);
  if (state.previous || state.alreadyBorderless) {
    return { species: row.species_key, status: "skipped" };
  }

  const db = adminClient();
  const { data: blob, error: downloadError } = await db.storage.from("sheets").download(row.sheet_path);
  if (downloadError || !blob) {
    throw new Error(`unduh ${row.sheet_path}: ${downloadError?.message ?? "kosong"}`);
  }

  const result = await stripWhiteKeylineFromRgba(
    new Uint8Array(await blob.arrayBuffer())
  );
  if (!apply || result.pixelsStripped === 0) {
    return {
      species: row.species_key,
      status: apply ? "no_keyline" : "preview",
      old_path: row.sheet_path,
      pixels_stripped: result.pixelsStripped,
    };
  }

  const hash = await sha256Hex(result.png);
  const newPath = `${hash.slice(0, 16)}.png`;
  const { error: uploadError } = await db.storage
    .from("sheets")
    .upload(newPath, new Blob([result.png], { type: "image/png" }), {
      contentType: "image/png",
      upsert: true,
    });
  if (uploadError) throw new Error(`unggah ${newPath}: ${uploadError.message}`);

  state.qa.white_keyline_previous_sheet_path = row.sheet_path;
  state.qa.white_keyline_pixels_stripped = result.pixelsStripped;
  state.qa.white_keyline_migrated_at = new Date().toISOString();
  state.manifest.qa = state.qa;
  state.manifest.sheet = newPath;

  const { data: updated, error: updateError } = await db
    .from("species_library")
    .update({ sheet_path: newPath, manifest: state.manifest })
    .eq("species_key", row.species_key)
    .eq("color_bucket", row.color_bucket)
    .eq("stage", row.stage)
    .eq("sheet_path", row.sheet_path)
    .select("sheet_path")
    .maybeSingle();
  if (updateError) throw new Error(`update ${row.species_key}: ${updateError.message}`);
  if (!updated) return { species: row.species_key, status: "changed_concurrently" };

  return {
    species: row.species_key,
    status: "migrated",
    old_path: row.sheet_path,
    new_path: newPath,
    pixels_stripped: result.pixelsStripped,
  };
}

async function rollbackRow(row: ArtRow) {
  const state = migrationState(row);
  if (!state.previous) return { species: row.species_key, status: "skipped" };

  const currentPath = row.sheet_path;
  state.manifest.sheet = state.previous;
  delete state.qa.white_keyline_previous_sheet_path;
  delete state.qa.white_keyline_pixels_stripped;
  delete state.qa.white_keyline_migrated_at;
  state.manifest.qa = state.qa;

  const db = adminClient();
  const { data: updated, error } = await db
    .from("species_library")
    .update({ sheet_path: state.previous, manifest: state.manifest })
    .eq("species_key", row.species_key)
    .eq("color_bucket", row.color_bucket)
    .eq("stage", row.stage)
    .eq("sheet_path", currentPath)
    .select("sheet_path")
    .maybeSingle();
  if (error) throw new Error(`rollback ${row.species_key}: ${error.message}`);
  return {
    species: row.species_key,
    status: updated ? "rolled_back" : "changed_concurrently",
    restored_path: state.previous,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "hanya POST" });
  if (!authorized(req)) return json(401, { error: "token migrasi tidak sah" });

  const body = await req.json().catch(() => ({}));
  const action = String(body.action ?? "preview");
  if (!["preview", "apply", "rollback"].includes(action)) {
    return json(400, { error: "action harus preview, apply, atau rollback" });
  }

  const db = adminClient();
  const { data, error } = await db
    .from("species_library")
    .select("species_key, color_bucket, stage, sheet_path, manifest")
    .order("species_key")
    .order("color_bucket")
    .order("stage");
  if (error) return json(500, { error: error.message });

  const rows = (data ?? []) as ArtRow[];
  const candidates = rows.filter((row) => {
    const state = migrationState(row);
    return action === "rollback"
      ? Boolean(state.previous)
      : !state.previous && !state.alreadyBorderless;
  });
  // ponytail: dua PNG per invocation menjaga CPU edge <2s. Ulangi request
  // idempoten sampai remaining=0; naikkan hanya jika ukuran sheet mengecil.
  const limit = action === "rollback" ? 10 : 2;
  const chosen = candidates.slice(0, limit);

  try {
    const results = [];
    for (const row of chosen) {
      results.push(
        action === "rollback"
          ? await rollbackRow(row)
          : await processRow(row, action === "apply")
      );
    }
    return json(200, {
      action,
      processed: results.length,
      remaining: Math.max(0, candidates.length - chosen.length),
      results,
    });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});
