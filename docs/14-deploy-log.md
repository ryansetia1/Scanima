# 14 — Log deploy

Riwayat rollout yang sebelumnya hidup di `CLAUDE.md`. Isinya dipindahkan verbatim; urutannya sama dengan urutan di file asal, bukan kronologis. Yang berlaku sekarang diringkas sebagai tabel status di `CLAUDE.md` — file ini adalah catatan bagaimana keadaan itu tercapai, termasuk probe production dan angka yang terukur saat itu.

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

## Daftar migration yang sudah live

- Migration Battle `20260813103446_battle_vertical_slice`, indeks bot `20260813105258_index_battle_bot_anima`, cap reward `20260813174007_limit_daily_battle_rewards`, indeks unik ledger `20260813174454_index_battle_reward_ledger_ref`, perbaikan status `20260813180241_refine_battle_reward_status`, guard Energy `20260813193612_require_battle_energy`, decay realtime + biaya Energy Battle `20260813195613_decay_realtime_and_battle_energy`, EXP/Level tanpa Bond `20260813201820_exp_level_growth`, gerbang Feed/Clean penuh `20260813220036_reject_full_feed_clean`, dan tidur Anima yang tidak di-Summon `20260813220954_bench_unsummoned_sleep` + `20260813221113_apply_care_bench_summon` + Energy bangku 3 jam `20260813224221_bench_sleep_faster` + gerbang Hunger Battle `20260814043053_reject_hungry_battle` (sudah di-drop: lapar tidak mengunci Bits) + reset hari sipil lokal `20260814064443_local_day_reset` + `20260814064550_local_day_reset_status` + `20260814064614_local_day_reset_care` sudah live. Lapar tidak mengunci Battle: `20260814101323_allow_hungry_battle`. Clean gratis: `20260814104237_free_clean`. Shop live: `20260814082442_shop_inventory_bits` + `20260814082512_shop_inventory_rpcs` + `20260814082545_shop_apply_care` + `20260814082612_shop_battle_rewards` + `20260814082658_shop_commit_battle_turn`. Guest Seeker/Google live lewat `20260814153135_seeker_google_accounts`; guard guest sebelum Vision lewat `20260814172154_guard_guest_scan_before_vision`. Capture/private art live lewat `20260814215746_capture_foundations`; Gallery lewat `20260814215801_gallery`. Tinggi kanonis live lewat `20260815214409_anima_body_height`; kalibrasi tinggi/metrics lewat `20260815225656_recalibrate_anima_heights_and_metrics`; prompt production v18 lewat `20260815225859_prompt_version_v18`. Tinggi Veridian 150 cm lewat `20260815234322_lower_veridian_height`. Starter lifetime 4 + Care rebalance live lewat `20260816074701_starter_four_and_care_rebalance`. Floor bangku / well_cared aktif-only live lewat `20260816082652_bench_care_safe_rest`. Tiered EXP, reward Battle berskala, cap Sleep harian, dan budget Expedition 30 live lewat `20260816200507_tiered_exp_and_battle_rewards`. Lawan Duel sistem live lewat `20260817072847_system_duel_opponents`. Typing kanonis Playtron + sinkron proyeksi Atlas live lewat `20260820134728_backfill_legacy_handheld_typing`. `shop` version 4, `care_anima` version 9, `battle_anima` version 26, `create_anima` version 22, `seeker` version 5, `replicate_webhook` version 10, `gallery` version 2, `team_battle` version 8, dan `expedition` version 16 ACTIVE; semua kecuali webhook memakai `verify_jwt=true`. `create_anima` membundel seluruh versi lokal; `app_config.prompt_version = "v31"` production, v20 rollback capture tanpa Vibe, v19 rollback gate, v18 rollback kebijakan tinggi handheld, v17 rollback kebijakan tinggi awal, v15 rollback art, dan v13 rollback kontrak capture. Tujuh Anima ready production sudah dibackfill `body_height_cm` dan `render_metrics` hasil ukur sheet privat. Enam Anima ready legacy sudah dipindahkan ke `anima_sheets`, diretype v2, dan bucket `sheets` dibuat privat. `apply_care()` menolak Hunger/Hygiene >= 99.5 dengan `NEED_FULL`. `Summon` menulis `profiles.active_anima_id` dan menidurkan sisanya. `care_anima` menyimpan `timezone_offset_minutes` lewat `set_profile_timezone` sebelum RPC; snapshot player/bot membawa `level` dari `care_score`, `body_height_cm`, plus `strike_name`/`surge_name`, dan `createFighter` memakai growth multiplier. Error boundary tetap membaca `message` dari object PostgREST, bukan hanya instance `Error`; tanpa itu exception RPC yang dikenal jatuh menjadi 500 generik. Probe SQL production membuktikan win ketiga dibayar dan win keempat menjadi Training tanpa satu pun mutation progression.
