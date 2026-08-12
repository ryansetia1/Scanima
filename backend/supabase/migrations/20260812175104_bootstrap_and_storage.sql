-- Dua hal yang harus ada sebelum endpoint pertama bisa dipakai: profil yang lahir
-- bersama akun, dan tempat menyimpan foto serta sheet.

-- Anonymous sign-in berarti tidak ada layar pendaftaran, jadi tidak ada momen
-- alami untuk membuat profil. Tanpa trigger ini, panggilan pertama pemain baru
-- gagal dengan NO_PROFILE dari fungsi kuota — dan gagalnya di tempat yang salah,
-- jauh dari sebabnya.
create or replace function public.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;

-- SECURITY DEFINER di schema public otomatis mendapat EXECUTE dari PUBLIC. Fungsi
-- trigger tidak berguna kalau dipanggil langsung, tapi ia tetap muncul sebagai
-- endpoint rpc dan sebagai temuan advisor, jadi ditutup seperti fungsi kuota.
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Dua bucket dengan sifat yang sengaja berbeda. `photos` privat dan isinya fana:
-- foto mentah pemain dihapus setelah post-processing selesai. `sheets` publik,
-- karena art memang di-share lintas pemain lewat CDN dan itu inti penghematan
-- biaya kita — satu sheet dipakai semua pemain yang men-scan spesies yang sama.
--
-- Batas ukuran dan mime ditegakkan bucket, bukan oleh endpoint kita. Itu sebabnya
-- client boleh mengunggah langsung: pagarnya ada di platform, bukan di kode yang
-- harus kita tulis dan uji sendiri.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('photos', 'photos', false, 6291456, array['image/jpeg', 'image/png', 'image/webp']),
  ('sheets', 'sheets', true,  4194304, array['image/png'])
on conflict (id) do nothing;

-- Pemain hanya boleh menulis ke dalam folder namanya sendiri. Prefix inilah yang
-- menggantikan endpoint penerbit signed URL: hak akses per-path adalah fitur
-- Storage, dan menulis endpoint sendiri untuk itu berarti menulis ulang pagar
-- yang sudah ada.
create policy "unggah foto ke folder sendiri" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Sengaja tidak ada policy select/update/delete untuk `photos`: pemain tidak perlu
-- membaca kembali fotonya, dan yang menghapusnya adalah service role setelah
-- sheet-nya jadi. Bucket `sheets` publik sehingga bacanya tidak lewat RLS sama
-- sekali; tulisnya tetap service role saja.
