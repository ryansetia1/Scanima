-- rls_auto_enable() adalah event trigger bawaan platform Supabase yang menyalakan
-- RLS otomatis pada setiap tabel baru di schema public. Ia SECURITY DEFINER milik
-- postgres, dan Postgres memberi EXECUTE ke PUBLIC secara default, sehingga ia
-- terekspos di /rest/v1/rpc/rls_auto_enable untuk anon maupun authenticated.
--
-- Terukur: dipanggil sebagai fungsi biasa oleh peran authenticated, ia TIDAK
-- error dan tidak melakukan apa pun (pg_event_trigger_ddl_commands() kosong di
-- luar konteks event trigger, jadi loop-nya tidak pernah berjalan). Jadi bukan
-- eskalasi hak, tapi tetap endpoint publik yang tidak kita perlukan.
--
-- Mencabut EXECUTE aman untuk event trigger-nya: hak eksekusi event trigger
-- diperiksa saat CREATE EVENT TRIGGER, bukan saat ia menyala. Diverifikasi dengan
-- membuat tabel uji setelah revoke dan memastikan RLS-nya tetap otomatis aktif.

revoke all on function public.rls_auto_enable() from public, anon, authenticated;
