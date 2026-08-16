# 09 — Team Battle, Expedition, dan Chapter Factory

Dokumen ini adalah spesifikasi target untuk dua mode setelah Duel 1v1:
**Team Battle** async dan **Expedition** bercabang. Keduanya memakai formula
combat Scanima yang sama, tetapi state, reward, dan rollout-nya terpisah dari
Duel yang sudah live.

Sampai feature flag terkait aktif, panduan pemain di `docs/wiki/` tetap
menjelaskan Duel saja.

## 1. Prinsip

1. **Duel tidak ditulis ulang.** Formula stat, damage, elemen, PP, dan item
   dibagi; resolver roster hidup terpisah.
2. **Server tetap berwenang.** Client hanya mengirim intent, slot switch, dan
   idempotency key. HP, map, reward, unlock, dan Trophy tidak pernah dipercaya
   dari client.
3. **Empat anggota, satu aktif.** Team Battle dan Expedition membutuhkan tepat
   empat Anima, tetapi arena tetap 1 aktif vs 1 aktif.
4. **Konten baru tidak membutuhkan update app.** Chapter adalah manifest
   immutable + aset CDN. Mekanik/effect type baru tetap membutuhkan build baru.
5. **Tidak ada model call saat pemain bermain.** Semua art dan copy chapter
   dibuat developer lebih dulu, direview, lalu dipublish.

## 2. Team Battle

### Tim dan lawan

- Pemain menyimpan Team Battle berisi tepat 4 Anima.
- Defense Team disimpan terpisah dan hanya masuk pool lawan setelah opt-in.
- Snapshot Defense tidak membawa owner ID, Seeker Name, atau nickname privat.
- Mengubah roster pemilik tidak mengubah session yang sudah dimulai.
- Jika pool pemain kosong, server menyediakan system team.

Lobby menawarkan tiga candidate: **Favorable**, **Even**, dan **Tough**.
Kekuatan dibandingkan dari total combat power roster, bukan jumlah anggota.
Lawan boleh membawa 1–4 Anima; satu lawan sangat kuat sah menjadi mini-boss.
Fresh database mempunyai satu system team placeholder supaya lobby tidak
dead-end sebelum Defense opt-in tersedia. Feature flag tidak boleh aktif luas
sebelum placeholder itu diganti roster/art authored oleh Chapter Factory.

### Eligibility dan Energy

Keempat anggota pemain harus owned, `ready`, tidak Dormant, dan punya Energy
cukup. Companion aktif harus bangun. Anggota Collection boleh tetap memiliki
penanda tidur server—seperti picker Duel, Energy projected-nya yang menentukan—
karena membuat empat Anima aktif di Home akan melanggar aturan satu Summon.
Start session baru memotong **10 Energy per anggota** dalam satu transaksi.
Resume tidak memotong lagi. Hunger dan Hygiene tidak mengunci, tetapi tetap
menurunkan combat stats melalui formula care yang sama dengan Duel.

### Turn dan switch

Wire action Team Battle:

- `strike`, `surge`, `guard`, `item` — arti identik dengan Duel.
- `switch` + `switch_to_slot` — switch sukarela memakai turn.

Switch sukarela selesai sebelum serangan lawan; Anima yang baru masuk dapat
menerima serangan pada turn yang sama. Setelah KO, forced switch wajib dan tidak
memakan turn berikutnya. PP, HP, buff, dan status item milik masing-masing
fighter bertahan selama encounter. Satu item Battle hanya boleh dipakai sekali
untuk seluruh encounter.

Sesudah art anggota baru dipasang dalam keadaan tersembunyi, client langsung
menghitung ulang rasio tinggi, posisi, layer, framing kamera, Boss Seeker, dan
backdrop. Layout lama lalu bergerak ke target selama 0,32 detik bersamaan dengan
charge portal, sebelum Anima baru di-reveal atau serangan berikutnya dimainkan.
Reduced Motion menerapkan target tanpa tween. Reframe tidak boleh ditunda sampai
event Attack berikutnya atau commit session di akhir event log.

Menang berarti seluruh roster lawan KO. Saat turn ceiling tercapai, hasil
ditentukan dari rasio total HP roster yang tersisa; rasio sama menjadi draw dan
tidak memberi reward.

### EXP dan cap

Baseline rollout, semuanya tetap `app_config`:

- 2 kemenangan progression per hari sipil lokal.
- 40 Bits per hari dari Team Battle.
- Anima yang pernah aktif dan masih hidup mendapat +2 EXP.
- Bench yang tidak pernah aktif dan masih hidup mendapat +1 EXP.
- Anggota yang KO di akhir encounter mendapat 0 EXP.

Cap Team Battle terpisah dari Duel. Loss, draw, dan forfeit memberi nol. Seeker
EXP tetap bertambah hanya dari delta EXP Anima yang benar-benar committed.

## 3. Expedition

### Chapter dan zona

Satu chapter terdiri dari tiga zona. Setiap zona membuat directed acyclic map
dari seed server; pemain menempuh empat node pilihan. Boss chapter muncul setelah
zona ketiga, sehingga satu clear penuh sekitar 12 node + boss dan boleh
dilanjutkan lintas hari.

Chapter permanen dan terbuka berurutan. First clear membuka chapter berikutnya.
Published content version immutable; run mengunci `chapter_id` dan
`content_version` agar publish baru tidak mengubah perjalanan yang sedang aktif.

Client menggambar map itu sebagai route tree bercabang, bukan grid dua kolom.
Battle, Cache, Recovery, Mystery, Shop, dan Boss punya ikon berbeda. Edge yang
sudah dilalui dan cabang terkunci sama-sama redup; hanya jalur pratinjau ke
depan yang disorot. Brightness, focus border, dan state input menggantikan label
`Reachable`/`Locked` berulang. Node memakai target sentuh minimal 96 px. Tap
pertama hanya memilih node dan menyorot turunannya; RPC `enter_node` baru
dikirim setelah pemain menekan **Enter Node**. Peta memakai surface gelap opak supaya ambient ring dari
shell tidak bersaing dengan node. Status run dipadatkan menjadi satu baris;
rincian empat HP disembunyikan saat penuh dan diganti ringkasan tim hanya bila
ada anggota terluka. `visited_node_ids` disimpan authoritative per attempt dan
dikosongkan saat zona di-reset.

### Tim, snapshot, dan checkpoint

Expedition Team berisi tepat 4 Anima dan terpisah dari Team Battle. **Begin
Expedition** menyinkronkan care authoritative lalu memeriksa dan memotong
**30 Energy per anggota satu kali** dalam transaksi pembuatan run. Idempotency
start menjaga retry/resume tidak mendebit ulang. Roster terkunci selama seluruh
run, termasuk checkpoint, dan baru dapat diedit setelah complete atau abandon.
Start zona 1–3 serta Boss tidak memeriksa atau memotong Energy; active run tetap
dapat diteruskan ketika Energy anggota sudah 0. Snapshot pemain memakai UUID
Anima; roster lawan chapter memakai slug konten (`sugarworks-gumdrop`) dan
dibandingkan sebagai text, bukan UUID. Config wire
`expedition_energy_per_member` berarti biaya masuk per run, bukan biaya zona.

HP penuh hanya saat Zona 1 dimulai. Sesudah Zona 1 dan 2 selesai, run berhenti
di checkpoint dan server mewajibkan tepat satu pilihan idempoten sebelum zona
berikutnya:

- **Recover** menambah 50% max HP ke setiap anggota, dijepit ke max HP; anggota
  KO bangkit dengan 50% max HP.
- **Power Up** mempertahankan HP dan memberi +10% Attack, Guard, serta Speed
  selama zona berikutnya saja. Boost ini tidak masuk ke daftar boost permanen
  run dan kedaluwarsa pada checkpoint berikutnya.

HP sesudah pilihan bertahan ke zona berikutnya; PP tetap kembali penuh setiap
encounter. Nilai 50% dipilih untuk chapter pemula: ia cukup memulihkan satu
roster yang rusak tanpa menghapus keputusan rute atau membuat Boss Zona 3
otomatis mudah. Power Up menjadi pilihan untuk tim yang masih sehat, bukan heal
gratis sekaligus buff.

Arena memakai `zones[].background_path` dari manifest.
Art zona adalah backdrop Battle, bukan peta node: kaki petarung duduk dekat
88% tinggi stage, layar tinggi mencrop sisi kiri/kanan, dan Boss Seeker
mengisi pita kanan. Background wajib menyediakan lantai padat lebar di pita
bawah serta detail yang tenang di tengah supaya Anima tetap fokus. Kontrak
prompt hidup di `backend/prompts/chapter_factory/zone_art.md` dan
[runbook manual](10-manual-chapter-assets.md). EXP yang
didapat langsung masuk ke Anima, dan growth stat dipakai di encounter Battle
berikutnya di zona yang sama. Retreat dari encounter memakai reset zona yang sama. Jika seluruh tim KO:

1. state kembali ke snapshot masuk zona,
2. map zona dibuat ulang dari seed baru,
3. HP, Tokens (wire `supplies`), dan boost dari attempt gagal dibatalkan,
4. Bits untuk refresh Shop direfund sekali lewat ledger idempoten.

Zona yang sudah selesai tidak hilang saat attempt zona gagal. **Abandon** manual
selalu membuka dialog destruktif: run berakhir permanen, progres zona aktif,
Tokens, dan boost run tidak dapat dipakai lagi, serta biaya Energy masuk tidak
dikembalikan. Reward yang sudah authoritative tetap dimiliki. Run baru memakai
seed baru sehingga route-nya juga baru; refresh Shop yang memang eligible tetap
mengikuti refund idempoten server.

### Node allowlist

| Node | Kontrak minimum |
| --- | --- |
| Battle | Team reguler bertema; Tokens normal |
| Elite | Team lebih kuat; Tokens dan pilihan boost lebih baik |
| Recovery | Pilih heal roster atau revive satu Anima |
| Cache | Pilih satu dari maksimal tiga boost |
| Shop | Tiga offer memakai Tokens; satu refresh boleh memakai Bits; `shop-skip` melanjutkan tanpa pembelian |
| Mystery | Dua pilihan singkat dari effect allowlist |
| Boss | Boss Seeker + 3 Anima reguler + 1 ace `special` yang ditahan sampai akhir |

Effect v1 dibatasi ke heal, revive, Tokens (wire `supplies`), max HP, Attack,
Special, Guard, Speed, start PP, dan Shop discount. Manifest tidak boleh
mengarang effect baru. Copy pemain memakai Tokens; kolom dan effect type tetap
`supplies`. `shop-skip` adalah choice wire yang dicadangkan runtime, bukan
effect atau option manifest. RPC hanya menerimanya pada pending node `shop` dan
menuntut `party_state`, Tokens, serta boost identik dengan state authoritative.

Tiga encounter pertama per hari sipil lokal memberi progression EXP:
+2 untuk fighter yang pernah aktif dan masih hidup, +1 untuk bench yang masih
hidup, dan 0 untuk yang KO. Layar hasil menampilkan
EXP tiap anggota dan siapa yang naik Level. Tokens tetap diberikan
setelah cap karena merupakan resource run, bukan mata uang permanen. Encounter
biasa tidak mencetak Bits.

Selesai zona mencetak Bits permanen sesuai `zones[].bits_reward` pada manifest.
The Sugarworks v5 menjadwalkan 10/20/30 Bits untuk Zone 1/2/3, sehingga cap
hariannya 60 Bits per stable chapter untuk seluruh run dan content version akun
itu. Hari memakai batas sipil lokal profile yang sama dengan Battle. Receipt
unik `(run_id, zone)` dan ledger `expedition_zone` membuat replay idempoten;
profile row lock membuat dua run paralel tidak dapat melewati sisa cap. Manifest
lama tanpa field itu memberi nol reward berulang. First clear 25 Bits dan Trophy
tetap satu kali serta berada di luar cap Zone Bits.

## 4. Boss Seeker dan dialog

Setiap boss mempunyai Seeker original yang selalu terlihat di belakang Anima
lawan. Pose idle dipakai saat menunggu; event authoritative dapat mengganti ke
Attack Command, Special Command, Switch Command, Concern/Hit, Last Anima,
Victory, atau Defeat. Pada momen command, pose boleh maju sebagai cut-in singkat.
Reduced Motion mengganti pose tanpa tween.

Dialog memakai budget per encounter: opening (`boss_intro` atau `rematch`),
maksimal satu line command dari Attack/Special/Switch pertama yang terjadi,
`last_anima` wajib ketika ace Boss masuk, lalu line terminal victory/defeat.
`chapter_intro` tetap sekali per run. Pose command tetap dimainkan pada setiap
aksi lawan meski budget dialog sudah habis. Urutannya selalu pose Seeker →
dialog opsional → event plate → animasi Anima → kembali ke Intro/Idle, sehingga
copy, Summon, dan serangan tidak saling menimpa.

Boss roster tepat empat dan tepat satu cast member bertanda `special`. Hanya
encounter `kind = boss` yang mengaktifkan reserve: starter dan switch AI memakai
anggota reguler selama salah satunya masih hidup. Switch ace mengeluarkan
`final_ace`, lalu `switch`, lalu `ace_passive` secara authoritative dan
deterministik. Passive allowlist live adalah bonus PP, bounded stat boost, atau
one-hit shield; flag applied di state mencegah efek kedua saat replay. Sugarworks
v2 memakai **Final Confection**: Cotton mendapat +1 max/current PP ketika masuk.

Satu sheet 3×3 memuat:

1. Intro/Idle
2. Attack Command
3. Special Command
4. Switch Command
5. Concern/Hit
6. Last Anima
7. Victory
8. Defeat
9. Profile

Portrait, profile image, dan cut-in diturunkan dari sheet yang sama. Map dialog
menyediakan trigger `chapter_intro`, `boss_intro`, `first_attack`,
`first_special`, `first_switch`, `last_anima`, `victory`, `defeat`, dan
`rematch`; director memilihnya sesuai budget di atas. Setiap line hanya boleh
tampil sekali per session state; replay event tidak mengulang dialog. Runtime menempel `boss_seeker` plus `sheet_url` pada
run/encounter; client memuat sheet 3×3. Encounter Boss pertama menampilkan
Seeker saja, dialog tanpa overlay gelap, lalu pose command dan Summon Anima
lawan sebelum input nyala. Sesudah itu Seeker di belakang Anima, di-clamp di
dalam stage, cut-in pada command, dan dialog tap-to-continue.

Semua cast dan Boss Seeker content v2+ wajib mempunyai `body_height_cm`.
Post-process menyimpan bbox opak pose Idle/Intro Idle sebagai
`render_metrics.reference_height_px` dan `reference_width_px`. Godot menghitung
skala non-linear dari dua kontrak itu lewat satu `shared_scales()` untuk
seluruh tubuh di arena, termasuk Seeker di back lane. Anima 120 cm mengisi
sekitar 45% kartu desain 720×800, lalu shot lebar di-fit ke 50% lebar kartu;
fit lebar hanya mengecilkan dua Anima karena Seeker memakai back lane
terpisah. Posisi X memakai tepi piksel opak dengan margin 5,5%, bukan tengah
sel transparan. Lebar jendela tidak mengubah skala, dan
ruang vertikal ekstra tidak membesarkan karakter. Sheet Boss 3×3 1024 dibuka per sel penuh (341 px)
di client supaya kaki Seeker tidak terpotong oleh capture 300 px. Tinggi
visual tidak mengubah combat power.

Referensi monster-handler hanya menjadi bahasa genre: anime ekspresif, siluet
kuat, outfit dan prop bertema, serta gesture command yang jelas. Prompt dan
review menolak karakter, kostum, device, logo, komposisi, atau istilah khas
Pokémon, Digimon, dan IP lain.

## 5. Trophy dan announcement

First clear memberi satu Trophy unik per chapter. Seeker Profile menampilkan
tiga Featured Trophy; koleksi lengkap tetap dapat dibuka terpisah. Trophy tidak
dicabut ketika chapter direvisi atau di-unpublish.

Secara visual semua Trophy memakai sistem dua lapis **Chapter Core v3**. Chapter
menyediakan satu Inner Core dengan perimeter, internal construction, dan palet
empat–lima warna yang khas; motif membentuk Core secara utuh, bukan emblem acak
yang ditempel pada gem generik. Chapter Factory lalu mengecilkan Inner Core dan
membungkusnya dengan canonical transparent RGBA
`point_hex_vessel_v1`: point-top hexagon sederhana dengan enam facet besar dan
satu highlight. Vessel, skala final, dan contour identik piksel demi piksel
lintas chapter; bentuk Inner Core di dalamnya bebas beragam selama muat di safe
window dan terbaca kecil. Inspirasi benda nyata boleh diabstraksi, tetapi Inner
Core tidak menggambar container, pedestal, miniature scene, badge/medal, glow,
atau transparency sendiri. Nama
player-facing berakhir `Core`, sementara wire/database tetap menyebut reward
ini `trophy`.

Setelah chapter baru aktif:

- Home menampilkan popup satu kali per akun, setelah modal auth/update/onboarding.
- Badge **New** bertahan pada Battle/Expedition sampai detail chapter dibuka.
- Receipt `home_popup_seen_at` dan `chapter_opened_at` disimpan server-side agar
  konsisten lintas device.
- Jika beberapa release terlewat, Home menampilkan satu ringkasan gabungan.
- Push OS bersifat opt-in dan best-effort; in-app announcement tetap otoritatif.
- Push membawa chapter ID/version saja. Client selalu mengambil manifest terbaru
  dari server setelah dibuka.

## 6. Reliability dan security

Setiap mutation membawa:

- `idempotency_key`
- `expected_version`
- `expected_turn` untuk combat

Postgres memegang row lock sebelum memvalidasi state transition. Satu active
combat encounter per owner mencegah Duel/Team/Expedition berjalan bersamaan,
tetapi run Expedition boleh disimpan di antara node saat pemain memakai mode
lain.

Anima yang terikat active zone/encounter tidak boleh dihapus. Defense snapshot
yang kehilangan sumber art dinonaktifkan dari candidate pool. Chapter version
yang masih dipakai active run tidak boleh dibersihkan.

RLS aktif pada seluruh row pemain. RPC yang mengubah Energy, Bits, EXP, Tokens,
checkpoint, atau Trophy dicabut dari `public`, `anon`, dan `authenticated`, lalu
hanya diberikan ke `service_role`.

## 7. Chapter manifest

Manifest v1 memuat:

- identity, sequence, content version, minimum client build,
- localized chapter/zone/copy data,
- node pools, legal directed connections, dan `bits_reward` per zona,
- Regular/Elite/Boss snapshots,
- Boss Seeker pose regions dan dialogue map,
- Trophy metadata,
- immutable asset paths + hashes,
- prompt/model version dan QA summary.

Content version 2 menambah `body_height_cm` pada seluruh cast dan Boss Seeker,
`render_metrics` pada manifest sheet, serta `boss.ace_passive`. Ini content
version, bukan schema/effect bebas: run yang sudah dimulai tetap terkunci pada
version lamanya dan v1 tidak pernah ditimpa.

Client menolak schema version atau effect type yang tidak dikenalnya. Publisher
menulis draft inactive, memverifikasi seluruh hash/asset/schema, lalu
mengaktifkan version secara atomik.

## 8. Chapter Factory

Input-nya satu theme brief terversi. Pipeline:

1. `brief.json` tervalidasi menjadi `design.json`; perintah `design` default hanya
   preview dan baru memanggil model dengan paid/apply/acknowledgement eksplisit;
2. schema/game-rule/IP validation gagal tertutup sebelum image spend;
3. CLI menampilkan jumlah call dan cost ceiling;
4. aset berasal dari salah satu jalur: explicit paid flag menghasilkan 9 Anima
   sheets, 3 zone art, 1 Boss Seeker sheet, dan 1 Trophy lewat Replicate; atau
   operator membuat 14 PNG factory-native di ChatGPT lalu menyerahkannya lewat
   `manual_inbox/` sesuai [runbook manual](10-manual-chapter-assets.md);
5. post-process, slicing, hash, thumbnail, dan manifest;
6. HTML contact sheet untuk review cast, stat, pose, dialogue, dan map;
7. selective regeneration per slot, tanpa image auto-retry;
8. approval bernama dari reviewer manusia mengunci manifest dan seluruh hash;
9. `publish` upload-if-absent, membaca ulang bytes CDN, lalu staging inactive;
10. `activate` menukar satu active version secara atomik;
11. `notify` default preview; apply memerlukan kalimat konfirmasi persis, claim
    database satu kali, lalu satu FCM topic send untuk perangkat opt-in.

Design call dan setiap image call—termasuk call gagal setelah request
diterima—masuk `cost.ledger.json`. Output mentah disimpan sebelum post-process,
jadi kegagalan slicing dapat diperbaiki tanpa generation baru. Upload parsial
dibersihkan bila kegagalan pasti terjadi sebelum staging. Kegagalan jaringan
yang hasilnya ambigu ditandai **uncertain** dan tidak di-retry otomatis, baik
untuk staging maupun push, agar version atau notifikasi tidak tergandakan.

Jalur manual tidak mengarang prediction ID atau biaya Replicate: bytes mentah,
provider, operator, waktu, hash, serta riwayat regenerate dicatat sebagai
provenance terpisah. Kedua jalur bertemu sebelum post-process dan memakai
validation, review, approval, publish, activation, serta notification gate yang
sama.

Tidak ada endpoint player yang dapat memanggil pipeline ini. Prompt, brief,
approved manifest, approval ledger, cost ledger, activation/push receipt, dan
hashes disimpan di Git; binary immutable disimpan di Storage.

## 9. Rollout dan definition of done

**The Sugarworks v3** adalah version aktif; v1/v2 tetap immutable untuk run lama.
V3 mengkalibrasi ulang tinggi sembilan Anima berdasarkan stance vertikal, bukan
panjang atau luas silhouette, serta membetulkan bbox opak The Confectioner.
Fudge Fang sekarang 135 cm, Cotton 130 cm, dan The Confectioner 156 cm dengan
reference metrics 158×282 px. Dialog kontekstual, Cotton sebagai ace terakhir,
dan Final Confection dari v2 tetap dipertahankan. Seluruh asset berasal dari raw
yang sudah disetujui dan direprocess tanpa model call. `feature_expedition` dan `feature_chapter_push` aktif. Team Battle juga aktif
dengan `feature_team_battle=true` untuk device playtest Godot. Jalur announcement
in-app sudah aktif; push OS pertama masih menunggu konfigurasi FCM sehingga
belum terkirim.

**The Sugarworks v4** masih draft lokal: zona Battle memakai backdrop manual
baru dan tinggi presentasi The Confectioner dinaikkan menjadi 165 cm. V3 tetap
authoritative sampai v4 di-review, di-approve, dipublish, dan diaktifkan.

Untuk chapter atau mode berikutnya, sebelum aktivasi:

- shared combat selftest lulus,
- SQL ownership/RLS/idempotency/concurrency/reward lulus,
- Godot builder/arena/map/replay/reduced-motion/i18n lulus,
- placeholder chapter berjalan tanpa model call,
- Chapter Factory menolak publish tanpa approval,
- Boss Seeker terbaca dan tidak menutup HUD pada perangkat target,
- push accept/deny/background/killed/fallback diuji di Android dan iOS nyata.

