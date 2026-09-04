-- Uji aturan kuota dan pagar akses. Hal terkecil yang gagal kalau invarian uang
-- rusak. Tidak ada framework: satu blok DO, jadi satu transaksi. Kalau ada assert
-- yang gagal, seluruh blok rollback dan tidak ada baris uji yang tertinggal;
-- kalau lulus, baris ujinya dihapus di akhir. Aman dijalankan berulang.
--
--   supabase db query --file backend/tests/quota_rules.sql --linked
--   psql "$SUPABASE_DB_URL" -f backend/tests/quota_rules.sql
--   (atau lewat Supabase MCP: execute_sql dengan isi file ini)
--
-- Lulus = satu baris NOTICE "SEMUA UJI LULUS".

do $uji$
declare
  u1        uuid := '00000000-0000-4000-8000-000000000001';
  u2        uuid := '00000000-0000-4000-8000-000000000002';
  u3        uuid := '00000000-0000-4000-8000-000000000003';
  u4        uuid := '00000000-0000-4000-8000-000000000004';
  u5        uuid := '00000000-0000-4000-8000-000000000005';
  v_spesies text := 'uji_cache_species';
  v_stats   jsonb := '{"hp":100,"atk":40,"def":30,"spd":50,"special":40}'::jsonb;
  v_care    jsonb := '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb;
  v_visi    jsonb := '{"species_key":"mouse_plastic","color_bucket":"gray"}'::jsonb;
  v_gen     public.generations;
  v_j       jsonb;
  v_j2      jsonb;
  v_id      uuid;
  v_refund  uuid;
  v_sukses  uuid;
  v_care_anima uuid;
  v_bench_anima uuid;
  v_delete_own uuid;
  v_delete_other uuid;
  v_delete_generation uuid;
  v_cores_before_delete int;
  v_battle_player uuid;
  v_battle_bot uuid;
  v_battle_session uuid;
  v_atlas_form uuid;
  v_battle_player_snapshot jsonb;
  v_battle_bot_snapshot jsonb;
  v_system_bot_snapshot jsonb;
  v_battle_state jsonb;
  v_team_ids uuid[];
  v_defense_ids uuid[];
  v_team_id uuid;
  v_defense_team_id uuid;
  v_team_candidate uuid;
  v_team_session uuid;
  v_team_snapshot jsonb;
  v_opponent_snapshot jsonb;
  v_team_state jsonb;
  v_team_scores_before int[];
  v_expedition_chapter uuid;
  v_expedition_version uuid;
  v_expedition_version_next uuid;
  v_expedition_trophy uuid;
  v_expedition_run uuid;
  v_expedition_encounter uuid;
  v_expedition_map jsonb;
  v_expedition_party jsonb;
  v_expedition_state jsonb;
  v_name_anima uuid;
  v_evolution_anima uuid;
  v_evolution_other uuid;
  v_evolution_gen uuid;
  v_evolution_success_gen uuid;
  v_evolution_cores int;
  v_evo_flag_prev jsonb;
  v_synthesis_a uuid;
  v_synthesis_b uuid;
  v_synthesis_gen uuid;
  v_synthesis_result uuid;
  v_synthesis_cores int;
  v_synthesis_bits int;
  v_synthesis_config jsonb;
  v_synthesis_seed_roll int;
  v_bits_before_battle int;
  v_score_before_battle int;
  v_wins_before_battle int;
  v_seeker_xp int;
  v_seeker_victories int;
  v_weekly_at timestamptz;
  v         int;
  n         int;
  ok        bool;
  v_mod_anima uuid;
  v_mod_entry uuid;
  v_mod_art_hash text;
  v_mod_case uuid;
  v_mod_case2 uuid;
  v_sanction_id uuid;
  v_sanction_id2 uuid;
  v_rep_c uuid;
  v_decision_count int;
  v_audit_count int;
begin
  -- Idempoten: sisa run yang gagal di tengah tidak boleh menggagalkan run ini.
  delete from auth.users where id in (u1, u2, u3, u4, u5);
  perform set_config('scanima.deleting_profiles', '', true);
  delete from public.species_library where species_key = v_spesies;
  insert into auth.users (id, is_anonymous)
  values (u1, false), (u2, true), (u3, true);

  -- Profilnya TIDAK disisipkan di sini: trigger on_auth_user_created yang
  -- membuatnya. Kalau trigger itu hilang, panggilan pertama pemain baru gagal
  -- dengan NO_PROFILE dari fungsi kuota — jauh dari sebabnya, dan tidak ada uji
  -- lain yang akan menunjukkan letaknya.
  assert (select count(*) from public.profiles where id in (u1, u2, u3)) = 3,
         'bootstrap profil saat sign-in anonim tidak jalan';
  assert (select count(*) from public.profiles where id in (u1, u2) and bits = 50) = 2,
         'profil baru harus menerima 50 starter Bits';
  assert (select count(*) from public.quota_ledger
           where owner_id in (u1, u2) and currency = 'bits'
             and delta = 50 and reason = 'care_starter') = 2,
         'starter Bits harus tercatat di ledger';
  assert (select count(*) from public.profiles
           where id in (u1, u2, u3) and genesis_cores = 1) = 3,
         'profil baru harus menerima tepat 1 starter Core';
  assert (select count(*) from public.quota_ledger
           where owner_id in (u1, u2, u3) and currency = 'genesis_cores'
             and delta = 1 and reason = 'starter_guest') = 3,
         'starter guest Core harus tercatat tepat sekali';

  assert public.anima_exp_to_next(1) = 5
         and public.anima_exp_to_next(5) = 5
         and public.anima_exp_to_next(6) = 10
         and public.anima_exp_to_next(39) = 40
         and public.anima_exp_to_next(40) = 0,
         'biaya Level harus naik per band lima Level';
  assert public.anima_exp_for_level(16) = 150
         and public.anima_exp_for_level(36) = 700
         and public.anima_exp_for_level(40) = 860,
         'threshold Adult, Evolved, dan Level cap harus kanonis';
  assert public.anima_level_from_exp(149) = 15
         and public.anima_level_from_exp(150) = 16
         and public.anima_level_from_exp(699) = 35
         and public.anima_level_from_exp(700) = 36
         and public.anima_level_from_exp(859) = 39
         and public.anima_level_from_exp(860) = 40,
         'inverse Level harus tepat di setiap boundary utama';
  assert public.battle_exp_yield(1, 1, 'even') = 2
         and public.battle_exp_yield(1, 11, 'even') = 5
         and public.battle_exp_yield(40, 40, 'tough') = 6
         and public.battle_exp_yield(1, 40, 'boss') = 8,
         'yield Battle harus memuat level lawan, underdog, tier, dan clamp';

  insert into auth.identities
    (provider_id, user_id, identity_data, provider)
  values
    ('uji-google-u1', u1, jsonb_build_object('sub', 'uji-google-u1'), 'google');
  v_j := public.upgrade_seeker_account(u1);
  assert (v_j->>'genesis_cores')::int = 4
         and (v_j->>'account_upgraded_at') is not null
         and (select delta from public.quota_ledger
               where owner_id = u1 and reason = 'starter_google') = 3,
         'upgrade Google harus melengkapi starter lifetime dari 1 menjadi 4';
  v_j2 := public.upgrade_seeker_account(u1);
  assert (v_j2->>'genesis_cores')::int = 4
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'starter_google') = 1,
         'retry upgrade tidak boleh menggandakan +3 Core';
  delete from public.quota_ledger where owner_id = u1 and reason = 'starter_google';
  update public.profiles
     set genesis_cores = 3
   where id = u1;
  insert into public.quota_ledger (owner_id, currency, delta, reason)
  values (u1, 'genesis_cores', 2, 'starter_google');
  v_j := public.upgrade_seeker_account(u1);
  assert (v_j->>'genesis_cores')::int = 4
         and (select delta from public.quota_ledger
               where owner_id = u1 and reason = 'starter_team') = 1,
         'akun Google lama dengan lifetime 3 mendapat +1 starter_team';
  v_j2 := public.upgrade_seeker_account(u1);
  assert (v_j2->>'genesis_cores')::int = 4
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'starter_team') = 1,
         'retry top-up tidak boleh menggandakan Core keempat';
  begin
    perform public.upgrade_seeker_account(u2);
    ok := false;
  exception when others then ok := (sqlerrm = 'ACCOUNT_STILL_ANONYMOUS');
  end;
  assert ok, 'akun anonim tidak boleh menerima grant upgrade Google';

  insert into auth.users (id, is_anonymous) values (u4, false);
  delete from public.quota_ledger where owner_id = u4 and reason = 'starter_guest';
  insert into public.quota_ledger (owner_id, currency, delta, reason)
  values (u4, 'genesis_cores', 3, 'starter_legacy');
  update public.profiles set genesis_cores = 9 where id = u4;
  insert into auth.identities
    (provider_id, user_id, identity_data, provider)
  values
    ('uji-google-u4', u4, jsonb_build_object('sub', 'uji-google-u4'), 'google');
  v_j := public.upgrade_seeker_account(u4);
  assert (v_j->>'genesis_cores')::int = 10
         and not exists (
           select 1 from public.quota_ledger
            where owner_id = u4 and reason = 'starter_google'
         )
         and (select delta from public.quota_ledger
               where owner_id = u4 and reason = 'starter_team') = 1,
         'akun legacy dengan lifetime starter 3 mendapat tepat +1 Core keempat';
  v_j2 := public.upgrade_seeker_account(u4);
  assert (v_j2->>'genesis_cores')::int = 10
         and (select count(*) from public.quota_ledger
               where owner_id = u4 and reason = 'starter_team') = 1,
         'retry legacy tidak boleh menggandakan starter_team';

  -- Nama dan figur mendarat lewat satu submit, jadi pemain baru tidak bisa
  -- berakhir dengan yang satu tersimpan dan yang lain tidak.
  v_j := public.complete_seeker_profile(u1, 'TestSeeker', 2000, null, 'feminine');
  assert v_j->>'seeker_name' = 'TestSeeker', 'profil Seeker harus tersimpan';
  assert v_j->>'seeker_avatar' = 'feminine',
         'figur yang dipilih saat onboarding harus ikut tersimpan';
  begin
    perform public.complete_seeker_profile(u2, 'Has Space', null, null);
    ok := false;
  exception when others then ok := (sqlerrm = 'INVALID_SEEKER_NAME');
  end;
  assert ok, 'nama Seeker tidak boleh mengandung spasi';
  begin
    perform public.complete_seeker_profile(u2, 'testseeker', null, null);
    ok := false;
  exception when others then ok := (sqlerrm = 'SEEKER_NAME_TAKEN');
  end;
  assert ok, 'nama Seeker harus unik tanpa membedakan huruf besar kecil';
  -- Picker onboarding selalu punya figur default terpilih, jadi ia tidak boleh
  -- punya kuasa menahan pemain di luar namanya sendiri: slug asing diabaikan
  -- seperti `SeekerRoster.normalize()` mengabaikannya di client.
  perform public.complete_seeker_profile(u2, 'GuestTwo', null, 'prefer_not_to_say', 'wizard');
  assert (select seeker_name = 'GuestTwo' and seeker_avatar is null
            from public.profiles where id = u2),
         'figur di luar roster harus diabaikan tanpa ikut menggagalkan nama';
  -- Argumen kelima yang hilang berarti "biarkan apa adanya", bukan
  -- "kosongkan" — pemain yang sempat memilih dari Profile sebelum menamai
  -- dirinya tidak boleh kehilangan figurnya karena picker tidak disentuh.
  update public.profiles set seeker_avatar = 'automaton' where id = u4;
  perform public.complete_seeker_profile(u4, 'LegacyFour', null, null);
  assert (select seeker_avatar from public.profiles where id = u4) = 'automaton',
         'onboarding tanpa menyentuh picker tidak boleh menghapus figur yang sudah ada';
  begin
    perform public.rename_seeker(u1, 'RenamedSeeker');
    ok := false;
  exception when others then ok := (sqlerrm = 'SEEKER_NAME_COOLDOWN');
  end;
  assert ok, 'rename Seeker harus menunggu cooldown 30 hari';
  update public.profiles
     set seeker_name_changed_at = now() - interval '31 days'
   where id = u1;
  assert (public.rename_seeker(u1, 'RenamedSeeker')->>'seeker_name') = 'RenamedSeeker',
         'rename sesudah cooldown harus berhasil';
  assert (select count(*) from public.catalog_items where active) = 18,
         'katalog v1 harus berisi 9 makanan dan 9 item';
  update public.profiles set display_name = 'uji' where id in (u1, u2);

  assert extract(hour from ((public.battle_daily_reward_status(u1)->>'reset_at')::timestamptz at time zone 'UTC')) = 0,
         'offset 0 harus reset di 00:00 UTC';
  assert public.set_profile_timezone(u1, 420) = 420,
         'set zona pertama harus diterima';
  assert public.set_profile_timezone(u1, 0) = 420,
         'ganti zona dalam 24 jam harus ditolak';
  update public.profiles
     set timezone_offset_set_at = now() - interval '25 hours'
   where id = u1;
  assert public.set_profile_timezone(u1, 0) = 0,
         'ganti zona sesudah 24 jam harus diterima';
  update public.profiles
     set timezone_offset_minutes = 420,
         timezone_offset_set_at = now()
   where id = u1;
  assert extract(hour from ((public.battle_daily_reward_status(u1)->>'reset_at')::timestamptz at time zone 'UTC')) = 17,
         'WIB +420 harus reset di 17:00 UTC';

  insert into public.animas (owner_id, nickname, species_key, color_bucket,
                             element, rarity, base_stats, care)
  values (u1, 'uji anima', 'mouse_plastic', 'gray', 'tech', 3, v_stats, v_care);
  insert into public.species_library
    (species_key, color_bucket, stage, sheet_path, manifest, prompt_version)
  values (v_spesies, 'gray', 1, 'uji.png', '{}'::jsonb, 'v3');

  ----------------------------------------------------------------------------
  -- Gerbang nama Rename: menyala di UPDATE, dan capture berbayar tetap lewat
  ----------------------------------------------------------------------------
  select id into v_name_anima
    from public.animas where owner_id = u1 and nickname = 'uji anima';
  update public.animas set nickname = 'Sir Fluffy' where id = v_name_anima;
  assert (select nickname from public.animas where id = v_name_anima) = 'Sir Fluffy',
         'nama peliharaan wajar harus lolos gerbang Rename';
  update public.animas set nickname = '  Padded Name  ' where id = v_name_anima;
  assert (select nickname from public.animas where id = v_name_anima) = 'Padded Name',
         'gerbang Rename harus memangkas spasi tepi, bukan menyimpannya';
  begin
    update public.animas set nickname = 'Kontol' where id = v_name_anima;
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_NAME_RESERVED');
  end;
  assert ok, 'Rename dengan profanity harus ditolak';
  begin
    update public.animas set nickname = 'Admin Bot' where id = v_name_anima;
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_NAME_RESERVED');
  end;
  assert ok, 'impersonasi harus diperiksa per kata, bukan hanya nama utuh';
  begin
    update public.animas set nickname = 'Pika' || chr(233) where id = v_name_anima;
    ok := false;
  exception when others then ok := (sqlerrm = 'INVALID_ANIMA_NAME');
  end;
  assert ok, 'karakter di luar ASCII harus ditolak';
  begin
    update public.animas set nickname = '12345' where id = v_name_anima;
    ok := false;
  exception when others then ok := (sqlerrm = 'INVALID_ANIMA_NAME');
  end;
  assert ok, 'nama tanpa satu pun huruf harus ditolak';
  -- Penamaan tidak boleh menggagalkan capture berbayar, jadi INSERT sengaja
  -- tidak dipagari: nama generated sudah disaring nameIsSafeForPlayers() di
  -- Edge Function, dan stem baru di daftar tidak boleh membunuh $0.07.
  insert into public.animas (owner_id, nickname, species_key, color_bucket,
                             element, rarity, base_stats, care)
  values (u1, 'staff', 'gate_probe', 'gray', 'tech', 1, v_stats, v_care);
  assert (select count(*) from public.animas
           where owner_id = u1 and species_key = 'gate_probe') = 1,
         'INSERT capture tidak boleh ikut dipagari gerbang Rename';
  delete from public.animas where owner_id = u1 and species_key = 'gate_probe';
  update public.animas set nickname = 'uji anima' where id = v_name_anima;

  ----------------------------------------------------------------------------
  -- Guest: satu Scan sukses per akun anonim, dan hatch gagal melepas slot
  ----------------------------------------------------------------------------
  v_j := public.claim_genesis(
    u3, 'guest-genesis', 'Guest Genesis', 'guest_object', 'gray', 1::smallint,
    'tech', 2, v_stats, v_care, v_visi, 'v7', 'model', 0.07, 'u3/photo.jpg'
  );
  v_refund := (v_j->>'generation_id')::uuid;
  assert (select genesis_cores from public.profiles where id = u3) = 0
         and (select guest_scan_used_at from public.profiles where id = u3) is not null,
         'Genesis guest pertama harus mendebit Core dan mengisi slot';
  begin
    perform public.claim_genesis(
      u3, 'guest-second', 'Guest Second', 'guest_second', 'gray', 1::smallint,
      'tech', 2, v_stats, v_care, v_visi, 'v7', 'model', 0.07, 'u3/second.jpg'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'GUEST_SCAN_USED');
  end;
  assert ok, 'guest Scan kedua harus ditolak atomik';
  v := (select scan_charges from public.profiles where id = u3);
  begin
    perform public.claim_scan_charge(u3);
    ok := false;
  exception when others then ok := (sqlerrm = 'GUEST_SCAN_USED');
  end;
  assert ok
         and (select scan_charges from public.profiles where id = u3) = v,
         'guest terpakai harus ditolak sebelum charge dan Vision';
  perform public.refund_generation(v_refund, 'uji hatch gagal');
  assert (select genesis_cores from public.profiles where id = u3) = 1
         and (select guest_scan_used_at from public.profiles where id = u3) is null,
         'refund hatch guest harus mengembalikan Core dan slot Scan';

  ----------------------------------------------------------------------------
  -- 1. Scan charge: debit tercatat, saldo nol menolak, refund dibatasi maksimum
  ----------------------------------------------------------------------------
  v := public.claim_scan_charge(u1);
  assert v = 7, format('sisa scan_charges harus 7, dapat %s', v);
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and currency = 'scan_charges' and delta = -1) = 1,
         'debit scan harus tercatat di ledger';

  for i in 1..7 loop perform public.claim_scan_charge(u1); end loop;
  begin
    perform public.claim_scan_charge(u1);
    ok := false;
  exception when others then ok := (sqlerrm = 'NO_SCAN_CHARGE');
  end;
  assert ok, 'saldo nol harus menolak dengan NO_SCAN_CHARGE';
  assert (select scan_charges from public.profiles where id = u1) = 0,
         'penolakan tidak boleh menyisakan saldo negatif';

  v := public.refund_scan_charge(u1, 'gate_menolak');
  assert v = 1, format('refund harus menaikkan ke 1, dapat %s', v);

  for i in 1..7 loop perform public.refund_scan_charge(u1); end loop;
  n := (select count(*) from public.quota_ledger
         where owner_id = u1 and currency = 'scan_charges' and delta > 0);
  v := public.refund_scan_charge(u1);
  assert v = 8, format('refund saat penuh harus tetap 8, dapat %s', v);
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and currency = 'scan_charges' and delta > 0) = n,
         'refund yang tidak menambah saldo tidak boleh menulis baris ledger';

  ----------------------------------------------------------------------------
  -- 2. claim_genesis: satu key = satu Core = satu Anima
  ----------------------------------------------------------------------------
  -- Isolate this legacy rollback path from the current four-Core starter grant.
  update public.profiles set genesis_cores = 3 where id = u1;
  v_j := public.claim_genesis(u1, 'key-a', 'Uji A', 'mouse_plastic', 'gray', 1::smallint,
                              'tech', 3, v_stats, v_care, v_visi, 'v3', 'openai/gpt-image-2',
                              0.07, 'u1/foto.jpg');
  v_id := (v_j->>'generation_id')::uuid;
  assert (select genesis_cores from public.profiles where id = u1) = 2,
         'Genesis Core harus terdebit satu';
  assert (select status from public.animas where id = (v_j->>'anima_id')::uuid) = 'incubating',
         'claim_genesis harus membuat Anima dalam status incubating';
  assert (select photo_path from public.generations where id = v_id) = 'u1/foto.jpg',
         'photo_path harus tersimpan, webhook yang memakainya untuk menghapus foto';

  -- Retry jaringan: baris yang sama, tanpa debit kedua, dan yang paling mudah
  -- terlewat — tanpa Anima kedua. Sebelum jalur ini satu transaksi, retry seperti
  -- ini meninggalkan Anima kembar untuk satu Core.
  v_j2 := public.claim_genesis(u1, 'key-a', 'Uji A', 'mouse_plastic', 'gray', 1::smallint,
                               'tech', 3, v_stats, v_care, v_visi, 'v3', 'openai/gpt-image-2',
                               0.07, 'u1/foto.jpg');
  assert v_j2 = v_j, 'key yang sama harus mengembalikan generation dan anima yang sama';
  assert (select genesis_cores from public.profiles where id = u1) = 2,
         'retry dengan key sama tidak boleh mendebit dua kali';
  assert (select count(*) from public.quota_ledger where ref_id = v_id) = 1,
         'retry tidak boleh menulis dua baris ledger';
  assert (select count(*) from public.animas
           where owner_id = u1 and nickname = 'Uji A') = 1,
         'retry tidak boleh membuat Anima kedua';

  ----------------------------------------------------------------------------
  -- 3. Core habis: menolak, dan tidak menyisakan generation atau Anima yatim
  ----------------------------------------------------------------------------
  v_sukses := (public.claim_genesis(u1, 'key-b', 'Uji B', 'mug_ceramic', 'warm_red',
                 1::smallint, 'water', 2, v_stats, v_care, v_visi, 'v3', 'model', 0.07,
                 'u1/b.jpg')->>'generation_id')::uuid;
  perform public.claim_genesis(u1, 'key-c', 'Uji C', 'shoe_fabric', 'neutral_dark',
            1::smallint, 'earth', 2, v_stats, v_care, v_visi, 'v3', 'model', 0.07, 'u1/c.jpg');
  begin
    perform public.claim_genesis(u1, 'key-d', 'Uji D', 'pen_plastic', 'cool_blue',
              1::smallint, 'tech', 1, v_stats, v_care, v_visi, 'v3', 'model', 0.07, 'u1/d.jpg');
    ok := false;
  exception when others then ok := (sqlerrm = 'NO_CORE');
  end;
  assert ok, 'Core habis harus menolak dengan NO_CORE';
  assert (select count(*) from public.generations
           where owner_id = u1 and idempotency_key = 'key-d') = 0,
         'penolakan tidak boleh meninggalkan baris generation';
  assert (select count(*) from public.animas where nickname = 'Uji D') = 0,
         'penolakan tidak boleh meninggalkan Anima tanpa generation';

  ----------------------------------------------------------------------------
  -- 4. Spend cap: dijaga di dalam transaksi yang sama dengan debitnya
  ----------------------------------------------------------------------------
  update public.profiles set genesis_cores = 5 where id = u1;
  update public.app_config set value = '0.01'::jsonb where key = 'daily_spend_cap_usd';
  begin
    perform public.claim_genesis(u1, 'key-cap', 'Uji Cap', 'lamp_metal', 'metallic',
              1::smallint, 'light', 3, v_stats, v_care, v_visi, 'v3', 'model', 0.07, 'u1/cap.jpg');
    ok := false;
  exception when others then ok := (sqlerrm = 'SPEND_CAP');
  end;
  update public.app_config set value = '25'::jsonb where key = 'daily_spend_cap_usd';
  assert ok, 'cap harian terlampaui harus menolak dengan SPEND_CAP';
  assert (select genesis_cores from public.profiles where id = u1) = 5,
         'penolakan cap tidak boleh mendebit Core';

  update public.profiles set genesis_cores = 1 where id = u1;

  ----------------------------------------------------------------------------
  -- 5. refund_generation: mengkredit tepat sekali walau dipanggil dua kali
  ----------------------------------------------------------------------------
  v_gen := public.refund_generation(v_id, 'uji: prediksi gagal');
  v_refund := v_gen.id;
  assert v_gen.status = 'failed', 'refund harus menandai generation failed';
  assert (select genesis_cores from public.profiles where id = u1) = 2,
         'refund harus mengkredit satu Core';

  perform public.refund_generation(v_refund, 'uji: webhook terkirim dua kali');
  assert (select genesis_cores from public.profiles where id = u1) = 2,
         'webhook kembar tidak boleh mengkredit Core kedua';
  assert (select count(*) from public.quota_ledger
           where ref_id = v_refund and reason = 'refund') = 1,
         'hanya boleh ada satu baris refund per generation';

  -- Indeks unik partial-nya yang menjadi pagar terakhir kalau ada race, jadi
  -- ia diuji langsung, bukan diasumsikan dari perilaku fungsi di atas.
  begin
    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (u1, 'genesis_cores', 1, 'refund', v_refund);
    ok := false;
  exception when unique_violation then ok := true;
  end;
  assert ok, 'indeks quota_ledger_refund_sekali_idx harus menolak refund kedua';

  ----------------------------------------------------------------------------
  -- 6. record_cache_hit: Anima siap tanpa Core, dan reuse terhitung sekali
  ----------------------------------------------------------------------------
  v := (select genesis_cores from public.profiles where id = u2);
  v_seeker_xp := (select seeker_xp from public.profiles where id = u2);
  v_j := public.record_cache_hit(u2, 'key-cache', 'Uji Cache', v_spesies, 'gray',
                                 1::smallint, 'tech', 3, v_stats, v_care, v_visi, 'v3');
  assert (select genesis_cores from public.profiles where id = u2) = v,
         'cache hit tidak boleh mendebit Core';
  assert (select status from public.animas where id = (v_j->>'anima_id')::uuid) = 'ready',
         'cache hit harus langsung menghasilkan Anima ready';
  assert (select cost_usd_estimate from public.generations
           where id = (v_j->>'generation_id')::uuid) = 0,
         'cache hit tidak boleh tercatat berbiaya, ia yang menyelamatkan model biaya';
  assert (select times_reused from public.species_library
           where species_key = v_spesies and color_bucket = 'gray' and stage = 1) = 1,
         'reuse harus terhitung, angka itu yang mengukur apakah cache bekerja';
  assert (select seeker_xp from public.profiles where id = u2) = v_seeker_xp + 5,
         'Anima ready dari cache harus memberi +5 Seeker EXP';
  assert (select guest_scan_used_at from public.profiles where id = u2) is not null,
         'cache hit tetap harus memakai satu slot guest';

  v_j2 := public.record_cache_hit(u2, 'key-cache', 'Uji Cache', v_spesies, 'gray',
                                  1::smallint, 'tech', 3, v_stats, v_care, v_visi, 'v3');
  assert v_j2 = v_j, 'cache hit dengan key sama harus mengembalikan baris yang sama';
  assert (select count(*) from public.animas where owner_id = u2) = 1,
         'retry cache hit tidak boleh membuat Anima kedua';
  assert (select times_reused from public.species_library
           where species_key = v_spesies and color_bucket = 'gray' and stage = 1) = 1,
         'retry tidak boleh menaikkan times_reused dua kali';
  begin
    perform public.record_cache_hit(u2, 'key-cache-second', 'Uji Cache 2', v_spesies, 'gray',
                                    1::smallint, 'tech', 3, v_stats, v_care, v_visi, 'v3');
    ok := false;
  exception when others then ok := (sqlerrm = 'GUEST_SCAN_USED');
  end;
  assert ok, 'cache hit kedua guest harus ditolak tanpa mendebit Core';

  -- Cache hit tidak pernah mendebit, jadi tidak ada yang bisa dikembalikan.
  perform public.refund_generation((v_j->>'generation_id')::uuid, 'uji: cache hit');
  assert (select genesis_cores from public.profiles where id = u2) = v,
         'cache hit tidak boleh menghasilkan Core gratis';

  ----------------------------------------------------------------------------
  -- 7. Generation yang sudah berhasil tidak boleh direfund (art sudah diberikan)
  ----------------------------------------------------------------------------
  v_seeker_xp := (select seeker_xp from public.profiles where id = u1);
  update public.generations set status = 'succeeded' where id = v_sukses;
  update public.animas
     set status = 'ready'
   where id = (select anima_id from public.generations where id = v_sukses);
  assert (select seeker_xp from public.profiles where id = u1) = v_seeker_xp + 5,
         'Genesis hanya memberi +5 Seeker EXP saat Anima benar-benar ready';
  begin
    perform public.refund_generation(v_sukses, 'uji: seharusnya ditolak');
    ok := false;
  exception when others then ok := (sqlerrm = 'ALREADY_SUCCEEDED');
  end;
  assert ok, 'refund atas generation succeeded harus gagal keras';

  -- Fixture delete dipasang sebelum role berganti. Generation sengaja menunjuk
  -- row itu untuk memastikan audit tetap ada, sedangkan care_event harus cascade.
  insert into public.animas (owner_id, nickname, species_key, color_bucket,
                             element, rarity, base_stats, care, status)
  values (u1, 'hapus sendiri', 'delete_owned', 'gray',
          'tech', 1, v_stats, v_care, 'ready')
  returning id into v_delete_own;
  insert into public.animas (owner_id, nickname, species_key, color_bucket,
                             element, rarity, base_stats, care, status)
  values (u2, 'jangan hapus', 'delete_foreign', 'gray',
          'tech', 1, v_stats, v_care, 'ready')
  returning id into v_delete_other;
  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model)
  values
    (u1, v_delete_own, 'delete-audit', 'create', 'succeeded', 'v3', 'uji')
  returning id into v_delete_generation;
  insert into public.care_events
    (owner_id, anima_id, idempotency_key, action)
  values
    (u1, v_delete_own, 'delete-care', 'play');
  select genesis_cores into v_cores_before_delete from public.profiles where id = u1;

  ----------------------------------------------------------------------------
  -- 8. Jalur client (anon key). Inilah kriteria keluar Phase 2: kuota tidak bisa
  --    dicurangi lewat panggilan langsung ke Postgres.
  ----------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  -- Semua penolakan di bawah harus berupa insufficient_privilege, bukan sembarang
  -- error. Assert yang menerima "error apa pun" bisa lulus karena salah nama
  -- tabel dan diam-diam berhenti menguji mekanismenya.
  begin
    update public.profiles set genesis_cores = 99 where id = u1;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh bisa menaikkan genesis_cores sendiri';

  begin
    update public.profiles
       set seeker_xp = 9999,
           battle_victories = 9999,
           guest_scan_used_at = null,
           account_upgraded_at = now()
     where id = u1;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'progress dan status akun Seeker harus server-authoritative';

  begin
    perform public.complete_seeker_profile(u1, 'ClientBypass', null, null);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil RPC Seeker dengan owner_id pilihan';

  begin
    update public.animas set care_score = 9999 where owner_id = u1;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'care_score adalah gerbang evolusi, client tidak boleh menulisnya';

  begin
    update public.animas set care = '{"hunger":100}'::jsonb where owner_id = u1;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'care harus server-authoritative setelah Bits aktif';

  begin
    perform public.apply_care(
      u1,
      (select id from public.animas where owner_id = u1 and nickname = 'uji anima'),
      'play',
      'care-client-curang'
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'fungsi care yang menyentuh Bits tidak boleh dipanggil client';

  begin
    perform public.claim_genesis(u1, 'key-client', 'Curang', 'mouse_plastic', 'gray',
              1::smallint, 'tech', 3, v_stats, v_care, v_visi, 'v3', 'model', 0.07, 'u1/x.jpg');
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'fungsi kuota tidak boleh bisa dipanggil client lewat rpc';

  -- record_cache_hit tidak menyentuh mata uang, tapi ia membuat Anima atas nama
  -- uid mana pun yang disebut penelepon. Terbuka untuk client berarti art gratis
  -- untuk spesies apa pun yang sudah ada di pustaka.
  begin
    perform public.record_cache_hit(u1, 'key-client-2', 'Curang', v_spesies, 'gray',
              1::smallint, 'tech', 3, v_stats, v_care, v_visi, 'v3');
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'record_cache_hit tidak boleh bisa dipanggil client lewat rpc';

  begin
    perform public.refund_generation(v_refund, 'uji: refund oleh client');
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client yang bisa refund sendiri berarti generation gratis';

  begin
    insert into public.animas (owner_id, nickname, species_key, color_bucket,
                               element, rarity, base_stats, care)
    values (u1, 'palsu', 'x', 'y', 'fire', 5, '{}'::jsonb, '{}'::jsonb);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh menyisipkan Anima tanpa lewat Edge Function';

  begin
    perform 1 from public.app_config;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'sakelar biaya tidak boleh terbaca client';

  assert (select count(*) from public.profiles where id = u2) = 0,
         'RLS harus menyembunyikan profil pemain lain';
  assert (select count(*) from public.profiles where id = u1) = 1,
         'pemain harus tetap bisa membaca profilnya sendiri';

  update public.profiles set display_name = 'nama baru' where id = u1;
  assert (select display_name from public.profiles where id = u1) = 'nama baru',
         'kolom kosmetik harus tetap bisa diubah client';

  -- Seeker Avatar adalah pilihan kosmetik, jadi hak tulisnya diberikan sebagai
  -- kolom ketiga di atas dua yang sudah ada — bukan dengan mencabut hak tabel
  -- lalu memberikannya ulang. Dua baris berikut yang membuktikan penambahan itu
  -- benar-benar aditif: kalau migrasi avatar memakai `revoke update on
  -- profiles`, display_name di atas dan last_seen_at di sini yang mati lebih
  -- dulu, dan matinya diam-diam.
  update public.profiles set last_seen_at = now() where id = u1;
  get diagnostics n = row_count;
  assert n = 1, 'hak kolom last_seen_at hilang saat hak avatar ditambahkan';

  update public.profiles set seeker_avatar = 'automaton' where id = u1;
  assert (select seeker_avatar from public.profiles where id = u1) = 'automaton',
         'pemain harus bisa memilih Seeker Avatar-nya sendiri tanpa RPC';

  -- Yang membatasi nilainya adalah CHECK terhadap Seeker Roster, bukan UI.
  begin
    update public.profiles set seeker_avatar = 'wizard' where id = u1;
    ok := false;
  exception when check_violation then ok := true;
  end;
  assert ok, 'avatar di luar Seeker Roster harus ditolak database';
  assert (select seeker_avatar from public.profiles where id = u1) = 'automaton',
         'avatar yang ditolak tidak boleh mengubah pilihan yang sudah tersimpan';

  -- RLS, bukan hak kolom, yang menahan tulisan lintas pemain: hak UPDATE
  -- avatar memang dimiliki setiap authenticated. Row pemain lain karena itu
  -- tidak terlihat dan tidak tersentuh, bukan menghasilkan galat privilege.
  update public.profiles set seeker_avatar = 'masculine' where id = u2;
  get diagnostics n = row_count;
  assert n = 0, 'RLS tidak boleh membiarkan pemain menulis avatar pemain lain';

  begin
    update public.profiles set active_anima_id = v_delete_own where id = u1;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh menulis companion aktif';

  begin
    update public.profiles set timezone_offset_minutes = 0 where id = u1;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh menulis offset zona';

  begin
    perform public.set_profile_timezone(u1, 0);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'set_profile_timezone tidak boleh dipanggil client';

  update public.animas set nickname = 'nama pilihan' where id = v_delete_own;
  assert (select nickname from public.animas where id = v_delete_own) = 'nama pilihan',
         'pemain harus bisa mengganti nickname Anima sendiri';
  begin
    update public.animas set nickname = '   ' where id = v_delete_own;
    ok := false;
  -- Dulu `check_violation` dari `animas_nickname_length`. Sejak gerbang Rename,
  -- trigger menyala lebih dulu dan menjawab dengan kode yang bisa dipetakan
  -- client; CHECK-nya tetap ada sebagai pagar kedua untuk INSERT.
  exception when others then ok := (sqlerrm = 'INVALID_ANIMA_NAME');
  end;
  assert ok, 'nickname kosong harus ditolak di trust boundary database';

  delete from public.animas where id = v_delete_other;
  get diagnostics n = row_count;
  assert n = 0, 'RLS tidak boleh menghapus Anima pemain lain';

  delete from public.animas where id = v_delete_own;
  get diagnostics n = row_count;
  assert n = 1, 'pemain harus bisa menghapus Anima sendiri';
  assert (select genesis_cores from public.profiles where id = u1) = v_cores_before_delete,
         'menghapus Anima tidak boleh merefund Genesis Core';

  -- Fungsi bawaan platform yang tadinya terekspos di /rest/v1/rpc. Ia inert kalau
  -- dipanggil, tapi EXECUTE-nya sudah dicabut di migrasi
  -- harden_platform_rls_helper; uji ini yang memberi tahu kita kalau bootstrap
  -- Supabase memberikannya lagi di masa depan.
  begin
    perform public.rls_auto_enable();
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'rls_auto_enable() kembali terbuka untuk client';

  ----------------------------------------------------------------------------
  -- 9. Trigger guard adalah lapis kedua: ia harus tetap menolak walau privilege
  --    UPDATE penuh diberikan (misalnya oleh migrasi masa depan yang longgar).
  ----------------------------------------------------------------------------
  perform set_config('role', 'none', true);
  assert exists (select 1 from public.animas where id = v_delete_other),
         'percobaan delete lintas pemain ternyata menghapus row';
  assert not exists (select 1 from public.animas where id = v_delete_own),
         'row milik sendiri masih ada setelah delete berhasil';
  assert (select anima_id is null from public.generations where id = v_delete_generation),
         'generation audit harus dipertahankan dengan anima_id null';
  assert not exists (select 1 from public.care_events where anima_id = v_delete_own),
         'care_events milik Anima terhapus harus ikut cascade';
  -- Row u2 hanya terbaca dari luar RLS, jadi bukti bahwa tulisan avatar lintas
  -- pemain di atas benar-benar tidak mendarat harus diambil di sini. Tanpa ini,
  -- `row_count = 0` juga akan lulus kalau policy-nya hilang tetapi baris u2
  -- kebetulan tidak cocok dengan predikat lain.
  assert (select seeker_avatar is null from public.profiles where id = u2),
         'avatar pemain lain berubah walau update-nya melaporkan 0 baris';
  grant update on public.profiles to authenticated;
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles set genesis_cores = 99 where id = u1;
    ok := false;
  exception when others then ok := (sqlerrm like 'hanya display_name%');
  end;
  perform set_config('role', 'none', true);
  -- Revoke tingkat tabel juga mencabut hak kolom, jadi hak kolomnya diberikan
  -- ulang — ketiganya. Blok ini commit kalau lulus, jadi kolom yang lupa
  -- disebut di sini kehilangan hak tulisnya di production, dan yang gagal
  -- adalah pemain, bukan uji ini.
  revoke update on public.profiles from authenticated;
  grant update (display_name, last_seen_at, seeker_avatar) on public.profiles to authenticated;
  assert ok, 'trigger guard harus menolak perubahan mata uang oleh non-service role';

  ----------------------------------------------------------------------------
  -- 10. Care loop: decay, idempotency, debit Bits, cap harian, tidur, Dormant
  ----------------------------------------------------------------------------
  select id into v_care_anima
    from public.animas
   where owner_id = u1 and nickname = 'uji anima';

  update public.animas set care_score = 34 where id = v_care_anima;
  v_seeker_xp := (select seeker_xp from public.profiles where id = u1);
  alter table public.animas disable trigger animas_mirror_seeker_xp;
  update public.animas
     set care_score = public.anima_exp_for_level(1 + care_score / 5)
       + floor(
           (care_score % 5)::numeric
           * public.anima_exp_to_next(1 + care_score / 5)
           / 5.0
         )::integer
   where id = v_care_anima;
  alter table public.animas enable trigger animas_mirror_seeker_xp;
  assert (select care_score from public.animas where id = v_care_anima) = 43
         and public.anima_level_from_exp(
           (select care_score from public.animas where id = v_care_anima)
         ) = 7
         and (select seeker_xp from public.profiles where id = u1) = v_seeker_xp,
         'rebase harus menjaga Level/bar tanpa memberi Seeker EXP administratif';

  update public.profiles set bits = 50 where id = u1;
  update public.animas
     set status = 'ready',
         care = '{"hunger":0,"energy":100,"hygiene":0,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now(),
         sleep_started_at = null,
         sleep_energy_at_start = null,
         well_cared_on = null,
         play_score_on = null,
         play_score_today = 0,
         dormant_since = null
   where id = v_care_anima;
  insert into public.player_inventory (owner_id, item_id, quantity)
  values
    (u1, 'ember_noodles', 10),
    (u1, 'byte_berry', 10),
    (u1, 'nova_feast', 4),
    (u1, 'pulse_cell', 4),
    (u1, 'vital_patch', 4)
  on conflict (owner_id, item_id) do update
    set quantity = excluded.quantity;

  v_seeker_xp := (select seeker_xp from public.profiles where id = u1);
  v_j := public.apply_care(u1, v_care_anima, 'feed', 'care-feed-1', 'ember_noodles');
  assert (v_j->>'bits')::int = 50, 'Feed dari inventory tidak boleh mendebit Bits';
  assert (v_j #>> '{anima,care,hunger}')::numeric = 45,
         'Ember Noodles harus memulihkan 45 Hunger';
  assert (v_j #>> '{anima,care,bond}')::numeric = 0,
         'Bond tidak lagi meter progres';
  assert (v_j #>> '{anima,care_score}')::int = 3,
         'Feed yang menyeberang Hunger 40 harus memberi 3 care_score';
  assert (select seeker_xp from public.profiles where id = u1) = v_seeker_xp + 3,
         'care_score yang sah harus dicerminkan ke Seeker EXP';
  assert (select quantity from public.player_inventory
           where owner_id = u1 and item_id = 'ember_noodles') = 9,
         'Feed harus mengonsumsi satu makanan';
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and currency = 'bits' and reason = 'feed') = 0,
         'Feed inventory tidak boleh menulis ledger Bits';

  v_j2 := public.apply_care(u1, v_care_anima, 'feed', 'care-feed-1', 'ember_noodles');
  assert (v_j2->>'replayed')::bool, 'key care yang sama harus masuk jalur replay';
  assert (v_j2->>'bits')::int = 50, 'replay Feed tidak boleh mendebit Bits';
  assert (v_j2 #>> '{anima,care,hunger}')::numeric = 45,
         'replay Feed tidak boleh memulihkan dua kali';
  assert (select quantity from public.player_inventory
           where owner_id = u1 and item_id = 'ember_noodles') = 9,
         'replay Feed tidak boleh mengonsumsi makanan lagi';
  assert (select count(*) from public.care_events
           where owner_id = u1 and idempotency_key = 'care-feed-1') = 1,
         'retry care harus tetap satu event';

  begin
    perform public.apply_care(u1, v_care_anima, 'clean', 'care-feed-1');
    ok := false;
  exception when others then ok := (sqlerrm = 'IDEMPOTENCY_CONFLICT');
  end;
  assert ok, 'key yang dipakai ulang untuk aksi berbeda harus ditolak';

  v_j := public.apply_care(u1, v_care_anima, 'clean', 'care-clean-1');
  assert (v_j->>'bits')::int = 50, 'Clean tidak boleh mendebit Bits';
  assert (v_j #>> '{anima,care,hygiene}')::numeric = 35,
         'Clean harus memulihkan 35 Hygiene';
  assert (v_j #>> '{anima,care_score}')::int = 6,
         'Clean saat Hygiene <50 harus memberi 3 care_score';
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and currency = 'bits' and reason = 'clean') = 0,
         'Clean gratis tidak boleh menulis ledger Bits';

  -- Meter yang tampil penuh (100 atau 99.99) tidak boleh mengonsumsi makanan.
  update public.profiles set bits = 45 where id = u1;
  update public.animas
     set care = '{"hunger":99.99,"energy":100,"hygiene":99.99,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_care_anima;
  begin
    perform public.apply_care(u1, v_care_anima, 'feed', 'care-feed-full', 'ember_noodles');
    ok := false;
  exception when others then ok := (sqlerrm = 'NEED_FULL');
  end;
  assert ok, 'Feed pada Hunger yang tampil penuh harus ditolak';
  assert (select bits from public.profiles where id = u1) = 45,
         'NEED_FULL Feed tidak boleh mendebit Bits';
  assert (select quantity from public.player_inventory
           where owner_id = u1 and item_id = 'ember_noodles') = 9,
         'NEED_FULL Feed tidak boleh mengonsumsi makanan';
  assert not exists (
    select 1 from public.care_events
     where owner_id = u1 and idempotency_key = 'care-feed-full'
  ), 'NEED_FULL tidak boleh menyisakan event yang memblokir retry';

  begin
    perform public.apply_care(u1, v_care_anima, 'clean', 'care-clean-full');
    ok := false;
  exception when others then ok := (sqlerrm = 'NEED_FULL');
  end;
  assert ok, 'Clean pada Hygiene yang tampil penuh harus ditolak';
  assert (select bits from public.profiles where id = u1) = 45,
         'NEED_FULL Clean tidak boleh mendebit Bits';

  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":0,"bond":0}'::jsonb,
         care_score = 859,
         care_synced_at = now()
   where id = v_care_anima;
  v_seeker_xp := (select seeker_xp from public.profiles where id = u1);
  v_j := public.apply_care(u1, v_care_anima, 'clean', 'care-score-clamp');
  assert (v_j #>> '{anima,care_score}')::integer = 860
         and (select care_score_delta from public.care_events
               where owner_id = u1 and idempotency_key = 'care-score-clamp') = 1
         and (select seeker_xp from public.profiles where id = u1) = v_seeker_xp + 1,
         'grant lewat Lv.40 harus menjepit receipt dan Seeker ke delta aktual';

  -- Play tetap berjalan setelah cap score harian tercapai, tetapi tidak
  -- boleh menjadi mesin care_score tanpa batas.
  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now(),
         play_score_on = null,
         play_score_today = 0
   where id = v_care_anima;
  for i in 1..6 loop
    perform public.apply_care(u1, v_care_anima, 'play', 'care-play-' || i);
  end loop;
  assert (select care_score from public.animas where id = v_care_anima) = 5,
         'enam Play sehari hanya boleh memberi 5 care_score';
  assert (select play_score_today from public.animas where id = v_care_anima) = 5,
         'counter Play harian harus berhenti di 5';
  assert (select (care->>'energy')::numeric from public.animas where id = v_care_anima) = 70,
         'enam Play harus memakai 30 Energy';
  assert (select (care->>'bond')::numeric from public.animas where id = v_care_anima) = 0,
         'Play tidak boleh menulis Bond';

  update public.animas
     set care = '{"hunger":100,"energy":70,"hygiene":100,"bond":100}'::jsonb,
         care_score = 5,
         care_synced_at = now()
   where id = v_care_anima;
  v_j := public.apply_care(u1, v_care_anima, 'play', 'care-bond-ignored');
  assert (v_j #>> '{anima,care,energy}')::numeric = 65,
         'Play tidak boleh ditolak karena Bond penuh';
  assert (v_j #>> '{anima,care,bond}')::numeric = 0,
         'Play menuliskan ulang Bond jadi 0';
  assert (select care_score from public.animas where id = v_care_anima) = 5,
         'Play setelah cap harian tidak boleh menambah EXP';
  assert exists (
    select 1 from public.care_events
     where owner_id = u1 and idempotency_key = 'care-bond-ignored'
  ), 'Play tanpa Bond tetap harus tercatat';

  update public.profiles set bits = 0 where id = u1;
  update public.animas
     set care = '{"hunger":0,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now(),
         care_score = 0
   where id = v_care_anima;
  delete from public.player_inventory
   where owner_id = u1 and item_id = 'byte_berry';
  begin
    perform public.apply_care(u1, v_care_anima, 'feed', 'care-no-item', 'byte_berry');
    ok := false;
  exception when others then ok := (sqlerrm = 'NO_ITEM');
  end;
  assert ok, 'Feed tanpa makanan di inventory harus ditolak dengan NO_ITEM';
  assert not exists (
    select 1 from public.care_events
     where owner_id = u1 and idempotency_key = 'care-no-item'
  ), 'aksi gagal tidak boleh menyisakan event yang memblokir retry';
  insert into public.player_inventory (owner_id, item_id, quantity)
  values (u1, 'byte_berry', 2)
  on conflict (owner_id, item_id) do update set quantity = 2;
  v_j := public.apply_care(u1, v_care_anima, 'feed', 'care-byte-berry', 'byte_berry');
  assert (v_j #>> '{anima,care,hunger}')::numeric = 10,
         'Byte Berry dari 0 harus mengisi 10 Hunger';
  assert (v_j #>> '{anima,care_score}')::int = 0,
         'restore yang tidak menyeberang 40 tidak boleh +3 EXP';
  v_j := public.apply_care(u1, v_care_anima, 'feed', 'care-byte-cross', 'byte_berry');
  assert (v_j #>> '{anima,care,hunger}')::numeric = 20,
         'Byte Berry kedua menambah Hunger tanpa Bits';
  assert (v_j #>> '{anima,care_score}')::int = 0,
         'Hunger 10+10 masih di bawah 40 jadi tanpa EXP';
  insert into public.player_inventory (owner_id, item_id, quantity)
  values (u1, 'ember_noodles', 1)
  on conflict (owner_id, item_id) do update set quantity = public.player_inventory.quantity + 1;
  v_j := public.apply_care(u1, v_care_anima, 'feed', 'care-ember-cross', 'ember_noodles');
  assert (v_j #>> '{anima,care,hunger}')::numeric = 65,
         'Ember Noodles dari 20 harus menyeberang 40';
  assert (v_j #>> '{anima,care_score}')::int = 3,
         'menyeberang 40 dari makanan kecil sebelumnya tetap +3 EXP';

  update public.animas
     set care = '{"hunger":80,"energy":90,"hygiene":80,"bond":0}'::jsonb,
         care_synced_at = now(),
         care_score = 3
   where id = v_care_anima;
  v_j := public.apply_care(u1, v_care_anima, 'use_item', 'care-energy-clamp', 'pulse_cell');
  assert (v_j #>> '{anima,care,energy}')::numeric = 100,
         'item Energy harus dijepit ke 100';
  assert (v_j #>> '{anima,care_score}')::int = 3,
         'item Energy tidak boleh menambah EXP';
  begin
    perform public.apply_care(u1, v_care_anima, 'use_item', 'care-energy-full', 'pulse_cell');
    ok := false;
  exception when others then ok := (sqlerrm = 'NEED_FULL');
  end;
  assert ok, 'Energy yang tampil penuh harus menolak item Energy';

  -- Tidur memakai nilai Energy saat mulai, jadi sync berkali-kali tidak
  -- menggandakan pemulihan. Tiga jam = setengah jalan; enam jam = penuh +5.
  update public.animas
     set care = '{"hunger":100,"energy":0,"hygiene":100,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now(),
         sleep_started_at = null,
         sleep_energy_at_start = null,
         sleep_exp_on = null,
         well_cared_on = public.local_civil_date(
           now(),
           (select timezone_offset_minutes from public.profiles where id = u1)
         )
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sleep', 'care-sleep-1');
  update public.animas
     set sleep_started_at = now() - interval '3 hours',
         sleep_energy_at_start = 0,
         care_synced_at = now()
   where id = v_care_anima;
  v_j := public.apply_care(u1, v_care_anima, 'sync', null);
  assert (v_j #>> '{anima,care,energy}')::numeric between 49.9 and 50.1,
         'tidur tiga jam harus memulihkan setengah Energy';
  assert (v_j #>> '{anima,sleep_started_at}') is not null,
         'tidur tiga jam belum boleh selesai otomatis';

  update public.animas
     set sleep_started_at = now() - interval '6 hours',
         sleep_energy_at_start = 0,
         care_synced_at = now()
   where id = v_care_anima;
  v_j := public.apply_care(u1, v_care_anima, 'sync', null);
  assert (v_j #>> '{anima,care,energy}')::numeric = 100,
         'tidur enam jam harus mengisi Energy penuh';
  assert (v_j #>> '{anima,sleep_started_at}') is null,
         'tidur penuh harus selesai otomatis';
  assert (v_j #>> '{anima,care_score}')::int = 5,
         'tidur penuh harus memberi 5 care_score';
  update public.animas
     set care = jsonb_set(care, '{energy}', '0'::jsonb),
         sleep_started_at = now() - interval '6 hours',
         sleep_energy_at_start = 0,
         care_synced_at = now()
   where id = v_care_anima;
  v_j := public.apply_care(u1, v_care_anima, 'sync', null);
  assert (v_j #>> '{anima,care,energy}')::numeric = 100
         and (v_j #>> '{anima,care_score}')::integer = 5
         and (v_j #>> '{anima,sleep_started_at}') is null,
         'siklus tidur kedua tetap memulihkan Energy tanpa EXP tambahan hari itu';

  -- Bonus terawat tepat sekali per hari sipil lokal, tanpa Bond.
  update public.animas
     set care = '{"hunger":80,"energy":80,"hygiene":80,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now(),
         well_cared_on = null
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select care_score from public.animas where id = v_care_anima) = 8,
         'bonus terawat +8 hanya boleh sekali per hari';

  -- Decay sejak sync terakhir, tanpa grace. Dua jam sudah memotong Hunger;
  -- 25 jam menghabiskannya. Cap 48 jam tetap memasukkan Dormant.
  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now() - interval '2 hours',
         well_cared_on = public.local_civil_date(now(), 420)
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select (care->>'hunger')::numeric from public.animas where id = v_care_anima) = 92,
         'dua jam aktif harus memotong Hunger 8 supaya Feed terasa';

  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now() - interval '8 hours'
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select (care->>'hunger')::numeric from public.animas where id = v_care_anima) = 68,
         'delapan jam aktif harus memotong Hunger 32';

  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now() - interval '25 hours'
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select (care->>'hunger')::numeric from public.animas where id = v_care_anima) = 0,
         'Hunger aktif habis dalam 25 jam';

  -- Cap 48 jam memasukkan Dormant. EXP tetap. Dua Feed + dua Clean dari nol
  -- melewati ambang recovery 50 tanpa mengubah generation status=ready.
  update public.profiles set bits = 50 where id = u1;
  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":40}'::jsonb,
         care_score = 99,
         care_synced_at = now() - interval '56 hours',
         dormant_since = null,
         well_cared_on = public.local_civil_date(now(), 420)
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select dormant_since is not null from public.animas where id = v_care_anima),
         '48 jam decay efektif harus memasukkan Dormant';
  assert (select care_score from public.animas where id = v_care_anima) = 99,
         'masuk Dormant tidak boleh mereset EXP';
  assert (select status from public.animas where id = v_care_anima) = 'ready',
         'Dormant tidak boleh mencampur arti generation status';

  insert into public.player_inventory (owner_id, item_id, quantity)
  values (u1, 'ember_noodles', 2)
  on conflict (owner_id, item_id) do update set quantity = 2;
  perform public.apply_care(u1, v_care_anima, 'feed', 'care-recover-feed-1', 'ember_noodles');
  perform public.apply_care(u1, v_care_anima, 'feed', 'care-recover-feed-2', 'ember_noodles');
  perform public.apply_care(u1, v_care_anima, 'clean', 'care-recover-clean-1');
  perform public.apply_care(u1, v_care_anima, 'clean', 'care-recover-clean-2');
  assert (select dormant_since is null from public.animas where id = v_care_anima),
         'Hunger dan Hygiene >=50 harus memulihkan Dormant';

  -- Anima yang tidak di-Summon tidur: Energy pulih, tanpa +5 EXP.
  insert into public.animas (
    owner_id, nickname, species_key, color_bucket, element, rarity,
    base_stats, care, status, care_synced_at
  )
  values (
    u1, 'uji bench', 'mouse_plastic', 'gray', 'tech', 1, v_stats,
    '{"hunger":100,"energy":10,"hygiene":100,"bond":0}'::jsonb,
    'ready', now() - interval '90 minutes'
  )
  returning id into v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,sleep_started_at}') is not null,
         'Anima yang tidak di-Summon harus tidur';
  assert (v_j #>> '{anima,care,energy}')::numeric between 54.9 and 55.1,
         'tidur 1.5 jam di Collection harus memulihkan setengah Energy';
  assert (v_j #>> '{anima,care_score}')::int = 0,
         'tidur di Collection tidak boleh memberi EXP tidur penuh';

  update public.animas
     set sleep_started_at = now() - interval '3 hours',
         sleep_energy_at_start = 10,
         care = '{"hunger":70,"energy":10,"hygiene":70,"bond":0}'::jsonb,
         care_synced_at = now() - interval '3 hours',
         care_score = 0
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,sleep_started_at}') is not null,
         'tidur Collection tidak auto-bangun setelah Energy penuh';
  assert (v_j #>> '{anima,care,energy}')::numeric = 100,
         'Energy Collection penuh dalam tiga jam';
  assert (v_j #>> '{anima,care_score}')::int = 0,
         'tiga jam di Collection tidak boleh +5 EXP';

  v_j := public.apply_care(u1, v_bench_anima, 'summon', 'care-summon-bench');
  assert (v_j #>> '{anima,sleep_started_at}') is null,
         'Summon harus membangunkan companion baru';
  assert (select sleep_started_at is not null from public.animas where id = v_care_anima),
         'companion lama harus tidur saat yang lain di-Summon';
  assert (select active_anima_id from public.profiles where id = u1) = v_bench_anima,
         'Summon menulis companion aktif di server';
  perform public.apply_care(u1, v_care_anima, 'summon', 'care-summon-back');

  -- Collection memakai 25% decay aktif dan floor di atas ambang Hungry/Dirty.
  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now() - interval '8 hours',
         dormant_since = null
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,care,hunger}')::numeric = 92,
         'delapan jam bangku harus memotong Hunger 8';
  assert (v_j #>> '{anima,care,hygiene}')::numeric = 91.6,
         'Hygiene bangku turun 1.05 per jam';

  update public.animas
     set care = '{"hunger":10,"energy":100,"hygiene":10,"bond":0}'::jsonb,
         care_synced_at = now() - interval '2 hours',
         care_score = 0,
         well_cared_on = null,
         dormant_since = null
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,care,hunger}')::numeric = 8,
         'bangku tidak mengangkat Hunger yang sudah di bawah 40';
  assert (v_j #>> '{anima,care,hygiene}')::numeric = 7.9,
         'bangku tidak mengangkat Hygiene yang sudah di bawah 50';

  update public.animas
     set care = '{"hunger":80,"energy":80,"hygiene":80,"bond":0}'::jsonb,
         care_synced_at = now(),
         care_score = 0,
         well_cared_on = null,
         dormant_since = null
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,care_score}')::int = 0
         and (v_j #>> '{anima,well_cared_on}') is null,
         'sync Collection tidak boleh memberi bonus terawat +8';

  update public.animas
     set care = '{"hunger":60,"energy":100,"hygiene":10,"bond":0}'::jsonb,
         care_synced_at = now() - interval '2 hours',
         care_score = 0,
         dormant_since = now() - interval '1 day'
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,dormant_since}') is not null,
         'Dormant bangku tidak pulih hanya karena floor Hygiene';
  assert (v_j #>> '{anima,care,hunger}')::numeric = 58,
         'Hunger bangku yang sudah di-Feed tetap turun 1/jam';
  assert (v_j #>> '{anima,care,hygiene}')::numeric = 7.9,
         'Hygiene Dormant bangku tidak diangkat ke 50';

  update public.animas
     set care = '{"hunger":60,"energy":100,"hygiene":60,"bond":0}'::jsonb,
         care_synced_at = now(),
         dormant_since = now() - interval '1 day'
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'summon', 'care-summon-dormant-ready');
  assert (v_j #>> '{anima,dormant_since}') is null,
         'Summon Anima yang sudah 50/50 boleh memulihkan Dormant';
  perform public.apply_care(u1, v_care_anima, 'summon', 'care-summon-after-dormant');

  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now() - interval '56 hours',
         dormant_since = null
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,dormant_since}') is null,
         'Anima bangku tidak masuk Dormant baru';
  assert (v_j #>> '{anima,care,hunger}')::numeric = 52,
         '48 jam bangku menahan Hunger di 52';
  assert (v_j #>> '{anima,care,hygiene}')::numeric = 50,
         '48 jam bangku menahan Hygiene di floor 50';

  ----------------------------------------------------------------------------
  -- 11. Battle: eligibility, satu session, turn idempoten, dan reward atomik
  ----------------------------------------------------------------------------
  v_battle_player := v_care_anima;
  select id into v_battle_bot
    from public.animas
   where owner_id = u2 and status = 'ready'
   order by created_at
   limit 1;
  assert v_battle_bot is not null, 'fixture Battle membutuhkan bot ready pemain lain';

  v_battle_player_snapshot := jsonb_build_object(
    'anima_id', v_battle_player,
    'name', 'Uji Anima',
    'species_key', 'mouse_plastic',
    'color_bucket', 'gray',
    'stage', 1,
    'level', 1,
    'element', 'metal',
    'base_stats', '{"hp":50,"atk":50,"def":50,"spd":50,"special":50}'::jsonb
  );
  v_battle_bot_snapshot := jsonb_build_object(
    'anima_id', v_battle_bot,
    'nickname', 'NAMA RAHASIA',
    'owner_id', u2,
    'species_key', v_spesies,
    'color_bucket', 'gray',
    'stage', 1,
    'level', 11,
    'element', 'plant',
    'base_stats', '{"hp":50,"atk":50,"def":50,"spd":50,"special":50}'::jsonb
  );
  v_battle_state := jsonb_build_object(
    'status', 'active',
    'turn', 1,
    'seed', 'quota-battle',
    'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3),
    'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
  );
  update public.animas
     set sheet_path = coalesce(
           sheet_path,
           u2::text || '/' || v_battle_bot::text || '/atlas-test.png'
         ),
         manifest = coalesce(
           manifest,
           '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
         )
   where id = v_battle_bot;
  insert into public.gallery_entries (
    owner_id, anima_id, art_hash, display_name, element, secondary_element,
    stage, thumb_path, moderation_status, published, auto_hidden,
    report_count, published_at
  ) values (
    u2, v_battle_bot, repeat('a', 64), 'Atlas Bot', 'plant', null,
    1, null, 'approved', true, false, 0, now()
  );

  -- Batas kepemilikan diverifikasi lagi di transaksi, bukan dipercaya dari JWT
  -- yang sudah diterjemahkan Edge Function menjadi p_owner.
  begin
    perform public.start_battle(
      u1, v_battle_bot, v_battle_player,
      v_battle_bot_snapshot, v_battle_player_snapshot, v_battle_state, 'cross-owner'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_NOT_FOUND');
  end;
  assert ok, 'pemain tidak boleh memulai Battle memakai Anima pemain lain';

  update public.animas
     set sleep_started_at = now(),
         sleep_energy_at_start = 50,
         care_synced_at = now()
   where id = v_battle_player;
  begin
    perform public.start_battle(
      u1, v_battle_player, v_battle_bot,
      v_battle_player_snapshot, v_battle_bot_snapshot, v_battle_state, 'sleeping'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_SLEEPING');
  end;
  assert ok, 'Anima tidur tidak boleh masuk Battle';

  update public.animas
     set sleep_started_at = null,
         sleep_energy_at_start = null,
         dormant_since = now(),
         care = '{"hunger":0,"energy":100,"hygiene":0,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_battle_player;
  begin
    perform public.start_battle(
      u1, v_battle_player, v_battle_bot,
      v_battle_player_snapshot, v_battle_bot_snapshot, v_battle_state, 'dormant'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_DORMANT');
  end;
  assert ok, 'Anima Dormant tidak boleh masuk Battle';
  update public.animas set dormant_since = null where id = v_battle_player;

  update public.animas
     set care = '{"hunger":100,"energy":19,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_battle_player;
  begin
    perform public.start_battle(
      u1, v_battle_player, v_battle_bot,
      v_battle_player_snapshot, v_battle_bot_snapshot, v_battle_state, 'low-energy'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_LOW_ENERGY');
  end;
  assert ok, 'Energy di bawah 20 harus menolak Battle dan Training';
  update public.animas
     set care = jsonb_set(care, '{energy}', '20'::jsonb),
         care_synced_at = now()
   where id = v_battle_player;

  update public.animas
     set care = '{"hunger":39,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_battle_player;
  begin
    v_j := public.start_battle(
      u1, v_battle_player, v_battle_bot,
      v_battle_player_snapshot, v_battle_bot_snapshot, v_battle_state, 'hungry'
    );
    ok := coalesce(v_j->>'id', '') <> '';
  exception when others then ok := false;
  end;
  assert ok, 'Anima lapar tetap boleh Battle supaya Bits tidak terkunci';
  assert exists (
           select 1
             from public.seeker_atlas_discoveries discovery
             join public.atlas_forms form on form.id = discovery.form_id
            where discovery.owner_id = u1
              and discovery.discovery_source = 'duel'
              and form.anima_id = v_battle_bot
              and form.stage = 1
         ),
         'session Duel pemain yang committed harus mendaftarkan form ke Atlas';
  update public.battle_sessions
     set status = 'forfeited', finished_at = now(), updated_at = now()
   where owner_id = u1 and status = 'active';
  update public.animas
     set care = '{"hunger":40,"energy":20,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_battle_player;

  -- Lawan Duel sistem dipakai ketika tidak ada Anima pemain lain yang duelnya
  -- masih seimbang. Ia sengaja tidak punya baris `animas`, jadi verifikasi lawan
  -- tidak bisa memakai tabel; yang diperiksa adalah penanda snapshot-nya sendiri.
  -- Tanpa dua penolakan di bawah, `bot_anima_id` null berarti client boleh
  -- mengarang lawan apa pun — termasuk lawan berstat sengaja lemah.
  v_system_bot_snapshot := jsonb_build_object(
    'anima_id', 'system-duel-fledgling',
    'name', 'Echo Fledgling',
    'species_key', 'system-duel-fledgling',
    'color_bucket', 'system',
    'stage', 1,
    'level', 1,
    'element', 'metal',
    'base_stats', '{"hp":50,"atk":50,"def":50,"spd":50,"special":50}'::jsonb,
    'system_asset', 'placeholder'
  );
  begin
    perform public.start_battle(
      u1, v_battle_player, null,
      v_battle_player_snapshot,
      v_system_bot_snapshot - 'system_asset',
      v_battle_state, 'system-unmarked'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'BOT_NOT_FOUND');
  end;
  assert ok, 'bot_anima_id null tanpa penanda placeholder harus ditolak';

  begin
    perform public.start_battle(
      u1, v_battle_player, null,
      v_battle_player_snapshot,
      v_system_bot_snapshot || '{"anima_id":""}'::jsonb,
      v_battle_state, 'system-no-slug'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'SNAPSHOT_MISMATCH');
  end;
  assert ok, 'lawan sistem tanpa slug identitas harus ditolak';

  v_j := public.start_battle(
    u1, v_battle_player, null,
    v_battle_player_snapshot, v_system_bot_snapshot, v_battle_state, 'system-bot'
  );
  assert coalesce(v_j->>'id', '') <> '',
         'lawan sistem bertanda placeholder harus diterima';
  assert (select bot_anima_id is null
            from public.battle_sessions where id = (v_j->>'id')::uuid),
         'session lawan sistem tidak boleh menunjuk baris animas';
  assert (select (care->>'energy')::numeric from public.animas where id = v_battle_player) = 0,
         'Duel lawan sistem tetap membayar 20 Energy';
  update public.battle_sessions
     set status = 'forfeited', finished_at = now(), updated_at = now()
   where owner_id = u1 and status = 'active';
  update public.animas
     set care = '{"hunger":40,"energy":20,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_battle_player;

  -- Dua reward sebelumnya membuat kemenangan berikutnya menjadi reward ketiga
  -- hari ini. Nominal kedua sengaja berbeda: reason battle_win adalah counter,
  -- sehingga balancing Bits tidak boleh diam-diam membuka cap.
  update public.profiles set bits = bits + 11 where id = u1;
  update public.animas
     set care_score = care_score + 8,
         battle_wins = battle_wins + 2
   where id = v_battle_player;
  insert into public.quota_ledger
    (owner_id, currency, delta, reason, ref_id, created_at)
  values
    (u1, 'bits', 5, 'battle_win', gen_random_uuid(), now()),
    (u1, 'bits', 6, 'battle_win', gen_random_uuid(), now()),
    (u1, 'bits', 5, 'battle_win', gen_random_uuid(), now() - interval '25 hours');

  v_j := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot, v_battle_state, 'battle-win'
  );
  v_battle_session := (v_j->>'id')::uuid;
  assert v_battle_session is not null, 'start Battle harus membuat session';
  assert (select (care->>'energy')::numeric from public.animas where id = v_battle_player) = 0,
         'start Battle harus memotong 20 Energy';
  assert (v_j #>> '{daily_reward,earned}')::int = 2
         and (v_j #>> '{daily_reward,limit}')::int = 3
         and (v_j #>> '{daily_reward,remaining}')::int = 1,
         'counter harus memakai reason lintas nominal dan mengabaikan hari sebelumnya';
  assert not (v_j->'bot_snapshot' ? 'owner_id')
         and not (v_j->'bot_snapshot' ? 'nickname'),
         'snapshot bot yang kembali ke client wajib anonim';
  v_j2 := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot, v_battle_state, 'battle-start-race'
  );
  assert (v_j2->>'id')::uuid = v_battle_session,
         'dua start paralel harus bertemu di satu session aktif';
  assert (select (care->>'energy')::numeric from public.animas where id = v_battle_player) = 0,
         'resume start tidak boleh memotong Energy kedua kali';
  assert (public.resume_battle(u1, v_battle_session)->>'id')::uuid = v_battle_session,
         'session aktif harus bisa dilanjutkan setelah restart';

  select bits into v_bits_before_battle from public.profiles where id = u1;
  select care_score, battle_wins
    into v_score_before_battle, v_wins_before_battle
    from public.animas where id = v_battle_player;
  select seeker_xp, battle_victories
    into v_seeker_xp, v_seeker_victories
    from public.profiles where id = u1;
  v_battle_state := jsonb_build_object(
    'status', 'won',
    'turn', 2,
    'seed', 'battle-win',
    'player', jsonb_build_object('hp', 120, 'max_hp', 220, 'momentum', 2),
    'bot', jsonb_build_object('hp', 0, 'max_hp', 220, 'momentum', 3)
  );
  v_j := public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-win', 'surge',
    v_battle_state,
    '[{"type":"attack","actor":"player","damage":220},{"type":"finished","result":"won"}]'::jsonb,
    'strike'
  );
  assert (v_j #>> '{reward,bits}')::int = 8, 'menang Even default harus memberi 8 Bits';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 8,
         'saldo Bits dan response reward harus commit bersama';
  assert (select care_score from public.animas where id = v_battle_player)
           = v_score_before_battle + 5
         and (v_j #>> '{reward,care_score}')::integer = 5,
         'Duel lawan Lv.11 harus memberi base + underdog dari snapshot';
  assert (select battle_wins from public.animas where id = v_battle_player)
           = v_wins_before_battle + 1,
         'menang harus menaikkan battle_wins satu';
  assert (select seeker_xp from public.profiles where id = u1) = v_seeker_xp + 5
         and (select battle_victories from public.profiles where id = u1)
           = v_seeker_victories + 1,
         'Battle rewarded harus memberi Seeker EXP dan satu victory';
  assert (select count(*) from public.quota_ledger
           where ref_id = v_battle_session and currency = 'bits'
             and delta = 8 and reason = 'battle_win') = 1,
         'reward Battle harus punya tepat satu baris ledger';
  assert (v_j #>> '{session,daily_reward,earned}')::int = 3
         and (v_j #>> '{session,daily_reward,remaining}')::int = 0
         and (v_j #>> '{session,daily_reward,rewarded}')::bool,
         'reward ketiga tetap dibayar lalu menutup kuota hari ini';

  v_j2 := public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-win', 'surge',
    v_battle_state,
    '[{"type":"attack","actor":"player","damage":220},{"type":"finished","result":"won"}]'::jsonb,
    'strike'
  );
  assert (v_j2->>'replayed')::bool, 'retry turn harus mengembalikan response tersimpan';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 8,
         'retry tidak boleh membayar reward kedua';
  assert (select count(*) from public.battle_turns
           where session_id = v_battle_session) = 1,
         'retry harus tetap satu battle_turn';

  begin
    perform public.commit_battle_turn(
      u1, v_battle_session, 1, 1, 'battle-race-loser', 'strike',
      v_battle_state, '[]'::jsonb, 'strike'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'BATTLE_FINISHED');
  end;
  assert ok, 'request turn kedua yang kalah race tidak boleh commit';

  -- Kemenangan keempat tetap menyelesaikan Battle, tetapi seluruh progression
  -- reward nol. Membatasi Bits saja akan memindahkan exploit ke evolusi.
  update public.animas
     set care = jsonb_set(care, '{energy}', '100'::jsonb),
         care_synced_at = now()
   where id = v_battle_player;
  v_j := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot,
    jsonb_set(jsonb_set(v_battle_state, '{status}', '"active"'), '{turn}', '1'),
    'battle-training'
  );
  v_battle_session := (v_j->>'id')::uuid;
  select bits into v_bits_before_battle from public.profiles where id = u1;
  select care_score, battle_wins
    into v_score_before_battle, v_wins_before_battle
    from public.animas where id = v_battle_player;
  select seeker_xp, battle_victories
    into v_seeker_xp, v_seeker_victories
    from public.profiles where id = u1;
  v_j := public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-training', 'surge',
    jsonb_build_object(
      'status', 'won', 'turn', 2, 'seed', 'battle-training',
      'player', jsonb_build_object('hp', 120, 'max_hp', 220, 'momentum', 2),
      'bot', jsonb_build_object('hp', 0, 'max_hp', 220, 'momentum', 3)
    ),
    '[{"type":"attack","actor":"player","damage":220},{"type":"finished","result":"won"}]'::jsonb,
    'strike'
  );
  assert (v_j #>> '{reward,bits}')::int = 8
         and (v_j #>> '{reward,care_score}')::int = 0
         and (v_j #>> '{reward,battle_wins}')::int = 0
         and (v_j #>> '{reward,progression_capped}')::bool,
         'win setelah 3/3 harus tetap membayar Bits sebagai Training';
  assert (v_j #>> '{session,daily_reward,progression_rewarded}')::bool = false
         and (v_j #>> '{session,daily_reward,earned}')::int = 3,
         'payload Training harus menjelaskan bahwa progression sudah cap';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 8
         and (select care_score from public.animas where id = v_battle_player)
           = v_score_before_battle
         and (select battle_wins from public.animas where id = v_battle_player)
           = v_wins_before_battle,
         'Training boleh menambah Bits tetapi tidak EXP atau win tercatat';
  assert (select seeker_xp from public.profiles where id = u1) = v_seeker_xp
         and (select battle_victories from public.profiles where id = u1)
           = v_seeker_victories + 1,
         'Training harus dihitung sebagai victory tanpa memberi Seeker EXP';
  assert (select count(*) from public.quota_ledger
           where ref_id = v_battle_session and reason = 'battle_train') = 1,
         'Training ber-Bits harus memakai reason battle_train';
  assert (select count(*) from public.quota_ledger
           where ref_id = v_battle_session and reason = 'battle_win') = 0,
         'Training tidak boleh menambah counter progression';
  v_j2 := public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-training', 'surge',
    jsonb_build_object(
      'status', 'won', 'turn', 2, 'seed', 'battle-training',
      'player', jsonb_build_object('hp', 120, 'max_hp', 220, 'momentum', 2),
      'bot', jsonb_build_object('hp', 0, 'max_hp', 220, 'momentum', 3)
    ),
    '[{"type":"attack","actor":"player","damage":220},{"type":"finished","result":"won"}]'::jsonb,
    'strike'
  );
  assert (v_j2->>'replayed')::bool
         and (v_j2 #>> '{reward,bits}')::int = 8,
         'retry Training harus replay Bits yang sama';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 8,
         'retry Training tidak boleh membuat reward baru';
  assert (select battle_victories from public.profiles where id = u1)
           = v_seeker_victories + 1,
         'replay Training tidak boleh menghitung victory kedua';

  -- Kalah dan forfeit tidak pernah menyentuh Bits, score, wins, atau Core.
  update public.animas
     set care = jsonb_set(care, '{energy}', '100'::jsonb),
         care_synced_at = now()
   where id = v_battle_player;
  v_j := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot,
    jsonb_set(jsonb_set(v_battle_state, '{status}', '"active"'), '{turn}', '1'),
    'battle-loss'
  );
  v_battle_session := (v_j->>'id')::uuid;
  select bits, genesis_cores into v_bits_before_battle, v from public.profiles where id = u1;
  select care_score, battle_wins
    into v_score_before_battle, v_wins_before_battle
    from public.animas where id = v_battle_player;
  perform public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-loss', 'strike',
    jsonb_build_object(
      'status', 'lost', 'turn', 2, 'seed', 'battle-loss',
      'player', jsonb_build_object('hp', 0, 'max_hp', 220, 'momentum', 3),
      'bot', jsonb_build_object('hp', 100, 'max_hp', 220, 'momentum', 2)
    ),
    '[{"type":"finished","result":"lost"}]'::jsonb,
    'surge'
  );
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle,
         'kalah tidak boleh memberi Bits';
  assert (select genesis_cores from public.profiles where id = u1) = v,
         'Battle tidak pernah mengubah Genesis Core';
  assert (select care_score from public.animas where id = v_battle_player)
           = v_score_before_battle
         and (select battle_wins from public.animas where id = v_battle_player)
           = v_wins_before_battle,
         'kalah tidak boleh memberi score atau win';

  update public.animas
     set care = jsonb_set(care, '{energy}', '100'::jsonb),
         care_synced_at = now()
   where id = v_battle_player;
  v_j := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot,
    jsonb_build_object(
      'status', 'active', 'turn', 1, 'seed', 'battle-forfeit',
      'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3),
      'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
    ),
    'battle-forfeit'
  );
  v_battle_session := (v_j->>'id')::uuid;
  select bits into v_bits_before_battle from public.profiles where id = u1;
  perform public.forfeit_battle(u1, v_battle_session);
  assert (select status from public.battle_sessions where id = v_battle_session) = 'forfeited',
         'forfeit harus menutup session';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle,
         'forfeit tidak boleh memberi reward';

  ----------------------------------------------------------------------------
  -- Shop: pembelian atomik, harga basi, stack, Bits kurang
  ----------------------------------------------------------------------------
  update public.profiles set bits = 50 where id = u1;
  delete from public.player_inventory where owner_id = u1 and item_id = 'byte_berry';
  v_j := public.purchase_catalog_item(u1, 'byte_berry', 1, 'buy-byte-1');
  assert (v_j->>'bits')::int = 49 and (v_j->>'quantity')::int = 1
         and not (v_j->>'replayed')::bool,
         'pembelian harus mendebit harga katalog dan menambah inventory';
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and reason = 'shop_buy' and delta = -1) = 1,
         'pembelian harus punya satu baris ledger';
  v_j2 := public.purchase_catalog_item(u1, 'byte_berry', 1, 'buy-byte-1');
  assert (v_j2->>'replayed')::bool and (v_j2->>'bits')::int = 49
         and (v_j2->>'quantity')::int = 1,
         'replay pembelian tidak boleh mendebit dua kali';
  begin
    perform public.purchase_catalog_item(u1, 'byte_berry', 99, 'buy-stale');
    ok := false;
  exception when others then ok := (sqlerrm = 'PRICE_CHANGED');
  end;
  assert ok, 'harga yang tidak cocok harus ditolak';
  assert (select bits from public.profiles where id = u1) = 49,
         'PRICE_CHANGED tidak boleh mendebit';
  insert into public.player_inventory (owner_id, item_id, quantity)
  values (u1, 'moon_biscuit', 999)
  on conflict (owner_id, item_id) do update set quantity = 999;
  begin
    perform public.purchase_catalog_item(u1, 'moon_biscuit', 2, 'buy-stack');
    ok := false;
  exception when others then ok := (sqlerrm = 'STACK_FULL');
  end;
  assert ok, 'stack 999 harus menolak pembelian baru';
  update public.profiles set bits = 1 where id = u1;
  begin
    perform public.purchase_catalog_item(u1, 'nova_feast', 10, 'buy-poor');
    ok := false;
  exception when others then ok := (sqlerrm = 'NO_BITS');
  end;
  assert ok, 'Bits kurang harus menolak pembelian';

  ----------------------------------------------------------------------------
  -- Item Battle dibatasi stok, bukan sekali per encounter, dan cap 100 Bits Training
  ----------------------------------------------------------------------------
  update public.profiles set bits = 50 where id = u1;
  insert into public.player_inventory (owner_id, item_id, quantity)
  values (u1, 'vital_patch', 2)
  on conflict (owner_id, item_id) do update set quantity = 2;
  update public.animas
     set care = jsonb_set(care, '{energy}', '100'::jsonb),
         care_synced_at = now()
   where id = v_battle_player;
  v_j := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot,
    jsonb_build_object(
      'status', 'active', 'turn', 1, 'seed', 'battle-item',
      'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3),
      'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
    ),
    'battle-item'
  );
  v_battle_session := (v_j->>'id')::uuid;
  v_j := public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-item', 'item',
    jsonb_build_object(
      'status', 'active', 'turn', 2, 'seed', 'battle-item',
      'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3, 'item_used', true),
      'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
    ),
    '[{"type":"item","actor":"player","item_id":"vital_patch"}]'::jsonb,
    'strike',
    'vital_patch'
  );
  assert (v_j #>> '{session,item_used_id}') = 'vital_patch',
         'item Battle harus tercatat di session';
  assert (select quantity from public.player_inventory
           where owner_id = u1 and item_id = 'vital_patch') = 1,
         'item Battle harus dikonsumsi sekali per use';
  v_j := public.commit_battle_turn(
    u1, v_battle_session, 2, 2, 'battle-turn-item-2', 'item',
    jsonb_build_object(
      'status', 'active', 'turn', 3, 'seed', 'battle-item',
      'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3, 'item_used', true),
      'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
    ),
    '[{"type":"item","actor":"player","item_id":"vital_patch"}]'::jsonb,
    'strike',
    'vital_patch'
  );
  assert (v_j #>> '{session,item_used_id}') = 'vital_patch',
         'item Battle boleh dipakai lagi turn berikutnya selama stok masih ada';
  assert not exists (
           select 1 from public.player_inventory
            where owner_id = u1 and item_id = 'vital_patch'
         ),
         'stok habis harus menghapus baris inventory, bukan menyisakan quantity 0';
  begin
    perform public.commit_battle_turn(
      u1, v_battle_session, 3, 3, 'battle-turn-item-3', 'item',
      jsonb_build_object(
        'status', 'active', 'turn', 4, 'seed', 'battle-item',
        'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3, 'item_used', true),
        'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
      ),
      '[{"type":"item","actor":"player","item_id":"vital_patch"}]'::jsonb,
      'strike',
      'vital_patch'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'NO_ITEM');
  end;
  assert ok, 'item Battle tanpa stok tersisa harus ditolak NO_ITEM';
  perform public.forfeit_battle(u1, v_battle_session);

  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id, created_at)
  values (u1, 'bits', 70, 'battle_train', gen_random_uuid(), now());
  update public.animas
     set care = jsonb_set(care, '{energy}', '100'::jsonb),
         care_synced_at = now()
   where id = v_battle_player;
  v_j := public.start_battle(
    u1, v_battle_player, v_battle_bot,
    v_battle_player_snapshot, v_battle_bot_snapshot,
    jsonb_build_object(
      'status', 'active', 'turn', 1, 'seed', 'battle-cap',
      'player', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3),
      'bot', jsonb_build_object('hp', 220, 'max_hp', 220, 'momentum', 3)
    ),
    'battle-cap'
  );
  v_battle_session := (v_j->>'id')::uuid;
  select bits into v_bits_before_battle from public.profiles where id = u1;
  v_j := public.commit_battle_turn(
    u1, v_battle_session, 1, 1, 'battle-turn-cap', 'surge',
    jsonb_build_object(
      'status', 'won', 'turn', 2, 'seed', 'battle-cap',
      'player', jsonb_build_object('hp', 120, 'max_hp', 220, 'momentum', 2),
      'bot', jsonb_build_object('hp', 0, 'max_hp', 220, 'momentum', 3)
    ),
    '[{"type":"finished","result":"won"}]'::jsonb,
    'strike'
  );
  assert (v_j #>> '{reward,bits}')::int = 3
         and (v_j #>> '{reward,capped}')::bool = false,
         'payout terakhir harus dijepit sisa cap 100 tanpa melewatinya';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 3,
         'cap 100 Bits harus dihormati di saldo';

  select form.id into v_atlas_form
    from public.atlas_forms form
   where form.anima_id = v_battle_bot and form.stage = 1;
  update public.gallery_entries set published = false
   where anima_id = v_battle_bot;
  assert not exists (
           select 1 from public.seeker_atlas_discoveries
            where owner_id = u1 and form_id = v_atlas_form
         )
         and exists (
           select 1 from public.seeker_atlas_discoveries
            where owner_id = u2 and form_id = v_atlas_form
              and discovery_source = 'scanned'
         ),
         'Unpublish harus menghapus discovery Duel tanpa menghapus form milik owner';
  update public.gallery_entries set published = true, moderation_status = 'approved'
   where anima_id = v_battle_bot;
  perform public._atlas_upsert_discovery(u1, v_atlas_form, 'duel', now(), 11);
  insert into public.gallery_reports (entry_id, reporter_id, art_hash)
  select id, u1, art_hash from public.gallery_entries where anima_id = v_battle_bot;
  assert not exists (
           select 1 from public.seeker_atlas_discoveries
            where owner_id = u1 and form_id = v_atlas_form
         )
         and exists (
           select 1
             from public.gallery_hidden hidden
             join public.gallery_entries entry on entry.id = hidden.entry_id
            where hidden.owner_id = u1 and entry.anima_id = v_battle_bot
         ),
         'Report harus langsung menghilangkan lineage dari Atlas reporter';
  perform public._atlas_upsert_discovery(u3, v_atlas_form, 'duel', now(), 9);
  delete from public.gallery_entries where anima_id = v_battle_bot;
  assert not exists (
           select 1 from public.seeker_atlas_discoveries
            where owner_id = u3 and form_id = v_atlas_form
         )
         and exists (
           select 1 from public.seeker_atlas_discoveries
            where owner_id = u2 and form_id = v_atlas_form
              and discovery_source = 'scanned'
         ),
         'Delete publication harus membersihkan discovery Duel tanpa menghapus form milik owner';

  ----------------------------------------------------------------------------
  -- Structured failure log Duel: service-role only, no PII/raw request body
  ----------------------------------------------------------------------------
  assert to_regclass('public.battle_failures') is not null
         and (select relrowsecurity
                from pg_class
               where oid = 'public.battle_failures'::regclass),
         'battle_failures harus ada dengan RLS aktif';
  assert not exists (
           select 1
             from pg_policies
            where schemaname = 'public' and tablename = 'battle_failures'
         ),
         'battle_failures harus default-deny tanpa policy client';
  assert not has_table_privilege('anon', 'public.battle_failures', 'SELECT')
         and not has_table_privilege('anon', 'public.battle_failures', 'INSERT')
         and not has_table_privilege('authenticated', 'public.battle_failures', 'SELECT')
         and not has_table_privilege('authenticated', 'public.battle_failures', 'INSERT')
         and has_table_privilege('service_role', 'public.battle_failures', 'SELECT')
         and has_table_privilege('service_role', 'public.battle_failures', 'INSERT'),
         'battle_failures hanya boleh diakses service_role';

  insert into public.battle_failures (
    owner_id, session_id, operation, rules_version, error, context
  ) values (
    u1, v_battle_session, 'turn', 3, 'uji failure terstruktur',
    '{"turn_action":"strike","expected_turn":1,"expected_version":1}'::jsonb
  ) returning id into v_id;
  delete from public.battle_sessions where id = v_battle_session;
  assert (select session_id is null from public.battle_failures where id = v_id),
         'hapus session harus mempertahankan failure row dengan session_id null';
  begin
    insert into public.battle_failures (
      owner_id, operation, rules_version, error, context
    ) values (
      u1, 'turn', 3, 'uji context mentah', '{"raw_body":{"token":"x"}}'::jsonb
    );
    ok := false;
  exception when check_violation then ok := true;
  end;
  assert ok, 'context battle failure harus menolak field di luar whitelist';
  delete from public.battle_failures where id = v_id;

  insert into auth.users (id, is_anonymous) values (u5, true);
  insert into public.battle_failures (
    owner_id, operation, rules_version, error
  ) values (
    u5, 'start', 3, 'uji cascade owner'
  ) returning id into v_id;
  delete from auth.users where id = u5;
  assert not exists (select 1 from public.battle_failures where id = v_id),
         'hapus profil harus cascade failure log pemilik';

  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.purchase_catalog_item(u1, 'byte_berry', 1, 'buy-client');
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil RPC pembelian';

  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.resume_battle(u1, v_battle_session);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil RPC Battle service-role';
  begin
    perform 1 from public.battle_sessions;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'state internal Battle tidak boleh terbaca lewat Data API';
  perform set_config('role', 'none', true);

  ----------------------------------------------------------------------------
  -- Capture foundations: schema, flags, Core mingguan, antrian cleanup
  ----------------------------------------------------------------------------
  assert exists (
           select 1
             from pg_constraint
            where conrelid = 'public.animas'::regclass
              and conname = 'animas_element_v2_valid'
              and pg_get_constraintdef(oid) like '%sound%'
         ),
         'constraint roster 18 elemen harus terpasang pada animas';
  assert (select count(*) from public.app_config
           where key in (
             'feature_typing_v13', 'feature_unique_generation', 'feature_animals',
             'feature_weekly_core', 'feature_gallery', 'feature_atlas',
             'min_client_version'
           )) = 7,
         'app_config rollout flags dan min_client_version harus ada';
  assert (
           select jsonb_typeof(value) = 'boolean'
             from public.app_config
            where key = 'feature_weekly_core'
         ),
         'feature_weekly_core harus berupa feature flag boolean';
  assert (select count(*) from public.app_config
           where key in (
             'feature_team_battle', 'feature_expedition', 'feature_chapter_push',
             'team_battle_energy_per_member', 'team_battle_rewarded_wins_per_day',
             'team_battle_bits_per_day', 'team_battle_active_exp',
             'team_battle_bench_exp', 'expedition_energy_per_member',
             'expedition_rewarded_encounters_per_day', 'expedition_active_exp',
             'expedition_bench_exp', 'expedition_daily_exp_budget'
           )) = 13,
         'app_config Team Battle/Expedition harus lengkap';
  assert (select count(*) from public.app_config
           where key in (
             'feature_team_battle', 'feature_expedition', 'feature_chapter_push'
           )
             and jsonb_typeof(value) = 'boolean') = 3,
         'feature Team Battle/Expedition/push harus berupa boolean';
  assert exists (
           select 1 from public.system_team_templates where active
         ),
         'fresh database harus punya system team fallback';
  assert (select value from public.app_config where key = 'team_battle_energy_per_member') = '10'::jsonb
         and (select value from public.app_config where key = 'team_battle_rewarded_wins_per_day') = '2'::jsonb
         and (select value from public.app_config where key = 'team_battle_bits_per_day') = '40'::jsonb
         and (select value from public.app_config where key = 'team_battle_active_exp') = '2'::jsonb
         and (select value from public.app_config where key = 'team_battle_bench_exp') = '1'::jsonb
         and (select value from public.app_config where key = 'expedition_energy_per_member') = '30'::jsonb
         and (select value from public.app_config where key = 'expedition_rewarded_encounters_per_day') = '3'::jsonb
         and (select value from public.app_config where key = 'expedition_active_exp') = '2'::jsonb
         and (select value from public.app_config where key = 'expedition_bench_exp') = '1'::jsonb
         and (select value from public.app_config where key = 'expedition_daily_exp_budget') = '30'::jsonb,
         'baseline economy Team Battle/Expedition harus sesuai spesifikasi';

  with inserted as (
    insert into public.animas (
      owner_id, nickname, species_key, color_bucket, element, rarity,
      base_stats, care, status, sheet_path, manifest
    )
    select
      u1, 'team-' || gs.n, 'team_species_' || gs.n, 'blue', 'metal', 1,
      v_stats, v_care, 'ready', u1::text || '/team-' || gs.n || '/sheet.png',
      '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
      from generate_series(1, 5) as gs(n)
    returning id, nickname
  )
  select array_agg(id order by nickname) into v_team_ids from inserted;

  begin
    perform public.save_anima_team(u1, 'team_battle', v_team_ids[1:1]);
    ok := false;
  exception when others then ok := (sqlerrm = 'TEAM_REQUIRES_TWO_TO_FOUR');
  end;
  assert ok, 'Team Battle satu anggota harus ditolak';
  v_j := public.save_anima_team(u1, 'team_battle', v_team_ids[1:2]);
  assert jsonb_array_length(v_j->'members') = 2,
         'Team Battle dua anggota harus diterima';
  v_j := public.save_anima_team(u1, 'team_battle', v_team_ids[1:3]);
  assert jsonb_array_length(v_j->'members') = 3,
         'Team Battle tiga anggota harus diterima';
  v_j := public.save_anima_team(u1, 'team_battle', v_team_ids[1:4]);
  assert jsonb_array_length(v_j->'members') = 4,
         'Team Battle empat anggota harus tetap diterima';
  begin
    perform public.save_anima_team(u1, 'team_battle', v_team_ids);
    ok := false;
  exception when others then ok := (sqlerrm = 'TEAM_REQUIRES_TWO_TO_FOUR');
  end;
  assert ok, 'Team Battle lima anggota harus ditolak';
  begin
    perform public.save_anima_team(u1, 'expedition', v_team_ids[1:2]);
    ok := false;
  exception when others then ok := (sqlerrm = 'TEAM_REQUIRES_FOUR');
  end;
  assert ok, 'Expedition dua anggota harus tetap ditolak';
  begin
    perform public.save_anima_team(u1, 'expedition', v_team_ids[1:3]);
    ok := false;
  exception when others then ok := (sqlerrm = 'TEAM_REQUIRES_FOUR');
  end;
  assert ok, 'Expedition tiga anggota harus tetap ditolak';
  v_team_ids := v_team_ids[1:4];

  with inserted as (
    insert into public.animas (
      owner_id, nickname, species_key, color_bucket, element, rarity,
      base_stats, care, status, sheet_path, manifest
    )
    select
      u2, 'defense-' || gs.n, 'defense_species_' || gs.n, 'red', 'plant', 1,
      v_stats, v_care, 'ready', u2::text || '/defense-' || gs.n || '/sheet.png',
      '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
      from generate_series(1, 4) as gs(n)
    returning id, nickname
  )
  select array_agg(id order by nickname) into v_defense_ids from inserted;

  v_j := public.save_anima_team(u1, 'team_battle', v_team_ids);
  v_team_id := (v_j->>'id')::uuid;
  assert jsonb_array_length(v_j->'members') = 4,
         'save Team empat anggota harus atomik';

  v_j := public.save_anima_team(u2, 'defense', v_defense_ids[1:2]);
  select jsonb_agg(jsonb_build_object('anima_id', id) order by ordinality)
    into v_opponent_snapshot
    from unnest(v_defense_ids[1:2]) with ordinality roster(id, ordinality);
  v_j := public.publish_defense_team(u2, v_opponent_snapshot, true);
  assert (v_j->>'published')::boolean
         and (select jsonb_array_length(snapshot) from public.anima_teams
               where owner_id = u2 and kind = 'defense') = 2,
         'Defense dua anggota harus dapat dipublikasikan';
  v_j := public.save_anima_team(u2, 'defense', v_defense_ids[1:3]);
  select jsonb_agg(jsonb_build_object('anima_id', id) order by ordinality)
    into v_opponent_snapshot
    from unnest(v_defense_ids[1:3]) with ordinality roster(id, ordinality);
  v_j := public.publish_defense_team(u2, v_opponent_snapshot, true);
  assert (v_j->>'published')::boolean
         and (select jsonb_array_length(snapshot) from public.anima_teams
               where owner_id = u2 and kind = 'defense') = 3,
         'Defense tiga anggota harus dapat dipublikasikan';
  v_j := public.save_anima_team(u2, 'defense', v_defense_ids);
  v_defense_team_id := (v_j->>'id')::uuid;
  assert jsonb_array_length(v_j->'members') = 4,
         'Defense empat anggota harus tetap diterima';

  select jsonb_agg(jsonb_build_object(
    'anima_id', a.id,
    'name', a.nickname,
    'species_key', a.species_key,
    'color_bucket', a.color_bucket,
    'stage', a.stage,
    'level', 1,
    'element', a.element,
    'base_stats', a.base_stats,
    'hunger', 100,
    'hygiene', 100,
    'strike_name', a.strike_name,
    'surge_name', a.surge_name,
    'sheet_path', a.sheet_path,
    'manifest', a.manifest
  ) order by ids.ordinality)
  into v_team_snapshot
  from unnest(v_team_ids) with ordinality ids(id, ordinality)
  join public.animas a on a.id = ids.id;

  select jsonb_agg(jsonb_build_object(
    'anima_id', a.id,
    'name', 'Anima',
    'species_key', a.species_key,
    'color_bucket', a.color_bucket,
    'stage', a.stage,
    'level', 11,
    'element', a.element,
    'base_stats', a.base_stats,
    'hunger', 100,
    'hygiene', 100,
    'strike_name', a.strike_name,
    'surge_name', a.surge_name,
    'sheet_path', a.sheet_path,
    'manifest', a.manifest
  ) order by ids.ordinality)
  into v_opponent_snapshot
  from unnest(v_defense_ids) with ordinality ids(id, ordinality)
  join public.animas a on a.id = ids.id;

  v_j := public.publish_defense_team(u2, v_opponent_snapshot, true);
  assert (v_j->>'published')::boolean,
         'Defense Team harus opt-in sebelum masuk pool';

  begin
    perform public.replace_team_battle_candidates(
      u1,
      v_team_id,
      jsonb_build_array(jsonb_build_object(
        'opponent_source', 'atlas',
        'opponent_team_id', null,
        'opponent_snapshot', v_opponent_snapshot - 3,
        'reward_tier', 'even',
        'reward_roll', 0,
        'reward_bits', 8
      ))
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'INVALID_TEAM_CANDIDATES');
  end;
  assert ok, 'rival Atlas harus persis sebesar roster pemain';
  v_j := public.replace_team_battle_candidates(
    u1,
    v_team_id,
    jsonb_build_array(jsonb_build_object(
      'opponent_source', 'atlas',
      'opponent_team_id', null,
      'opponent_snapshot', v_opponent_snapshot,
      'reward_tier', 'even',
      'reward_roll', 0,
      'reward_bits', 8
    ))
  );
  assert v_j->0->>'opponent_source' = 'atlas',
         'rival campuran dari publication Atlas harus diterima';

  v_j := public.replace_team_battle_candidates(
    u1,
    v_team_id,
    jsonb_build_array(jsonb_build_object(
      'opponent_source', 'defense',
      'opponent_team_id', v_defense_team_id,
      'opponent_snapshot', v_opponent_snapshot,
      'reward_tier', 'even',
      'reward_roll', 0,
      'reward_bits', 8
    ))
  );
  v_team_candidate := (v_j->0->>'id')::uuid;
  v_j2 := public.replace_team_battle_candidates(
    u1,
    v_team_id,
    jsonb_build_array(jsonb_build_object(
      'opponent_source', 'defense',
      'opponent_team_id', v_defense_team_id,
      'opponent_snapshot', v_opponent_snapshot,
      'reward_tier', 'even',
      'reward_roll', 0,
      'reward_bits', 8
    ))
  );
  assert not exists (
           select 1 from public.team_battle_candidates where id = v_team_candidate
         )
         and (select count(*) from public.team_battle_candidates
               where owner_id = u1 and consumed_at is null) = 1,
         'refresh rival harus mengganti candidate lama, bukan menumpuk pilihan';
  v_team_candidate := (v_j2->0->>'id')::uuid;

  select jsonb_build_object(
    'status', 'active',
    'turn', 1,
    'seed', 'team-sql-test',
    'player', jsonb_build_object(
      'active_slot', 0,
      'forced_switch', false,
      'item_used', false,
      'roster', (
        select jsonb_agg(jsonb_build_object(
          'anima_id', member->>'anima_id',
          'slot', ordinality - 1,
          'hp', 100,
          'max_hp', 100,
          'momentum', 3,
          'participated', ordinality = 1
        ) order by ordinality)
        from jsonb_array_elements(v_team_snapshot) with ordinality roster(member, ordinality)
      )
    ),
    'opponent', jsonb_build_object(
      'active_slot', 0,
      'forced_switch', false,
      'item_used', false,
      'roster', (
        select jsonb_agg(jsonb_build_object(
          'anima_id', member->>'anima_id',
          'slot', ordinality - 1,
          'hp', 100,
          'max_hp', 100,
          'momentum', 3,
          'participated', false
        ) order by ordinality)
        from jsonb_array_elements(v_opponent_snapshot) with ordinality roster(member, ordinality)
      )
    )
  ) into v_team_state;

  update public.profiles set active_anima_id = v_team_ids[1] where id = u1;
  update public.animas
     set sleep_started_at = now(),
         sleep_energy_at_start = (care->>'energy')::numeric
   where id = v_team_ids[1];
  begin
    perform public.start_team_battle(
      u1, v_team_id, v_team_candidate, v_team_snapshot, v_team_state, 'team-sleep-test'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'TEAM_MEMBER_SLEEPING');
  end;
  assert ok, 'companion aktif yang tidur tidak boleh mulai Team Battle';
  update public.animas
     set sleep_started_at = null, sleep_energy_at_start = null
   where id = v_team_ids[1];

  update public.animas
     set care = jsonb_set(care, '{energy}', '9'::jsonb),
         care_synced_at = now()
   where id = v_team_ids[4];
  begin
    perform public.start_team_battle(
      u1, v_team_id, v_team_candidate, v_team_snapshot, v_team_state, 'team-energy-test'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'TEAM_MEMBER_LOW_ENERGY');
  end;
  assert ok
         and (select count(*) from public.animas
               where id = any(v_team_ids[1:3])
                 and (care->>'energy')::numeric = 100) = 3,
         'Energy rendah harus menolak atomik tanpa debit anggota sebelumnya';
  update public.animas
     set care = jsonb_set(care, '{energy}', '100'::jsonb),
         care_synced_at = now()
   where id = v_team_ids[4];

  v_j := public.start_team_battle(
    u1, v_team_id, v_team_candidate, v_team_snapshot, v_team_state, 'team-sql-test'
  );
  v_team_session := (v_j->>'id')::uuid;
  assert (select count(*) from public.animas
           where id = any(v_team_ids) and (care->>'energy')::numeric = 90) = 4,
         'start Team Battle harus memotong 10 Energy dari semua anggota';
  select array_agg(a.care_score order by ids.ordinality)
    into v_team_scores_before
    from unnest(v_team_ids) with ordinality ids(id, ordinality)
    join public.animas a on a.id = ids.id;
  begin
    delete from public.animas where id = v_team_ids[1];
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_IN_ACTIVE_COMBAT');
  end;
  assert ok, 'Anima di active Team Battle tidak boleh dihapus';

  begin
    insert into public.battle_sessions (
      owner_id, player_anima_id, bot_anima_id,
      player_snapshot, bot_snapshot, state,
      player_hp, bot_hp, rng_seed
    ) values (
      u1, v_team_ids[1], v_defense_ids[1],
      '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
      100, 100, 'cross-mode-test'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'COMBAT_ALREADY_ACTIVE');
  end;
  assert ok, 'Duel dan Team Battle tidak boleh aktif bersamaan';

  v_team_state := jsonb_set(
    v_team_state,
    '{player,roster}',
    (
      select jsonb_agg(
        case
          when ordinality <= 2
            then jsonb_set(member, '{participated}', 'true'::jsonb)
          when ordinality = 4
            then jsonb_set(member, '{hp}', '0'::jsonb)
          else member
        end
        order by ordinality
      )
      from jsonb_array_elements(v_team_state #> '{player,roster}')
           with ordinality roster(member, ordinality)
    )
  );
  v_team_state := jsonb_set(v_team_state, '{status}', '"won"'::jsonb);
  v_team_state := jsonb_set(v_team_state, '{turn}', '2'::jsonb);
  v_team_state := jsonb_set(
    v_team_state,
    '{opponent,roster}',
    (
      select jsonb_agg(jsonb_set(member, '{hp}', '0'::jsonb) order by ordinality)
      from jsonb_array_elements(v_team_state #> '{opponent,roster}')
           with ordinality roster(member, ordinality)
    )
  );
  v_bits_before_battle := (select bits from public.profiles where id = u1);
  v_seeker_victories := (select battle_victories from public.profiles where id = u1);
  v_j := public.commit_team_battle_turn(
    u1, v_team_session, 1, 1, 'team-turn-1', 'strike',
    null, null, v_team_state,
    '[{"type":"finished","result":"won"}]'::jsonb,
    '{"action":"strike","switch_to_slot":null}'::jsonb
  );
  assert (v_j->'reward'->>'bits')::integer = 8
         and (v_j->'reward'->>'progression')::boolean,
         'win Team pertama harus memberi Bits dan progression';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 8,
         'reward Bits Team harus commit atomik';
  assert (
           select bool_and(
             a.care_score = v_team_scores_before[ids.ordinality::integer]
               + case
                  when ids.ordinality <= 2 then 3
                  when ids.ordinality = 3 then 2
                   else 0
                 end
           )
             from unnest(v_team_ids) with ordinality ids(id, ordinality)
             join public.animas a on a.id = ids.id
         ),
         format(
           'yield penuh 5 dibagi active +3, bench hidup +2, KO 0; actual=%s',
           (select jsonb_agg(jsonb_build_object(
             'id', id,
             'nickname', nickname,
             'care_score', care_score
           ) order by nickname)
              from public.animas
             where id = any(v_team_ids))
         );
  assert (select count(*) from public.animas
           where id = v_team_ids[1] and battle_wins = 1) = 1
         and (select count(*) from public.animas
               where id = any(v_team_ids[2:4]) and battle_wins = 0) = 3,
         'satu Team win hanya boleh menambah satu battle_wins Anima';
  assert (select battle_victories from public.profiles where id = u1)
           = v_seeker_victories + 1,
         'satu session Team won harus menghitung satu Seeker victory';
  assert (select count(*) from public.team_battle_rewards
           where session_id = v_team_session and progression and bits = 8) = 1,
         'receipt reward Team harus unik per session';
  v_j2 := public.resume_team_battle(u1, v_team_session);
  assert (v_j2->'last_reward'->>'bits')::integer = 8
         and (v_j2->'last_reward'->>'progression')::boolean
         and v_j2->'last_reward'->'anima_exp' = v_j->'reward'->'anima_exp'
         and jsonb_array_length(v_j2->'last_reward'->'anima_exp') = 4,
         'resume Team terminal harus membawa receipt per-Anima EXP untuk result UI';

  v_j2 := public.commit_team_battle_turn(
    u1, v_team_session, 1, 1, 'team-turn-1', 'strike',
    null, null, v_team_state,
    '[{"type":"finished","result":"won"}]'::jsonb,
    '{"action":"strike","switch_to_slot":null}'::jsonb
  );
  assert (v_j2->>'replayed')::boolean
         and (select bits from public.profiles where id = u1) = v_bits_before_battle + 8
         and (select count(*) from public.team_battle_rewards
               where session_id = v_team_session) = 1,
         'replay turn Team tidak boleh menggandakan reward atau EXP';

  insert into public.battle_sessions (
    owner_id, player_anima_id, bot_anima_id,
    player_snapshot, bot_snapshot, state,
    player_hp, bot_hp, rng_seed
  ) values (
    u1, v_team_ids[1], v_defense_ids[1],
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    100, 100, 'reverse-cross-mode'
  ) returning id into v_battle_session;
  begin
    insert into public.team_battle_sessions (
      owner_id, player_team_id, opponent_source, opponent_team_id,
      player_snapshot, opponent_snapshot, state, rng_seed,
      reward_tier, reward_roll, reward_bits
    ) values (
      u1, v_team_id, 'defense', v_defense_team_id,
      v_team_snapshot, v_opponent_snapshot, v_team_state, 'blocked-team',
      'even', 0, 8
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'COMBAT_ALREADY_ACTIVE');
  end;
  assert ok, 'Team Battle juga harus ditolak saat Duel sudah aktif';
  update public.battle_sessions
     set status = 'forfeited', finished_at = now()
   where id = v_battle_session;

  update public.app_config set value = '1'::jsonb
   where key = 'team_battle_rewarded_wins_per_day';
  update public.app_config set value = '40'::jsonb
   where key = 'team_battle_bits_per_day';
  v_team_state := jsonb_set(v_team_state, '{status}', '"active"'::jsonb);
  v_team_state := jsonb_set(v_team_state, '{turn}', '1'::jsonb);
  v_team_state := jsonb_set(
    v_team_state,
    '{opponent,roster}',
    (
      select jsonb_agg(jsonb_set(member, '{hp}', '100'::jsonb) order by ordinality)
      from jsonb_array_elements(v_team_state #> '{opponent,roster}')
           with ordinality roster(member, ordinality)
    )
  );
  insert into public.team_battle_sessions (
    owner_id, player_team_id, opponent_source, opponent_team_id,
    player_snapshot, opponent_snapshot, state, rng_seed,
    reward_tier, reward_roll, reward_bits
  ) values (
    u1, v_team_id, 'defense', v_defense_team_id,
    v_team_snapshot, v_opponent_snapshot, v_team_state, 'team-training',
    'even', 0, 8
  ) returning id into v_team_session;
  v_team_state := jsonb_set(v_team_state, '{status}', '"won"'::jsonb);
  v_team_state := jsonb_set(v_team_state, '{turn}', '2'::jsonb);
  v_team_state := jsonb_set(
    v_team_state,
    '{opponent,roster}',
    (
      select jsonb_agg(jsonb_set(member, '{hp}', '0'::jsonb) order by ordinality)
      from jsonb_array_elements(v_team_state #> '{opponent,roster}')
           with ordinality roster(member, ordinality)
    )
  );
  v_score_before_battle := (
    select sum(care_score)::integer from public.animas where id = any(v_team_ids)
  );
  v_bits_before_battle := (select bits from public.profiles where id = u1);
  v_j := public.commit_team_battle_turn(
    u1, v_team_session, 1, 1, 'team-training-turn', 'strike',
    null, null, v_team_state,
    '[{"type":"finished","result":"won"}]'::jsonb,
    '{"action":"strike","switch_to_slot":null}'::jsonb
  );
  assert (v_j->'reward'->>'bits')::integer = 8
         and not (v_j->'reward'->>'progression')::boolean
         and (select sum(care_score)::integer from public.animas
               where id = any(v_team_ids)) = v_score_before_battle
         and (select bits from public.profiles where id = u1) = v_bits_before_battle + 8
         and exists (
           select 1 from public.quota_ledger
            where ref_id = v_team_session and reason = 'team_battle_train' and delta = 8
         ),
         'setelah cap progression, Team Training hanya memberi Bits';
  update public.app_config set value = '16'::jsonb
   where key = 'team_battle_bits_per_day';
  v_j := public.team_battle_daily_reward_status(u1, v_team_session);
  assert (v_j->>'bits_earned')::integer = 16
         and (v_j->>'bits_remaining')::integer = 0,
         'cap Bits Team harus memakai receipt harian terpisah dari Duel';
  update public.app_config set value = '2'::jsonb
   where key = 'team_battle_rewarded_wins_per_day';
  update public.app_config set value = '40'::jsonb
   where key = 'team_battle_bits_per_day';

  perform public.publish_defense_team(u2, '[]'::jsonb, false);
  assert not exists (
           select 1 from public.team_battle_candidates where id = v_team_candidate
         ),
         'unpublish Defense harus membatalkan candidate yang belum/baru dipakai';

  v_j := public.seeker_profile_summary(u1);
  assert jsonb_typeof(v_j->'client_config'->'min_client_version') = 'object'
         and coalesce((v_j->'client_config'->'min_client_version'->>'android')::int, -1) >= 0
         and coalesce((v_j->'client_config'->'min_client_version'->>'ios')::int, -1) >= 0
         and coalesce((v_j->'client_config'->'min_client_version'->>'desktop')::int, -1) >= 0,
         'profile bootstrap harus membawa min_client_version yang client-safe';
  -- Avatar pulang lewat ringkasan yang sama dengan saldo dan statistik, jadi
  -- client tidak butuh round trip kedua untuk satu string. Nilainya dipilih u1
  -- di bagian 8; `is not null` yang membuat uji ini gagal keras kalau tulisan
  -- itu hilang, alih-alih lulus dengan membandingkan dua null.
  assert (v_j->>'seeker_avatar') is not null
         and (v_j->>'seeker_avatar')
             = (select seeker_avatar from public.profiles where id = u1),
         'ringkasan profil Seeker harus membawa Seeker Avatar yang tersimpan';
  assert exists (
           select 1 from storage.buckets
            where id = 'anima_sheets' and not public
         ),
         'bucket anima_sheets harus privat';
  assert exists (
           select 1 from storage.buckets
            where id = 'gallery_thumbs' and not public
         ),
         'bucket gallery_thumbs harus privat';

  assert exists (
           select 1 from information_schema.tables
            where table_schema = 'public' and table_name = 'gallery_entries'
         ),
         'gallery_entries harus ada';
  assert exists (
           select 1 from information_schema.tables
            where table_schema = 'public' and table_name = 'gallery_moderations'
         ),
         'gallery_moderations harus ada';
  assert (
           select relrowsecurity from pg_class
            where oid = 'public.gallery_entries'::regclass
         ),
         'gallery_entries harus RLS aktif';
  assert (
           select bool_and(relrowsecurity) from pg_class
            where oid = any(array[
              'public.staff_accounts', 'public.profile_sanctions',
              'public.admin_audit_log', 'public.moderation_cases',
              'public.moderation_decisions', 'public.gallery_moderation_runs'
            ]::regclass[])
         ),
         'seluruh tabel Atlas Moderation Admin v2 harus RLS aktif';
  assert exists (
           select 1 from information_schema.tables
            where table_schema = 'public' and table_name = 'atlas_forms'
         )
         and exists (
           select 1 from information_schema.tables
            where table_schema = 'public'
              and table_name = 'seeker_atlas_discoveries'
         ),
         'registry form dan discovery ledger Atlas harus ada';
  assert exists (
           select 1 from information_schema.columns
            where table_schema = 'public'
              and table_name = 'atlas_forms'
              and column_name = 'chapter_seeker_name'
         ),
         'Atlas form harus menyimpan nama Boss Seeker untuk special Expedition';
  assert exists (
           select 1
             from public.atlas_forms form
             join public.expedition_chapters chapter on chapter.id = form.chapter_id
            where chapter.slug = 'the-sugarworks'
              and form.source_slug = 'sugarworks-cotton'
              and form.catalog_active
              and form.chapter_seeker_name = 'The Confectioner'
         )
         and exists (
           select 1
             from public.atlas_forms form
             join public.expedition_chapters chapter on chapter.id = form.chapter_id
            where chapter.slug = 'the-sugarworks'
              and form.source_slug = 'sugarworks-gumdrop'
              and form.catalog_active
              and form.chapter_seeker_name is null
         ),
         'hanya Cotton special yang mewarisi The Confectioner di Sugarworks';
  assert (select relrowsecurity from pg_class
           where oid = 'public.atlas_forms'::regclass)
         and (select relrowsecurity from pg_class
               where oid = 'public.seeker_atlas_discoveries'::regclass),
         'kedua tabel Atlas harus tertutup RLS';

  begin
    insert into public.animas
      (owner_id, nickname, species_key, color_bucket, subject_kind, element,
       typing_version, rarity, base_stats, care)
    values
      (u1, 'bad kind', 'mouse_plastic', 'gray', 'creature', 'tech', 1, 1, v_stats, v_care);
    ok := false;
  exception when check_violation then ok := true;
  end;
  assert ok, 'subject_kind tidak dikenal harus ditolak';

  begin
    insert into public.animas
      (owner_id, nickname, species_key, color_bucket, element, secondary_element,
       typing_version, rarity, base_stats, care)
    values
      (u1, 'dup type', 'mouse_plastic', 'gray', 'metal', 'metal', 2, 1, v_stats, v_care);
    ok := false;
  exception when check_violation then ok := true;
  end;
  assert ok, 'secondary identik primary harus ditolak';

  begin
    insert into public.animas
      (owner_id, nickname, species_key, color_bucket, element, secondary_element,
       typing_version, rarity, base_stats, care)
    values
      (u1, 'bad v2', 'mouse_plastic', 'gray', 'tech', null, 2, 1, v_stats, v_care);
    ok := false;
  exception when check_violation then ok := true;
  end;
  assert ok, 'typing_version >= 2 menolak element di luar roster 18';

  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, subject_kind, element,
     secondary_element, typing_version, sheet_path, manifest, rarity, base_stats, care)
  values
    (u1, 'v2 ok', 'ceramic_mug', 'gray', 'object', 'ceramic', 'flow', 2,
     u1::text || '/00000000-0000-4000-8000-000000000099/sheet.png',
     '{"poses":{}}'::jsonb, 2, v_stats, v_care);

  update public.profiles set genesis_cores = 3 where id = u1;
  update public.app_config set value = '999'::jsonb where key = 'daily_spend_cap_usd';
  v_j := public.claim_capture(
    u1, 'uji-private-capture', 'private capture', 'mug_ceramic_handled', 'gray',
    1::smallint, 'ceramic', 'flow', 'object', 2, v_stats, v_care,
    v_visi || '{"strike_name":"Glaze Tap","surge_name":"Cup Torrent"}'::jsonb,
    'v13', 'test-model', 0.07, u1::text || '/uji-private-capture.png'
  );
  v_id := (v_j->>'generation_id')::uuid;
  assert (select genesis_cores from public.profiles where id = u1) = 2
         and (select count(*) from public.generations
               where owner_id = u1 and idempotency_key = 'uji-private-capture') = 1
         and exists (
           select 1 from public.animas
            where id = (v_j->>'anima_id')::uuid
              and subject_kind = 'object'
              and element = 'ceramic'
              and secondary_element = 'flow'
              and typing_version = 2
         ),
         'claim_capture harus mendebit sekali dan menyimpan kontrak typing v2';
  v_j2 := public.claim_capture(
    u1, 'uji-private-capture', 'ignored retry', 'ignored_species', 'gray',
    1::smallint, 'metal', null, 'object', 1, v_stats, v_care, v_visi,
    'v13', 'test-model', 0.07, u1::text || '/ignored.png'
  );
  assert v_j2 = v_j
         and (select genesis_cores from public.profiles where id = u1) = 2
         and (select count(*) from public.quota_ledger
               where ref_id = v_id and delta = -1 and reason = 'genesis') = 1,
         'retry claim_capture harus replay tanpa debit atau row kedua';
  assert (select capture_vibe from public.generations where id = v_id) = 'natural',
         'claim_capture tanpa vibe harus default natural';
  begin
    update public.generations set capture_vibe = 'spicy' where id = v_id;
    ok := false;
  exception when check_violation then ok := true;
  end;
  assert ok, 'capture_vibe di luar allowlist harus ditolak constraint';
  perform public.refund_generation(v_id, 'uji private capture refund');
  assert (select genesis_cores from public.profiles where id = u1) = 3
         and (select count(*) from public.quota_ledger
               where ref_id = v_id and reason = 'refund') = 1,
         'refund capture privat harus mengembalikan Core tepat sekali';
  v_j := public.claim_capture(
    u1, 'uji-capture-vibe', 'vibe capture', 'mug_ceramic_handled', 'gray',
    1::smallint, 'ceramic', 'flow', 'object', 2, v_stats, v_care,
    v_visi, 'v31', 'test-model', 0.07, u1::text || '/uji-capture-vibe.png', 'cute'
  );
  assert (select capture_vibe from public.generations
           where id = (v_j->>'generation_id')::uuid) = 'cute',
         'claim_capture harus menyimpan vibe permintaan pertama';
  v_j2 := public.claim_capture(
    u1, 'uji-capture-vibe', 'ignored retry', 'ignored_species', 'gray',
    1::smallint, 'metal', null, 'object', 1, v_stats, v_care, v_visi,
    'v31', 'test-model', 0.07, u1::text || '/ignored-vibe.png', 'sinister'
  );
  assert v_j2 = v_j
         and (select capture_vibe from public.generations
               where id = (v_j->>'generation_id')::uuid) = 'cute',
         'retry claim_capture tidak boleh mengganti capture_vibe';
  begin
    perform public.claim_capture(
      u1, 'uji-capture-vibe-bad', 'bad vibe', 'mug_ceramic_handled', 'gray',
      1::smallint, 'ceramic', 'flow', 'object', 2, v_stats, v_care,
      v_visi, 'v31', 'test-model', 0.07, u1::text || '/bad-vibe.png', 'spicy'
    );
    ok := false;
  exception when others then
    ok := sqlerrm like '%INVALID_VIBE%';
  end;
  assert ok, 'claim_capture harus menolak vibe di luar allowlist';
  perform public.refund_generation((v_j->>'generation_id')::uuid, 'uji capture vibe refund');

  delete from public.quota_ledger
   where owner_id = u1 and reason = 'weekly_core';
  update public.app_config set value = 'true'::jsonb where key = 'feature_weekly_core';

  update public.profiles
     set genesis_cores = 2,
         last_weekly_core_at = now() - interval '8 days'
   where id = u1;
  v_j := public.seeker_profile_summary(u1);
  assert (v_j->>'genesis_cores')::int = 3,
         'linked account eligible harus menerima +1 Core mingguan';
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and reason = 'weekly_core' and delta = 1) = 1,
         'grant mingguan harus tercatat di ledger';
  v := (select genesis_cores from public.profiles where id = u1);
  v_j := public.seeker_profile_summary(u1);
  assert (v_j->>'genesis_cores')::int = v
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'weekly_core') = 1,
         'sync profil ganda tidak boleh menggandakan grant mingguan';

  update public.profiles
     set genesis_cores = 2,
         last_weekly_core_at = now() - interval '3 days'
   where id = u1;
  v := (select genesis_cores from public.profiles where id = u1);
  v_j := public.seeker_profile_summary(u1);
  assert (v_j->>'genesis_cores')::int = v,
         'grant mingguan harus menunggu rolling 7 hari';

  update public.profiles
     set genesis_cores = 3,
         last_weekly_core_at = now() - interval '14 days'
   where id = u1;
  v_weekly_at := (select last_weekly_core_at from public.profiles where id = u1);
  perform public.seeker_profile_summary(u1);
  assert (select genesis_cores from public.profiles where id = u1) = 3
         and (select last_weekly_core_at from public.profiles where id = u1) = v_weekly_at
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'weekly_core') = 1,
         'bank penuh tidak boleh membuang eligibility mingguan';
  update public.profiles set genesis_cores = 2 where id = u1;
  v_j := public.seeker_profile_summary(u1);
  assert (v_j->>'genesis_cores')::int = 3
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'weekly_core') = 2,
         'sesudah bank turun, grant tertunda harus langsung jatuh';

  update public.profiles
     set genesis_cores = 0,
         last_weekly_core_at = now() - interval '21 days'
   where id = u1;
  v_j := public.seeker_profile_summary(u1);
  assert (v_j->>'genesis_cores')::int = 1
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'weekly_core') = 3,
         'tidak ada catch-up: 21 hari terlewat tetap hanya +1 Core';

  update public.profiles set genesis_cores = 2 where id = u2;
  perform public.seeker_profile_summary(u2);
  assert (select genesis_cores from public.profiles where id = u2) = 2
         and not exists (
           select 1 from public.quota_ledger
            where owner_id = u2 and reason = 'weekly_core'
         ),
         'guest/anonim tidak boleh menerima Core mingguan';

  n := (select count(*) from public.quota_ledger
         where owner_id = u1 and reason = 'weekly_core');
  update public.app_config set value = 'false'::jsonb where key = 'feature_weekly_core';
  update public.profiles
     set genesis_cores = 0,
         last_weekly_core_at = now() - interval '14 days'
   where id = u1;
  v := (select genesis_cores from public.profiles where id = u1);
  perform public.seeker_profile_summary(u1);
  assert (select genesis_cores from public.profiles where id = u1) = v
         and (select count(*) from public.quota_ledger
               where owner_id = u1 and reason = 'weekly_core') = n,
         'feature_weekly_core mati tidak boleh memberi grant';

  begin
    begin
      perform public.stage_expedition_chapter_version(
        'test-stage-gate', 9996, 1, 1,
        '{"android":0,"ios":0,"desktop":0}'::jsonb,
        '{"schema_version":1}'::jsonb,
        repeat('d', 64),
        'expeditions/test-stage-gate/v1/',
        null,
        'test-stage-gate-trophy',
        'Stage Gate Trophy',
        'Only used by the transactional publish gate test.',
        'expeditions/test-stage-gate/trophy/test.png',
        repeat('e', 64),
        '{}'::jsonb
      );
      ok := false;
    exception when others then ok := (sqlerrm = 'CHAPTER_NOT_APPROVED');
    end;
    assert ok, 'staging wajib menolak chapter tanpa approval timestamp';

    v_j := public.stage_expedition_chapter_version(
      'test-stage-gate', 9996, 1, 1,
      '{"android":0,"ios":0,"desktop":0}'::jsonb,
      jsonb_build_object(
        'schema_version', 1,
        'content_version', 1,
        'sequence', 9996,
        'factory', jsonb_build_object(
          'slug', 'test-stage-gate',
          'mode', 'production'
        ),
        'assets', jsonb_build_object(
          'prefix', 'expeditions/test-stage-gate/v1/'
        ),
        'manifest_hash', repeat('d', 64),
        'summary', jsonb_build_object('title', 'Stage Gate'),
        'zones', jsonb_build_array('{}'::jsonb, '{}'::jsonb, '{}'::jsonb),
        'opponents', jsonb_build_array(
          '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
        ),
        'boss', '{}'::jsonb
      ),
      repeat('d', 64),
      'expeditions/test-stage-gate/v1/',
      now(),
      'test-stage-gate-trophy',
      'Stage Gate Trophy',
      'Only used by the transactional publish gate test.',
      'expeditions/test-stage-gate/trophy/test.png',
      repeat('e', 64),
      '{}'::jsonb
    );
    assert not (v_j->>'active')::boolean
           and exists (
             select 1
               from public.expedition_chapter_versions
              where id = (v_j->>'version_id')::uuid
                and approved_at is not null
                and published_at is not null
                and not active
           )
           and exists (
             select 1
               from public.expedition_trophies
              where chapter_id = (v_j->>'chapter_id')::uuid
           ),
           'staging harus menulis version inactive + Trophy secara atomik';
    begin
      perform public.stage_expedition_chapter_version(
        'test-stage-gate', 9996, 2, 1,
        '{"android":0,"ios":0,"desktop":0}'::jsonb,
        jsonb_build_object(
          'schema_version', 1,
          'content_version', 2,
          'sequence', 9996,
          'factory', jsonb_build_object(
            'slug', 'test-stage-gate',
            'mode', 'procedural'
          ),
          'assets', jsonb_build_object(
            'prefix', 'expeditions/test-stage-gate/v2/'
          ),
          'manifest_hash', repeat('f', 64),
          'summary', jsonb_build_object('title', 'Placeholder'),
          'zones', jsonb_build_array('{}'::jsonb, '{}'::jsonb, '{}'::jsonb),
          'opponents', jsonb_build_array(
            '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
          ),
          'boss', '{}'::jsonb
        ),
        repeat('f', 64),
        'expeditions/test-stage-gate/v2/',
        now(),
        'test-stage-gate-trophy',
        'Stage Gate Trophy',
        'Only used by the transactional publish gate test.',
        'expeditions/test-stage-gate/trophy/test.png',
        repeat('e', 64),
        '{}'::jsonb
      );
      ok := false;
    exception when others then ok := (sqlerrm = 'INVALID_CHAPTER_MANIFEST');
    end;
    assert ok, 'staging wajib menolak placeholder chapter';
    raise exception using errcode = 'ZX005', message = 'rollback stage gate fixture';
  exception when sqlstate 'ZX005' then
    null;
  end;

  ----------------------------------------------------------------------------
  -- Expedition memakai subtransaksi yang sengaja di-rollback supaya chapter
  -- published immutable tidak meninggalkan fixture di production.
  begin
    insert into public.expedition_chapters (slug, sequence, status)
    values ('test-sugarworks-prerequisite', 9998, 'retired')
    returning id into v_id;
    insert into public.expedition_progress (
      owner_id, chapter_id, first_cleared_at, clear_count
    ) values (u1, v_id, now(), 1);
    insert into public.expedition_chapters (slug, sequence, status)
    values ('test-sugarworks', 9999, 'published')
    returning id into v_expedition_chapter;
    insert into public.expedition_chapter_versions (
      chapter_id, content_version, manifest, manifest_hash, asset_prefix,
      approved_at, published_at, active
    ) values (
      v_expedition_chapter,
      1,
      jsonb_build_object(
        'schema_version', 1,
        'summary', jsonb_build_object('title', 'Test Sugarworks'),
        'zones', jsonb_build_array(
          jsonb_build_object('bits_reward', 10),
          jsonb_build_object('bits_reward', 20),
          jsonb_build_object('bits_reward', 30)
        ),
        'opponents', '[]'::jsonb,
        'boss', '{}'::jsonb
      ),
      repeat('a', 64),
      'expeditions/test-sugarworks/v1/',
      now(),
      clock_timestamp(),
      true
    ) returning id into v_expedition_version;
    v_j := public.expedition_announcements_payload(u1);
    assert jsonb_array_length(v_j->'unread') = 1
           and jsonb_array_length(v_j->'home_popup') = 1,
           format('chapter baru harus membuat badge dan satu popup Home; actual=%s', v_j);
    v_j := public.ack_expedition_home_popup(
      u1, array[v_expedition_chapter]
    );
    assert jsonb_array_length(v_j->'unread') = 1
           and jsonb_array_length(v_j->'home_popup') = 0,
           'ack popup tidak boleh menghapus badge sebelum chapter dibuka';
    perform public.ack_expedition_home_popup(
      u1, array[v_expedition_chapter]
    );
    assert (
      select home_popup_seen_at is not null and chapter_opened_at is null
      from public.seeker_chapter_receipts
      where owner_id = u1 and chapter_id = v_expedition_chapter
    ), 'ack popup harus idempoten dan tidak menandai chapter terbuka';
    v_j := public.mark_expedition_chapter_opened(
      u1, v_expedition_version
    );
    assert jsonb_array_length(v_j->'unread') = 0
           and jsonb_array_length(v_j->'home_popup') = 0
           and exists (
             select 1 from public.seeker_chapter_receipts
              where owner_id = u1
                and chapter_id = v_expedition_chapter
                and home_popup_seen_at is not null
                and chapter_opened_at is not null
           ),
           'membuka detail chapter harus menghapus badge lintas device';
    insert into public.expedition_trophies (
      chapter_id, slug, display_name, description, art_path, art_hash
    ) values (
      v_expedition_chapter,
      'test-sugarworks-trophy',
      'Sugarworks Trophy',
      'Proof that the test expedition was cleared.',
      'expeditions/test-sugarworks/trophy/test.png',
      repeat('b', 64)
    ) returning id into v_expedition_trophy;

    v_j := public.save_anima_team(u1, 'expedition', v_team_ids);
    v_team_id := (v_j->>'id')::uuid;
    select jsonb_agg(
      member || jsonb_build_object(
        'slot', ordinality - 1,
        'hp', 50,
        'current_hp', 50,
        'max_hp', 50,
        'momentum', 3,
        'momentum_max', 3,
        'guarding', false,
        'participated', ordinality = 1
      )
      order by ordinality
    ) into v_expedition_party
    from jsonb_array_elements(v_team_snapshot)
         with ordinality roster(member, ordinality);
    update public.animas
       set care = jsonb_set(care, '{energy}', '100'::jsonb),
           care_synced_at = now(),
           sleep_started_at = null,
           sleep_energy_at_start = null
     where id = any(v_team_ids);

    update public.animas
       set care = jsonb_set(care, '{energy}', '29'::jsonb)
     where id = v_team_ids[4];
    begin
      perform public.start_expedition_run(
        u1, v_expedition_version, v_team_id, 'test-low-energy-seed',
        v_expedition_party, 'test-expedition-low-energy'
      );
      ok := false;
    exception when others then ok := sqlerrm = 'TEAM_MEMBER_LOW_ENERGY';
    end;
    assert ok
           and (select count(*) from public.expedition_runs
                 where owner_id = u1 and status in ('checkpoint', 'active')) = 0
           and (select count(*) from public.animas
                 where id = any(v_team_ids[1:3])
                   and (care->>'energy')::numeric = 100) = 3,
           'biaya masuk Expedition harus gagal atomik jika satu anggota di bawah 30 Energy';
    update public.animas
       set care = jsonb_set(care, '{energy}', '100'::jsonb),
           care_synced_at = now(),
           sleep_started_at = null,
           sleep_energy_at_start = null
     where id = any(v_team_ids);

    v_j := public.start_expedition_run(
      u1, v_expedition_version, v_team_id, 'test-run-seed',
      v_expedition_party, 'test-expedition-start'
    );
    v_expedition_run := (v_j->>'id')::uuid;
    assert (select count(*) from public.animas
             where id = any(v_team_ids)
               and (care->>'energy')::numeric = 70) = 4,
           'Begin Expedition harus memotong 30 Energy dari semua anggota sekali';
    v_j2 := public.start_expedition_run(
      u1, v_expedition_version, v_team_id, 'ignored-replay-seed',
      v_expedition_party, 'test-expedition-start'
    );
    assert (v_j2->>'replayed')::boolean
           and (select count(*) from public.animas
                 where id = any(v_team_ids)
                   and (care->>'energy')::numeric = 70) = 4,
           'replay Begin Expedition tidak boleh memotong Energy kedua kali';
    begin
      perform public.save_anima_team(u1, 'expedition', v_team_ids);
      ok := false;
    exception when others then ok := sqlerrm = 'EXPEDITION_TEAM_LOCKED';
    end;
    assert ok, 'roster Expedition harus terkunci sejak checkpoint awal';
    v_expedition_map := '{
      "entry":["recovery-1"],
      "nodes":[{
        "id":"recovery-1","kind":"recovery","depth":1,"next":["next-1"],
        "options":[{"id":"heal","effect":{"type":"heal_party","ratio":0.25}}]
      }]
    }'::jsonb;
    update public.animas
       set care = jsonb_set(care, '{energy}', '0'::jsonb),
           care_synced_at = now()
     where id = any(v_team_ids);
    v_j := public.start_expedition_zone(
      u1, v_expedition_run, 1, v_team_id, 'test-zone-seed',
      v_expedition_party, v_expedition_map, 'test-zone-start'
    );
    assert (v_j->>'status') = 'active'
           and (v_j->>'version')::integer = 2
           and (select count(*) from public.animas
                 where id = any(v_team_ids)
                   and (care->>'energy')::numeric = 0) = 4,
           'Start Zone harus mengabaikan Energy setelah biaya masuk dibayar';
    begin
      perform public.save_anima_team(u1, 'expedition', v_team_ids);
      ok := false;
    exception when others then ok := sqlerrm = 'EXPEDITION_TEAM_LOCKED';
    end;
    assert ok, 'roster Expedition tidak boleh diubah selama zona aktif';

    v_j := public.enter_expedition_node(
      u1, v_expedition_run, 2,
      v_expedition_map->'nodes'->0, 'test-enter-recovery'
    );
    v_j := public.commit_expedition_choice(
      u1, v_expedition_run, 3, 'recovery-1', 'heal',
      v_expedition_party, 2, '[]'::jsonb, '["next-1"]'::jsonb, false,
      'test-choose-recovery'
    );
    assert (v_j->>'supplies')::integer = 2
           and (v_j->>'nodes_completed')::integer = 1
           and v_j->'visited_node_ids' ? 'recovery-1',
           'node non-combat harus commit Supplies, progress, dan riwayat rute satu kali';
    v_j2 := public.commit_expedition_choice(
      u1, v_expedition_run, 3, 'recovery-1', 'heal',
      v_expedition_party, 2, '[]'::jsonb, '["next-1"]'::jsonb, false,
      'test-choose-recovery'
    );
    assert (v_j2->>'replayed')::boolean,
           'retry choice Expedition harus replay tanpa mutation kedua';

    v_expedition_map := '{
      "entry":["shop-1"],
      "nodes":[{
        "id":"shop-1","kind":"shop","depth":3,"next":["battle-1"],
        "options":[{"id":"buy","effect":{"type":"supplies","value":1}}]
      }]
    }'::jsonb;
    update public.expedition_runs set
      zone_map = v_expedition_map,
      available_node_ids = '["shop-1"]'::jsonb,
      current_node_id = null,
      pending_node = null
    where id = v_expedition_run;
    v_bits_before_battle := (select bits from public.profiles where id = u1);
    v_j := public.enter_expedition_node(
      u1, v_expedition_run, 4,
      v_expedition_map->'nodes'->0, 'test-enter-shop'
    );
    v_j := public.refresh_expedition_shop(
      u1, v_expedition_run, 5,
      v_expedition_map->'nodes'->0, 'test-refresh-shop'
    );
    assert (select bits from public.profiles where id = u1)
             = v_bits_before_battle - 3
           and (v_j->>'shop_refreshed')::boolean,
           'refresh Shop Expedition harus mendebit Bits sekali';
    v_j2 := public.refresh_expedition_shop(
      u1, v_expedition_run, 5,
      v_expedition_map->'nodes'->0, 'test-refresh-shop'
    );
    assert (v_j2->>'replayed')::boolean
           and (select bits from public.profiles where id = u1)
                 = v_bits_before_battle - 3,
           'retry refresh Shop tidak boleh mendebit Bits kedua kali';
    begin
      perform public.commit_expedition_choice(
        u1, v_expedition_run, 6, 'shop-1', 'shop-skip',
        v_expedition_party, 3, '[]'::jsonb, '["battle-1"]'::jsonb, false,
        'test-skip-shop-tamper'
      );
      ok := false;
    exception when others then ok := sqlerrm = 'INVALID_EXPEDITION_STATE';
    end;
    assert ok, 'skip Shop tidak boleh dipakai untuk mengubah Tokens';
    v_j := public.commit_expedition_choice(
      u1, v_expedition_run, 6, 'shop-1', 'shop-skip',
      v_expedition_party, 2, '[]'::jsonb, '["battle-1"]'::jsonb, false,
      'test-skip-shop'
    );
    assert (v_j->>'supplies')::integer = 2
           and (v_j->>'nodes_completed')::integer = 2
           and v_j->'visited_node_ids' ? 'shop-1'
           and (select bits from public.profiles where id = u1)
                 = v_bits_before_battle - 3,
           'skip Shop harus maju tanpa item, Token, boost, atau refund refresh';

    v_expedition_map := '{
      "entry":["battle-1"],
      "nodes":[{
        "id":"battle-1","kind":"battle","depth":1,"next":["next-1"],
        "opponent_id":"test-battle","supplies_reward":2
      }]
    }'::jsonb;
    update public.expedition_runs set
      zone_map = v_expedition_map,
      available_node_ids = '["battle-1"]'::jsonb,
      current_node_id = null,
      pending_node = null
    where id = v_expedition_run;
    select jsonb_agg(
      member || jsonb_build_object(
        'slot', ordinality - 1,
        'hp', 50,
        'max_hp', 50,
        'momentum', 3,
        'momentum_max', 3,
        'guarding', false,
        'participated', ordinality = 1
      )
      order by ordinality
    ) into v_expedition_state
    from jsonb_array_elements(v_opponent_snapshot)
         with ordinality roster(member, ordinality);
    v_expedition_state := jsonb_build_object(
      'status', 'active',
      'turn', 1,
      'seed', 'test-reset-seed',
      'player', jsonb_build_object(
        'active_slot', 0, 'forced_switch', false, 'item_used', false,
        'roster', v_expedition_party
      ),
      'opponent', jsonb_build_object(
        'active_slot', 0, 'forced_switch', false, 'item_used', false,
        'roster', v_expedition_state
      )
    );
    update public.team_battle_sessions set
      status = 'active',
      finished_at = null,
      expires_at = now() + interval '30 minutes'
    where id = v_team_session;
    begin
      perform public.start_expedition_encounter(
        u1, v_expedition_run, 7, v_expedition_map->'nodes'->0,
        v_team_snapshot, v_opponent_snapshot, v_expedition_state,
        'test-reset-seed', 2, 'test-cross-mode-expedition'
      );
      ok := false;
    exception when others then ok := sqlerrm = 'COMBAT_ALREADY_ACTIVE';
    end;
    assert ok, 'Team Battle aktif harus memblokir encounter Expedition';
    update public.team_battle_sessions set
      status = 'won',
      finished_at = now()
    where id = v_team_session;
    begin
      v_j2 := (
        select jsonb_agg(
          jsonb_set(
            member,
            '{anima_id}',
            to_jsonb('sugarworks-gumdrop-' || ordinality::text)
          )
          order by ordinality
        )
        from jsonb_array_elements(v_opponent_snapshot)
             with ordinality roster(member, ordinality)
      );
      v_j := public.start_expedition_encounter(
        u1, v_expedition_run, 7, v_expedition_map->'nodes'->0,
        v_team_snapshot, v_j2,
        jsonb_set(v_expedition_state, '{opponent,roster}', (
          select jsonb_agg(
            jsonb_set(
              member,
              '{anima_id}',
              to_jsonb('sugarworks-gumdrop-' || ordinality::text)
            )
            order by ordinality
          )
          from jsonb_array_elements(v_expedition_state #> '{opponent,roster}')
               with ordinality roster(member, ordinality)
        )),
        'test-chapter-seed', 2, 'test-chapter-opponent-slug'
      );
      assert v_j->'encounter'->>'id' is not null,
             'encounter Expedition harus menerima anima_id chapter berupa slug';
      raise exception using errcode = 'ZX003',
        message = 'rollback chapter opponent fixture';
    exception when sqlstate 'ZX003' then
      null;
    end;
    v_j := public.start_expedition_encounter(
      u1, v_expedition_run, 7, v_expedition_map->'nodes'->0,
      v_team_snapshot, v_opponent_snapshot, v_expedition_state,
      'test-reset-seed', 2, 'test-enter-reset-battle'
    );
    v_expedition_encounter := (v_j->'encounter'->>'id')::uuid;
    assert exists (
             select 1
               from public.seeker_atlas_discoveries
              where owner_id = u1 and discovery_source = 'expedition'
           ),
           'anggota aktif saat encounter Expedition mulai harus masuk Atlas';
    v_j := public.forfeit_expedition_encounter(
      u1, v_expedition_encounter,
      '{"entry":["retry-1"],"nodes":[{"id":"retry-1","kind":"battle","next":[]}]}'::jsonb,
      'test-retry-seed'
    );
    assert (v_j->'run'->>'status') = 'active'
           and (v_j->'run'->>'supplies')::integer = 0
           and (v_j->'run'->>'zone_attempt')::integer = 2
           and jsonb_array_length(v_j->'run'->'visited_node_ids') = 0
           and (select bits from public.profiles where id = u1)
                 = v_bits_before_battle
           and exists (
             select 1 from public.quota_ledger
              where owner_id = u1 and reason = 'expedition_refund'
           ),
           'forfeit harus memulihkan checkpoint dan refund refresh Shop sekali';
    v := (v_j->'run'->>'version')::integer;

    v_expedition_map := '{
      "entry":["zone-1-exit"],
      "nodes":[{
        "id":"zone-1-exit","kind":"recovery","depth":4,"next":[],
        "options":[{"id":"continue","effect":{"type":"supplies","value":0}}]
      }]
    }'::jsonb;
    update public.expedition_runs set
      nodes_completed = 3,
      zone_map = v_expedition_map,
      available_node_ids = v_expedition_map->'entry',
      current_node_id = null,
      pending_node = null
    where id = v_expedition_run;
    v_j := public.enter_expedition_node(
      u1, v_expedition_run, v,
      v_expedition_map->'nodes'->0, 'test-enter-zone-1-exit'
    );
    v := (v_j->>'version')::integer;
    select jsonb_agg(
      member || jsonb_build_object(
        'hp', case ordinality when 1 then 0 when 2 then 10 when 3 then 30 else 50 end,
        'current_hp', case ordinality when 1 then 0 when 2 then 10 when 3 then 30 else 50 end,
        'max_hp', 50
      )
      order by ordinality
    ) into v_expedition_party
      from jsonb_array_elements(v_expedition_party)
      with ordinality as roster(member, ordinality);
    v_j := public.commit_expedition_choice(
      u1, v_expedition_run, v, 'zone-1-exit', 'continue',
      v_expedition_party, 0, '[]'::jsonb, '[]'::jsonb, true,
      'test-clear-zone-1'
    );
    assert (v_j->>'status') = 'checkpoint'
           and (v_j->>'zone')::integer = 2
           and (v_j->>'checkpoint_choice_pending')::boolean
           and (v_j->'last_zone_reward'->>'bits')::integer = 10
           and (v_j->'daily_bits'->>'bits_earned')::integer = 10
           and (v_j->'daily_bits'->>'bits_limit')::integer = 60,
           'checkpoint RPC Zone 1 harus memberi 10 Bits dari manifest';
    v_j2 := public.commit_expedition_choice(
      u1, v_expedition_run, v, 'zone-1-exit', 'continue',
      v_expedition_party, 0, '[]'::jsonb, '[]'::jsonb, true,
      'test-clear-zone-1'
    );
    assert (v_j2->>'replayed')::boolean
           and (select count(*) from public.expedition_zone_rewards
                 where run_id = v_expedition_run and zone = 1) = 1,
           'replay checkpoint Zone 1 tidak boleh mint kedua kali';
    v := (v_j->>'version')::integer;
    begin
      perform public.start_expedition_zone(
        u1, v_expedition_run, v, v_team_id, 'test-choice-required',
        v_expedition_party, v_expedition_map, 'test-choice-required'
      );
      ok := false;
    exception when others then
      ok := sqlerrm = 'EXPEDITION_CHECKPOINT_CHOICE_REQUIRED';
    end;
    assert ok, 'zona berikutnya tidak boleh dimulai sebelum checkpoint choice';

    v_j := public.commit_expedition_checkpoint_choice(
      u1, v_expedition_run, v, 'recover', 'test-checkpoint-recover'
    );
    assert not (v_j->>'checkpoint_choice_pending')::boolean
           and v_j->>'checkpoint_choice' = 'recover'
           and (v_j->'party_state'->0->>'hp')::integer = 25
           and (v_j->'party_state'->1->>'hp')::integer = 35
           and (v_j->'party_state'->2->>'hp')::integer = 50
           and (v_j->'party_state'->3->>'hp')::integer = 50,
           'Recover harus heal 50 persen dan membangunkan KO pada 50 persen';
    v_j2 := public.commit_expedition_checkpoint_choice(
      u1, v_expedition_run, v, 'recover', 'test-checkpoint-recover'
    );
    assert (v_j2->>'replayed')::boolean
           and v_j2->'party_state' = v_j->'party_state',
           'replay Recover tidak boleh heal checkpoint dua kali';
    v := (v_j->>'version')::integer;
    v_expedition_party := v_j->'party_state';

    v_expedition_map := '{
      "entry":["zone-2-exit"],
      "nodes":[{
        "id":"zone-2-exit","kind":"recovery","depth":4,"next":[],
        "options":[{"id":"continue","effect":{"type":"supplies","value":0}}]
      }]
    }'::jsonb;
    v_j := public.start_expedition_zone(
      u1, v_expedition_run, v, v_team_id, 'test-zone-2-seed',
      v_expedition_party, v_expedition_map, 'test-zone-2-start'
    );
    v := (v_j->>'version')::integer;
    update public.expedition_runs set nodes_completed = 3
    where id = v_expedition_run;
    v_j := public.enter_expedition_node(
      u1, v_expedition_run, v,
      v_expedition_map->'nodes'->0, 'test-enter-zone-2-exit'
    );
    v := (v_j->>'version')::integer;
    v_j := public.commit_expedition_choice(
      u1, v_expedition_run, v, 'zone-2-exit', 'continue',
      v_expedition_party, 0, '[]'::jsonb, '[]'::jsonb, true,
      'test-clear-zone-2'
    );
    assert (v_j->>'status') = 'checkpoint'
           and (v_j->>'zone')::integer = 3
           and (v_j->>'checkpoint_choice_pending')::boolean
           and (v_j->'last_zone_reward'->>'bits')::integer = 20
           and (v_j->'daily_bits'->>'bits_earned')::integer = 30,
           'checkpoint RPC Zone 2 harus memberi 20 Bits dari manifest';
    v := (v_j->>'version')::integer;
    v_j := public.commit_expedition_checkpoint_choice(
      u1, v_expedition_run, v, 'power_up', 'test-checkpoint-power'
    );
    assert not (v_j->>'checkpoint_choice_pending')::boolean
           and v_j->>'checkpoint_choice' = 'power_up',
           'Power Up harus disimpan sampai Start Zone berikutnya';

    -- Represent 20 Bits earned by another completed run in this stable chapter.
    -- The live Boss clear below must clip its scheduled 30 Bits to the 10 left.
    insert into public.expedition_runs (
      owner_id, chapter_version_id, team_id, status, zone, seed,
      nodes_completed, party_state, completed_at
    ) values (
      u1, v_expedition_version, v_team_id, 'complete', 3,
      'partial-cap-prior-run', 4, v_expedition_party, now()
    ) returning id into v_id;
    insert into public.expedition_zone_rewards (
      run_id, owner_id, chapter_id, chapter_version_id,
      zone, scheduled_bits, bits
    ) values (
      v_id, u1, v_expedition_chapter, v_expedition_version,
      2, 20, 20
    ) returning id into v_refund;
    update public.profiles set bits = bits + 20 where id = u1;
    insert into public.quota_ledger (
      owner_id, currency, delta, reason, ref_id
    ) values (u1, 'bits', 20, 'expedition_zone', v_refund);
    assert (
      public.expedition_daily_bits_status(
        u1, v_expedition_version
      )->>'bits_earned'
    )::integer = 50,
    'cap Expedition harus menjumlahkan reward lintas run dalam stable chapter';

    v := (v_j->>'version')::integer;
    v_j := public.start_expedition_zone(
      u1, v_expedition_run, v, v_team_id, 'test-zone-3-seed',
      v_expedition_party, v_expedition_map, 'test-zone-3-start'
    );
    assert v_j->>'checkpoint_choice' is null
           and not (v_j->>'checkpoint_choice_pending')::boolean,
           'Start Zone harus mengonsumsi checkpoint choice sekali';
    v := (v_j->>'version')::integer;

    v_expedition_map := '{
      "entry":["boss-1"],
      "nodes":[{
        "id":"boss-1","kind":"boss","depth":5,"next":[],
        "opponent_id":"test-boss","supplies_reward":8
      }]
    }'::jsonb;
    update public.expedition_runs set
      zone = 3,
      nodes_completed = 4,
      zone_map = v_expedition_map,
      available_node_ids = '["boss-1"]'::jsonb,
      current_node_id = null,
      pending_node = null
    where id = v_expedition_run;
    select jsonb_agg(
      member || jsonb_build_object(
        'slot', ordinality - 1,
        'hp', 50,
        'max_hp', 50,
        'momentum', 3,
        'momentum_max', 3,
        'guarding', false,
        'participated', ordinality = 1
      )
      order by ordinality
    ) into v_expedition_state
    from jsonb_array_elements(v_opponent_snapshot)
         with ordinality roster(member, ordinality);
    v_expedition_state := jsonb_build_object(
      'status', 'active',
      'turn', 1,
      'seed', 'test-boss-seed',
      'player', jsonb_build_object(
        'active_slot', 0, 'forced_switch', false, 'item_used', false,
        'roster', v_expedition_party
      ),
      'opponent', jsonb_build_object(
        'active_slot', 0, 'forced_switch', false, 'item_used', false,
        'roster', v_expedition_state
      )
    );
    update public.app_config set value = '30'::jsonb
     where key = 'expedition_daily_exp_budget';
    insert into public.expedition_encounters (
      run_id, owner_id, node_id, kind, player_snapshot, opponent_snapshot,
      state, status, rng_seed, finished_at, rewarded_at
    ) values (
      v_expedition_run, u1, 'reward-cap-fixture', 'battle',
      v_team_snapshot, v_opponent_snapshot, v_expedition_state,
      'won', 'reward-cap-fixture', now(), now()
    ) returning id into v_id;
    insert into public.expedition_encounter_rewards (
      encounter_id, owner_id, progression, supplies, anima_exp_total
    ) values (v_id, u1, true, 2, 29);
    assert (public.expedition_daily_reward_status(u1, v_id)->>'exp_remaining')::integer = 1,
           'sisa budget positif harus mempertahankan eligibility encounter penuh berikutnya';
    update public.expedition_encounter_rewards
       set anima_exp_total = 30
     where encounter_id = v_id;
    assert (public.expedition_daily_reward_status(u1, v_id)->>'exp_remaining')::integer = 0,
           'budget 30 EXP harus habis berdasarkan total receipt roster';
    begin
      perform public.start_expedition_encounter(
        u1, v_expedition_run, v, v_expedition_map->'nodes'->0,
        v_team_snapshot, v_opponent_snapshot,
        jsonb_set(v_expedition_state, '{player,roster,0,momentum}', '2'::jsonb),
        'test-boss-seed', 8, 'test-invalid-pp'
      );
      ok := false;
    exception when others then ok := sqlerrm = 'INVALID_EXPEDITION_PP';
    end;
    assert ok, 'setiap encounter Expedition harus mulai dengan PP penuh';
    v_j := public.start_expedition_encounter(
      u1, v_expedition_run, v, v_expedition_map->'nodes'->0,
      v_team_snapshot, v_opponent_snapshot, v_expedition_state,
      'test-boss-seed', 8, 'test-enter-boss'
    );
    v_expedition_encounter := (v_j->'encounter'->>'id')::uuid;
    begin
      v_j2 := public.abandon_expedition_run(
        u1, v_expedition_run, 'test-abandon-active'
      );
      assert v_j2->>'status' = 'abandoned'
             and (select status from public.expedition_encounters
                   where id = v_expedition_encounter) = 'forfeited',
             'abandon harus menutup encounter aktif dalam transaksi yang sama';
      raise exception using errcode = 'ZX002', message = 'rollback abandon fixture';
    exception when sqlstate 'ZX002' then
      null;
    end;
    v_expedition_state := jsonb_set(v_expedition_state, '{status}', '"won"'::jsonb);
    v_expedition_state := jsonb_set(v_expedition_state, '{turn}', '2'::jsonb);
    v_expedition_state := jsonb_set(
      v_expedition_state,
      '{opponent,roster}',
      (
        select jsonb_agg(jsonb_set(member, '{hp}', '0'::jsonb) order by ordinality)
        from jsonb_array_elements(v_expedition_state #> '{opponent,roster}')
             with ordinality roster(member, ordinality)
      )
    );
    v_bits_before_battle := (select bits from public.profiles where id = u1);
    v_score_before_battle := (
      select sum(care_score)::integer from public.animas where id = any(v_team_ids)
    );
    v_j := public.commit_expedition_turn(
      u1, v_expedition_encounter, 1, 1, 'test-boss-turn', 'strike',
      null, null, v_expedition_state,
      '[{"type":"finished","result":"won"}]'::jsonb,
      '{"action":"strike"}'::jsonb,
      '[]'::jsonb, false, true, '{}'::jsonb, 'unused-retry'
    );
    assert v_j->'run'->>'status' = 'complete'
           and (v_j->'reward'->>'first_clear')::boolean
           and (v_j->'reward'->>'clear_bits')::integer = 25
           and (v_j->'reward'->>'progression')::boolean
           and (v_j->'reward'->>'supplies')::integer = 8
           and (v_j->'run'->'last_zone_reward'->>'scheduled_bits')::integer = 30
           and (v_j->'run'->'last_zone_reward'->>'bits')::integer = 10
           and (v_j->'run'->'last_zone_reward'->>'capped')::boolean
           and (v_j->'run'->'daily_bits'->>'bits_earned')::integer = 60
           and (v_j->'run'->'daily_bits'->>'bits_remaining')::integer = 0
           and v_j->'run'->'visited_node_ids' ? 'boss-1'
           and (select sum(care_score)::integer from public.animas
                 where id = any(v_team_ids)) = v_score_before_battle + 9
           and (select boss_exp_awarded_at is not null from public.expedition_runs
                 where id = v_expedition_run)
           and (select anima_exp_total from public.expedition_encounter_rewards
                 where encounter_id = v_expedition_encounter) = 9,
           'Boss harus membayar party sekali meski budget harian habis';
    select public.expedition_encounter_payload(encounter)
      into v_j2
      from public.expedition_encounters encounter
     where encounter.id = v_expedition_encounter;
    assert v_j2->'last_reward'->'anima_exp' = v_j->'reward'->'anima_exp',
           'payload encounter terminal harus memulihkan receipt per-Anima EXP';
    assert exists (
             select 1 from public.seeker_trophies
              where owner_id = u1 and trophy_id = v_expedition_trophy
           )
           and (select bits from public.profiles where id = u1)
                 = v_bits_before_battle + 35,
           'Zone 3 harus terpotong ke sisa cap dan first clear tetap di luar cap';
    v_j2 := public.commit_expedition_turn(
      u1, v_expedition_encounter, 1, 1, 'test-boss-turn', 'strike',
      null, null, v_expedition_state,
      '[{"type":"finished","result":"won"}]'::jsonb,
      '{"action":"strike"}'::jsonb,
      '[]'::jsonb, false, true, '{}'::jsonb, 'unused-retry'
    );
    assert (v_j2->>'replayed')::boolean
           and (select sum(care_score)::integer from public.animas
                 where id = any(v_team_ids)) = v_score_before_battle + 9
           and (select count(*) from public.seeker_trophies
                 where owner_id = u1 and trophy_id = v_expedition_trophy) = 1
           and (select count(*) from public.quota_ledger
                 where reason = 'expedition_clear' and ref_id = v_expedition_run) = 1
           and (select count(*) from public.quota_ledger
                 where reason = 'expedition_zone'
                   and owner_id = u1) = 4
           and (select count(*) from public.quota_ledger
                 where reason = 'expedition_zone'
                   and ref_id in (
                     select id from public.expedition_zone_rewards
                      where run_id = v_expedition_run
                   )) = 3,
           'replay Boss tidak boleh menggandakan Trophy, first-clear, atau Zone Bits';

    v_bits_before_battle := (select bits from public.profiles where id = u1);
    insert into public.expedition_runs (
      owner_id, chapter_version_id, team_id, status, zone, seed,
      zone_map, available_node_ids, current_node_id, nodes_completed,
      party_state, pending_node
    ) values (
      u1, v_expedition_version, v_team_id, 'active', 3, 'cap-repeat-seed',
      '{"entry":["boss-repeat"],"nodes":[{"id":"boss-repeat","kind":"boss","next":[]}]}'::jsonb,
      '[]'::jsonb, 'boss-repeat', 4, v_expedition_party,
      '{"id":"boss-repeat","kind":"boss","next":[]}'::jsonb
    ) returning id into v_id;
    update public.expedition_runs set
      status = 'complete',
      current_node_id = null,
      pending_node = null,
      completed_at = now()
    where id = v_id;
    assert (select bits from public.expedition_zone_rewards
             where run_id = v_id and zone = 3) = 0
           and (select bits from public.profiles where id = u1)
                 = v_bits_before_battle
           and (public.expedition_daily_bits_status(
             u1, v_expedition_version
           )->>'bits_earned')::integer = 60,
           'run kedua pada hari yang sama harus mentok cap 60 Bits per chapter';

    insert into public.expedition_chapter_versions (
      chapter_id, content_version, manifest, manifest_hash, asset_prefix,
      approved_at, published_at, active
    ) values (
      v_expedition_chapter,
      2,
      jsonb_build_object(
        'schema_version', 1,
        'summary', jsonb_build_object('title', 'Test Sugarworks v2'),
        'zones', '[]'::jsonb,
        'opponents', '[]'::jsonb,
        'boss', '{}'::jsonb
      ),
      repeat('c', 64),
      'expeditions/test-sugarworks/v2/',
      now(),
      now(),
      false
    ) returning id into v_expedition_version_next;
    assert (
      public.expedition_daily_bits_status(
        u1, v_expedition_version_next
      )->>'bits_limit'
    )::integer = 0,
    'manifest lama tanpa bits_reward tidak boleh mint repeatable Bits';
    v_j := public.activate_expedition_chapter_version(
      v_expedition_chapter, 2
    );
    assert (v_j->>'version_id')::uuid = v_expedition_version_next
           and (v_j->>'active')::boolean
           and (select active from public.expedition_chapter_versions
                 where id = v_expedition_version_next)
           and not (select active from public.expedition_chapter_versions
                     where id = v_expedition_version)
           and (select status from public.expedition_chapters
                 where id = v_expedition_chapter) = 'published',
           'activation harus menukar satu versi aktif secara atomik';
    update public.app_config
       set value = 'true'::jsonb
     where key = 'feature_chapter_push';
    v_j := public.claim_expedition_chapter_push(v_expedition_version_next);
    assert (v_j->>'chapter_version_id')::uuid = v_expedition_version_next
           and v_j->>'slug' = 'test-sugarworks',
           'push claim hanya boleh mengambil chapter aktif';
    begin
      perform public.claim_expedition_chapter_push(v_expedition_version_next);
      ok := false;
    exception when others then ok := (sqlerrm = 'CHAPTER_PUSH_ALREADY_CLAIMED');
    end;
    assert ok, 'push claim pending harus mencegah kirim ganda';
    v_j := public.finish_expedition_chapter_push(
      v_expedition_version_next, 'sent', 'test-fcm-message', null
    );
    assert v_j->>'status' = 'sent'
           and v_j->>'message_id' = 'test-fcm-message'
           and (v_j->>'sent_at') is not null,
           'push completion harus menyimpan receipt satu kali';

    begin
      update public.expedition_chapter_versions
         set manifest = '{"changed":true}'::jsonb
       where id = v_expedition_version;
      ok := false;
    exception when others then ok := (sqlerrm = 'PUBLISHED_CHAPTER_IMMUTABLE');
    end;
    assert ok, 'chapter version published harus immutable';
    raise exception using errcode = 'ZX001', message = 'rollback fixture Expedition';
  exception when sqlstate 'ZX001' then
    null;
  end;

  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public._grant_weekly_core_if_eligible(u1);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil grant Core mingguan';
  begin
    perform public.claim_capture(
      u1, 'forbidden', 'forbidden', 'forbidden_species', 'gray', 1::smallint,
      'stone', null, 'object', 1, v_stats, v_care, v_visi,
      'v13', 'test-model', 0.07, u1::text || '/forbidden.png'
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil claim_capture';

  begin
    perform 1 from public.storage_cleanup_queue;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'storage_cleanup_queue tidak boleh terbaca client';

  perform set_config('role', 'authenticated', true);
  begin
    perform 1 from public.gallery_entries;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'gallery_entries tidak boleh terbaca langsung oleh client';
  begin
    insert into public.gallery_hidden (owner_id, entry_id)
    values (u1, '00000000-0000-4000-8000-000000000099');
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'gallery_hidden hanya boleh ditulis lewat Edge Function';
  begin
    perform 1 from public.atlas_forms;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'atlas_forms tidak boleh terbaca langsung oleh client';
  begin
    perform 1 from public.seeker_atlas_discoveries;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'discovery ledger Atlas tidak boleh terbaca langsung oleh client';
  assert not pg_catalog.has_function_privilege(
    'authenticated',
    'public._atlas_upsert_discovery(uuid,uuid,text,timestamptz,integer)',
    'EXECUTE'
  ), 'client tidak boleh memalsukan unlock Atlas';
  begin
    perform 1 from public.anima_teams;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'anima_teams tidak boleh dibaca langsung oleh client';
  begin
    perform public.save_anima_team(u1, 'team_battle', v_team_ids);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil save_anima_team';
  begin
    perform public.commit_team_battle_turn(
      u1, v_team_session, 1, 1, 'forbidden-team', 'strike',
      null, null, v_team_state, '[]'::jsonb, '{}'::jsonb
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh commit turn Team Battle langsung';
  begin
    perform 1 from public.expedition_runs;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'expedition_runs tidak boleh dibaca langsung oleh client';
  begin
    perform 1 from public.expedition_zone_rewards;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'receipt Zone Bits Expedition tidak boleh dibaca langsung oleh client';
  assert not pg_catalog.has_function_privilege(
    'authenticated',
    'public.award_expedition_zone_bits(public.expedition_runs,smallint)',
    'EXECUTE'
  ), 'client tidak boleh memanggil award_expedition_zone_bits';
  assert not pg_catalog.has_function_privilege(
    'authenticated',
    'public.commit_expedition_choice(uuid,uuid,integer,text,text,jsonb,integer,jsonb,jsonb,boolean,text)',
    'EXECUTE'
  ), 'client tidak boleh melewati Edge Function untuk choice atau skip Expedition';
  assert not pg_catalog.has_function_privilege(
    'authenticated',
    'public.commit_expedition_checkpoint_choice(uuid,uuid,integer,text,text)',
    'EXECUTE'
  ), 'client tidak boleh commit checkpoint choice langsung';
  begin
    perform public.expedition_daily_bits_status(
      u1, '00000000-0000-4000-8000-000000000099'
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh menghitung status Zone Bits langsung';
  begin
    perform public.expedition_chapter_catalog(u1);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil RPC Expedition service-only';
  begin
    perform public.activate_expedition_chapter_version(
      '00000000-0000-4000-8000-000000000099', 1
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh mengaktifkan chapter version langsung';
  begin
    perform public.stage_expedition_chapter_version(
      'forbidden-stage', 1, 1, 1, '{}'::jsonb, '{}'::jsonb,
      repeat('f', 64), 'expeditions/forbidden-stage/v1/', now(),
      'forbidden-trophy', 'Forbidden', 'Forbidden',
      'expeditions/forbidden-stage/trophy/test.png', repeat('f', 64), '{}'::jsonb
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh staging chapter version langsung';
  begin
    perform 1 from public.expedition_chapter_push_events;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'receipt push chapter tidak boleh dibaca client';
  begin
    perform public.claim_expedition_chapter_push(
      '00000000-0000-4000-8000-000000000099'
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh claim pengiriman push chapter';
  begin
    perform 1 from public.seeker_chapter_receipts;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'receipt announcement tidak boleh dibaca langsung oleh client';
  begin
    perform public.ack_expedition_home_popup(
      u1, array[v_expedition_chapter]
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh menulis receipt announcement langsung';
  perform set_config('role', 'none', true);

  ----------------------------------------------------------------------------
  -- Evolusi: berurutan, idempoten, gratis untuk pemain, rollback aman, privat.
  ----------------------------------------------------------------------------
  select value into v_evo_flag_prev
    from public.app_config where key = 'feature_evolution';
  update public.app_config set value = 'true'::jsonb where key = 'feature_evolution';
  insert into public.animas (
    owner_id, nickname, species_key, color_bucket, element, rarity,
    base_stats, care, care_score, status, stage, evolution_version,
    body_height_cm, sheet_path, manifest, strike_name, surge_name
  ) values (
    u1, 'evolution-main', 'evolution_species', 'blue', 'metal', 2,
    v_stats, v_care, 700, 'ready', 1, 1,
    100, u1::text || '/evolution-main/hatchling.png',
    '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb,
    'Tin Tap', 'Metal Bloom'
  ) returning id into v_evolution_anima;
  insert into public.animas (
    owner_id, nickname, species_key, color_bucket, element, rarity,
    base_stats, care, care_score, status, stage, evolution_version,
    body_height_cm, sheet_path, manifest
  ) values (
    u1, 'evolution-other', 'evolution_other', 'red', 'flame', 2,
    v_stats, v_care, 700, 'ready', 1, 1,
    100, u1::text || '/evolution-other/hatchling.png',
    '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
  ) returning id into v_evolution_other;
  select genesis_cores into v_evolution_cores from public.profiles where id = u1;

  v_j := public.begin_evolution(u1, v_evolution_anima, 'evolution-fail');
  v_evolution_gen := (v_j->>'generation_id')::uuid;
  assert (v_j->>'target_stage')::int = 2
         and (select status from public.animas where id = v_evolution_anima) = 'evolving',
         'Lv36 stage1 tetap wajib memulai dari ritual Adult';
  v_j2 := public.begin_evolution(u1, v_evolution_anima, 'evolution-fail');
  assert (v_j2->>'generation_id')::uuid = v_evolution_gen
         and (v_j2->>'replayed')::boolean,
         'begin_evolution replay harus mengembalikan generation yang sama';
  begin
    perform public.begin_evolution(u1, v_evolution_other, 'evolution-overlap');
    ok := false;
  exception when others then ok := sqlerrm = 'EVOLUTION_ALREADY_ACTIVE';
  end;
  assert ok, 'satu akun tidak boleh membayar dua evolusi bersamaan';
  assert (select genesis_cores from public.profiles where id = u1) = v_evolution_cores,
         'begin evolution tidak boleh mendebit Core';

  v_j := public.fail_evolution(v_evolution_gen, 'uji rollback');
  assert (v_j->>'status') = 'failed'
         and (select status from public.animas where id = v_evolution_anima) = 'ready'
         and (select stage from public.animas where id = v_evolution_anima) = 1,
         'evolusi gagal harus mengembalikan form lama tanpa progression loss';
  v_j2 := public.fail_evolution(v_evolution_gen, 'uji replay rollback');
  assert (v_j2->>'replayed')::boolean
         and (select genesis_cores from public.profiles where id = u1) = v_evolution_cores,
         'fail_evolution replay harus idempoten dan tidak merefund Core';
  update public.animas set status = 'evolving' where id = v_evolution_anima;
  v_j2 := public.resume_evolution(u1, v_evolution_anima);
  assert (v_j2->>'not_found')::boolean
         and (select status from public.animas where id = v_evolution_anima) = 'ready'
         and not exists (
           select 1 from public.generations
            where anima_id = v_evolution_anima
              and kind = 'evolve'
              and status in ('pending', 'running')
         ),
         'resume orphan harus pulih tanpa membuka spend baru';

  v_j := public.begin_evolution(u1, v_evolution_anima, 'evolution-success');
  v_evolution_gen := (v_j->>'generation_id')::uuid;
  v_evolution_success_gen := v_evolution_gen;
  v_j2 := public.resume_evolution(u1, v_evolution_anima);
  assert (v_j2->>'generation_id')::uuid = v_evolution_gen
         and (v_j2->>'replayed')::boolean,
         'resume lintas device harus menempel ke generation aktif tanpa membuat spend baru';
  v_j := public.reserve_evolution(
    u1, v_evolution_gen, null, 'v21', 'uji', 0.001
  );
  assert (v_j->>'planning_claimed')::boolean,
         'request pertama harus memegang lease Vision';
  v_j2 := public.reserve_evolution(
    u1, v_evolution_gen, null, 'v21', 'uji', 0.001
  );
  assert not (v_j2->>'planning_claimed')::boolean
         and (v_j2->>'planning')::boolean,
         'request bersamaan tidak boleh memanggil Vision kedua';
  v_j := public.reserve_evolution(
    u1,
    v_evolution_gen,
    '{
      "lineage_anchors":["round body","loop handle","blue glaze"],
      "stage_brief":"Adult bridge",
      "body_height_cm":125,
      "strike_name":"Glaze Fang",
      "surge_name":"Steam Crown",
      "strike_effect_id":"armor_pierce",
      "surge_effect_id":"barrier"
    }'::jsonb,
    'v21',
    'uji',
    0.001
  );
  v_j := public.attach_evolution_prediction(v_evolution_gen, 'evolution-image-attempt-1');
  assert (v_j->>'attached')::boolean
         and (v_j->>'image_attempts')::int = 1,
         'prediction image pertama harus tercatat sebagai attempt 1';
  v_j := public.replace_evolution_prediction(
    v_evolution_gen,
    'evolution-image-attempt-1',
    'evolution-image-attempt-2'
  );
  assert (v_j->>'attached')::boolean
         and (v_j->>'image_attempts')::int = 2
         and v_j->>'prediction_id' = 'evolution-image-attempt-2',
         'E005 boleh mengganti prediction tepat satu kali';
  v_j2 := public.replace_evolution_prediction(
    v_evolution_gen,
    'evolution-image-attempt-1',
    'evolution-image-stale'
  );
  assert not (v_j2->>'attached')::boolean
         and (v_j2->>'stale')::boolean
         and (select prediction_id from public.generations where id = v_evolution_gen)
             = 'evolution-image-attempt-2',
         'callback E005 duplikat tidak boleh menimpa retry yang sudah aktif';
  v_j2 := public.replace_evolution_prediction(
    v_evolution_gen,
    'evolution-image-attempt-2',
    'evolution-image-attempt-3'
  );
  assert not (v_j2->>'attached')::boolean
         and (v_j2->>'exhausted')::boolean
         and (select image_attempts from public.generations where id = v_evolution_gen) = 2,
         'retry image harus berhenti setelah dua attempt total';
  v_j := public.commit_evolution(
    v_evolution_gen,
    u1::text || '/evolution-main/adult.png',
    '{"stage":2,"prompt_version":"v21","poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
  );
  assert (v_j->>'stage')::int = 2
         and (select status from public.animas where id = v_evolution_anima) = 'ready'
         and (select nickname from public.animas where id = v_evolution_anima) = 'evolution-main'
         and (select strike_effect_id from public.animas where id = v_evolution_anima) = 'armor_pierce'
         and (select surge_effect_id from public.animas where id = v_evolution_anima) = 'barrier',
         'commit evolution harus mengaktifkan art, form, move, dan dua efek sekaligus tanpa menimpa nickname';
  assert exists (
           select 1 from public.anima_forms
            where anima_id = v_evolution_anima
              and stage = 1
              and sheet_path = u1::text || '/evolution-main/hatchling.png'
              and reference_path =
                u1::text || '/' || v_evolution_anima::text
                || '/evolution_refs/' || v_evolution_success_gen::text || '.png'
         ),
         'form lama dan reference Idle privat harus tersimpan untuk rollback';
  assert (select count(*) from public.atlas_forms
           where anima_id = v_evolution_anima and stage in (1, 2)) = 2
         and (select count(*) from public.seeker_atlas_discoveries discovery
               join public.atlas_forms form on form.id = discovery.form_id
              where discovery.owner_id = u1
                and discovery.discovery_source = 'scanned'
                and form.anima_id = v_evolution_anima) = 2,
         'Hatchling dan Adult harus menjadi dua entry Atlas milik owner';
  v_j2 := public.commit_evolution(
    v_evolution_gen,
    u1::text || '/evolution-main/adult.png',
    '{"stage":2,"prompt_version":"v21"}'::jsonb
  );
  assert (v_j2->>'replayed')::boolean
         and (select genesis_cores from public.profiles where id = u1) = v_evolution_cores,
         'commit evolution replay tidak boleh menggandakan stage atau menyentuh Core';

  v_j := public.begin_evolution(u1, v_evolution_anima, 'evolution-stage-three');
  assert (v_j->>'target_stage')::int = 3,
         'Lv36 baru boleh meminta Evolved sesudah Adult committed';
  v_evolution_gen := (v_j->>'generation_id')::uuid;
  perform public.reserve_evolution(
    u1,
    v_evolution_gen,
    '{
      "lineage_anchors":["round body","loop handle","blue glaze"],
      "stage_brief":"Evolved culmination",
      "body_height_cm":160,
      "strike_name":"Toxic Crown",
      "surge_name":"Steam Bastion",
      "strike_effect_id":"poison",
      "surge_effect_id":"barrier"
    }'::jsonb,
    'v21',
    'uji',
    0.001
  );
  begin
    perform public.commit_evolution(
      v_evolution_gen,
      u1::text || '/evolution-main/evolved-invalid.png',
      '{"stage":3,"prompt_version":"v21"}'::jsonb
    );
    ok := false;
  exception when others then ok := sqlerrm = 'EVOLUTION_PLAN_EFFECT_NOT_UPGRADE';
  end;
  assert ok, 'Evolved hanya boleh mempertahankan atau meng-upgrade family efek Adult';
  perform public.fail_evolution(v_evolution_gen, 'uji sequential rollback');

  v_j := public.begin_evolution(u1, v_evolution_anima, 'evolution-stale-old');
  v_evolution_gen := (v_j->>'generation_id')::uuid;
  update public.generations
     set vision_started_at = now() - interval '4 minutes'
   where id = v_evolution_gen;
  v_j2 := public.begin_evolution(u1, v_evolution_other, 'evolution-stale-new');
  assert (v_j2->>'target_stage')::int = 2
         and (select status from public.generations where id = v_evolution_gen) = 'failed'
         and (select status from public.animas where id = v_evolution_anima) = 'ready',
         'intent lokal yang hilang harus self-heal sebelum memblokir evolusi berikutnya';
  perform public.fail_evolution(
    (v_j2->>'generation_id')::uuid, 'uji stale recovery cleanup'
  );

  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.begin_evolution(u1, v_evolution_anima, 'evolution-client-forbidden');
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  begin
    perform public.resume_evolution(u1, v_evolution_anima);
    ok := false;
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_evolution_lock(u1, v_evolution_gen);
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  begin
    perform public.replace_evolution_prediction(
      v_evolution_gen,
      'forbidden-old',
      'forbidden-new'
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  perform set_config('role', 'none', true);
  assert ok, 'client tidak boleh memanggil RPC evolusi termasuk retry image service-role langsung';

  insert into public.anima_evolution_locks (
    anima_id, target_stage, sheet_path, manifest, evolution_plan, prompt_version
  ) values (
    v_evolution_other, 2,
    u1::text || '/evolution-other/adult-lock.png',
    '{"stage":2,"prompt_version":"v21","poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb,
    '{
      "lineage_anchors":["square body","front screen","side buttons"],
      "stage_brief":"Locked Adult",
      "body_height_cm":125,
      "strike_name":"Lock Tap",
      "surge_name":"Lock Bloom",
      "strike_effect_id":"armor_pierce",
      "surge_effect_id":"barrier"
    }'::jsonb,
    'v21'
  );
  v_j := public.begin_evolution(u1, v_evolution_other, 'evolution-lock');
  v_evolution_gen := (v_j->>'generation_id')::uuid;
  v_j := public.apply_evolution_lock(u1, v_evolution_gen);
  assert (v_j->>'locked')::boolean
         and (v_j->>'stage')::int = 2
         and (select status from public.animas where id = v_evolution_other) = 'ready'
         and (select stage from public.animas where id = v_evolution_other) = 2
         and (select model from public.generations where id = v_evolution_gen) = 'locked'
         and (select cost_usd_estimate from public.generations where id = v_evolution_gen) = 0
         and (select genesis_cores from public.profiles where id = u1) = v_evolution_cores,
         'evolution lock harus commit Adult tanpa Core dan tanpa generation berbayar';
  assert (
           select nickname_snapshot
             from public.anima_forms
            where anima_id = v_evolution_other and stage = 1
         ) = 'evolution-other',
         'form legacy tanpa generation create harus menyimpan nama sebelum Evolve';
  v_j2 := public.apply_evolution_lock(u1, v_evolution_gen);
  assert (v_j2->>'replayed')::boolean,
         'apply_evolution_lock replay harus idempoten';

  delete from public.animas where id = v_evolution_anima;
  assert exists (
           select 1 from public.storage_cleanup_queue
            where bucket_id = 'anima_sheets'
              and object_path = u1::text || '/evolution-main/hatchling.png'
              and reason = 'anima_form_deleted'
         )
         and exists (
           select 1 from public.storage_cleanup_queue
            where bucket_id = 'anima_sheets'
              and object_path =
                u1::text || '/' || v_evolution_anima::text
                || '/evolution_refs/' || v_evolution_success_gen::text || '.png'
              and reason = 'anima_form_reference_deleted'
         ),
         'delete Anima harus mengantrekan cleanup seluruh history evolusi';
  delete from public.animas where id = v_evolution_other;
  update public.app_config
     set value = coalesce(v_evo_flag_prev, 'true'::jsonb)
   where key = 'feature_evolution';

  ----------------------------------------------------------------------------
  -- Guided Synthesis: roll gagal gratis, claim sukses atomik, refund dua mata
  -- uang, mode lock, Source lock, history, dan RPC tetap service-role-only.
  select jsonb_object_agg(key, value) into v_synthesis_config
    from public.app_config
   where key in (
     'feature_synthesis',
     'synthesis_resonance_base',
     'synthesis_resonance_level_max',
     'synthesis_resonance_care_max',
     'synthesis_resonance_affinity_max',
     'synthesis_resonance_dominant_bonus',
     'synthesis_calibration_max'
   );
  update public.app_config
     set value = case key
       when 'feature_synthesis' then 'true'::jsonb
       when 'synthesis_resonance_base' then '-1000'::jsonb
       else '0'::jsonb
     end
   where key in (
     'feature_synthesis',
     'synthesis_resonance_base',
     'synthesis_resonance_level_max',
     'synthesis_resonance_care_max',
     'synthesis_resonance_affinity_max',
     'synthesis_resonance_dominant_bonus',
     'synthesis_calibration_max'
   );

  update public.profiles set genesis_cores = 20, bits = 1000 where id = u1;
  insert into public.animas (
    owner_id, nickname, species_key, color_bucket, element, secondary_element,
    rarity, base_stats, care, care_score, status, stage, body_height_cm,
    sheet_path, manifest
  ) values (
    u1, 'synthesis-source-a', 'synthesis_source_a', 'green', 'plant', null,
    3, '{"hp":70,"atk":60,"def":55,"spd":35,"special":40}'::jsonb,
    v_care, public.anima_exp_for_level(10), 'ready', 1, 150,
    u1::text || '/synthesis-source-a/sheet.png',
    '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
  ) returning id into v_synthesis_a;
  insert into public.animas (
    owner_id, nickname, species_key, color_bucket, element, secondary_element,
    rarity, base_stats, care, care_score, status, stage, body_height_cm,
    sheet_path, manifest
  ) values (
    u1, 'synthesis-source-b', 'synthesis_source_b', 'gold', 'spark', null,
    4, '{"hp":45,"atk":75,"def":35,"spd":80,"special":65}'::jsonb,
    v_care, public.anima_exp_for_level(10), 'ready', 1, 75,
    u1::text || '/synthesis-source-b/sheet.png',
    '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
  ) returning id into v_synthesis_b;
  assert public.synthesis_source_display_name(v_synthesis_a) = 'synthesis-source-a'
         and public.synthesis_source_display_name(v_synthesis_b) = 'synthesis-source-b',
         'label Source Synthesis wajib memakai nickname, bukan fallback Anima';

  -- Historical art may remain available for Collection/Profile, but Synthesis
  -- must reject it and use only the Source's current committed form.
  insert into public.anima_forms (
    anima_id, stage, sheet_path, manifest, body_height_cm
  ) values (
    v_synthesis_a,
    1,
    u1::text || '/synthesis-source-a/form-1.png',
    '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb,
    150
  );
  update public.animas
     set stage = 2,
         sheet_path = u1::text || '/synthesis-source-a/form-2.png'
   where id = v_synthesis_a;
  begin
    perform public.preview_synthesis(
      u1, v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'SYNTHESIS_STAGE_MISMATCH');
  end;
  assert ok, 'preview Synthesis wajib menolak form historis';
  begin
    perform public.attempt_synthesis(
      u1, 'synthesis-stage-mismatch',
      v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint,
      'balanced', 'v42', 'uji'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'SYNTHESIS_STAGE_MISMATCH');
  end;
  assert ok, 'attempt Synthesis wajib menolak form historis sebelum debit';
  v_j := public.preview_synthesis(
    u1, v_synthesis_a, 2::smallint, v_synthesis_b, 1::smallint, 'balanced'
  );
  assert (v_j->'breakdown'->>'chance')::integer = 1,
         'preview Synthesis wajib menerima form committed saat ini';
  update public.animas
     set stage = 1,
         sheet_path = u1::text || '/synthesis-source-a/sheet.png'
   where id = v_synthesis_a;
  delete from public.anima_forms
   where anima_id = v_synthesis_a and stage = 1;
  delete from public.storage_cleanup_queue
   where object_path = u1::text || '/synthesis-source-a/form-1.png';

  v_j := public.preview_synthesis(
    u1, v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced'
  );
  assert (v_j->'breakdown'->>'chance')::integer = 1,
         'preview Resonance wajib memakai konfigurasi authoritative';

  -- Preview memakai gerbang yang sama dengan attempt. Kalau tidak, Source yang
  -- sedang bertarung tetap memperlihatkan angka Resonance yang tidak bisa dibeli.
  insert into public.battle_sessions (
    owner_id, player_anima_id, player_snapshot, bot_snapshot, state,
    player_hp, bot_hp, rng_seed
  ) values (
    u1, v_synthesis_a, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 10, 10, 'uji'
  );
  begin
    perform public.preview_synthesis(
      u1, v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'ANIMA_IN_ACTIVE_COMBAT');
  end;
  assert ok, 'preview Synthesis wajib menolak Source yang sedang bertarung';
  delete from public.battle_sessions
   where owner_id = u1 and player_anima_id = v_synthesis_a;

  perform setseed(0.42);
  select floor(random() * 100)::integer + 1 into v_synthesis_seed_roll;
  if v_synthesis_seed_roll = 1 then
    perform setseed(-0.42);
    select floor(random() * 100)::integer + 1 into v_synthesis_seed_roll;
    assert v_synthesis_seed_roll > 1, 'seed uji Resonance gagal tidak sah';
    perform setseed(-0.42);
  else
    perform setseed(0.42);
  end if;
  select genesis_cores, bits into v_synthesis_cores, v_synthesis_bits
    from public.profiles where id = u1;
  v_j := public.attempt_synthesis(
    u1, 'synthesis-failure',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced', 'v42', 'uji'
  );
  assert not (v_j->>'resonance_succeeded')::boolean
         and (v_j->>'chance')::integer = 1
         and (select genesis_cores from public.profiles where id = u1) = v_synthesis_cores
         and (select bits from public.profiles where id = u1) = v_synthesis_bits
         and (select count(*) from public.generations
               where owner_id = u1 and idempotency_key = 'synthesis-failure') = 0
         and (select (care->>'energy')::numeric from public.animas
               where id = v_synthesis_a) = 90
         and (select (care->>'energy')::numeric from public.animas
               where id = v_synthesis_b) = 90,
         'Resonance gagal tidak boleh membayar model/Core/Bits dan wajib memotong Energy';
  v_j2 := public.attempt_synthesis(
    u1, 'synthesis-failure',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced', 'v42', 'uji'
  );
  assert (v_j2->>'replayed')::boolean
         and (select failure_count from public.anima_synthesis_slots
               where owner_id = u1
                 and source_low_id::text = least(v_synthesis_a::text, v_synthesis_b::text)
                 and source_high_id::text = greatest(v_synthesis_a::text, v_synthesis_b::text)
                 and mode = 'balanced') = 1,
         'retry Resonance gagal tidak boleh memotong Energy atau menambah Calibration lagi';

  update public.anima_synthesis_slots
     set cooldown_until = null
   where owner_id = u1
     and source_low_id::text = least(v_synthesis_a::text, v_synthesis_b::text)
     and source_high_id::text = greatest(v_synthesis_a::text, v_synthesis_b::text)
     and mode = 'balanced';
  update public.app_config set value = '100'::jsonb
   where key = 'synthesis_resonance_base';
  insert into public.generations (
    owner_id, idempotency_key, kind, status, prompt_version, model, cost_usd_estimate
  ) values (
    u1, 'synthesis-technical-fail', 'create', 'failed', 'uji', 'uji', 0
  );
  v_j := public.attempt_synthesis(
    u1, 'synthesis-technical-fail',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced', 'v42', 'uji'
  );
  v_synthesis_gen := (v_j->>'generation_id')::uuid;
  v_synthesis_result := (v_j->>'result_anima_id')::uuid;
  assert (v_j->>'resonance_succeeded')::boolean
         and (select genesis_cores from public.profiles where id = u1) = v_synthesis_cores - 1
         and (select bits from public.profiles where id = u1) = v_synthesis_bits - 250
         and (select count(*) from public.quota_ledger
               where ref_id = v_synthesis_gen and delta < 0) = 2,
         'Resonance sukses harus claim Result + Core + Bits dalam satu transaksi';
  -- A paid replay is tied to its immutable snapshot. If a Source changes after
  -- claim, the same key must still resume instead of being rejected as a new
  -- historical-form request.
  update public.animas set stage = 2 where id = v_synthesis_a;
  v_j2 := public.attempt_synthesis(
    u1, 'synthesis-technical-fail',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced', 'v42', 'uji'
  );
  assert (v_j2->>'replayed')::boolean
         and (select count(*) from public.quota_ledger
               where ref_id = v_synthesis_gen and delta < 0) = 2,
         'retry claim Synthesis harus memakai snapshot lama tanpa mendebit ulang';
  update public.animas set stage = 1 where id = v_synthesis_a;
  assert (select idempotency_key from public.generations where id = v_synthesis_gen)
           = 'synthesis:synthesis-technical-fail',
         'generation Synthesis wajib menamespace key agar tidak bentrok dengan kind lain';

  begin
    perform public.attempt_synthesis(
      u1, 'synthesis-overlap',
      v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'dominant_a', 'v42', 'uji'
    );
    ok := false;
  exception when others then ok := sqlerrm = 'SYNTHESIS_ALREADY_ACTIVE';
  end;
  assert ok, 'satu akun hanya boleh memiliki satu Synthesis aktif';
  begin
    delete from public.animas where id = v_synthesis_a;
    ok := false;
  exception when others then ok := sqlerrm = 'SYNTHESIS_SOURCE_LOCKED';
  end;
  assert ok, 'Source tidak boleh dihapus sebelum reference snapshot aman';

  update public.animas
     set synthesis_history = '{"source_a":{"thumbnail_path":"stale.png"}}'::jsonb
   where id = v_synthesis_result;
  update public.anima_synthesis_slots
     set reference_paths = jsonb_build_object(
           'source_a', u1::text || '/synthesis-stale-a.png',
           'source_b', u1::text || '/synthesis-stale-b.png'
         )
   where active_generation_id = v_synthesis_gen;
  v_j := public.fail_synthesis(v_synthesis_gen, 'uji technical failure');
  v_j2 := public.fail_synthesis(v_synthesis_gen, 'uji technical replay');
  assert (v_j->>'core_refund')::integer = 1
         and (v_j->>'bits_refund')::integer = 250
         and (v_j2->>'core_refund')::integer = 0
         and (v_j2->>'bits_refund')::integer = 0
         and (select genesis_cores from public.profiles where id = u1) = v_synthesis_cores
         and (select bits from public.profiles where id = u1) = v_synthesis_bits
         and (select count(*) from public.quota_ledger
               where ref_id = v_synthesis_gen and reason = 'refund') = 1
         and (select count(*) from public.quota_ledger
               where ref_id = v_synthesis_gen and reason = 'synthesis_bits_refund') = 1
         and (select status from public.anima_synthesis_slots
               where owner_id = u1
                 and source_low_id::text = least(v_synthesis_a::text, v_synthesis_b::text)
                 and source_high_id::text = greatest(v_synthesis_a::text, v_synthesis_b::text)
                 and mode = 'balanced') = 'open'
         and (select synthesis_history is null from public.animas
               where id = v_synthesis_result)
         and (select count(*) from public.storage_cleanup_queue
               where object_path in (
                 u1::text || '/synthesis-stale-a.png',
                 u1::text || '/synthesis-stale-b.png'
               )
                 and reason = 'synthesis_failed') = 2,
         'technical failure wajib refund Core+Bits tepat sekali dan membuka mode lagi';
  -- storage_cleanup_queue tidak punya owner_id, jadi ia tidak ikut cascade saat
  -- user uji dihapus. Tanpa hapus manual, hitungan di atas menumpuk dan run
  -- kedua gagal walau kodenya benar.
  delete from public.storage_cleanup_queue
   where object_path in (
     u1::text || '/synthesis-stale-a.png',
     u1::text || '/synthesis-stale-b.png'
   );

  v_j := public.attempt_synthesis(
    u1, 'synthesis-success',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced', 'v42', 'uji'
  );
  v_synthesis_gen := (v_j->>'generation_id')::uuid;
  v_synthesis_result := (v_j->>'result_anima_id')::uuid;
  perform public.store_synthesis_references(
    u1, v_synthesis_gen,
    jsonb_build_object(
      'source_a', u1::text || '/synthesis-history-a.png',
      'source_b', u1::text || '/synthesis-history-b.png',
      'model_source_a', u1::text || '/synthesis-ref-a.png',
      'model_source_b', u1::text || '/synthesis-ref-b.png'
    )
  );
  perform public.reserve_synthesis_plan(
    u1,
    v_synthesis_gen,
    '{
      "suggested_name":"Verdiflux",
      "species_key":"synthesis_verdiflux",
      "color_bucket":"green_gold",
      "subject_kind":"animal",
      "primary_element":"plant",
      "secondary_element":"spark",
      "rarity":4,
      "base_stats":{"hp":58,"atk":68,"def":45,"spd":58,"special":51},
      "body_height_cm":113,
      "strike_name":"Vine Pounce",
      "surge_name":"Aurora Canopy",
      "strike_effect_id":"drain",
      "surge_effect_id":"slow",
      "inheritance_summary":{
        "source_a":"leaf mane",
        "source_b":"quadruped motion",
        "coherence":"conductive leaf veins"
      }
    }'::jsonb,
    jsonb_build_object(
      'source_a', u1::text || '/synthesis-history-a.png',
      'source_b', u1::text || '/synthesis-history-b.png',
      'model_source_a', u1::text || '/synthesis-ref-a.png',
      'model_source_b', u1::text || '/synthesis-ref-b.png'
    )
  );
  v_j := public.complete_synthesis(
    v_synthesis_gen,
    u1::text || '/synthesis-result/sheet.png',
    '{"stage":1,"prompt_version":"v42","poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
  );
  assert (v_j->>'status') = 'succeeded'
         and (select status from public.animas where id = v_synthesis_result) = 'ready'
         and (select stage from public.animas where id = v_synthesis_result) = 1
         and (select care_score from public.animas where id = v_synthesis_result) = 0
         and (select synthesis_history is not null from public.animas
               where id = v_synthesis_result)
         and (select synthesis_history->'source_a'->>'name'
               from public.animas where id = v_synthesis_result)
              = 'synthesis-source-a'
         and (select synthesis_history->'source_b'->>'name'
               from public.animas where id = v_synthesis_result)
              = 'synthesis-source-b'
         and (select synthesis_history is not null from public.atlas_forms
               where anima_id = v_synthesis_result and stage = 1)
         and (select status from public.anima_synthesis_slots
               where active_generation_id = v_synthesis_gen) = 'succeeded',
         'Result harus lahir Hatchling Lv1 dengan history privat + Atlas snapshot';
  perform public.store_synthesis_history_references(
    u1,
    v_synthesis_result,
    jsonb_build_object(
      'source_a', u1::text || '/synthesis-history-a-v2.png',
      'source_b', u1::text || '/synthesis-history-b-v2.png',
      'model_source_a', u1::text || '/synthesis-ref-a.png',
      'model_source_b', u1::text || '/synthesis-ref-b.png'
    )
  );
  assert (select reference_paths->>'source_a'
            from public.anima_synthesis_slots
           where result_anima_id = v_synthesis_result)
              = u1::text || '/synthesis-history-a-v2.png'
         and (select reference_paths->>'model_source_a'
                from public.anima_synthesis_slots
               where result_anima_id = v_synthesis_result)
              = u1::text || '/synthesis-ref-a.png'
         and (select synthesis_history->'source_a'->>'thumbnail_path'
                from public.animas where id = v_synthesis_result)
              = u1::text || '/synthesis-history-a-v2.png'
         and (select synthesis_history->'source_b'->>'thumbnail_path'
                from public.atlas_forms
               where anima_id = v_synthesis_result and stage = 1)
              = u1::text || '/synthesis-history-b-v2.png',
         'History harus bisa berpindah ke crop transparan tanpa mengganti model reference';
  begin
    perform public.attempt_synthesis(
      u1, 'synthesis-mode-reused',
      v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'balanced', 'v42', 'uji'
    );
    ok := false;
  exception when others then ok := sqlerrm = 'SYNTHESIS_MODE_USED';
  end;
  assert ok, 'satu Source Pair hanya boleh sukses sekali per bias';

  -- Synthesis yang sudah dibayar tapi tidak pernah di-resume (uninstall, ganti
  -- HP, data dihapus) harus dibebaskan sendiri. Tanpa sapuan ini slot satu-aktif
  -- terkunci selamanya dan Core + Bits-nya tidak pernah kembali.
  v_synthesis_cores := (select genesis_cores from public.profiles where id = u1);
  v_synthesis_bits := (select bits from public.profiles where id = u1);
  v_j := public.attempt_synthesis(
    u1, 'synthesis-stale-lock',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'dominant_b', 'v42', 'uji'
  );
  v_synthesis_gen := (v_j->>'generation_id')::uuid;
  update public.generations
     set created_at = now() - interval '30 minutes'
   where id = v_synthesis_gen;
  v_j := public.attempt_synthesis(
    u1, 'synthesis-after-stale',
    v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'dominant_a', 'v42', 'uji'
  );
  assert (v_j->>'resonance_succeeded')::boolean
         and (select status from public.generations where id = v_synthesis_gen) = 'failed'
         and (select error from public.generations where id = v_synthesis_gen)
               = 'SYNTHESIS_STALE_RECOVERED'
         and (select count(*) from public.anima_synthesis_slots
               where owner_id = u1 and status = 'pending') = 1
         and (select count(*) from public.quota_ledger
               where ref_id = v_synthesis_gen and reason = 'refund') = 1
         and (select genesis_cores from public.profiles where id = u1) = v_synthesis_cores - 1
         and (select bits from public.profiles where id = u1) = v_synthesis_bits - 250,
         'pending Synthesis yang basi wajib direfund dan tidak mengunci slot lain';
  perform public.fail_synthesis((v_j->>'generation_id')::uuid, 'uji bersihkan pending');
  assert (select count(*) from public.anima_synthesis_slots
           where owner_id = u1 and status = 'pending') = 0
         and (select genesis_cores from public.profiles where id = u1) = v_synthesis_cores
         and (select bits from public.profiles where id = u1) = v_synthesis_bits,
         'membatalkan pending terakhir harus memulihkan saldo apa adanya';

  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.attempt_synthesis(
      u1, 'synthesis-client-forbidden',
      v_synthesis_a, 1::smallint, v_synthesis_b, 1::smallint, 'dominant_b', 'v42', 'uji'
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'client tidak boleh memanggil RPC Synthesis service-role langsung';
  begin
    perform public.store_synthesis_history_references(
      u1,
      v_synthesis_result,
      jsonb_build_object(
        'source_a', u1::text || '/forbidden-history-a.png',
        'source_b', u1::text || '/forbidden-history-b.png',
        'model_source_a', u1::text || '/forbidden-model-a.png',
        'model_source_b', u1::text || '/forbidden-model-b.png'
      )
    );
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  perform set_config('role', 'none', true);
  assert ok, 'client tidak boleh mengganti reference Synthesis History';

  update public.app_config config
     set value = saved.value
    from jsonb_each(v_synthesis_config) saved
   where config.key = saved.key;

  delete from public.animas where owner_id = u1 and nickname = 'v2 ok';
  assert exists (
           select 1 from public.storage_cleanup_queue
            where bucket_id = 'anima_sheets'
              and object_path =
                u1::text || '/00000000-0000-4000-8000-000000000099/sheet.png'
              and reason = 'anima_deleted'
         ),
         'delete Anima privat harus mengantrekan cleanup blob';

  ----------------------------------------------------------------------------
  -- Penghapusan auth user adalah mekanisme yang dipakai endpoint delete_account.
  with inserted as (
    insert into public.animas (
      owner_id, nickname, species_key, color_bucket, element, rarity,
      base_stats, care, status, sheet_path, manifest
    )
    select
      u3, 'account-team-' || gs.n, 'account_team_species_' || gs.n, 'blue', 'metal', 1,
      v_stats, v_care, 'ready', u3::text || '/account-team-' || gs.n || '/sheet.png',
      '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
      from generate_series(1, 4) as gs(n)
    returning id, nickname
  )
  select array_agg(id order by nickname) into v_team_ids from inserted;
  v_j := public.save_anima_team(u3, 'team_battle', v_team_ids);
  v_team_id := (v_j->>'id')::uuid;
  select jsonb_agg(jsonb_build_object(
    'anima_id', a.id,
    'name', a.nickname,
    'species_key', a.species_key,
    'color_bucket', a.color_bucket,
    'stage', a.stage,
    'level', 1,
    'element', a.element,
    'base_stats', a.base_stats,
    'sheet_path', a.sheet_path,
    'manifest', a.manifest
  ) order by ids.ordinality)
  into v_team_snapshot
  from unnest(v_team_ids) with ordinality ids(id, ordinality)
  join public.animas a on a.id = ids.id;
  select roster_snapshot into v_opponent_snapshot
    from public.system_team_templates
   where active
   order by created_at
   limit 1;
  insert into public.team_battle_sessions (
    owner_id, player_team_id, opponent_source,
    player_snapshot, opponent_snapshot, state, rng_seed,
    reward_tier, reward_roll, reward_bits
  ) values (
    u3, v_team_id, 'system',
    v_team_snapshot, v_opponent_snapshot, '{"status":"active"}'::jsonb,
    'account-delete-active-team', 'even', 0, 8
  );
  delete from auth.users where id = u3;
  assert not exists (select 1 from public.profiles where id = u3),
         'delete account harus melewati guard active Team dan cascade ke profil';
  assert not exists (select 1 from public.team_battle_sessions where owner_id = u3),
         'delete account harus cascade active Team session';
  assert exists (
    select 1 from public.species_library
     where species_key = v_spesies and color_bucket = 'gray' and stage = 1
  ), 'delete account tidak boleh menghapus pustaka spesies bersama';

  begin
    with inserted as (
      insert into public.animas (
        owner_id, nickname, species_key, color_bucket, element, rarity,
        base_stats, care, status, sheet_path, manifest
      )
      select
        u4, 'expedition-delete-' || gs.n, 'expedition_delete_species_' || gs.n,
        'blue', 'metal', 1, v_stats, v_care, 'ready',
        u4::text || '/expedition-delete-' || gs.n || '/sheet.png',
        '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
      from generate_series(1, 4) as gs(n)
      returning id, nickname
    )
    select array_agg(id order by nickname) into v_team_ids from inserted;
    v_j := public.save_anima_team(u4, 'expedition', v_team_ids);
    v_team_id := (v_j->>'id')::uuid;
    select jsonb_agg(jsonb_build_object(
      'anima_id', a.id,
      'name', a.nickname,
      'base_stats', a.base_stats,
      'hp', 100,
      'max_hp', 100
    ) order by ids.ordinality)
    into v_team_snapshot
    from unnest(v_team_ids) with ordinality ids(id, ordinality)
    join public.animas a on a.id = ids.id;
    insert into public.expedition_chapters (slug, sequence)
    values ('test-account-delete-expedition', 9997)
    returning id into v_expedition_chapter;
    insert into public.expedition_chapter_versions (
      chapter_id, content_version, manifest, manifest_hash, asset_prefix
    ) values (
      v_expedition_chapter, 1, '{}'::jsonb, repeat('c', 64),
      'expeditions/test-account-delete-expedition/v1/'
    ) returning id into v_expedition_version;
    insert into public.expedition_runs (
      owner_id, chapter_version_id, team_id, status, seed,
      zone_map, available_node_ids, party_state
    ) values (
      u4, v_expedition_version, v_team_id, 'active', 'delete-expedition',
      '{"entry":["active"],"nodes":[]}'::jsonb, '[]'::jsonb, v_team_snapshot
    ) returning id into v_expedition_run;
    insert into public.expedition_encounters (
      run_id, owner_id, node_id, kind, player_snapshot, opponent_snapshot,
      state, rng_seed
    ) values (
      v_expedition_run, u4, 'active-delete', 'battle',
      v_team_snapshot, v_opponent_snapshot, '{}'::jsonb, 'delete-expedition'
    ) returning id into v_expedition_encounter;
    delete from auth.users where id = u4;
    assert not exists (select 1 from public.expedition_runs where owner_id = u4)
           and not exists (
             select 1 from public.expedition_encounters
              where id = v_expedition_encounter
           ),
           'delete account harus cascade active run dan encounter Expedition';
    raise exception using errcode = 'ZX003', message = 'rollback delete Expedition fixture';
  exception when sqlstate 'ZX003' then
    null;
  end;

  ----------------------------------------------------------------------------
  -- Atlas Moderation Admin v2: default-deny, staff role gate, idempotent
  -- case-open, thumb-required approve/restore, decision+audit atomicity,
  -- report quarantine with category mapping, and sanction lifecycle.
  --
  -- moderation_cases/moderation_decisions/gallery_reports are the one
  -- deliberate exception: 20260823160255_atlas_moderation_realtime_rls.sql
  -- grants authenticated SELECT (needed for the admin console's Realtime
  -- subscriptions) but gates every row behind a staff-only RLS policy, so a
  -- non-staff session succeeds with zero rows instead of erroring. A 0-row
  -- result only proves anything once real rows exist, so those three are
  -- asserted further down, right after this block's own fixture has created
  -- cases, decisions and reports -- not here, where a fresh database has none.
  perform set_config('role', 'authenticated', true);
  begin
    perform 1 from public.staff_accounts;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'staff_accounts tidak boleh dibaca client';
  begin
    perform 1 from public.profile_sanctions;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'profile_sanctions tidak boleh dibaca client';
  begin
    perform 1 from public.admin_audit_log;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'admin_audit_log tidak boleh dibaca client';
  begin
    perform 1 from public.gallery_moderation_runs;
    ok := false;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'gallery_moderation_runs tidak boleh dibaca client';
  assert not pg_catalog.has_function_privilege(
    'authenticated', 'public.moderation_decide_case(uuid,uuid,text,text,text,text,text)', 'EXECUTE'
  ), 'client tidak boleh memanggil moderation_decide_case langsung';
  assert not pg_catalog.has_function_privilege(
    'authenticated', 'public.moderation_set_sanction(uuid,uuid,text,text,text,timestamptz,text)', 'EXECUTE'
  ), 'client tidak boleh memanggil moderation_set_sanction langsung';
  assert not pg_catalog.has_function_privilege(
    'authenticated', 'public.admin_set_staff_role(uuid,text,uuid,text)', 'EXECUTE'
  ), 'client tidak boleh memanggil admin_set_staff_role langsung';
  perform set_config('role', 'none', true);

  -- Staff setup: u1 admin, u2 moderator (both already real profiles from
  -- earlier in this suite; neither was ever deleted).
  insert into public.staff_accounts (user_id, role) values (u1, 'admin');
  insert into public.staff_accounts (user_id, role) values (u2, 'moderator');

  begin
    perform public.admin_set_staff_role(u1, 'moderator', u1, 'selftest-self-demote');
    ok := false;
  exception when others then ok := (sqlerrm = 'CANNOT_REVOKE_SELF');
  end;
  assert ok, 'admin tidak boleh menurunkan role dirinya sendiri, bukan cuma tidak boleh revoke penuh';

  begin
    perform public.admin_set_staff_role(u4, 'viewer', u2, 'selftest-mod-cannot-staff');
    ok := false;
  exception when others then ok := (sqlerrm = 'STAFF_ROLE_INSUFFICIENT');
  end;
  assert ok, 'moderator tidak boleh mengelola staff_accounts';

  perform public.admin_set_staff_role(u4, 'viewer', u1, 'selftest-grant-viewer');
  assert (select role from public.staff_accounts where user_id = u4) = 'viewer',
         'admin harus bisa memberi role staff';
  perform public.admin_set_staff_role(u4, 'revoked', u1, 'selftest-revoke-viewer');
  assert not exists (select 1 from public.staff_accounts where user_id = u4),
         'admin harus bisa mencabut role staff';

  -- Fixture: an entry with no thumbnail, simulating a pass-2-uncertain
  -- publish that returned into "pending" before gallery/index.ts's thumb
  -- crop+upload step ever ran.
  v_mod_art_hash := repeat('m', 64);
  insert into public.animas (
    owner_id, nickname, species_key, color_bucket, element, rarity,
    base_stats, care, status, sheet_path, manifest
  ) values (
    u4, 'mod-fixture', 'mod_fixture_species', 'blue', 'metal', 1,
    v_stats, v_care, 'ready', u4::text || '/mod-fixture/sheet.png',
    '{"poses":{"idle":{"region":[0,0,64,64]}}}'::jsonb
  ) returning id into v_mod_anima;
  insert into public.gallery_entries (
    owner_id, anima_id, art_hash, display_name, element, secondary_element,
    stage, thumb_path, moderation_status, published, auto_hidden,
    report_count, published_at
  ) values (
    u4, v_mod_anima, v_mod_art_hash, 'Mod Fixture', 'metal', null,
    1, null, 'pending', false, false, 0, null
  ) returning id into v_mod_entry;

  v_mod_case := public.moderation_open_case_for_entry(
    v_mod_entry, v_mod_art_hash, 'publish', 'ip_character', 'low', 'pass2_uncertain'
  );
  v_mod_case2 := public.moderation_open_case_for_entry(
    v_mod_entry, v_mod_art_hash, 'publish', 'ip_character', 'low', 'pass2_uncertain'
  );
  assert v_mod_case = v_mod_case2,
         'membuka case yang sama dua kali harus mengembalikan case_id yang sama';
  assert (
           select count(*) from public.moderation_cases
            where entry_id = v_mod_entry and art_hash = v_mod_art_hash
         ) = 1,
         'tidak boleh ada dua case aktif untuk entry+art_hash yang sama';

  begin
    perform public.moderation_decide_case(
      v_mod_case, u2, 'approve', 'ip_character_match', null, 'selftest-approve-no-thumb'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'THUMB_REQUIRED');
  end;
  assert ok, 'approve tanpa thumbnail siap harus ditolak THUMB_REQUIRED, bukan menerbitkan entry tanpa gambar';

  v_j := public.moderation_decide_case(
    v_mod_case, u2, 'approve', 'ip_character_match', 'looks fine on review',
    'selftest-approve-1', u4::text || '/mod-fixture/thumb.png'
  );
  assert (v_j->>'case_status') = 'approved', 'approve harus mengembalikan case_status approved';
  assert (
           select published and moderation_status = 'approved' and thumb_path is not null
             from public.gallery_entries where id = v_mod_entry
         ),
         'approve harus menerbitkan entry dan mengisi thumb_path dalam transaksi yang sama';
  select count(*) into v_decision_count from public.moderation_decisions where case_id = v_mod_case;
  assert v_decision_count = 1, 'approve harus menulis tepat satu baris moderation_decisions';
  select count(*) into v_audit_count from public.admin_audit_log
   where target_type = 'moderation_case' and target_id = v_mod_case::text;
  assert v_audit_count = 1, 'approve harus menulis tepat satu baris admin_audit_log';

  v_j := public.moderation_decide_case(
    v_mod_case, u2, 'approve', 'ip_character_match', 'looks fine on review',
    'selftest-approve-1', u4::text || '/mod-fixture/thumb.png'
  );
  assert (v_j->>'idempotent_replay')::bool, 'replay idempotency_key yang sama harus dikenali, bukan diproses ulang';
  select count(*) into v_decision_count from public.moderation_decisions where case_id = v_mod_case;
  assert v_decision_count = 1, 'replay tidak boleh menggandakan moderation_decisions';

  begin
    perform public.moderation_decide_case(
      v_mod_case, u2, 'reject', 'unsafe_content', null, 'selftest-reject-after-approve'
    );
    ok := false;
  exception when others then ok := (sqlerrm = 'CASE_ALREADY_RESOLVED');
  end;
  assert ok, 'case yang sudah resolved tidak boleh diputuskan lagi walau dengan idempotency_key baru';

  -- Report quarantine: three distinct non-owner reporters, category
  -- "character" must map into the automated "ip_character" vocabulary
  -- instead of violating moderation_cases' CHECK constraint.
  v_rep_c := gen_random_uuid();
  insert into auth.users (id, is_anonymous) values (v_rep_c, true);
  perform public.moderation_report_and_maybe_case(v_mod_entry, u1, 'character', null, 3);
  assert (select report_count from public.gallery_entries where id = v_mod_entry) = 1,
         'report pertama harus menghitung report_count = 1';
  assert not (select auto_hidden from public.gallery_entries where id = v_mod_entry),
         'satu laporan belum boleh mencapai ambang auto-hide';
  perform public.moderation_report_and_maybe_case(v_mod_entry, u2, 'character', null, 3);
  v_j := public.moderation_report_and_maybe_case(v_mod_entry, v_rep_c, 'character', null, 3);
  assert (v_j->>'newly_hidden')::bool, 'laporan ketiga harus melewati ambang auto-hide';
  assert (select auto_hidden from public.gallery_entries where id = v_mod_entry),
         'entry harus auto-hidden setelah ambang tercapai';
  assert exists (
           select 1 from public.moderation_cases
            where entry_id = v_mod_entry and source = 'report'
              and category = 'ip_character' and status = 'open'
         ),
         'quarantine harus membuka case dengan kategori report dipetakan ke kosakata otomatis, bukan mentah';

  -- Sanctions: set, one-active-per-scope, revoke, idempotent revoke, and a
  -- second set on the same profile+scope creates a fresh row.
  v_sanction_id := public.moderation_set_sanction(
    u4, u2, 'atlas_publish', 'report_upheld', 'selftest sanction', null, 'selftest-sanction-1'
  );
  assert exists (
           select 1 from public.profile_sanctions
            where id = v_sanction_id and profile_id = u4 and scope = 'atlas_publish'
              and revoked_at is null
         ),
         'set_sanction harus membuat baris sanction aktif';
  perform public.moderation_revoke_sanction(v_sanction_id, u2, 'owner_appeal_valid', 'selftest-sanction-revoke-1');
  assert (select revoked_at from public.profile_sanctions where id = v_sanction_id) is not null,
         'revoke_sanction harus menandai revoked_at';
  perform public.moderation_revoke_sanction(v_sanction_id, u2, 'owner_appeal_valid', 'selftest-sanction-revoke-1');
  begin
    perform public.moderation_revoke_sanction(v_sanction_id, u2, 'owner_appeal_valid', 'selftest-sanction-revoke-2');
    ok := false;
  exception when others then ok := (sqlerrm = 'SANCTION_ALREADY_REVOKED');
  end;
  assert ok, 'me-revoke sanction yang sudah revoked dengan idempotency_key baru harus ditolak';

  v_sanction_id2 := public.moderation_set_sanction(
    u4, u1, 'atlas_publish', 'unsafe_content', null, null, 'selftest-sanction-2'
  );
  assert v_sanction_id2 <> v_sanction_id, 'set_sanction berikutnya harus membuat baris baru, bukan reuse';
  assert (
           select count(*) from public.profile_sanctions
            where profile_id = u4 and scope = 'atlas_publish' and revoked_at is null
         ) = 1,
         'hanya boleh ada satu sanction aktif per profile+scope';

  -- The staff-gated-but-granted trio, now that the fixture above has left real
  -- cases, decisions and reports behind: a 0-row result proves nothing on an
  -- empty table, so existence is asserted first as the unrestricted role.
  assert (select count(*) from public.moderation_cases) >= 1,
         'fixture harus meninggalkan moderation_cases nyata sebelum menguji RLS-nya';
  assert (select count(*) from public.moderation_decisions) >= 1,
         'fixture harus meninggalkan moderation_decisions nyata sebelum menguji RLS-nya';
  assert (select count(*) from public.gallery_reports) >= 1,
         'fixture harus meninggalkan gallery_reports nyata sebelum menguji RLS-nya';

  -- Both directions, each under an identity this block states outright.
  -- Inheriting whatever `request.jwt.claims` an earlier block happened to
  -- leave set is how the older version of this check passed for the wrong
  -- reason: u1 is made an admin above, so a "sees nothing" assertion running
  -- as u1 was exercising the staff path while claiming to prove the player
  -- one. u4's staff row was granted and then revoked above, so it is a
  -- genuine non-staff authenticated session.
  perform set_config('request.jwt.claims',
    json_build_object('sub', u4::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  assert (select count(*) from public.moderation_cases) = 0,
         'RLS harus menyembunyikan seluruh moderation_cases dari authenticated non-staff, walau grant SELECT ada untuk Realtime';
  assert (select count(*) from public.moderation_decisions) = 0,
         'RLS harus menyembunyikan seluruh moderation_decisions dari authenticated non-staff';
  assert (select count(*) from public.gallery_reports) = 0,
         'RLS harus menyembunyikan seluruh gallery_reports dari authenticated non-staff';

  -- And the staff side must actually be readable, otherwise the console's
  -- Realtime subscriptions would deliver nothing and a policy that denied
  -- everyone would still pass the checks above.
  perform set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  assert (select count(*) from public.moderation_cases) >= 1,
         'staff harus tetap bisa membaca moderation_cases, kalau tidak Realtime admin mati';
  assert (select count(*) from public.moderation_decisions) >= 1,
         'staff harus tetap bisa membaca moderation_decisions';
  assert (select count(*) from public.gallery_reports) >= 1,
         'staff harus tetap bisa membaca gallery_reports';
  perform set_config('role', 'none', true);

  v_j := public.moderation_analytics_summary(now() - interval '1 day');
  assert (v_j->>'open_cases')::int >= 1,
         'analytics harus menghitung case report yang baru dibuka';
  assert (v_j->'manual_outcomes'->>'approved')::int >= 1,
         'analytics harus menghitung outcome approved dari case publish di atas';
  assert (v_j->'decisions_by_action'->>'approve')::int >= 1,
         'analytics harus membaca moderation_decisions, bukan tabel kosong';

  -- Cleanup: tabel baru ini di-reference dari auth.users TANPA cascade
  -- (moderation_decisions.staff_id, admin_audit_log, dan profile_sanctions
  -- sengaja immutable/RESTRICT), jadi harus dibersihkan sebelum delete
  -- auth.users di akhir file atau delete itu sendiri akan gagal
  -- foreign_key_violation -- terukur nyata saat menguji ini lokal.
  delete from public.moderation_decisions where staff_id in (u1, u2);
  delete from public.admin_audit_log where actor_id in (u1, u2);
  delete from public.profile_sanctions where created_by in (u1, u2) or revoked_by in (u1, u2);
  delete from auth.users where id = v_rep_c;

  delete from auth.users where id in (u1, u2, u3, u4, u5);
  delete from public.species_library where species_key = v_spesies;
  raise notice 'SEMUA UJI LULUS';
end $uji$;
