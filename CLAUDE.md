# CLAUDE.md — konteks untuk AI coding agent

Baca file ini sebelum menyentuh kode Scanima. Update file ini setiap ada perubahan signifikan pada stack, konvensi, atau keputusan arsitektur.

## Apa itu Scanima

Game mobile virtual pet. Pemain memfoto objek nyata, foto itu jadi monster (**Anima**) lewat Vision LLM + image generation. Lalu dirawat gaya Tamagotchi, dievolusikan, dan dipakai bertarung. Panduan pemain (bukan spek) di [docs/wiki/](docs/wiki/README.md). Spek dan rumus di [README.md](README.md) dan [docs/](docs/).

## Aturan yang tidak bisa dinegosiasikan

1. **API key tidak pernah masuk ke build Godot.** Hanya ada satu, `REPLICATE_API_TOKEN`, dan ia hanya hidup di Supabase Edge Function secrets. Client Godot bicara ke Edge Function, bukan ke Replicate. Satu-satunya pengecualian adalah mode BYOK di mana token milik pemain sendiri disimpan lokal di device.
2. **Setiap panggilan image generation tetap dipagari sebagai biaya ~\$0.07.** Default-nya GPT Image 2 medium. Snapshot Replicate 13 Agustus 2026 mencantumkan auto $0.128, low $0.012, medium $0.047, dan high $0.128 per output image; generation medium terbaru terukur sekitar $0.05 per sheet, sementara dua run lama $0.068 dan $0.072. `pricing.mjs` sengaja tetap memakai $0.07 untuk spend cap konservatif sampai sampel production berulang membenarkan perubahan. Jangan pernah menulis kode yang bisa memanggil generation dalam loop, retry otomatis tanpa batas, atau tanpa idempotency key. Kalau ragu, jangan panggil.
3. **Semua mata uang bersifat server-authoritative.** Ada tiga: `scan_charges` (Discovery Scan), `genesis_cores` (spesies baru), `bits` (item perawatan). Client boleh menampilkan sisanya, tapi keputusan boleh-tidaknya generate hanya diambil di Postgres dalam transaksi yang sama dengan pencatatan debit. Jangan pernah menambah `genesis_cores` dari callback iklan. Keputusan produk yang belum diimplementasikan: pemain mendapat **1 Genesis Core gratis per minggu**, dan grant itu wajib server-authoritative + ledger-backed. Yang sudah final baru rate-nya; auto-credit versus claim, catch-up/cap, dan anti-abuse akun anonim masih harus diputuskan sebelum migrasi ditulis.
4. **Jangan commit foto pemain, output generation, atau `.env`.** Foto mentah dihapus dari Storage setelah post-processing selesai.

## Konvensi Godot / GDScript

- Godot 4.x, Mobile renderer, project 2D. Root project ada di `game/`.
- File script `snake_case.gd`, nama class `PascalCase`, node `PascalCase`.
- Type hints di mana-mana: `var hp: int = 0`, `func feed(amount: int) -> void:`.
- Referensi node lewat `@onready var sprite: AnimatedSprite2D = %AnimaSprite` (pakai unique name `%`, bukan path panjang yang gampang putus saat scene di-refactor).
- Cek validitas objek dengan `is_instance_valid()` sebelum akses, khususnya untuk node yang bisa di-free saat async request masih jalan.
- Semua state game yang persist lewat satu autoload `GameState`; jangan sebar `save()` ke banyak node.
- Sprite Anima **tidak** diimpor sebagai resource `.import` — datang saat runtime dari server, disimpan di `user://animas/`.
- Tiga autoload: `GameState` (pemilik `user://state.json`) lalu `Backend` (transport HTTP), kemudian `LocaleManager` (locale + formatter, tanpa persistence sendiri). Urutan dua pertama wajib: `Backend` menulis sesi ke `GameState`, `GameState` tidak pernah memanggil `Backend`. Yang mengorkestrasi tetap scene: `await Backend.ensure_session()`.
- Entry point-nya `scenes/scan_flow.tscn`: satu shell persisten yang meng-instance lima child scene `home_view`, `scan_view`, `battle_view`, `collection_view`, dan `anima_details_view`, plus `bottom_nav`. Urutan tab Home, Scan, Battle, Collection, Anima; seluruh tombol memakai ikon di atas label supaya lima target 96px muat. Tab tidak memakai `change_scene_to_file()`, supaya request, pending scan/care/battle, Stage, dan inkubator tidak di-reset saat pemain berpindah layar. `scenes/anima_demo.tscn` tetap alat periksa art yang dipanggil eksplisit.
- `Backend.gd` satu-satunya tempat yang tahu URL project dan kunci. Kuncinya **publishable** (`sb_publishable_...`) dan memang ikut ke dalam build; yang membatasi akses RLS, bukan kerahasiaannya. Terukur diterima kelima endpoint yang dipakai client: `auth/signup`, `auth/token`, REST, Storage, dan `functions/v1`. Yang tidak boleh masuk ke sana sampai kapan pun: `REPLICATE_API_TOKEN` atau service role key.
- Yang persist hanya sesi, scan yang sedang berjalan, satu `pending_care`, dan satu `pending_battle` berisi session/turn/version + intent + idempotency key. Saldo, kebutuhan, dan daftar Anima **selalu** dibaca ulang dari Postgres — server yang berwenang. Pending intent dihapus hanya setelah server menjawab; timeout/restart me-replay key yang sama supaya Bits, damage, atau reward tidak commit dua kali.

## Konvensi backend

- Supabase Edge Functions berjalan di Deno. Pakai `npm:` specifier hanya untuk paket pure-JS/TS. **Jangan pakai `sharp`** (butuh native binary, tidak jalan di edge runtime); untuk manipulasi piksel pakai `ImageScript`.
- **`npm:imagescript` GAGAL di edge runtime** dengan galat arch/platform tidak didukung, walaupun paketnya pure-JS. Yang jalan adalah `https://deno.land/x/imagescript@1.2.15/mod.ts` lewat `functions/import_map.json`. Node di-pin ke `imagescript@1.2.15` supaya dua runtime memakai versi yang sama; jangan naikkan salah satunya sendiri.
- **Kode yang dipakai dua runtime hidup di `functions/_shared/` sebagai `.mjs`**, bukan disalin ke masing-masing sisi: `postprocess.mjs` (keying + slicing), `vision.mjs` (parsing, gate, perakitan prompt), `pricing.mjs` (harga per panggilan), dan `battle.mjs` (seluruh formula combat). Deno bisa mengimpor `.mjs` apa adanya, dan eval mengimpor file yang sama. Dua salinan berarti eval bisa lulus sementara produksi memakai aturan lain.
- **Tidak ada endpoint unggah foto.** Client menulis langsung ke bucket `photos` dengan anon key-nya; yang membatasinya adalah policy Storage (`(storage.foldername(name))[1] = auth.uid()`) plus `file_size_limit` dan `allowed_mime_types` milik bucket. `create_anima` hanya menerima `photo_path` dan memeriksa prefix-nya. Menulis endpoint penerbit signed URL berarti menulis ulang pagar yang sudah disediakan platform.
- Satu jalur uang: `claim_genesis` (debit Core + baris generation + baris anima + ledger, satu transaksi) dan `record_cache_hit` (art gratis dari pustaka). `claim_generation` yang lama **sudah di-drop** — dua fungsi yang dua-duanya bisa mendebit Core berarti dua tempat yang harus benar.
- Migrasi SQL di `backend/supabase/migrations/`, satu file per perubahan, tidak pernah diedit setelah di-apply ke remote.
- RLS wajib aktif di semua tabel yang menyimpan data pemain. Edge Function pakai service role key, client pakai anon key.
- Semua endpoint yang menghabiskan uang menerima `idempotency_key` dari client.
- Proyek remote: **Scanima**, ref `kgcaisvmmpxswevjvgft`, region `ap-northeast-1`, Postgres 17. Empat migrasi pertama di-apply lewat Supabase MCP, dan nama file lokal sengaja disamakan dengan versi yang dicatat remote supaya `supabase migration list` tidak melihat drift. Kalau apply lewat MCP lagi, samakan lagi nama filenya sesudahnya.
- Migration Battle `20260813103446_battle_vertical_slice`, indeks bot `20260813105258_index_battle_bot_anima`, cap reward `20260813174007_limit_daily_battle_rewards`, indeks unik ledger `20260813174454_index_battle_reward_ledger_ref`, perbaikan status `20260813180241_refine_battle_reward_status`, guard Energy `20260813193612_require_battle_energy`, decay realtime + biaya Energy Battle `20260813195613_decay_realtime_and_battle_energy`, EXP/Level tanpa Bond `20260813201820_exp_level_growth`, gerbang Feed/Clean penuh `20260813220036_reject_full_feed_clean`, dan tidur Anima yang tidak di-Summon `20260813220954_bench_unsummoned_sleep` + `20260813221113_apply_care_bench_summon` + Energy bangku 3 jam `20260813224221_bench_sleep_faster` + gerbang Hunger Battle `20260814043053_reject_hungry_battle` sudah live. `apply_care()` menolak Hunger/Hygiene >= 99.5 dengan `NEED_FULL`. `Summon` menulis `profiles.active_anima_id` dan menidurkan sisanya. `battle_anima` version 9 ACTIVE dengan `verify_jwt=true` dan `ANIMA_HUNGRY: 409`; snapshot player/bot membawa `level` dari `care_score`, plus `strike_name`/`surge_name`, dan `createFighter` memakai growth multiplier. Error boundary tetap membaca `message` dari object PostgREST, bukan hanya instance `Error`; tanpa itu exception RPC yang dikenal jatuh menjadi 500 generik. Probe SQL production membuktikan win ketiga dibayar dan win keempat menjadi Training tanpa satu pun mutation progression; harness transport `live_battle.gd` lama yang tertahan oleh sesi uji `Invalid Refresh Token: Already Used` bukan kegagalan formula atau migrasi.
- **Fungsi yang menyentuh mata uang wajib dicabut EXECUTE-nya dari `anon` dan `authenticated`.** Postgres memberi EXECUTE ke PUBLIC secara default, jadi fungsi SECURITY DEFINER di schema `public` otomatis menjadi endpoint di `/rest/v1/rpc/<nama>`. Untuk `refund_generation` itu berarti pemain bisa mengembalikan Core-nya sendiri sementara gambarnya tetap kita bayar. Pola yang dipakai: `revoke all ... from public, anon, authenticated` lalu `grant execute ... to service_role`.
- Hak tulis client diberikan **per kolom**, bukan per tabel: `revoke update on <tabel>` lalu `grant update (<kolom yang boleh>)`. Dengan begitu kolom baru di masa depan otomatis tertutup. Ingat bahwa `revoke update on <tabel>` juga mencabut hak kolom, jadi sesudahnya hak kolom harus diberikan ulang.

## Prompt versioning

Prompt hidup di `backend/prompts/<version>/` sebagai file teks, bukan string literal di dalam kode:

```
backend/prompts/
├── v1/
│   ├── vision_system.md          # system prompt untuk Vision LLM
│   ├── vision_schema.json        # responseSchema Gemini (subset OpenAPI, bukan JSON Schema penuh)
│   ├── sprite_sheet.md           # baseline nano-banana-pro
│   └── sprite_sheet_evolve.md    # varian untuk evolusi, pakai sprite lama sebagai image_input
├── v2/
│   ├── vision_system.md          # gate yang sama dengan v1
│   ├── vision_schema.json        # kontrak yang sama dengan v1
│   ├── sprite_sheet.md           # GPT Image 2 medium + anime cel-shaded style
│   └── sprite_sheet_evolve.md
├── v3/                           # predecessor: v2 + blok BRAND MARKS
│   ├── vision_system.md          # identik v2
│   ├── vision_schema.json        # identik v2
│   ├── sprite_sheet.md           # logo merek diganti marking ciptaan
│   └── sprite_sheet_evolve.md
├── v4/                           # predecessor: material + damage
│   ├── vision_system.md          # + surface_finish dan damage_hints
│   ├── vision_schema.json        # material/damage nullable, cache key tetap
│   ├── sprite_sheet.md           # permukaan polos; damage wajib sesuai material
│   └── sprite_sheet_evolve.md
├── v5/                           # predecessor candidate: karakter + body plan
│   ├── vision_system.md          # + karakter, limb plan, larangan suffix -mon
│   ├── vision_schema.json        # presentation nullable, cache key tetap
│   ├── sprite_sheet.md           # Idle non-angry; tubuh mengikuti objek
│   └── sprite_sheet_evolve.md    # presentation + zero-limb tetap dipertahankan
├── v6/                           # predecessor candidate: facing lock kiri
│   ├── vision_system.md          # identik v5; species cache key tidak berubah
│   ├── vision_schema.json        # identik v5
│   ├── sprite_sheet.md           # v5 + facing lock empat pose ke canvas-left
│   └── sprite_sheet_evolve.md    # facing lock dipertahankan lintas evolusi
├── v7/                           # DEFAULT production: sheet 3x3 + nama move
│   ├── vision_system.md          # v6 + strike_name / surge_name dua kata; species_key tetap
│   ├── vision_schema.json        # dua field move, cache key tidak berubah
│   ├── sprite_sheet.md           # sembilan sel: 7 pose karakter + 2 efek battle
│   └── sprite_sheet_evolve.md    # grid 3x3 dipertahankan lintas evolusi
└── v8/                           # predecessor candidate: facing lock kolom kiri
    ├── vision_system.md          # identik v7; species cache key tidak berubah
    ├── vision_schema.json        # identik v7
    ├── sprite_sheet.md           # v7 + anti-inward facing pada Idle/Happy/Damaged
    └── sprite_sheet_evolve.md    # facing lock kolom kiri dipertahankan lintas evolusi
```

**Prompt tidak bisa dibaca sebagai file di Edge Function.** `Deno.readTextFile()` gagal untuk file pendamping yang dideploy lewat MCP, jadi `backend/tools/bundle_prompts.mjs` membundel semua versi menjadi `functions/_shared/prompts.generated.ts` yang diimpor sebagai modul. Sumbernya tetap file `.md` di git; artefaknya turunan. Setelah mengubah prompt: `node backend/tools/bundle_prompts.mjs`. Skenario 17 di `npm run selftest` gagal kalau bundelnya basi, jadi kelupaan ketangkap gratis, bukan saat art produksi ternyata berbeda dari art yang sudah disetujui.

`vision_schema.json` **tidak** dikirim sebagai parameter API — ia disisipkan ke `system_instruction`, sebab wrapper Gemini di Replicate tidak punya `response_schema`. Notasinya tetap subset OpenAPI (`"nullable": true`, bukan `["string", "null"]`, tanpa `pattern`) supaya file yang sama bisa langsung dipakai kalau nanti pindah ke Gemini API langsung. Bentuk data ditegakkan `extractJson()` dan `validateVision()` di `backend/supabase/functions/_shared/vision.mjs`, bukan diharapkan dari model.

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md) dan sumber art direction v2 ada di [docs/monster_camera_anime_cel_shaded_style_guide.md](docs/monster_camera_anime_cel_shaded_style_guide.md). Jangan mengarang aturan style baru; konsistensi visual antar Anima bergantung pada style lock itu.

**Larangan negatif saja tidak menghapus logo merek, tapi instruksi pengganti v3 juga punya efek samping.** v2 sudah memuat "no logos, brand names" dan GPT Image 2 tetap menggambar swoosh Nike karena logonya datang dari `input_images`. v3 menghilangkannya dengan meminta permukaan polos atau marking geometris ciptaan sendiri; itu lolos satu uji sepatu dan menjaga `species_key`, tetapi model lalu mengarang emblem mirip logo bahkan pada objek tanpa logo. v4 menghapus pilihan marking itu seluruhnya: logo/teks/sigil dianggap tidak ada dan tempatnya selalu material polos yang setia pada objek.

**Damage v3 bias robot bukan kebetulan model.** Template universalnya sendiri menyebut `loose cable`, `exposed wire`, dan `broken key`, sementara style lock memberi semua objek bahasa `techno-organic`; material Vision tidak pernah sampai ke prompt gambar. v4 menambah `surface_finish` + `damage_hints` ke Vision dan menyaring hint teknis di `assemblePrompt()`: kata cable/wire/circuit/key hanya lolos jika fitur yang sama benar-benar ada di `signature_features`. Keramik retak/terkelupas, kain berjumbai/robek, tanaman sobek/layu, logam penyok/tergores.

**V7 adalah default production.** V7 membawa seluruh pagar v6, lalu mengubah layout sheet dari 2×2 (4 pose) menjadi 3×3 (9 sel): Idle, Battle, Sleep, Happy, Hungry, Dirty, Damaged, plus efek `fx_strike` / `fx_surge` tanpa tubuh kreatur. Vision menambah `strike_name` dan `surge_name` per Anima (tepat dua kata Inggris pendek, dipotong di `normalizeMoveName()` kalau model mengabaikan); keduanya **bukan** bagian `species_key`, jadi cache art lama tetap kena. Post-process memilih grid dari `prompt_version` (>= v7 = 3×3, selain itu 2×2) supaya pustaka production tidak pecah. Canvas tetap 1024×1024 (~341 px per sel, turun dari 512). Sheet cache 2×2 tetap dimuat; pose ekstra dan overlay FX diabaikan kalau tidak ada. v3–v6 tetap di git untuk rollback. **v8 adalah predecessor candidate**: Vision identik v7; yang berubah hanya facing lock di kolom kiri (Idle/Happy/Damaged) supaya sel tidak menoleh ke tengah sheet. Jangan promote ke `app_config` sebelum eval visual lulus.

## Fakta teknis yang mudah salah

- **Sign-in anonim mati secara default, dan Scanima tidak punya layar login.** Identitas pemain adalah user anonim yang dibuat saat app pertama kali jalan; `handle_new_user` yang mengisi profil beserta 8 scan charge, 3 Core, dan 30 Bits awalnya. Dengan setelan default project, `POST /auth/v1/signup` menjawab `anonymous_provider_disabled` dan app mati di detik pertama — bukan di jalur yang mahal, jadi tidak ada test berbayar yang akan menangkapnya. Sudah dinyalakan di remote dan dideklarasikan di `backend/supabase/config.toml` (`enable_anonymous_sign_ins = true`) supaya ia tidak jadi setelan hantu yang hanya hidup di dashboard. Batas bawaannya 30 sign-in anonim per jam per IP; itu pagar abuse, bukan angka yang perlu dinaikkan sampai ada bukti pemain nyata kena.
- **`species_library` hanya bisa dibaca peran `authenticated`, dan anon key mentah menjawab `[]`, bukan galat.** Client harus sign-in anonim **sebelum** membaca pustaka. Gejala salahnya berbahaya karena tidak terlihat seperti masalah autentikasi: array kosong terbaca sebagai "pustaka masih kosong", jadi setiap scan tampak sebagai spesies baru dan setiap scan membayar $0.07. Terukur saat mengambil manifest untuk uji Godot — anon key memberi nol baris untuk baris yang jelas ada.
- **Bucket `photos` hanya punya policy INSERT, dan itu lengkap.** Client boleh menaruh foto di foldernya sendiri, tapi tidak boleh membaca, melihat daftar, maupun menghapus — DELETE dari client dijawab RLS dengan 403. Terlihat seperti policy yang lupa ditulis; sebenarnya client tidak pernah membutuhkannya. Yang membaca foto adalah Edge Function lewat signed URL service role, dan yang menghapusnya adalah `create_anima`/`finalize_sheet` setelah post-processing selesai. Menambahkan SELECT berarti memberi jalan membaca foto yang seharusnya sudah lenyap.
- **Care sepenuhnya server-authoritative.** `care`, `care_synced_at`, `care_score` (EXP pemain), sleep, counter harian, Dormant, dan debit Bits berubah hanya lewat `apply_care()` di balik Edge Function JWT `care_anima`. Feed/Clean masing-masing 5 Bits; event + ledger + kebutuhan diubah dalam satu transaksi dan satu idempotency key. `apply_care()` menolak Feed/Clean dengan `NEED_FULL` kalau Hunger/Hygiene setelah decay >= 99.5, bukan 100, supaya meter yang tampil penuh (99.99 atau sisa decay beberapa menit) tidak mendebit Bits. Client meredupkan tombol yang sama dan toast `ERROR_NEED_FULL` tanpa request. Client hanya boleh PATCH `nickname`. Wire tetap `care_score`; UI bilang EXP/Level. `level = 1 + floor(exp / 5)`, cap 40; Adult di 16, Evolved di 36. Jangan menaikkan `animas.stage` sebelum art evolusi ada.
- **Respons care dipisah menjadi intent instan dan commit server.** `scan_flow` memanggil `AnimaPresenter.care_feedback()` sebelum `await care_anima` dan hanya mengunci Care Dock; meter, Bits, sleep, serta `care_score` tetap berubah sesudah row authoritative kembali. Feed memberi satu hop, Play memakai pose Happy plus enam bounce selama ~2,5 detik, naik level dan menang Battle juga Happy, Hungry/Dirty mengikuti kebutuhan, dan pose visual Damaged (`defeated`) melakukan heavy breathing loop selama Dormant. Semua berhenti/diam saat `UiMotion.reduced_motion` aktif. Edge Function mempertahankan `verify_jwt = true` dan memakai `getClaims()` pada satu admin client per isolate supaya JWT ES256 diverifikasi lewat cache JWKS, bukan round-trip `getUser()` pada setiap tap. Jangan menggantinya dengan decode JWT tanpa verifikasi.
- **Battle vertical slice sepenuhnya server-authoritative.** Formula tunggal hidup di `_shared/battle.mjs`; client hanya mengirim `strike`/`surge`/`guard` lalu menganimasikan ordered event log. `battle_sessions` menyimpan state/version dengan TTL 30 menit dan satu active session per owner; `battle_turns` menyimpan `(session, turn, idempotency_key)` untuk replay. Menang memberi tepat 5 Bits, `care_score +4`, `battle_wins +1` dalam transaksi yang sama; loss/forfeit nol reward dan tidak pernah menyentuh Genesis Core. Anima pemain wajib `ready`, bangun, tidak Dormant, punya **Energy >=20**, dan **Hunger >=40** (ambang pose Hungry) untuk memulai Battle maupun Training. `start_battle()` memanggil `apply_care(..., 'sync')` sebelum guard Energy/Hunger, lalu **memotong 20 Energy** pada session baru. Hunger rendah menolak dengan `ANIMA_HUNGRY`; client meredupkan Battle/Train seperti Energy. Resume session aktif tidak memotong lagi. Client hanya preflight dari roster. Session aktif tidak dibatalkan di tengah duel. Bot adalah snapshot anonim Anima `ready` pemain lain; jangan kirim `owner_id` atau nickname. Snapshot membawa `level` dari `care_score`; stats memakai `growthMultiplier(level)`, bukan `stageMultipliers`, sampai art evolusi live. Matching bot tetap ±15% `base_stats`.
- **Hanya tiga kemenangan Battle pertama per akun per hari UTC yang memberi progression reward.** Sesudah itu duel tetap bisa dimainkan sebagai Training, tetapi Bits, `care_score`, dan `battle_wins` semuanya nol—membatasi Bits saja memindahkan exploit ke gerbang evolusi. Counter authoritative bukan kolom baru: `battle_daily_reward_status()` menghitung semua ledger dengan `reason = 'battle_win'` hari ini, tanpa mengikat counter ke nominal 5 Bits, sedangkan `commit_battle_turn()` memegang profile row lock agar check + saldo + score + win + ledger tetap atomik. Angka 3 hidup di `app_config.battle_rewarded_wins_per_day`; jangan jadikan cap per-Anima karena pemain cukup mengganti companion. Session payload dan operasi `battle_anima/status` membawa `daily_reward` (`earned/limit/remaining/server_now/reset_at/rewarded`). Lobby memakai satu CTA—`Battle` sebelum cap, `Train` setelah cap—beserta alasan dan reset 00:00 UTC; kemenangan ketiga tetap `Rewards 3/3`, Training baru session berikutnya. Timer memakai selisih dua timestamp server dan refresh lagi saat app resume, bukan mempercayai jam device.
- **Copy Battle memakai Attack/Special/PP, sementara wire value tetap `strike`/`surge`/`guard`/`momentum`.** Keduanya sengaja tidak disamakan. Wire value terpasang di CHECK constraint `battle_turns_action_valid`, di kolom `player_momentum`/`bot_momentum`, di `BATTLE_ACTIONS`, dan di `GameState.pending_battle` yang bisa sedang tersimpan di device pemain — menyeragamkannya dengan istilah UI berarti migrasi plus memecahkan session yang sedang berjalan, demi nol perubahan yang dilihat pemain. Identifier client (`MOMENTUM_MAX`, `SURGE_COST`) ikut nama server supaya masih bisa di-grep lintas runtime; kata player-facing hanya hidup di `locales/ui.csv`. Counter PP hidup **hanya** di tombol Special (`{surge_name} 3/3`, fallback `Special`); tombol Attack memakai `strike_name`. Label header yang mengulanginya sudah dihapus karena angka yang jauh dari tombolnya terbaca sebagai angka tanpa sebab. `startBattle` wajib `select` kolom `strike_name`/`surge_name` — menulisnya ke snapshot dari row yang tidak membacanya menghasilkan string kosong dan tombol jatuh ke Attack/Special. Kedua meter HP dicerminkan mengikuti konvensi Street Fighter: **sisa HP memeluk tengah arena dan damage memakan dari tepi luar layar ke dalam**, jadi bar pemain memakai `fill_mode = FILL_END_TO_BEGIN` dan bar bot memakai default `FILL_BEGIN_TO_END`. Versi kebalikannya terasa lebih intuitif ketika ditulis (sisa HP memeluk tepi luar, kosong bertemu di tengah) dan sudah dicoba lalu ditolak dengan referensi gambar: bukan itu yang dilakukan fighting game, dan pemain membacanya sebagai arah yang terbalik. Kalau ragu, ukur ulang piksel screenshot-nya, jangan menyimpulkan dari nama `fill_mode`-nya.
- **PP adalah budget per-battle, bukan meter yang mengisi sendiri.** Mulai penuh 3, Special memakan 1, dan **tidak ada regen per-turn** — satu-satunya pemulihan adalah Guard di `applyIntent()`. Jangan mengembalikan regen +1/turn: satu battle terukur selesai sekitar empat turn, jadi regen membuat PP membeku di angka awalnya, counter di tombol tidak pernah bergerak, dan Attack jadi tombol mati karena Special selalu tersedia sekaligus selalu lebih kuat. Karena PP hanya pulih lewat Guard, layar **wajib** menyebutkan jalan keluarnya saat PP habis (`BATTLE_NO_MOMENTUM` di `BattleFeedback`); tombol mati tanpa kalimat itu adalah versi baru dari kebingungan yang justru sedang diperbaiki. `MOMENTUM_MAX`/`SURGE_COST` hidup di dua tempat yang wajib identik, `_shared/battle.mjs` dan `battle_view.gd`, sebab client yang lebih longgar akan menyalakan Special yang lalu ditolak server sebagai `NO_MOMENTUM` — mengubah salah satunya berarti `supabase functions deploy battle_anima` di langkah yang sama. **PP juga sengaja tidak persist antar battle**; alasannya beserta empat konsekuensi yang diukur dari kode ada di [docs/04](docs/04-game-systems-economy.md), jadi jangan mengubahnya jadi PP gaya Pokémon tanpa membaca itu dulu.
- **Initiative Battle mengikuti SPD, bukan selalu pemain dulu.** Ordered event log boleh dimulai bot jika SPD-nya lebih tinggi; client wajib mengumumkan kedua angka sebelum animasi supaya ini terbaca sebagai aturan, bukan event terbalik. Semua sprite sheet dihasilkan menghadap forward-left: petarung pemain di sisi kiri harus `flip_h`, bot di kanan tidak, dan arah lunge mengikuti lawan. Loading art Battle tidak boleh memakai toast global milik Home/Scan. Result win/loss/forfeit menimpa footer berukuran tetap, bukan menjadi sibling `BattleContent`, supaya arena dan kaki kedua petarung tidak bergeser saat result muncul.
- **VFX Attack/Special adalah overlay tambahan, bukan ganti pose.** `set_pose("attack")` tetap menampilkan tubuh; `play_fx("fx_strike"|"fx_surge", impact_global)` menaruh sel efek sebagai sibling di bawah anchor petarung lalu meluncurkannya cepat ke tubuh lawan. Tanpa `impact_global` overlay tetap di tempat (uji/sheet 2×2). Sheet 2×2 tanpa sel itu melewati `play_fx` diam-diam.
- **Arena adalah fokus tunggal layar Battle aktif.** Header `Battle Arena` + subtitle hanya tampil di lobby. Saat session aktif, turn/reward, Forfeit, dan fighter HUD menjadi overlay di bagian atas arena; footer hanya memuat feedback satu baris dan tiga aksi 96px. Fighter HUD adalah satu strip versus tanpa `PanelContainer` per monster: identity kiri/kanan, HP mirrored menuju tengah, dan nilai authoritative `current / max` di atas bar. Forfeit tetap punya hit area 96px tetapi tampil sebagai teks datar, bukan panel merah besar. Result berukuran 236px tumbuh ke atas dari footer sehingga muat tanpa mendorong arena atau tertutup bottom nav. Counter `Rewards x/3` hanya tampil pada Battle berhadiah dan dijepit ke limit; Training tidak menampilkan `3/3` karena Training sendiri tidak terbatas. Saat hit, `Super effective!`/`Not very effective.` memakai Oxanium ExtraBold besar dengan outline + glow, tanpa box, border, atau garis samping, di ruang kosong tepat di bawah fighter HUD. Tilt/pop, warna, damage punch, dan haptic dibaca dari `element_multiplier` event server. Reduced Motion mempertahankan informasinya tanpa animasi, dan client tidak menduplikasi roda elemen.
- **Pending Battle bertahan sampai response authoritative.** `GameState.pending_battle` tetap menyimpan action/key ketika timeout atau app mati. Startup me-resume session lalu me-replay key yang sama jika action belum terkonfirmasi. Hanya Care Dock/Battle action yang dikunci saat request; tab lain tetap bisa dibuka karena shell persisten. Saat pemain memilih aksi, tombol itu langsung mendapat underline pulse dan copy `Attack locked in`/`Special charged`/`Guard up`; tombol lain diredupkan dan input ketiganya diabaikan tanpa memakai visual disabled. Ini feedback command, bukan prediksi damage atau initiative—event server tetap satu-satunya hasil turn. Session terminal menghapus pending state.
- **Play tidak ditutup Bond.** Meter Bond hilang dari UI; JSON menulis `bond: 0`. Anti-farm Play adalah Energy -5 dan +1 EXP maksimal lima kali per UTC day. Care Dock bangun selalu empat kolom satu baris (Feed/Clean/Sleep/Play); jangan wrap 2×2. Label Play tetap `Play` tanpa `x/y`. Saat cap harian tercapai, atau Hunger/Hygiene tampil penuh, tombolnya hanya redup — Godot menelan `pressed` kalau `disabled` — dan tap memunculkan toast tanpa request care. Saat tidur Feed/Clean/Play disembunyikan dan Wake memakai lebar penuh.
- **Decay tidak butuh cron.** `apply_care()` menghitung selisih dari `care_synced_at`: cap 48 jam, Hunger 10/jam, Energy 7,1/jam saat bangun, Hygiene 4,2/jam. Tidak ada grace — sync yang sering tetap memotong kebutuhan, supaya Feed/Clean terasa. Sleep memulihkan Energy linear sampai penuh dalam 6 jam; Hunger dan Hygiene tetap turun selama tidur. Anima yang **tidak di-Summon** ikut tidur (Energy pulih dalam 3 jam, tanpa auto-bangun, tanpa +5 EXP) supaya Collection tidak jadi mesin EXP. Collection menampilkan Idle begitu Energy penuh supaya pemain tahu Anima itu siap di-Summon; row Postgres tetap tidur. Client memasang satu `Timer` dari selisih dua timestamp server (`care_synced_at - sleep_started_at`) lalu sync tepat di batasnya; resume Android/iOS juga memicu sync, jadi jam device tidak dipercaya dan background tidak membuat Anima tertahan tidur. `dormant_since` terpisah dari generation `status`, **tidak** mereset EXP, dan hilang setelah Hunger serta Hygiene sama-sama >=50.
- **Art cache tidak boleh menebak pose saat cold start.** `GameState.last_anima` hanya pilihan terakhir dan sengaja tidak menyimpan care. Menampilkan sheet itu sebelum roster server datang selalu memulai Idle, sehingga Anima tidur terlihat bangun sekelebat. Sprite tetap tersembunyi sampai `_present()` memiliki row authoritative dan menerapkan Sleep/Dormant pada frame yang sama.
- **`rls_auto_enable()` bukan buatan kita.** Ia event trigger bawaan bootstrap Supabase yang menyalakan RLS otomatis pada setiap tabel baru di `public`. Terukur: peran `authenticated` bisa memanggilnya sebagai fungsi biasa dan ia selesai tanpa error maupun efek (`pg_event_trigger_ddl_commands()` kosong di luar konteks trigger). EXECUTE-nya sudah dicabut di migrasi `harden_platform_rls_helper`, dan event trigger-nya diverifikasi tetap menyala sesudahnya — hak eksekusi event trigger diperiksa saat `create event trigger`, bukan saat ia menyala.
- **Advisor `rls_enabled_no_policy` pada `app_config`, `care_events`, `battle_sessions`, dan `battle_turns` itu disengaja.** RLS aktif tanpa policy sama sekali adalah cara menutup tabel dari client; jangan "perbaiki" dengan menambahkan policy baca. Tabel event/session internal hanya diakses transaction function service-role.
- **Enam WARN `auth_allow_anonymous_sign_ins` juga disengaja, dan "memperbaikinya" akan mematikan game.** Advisor memberi peringatan untuk `profiles`, `animas`, `generations`, `quota_ledger`, `pending_discoveries`, dan `species_library` karena policy-nya `to authenticated`, dan user anonim memakai peran itu. Di Scanima user anonim **adalah** pemainnya — bukan tamu yang menyusup. Yang membatasi tetap `auth.uid() = owner_id`, jadi pemain anonim A tidak bisa membaca data pemain anonim B; `species_library` memang dibaca semua orang karena ia pustaka art bersama. Menambahkan `and not (auth.jwt() ->> 'is_anonymous')::boolean` akan menutup satu-satunya jenis akun yang dimiliki game ini.
- **Satu INFO performa dibiarkan sadar:** `generations.anima_id` tanpa indeks penutup. Ia hanya menyakitkan saat baris `animas` dihapus, dan itu jalur langka; tambahkan indeksnya kalau fitur melepas Anima jadi rutin. Foreign key `battle_sessions.bot_anima_id` sudah punya indeks penutup sendiri.

- **Setiap request terautentikasi memeriksa umur token, bukan hanya saat boot.** `Backend._send()` memanggil `ensure_session()` sebelum mengirim, mengganti header dengan token terbaru, lalu memberi satu bounded refresh+retry jika gateway masih menjawab 401. Ini mencegah Battle panjang mati tepat saat access token habis. Refresh token yang ditolak tetap tidak boleh dijawab dengan sign-in anonim baru: itu akan meninggalkan seluruh Anima di akun yang tidak bisa dijangkau lagi.
- **Node autoload SUDAH ada dalam mode `--script`, tetapi nama globalnya belum.** Menulis `GameState` di skrip yang dijalankan `--script` gagal saat kompilasi dengan `Identifier not found`, sebab skrip itu dikompilasi sebelum autoload terdaftar sebagai global — sementara node-nya sendiri terpasang di bawah root dan bisa diambil dengan `get_root().get_node("GameState")`. Itu yang dipakai `tests/test_client_state.gd`, `tests/live_scan.gd`, dan `tests/live_battle.gd`. Konstanta dan fungsi statis diambil dari `get_script()`, bukan dari instance-nya.
- **Skrip `--script` jalan lebih awal daripada saat node autoload benar-benar masuk tree.** `HTTPRequest` yang ditambahkan di titik itu menolak dengan `ERR_UNCONFIGURED` (`Condition "!is_inside_tree()" is true`). Satu `await process_frame` di awal harness menyelesaikannya; scene sungguhan tidak pernah kena karena `_ready()` jalan setelah tree berdiri.
- **`CameraServer` SUDAH mendukung Android sejak setelah 4.4, dan tetap bukan yang dipakai.** Catatan lama di file ini salah; dokumentasi stable kini menyebut `CameraFeed` terimplementasi di Linux, Android, macOS, dan iOS. Alasan tidak memakainya bukan ketiadaan API: ia memberi feed hidup, sementara yang dibutuhkan satu jepretan, jadi memakainya berarti membangun sendiri UI fokus, eksposur, dan tombol jepret yang sudah gratis dari aplikasi kamera OEM — dengan frame preview yang resolusinya di bawah kamera still-nya. Ia juga masih berdarah: PR #110720 baru memperbaiki stride `YUV_420_888` yang mengacaukan gambar di perangkat dengan padding, dan issue #114468 mencatat pergantian feed rusak sejak fitur ini lahir.
- **Kamera lewat `addons/GodotGetImage` ([fork PhotoPicker](https://github.com/cenullum/GodotGetImagePlugin-Android-PhotoPicker)), dan `.aar`-nya ikut di-commit.** Fork, bukan upstream, karena manifest upstream menyuntikkan `READ_MEDIA_IMAGES` ke APK **walau `getGalleryImage()` tidak pernah dipanggil** — Godot menggabungkan manifest plugin saat export — dan Play menolak izin itu untuk keperluan pilih-satu-foto. Manifest fork sudah diperiksa: hanya `CAMERA`, `minSdkVersion` 21, kamera ditandai opsional. Arsipnya 27 KB dan prebuilt untuk 4.6.2 persis, jadi tidak ada langkah Gradle; ia di-commit supaya build tetap reproducible kalau repo pihak ketiganya hilang. Plafonnya: `.aar` terikat versi Godot, jadi naik versi engine berarti menunggu atau membangun ulang arsip yang cocok.
- **`resendPermission()` ada di README plugin tapi `private` di `.aar` yang dirilis.** Memanggilnya dari GDScript gagal saat runtime. Terverifikasi lewat `javap` pada `classes.jar`: yang publik hanya `setOptions`, `getGalleryImage`, `getGalleryImages`, `hasCamera`, `getCameraImage`. Pemulihan setelah izin ditolak adalah memanggil `getCameraImage()` lagi — permintaan izinnya menempel di sana — jadi UI harus menyuruh pemain menekan tombolnya sekali lagi, bukan memanggil metode yang tidak ada.
- **Ketiga signal plugin membawa argumen, termasuk yang izin.** Dari bytecode `getPluginSignals()`: `image_request_completed(Dictionary)`, `error(String)`, dan `permission_not_granted_by_user(String)` — yang terakhir tidak terbaca demikian dari README. Arity yang salah membuat `connect` gagal dan handler-nya tidak pernah terpanggil, tanpa galat yang jelas.
- **Tombol foto TIDAK dikunci saat kamera terbuka.** Kamera itu Activity terpisah dan pembatalan tidak memancarkan signal apa pun, jadi kunci yang dipasang saat permintaan dikirim akan mati selamanya bagi pemain yang berubah pikiran. Kuncinya dipasang di `_scan_bytes`, saat byte-nya sudah ada.
- **Izin `INTERNET` MATI secara default di ekspor Android Godot 4, dan ini kegagalan yang paling mahal waktunya.** APK pertama yang dibangun di sini keluar dengan `CAMERA` sebagai satu-satunya izin: ia terpasang, terbuka, lalu mati di sign-in anonim — tanpa dialog izin, tanpa crash, cuma galat jaringan yang menyesatkan, sebab Android menolak socket-nya secara senyap. Preset **wajib** memuat `permissions/internet=true`. `export_presets.cfg` di-gitignore, jadi tidak ada uji di repo yang bisa menjaga ini; catatan ini adalah pagarnya, dan `aapt2 dump permissions` sesudah build adalah pemeriksaannya.
- **Terverifikasi pada APK sungguhan: tepat dua izin, `INTERNET` dan `CAMERA`.** Nol `READ_MEDIA_IMAGES`, nol `READ_EXTERNAL_STORAGE` — jadi pilihan fork PhotoPicker terbukti di artefak akhir, bukan cuma di manifest sumbernya. Kelas `GodotGetImage` juga terkonfirmasi ada di `classes.dex`. Periksa keduanya setiap kali plugin atau versi engine berubah; manifest yang ter-merge tidak membuktikan kodenya ikut.
- **Template Android 4.6.2 mematok Gradle 8.11.1, jadi JDK-nya tidak boleh lebih baru dari 23.** Mesin ini punya JDK 26 dan build-nya berhenti di `Unsupported class file major version 70` sebelum menyentuh kode kita. Yang dipakai: `brew install openjdk@17` — **formula, bukan cask `temurin@17`**, sebab cask memasang ke `/Library/Java/...` dan menuntut sudo sementara formula tidak. JDK 26 **tidak** perlu dihapus walau banyak jawaban forum menyuruhnya: Godot punya setelan `Java SDK Path` sendiri, jadi keduanya hidup berdampingan. Alternatif menaikkan `distributionUrl` di `gradle-wrapper.properties` menukar satu masalah pasti dengan pasangan Gradle/AGP yang tidak diuji siapa pun.
- **Godot membaca `ANDROID_HOME` tapi TIDAK membaca `JAVA_HOME`.** SDK-nya terdeteksi sendiri; jalur JDK harus ada di `export/android/java_sdk_path` pada `editor_settings-4.6.tres` (nama file-nya per-minor, bukan `editor_settings-4.tres`). Menulisnya lewat file **hanya aman saat editor tertutup** — editor menyimpan setelannya sendiri ketika keluar dan akan menimpa suntingan dari luar. `export/android/debug_keystore` juga sudah diisi sendiri oleh editor ke keystore yang belum ada; ia dibuat lambat memakai `keytool` dari JDK, jadi preset di sini menunjuk `~/.android/debug.keystore` yang nyata ada supaya hasilnya deterministik.
- **APK sideload memakai native-library compression.** `export_presets.cfg` wajib memuat `gradle_build/compress_native_libraries=true`: pada debug APK, 71,47 MB dari total 76 MB adalah `libgodot_android.so`, dan opsi ini diperkirakan menurunkan berkas transfer ke sekitar 30 MB. Trade-off-nya startup sedikit lebih lambat dan ukuran terpasang tidak banyak berubah; untuk AAB Play Store, evaluasi ulang dan umumnya biarkan library tidak terkompresi.
- **Basis UI 720×1280 berarti angka Godot kira-kira 2× target dp Android.** Target Material minimum 48dp menjadi `custom_minimum_size.y = 96`, body/button 16sp menjadi sekitar 32 px, spacing 8dp menjadi 16 px. Default font Godot 16 px yang lama setara kira-kira 8sp dan memang terlalu kecil, bukan sekadar selera. Angka bersama hidup di `themes/mobile_theme.tres`; jangan mengecilkan satu tombol secara lokal.
- **`mobile_theme.tres` adalah satu-satunya sumber visual UI.** Palette-nya deep navy + cyan/violet + gold, body memakai Nunito Sans, display memakai Oxanium, dan variasi semantiknya (`PrimaryButton`, `CareDock`, `BottomNavPanel`, empat Care button, `ToastPanel`) dipakai seluruh shell. Ikon Lucide SVG + lisensinya hidup di `game/assets/icons/`; jangan kembali ke Unicode pseudo-icon atau override StyleBox per-node untuk chrome umum. Override lokal tetap hanya empat warna meter yang membawa makna gameplay. `PrimaryButton` wajib menentukan `font_focus_color` serta focus style sendiri—fallback putih di atas cyan membuat label focused tidak terbaca.
- **Chrome interaktif bersama hidup sebagai komponen scene.** `UiModal` menangani info/confirm/input dengan backdrop, Cancel, focus, dan aksi 96px; Core info, Bits info, Delete, Rename, dan bantuan Profile memakai satu instance shell. `ResourceChip` dipakai Animas/Cores/Bits; Animas membuka Collection, Cores dan Bits membuka info. `ResourceChip` menengahkan isinya di dalam target 96px, bukan menempel ke atas. `UiBottomSheet` memiliki chrome slide/dismiss, `UiSkeleton` loading bounded tanpa `_process`, dan `InfoValueRow` menyusun label, value rata kanan pada kolom lebar tetap, lalu tombol bantuan redup paling akhir supaya kolomnya tetap sejajar walau panjang value berbeda. FileDialog native, toast, Battle panel, dan efek procedural tidak dipaksakan masuk komponen ini.
- **Semua micro-interaction Control dimiliki `UiJuice`.** Ia memasang press squash, release bounce, hover/focus, reveal, bottom-sheet slide, dan tween meter sekali secara rekursif; tween lama dibunuh sebelum writer baru. `UiMotion.reduced_motion` adalah satu sakelar bersama untuk chrome, latar, inkubator, dan presenter; settings accessibility masa depan cukup menulis flag itu, bukan mengubah tiap scene.
- **Tap tepat pada Anima Home hanya memberi feedback lokal.** `AnimaPresenter.hit_test()` memakai frame aktif dengan padding touch dan `make_canvas_position_local()`, bukan `to_local()`, supaya Stage yang bergeser tidak menggeser area tapnya; awake hop/pop, Sleep sleepy bob, dan Dormant weak accent. Tidak ada care mutation atau request. Input mouse/touch di-dedupe, dan Reduced Motion tidak memindahkan sprite.
- **`Container` memakai `MOUSE_FILTER_STOP` secara default, jadi seluruh rantai di atas Stage wajib `mouse_filter = 2`.** Ini kegagalan senyap: `SafeMargin`, `Shell`, `ViewStack`, `HomeView`, dan `HomeView/Column` menutupi layar penuh, jadi GUI menelan tap sebelum `_unhandled_input()` dan interaksi Anima mati tanpa satu pun galat. Terukur dengan `--home-tap-demo`: satu node saja dikembalikan ke default membuat `reaction=(0, 0)`, sementara rantai tembus klik memberi `reaction=(0, -8.9)`. Tombol Care/nav tetap `STOP` dan tidak boleh diikutkan.
- **`tween.chain().set_parallel(true)` membatalkan chain-nya.** `chain()` menutup step, lalu `set_parallel(true)` langsung membukanya lagi, sehingga hop dan kembalinya jalan bersamaan dan sprite tampak tidak bergerak sama sekali. Pola yang benar: `chain().tween_property(...)` untuk step baru lalu `parallel().tween_property(...)` untuk pasangannya. Ini pernah membuat tap awake/Sleep terlihat mati padahal input sudah sampai.
- **Visual shell tetap procedural kecuali font dan ikon UI.** `ScanimaBackground` menggambar gradient, chamber ring, particle, glow floor, dan grid pada 15 fps; `IncubatorEffect` memiliki telur generation serta portal Summon 30 fps; `FirstAnimaEffect` menggambar scanner/orb empty state 15 fps. Stage Anima berada di 60% safe band supaya identity copy tidak tertutup silhouette tinggi. Pose `Idle/Attack/Sleep/Defeated` tidak lagi muncul di production; fungsinya tetap tersedia di `anima_demo`.
- **Semua copy production berasal dari katalog `game/locales/ui.csv`.** English adalah default/fallback dan `LocaleManager` memusatkan angka, rasio, ukuran file, nama element/stage, serta mapping kode gate. Jangan menampilkan error transport/server mentah dan jangan menulis string player-facing baru langsung di `.gd`; tambah key English, lalu pakai `tr()`. Locale baru cukup menambah kolom/resource, mendaftarkannya, dan memilih locale.
- **Target SDK 35 memaksakan edge-to-edge di Android 15.** `DisplayServer.get_display_safe_area()` mengembalikan piksel fisik, bukan koordinat viewport. `scan_flow.gd` mengubahnya dengan rasio viewport/screen sebelum memasang margin. Memakai nilainya langsung akan menggandakan inset pada device ber-DPI tinggi; mengabaikannya menaruh Koleksi/Stats di bawah status bar atau gesture bar.
- **Daftar Anima tidak dipersist lokal.** `Backend.fetch_animas()` membaca ulang hanya row `ready` dari Postgres di bawah RLS; `GameState.last_anima` tetap hanya pilihan terakhir dan bukan salinan roster. Screen Collection memakai `ItemList` dua kolom. Thumbnail 128px dibuat hanya dari sheet yang sudah ada di cache; jangan mengunduh semua sheet ~1 MB saat Collection dibuka hanya demi thumbnail.
- **Toast global menempel di bawah HUD**, bukan di tengah layar. `StatusPanel` di-anchor ke atas `ToastLayer` dengan offset safe-area + tinggi chip supaya tidak menutupi Anima, Care Dock, atau arena. Tab Scan tetap memakai status in-page.
- **Level Up** tampil di pita identity (bukan di atas tubuh Anima). Setelah banner hilang, `UiModal` menampilkan delta stat grown (`43 → 44`). `--level-up-demo` memicu keduanya.
- **Profil Anima** memakai dua kartu `HudSurface` yang sama (About + Combat): Traits grid 2 kolom, stats grid 5 kolom seperti Collection, satu help 96px per section, portrait 132px. Delete adalah teks datar gaya Forfeit (bukan `DangerButton` lebar penuh); konfirmasi tetap modal destruktif.
- **`genesis_cores == 0` mengunci Scan di client** sampai IAP/ads/BYOK ada. Tombol kamera meredup tapi tetap menerima tap (pola Care Dock) lalu toast `STATUS_NEED_CORE`; tab Scan kehilangan `ScanTabButton` cyan dan memakai `NavTabButton`. Server `NO_CORE` tetap pagar terakhir. Jangan grant Core dari client.
- **Tap Collection membuka bottom sheet, bukan langsung mengganti companion.** Sheet mengikuti tinggi konten, handle 96px bisa di-swipe ke bawah untuk menutup, dan Android back (`NOTIFICATION_WM_GO_BACK_REQUEST`, `quit_on_go_back=false`) menutup modal lalu sheet lalu kembali ke Home sebelum quit. Identity dan lima base stat tampil langsung; pada uncached care sync, empat meter lama di-reset/disembunyikan dan `UiSkeleton` tampil sampai row authoritative datang. Cache, error fallback, dan respons basi tetap dijaga revision. `View Profile` membuka row pilihan tanpa mengaktifkannya. `Summon` menyiapkan art dulu, lalu `apply_care('summon')` menulis `profiles.active_anima_id`, menidurkan Anima lain, dan membangunkan yang dipilih; dissolve companion lama, portal, `GameState.last_anima`, dan reveal di Home. Gagal sebelum summon tidak mengganti companion. Thumbnail Collection memakai pose Sleep selama Energy belum penuh, Idle begitu Energy penuh (termasuk Anima di bangku yang masih ditandai tidur di server), Damaged jika Dormant. Pose itu memakai Energy hasil `CareRules.projected_care()` dari timestamp tidur, bukan `care.energy` mentah di roster — tap sync tidak boleh jadi syarat supaya Anima terlihat siap. Bangku tidak auto-bangun di Postgres supaya Energy tidak luruh dan tidak kena +5 EXP. Tidak ada biaya atau model call.
- **Home membedakan Loading, Error, Empty, dan Ready.** Roster error tidak boleh terlihat sebagai pemain baru. Empty hanya muncul setelah fetch roster sukses dan kosong, memakai `FirstAnimaEffect` + CTA menuju tab Scan; kamera tetap butuh tap eksplisit berikutnya. State yang sama dipakai setelah Anima terakhir dihapus, tanpa onboarding flag.
- **Setelah setiap scan selesai, modal Rename muncul dengan nama generated sebagai nilai awal.** Save PATCH `nickname`; Cancel menutup tanpa request dan mempertahankan nama yang ada. Profile memakai sebelas `InfoValueRow` dalam scroll view; tiap tombol bantuan 96px membuka penjelasan localized lewat `UiModal`. Dua baris Attack/Special menampilkan `strike_name`/`surge_name` hasil Vision, dengan fallback katalog kalau Anima lama belum punya nama. Nama lama tidak dimigrasi karena database tidak bisa membedakan hasil model dari nickname manual.
- **Delete Anima memakai PostgREST + RLS native, bukan Edge Function.** Policy hanya mengizinkan `auth.uid() = owner_id`; hard delete tidak merefund Core/Bits. `care_events` cascade, `generations` tetap untuk audit dengan `anima_id = null`, dan `species_library` serta cache device tidak dihapus karena art dapat dipakai row lain. Setelah delete, roster dibaca ulang dan Home memilih row terbaru berikutnya. Migration `20260813071410_allow_owned_anima_deletion` sudah di-apply ke production dan diuji langsung untuk owner, cross-owner, audit, cascade, serta no-refund.
- **`FOTO_MAX_PX` di `scan_flow.gd` bukan angka bebas: ia sengaja sama dengan foto terbesar di `eval/photos/` (1280 px).** Menaikkannya berarti produksi memberi Vision gambar yang lebih besar daripada apa pun yang pernah diuji Smoke Set, dan yang bergeser bukan cuma stat — `species_key` yang berubah memecah dedup cache, jadi scan yang seharusnya gratis membayar $0.07. Skenario 18 di `npm run selftest` menegakkan batas itu secara gratis. Naikkan hanya bersamaan dengan eval ulang.
- **Plugin men-decode lalu meng-encode ulang fotonya**, jadi EXIF ikut hilang — termasuk koordinat GPS. Rotasi dibakar ke piksel lewat `rotateImageIfRequired`, bukan ditinggalkan sebagai tag. Konsekuensi baiknya: server tidak pernah menerima lokasi pemain. Konsekuensi lainnya: `auto_rotate_image` mengaku sendiri "tidak 100%", jadi `scan_flow` menampilkan preview foto plus mencetak dimensinya — potret yang keluar sebagai lanskap adalah satu-satunya gejala yang terlihat sebelum ia menjelma jadi stat yang aneh.
- **Balasan biner tidak boleh dikonversi ke String untuk dicoba jadi JSON.** Sheet 1 MB dari CDN yang dipaksa lewat `get_string_from_utf8()` memberi `Unicode parsing error` plus galat parser JSON di log setiap unduhan, dan menyalin satu megabyte tanpa guna, padahal pemanggilnya memakai `bytes`. `Backend._maybe_json()` memeriksa byte pertama dulu.
- **Terukur dari client sungguhan (headless, jalur cache hit):** `create_anima` balik 11–16 detik, dan seluruh rantai sampai `AnimaLoader` menerima art 14–19 detik termasuk unduh sheet ~1 MB dari CDN. Konsisten dengan 15 detik yang terukur di sisi server, jadi jaringan client bukan biaya tambahan yang berarti — yang panjang tetap Vision di dalam `create_anima`.

- **Jalur image production tidak punya alpha.** Runtime `openai/gpt-image-2` menolak `background: "transparent"` dengan `invalid_value` walaupun opsi itu tercantum di schema wrapper; nano-banana-pro juga tidak memberi alpha yang bisa diandalkan. Transparansi tetap berasal dari chroma key `#00FF00` + post-processing.
- **Vision dan image generation dua-duanya lewat Replicate**, bukan API provider langsung. Default Vision `google/gemini-2.5-flash`; default gambar `openai/gpt-image-2` dengan `quality: "medium"`, `aspect_ratio: "1024x1024"`, dan `background: "opaque"`. Jangan tambahkan `GEMINI_API_KEY` atau `OPENAI_API_KEY`; satu token Replicate tetap cukup.
- **Wrapper Gemini di Replicate tidak punya `response_schema`.** Parameter yang tersedia cuma `prompt`, `images`, `videos`, `system_instruction`, `temperature`, `top_p`, `max_output_tokens`, `thinking_budget`, `dynamic_thinking`. Jadi JSON valid tidak dijamin API: kontrak skema disisipkan ke `system_instruction`, dan `extractJson()` di `_shared/vision.mjs` menangani bungkus ```json serta kalimat pengantar. Jangan hapus parser itu dengan asumsi model selalu patuh.
- **Set `thinking_budget: 0` untuk panggilan Vision.** Token thinking ditagih sebagai output, dan tugas ini ekstraksi terstruktur, bukan penalaran. Kalau `dynamic_thinking` true ia menimpa `thinking_budget`, jadi biarkan false.
- **Output wrapper Vision itu array potongan string**, bukan satu string. Harus disambung sebelum di-parse. Model gambar sebaliknya mengembalikan satu URI.
- **`gemini-2.5-flash` retirement 20 Oktober 2026.** Ini plafon yang sudah diketahui, bukan kejutan: `# ponytail: Vision di 2.5-flash karena satu vendor satu token. Plafon 20 Okt 2026; upgrade dengan mengganti env VISION_MODEL ke google/gemini-3-flash, tanpa ubah kode.` Jangan diam-diam mengganti modelnya tanpa menjalankan ulang Smoke Set, karena stat dan `species_key` bisa bergeser.
- **Slicing sheet bukan pembagian grid atau bbox kuadran keras.** GPT Image 2 terbukti menggambar tangan Attack melewati center seam. `segmentPosePixels()` menetapkan komponen alpha 8-connected ke kuadran yang memuat mayoritas pikselnya, menyimpan ownership per piksel, lalu `blitOwned()` menyalin hanya piksel milik pose itu. Mengganti ini dengan crop 512×512 akan memotong tangan/kabel lagi.
- **Fragmen yang terlepas ikut kuadran mayoritasnya, bukan body terdekat.** Terlihat menggoda untuk menempelkan percikan atau simbol Z ke body yang paling dekat, tapi di sheet mouse v2 fragmen Z tidur berjarak 37 px ke body Idle dan 39 px ke body Sleep: aturan "body terdekat" akan memindahkannya ke pose yang salah, sementara mayoritas kuadran benar. Sudah diukur di enam sheet, 24 pose, tanpa satu pun fragmen salah alamat.
- **Sel ditolak kalau bbox-nya seluas kuadran DAN terisi padat, bukan salah satu saja.** Kedua syarat wajib berpasangan. Versi lama hanya mengukur luas bbox terhadap kuadran dan itu membuang pose Attack yang sah di run v2 pertama: speed line dan percikan membuat bbox-nya 96% kuadran padahal cuma 42% opak. Sebaliknya kepadatan sendirian akan menolak sprite bersilhouette kotak. Lihat `maxCellFillRatio` di `backend/supabase/functions/_shared/postprocess.mjs`.
- **Halo hijau di tepi TIDAK diperbaiki dengan menurunkan ambang saturasi.** Campuran keyline putih dengan `#00FF00` berbentuk `(t,255,t)` dan bersaturasi bisa hanya 0,5 — untuk menghapusnya lewat ambang, ambangnya harus turun di bawah saturasi hijau daun (0,63) dan tubuh Anima `plant` jadi bolong. Yang dipakai: erosi hanya pada cincin 1px terluar (harus bertetangga piksel transparan) dengan syarat `g >= 220` dan hijau dominan. Terukur menurunkan residu dari 0,21% ke 0,014%. Lihat `isKeyContaminatedEdge()` di `backend/supabase/functions/_shared/postprocess.mjs`.
- **Ambang chroma key harus ketat: `sat > 0.85`, `val > 0.5`.** Resep chroma key umum memakai 0,3 dan itu akan **melubangi tubuh Anima berelemen `plant`**, karena hijau daun `rgb(60,160,70)` punya saturasi 0,63 dan hue 126°. Nilai ini muncul di dua tempat dan harus selalu sama: `backend/supabase/functions/_shared/postprocess.mjs` (dipakai eval maupun Edge Function) dan `game/shaders/chroma_key.gdshader`.
- **Post-processing muat di Edge Function dengan lega: 173 ms.** Terukur pada sheet v3 sungguhan (1024×1024, 1,46 MB) di runtime edge, versus 162 ms di Node — batas CPU 2 detik tidak pernah dekat. Total request 1.448 ms termasuk unduh keluaran, unggah sheet, dan tulis database. Jangan memindahkan langkah ini ke worker terpisah "karena mungkin berat"; sudah diukur.
- **Hash PNG berbeda antar runtime walau pikselnya identik.** Sheet yang sama diproses di Node dan di edge memberi 3.544.272 byte channel yang sama persis (nol selisih) dan manifest yang sama, tapi PNG-nya 886 KB versus 964 KB karena setelan deflate-nya beda. Konsekuensinya: `sheet_path` yang berbasis SHA-256 byte terenkode **tidak** stabil lintas runtime. Produksi selalu mengenkode di edge sehingga dedup-nya utuh, tapi jangan pernah membandingkan hash Node dengan hash produksi untuk menyimpulkan ada regresi — bandingkan pikselnya.
- **Keempat region wajib berukuran sama.** `AnimatedSprite2D` cuma punya satu `offset` untuk seluruh animasi, jadi region yang ukurannya beda membuat sprite tersentak berpindah tiap ganti pose. `AnimaLoader` menolak manifest yang melanggar ini; jangan "perbaiki" dengan melonggarkan pemeriksaannya.
- **Jangan mengukur konsistensi skala dari varians keempat pose.** Pose Sleep memang jauh lebih pendek daripada Idle, jadi metrik itu memberi alarm palsu terus-menerus. Bandingkan Idle vs Attack saja (`standing_height_variance`).
- **Yang ditunggu pemain bukan cuma latensi model.** Terukur di produksi: `create_anima` balik **15 detik** di jalur Genesis (Vision ikut ditunggu di dalamnya, sebab hasilnya yang menentukan apakah kita berhak mendebit Core) dan **11 detik** di jalur cache hit. Jadi UI butuh dua status, bukan satu: belasan detik pertama tanpa apa pun di layar sudah terasa seperti macet, padahal Anima-nya belum tentu menetas sampai ~satu menit kemudian.
- **Latensi GPT Image 2 medium terukur 57–63 detik** untuk dua sheet 1024×1024; desain incubator tetap harus menganggap sekitar satu menit dan tahan app masuk background. Quality high terukur ~153 detik dan tidak dipakai.
- **Jeda Replicate memakai `IncubatorEffect`, bukan progress bar palsu.** Setelah `create_anima` mengonfirmasi Genesis, foto/Anima lama diganti telur energi procedural (ring cyan-violet, scan line, spark emas) selama polling. Cache hit mem-bypass inkubator dan langsung reveal. Resume pending scan menyalakannya lagi; gagal/timeout mematikannya dan mengembalikan Anima lama. Karena Replicate tidak memberi persentase yang bermakna, animasinya loop tanpa angka progres.
- **Tween hatch/Summon dibagi menurut pemilik transform.** `IncubatorEffect` mengurus telur/portal/flash, sedangkan `AnimaPresenter` mengurus dissolve serta squash-and-stretch reveal lalu menyalakan tween pose lagi. Jangan menganimasikan `Anima.scale/position` dari `scan_flow.gd`; dua tween yang menulis properti sama akan saling berebut dan membuat reveal acak.
- **GPT Image 2 medium dipilih setelah perbandingan nyata.** Medium memakai 1.756 output token dan ~57–63 detik; high memakai 7.024 output token dan ~153 detik tanpa lompatan kualitas yang sebanding. Jangan naikkan quality diam-diam.
- **nano-banana-pro tetap rollback/A-B saja** lewat `IMAGE_MODEL`; model itu pernah berulang kali memberi `ModelRateLimitError (E003)`. Kalau dipakai lagi, resolusi 1K dan 2K berharga sama sehingga minta `"2K"`.
- **`google/nano-banana-2-lite` sudah diuji dan ditolak; GPT Image 2 medium tetap dipakai.** Harga tercantum $0.034 dan billing run tampil $0.03. Schema-nya hanya menerima `prompt`, `image_input`, `aspect_ratio`, dan `output_format`; adapter eval tetap ada untuk reproduksi A/B. Run mouse + v5 selesai 7 detik dan punya 4/4 pose, tetapi menyalin label kuadran serta garis pembagi: bbox Sleep menjadi 1024 px, 21.361 cross-boundary pixels, dan residu hijau 2,04% versus target <0,1%. Harga/latensi tidak menutup kegagalan layout; 4/4 detector saja bukan bukti sheet siap pakai.

## Perintah umum

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

```bash
# gratis, jalankan ini dulu
npm run selftest                       # 26 skenario + 12 uji tanda tangan webhook
godot --headless --path game --script res://tests/test_sprite_slicing.gd
godot --headless --path game --script res://tests/test_client_state.gd  # 60 check sesi, refresh, pending scan/care/Battle, cache
godot --headless --path game --script res://tests/test_scan_ui.gd       # 422 check shell + Battle + komponen + tap + touch + reduced motion
godot --headless --path game --script res://tests/test_i18n.gd          # 1486 check katalog + key + formatter + wrapping
godot --headless --path game --script res://tests/test_game_rules.gd    # 68 check care + EXP/Level + kontrak event Battle
node eval/run.mjs --set smoke --dry-run # cek foto + template tanpa API

# setelah mengubah prompt: regenerasi bundel yang dipakai Edge Function
node backend/tools/bundle_prompts.mjs
node backend/tools/bundle_prompts.mjs --check   # gagal kalau bundel basi

# menguji ulang post-processing pada sheet yang SUDAH dibayar, nol panggilan API
node eval/run.mjs --set smoke --reprocess

# kontrak Node <-> Godot, juga gratis
node eval/selftest.mjs --emit /tmp/scanima_e2e
godot --headless --path game --script res://tests/test_sprite_slicing.gd \
    -- --manifest=/tmp/scanima_e2e/manifest.json

# game
godot --path game                      # scan_flow: sesi, saldo, Anima dari cache
godot --path game -- --screenshot=/tmp/scan.png       # periksa layar tanpa editor
godot --headless --path game --import  # rebuild cache class, cek parse error
godot --path game -- --core-info --screenshot=/tmp/core.png
godot --path game -- --bits-info --screenshot=/tmp/bits.png
godot --path game -- --sleep-demo --screenshot=/tmp/sleep.png
godot --path game -- --rename-demo --screenshot=/tmp/rename.png
godot --path game -- --delete-demo --screenshot=/tmp/delete.png
godot --path game -- --collection-sheet-demo --screenshot=/tmp/collection-sheet.png
godot --path game -- --collection-sheet-loading-demo --screenshot=/tmp/collection-loading.png
godot --path game -- --profile-demo --screenshot=/tmp/profile.png
godot --path game -- --profile-help-demo --screenshot=/tmp/profile-help.png
# tap demo mendorong event lewat push_input, jadi log "reaction=(0, -8.9)" adalah
# bukti routing GUI, sementara "(0, 0)" berarti ada Control yang menelan tapnya
godot --path game -- --home-tap-demo
godot --path game -- --level-up-demo --screenshot=/tmp/level-up.png
godot --path game -- --empty-demo --screenshot=/tmp/empty.png
godot --path game -- --summon-demo
godot --path game -- --battle-demo --screenshot=/tmp/battle.png
godot --path game -- --battle-pending-demo --screenshot=/tmp/battle-pending.png
godot --path game -- --battle-effective-demo --screenshot=/tmp/battle-effective.png
godot --path game -- --battle-result-demo --screenshot=/tmp/battle-result.png
godot --path game -- --battle-win-demo --screenshot=/tmp/battle-win.png
godot --path game -- --battle-training-demo --screenshot=/tmp/battle-training.png
godot --path game -- --battle-training-active-demo \
 --screenshot=/tmp/battle-training-active.png

# band preview foto tanpa memindai apa pun, jadi tata letaknya bisa diperiksa
# dengan biaya nol. Tanpa ini satu-satunya cara melihatnya adalah membayar scan.
godot --path game -- --preview=$PWD/eval/photos/sepatu.jpg \
    --screenshot=/tmp/scan.png

# preview gratis loading Genesis; tidak memanggil API
godot --path game -- --incubator --screenshot=/tmp/incubator.png
godot --path game -- --hatch-demo  # mainkan loading + reveal sekali, gratis

# alat periksa art, sekarang harus ditunjuk eksplisit karena main scene bukan demo
godot --path game res://scenes/anima_demo.tscn        # sheet placeholder
godot --path game res://scenes/anima_demo.tscn \
    -- --manifest=<abs>.json --pose=sleep --screenshot=/tmp/a.png

# jalur client sungguhan terhadap produksi, BERBIAYA ~$0.003 (satu Vision)
# Pakai foto yang spesiesnya SUDAH ada di species_library, kalau tidak ia
# memicu generation $0.07. Sesi uji disimpan di user://live_scan_state.json dan
# sengaja dipertahankan supaya jalan berikutnya memakai pemain uji yang sama.
godot --headless --path game --script res://tests/live_scan.gd \
    -- --photo=$PWD/eval/photos/mug-putih.jpg

# jalur Battle client sungguhan terhadap produksi, NOL model call/Core.
# Memakai sesi uji live_scan; menjalankan start/resume/tiga action/replay/forfeit.
godot --headless --path game --script res://tests/live_battle.gd

# Android. Tidak ada langkah editor yang wajib: --install-android-build-template
# adalah flag CLI, dipakai bersama --export-debug, dan export_presets.cfg boleh
# ditulis tangan. Sekali saja per mesin; sesudahnya cukup baris --export-debug.
# Jangan menambahkan izin storage apa pun di preset — CAMERA sudah datang dari
# manifest plugin, dan izin galeri adalah yang membuat Play menolak. Preset dan
# game/android/ di-gitignore karena keduanya memuat jalur keystore.
godot --headless --path game --install-android-build-template \
    --export-debug Android /tmp/scanima.apk

# Verifikasi APK. Yang diperiksa bukan "file-nya ada" tetapi tepat dua izin dan
# kelas plugin benar-benar masuk dex; manifest yang ter-merge saja tidak cukup.
B=~/Library/Android/sdk/build-tools/36.1.0
$B/aapt2 dump permissions /tmp/scanima.apk | grep permission  # INTERNET + CAMERA
unzip -p /tmp/scanima.apk classes.dex | strings | grep -c GodotGetImage
$B/apksigner verify /tmp/scanima.apk && echo tertandatangani

# Uji kamera di perangkat sungguhan. Tidak ada versi headless-nya: satu-satunya
# hal di client yang tidak dijaga npm run selftest. Foto benda yang spesiesnya
# SUDAH ada di species_library supaya jalurnya cache hit (~$0.003, bukan $0.07).
# Yang dibuktikan: izin diminta sekali dan pemulihannya jalan, dimensi di log
# menunjukkan <=1280 px dengan orientasi benar, dan Anima-nya tampil.
# adb tidak ada di PATH di mesin ini; ia hidup di platform-tools SDK.
A=~/Library/Android/sdk/platform-tools/adb
$A install -r /tmp/scanima.apk && $A logcat -s godot:V

# eval prompt, BERBIAYA
node eval/run.mjs --set smoke --vision-only  # gate + stat saja, ~$0.015
node eval/run.mjs --set smoke                # 5 foto, ~$0.225, untuk iterasi
node eval/run.mjs --set full                 # 20 foto, ~$1.32, gerbang penerimaan

# aturan kuota dan pagar akses, gratis, jalankan setiap kali migrasi berubah
supabase db query --file backend/tests/quota_rules.sql --linked
# (atau lewat Supabase MCP execute_sql dengan isi file itu; lulus = NOTICE
#  "SEMUA UJI LULUS", gagal = satu ASSERT yang menyebut invarian yang rusak)

# backend lokal, Phase 2 (butuh Docker jalan)
cd backend && supabase start
supabase functions serve create_anima --env-file .env.local

# deploy Edge Function — PAT lewat env, bukan `supabase login`, lihat di bawah
export SUPABASE_ACCESS_TOKEN=sbp_...
cd backend && supabase functions deploy create_anima replicate_webhook \
  --project-ref kgcaisvmmpxswevjvgft
supabase secrets set REPLICATE_API_TOKEN=... --project-ref kgcaisvmmpxswevjvgft

# smoke check sesudah deploy: nol kredensial, nol biaya.
# 401 dua-duanya = kedua fungsi boot dan pagarnya berdiri. 500 = modulnya gagal impor,
# dan yang kedua juga membuktikan REPLICATE_API_TOKEN hidup, sebab rahasia penanda
# tangan diambil dari Replicate sebelum tanda tangannya diperiksa.
F=https://kgcaisvmmpxswevjvgft.supabase.co/functions/v1
curl -sS -X POST $F/create_anima -d '{}'
curl -sS -X POST $F/replicate_webhook -H 'webhook-id: a' \
  -H 'webhook-timestamp: 1' -H 'webhook-signature: v1,eA==' -d '{}'
```

**Deploy butuh CLI yang terautentikasi ke project ini, dan `supabase login` bukan caranya.** Supabase MCP bisa apply migrasi dan menjalankan SQL, dan `deploy_edge_function`-nya juga jalan, tapi ia menuntut isi setiap file ditempelkan ke dalam panggilan (bundel prompt saja 65 KB) dan **tidak bisa memasang secret sama sekali**.

Yang terukur di mesin ini: `supabase login` memakai sesi browser yang sudah aktif tanpa bertanya, jadi ia bisa "berhasil" ke akun yang salah. Lebih buruk, `supabase login --token sbp_...` juga membalas "You are now logged in" sementara `supabase projects list` **tetap** memuat project akun lama — token baru itu tidak menang atas kredensial yang sudah tersimpan. Yang menang adalah env var:

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
supabase projects list   # Scanima harus muncul di sini sebelum lanjut
```

Dengan env var itu, `link` tidak diperlukan; cukup `--project-ref`. Kalau ragu token siapa yang dipegang, tanya langsung ke Management API — `curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" https://api.supabase.com/v1/organizations` harus menjawab `rekansebangku`, bukan organisasi lain.

`REPLICATE_WEBHOOK_SECRET` **tidak ada dan tidak perlu dibuat**: `replicate_webhook` mengambil rahasia penanda tangan dari `GET /v1/webhooks/default/secret` memakai token yang sudah ada, lalu men-cache-nya selama instance hidup. Satu kredensial lebih sedikit berarti satu langkah setup yang tidak bisa terlupakan — dan webhook tanpa verifikasi berarti siapa pun bisa mengisi pustaka art yang di-share semua pemain.

`backend/tests/quota_rules.sql` aman dijalankan di proyek remote: ia satu blok `DO`, jadi satu transaksi. Assert yang gagal me-rollback semuanya termasuk user uji dan grant sementara yang dipakai untuk menguji trigger; kalau lulus, barisnya dihapus sendiri di akhir. Jangan mengubahnya menjadi banyak statement terpisah, karena sifat itulah yang membuatnya boleh menyentuh database produksi.

Default-nya `smoke`, prompt `v7`, dan GPT Image 2 `medium`. Jangan jalankan `full` sebagai bagian dari iterasi biasa — ia enam kali lebih mahal dan tidak memberi informasi tambahan sampai Smoke Set sudah bersih. Sebelum memicu satu pun generation gambar, `--vision-only` sudah cukup untuk menguji gate keamanan dan pemetaan stat dengan biaya ~$0.015.

**Kalau yang diubah cuma post-processing, jangan bayar generation lagi.** `--reprocess` menyusun ulang sheet, manifest, dan contact sheet dari `raw.png` run sebelumnya tanpa satu pun panggilan API, jadi perubahan keying/slicing bisa diverifikasi terhadap gambar model sungguhan dengan biaya nol. Ia sengaja tidak menimpa `vision.json` dan `prompt.txt`, karena keduanya catatan run yang menghasilkan `raw.png` itu.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`
