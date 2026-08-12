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

  update public.animas set care = '{"hunger":100}'::jsonb where owner_id = u1;
  assert (select care->>'hunger' from public.animas
           where owner_id = u1 and nickname = 'uji anima') = '100',
         'aksi perawatan harus tetap bisa ditulis client tanpa round-trip server';

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
  delete from auth.users where id in (u1, u2);
  delete from public.species_library where species_key = v_spesies;
  raise notice 'SEMUA UJI LULUS';
end $uji$;
