-- Seeker Avatar ikut satu submit onboarding, sebagai argumen opsional kelima.
--
-- Bukan PATCH kedua sesudah `complete`: dua tulisan berarti pemain baru bisa
-- berakhir dengan nama tersimpan dan figur tidak, tepat pada layar yang paling
-- tidak boleh setengah jadi. Ia mengikuti pola birth year dan gender, yang juga
-- opsional dan juga ditulis di sini.
--
-- Parameter baru berarti signature baru, dan `create or replace` akan membuat
-- overload kedua alih-alih menggantinya — dua fungsi dengan default yang sama
-- membuat panggilan bernama PostgREST ambigu. Jadi yang lama di-drop dulu.
-- Drop itu juga membuang revoke/grant miliknya: fungsi baru lahir dengan
-- EXECUTE untuk PUBLIC, dan karena ia SECURITY DEFINER dengan p_owner sebagai
-- argumen, membiarkannya berarti setiap client boleh menamai profil pemain
-- lain lewat /rest/v1/rpc. Revoke di bawah bukan formalitas.
drop function if exists public.complete_seeker_profile(uuid, text, integer, text);

create or replace function public.complete_seeker_profile(
  p_owner uuid,
  p_name text,
  p_birth_year integer default null,
  p_gender text default null,
  p_avatar text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_name text;
  v_avatar text;
  v_min_year integer := extract(year from current_date)::integer - 13;
begin
  v_name := public._validated_seeker_name(p_name);
  if p_birth_year is not null and (p_birth_year < 1900 or p_birth_year > v_min_year) then
    raise exception 'INVALID_BIRTH_YEAR';
  end if;
  if p_gender is not null
     and p_gender not in ('woman', 'man', 'non_binary', 'another_identity', 'prefer_not_to_say') then
    raise exception 'INVALID_GENDER';
  end if;

  select * into v_profile
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  -- Gender di atas menolak nilai asing, figur di sini mengabaikannya, dan
  -- perbedaan itu disengaja. Gender adalah jawaban pemain tentang dirinya:
  -- menyimpan yang salah berarti menyimpan kebohongan tentang orang, jadi lebih
  -- baik gagal keras. Figur cuma kosmetik yang bisa diganti gratis kapan saja,
  -- dan kalau ia boleh menggagalkan transaksi ini maka ia bisa mengunci pemain
  -- di luar namanya sendiri — persis yang tidak boleh terjadi pada baris picker
  -- yang selalu punya pilihan default. Client memperlakukan slug asing dengan
  -- cara yang sama (`SeekerRoster.normalize()` menggambar figur default), jadi
  -- kedua sisi berakhir menampilkan figur yang sama.
  --
  -- NULL di sini berarti "biarkan apa adanya", bukan "kosongkan": pemain yang
  -- sempat memilih dari Profile sebelum menamai dirinya tidak boleh kehilangan
  -- figurnya hanya karena ia tidak menyentuh picker onboarding. `in (...)`
  -- menjawab NULL untuk p_avatar NULL, jadi satu CASE menutup kedua jalur.
  --
  -- Daftar slug-nya sama dengan CHECK `profiles_seeker_avatar_in_roster` dan
  -- dengan `SeekerRoster.SLUGS`; figur kelima nanti berarti satu nilai baru di
  -- ketiganya.
  v_avatar := case
    when p_avatar in ('androgynous', 'masculine', 'feminine', 'automaton') then p_avatar
    else v_profile.seeker_avatar
  end;

  if v_profile.seeker_name is not null then
    -- Figur sengaja tidak ikut membentuk identitas request ini. Ia dapat
    -- berubah dari Profile kapan saja sesudah onboarding, jadi memasukkannya ke
    -- perbandingan akan membuat replay yang sah dijawab SEEKER_PROFILE_COMPLETE
    -- hanya karena pemain sudah mengganti figurnya di antara dua percobaan.
    if lower(v_profile.seeker_name) = lower(v_name)
       and v_profile.birth_year is not distinct from p_birth_year
       and v_profile.gender is not distinct from p_gender then
      return to_jsonb(v_profile);
    end if;
    raise exception 'SEEKER_PROFILE_COMPLETE';
  end if;

  begin
    update public.profiles
       set seeker_name = v_name,
           seeker_name_changed_at = now(),
           birth_year = p_birth_year,
           gender = p_gender,
           seeker_avatar = v_avatar
     where id = p_owner
    returning * into v_profile;
  exception
    when unique_violation then raise exception 'SEEKER_NAME_TAKEN';
  end;
  return to_jsonb(v_profile);
end $$;

revoke all on function public.complete_seeker_profile(uuid, text, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_seeker_profile(uuid, text, integer, text, text)
  to service_role;
