# CLAUDE.md — konteks untuk AI coding agent

Baca file ini sebelum menyentuh kode Scanima. Update file ini setiap ada perubahan signifikan pada stack, konvensi, atau keputusan arsitektur.

## Apa itu Scanima

Game mobile virtual pet. Pemain memfoto objek nyata, foto itu jadi monster (**Anima**) lewat Vision LLM + image generation. Lalu dirawat gaya Tamagotchi, dievolusikan, dan dipakai bertarung. Detail lengkap di [README.md](README.md) dan [docs/](docs/).

## Aturan yang tidak bisa dinegosiasikan

1. **API key tidak pernah masuk ke build Godot.** Hanya ada satu, `REPLICATE_API_TOKEN`, dan ia hanya hidup di Supabase Edge Function secrets. Client Godot bicara ke Edge Function, bukan ke Replicate. Satu-satunya pengecualian adalah mode BYOK di mana token milik pemain sendiri disimpan lokal di device.
2. **Setiap panggilan image generation berbiaya ~\$0.07.** Default-nya GPT Image 2 medium; biaya berbasis token dan dua run nyata berada di sekitar angka ini. Jangan pernah menulis kode yang bisa memanggil generation dalam loop, retry otomatis tanpa batas, atau tanpa idempotency key. Kalau ragu, jangan panggil.
3. **Semua mata uang bersifat server-authoritative.** Ada tiga: `scan_charges` (Discovery Scan), `genesis_cores` (spesies baru), `bits` (item perawatan). Client boleh menampilkan sisanya, tapi keputusan boleh-tidaknya generate hanya diambil di Postgres dalam transaksi yang sama dengan pencatatan debit. Jangan pernah menambah `genesis_cores` dari callback iklan.
4. **Jangan commit foto pemain, output generation, atau `.env`.** Foto mentah dihapus dari Storage setelah post-processing selesai.

## Konvensi Godot / GDScript

- Godot 4.x, Mobile renderer, project 2D. Root project ada di `game/`.
- File script `snake_case.gd`, nama class `PascalCase`, node `PascalCase`.
- Type hints di mana-mana: `var hp: int = 0`, `func feed(amount: int) -> void:`.
- Referensi node lewat `@onready var sprite: AnimatedSprite2D = %AnimaSprite` (pakai unique name `%`, bukan path panjang yang gampang putus saat scene di-refactor).
- Cek validitas objek dengan `is_instance_valid()` sebelum akses, khususnya untuk node yang bisa di-free saat async request masih jalan.
- Semua state game yang persist lewat satu autoload `GameState`; jangan sebar `save()` ke banyak node.
- Sprite Anima **tidak** diimpor sebagai resource `.import` — datang saat runtime dari server, disimpan di `user://animas/`.
- Dua autoload, dan urutannya penting: `GameState` (pemilik `user://state.json`) lalu `Backend` (transport HTTP). Ketergantungannya satu arah — `Backend` menulis sesi ke `GameState`, `GameState` tidak pernah memanggil `Backend`. Yang mengorkestrasi adalah scene: `await Backend.ensure_session()`.
- Entry point-nya `scenes/scan_flow.tscn`. `scenes/anima_demo.tscn` tetap ada sebagai alat periksa art dan harus dipanggil eksplisit: `godot --path game res://scenes/anima_demo.tscn -- --manifest=...`.
- `Backend.gd` satu-satunya tempat yang tahu URL project dan kunci. Kuncinya **publishable** (`sb_publishable_...`) dan memang ikut ke dalam build; yang membatasi akses RLS, bukan kerahasiaannya. Terukur diterima kelima endpoint yang dipakai client: `auth/signup`, `auth/token`, REST, Storage, dan `functions/v1`. Yang tidak boleh masuk ke sana sampai kapan pun: `REPLICATE_API_TOKEN` atau service role key.
- Yang persist hanya sesi dan scan yang sedang berjalan. Saldo dan daftar Anima **selalu** dibaca ulang dari Postgres — server yang berwenang, dan salinan lokal cuma menambah satu sumber kebenaran yang bisa salah.

## Konvensi backend

- Supabase Edge Functions berjalan di Deno. Pakai `npm:` specifier hanya untuk paket pure-JS/TS. **Jangan pakai `sharp`** (butuh native binary, tidak jalan di edge runtime); untuk manipulasi piksel pakai `ImageScript`.
- **`npm:imagescript` GAGAL di edge runtime** dengan galat arch/platform tidak didukung, walaupun paketnya pure-JS. Yang jalan adalah `https://deno.land/x/imagescript@1.2.15/mod.ts` lewat `functions/import_map.json`. Node di-pin ke `imagescript@1.2.15` supaya dua runtime memakai versi yang sama; jangan naikkan salah satunya sendiri.
- **Kode yang dipakai dua runtime hidup di `functions/_shared/` sebagai `.mjs`**, bukan disalin ke masing-masing sisi: `postprocess.mjs` (keying + slicing), `vision.mjs` (parsing, gate, perakitan prompt), `pricing.mjs` (harga per panggilan). Deno bisa mengimpor `.mjs` apa adanya, dan eval mengimpor file yang sama. Dua salinan berarti eval bisa lulus sementara produksi memakai aturan lain — dan aturan itu yang memutuskan apakah kita membayar $0.07.
- **Tidak ada endpoint unggah foto.** Client menulis langsung ke bucket `photos` dengan anon key-nya; yang membatasinya adalah policy Storage (`(storage.foldername(name))[1] = auth.uid()`) plus `file_size_limit` dan `allowed_mime_types` milik bucket. `create_anima` hanya menerima `photo_path` dan memeriksa prefix-nya. Menulis endpoint penerbit signed URL berarti menulis ulang pagar yang sudah disediakan platform.
- Satu jalur uang: `claim_genesis` (debit Core + baris generation + baris anima + ledger, satu transaksi) dan `record_cache_hit` (art gratis dari pustaka). `claim_generation` yang lama **sudah di-drop** — dua fungsi yang dua-duanya bisa mendebit Core berarti dua tempat yang harus benar.
- Migrasi SQL di `backend/supabase/migrations/`, satu file per perubahan, tidak pernah diedit setelah di-apply ke remote.
- RLS wajib aktif di semua tabel yang menyimpan data pemain. Edge Function pakai service role key, client pakai anon key.
- Semua endpoint yang menghabiskan uang menerima `idempotency_key` dari client.
- Proyek remote: **Scanima**, ref `kgcaisvmmpxswevjvgft`, region `ap-northeast-1`, Postgres 17. Empat migrasi pertama di-apply lewat Supabase MCP, dan nama file lokal sengaja disamakan dengan versi yang dicatat remote supaya `supabase migration list` tidak melihat drift. Kalau apply lewat MCP lagi, samakan lagi nama filenya sesudahnya.
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
├── v3/                           # DEFAULT production: v2 + blok BRAND MARKS
│   ├── vision_system.md          # identik v2
│   ├── vision_schema.json        # identik v2
│   ├── sprite_sheet.md           # logo merek diganti marking ciptaan
│   └── sprite_sheet_evolve.md
└── v4/                           # CANDIDATE, belum diuji berbayar
    ├── vision_system.md          # + surface_finish dan damage_hints
    ├── vision_schema.json        # material/damage nullable, cache key tetap
    ├── sprite_sheet.md           # permukaan polos; damage wajib sesuai material
    └── sprite_sheet_evolve.md
```

**Prompt tidak bisa dibaca sebagai file di Edge Function.** `Deno.readTextFile()` gagal untuk file pendamping yang dideploy lewat MCP, jadi `backend/tools/bundle_prompts.mjs` membundel semua versi menjadi `functions/_shared/prompts.generated.ts` yang diimpor sebagai modul. Sumbernya tetap file `.md` di git; artefaknya turunan. Setelah mengubah prompt: `node backend/tools/bundle_prompts.mjs`. Skenario 17 di `npm run selftest` gagal kalau bundelnya basi, jadi kelupaan ketangkap gratis, bukan saat art produksi ternyata berbeda dari art yang sudah disetujui.

`vision_schema.json` **tidak** dikirim sebagai parameter API — ia disisipkan ke `system_instruction`, sebab wrapper Gemini di Replicate tidak punya `response_schema`. Notasinya tetap subset OpenAPI (`"nullable": true`, bukan `["string", "null"]`, tanpa `pattern`) supaya file yang sama bisa langsung dipakai kalau nanti pindah ke Gemini API langsung. Bentuk data ditegakkan `extractJson()` dan `validateVision()` di `backend/supabase/functions/_shared/vision.mjs`, bukan diharapkan dari model.

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md) dan sumber art direction v2 ada di [docs/monster_camera_anime_cel_shaded_style_guide.md](docs/monster_camera_anime_cel_shaded_style_guide.md). Jangan mengarang aturan style baru; konsistensi visual antar Anima bergantung pada style lock itu.

**Larangan negatif saja tidak menghapus logo merek, tapi instruksi pengganti v3 juga punya efek samping.** v2 sudah memuat "no logos, brand names" dan GPT Image 2 tetap menggambar swoosh Nike karena logonya datang dari `input_images`. v3 menghilangkannya dengan meminta permukaan polos atau marking geometris ciptaan sendiri; itu lolos satu uji sepatu dan menjaga `species_key`, tetapi model lalu mengarang emblem mirip logo bahkan pada objek tanpa logo. v4 menghapus pilihan marking itu seluruhnya: logo/teks/sigil dianggap tidak ada dan tempatnya selalu material polos yang setia pada objek.

**Damage v3 bias robot bukan kebetulan model.** Template universalnya sendiri menyebut `loose cable`, `exposed wire`, dan `broken key`, sementara style lock memberi semua objek bahasa `techno-organic`; material Vision tidak pernah sampai ke prompt gambar. v4 menambah `surface_finish` + `damage_hints` ke Vision dan menyaring hint teknis di `assemblePrompt()`: kata cable/wire/circuit/key hanya lolos jika fitur yang sama benar-benar ada di `signature_features`. Keramik retak/terkelupas, kain berjumbai/robek, tanaman sobek/layu, logam penyok/tergores. v4 **belum default dan belum boleh dipromosikan sebelum Smoke Set visual berbayar disetujui**.

## Fakta teknis yang mudah salah

- **Sign-in anonim mati secara default, dan Scanima tidak punya layar login.** Identitas pemain adalah user anonim yang dibuat saat app pertama kali jalan; `handle_new_user` yang mengisi profil beserta 8 scan charge dan 3 Core awalnya. Dengan setelan default project, `POST /auth/v1/signup` menjawab `anonymous_provider_disabled` dan app mati di detik pertama — bukan di jalur yang mahal, jadi tidak ada test berbayar yang akan menangkapnya. Sudah dinyalakan di remote dan dideklarasikan di `backend/supabase/config.toml` (`enable_anonymous_sign_ins = true`) supaya ia tidak jadi setelan hantu yang hanya hidup di dashboard. Batas bawaannya 30 sign-in anonim per jam per IP; itu pagar abuse, bukan angka yang perlu dinaikkan sampai ada bukti pemain nyata kena.
- **`species_library` hanya bisa dibaca peran `authenticated`, dan anon key mentah menjawab `[]`, bukan galat.** Client harus sign-in anonim **sebelum** membaca pustaka. Gejala salahnya berbahaya karena tidak terlihat seperti masalah autentikasi: array kosong terbaca sebagai "pustaka masih kosong", jadi setiap scan tampak sebagai spesies baru dan setiap scan membayar $0.07. Terukur saat mengambil manifest untuk uji Godot — anon key memberi nol baris untuk baris yang jelas ada.
- **Bucket `photos` hanya punya policy INSERT, dan itu lengkap.** Client boleh menaruh foto di foldernya sendiri, tapi tidak boleh membaca, melihat daftar, maupun menghapus — DELETE dari client dijawab RLS dengan 403. Terlihat seperti policy yang lupa ditulis; sebenarnya client tidak pernah membutuhkannya. Yang membaca foto adalah Edge Function lewat signed URL service role, dan yang menghapusnya adalah `create_anima`/`finalize_sheet` setelah post-processing selesai. Menambahkan SELECT berarti memberi jalan membaca foto yang seharusnya sudah lenyap.
- **`care_score` bukan bagian dari `care` yang client-writable.** Nilai kenyang boleh dicontek, `care_score` tidak: ia gerbang evolusi dan evolusi memicu generation ~$0.07 tanpa mendebit Core. Hak update-nya server-only.
- **`rls_auto_enable()` bukan buatan kita.** Ia event trigger bawaan bootstrap Supabase yang menyalakan RLS otomatis pada setiap tabel baru di `public`. Terukur: peran `authenticated` bisa memanggilnya sebagai fungsi biasa dan ia selesai tanpa error maupun efek (`pg_event_trigger_ddl_commands()` kosong di luar konteks trigger). EXECUTE-nya sudah dicabut di migrasi `harden_platform_rls_helper`, dan event trigger-nya diverifikasi tetap menyala sesudahnya — hak eksekusi event trigger diperiksa saat `create event trigger`, bukan saat ia menyala.
- **Advisor `rls_enabled_no_policy` pada `app_config` itu disengaja.** RLS aktif tanpa policy sama sekali adalah cara menutup tabel dari client; jangan "perbaiki" dengan menambahkan policy baca.
- **Enam WARN `auth_allow_anonymous_sign_ins` juga disengaja, dan "memperbaikinya" akan mematikan game.** Advisor memberi peringatan untuk `profiles`, `animas`, `generations`, `quota_ledger`, `pending_discoveries`, dan `species_library` karena policy-nya `to authenticated`, dan user anonim memakai peran itu. Di Scanima user anonim **adalah** pemainnya — bukan tamu yang menyusup. Yang membatasi tetap `auth.uid() = owner_id`, jadi pemain anonim A tidak bisa membaca data pemain anonim B; `species_library` memang dibaca semua orang karena ia pustaka art bersama. Menambahkan `and not (auth.jwt() ->> 'is_anonymous')::boolean` akan menutup satu-satunya jenis akun yang dimiliki game ini.
- **Dua INFO performa dibiarkan sadar:** `generations.anima_id` tanpa indeks penutup, dan `generations_prediction_idx` yang belum terpakai. Yang pertama hanya menyakitkan saat baris `animas` dihapus, dan itu jalur langka; tambahkan indeksnya kalau fitur melepas Anima jadi rutin. Yang kedua wajar di database tanpa trafik.

- **Refresh token yang ditolak tidak boleh dijawab dengan sign-in anonim baru.** Ini terlihat seperti pemulihan yang sopan — app kembali jalan, pemain bisa main lagi — padahal seluruh Anima-nya tertinggal di akun yang tidak bisa dijangkau lagi, dan tidak ada email atau password untuk kembali ke sana. `Backend.refresh_session()` mengembalikan galat dan berhenti; scene menampilkannya sebagai kegagalan jaringan. Gagal yang kelihatan jauh lebih murah daripada kehilangan data yang tidak kelihatan.
- **Node autoload SUDAH ada dalam mode `--script`, tetapi nama globalnya belum.** Menulis `GameState` di skrip yang dijalankan `--script` gagal saat kompilasi dengan `Identifier not found`, sebab skrip itu dikompilasi sebelum autoload terdaftar sebagai global — sementara node-nya sendiri terpasang di bawah root dan bisa diambil dengan `get_root().get_node("GameState")`. Itu yang dipakai `tests/test_client_state.gd` dan `tests/live_scan.gd`. Konstanta dan fungsi statis diambil dari `get_script()`, bukan dari instance-nya.
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
- **Basis UI 720×1280 berarti angka Godot kira-kira 2× target dp Android.** Target Material minimum 48dp menjadi `custom_minimum_size.y = 96`, body/button 16sp menjadi sekitar 32 px, spacing 8dp menjadi 16 px. Default font Godot 16 px yang lama setara kira-kira 8sp dan memang terlalu kecil, bukan sekadar selera. Angka bersama hidup di `themes/mobile_theme.tres`; jangan mengecilkan satu tombol secara lokal.
- **Target SDK 35 memaksakan edge-to-edge di Android 15.** `DisplayServer.get_display_safe_area()` mengembalikan piksel fisik, bukan koordinat viewport. `scan_flow.gd` mengubahnya dengan rasio viewport/screen sebelum memasang margin. Memakai nilainya langsung akan menggandakan inset pada device ber-DPI tinggi; mengabaikannya menaruh Koleksi/Stats di bawah status bar atau gesture bar.
- **Daftar Anima tidak dipersist lokal.** `Backend.fetch_animas()` membaca ulang hanya row `ready` dari Postgres di bawah RLS; `GameState.last_anima` tetap hanya pilihan terakhir dan bukan salinan roster. Modal memakai `ItemList` dua kolom. Thumbnail 128px dibuat hanya dari sheet yang sudah ada di cache; jangan mengunduh semua sheet ~1 MB saat modal dibuka hanya demi thumbnail.
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
- **Tween hatch dibagi menurut pemilik transform.** `IncubatorEffect.burst()` mengurus flash/ring, sedangkan `AnimaPresenter.hatch_reveal()` menghentikan tween pose, melakukan squash-and-stretch reveal, lalu menyalakan tween pose lagi. Jangan menganimasikan `Anima.scale/position` dari `scan_flow.gd`; dua tween yang menulis properti sama akan saling berebut dan membuat reveal acak.
- **GPT Image 2 medium dipilih setelah perbandingan nyata.** Medium memakai 1.756 output token dan ~57–63 detik; high memakai 7.024 output token dan ~153 detik tanpa lompatan kualitas yang sebanding. Jangan naikkan quality diam-diam.
- **nano-banana-pro tetap rollback/A-B saja** lewat `IMAGE_MODEL`; model itu pernah berulang kali memberi `ModelRateLimitError (E003)`. Kalau dipakai lagi, resolusi 1K dan 2K berharga sama sehingga minta `"2K"`.

## Perintah umum

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

```bash
# gratis, jalankan ini dulu
npm run selftest                       # 20 skenario + 12 uji tanda tangan webhook
godot --headless --path game --script res://tests/test_sprite_slicing.gd
godot --headless --path game --script res://tests/test_client_state.gd  # sesi, kunci scan, cache art
godot --headless --path game --script res://tests/test_scan_ui.gd       # 50 check layout + incubator
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

Default-nya `smoke`, prompt `v3`, dan GPT Image 2 `medium`. Jangan jalankan `full` sebagai bagian dari iterasi biasa — ia enam kali lebih mahal dan tidak memberi informasi tambahan sampai Smoke Set sudah bersih. Sebelum memicu satu pun generation gambar, `--vision-only` sudah cukup untuk menguji gate keamanan dan pemetaan stat dengan biaya ~$0.015.

**Kalau yang diubah cuma post-processing, jangan bayar generation lagi.** `--reprocess` menyusun ulang sheet, manifest, dan contact sheet dari `raw.png` run sebelumnya tanpa satu pun panggilan API, jadi perubahan keying/slicing bisa diverifikasi terhadap gambar model sungguhan dengan biaya nol. Ia sengaja tidak menimpa `vision.json` dan `prompt.txt`, karena keduanya catatan run yang menghasilkan `raw.png` itu.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`
