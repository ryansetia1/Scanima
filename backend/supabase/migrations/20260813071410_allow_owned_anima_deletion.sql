-- Delete memakai Data API + RLS langsung: tidak ada mata uang yang berubah dan
-- tidak perlu Edge Function service-role untuk operasi yang sudah bisa dibatasi
-- native oleh Postgres. Generation tetap hidup karena FK-nya ON DELETE SET NULL;
-- care_events ikut hilang karena hanya merupakan detail milik Anima tersebut.
create policy "hapus anima sendiri" on public.animas
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

grant delete on public.animas to authenticated;

-- Nickname bisa ditulis client. Pagar panjang wajib ada di trust boundary
-- database, bukan hanya di LineEdit Godot yang bisa dilewati lewat Data API.
alter table public.animas
  add constraint animas_nickname_length
  check (char_length(btrim(nickname)) between 1 and 32);
