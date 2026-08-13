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
  v_bits_before_battle int;
  v_score_before_battle int;
  v_wins_before_battle int;
  v         int;
  n         int;
  ok        bool;
begin
  -- Idempoten: sisa run yang gagal di tengah tidak boleh menggagalkan run ini.
  delete from auth.users where id in (u1, u2);
  delete from public.species_library where species_key = v_spesies;
  insert into auth.users (id, is_anonymous) values (u1, true), (u2, true);

  -- Profilnya TIDAK disisipkan di sini: trigger on_auth_user_created yang
  -- membuatnya. Kalau trigger itu hilang, panggilan pertama pemain baru gagal
  -- dengan NO_PROFILE dari fungsi kuota — jauh dari sebabnya, dan tidak ada uji
  -- lain yang akan menunjukkan letaknya.
  assert (select count(*) from public.profiles where id in (u1, u2)) = 2,
         'bootstrap profil saat sign-in anonim tidak jalan';
  assert (select count(*) from public.profiles where id in (u1, u2) and bits = 30) = 2,
         'profil baru harus menerima 30 starter Bits';
  assert (select count(*) from public.quota_ledger
           where owner_id in (u1, u2) and currency = 'bits'
             and delta = 30 and reason = 'care_starter') = 2,
         'starter Bits harus tercatat di ledger';
  update public.profiles set display_name = 'uji' where id in (u1, u2);

  insert into public.animas (owner_id, nickname, species_key, color_bucket,
                             element, rarity, base_stats, care)
  values (u1, 'uji anima', 'mouse_plastic', 'gray', 'tech', 3, v_stats, v_care);
  insert into public.species_library
    (species_key, color_bucket, stage, sheet_path, manifest, prompt_version)
  values (v_spesies, 'gray', 1, 'uji.png', '{}'::jsonb, 'v3');

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

  v_j2 := public.record_cache_hit(u2, 'key-cache', 'Uji Cache', v_spesies, 'gray',
                                  1::smallint, 'tech', 3, v_stats, v_care, v_visi, 'v3');
  assert v_j2 = v_j, 'cache hit dengan key sama harus mengembalikan baris yang sama';
  assert (select count(*) from public.animas where owner_id = u2) = 1,
         'retry cache hit tidak boleh membuat Anima kedua';
  assert (select times_reused from public.species_library
           where species_key = v_spesies and color_bucket = 'gray' and stage = 1) = 1,
         'retry tidak boleh menaikkan times_reused dua kali';

  -- Cache hit tidak pernah mendebit, jadi tidak ada yang bisa dikembalikan.
  perform public.refund_generation((v_j->>'generation_id')::uuid, 'uji: cache hit');
  assert (select genesis_cores from public.profiles where id = u2) = v,
         'cache hit tidak boleh menghasilkan Core gratis';

  ----------------------------------------------------------------------------
  -- 7. Generation yang sudah berhasil tidak boleh direfund (art sudah diberikan)
  ----------------------------------------------------------------------------
  update public.generations set status = 'succeeded' where id = v_sukses;
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

  update public.profiles set bits = 30 where id = u1;
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

  v_j := public.apply_care(u1, v_care_anima, 'feed', 'care-feed-1');
  assert (v_j->>'bits')::int = 25, 'Feed harus mendebit tepat 5 Bits';
  assert (v_j #>> '{anima,care,hunger}')::numeric = 35,
         'Feed harus memulihkan 35 Hunger';
  assert (v_j #>> '{anima,care,bond}')::numeric = 0,
         'Bond tidak lagi meter progres';
  assert (v_j #>> '{anima,care_score}')::int = 3,
         'Feed saat Hunger <40 harus memberi 3 care_score';
  assert (select count(*) from public.quota_ledger
           where owner_id = u1 and currency = 'bits' and delta = -5
             and reason = 'feed') = 1,
         'debit Feed harus punya tepat satu baris ledger';

  v_j2 := public.apply_care(u1, v_care_anima, 'feed', 'care-feed-1');
  assert (v_j2->>'replayed')::bool, 'key care yang sama harus masuk jalur replay';
  assert (v_j2->>'bits')::int = 25, 'replay Feed tidak boleh mendebit lagi';
  assert (v_j2 #>> '{anima,care,hunger}')::numeric = 35,
         'replay Feed tidak boleh memulihkan dua kali';
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
  assert (v_j->>'bits')::int = 20, 'Clean harus mendebit tepat 5 Bits';
  assert (v_j #>> '{anima,care,hygiene}')::numeric = 35,
         'Clean harus memulihkan 35 Hygiene';
  assert (v_j #>> '{anima,care_score}')::int = 6,
         'Clean saat Hygiene <50 harus memberi 3 care_score';

  -- Meter yang tampil penuh (100 atau 99.99) tidak boleh mendebit Bits.
  update public.profiles set bits = 20 where id = u1;
  update public.animas
     set care = '{"hunger":99.99,"energy":100,"hygiene":99.99,"bond":0}'::jsonb,
         care_synced_at = now()
   where id = v_care_anima;
  begin
    perform public.apply_care(u1, v_care_anima, 'feed', 'care-feed-full');
    ok := false;
  exception when others then ok := (sqlerrm = 'NEED_FULL');
  end;
  assert ok, 'Feed pada Hunger yang tampil penuh harus ditolak';
  assert (select bits from public.profiles where id = u1) = 20,
         'NEED_FULL Feed tidak boleh mendebit Bits';
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
  assert (select bits from public.profiles where id = u1) = 20,
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
         care_synced_at = now()
   where id = v_care_anima;
  begin
    perform public.apply_care(u1, v_care_anima, 'feed', 'care-no-bits');
    ok := false;
  exception when others then ok := (sqlerrm = 'NO_BITS');
  end;
  assert ok, 'Feed tanpa saldo harus ditolak dengan NO_BITS';
  assert not exists (
    select 1 from public.care_events
     where owner_id = u1 and idempotency_key = 'care-no-bits'
  ), 'aksi gagal tidak boleh menyisakan event yang memblokir retry';

  -- Tidur memakai nilai Energy saat mulai, jadi sync berkali-kali tidak
  -- menggandakan pemulihan. Tiga jam = setengah jalan; enam jam = penuh +5.
  update public.animas
     set care = '{"hunger":100,"energy":0,"hygiene":100,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now(),
         sleep_started_at = null,
         sleep_energy_at_start = null
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

  -- Bonus terawat tepat sekali per UTC day, tanpa Bond.
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
  -- 10 jam menghabiskannya. Cap 48 jam tetap memasukkan Dormant.
  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_score = 0,
         care_synced_at = now() - interval '2 hours',
         well_cared_on = (now() at time zone 'UTC')::date
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select (care->>'hunger')::numeric from public.animas where id = v_care_anima) = 80,
         'dua jam harus memotong Hunger 20 supaya Feed terasa';

  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now() - interval '8 hours'
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select (care->>'hunger')::numeric from public.animas where id = v_care_anima) = 20,
         'delapan jam harus memotong Hunger 80';

  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":0}'::jsonb,
         care_synced_at = now() - interval '18 hours'
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select (care->>'hunger')::numeric from public.animas where id = v_care_anima) = 0,
         'Hunger habis dalam 10 jam';

  -- Cap 48 jam memasukkan Dormant. EXP tetap. Dua Feed + dua Clean dari nol
  -- melewati ambang recovery 50 tanpa mengubah generation status=ready.
  update public.profiles set bits = 30 where id = u1;
  update public.animas
     set care = '{"hunger":100,"energy":100,"hygiene":100,"bond":40}'::jsonb,
         care_score = 99,
         care_synced_at = now() - interval '56 hours',
         dormant_since = null,
         well_cared_on = (now() at time zone 'UTC')::date
   where id = v_care_anima;
  perform public.apply_care(u1, v_care_anima, 'sync', null);
  assert (select dormant_since is not null from public.animas where id = v_care_anima),
         '48 jam decay efektif harus memasukkan Dormant';
  assert (select care_score from public.animas where id = v_care_anima) = 99,
         'masuk Dormant tidak boleh mereset EXP';
  assert (select status from public.animas where id = v_care_anima) = 'ready',
         'Dormant tidak boleh mencampur arti generation status';

  perform public.apply_care(u1, v_care_anima, 'feed', 'care-recover-feed-1');
  perform public.apply_care(u1, v_care_anima, 'feed', 'care-recover-feed-2');
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
    'ready', now() - interval '3 hours'
  )
  returning id into v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,sleep_started_at}') is not null,
         'Anima yang tidak di-Summon harus tidur';
  assert (v_j #>> '{anima,care,energy}')::numeric between 54.9 and 55.1,
         'tidur tiga jam di Collection harus memulihkan Energy';
  assert (v_j #>> '{anima,care_score}')::int = 0,
         'tidur di Collection tidak boleh memberi EXP tidur penuh';

  update public.animas
     set sleep_started_at = now() - interval '6 hours',
         sleep_energy_at_start = 10,
         care = '{"hunger":70,"energy":10,"hygiene":70,"bond":0}'::jsonb,
         care_synced_at = now() - interval '6 hours',
         care_score = 0
   where id = v_bench_anima;
  v_j := public.apply_care(u1, v_bench_anima, 'sync', null);
  assert (v_j #>> '{anima,sleep_started_at}') is not null,
         'tidur Collection tidak auto-bangun setelah enam jam';
  assert (v_j #>> '{anima,care,energy}')::numeric = 100,
         'Energy Collection penuh dalam enam jam';
  assert (v_j #>> '{anima,care_score}')::int = 0,
         'enam jam di Collection tidak boleh +5 EXP';

  v_j := public.apply_care(u1, v_bench_anima, 'summon', 'care-summon-bench');
  assert (v_j #>> '{anima,sleep_started_at}') is null,
         'Summon harus membangunkan companion baru';
  assert (select sleep_started_at is not null from public.animas where id = v_care_anima),
         'companion lama harus tidur saat yang lain di-Summon';
  assert (select active_anima_id from public.profiles where id = u1) = v_bench_anima,
         'Summon menulis companion aktif di server';
  perform public.apply_care(u1, v_care_anima, 'summon', 'care-summon-back');

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
  assert (v_j #>> '{reward,bits}')::int = 5, 'menang harus memberi 5 Bits';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 5,
         'saldo Bits dan response reward harus commit bersama';
  assert (select care_score from public.animas where id = v_battle_player)
           = v_score_before_battle + 4,
         'menang harus memberi care_score +4';
  assert (select battle_wins from public.animas where id = v_battle_player)
           = v_wins_before_battle + 1,
         'menang harus menaikkan battle_wins satu';
  assert (select count(*) from public.quota_ledger
           where ref_id = v_battle_session and currency = 'bits'
             and delta = 5 and reason = 'battle_win') = 1,
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
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle + 5,
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
  assert (v_j #>> '{reward,bits}')::int = 0
         and (v_j #>> '{reward,care_score}')::int = 0
         and (v_j #>> '{reward,battle_wins}')::int = 0
         and (v_j #>> '{reward,capped}')::bool,
         'win setelah cap harus menjadi Training tanpa progression reward';
  assert (v_j #>> '{session,daily_reward,rewarded}')::bool = false
         and (v_j #>> '{session,daily_reward,earned}')::int = 3,
         'payload Training harus menjelaskan bahwa session ini tidak dibayar';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle
         and (select care_score from public.animas where id = v_battle_player)
           = v_score_before_battle
         and (select battle_wins from public.animas where id = v_battle_player)
           = v_wins_before_battle,
         'Training tidak boleh mengubah Bits, care_score, atau battle_wins';
  assert (select count(*) from public.quota_ledger
           where ref_id = v_battle_session and reason = 'battle_win') = 0,
         'Training tidak boleh meninggalkan ledger reward palsu';
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
         and (v_j2 #>> '{reward,capped}')::bool,
         'retry Training harus replay response capped yang sama';
  assert (select bits from public.profiles where id = u1) = v_bits_before_battle,
         'retry Training tidak boleh membuat reward baru';

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
  delete from auth.users where id in (u1, u2);
  delete from public.species_library where species_key = v_spesies;
  raise notice 'SEMUA UJI LULUS';
end $uji$;
