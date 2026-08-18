import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { BATTLE_SHEET_SIGNED_TTL } from "./gallery_constants.mjs";

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
  return (await signSheetUrls(db, [path])).get(path) ?? "";
}

export async function signSheetUrls(
  db: SupabaseClient,
  paths: string[],
): Promise<Map<string, string>> {
  const now = Date.now();
  const uniquePaths = [...new Set(paths.filter(Boolean))];
  const result = new Map<string, string>();
  const missing: string[] = [];
  for (const path of uniquePaths) {
    const hit = signCache.get(path);
    if (hit && hit.expires_at - now > SIGN_REFRESH_MARGIN_MS) {
      result.set(path, hit.url);
    } else {
      missing.push(path);
    }
  }
  if (missing.length === 0) return result;

  const { data, error } = await db.storage
    .from("anima_sheets")
    .createSignedUrls(missing, BATTLE_SHEET_SIGNED_TTL);
  if (error) throw error;
  if (signCache.size + missing.length > SIGN_CACHE_MAX) signCache.clear();
  for (const [index, item] of (data ?? []).entries()) {
    const path = typeof item.path === "string" ? item.path : missing[index];
    const url = item.signedUrl ?? "";
    if (!path || !url) continue;
    result.set(path, url);
    signCache.set(path, {
      url,
      expires_at: now + BATTLE_SHEET_SIGNED_TTL * 1000,
    });
  }
  return result;
}

export async function withSignedRoster(
  db: SupabaseClient,
  value: unknown,
): Promise<Record<string, unknown>[]> {
  const { asSnapshotArray } = await import("./team_snapshot.mjs");
  const roster = asSnapshotArray(value) as Record<string, unknown>[] | null;
  if (!roster) throw new Error("INVALID_TEAM_SNAPSHOT");
  return await Promise.all(roster.map(async (raw) => {
    const member = { ...raw };
    if (
      member.system_asset === "placeholder" || member.system_asset === "chapter"
    ) {
      if (
        member.system_asset === "chapter" &&
        typeof member.sheet_url !== "string"
      ) {
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
