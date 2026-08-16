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
  v_battle_player_snapshot jsonb;
  v_battle_bot_snapshot jsonb;
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
  v_bits_before_battle int;
  v_score_before_battle int;
  v_wins_before_battle int;
  v_seeker_xp int;
  v_seeker_victories int;
  v_weekly_at timestamptz;
  v         int;
  n         int;
  ok        bool;
begin
  -- Idempoten: sisa run yang gagal di tengah tidak boleh menggagalkan run ini.
  delete from auth.users where id in (u1, u2, u3, u4);
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

  v_j := public.complete_seeker_profile(u1, 'TestSeeker', 2000, null);
  assert v_j->>'seeker_name' = 'TestSeeker', 'profil Seeker harus tersimpan';
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
  perform public.complete_seeker_profile(u2, 'GuestTwo', null, 'prefer_not_to_say');
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
  exception when check_violation then ok := true;
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
  grant update on public.profiles to authenticated;
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles set genesis_cores = 99 where id = u1;
    ok := false;
  exception when others then ok := (sqlerrm like 'hanya display_name%');
  end;
  perform set_config('role', 'none', true);
  -- Revoke tingkat tabel juga mencabut hak kolom, jadi hak kolomnya diberikan ulang.
  revoke update on public.profiles from authenticated;
  grant update (display_name, last_seen_at) on public.profiles to authenticated;
  assert ok, 'trigger guard harus menolak perubahan mata uang oleh non-service role';

  ----------------------------------------------------------------------------
  -- 10. Care loop: decay, idempotency, debit Bits, cap harian, tidur, Dormant
  ----------------------------------------------------------------------------
  select id into v_care_anima
    from public.animas
   where owner_id = u1 and nickname = 'uji anima';

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

  -- Play tetap memberi Bond setelah cap score harian tercapai, tetapi tidak
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
           = v_score_before_battle + 4,
         'menang harus memberi care_score +4';
  assert (select battle_wins from public.animas where id = v_battle_player)
           = v_wins_before_battle + 1,
         'menang harus menaikkan battle_wins satu';
  assert (select seeker_xp from public.profiles where id = u1) = v_seeker_xp + 4
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
  -- Satu item per Battle, dan cap 100 Bits Training
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
         'item Battle harus dikonsumsi sekali';
  begin
    perform public.commit_battle_turn(
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
    ok := false;
  exception when others then ok := (sqlerrm = 'ITEM_ALREADY_USED');
  end;
  assert ok, 'item kedua dalam Battle yang sama harus ditolak';
  assert (select quantity from public.player_inventory
           where owner_id = u1 and item_id = 'vital_patch') = 1,
         'item yang ditolak tidak boleh dikonsumsi';
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
             'feature_weekly_core', 'feature_gallery', 'min_client_version'
           )) = 6,
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
             'expedition_bench_exp'
           )) = 12,
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
         and (select value from public.app_config where key = 'expedition_bench_exp') = '1'::jsonb,
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
      from generate_series(1, 4) as gs(n)
    returning id, nickname
  )
  select array_agg(id order by nickname) into v_team_ids from inserted;

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
  v_j := public.save_anima_team(u2, 'defense', v_defense_ids);
  v_defense_team_id := (v_j->>'id')::uuid;
  assert jsonb_array_length(v_j->'members') = 4,
         'save Team harus atomik berisi tepat empat Anima';

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
  into v_opponent_snapshot
  from unnest(v_defense_ids) with ordinality ids(id, ordinality)
  join public.animas a on a.id = ids.id;

  v_j := public.publish_defense_team(u2, v_opponent_snapshot, true);
  assert (v_j->>'published')::boolean,
         'Defense Team harus opt-in sebelum masuk pool';

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
                   when ids.ordinality <= 2 then 2
                   when ids.ordinality = 3 then 1
                   else 0
                 end
           )
             from unnest(v_team_ids) with ordinality ids(id, ordinality)
             join public.animas a on a.id = ids.id
         ),
         format(
           'active Team mendapat +2, bench hidup +1, KO 0; actual=%s',
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
         and (v_j2->'last_reward'->>'progression')::boolean,
         'resume Team terminal harus membawa receipt reward untuk result UI';

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
  perform public.refund_generation(v_id, 'uji private capture refund');
  assert (select genesis_cores from public.profiles where id = u1) = 3
         and (select count(*) from public.quota_ledger
               where ref_id = v_id and reason = 'refund') = 1,
         'refund capture privat harus mengembalikan Core tepat sekali';

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
    v_j := public.commit_expedition_choice(
      u1, v_expedition_run, v, 'zone-1-exit', 'continue',
      v_expedition_party, 0, '[]'::jsonb, '[]'::jsonb, true,
      'test-clear-zone-1'
    );
    assert (v_j->>'status') = 'checkpoint'
           and (v_j->>'zone')::integer = 2
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
           and (v_j->'last_zone_reward'->>'bits')::integer = 20
           and (v_j->'daily_bits'->>'bits_earned')::integer = 30,
           'checkpoint RPC Zone 2 harus memberi 20 Bits dari manifest';

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
    update public.app_config set value = '1'::jsonb
     where key = 'expedition_rewarded_encounters_per_day';
    insert into public.expedition_encounters (
      run_id, owner_id, node_id, kind, player_snapshot, opponent_snapshot,
      state, status, rng_seed, finished_at, rewarded_at
    ) values (
      v_expedition_run, u1, 'reward-cap-fixture', 'battle',
      v_team_snapshot, v_opponent_snapshot, v_expedition_state,
      'won', 'reward-cap-fixture', now(), now()
    ) returning id into v_id;
    insert into public.expedition_encounter_rewards (
      encounter_id, owner_id, progression, supplies
    ) values (v_id, u1, true, 2);
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
           and not (v_j->'reward'->>'progression')::boolean
           and (v_j->'reward'->>'supplies')::integer = 8
           and (v_j->'run'->'last_zone_reward'->>'scheduled_bits')::integer = 30
           and (v_j->'run'->'last_zone_reward'->>'bits')::integer = 10
           and (v_j->'run'->'last_zone_reward'->>'capped')::boolean
           and (v_j->'run'->'daily_bits'->>'bits_earned')::integer = 60
           and (v_j->'run'->'daily_bits'->>'bits_remaining')::integer = 0
           and v_j->'run'->'visited_node_ids' ? 'boss-1'
           and (select sum(care_score)::integer from public.animas
                 where id = any(v_team_ids)) = v_score_before_battle,
           'Boss pertama harus menyelesaikan run dan memberi reward Zone 3';
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

  delete from auth.users where id in (u1, u2, u3, u4);
  delete from public.species_library where species_key = v_spesies;
  raise notice 'SEMUA UJI LULUS';
end $uji$;
