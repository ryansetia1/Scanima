# 14 — Log deploy

Riwayat rollout yang sebelumnya hidup di `CLAUDE.md`. Isinya dipindahkan verbatim; urutannya sama dengan urutan di file asal, bukan kronologis. Yang berlaku sekarang diringkas sebagai tabel status di `CLAUDE.md` — file ini adalah catatan bagaimana keadaan itu tercapai, termasuk probe production dan angka yang terukur saat itu.

## 3 September 2026: `seekers/v2` — pose hit yang tercermin dan roster sebaya

Enam generation berbayar, $0.42 pada plafon konservatif `pricing.mjs` ($0,07)
atau ~$0,30 pada harga medium terukur, memperbaiki dua keluhan yang ternyata
sama-sama tertulis di prompt-nya sendiri, bukan variansi model.

**Yang rusak.** Tiga dari empat sel `concern_hit` digambar sebagai figur yang
**dicerminkan**: menjangkau ke canvas-right padahal kontrak mengunci canvas-left.
Buktinya bukan selera — kuncir feminine, landmark asimetrinya, pindah sisi
antara `intro_idle` dan `concern_hit`. Akarnya kata "recoil" di arah pose 5: ia
satu-satunya pose yang menyuruh badan menjauh dari arah yang dihadapinya, dan
model menyelesaikan pertentangan itu dengan membalik figur. Ini pengulangan
persis temuan v16 pada sheet Anima ("instruksi facing global saja belum cukup"),
dan obatnya sama: kontraknya diulang **di dalam** baris pose itu, bukan hanya di
blok global. Dua keluhan estetika juga tertulis eksplisit: `masculine.md` meminta
"mid thirties … weathered" plus stubble, dan `automaton.md` meminta antena
berdisc yang di art jadi blob melayang di atas kepala.

**Yang berubah.** `roster_sheet.md` mendapat Roster consistency lock (umur
pertengahan 20-an, tinggi dan rangka sama, pembeda hanya outfit/rambut/palet/
gender read), aturan landmark asimetri tidak boleh pindah sisi, dan pose 5
ditulis ulang sebagai *lean* ke belakang yang tetap menghadap canvas-left.
Umur/build dicabut dari keempat file figur supaya tidak ada dua sumber
kebenaran. Antena automaton diganti larangan eksplisit "nothing protrudes".

**Biaya dan urutan.** Karena `roster_sheet.md` dipakai bersama, mengeditnya
membatalkan hash prompt keempat slug, jadi ronde pertama empat generation
($0.28). Hasilnya: androgynous, feminine, automaton bersih; masculine masih
tercermin. Roll kedua masculine ($0.07) membuka penyebab kedua yang lebih halus
— deskripsi strap "from the right shoulder to the left hip" **ambigu**, kanan
menurut karakter atau penonton, dan pose yang diimprovisasi menyelesaikannya
dengan memutar figur. Ditulis ulang dalam istilah kanvas (high canvas-RIGHT
shoulder → low canvas-LEFT hip, diagonal yang sama di sembilan sel). Hasil roll
kedua tidak tercermin lagi (strap dan wajah benar) tetapi tangan menjangkaunya
terayun ke canvas-right sebagai penyeimbang, sebab teks pose 5 menyuruh bahu
"draw **in**" sekaligus tangan "reaches **out**" sambil "torso tips back". Roll
ketiga ($0.07) mengunci keduanya di `masculine.md` saja — kedua tangan tetap di
paruh canvas-left, lengan jauh rapat di rusuk — dan lolos. Ketiga roll masculine
hanya menyentuh `figures/masculine.md`; menyentuh file bersama untuk itu akan
berharga $0.21 tambahan.

**Deteksi otomatis dicoba dan sengaja diturunkan jadi penunjuk.** Dua metrik
diuji terhadap 8 sampel berlabel (v1 dan v2 keempat slug). Reach skew — pusat
massa horizontal relatif pusat bbox, positif kalau tungkai terulur memanjangkan
bbox ke canvas-left sementara massa tertinggal — benar 7/8: ia menangkap ketiga
sel tercermin v1 (-0,049/-0,068/-0,084 lawan +0,056) tetapi menuduh feminine v2
yang benar (-0,013), sebab kuncirnya memanjangkan bbox ke kanan dan meniru
tanda tangan cermin. Kandidat kedua, korelasi sidik jari 8×8 terhadap idle yang
dibalik, juga 7/8 dengan margin setipis 2% pada kasus sulit. Gerbang yang bisa
memberi alarm palsu pada aset $0.07 mendorong regenerasi yang tidak perlu, jadi
angkanya dicetak `--strip` sebagai penunjuk "lihat sel ini duluan" dan `--check`
tetap hanya menegakkan provenance, hash, dan dimensi — invarian tanpa alarm
palsu. `--strip` sendiri yang jadi gerbang sungguhan: kesembilan pose × keempat
slug dalam satu PNG, gitignore karena turunan gratis.

**Kenapa `facing_audit.mjs` tidak dipakai di sini.** Jalur Anima sudah punya
penyelesaian yang lebih murah: Vision dua pass yang harus setuju, lalu sel
tercermin dibalik lewat `meta.flipPoses` seharga ~$0.006. Ia tidak dipasang
untuk roster karena `auditableCells()` terikat nama pose Anima, dan — yang
menentukan — membalik satu sel ikut membalik landmark asimetri figur, sehingga
strap masculine atau kuncir feminine berpindah sisi dan sel itu jadi ganjil di
antara delapan lainnya. Untuk Anima flip itu bersih; untuk Seeker ia menukar
cacat arah dengan cacat landmark.

**Verifikasi.** `--check` 4/4, `npm run selftest` hijau, `test_sprite_slicing`
OK (304 check, pasangan pose termirip 72–118 terhadap ambang 12),
`test_scan_ui` OK (1581 check). Sumber PNG 2,336 MiB versus 2,330 MiB
sebelumnya, selisih 0,2%, jadi angka PCK 1,93 MiB di bawah ini tetap berlaku.
Art dan provenance `seekers/v1` tidak diarsipkan ke path terpisah — riwayat git
sudah menyimpannya, dan `git show HEAD~1:game/assets/seekers/<slug>.png`
memulihkannya kalau perlu dibandingkan.

## 3 September 2026: art final Seeker Roster menggantikan placeholder

Empat generation `openai/gpt-image-2` medium, satu per figur, tanpa retry
otomatis, lewat `backend/tools/generate_seeker_art.mjs <slug> --paid --apply
"--ack=US$0.07"`. Angka ack-nya dibaca dari `pricing.mjs`, jadi ia plafon
konservatif $0,07 per gambar, bukan harga medium terukur ~$0,05. Prompt
`seekers/v1`: satu kontrak bersama
`backend/prompts/seekers/roster_sheet.md` plus empat arahan per figur di
`backend/prompts/seekers/figures/`. Raw prediction disimpan ke
`backend/generated/seekers/raw/` bersama provenance per slug, jadi seluruh
perbaikan post-processing di bawah ini dikerjakan dengan `--reprocess`, nol
panggilan API tambahan.

Pertumbuhan build diukur dengan dua `--export-pack Android`, dengan dan tanpa
`game/assets/seekers/`: 29.311.712 versus 27.288.936 byte, jadi **2.022.776 byte
= 1,93 MiB**. ADR-0002 memperkirakan ~3,2 MB, jadi angkanya di bawah perkiraan
dan ADR-nya tidak perlu dievaluasi ulang. Empat `.ctex` hasil impor berjumlah
1,93 MiB, cocok dengan delta PCK-nya.

Dua cacat kosmetik ditemukan sesudah generation dibayar, dan keduanya diperbaiki
alih-alih ditolak — sesuai aturan biaya di `CLAUDE.md`:

- **Pose lebih tinggi daripada selnya.** Generation pertama gagal
  `GRID_SEAM_VIOLATION` (`special_command->last_anima:26553px`) karena figur
  meluber 5–9px ke sel tetangga, dan masculine `victory` bahkan 353px terhadap
  sel 341px. `postprocessChromaGridSheet()` mendapat opsi `alignCells`: kalau
  ada pose yang tidak muat, seluruh sheet diperkecil seragam sesuai
  `cellFitScale()` lebih dulu, lalu setiap pose digeser minimal ke dalam selnya
  dan hanya piksel miliknya yang di-blit. Terukur `content_scale` 0,9660
  (masculine) dan 0,9827 (automaton); androgynous dan feminine 1,0.
- **Spill hijau yang diteduhkan figurnya sendiri.** Terlihat sebagai bercak
  hijau di mantel automaton pada arena Duel, plus garis 1px kehijauan di tepi
  potong bust Profile. Sebabnya `isKeyContaminatedEdge` menuntut `g >= 220`
  karena ia mengasumsikan campuran dengan keyline **putih**; campuran dengan
  art **gelap** mendarat di `rgb(10,110,48)`. Ditambahkan
  `stripSeekerSpillInPlace()`, opt-in lewat `despill` dan hanya untuk jalur
  Seeker. Terukur turun dari 4.096–5.809px per sheet menjadi 10–32px. Cincin 1px
  terluar tinggal 20,8%–34,1% green-dominant, dibandingkan **53,7%** milik Boss
  Seeker Confectioner yang sudah production sejak chapter v1 — jadi lebih bersih
  daripada baseline, dan sisanya sengaja tidak dikejar karena batas berikutnya
  sudah menyentuh art sungguhan.

Verifikasi visual lewat harness yang sudah ada, portrait 526×1024 dan landscape
1600×720: picker `--seeker-avatar-demo`, potret Profile `--trophy-demo`, lalu
ketiga arena `--battle-demo`, `--team-battle-demo`, dan
`--sugarworks-zone-demo=1`. Suite yang dijalankan hijau: `npm run selftest` (44
skenario, `generate_seeker_art.mjs --check` sekarang ikut di dalamnya),
`test_sprite_slicing` 304, `test_scan_ui` 1576, `test_i18n` 5120,
`test_client_state` 199, `test_auth_flow` 63, `test_game_rules` 181,
`test_expedition_route_map` 91, `test_battle_sim_parity` 530.

## 30 Agustus 2026: kurva Level tajam + band Level matchmaking Duel

Latar belakang penuh dan keputusan arah ada di
[`docs/designs/2026-08-30-level-curve-and-duel-matchmaking.md`](designs/2026-08-30-level-curve-and-duel-matchmaking.md).
Ringkas: pemain melaporkan Duel Lv 13 HP 292 melawan bot Lv 4 HP 240 terasa
seperti underdog match padahal Level-nya jauh — terukur win rate pemain 40,6%,
bukan walkover seperti dijanjikan angka Level. Akar masalahnya tiga lapis:
`GROWTH_PER_LEVEL` lama (`0,02`) membuat Level nyaris tidak berarti (satu poin
base stat Vision ≈ 1,13 Level), matchmaking Duel buta Level dan malah
menyamakan base stat lawan ke anggaran pemain, dan keduanya saling menutupi.

Perubahan: `GROWTH_PER_LEVEL` naik ke `0,09` (Lv 40 ×4,51). Ini merusak pacing
turn kalau berdiri sendiri (`100/(100+DEF)` tidak skala-invarian, Lv 40 mirror
duel jadi 10,2 turn) — perbaikan wajibnya `mitigationBase(level) = 100 ×
growthMultiplier(level)` dipakai sebagai basis mitigasi `computeDamage`,
disimpan per-fighter di `mitigation_base` saat `createFighter`. Session lama
(TTL 30 menit) tanpa field itu jatuh ke default `100`, jadi **tidak perlu
menaikkan `RULES_VERSION`**. Sesudah perbaikan, mirror duel Lv 1/13/40 kembali
ke ~4 turn.

Matchmaking Duel (`pickFairCandidate`) diberi band Level `±30% (minimum ±3)`
sebelum shortlist taksiran; base stat lawan tidak lagi direscale ke anggaran
pemain — yang disetel adalah Level efektifnya (`refitLevel`), dipakai untuk
stat maupun tampilan HUD. Team Battle mendapat perlakuan sama: tiga template
sistem (`scrap-scavengers` Lv 2, `starter-sentinels` Lv 4, `vault-wardens` Lv
7) sekarang direfit ke rata-rata Level roster pemain di `createCandidates()`,
sebab Level tetapnya jadi latihan sasaran begitu kurva menajam.

**Tidak dikerjakan dalam rollout ini:** Expedition The Sugarworks (70 lawan
chapter v1–v7 semuanya `level: 12`) belum mendapat chapter v8 dengan ramp Level
per zona. Pada kurva baru level 12 tetap (×1,99) melayani rentang pemain yang
jauh lebih sempit daripada sebelumnya (×1,22) — pemain Lv 4 nyaris tanpa
peluang, pemain Lv 30 menang tanpa perlawanan. Membuat versi chapter baru
menyalin ~57 MB aset per versi dan menyentuh pipeline `chapter_factory`
(ledger, manifest hash) yang belum divalidasi untuk perubahan level-only;
ditunda sebagai pekerjaan terpisah alih-alih dipaksakan lewat penyalinan file
manual.

Golden vector diregenerasi (`node backend/tools/emit_sim_vectors.mjs`); tiga
fixture team battle (`team-basic`, `team-voluntary-switch`, `team-long-grind`)
diperpanjang supaya total turn yang terekam tetap ≥60 setelah battle-battle
mismatch-level (crusher vs bossPack) selesai lebih cepat di bawah kurva baru.
Fixture `selftest.mjs` skenario 34 (roster production win rate) dan skenario
38 (`duelWinRate(adult, hatchling)`) diukur ulang terhadap resolver production,
bukan ditebak — beberapa pasangan pilihan (mis. klasik vs Playtron) berubah
plausibility-nya di bawah kurva baru dan diganti pasangan lain yang tetap lolos
shortlist.

## APK 23-24 Agustus: Publish Atlas UI, reject-reason dialog, dan saga ItemList touch scroll

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

## HUD restructure, toast 4-state, loading screen, dan unifikasi tab Anima (25 Agustus 2026)

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

## UAT follow-up: thumbnail preview, reject-reason dialog, dan Realtime admin

23 Agustus 2026 malam, UAT pertama di console live menemukan dua hal nyata:
dialog konfirmasi native `<dialog>` merender di pojok kiri-atas (Tailwind
preflight me-reset `margin` yang biasanya membuat `<dialog>` center secara
default — diperbaiki lewat `margin:auto` via fixed+transform di
`globals.css`), dan entry yang belum pernah disetujui (rejected sebelum
sempat publish) tidak punya `thumb_path` sama sekali sehingga Idle thumb
kosong di Queue, Case Detail, dan daftar Publications Seeker (yang sebelumnya
cuma `JSON.stringify` mentah). `admin_moderation` sekarang crop idle langsung
dari full sheet sebagai data URI read-only saat `thumb_path` kosong — tidak
pernah ditulis ke storage karena entry itu mungkin tidak pernah disetujui.

Player sekarang melihat alasan reject: tombol Publish yang ditolak tetap
bisa ditekan (bukan mati), membuka dialog kategori player-safe (tidak pernah
teks mentah model) plus catatan moderator kalau staff menulis satu saat
reject manual, dan tombol Request Review konsisten di dalam dialog yang sama
selama kesempatan appeal untuk versi art itu belum terpakai. `gallery`
`my_status` membawa `reject_category`/`reject_note`/`appeal_available` hanya
untuk entry rejected (nol biaya tambahan di jalur approved/pending).
`GalleryAppealButton` yang berdiri sendiri dihapus; appeal sekarang satu
titik interaksi lewat tombol Publish yang sama.

Admin console mendapat Realtime sungguhan (bukan polling): migration
`20260823160255_atlas_moderation_realtime_rls.sql` menambah RLS SELECT
policy staff-only (`is_staff(auth.uid())`) pertama di seluruh tabel Atlas
Moderation Admin — sebelumnya semua default-deny total. Queue dan Case Detail
subscribe `postgres_changes` di `moderation_cases`/`moderation_decisions`/
`gallery_reports` lewat publishable key dari browser; payload event tidak
pernah dipakai untuk render, cuma memicu `router.refresh()` supaya
`admin_moderation` tetap satu-satunya sumber logika render. `quota_rules.sql`
diperbarui (RLS moderation_cases kini memberi grant SELECT tapi menyaring
baris, bukan menolak total) dan lulus dua kali langsung di production,
termasuk pembuktian nyata: satu case production ("Padronic") ada saat
diperiksa sebagai service-role, nol baris saat diperiksa sebagai authenticated
non-staff.

## Atlas Moderation Admin v2 live: schema, admin_moderation, dan console

23 Agustus 2026, migration `20260823080000_atlas_moderation_v2_schema`
ter-apply ke production tanpa drift; `quota_rules.sql` (termasuk blok baru
untuk staff role gate, idempotent case-open, thumb-required approve/restore,
report quarantine dengan pemetaan kategori, dan sanction lifecycle) lulus dua
kali berturut-turut langsung di remote. `admin_moderation` dan `gallery`
(moderasi dua-pass) dideploy; keduanya menjawab 401 tanpa JWT, menandakan
modul boot dan pagar berdiri. Console `admin/` (Next.js 16, Control Deck)
dijalankan lokal terhadap production dengan kredensial publishable asli.

Redirect `http://localhost:3000/auth/callback**` ditambahkan ke Auth
allowlist lewat PATCH Management API pada field `uri_allow_list` saja —
bukan `supabase config push`, karena `config.toml` lokal membawa entri
`https://127.0.0.1:3000` yang ternyata tidak pernah live di remote (dicek
lewat GET sebelum PATCH) dan section `[auth.external.google]`-nya memakai
placeholder `env(SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID/SECRET)` yang kalau
di-push utuh akan menimpa client secret Google asli dengan string kosong.
Diverifikasi sesudahnya: `external_google_enabled`,
`external_anonymous_users_enabled`, dan `security_manual_linking_enabled`
semua tidak berubah.

Sign-in pertama `ryansetiawan.works@gmail.com` sempat menjawab 500
`admin_moderation gagal diproses` dari operation `whoami` — bukan 403
`STAFF_FORBIDDEN` yang diharapkan sebelum bootstrap. Query SQL langsung ke
`staff_accounts` untuk uid yang sama berhasil nol baris tanpa galat, tapi
panggilan lewat REST (`.from("staff_accounts")`, jalur yang dipakai
`admin_moderation`) tetap gagal — cache schema PostgREST belum tahu tabel
baru dari migration yang baru saja ter-apply. `notify pgrst, 'reload
schema';` memperbaikinya seketika; diverifikasi lewat REST langsung ke tujuh
tabel baru dan satu RPC, semuanya 200 sesudah reload. Bootstrap admin lewat
snippet SQL di `docs/15-commands.md` sesudah itu berhasil di percobaan
pertama, console termuat penuh, dan `feature_atlas_moderation_v2` di-flip ke
`true`.

## Follow-up UAT state Publish Atlas dan musik Retreat Team

23 Agustus 2026 pukul 12:40 WIB, UAT membuktikan dua bug client dan satu hasil
moderation yang sah. Probe production menemukan Padronic dan Drakabyss tersimpan
`rejected` dengan alasan model bahwa art tampak seperti karakter/creature
franchise yang dapat dikenali. VerdantPup, klasik, dan Sunhound tersimpan
`approved`. Pagar moderation tidak dibypass dan tidak ada perubahan backend,
migration, maupun panggilan model tambahan.

Profile sebelumnya masih membawa status publication Anima lama selama request
`my_status` berikutnya terbang, sehingga **Unpublish from Atlas** sempat
berkedip menjadi **Publish to Atlas**. Sekarang pergantian `anima_id`
membersihkan state itu lebih dulu. Rejection dari response Publish maupun status
server berikutnya tetap terlihat sebagai tombol disabled **Cannot publish to
Atlas**, bukan membuat tombol hilang; toast juga menjelaskan kategori konten
tidak aman/franchise tanpa membocorkan output model mentah.

Team Battle menyembunyikan view setelah hasil Retreat, tetapi arena terminalnya
sengaja tetap tersimpan untuk reopen. `music_cue` sebelumnya membaca arena
internal itu tanpa memeriksa visibility. Ia sekarang memakai gate immersive
yang sama dengan shell chrome: hanya arena Duel, Team, atau Expedition yang
benar-benar terlihat yang dapat meminta musik Battle/Boss.

Pagar gratis lulus: 42 skenario shared + 12 signature webhook, **1.378** check
UI, dan **4.827** i18n; linter serta compile check tiga GDScript bersih. APK
debug 57.276.155 byte dibangun pukul 12:55, memuat `INTERNET` + `CAMERA`,
signature v2 sah, dan ketiga script yang berubah ada sebagai `.gdc`. Install
selesai pukul 13:10:50 setelah Wireless debugging memberi endpoint baru
`100.96.188.61:42349`; streamed install pertama putus tanpa diagnostic, lalu
`--no-streaming` mendorong 57 MB lewat DERP selama 200 detik dan sukses.

## Rival Team dari Atlas, public name Veridian, dan client battle polish

23 Agustus 2026, migration `20260823003917_atlas_team_rivals` dan
`20260823073500_fix_veridian_public_name` ter-apply tanpa drift; blok
`quota_rules.sql` lulus sesudahnya. `team_battle` 10 ACTIVE,
`verify_jwt=true`, dan smoke tanpa token menjawab 401
`UNAUTHORIZED_NO_AUTH_HEADER`.

Team Battle tidak lagi membaca Defense Team yang harus dipublish manual.
`createCandidates` membaca publication Atlas yang published + approved +
tidak auto-hidden, menetralkan care snapshot, lalu merakit kombinasi unik tepat
sebesar roster pemain (2, 3, atau 4). Kombinasi mengutamakan pemilik berbeda,
tetapi boleh memakai dua publication pemilik yang sama bila jumlah Seeker belum
cukup; `owner_id` dan nickname privat tidak masuk snapshot. Template sistem
dipotong ke ukuran yang sama, lalu pipeline combat-power tier yang sudah ada
tetap memilih sampai tiga candidate paling dekat. RPC replace dan start session
sama-sama menolak jumlah anggota berbeda. Probe production sesudah deploy
menemukan 2 publication Team yang eligible dan 3 template sistem aktif yang
masing-masing berisi 4 anggota, jadi roster 3/4 tetap punya fallback exact-size.

Migration kedua memperbaiki hanya projection legacy Veridian
`c80ddef5-533d-4f36-9f26-7f449981e996` yang masih generik. Probe sesudah apply:
`gallery_entries.display_name = Veridian`,
`atlas_forms.display_name = Veridian`, dan nol snapshot Duel Veridian tersisa
dengan nama kosong/`Anima`. Rename privat tidak disentuh.

Client build yang sama membawa:

- **Publishing… / Unpublishing…** dan lock tombol selama request Atlas;
- pagination Atlas yang mempertahankan grid lama dan menyembunyikan **Load
  More** setelah cursor habis;
- Level di picker Team/Expedition serta row **Back + Save Team** dengan lebar
  50/50;
- hilangnya **Publish Defense**;
- pelat gelap berbingkai cyan yang membungkus nama/HP kedua fighter Duel;
- cue musik yang membaca arena Duel yang benar-benar terlihat, bukan session
  lama yang tersembunyi saat masuk mode lobby lain.

Pagar gratis lulus: 42 skenario shared + 12 signature webhook, 1.369 check UI,
dan 4.822 i18n. Deno CLI tidak terpasang di mesin ini, tetapi deploy bundling
Edge Function sukses. APK debug 57.273.971 byte dibangun dalam 9,8 detik,
memuat tepat `INTERNET` + `CAMERA`, 22 referensi `GodotGetImage`, dan signature
v2 sah. Install wireless ke `23127PN0CG` sukses pukul 08:10:05 WIB. Layar
perangkat masih `Dozing` dan HyperOS tetap menolak input injection, jadi boot
dan tap flow client baru masih menunggu layar dibuka manual.

## Kelayakan lawan Duel diputuskan simulasi, bukan taksiran

23 Agustus 2026, `battle_anima` 30 ACTIVE (`verify_jwt=true`, smoke 401); nol
migrasi, nol perubahan client, nol panggilan model. Kelanjutan langsung dari
entri di bawah: dua ujung yang dicatat "lolos heuristik walau di luar band even"
sekarang ditolak.

**Band-nya tidak bisa dikalibrasi ulang, dan itu yang diukur lebih dulu.** Kalau
`REAL_BALANCE_MIN/MAX` cuma perlu digeser, itu dua konstanta. Sweep atas **552
pasangan** — seluruh pasangan roster production plus bentuk stat acak termasuk
hiper-spesialis `95/95/95/10/10` — dengan patokan 512 duel per pasangan
menunjukkan ketiga kelas saling tumpang tindih sepenuhnya:

| Kelas hasil simulasi | Jumlah | Sebaran rasio taksiran |
| --- | --- | --- |
| adil (`tough` / `even`) | 78 | 0,430 – 1,187 |
| walkover (`favorable`) | 288 | 0,000 – 0,949 |
| mustahil (`formidable`) | 186 | 0,702 – 16,832 |

Tidak ada satu pun band di 0,30..1,60 yang nol false accept. Band yang dipakai,
0,53..1,00, meloloskan **70 dari 138** kandidat sebagai duel timpang — win rate
yang lolos membentang **0,8% sampai 100%**, jadi gate itu praktis dekoratif. Band
paling ketat yang bisa dicari, 0,765..0,940, masih meloloskan duel 10% sambil
membuang 42 dari 78 matchup adil: pertukaran yang lebih buruk, bukan lebih baik.

Yang **tidak** diukur sebelumnya: tier lawan terpilih sudah disimulasikan
`duelWinRate()` untuk `battleRewardPreview()`. Jadi jawaban eksaknya sudah dibayar
setiap duel dan cuma tidak dipakai untuk memutuskan. Perubahannya karena itu
memakai ulang yang sudah ada, bukan menambah mesin baru: heuristiknya diturunkan
menjadi **shortlist** (`isFairRealOpponent()` → `isPlausibleRealOpponent()`; nama
lamanya adalah akar masalahnya, ia berjanji menilai keadilan padahal cuma
menaksir), dan `isWinnableDuel()` — tier `tough` atau `even`, ambangnya dari
`REWARD_TIERS` supaya tidak ada notion ketiga tentang "adil" — yang memutuskan
atas paling banyak `DUEL_GATE_CANDIDATES = 3` kandidat. Win rate kandidat yang
lolos diteruskan ke `battleRewardPreview(..., knownWinRate)`, jadi lawan terpilih
tidak menambah satu simulasi pun.

Band-nya sengaja **tidak digeser**. Untuk peran barunya ia sudah baik: ia
menaikkan proporsi matchup adil dari 14,1% base rate ke 49,3%, jadi kandidat
pertama yang disimulasikan biasanya langsung lolos. Melebarkannya ke 0,480..1,190
menaikkan recall 87,2% → 98,7% tetapi memberi hasil akhir yang identik (10/12
dapat lawan sungguhan) dengan simulasi lebih banyak, 2,08 versus 1,75 per duel.

Terukur sesudahnya pada roster production 12 Anima:

| | Sebelum | Sesudah |
| --- | --- | --- |
| Win rate lawan sungguhan yang diterima | 0,8% – 100% | **41,0% – 86,1%** |
| Tier yang bisa disajikan Duel | keempatnya | **`even` dan `tough` saja** |
| Anima yang dapat lawan sungguhan | 12/12 | 10/12 (2 jatuh ke Echo) |
| Simulasi per duel | 1 (tier saja) | 3,08 |
| Wall time terburuk, Anima paling tebal | 66,4 ms | **76,8 ms** |

Kasus yang dilaporkan operator: Gearbit Racer vs Veridian (balance 0,941, lolos
shortlist) disimulasikan **31,3%** → `formidable` → ditolak; VerdantPup vs
Veridian (balance 0,666) disimulasikan **87,5%** → `favorable` → ditolak.
Keduanya sekarang mencoba kandidat berikutnya, lalu Echo.

Cap 3 dipilih terukur, bukan ditebak: cap 2 memberi 8/12 lawan sungguhan dan cap
4 tidak menambah apa pun karena shortlist-nya sendiri sudah habis. 76,8 ms masih
di bawah plafon ~80 ms yang dicatat `balancedRatio()`; kalau nanti terlewati,
turunkan `runs` pencarian ke 32, **bukan** cap kandidat — cap yang lebih kecil
langsung menukar lawan sungguhan dengan Echo.

Derau 64 duel tetap ada di ambang dan sengaja dibiarkan: dua matchup roster yang
dinilai 78,1% dan 76,6% sebenarnya 86,1% dan 83,8% pada 512 duel. Bayarannya
tetap jujur sebab tier memakai angka 64 duel yang **sama** dengan gate — pemain
dibayar sesuai duel yang gate-nya lihat. Menaikkan `runs` menggandakan biaya
kedua sisi hanya untuk menggeser kasus di ambang.

Skenario 34 `npm run selftest` membawa pagarnya: 12 pasangan fixture yang
benar-benar lolos shortlist (enam ditolak simulasi, enam diterima), assert bahwa
Duel tidak pernah menyajikan tier selain `tough`/`even`, assert bahwa
`battleRewardPreview` identik dengan dan tanpa `knownWinRate`, plus pemeriksaan
sumber bahwa `startBattle` memanggil `duelWinRate` dan membatasinya dengan cap.
Monotonisitas tier dipisah ke daftar tanpa filter matchmaker, sebab itu sifat
`battleRewardPreview` sendiri dan gate baru membuat daftar yang tersaring hanya
memuat dua tier.

Wiki ikut berubah karena pemain merasakannya: `battle.md` mengganti "menaksir
dulu" menjadi duel yang benar-benar dimainkan, menyebut Echo akan lebih sering
muncul, dan mencatat Duel hanya membayar 7–12 Bits (`even`/`tough`) sementara
Favorable/Formidable tinggal di Team Battle dan Expedition; `economy.md` mengikuti
rentang Bits itu.

## Anima tanpa consent berhenti menjadi lawan Duel

23 Agustus 2026, `battle_anima` 29 ACTIVE (`verify_jwt=true`, smoke 401); nol
migrasi, nol perubahan client, nol panggilan model, nol perubahan wiki. Versi 28
membawa perubahan yang sama, dan 29 hanya membetulkan satu string `console.error`
yang masih menyebut fallback yang sudah tidak ada.

Operator melaporkan sesuatu yang terasa bertentangan: bermain sebagai guest ia
bertemu **Veridian** di Duel, tetapi tab **Duel** di Atlas guest itu kosong,
sementara di akun Google pemiliknya tombol **Publish to Atlas** masih menyala dan
belum pernah ditekan. Ketiganya benar sekaligus, dan hanya satu di antaranya bug.

Probe production: Veridian (`c80ddef5`) punya **nol** baris `gallery_entries`,
jadi tombol Publish yang menyala memang jujur. `battle_sessions` mencatat tiga
sesi dengan `bot_anima_id` Veridian — dua di antaranya milik guest anonim
`macosm3pro` pada 22 Agustus (00:27 `won`, 22:52 `lost`), dan yang ketiga 20
Agustus dari akun lain saat Veridian masih dimiliki guest `518a96ab`, jadi bukan
self-duel. Atlas guest itu hanya punya dua discovery `scanned` dan nol `duel`,
yang **benar**: trigger `atlas_record_battle_session` sengaja berhenti sebelum
mencatat kalau bot tidak punya publication published+approved. Atlas kosong
adalah Atlas yang benar; yang salah adalah matchmaking-nya.

Akarnya pool kedua di `startBattle`. Di samping `gallery_entries` yang
ber-consent, ada query `animas` `.neq("owner_id", ownerId).eq("status",
"ready")` yang tidak menyentuh publication sama sekali; satu-satunya saringannya
apakah `species_key:color_bucket:stage` ada di `species_library`. Penanda itu
dimaksudkan menandai Anima era pustaka art bersama, tetapi ia tidak menanyakan
**kapan** Anima dibuat — jadi Anima baru ber-species umum ikut lolos. Terukur:
5 dari 12 Anima `ready` lolos penanda itu, **4 di antaranya belum pernah
Publish** (klasik, Mugshots, Playtron, Veridian), dan hanya Deckon yang benar
published. Sidik jarinya terekam di data: kedua `bot_snapshot` guest itu tidak
punya field `name` dan memakai `sheet_path`, bukan `sheet_url` — tanda tangan
jalur legacy, sebab jalur gallery selalu mengisi `display_name` dan
menandatangani URL.

Menggerbangi pool itu dengan consent hanya menghasilkan pool gallery lagi, jadi
ia dihapus alih-alih ditambal (−33 baris). Ketersediaan Duel tidak pernah
bergantung padanya sejak `systemDuelBot()` masuk pada 17 Agustus, dan bot sistem
justru lebih seimbang: kekuatannya dicari per-Anima ke target 65% menang,
sedangkan kandidat legacy cuma perlu lolos gate 0,53..1,00.

Diukur dengan resolver production terhadap stat asli, nol panggilan API. Veridian
(Level 15, total base stat 245, `plant` tunggal) melawan Echo yang dirakit
untuknya: balance 0,746, menang **65,6%**, tier `even` — tepat di target. Deckon,
satu-satunya Anima published sekarang, **ditolak** gate sebagai lawan Veridian
(balance 0,453, walkover 100%), jadi pemiliknya mendapat Echo, bukan duel timpang.
Kalau Veridian dipublish, 6 dari 11 Anima lain menerimanya sebagai lawan seimbang
(Chromvein 57,8%, Playtron 59,4%, klasik 42,2%, Deckon 35,9%, Gearbit Racer 31,3%,
VerdantPup 87,5%) dan lima ditolak dengan benar: Mugshots 0%, Drakabyss 0%,
Drowake 0%, Padronic 7,8%, dan walkover Sunhound 95,3%. Dua ujung yang lolos —
Gearbit Racer 31,3% dan VerdantPup 87,5% — duduk di luar band `even` hasil
simulasi walau lolos heuristik `estimateDuelBalance`; itu imprecision gate yang
sudah ada sebelumnya, dan labelnya tetap jujur karena tier dihitung dari simulasi,
bukan dari heuristik itu. Keduanya ditutup hari yang sama oleh `battle_anima` 30
di entri di atas: heuristiknya diturunkan menjadi shortlist dan simulasi yang
memutuskan.

Wiki tidak diubah karena ia sudah benar sejak awal: `atlas.md`, `economy.md`,
dan `battle.md` sama-sama hanya mengenal dua sumber lawan — Anima yang sudah
Publish, atau lawan sistem Echo. Kodenya yang melanggar dokumen, bukan
sebaliknya. Konsekuensi yang disengaja: dengan baru satu Anima published,
hampir semua Duel menjadi Echo sampai lebih banyak pemain Publish; wiki sudah
menyebut kondisi itu (`selama pemain masih sedikit itu sering terjadi`).

Skenario 23 `npm run selftest` dibalik arahnya. Sebelumnya ia **menuntut**
fallback legacy ada (`legacyCandidates ... .filter`); sekarang ia menuntut
`startBattle` menyentuh tabel `animas` tepat sekali, tidak memuat
`.eq("status", "ready")`, dan mempertahankan ketiga gerbang publication. Pagar itu
ada karena jalur ini gagal senyap — nol error, cuma art privat di arena orang
lain.

## Publish to Atlas berhenti buntu untuk guest

23 Agustus 2026, client saja; nol migrasi, nol Edge Function, nol panggilan
model. `gallery/publish` selalu ber-`requireLinkedGoogle`, tetapi
`_refresh_gallery_status()` hanya memeriksa ready + `typing_v2` + bukan rejected
— tidak pernah Google. Guest karena itu melihat tombol **Publish to Atlas**,
menekannya, dan dijawab `GALLERY_LINK_REQUIRED` sesudah request yang tidak
mungkin berhasil. Servernya benar; UI-nya yang mengiklankan sesuatu yang belum
bisa dilakukan.

Tombolnya sengaja tetap terlihat karena ia memang mengiklankan fiturnya.
`_toggle_gallery_publish()` sekarang memeriksa `GameState.is_anonymous()`
**sebelum** consent asli dan membuka `atlas_publish_signin`: penjelasan singkat
plus **Sign in with Google**. Konfirmasi itu memanggil
`_show_sign_in_confirmation()` — choice `Keep Guest Separate` / `Move Guest
Progress` / Cancel — bukan `_show_transfer_confirmation()` langsung, sebab
pilihan akun itu invarian dan publish tidak berhak melewatinya.

Intent tap itu selamat melewati round trip OAuth lewat `_publish_after_sign_in`
berisi `{anima_id, uid}`; `_resume_pending_publish()` di ujung
`_on_auth_succeeded()` membuka kembali profil Anima beserta consent-nya. Dua
invarian di sana. Pertama, intent **dikonsumsi sebelum** pagar apa pun diperiksa
— kalau urutannya dibalik, `separate` meninggalkan intent terkokang dan sign-in
berikutnya menerbitkan Anima yang tidak pernah diminta. Kedua, UID pembuatnya
dibawa serta alih-alih disimpulkan dari roster: transfer justru didefinisikan
sebagai UID yang tidak berubah (`auth_flow.handle_callback_url()` membatalkan
pertukaran token kalau `new_uid != guest_uid`), jadi kecocokan UID menyatakan
langsung "pemiliknya masih orang yang sama" dan `separate` gagal karena
konstruksi. Ini kenyamanan UI, bukan kontrol keamanan: `publishEntry` tetap
menolak dengan `ANIMA_NOT_OWNED`.

Urutan dua tombol pertama sekarang mengikuti isi roster:
`_sign_in_move_first = not _roster.is_empty() or _guest_scan_locked()`. Klausa
kedua ada karena roster yang gagal dimuat akan membungkam peringatan itu tepat
pada pemain yang paling membutuhkannya — `guest_scan_used_at` adalah bukti kedua
dari sumber lain, dan salah memperingatkan lebih murah daripada diam.
`SEEKER_SIGN_IN_CHOICE_BODY` membuang framing "safe default" yang menyesatkan,
`SEEKER_SIGN_IN_CHOICE_BODY_ANIMA` baru menyebut konsekuensi kedua tombol dengan
nama, dan tap yang mendarat saat `_busy` menjawab `SEEKER_SWITCH_BLOCKED`
alih-alih diam.

Satu regresi ditemukan di pekerjaan sendiri: `_check_referenced_keys()` di
`test_i18n` hanya cocok dengan `tr(\s*"KEY"`, jadi key yang bersembunyi di cabang
`else` sebuah ternary multi-baris diam-diam kehilangan pemeriksaan
keberadaannya. Ketiga label dipindah ke variabel lokal sehingga tercakup lagi.

Verifikasi lulus, delapan suite: `test_scan_ui` 1.358, `test_i18n` 4.813,
`test_client_state` 196, `test_sprite_slicing` 174, `test_auth_flow` 63,
`test_game_rules` 181, `test_expedition_route_map` 91, dan
`test_battle_sim_parity` 590 check. APK debug 05:40 WIB berhasil dibangun ke
`/tmp/scanima.apk`: 57.269.155 byte, SHA-256
`d4e11d855f92d0652ae1cea8b7c6c709840e8e030c2c8f5a3173b934a06b3beb`, izin tepat
INTERNET + CAMERA, 22 string `GodotGetImage` di dex, signature sah, dan
`libgodot_android.so` terkompresi 74.945.024 → 27.030.921 byte. `adb devices -l`
butuh 110 detik lalu menjawab kosong, jadi sideload dan smoke fisik jalur ini
masih menunggu device tersambung. Semua pagar di atas adalah source scan: ia
membuktikan kodenya tersambung, bukan bahwa layarnya benar, dan
`_resume_pending_publish()` khususnya belum pernah dieksekusi sekali pun. Wiki
pemain ikut di langkah yang sama: `docs/wiki/atlas.md` dan `docs/wiki/seeker.md`.

## Resume picker layer, shared Team builder, toast, dan Seeker HUD

23 Agustus 2026, client saja. `BattlePickSheet` sebelumnya tetap di `z_index=0`
ketika dibuka dari result Duel terminal; fighter, pelat **Retreating**, dan
`BattleResultPanel` punya layer lebih tinggi, jadi Choose Anima benar-benar
terbuka tetapi terlihat di belakang dua surface lama. Root sheet sekarang
`z_index=20`, sama dengan modal shell.

Team dan Expedition sudah memakai `TeamRosterList` yang sama; perbedaan yang
tersisa ada pada flow builder. Team sekarang juga punya row **Back + Save**.
Back membatalkan edit lokal dan kembali ke rival lobby, lalu pembukaan berikutnya
memulihkan urutan tim tersimpan. **Next Battle**, **Try Again**, blocked
**Edit Team**, dan recovery tanpa team id semuanya membuka
`set_builder(_roster, _team_battle_team)` tanpa refetch hub atau kehilangan
argumen restore. Follow-up review menutup race saat Save: Back ikut disabled
selama `_busy`, dan `_leave_builder()` tetap menolak signal programatis sampai
commit selesai.

Toast global tetap satu komponen/funnel `_say()`: lantai tetap 76 px dihapus,
`_place_toast()` memakai minimum content aktual, dan perubahan teks memicu layout
ulang satu `process_frame` kemudian agar minimum wrapped text sudah terpropagasi.
Revision guard membuang relayout pesan lama; satu `call_deferred()` yang lebih
awal terukur masih membaca tinggi pesan sebelumnya. Top HUD mengganti label
SCANIMA dengan nama Seeker (`Guest Seeker` untuk guest) dan menghapus chip
Animas; hanya Cores + Bits tersisa, sementara Collection tetap di tab
**Animas**. Home demo mengikuti struktur production yang sama.

Verifikasi lulus: `test_scan_ui` 1.358 check, `test_i18n` 4.807 check, 0 orphan
signal, boot Play-mode bersih, serta parser/convention check project tanpa error
baru. APK debug final 05:26 WIB berhasil dibangun ke `/tmp/scanima.apk`:
57.268.707 byte, SHA-256
`115b777503a93b812856e762b68de38b4d6a347822ca9927ddb651ddb15bf8bc`,
izin tepat INTERNET + CAMERA, 22 string `GodotGetImage` di dex, signature v2
sah, dan `libgodot_android.so` terkompresi 74.945.024 → 27.030.921 byte.
Daemon ADB yang macet sudah di-restart; `adb devices -l` kembali selesai normal
tetapi tidak menemukan device. Sideload dan smoke fisik empat flow ini masih
menunggu device tersambung lagi.

## Ordered Team roster, Duel reset, dan arena sky reframe

23 Agustus 2026, client + enam generation art developer. Keanehan Team picker
bukan dari backend: `ItemList` multi-select melaporkan state bawaan Godot yang
diganti oleh satu tap dan selalu mengurutkan hasil berdasarkan indeks card.
Akibatnya checklist, counter, dan payload dapat menceritakan tiga hal berbeda,
serta Anima pertama di layar diam-diam menjadi starter. `TeamRosterList`
sekarang memegang satu array urutan tap; badge 1–4, counter, restore, dan payload
Team/Expedition semuanya membaca array yang sama. Slot 1 adalah fighter awal.

Result Team sekarang memakai **Next Battle** untuk win dan **Try Again** untuk
loss/draw/forfeit. Keduanya masuk lagi ke builder dengan roster terakhir
terpilih; Energy yang sudah kurang tetap mengubah CTA menjadi **Edit Team**.
Duel juga membersihkan event plate/damage/result/command lock pada
`set_loading`, `set_session`, dan `set_lobby`. `_apply_lobby()` mengembalikan
visibility Start sesudah request gagal, jadi `Retreating` tidak bocor ke Anima
berikutnya dan kartu Duel tidak hilang sesudah **Finding Rival** gagal.

Enam call GPT Image 2 medium—Duel night/day portrait+landscape dan Team
portrait+landscape—semuanya sukses satu kali dalam 42–49 detik per aset, tanpa
auto-retry; plafon konservatif batch US$0,42. Raw PNG, prediction ID, prompt,
reference snapshot, dan hash output hidup di
`backend/generated/ui_backgrounds/`. Source baru menaruh foot-contact pada 91%
seperti Expedition, runtime membuang zoom statis 1,18× menjadi 1,0×, dan
vertical pan 0,5 dipilih setelah screenshot: percobaan 0,96 justru mengunci crop
portrait ke bawah dan membuang langit yang baru dibuat. Screenshot portrait dan
1600×900 memastikan Duel/Team menampilkan lebih banyak langit, lantai lebih
pendek, dan kaki tetap berada di permukaan.

Verifikasi lulus: 42 skenario shared + 12 signature webhook, 1.337 check UI,
4.793 i18n, provenance background 12/12, 0 parser/convention error, dan 0 orphan
signal. APK debug 23 Agustus 2026 04:22 WIB berhasil dibangun 54,6 MB; manifest
tepat `INTERNET` + `CAMERA`, class `GodotGetImage` ada di dex, signature sah,
dan native library terkompresi 74.945.024 → 27.030.921 byte. Device Wi-Fi
`23127PN0CG` sempat terlihat sebelum build tetapi terputus saat `adb install -r`,
jadi APK baru belum tersideload dan device flow belum diuji.

## Team Battle 2–4, outcome global, dan Sugarworks v7

22 Agustus 2026. Team Battle dan Defense sekarang menerima 2–4 Anima, sementara
Expedition tetap tepat empat. Client selalu membuka builder sebelum Find Rivals;
roster 1/5 ditolak dan 2/3/4 diterima di pagar UI serta backend. Migration
`20260822152859_team_battle_variable_roster` sudah tercatat production dan
`team_battle` version 9 ACTIVE.

Level Up, Synthesis success/failure, dan Evolution success/failure sekarang
masuk satu FIFO milik shell, jadi outcome menunggu modal aktif dan tetap muncul
di screen mana pun. Evolution success menawarkan **Summon** atau **Rename**.
Bottom nav menjadi Home, Scan, Battle, Animas, Menu; static backdrop Duel/Team
dipan vertikal ke 0,88 tanpa mengubah Expedition.

Kegagalan Duel 500 yang tidak punya mapping 4xx/409 dicatat terstruktur tanpa
raw body melalui `battle_failures`; RLS-nya default-deny dan hanya service role
yang punya privilege. Migration `20260822155005_battle_failure_log` sudah
production. Advisor sesudah deploy menemukan kedua FK belum berindeks; migration
lanjutan `20260822160718_battle_failure_fk_indexes` menutupnya. Terminal failure
Evolve/Synthesis sesudah row generation ada memakai helper fail-open, sehingga
logging yang gagal tidak mengganti response asli. Function production:
`battle_anima` 27, `evolve_anima` 15, dan `synthesize_anima` 7, semuanya ACTIVE
dan `verify_jwt=true`. Keempat smoke tanpa JWT menjawab 401; blok
`quota_rules.sql` production selesai tanpa assertion.

Verifikasi client lulus: 42 skenario `npm run selftest` + 12 signature webhook,
1.323 check UI, 196 client-state, 4.776 i18n, 590 parity combat, 0 error parser,
0 issue convention, dan 0 orphan signal. Screenshot portrait memastikan Battle
berada di tengah nav, outcome Level Up menutupi arena sebagai modal global, dan
fighter Team berdiri pada lantai arena baru.

APK debug 23:22 WIB berhasil dibangun 54,7 MB. Manifest hanya membawa
`INTERNET` + `CAMERA`, class `GodotGetImage` ditemukan di dex, signature lolos,
dan `libgodot_android.so` terkompresi 74.945.024 → 27.030.921 byte. Tidak ada
device pada `adb devices`, jadi sideload dan uji akun
`ryansetiawan.works@gmail.com` belum dapat dijalankan; build 19:48 tetap yang
terakhir terpasang.

Sugarworks v7 (`7dae1c10-ffd7-4a26-b3ff-97000fae8060`, manifest
`f9effb7967c9cc90605f1be41ef5aa87d2756edea7780903a1cdbcf1759fa7ec`) sudah
di-stage lalu diaktifkan. V7 hanya membetulkan copy `ace_passive` dan
`last_anima` dari Cotton ke Nimbelisk; asset binary byte-identik dengan v6 dan
tidak ada model call.

## Skala Home dikalibrasi ke roster, bukan ke satu sampel

22 Agustus 2026, client saja. Dua laporan pemain sesudah normalisasi tinggi Home
menyala: "semua Anima jadi membesar" dan "seperti tidak ada beda tinggi".
Keduanya benar, dan sebabnya satu — **kalibrasi memakai satu sampel**.

`HOME_BODY_SPAN_RATIO` 0,27 dipas ke satu Rookie yang sheet-nya 517 px, dan
probe terhadap roster produksi menunjukkan sheet itu **yang terbesar di seluruh
roster**: sembilan Anima datang di 219–401 px, median 312. Ukuran gambar
terukur sesudah normalisasi versi pertama: Padronic +42%, VerdantPup +35%,
Veridian +45%, Drakabyss +76%, Drowake +81%; hanya satu Anima yang mengecil.
Sekarang 0,23, dipas ke median roster — Anima 90 cm (median tinggi badan)
kembali ke ~310 px, praktis sama dengan yang sudah dilihat pemain, sementara
yang tinggi tetap tumbuh.

Keluhan kedua nyata tetapi sebagian memang benar apa adanya: enam dari sembilan
Anima berada di 55–95 cm, jadi mereka *memang* setinggi itu. Yang bisa
diperbaiki adalah kompresinya. Kurva arena 0,42 memetakan rentang nyata
55–225 cm hanya ke 1,81x di layar. Home sekarang memakai
`HOME_BODY_HEIGHT_CURVE` 0,62 sendiri — 2,40x — karena arena selalu punya lawan
sebagai pembanding sementara lobby hanya menampilkan satu Anima. **Duel, Team,
dan Expedition sengaja tidak disentuh**, sesuai keputusan yang sudah disetujui.

Ukuran gambar sesudah perbaikan (px, art 1602): Padronic 227, Sunhound 275,
VerdantPup 293, klasik 308, Mugshots 308, Deckon 318, Veridian 423,
Drakabyss 510, Drowake 544.

Dua pagar baru di `test_scan_ui` mengunci keduanya per viewport: median tetap
~310 px dan rentang 55→225 cm di atas 2,2x. Diuji negatif — mengembalikan 0,27
dan 0,42 menjatuhkan tepat enam check itu, dan pesannya melaporkan 1,81x
terukur. Pemeriksaannya memakai probe headless sekali pakai yang memanggil
`stage_scale_for()` dengan roster asli; probe-nya dibuang setelah angkanya masuk
ke test.

Evolution History juga mendapat skeleton loading-nya. Section itu sebelumnya
diam sampai server menjawab, jadi pemain tidak tahu ia ada.

## Evolution History di Profile

22 Agustus 2026, `evolve_anima` 13→14. Profile mendapat section **Evolution
History** di antara Attributes dan Synthesis History: silsilah bentuk rata
tengah dengan panah di antaranya, dua kartu sesudah Evolve pertama dan tiga
sesudah yang kedua.

Datanya sudah ada seluruhnya, jadi tidak ada migration dan tidak ada kolom baru.
`anima_forms` menyimpan `stage`, `sheet_path`, dan `manifest` tiap bentuk lama,
tetapi client tidak bisa membacanya: RLS aktif dengan **nol policy** dan grant
hanya ke `postgres` + `service_role`. Karena itu jalurnya satu `operation:
"history"` read-only di `evolve_anima`, ditempatkan **sebelum** gerbang
idempotency — menuntut kunci untuk request yang tidak membelanjakan apa pun
hanya akan menolak pembacaan yang sah.

Nama bentuk lama sempat terlihat hilang: `anima_forms` tidak punya kolom nama,
`evolution_plan` bentuk pertama `null`, dan `animas.nickname` sudah berisi nama
terbaru. Ia ternyata utuh satu join jauhnya — `anima_forms.generation_id` →
`generations.vision_result.suggested_name`. Terukur pada Drowake: stage 1
menjawab `Hydron` (generation `create`), stage 2 `Drowake` (generation `evolve`
yang sukses). Bentuk sekarang memakai `nickname`, sebab itulah nama yang dikenal
pemain.

Thumbnail-nya nol panggilan model. `cropIdleThumb` yang sama dengan Atlas
memotong Idle dari sheet yang **sudah dibayar**, hasilnya disimpan sekali ke
`<uid>/<anima_id>/form_history/<stage>.png`, dan pembukaan Profile berikutnya
hanya menandatangani ulang objek itu. Client memakai cache thumb di disk yang
sudah dipakai Synthesis History; tidak ada cache kedua. Stage 1 tidak pernah
memanggil server sama sekali — ia belum punya bentuk sebelumnya.

Panelnya dibangun di kode, bukan di `.tscn`, karena jumlah kartunya memang
berubah dan lima belas scene sedang terbuka di editor saat itu; ia disisipkan
pada indeks `SynthesisHistoryPanel` supaya urutannya tetap benar walau salah satu
section disembunyikan. Panahnya `chevron-left.svg` yang sudah ada dengan
`flip_h`, jadi tidak ada aset baru. Berpindah Anima menghapus silsilah lama saat
itu juga, bukan menunggu jawaban server.

Pagar: `_test_evolution_history_section()` menambah 14 check di `test_scan_ui`
(1282→1296), termasuk urutan section, jumlah anak baris untuk dua dan tiga
bentuk, arah panah, dan urutan nama. Guard-nya diuji negatif — menghapus
`move_child` menjatuhkan tepat check urutan itu. `test_i18n` 4749→4765 dengan
`EVOLUTION_HISTORY_TITLE`. `npm run selftest` tetap lulus; smoke `evolve_anima`
menjawab 401, jadi modulnya mengimpor bersih.

## "stubby legs" — validator menolak jawaban benar

22 Agustus 2026, `evolve_anima` 12→13. Dua ritual Hydron berikutnya (12:52 dan
12:53 UTC) mati lagi sebelum satu gambar pun dibuat, dan pembongkarannya memberi
dua temuan terpisah.

Temuan pertama: **resample versi 12 tidak me-resample apa pun.** Enam prediction
Gemini diambil ulang dari Replicate dan divalidasi lokal terhadap opsi produksi
yang direkonstruksi. Ketiga sampel run 12:53 berbeda **satu kata dari 12.105
karakter** (`derived from a bottle` → `derived from a vessel`); run 12:52 malah
menghasilkan tiga plan identik. Sebabnya suhu retry yang diturunkan ke 0,15
digabung dengan JSON plan lama plus perintah "preserve every already-valid value
exactly" — dekoding jadi nyaris greedy dan model membacakan ulang mode yang sama.
Tiga panggilan Vision, nol informasi baru. Suhu sekarang **naik**
0,35→0,60→0,85; korekinya tetap, karena ia terbukti berguna saat model mengerti
keluhannya: satu attempt melunasi `silhouette_break_contract` sendiri dengan
mengganti satu kata.

Temuan kedua, yang sebenarnya membunuh kedua ritual: **validator menolak jawaban
yang benar.** `primary_shapes v25 harus punya source, expression, dan visual_role
sah` muncul di **enam dari enam** sampel, dan penyebabnya tunggal —
`source_basis` `"stubby legs"` panjangnya 11 karakter sementara lantainya 12.
Field itu menamai struktur yang terlihat, ia tidak menjelaskannya, jadi jawaban
benarnya memang pendek; `source_detail` di fungsi yang sama sudah memakai lantai
4 sejak awal. Lantai `source_basis` dan `dominant_motif.source_basis` disamakan
ke `MIN_SOURCE_PHRASE` 4.

Dua kontrak lain berhenti menjatuhkan Plan karena hal yang jawabannya sudah
ditentukan server. Entri `derived_anatomy` yang tidak menelusuri anchor-nya
dibuang alih-alih membatalkan seluruh desain — prompt v41 menyatakan array itu
boleh kosong dan `assembleEvolvePrompt` sudah punya kalimat pengganti untuk
keadaan itu; pada Hydron dua dari tiga entri sah dan yang ketiga menunjuk sebuah
Identity Invariant. Dan `realization_mode` di Adult ditegakkan ke `preserve`,
satu-satunya nilai sah di stage itu dan sudah tertulis di prompt sebagai "always
preserve for Adult"; `evolved_policy` tidak disentuh karena ia menyimpan apa yang
boleh terjadi di stage berikutnya.

Verifikasi terhadap keenam plan produksi yang ditolak: empat lolos setelah
perbaikan, termasuk **attempt terakhir dari kedua ritual**, jadi keduanya akan
sampai ke image generation. Dua sisanya gagal pada `kind_noun` — persis error
yang resample terbukti bisa perbaiki sendiri. Pagarnya di `npm run selftest`
scenario 36: `"stubby legs"` wajib diterima, `"rim"` (3 karakter) wajib tetap
ditolak, entri `derived_anatomy` tanpa anchor wajib dibuang tanpa melempar, dan
Adult wajib menegakkan `preserve` tanpa menulis ulang `evolved_policy`.
Mengembalikan lantai ke 12 membuat selftest gagal dengan pesan produksi yang
sama persis. 42 skenario + 12 signature check lulus; smoke `evolve_anima` 401.

## E005 satu redraw, Plan membawa koreksi lama, Home bicara Evolution

22 Agustus 2026, `evolve_anima` 11→12 dan `replicate_webhook` 14→15. Attempt
Hydron pukul 12:05 UTC lolos Vision pada sampel kedua lalu GPT Image berhenti
47,08 detik kemudian dengan `The input or output was flagged as sensitive
(E005)`. Output kosong. Log sebelum generation mencatat `NSFW check failed for
image 0: Unable to infer channel dimension format`; reference privatnya sendiri
valid PNG 486×535, tetapi opak RGBA 4-channel. `buildEvolutionIdleReference()`
sekarang mengodekannya sebagai PNG RGB color type 2. Exact E005 masih diberi
satu redraw dengan allowlist + family-safe suffix, memakai Plan tersimpan dan
tanpa mengulang Gemini. Batas dua attempt total dijaga kolom
`generations.image_attempts` dan RPC service-role-only
`replace_evolution_prediction`; callback paralel yang kalah membatalkan
prediction yatim. Error lain tidak masuk jalur ini. Dokumentasi billing
Replicate saat deploy menyatakan official prediction berstatus `failed` tidak
ditagih.

Attempt berikutnya pukul 12:09 membuktikan pagar Plan versi 11 berjalan tetapi
konteks koreksinya kurang: tiga Gemini selesai, lalu validator menolak. Attempt
pertama salah anchor `derived_anatomy`; kedua memperbaikinya tetapi lupa
`kind_noun`; ketiga memperbaiki kind lalu meregresi invariant Adult ke
`transfigure` dan merusak anchor lagi. Sebabnya correction hanya membawa pesan
error sambil menyuruh “keep every other rule”, tetapi tidak membawa JSON yang
harus dipertahankan. Versi 12 menempelkan JSON plan yang ditolak sebagai data,
menurunkan suhu retry 0,35→0,15, dan meminta field valid dipertahankan persis.
Validator tidak dilonggarkan.

Migration `20260822121730_evolution_image_retry` di-push setelah dry-run tunggal,
`quota_rules.sql` lulus di production, dan probe hak menunjukkan `anon=false`,
`authenticated=false`, `service_role=true`, serta nol row di atas limit.
`npm run selftest` lulus 42 skenario + 12 signature check. Smoke deploy:
`evolve_anima` 401 dengan `verify_jwt=true`; `replicate_webhook` 401 untuk
signature palsu dengan `verify_jwt=false`.

Client source juga menutup bug terpisah. **Begin Evolution** sekarang langsung
ke Home, termasuk untuk Anima bench. Home memakai state `evolving` dengan nama
Anima dan copy Evolution Chamber; sebelumnya chamber memanggil state `ready`
yang jatuh ke fallback `HOME_LOADING_*`, sehingga menampilkan “Preparing your
habitat / Connecting your account…” di tengah ritual. Cold resume mencari
Anima evolving di seluruh roster. Verifikasi: `test_scan_ui` 1269 dan
`test_i18n` 4759; screenshot 720×1280 menunjukkan chamber, nama, dan copy baru
tanpa boot loading. APK debug 54,7 MB diverifikasi hanya memuat izin INTERNET +
CAMERA, plugin kamera ada di DEX, signature v2 sah, lalu terpasang ke perangkat
uji pukul 19:48 dan cold launch bertahan tanpa crash.

## Plan Evolve disampel ulang, bukan dijatuhkan (backend)

22 Agustus 2026, `evolve_anima` 10→11. Evolve Hydron gagal untuk ketiga kalinya,
kali ini **sebelum** satu dolar pun keluar: `dispatch_started_at` null dan Vision
mengembalikan JSON lengkap 14.277 karakter, tetapi validator menolak isinya
karena empat kontrak dilanggar sekaligus — satu Identity Invariant memakai
`transfigure` padahal stage Adult mewajibkan `preserve`, `kind_noun` "vessel"
tidak diulang di `source_kind_read`, kategori subjek lari ke bentuk serpentine,
dan `derived_anatomy` menautkan kaki berkuku ke anchor "ribbed side panels".
Validator benar di keempatnya; model memang mencoba mengubah botol jadi ular.

Yang salah bukan gerbangnya melainkan ketiadaan percobaan kedua. Prediksi Vision
pukul 11:04 pada Anima yang sama, dengan pagar thinking dan plafon token yang
identik, menghasilkan plan yang lolos utuh — jadi ini variansi model, bukan
regresi. Sampai versi 10 satu sampel menentukan nasib seluruh ritual.

Sejak versi 11 plan yang ditolak disampel ulang sampai tiga kali dengan pesan
validator ditempelkan ke prompt sebagai instruksi perbaikan. Batasnya waktu,
bukan uang: plan $0,003 versus gambar ~$0,05, sementara client menyerah pada 90
detik dan satu siklus terukur 26 detik, jadi percobaan baru hanya dimulai di
bawah 50 detik. Sampel tambahan ikut dihitung ke spend cap. Aturan berhentinya
hidup sebagai `evolutionPlanResampleAllowed()` di `_shared/evolution.mjs` supaya
bisa diuji; pagarnya `npm run selftest`, dan diverifikasi merah saat predikatnya
dimatikan.

## Sheet berbayar diselamatkan, bukan dibuang (backend)

22 Agustus 2026. Dua kegagalan Evolve berturut-turut memperlihatkan masalah yang
lebih besar daripada kedua bug-nya sendiri: biaya generation terkunci saat
Replicate menjawab, sementara seluruh gerbang kita berjalan sesudahnya, jadi
setiap penolakan post-processing menghapus aset yang sudah dibayar lalu menagih
satu generation lagi. Terukur di `generations`: $0,073 hangus dari $0,639 total
belanja, 1 dari 9 generation berbayar.

Dua perubahan, keduanya di jalur yang sudah ada. Pertama, dari lima `throw` di
`postprocess.mjs` hanya tiga yang benar-benar tidak bisa diselamatkan — semuanya
soal keying gagal. Dua sisanya kosmetik, dan `clearAlphaComponent()` sudah
dipakai untuk salah satunya pada capture v31+. `shouldRemoveIdleSeamLeaks()`
karena itu menjadi `shouldRepairDetachedArtifacts()`, pengecualian `kind !==
"evolve"` dicabut, dan gerbang `detached character components` mendapat jalur
perbaikan yang sama. Hasilnya dicatat sebagai `manifest.qa.detached_cleanup`,
bukan disembunyikan. Pagarnya all-or-nothing terhadap `maxRepairableFragmentRatio`
0,05: satu fragmen di atas 5% badan pose berarti segmentasi rusak, dan setengah
monster yang terkirim diam-diam lebih mahal daripada gagal keras. Versi prompt
lama tetap ketat, dan `eval/run.mjs` tetap tempat menghakimi art.

Kedua, `replicate_webhook` 13→14 menyimpan raw PNG ke
`anima_sheets/failed_raw/<generation_id>.png` pada kegagalan terminal, sehingga
perbaikan pipeline berikutnya bisa diproses ulang dengan nol panggilan API.
Sebelumnya byte-nya diunduh ke memori lalu dibuang bersama kegagalan. Kegagalan
transient sengaja tidak disimpan karena Replicate mengirim ulang gambarnya.

Diverifikasi pada byte sheet Adult Hydron yang sungguhan: dengan bug keyline
sengaja dikembalikan, sheet yang sebelumnya hangus tetap lolos 9/9 sel dengan 2
fragmen/36px dibuang dan tercatat. Pagarnya skenario 24 `npm run selftest`, yang
juga menuntut fragmen di atas plafon tetap ditolak.

## Keyline stripper dibatasi ke prompt pra-v11 (backend)

22 Agustus 2026. Sesudah pagar thinking dipasang, Evolve Hydron berjalan sampai
gambar jadi lalu gagal di post-processing dengan `sheet v26 punya detached
character components: sleep:19px, sleep:17px`. Sebabnya bukan model dan bukan
audit: `stripWhiteKeylineInPlace()` mengupas putih yang menyentuh transparansi
sampai bertemu dark line art, jadi ia benar pada matte berbentuk cincin tetapi
melahap habis bentuk putih yang berdiri sendiri. Yang berdiri sendiri itu art
yang diminta prompt — v41 baris 350 meminta Z tidur, baris 426 justru melarang
keyline putih.

Direproduksi lokal pada byte sheet yang sama, nol panggilan API: tanpa stripper
`sleep` punya 3 komponen (badan 30.114px + Z 218px + Z 146px) dan audit lolos;
dengan stripper Z pecah menjadi 8 remah (57, 22, 19, 17, 9, 7, 4px) sehingga
empat melewati `minDetachedCharacterPixels` 16 dan dua terakhir menjadi
violation — angka yang sama persis dengan produksi. Dari 1.076px yang dikupas,
727px adalah semprotan air `fx_strike` dan 238px Z tidur; sisanya remah
anti-alias 6–31px. Model tidak menggambar keyline sama sekali, jadi seluruhnya
kerusakan sampingan.

`shouldStripWhiteKeyline()` sekarang membatasi stripper ke `promptMajor < 11`,
batas tempat prompt berhenti meminta keyline 3–5px; sheet tanpa `promptVersion`
tetap dianggap lama dan tetap dikupas, jadi jalur migrasi dan selftest lama tidak
berubah. Mematikannya tidak menukar apa pun: residu hijau 0,00365 menjadi
0,00364 dan tinggi bbox kesembilan pose identik. `replicate_webhook` 13 di-deploy
dan smoke tanpa tanda tangan menjawab 401. Skenario 24 `npm run selftest`
menuntut `white_keyline_pixels_stripped === 0` pada v41 dan `> 0` pada v10;
diverifikasi merah saat perbaikannya dikembalikan. Tidak ada migration dan tidak
ada perubahan prompt version. `reprocess_species_art` sempat ikut ter-deploy
sebagai v1 dan langsung dihapus lagi — ia alat migrasi sekali pakai yang memang
tidak boleh hidup di produksi.

## Pagar thinking Vision (backend)

22 Agustus 2026. Evolve stage 2 milik Hydron gagal dengan Plan terpotong di
tengah `lineage_anchors`, sementara prediksi Replicate-nya tercatat `succeeded`
dan `error` null. Sebabnya `thinking_budget: 0`: wrapper Gemini di Replicate
memeriksanya sebagai nilai falsy dan membuangnya, jadi thinking berjalan dinamis
dan menghabiskan `max_output_tokens` yang seharusnya menampung JSON. Diukur pada
prompt yang sama (input 9.248 token, plafon 4.096) — budget 0 menyisakan 162
token teks, budget dihilangkan 249, budget 1 menyisakan 2.572, budget 128
menyisakan 3.230; dua yang terakhir JSON lengkap 28 key. Tiga run pada setelan
produksi baru menghasilkan 2.550 / 2.757 / 2.673 token, semuanya utuh.

Radiusnya bukan hanya Evolve: `generations` menyimpan tiga kegagalan Synthesis
bertanda `Vision tidak mengembalikan JSON yang bisa diparse`, tanda tangan
potongan yang sama, jadi batas prose v43 dan penutup fence v45 sebelumnya
mengobati gejala dari ujung yang salah. Capture lolos 6 dari 6 karena prompt-nya
lebih pendek, dan moderasi Gallery berplafon 512 token belum kena hanya karena
baru sekali dipakai.

Perbaikannya satu konstanta `VISION_THINKING` di `_shared/vision.mjs` yang
di-spread keenam call site, plus plafon Evolve naik ke 8.192. `create_anima` 25,
`evolve_anima` 10, `synthesize_anima` 6, dan `gallery` 19 di-deploy; smoke tanpa
JWT menjawab 401 pada keempatnya. Skenario 42 `npm run selftest` gagal kalau
angka 0 kembali. Tidak ada migration dan tidak ada perubahan prompt version.
Client mendapat dialog **Evolution Failed** dengan tombol Retry menggantikan
toast; itu menunggu APK.

## Synthesis History source names (backend)

22 Agustus 2026. Snapshot History mencari `generations.suggested_name` lalu
jatuh ke literal `Anima` kalau baris generation tidak ada. Playtron di kartu
Gearbit Racer kena itu. Migration
`20260822085800_synthesis_history_source_names` menulis ulang nama Source dari
nickname, memperbaiki History yang sudah tersimpan, dan mengisi snapshot baru
lewat trigger. Kartu Profile menyembunyikan catatan inheritance di belakang
tombol bantuan Resonance; APK lama tetap melihat teks penuh sampai build baru.

## Synthesis JSON close v45 (backend)

22 Agustus 2026. `extractJson()` sekarang menutup pagar markdown yang tidak
selesai dan JSON yang terpotong di tengah string — recovery yang sama untuk
Scan dan Synthesis. Planner v45 menulis `name_roots` terakhir supaya field
wajib Plan tidak ikut hilang. Migration
`20260822074932_synthesis_json_close_v45` di-push sesudah `create_anima` 24,
`synthesize_anima` 5, dan `evolve_anima` 9. Rollback `v44`.

## Synthesis Name Lineage v44 (backend)

22 Agustus 2026. Planner Synthesis tidak lagi menulis nama akhir; ia mengirim
`name_roots` dan server merakit kata spesies lewat `deriveMorphemeSpeciesName()`,
sama dengan Scan v41. `synthesize_anima` 4 dan `evolve_anima` 8 di-deploy
dulu (bundle sudah memuat v44), lalu migration
`20260822073538_synthesis_name_lineage_v44` di-push. Production sekarang
`synthesis_prompt_version = v44`; rollback-nya `v43`. Evolve membaca
generation `kind=synthesis` sebagai birth lineage. Smoke tanpa JWT menjawab
401. Result yang sudah menetas (Gearbit Racer, VerdantPup) tidak di-rename.
Sheet tetap v42.

## Status deploy Guided Synthesis (backend production, flag hidup, APK pending)

Rollout 22 Agustus 2026. Migration `20260821121417_anima_synthesis` di-apply
lewat `supabase db push --linked --workdir backend`, jadi versi yang tercatat
remote sama dengan nama file lokal dan `migration list` tidak melihat drift —
berbeda dari empat migrasi pertama yang lewat MCP dan harus di-rename manual.
Terukur sesudahnya di production: dua tabel baru (`anima_synthesis_slots`,
`anima_synthesis_attempts`), tujuh fungsi Synthesis, dan 14 kunci `app_config`
dengan `feature_synthesis` = `false` sesuai seed migration.

Edge Function di-deploy satu batch: `synthesize_anima` version 1 (baru),
`gallery` 18, `replicate_webhook` 12, `seeker` 6, plus `create_anima` 23 dan
`evolve_anima` 7 yang ikut karena keduanya memuat `prompts.generated.ts` yang
sekarang membawa v42. Semua `verify_jwt=true` kecuali webhook.

Smoke test: kelima fungsi ber-JWT menjawab 401 tanpa header, dan webhook
menolak tanda tangan palsu. Karena `verify_jwt=true` menolak di gateway sebelum
modul diimpor, 401 saja **tidak** membuktikan impor berhasil; pemanggilan ulang
dengan publishable key menembus gateway dan berhenti di 426 `CLIENT_OUTDATED`,
yang berarti `prompts.generated.ts` dan `synthesis.mjs` benar-benar termuat.

Blok uji Synthesis dari `backend/tests/quota_rules.sql` dijalankan terhadap
production lewat MCP `execute_sql` dan lulus: Resonance gagal tidak membayar,
claim sukses atomik, refund Core+Bits tepat sekali, sapuan pending basi,
mode lock, Source lock, dan RPC tetap service-role-only. Sesudahnya database
bersih — nol slot, nol attempt, nol generation `kind='synthesis'`, user uji
terhapus, dan `synthesis_resonance_base` kembali ke 40.

Probe end-to-end sesudah flag hidup, nol biaya: satu guest anonim sekali pakai
dibuat lewat `auth/v1/signup`, lalu `synthesize_anima` dipanggil dengan JWT-nya
plus header `x-scanima-platform: android` dan `x-scanima-build: 1`. `preview`
dengan Source palsu menjawab 409 `ANIMA_NOT_FOUND` — artinya JWT, routing
operation, validasi payload, RPC, dan pemetaan error benar-benar terhubung, bukan
cuma modulnya termuat. Guest-nya dihapus lagi dan cascade-nya bersih sampai
`profiles`. Terukur juga: `operation` yang tidak dikenal ditolak 400 sebelum
menyentuh `attempt`, jadi salah tulis operation tidak bisa mendebit apa pun —
pesan 400 yang muncul lebih dulu hanyalah validasi Source, yang berjalan sebelum
whitelist operation.

`feature_synthesis` dinyalakan ke `true` sesudah smoke test itu, atas keputusan
eksplisit dan lebih awal dari pagar "tunggu APK" yang tercatat sebelumnya.
Konsekuensinya: jalur 1 Core + 250 Bits sudah terbuka di server sekarang, tetapi
belum ada APK terdistribusi yang punya layar Synthesis Lab, jadi praktis hanya
build dari source yang bisa memanggilnya. Rollback-nya satu baris —
`update public.app_config set value = 'false'::jsonb where key = 'feature_synthesis'`
— dan `attempt_synthesis` maupun `preview_synthesis` langsung menolak dengan
`FEATURE_DISABLED` tanpa menyentuh saldo.

## Hardening Guided Synthesis v43 (backend production, client APK pending)

Follow-up 22 Agustus 2026 berangkat dari lima attempt production: dua output
Planner bukan JSON lengkap, dua plan valid melewati batas 180 karakter pada
`inheritance_summary.coherence`, dan satu benar-benar gagal Resonance. Empat
kegagalan teknis ter-refund penuh (net 0 Core, net 0 Bits) dan tidak memicu
image generation; Resonance miss juga tidak mendebit mata uang.

`synthesize_anima` version 2 di-deploy lebih dulu dengan bundle v42 + v43, lalu
migration `20260821230502_synthesis_committed_form_only` dan
`20260822001202_synthesis_prompt_v43` di-push. Urutan itu mencegah
`app_config` menunjuk prompt yang belum tersedia. Production sekarang
`synthesis_prompt_version = v43`, `feature_synthesis = true`, dan historical
form ditolak oleh wrapper RPC yang mengunci row Source.

V43 memberi schema maxLength/maxItems dan enum candidate eksplisit; Function
memakai temperature 0,35, output budget 4.096 token, serta clipping prose valid
di trust boundary. Prompt sheet berbayar tetap v42. Smoke tanpa JWT menjawab
401, kedua migration tercatat remote, dan `quota_rules.sql` selesai exit 0
terhadap production sesudah rollout. Tidak ada panggilan model berbayar yang
dibuat untuk verifikasi rollout ini.

Client source pada rollout yang sama mengganti terminal toast dengan dialog:
Resonance miss menjelaskan cooldown/Calibration, kegagalan teknis menegaskan
refund, dan success menampilkan portrait Result dengan reveal animation serta
**View Result**. APK terpasang belum membawa perubahan presentation itu.

## Status deploy Anima Atlas (backend production, APK pending)

Gallery Feed sudah diganti di source dengan **Anima Atlas**: registry
`atlas_forms`, ledger `seeker_atlas_discoveries`, hook authoritative untuk
owned form/Duel/Expedition, cleanup unpublish/delete/report, dan backfill valid.
Edge Function tetap memakai slug `/gallery` untuk kompatibilitas transport,
tetapi client Atlas memakai operation versioned `atlas_list`/`atlas_detail`;
`publish`, `unpublish`, `report`, dan `my_status` tetap shared. Operation lama
`list`/`hide` dipertahankan hanya agar APK Gallery yang sudah terpasang tidak
rusak selama rollout; `hide` juga membersihkan discovery pemiliknya. Migration
`20260818162758_anima_atlas` + `20260818163916_index_anima_atlas_foreign_keys`
+ `20260818194445_atlas_expedition_seeker_name` +
`20260818194755_defer_atlas_registration_until_art` tercatat production dan
`gallery` version 17 ACTIVE dengan `verify_jwt=true`. Migration terakhir
membuat trigger Atlas menunggu `sheet_path` + `manifest`, sehingga RPC rollback
legacy `record_cache_hit` tetap bisa membuat Anima ready tanpa art privat.
Jalur list tidak lagi memverifikasi JWT dua kali: gateway memvalidasi signature,
lalu function hanya membaca `sub` UUID dari payload yang sudah terverifikasi.
Query independen berangkat paralel, URL Storage ditandatangani per batch, dan
filter All/Scanned/Expedition/Duel diproyeksikan lokal dari page All lengkap.
Smoke production 19 Agustus mengukur first load 1,508 detik dan warm
0,931–0,990 detik (sebelumnya sekitar 4–7 detik); perpindahan filter sesudahnya
tidak memakai request jaringan. Deploy wajib dari source lewat Supabase CLI agar
dynamic import modul image/moderation tetap malas—bundel MCP tunggal menarik
`imagescript` saat boot, sedangkan split bundle pernah membuat worker crash.
Backfill production menghasilkan 8 form pemain, 9 form Expedition, serta
discovery 8 Scanned / 1 Duel / 9 Expedition; RLS, revoke helper internal, dan
covering index cleanup terverifikasi. Smoke tanpa JWT menjawab 401, client baru
`atlas_list` menjawab 200 dengan 9 siluet chapter untuk akun baru, dan operation
legacy `list` tetap menjawab 200 dengan satu publication; kedua akun smoke sudah
dihapus. Uji transaksi production untuk backfill, siluet chapter, serta cleanup
unpublish/report/delete lulus dan rollback kembali ke 17 form / 18 discovery /
1 publication. Backend rollout selesai; APK baru masih perlu
dibangun/didistribusikan agar pemain melihat Menu dan Atlas.
Follow-up `20260818194445_atlas_expedition_seeker_name` menyalin
`boss_seeker.display_name` hanya ke form Expedition yang `special`, lalu
`gallery` memproyeksikannya sebagai `owner_name`; jadi Nimbelisk mendapat
The Confectioner tanpa hardcode client. Migration/backfill dan source `gallery`
ini sudah production 19 Agustus: Cotton terukur membawa The Confectioner,
Gumdrop tetap null, helper internal hanya executable oleh `service_role`, dan
smoke tanpa JWT tetap menjawab 401. `quota_rules.sql` lengkap lulus terhadap
production sesudah guard art trigger ditambahkan.

Client kandidat memakai bottom nav Home/Scan/Battle/Collection/**Menu**. Menu
adalah launcher popover untuk Seeker Profile, Anima Atlas, dan Settings;
Anima Profile hanya dari Collection/Battle picker, dan burger Top HUD dihapus.
Collection dan Atlas juga memakai pasangan tab **Collection / Atlas** 96px;
Menu Atlas menjadi deep link ke destination yang sama, bukan implementasi kedua.
Atlas memakai satu grid All/Scanned/Expedition/Duel, form terpisah, siluet
Expedition, profil statis, serta consent publish satu lineage. Detail profil
memakai hero ringkas lalu kartu Traits/Attributes/Discovery; lima stat tetap
satu baris, Attack/Special menjadi nilai terpisah, dan Report adalah aksi teks
sekunder touch-safe. Grid mobile memakai tiga kolom ringkas yang hanya membawa
nama + elemen; stage tinggal di detail. Portrait detail memakai napas Idle,
`owner_name = null` menghilangkan sel Seeker alih-alih menulis `<null>`, dan
chevron header dipusatkan vertikal. Tap form memberi shimmer lokal pada portrait
selama `atlas_detail` dimuat. Back sistem/gesture menutup
detail lebih dulu, lalu fallback shell menutup `UiBottomSheet` visible terakhir
agar semua bottom sheet mengikuti kontrak yang sama. Seluruh
preference, setting, cabang, dan referensi runtime **Reduced Motion** sudah
dihapus; timing animasi normal adalah satu-satunya jalur. Detail desain ada di
[`docs/designs/2026-08-18-anima-atlas.md`](docs/designs/2026-08-18-anima-atlas.md)
dan panduan pemain di [`docs/wiki/atlas.md`](docs/wiki/atlas.md).

## Status deploy Name Lineage v41 (player-live, 19 Agustus 2026)

`app_config.prompt_version = "v41"` dan `evolution_prompt_version = "v41"` lewat
migration `20260819120015_prompt_version_v41.sql`; `create_anima`, `evolve_anima`,
dan `replicate_webhook` sudah dideploy dari source dan smoke tanpa JWT/signature
menjawab 401. Flip ini **nol risiko art**: keempat prompt gambar byte-identik
dengan versi yang digantikan (capture sprite v31, evolve sprite v30, diverifikasi
shasum), jadi yang berubah hanya nama. Nol baris `generations` lahir di jendela
antara flip config dan deploy. Rollback: `prompt_version` kembali `"v31"` dan
`evolution_prompt_version` kembali `"v30"` — keduanya tetap di bundel.

## Status deploy gerbang Rename + dedup nama (19 Agustus 2026)

Migration `20260819132458_anima_name_gate` **sudah tercatat production** dan
diterapkan lewat Supabase MCP, jadi nama filenya sengaja disamakan dengan versi
remote supaya `supabase migration list` tidak melihat drift. Probe production
membuktikan trigger `animas_validate_nickname` menyala `BEFORE UPDATE ... WHEN
(new.nickname is distinct from old.nickname)`, nama wajar lolos, spasi tepi
dipangkas, `Kontol`/`Admin Bot` ditolak `ANIMA_NAME_RESERVED`, non-ASCII dan
nama tanpa huruf ditolak `INVALID_ANIMA_NAME`, INSERT capture tetap lewat, dan
ketiga perilaku `_validated_seeker_name` tidak berubah sesudah daftar
terlarangnya dipindah ke `_name_is_reserved`. Kedelapan nickname production yang
ada sekarang lolos validator baru, jadi tidak ada pemain yang namanya mendadak
tidak bisa disimpan ulang. Baris uji dibersihkan.

Trigger ini menyala **lebih dulu** daripada CHECK `animas_nickname_length`, dan
`quota_rules.sql` yang lengkap adalah yang menangkapnya: uji lama menuntut
nickname spasi-saja ditolak sebagai `check_violation`, sedangkan sekarang ia
ditolak `INVALID_ANIMA_NAME`. Invariannya tidak berubah — kosong tetap ditolak di
trust boundary — tetapi kodenya kini bisa dipetakan client, jadi uji itu
menuntut kode barunya dan CHECK tinggal sebagai pagar kedua untuk INSERT.
Seluruh suite lulus terhadap production sesudah perubahan itu.

Dedup nama per pemilik juga sudah live: `create_anima` version 22 dan
`evolve_anima` version 6 ACTIVE dengan `verify_jwt=true`, dideploy dari source
lewat CLI. Smoke tanpa JWT menjawab 401, tetapi 401 itu datang dari gateway
**sebelum** worker boot, jadi ia tidak membuktikan modulnya terimpor; smoke
kedua memakai publishable key sampai keduanya menjawab `CLIENT_OUTDATED` 426 —
itu jawaban aplikasi sesudah import dan sesudah `app_config` dibaca, jadi
bundel 2,9 MB `prompts.generated.ts` benar-benar dimuat. Nol baris `generations`
lahir di jendela deploy.

`SUPABASE_ACCESS_TOKEN` yang di-export `.zshrc` mesin ini milik org
`PT Global Tiket Network`, bukan `rekansebangku`, jadi CLI menolak project
Scanima sampai token yang benar diberikan per-perintah. MCP bukan jalan keluar
untuk kedua fungsi ini: `prompts.generated.ts` sendiri 2,9 MB.

Sisa yang belum sampai ke pemain adalah **APK baru**. Trigger sudah menolak nama
di server, tetapi build lama tidak punya preflight maupun peta error, jadi ia
menampilkan `ANIMA_RENAME_ERROR` generik alih-alih copy yang menjelaskan
aturannya.

## Status deploy Capture Vibe v31 (art baseline, 18 Agustus 2026)

Vibe adalah kontrak art yang **masih berlaku** di v41; hanya nomor versinya yang
maju. `app_config.prompt_version` sudah `"v41"`, dan v31 tetap rollback capture.
Scan optional **Vibe** (Natural / Cute / Brave / Wild / Sinister) adalah art-only:
Vision, stats, elemen, tinggi, Core, dan gate IP tidak berubah. Default Natural
setiap Scan baru; slug tersimpan di `generations.capture_vibe`, bukan `animas`.
Client lama yang tidak mengirim field tetap Natural. Non-Natural pada prompt < v31
masih `VIBE_UNAVAILABLE`; slug di luar allowlist `INVALID_VIBE`. Replay claim
memakai vibe baris pertama.

- Migrasi `20260817205256_capture_vibe` + `20260817205349_prompt_version_v31`.
- Edge Function `create_anima` version 20 ACTIVE (`verify_jwt=true`) dan
  `replicate_webhook` version 10 ACTIVE. Smoke tanpa JWT/signature menjawab 401.
- Capture v31 membuang bocoran Idle deterministik; audit tubuh terlepas hanya
  untuk evolusi. Eval Monstera Cute/Brave/Sinister lulus visual operator lalu
  `--reprocess` 9/9 tanpa panggilan model. `quota_rules.sql` lulus terhadap
  production sesudah flip.
- Rollback capture: `app_config.prompt_version` kembali `"v20"` (Natural only).
  Chip Vibe butuh APK baru; build lama Scan sebagai Natural.

## Status deploy gate IP 17 Agustus 2026

Gate karakter franchise sudah live. `create_anima` version 19 dan `gallery`
version 2 ACTIVE dengan `verify_jwt=true`; smoke tanpa JWT keduanya menjawab 401.
`app_config.prompt_version = "v20"`. V20 menerima ilustrasi non-manusia
orisinal/generik, menolak karakter franchise yang dapat disebut namanya sebelum
Core dan image generation dipakai, serta memakai tiga prompt sprite yang identik
byte-for-byte dengan v19. Gallery memakai pagar yang sama saat publish; cache
moderasi lama sengaja tidak dipindai ulang. Probe source production memastikan
bundel v20 memuat `known_character` dan Gallery memuat aturan franchise.
Eval Vision-only menolak fixture karakter franchise, menerima naga
public-domain sebagai Fauna, dan memakai nol image generation; fixture dinding
kosong tetap salah dibaca sebagai panel beton pada v19 maupun v20.

## Status deploy Evolution art (player-live, 18 Agustus 2026)

**`feature_evolution=true`**, `evolution_prompt_version = "v41"` (v30 rollback),
default `evolution_version=1` (backfill row lama). Capture `prompt_version = "v41"`
(rollback v31, lalu v20).
Ritual Evolve gratis; sheet terkunci di `anima_evolution_locks` melewati Replicate.
Plan v30 mengusulkan `suggested_name`; `commit_evolution` tidak menimpa `nickname`.
Sesudah sukses, client membuka Rename terisi nama itu; Cancel mempertahankan nama lama.

- Migrasi `20260817095700_evolution_art_pipeline` + `20260817200110_evolution_go_live` + `20260817201340_evolution_name_lineage_v30`.
- Edge Function `evolve_anima`: Vision Plan (~$0.003) + satu generation (~$0.07)
  **tanpa Core**, atau commit lock 0 USD. Kegagalan memanggil `fail_evolution`.
- **`RULES_VERSION = 3`**: committed form ×1.06/×1.18 + move effects saat
  `evolution_version>=1`. Snapshot `evolution_version=0` tetap growth legacy.

- Migrasi `20260817095700_evolution_art_pipeline`: `animas.status` + `evolving`,
  `evolution_version`, `strike_effect_id`/`surge_effect_id`, `generations.target_stage`,
  tabel internal `anima_forms`, RPC `begin/reserve/commit/fail_evolution` (service-role only).
- Edge Function `evolve_anima` + cabang `replicate_webhook`/`finalize_sheet` untuk
  `kind=evolve`: Vision Plan (~$0.003) + satu generation (~$0.07), **tanpa Core**;
  kegagalan memanggil `fail_evolution` saja (bukan `refund_generation`).
- Input model evolusi adalah crop Idle privat di atas chroma green, bukan seluruh
  sheet. Reference disimpan di `anima_sheets`, ditandatangani singkat, ikut
  history form saat sukses, dan masuk cleanup queue saat fail/timeout/delete.
- Prompt v21: file capture byte-identik v20 + `vision_evolve_*` + `sprite_sheet_evolve` Adult/Evolved.
- Validasi Plan di `_shared/evolution.mjs`; katalog efek + combat v3 di `_shared/move_effects.mjs` (refactor evolution import); selftest skenario 36–38.
- **`RULES_VERSION = 3`** + port GDScript (`move_effects.gd`) sudah live.

Paid eval pertama v21 pada Veridian/Monstera lulus teknis 9/9 sel dan seam,
tetapi **ditolak secara art direction**: pot, wajah tengah, dan massa daun radial
tetap membentuk siluet yang sama; output hanya menambah daun, akar, dan retak.
Desain pengganti v22 sudah diterima di
[`docs/13-evolution-silhouette-design.md`](docs/13-evolution-silhouette-design.md):
setiap stage wajib body plan/siluet baru, minimal dua transformed anchors,
Silhouette Delta Contract, dan archetype kecil. V22 sudah diimplementasikan di
repo tetapi belum di-deploy/dipromosikan; production tetap v21 dengan feature
flag off. Paid eval Adult v22 (`rooted_to_mobile`) lulus teknis 9/9 sel + seam,
mengubah aspect siluet 0,838→1,445 dan terbaca sebagai leaf-carapace crawler di
Godot; operator menyetujuinya. Evolved pertama (`unfolding`) juga distinct
(Adult→Evolved IoU 0,361), 9/9 sel, dan seam lulus, tetapi **technical reject**
dan **identity reject**: luminous green pada core/VFX menghasilkan residue 4,42%
serta 3,2287% cincin alpha bright-chroma, sementara dua mata ekspresif
Hatchling/Adult berubah menjadi satu aperture tanpa character read. Tidak ada
retry berbayar otomatis. Desain v23 sudah disetujui di
[`docs/designs/2026-08-17-evolution-identity-invariants-v23.md`](docs/designs/2026-08-17-evolution-identity-invariants-v23.md):
Vision memilih 2–4 Identity Invariants dari Hatchling, menguncinya di Adult
Plan, dan Evolved hanya boleh mentransfigurasi maksimal satu dengan turunan
visual jelas. V23 sudah diimplementasikan dan v22 dipulihkan untuk provenance.
Paid eval Evolved v23 lulus silhouette + soul (dua mata, senyum, dan daun
fenestrasi bertahan), 9/9 sel, serta seam, tetapi **maturity/apex reject** dan
**technical reject**: core kecil, tendril tipis, serta wajah muda belum terasa
sebagai payoff Lv36; Attack/VFX masih memiliki 643/41.433 alpha-edge
bright-chroma (1,5519%). Vision Plan sendiri meminta `shimmering green toxin`,
jadi larangan template saja tidak cukup. Tidak ada retry otomatis.

V24 diimplementasikan sesuai desain
[`docs/designs/2026-08-17-evolution-maturity-apex-presence-v24.md`](docs/designs/2026-08-17-evolution-maturity-apex-presence-v24.md):
Identity Invariant mendapat maturation path, Adult/Evolved mendapat kontrak
kematangan, dan Evolved wajib memiliki power center, mass hierarchy, authority
pose, aura architecture, grandeur cues, serta reliability cue. Aura/VFX memakai
allowlist non-green di Plan. Bundle dan seluruh selftest gratis lulus. Adult v24
(`rooted_to_mobile`) lulus 9/9, seam, soul, maturity, style, dan chroma-edge
(3/33.268 bright), tetapi visual reject karena terlalu banyak leaf cluster,
vein, root-finger, pebble joint, glow, dan detail kecil. Evolved v24
(`unfolding`) mempertahankan soul dan ancient-power read, tetapi wajah tetap
terlalu dekat dengan Adult, detail makin padat, dan technical reject karena tiga
detached Idle fragment 27/50/32px dekat seam. Tidak ada retry otomatis.

Desain pengganti v25 disetujui di
[`docs/designs/2026-08-17-evolution-pokemon-clarity-v25.md`](docs/designs/2026-08-17-evolution-pokemon-clarity-v25.md):
clarity diterjemahkan menjadi Shape Budget 2–3 primary shapes, satu dominant
read, detail dibatasi dan wajib disederhanakan, serta Identity Focal Maturity
yang anatomy-agnostic. Revisi terakhir mencabut bias `power = massa besar`:
Vision bebas mengganti body archetype, `apex_thesis` tetap open-ended, dan
tepat dua channel generik menjelaskan presence lewat line/proportion/posture/
negative space/motion/shape distribution/focal motif. Evolved boleh 0,75×–1,50×
tinggi Adult dengan alasan konkret. Aura/glow dihapus dari seluruh character
cells; power supernatural hanya ada di `fx_strike` dan `fx_surge`. V25 sudah
diimplementasikan lokal, dibundel, dan seluruh selftest gratis lulus. Paid
eval Adult Veridian (`rooted_to_mobile`) lulus teknis 9/9 sel, seam, dan
chroma-edge (24/31.813 bright = 0,0754%), tetapi visual masih berupa kolom
akar/daun yang tertanam di batu: soul dua mata bertahan, mobility belum.
Tidak ada Evolved sampai Adult disetujui. Desain v26 menambah
`mobility_contract` anatomy-agnostic di atas v25: tubuh wajib terlihat bisa
hop/walk/roll tanpa menyatu dengan tanah, pot, plinth, atau base diam lain.
Paid Adult v26 disetujui operator 18 Agustus 2026 dan terkunci untuk iterasi
Evolved. Vision Evolved v26 yang lengkap (a5) lolos validator; satu image
GPT Image 2 medium (`5w667r8pa1rmr0d0245bq48jf0`) **technical reject**
karena detached character components pada Happy (115/61px) dan Dirty
(205/46px). Tidak ada image retry. Candidate v27 menambah `face_age_contract`
agar wajah menua antar stage. Paid Evolved v27-a1 Vision
(`vvcrnd3khnrmw0d024at9jabaw`) lolos Plan `mature` + `pillar_stride`; satu
image (`gb69jajrcxrmt0d024bsftg5mg`) **technical reject** Happy sparkle 88px.
Tidak ada image retry. Operator menolak siluet: Evolved masih walker empat
kaki yang sama dengan Adult. Candidate v28 menambah `silhouette_break_contract`
agar Evolved meninggalkan gait kaki Adult (coil/tether). Paid Evolved v28-a1
Vision (`457h8f4x4xrmt0d024g8546xvr`) lolos Plan `unfolding` + `Undulating glide`
+ wajah `mature`; satu image (`jamfktgm1nrmr0d024hbrcm05c`) **technical reject**
(fragmen Happy/Hungry/Dirty/Damaged terlepas). Tidak ada image retry.
Paid Sunhound v28-a1 (Hatchling 75 cm, `dog_canine_retriever_standing`): Adult
Vision reuse `0cpy044w85rmw0d024msjfa8mr` Plan `mass_redistribution` +
`Four-legged stride` + wajah `adolescent` 95 cm; image
`58v15a0gzdrmw0d024nsdxc4dg` lulus teknis 9/9, seam, detached, residu 0,67%.
Operator menyetujui Adult 18 Agustus 2026 dan menguncinya di
`eval/results/evolution-sunhound-adult-v28-approved/` (gitignored) untuk Anima
`2168d17e-440d-4ba3-9004-5104800c6722` saja — go-live memakai byte ini, tanpa
generation ulang. Row live tetap Hatchling sampai ritual. Evolved Vision
`xbe2vc53e5rmy0d024qayj5gdc` Plan `unfolding` + `Undulating glide` + wajah
`mature` 120 cm; image `dc5sgg9hn5rmy0d024qr2m617c` lulus teknis 9/9, seam,
detached, residu 0,51%, tetapi **visual reject** operator 18 Agustus 2026:
limbless coil terbaca ular, bukan Sunhound. Penyebab: v28 wajib Evolved
meninggalkan gait kaki Adult. Adult tetap terkunci; Evolved coil tidak dipakai.
Candidate v29: kind lock + contour delta (bukan exile gait). Paid Evolved
Sunhound v29-a1 Vision `1nm42fcsexrmt0d024wrvse3p4` Plan `unfolding` +
`Swift four-legged gallop` + wajah `mature` 120 cm — tetap canine. Image
`tzp0bpsbg1rmr0d024xb9mzqem` technical reject Sleep 55px. Operator memilih
a2 `x1sh5skgf5rmw0d024z9q5zfgw` (Plan reuse) Sleep 37px lalu menguncinya 18
Agustus 2026 di `eval/results/evolution-sunhound-evolved-v29-approved/` untuk
Anima yang sama — go-live memakai byte ini, tanpa generation ulang.
Paid Playtron v29-a1 (Hatchling 50 cm, `console_plastic_handheld`): Adult
Vision `t665hcctc1rmt0d0251rha0ykm` Plan `unfolding` + `bipedal walk` +
wajah `adolescent` 65 cm + `kind_noun=handheld`; image `z5ycgdr459rmw0d0252axdv5h4`
**technical reject** Sleep Z ketiga 30px. Evolved Vision `8s4hgcreh5rmt0d0252t9htwe8`
Plan `mass_redistribution` + `multi-limbed scuttle/hover` + wajah `mature`
80 cm + `kind_noun=handheld`; image `nz9kcs4e2srmt0d0252r8edke4` **technical
reject** Sleep Z ketiga 135px. Tidak ada image retry. Kind lock lulus (tetap
console, bukan hewan). Operator menguncinya 18 Agustus 2026 di
`eval/results/evolution-playtron-adult-v29-approved/` dan
`eval/results/evolution-playtron-evolved-v29-approved/` untuk Anima
`99b04a1c-07be-4753-be04-ae68183817e6` — go-live memakai byte ini, tanpa
generation ulang. Adult Veridian v26, Adult+Evolved Sunhound, dan
Adult+Evolved Playtron masuk `anima_evolution_locks`. Production v29/flag on.

Vision memakai lease atomik supaya dua isolate tidak membayar Plan dua kali.
Dispatch ambigu tidak diulang; HTTP 4xx/token lokal gagal cepat, sedangkan job
tanpa callback dipulihkan oleh lease 10/20 menit. `begin_evolution` membersihkan
intent stale sebelum one-active gate, sehingga install ulang tidak memblokir akun
selamanya. Cold start lintas device yang kehilangan intent lokal memakai
`resume_evolution`: ia hanya menempel ke generation aktif, memulihkan status
`evolving` yatim, dan tidak pernah membuat generation/spend baru.
`quota_rules.sql` mencakup no-Core, urutan Adult→Evolved, idempotency, rollback,
lease Vision, history/reference cleanup, dan revoke RPC; seluruh suite lulus
terhadap production setelah migrasi.

Migration `20260817095700_evolution_art_pipeline` + `20260817200110_evolution_go_live` + `20260817201340_evolution_name_lineage_v30` tercatat remote. Edge Function
`evolve_anima` version 6, `create_anima` version 22, `replicate_webhook` version
11, `battle_anima` version 26, `team_battle` version 8, `expedition` version 16,
dan `seeker` version 5 ACTIVE; semua selain webhook memakai `verify_jwt=true`.
Smoke tanpa JWT/signature mengembalikan 401, dan RPC evolusi tidak executable
oleh `anon`/`authenticated`.

**Client evolution ritual (live):** `GameState.pending_evolution`, stage-aware sprite cache `v6_<anima_id>_<stage>`, Profile **Evolve** CTA, Collection **Ready to Evolve**, `IncubatorEffect.start_evolution()` chamber, resume/poll di `scan_flow.gd`, modal Rename terisi `suggested_name` sesudah sukses, pelat status/efek Battle. Butuh `feature_evolution` + `evolution_version>=1`. Wiki pemain di `docs/wiki/anima.md`.

Wiki pemain ikut ritual Evolve. APK baru perlu diinstal supaya tombolnya ada di device yang masih memegang build lama.

## Status deploy Battle polish + Tiered EXP 17 Agustus 2026

Tier hadiah Duel terukur dan lawan Duel sistem sudah live: migration
`20260817072847_system_duel_opponents` tercatat remote dan `battle_anima`
version 26 ACTIVE. Probe production memberi Hydron Level 11 lawan
`system-duel-fledgling` Level 11 dengan `bot_anima_id` null, bentuk stat cermin
persis pada 1,121× (HP 90 vs 80, Special 56 vs 50), tier `even`, dan 7–8 Bits —
sama dengan rasio yang dihitung `balancedRatio()` di selftest, jadi pencarian
kekuatan bot berperilaku identik di edge runtime. `quota_rules.sql` dan
`live_battle.gd` (start, resume, tiga aksi, replay, forfeit) lulus terhadap
production.

Backend Battle polish dan Tiered EXP sudah live: migration
`20260816171515_battle_exp_reward_payloads` serta
`20260816200507_tiered_exp_and_battle_rewards` tercatat remote. Edge Function
`battle_anima` version 26, `team_battle` version 8, dan `expedition` version 16
ACTIVE dengan `verify_jwt=true`; ketiganya membawa `RULES_VERSION = 3`.
Snapshot `evolution_version=0` mempertahankan growth + event legacy, sementara
aturan v2 tetap membuang `idempotency_key` dari seed RNG turn. Cache signed URL
roster tetap aktif. Probe production mengonfirmasi threshold
150/700/860, budget Expedition 30, semua 7 Anima tetap pada citra rebase Level
lama, EXP 0–860, tiga kolom baru live, dan helper progression tidak executable
oleh `anon`/`authenticated`. Runtime Expedition
membuang cast `special` dari node Battle/Elite lalu mengisi roster deterministik
dari pool Battle zona; Boss tetap memakai
`final_ace → switch → ace_passive`. Version 12 juga mencegah switch sukarela
AI memilih reserve ace ketika Anima reguler aktif masih hidup; sebelumnya state
low-HP dengan hanya ace di bangku gagal `INVALID_SWITCH_SLOT` sebelum turn commit.
Client
menghitung ulang layer setelah intro sebelum reveal pertama, menjaga semua pose
Boss Seeker pada anchor horizontal yang sama sambil menghitung baseline kaki opak
per pose. Piksel opak terbawah Anima maupun Boss Seeker berimpit tepat dengan pusat
vertikal ground shadow centered tanpa nudge Y, tidak memakai `concern_hit` saat Guard, dan
memasang pose itu tepat pada impact Anima; Seeker kembali Idle sesudah animasi
damage dan sebelum pelat effectiveness. Pose Attack Duel/Team/Expedition baru
muncul setelah pelat nama aksi menahan copy 1,4 detik dan selesai menghilang.
Setelah itu urutannya Attack → VFX → impact → Idle → pelat effectiveness.
Ground shadow arena turun dari alpha 0,90 ke 0,45 dan semua HP bar berganti
warna diskret: biru/cyan di atas 50%, oranye pada 20% < HP ≤ 50%, dan merah
pada HP ≤ 20%, tanpa menghapus angka. Result ber-EXP menyebut nama Anima;
migration itu memulihkan `last_reward.anima_exp` Team/Expedition dari receipt
turn JSON setelah restart. Debug APK baru sudah berhasil diekspor dan diverifikasi,
tetapi perubahan client baru sampai ke pemain setelah APK/AAB baru
diinstal/didistribusikan. Manifest Sugarworks v5 tidak berubah.

## Status deploy label elemen kedua + backfill typing legacy (20 Agustus 2026)

Dilaporkan dari device sebagai "kenapa semua Anima punya elemen kedua Stone".
Diperiksa di Postgres lebih dulu: empat dari lima Anima yang tampil di Collection
justru **tidak punya** elemen kedua sama sekali, dan Mugshots — satu-satunya yang
benar-benar dual (`ceramic`/`flow`) — adalah satu-satunya yang labelnya benar.
Penyebabnya `ElementCatalog.normalize()`, salinan client dari
`normalizeElement()`: parameternya `String`, jadi pemanggilnya menulis
`str(row.get("secondary_element"))` dan `null` PostgREST menjadi `"<null>"` yang
lolos guard `is_empty()`, lalu baris terakhirnya memaksa fallback kosong menjadi
`"stone"`. Kena di setiap layar yang menampilkan elemen: Home, Collection, pick
sheet Battle, profil Anima, lobby Duel, Team, Expedition, dan Atlas. Damage tidak
pernah salah — matchup dihitung `_shared/elements.mjs` dan prediksi client memakai
`ElementRules.normalize()` yang sudah null-safe — jadi ini murni label yang
bertentangan dengan wiki pemain yang sudah benar.

Perbaikannya menghapus salinan itu: `ElementCatalog` memakai
`ElementRules.normalize()` dan berhenti membaca `typing_version`, sebab
`defenseElements()` di server juga tidak membacanya dan constraint
`animas_secondary_v1_null` sudah menjamin row legacy selalu null. Tambalan
`atlas_view._atlas_element_label()` yang mengarang `typing_version` ikut dihapus,
dan prefill Rename Seeker memakai `profile_value_present()`. Tiga check label di
`test_i18n.gd` (4288, dari 4285) menjaga null, `"<null>"`, dan pasangan sungguhan;
seluruh suite client plus `npm run selftest` hijau.

Backfill-nya satu row, dan bukan penilaian baru. `inferCanonicalLegacyTyping()`
dijalankan ulang atas delapan Anima production dengan elemen legacy dari
`generations.vision_result`: tujuh cocok dengan yang live, satu drift — Playtron
masih `spark` tanpa elemen kedua sementara dua Anima ber-`species_key`
`console_plastic_handheld` yang sama (Deckon, klasik) sudah `plastic`/`spark`
lewat `material:plastic_tech`. Playtron memang capture cache hit, jadi ia tidak
punya `vision_result` dan `legacy_art_migration.mjs` melewatinya di
`isAlreadyMigrated()`. Migration `20260820134728_backfill_legacy_handheld_typing`
menyetel typing kanonis itu dan menyinkronkan proyeksi `atlas_forms`, yang hanya
di-upsert saat Scan/Evolve. Predikatnya menyalin syarat drift-nya sehingga aman
dijalankan ulang. Hydron (`legacy:ambiguous`), Veridian (`material:plant`), dan
Sunhound (`subject:animal`) sengaja tetap bertipe tunggal: fungsi yang sama tidak
menemukan elemen kedua untuk mereka, dan mengarangnya akan mengubah damage tanpa
bukti dari foto.

## Synthesis History transparan tanpa merusak Veridian (22 Agustus 2026)

Penyebab art Source hijau rusak bukan post-process utama, melainkan History lama
memakai file reference Planner yang sudah diratakan ke chroma green. Client
kemudian mencoba merekonstruksi alpha lewat flood-fill; informasi itu sudah
lossy, jadi material hijau Veridian dapat ikut terhapus.

Migration `20260822063112_synthesis_transparent_history_refs` sudah live dan
`synthesize_anima` version 3 ACTIVE. Jalur baru membuat dua derivative dari sheet
privat yang sama: `model_source_a/b` tetap chroma-backed untuk Planner, sedangkan
`source_a/b` memakai `cropIdleThumb()` transparan yang sama dengan Atlas.
History sukses lama diperbaiki sekali saat Profile pertama kali meminta History,
tanpa Vision atau image generation baru. Client tidak lagi melakukan chroma key;
dua slot art memakai pulse `UiSkeleton` selama PNG diunduh.

`npm run selftest` lulus, `test_scan_ui.gd` lulus 1.205 check, blok
`quota_rules.sql` production selesai tanpa error, smoke tanpa JWT membalas 401,
dan daftar Edge Function mengonfirmasi version 3 ACTIVE dengan
`verify_jwt=true`.

## Kartu hantu Collection dan bug susulannya: Anima menghilang setelah Summon (26–28 Agustus 2026)

Tiga hari, empat commit, satu root cause yang **bukan** di commit pertama.
Ditulis panjang dengan sengaja karena kelasnya (reference aliasing GDScript,
bukan sekadar `null` yang lolos guard) belum pernah tercatat di sini, dan
biaya menemukannya (dua putaran instrumentasi produksi) layak diingat supaya
tidak diulang. Pagar teknisnya sudah dipindah ke
`.cursor/rules/client-shell-ui.mdc`; bagian ini riwayatnya.

**Gejala awal (26 Agustus):** Anima kehilangan art di Collection sesudah
Summon — kotak abu kosong yang tidak bisa di-tap, kadang bertambah satu slot
tanpa pemilik, kadang seluruh grid mati sampai app di-restart. Root cause
analysis lengkap (lima penyebab berbeda, terkonfirmasi baca kode) dan
rencana perbaikan enam fase ada di
[`docs/designs/2026-08-26-collection-ghost-art-cards.md`](designs/2026-08-26-collection-ghost-art-cards.md).
Fix-nya menutup latch permanen `_thumbnail_backfill_seen`, `_busy`, dan
`_summon_in_flight`, plus menutup re-entrancy `CollectionView.set_rows()`
lewat `call_deferred()`, plus guard dedup id kosong/`"<null>"`. Diverifikasi
lewat test suite (1485+ check) sebelum dianggap selesai.

**Regresi (27 Agustus):** APK baru diuji, dan muncul perilaku baru yang
justru lebih parah — Summon satu Anima membuat Anima itu **hilang total**
dari grid Collection, bukan cuma kehilangan art. Ulangi untuk Anima
berikutnya, dan berikutnya, sampai grid kosong dan CTA "Start First Scan"
muncul di akun yang sudah punya empat Anima. Dua percobaan pertama
menerka dari membaca kode (race kondisi `_thumbnail_backfill_running`,
latch `_populating` di `CollectionView` yang bisa nyangkut kalau satu
baris error saat render) — keduanya nyata sebagai bug tapi **tidak**
terbukti sebagai penyebab lewat repro sintetis yang mensimulasikan seluruh
alur Summon dengan Backend di-mock. Diperbaiki dan di-ship, tapi user
melaporkan gejalanya **masih persis sama** di Godot editor preview.

**Cara menemukannya:** tebakan dihentikan, diganti print di setiap titik
yang menyentuh `_roster` (`_populate_collection`, `_upsert_roster`,
`_reload_roster`), lalu user mereproduksi ulang dan menempelkan Output
panel Godot editor-nya secara langsung — sesuatu yang tidak bisa didapat
dari APK tanpa `adb logcat`. Log pertama membuktikan `_roster.size()`
**tidak pernah berubah** (tetap 4 sepanjang sesi) tapi `id` salah satu
entrinya berubah jadi string kosong tepat sesudah toast "X answered your
summon" — dan entri yang kosong itu selalu persis Anima yang baru saja
di-Summon. `_upsert_roster()` sendiri terbukti bersih: print di dalamnya
selalu menunjukkan `id` yang benar tepat sesudah merge. Berarti sesuatu
menulis ke Dictionary itu **in-place**, sesudah `_upsert_roster()` selesai,
tanpa lewat fungsi manapun yang sudah diberi print.

Putaran kedua menambah pemeriksaan `is_same()` (identity check Godot,
bukan `==` yang membandingkan isi) di setiap kandidat alias —
`_current_anima`, `_profile_anima`, roster melawan dirinya sendiri — dan
semuanya `false`. Ini yang akhirnya mengarahkan pencarian ke tempat yang
benar: bukan `_current_anima`/`_roster`, tapi **`CollectionView`'s
`_selected_row`**, yang tidak pernah diperiksa `is_same()` sebab tidak ada
getter untuk membacanya dari luar. Grep manual atas setiap penulisan
`_selected_row` menemukan `begin_visit()` memanggil `_selected_row.clear()`
— dan `_row_with_id()`, dipakai `set_rows()` untuk merekonsiliasi kartu yang
sheet-nya sedang terbuka, mengembalikan Dictionary `_roster` **tanpa
duplicate**. `_selected_row = replacement` di titik rekonsiliasi itu berarti
"kartu yang lagi dibuka" dan "baris roster-nya" jadi **objek yang sama
persis** di memori. Rantainya: pemain tap kartu (sheet terbuka, alias
terbentuk) → Summon → server menjawab, `_populate_collection()` jalan
beberapa kali, tiap kali merekonsiliasi ulang alias ke row `_roster` yang
baru di-merge → pemain balik ke tab Collection buat Summon Anima
berikutnya → `begin_visit()` (dipanggil **setiap kali** tab Collection
dibuka, termasuk sesudah tiap Summon karena Summon pindah ke Home)
memanggil `.clear()` pada Dictionary yang ternyata **adalah** baris roster
itu sendiri. Guard dedup id-kosong dari fix hari sebelumnya lalu
correctly membuang baris yang idnya sudah kosong itu dari grid — bug
kartu hantu dan bug kartu hilang sebenarnya berbagi satu guard yang sama,
cuma dipicu penyebab yang berlawanan arah.

Repro sintetis yang **akhirnya** berhasil butuh tiga elemen yang absen di
percobaan sebelumnya sekaligus: Backend di-mock (supaya jalan tanpa
jaringan sungguhan), `show_preview()` dipanggil sebelum tiap Summon (supaya
alias-nya benar-benar terbentuk), **dan** `_switch_destination(&"collection")`
dipanggil sebelum tiap Summon (supaya `begin_visit()` benar-benar
memicu `.clear()`-nya) — tanpa unsur ketiga itu, alias terbentuk tapi tidak
pernah dipicu, dan roster tetap terlihat sehat.

**Perbaikan:** dua baris. `_selected_row = replacement.duplicate(true)`
saat rekonsiliasi (memutus alias di sumbernya), dan `_selected_row = {}`
menggantikan `_selected_row.clear()` di `begin_visit()` (reassign, bukan
mutasi in-place — pagar kedua kalau ada alias lain yang belum ketemu).
Regression test mereproduksi rantai persis `set_rows → show_preview →
set_rows lagi → begin_visit` dan memastikan Dictionary milik pemanggil
selamat; dikonfirmasi gagal di kode sebelum-fix dan lulus sesudahnya.
Semua print diagnostik dan pemeriksaan `is_same()` dibuang sesudah root
cause terkonfirmasi — nilainya cuma untuk investigasi, bukan untuk tetap
hidup di kode production.

**Pelajaran untuk lain kali**, ditulis di
`.cursor/rules/client-shell-ui.mdc` supaya termuat otomatis saat
menyentuh `game/scripts/`: `Dictionary`/`Array` GDScript adalah reference
type. Fungsi apa pun yang mengembalikan row dari `_roster` tanpa
`.duplicate(true)` — `_roster_row()`, `_active_row()`,
`_evolving_roster_row()` semuanya begini — menyerahkan objek yang sama
persis ke pemanggilnya. Aman selama pemanggil hanya membaca atau
melewatkannya lagi; berbahaya begitu pemanggil menaruhnya di state lokal
lalu memanggil `.clear()`/`.erase()`/`[key] = value` di atasnya alih-alih
`.merge()` atau reassignment — itu menulis ke `_roster` tanpa lewat
`_upsert_roster()`, diam-diam, dan gejalanya muncul di layar yang sama
sekali tidak terlihat terkait dengan baris kode yang salah.

## Daftar migration yang sudah live

- Figur pemilik di sheet detail Atlas live 3 September 2026 lewat `gallery`
  version 25, **tanpa migrasi**: `profiles.seeker_avatar` sudah ada sejak
  `20260903032000_seeker_avatar_choice`, jadi rollout ini cuma satu kolom
  tambahan di `select` dan satu field di proyeksi detail. Smoke sesudah deploy:
  POST tanpa JWT menjawab 401, dan `functions list` mencatat `gallery` 25 ACTIVE
  `verify_jwt=true`. Normalisasi ada di server (`atlasOwnerAvatar`): profil
  `NULL` pulang sebagai `androgynous` karena pemain itu memang punya tampilan
  default, sementara form `expedition` tetap `null` supaya Boss Seeker memakai
  art chapter-nya sendiri alih-alih figur roster yang kita karang. Client cuma
  perlu membaca satu aturan: string berarti gambar, `null` berarti sembunyikan.
  Kartu grid **tidak** ikut walau payload-nya sudah membawa `owner_name` —
  tidak ada surface client yang menggambar nama itu, jadi figur di sana berarti
  surface baru, bukan surface yang didandani.

  Dua angka yang mahal didapat. Pertama, memindahkan label nama pemilik ke dalam
  `HBoxContainer` bersama figurnya **tanpa** `SIZE_EXPAND_FILL` + lantai lebar
  membuat label itu menyusut ke 1 px: autowrap lalu membungkus per karakter,
  16 baris, 717 px, dan `AtlasDetailSheet` tumbuh 1.126 → 1.801 px sementara
  lebar selnya tetap terlihat sehat (99 px) — persis pola "layout diukur sebelum
  settle" di `.cursor/rules/client-shell-ui.mdc`, ditemukan probe headless
  `SubViewport` 720×1602, bukan oleh mata. Sesudah `SIZE_EXPAND_FILL` +
  `OWNER_NAME_WRAP_PX = 180`: nama 15 karakter jadi 2 baris, sel 141 px, sheet
  1.171 px, dan tiga kali `_present_detail` berturut-turut tidak menumbuhkan
  apa pun. Kedua, **selama sheet masih tertutup, setiap label autowrap di
  dalamnya melapor sampah** — `AtlasDetailIdentity` yang tidak disentuh siapa
  pun juga melapor 717 px pada `size.x = 1`, sebab Godot tidak me-layout subtree
  tak terlihat. Karena itu `_test_atlas_view()` sekarang `await sheet.open()`
  sebelum satu pun ukuran diperiksa; assert ukuran pada sheet tertutup mengukur
  keadaan yang tidak pernah dilihat pemain.

  Pagar anonimitasnya masuk ke skenario 39 `npm run selftest` sebagai gerbang
  kelima, di sebelah empat gerbang nickname yang sudah ada: `profiles.seeker_avatar`
  hanya boleh dibaca `seeker` dan `gallery`, `owner_avatar` hanya boleh muncul
  sekali dan persis di sebelah `owner_name` di `atlasDetail`, `atlasCard` tidak
  boleh membawanya, dan `battle_anima`/`team_battle`/`expedition` tidak boleh
  menyentuh `from("profiles")`, `seeker_name`, `seeker_avatar`, atau
  `owner_avatar` sama sekali. Regex-nya diperiksa tidak vakum: ia menyala pada
  `gallery` dan `seeker` yang memang membaca profil, dan `null` di ketiga perakit
  lawan. Sembilan suite hijau: `npm run selftest` (43 skenario + 12 webhook),
  `test_scan_ui` 1.576, `test_i18n` 5.120, `test_sprite_slicing` 304,
  `test_client_state` 199, `test_auth_flow` 63, `test_game_rules` 181,
  `test_expedition_route_map` 91, `test_battle_sim_parity` 530.
- Seeker Avatar ikut submit onboarding live 3 September 2026 lewat
  `20260903043000_seeker_avatar_at_onboarding` + `seeker` version 9. Ini satu
  dari sedikit migrasi yang **drop lalu create** alih-alih `create or replace`:
  parameter kelima berarti signature baru, dan `create or replace` akan
  meninggalkan overload 4-argumen di sebelahnya sehingga panggilan bernama
  PostgREST menjadi ambigu. Konsekuensi yang tidak boleh dilupakan adalah drop
  itu ikut membuang revoke/grant milik fungsi lama, dan fungsi baru lahir dengan
  EXECUTE untuk PUBLIC — pada fungsi SECURITY DEFINER yang menerima `p_owner`,
  membiarkannya berarti siapa pun boleh menamai profil pemain lain lewat
  `/rest/v1/rpc`. Probe production sesudah apply: tepat satu
  `complete_seeker_profile(uuid,text,integer,text,text)` ada, dan ACL-nya persis
  `postgres=X/postgres | service_role=X/postgres` — nol `anon`, nol
  `authenticated`. `quota_rules.sql` lengkap lulus terhadap production dengan
  tiga pemeriksaan baru: figur yang dipilih ikut tersimpan bersama nama, slug di
  luar roster diabaikan tanpa menggagalkan nama, dan argumen kelima yang hilang
  tidak menghapus figur yang sudah dipilih. Argumen kelima itu sengaja
  **mengabaikan** nilai asing alih-alih menolaknya seperti `p_gender`: gender
  adalah jawaban pemain tentang dirinya sehingga menyimpan yang salah berarti
  menyimpan kebohongan, sedangkan figur cuma kosmetik yang bisa diganti gratis —
  dan kalau ia boleh menggagalkan transaksi, satu baris picker yang selalu punya
  pilihan default jadi bisa mengunci pemain di luar namanya sendiri. Delapan
  suite Godot dan `npm run selftest` tetap hijau.
- Penyimpanan Seeker Avatar live 3 September 2026 lewat
  `20260903032000_seeker_avatar_choice`, di-push dengan `supabase db push
  --linked --workdir backend` sesudah satu dry-run, jadi tidak ada drift nama
  file. **Tidak ada Edge Function yang ikut naik**: `seeker_profile_summary`
  adalah RPC yang sudah dipanggil `seeker` version 6, jadi kolom barunya ikut
  pulang tanpa deploy. Probe production sesudah apply: hak UPDATE
  `authenticated` pada `profiles` berisi tepat `display_name, last_seen_at,
  seeker_avatar` (aditif, bukan hasil revoke + grant ulang), constraint
  `profiles_seeker_avatar_in_roster` menerima empat slug roster, dan nol row
  membawa avatar karena belum ada UI yang menulisnya. `quota_rules.sql` lengkap
  lulus terhadap production sesudah migrasi, dengan tiga pemeriksaan baru: nilai
  di luar roster ditolak `check_violation`, tulisan ke row sendiri mendarat, dan
  tulisan ke row pemain lain menyentuh 0 baris serta terbukti tidak mengubah
  nilai korban saat dibaca dari luar RLS. Delapan suite Godot tetap hijau.
- Migration Battle `20260813103446_battle_vertical_slice`, indeks bot `20260813105258_index_battle_bot_anima`, cap reward `20260813174007_limit_daily_battle_rewards`, indeks unik ledger `20260813174454_index_battle_reward_ledger_ref`, perbaikan status `20260813180241_refine_battle_reward_status`, guard Energy `20260813193612_require_battle_energy`, decay realtime + biaya Energy Battle `20260813195613_decay_realtime_and_battle_energy`, EXP/Level tanpa Bond `20260813201820_exp_level_growth`, gerbang Feed/Clean penuh `20260813220036_reject_full_feed_clean`, dan tidur Anima yang tidak di-Summon `20260813220954_bench_unsummoned_sleep` + `20260813221113_apply_care_bench_summon` + Energy bangku 3 jam `20260813224221_bench_sleep_faster` + gerbang Hunger Battle `20260814043053_reject_hungry_battle` (sudah di-drop: lapar tidak mengunci Bits) + reset hari sipil lokal `20260814064443_local_day_reset` + `20260814064550_local_day_reset_status` + `20260814064614_local_day_reset_care` sudah live. Lapar tidak mengunci Battle: `20260814101323_allow_hungry_battle`. Clean gratis: `20260814104237_free_clean`. Shop live: `20260814082442_shop_inventory_bits` + `20260814082512_shop_inventory_rpcs` + `20260814082545_shop_apply_care` + `20260814082612_shop_battle_rewards` + `20260814082658_shop_commit_battle_turn`. Guest Seeker/Google live lewat `20260814153135_seeker_google_accounts`; guard guest sebelum Vision lewat `20260814172154_guard_guest_scan_before_vision`. Capture/private art live lewat `20260814215746_capture_foundations`; Gallery lewat `20260814215801_gallery`. Tinggi kanonis live lewat `20260815214409_anima_body_height`; kalibrasi tinggi/metrics lewat `20260815225656_recalibrate_anima_heights_and_metrics`; prompt production v18 lewat `20260815225859_prompt_version_v18`. Tinggi Veridian 150 cm lewat `20260815234322_lower_veridian_height`. Starter lifetime 4 + Care rebalance live lewat `20260816074701_starter_four_and_care_rebalance`. Floor bangku / well_cared aktif-only live lewat `20260816082652_bench_care_safe_rest`. Tiered EXP, reward Battle berskala, cap Sleep harian, dan budget Expedition 30 live lewat `20260816200507_tiered_exp_and_battle_rewards`. Lawan Duel sistem live lewat `20260817072847_system_duel_opponents`. Typing kanonis Playtron + sinkron proyeksi Atlas live lewat `20260820134728_backfill_legacy_handheld_typing`. `shop` version 4, `care_anima` version 9, `battle_anima` version 26, `create_anima` version 22, `seeker` version 5, `replicate_webhook` version 10, `gallery` version 2, `team_battle` version 8, dan `expedition` version 16 ACTIVE; semua kecuali webhook memakai `verify_jwt=true`. `create_anima` membundel seluruh versi lokal; `app_config.prompt_version = "v31"` production, v20 rollback capture tanpa Vibe, v19 rollback gate, v18 rollback kebijakan tinggi handheld, v17 rollback kebijakan tinggi awal, v15 rollback art, dan v13 rollback kontrak capture. Tujuh Anima ready production sudah dibackfill `body_height_cm` dan `render_metrics` hasil ukur sheet privat. Enam Anima ready legacy sudah dipindahkan ke `anima_sheets`, diretype v2, dan bucket `sheets` dibuat privat. `apply_care()` menolak Hunger/Hygiene >= 99.5 dengan `NEED_FULL`. `Summon` menulis `profiles.active_anima_id` dan menidurkan sisanya. `care_anima` menyimpan `timezone_offset_minutes` lewat `set_profile_timezone` sebelum RPC; snapshot player/bot membawa `level` dari `care_score`, `body_height_cm`, plus `strike_name`/`surge_name`, dan `createFighter` memakai growth multiplier. Error boundary tetap membaca `message` dari object PostgREST, bukan hanya instance `Error`; tanpa itu exception RPC yang dikenal jatuh menjadi 500 generik. Probe SQL production membuktikan win ketiga dibayar dan win keempat menjadi Training tanpa satu pun mutation progression.
