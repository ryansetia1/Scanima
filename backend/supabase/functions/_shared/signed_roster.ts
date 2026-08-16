import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { BATTLE_SHEET_SIGNED_TTL } from "./gallery.mjs";
import { asSnapshotArray } from "./team_snapshot.mjs";

// ponytail: URL bertanda tangan di-cache per path selama isolate hidup, jadi satu
// battle empat lawan empat tidak memanggil Storage 8-12 kali tiap turn. Plafonnya
// satu isolate (tidak dibagi lintas region) dan 512 path; upgrade ke store bersama
// hanya kalau jumlah roster unik per 10 menit benar-benar melewati itu.
const SIGN_CACHE_MAX = 512;
const SIGN_REFRESH_MARGIN_MS = 300_000;
const signCache = new Map<string, { url: string; expires_at: number }>();

export async function signSheetUrl(
  db: SupabaseClient,
  path: string,
): Promise<string> {
  const now = Date.now();
  const hit = signCache.get(path);
  if (hit && hit.expires_at - now > SIGN_REFRESH_MARGIN_MS) return hit.url;
  const { data, error } = await db.storage
    .from("anima_sheets")
    .createSignedUrl(path, BATTLE_SHEET_SIGNED_TTL);
  if (error) throw error;
  const url = data?.signedUrl ?? "";
  if (!url) return "";
  if (signCache.size >= SIGN_CACHE_MAX) signCache.clear();
  signCache.set(path, { url, expires_at: now + BATTLE_SHEET_SIGNED_TTL * 1000 });
  return url;
}

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
    const signedUrl = await signSheetUrl(db, path);
    if (!signedUrl) throw new Error("TEAM_ART_NOT_READY");
    delete member.owner_id;
    delete member.nickname;
    delete member.sheet_path;
    member.sheet_url = signedUrl;
    return member;
  }));
}
