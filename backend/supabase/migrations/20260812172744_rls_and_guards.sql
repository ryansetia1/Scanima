-- RLS dan pagar hak akses. Aturan yang tidak bisa dinegosiasikan: semua mata
-- uang server-authoritative. Client boleh MELIHAT saldonya, tidak boleh
-- mengubahnya lewat jalur mana pun, termasuk panggilan langsung ke PostgREST
-- dengan anon key.
--
-- Ada dua lapis yang saling melengkapi, dan keduanya sengaja ada karena ini
-- soal uang:
--   1. Hak kolom Postgres — client secara struktural tidak punya privilege
--      UPDATE pada kolom mata uang, jadi upayanya gagal sebelum menyentuh RLS.
--   2. Trigger guard_profile_columns — menjaga invariannya tetap berlaku
--      kalau migrasi di masa depan memberikan UPDATE lebih longgar.

alter table profiles            enable row level security;
alter table animas              enable row level security;
alter table generations         enable row level security;
alter table quota_ledger        enable row level security;
alter table species_library     enable row level security;
alter table pending_discoveries enable row level security;
alter table app_config          enable row level security;

-- Pemain hanya melihat barisnya sendiri. Predikat kepemilikan wajib ada:
-- `to authenticated` sendirian hanya memeriksa peran, dan dengan anonymous
-- sign-in aktif semua pemain memegang peran itu.
create policy "baca profil sendiri" on profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "ubah kosmetik sendiri" on profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "baca anima sendiri" on animas
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy "ubah anima sendiri" on animas
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "baca generation sendiri" on generations
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy "baca ledger sendiri" on quota_ledger
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy "baca temuan tertunda sendiri" on pending_discoveries
  for select to authenticated using ((select auth.uid()) = owner_id);

-- Art di-share lintas pemain, jadi pustaka spesies boleh dibaca semua yang
-- login. Tidak ada policy tulis: pengisiannya lewat service role di webhook.
create policy "baca pustaka spesies" on species_library
  for select to authenticated using (true);

-- app_config tidak punya policy sama sekali: sakelar biaya bukan urusan client.

-- INSERT dan DELETE tidak pernah punya policy, jadi RLS sudah menolaknya.
-- Mencabut privilegenya juga membuat penolakan itu tidak bergantung pada
-- ketiadaan policy: policy permisif yang ditambahkan tanpa sengaja nanti tetap
-- tidak akan membuka jalur tulis.
revoke insert, delete, truncate on
  profiles, animas, generations, quota_ledger, species_library,
  pending_discoveries, app_config
  from anon, authenticated;
revoke all on app_config from anon, authenticated;

-- Kolom yang boleh ditulis client, disebutkan satu per satu. Kolom baru apa pun
-- di masa depan otomatis tertutup, yang merupakan arah gagal yang benar.
revoke update on profiles from anon, authenticated;
grant update (display_name, last_seen_at) on profiles to authenticated;

-- care sengaja client-writable: satu tap tidak perlu round-trip ke server dan
-- menyontek nilai kenyang tidak merugikan siapa pun. care_score TIDAK ikut,
-- karena ia gerbang evolusi dan evolusi memicu generation ~$0.07 tanpa mendebit
-- Core. Kalau client bisa menaikkan care_score, ia bisa memaksa kita membayar
-- gambar kapan saja. Akumulasinya nanti lewat RPC server-side.
revoke update on animas from anon, authenticated;
grant update (nickname, care, care_synced_at) on animas to authenticated;

create or replace function guard_profile_columns() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Whitelist, bukan blacklist: yang diperiksa adalah "apakah ada kolom LAIN
  -- yang berubah", jadi menambah kolom mata uang baru tidak perlu mengingat
  -- untuk memperbarui trigger ini.
  if current_role not in ('service_role', 'postgres', 'supabase_admin')
     and (to_jsonb(new) - 'display_name' - 'last_seen_at')
         is distinct from (to_jsonb(old) - 'display_name' - 'last_seen_at') then
    raise exception 'hanya display_name dan last_seen_at yang boleh diubah client';
  end if;
  return new;
end $$;

create trigger guard_profiles before update on profiles
  for each row execute function guard_profile_columns();
