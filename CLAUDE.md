# CLAUDE.md — konteks untuk AI coding agent

Baca file ini sebelum menyentuh kode Scanima. Update file ini setiap ada perubahan signifikan pada stack, konvensi, atau keputusan arsitektur.

File ini sengaja pendek karena ia ikut ke **setiap** request. Yang tinggal di
sini hanya yang berlaku lintas domain atau menyangkut uang; detail per-domain
hidup di lima rule ber-glob `.cursor/rules/` yang dimuat sendiri saat file yang
cocok disentuh, dan riwayat hidup di `docs/`. Peta lengkapnya di bagian
terakhir. Fakta baru masuk ke rule atau docs yang tepat, dan hanya naik ke file
ini kalau ia tidak punya glob — bukan karena ia terasa penting.

Turn Battle sekarang **local-first**: client menyimulasikan turn dengan aturan
yang identik lalu menganimasikannya sementara request-nya terbang, dan hasil
server tetap yang tersimpan. Care dan Shop optimistis dengan rollback tanpa
meredupkan dock/sheet-nya, Summon menyembunyikan round trip-nya di balik dissolve
dan charge portal, Home digambar dari `user://boot_cache.json` sebelum jaringan
menjawab, dan commit turn mengulang sendiri saat transport gagal. Detail, pagar
parity, dan daftar jalur yang sengaja tetap menunggu server ada di
[`docs/12-local-first-turns.md`](docs/12-local-first-turns.md).

## Apa itu Scanima

Game mobile virtual pet. Pemain memfoto objek nyata, hewan non-manusia yang
aman, atau ilustrasi non-manusia orisinal/generik; foto itu jadi monster
(**Anima**) lewat Vision LLM + image generation. Karakter franchise yang dapat
disebut namanya ditolak sebelum Core dan generation dipakai. Lalu Anima dirawat
gaya Tamagotchi, dievolusikan, dan dipakai bertarung. Panduan pemain (bukan spek)
di [docs/wiki/](docs/wiki/README.md). Spek dan rumus di [README.md](README.md)
dan [docs/](docs/).

Diagnosis produk non-teknis hidup di
[`docs/11-core-loop-and-player-motivation.md`](docs/11-core-loop-and-player-motivation.md):
Scan adalah hook terkuat, Care/Battle adalah loop berulang paling lengkap, dan
aktivitas harian belum membawa pemain kembali ke discovery. Itu baseline untuk
diskusi arah produk, **bukan** keputusan redesign atau fitur yang sudah dijanjikan.

## Status live

Angka di bawah adalah yang **terakhir tercatat** per 23 Agustus 2026. Bagaimana
tiap baris sampai ke keadaan itu, beserta probe production dan angka yang
terukur saat rollout, ada di [`docs/14-deploy-log.md`](docs/14-deploy-log.md);
kalau log menyebut versi yang lebih rendah, itu entri historis, bukan
kontradiksi.

| Yang live | Nilai | Rollback |
|---|---|---|
| `app_config.prompt_version` (capture) | `v41` | `v31`, lalu `v20` |
| `evolution_prompt_version` | `v41` | `v30` |
| `synthesis_prompt_version` | `v45` | `v44` |
| `RULES_VERSION` combat | `3` | snapshot `evolution_version=0` tetap legacy |
| Chapter aktif | The Sugarworks v7 | v1–v6 immutable untuk run lama |
| Feature flag | `feature_evolution`, `feature_team_battle`, `feature_expedition`, `feature_chapter_push`, dan `feature_synthesis` semuanya `true` | matikan per flag |

Edge Function ACTIVE, semua `verify_jwt=true` kecuali webhook: `create_anima` 25,
`evolve_anima` 15, `replicate_webhook` 15, `battle_anima` 30, `team_battle` 9,
`expedition` 16, `seeker` 6, `gallery` 19, `shop` 4, `care_anima` 9,
`synthesize_anima` 7.

Team Battle/Defense production sekarang menerima **2–4 Anima** dan builder
selalu muncul sebelum Find Rivals; Expedition tetap tepat 4. Pilihan roster
sekarang benar-benar berurutan dengan badge 1–4 (slot 1 aktif), dan melepas card
yang sudah terpilih benar-benar melepasnya: `TeamRosterList` memakai
`SELECT_TOGGLE`, sebab `SELECT_MULTI` menelan press deselect lalu menjatuhkan
sisa tim saat jari diangkat — builder Expedition memakai list yang sama, jadi ia
ikut sembuh. Menang memakai
**Next Battle**, dan hasil lain memakai **Try Again**; keduanya membuka builder
dengan tim terakhir tetap terpilih. Builder Team sekarang juga memakai row
**Back + Save** seperti Expedition: Back membatalkan edit lalu kembali ke rival
lobby, tetapi Back dikunci selama Save masih commit; semua jalur reopen
memulihkan urutan tersimpan tanpa hub round trip.
Boundary session Duel membersihkan pelat
transient lama dan kegagalan start kembali merender lobby, jadi **Retreating**
tidak bocor ke Anima berikutnya dan kartu Duel tidak menghilang. Migrasi
`20260822152859_team_battle_variable_roster` membawa kontraknya. Unmapped 500
Duel dicatat tanpa raw body ke `battle_failures` yang default-deny
(`20260822155005_battle_failure_log` +
`20260822160718_battle_failure_fk_indexes`), sementara terminal failure
Evolve/Synthesis lewat helper fail-open agar kegagalan logging tidak menimpa
response asli. Sugarworks v7 membetulkan copy ace terakhir dari Cotton menjadi
Nimbelisk tanpa mengubah binary asset atau memanggil model.

Choose Anima dari result Duel terminal sekarang membuka `BattlePickSheet` pada
`z_index=20`, jadi sheet berada di atas fighter, pelat Retreating, dan kartu
hasil. Toast shell tetap satu funnel `_say()` tetapi tingginya sekarang mengikuti
minimum teks, bukan slab tetap 76 px; relayout-nya menunggu satu frame agar
minimum wrapped text sudah aktual dan menolak callback pesan lama lewat revision.
Header kiri menampilkan nama Seeker
(`Guest Seeker` untuk guest), dan row resource hanya menyisakan Cores + Bits;
Collection tetap di tab **Animas**.

APK debug 23 Agustus 2026 05:40 berhasil dibangun
(`com.rekansebangku.scanima` 0.1.0, 57,3 MB) dan memuat ordered/shared Team
builder termasuk busy Back guard, CTA outcome, reset lifecycle + picker layer
Duel, toast compact dengan relayout minimum terbaru, Seeker HUD, enam arena
reframe, serta jalur sign-in guest untuk Publish to Atlas. Manifest tepat memuat
`INTERNET` + `CAMERA`, class kamera ada di dex, signature sah, dan native library
terkompresi. `adb devices -l` butuh 110 detik lalu menjawab kosong — daemon-nya
lambat, bukan device yang tidak terdeteksi. APK ini belum di-sideload dan build
19:48 tanggal 22 tetap yang terakhir terpasang, jadi seluruh perilaku client di
atas masih terverifikasi lewat test headless saja, belum pernah dilihat di
perangkat. Perbaikan `SELECT_TOGGLE` builder Team datang **sesudah** build itu,
jadi APK 05:40 masih memuat tap deselect yang menjatuhkan sisa tim.

Pagar thinking Vision live per 22 Agustus 2026: `thinking_budget: 0` dibuang
wrapper Replicate sebagai nilai falsy, jadi thinking berjalan dinamis dan memakan
`max_output_tokens` sampai JSON Vision terpotong di tengah field — terukur
menggagalkan Evolve stage 2 dengan sisa 162 token teks dari plafon 4.096, dan
meninggalkan tiga kegagalan Synthesis bertanda potongan yang sama. Nilainya
sekarang satu konstanta `VISION_THINKING` (`thinking_budget: 1`) yang di-spread
keenam call site, dan plafon Evolve naik ke 8.192; provenance pengukurannya di
`.cursor/rules/art-and-prompt-pipeline.mdc`, pagarnya skenario 42
`npm run selftest`. Dialog **Evolution Failed** dengan tombol Retry menggantikan
toast di client, dan ia ikut APK 22 Agustus 2026.

Evolve juga tidak lagi mati karena satu sampel Vision yang buruk. Plan yang
ditolak validator disampel ulang maksimal tiga kali dengan keluhan validator
dibacakan kembali ke model **bersama JSON plan yang ditolak**, dan suhu **naik**
0,35→0,60→0,85. Percobaan baru hanya dimulai selama masih di bawah 50 detik
supaya tidak menabrak timeout client 90 detik. Plan berharga $0,003 versus ~$0,05
gambar, jadi ini langkah termurah untuk melawan variansi model; pagarnya
`evolutionPlanResampleAllowed()` di `npm run selftest`.

Suhu itu sempat **turun** 0,35→0,15, dan itu membatalkan seluruh gunanya:
terukur 22 Agustus 2026, tiga sampel Hydron berturut-turut keluar berbeda **satu
kata dari 12.105 karakter**, jadi loop-nya membayar tiga panggilan Vision untuk
nol informasi baru. Sampel ulang harus benar-benar sampel lain. Yang tetap
berguna adalah koreksinya: attempt yang mengerti keluhannya memang
memperbaikinya sendiri — satu sampel melunasi `silhouette_break_contract` dengan
mengganti satu kata.

Yang sebenarnya membunuh dua ritual Hydron itu bukan variansi model melainkan
**validator yang menolak jawaban benar**. `source_basis` menamai struktur yang
terlihat, jadi jawaban benarnya memang pendek, sementara lantainya 12 karakter:
`"stubby legs"` hanya 11, dan ia menggagalkan **enam sampel Plan berturut-turut**
sebelum satu gambar pun dibuat. Lantai itu sekarang `MIN_SOURCE_PHRASE` 4,
disamakan dengan `source_detail` di fungsi yang sama. Dua kontrak lain berhenti
menjatuhkan Plan karena hal yang server sudah tahu jawabannya: entri
`derived_anatomy` yang tidak menelusuri anchor-nya dibuang (prompt v41 menyatakan
array itu boleh kosong dan perakit prompt punya kalimat penggantinya), dan
`realization_mode` di Adult ditegakkan ke `preserve` — satu-satunya nilai sah di
stage itu — tanpa menyentuh `evolved_policy`. Empat dari enam plan yang ditolak
produksi lolos setelah perbaikan ini, termasuk attempt terakhir kedua ritual.
`evolve_anima` 13 membawanya.

Profile punya section **Evolution History** di antara Attributes dan Synthesis
History: silsilah bentuk Anima dari Rookie ke bentuk sekarang, rata tengah,
dengan panah di antaranya. Datanya dari `operation: "history"` di `evolve_anima`
— **read-only**, berdiri sebelum gerbang idempotency karena ia tidak
membelanjakan apa pun. Bentuk lama dibaca dari `anima_forms` (client tidak bisa:
RLS aktif tanpa policy, grant hanya `service_role`), dan **namanya diambil dari
generation yang melahirkannya** lewat `anima_forms.generation_id` →
`generations.vision_result.suggested_name`, sebab `animas.nickname` sudah
menjadi nama bentuk terbaru — terukur 22 Agustus 2026: stage 1 menjawab
`Hydron`, stage 2 `Drowake`. Thumbnail-nya dipotong malas dari sheet yang sudah
dibayar memakai `cropIdleThumb` yang sama dengan Atlas lalu disimpan di
`<uid>/<anima_id>/form_history/<stage>.png`, jadi section ini **nol panggilan
model** berapa kali pun Profile dibuka. Stage 1 tidak pernah memanggil server.
Panelnya dibangun di kode, bukan scene, karena jumlah bentuknya memang berubah;
pagarnya `_test_evolution_history_section()` di `test_scan_ui`.

GPT Image E005 safety false-positive mendapat tepat **satu** redraw otomatis
tanpa mengulang Vision. Provenance 22 Agustus 2026: reference Idle valid
486×535 dikirim sebagai RGBA opak, dan log model mencatat `Unable to infer
channel dimension format` sebelum output ditolak sensitif setelah 47 detik.
Reference sekarang PNG RGB color type 2; kalau E005 masih terjadi, webhook
memakai input allowlist + family-safe suffix dan mengganti prediction secara
atomik lewat `replace_evolution_prediction`. Hanya exact E005 yang boleh retry,
dua attempt total disimpan di `generations.image_attempts`, RPC service-role-only,
dan prediction resmi berstatus failed tidak ditagih menurut dokumentasi
Replicate. Migration `20260822121730_evolution_image_retry`,
`replicate_webhook` 15.

Sesudah pagar itu, Evolve yang sama gagal sekali lagi di post-processing, dan
sebabnya terpisah: `stripWhiteKeylineInPlace()` melahap art putih yang berdiri
sendiri karena tidak ada dark line art yang menghentikannya, jadi dua Z tidur
pecah menjadi remah yang lalu ditolak `auditDetachedCharacterComponents` — dua
pagar di file yang sama saling bertentangan. Stripper sekarang hanya jalan untuk
`promptMajor < 11`, yaitu versi yang memang meminta keyline; `replicate_webhook`
13 membawanya. Provenance dan angkanya di
`.cursor/rules/art-and-prompt-pipeline.mdc`.

Guided Synthesis **live di backend** per 22 Agustus 2026: migration
`20260821121417_anima_synthesis`,
`20260821230502_synthesis_committed_form_only`,
`20260822001202_synthesis_prompt_v43`,
`20260822063112_synthesis_transparent_history_refs`,
`20260822073538_synthesis_name_lineage_v44`, dan
`20260822074932_synthesis_json_close_v45` ter-apply; `synthesize_anima` version 5 ACTIVE, `evolve_anima` version 9 ACTIVE, `create_anima` version 24 ACTIVE, blok uji Synthesis di `quota_rules.sql` lulus terhadap schema production,
`synthesis_prompt_version=v45`, dan `feature_synthesis=true`. V45 menulis
`name_roots` terakhir dan `extractJson()` menutup JSON/fence yang terpotong
(Scan memakai parser yang sama). V44 memakai pipeline morfem capture v41:
Planner mengirim `name_roots`, server merakit nama spesies, dan Evolve
membaca generation Synthesis sebagai birth lineage. V44 tetap rollback. V43 sebelumnya mencantumkan batas prose Planner, 4.096
output token, serta memotong prose valid di trust boundary supaya verbosity
model tidak menggagalkan attempt yang sudah lolos Resonance. Backend sekarang hanya menerima form committed. Reference chroma
Planner dan thumbnail History transparan dipisah; History lama diperbaiki malas
dari sheet Source asli memakai crop Idle Atlas, tanpa panggilan model. Sisi
client-nya — kartu art/picker visual, Incubator Capsule, dialog failure/refund,
Result reveal animation, dan skeleton History — ikut APK 22 Agustus 2026. Jalur
1 Core + 250 Bits terbuka; kalau perlu ditahan, matikan flag-nya.

## Aturan yang tidak bisa dinegosiasikan

1. **API key tidak pernah masuk ke build Godot.** Hanya ada satu, `REPLICATE_API_TOKEN`, dan ia hanya hidup di Supabase Edge Function secrets. Client Godot bicara ke Edge Function, bukan ke Replicate. Satu-satunya pengecualian adalah mode BYOK di mana token milik pemain sendiri disimpan lokal di device.
2. **Setiap panggilan image generation tetap dipagari sebagai biaya ~\$0.07.** Default-nya GPT Image 2 medium. Snapshot Replicate 13 Agustus 2026 mencantumkan auto $0.128, low $0.012, medium $0.047, dan high $0.128 per output image; generation medium terbaru terukur sekitar $0.05 per sheet, sementara dua run lama $0.068 dan $0.072. `pricing.mjs` sengaja tetap memakai $0.07 untuk spend cap konservatif sampai sampel production berulang membenarkan perubahan. Jangan pernah menulis kode yang bisa memanggil generation dalam loop, retry otomatis tanpa batas, atau tanpa idempotency key. Kalau ragu, jangan panggil. **Biaya itu terkunci saat Replicate menjawab, bukan saat post-processing lulus**, jadi menolak sheet di webhook tidak memperbaiki art apa pun — ia menghapus aset yang sudah dibayar lalu menagih pemain lagi. Sejak 22 Agustus 2026 produksi karena itu **memperbaiki** cacat kosmetik (bintik melayang, bocoran seam) lalu mencatatnya di `manifest.qa`, dan hanya menolak sheet yang keying-nya benar-benar gagal; yang menghakimi art tetap `eval/run.mjs`, tempat penolakan murah dan informatif. Sheet yang tetap gagal disimpan mentah ke `anima_sheets/failed_raw/<generation_id>.png` supaya perbaikan pipeline bisa diproses ulang tanpa membayar generation kedua.
3. **Semua mata uang bersifat server-authoritative.** Ada tiga: `scan_charges` (batas percobaan Vision), `genesis_cores` (setiap capture yang diterima), `bits` (Shop). Client boleh menampilkan sisanya, tapi keputusan boleh-tidaknya generate hanya diambil di Postgres dalam transaksi yang sama dengan pencatatan debit. Jangan pernah menambah `genesis_cores` dari callback iklan. Akun Google mendapat **1 Genesis Core otomatis setiap 7 hari server**, tanpa catch-up, saat free bank di bawah 3; grant ledger-backed dan guest tidak eligible.
4. **Jangan commit foto pemain, output generation, atau `.env`.** Foto mentah dihapus dari Storage setelah post-processing selesai.
5. **Wiki pemain ikut berubah di langkah yang sama.** `docs/wiki/` adalah panduan pemain, bukan spek. Setiap perubahan mekanisme yang pemain rasakan (care, Cores/Bits, Battle, traits/EXP/Level, Summon) wajib meng-update halaman wiki yang kena bersamaan dengan kodenya. Tulis yang live, bukan rencana. Rumus dan nama kolom tetap di `docs/04` / file ini.

## Konvensi Godot / GDScript

- Godot 4.x, Mobile renderer, project 2D. Root project ada di `game/`.
- Editor plugin GodotIQ (`addons/godotiq`, v0.5.16) aktif untuk MCP bridge. `GODOTIQ_PROJECT_ROOT` wajib menunjuk `game/` (bukan root repo); config project-nya di `.cursor/mcp.json`. Aturan lengkap di `game/GODOTIQ_RULES.md`. Autoload `GodotIQRuntime` hanya hidup saat debugger editor aktif; di APK ia `queue_free()` sendiri. Jangan commit `game/.godotiq/`.
- Workflow gabungan lintas disiplin hidup di `.agents/skills/godot-ultimate-mode/`; itu sumber kanonis untuk symlink global Cursor/Claude. Skill hanya mengaktifkan gate yang kena (gameplay, UI/UX, animasi, audio, VFX, persistence, performance), lalu wajib me-review implementasi dan memperbaiki temuan in-scope berkeyakinan tinggi sebelum selesai. Ini tooling developer, bukan runtime game.
- File script `snake_case.gd`, nama class `PascalCase`, node `PascalCase`.
- Type hints di mana-mana: `var hp: int = 0`, `func feed(amount: int) -> void:`.
- Referensi node lewat `@onready var sprite: AnimatedSprite2D = %AnimaSprite` (pakai unique name `%`, bukan path panjang yang gampang putus saat scene di-refactor).
- Cek validitas objek dengan `is_instance_valid()` sebelum akses, khususnya untuk node yang bisa di-free saat async request masih jalan.
- Semua state game yang persist lewat satu autoload `GameState`; jangan sebar `save()` ke banyak node.
- Sprite Anima **tidak** diimpor sebagai resource `.import` — datang saat runtime dari server, disimpan di `user://animas/`. Ikon Shop sebaliknya **statis**: `game/assets/catalog/food_sheet.png` dan `item_sheet.png`, mapping ID→sel di `CatalogAtlas`. Runtime tidak memanggil model. `node eval/catalog_art.mjs` menggambar placeholder lokal; `--replicate` memanggil GPT Image 2 medium sekali per sheet (~$0.10 total), tanpa retry. `--rekey` mengulang keying pada PNG yang sudah ada (buang uap neon sat 0,83 yang lolos `satMin` 0,85) tanpa API. Prompt makanan melarang steam/asap hijau — model menggambarnya warna chroma. Sheet production sudah di-commit.
- Lima autoload, urutannya wajib: `SecureStore` (Keystore/Keychain), `GameState` (preference + pending intent), `Backend` (transport HTTP), `LocaleManager`, lalu `AuthFlow` (PKCE/deep link). Refresh/access token dan verifier PKCE tidak lagi hidup di `state.json`; file itu hanya UID, preference, pilihan Anima, dan pending intent nonrahasia. `Backend` menulis sesi ke `GameState`, `GameState` tidak pernah memanggil `Backend`. Yang mengorkestrasi tetap scene: `await Backend.ensure_session()`.
- Account switching memakai satu session aktif + satu `scanima:device_guest_session` permanen per instalasi; jangan membuat vault token Google A/B. Separate menyimpan guest lalu authorize Google, transfer memakai identity link same-UID dan baru menghapus slot guest setelah commit. Google existing tidak pernah di-merge. Sign Out menyiapkan guest dulu, memakai `/logout?scope=local`, lalu reset seluruh state/cache UID lama; Delete Account linked juga wajib me-refresh guest terpisah sebelum penghapusan permanen dimulai. Semua mutation pending memblokir switch **dan Delete Account**. `pending_account_switch` nonrahasia menyelesaikan crash, sementara kehilangan guest yang ditandai wajib ada gagal aman tanpa membuat anonymous baru diam-diam. Recovery marker dan cold-start deeplink dijalankan serial sebelum cache Home boleh dicat; boot memegang satu-satunya reload bila OAuth selesai saat cold start. Setiap pergantian UID menaikkan `GameState.session_epoch`; callback UI, download art, dan dispatch Expedition hanya boleh menulis state bila epoch response masih aktif, lalu konteks shell/Atlas/Expedition di-reset bersama saat handoff.
- Entry point-nya `scenes/scan_flow.tscn`: satu shell persisten yang meng-instance lima child scene `home_view`, `scan_view`, `battle_view`, `collection_view`, dan `anima_details_view`, plus `bottom_nav`. Urutan tab Home, Scan, Battle, Animas, Menu; Battle sengaja ada di tengah. Top HUD menampilkan nama Seeker di kiri (`Guest Seeker` untuk guest) dan hanya Cores/Bits di kanan; Collection tetap lewat tab Animas. Seluruh tombol memakai ikon di atas label, tinggi 100px, dan bar-nya digambar full-bleed 152px sesuai desain. Pada viewport lebar, backdrop nav menjaga aspect ratio dan row lima tab tetap 674px terpusat, jadi pill dan spacing tidak ikut melar. Tab tidak memakai `change_scene_to_file()`, supaya request, pending scan/care/battle, Stage, dan inkubator tidak di-reset saat pemain berpindah layar. Outcome Level Up, Synthesis, dan Evolution dimiliki shell sebagai FIFO global: hasil menunggu modal aktif, lalu tampil di screen mana pun tanpa saling menimpa; Evolution success menawarkan Summon atau Rename. `scenes/anima_demo.tscn` tetap alat periksa art yang dipanggil eksplisit, dan `scenes/home_demo.tscn` adalah harness layout Home: ia meng-instance `home_view.tscn` yang sama dengan production plus HUD, bottom nav, dan overlay Shop/Bag lalu memberi satu row Anima palsu, jadi layout bisa disetel di editor tanpa jaringan atau akun. Keduanya dev tooling dan tidak pernah masuk jalur pemain.
- Background Home/Duel mencampur pasangan PNG siang–malam di shader berdasarkan jam lokal absolut: fajar 05:30–06:30, siang penuh sampai 17:30, dan senja 17:30–18:30, disampel tiap detik supaya resume tidak melompat. Home, Duel, dan Team Battle masing-masing punya varian 9:16 dan 16:9 yang dipilih dari aspect viewport. Kaki Home tetap pada ground line 68% portrait / 69% landscape di **rect art dasar**, bukan pada viewport. Karena pasangan portrait day/night menggambar pusat dais pada row berbeda, background portrait diberi overscan 1,11× lalu focal point dais-nya diikat ke Stage; background yang bergerak halus saat blend, bukan Anima. Home juga memberi contact shadow radial yang mengikuti bbox kaki dan visibility pose. Enam background statis Duel/Team portrait/landscape day/night sekarang mengomposisi foot-contact baseline 91% seperti Expedition/Boss; runtime memakai cover maksimum 1,0× dan pan vertikal `0.5` agar crop portrait mempertahankan langit, sedangkan background chapter tetap boleh zoom sampai 1,55×. Duel memakai dock 2×2, Team menonjolkan Attack/Special di baris dua kolom lalu Guard/Item/Switch/Retreat di baris empat kolom, sedangkan Expedition tetap 3+3. Art Home hidup di root canvas di belakang `Stage`; peta node The Sugarworks memakai top-view sendiri, dan art chapter dari server tetap menang serta tetap center-crop di combat Expedition.
- `Backend.gd` satu-satunya tempat yang tahu URL project dan kunci. Kuncinya **publishable** (`sb_publishable_...`) dan memang ikut ke dalam build; yang membatasi akses RLS, bukan kerahasiaannya. Terukur diterima endpoint yang dipakai client: `auth/signup`, `auth/token`, identity authorize/link, REST, Storage, dan `functions/v1` (`create_anima`, `care_anima`, `battle_anima`, `shop`, `seeker`, `gallery`). Yang tidak boleh masuk ke sana sampai kapan pun: `REPLICATE_API_TOKEN` atau service role key.
- Yang persist hanya sesi aman aktif + guest perangkat + verifier PKCE sementara di SecureStore, marker `pending_oauth`/`pending_account_switch` nonrahasia, scan yang sedang berjalan, satu `pending_care`, satu `pending_battle` berisi session/turn/version + intent + idempotency key, dan satu `pending_purchase`. Saldo, kebutuhan, tas, profil Seeker, dan daftar Anima **selalu** dibaca ulang dari Postgres — server yang berwenang. Pending intent dihapus hanya setelah server menjawab; timeout/restart me-replay key yang sama supaya Bits, damage, reward, atau grant Google tidak commit dua kali.

## Konvensi backend

- Supabase Edge Functions berjalan di Deno. Pakai `npm:` specifier hanya untuk paket pure-JS/TS. **Jangan pakai `sharp`** (butuh native binary, tidak jalan di edge runtime); untuk manipulasi piksel pakai `ImageScript`.
- **`npm:imagescript` GAGAL di edge runtime** dengan galat arch/platform tidak didukung, walaupun paketnya pure-JS. Yang jalan adalah `https://deno.land/x/imagescript@1.2.15/mod.ts` lewat `functions/import_map.json`. Node di-pin ke `imagescript@1.2.15` supaya dua runtime memakai versi yang sama; jangan naikkan salah satunya sendiri.
- **Kode yang dipakai dua runtime hidup di `functions/_shared/` sebagai `.mjs`**, bukan disalin ke masing-masing sisi: `postprocess.mjs` (keying + slicing), `vision.mjs` (parsing, gate, perakitan prompt), `pricing.mjs` (harga per panggilan), `battle.mjs` (seluruh formula combat), dan `catalog.mjs` (harga/efek toko + reward tier). Deno bisa mengimpor `.mjs` apa adanya, dan eval mengimpor file yang sama. Dua salinan berarti eval bisa lulus sementara produksi memakai aturan lain.
- **Tidak ada endpoint unggah foto.** Client menulis langsung ke bucket `photos` dengan anon key-nya; yang membatasinya adalah policy Storage (`(storage.foldername(name))[1] = auth.uid()`) plus `file_size_limit` dan `allowed_mime_types` milik bucket. `create_anima` hanya menerima `photo_path` dan memeriksa prefix-nya. Menulis endpoint penerbit signed URL berarti menulis ulang pagar yang sudah disediakan platform.
- Satu jalur uang capture v13: `claim_capture` mendebit satu Core + membuat generation + Anima + ledger dalam satu transaksi. `claim_genesis`/`record_cache_hit` dipertahankan service-role-only hanya untuk rollback legacy; capture baru tidak membaca atau menulis `species_library`. Shop tetap lewat `purchase_catalog_item`.
- Migrasi SQL di `backend/supabase/migrations/`, satu file per perubahan, tidak pernah diedit setelah di-apply ke remote.
- RLS wajib aktif di semua tabel yang menyimpan data pemain. Edge Function pakai service role key, client pakai anon key.
- Semua endpoint yang menghabiskan uang menerima `idempotency_key` dari client.
- Proyek remote: **Scanima**, ref `kgcaisvmmpxswevjvgft`, region `ap-northeast-1`, Postgres 17. Empat migrasi pertama di-apply lewat Supabase MCP, dan nama file lokal sengaja disamakan dengan versi yang dicatat remote supaya `supabase migration list` tidak melihat drift. Kalau apply lewat MCP lagi, samakan lagi nama filenya sesudahnya.
- **Fungsi yang menyentuh mata uang wajib dicabut EXECUTE-nya dari `anon` dan `authenticated`.** Postgres memberi EXECUTE ke PUBLIC secara default, jadi fungsi SECURITY DEFINER di schema `public` otomatis menjadi endpoint di `/rest/v1/rpc/<nama>`. Untuk `refund_generation` itu berarti pemain bisa mengembalikan Core-nya sendiri sementara gambarnya tetap kita bayar. Pola yang dipakai: `revoke all ... from public, anon, authenticated` lalu `grant execute ... to service_role`.
- Hak tulis client diberikan **per kolom**, bukan per tabel: `revoke update on <tabel>` lalu `grant update (<kolom yang boleh>)`. Dengan begitu kolom baru di masa depan otomatis tertutup. Ingat bahwa `revoke update on <tabel>` juga mencabut hak kolom, jadi sesudahnya hak kolom harus diberikan ulang.

## Prompt versioning

Prompt hidup di `backend/prompts/<version>/` sebagai file teks, bukan string literal di dalam kode.

Pohon versi lengkap beserta provenance setiap versi yang ditolak ada di
[`docs/16-prompt-version-history.md`](docs/16-prompt-version-history.md). Yang
production sekarang **v41** untuk capture maupun evolution; kontrak siluet,
mobility, dan face-age v29 serta art v30 tetap berlaku di dalamnya, dan v31/v30
adalah rollback. Adult Veridian v26, Adult Sunhound v28, Evolved Sunhound v29,
serta Adult+Evolved Playtron v29 terkunci per Anima lewat
`anima_evolution_locks`; lock Plan membawa `suggested_name` operator.

**Prompt tidak bisa dibaca sebagai file di Edge Function.** `Deno.readTextFile()` gagal untuk file pendamping yang dideploy lewat MCP, jadi `backend/tools/bundle_prompts.mjs` membundel semua versi menjadi `functions/_shared/prompts.generated.ts` yang diimpor sebagai modul. Sumbernya tetap file `.md` di git; artefaknya turunan. Setelah mengubah prompt: `node backend/tools/bundle_prompts.mjs`. Skenario 17 di `npm run selftest` gagal kalau bundelnya basi, jadi kelupaan ketangkap gratis, bukan saat art produksi ternyata berbeda dari art yang sudah disetujui.

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md) dan sumber art direction v2 ada di [docs/monster_camera_anime_cel_shaded_style_guide.md](docs/monster_camera_anime_cel_shaded_style_guide.md). Jangan mengarang aturan style baru; konsistensi visual antar Anima bergantung pada style lock itu.

## Tripwire build dan mesin ini

Lima hal yang gagal **senyap** — tanpa galat yang menunjuk sebabnya — jadi
kelimanya tetap di sini alih-alih di rule ber-glob yang belum tentu dimuat
saat build atau push dijalankan.

- **Mesin ini memegang dua identitas GitHub dan default-nya identitas kerja, jadi `origin` wajib SSH.** Sama seperti `SUPABASE_ACCESS_TOKEN` yang menunjuk org kerja: `~/.gitconfig` mengarahkan kredensial HTTPS ke `gh auth git-credential`, dan helper itu **hanya melayani akun aktif** — terukur, permintaan untuk `username=ryansetia1` dijawab kosong sementara permintaan tanpa username dijawab `ryansetiawan-tiket`. Remote HTTPS karena itu ditolak GitHub dan Cursor menawarkan membuat fork; menerimanya memindahkan `origin` ke akun kerja. `user.name`/`user.email` per-repo **tidak** memperbaikinya — itu hanya author commit, bukan autentikasi. Pagarnya `origin = git@github-personal:ryansetia1/Scanima.git`; alias itu ada di `~/.ssh/config` dan memakai `id_ed25519_personal` dengan `IdentitiesOnly yes`, sedangkan `git@github.com` sengaja tetap milik akun kerja. Verifikasinya `ssh -T git@github-personal` harus menjawab `Hi ryansetia1!`. `.git/config` tidak ikut git, jadi clone berikutnya harus memakai URL SSH itu sejak awal.
- **Izin `INTERNET` MATI secara default di ekspor Android Godot 4, dan ini kegagalan yang paling mahal waktunya.** APK pertama yang dibangun di sini keluar dengan `CAMERA` sebagai satu-satunya izin: ia terpasang, terbuka, lalu mati di sign-in anonim — tanpa dialog izin, tanpa crash, cuma galat jaringan yang menyesatkan, sebab Android menolak socket-nya secara senyap. Preset **wajib** memuat `permissions/internet=true`. `export_presets.cfg` di-gitignore, jadi tidak ada uji di repo yang bisa menjaga ini; catatan ini adalah pagarnya, dan `aapt2 dump permissions` sesudah build adalah pemeriksaannya.
- **Template Android 4.6.2 mematok Gradle 8.11.1, jadi JDK-nya tidak boleh lebih baru dari 23.** Mesin ini punya JDK 26 dan build-nya berhenti di `Unsupported class file major version 70` sebelum menyentuh kode kita. Yang dipakai: `brew install openjdk@17` — **formula, bukan cask `temurin@17`**, sebab cask memasang ke `/Library/Java/...` dan menuntut sudo sementara formula tidak. JDK 26 **tidak** perlu dihapus walau banyak jawaban forum menyuruhnya: Godot punya setelan `Java SDK Path` sendiri, jadi keduanya hidup berdampingan. Alternatif menaikkan `distributionUrl` di `gradle-wrapper.properties` menukar satu masalah pasti dengan pasangan Gradle/AGP yang tidak diuji siapa pun.
- **Godot membaca `ANDROID_HOME` tapi TIDAK membaca `JAVA_HOME`.** SDK-nya terdeteksi sendiri; jalur JDK harus ada di `export/android/java_sdk_path` pada `editor_settings-4.6.tres` (nama file-nya per-minor, bukan `editor_settings-4.tres`). Menulisnya lewat file **hanya aman saat editor tertutup** — editor menyimpan setelannya sendiri ketika keluar dan akan menimpa suntingan dari luar. `export/android/debug_keystore` juga sudah diisi sendiri oleh editor ke keystore yang belum ada; ia dibuat lambat memakai `keytool` dari JDK, jadi preset di sini menunjuk `~/.android/debug.keystore` yang nyata ada supaya hasilnya deterministik.
- **APK sideload memakai native-library compression.** `export_presets.cfg` wajib memuat `gradle_build/compress_native_libraries=true`: pada debug APK, 71,47 MB dari total 76 MB adalah `libgodot_android.so`, dan opsi ini terukur menurunkan berkas transfer ke 54,7 MB pada build 22 Agustus 2026 — nyata, tetapi jauh dari perkiraan awal ~30 MB, jadi jangan pakai angka itu untuk merencanakan ukuran rilis. Trade-off-nya startup sedikit lebih lambat dan ukuran terpasang tidak banyak berubah; untuk AAB Play Store, evaluasi ulang dan umumnya biarkan library tidak terkompresi.

## Perintah umum

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

```bash
# gratis, jalankan ini dulu
npm run selftest                       # 42 skenario + 12 uji tanda tangan webhook
godot --headless --path game --script res://tests/test_sprite_slicing.gd # 174 check manifest, loader, presenter, Boss Seeker
godot --headless --path game --script res://tests/test_auth_flow.gd    # 63 check PKCE secure, restart, transfer/separate, recovery, no-merge
godot --headless --path game --script res://tests/test_client_state.gd  # 196 check sesi, refresh, pending scan/care/Battle/Shop/evolution, cache art, cache boot, stale UID, retry transport
godot --headless --path game --script res://tests/test_scan_ui.gd       # 1266 check shell + Battle + Shop + Bag + komponen + tap + touch + UI/SFX hooks + prediksi turn/care/Summon + rollback + cache boot + Trophy Showcase/evolution/Atlas + dialog Evolve gagal + preflight nama + LoadingScreen
godot --headless --path game --script res://tests/test_i18n.gd          # 4749 check katalog + key + formatter + wrapping
godot --headless --path game --script res://tests/test_game_rules.gd    # 181 check care + EXP/Level/evolution + kontrak event Battle
godot --headless --path game --script res://tests/test_expedition_route_map.gd # 91 check route tree + preview/Enter Node + Skip Shop + prediksi turn/Switch/penutup Boss + preload art run
node backend/tools/emit_sim_vectors.mjs                                 # regen golden vector JS -> GDScript, nol panggilan API
godot --headless --path game --script res://tests/test_battle_sim_parity.gd # 590 check parity simulasi client vs _shared
node eval/run.mjs --set smoke --dry-run # cek foto + template tanpa API

# regenerasi golden vector kalau formula combat berubah; nol panggilan API
node backend/tools/emit_sim_vectors.mjs

# setelah mengubah prompt: regenerasi bundel yang dipakai Edge Function
node backend/tools/bundle_prompts.mjs
node backend/tools/bundle_prompts.mjs --check   # gagal kalau bundel basi

# menguji ulang post-processing pada sheet yang SUDAH dibayar, nol panggilan API
node eval/run.mjs --set smoke --reprocess

# kontrak Node <-> Godot, juga gratis
node eval/selftest.mjs --emit /tmp/scanima_e2e
godot --headless --path game --script res://tests/test_sprite_slicing.gd \
    -- --manifest=/tmp/scanima_e2e/manifest.json

# eval prompt, BERBIAYA
node eval/run.mjs --set smoke --vision-only  # gate + stat saja, ~$0.015
node eval/run.mjs --set smoke                # 5 foto, ~$0.225, untuk iterasi
node eval/run.mjs --set full                 # 20 foto, ~$1.32, gerbang penerimaan

# aturan kuota dan pagar akses, gratis, jalankan setiap kali migrasi berubah
supabase db query --file backend/tests/quota_rules.sql --linked
# (atau lewat Supabase MCP execute_sql dengan isi file itu; lulus = NOTICE
#  "SEMUA UJI LULUS", gagal = satu ASSERT yang menyebut invarian yang rusak)

# deploy Edge Function — PAT lewat env, bukan `supabase login`, lihat di bawah
# Shop sudah live di remote. Deploy ulang shop/care_anima/battle_anima hanya
# kalau RPC atau Edge Function berubah. CLI `supabase` di mesin ini bisa
# terikat org yang salah — pakai MCP atau `SUPABASE_ACCESS_TOKEN` yang
# `projects list`-nya memuat Scanima. Smoke 401, baru client.
export SUPABASE_ACCESS_TOKEN=sbp_...
cd backend && supabase functions deploy create_anima replicate_webhook \
  care_anima battle_anima shop seeker \
  --project-ref kgcaisvmmpxswevjvgft
supabase secrets set REPLICATE_API_TOKEN=... --project-ref kgcaisvmmpxswevjvgft

# smoke check sesudah deploy: nol kredensial, nol biaya.
# 401 = fungsi boot dan pagar JWT/signature berdiri. 500 = modulnya gagal impor.
F=https://kgcaisvmmpxswevjvgft.supabase.co/functions/v1
curl -sS -X POST $F/create_anima -d '{}'
curl -sS -X POST $F/seeker -d '{}'
curl -sS -X POST $F/shop -d '{}'
curl -sS -X POST $F/care_anima -d '{}'
curl -sS -X POST $F/battle_anima -d '{}'
curl -sS -X POST $F/replicate_webhook -H 'webhook-id: a' \
  -H 'webhook-timestamp: 1' -H 'webhook-signature: v1,eA==' -d '{}'
```

Katalog demo visual, uji terhadap production, dan perintah Android ada di
[`docs/15-commands.md`](docs/15-commands.md).

**Deploy butuh CLI yang terautentikasi ke project ini, dan `supabase login` bukan caranya.** Supabase MCP bisa apply migrasi dan menjalankan SQL, dan `deploy_edge_function`-nya juga jalan, tapi ia menuntut isi setiap file ditempelkan ke dalam panggilan (bundel prompt saja 65 KB) dan **tidak bisa memasang secret sama sekali**.

Yang terukur di mesin ini: `supabase login` memakai sesi browser yang sudah aktif tanpa bertanya, jadi ia bisa "berhasil" ke akun yang salah. Lebih buruk, `supabase login --token sbp_...` juga membalas "You are now logged in" sementara `supabase projects list` **tetap** memuat project akun lama — token baru itu tidak menang atas kredensial yang sudah tersimpan. Yang menang adalah env var:

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
supabase projects list   # Scanima harus muncul di sini sebelum lanjut
```

Dengan env var itu, `link` tidak diperlukan; cukup `--project-ref`. Kalau ragu token siapa yang dipegang, tanya langsung ke Management API — `curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" https://api.supabase.com/v1/organizations` harus menjawab `rekansebangku`, bukan organisasi lain.

Pisau itu bermata dua, dan pada 22 Agustus 2026 mata satunya yang kena: shell di
mesin ini sudah membawa `SUPABASE_ACCESS_TOKEN` milik **org kerja**, jadi env var
yang biasanya menyelamatkan justru merampas project yang benar — `projects list`
memuat tiketdesign dan `organizations` menjawab `PT Global Tiket Network`. Karena
env var menang, satu-satunya jalan adalah membuangnya per perintah: `env -u
SUPABASE_ACCESS_TOKEN supabase ...` memakai kredensial tersimpan, yang di mesin
ini memang milik Scanima dan sudah ter-`link` (`backend/supabase/.temp/project-ref`
berisi `kgcaisvmmpxswevjvgft`). Jadi periksa isi env var itu **sebelum** memakainya;
kalau ia bukan `rekansebangku`, `env -u` dulu, jangan `export` lagi.

Dengan project yang sudah ter-link, migrasi lebih baik lewat `supabase db push
--linked --workdir backend` daripada MCP `apply_migration`: versi yang tercatat
remote sama dengan nama file lokal, jadi tidak ada langkah rename dan
`migration list` tetap bersih. Jalankan `--dry-run` lebih dulu untuk melihat
tepatnya file mana yang akan naik. Ia butuh password database, dan yang tersimpan
dari `link` sudah cukup; `psql` langsung ke pooler tidak punya password itu.

`REPLICATE_WEBHOOK_SECRET` **tidak ada dan tidak perlu dibuat**: `replicate_webhook` mengambil rahasia penanda tangan dari `GET /v1/webhooks/default/secret` memakai token yang sudah ada, lalu men-cache-nya selama instance hidup. Satu kredensial lebih sedikit berarti satu langkah setup yang tidak bisa terlupakan — dan webhook tanpa verifikasi berarti siapa pun bisa mengisi pustaka art yang di-share semua pemain.

`backend/tests/quota_rules.sql` aman dijalankan di proyek remote: ia satu blok `DO`, jadi satu transaksi. Assert yang gagal me-rollback semuanya termasuk user uji dan grant sementara yang dipakai untuk menguji trigger; kalau lulus, barisnya dihapus sendiri di akhir. Jangan mengubahnya menjadi banyak statement terpisah, karena sifat itulah yang membuatnya boleh menyentuh database produksi.

Default-nya `smoke`, prompt `v7`, dan GPT Image 2 `medium`. Jangan jalankan `full` sebagai bagian dari iterasi biasa — ia enam kali lebih mahal dan tidak memberi informasi tambahan sampai Smoke Set sudah bersih. Sebelum memicu satu pun generation gambar, `--vision-only` sudah cukup untuk menguji gate keamanan dan pemetaan stat dengan biaya ~$0.015.

**Kalau yang diubah cuma post-processing, jangan bayar generation lagi.** `--reprocess` menyusun ulang sheet, manifest, dan contact sheet dari `raw.png` run sebelumnya tanpa satu pun panggilan API, jadi perubahan keying/slicing bisa diverifikasi terhadap gambar model sungguhan dengan biaya nol. Ia sengaja tidak menimpa `vision.json` dan `prompt.txt`, karena keduanya catatan run yang menghasilkan `raw.png` itu.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`

## Di mana sisanya hidup

Lima rule di bawah `alwaysApply: false` dan hanya masuk konteks saat file yang
cocok dengan glob-nya disentuh. Isinya dipindahkan verbatim dari file ini, jadi
angka terukurnya tidak berubah — kalau butuh detail satu domain, buka
rule-nya, jangan menebak.

| Rule | Dimuat saat menyentuh | Isi |
|---|---|---|
| `.cursor/rules/battle-and-expedition.mdc` | script/scene Battle, Team, Expedition, `sim/`, `anima_presenter.gd`, Edge Function battle/team/expedition, `backend/chapters/` | Prediksi turn, PP, initiative, tier hadiah, gate lawan Duel, lawan sistem, ace Boss, skala/framing arena, chapter runtime |
| `.cursor/rules/client-shell-ui.mdc` | `game/scripts/`, `game/scenes/`, theme, shader, locale, test | Theme, komponen, `LoadingScreen`, jebakan Tween, audio, state layar, cache boot, Care Dock/Shop/Bag |
| `.cursor/rules/backend-guardrails.mdc` | `backend/` | Identitas dan guest, care authoritative, decay, gerbang nama, RLS, advisor yang disengaja, jebakan PostgREST |
| `.cursor/rules/art-and-prompt-pipeline.mdc` | `backend/prompts/`, `_shared/postprocess`/`vision`/`png`, `create_anima`, `evolve_anima`, `backend/tools/`, `eval/` | Vision dan wrapper Replicate, chroma key, slicing, encoder PNG, latensi model, art direction chapter |
| `.cursor/rules/android-and-plugins.mdc` | `game/android/`, `game/addons/`, preset export, `scan_flow.gd`, `auth_flow.gd` | Plugin kamera, OAuth/deep link, sinyal plugin, verifikasi APK |

Dua rule lain sudah ada sejak sebelumnya: `player-wiki.mdc` (`alwaysApply: true`)
dan `sfx-presentation.mdc`.

| Dokumen | Isi |
|---|---|
| [`docs/14-deploy-log.md`](docs/14-deploy-log.md) | Riwayat rollout: Atlas, Name Lineage v41, gerbang Rename, Capture Vibe, gate IP, Evolution art, Battle polish, gate lawan Duel, daftar migration |
| [`docs/15-commands.md`](docs/15-commands.md) | Katalog `--*-demo`, uji terhadap production, build/verifikasi APK, backend lokal |
| [`docs/16-prompt-version-history.md`](docs/16-prompt-version-history.md) | Pohon `backend/prompts/` v1–v41 dan provenance setiap versi yang ditolak |

Indeks dokumen selengkapnya ada di [README.md](README.md); panduan pemain di
[`docs/wiki/`](docs/wiki/README.md).
