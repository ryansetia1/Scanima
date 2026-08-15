import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { BATTLE_SHEET_SIGNED_TTL } from "./gallery.mjs";
import { asSnapshotArray } from "./team_snapshot.mjs";

export async function withSignedRoster(
  db: SupabaseClient,
  value: unknown,
): Promise<Record<string, unknown>[]> {
  const roster = asSnapshotArray(value) as Record<string, unknown>[] | null;
  if (!roster) throw new Error("INVALID_TEAM_SNAPSHOT");
  return await Promise.all(roster.map(async (raw) => {
    const member = { ...raw };
    if (member.system_asset === "placeholder" || member.system_asset === "chapter") {
      if (member.system_asset === "chapter" && typeof member.sheet_url !== "string") {
        throw new Error("TEAM_ART_NOT_READY");
      }
      delete member.owner_id;
      delete member.nickname;
      delete member.sheet_path;
      return member;
    }
    const path = typeof member.sheet_path === "string" ? member.sheet_path : "";
    if (!path) throw new Error("TEAM_ART_NOT_READY");
    const { data, error } = await db.storage
      .from("anima_sheets")
      .createSignedUrl(path, BATTLE_SHEET_SIGNED_TTL);
    if (error) throw error;
    if (!data?.signedUrl) throw new Error("TEAM_ART_NOT_READY");
    delete member.owner_id;
    delete member.nickname;
    delete member.sheet_path;
    member.sheet_url = data.signedUrl;
    return member;
  }));
}
