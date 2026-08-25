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
| Feature flag | `feature_evolution`, `feature_team_battle`, `feature_expedition`, `feature_chapter_push`, `feature_synthesis`, dan `feature_atlas_moderation_v2` semuanya `true` | matikan per flag |

Edge Function ACTIVE, semua `verify_jwt=true` kecuali webhook: `create_anima` 25,
`evolve_anima` 15, `replicate_webhook` 15, `battle_anima` 30, `team_battle` 10,
`expedition` 16, `seeker` 6, `gallery` 19, `shop` 4, `care_anima` 9,
`synthesize_anima` 7, `admin_moderation` (staff-only, tanpa rate limit publik).

Atlas Moderation Admin v2 live 23 Agustus 2026: migration
`20260823080000_atlas_moderation_v2_schema` ter-apply, `admin_moderation`
dan `gallery` (moderasi dua-pass) dideploy, admin pertama
(`ryansetiawan.works@gmail.com`) sudah di-bootstrap sebagai `admin` di
`staff_accounts`, dan `feature_atlas_moderation_v2=true`. Redirect
`http://localhost:3000/auth/callback**` ditambahkan ke allowlist Auth lewat
Management API secara surgical (PATCH hanya field `uri_allow_list`, bukan
`supabase config push` — file `config.toml` lokal punya entri
`https://127.0.0.1:3000` yang TIDAK pernah benar-benar live di remote, dan
section Google OAuth-nya memakai placeholder `env(...)` yang akan menimpa
client secret asli kalau di-push utuh). Setelah apply migration,
`staff_accounts` dan tabel baru lain sempat menjawab 500 dari
`admin_moderation` karena cache schema PostgREST belum reload untuk tabel
yang baru dibuat; `notify pgrst, 'reload schema'` memperbaikinya seketika —
kalau tabel baru menjawab lewat SQL langsung tapi tidak lewat `.from()`
client, ini pagarnya.

Team Battle production menerima **2–4 Anima** dan rival selalu persis sebesar
roster pemain. Candidate pemain dirakit dari publication Atlas approved beberapa
Seeker, boleh bercampur pemilik tanpa owner/nickname privat; template sistem
dipotong ke ukuran yang sama lalu balancing combat power lama tetap memilih
tiga yang terdekat. Tidak ada lagi UI **Publish Defense** — Publish to Atlas
adalah consent-nya. RPC Defense legacy tetap wire-compatible untuk rollback,
tetapi tidak dibaca candidate baru. Migration
`20260823003917_atlas_team_rivals` membawa source `atlas` dan pagar exact-size;
`20260823073500_fix_veridian_public_name` memperbaiki projection Veridian di
Gallery/Atlas/snapshot Duel tanpa menyentuh Rename privat.

Builder selalu muncul sebelum Find Rivals; Expedition tetap tepat 4. Pilihan
roster benar-benar berurutan dengan badge 1–4 (slot 1 aktif), dan melepas card
yang sudah terpilih benar-benar melepasnya: `TeamRosterList` memakai
`SELECT_TOGGLE`, sebab `SELECT_MULTI` menelan press deselect lalu menjatuhkan
sisa tim saat jari diangkat — builder Expedition memakai list yang sama, jadi ia
ikut sembuh. Picker keduanya sekarang juga menulis Level. **Back + Save Team**
berbagi lebar 50/50; Back membatalkan edit lalu kembali ke rival lobby dan tetap
dikunci selama Save commit. Menang memakai **Next Battle**, hasil lain memakai
**Try Again**, dan semua jalur reopen memulihkan urutan tersimpan tanpa hub round
trip.

Boundary session Duel membersihkan pelat transient lama dan kegagalan start
kembali merender lobby, jadi **Retreating** tidak bocor ke Anima berikutnya dan
kartu Duel tidak menghilang. HUD nama/HP Duel sekarang dibungkus satu pelat, dan
music cue membaca arena yang benar-benar terlihat supaya session Duel/Team yang
tersembunyi tidak menahan musik battle di mode lobby lain. Atlas memberi
**Publishing…/Unpublishing…**, membersihkan state publication Anima sebelumnya
sebelum status baru tiba, dan mempertahankan penolakan moderation sebagai tombol
disabled **Cannot publish to Atlas** alih-alih menghilangkannya. Pagination tetap
mempertahankan grid saat page terakhir kosong dan menyembunyikan Load More saat
cursor habis. Unmapped 500 Duel dicatat tanpa
raw body ke `battle_failures` yang default-deny
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

APK debug 23 Agustus 2026 **08:03** dibangun dan **terpasang** di perangkat
(`com.rekansebangku.scanima` 0.1.0, 57.273.971 byte; `lastUpdateTime`
08:10:05 menggantikan build 06:44). Ia memuat feedback Publish Atlas, pagination
akhir, Level picker, builder 50/50 tanpa Publish Defense, rival exact-size,
perbaikan nama Veridian, pelat HUD + musik lobby Duel, serta seluruh perubahan
build sebelumnya. Manifest tepat memuat `INTERNET` + `CAMERA`, class kamera ada
di dex (22 rujukan `GodotGetImage`), dan signature v2 sah. Export inkremental
selesai 9,8 detik; enam script client yang berubah terukur ada sebagai `.gdc` di
APK. Script itu tertokenisasi penuh, jadi jangan mencari nama identifier di
dalam APK.

APK follow-up UAT **12:55** (57.276.155 byte) sudah dibangun dan diverifikasi:
`INTERNET` + `CAMERA`, signature v2, serta `anima_details_view.gdc`,
`scan_flow.gdc`, dan `test_scan_ui.gdc` ada. Build ini membawa state moderation
Atlas yang tidak menghilang/berkedip serta musik lobby sesudah keluar Team
Battle. Ia **terpasang** pukul 13:10:50 (`com.rekansebangku.scanima` 0.1.0)
setelah endpoint Wireless debugging berpindah ke `100.96.188.61:42349`;
streaming install pertama putus tanpa diagnostic, lalu `--no-streaming`
mendorong 57 MB lewat DERP selama 200 detik dan sukses.

APK debug 23 Agustus 2026 **22:24** (54,6 MB) dibangun dan **terpasang**
membawa seluruh client Atlas Moderation Admin v2: tombol **Under Review**,
**Request Review** (appeal, satu kali per versi art), dan category sheet
Report (character/sexual/gore/hate/other) menggantikan one-tap report lama.
`INTERNET` + `CAMERA` tepat dua izin, 22 rujukan `GodotGetImage` di dex,
signature v2 sah. Endpoint Wireless debugging pindah ke `100.96.188.61:34921`
untuk build ini; streaming install langsung sukses tanpa perlu
`--no-streaming`.

Dua bug lanjutan dari UAT build itu sendiri: dialog reject player selalu
menampilkan pesan generik meski staff mengisi reason/note spesifik. Sebabnya
dua lapis. Pertama, `scan_flow.gd`'s `_refresh_gallery_status()` tidak pernah
meneruskan `reject_category`/`reject_note`/`appeal_available` dari respons
`my_status` ke dict yang dikirim ke `set_gallery_status()` — backend dan
`anima_details_view.gd` sudah benar, tapi jembatan di `scan_flow.gd` bolong.
Kedua, `rejectionDetails()` di `gallery/index.ts` hanya membaca
`moderation_cases.category`, yang selalu `null` untuk case dari appeal
(appeal tidak pernah menjalankan Vision) — staff punya `reason_code` sendiri
(preset seperti `ip_character_match`) yang tidak pernah dipetakan balik ke
kategori pemain. Diverifikasi lewat kasus nyata "Padronic":
`case_category: null`, `reason_code: 'ip_character_match'`, note "Looks like
playstation" — pemain tetap melihat pesan generik. Fix: `rejectionDetails()`
sekarang fallback ke `category = 'ip_character'` saat `reason_code ===
'ip_character_match'` dan case/cache category null; kategori lain
(`unsafe_content`, `report_upheld`, dst.) tidak punya pemetaan satu-satu ke
salah satu dari empat kategori pemain, jadi tetap jatuh ke pesan generik.
`gallery` di-deploy ulang. APK debug 23 Agustus 2026 **23:48** (54,6 MB)
membawa fix `scan_flow.gd` dan terpasang di perangkat yang sama.

UAT lanjutan menemukan lima hal lagi, semuanya di-root-cause sebelum ditambal.
Tombol Publish/Cannot Publish di Profile tidak muncul sama sekali selama
round trip `my_status` (tidak ada gambaran error, tapi juga tidak ada gambaran
loading), lalu tiba-tiba muncul setelah beberapa detik — `anima_details_view.gd`
sekarang punya state `_gallery_loading` terpisah yang menampilkan tombol
disabled bertuliskan **Checking Atlas status…** sejak `set_anima()` dipanggil,
bukan menyembunyikannya sampai jawaban server tiba. Dialog manapun yang isinya
teks panjang/baru kadang terlalu tinggi tepat di pembukaan **pertama**, dan
baru pas sesudah dibuka ulang: `ui_modal.gd`'s `_fit_body_scroll()` dipanggil
lewat `call_deferred()`, yang jalan **sebelum** `Label` ber-autowrap sempat
menghitung ulang wrap line-nya untuk lebar sebenarnya, sehingga height yang
terukur salah dan tidak pernah dihitung ulang. Diganti pola yang sama dengan
toast (`_relayout_toast_after_minimum_update`): menunggu satu
`await get_tree().process_frame` penuh, dijaga revision counter supaya dua
pemanggilan berturut (dari `_configure()` dan `_show_modal()`) tidak saling
menimpa. `BattlePickSheet`'s daftar Anima cuma menampilkan sekitar 4 Anima dan
Team Battle roster builder terasa tidak bisa digulir sama sekali — akar
masalahnya sama untuk keduanya: `UiJuice.relay_touch_scroll()` (dipasang
global sejak boot untuk meneruskan drag ke `ScrollContainer` leluhur) menyapu
**semua** Control ber-`mouse_filter=STOP`, termasuk `ItemList`, yang sudah
punya scrollbar dan penanganan drag-nya sendiri. Membalik `ItemList` ke PASS
membuat drag yang sama diperebutkan `ItemList` dan `ScrollContainer` pembungkus
sekaligus, dan di layar sentuh nyata itu terasa seperti "tidak bisa digulir
sama sekali". Fix-nya satu guard `if control is ItemList or control is Tree:
return` di `relay_touch_scroll`, menyembuhkan `BattlePickSheet` maupun
`TeamRosterList` (dipakai builder Team Battle dan Expedition) sekaligus karena
keduanya lewat fungsi bersama yang sama. `BattlePickSheet` juga mendapat Level
di baris daftarnya (`BATTLE_PICK_ITEM_META`, sebelumnya cuma nama + elemen).
Profile sekarang punya badge **Published to Atlas** / **Not published to
Atlas** di sebelah nama, dan nama Seeker di Top HUD serta nama+meta Anima di
Home kini bisa disentuh untuk membuka Seeker Profile / Anima Profile masing-
masing (`_on_brand_input` di `scan_flow.gd`, `anima_profile_requested` baru
di `home_view.gd`), tanpa mengubah kontrak signal yang sudah ada.
`test_scan_ui` naik ke 1386 check, `test_i18n` ke 4965. Di sisi admin,
dropdown Status/Source di Queue sekarang auto-navigate lewat `router.push` di
komponen client `QueueFilters` (bukan submit form manual), dan setiap route
`(protected)/*` punya `loading.tsx` sendiri (skeleton spinner bersama
`PageLoading`) supaya navigasi App Router — termasuk ganti query param di
halaman yang sama — tidak pernah terasa diam; `ActionPanel` juga menambah
indikator **Working…** saat `pending`. APK debug 24 Agustus 2026 **00:29**
membawa keenamnya dan terpasang di perangkat yang sama.

Tiga tab Anima (Collection, Synthesis, Atlas) diseragamkan dengan menghapus PanelContainer `LabSurface` (`LabPanel`) dari `SynthesisLabView` di `scan_flow.tscn`, menyatukan struktur layout VBoxContainer `Column` di ketiga tab sebagai anak langsung Control view masing-masing dengan anchors fill (`layout_mode=1`, `anchors_preset=15`). Untuk meredam gangguan visual animasi background, dibuat PanelContainer baru (`SynthesisPanel` dan `AtlasPanel`) dengan style box flat gelap semi-transparan (`Color(0.025, 0.04, 0.095, 0.74)` dengan border 1px dan corner radius 18) untuk membungkus kontainer scroll utama di Synthesis dan Atlas. Bug transisi Synthesis diselesaikan dengan menambahkan case `SYNTHESIS_DEST` pada `_active_view()` di `scan_flow.gd` agar mengembalikan `_synthesis_view` secara tepat (sebelumnya fallback ke `_home_view`, yang memicu penayangan needs panel/CareDock secara keliru dan melewatkan animasi kemunculan Synthesis).

"Battle picker cuma menampilkan 4 Anima" butuh **empat** percobaan; tiga yang
pertama dicatat di sini justru supaya tidak diulang, karena masing-masing
terdengar masuk akal.

1. Mengecualikan `ItemList` dari `UiJuice.relay_touch_scroll()`, dengan asumsi
   `ItemList` punya drag-to-scroll native yang diperebutkan `ScrollContainer`
   pembungkus. Ia tidak punya.
2. Meneruskan drag ke `get_v_scroll_bar()` milik list sendiri. Ini **sudah
   benar secara mekanis** dan terukur menggerakkan scrollbar-nya, tetapi tetap
   terasa rusak di perangkat karena penyebab sebenarnya belum tersentuh.
3. Menumbuhkan list ke tinggi konten penuh supaya `ScrollContainer` luar yang
   menggulir. Ini memang membuat sembilan Anima terlihat, tapi menukar satu bug
   dengan tiga: bottom sheet menyusut jadi sesobek pada pembukaan pertama
   (mengukur list yang belum terlihat — `ItemList` tersembunyi menjawab
   last-item rect 4 px dan scrollbar 100 px), list menyimpan ekor kosong saat
   diisi ulang dengan lebih sedikit item (`scrollbar.max_value` di-clamp ke
   `page`, jadi dua kartu menjawab 652 px padahal kontennya 136 px), dan
   builder Team/Expedition ikut menggulirkan judul serta baris Back/Save-nya.

Penyebab sebenarnya, yang membuat percobaan 2 terasa gagal padahal jalan:
**`ItemList` memilih pada PRESS**, jadi setiap usaha menggulir sekaligus
memilih kartu tempat jari mendarat. Di Battle picker itu membuka halaman detail
di tengah gerakan gulir; di builder Team itu **diam-diam mengubah roster**.
Selama itu belum diperbaiki, scroll yang berfungsi pun tetap terasa mustahil
dipakai.

Bentuk akhirnya `UiJuice.install_item_list_touch_scroll(list, on_tap,
on_drag_end)`: list tetap dibatasi tingginya dan menggulir **viewport-nya
sendiri**, sehingga chrome di sekelilingnya tidak bergerak (itu yang
memperbaiki keluhan builder), dan pilihan dilaporkan pada **RELEASE** saja,
hanya bila jari tidak melewati `ITEM_LIST_TAP_SLOP`. `on_drag_end` dipakai
pemanggil untuk membatalkan sorot yang sudah dilukis pada press. Dipasang di
`BattlePickSheet`, `TeamRosterList` (builder Team dan Expedition), dan
`CollectionView` — Collection punya bug identik yang belum dilaporkan: drag di
roster panjang membuka sheet preview kartu yang tersentuh.

Dua pagar yang lahir dari kesalahan di jalur ini:

- **`relay_touch_scroll` mengecualikan list yang opt-in saja**, lewat
  `META_LIST_SCROLL`, bukan setiap `ItemList`. Pengecualian menyeluruh
  sempat ditulis dan akan membuat regresi baru: `_chapter_list` Expedition
  tidak punya scroll internal dan justru **bergantung** pada relay itu untuk
  bisa dijangkau sama sekali.
- **Slop diukur sebagai displacement dari titik press di koordinat list**,
  bukan akumulasi delta (jitter pada press lama akan melampaui slop dan
  membuang tap yang sah) dan bukan di ruang konten. Menambahkan offset scroll
  supaya "content space" terdengar lebih benar justru **fatal**: drag yang
  menggulir list di bawah jari membuat jari tetap di atas konten yang sama,
  displacement-nya saling menghilangkan, dan setiap gulir kembali terbaca
  sebagai tap. Versi itu sempat ditulis dan ditangkap `test_scan_ui`.

Pagarnya `_test_item_list_drag_scroll()` — drag sungguhan lewat harness
`_drag_scrolls`, memeriksa list bergulir, chrome **tidak** bergulir, drag tidak
melaporkan pilihan apa pun, dan tap bersih memilih tepat baris di bawah jari —
plus satu pagar end-to-end di `_test_battle_pick_sheet()` yang membuka picker
sungguhan berisi sembilan Anima lalu men-drag di atasnya. Kedua probe **wajib**
memakai row ber-ikon dan thumbnail provider sungguhan, bukan `Callable()`:
sembilan row teks pendek memang muat dalam jendelanya dan tidak mereproduksi
bug-nya sama sekali — test end-to-end saya sempat lolos-palsu karena ini.

UAT atas bentuk akhir itu menyisakan dua hal, dan keduanya konsekuensi yang
terlewat, bukan penyebab baru:

- **Picker terbuka hanya sekitar seperempat layar.** `custom_minimum_size`
  360 px di scene adalah satu-satunya tinggi yang list minta, jadi sheet-nya
  mengukur diri terhadap stub itu — roster-nya bisa digulir, tapi jendelanya
  memang kecil. `BattlePickSheet._size_list_window()` sekarang menumbuhkan
  jendela itu ke ruang yang benar-benar bisa ditawarkan sheet
  (`host * max_height_ratio` dikurangi chrome-nya, dengan nilai scene sebagai
  lantai). Ini dihitung dari **minimum size dan viewport saja**, bukan dari
  internal `ItemList`, jadi aman dipanggil sebelum sheet tampil — pelajaran
  dari percobaan ke-3, di mana mengukur konten list yang belum terlihat
  membuat sheet menyusut. Efek sampingnya: di 720×1602 kesembilan Anima
  sekarang muat tanpa perlu digulir sama sekali, sehingga assertion lama
  ("wajib overflow") jadi salah dan diganti dua yang benar — panel wajib
  melampaui separuh tinggi host, dan baris terakhir wajib terjangkau entah
  karena muat atau karena bisa digulir.
- **Kartu tersorot saat jari cuma hendak menggulir.** `on_drag_end` hanya
  membetulkannya **sesudah** jari diangkat, jadi ring tetap berkedip selama
  gerakan. Sekarang press-nya ditelan langsung: `Control` memancarkan sinyal
  `gui_input` **sebelum** memanggil `_gui_input`, jadi `accept_event()` di
  handler membuat seleksi bawaan `ItemList` tidak pernah jalan. Konsekuensinya
  ring sepenuhnya milik pemanggil — `CollectionView` karena itu melukis sendiri
  baris yang di-tap (`_on_row_tapped`), yang tanpa itu tidak akan pernah
  tersorot. Pagarnya memeriksa **di tengah** gesture, bukan hanya sesudahnya,
  karena "membetulkan pada release" persis bug yang sudah terkirim.

Lalu fix tinggi itu sendiri **membuat bug ketiga**, dan ini yang paling penting
dicatat: menyentuh sheet membuat grid Anima meluncur ke atas tak terkendali.
Sebabnya matematika `chrome` saya sendiri. `_size_list_window()` menghitung
`chrome = panel.get_combined_minimum_size().y - list.custom_minimum_size.y`,
padahal minimum panel **sudah memuat** minimum scroll yang **sudah memuat**
minimum list — dan scroll itu meng-clamp-nya. Jadi setiap pemanggilan
memasukkan hasilnya sendiri ke pengukuran berikutnya: terukur, list tumbuh ke
**1698 px di layar 1602 px**, sehingga `ContentScroll` milik sheet **sendiri**
jadi punya overflow (max 1756 > page 1338) dan panel-nya terdorong keluar dari
atas sheet.

`UiBottomSheet._fit_scroll_to_host()` sudah punya trik yang benar dan saya
tidak memakainya: ia **menol-kan** `_scroll.custom_minimum_size.y` dulu, lalu
mengukur, sehingga `chrome_h` bersih dari kontribusi anaknya. Perhitungannya
karena itu dipindahkan ke sana lewat `set_fill_child()`: satu anak dinominasikan
menyerap sisa tinggi, minimumnya di-reset ke lantai scene sebelum tiap
pengukuran, jadi hasilnya idempoten. Terukur sesudahnya di 720×1602: list
1278,8 px, panel 1473 px (tepat di bawah plafon 1474), `ContentScroll` sheet
**tanpa** overflow, posisi panel konvergen persis ke 129 px, dan mode detail
kembali kompak ke 633 px lalu pulih saat kembali ke list. Pagarnya memeriksa
ketiganya sekaligus: window tidak melampaui host, scroll sheet tidak punya sisa
untuk digulir, dan tinggi list **tidak berubah** setelah tiga kali `fit_to_content()`
— divergensi itu yang membuat gejalanya baru muncul saat disentuh.

Sheet preview Collection lalu ketahuan terbuka terlalu tinggi dan baru pas saat
dibuka ulang — dan penyebabnya bukan lagi aritmetika kita, melainkan **regresi
engine**: minimum autowrap `Label` dihitung terhadap lebar, dan Godot bisa
mengukurnya sebelum container sort memberi lebar, sehingga label membungkus di
lebar ~0 dan melapor tinggi absurd
([godotengine/godot#83546](https://github.com/godotengine/godot/issues/83546),
gejala khasnya memang "buka ulang jadi benar"). Terukur di 720×1602: `Column`
duduk di minimum 350 px di dalam panel 720 px, label meta satu baris melapor
**312 px**, dan minimum panel jadi **897 px**.

Dua hal memperbaikinya, dan yang pertama adalah kesalahan sesi ini sendiri:
badge **CollectionAtlasBadge** dan **AtlasStatusBadge** yang ditambahkan tadi
memakai autowrap padahal isinya satu baris pendek, jadi keduanya ikut melapor
tinggi palsu — autowrap-nya dibuang. Lalu label meta yang memang bisa
membungkus (`CollectionSheetMeta`, `BattlePickMeta`, `BattlePickReason`,
`BattlePickEmpty`) diberi lantai lebar wrap `custom_minimum_size.x = 300`,
sesuai workaround yang dianjurkan komunitas: minimum dihormati container bahkan
saat sort-nya masih basi, jadi wrap terburuknya dua baris, bukan sembilan.
Terukur sesudahnya: label meta **67 px**, minimum panel **660 px**, stabil di
setiap pembukaan. `UiBottomSheet` juga sekarang me-refit saat lebar **konten**
berubah (bukan lebar panel, yang anchor-stretched dan tidak pernah berubah),
supaya sort yang datang terlambat menyembuhkan dirinya sendiri.

Pagarnya `_test_autowrap_labels_have_wrap_width()`, dibatasi pada label di
dalam `PanelContainer` ber-variation `BottomSheetPanel` — surface yang diukur
dari kontennya. Layar penuh punya `ScrollContainer` yang menyerap salah-ukur
yang sama, jadi memagari semuanya hanya menghasilkan kebisingan.

Prosedur lengkap untuk seluruh kelas bug ini (gejala, empat sumber terukur, dan
urutan penanganan yang mengikat) hidup di `.cursor/rules/client-shell-ui.mdc`
bagian "Layout diukur sebelum settle", dengan penunjuk di bagian sendiri di
file ini. Ia ditulis karena kelas ini terulang **empat kali** dalam satu sesi
UAT dan dugaan pertama selalu salah.

Level yang ditambahkan ke baris Battle picker lalu **merusak grid-nya**, dan ini
ditemukan hanya karena screenshot perangkat: teks tiap sel membungkus, baris
pertamanya di-ellipsis, dan baris **kedua** tetap tergambar di luar sel — menimpa
art baris di bawahnya, terlihat sebagai "Drakabyss · Lv. 6 · Flow · …" diikuti
"lant" yang menggantung. Sel `ItemList` hanya punya ruang untuk baris yang ikut
diukur, jadi keduanya dipagari sekarang: `max_text_lines = 1` +
`text_overrun_behavior = 3` pada `BattlePickList` dan `AnimaList` (nama Anima
berasal dari pemain, jadi panjangnya tidak bisa diasumsikan), dan **element
dibuang dari baris grid** karena "Drakabyss · Lv. 6 · Flow · Plant" memang tidak
muat di kolom 290 px sementara panel detail sudah menampilkan element-nya.
Pagarnya `_test_item_grids_clip_to_one_line()`, dibatasi pada grid multi-kolom —
roster satu kolom dapat lebar penuh dan tidak berisiko.

Dua koreksi lanjutan sesudah screenshot perangkat kedua. Pertama,
`max_text_lines = 1` **tidak cukup**: baris "tidak bisa dipakai"
(`Drowake · Lv. 16 · Sleeping`) tetap membungkus dan membocorkan ekornya walau
selnya sudah dikunci satu baris ber-ellipsis. Baris itu sekarang juga dua
segmen dan **dipimpin alasannya**, bukan Level — alasan itu yang harus
ditindak pemain, Level ada di panel detail; key `BATTLE_PICK_ITEM_META`
tiga-slot jadi yatim dan dihapus. Kedua, keluhan "terpotong ke kiri" sejak awal
ternyata **bukan** konten meluber melainkan **border sheet yang hilang**:
`BottomSheetPanel` punya border kiri/kanan 2 px, tapi panel digambar full-bleed
sehingga garis itu jatuh di kolom piksel terluar dan dimakan lengkung layar
perangkat. `UiJuice.SHEET_SIDE_INSET` (12 px) memberi inset samping; bawahnya
tetap rapat karena stylebox-nya tidak punya border bawah dan sudut bawahnya
kotak. Jebakannya dicatat di kode: `sheet_rest_position()` wajib mengembalikan
x = inset, **bukan 0** — menetapkan `position` menulis ulang offset Control,
jadi rest x=0 akan membatalkan inset itu setiap kali sheet beranimasi masuk,
bug yang hanya muncul sesudah animasi dan bukan saat frame pertama.

Dua pelajaran metode dari babak ini, keduanya sudah masuk rule ber-glob:
**lantai lebar wrap tidak gratis** (ia menaikkan minimum lebar konten, dan
sheet yang lebih lebar dari layar terpotong karena scroll horizontalnya mati),
dan **child `visible = false` tidak menyumbang minimum** — jadi mengukur lebar
wajib dilakukan dengan badge opsionalnya dinyalakan. Yang paling menentukan:
pengukuran headless saya sempat memburu surface yang salah dan menyimpulkan
"muat" (448 px di ruang 720 px) sementara yang rusak adalah grid picker. Satu
`adb exec-out screencap` menyelesaikannya; layar perangkat harus menyala lebih
dulu karena `adb shell input` diblokir di HyperOS ini.

Ring sorot Collection juga melompat kembali ke Anima yang sedang di lobby tiap
kali sheet preview Anima lain dibuka. `_list.clear()` di `set_rows()` ikut
menghapus selection native, jadi selection harus dipilih ulang — dan
`set_rows()` jalan di **setiap** care sync latar, bukan hanya muat pertama.
Karena default-nya selalu `active_id`, satu sync yang mendarat saat sheet Anima
lain terbuka menarik ring itu balik ke Anima Home. Aturannya sekarang satu
fungsi, `_highlight_id()`, dipakai bersama `set_rows()` dan repaint sesudah
gulir; `on_drag_end` Collection **tidak** boleh `deselect_all` (versi pertama
memakai itu dan menghapus ring Anima aktif setiap kali roster digulir).

Back dari Anima Profile yang dibuka lewat tap nama di Home tadinya mendarat di
Collection, sebab whitelist `_show_collection_profile()` cuma mengizinkan
Collection/Battle/Synthesis sebagai asal — Home baru ditambahkan sesi ini
lewat fitur tap-nama dan lupa didaftarkan. Membuka Atlas/Seeker Profile dari
atas Anima Profile (mis. lewat Menu) juga bisa mendarat di tujuan basi, sebab
`_remember_overlay_origin()` cuma mengenali empat tujuan dasar dan diam kalau
`_destination` sedang `ANIMA_PROFILE_DEST` — sekarang ia merantai lewat
`_profile_return_destination` Profile sendiri, jadi satu kali Back dari Atlas
tetap mendarat di layar tempat rantainya benar-benar dimulai. Membuka Seeker
Profile lewat tap nama juga diam total selama round trip `seeker/profile`;
`LoadingScreen.show_screen("SEEKER_PROFILE_LOADING")` sekarang menutupinya,
konsisten dengan `BATTLE_CONNECTING`/`TEAM_STARTING`. Bottom sheet preview
Collection (kartu Anima yang di-tap dari grid) tidak pernah tahu status
publish sama sekali — beda dari Anima Profile, ia dibangun instan dari roster
lokal tanpa panggilan `my_status`. Parsing responsnya dipisah ke
`_gallery_status_from_response()` yang dipakai bersama oleh Profile dan sheet
baru ini, dan sheet mendapat sinyal terpisah `atlas_preview_requested` (bukan
numpang `preview_requested`, yang sengaja dilewati saat care data sudah
ter-cache supaya tidak sync ulang) supaya badge publish tetap refresh setiap
sheet dibuka.

`test_scan_ui` berakhir di 1402 check, `test_i18n` 4970 dan dijalankan berulang untuk memastikan
stabil; satu check lain (`UiBottomSheet closes after its dismiss animation`)
memang **flaky** karena bergantung timer animasi, bukan regresi. `test_i18n`
4974, `test_game_rules` 181, `test_client_state` 196,
`test_expedition_route_map` 91, `test_auth_flow` 63, `test_sprite_slicing` 174,
`npm run selftest` lulus, dan `quota_rules.sql` lulus terhadap production.
`admin_moderation` dideploy ulang (smoke 401 = boot benar). APK debug
24 Agustus 2026 **04:17** membawa semuanya dan terpasang di perangkat yang sama.
Verifikasi visualnya **belum** dilakukan: layar perangkat kembali `Dozing` dan
`adb shell input` diblokir HyperOS, jadi baris Drowake dan border samping sheet
masih menunggu satu screenshot dengan layar menyala.

Code review atas semuanya menemukan lima cacat lain yang semuanya lahir di sesi
ini, jadi keduanya dicatat bersama pagarnya:

- **Tap nama di Home memancar dua kali** (emulasi touch menyerahkan jari yang
  sama sebagai screen touch dan mouse press). Chip kebutuhan di file yang sama
  sudah punya guard per-frame; tap identitas belum. Di sini pancaran kedua lebih
  buruk daripada tap mati: ia masuk lagi ke `_show_collection_profile()` saat
  Profile **sudah** jadi tujuan, sehingga asal yang diingat di-reset ke
  Collection dan justru membatalkan Back-ke-Home yang baru diperbaiki.
- **Jalur `GALLERY_MODERATION_REJECTED` tidak menyatakan `appeal_available`.**
  Penolakan yang baru terjadi belum punya appeal tercatat, tapi default `false`
  memberi tahu pemain bahwa ia "sudah meminta review" sekaligus menyembunyikan
  appeal yang sebenarnya jadi haknya.
- **`previewIdleThumbDataUri()` throw dan fan-out tak terbatas.** Setiap preview
  mengunduh lalu men-decode satu sheet penuh dan meng-inline-nya sebagai base64;
  satu Seeker dengan banyak publication mengubah satu page load menjadi puluhan
  fetch, dan satu baris tak terbaca men-500-kan seluruh halaman Seekers. Sekarang
  fail-soft (tetap dicatat ke log) dengan plafon `PREVIEW_THUMB_BUDGET` per
  request; barisnya jatuh ke placeholder yang sudah ada. `ensureEntryThumb()` di
  file yang sama **tetap** throw dengan sengaja — approve/restore tidak boleh
  diam-diam menerbitkan entry tanpa thumbnail, dan pagar selftest-nya karena itu
  dipersempit ke fungsi preview saja.
- **`src=""` bukan src kosong.** Browser me-resolve string kosong terhadap URL
  saat ini dan mengambil ulang halamannya sendiri sebagai gambar. Queue dan
  Seekers memakai `?? undefined`/`typeof === "string"` yang meloloskan `""`;
  Case Detail sudah aman karena memakai truthiness.
- **Assertion RLS `moderation_cases` lolos karena alasan yang salah.** Ia
  mewarisi `request.jwt.claims` yang ditinggalkan blok sebelumnya, dan `u1`
  **menjadi admin** di tengah fixture — jadi assertion "tidak melihat baris"
  sebenarnya menguji jalur staff. Memindahkannya ke sesudah fixture (supaya
  hasil 0-baris tidak lolos hampa di database kosong) membongkar ini. Sekarang
  kedua arah diuji dengan identitas yang dinyatakan eksplisit: `u4` (staff-nya
  sudah di-revoke) wajib melihat nol baris, `u1` wajib tetap bisa membaca —
  kalau tidak, kebijakan yang menolak semua orang pun akan lolos. `gallery_reports`
  yang sebelumnya tidak punya assertion ikut ditambahkan.

Perangkatnya (`23127PN0CG`, HyperOS) tersambung **wireless lewat Tailscale**
`100.96.188.61:<port>`, bukan USB; port-nya berubah saat Wireless debugging
diaktifkan ulang (terakhir `34921`) dan koneksinya putus sendiri di antara
perintah. Per 24 Agustus 2026 endpoint Tailscale itu berhenti menjawab dan
`adb kill-server` malah menabrak daemon yang masih hidup
(`could not install *smartsocket* listener: Address already in use`), tetapi
perangkatnya tetap terdaftar lewat mDNS sebagai
`adb-407f470f-SpxqzU (2)._adb-tls-connect._tcp` dan `adb install` ke sana
berhasil tanpa `adb connect` sama sekali — jadi periksa `adb devices` dulu
sebelum menyimpulkan perangkatnya lepas. Selama endpoint aktif, `adb connect <ip>:<port>` menyambungkannya
kembali; `Connection refused` walau `tailscale ping` masih membalas berarti
endpoint ADB mati atau port berubah dan perlu dibuka lagi di perangkat. Dua hal
yang **tidak bisa** dilakukan dari sini: perangkat ini menolak
`adb shell input` dengan `SecurityException: INJECT_EVENTS` (butuh "USB debugging
(Security settings)" di HyperOS), jadi layar tidak bisa dibangunkan atau dibuka
kuncinya secara remote. Konsekuensinya, `monkey` yang meluncurkan app saat layar
`Dozing` **selalu** gagal dengan `Failed to create vulkan window` /
`Unable to create DisplayServer` — itu layar mati, bukan APK rusak. Boot di
perangkat karena itu masih belum pernah dilihat; verifikasi runtime butuh layar
dibuka tangan.

Animasi ikon terbang saat feeding dan buying di Shop **menghilang** setelah HUD
restructure memindahkan `BagButton`/`ShopButton` dari `ChipLayer` ke
`TopHud/Column/BottomSection/RightButtons`. Dua penyebab utama teridentifikasi
dan diperbaiki:
1. `UiJuice.fly_to()` membutuhkan `flyer.top_level = true`: tanpa flag ini,
   ketika host flyer berada di bawah `Container` (seperti `MarginContainer` atau
   `HBoxContainer`), Godot mereset `flyer.position` dan memperbesar `flyer.size`
   ke dimensi container pada `NOTIFICATION_SORT_CHILDREN` (terukur: `(72, 72)`
   didorong menjadi `(688, 1576)` dan posisinya melenceng keluar layar).
2. Host flyer di `scan_flow.gd` diarahkan ke `_toast_layer` (`ToastLayer`,
   Control full-screen non-container yang duduk di canvas root di atas seluruh
   sheet), dengan fallback `_safe_margin`.

Label tombol `ShopButton` dan `BagButton` pada `RightButtons` (TopHud) yang
berada di atas surface terang memakai `GhostChipValueLabel` (warna font gelap
navy/slate `Color(0.094, 0.196, 0.365, 1)` tanpa font shadow `Color(0, 0, 0, 0)`)
agar terbaca tajam dan bersih. Dimensi `TopHud` dan tombol dipertahankan pada
ukuran aslinya (`custom_minimum_size = Vector2(96, 96)`) agar garis divider dan
background 9-patch `HomeHudSurface` (`home_top_container_bg.png`, 203px) tidak
terdistorsi. Non-Home tab (Scan, Battle, Anima, dll.) memakai `CompactHudSurface`
(`compact_top_container_bg.png`, 82×82 px downsampled dari export 3x Figma) sebagai `StyleBoxTexture` NinePatch —
stretch margin 23 px di semua sisi (corner radius 23 px presisi sesuai canvas Figma), content margin 16/10 px —
menampung nama Seeker dan tombol Core + Bits. Asset disalin ke
`assets/ui/compact_top_container_bg.png`, didefinisikan sebagai `ext_resource` id
`7_compact_hud_bg` dan subresource `CompactHudSurface` di `mobile_theme.tres`, dan
dipasang via `theme_type_variation` di `_go_to()` dalam `scan_flow.gd`.
Ikon dan label diturunkan secara presisi di dalam chip menggunakan
`_column.alignment = BoxContainer.ALIGNMENT_END`, `Icon` `Vector2(46, 46)`, dan
`ICON_SEPARATION = 8`. Interaksi pada `ResourceChip` diberi full feedback juice
(squish `0.90` saat ditekan dengan micro-tilt & brightness, spring bounce `TRANS_BACK`
saat dilepas, serta pop overshoot `1.08` saat tap).

Desain toast 4-state (`GENERAL`, `SUCCESS`, `WARNING`, `ERROR`) berbasis
`StyleBoxTexture` (`toast_panel_*.tres`) sekarang distandarisasi ke seluruh
event banner / toast di `BattleView` dan `TeamBattleView` lewat
`_event_plate.add_theme_stylebox_override("panel", TOAST_STYLES[type])`:
`SUCCESS` untuk Super Effective / Guard / Item / Win KO / Ace Passive,
`WARNING` untuk Not Effective / Timeout / Retreating, `ERROR` untuk Defeat /
Player KO, dan `GENERAL` untuk Initiative / Attack / Move Effects.

Seluruh toast/banner kini diposisikan pada **30% dari atas layar** (golden focal zone):
- **Shell toast** (`StatusPanel` / `_place_toast`): ditargetkan pada `viewport_h * 0.30`
  dengan boundary clamping antara batas bawah TopHud dan batas atas BottomNav / sheet,
  sehingga nyaman di mata tanpa tertutup atau menabrak HUD.
- **Battle banners** (`BattleEffectiveness` / `TeamEffectiveness`): anchor diatur
  ke `anchor_top = 0.3`, `anchor_bottom = 0.3` di dalam arena
  (`BattleArena` / `TeamBattleStage`), duduk pas di bawah HP bar fighter dan di atas
  animasi pertarungan.

Layar loading (`LoadingScreen` / `ScanimaBackground` / Web Shell):
- Engine boot splash image Godot dimatikan (`application/boot_splash/show_image=false`, `boot_splash/bg_color=Color(0.018, 0.026, 0.07, 1)`, `boot_splash/minimum_display_time=0`) agar startup langsung meluncur mulus ke loading screen Scanima tanpa jeda/logo engine.
- Animasi chamber cincin berputar diposisikan tepat di tengah layar (`CHAMBER_Y = 0.5`).
- Elips glow biru terang di bawah cincin chamber dihapus agar tampilan lebih bersih dan modern.
- Teks judul brand "SCANIMA" (`BrandTitle`), loading sweep progress bar (`LoadingSweep`), dan teks loading (`LoadingMessage`) disusun rapi berurutan tepat di tengah layar (`CenterContainer` penuh).
- Web HTML export shell template (`game/web_shell.html` dan `build/web/index.html`) diperbarui dengan judul neon glowing "SCANIMA" dan loading bar presisi di tengah viewport sebelum engine WASM selesai diunduh.
- Jembatan foto Web (`_request_web_photo` di `scan_flow.gd`) disederhanakan ke pemilih berkas murni (`accept="image/*"`) tanpa modal webcam WebRTC yang rentan masalah izin pada desktop browser, sambil tetap membuka kamera/galeri secara native pada mobile browser.
- Perbaikan Bottom Sheet fly-up bug di `ui_bottom_sheet.gd`: `open()` kini memvalidasi `_panel.get_combined_minimum_size().y >= 1.0` dan menunggu layout settle penuh sebelum memulai animasi kemunculan agar panel tidak beranjak dari posisi salah yang membuatnya seolah terbang ke atas.

Relayout Navigasi Tabbing Animas & Unifikasi UI Sub-tab:
- Tombol **Synthesis Lab** di header `CollectionView` dihapus dan dipindahkan menjadi sub-tab di antara **Collection** dan **Atlas** (`CollectionTabs`: `Collection` | `Synthesis` | `Atlas`), dengan label ringkas `Synthesis` (`COLLECTION_TAB_SYNTHESIS`).
- Sub-tab tiga serangkai (`Collection`, `Synthesis`, `Atlas`) distandarisasi di seluruh `CollectionView`, `AtlasView`, dan `SynthesisLabView`, memungkinkan navigasi langsung bolak-balik antartab di seluruh sub-page Animas.
- **Unifikasi Header & Breathing Room**:
  - Chevron back (`<`) pada Atlas (`AtlasBack`) dan Synthesis (`SynthesisBackButton`) dihapus total karena alur navigasi kini sepenuhnya berbasis tab.
  - Subtitle deskriptif ditambahkan ke Atlas (`ATLAS_SUBTITLE`: "Discover, track, and explore every known Anima.") di bawah `AtlasTitle`, sehingga ketiga sub-tab memiliki struktur header yang seragam (`Titles` VBox: `Title` + `Subtitle`).
  - Tinggi tombol tab diseragamkan menjadi 72px (`custom_minimum_size = Vector2(0, 72)`) dengan spacing dan breathing room yang proporsional, bersih, dan konsisten tanpa frame/border yang mengganggu.
- **Selection Ring Fix**: Selection ring emas (`ItemSelected`) yang sebelumnya nyangkut/terpilih terus pada kartu di `CollectionView` saat berpindah tabbing atau saat sheet ditutup telah diperbaiki: `_highlight_id()` kini hanya mengembalikan ID Anima ketika preview sheet benar-benar sedang terbuka (`_sheet.visible`), dan `_restore_highlight()` / `close_sheet()` / `begin_visit()` membersihkan seleksi saat sheet tidak aktif sehingga grid tampil bersih tanpa ring nyangkut.



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

## Konvensi admin console

`admin/` adalah workspace npm terpisah: Next.js 16 App Router, local-only,
untuk staff moderasi Atlas (queue, reports, appeals, decisions, sanctions,
staff, audit, analytics). Browser hanya memegang Supabase URL + publishable
key; setiap operasi privileged lewat Edge Function `admin_moderation` yang
memverifikasi role dari `staff_accounts`, bukan dari `proxy.ts` (konvensi
Next.js 16 pengganti `middleware.ts`, dipakai hanya untuk refresh cookie).
Detail lengkap dan state machine moderasi di
[`docs/designs/2026-08-23-atlas-moderation-admin.md`](docs/designs/2026-08-23-atlas-moderation-admin.md);
pagar Next.js-nya di `.cursor/rules/admin-guardrails.mdc`.

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

Enam hal yang gagal **senyap** — tanpa galat yang menunjuk sebabnya — jadi
keenamnya tetap di sini alih-alih di rule ber-glob yang belum tentu dimuat
saat build atau push dijalankan.

- **Mesin ini memegang dua identitas GitHub dan default-nya identitas kerja, jadi `origin` wajib SSH.** Sama seperti `SUPABASE_ACCESS_TOKEN` yang menunjuk org kerja: `~/.gitconfig` mengarahkan kredensial HTTPS ke `gh auth git-credential`, dan helper itu **hanya melayani akun aktif** — terukur, permintaan untuk `username=ryansetia1` dijawab kosong sementara permintaan tanpa username dijawab `ryansetiawan-tiket`. Remote HTTPS karena itu ditolak GitHub dan Cursor menawarkan membuat fork; menerimanya memindahkan `origin` ke akun kerja. `user.name`/`user.email` per-repo **tidak** memperbaikinya — itu hanya author commit, bukan autentikasi. Pagarnya `origin = git@github-personal:ryansetia1/Scanima.git`; alias itu ada di `~/.ssh/config` dan memakai `id_ed25519_personal` dengan `IdentitiesOnly yes`, sedangkan `git@github.com` sengaja tetap milik akun kerja. Verifikasinya `ssh -T git@github-personal` harus menjawab `Hi ryansetia1!`. `.git/config` tidak ikut git, jadi clone berikutnya harus memakai URL SSH itu sejak awal.
- **Izin `INTERNET` MATI secara default di ekspor Android Godot 4, dan ini kegagalan yang paling mahal waktunya.** APK pertama yang dibangun di sini keluar dengan `CAMERA` sebagai satu-satunya izin: ia terpasang, terbuka, lalu mati di sign-in anonim — tanpa dialog izin, tanpa crash, cuma galat jaringan yang menyesatkan, sebab Android menolak socket-nya secara senyap. Preset **wajib** memuat `permissions/internet=true`. `export_presets.cfg` di-gitignore, jadi tidak ada uji di repo yang bisa menjaga ini; catatan ini adalah pagarnya, dan `aapt2 dump permissions` sesudah build adalah pemeriksaannya.
- **Template Android 4.6.2 mematok Gradle 8.11.1, jadi JDK-nya tidak boleh lebih baru dari 23.** Mesin ini punya JDK 26 dan build-nya berhenti di `Unsupported class file major version 70` sebelum menyentuh kode kita. Yang dipakai: `brew install openjdk@17` — **formula, bukan cask `temurin@17`**, sebab cask memasang ke `/Library/Java/...` dan menuntut sudo sementara formula tidak. JDK 26 **tidak** perlu dihapus walau banyak jawaban forum menyuruhnya: Godot punya setelan `Java SDK Path` sendiri, jadi keduanya hidup berdampingan. Alternatif menaikkan `distributionUrl` di `gradle-wrapper.properties` menukar satu masalah pasti dengan pasangan Gradle/AGP yang tidak diuji siapa pun.
- **Godot membaca `ANDROID_HOME` tapi TIDAK membaca `JAVA_HOME`.** SDK-nya terdeteksi sendiri; jalur JDK harus ada di `export/android/java_sdk_path` pada `editor_settings-4.6.tres` (nama file-nya per-minor, bukan `editor_settings-4.tres`). Menulisnya lewat file **hanya aman saat editor tertutup** — editor menyimpan setelannya sendiri ketika keluar dan akan menimpa suntingan dari luar. `export/android/debug_keystore` juga sudah diisi sendiri oleh editor ke keystore yang belum ada; ia dibuat lambat memakai `keytool` dari JDK, jadi preset di sini menunjuk `~/.android/debug.keystore` yang nyata ada supaya hasilnya deterministik.
- **APK sideload memakai native-library compression.** `export_presets.cfg` wajib memuat `gradle_build/compress_native_libraries=true`: pada debug APK, 71,47 MB dari total 76 MB adalah `libgodot_android.so`, dan opsi ini terukur menurunkan berkas transfer ke 54,7 MB pada build 22 Agustus 2026 — nyata, tetapi jauh dari perkiraan awal ~30 MB, jadi jangan pakai angka itu untuk merencanakan ukuran rilis. Trade-off-nya startup sedikit lebih lambat dan ukuran terpasang tidak banyak berubah; untuk AAB Play Store, evaluasi ulang dan umumnya biarkan library tidak terkompresi.
- **Export Web (`build/web/`, seluruhnya gitignore) tidak boleh disajikan dengan static file server polos — WASM thread Godot butuh cross-origin isolation, dan itu dua header HTTP yang tidak dikirim server mana pun secara default.** Membuka `index.html` langsung lewat `python3 -m http.server` (atau server statis lain tanpa konfigurasi tambahan) gagal dengan galat eksplisit di layar ("Cross-Origin Isolation", "SharedArrayBuffer"), bukan senyap — tapi begitu itu teratasi, kegagalan berikutnya (Google Sign-In lewat popup) **senyap total**: popup terbuka, pemain memilih akun, lalu macet tanpa galat apa pun. Sebabnya sama, satu header: `Cross-Origin-Opener-Policy: same-origin` (dipasang bersama `Cross-Origin-Embedder-Policy: require-corp` supaya `self.crossOriginIsolated` benar) memutus `window.opener` untuk **popup mana pun ke origin lain**, sejak popup itu dibuka — bukan cuma saat ia mencoba redirect balik — jadi pola "buka popup lalu dengarkan `postMessage` balik" tidak akan pernah bisa dipakai selama header ini aktif, di server manapun. Karena itu `auth_flow.gd` untuk `OS.has_feature("web")` memakai navigasi top-level satu tab, bukan popup — detail dan pagar Supabase Auth redirect allow-list-nya ada di `.cursor/rules/android-and-plugins.mdc`. Skrip server dev lokal yang sudah menambahkan kedua header itu (`build/web/_coi_server.py`) tidak ikut git karena seluruh `build/` di-gitignore; menulis ulang isinya kalau hilang cukup dua baris `send_header` di atas `SimpleHTTPRequestHandler.end_headers()`.

## Perintah umum

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

```bash
# gratis, jalankan ini dulu
npm run selftest                       # 42 skenario + 12 uji tanda tangan webhook
godot --headless --path game --script res://tests/test_sprite_slicing.gd # 174 check manifest, loader, presenter, Boss Seeker
godot --headless --path game --script res://tests/test_auth_flow.gd    # 63 check PKCE secure, restart, transfer/separate, recovery, no-merge
godot --headless --path game --script res://tests/test_client_state.gd  # 196 check sesi, refresh, pending scan/care/Battle/Shop/evolution, cache art, cache boot, stale UID, retry transport
godot --headless --path game --script res://tests/test_scan_ui.gd       # 1378 check shell + Battle + Shop + Bag + komponen + tap + touch + press/release roster sungguhan + UI/SFX hooks + prediksi turn/care/Summon + rollback + cache boot + Trophy Showcase/evolution/Atlas + dialog Evolve gagal + preflight nama + LoadingScreen
godot --headless --path game --script res://tests/test_i18n.gd          # 4827 check katalog + key + formatter + wrapping
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

## Dua percobaan gagal = berhenti menebak, riset dulu

Kalau satu masalah sudah **dua sampai tiga kali** ditambal dan gejalanya tetap
ada, percobaan berikutnya jangan dugaan keempat. Cari dulu ke luar: dokumentasi
resmi Godot untuk versi yang dipakai project, lalu issue tracker
`godotengine/godot` dan `godot-proposals`, lalu forum/diskusi. Ini bukan
formalitas — terukur di sesi 24 Agustus 2026, tiga percobaan pada
"Battle picker cuma menampilkan 4 Anima" dan dua percobaan pada "sheet terlalu
tinggi" habis karena penyebabnya **bukan** di kode kita: yang kedua adalah
regresi engine yang sudah terdokumentasi
([godotengine/godot#83546](https://github.com/godotengine/godot/issues/83546)),
lengkap dengan gejala yang sama persis dan workaround yang dianjurkan
komunitas. Satu pencarian mengubah arah fix dari "tunggu layout settle" (rapuh,
menebak jumlah frame) menjadi "beri lebar wrap konkret" (deterministik).

Tandanya sebuah masalah masuk kategori ini: gejalanya bergantung timing atau
urutan, hilang saat diulang, atau angka yang dilaporkan API engine tidak masuk
akal. Saat menemukan issue engine yang cocok, **catat nomornya** di kode dekat
workaround-nya, supaya penerusnya tahu itu pagar terhadap bug orang lain dan
bukan kerumitan yang bisa disederhanakan.

## Bug UI yang "benar setelah dibuka kedua kali"

Kalau sebuah panel, dialog, atau bottom sheet terbuka dengan ukuran salah lalu
menjadi benar saat dibuka ulang, **jangan** menambal dengan menunggu beberapa
frame sampai kebetulan cukup. Itu selalu berarti sesuatu diukur sebelum
nilainya sah, dan penyebabnya sudah terdokumentasi beserta angka terukurnya —
termasuk regresi engine autowrap `Label`
([godotengine/godot#83546](https://github.com/godotengine/godot/issues/83546)),
aritmetika sisa-ruang yang divergen, dan control tersembunyi yang melapor angka
sampah. Prosedur penanganannya wajib diikuti dan hidup di
`.cursor/rules/client-shell-ui.mdc` (bagian "Layout diukur sebelum settle"),
yang otomatis termuat saat menyentuh `game/scripts/` atau `game/scenes/`.
Ringkasnya: probe headless di `SubViewport` 720×1602 lebih dulu, perbaiki di
tempat otoritas layout-nya, dan uji keadaan tengah gesture serta idempotensi —
bukan hanya keadaan akhir.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`

## Di mana sisanya hidup

Enam rule di bawah `alwaysApply: false` dan hanya masuk konteks saat file yang
cocok dengan glob-nya disentuh. Isinya dipindahkan verbatim dari file ini, jadi
angka terukurnya tidak berubah — kalau butuh detail satu domain, buka
rule-nya, jangan menebak.

| Rule | Dimuat saat menyentuh | Isi |
|---|---|---|
| `.cursor/rules/battle-and-expedition.mdc` | script/scene Battle, Team, Expedition, `sim/`, `anima_presenter.gd`, Edge Function battle/team/expedition, `backend/chapters/` | Prediksi turn, PP, initiative, tier hadiah, gate lawan Duel, lawan sistem, ace Boss, skala/framing arena, chapter runtime |
| `.cursor/rules/client-shell-ui.mdc` | `game/scripts/`, `game/scenes/`, theme, shader, locale, test | Theme, komponen, `LoadingScreen`, jebakan Tween, audio, state layar, cache boot, Care Dock/Shop/Bag, **prosedur wajib "layout diukur sebelum settle"** |
| `.cursor/rules/backend-guardrails.mdc` | `backend/` | Identitas dan guest, care authoritative, decay, gerbang nama, RLS, advisor yang disengaja, jebakan PostgREST |
| `.cursor/rules/art-and-prompt-pipeline.mdc` | `backend/prompts/`, `_shared/postprocess`/`vision`/`png`, `create_anima`, `evolve_anima`, `backend/tools/`, `eval/` | Vision dan wrapper Replicate, chroma key, slicing, encoder PNG, latensi model, art direction chapter |
| `.cursor/rules/android-and-plugins.mdc` | `game/android/`, `game/addons/`, preset export, `scan_flow.gd`, `auth_flow.gd` | Plugin kamera, OAuth/deep link, sinyal plugin, verifikasi APK |
| `.cursor/rules/admin-guardrails.mdc` | `admin/**` | `proxy.ts` bukan gerbang otorisasi, staff role hanya dari `staff_accounts`, larangan service-role di browser, scope moderasi-only |

Dua rule lain sudah ada sejak sebelumnya: `player-wiki.mdc` (`alwaysApply: true`)
dan `sfx-presentation.mdc`.

| Dokumen | Isi |
|---|---|
| [`docs/14-deploy-log.md`](docs/14-deploy-log.md) | Riwayat rollout: Atlas, Name Lineage v41, gerbang Rename, Capture Vibe, gate IP, Evolution art, Battle polish, gate lawan Duel, daftar migration |
| [`docs/15-commands.md`](docs/15-commands.md) | Katalog `--*-demo`, uji terhadap production, build/verifikasi APK, backend lokal |
| [`docs/16-prompt-version-history.md`](docs/16-prompt-version-history.md) | Pohon `backend/prompts/` v1–v41 dan provenance setiap versi yang ditolak |

Indeks dokumen selengkapnya ada di [README.md](README.md); panduan pemain di
[`docs/wiki/`](docs/wiki/README.md).

## Perbaikan UI & State Caching Synthesis (25 Agustus 2026)

1. **State Caching per Bias Mode**: Hasil review resonance (`_preview`) dan error (termasuk `SYNTHESIS_MODE_USED`) sekarang di-cache per bias mode (`dominant_a`, `balanced`, `dominant_b`) menggunakan `_preview_cache` dalam `SynthesisLabView`. Ketika player berpindah tab bias inheritance dan kembali, hasil review yang sama langsung terpulihkan secara local tanpa hit backend ulang. Caching sepenuhnya dibersihkan (`_invalidate_all()`) ketika player mengubah source Anima A atau B.
2. **Redundant Button Hidden**: Tombol `Review Resonance` disembunyikan secara dinamis ketika preview hasil review, pesan error, atau loading state sedang aktif.
3. **Loading State Review**: Indikator loading pada review area mengadopsi pola looping sweep linear milik `LoadingScreen` (`_loading_track` berlatar gelap dan `_loading_spark` cyan yang meluncur maju secara berulang via `Tween.set_loops()`), diposisikan center vertically dengan ketinggian 220px agar mengisi ruang lapang area review secara seimbang.
4. **Pencegahan Opsi Terpakai (SYNTHESIS_MODE_USED)**: Mode bias yang sudah pernah diselesaikan untuk pasangan Source tersebut ditandai ke `_used_modes` ketika server mengembalikan error, kemudian tombol mode bias tersebut dinonaktifkan (`disabled = true`) agar player tidak memicu review berulang.
5. **Warna Banner/Toast Battle (Complete & KO)**: 
   - Banner `finished` (`Battle complete.`): Biru (`COMPLETE_COLOR` + `ToastType.GENERAL`) dengan teks dan panel toast biru untuk semua hasil (menang/kalah).
   - Banner `knockout` (`[Anima] is knockout`): Hijau (`WIN_COLOR` + `ToastType.SUCCESS`) jika yang KO adalah musuh/lawan, merah (`DAMAGE_COLOR` + `ToastType.ERROR`) jika yang KO adalah Anima pemain.
6. **Incubating Layout Clean**: Pada state `_set_incubating(true)`, `_synthesis_panel` (`SynthesisPanel`) disembunyikan bersama `_editor_scroll` sehingga tidak meninggalkan panel kosong di atas tampilan visual inkubasi.
7. **Uji Otomatis**: Memperbaiki `test_scan_ui.gd` agar mencari container `Column` yang dipromosikan (bukan `LabSurface` yang sudah dideprecate) untuk pengujian kecocokan dimensi viewport, sehingga seluruh 1467 checks client UI test suite kembali hijau / lulus 100%.
## Perbaikan UI Scan View, Home CTA, & Modal Fit-to-Content (25 Agustus 2026)

1. **Title Dynamic Alignment**: `ScanTitle` ("Discover a New Anima") diposisikan secara dinamis pada `_align_idle_graphic` tepat di atas animasi cincin chamber di area tengah layar (`local.y - 290px`), menghilangkan gap kosong di bawah HUD.
2. **Icon Camera Centering**: `CAMERA_OPTICAL_OFFSET` pada `ScanView` dinormalkan ke `Vector2.ZERO`, sehingga icon kamera duduk presisi tepat di titik pusat matematis animasi cincin chamber yang berputar.
3. **Vibe & CTA Section Lift (+30%)**: Ditambahkan `BottomSpacer` pada `scan_view.tscn` sehingga seluruh blok "Choose Your Anima Vibe", opsi vibe, tombol "Scan Real Object", dan privacy hint terangkat ~30% ke atas, tidak lagi menempel ketat di navigation bar bawah.
4. **Pembersihan Copy Hint**: Teks "Center one clear object in the frame." (`SCAN_CAMERA_HINT`) pada `StatusPanel` disembunyikan saat idle agar pemain tidak mengira kamera sedang loading di layar.
5. **Perjelas Copy Vibe**: `SCAN_VIBE_TITLE` diperbarui menjadi **"Choose Your Anima Vibe"** pada `locales/ui.csv`.
6. **Home Single CTA Fix**: `_primary_action.visible` pada `home_view.gd` diatur hanya aktif pada state `error`, sehingga pada state `empty` hanya tombol `ScanCtaButton` di tengah `StageSpace` yang tampil, menghilangkan tombol kembar di bagian bawah Home.
7. **UiModal Autowrap Fit-to-Content**: Diberikan lantai lebar wrap `custom_minimum_size.x = 520.0` pada `ModalBody` (`ui_modal.tscn` dan `ui_modal.gd`) untuk mencegah regresi pengukuran autowrap Godot (godotengine/godot#83546) yang sebelumnya menyebabkan dialog melapor tinggi absurd dan memanjang kosong. Dialog kini pas dan rapat membungkus kontennya.
8. **Web Build Native Camera & Desktop Webcam Support**: Ditambahkan jembatan `JavaScriptBridge` pada `scan_flow.gd` (`_request_web_photo` dan `_on_web_file_selected`) saat `OS.has_feature("web")`. Pada browser mobile (iOS/Android), digunakan HTML `<input type="file" accept="image/*" capture="environment">` untuk membuka kamera bawaan HP; pada browser desktop (MacBook/PC), digunakan modal WebRTC `getUserMedia` (`Webcam Viewfinder`) live stream dengan preview mirrored dan tombol "Take Photo" un-mirrored, dilengkapi auto-resize canvas client-side ke `FOTO_MAX_PX` (1280px, JPEG 85%). Alur Android native APK (`GodotGetImage`) tetap tidak tersentuh.
