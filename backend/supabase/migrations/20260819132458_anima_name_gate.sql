-- Gerbang nama untuk Rename Anima, dan satu daftar terlarang untuk dua nama.
--
-- `animas.nickname` adalah satu-satunya kolom yang boleh ditulis client secara
-- langsung lewat PATCH PostgREST, dan sampai sekarang pagarnya hanya panjang
-- 1..32. Nickname memang tidak pernah sampai ke pemain lain — Atlas
-- memproyeksikan `atlas_forms.display_name` dan snapshot Battle membuang
-- kolomnya — tetapi jaminan itu hidup di kode Edge Function, bukan di
-- database, jadi teks yang masuk tetap harus wajar.
--
-- Daftar impersonasi/profanity dipindah keluar dari `_validated_seeker_name`
-- supaya tidak ada dua daftar yang perlahan berbeda isi. Perilaku seeker tidak
-- berubah: nama seeker tidak pernah mengandung spasi atau tanda baca, jadi
-- pemeriksaan per kata di bawah menghasilkan tepat satu kata yang sama dengan
-- nama utuhnya.
--
-- Validator ini sengaja TIDAK dicabut dari `authenticated`. Keduanya fungsi
-- murni yang hanya mengembalikan string tervalidasi — tidak menyentuh mata uang,
-- tidak membaca baris, dan aturannya sudah dicerminkan client — jadi aturan
-- revoke untuk SECURITY DEFINER tidak berlaku di sini, sama seperti
-- `_validated_seeker_name` yang sudah live.

create or replace function public._name_is_reserved(p_name text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(btrim(coalesce(p_name, ''))) = any (array[
    'admin', 'administrator', 'moderator', 'scanima', 'seeker',
    'support', 'system', 'official', 'staff', 'null'
  ])
  or lower(coalesce(p_name, '')) ~ '(fuck|shit|bitch|cunt|kontol|memek|ngentot)';
$$;

create or replace function public._validated_seeker_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  if v_name !~ '^[A-Za-z][A-Za-z0-9_]{2,15}$' then
    raise exception 'INVALID_SEEKER_NAME';
  end if;
  if public._name_is_reserved(v_name) then
    raise exception 'SEEKER_NAME_RESERVED';
  end if;
  return v_name;
end $$;

create or replace function public._validated_anima_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  -- Spasi, apostrof, dan hubung diizinkan karena ini nama peliharaan, bukan
  -- handle identitas seperti seeker_name. Batas 32 mengikuti CHECK
  -- `animas_nickname_length` yang sudah ada supaya tidak lahir angka kedua.
  --
  -- ponytail: ASCII saja karena satu-satunya kolom locale yang dibangun adalah
  -- English. Plafon: nama beraksara non-Latin ditolak; longgarkan bersamaan
  -- dengan locale kedua di `game/locales/ui.csv`.
  if v_name !~ '^[A-Za-z0-9][A-Za-z0-9 ''-]{0,31}$'
     or v_name !~ '[A-Za-z]'
     or v_name ~ '  ' then
    raise exception 'INVALID_ANIMA_NAME';
  end if;
  if public._name_is_reserved(v_name)
     or exists (
       select 1
         from unnest(regexp_split_to_array(v_name, '[^A-Za-z0-9]+')) as t(word)
        where public._name_is_reserved(t.word)
     ) then
    raise exception 'ANIMA_NAME_RESERVED';
  end if;
  return v_name;
end $$;

-- HANYA UPDATE. Nickname generated ditulis oleh `claim_capture`/`claim_genesis`
-- di dalam transaksi capture yang sudah membayar Vision dan generation, dan
-- prinsip di `_shared/vision.mjs` berlaku di sini juga: penamaan tidak boleh
-- menggagalkan capture berbayar. Nama itu lahir dari `selectMorphemeName()`
-- yang sudah menyaring `nameIsSafeForPlayers()`, jadi INSERT tidak butuh
-- gerbang kedua yang bisa membunuh $0.07 karena satu stem baru di daftar.
-- Terverifikasi: tidak ada satu pun RPC yang menulis `update animas set
-- nickname`, jadi trigger ini hanya menyala untuk Rename pemain.
create or replace function public.animas_validate_nickname()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nickname := public._validated_anima_name(new.nickname);
  return new;
end $$;

drop trigger if exists animas_validate_nickname on public.animas;
create trigger animas_validate_nickname
before update on public.animas
for each row
when (new.nickname is distinct from old.nickname)
execute function public.animas_validate_nickname();
