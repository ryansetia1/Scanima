-- Seeker Avatar: satu kolom pilihan kosmetik pada profil pemain.
--
-- Sengaja TIDAK ada RPC baru dan tidak ada operasi Edge Function baru untuk
-- menulisnya. Itu keputusan sadar, bukan pagar yang lupa dipasang. Aturan
-- server-authoritative di project ini mengikat mata uang: Core, Bits, dan scan
-- charge diputuskan Postgres karena client yang berbohong soal ketiganya
-- membuat kita membayar gambar atau memberi barang gratis. Avatar bukan mata
-- uang — ia tidak dibeli, tidak unik, tidak ber-namespace, dan CHECK di bawah
-- mengunci nilainya ke roster yang ikut ter-bundel di build. Policy RLS "ubah
-- kosmetik sendiri" sudah membatasi pemain ke row-nya sendiri, jadi hal
-- terburuk yang bisa dilakukan client adalah memakai avatar valid pada dirinya
-- sendiri, persis yang memang boleh ia lakukan lewat UI. Jangan "perbaiki"
-- ini menjadi RPC: itu menambah satu boundary yang tidak menutup apa pun.

alter table public.profiles
  add column if not exists seeker_avatar text;

-- Daftar slug-nya adalah Seeker Roster di `game/scripts/seeker_roster.gd`;
-- figur kelima nanti berarti satu nilai baru di kedua tempat. NULL berarti
-- belum memilih — digambar sebagai figur default, tetapi tetap dapat dibedakan
-- dari pemain yang benar-benar memilih figur default itu.
alter table public.profiles
  add constraint profiles_seeker_avatar_in_roster
  check (seeker_avatar in ('androgynous', 'masculine', 'feminine', 'automaton'));

-- Aditif, satu kolom di atas hak yang sudah ada. `revoke update on <tabel>`
-- sengaja tidak dipakai: ia ikut mencabut hak kolom display_name dan
-- last_seen_at, dan migrasi yang lupa memberikannya ulang mematikan onboarding
-- tanpa galat yang menunjuk ke sini.
grant update (seeker_avatar) on public.profiles to authenticated;

-- Lapis kedua di sebelah hak kolom. Whitelist-nya bertambah satu nama; sisa
-- kolom profil tetap tertutup untuk peran client.
create or replace function public.guard_profile_columns() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Whitelist, bukan blacklist: yang diperiksa adalah "apakah ada kolom LAIN
  -- yang berubah", jadi menambah kolom mata uang baru tidak perlu mengingat
  -- untuk memperbarui trigger ini.
  if current_role not in ('service_role', 'postgres', 'supabase_admin')
     and (to_jsonb(new) - 'display_name' - 'last_seen_at' - 'seeker_avatar')
         is distinct from (to_jsonb(old) - 'display_name' - 'last_seen_at' - 'seeker_avatar') then
    raise exception 'hanya display_name, last_seen_at, dan seeker_avatar yang boleh diubah client';
  end if;
  return new;
end $$;

-- Client membaca avatarnya lewat jalur yang sama dengan saldo dan statistik,
-- jadi tidak ada round trip kedua hanya untuk satu string.
create or replace function public.seeker_profile_summary(p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_anima_count integer;
  v_species_count integer;
begin
  perform public._grant_weekly_core_if_eligible(p_owner);

  select * into v_profile from public.profiles where id = p_owner;
  if not found then raise exception 'NO_PROFILE'; end if;

  select count(*)::integer, count(distinct species_key)::integer
    into v_anima_count, v_species_count
    from public.animas
   where owner_id = p_owner and status = 'ready';

  return jsonb_build_object(
    'id', v_profile.id,
    'seeker_name', v_profile.seeker_name,
    'seeker_name_changed_at', v_profile.seeker_name_changed_at,
    'seeker_avatar', v_profile.seeker_avatar,
    'birth_year', v_profile.birth_year,
    'gender', v_profile.gender,
    'seeker_xp', v_profile.seeker_xp,
    'guest_scan_used_at', v_profile.guest_scan_used_at,
    'account_upgraded_at', v_profile.account_upgraded_at,
    'battle_victories', v_profile.battle_victories,
    'anima_count', v_anima_count,
    'species_count', v_species_count,
    'active_anima_id', v_profile.active_anima_id,
    'genesis_cores', v_profile.genesis_cores,
    'bits', v_profile.bits,
    'client_config', jsonb_build_object(
      'min_client_version', coalesce(
        (select value from public.app_config where key = 'min_client_version'),
        '{"android":0,"ios":0,"desktop":0}'::jsonb
      )
    ),
    'created_at', v_profile.created_at
  );
end $$;
