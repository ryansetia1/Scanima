# CLAUDE.md — konteks untuk AI coding agent

Baca file ini sebelum menyentuh kode Scanima. Update file ini setiap ada perubahan signifikan pada stack, konvensi, atau keputusan arsitektur.

Hotfix forced Switch: auto-summon anggota hidup terakhir wajib di-defer sampai
controller menyimpan encounter authoritative dan melepas `_busy`. Memancarkan
`action_requested("switch")` dari dalam `play_events()` membuat controller
membuang request karena turn sebelumnya masih commit.

Turn Battle sekarang **local-first**: client menyimulasikan turn dengan aturan
yang identik lalu menganimasikannya sementara request-nya terbang, dan hasil
server tetap yang tersimpan. Care dan Shop optimistis dengan rollback tanpa
meredupkan dock/sheet-nya, Summon menyembunyikan round trip-nya di balik dissolve
dan charge portal, Home digambar dari `user://boot_cache.json` sebelum jaringan
menjawab, dan commit turn mengulang sendiri saat transport gagal. Detail, pagar
parity, dan daftar jalur yang sengaja tetap menunggu server ada di
[`docs/12-local-first-turns.md`](docs/12-local-first-turns.md).

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

## Aturan yang tidak bisa dinegosiasikan

1. **API key tidak pernah masuk ke build Godot.** Hanya ada satu, `REPLICATE_API_TOKEN`, dan ia hanya hidup di Supabase Edge Function secrets. Client Godot bicara ke Edge Function, bukan ke Replicate. Satu-satunya pengecualian adalah mode BYOK di mana token milik pemain sendiri disimpan lokal di device.
2. **Setiap panggilan image generation tetap dipagari sebagai biaya ~\$0.07.** Default-nya GPT Image 2 medium. Snapshot Replicate 13 Agustus 2026 mencantumkan auto $0.128, low $0.012, medium $0.047, dan high $0.128 per output image; generation medium terbaru terukur sekitar $0.05 per sheet, sementara dua run lama $0.068 dan $0.072. `pricing.mjs` sengaja tetap memakai $0.07 untuk spend cap konservatif sampai sampel production berulang membenarkan perubahan. Jangan pernah menulis kode yang bisa memanggil generation dalam loop, retry otomatis tanpa batas, atau tanpa idempotency key. Kalau ragu, jangan panggil.
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
- Lima autoload, urutannya wajib: `SecureStore` (Keystore/Keychain), `GameState` (preference + pending intent), `Backend` (transport HTTP), `LocaleManager`, lalu `AuthFlow` (PKCE/deep link). Refresh/access token tidak lagi hidup di `state.json`; file itu hanya UID, preference, pilihan Anima, dan pending intent. `Backend` menulis sesi ke `GameState`, `GameState` tidak pernah memanggil `Backend`. Yang mengorkestrasi tetap scene: `await Backend.ensure_session()`.
- Entry point-nya `scenes/scan_flow.tscn`: satu shell persisten yang meng-instance lima child scene `home_view`, `scan_view`, `battle_view`, `collection_view`, dan `anima_details_view`, plus `bottom_nav`. Urutan tab Home, Scan, Battle, Collection, Anima; seluruh tombol memakai ikon di atas label supaya lima target 96px muat. Tab tidak memakai `change_scene_to_file()`, supaya request, pending scan/care/battle, Stage, dan inkubator tidak di-reset saat pemain berpindah layar. `scenes/anima_demo.tscn` tetap alat periksa art yang dipanggil eksplisit.
- `Backend.gd` satu-satunya tempat yang tahu URL project dan kunci. Kuncinya **publishable** (`sb_publishable_...`) dan memang ikut ke dalam build; yang membatasi akses RLS, bukan kerahasiaannya. Terukur diterima endpoint yang dipakai client: `auth/signup`, `auth/token`, identity authorize/link, REST, Storage, dan `functions/v1` (`create_anima`, `care_anima`, `battle_anima`, `shop`, `seeker`, `gallery`). Yang tidak boleh masuk ke sana sampai kapan pun: `REPLICATE_API_TOKEN` atau service role key.
- Yang persist hanya sesi aman, `pending_oauth`, scan yang sedang berjalan, satu `pending_care`, satu `pending_battle` berisi session/turn/version + intent + idempotency key, dan satu `pending_purchase`. Saldo, kebutuhan, tas, profil Seeker, dan daftar Anima **selalu** dibaca ulang dari Postgres — server yang berwenang. Pending intent dihapus hanya setelah server menjawab; timeout/restart me-replay key yang sama supaya Bits, damage, reward, atau grant Google tidak commit dua kali.

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
- **Sugarworks v6 sekarang aktif.** Version `ae9cd74f-a32d-4a99-a1f8-19681ecbe54b`, manifest `a28aee4e9d5d5bc37a21fcd5ba6e2a4e64cc59e4dd132468efa8c2a259250384`; v1–v5 tetap immutable untuk run lama. V6 adalah metadata-only successor yang mengganti sembilan display name menjadi Gellume, Velastra, Noxcoil, Cindrusk, Rimespin, Pralith, Duskadon, Ambermire, dan Nimbelisk. `brief.asset_source_version=5` membuat Factory mereferensikan 14 byte aset v5 yang sudah ada, jadi publish lewat Supabase MCP tidak menduplikasi PNG atau memanggil model. Probe production memastikan v6 aktif, v5 inactive, 14/14 Storage object tersedia, dan sembilan Atlas form membawa nama baru. V5 (`b85a350c-7eba-4ad3-8e94-bfd8441aeb0c`) tetap predecessor Zone Bits 10/20/30.
- Migration Battle `20260813103446_battle_vertical_slice`, indeks bot `20260813105258_index_battle_bot_anima`, cap reward `20260813174007_limit_daily_battle_rewards`, indeks unik ledger `20260813174454_index_battle_reward_ledger_ref`, perbaikan status `20260813180241_refine_battle_reward_status`, guard Energy `20260813193612_require_battle_energy`, decay realtime + biaya Energy Battle `20260813195613_decay_realtime_and_battle_energy`, EXP/Level tanpa Bond `20260813201820_exp_level_growth`, gerbang Feed/Clean penuh `20260813220036_reject_full_feed_clean`, dan tidur Anima yang tidak di-Summon `20260813220954_bench_unsummoned_sleep` + `20260813221113_apply_care_bench_summon` + Energy bangku 3 jam `20260813224221_bench_sleep_faster` + gerbang Hunger Battle `20260814043053_reject_hungry_battle` (sudah di-drop: lapar tidak mengunci Bits) + reset hari sipil lokal `20260814064443_local_day_reset` + `20260814064550_local_day_reset_status` + `20260814064614_local_day_reset_care` sudah live. Lapar tidak mengunci Battle: `20260814101323_allow_hungry_battle`. Clean gratis: `20260814104237_free_clean`. Shop live: `20260814082442_shop_inventory_bits` + `20260814082512_shop_inventory_rpcs` + `20260814082545_shop_apply_care` + `20260814082612_shop_battle_rewards` + `20260814082658_shop_commit_battle_turn`. Guest Seeker/Google live lewat `20260814153135_seeker_google_accounts`; guard guest sebelum Vision lewat `20260814172154_guard_guest_scan_before_vision`. Capture/private art live lewat `20260814215746_capture_foundations`; Gallery lewat `20260814215801_gallery`. Tinggi kanonis live lewat `20260815214409_anima_body_height`; kalibrasi tinggi/metrics lewat `20260815225656_recalibrate_anima_heights_and_metrics`; prompt production v18 lewat `20260815225859_prompt_version_v18`. Tinggi Veridian 150 cm lewat `20260815234322_lower_veridian_height`. Starter lifetime 4 + Care rebalance live lewat `20260816074701_starter_four_and_care_rebalance`. Floor bangku / well_cared aktif-only live lewat `20260816082652_bench_care_safe_rest`. Tiered EXP, reward Battle berskala, cap Sleep harian, dan budget Expedition 30 live lewat `20260816200507_tiered_exp_and_battle_rewards`. Lawan Duel sistem live lewat `20260817072847_system_duel_opponents`. `shop` version 4, `care_anima` version 9, `battle_anima` version 26, `create_anima` version 22, `seeker` version 5, `replicate_webhook` version 10, `gallery` version 2, `team_battle` version 8, dan `expedition` version 16 ACTIVE; semua kecuali webhook memakai `verify_jwt=true`. `create_anima` membundel seluruh versi lokal; `app_config.prompt_version = "v31"` production, v20 rollback capture tanpa Vibe, v19 rollback gate, v18 rollback kebijakan tinggi handheld, v17 rollback kebijakan tinggi awal, v15 rollback art, dan v13 rollback kontrak capture. Tujuh Anima ready production sudah dibackfill `body_height_cm` dan `render_metrics` hasil ukur sheet privat. Enam Anima ready legacy sudah dipindahkan ke `anima_sheets`, diretype v2, dan bucket `sheets` dibuat privat. `apply_care()` menolak Hunger/Hygiene >= 99.5 dengan `NEED_FULL`. `Summon` menulis `profiles.active_anima_id` dan menidurkan sisanya. `care_anima` menyimpan `timezone_offset_minutes` lewat `set_profile_timezone` sebelum RPC; snapshot player/bot membawa `level` dari `care_score`, `body_height_cm`, plus `strike_name`/`surge_name`, dan `createFighter` memakai growth multiplier. Error boundary tetap membaca `message` dari object PostgREST, bukan hanya instance `Error`; tanpa itu exception RPC yang dikenal jatuh menjadi 500 generik. Probe SQL production membuktikan win ketiga dibayar dan win keempat menjadi Training tanpa satu pun mutation progression.
- **Team Battle live untuk device playtest.** Migrasi `20260815002835_team_expedition_feature_flags` + `20260815003600_team_battle_vertical_slice` + `20260815003700_team_battle_roster_rpcs` + `20260815003736_team_battle_session_rpcs` + `20260815003846_team_battle_commit_turn` sudah tercatat remote; Edge Function `team_battle` version 7 ACTIVE dengan `verify_jwt=true`, dan `feature_team_battle=true`. Builder Team/Defense tepat 4, Defense opt-in, tiga rival atau fallback system, switch sukarela/forced, replay lintas restart, Energy 10×4, EXP berskala dari rata-rata Level roster lawan dengan pembagian active `ceil(full/2)`, bench `ceil(full/4)`, KO 0, receipt resume, cap 2 win + 40 Bits, dan mutex lintas Duel sudah tertutup oleh SQL production test. Builder Team Battle dan Expedition memakai thumbnail cache pose needs saat ini (Idle/Hungry/Dirty/Sleep/Dormant), menulis Ready/Low Energy/Dormant secara eksplisit, mempertahankan art/text saat card dipilih, toggle multi-select lewat tap (bukan Ctrl), checklist kanan atas, cursor dan hover ItemList transparan supaya isi card tidak tertutup dan band hover tidak tertinggal setelah jari diangkat, header chevron Back, dan tombol Team/Expedition di lobby Duel langsung aktif dari last-known flag (default on) tanpa menunggu RPC; hanya FEATURE_DISABLED yang mengunci. Smoke tanpa JWT menjawab 401. Flag sengaja dinyalakan atas permintaan operator untuk pengujian Godot; matikan kembali bila device playtest menemukan blocker.
- **Recovery Team Battle stale bersifat self-healing.** Session lokal yang ditolak server sebagai `INVALID_SESSION_ID` atau `TEAM_BATTLE_NOT_FOUND` wajib dibuang lalu hub dimuat ulang. Mode demo Team/Boss tidak boleh mengirim action ke controller production atau menyimpan ID seperti `boss-demo`; sebelumnya state demo itu membuat Team Battle selalu gagal 400 walau Expedition hanya berada di checkpoint.
- **Expedition/announcement/Chapter Factory sudah live.** The Sugarworks v1 (`version_id=2801303d-96bc-4d83-98ae-2f5d1eeca48b`, manifest `309be7018291047b25512e62aff9d020d0966356098ba70e3bf37c065b05d7f8`) adalah version historis pertama; v6 aktif dicatat di atas dan v2–v5 tetap immutable. Ketiga rollout flag production sekarang true: `feature_team_battle`, `feature_expedition`, dan `feature_chapter_push`. Edge Function `expedition` version 15 ACTIVE dengan `verify_jwt=true`. Migrasi KO EXP `20260815191450_deny_ko_party_exp` + `20260815191543_deny_ko_party_exp_rpcs` + `20260815191702_deny_ko_team_battle_exp_rpcs` sudah live: `party_member_reward_exp` memberi 0 ke anggota HP ≤ 0, lalu `commit_expedition_turn` / `commit_team_battle_turn` memakainya. Migration `20260816171515_battle_exp_reward_payloads` memulihkan `last_reward.anima_exp` Team/Expedition dari receipt turn saat resume. Version 11 membuang cast `special` dari node Battle/Elite tanpa mengubah manifest immutable; Boss tetap mempertahankan ace final. Version 12 mencegah AI memilih reserve ace sebagai switch sukarela ketika reguler aktif low-HP masih hidup, sehingga jalur itu tidak lagi gagal `INVALID_SWITCH_SLOT`; forced switch sesudah KO tetap `final_ace → switch → ace_passive`. Version 13 membundel helper Level tiered; payout Expedition memakai rata-rata Level lawan, budget 30 EXP roster per hari, dan bypass Boss sekali per run. Version 3 membawa overlay Level live di zona yang sama (party_state hanya HP + boost; naik Level menambah sisa HP sebesar delta max HP, KO tetap 0). Lawan chapter memakai `anima_id` slug (`sugarworks-gumdrop`), bukan UUID pemain; `start_expedition_encounter` / `commit_expedition_turn` membandingkannya sebagai text lewat `expedition_roster_ids` (`20260815115431_expedition_chapter_opponent_ids` + `20260815115549_expedition_chapter_opponent_compare`). Jangan `::uuid` opponent `anima_id` — itu 400 setiap Battle node dan client menampilkan `EXPEDITION_ERROR_GENERIC`. `prepareExpeditionRoster` tidak boleh memakai `base_stats.hp` sebagai current/max HP Battle: itu membuat encounter pertama 65/295. HP penuh di `createTeamParty` kecuali party_state sudah menyimpan sisa HP Battle dari node sebelumnya. `party_state` hanya overlay HP dan boost zona; Level live dari `care_score` dipakai di encounter berikutnya di zona yang sama, dan naik Level menambah sisa HP sebesar delta max HP (KO tetap 0). Hasil menang menampilkan EXP per anggota plus siapa yang naik Level. `generateZoneMap` menyalin `background_path` zona; `withFreshExpeditionArt` mengisi `arena_background_url` supaya arena menampilkan art zona. In-app popup/badge berasal dari chapter aktif dan tetap authoritative. Push OS belum terkirim: `notify --apply` berhenti aman sebelum DB claim dengan `FCM_PUSH_ENV_MISSING`, karena `FCM_PROJECT_ID`/`FCM_ACCESS_TOKEN` dan konfigurasi Firebase app belum tersedia; jangan retry sampai kredensial FCM ada. The Sugarworks memakai sembilan Anima manual, tiga zona manual, serta Boss/Trophy Replicate. Fudge membersihkan satu detached Attack fragment 25px dan Cotton dua fragment 59px+19px dari sel Idle melalui opt-in deterministic `remove_detached_idle_components_v1`; raw tetap utuh dan keputusan reviewer tercatat. Chapter Factory membaca `brief.json` + `design.json`; approval bernama, immutable publish, verify CDN, activation atomik, dan push DB claim satu-kali tetap wajib untuk chapter berikutnya.
- **Boss Seeker runtime sudah lengkap, bukan intro-only.** `withFreshExpeditionArt` menempel `boss_seeker` (nama, dialogue, `body_height_cm`, poses, `sheet_path`/`sheet_url`, pose manifest) pada `run` dan encounter, plus `zone_attempt` untuk rematch. Client memuat sheet lewat `BossSeekerSheet` (bukan `AnimaLoader`). Opening `boss_intro`/`rematch` menampilkan Seeker saja tanpa overlay gelap, lalu pose command dan Summon Anima lawan sebelum input nyala; sesudah itu Seeker di belakang Anima kecuali Anima itu lebih tinggi dari 60% tinggi Seeker (maka Anima pindah ke belakang), di-clamp di dalam stage, cut-in pada command, dan dialog tap-to-continue. Layer default background/portal `z=0` < Boss Seeker `z=1` < Anima lawan `z=2` < Anima pemain `z=3`; `z=-1` menyembunyikan Seeker di belakang art zona. Anima raksasa (tampilan > 60% tinggi Seeker) memakai `FighterLayer` supaya Seeker bisa maju ke depan. Budget per encounter: `chapter_intro` sekali per run, opening `boss_intro`/`rematch`, maksimal satu command dialogue dari Attack/Special/Switch, `last_anima` wajib hanya dari event authoritative `final_ace`, lalu `victory`/`defeat` dengan pose terbalik (pemain menang → pose `defeat` + line `victory`). Pose command tetap dimainkan walau line sudah habis; urutan wajib pose → dialog opsional → event plate → animasi → idle. Trigger lama saat pemain tinggal satu sudah dihapus. Replay event tidak mengulang line. Sesudah baris terakhir itu ditutup, `_present_boss_result()` menyelipkan reveal Trophy first-clear di dialog yang sama — nama Core sebagai judul, art Core sebagai portrait — baru `_show_result()`. `play_events()` menahan `set_busy(false)` lewat `_boss_result_settled` sampai kedua dialog habis, supaya banner/modal Level Up tidak muncul di belakangnya; `_boss_result_pending` mencegah `set_session` kedua menutup dialog yang sedang ditunggu. Art Trophy diunduh sekali oleh `ExpeditionController._attach_trophy_art()` dari `reward.trophy.art_path` + `asset_base_url` dan dititipkan ke art cache sebagai `"trophy"`. Payload Seeker yang masuk sejak version 12 tetap dibundel di `expedition` version 15 ACTIVE; client fallback `asset_base_url + sheet_path` hanya untuk response lama.
- **Ace Boss server-authoritative.** Hanya encounter `kind=boss` yang menahan tepat satu cast `special`; starter dan switch memakai reguler sampai seluruhnya KO. Event terakhir selalu `final_ace → switch → ace_passive`. Allowlist passive: `bonus_pp`, bounded `stat_boost`, atau `one_hit_shield`; state `ace_passive_applied` mencegah replay menggandakan efek. Chapter validator menolak roster bukan empat, jumlah ace bukan satu, ace lebih lemah dari reguler, atau passive di luar allowlist. Opsi future yang belum live: ace-exclusive move (butuh action/VFX/schema) dan full Boss phase (butuh phase state, transition, reset/reward policy, dan UI).
- **Skala Battle memakai tinggi kanonis, bukan ukuran PNG.** `animas.body_height_cm` integer 20–2000 adalah server-authoritative; Vision v19 wajib memilihnya dari anchor skala nyata, floor boneka gendong ~50 cm untuk benda genggam kecil, dan exaggeration hanya ketika silhouette memang towering/massive. Manifest post-process membawa `render_metrics.reference_height_px/reference_width_px` dari bbox opak yang benar-benar terlihat di region Idle/Intro Idle. `BattleScale.shared_scales()` menghitung kurva non-linear per tubuh dari kartu desain 720×800; lebar layar tidak mengubah rasio tubuh. Tinggi *tampilan* Anima dijepit 300 cm (`ANIMA_VISUAL_HEIGHT_CAP_CM`) — 20 m tetap dibandingkan sebagai ~3 m. Boss Seeker tetap di kurva 720×800; Anima di sampingnya linear ke tinggi Seeker (3 m ≈ 1,8× Seeker 165 cm). `_match_anima_opaque_to_seeker` memakai `shared_scales`, bukan `_seeker.scale` sebelum `set_layout`. Bbox in-game adalah piksel opak (alpha ≥ 0,12), bukan sel kotak slicing. Setelah skala tubuh ditentukan, `FighterLayer`/`DuelFighterLayer` mendapat satu zoom kamera seragam: petarung kecil mendekat, petarung besar menjauh, lalu gabungan bbox opak dipasang penuh di arena dengan margin 5%. Karena zoom seragam, perbandingan tinggi tidak berubah dan dua Anima 20 m tetap sama-sama terbaca 3 m relatif terhadap Seeker, tetapi Seeker ikut terlihat lebih kecil. Art zona chapter ikut zoom dari pusat agar latar mengikuti framing. Anima yang tinggi tampilannya > 60% tinggi Seeker (`SEEKER_OVERLAP_RATIO`) pindah ke layer belakang; default tetap pemain di depan lawan di depan Seeker. Layer z hidup di `FighterLayer` (Node2D sibling anchors + Seeker), bukan di sprite di dalam Control — `z_as_relative = false` pada sprite Anima menaruhnya di depan Seeker. Tujuh Anima production punya metrics opak hasil ukur sheet privat serta backfill matang: Mugshots 90, Hydron 180, Deckon 95, Playtron 50, Veridian 150, klasik 90, Sunhound 75 cm. Kaki opak duduk di garis tanah 91%, Boss Seeker 3×3 1024 membuka sel penuh 341 px supaya kaki tidak terpotong oleh capture 300 px, dan padding transparan tidak masuk perhitungan kamera. Tinggi visual tidak masuk combat power. Riset pembanding cara Pokémon 2019–2025 menangani ukuran karakter, beserta alasan eksperimen 20 m linear ditinggalkan, ada di [`docs/pokemon-size-research.html`](docs/pokemon-size-research.html); itu catatan desain, bukan spek yang mengikat.
- **Framing kamera Battle mengikuti tinggi Anima.** Art zona chapter memakai Anima tertinggi untuk zoom: pasangan normal memperbesar latar sampai 1,55×, sedangkan Anima di cap 3 m memperlihatkan framing latar terluas. Backdrop mempertahankan crop raw 16:9 sampai maksimum 2048 px; runtime image membuat mipmap dan `TeamArenaBackground` memakai `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`. Shader `battle_background_dof.gdshader` mengambil satu mip LOD per piksel—far band lebih blur, lantai dekat lebih tajam—serta menurunkan saturation/brightness tipis; jangan ganti dengan Gaussian multi-tap tanpa profiling mobile. TextureRect dihitung manual sebagai cover lalu dipan horizontal dari hash ID encounter (margin 4%): battle berbeda mendapat potongan kiri/tengah/kanan berbeda, tetapi turn replay/resume session yang sama tidak melompat. Sesudah camera zoom selesai, pusat tubuh opak Boss Seeker dipin ke sisi kanan dengan margin 2,5% supaya ia terbaca berdiri di belakang posisi Anima lawan, bukan maju ke tengah arena. Switch Team/Expedition menghitung ulang seluruh layout segera setelah art anggota baru dipasang dalam keadaan tersembunyi, lalu men-tween `FighterLayer`, anchor, Seeker, shadow, dan backdrop selama 0,32 detik bersamaan dengan charge portal; jangan menunda reframe sampai event Attack atau `set_session()` akhir.
- **Biaya masuk Expedition sekali per chapter sudah live.** Migrasi `20260815182234_expedition_entry_energy` memindahkan debit menjadi 30 Energy × 4 di `start_expedition_run`, menghapus seluruh gate/debit Energy dari `start_expedition_zone`, dan mengunci roster pada status `checkpoint` maupun `active`. Run checkpoint lama tidak ditagih retroaktif. Probe SQL production membuktikan gagal satu anggota rollback atomik, replay tidak mendebit ulang, Start Zone tetap berhasil pada Energy 0, dan RPC tetap service-role-only. Edge Function tidak perlu dideploy ulang karena aturan authoritative seluruhnya hidup di RPC.
- **Zone Bits dan route tree Expedition sudah live.** Migrasi `20260816133107_expedition_zone_bits_and_routes` menyimpan `visited_node_ids`, receipt unik `(run_id, zone)`, dan ledger `expedition_zone`; profile row lock + batas hari sipil lokal menjaga cap lintas replay, run, dan content version dalam stable chapter yang sama. Jadwal berasal dari `zones[].bits_reward`: Sugarworks v5/v6 memberi 10/20/30 Bits dengan cap 60/chapter/hari, sedangkan run yang terkunci ke v1–v4 tanpa field tetap nol. Bonus first-clear 25 Bits tetap terpisah. Payload run membawa `daily_bits` dan `last_zone_reward`; client me-refresh saldo sesudah payout. Peta node sekarang route tree bercabang dengan ikon per jenis, state visited/reachable/locked, edge preview, target sentuh 96 px, dan alur tap node → preview → **Enter Node** sebelum RPC. Label status per-node dan hint tap berulang sengaja tidak tampil: brightness, disabled state, focus border, dan edge menyampaikan availability. Active map menyembunyikan subtitle, merangkum status run dalam satu baris, menyembunyikan HP tim saat penuh, hanya menampilkan ringkasan saat ada yang terluka, serta memakai surface gelap opak agar ambient ring shell tidak mengganggu jalur. Baris preview kosong tetap mengambil satu tinggi label supaya memilih node tidak mengubah viewport atau scroll map; ikon node terpilih memakai warna on-primary gelap yang sama dengan label. Preview cyan hanya menyorot edge dari node terpilih ke depan. Edge yang masuk maupun jalur yang sudah selesai memakai garis putus-putus redup, bukan highlight emas yang terlihat tertinggal.
- **Trail Shop boleh dilewati.** Migrasi `20260816154003_allow_expedition_shop_skip` membuat **Skip Shop** maju tanpa item, Tokens, boost, atau perubahan HP. Reserved wire choice `shop-skip` hanya sah pada pending node `shop`; Edge Function mengirim state no-op dan RPC memverifikasi state itu identik dengan state authoritative. Refresh yang sudah dibayar tidak direfund ketika Shop dilewati.
- **Checkpoint Expedition mempertahankan HP antar-zona.** Migrasi `20260816165646_expedition_checkpoint_choice` menandai checkpoint sesudah Zona 1/2 dan mewajibkan choice service-role-only yang idempoten sebelum `start_expedition_zone`. **Recover** menambah 50% max HP semua anggota dan membangunkan KO pada 50%; **Power Up** mempertahankan HP dan memberi +10% Attack/Guard/Speed hanya untuk zona berikutnya. `prepareExpeditionZoneRoster()` membuang `base_stats` checkpoint lama, menerapkan ulang boost run, lalu membakar boost sementara ke snapshot zona supaya tidak bocor ke zona selanjutnya. Zona 1 tetap mulai penuh. UI choice memakai panel existing dan Abandon selalu lewat `UiModal` destruktif yang menjelaskan progress/Tokens/boost hilang, Energy masuk tidak direfund, reward authoritative tetap aman, dan run baru membuat route baru. Probe production membuktikan dua kolom + trigger ada, nol checkpoint antar-zona lolos tanpa choice, `authenticated` tidak dapat mengeksekusi RPC, dan `service_role` dapat; `quota_rules.sql` remote lulus.
- **Aset chapter boleh dibuat lewat Replicate atau manual di ChatGPT.** Runbook copy-paste prompt, 14 nama file factory-native, checklist, dan folder handoff ada di [docs/10](docs/10-manual-chapter-assets.md). Hasil manual masuk `backend/chapters/<slug>/v<version>/manual_inbox/`, tidak langsung ke `assets/`; raw dipertahankan. `chapter_factory.mjs ingest-manual` default preview memeriksa PNG, menjalankan post-process canonical, dan melaporkan semua slot tanpa menulis; `--apply` all-or-nothing untuk slot pilihan, menyimpan hash-stable PNG, rebuild manifest/review, serta mencatat provider/operator/input+output hash/riwayat regenerate sebagai provenance `manual_chatgpt` tanpa prediction ID atau cost Replicate. `assetMode()` menganggap campuran Replicate + manual production hanya saat semua 14 slot tercatat, dan publish/activate mencocokkan setiap provenance output hash ke manifest. Kedua jalur memakai approval/publish gate yang sama.
- **Art zona adalah backdrop Battle, bukan peta node.** Prompt Replicate (`zone_art.md`) dan runbook manual memakai kontrak yang sama: establishing shot environment anime hand-painted yang cocok dengan Anima/Boss Seeker, 6–9 kelompok warna harmonis, dua value/shadow step, detail material selektif, langit terbuka di 40–45% atas, dan lantai padat kontinu hanya di 22–26% bawah tanpa cairan/rel/jurang di bawah kaki. Komposisi harus bervariasi antar-zona—asimetris, depth-centered dengan framing tidak sama, atau diagonal—bukan selalu satu hero object di tengah maupun selalu offset dengan rumus yang sama. Tema masuk lewat material/konstruksi, bukan literal candy raksasa atau toy diorama. Kaki petarung duduk dekat 88% tinggi stage; layar tinggi mencrop sisi kiri/kanan; Boss Seeker mengisi pita kanan. `review.html` menampilkan crop arena plus garis kaki sebagai gate visual. Jangan kembali ke wording "route-like lanes" atau "readable path lanes".
- **Boss Seeker memakai art direction silhouette-first, bukan generic glossy anime.** Template otomatis dan runbook manual mengunci satu dominant outfit geometry, satu intentional asymmetry, maksimal dua motif tema, nol/satu command prop, empat–enam warna flat, satu hard cel-shadow, serta umur/build/wajah/postur yang spesifik. Umur, tinggi, body build, face, posture, outfit archetype, dan gesture language harus bervariasi antar-chapter—jangan default semua boss menjadi young slim fashionable character. Cells 1–8 selalu memakai angle three-quarter forward-left yang sama tanpa yaw/mirror; cell 9 `profile` mempertahankan angle head/neck/nose/shoulder yang sama, tetapi kedua pupil menatap player untuk dialog. Nose tetap off-center dan shoulder tetap diagonal—bukan side profile atau front-facing passport portrait. Theme masuk lewat shape language, bukan tempelan dekorasi; gradient, glow, glossy material, random straps/buckles/piping, symmetrical generic long coat, dan tiny repeated ornaments dilarang. Referensi franchise boleh dianalisis menjadi prinsip abstrak, tetapi nama/gambar/karakter/kostum/komposisinya tidak masuk prompt atau image input. The Confectioner adalah 23-year-old short compact Confection Archive Curator dengan ivory bell coat-dress, empat folded-wrapper panels, asymmetric shoulder cape, dan octagonal recipe folio; whisk/baton/kitchen-tool prop serta desain Graphic Commandant lama sudah ditolak.
- **Trophy visual memakai sistem dua lapis `chapter_core_v3`.** Image model/manual handoff hanya membuat Inner Core chapter-specific yang muat dalam central hexagonal safe window: silhouette luarnya bebas beragam tetapi terbaca solid black, palet 4–5 warna, 6–10 region besar, serta perimeter+internal construction tematik—bukan emblem/letter tempel. Chapter Factory chroma-keys dan mengecilkan Inner Core agar sisi terpanjang maksimal 285px, lalu menaruh canonical transparent RGBA overlay `point_hex_vessel_v1` di atasnya. Vessel adalah point-top hexagon netral dengan enam facet besar dan satu highlight; contour serta final scale identik piksel demi piksel antar-chapter, sementara Inner Core membawa seluruh identitas chapter. Source overlay hidup di `backend/tools/chapter_factory/static/point-hex-vessel.png`, digambar deterministik oleh `generate_chapter_core_vessel.mjs`, dan `npm run selftest` menolak file stale. `reprocess-trophy --apply` membangun ulang final PNG dari `raw/trophy.png` tanpa model call serta mempertahankan prediction provenance. Display name berakhir `Core`; wire/database tetap `trophy`. Fixed `chapter_core_v1`, combined `chapter_core_v2`, dan Twin-Crown Vessel v3 ditolak setelah eval visual. Sugarworks **Sugarfold Core** mempertahankan dua shallow side pinches, empat raspberry corner facets, amber lozenge, serta ivory/muted-mint opposing folds sebagai Inner Core.
- **Trophy Showcase butuh foreign key langsung, bukan composite.** `listTrophies` membaca Featured lewat embed PostgREST `seeker_featured_trophies → expedition_trophies`, sedangkan tabel itu hanya menunjuk `seeker_trophies(owner_id, trophy_id)`. PostgREST menolak embed tanpa FK langsung dengan 400, error boundary menerjemahkannya menjadi 500, dan seluruh operasi `trophies` gagal — jadi pemain yang sudah memenangkan Boss tetap melihat profil tanpa Trophy sama sekali sementara `seeker_trophies` di Postgres benar-benar berisi row-nya. Migration `20260816230419_featured_trophy_embed` menambah FK redundan itu; integritasnya sudah dijamin composite key di atas, dan FK ini ada murni supaya relasinya terbaca. Jangan "sederhanakan" dengan menghapusnya.
- **Trophy Showcase menampilkan seluruh Core, tanpa picker Featured.** `seeker_featured_trophies` dan `set_featured_trophies` tetap hidup di server tetapi client tidak memanggilnya: satu-satunya layar Trophy adalah profil pemiliknya sendiri, dan Featured duduk tepat di atas daftar lengkap yang sama, jadi memilih tiga dari daftar yang seluruhnya sudah terlihat tidak mengubah apa pun. Kembalikan picker-nya kalau profil publik ada. `SeekerProfileView.set_trophies(rows)` membangun kartu art bernama dalam `GridContainer` 3 kolom dan **hanya** membangun ulang saat daftar id berubah; `set_trophy_art()` menempelkan PNG yang menyusul. Kartu memesan slot 176 px sejak dibuat supaya art yang datang belakangan tidak menggeser layout, dan rebuild memakai `remove_child()` sebelum `queue_free()` karena `get_child_count()` masih menghitung anak yang antre dibuang. Daftarnya tinggal di `boot_cache["trophies"]` dan PNG-nya di `user://trophies/<trophy_id>.png`, jadi kunjungan kedua nol round trip; art itu aset chapter publik ber-UUID global sehingga sengaja tidak ikut `clear_boot_cache()`. `--trophy-demo` memeriksa layar ini tanpa jaringan.
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
├── v7/                           # rollback production: sheet 3x3 + nama move
│   ├── vision_system.md          # v6 + strike_name / surge_name dua kata; species_key tetap
│   ├── vision_schema.json        # dua field move, cache key tidak berubah
│   ├── sprite_sheet.md           # sembilan sel: 7 pose karakter + 2 efek battle
│   └── sprite_sheet_evolve.md    # grid 3x3 dipertahankan lintas evolusi
├── v8/                           # predecessor candidate: facing lock kolom kiri
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v7 + anti-inward facing pada Idle/Happy/Damaged
│   └── sprite_sheet_evolve.md    # facing lock kolom kiri dipertahankan lintas evolusi
├── v9/                           # REJECTED: negative-space generik diabaikan model
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v7 + lubang/celah internal bukan matte putih
│   └── sprite_sheet_evolve.md    # uji Monstera tetap menghasilkan celah putih
├── v10/                          # REJECTED: membaik, tetapi slot putih masih tersisa
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v9 + material highlight + Monstera hole lock
│   └── sprite_sheet_evolve.md    # uji Monstera 0,166% residu, belum bersih visual
├── v11/                          # predecessor: borderless clean, seam leak sepatu
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v10 + dark contour langsung melawan green
│   └── sprite_sheet_evolve.md    # efek/evolusi juga tanpa border putih
├── v12/                          # rollback: safe seam + VFX per-Anima
│   ├── vision_system.md          # v11 + brief/form/motion Attack dan Special
│   ├── vision_schema.json        # strike_vfx/surge_vfx; species_key tetap
│   ├── sprite_sheet.md           # aksen Battle utuh dalam safe envelope 12%
│   └── sprite_sheet_evolve.md    # identitas VFX ikut bertahan saat evolusi
├── v13/                          # ROLLBACK: 18 elemen + fauna + unique private art
│   ├── vision_system.md          # object/animal gate + dual typing
│   ├── vision_schema.json        # subject_kind + secondary_element
│   ├── sprite_sheet.md           # objek, grid v12
│   ├── sprite_sheet_fauna.md     # hewan, Damaged tanpa gore
│   └── sprite_sheet_evolve.md
├── v14/                          # REJECTED: masih terlihat seperti anjing anime
│   ├── vision_system.md          # identik v13
│   ├── vision_schema.json        # identik v13
│   ├── sprite_sheet.md           # objek identik v13
│   ├── sprite_sheet_fauna.md     # monsterization floor + expression lock
│   └── sprite_sheet_evolve.md    # identik v13
├── v15/                          # production art baseline; rollback v18
│   ├── vision_system.md          # identik v13
│   ├── vision_schema.json        # identik v13
│   ├── sprite_sheet.md           # objek identik v13
│   ├── sprite_sheet_fauna.md     # proportion + landmark + organic motif
│   └── sprite_sheet_evolve.md    # identik v13
├── v16/                          # CANDIDATE: facing + gaze lock lintas semua Anima
│   ├── vision_system.md          # identik v15
│   ├── vision_schema.json        # identik v15
│   ├── sprite_sheet.md           # objek + source facing/gaze canvas-left
│   ├── sprite_sheet_fauna.md     # v15 + source facing/gaze canvas-left
│   └── sprite_sheet_evolve.md    # evolusi mempertahankan facing/gaze
├── v17/                          # rollback: v15 + tinggi kanonis Vision awal
│   ├── vision_system.md          # v15 + body_height_cm 20–2000
│   ├── vision_schema.json        # kontrak v15 + body_height_cm
│   ├── sprite_sheet.md           # identik v15; nol perubahan art
│   ├── sprite_sheet_fauna.md     # identik v15; nol perubahan art
│   └── sprite_sheet_evolve.md    # identik v15
├── v18/                          # rollback: v17 + floor handheld 70–120 cm
│   ├── vision_system.md          # real scale anchor + playable floor + deliberate exaggeration
│   ├── vision_schema.json        # kontrak sama; deskripsi tinggi diperjelas
│   ├── sprite_sheet.md           # identik v17/v15; nol perubahan art
│   ├── sprite_sheet_fauna.md     # identik v17/v15; nol perubahan art
│   └── sprite_sheet_evolve.md    # identik v17/v15
├── v19/                          # rollback: v18 + floor boneka gendong ~50 cm
│   ├── vision_system.md          # handheld kecil jadi Anima berbadan kecil
│   ├── vision_schema.json        # kontrak sama; deskripsi floor diperjelas
│   ├── sprite_sheet.md           # identik v18/v15; nol perubahan art
│   ├── sprite_sheet_fauna.md     # identik v18/v15; nol perubahan art
│   └── sprite_sheet_evolve.md    # identik v18/v15
├── v20/                          # DEFAULT capture: ilustrasi orisinal + gate franchise
│   ├── vision_system.md          # known_character + klasifikasi subjek ilustrasi
│   ├── vision_schema.json        # reason known_character
│   ├── sprite_sheet.md           # identik byte-for-byte dengan v19
│   ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v19
│   └── sprite_sheet_evolve.md    # identik byte-for-byte dengan v19
├── v21/                          # rollback evolution, terlalu konservatif
│   ├── vision_system.md          # capture tetap identik v20
│   ├── vision_schema.json        # capture tetap identik v20
│   ├── vision_evolve_system.md   # Evolution Director + lineage/effect contract
│   ├── vision_evolve_schema.json # Evolution Plan string anchors
│   ├── sprite_sheet.md           # identik byte-for-byte dengan v20
│   ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v20
│   └── sprite_sheet_evolve.md    # Adult/Evolved konservatif
├── v22/                          # predecessor silhouette-first
│   ├── vision_system.md          # capture tetap identik v20
│   ├── vision_schema.json        # capture tetap identik v20
│   ├── vision_evolve_system.md   # Silhouette Delta + archetype
│   ├── vision_evolve_schema.json # transformed anchors + body-plan delta
│   ├── sprite_sheet.md           # identik byte-for-byte dengan v20
│   ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v20
│   └── sprite_sheet_evolve.md    # body plan baru tiap stage dari Idle
├── v23/                          # predecessor: soul pass, apex reject
    ├── vision_system.md          # capture tetap identik v20
    ├── vision_schema.json        # capture tetap identik v20
    ├── vision_evolve_system.md   # v22 + Identity Invariants
    ├── vision_evolve_schema.json # v22 + soul contract
    ├── sprite_sheet.md           # identik byte-for-byte dengan v20
    ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v20
    └── sprite_sheet_evolve.md    # identity priority + green safety
├── v24/                          # predecessor: maturity pass, clarity reject
    ├── vision_evolve_system.md   # v23 + Maturity/Apex Presence
    ├── vision_evolve_schema.json # maturation path + presence contract
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
├── v25/                          # predecessor: clarity pass, mobility reject
    ├── vision_evolve_system.md   # Shape Budget + open apex thesis/channels
    ├── vision_evolve_schema.json # primary shapes + VFX-only palette
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v26/                          # predecessor: mobility pass
    ├── vision_evolve_system.md   # v25 + mobility_contract
    ├── vision_evolve_schema.json # v25 + locomotion/support fields
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v27/                          # predecessor: face-age craniofacial
    ├── vision_evolve_system.md   # v26 + face_age_contract
    ├── vision_evolve_schema.json # v26 + age_read/ratio fields
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v28/                          # predecessor: walker exile (Sunhound ular)
    ├── vision_evolve_system.md   # v27 + silhouette_break_contract
    ├── vision_evolve_schema.json # v27 + prior/forbidden/new contour
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v29/                          # predecessor: kind lock + contour delta
    ├── vision_evolve_system.md   # v28 minus gait exile, plus kind_noun
    ├── vision_evolve_schema.json # v28 + source/continued kind
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v30/                          # production evolution: name lineage
    ├── vision_evolve_system.md   # v29 + suggested_name lineage
    ├── vision_evolve_schema.json # v29 + suggested_name
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v31/                          # capture Vibe; evolution tetap v30
    ├── vision_system.md          # identik v20
    ├── vision_schema.json        # identik v20
    ├── sprite_sheet.md           # v20 + {{vibe_direction}}
    ├── sprite_sheet_fauna.md     # v20 + {{vibe_direction}}
    └── vibe_directions.json      # natural/cute/brave/wild/sinister
├── v32/                          # rejected: valid structure, naming quality 0/3
    ├── vision_system.md          # v31 + species naming/anchor 3–5 huruf
    ├── vision_schema.json        # v31 + name_lineage_anchor
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # v30 + exact authoritative name anchor
    ├── vision_evolve_schema.json # v30 + name_lineage_anchor
    └── sprite_sheet_evolve.md    # identik v30
├── v33/                          # rejected: coined-word naming quality 1/3
    ├── vision_system.md          # v32 + anti-compound/source-literal self-check
    ├── vision_schema.json        # v32 + pronounceable anchor contract
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v32
    ├── vision_evolve_schema.json # identik v32
    └── sprite_sheet_evolve.md    # identik v30
├── v34/                          # rejected after expanded eval: 3/6
    ├── vision_system.md          # v33 + private candidates + cover test
    ├── vision_schema.json        # v33 + identity-copy contract
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v32
    ├── vision_evolve_schema.json # identik v32
    └── sprite_sheet_evolve.md    # identik v30
├── v35/                          # rejected: structured self-review 1/6
    ├── vision_system.md          # v34 + lexical/product/creature checks
    ├── vision_schema.json        # v34 + required name_quality declaration
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v32
    ├── vision_evolve_schema.json # identik v32
    └── sprite_sheet_evolve.md    # identik v30
├── v36/                          # rejected: deterministic phonotactics 0/6
    ├── vision_system.md          # naming capture dipindah ke server
    ├── vision_schema.json        # tanpa field naming model
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # nama final dari server
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
├── v37/                          # rejected: hybrid semantic roots 0/6
    ├── vision_system.md          # enam root semantik terurut
    ├── vision_schema.json        # name_roots; final word milik server
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # semantic anchor + server continuation
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v38/                          # rejected: transformed roots 1/6
    ├── vision_system.md          # semantic seed 3–8 huruf, bukan final anchor
    ├── vision_schema.json        # enam seed; transform final milik server
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # empat cadence family seimbang
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v39/                          # rejected: scored candidate selection 3/6
    ├── vision_system.md          # seed sama; server memilih dari 32 kandidat
    ├── vision_schema.json        # identik v38
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # gerbang struktur untuk Adult/Evolved
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v40/                          # superseded sebelum eval berbayar
    ├── vision_system.md          # seed sama; campuran 2–3 suku kata
    ├── vision_schema.json        # identik v38
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v39
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v41/                          # candidate: dua morfem terbaca, menunggu operator
    ├── vision_system.md          # enam morfem 3–5 huruf + kalibrasi register
    ├── vision_schema.json        # root morfem terbaca, bukan seed acak
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # anchor utuh; eskalasi di makna morfem
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
```

V41 adalah production untuk capture maupun evolution; kontrak siluet/mobility/
face-age v29 dan art v30 tetap berlaku di dalamnya, dan v31/v30 adalah rollback.
Adult Veridian v26, Adult Sunhound v28, Evolved Sunhound
v29, serta Adult+Evolved Playtron v29 terkunci per Anima; lock Plan membawa
`suggested_name` operator.
Candidate **Name Lineage v32** sudah diimplementasikan lokal tetapi
**ditolak pada paid Vision eval** dan tidak pernah dipromosikan/live: Scan
membuat nama spesies dari
siluet/material/gerak plus anchor bunyi 3–5 huruf; Adult dan Evolved wajib
mempertahankan anchor authoritative yang sama tanpa fixed suffix atau model
call tambahan. Validator memperbaiki anchor capture invalid secara
deterministik; Evolution tetap exact. Legacy fallback memakai nama generated,
bukan nickname. Bundel prompt dan selftest gratis lulus, tetapi tiga Vision
berbayar (mouse, mug, ilustrasi naga; ~$0.009; nol image generation/retry)
menghasilkan `ClickGlide`, `Muggleton`, dan `Wyrmscale`: 0/3 lolos arah nama
spesies karena compound Inggris transparan/literal/surname-like. Production
tetap capture v31 + evolution v30.
Candidate **v33** memperbaiki akar reject tanpa dictionary hardcode: nama wajib
satu coined word pronounceable, bukan compound Inggris transparan, label/sinonim
sumber, ingredient literal, atau person/surname/place/title/job/rank. Anchor
tetap 3–5 huruf tetapi v33 menolak tiga consonant beruntun; v32 tetap
reproducible. Tidak ada model call/migrasi/perubahan art tambahan. Bundel dan
selftest gratis lulus. Paid Vision-only eval tiga fixture yang sama (~$0.009,
nol image generation/retry) menghasilkan `Cursora`, `Glazel`, dan `Dracovent`;
semua struktur/anchor valid tanpa repair, tetapi hanya `Glazel` lolos arah
kreatif. `Cursora` masih literal terhadap cursor dan `Dracovent` masih generic
draco + vent, jadi v33 ditolak 1/3 dan tidak live; revisi berikutnya wajib v34.
Candidate **v34** membuat filter itu operasional tanpa dictionary server:
Vision membangun forbidden identity list per subjek, membuat minimal lima
kandidat privat, menolak salinan empat huruf beruntun, lalu melakukan cover
test. Paid Vision-only eval tiga fixture yang sama (~$0.009, nol image
generation/retry) menghasilkan `Curvix`, `Glazel`, dan `Skalyn`; ketiganya
lolos arah nama dan anchor tanpa repair. Mug mencatat satu normalisasi
`strike_vfx` yang tidak terkait naming. Set kedua yang lebih beragam memakai
Monstera, sepatu, dan handheld; fixture WebP dikonversi lokal setelah gagal
sebelum API, jadi tetap tepat tiga paid call (~$0.009). Hasil `Fenestra`,
`Kineto`, dan `Portex` ditolak karena dictionary/scientific term, generic
kinetic root, atau product/brand-like read. Agregat v34 3/6: v34 ditolak dan
tidak live; revisi berikutnya wajib v35. Production tetap capture v31 +
evolution v30.
Candidate **v35** menambah delapan kandidat lintas empat construction family,
explicit dictionary/scientific/product/creature-read checks, serta enam boolean
`name_quality` yang wajib `true` di validator. Bundel dan seluruh selftest gratis
lulus. Enam paid Vision-only call (~$0.018, nol image generation/retry)
menghasilkan `Scurrix`, `Crockle`, `Aerisyn`, `Phyllaura`, `Solerix`, dan
`Vectron`; model menyatakan seluruh quality flag true. Audit independen menolak
lima terakhir: existing Scots word/character/bestiary creature, perusahaan
AI/produk, nomenklatur botani, SaaS, serta brand POS/lokomotif. Hanya `Scurrix`
lolos, jadi v35 ditolak **1/6** dan tidak live. Fakta penting: self-attestation
terstruktur menegakkan bentuk response, bukan kebenaran collision claim; revisi
berikutnya harus mengganti mekanisme dengan bukti independen atau lexical
boundary deterministik, bukan menambah checklist model lagi.
Candidate **v36** menguji batas deterministik itu: model tidak lagi membuat nama;
server meng-hash `species_key`, element, strongest stat, brief, dan features
menjadi anchor + syllable fonotaktik, sedangkan Evolution memakai anchor + Plan.
Bundel dan selftest gratis lulus. Enam paid Vision-only call (~$0.018, nol image
generation/retry) menghasilkan `Zimnuzem`, `Basgutun`, `Deshupil`, `Vadvuter`,
`Luvsufak`, dan `Therhalok`. Exact-name audit tidak menemukan collision langsung,
tetapi keenamnya ditolak kreatif: random/awkward, source character tidak dapat
dibaca, dan beberapa mendekati kata/nama/product lain. V36 ditolak **0/6** dan
tidak live. Kesimpulan: unique hash bukan authored species name; revisi berikut
harus hybrid—semantic phoneme/candidates dari model, selection/transformation
deterministik yang menjaga cue terbaik.
Candidate **v37** mengimplementasikan hybrid itu tanpa call/dependency baru.
Capture Vision meranking tepat enam `name_roots` 3–5 huruf dengan channel +
evidence dari silhouette/material/motion/temperament/structure. Server menolak
root yang menyalin `object_label`/`species_key`, memilih root valid terkuat,
lalu menambah continuation terkurasi berdasar visual payload + strongest stat.
Adult/Evolved mempertahankan anchor itu dengan continuation stage-specific dari
Plan. Model tidak membuat final word atau collision claim. Bundel, seluruh
selftest, dan dry run enam foto lulus tanpa API. Enam paid Vision-only call
(~$0.018, nol image generation/retry) menghasilkan `Glidora`, `Serpora`,
`Folialia`, dan `Tecnelia`; mug/sepatu gagal validator pada root `cylin` dan
`stride`. Keempat jalur valid tetap memilih root literal/generic (`glid`,
`serp`, `folia`, `tecn`); exact search menemukan penggunaan `Glidora` dan
`Serpora`. V37 ditolak **0/6** dan tidak live. Formatting root minor seharusnya
dinormalisasi deterministik di versi berikut, tetapi akar masalahnya adalah
server suffix tidak dapat menyelamatkan root dictionary/category yang literal.
Candidate **v38** menerima semantic seed 3–8 huruf lalu mengubah onset, vowel,
dan coda menjadi anchor baru. Continuation tidak lagi mengikuti strongest stat:
hash identitas visual memilih keluarga `closed`/`hard`/`liquid`/`open`, dan
Adult/Evolved memakai keluarga stage-specific yang sama-sama seimbang. Seluruh
selftest + dry run lulus; enam paid Vision-only call (~$0.018, nol image
generation/retry) valid 6/6 dan menghasilkan `Kuka`, `Graskorin`, `Zoskesk`,
`Bomari`, `Daxorin`, `Vororn`. Bias `-a/-ia` berhasil hilang: sample tersebar
open 2, liquid 2, hard 2, dengan ending `-a/-in/-esk/-ari/-in/-orn`. Namun audit
independen menolak lima: KUKA adalah perusahaan robotik, Bomari perusahaan
aktif, Daxorin artis, Vororn punya penggunaan historis/niche, dan Zoskesk sulit
diucapkan. Hanya `Graskorin` lolos provisional, jadi v38 ditolak **1/6** dan
tidak live. Diversitas cadence terbukti masalah terpisah dari collision dan
creature-read; memperbaiki rima saja tidak cukup.
Candidate **v39** menyerang akar reject v38: ia hanya membentuk satu kandidat
lalu memakainya. `nameStructureScore()` memberi penalti deterministik untuk
nama < 7 huruf, < 3 suku kata, rantai CV tunggal tanpa klaster/coda, bigram
berulang, tiga konsonan beruntun, dan substring identitas sumber; keempat reject
terukur v38 semuanya jatuh negatif sementara `Graskorin` positif.
`selectCadenceName()` membangun 32 kandidat (4 cadence family × 8 continuation),
membuang yang di bawah lantai, lalu memilih memakai hash identitas visual. Skor
adalah **gerbang, bukan fungsi objektif**: memilih skor tertinggi terukur
konvergen — 151/200 fixture berakhir `-rin`, yaitu bias rima yang baru
dibetulkan v38. Karena anchor selalu berakhir konsonan, medial v38 dibuang; itu
sekalian memperbaiki bug join vokal yang membuat family `closed`/`hard` tidak
pernah terjangkau. Terukur: hard 51 / liquid 51 / open 49 / closed 49, dan tail
tiga huruf terpadat turun 51/200 → 21/200. Tujuh paid Vision-only (~$0.021, nol
image generation/retry) valid 6/6 dan menghasilkan `Fimdakar`, `Zolvela`,
`Vurralis`, `Diskurak`, `Dorralis`, `Kurvesun`. Audit independen: tiga lolos, dua
borderline (`Diskurak` terbaca `Disk-` literal untuk mouse, `Dorralis` beda satu
huruf dari nama orang `Doralis` sekaligus mengulang tail `-ralis`), dan
`Kurvesun` **reject** karena `kurv-` vulgar di Ceko, Slovakia, Hungaria, Serbia,
Kroasia, dan Polandia. V39 ditolak **3/6** dan tidak live. Fakta penting: sisa
kegagalan bukan lagi bentuk kata melainkan fakta leksikal dunia nyata
(brand, nama orang, kata kasar lintas bahasa) yang tidak terlihat oleh
fonotaktik dan sudah terbukti tidak bisa diklaim model sendiri di v35. Empat
mekanisme berbeda v35–v39 semuanya mentok di 0/6–3/6, jadi revisi aturan
generasi berikutnya diperkirakan mendarat di band yang sama; yang harus berubah
adalah **bukti yang tersedia saat seleksi**, bukan cara kandidat dibentuk.
**Satu perbaikan v39 dipertahankan walau versinya ditolak:** penamaan tidak
boleh menggagalkan capture berbayar. `sepatu.jpg` kehilangan satu Vision karena
seed hanya mencakup tiga visual channel, jadi
`deriveCuratedHybridSpeciesName()` sekarang jatuh ke fonotaktik deterministik
v36 untuk setiap kegagalan seed, mencatat sebabnya di
`selected_name_root.seed_fallback`, dan tetap melewati gerbang struktur. Pagar
yang sama hidup di jalur morfem v41: seluruh akar rusak jatuh ke fonotaktik v36
alih-alih menggagalkan Vision yang sudah dibayar.

Riset pembanding seluruh generasi Pokémon membalik premisnya: Pokémon sendiri
memakai nama yang bertabrakan dengan kata, brand, dan nama orang nyata
(Onix/Onyx, Ditto, Golem, Arbok, Eevee), sementara aturan kita menolak nama
bermakna demi keunikan leksikal lalu meloloskan nama tanpa nyawa. Catatannya di
[`docs/pokemon-name-research.html`](docs/pokemon-name-research.html). **V40**
(campuran suku kata + blocklist beku) diimplementasikan tetapi digantikan
sebelum satu pun eval berbayar. **V41** berhenti mentransformasi root: morfem
terbaca dari Vision bertahan utuh sebagai paruh pertama nama sekaligus anchor
lineage, dan server menyambungnya dengan morfem bermakna dari tabel per elemen
(mineral `lith`/`crag`/`elisk`, tidal `rime`/`mire`/`brine`, ember
`ember`/`pyre`/`lume`), persis cara Noxcoil dan Ambermire dibangun. Aturan
kamus, compound, dan tabrakan nama dicabut; blocklist profanity tetap. Evolution
memakai anchor yang sama dengan tail per stage — biasa untuk Adult, berwibawa
untuk Evolved — jadi eskalasi ada di makna morfem, bukan di jumlah huruf.
Dua perbaikan produksi dipertahankan apa pun keputusannya: satu akar rusak tidak
lagi membuang lima akar sehat (`normalizeNameRoots` melewatinya dan mencatatnya
di `rejected_roots`), dan aturan pronounceable v33 tidak lagi berlaku saat jalur
morfem memiliki anchor — tanpa itu `cindr` milik `Cindrusk` diganti diam-diam.
Dua ronde Vision-only sembilan subjek (~$0.054, nol image generation/retry):
ronde pertama mengukur bug akar terbuang (5/9 memakai fonotaktik v36), ronde
kedua 9/9 anchor dari Vision dan menghasilkan `Vitrelisk`, `Lumecrag`,
`Resonelisk`, `Stridusk`, `Verdarbor`, `Glidfold`, `Pixelquill`, `Loopfold`,
`Dracovenom`. Lineage lulus tanpa syarat: head bertahan huruf demi huruf di
ketiga stage dan tidak bergantung pada Evolution Plan, jadi bentuk lineage bisa
diperiksa tanpa Plan berbayar atau image generation. Register adalah satu-satunya
sisa kegagalan: morfem Latin/material terbaca spesies, kata modern/teknologi
terbaca merchandise, dan empat dari lima kasus lemah sudah menawarkan morfem
lebih baik di peringkat bawah responsnya sendiri.
Operator menolak tail stage ronde kedua, dan keduanya sudah diperbaiki lalu
diukur ulang offline dari Vision JSON tersimpan tanpa satu pun panggilan API.
**Tail tidak boleh menjanjikan anatomi yang tidak ada di Plan:** `Loophorn` dan
`Lumegirt` memasang tanduk pada sarung tangan dan lampu, dan `-coil` pada konsol,
`-pelt` pada naga bersisik, serta `-thorn` pada Monstera tanpa duri adalah janji
yang sama. `planFeatureTails()` memindai `stage_brief`, archetype, mobility
contract, contour read, dan shape budget untuk enam belas fitur tubuh; hanya yang
cocok boleh dipakai, sementara `MORPHEME_BODY_TAILS` mencabut seluruh kelas itu
dari kolam keluarga di stage evolusi. Capture sengaja tetap memakainya karena di
sana morfem menggambarkan material objek aslinya — jalur yang sama yang
menghasilkan Noxcoil dan Duskadon. **Evolved berhenti berima:** penyebabnya
mekanis, bukan gaya — `monolith`/`paragon` melewati 12 karakter di atas head lima
huruf lalu dijatuhkan lantai struktur, dan `throne` tidak pernah terjangkau
karena onset `thr` selalu berbiaya seam >= 3, jadi kolam yang benar-benar
diterima menyusut ke tiga entri. Kolam Evolved sekarang delapan gelar pendek
(`sovran`, `titan`, `zenith`, `astral`, `aegis`, `apex`, `aeon`, `aether`) dan
Adult melanjut ke keluarga materialnya sendiri supaya terbaca spesies saudara.
Tiga cacat lain ikut tertutup: `Cylinonyx` terukur menjadi Hatchling sekaligus
Adult (nama stage sebelumnya sekarang dikecualikan), elisi menghasilkan `Aquamen`
yang terbaca dua kata Inggris dan `Glideeon` yang menumpuk tiga vokal (potongan
elisi wajib mulai konsonan), dan `y` di ujung head kini dihitung vokal untuk seam
sehingga `Cozyweave`/`Cozyseam` tidak lagi tertolak.
Bacaan operator berikutnya menemukan sembilan nama semuanya tiga suku kata dengan
ekor yang masih berulang, lalu meminta mesinnya **dikecilkan**, bukan ditambah:
nama ini placeholder yang boleh di-rename pemain, jadi cukup berbunyi seperti nama
Pokémon. Dua sebabnya mekanis. Tail berawal vokal selalu dua suku kata, dan seam
lama yang dibatasi dua konsonan mengunci setiap head berkoda ganda (`dash`, `dusk`,
`glaz`) pada tail itu — jadi head satu suku kata tidak pernah bisa menghasilkan
nama dua suku kata; batas tiga membuka `Dashcoil` sementara `Cindrvolt` tetap
tertutup di empat. Ekor berulang lahir dari `nameStructureScore()` +
`NAME_STRUCTURE_FLOOR` di atas seam: kolam tiap keluarga tersisa dua–tiga entri,
dan kolam kecil berulang secara aritmetika. Karena itu **seluruh lapisan seleksi
v39–v41 dicabut dari jalur ini** — nol skor, nol 32 kandidat, nol tiga tingkat
fallback. Yang tersisa: kolam lebar, tiga filter (profanity, seam, nama yang sudah
dipakai stage sebelumnya), satu indeks hash, sekitar lima belas baris menggantikan
enam puluh; cap 12 huruf di `morphemeSeamOk()` mengambil satu-satunya tugas yang
masih dimiliki scorer. Tiap keluarga ditambah empat morfem pendek, dan kolam
Evolved menerima gelar satu suku kata `king`/`zard`/`myth`/`doom` — Pokémon sendiri
memakai Nidoking, Slowking, dan Charizard. Aturan anatomi bersifat
**negatif**: hanya fitur yang Plan sebut boleh muncul, tetapi ia **ikut** ke kolam
dan tidak menggantikannya. Versi yang memaksa anatomi menang sudah diukur salah —
Plan bersatu fitur mengunci setiap Adult pada morfem yang sama (`Glidhusk`,
`Celerhusk`, `Glazehusk` pada tiga subjek berbeda) dan sekalian membuka satu crash
yang hanya bisa terjadi saat uang sudah keluar: kolam Evolved tinggal satu tail,
Adult sudah memakainya, filter nama terpakai mengosongkannya, derivasi melempar.
Anatomi yang ikut ke kolam menghapus kelas kegagalan itu, dan filter di dalam
seleksi kini usaha terbaik bukan gerbang — nama kembar itu gangguan kosmetik,
evolusi berbayar yang gagal bukan. Terukur atas tiga puluh head pada satu Plan
identik (kasus terburuk): lima belas ekor Adult berbeda, terpadat 5/30. Metrik
diversitas di selftest sendiri sempat off-by-one — ia menghitung huruf terakhir
head sebagai bagian ekor — dan sudah dibetulkan. Terukur offline atas
sembilan subjek ronde dua tanpa panggilan API: Hatchling dari 9/9 tiga suku kata
menjadi 2 dua suku kata / 3 tiga / 4 empat dengan tujuh ekor berbeda, dan Evolved
sembilan ekor berbeda dari sembilan. Head ronde dua sendiri dua suku kata (`aqua`,
`folia`, `cylin`), jadi prompt sekarang meminta Vision menjaga sebagian besar akar
satu suku kata; simulasi dua belas head satu suku kata mendarat di 5 dua suku kata
/ 7 tiga dengan sebelas ekor berbeda — bentuk Sugarworks. Selftest menuntut nama
dua suku kata tetap terjangkau supaya ini tidak diam-diam kembali.
Ronde ketiga enam subjek baru (~$0.018, nol image generation) memunculkan empat
cacat yang semuanya berupa aturan yang sudah ditulis tetapi baru separuh
diterapkan. **Gerbang anatomi ternyata hanya menjaga evolusi:** capture memberi
`Fenesthorn` pada Monstera tanpa duri, jadi `featureTailsFromText()` sekarang
melayani Plan maupun `signature_features` dan capture memakai gerbang negatif yang
sama. Satu-satunya pengecualian adalah kelas cangkang (`husk`, `usk`) karena setiap
objek punya kulit luar dan `Cindrusk` dibangun begitu; bulu tidak ikut — `Dracopelt`
pada naga bersisik adalah janji yang sama. **Plastik menarik morfem tekstil:**
`Pixlyarn` lahir karena plastic/cloth/paper berbagi keluarga `drape`, jadi `yarn`,
`twill`, dan `eider` dibuang dan diganti `arc`, `sheath`, `ridge`. **Memilih rentang
bit hash masih tebakan:** `seed % 4` harus menjadi `seed >>> 24` di v40 dengan sebab
yang sama seperti `seed >>> 8` memberi tiga dari enam Anima ekor Adult identik di
sini, jadi `mixNameSeed()` menjalankan satu finalizer lowbias32 atas seluruh 32 bit
dan modulo apa pun aman — terukur atas dua puluh empat head ber-Plan identik, ekor
berbeda naik dari 9/24 menjadi 12–15/24. **Elisi bisa menghancurkan morfemnya:**
`Dracolder` menyisakan `lder` yang bukan suku kata, jadi potongan elisi wajib
dibuka satu konsonan lalu vokal — `elisk`→`lisk` dan `adon`→`don` tetap lolos.
Hasil enam subjek: `Pixlusk`→`Pixlward`→`Pixlfold`, `Vitrore`→`Vitrforge`→
`Vitrsovran`, `Thrumridge`→`Thrumadon`→`Thrumzard`, `Resonforge`→`Resonvein`→
`Resondoom`, `Fenessap`→`Fenesbastion`→`Feneszenith`, `Dracosting`→`Dracocoil`→
`Dracopex`; enam ekor berbeda dari enam di ketiga stage, suku kata tersebar 2/3/4.
**Operator menyetujui ronde ketiga dan v41 dikunci player-live 19 Agustus 2026**
untuk capture maupun evolution; detail dan angka di
[`docs/designs/2026-08-19-anima-name-lineage-v41.md`](docs/designs/2026-08-19-anima-name-lineage-v41.md).

Sugarworks v6 sudah production dengan sembilan nama
spesies baru dan aset v5 yang direuse seperti dicatat di atas. Detail ada di
[`docs/designs/2026-08-19-anima-name-lineage-v39.md`](docs/designs/2026-08-19-anima-name-lineage-v39.md);
provenance reject v38 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v38.md`](docs/designs/2026-08-19-anima-name-lineage-v38.md);
provenance reject v37 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v37.md`](docs/designs/2026-08-19-anima-name-lineage-v37.md);
provenance reject v36 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v36.md`](docs/designs/2026-08-19-anima-name-lineage-v36.md);
provenance reject v35 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v35.md`](docs/designs/2026-08-19-anima-name-lineage-v35.md);
provenance reject v34 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v34.md`](docs/designs/2026-08-19-anima-name-lineage-v34.md);
provenance reject v33 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v33.md`](docs/designs/2026-08-19-anima-name-lineage-v33.md);
provenance reject v32 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v32.md`](docs/designs/2026-08-19-anima-name-lineage-v32.md).
Client Scan mengirim `capture_vibe`; server menolak nilai di luar allowlist
sebelum Vision, menolak non-Natural saat prompt < v31 (`VIBE_UNAVAILABLE`),
dan mengunci vibe di `generations.capture_vibe` pada claim pertama. Eval
Monstera 18 Agustus 2026 (satu Vision, tiga generation Cute/Brave/Sinister,
nol retry) lulus baca visual operator. Crop pertama gagal karena Cute/Sinister
bocor seam Idle dan Brave kena audit detached-character v26 milik evolusi.
Capture v31 membuang bocoran Idle deterministik dan tidak memakai audit tubuh
terlepas itu; `--reprocess` ketiga raw lulus 9/9 tanpa panggilan model.

**Prompt tidak bisa dibaca sebagai file di Edge Function.** `Deno.readTextFile()` gagal untuk file pendamping yang dideploy lewat MCP, jadi `backend/tools/bundle_prompts.mjs` membundel semua versi menjadi `functions/_shared/prompts.generated.ts` yang diimpor sebagai modul. Sumbernya tetap file `.md` di git; artefaknya turunan. Setelah mengubah prompt: `node backend/tools/bundle_prompts.mjs`. Skenario 17 di `npm run selftest` gagal kalau bundelnya basi, jadi kelupaan ketangkap gratis, bukan saat art produksi ternyata berbeda dari art yang sudah disetujui.

`vision_schema.json` **tidak** dikirim sebagai parameter API — ia disisipkan ke `system_instruction`, sebab wrapper Gemini di Replicate tidak punya `response_schema`. Notasinya tetap subset OpenAPI (`"nullable": true`, bukan `["string", "null"]`, tanpa `pattern`) supaya file yang sama bisa langsung dipakai kalau nanti pindah ke Gemini API langsung. Bentuk data ditegakkan `extractJson()` dan `validateVision()` di `backend/supabase/functions/_shared/vision.mjs`, bukan diharapkan dari model.

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md) dan sumber art direction v2 ada di [docs/monster_camera_anime_cel_shaded_style_guide.md](docs/monster_camera_anime_cel_shaded_style_guide.md). Jangan mengarang aturan style baru; konsistensi visual antar Anima bergantung pada style lock itu.

**Larangan negatif saja tidak menghapus logo merek, tapi instruksi pengganti v3 juga punya efek samping.** v2 sudah memuat "no logos, brand names" dan GPT Image 2 tetap menggambar swoosh Nike karena logonya datang dari `input_images`. v3 menghilangkannya dengan meminta permukaan polos atau marking geometris ciptaan sendiri; itu lolos satu uji sepatu dan menjaga `species_key`, tetapi model lalu mengarang emblem mirip logo bahkan pada objek tanpa logo. v4 menghapus pilihan marking itu seluruhnya: logo/teks/sigil dianggap tidak ada dan tempatnya selalu material polos yang setia pada objek.

**Damage v3 bias robot bukan kebetulan model.** Template universalnya sendiri menyebut `loose cable`, `exposed wire`, dan `broken key`, sementara style lock memberi semua objek bahasa `techno-organic`; material Vision tidak pernah sampai ke prompt gambar. v4 menambah `surface_finish` + `damage_hints` ke Vision dan menyaring hint teknis di `assemblePrompt()`: kata cable/wire/circuit/key hanya lolos jika fitur yang sama benar-benar ada di `signature_features`. Keramik retak/terkelupas, kain berjumbai/robek, tanaman sobek/layu, logam penyok/tergores.

**V7 adalah baseline 3×3 dan rollback layout.** V7 membawa seluruh pagar v6, lalu mengubah layout sheet dari 2×2 (4 pose) menjadi 3×3 (9 sel): Idle, Battle, Sleep, Happy, Hungry, Dirty, Damaged, plus efek `fx_strike` / `fx_surge` tanpa tubuh kreatur. Vision menambah `strike_name` dan `surge_name` per Anima. Post-process memilih grid dari `prompt_version` (>= v7 = 3×3, selain itu 2×2) supaya art lama tetap dimuat. V17 adalah default production dengan sprite prompt identik v15 dan tambahan tinggi kanonis Vision; v15 rollback art; v16 tetap candidate facing/gaze terpisah; v14 fauna ditolak; v13 rollback kontrak capture; v12 rollback aman tanpa animals/18-typing, dan v7 tetap rollback layout lama.

## Fakta teknis yang mudah salah

- **Sign-in anonim mati secara default, dan Scanima tidak punya login gate.** Identitas awal pemain adalah Guest Seeker anonim; `handle_new_user` mengisi 8 scan charge, **1 Core** (`starter_guest`), dan 50 Bits. Dengan setelan default project, `POST /auth/v1/signup` menjawab `anonymous_provider_disabled` dan app mati di detik pertama. Sudah dinyalakan di remote dan dideklarasikan di `backend/supabase/config.toml`. Batas 30 sign-in anonim/jam/IP tetap pagar abuse. Google adalah upgrade setelah progres ada, bukan syarat membuka app.
- **Guest Seeker hanya mendapat satu Scan sukses.** `claim_scan_charge()` menolak guest yang slotnya sudah terpakai sebelum Vision berbayar; `claim_capture()` lock profile lalu mengisi `guest_scan_used_at`, sehingga request paralel tidak dapat membuat dua Anima. Setiap hasil v13 memakai satu Core. `refund_generation()` mengembalikan Core dan melepaskan slot guest bila tidak ada Scan sukses/pending lain. Setelah slot dipakai, client menampilkan `Sign in to Scan Again`; jangan pakai device flag sebagai otoritas.
- **Upgrade Google adalah identity link same-UID + grant idempoten, bukan akun baru.** `AuthFlow` memakai PKCE, state acak, system browser, dan `scanima://auth/callback`; `SecureStore` memakai OAuth2Plugin (Android Keystore/iOS Keychain). Restore biasa membuka URL `/auth/v1/authorize` langsung di browser—jangan di-fetch lewat `HTTPRequest`, karena redirect-nya diikuti sampai HTML Google dan tidak pernah menghasilkan `{url}`. Link tetap fetch `/auth/v1/user/identities/authorize` dengan bearer guest + `skip_http_redirect=true`, baru membuka URL JSON-nya. Link wajib menghasilkan UID yang sama, lalu `upgrade_seeker_account()` memverifikasi identity Google dan melengkapi grant starter lifetime ke 4 (+3 maksimal sekali lewat ledger unik; akun lama lifetime 3 mendapat +1 `starter_team` sekali). Link baru mengumumkan sukses setelah grant itu kembali sukses; kegagalan menampilkan status sinkronisasi dan boot berikutnya me-retry RPC idempoten. Kalau Google sudah dimiliki akun lama, tampilkan warning lalu restore; progres guest **tidak di-merge** dan pending intent/`last_anima` guest dibuang. Cancel/error/timeout tetap memakai sesi guest utama; menekan Sign in lagi membuang intent browser yang tidak kembali lalu langsung membuat intent baru. Token baru baru diterima setelah exchange lengkap tersimpan aman.
- **Redirect Auth production harus mobile-aware.** `AuthFlow` mengirim callback dinamis `scanima://auth/callback?state=<acak>`, jadi Supabase URL Configuration wajib memakai Site URL `scanima://auth/callback` dan Redirect URL `scanima://auth/callback**`. Exact URL tanpa globstar tidak menerima query state; GoTrue diam-diam jatuh ke Site URL default `http://localhost:3000`, sehingga Google sukses tetapi browser berakhir di localhost dan app tidak menerima code. Nilai yang sama dideklarasikan di `config.toml`, tetapi perubahan file lokal tidak mengubah Dashboard remote.
- **Profil Seeker server-authoritative.** `seeker_name` unik case-insensitive, wajib 3–16 ASCII dengan huruf awal, tanpa spasi, dan rename cooldown 30 hari; birth year/gender opsional. Onboarding muncul sesudah hatch pertama dan memakai `seeker_name is null`, tanpa flag lokal. Client melakukan preflight regex yang sama, tetapi database tetap pagar final; nama invalid/taken menyalakan label + field `ErrorLineEdit` dan pesan `ErrorLabel` merah sampai pemain mengedit nama. `seeker_xp` mendapat +5 saat Anima pertama menjadi ready lalu mencerminkan kenaikan `care_score`; `battle_victories` menghitung setiap transisi session ke won termasuk Training. Level kosmetik `1 + floor(sqrt(seeker_xp / 5))` tidak memengaruhi game. Nilai nullable PostgREST adalah `null`; `str(null)` menjadi `<null>`, jadi cek Variant sebelum menentukan guest lock/onboarding/grant retry.
- **`species_library` bukan lagi jalur capture.** Ia dan `record_cache_hit` tetap service-role-only sebagai rollback legacy. Semua Anima ready lama sudah memiliki `sheet_path` privat dan bucket `sheets` sudah `public=false`; jangan membuka bucket atau menghidupkan cache hit tanpa rollback eksplisit.
- **18 elemen hidup di satu graph bersama.** Roster/edge/normalisasi ada di `_shared/elements.mjs`, mirror label saja di `ElementCatalog`; client tidak menghitung matchup. Attack memakai primary, Special secondary/fallback. Dual defender membatalkan weakness+resistance dan multiplier tidak stack. Peta yang bisa dibuka langsung di browser ada di [`docs/element-matchups.html`](docs/element-matchups.html) — satu file tanpa build, datanya salinan `ELEMENT_STRENGTHS` karena ES module lewat `file://` ditolak CORS, dan skenario 35 `npm run selftest` gagal kalau roster bergeser tanpa halaman itu ikut diperbarui.
- **Art capture adalah per-Anima dan privat.** Path tetap `<owner>/<anima>/<hash>.png` di `anima_sheets`; cache client memakai `anima_id`. Jangan mengembalikan permanent sheet URL atau owner path untuk lawan.
- **Fauna v13 sudah dibuktikan di production.** Satu foto Golden Retriever public-domain menghasilkan `subject_kind=animal`, primary `fauna`, secondary `air`, prompt v13, sheet privat yang dapat diunduh owner, dan nol row `species_library`; run selesai sekitar 86 detik termasuk Vision/polling. Akun dan blob uji dihapus sesudahnya.
- **Fauna v13 terlalu realistis; v14 memperbaiki ekspresi tetapi tetap bukan monster Scanima.** Eval Golden Retriever v14 selesai 57 detik dan 9/9 sel, tetapi Idle masih berupa anjing anime biasa dan residu hijau 0,453%; v14 REJECTED dan tidak pernah dipromosikan. V15 menyalin Vision/schema/object/evolve v13 apa adanya lalu memperkeras fauna dengan tiga syarat serentak: proportion break, minimal dua landmark evolution, dan satu original organic motif terintegrasi; bright chroma green juga dilarang di seluruh foreground/VFX. Hewan tanpa mata/wajah yang terlihat memakai sensory feature dan body gesture, bukan anatomi manusia buatan. Eval v15 lulus visual 9/9 dalam 55 detik dan terbaca sebagai monster pada ukuran game; residu hijau 0,526% tidak mengganggu di ukuran itu tetapi tetap dipantau. V17 memakai sprite prompt v15 byte-for-byte dan menambah `body_height_cm`; v18 mempertahankan art itu lalu memperjelas keputusan tingginya. V19 hanya mengubah floor benda genggam dan v20 hanya mengubah gate/dukungan ilustrasi; ketiganya mempertahankan sprite prompt v15 byte-for-byte. V31 menambahkan Vibe pada sprite object/fauna tanpa mengubah Vision. `create_anima` version 20 dan `app_config.prompt_version = "v31"` sudah live; rollback capture v20, rollback gate v19, rollback kebijakan tinggi handheld v18, rollback kebijakan tinggi awal v17, rollback art v15, rollback kontrak capture v13.
- **V16 adalah candidate facing/gaze, bukan production.** Temuan manual Gumdrop menunjukkan instruksi facing global saja belum cukup: pose tertentu membalik badan dan pupil menatap arah berbeda. V16 mempertahankan Vision/schema v15 lalu mengulang kontrak pada object, fauna, dan evolve: face/leading sensory plane, near-camera flank, tubuh, support point, serta landmark asimetris selalu forward-left menuju canvas-left; semua pupil terbuka menatap satu target canvas-left, Sleep menutup mata, dan Damaged boleh half-lidded tanpa mengubah arah. Ini tetap natural di Home dan benar di Battle karena client membalik seluruh sheet pemain. Prompt Chapter Factory serta sembilan prompt manual Sugarworks memakai lock yang sama secara lokal. `npm run selftest` dan dry-run Smoke Set v16 sudah lulus tanpa model call, tetapi jangan mengganti sprite prompt production v18 dengan v16 sebelum eval gambar berbayar membuktikan orientasi, gaze, layout, dan kualitas visual. Jika dipromosikan nanti, fork dari v18 agar kontrak dan kebijakan tinggi tidak hilang.
- **Anima Atlas mengganti Gallery Feed pada build kandidat.** Publish tetap hanya
  akun Google dan moderation sekali per art hash tetap menolak konten tidak aman
  atau karakter franchise yang dapat disebut namanya. Consent berlaku untuk satu
  lineage; lawan pemain baru tercatat sesudah Duel, cast Expedition tampil sebagai
  siluet sampai benar-benar muncul, dan owned form tercatat saat Scan/Evolve sukses.
  Detail Duel hanya membawa generated profile + nama Seeker terkini, tanpa
  nickname, care, account ID, atau link profil. Special Expedition membaca
  `special` + `boss_seeker.display_name` dari manifest chapter ke
  `atlas_forms.chapter_seeker_name`; jangan hardcode slug Cotton/Confectioner di
  Godot. Nilai null wajib menghilangkan sel Seeker, bukan menjadi `<null>`.
  Unpublish/delete/auto-hide
  membersihkan discovery non-owner; report langsung menyembunyikan lineage dari
  reporter. Tabel `gallery_entries`, `gallery_moderations`, dan slug function
  `/gallery` tetap dipertahankan sebagai consent/moderation/bot-pool wire, bukan
  feed publik. Battle bot pemain tetap hanya dari publication approved dan wajib
  punya fallback sistem/legacy.
- **Core mingguan otomatis, bukan Claim.** `seeker_profile_summary()` memanggil grant service-role ledger-backed: +1 setelah 7 hari server untuk linked account bila saldo gratis <3, tanpa catch-up. Bank penuh tidak mengonsumsi eligibility.
- **Bucket `photos` hanya punya policy INSERT, dan itu lengkap.** Client boleh menaruh foto di foldernya sendiri, tapi tidak boleh membaca, melihat daftar, maupun menghapus — DELETE dari client dijawab RLS dengan 403. Terlihat seperti policy yang lupa ditulis; sebenarnya client tidak pernah membutuhkannya. Yang membaca foto adalah Edge Function lewat signed URL service role, dan yang menghapusnya adalah `create_anima`/`finalize_sheet` setelah post-processing selesai. Menambahkan SELECT berarti memberi jalan membaca foto yang seharusnya sudah lenyap.
- **Care sepenuhnya server-authoritative.** `care`, `care_synced_at`, `care_score` (EXP pemain), sleep, counter harian, Dormant, dan inventory berubah hanya lewat `apply_care()` di balik Edge Function JWT `care_anima`. Feed wajib `food_id` dari tas; Clean gratis, Hygiene +35. EXP Feed +3 hanya saat Hunger menyeberang `<40` → `≥40`. Item Energy (`use_item`) dijepit 100 tanpa EXP. Event + ledger + kebutuhan diubah dalam satu transaksi dan satu idempotency key. `apply_care()` menolak Feed/Clean/Energy dengan `NEED_FULL` kalau meter setelah decay >= 99.5, bukan 100, supaya meter yang tampil penuh tidak mengonsumsi item atau Bits. Client meredupkan tombol yang sama dan toast `ERROR_NEED_FULL` tanpa request. Feed dan Energy dipakai dari **Bag** (bukan dari Shop). Client hanya boleh PATCH `nickname`. Wire tetap `care_score`; UI bilang EXP/Level. Kurva live `need_next(level) = 5 × ceil(level / 5)` untuk Level 1–39; Adult Lv.16 = 150 EXP, Evolved Lv.36 = 700, dan Lv.40 = 860. `care_score` dijepit 860. Sleep penuh memulihkan Energy setiap siklus, tetapi +5 EXP hanya sekali per Anima per hari sipil lokal lewat `sleep_exp_on`. Jangan menaikkan `animas.stage` sebelum art evolusi ada.
- **Respons care dipisah menjadi intent instan dan commit server.** `scan_flow` memanggil `AnimaPresenter.care_feedback()` sebelum `await care_anima` dan hanya mengunci Care Dock; meter dicat optimistis lewat `optimistic_care()` lalu ditimpa row authoritative, sedangkan Bits, sleep, dan `care_score` tetap menunggu server tanpa refetch katalog. Katalog di-fetch sekali di boot; Feed/Energy me-refresh inventory di belakang, Clean/Play/Sleep tidak. Pembelian memakai `quantity` dari `purchase_catalog_item`, bukan round-trip kedua. Feed memberi satu hop, Play memakai pose Happy plus enam bounce selama ~2,5 detik, naik level dan menang Battle juga Happy, Hungry/Dirty mengikuti kebutuhan, dan pose visual Damaged (`defeated`) melakukan heavy breathing loop selama Dormant. Edge Function mempertahankan `verify_jwt = true` dan memakai `getClaims()` pada satu admin client per isolate supaya JWT ES256 diverifikasi lewat cache JWKS, bukan round-trip `getUser()` pada setiap tap. Jangan menggantinya dengan decode JWT tanpa verifikasi.
- **Turn Battle dianimasikan dari simulasi lokal, tetapi hasilnya tetap milik server.** Client memutar `BattleSim.resolve_turn()` / `TeamSim.resolve_team_turn()` di frame yang sama dengan tap, memainkan event log hasil prediksi, lalu memasang row authoritative begitu response tiba. Kalau ringkasan yang dilihat pemain berbeda (status, turn, HP/PP Duel, tiap event beserta `target_hp` + `damage`), arena memutar ulang event server. Port GDScript-nya di `game/scripts/sim/` meniru semantik JavaScript (`Math.imul`, `Number()`, `clampInt`); `ElementRules` memiliki `ROSTER`/`ALIASES` dan `ElementCatalog` memakainya ulang — membalik arah itu membuat simulasi menarik autoload `LocaleManager` dan gagal dikompilasi di mode `--script`. Dua pagar wajib hijau: golden vector `backend/tools/emit_sim_vectors.mjs` → `tests/test_battle_sim_parity.gd`, dan pemindai konstanta skenario 32 di `npm run selftest`. **Switch ikut diprediksi selama sheet penggantinya sudah ada di arena**: `TeamSim.switch_targets()` membaca `anima_id` yang masuk dari tiap event `switch`, dan `_prepare_team_active_art()` / `_prepare_active_art()` memang sudah memuat seluruh slot kedua party saat session dibuka, jadi switch sukarela, forced switch sesudah KO, dan switch bot animasinya mulai di frame tap. Yang tetap menunggu server hanya **`final_ace` Boss** — pelat dan dialog `last_anima`-nya sekali per run, jadi tidak boleh datang dari tebakan — **turn yang menutup encounter Boss**, karena baris `victory`/`defeat`, ringkasan hadiah, dan reveal Trophy first-clear semuanya dibaca dari reward authoritative, dan **item Expedition**, karena `ExpeditionController` tidak memegang katalog Shop. Prediksi tidak pernah menulis saldo, EXP, atau inventory. Meter Care juga dicat lebih dulu lewat `scan_flow.optimistic_care()` dan dikembalikan kalau `care_anima` menolak; catnya wajib **sebelum** `_home_view.set_busy(true)`, sebab `_refresh_care()` menghitung ulang keadaan tombol dari `_busy`. Selengkapnya di [docs/12](docs/12-local-first-turns.md).
- **RNG turn tidak lagi diseed dari `idempotency_key`.** Key itu dipilih client, jadi seed lama `seed:turn:key` bisa dikocok sampai crit. `RULES_VERSION = 2` membuangnya; `state.rules_version < 2` tetap memakai formula lama supaya replay session lama cocok. Skenario 31 di `npm run selftest` menjaga keduanya. Nilainya hidup di `_shared/battle.mjs` dan `game/scripts/sim/battle_sim.gd` dan wajib identik.
- **Turn yang gagal terkirim punya dua lapis: ulang sendiri, lalu mundur.** `Backend._send()` menerima jatah `retries` dan `turn_retries()` hanya memberikannya pada operasi `turn` — start/resume/forfeit/katalog lebih baik gagal cepat dan ditawarkan lagi. Yang diulang **hanya** kegagalan transport; `_send_once()` menandainya `transport: true`, sebab server yang sudah menjawab 4xx berarti sudah memutuskan dan mengulangnya cuma menahan pemain. Backoff 2 lalu 4 detik, jadi offline sungguhan menambah ~6 detik yang tertutup animasi prediksi. Sesudah jatah habis, `_submit_pending_battle` / `_submit_pending_team_battle` / `ExpeditionController._submit_pending` mengembalikan arena ke session authoritative terakhir (`session_before`, atau `_encounter` di Expedition). Tanpa rollback itu arena tertinggal di masa depan dan tap berikutnya mengirim nomor turn yang belum pernah ada, lalu dijawab `STALE_BATTLE`. **Antrean multi-turn offline sengaja tidak dibangun**: TTL Duel 30 menit, forced switch butuh sheet yang belum tentu ter-cache, dan reward tidak bisa ditampilkan sebelum server menghitungnya—lima turn offline berisiko hilang sekaligus.
- **Home digambar dari `user://boot_cache.json` sebelum jaringan menjawab.** Cache itu display-only: profil, roster, katalog, dan inventory dari respons sukses terakhir. `_paint_boot_cache()` memasangnya lalu `_show_cached_anima()` memproyeksikan meter lewat `CareRules.projected_care()`, jadi Anima tidak pernah terlihat kenyang setelah app lama ditutup. Cache milik UID lain tidak pernah dipakai — satu device berpindah dari guest ke Google — dan `clear_account_state()` serta `discard_guest_local_state()` menghapusnya. `_boot()` melewati state `loading` kalau shell Home sudah `ready`, dan roster yang gagal di-refresh tetap tampil dengan error sebagai toast, bukan layar error yang menghapus isi. Katalog tetap wajib di-fetch sekali per sesi lewat `_catalog_synced` supaya harga baru tidak tertahan cache. Saldo, kebutuhan, dan inventory yang dibelanjakan tetap hanya dari Postgres.
- **Shop optimistis tanpa mengunci sheet-nya.** `_apply_optimistic_purchase()` mengurangi Bits dan menambah jumlah tas pada frame yang sama dengan tap, lalu `purchase_catalog_item` tetap pagar akhir dan rollback mengembalikan keduanya. Jangan kembalikan `ShopSheet.set_busy()` di jalur beli: ia membangun ulang seluruh daftar, dan kedipan itulah yang dulu terbaca sebagai lag.
- **`withSignedRoster()` tidak lagi menandatangani ulang art roster tiap turn.** Sampai delapan `createSignedUrl` per tap adalah biaya Storage yang tidak menghasilkan apa pun, sebab URL-nya masih hidup 15 menit. `_shared/signed_roster.ts` menyimpan cache module-level lewat `signSheetUrl()` dengan margin refresh; `battle_anima` memakai helper yang sama untuk `gallerySnapshot` dan `withFreshBotArt`. Isolate yang mati kehilangan cache-nya dan menandatangani ulang — itu benar, bukan regresi.
- **Battle vertical slice sepenuhnya server-authoritative.** Formula tunggal hidup di `_shared/battle.mjs`; client hanya mengirim `strike`/`surge`/`guard`/`item` lalu menganimasikan ordered event log. `battle_sessions` menyimpan state/version dengan TTL 30 menit, satu active session per owner, plus `reward_tier/roll/bits` dan `item_used_id`; `battle_turns` menyimpan `(session, turn, idempotency_key)` untuk replay. Menang: Bits dari tier lawan (Favorable 6 / Even 8 / Tough 11 / Formidable 15, ±1 deterministik dari seed), EXP snapshot-scaled, dan `battle_wins +1` untuk tiga kemenangan pertama hari lokal; loss/forfeit nol reward dan tidak pernah menyentuh Genesis Core. Full yield adalah `1 + ceil(opponent_level / 10)`, underdog +1 per selisih 5 Level maksimum +2, Tough/Formidable +1, lalu clamp 1–8. Satu item Battle per session mengganti aksi turn itu; konsumsi inventory atomik. Anima pemain wajib `ready`, bangun, tidak Dormant, dan punya **Energy >=20**. Hunger bukan gerbang; lapar/kotor memotong stats. `start_battle()` sync lalu memotong 20 Energy hanya pada session baru. Bot pemain berasal dari Gallery approved, snapshot tetap anonim, dan fallback sistem/legacy menjaga Battle tetap tersedia. Snapshot membawa primary/secondary element dan level; server memilih elemen Attack/Special serta multiplier final. Art lawan selalu datang dari `anima_sheets` lewat signed URL 15 menit yang disegarkan pada start/resume; ID-nya dibaca dari `bot_snapshot.anima_id` karena payload publik sengaja tidak membawa FK session. Fallback legacy memakai `species_library` hanya sebagai penanda eligibility, lalu menandatangani salinan privat milik row Anima hasil migrasi—jangan hidupkan kembali URL bucket `sheets`.
- **Lawan Duel lewat gate keseimbangan, dan yang tidak lolos diganti lawan sistem.** Pool lama ±15% total base stat tidak melihat Level, bentuk sebaran stat, maupun elemen; pada tujuh Anima production duel ber-label `even` terukur 8%–100% peluang menang. `_shared/duel_bot.mjs` menambah `estimateDuelBalance()` — rasio taksiran turn-to-kill dua sisi, memakai `computeDamage` yang sama plus elemen dan care — dan hanya menerima kandidat di 0,53..1,00 (terkalibrasi: walkover 98%–100% duduk di 0,39–0,50, mustahil 7%–8% di 1,22–1,34). Combat power **tidak** bisa dipakai sebagai gate karena ia menjumlahkan stat sementara hasil duel adalah damage dikali daya tahan; dua Anima ber-combat power identik menang 100% dan 0,3%. Gate ini murah karena harus jalan atas semua kandidat; tier hadiah dihitung sekali untuk lawan yang benar-benar dipilih dan karena itu **disimulasikan**, lihat butir berikutnya. Kalau tidak ada kandidat seimbang, `systemDuelBot()` merakit `system-duel-fledgling`/`-warden`/`-paragon` (dipilih `formFromLevel`, hanya nama dan art): Level dicerminkan persis, **bentuk sebaran stat cermin persis**, elemen tunggal netral dua arah, Hunger/Hygiene disamakan dengan pemain, dan **total base stat dicari per-Anima** — lihat butir kekuatan bot di bawah. Dua hal sudah diuji dan **ditolak**: mencampur bentuk stat bot ke arah distribusi rata (sebaran win rate antar-roster melebar dari 23 poin ke 71–88 poin), dan menyesuaikan total base stat bot dengan pengali care (suku HP tetap `+20` di `toBattleStats()` dan lantai 10 per stat di `normalizeBaseStats()` tidak menyusut, jadi bot lebih tebal daripada pemain — HP 152 versus 143 — dan Anima ber-Special rendah tetap 0% pada setiap lantai 1,00..0,50). Konsekuensi yang disengaja: **perawatan terlantar tidak lagi menentukan hasil Duel** — gerbang Hunger dibuang supaya pemain tanpa Bits punya jalan keluar, dan tanpa lawan yang ikut terpotong jalan itu cuma bergeser menjadi kalah (lapar 0%–22%, lapar+kotor 0%–2%). Biaya neglect hidup di EXP Feed, Dormant, dan Energy. `bot_anima_id` null hanya sah kalau snapshot menandai `system_asset = 'placeholder'` (migration `20260817072847_system_duel_opponents`, live), dan `withFreshBotArt()` wajib return dini untuk snapshot itu — ia tidak punya baris `animas`. Tiga pagarnya dijaga `quota_rules.sql`: null tanpa penanda placeholder ditolak `BOT_NOT_FOUND`, penanda tanpa slug identitas ditolak `SNAPSHOT_MISMATCH`, dan yang sah tetap membayar 20 Energy. `live_battle.gd` tidak boleh menuntut `sheet_url` pada snapshot placeholder maupun memakai `bot_snapshot.anima_id` sebagai UUID Anima orang lain — lawan sistem memakai slug, jadi pagar kepemilikan diuji dengan UUID sah yang bukan baris `animas`. Nol perubahan client: `_prepare_battle_art()` sudah memakai `PlaceholderSheet`. Skenario 34 `npm run selftest` menjalankan resolver production, jadi pergeseran rumus combat menggagalkan kalibrasinya alih-alih diam-diam berubah di tangan pemain.
- **Tier hadiah Duel diukur dengan mensimulasikan duelnya, bukan ditaksir dari combat power.** Catatan lama di file ini menyebut "tangga Bits terbalik"; diukur ulang, tangga 6/8/11/15 justru sehat dan yang rusak adalah **label**-nya. Combat power melabeli satu `even` yang isinya 38%–99% peluang menang, membayar `formidable` 15 Bits untuk duel yang dimenangkan 76%, dan `favorable` 6 Bits untuk lempar koin 52% — 47 dari 59 matchup salah label. `duelWinRate()` di `_shared/battle.mjs` menjalankan `DUEL_DIFFICULTY_RUNS = 64` duel penuh lewat `resolveTurn` production, lalu `tierFromWinRate()` memetakan ≥80% → `favorable`, ≥55% → `even`, ≥40% → `tough`, sisanya `formidable`. Nilai harapannya rata pada matchup yang lolos gate (5,8 / 5,6 / 5,4 Bits), jadi tier atas berhenti menjadi perangkap tanpa mengubah satu pun angka Bits, nol migrasi (clamp `start_battle` tetap 5..16), dan **nol perubahan Team Battle/Expedition** — keduanya tetap memakai `rewardTierFromRatio` atas combat power dua roster, sebab arena delapan Anima dengan switch tidak diwakili satu simulasi 1v1. Tiga hal wajib: kebijakannya `bestDuelAction()` (memakai `chooseBotAction` untuk kedua sisi menggeser tier di 30/38 matchup, sebab bot memilih Special 68% acak tanpa melihat elemen), **care dinetralkan di dua sisi** (tanpa itu lapar+kotor menang 0% → `formidable` 15 Bits, jadi menelantarkan Anima menjadi cara menaikkan Bits), dan seed simulasi **konstan** (matchup sama = tier sama, dan terukur lebih akurat daripada seed per-matchup: salah 6/38 versus 8/38 terhadap patokan 800 duel). Biayanya ~2 ms sekali per `startBattle`, dan tier tidak pernah salah lebih dari satu tingkat. Port GDScript-nya sudah **dihapus** (`battle_reward_preview`, `bits_for_tier`, `reward_tier_from_ratio`, `combat_power`, `REWARD_TIER_*`) beserta golden vector-nya: tidak ada satu pun pemanggil production, hadiah selalu dari server, jadi mempertahankannya berarti memport loop 64 duel ke GDScript demi kode mati. Skenario 32 sekarang menjaga simbol itu tidak kembali, dan 34 menjaga urutannya: duel yang lebih mudah tidak boleh pernah membayar tier lebih tinggi.
- **Kekuatan lawan Duel sistem dicari sampai duelnya terukur imbang, bukan dipatok satu band.** Versi pertama memakai band tetap `0,96..1,00` dan gagal begitu tier menjadi terukur: satu konstanta harus melayani dua ujung roster sekaligus, batas atasnya ditentukan Anima paling rapuh (ber-Special 15, yang jatuh 57%→29% begitu rasio menyentuh 1,02), dan angka aman untuk Anima itu ternyata walkover 89%–100% bagi enam Anima production lainnya — jujur dilabeli `favorable`, jadi Bits harapan per duel turun 8,00 → 6,29. `balancedRatio()` di `_shared/duel_bot.mjs` menggantinya dengan **bisection 7 langkah** atas `duelWinRate()` di `BOT_RATIO_MIN..MAX = 0,90..1,25`, menargetkan `BOT_TARGET_WIN_RATE = 0,65`. Hasil terukur: Mugshots 0,990, klasik/Playtron/Sunhound 1,000, Deckon 1,047, Veridian 1,053, Hydron 1,121; diverifikasi 800 duel pada keluarga seed berbeda, ketujuhnya 55,9%–77,3% alias Even, jadi Bits harapan kembali **8,00** untuk duel yang benar-benar pertandingan. Rasio **bukan** tuas linear dan itu justru alasan pencarian per-Anima diperlukan: pada langkah 0,005 klasik 100% di 0,990, 70% di 0,995, lalu 38% di 1,020 — langkah 0,04 yang lebih kasar menyembunyikan tebing itu dan membuatnya tampak seolah tidak ada k yang imbang. Bisection sah karena sweep 0,90–1,58 pada tujuh Anima tidak punya satu pun titik yang naik kembali. Tiga hal wajib: pencarian **care-neutral** (gratis, `duelWinRate` memang menetralkannya — bot yang ikut melemah saat pemain lapar membuat menelantarkan Anima menjadi cara mendapat duel gampang dengan bayaran yang sama, sebab tier juga care-neutral), target di **tengah** band Even (derau 64 duel sampai 10 poin, dan band 25 poin menyerapnya), dan elemen tetap boleh diundi seed karena netral dua arah tidak mengubah kesulitan — itu satu-satunya sumber variasi lawan yang tersisa. Biayanya 6 ms untuk Anima ringan dan 32 ms untuk Anima paling tebal (HP 404, pertarungannya menyentuh `BATTLE_MAX_TURNS`), sekali per `startBattle` dan tidak pernah pada resume/commit. Bentuk stat hiper-spesialis **tidak punya titik imbang sama sekali**: pada `95/95/95/10/10` duel cermin adalah fungsi tangga, 98% pada 1,007 lalu langsung ~30%, dan jarak-ke-target sendirian bisa memilih sisi 30% karena ia lebih dekat ke 65% daripada 98%. `preferBot()` karena itu memberi prioritas mutlak kepada kandidat yang masih dimenangkan ≥ `REWARD_TIERS.even.minWinRate`; disapu atas 400 bentuk acak, 8 (2%) tanpa pagar itu berakhir di duel 47%–52%, jadi cabangnya bukan hipotetis — duel mudah masih dibayar 6 Bits, duel yang tidak bisa dimenangkan tidak dibayar apa pun. Skenario 34 menuntut tier lawan sistem **tepat** `even` untuk roster production — `favorable` berarti pencarian mendarat di walkover, `formidable` berarti ia berhenti menjadi jalan keluar — plus sebaran rasio antar-Anima > 0,05 supaya kekuatannya tidak diam-diam kembali dipatok, plus `base_stats` bot identik pada lima kondisi care, plus tiga bentuk tangga hasil sapuan itu tetap dimenangkan ≥ 55%.
- **Team Battle dan Expedition adalah target terpisah, bukan cabang di resolver Duel.** `battle.mjs` tetap menjaga kontrak 1v1 dan pending session lama. Resolver team baru mengimpor formula canonical stat/damage/element, lalu menambah opponent roster 1–4, active slot, switch, dan party wipe. Team/Expedition pemain selalu membawa tepat 4 Anima; arena tetap 1 aktif per sisi. Switch sukarela memakan turn, forced switch sesudah KO gratis. Team Battle memakai Defense Team opt-in async, baseline cap 2 rewarded wins + 40 Bits/hari. Reward memakai rata-rata Level roster lawan; active hidup menerima `ceil(full/2)`, bench hidup `ceil(full/4)`, KO 0. Expedition memakai soft budget 30 total EXP roster/hari: encounter dibayar penuh selama sisa >0, berikutnya 0; Boss menerima satu payout normal per run meski budget habis, dijaga `boss_exp_awarded_at`. **Expedition membayar 30 Energy per anggota tepat sekali di `start_expedition_run`; Start Zone 1–3 dan Boss tidak memeriksa atau memotong Energy.** Idempotency mencegah debit ulang, dan roster terkunci selama status `checkpoint` maupun `active` sampai complete/abandon. Run lama tidak ditagih retroaktif. Expedition memakai tiga zona × empat node + boss, HP persisten dalam zona, dan checkpoint antar-zona. `ExpeditionView.set_run()` wajib `_busy = false` sebelum membangun tombol peta/choice: present terjadi sementara controller masih busy, dan `set_busy(false)` hanya menyentuh Abandon/chrome tetap — node yang sudah di-`disabled` saat `_render_map()` tetap redup. Start Zone memakai team run yang sama. Copy pemain memakai **Tokens**; wire tetap `supplies`. Config `expedition_energy_per_member` berarti biaya masuk run. Detail lengkap di [docs/09](docs/09-team-battle-and-expedition.md). Flag Team Battle, Expedition, dan chapter push default off sampai rollout masing-masing.
- **Chapter content adalah manifest immutable, bukan kode atau model call runtime.** Active run mengunci `chapter_id + content_version`; effect type di luar allowlist menuntut build/min-client baru. `anima_id` lawan chapter adalah slug konten, bukan UUID row `animas` — bandingkan sebagai text. Chapter Factory adalah developer CLI dengan cost preview, explicit paid flag, nol image auto-retry, review HTML, hash approval, lalu publish inactive → verify → activate. Boss Seeker memakai satu original 3×3 pose sheet + dialog event; referensi genre tidak boleh menjadi tiruan karakter/device/logo/komposisi IP lain. Binary tinggal immutable di Storage, sedangkan brief/prompt/approved manifest/hash ledger ada di Git.
- **Chapter release selalu punya jalur in-app; push hanya bonus opt-in.** Home popup tampil sekali per akun dengan receipt server lintas device, badge New bertahan sampai chapter dibuka, dan beberapa release tertinggal diringkas menjadi satu modal. Push memakai topic dan hanya membawa chapter ID/version; client tetap fetch manifest authoritative. Kegagalan push tidak boleh me-rollback chapter atau menyembunyikannya dari app.
- **Hanya tiga kemenangan Battle pertama per akun per hari sipil lokal yang memberi progression reward.** Hari itu 00:00 di `profiles.timezone_offset_minutes` (menit timur UTC, default 0), bukan jam device dan bukan UTC. Client hanya *melaporkan* `Time.get_time_zone_from_system().bias` lewat body care/battle; `set_profile_timezone()` yang menulis kolomnya, kunci 24 jam sesudah ganti, dan jangan grant kolom itu ke `authenticated`. Sesudah cap 3, duel tetap **Training**: EXP dan `battle_wins` nol, tetapi Bits masih dibayar sampai cap **100 Bits per hari lokal** (`app_config.battle_bits_per_day`, ledger `battle_train`). Payout terakhir dijepit sisa cap. Progression dihitung dari jumlah baris `reason = 'battle_win'`, bukan nominal Bits. `commit_battle_turn()` memegang profile row lock agar check + saldo + score + win + ledger tetap atomik. Angka 3 hidup di `app_config.battle_rewarded_wins_per_day`; jangan jadikan cap per-Anima karena pemain cukup mengganti companion. Session payload dan operasi `battle_anima/status` membawa `daily_reward` (`earned/limit/remaining/bits_earned/bits_limit/bits_remaining/server_now/reset_at/rewarded`). Lobby memakai satu CTA—`Battle` sebelum 3/3, `Train` (Bits only) sampai cap 100, lalu Training nol hadiah, atau `Choose Anima` kalau companion aktif tidak lolos preflight—beserta alasan dan reset tengah malam lokal; kemenangan ketiga tetap `Progress 3/3`, Training baru session berikutnya. Timer memakai selisih dua timestamp server dan refresh lagi saat app resume, bukan mempercayai jam device.
- **Copy Battle memakai Attack/Special/PP/Item, sementara wire value tetap `strike`/`surge`/`guard`/`item`/`momentum`.** Keduanya sengaja tidak disamakan. Wire value terpasang di CHECK constraint `battle_turns_action_valid`, di kolom `player_momentum`/`bot_momentum`, di `BATTLE_ACTIONS`, dan di `GameState.pending_battle` yang bisa sedang tersimpan di device pemain — menyeragamkannya dengan istilah UI berarti migrasi plus memecahkan session yang sedang berjalan, demi nol perubahan yang dilihat pemain. Identifier client (`MOMENTUM_MAX`, `SURGE_COST`) ikut nama server supaya masih bisa di-grep lintas runtime; kata player-facing hanya hidup di `locales/ui.csv`. Counter PP hidup **hanya** di tombol Special (`{surge_name} 3/3`, fallback `Special`); tombol Attack memakai `strike_name`. Label header yang mengulanginya sudah dihapus karena angka yang jauh dari tombolnya terbaca sebagai angka tanpa sebab. `startBattle` wajib `select` kolom `strike_name`/`surge_name` — menulisnya ke snapshot dari row yang tidak membacanya menghasilkan string kosong dan tombol jatuh ke Attack/Special. Kedua meter HP dicerminkan mengikuti konvensi Street Fighter: **sisa HP memeluk tengah arena dan damage memakan dari tepi luar layar ke dalam**, jadi bar pemain memakai `fill_mode = FILL_END_TO_BEGIN` dan bar bot memakai default `FILL_BEGIN_TO_END`. Versi kebalikannya terasa lebih intuitif ketika ditulis (sisa HP memeluk tepi luar, kosong bertemu di tengah) dan sudah dicoba lalu ditolak dengan referensi gambar: bukan itu yang dilakukan fighting game, dan pemain membacanya sebagai arah yang terbalik. Kalau ragu, ukur ulang piksel screenshot-nya, jangan menyimpulkan dari nama `fill_mode`-nya.
- **PP adalah budget per-battle, bukan meter yang mengisi sendiri.** Mulai penuh 3, Special memakan 1, dan **tidak ada regen per-turn** — satu-satunya pemulihan adalah Guard di `applyIntent()`. Jangan mengembalikan regen +1/turn: satu battle terukur selesai sekitar empat turn, jadi regen membuat PP membeku di angka awalnya, counter di tombol tidak pernah bergerak, dan Attack jadi tombol mati karena Special selalu tersedia sekaligus selalu lebih kuat. Karena PP hanya pulih lewat Guard, tombol Special mati saat PP habis; jangan mengembalikan copy `BATTLE_NO_MOMENTUM` di dock — aturan itu dijelaskan di wiki/menu, bukan di arena. `MOMENTUM_MAX`/`SURGE_COST` hidup di dua tempat yang wajib identik, `_shared/battle.mjs` dan `battle_view.gd`, sebab client yang lebih longgar akan menyalakan Special yang lalu ditolak server sebagai `NO_MOMENTUM` — mengubah salah satunya berarti `supabase functions deploy battle_anima` di langkah yang sama. **PP juga sengaja tidak persist antar battle**; alasannya beserta empat konsekuensi yang diukur dari kode ada di [docs/04](docs/04-game-systems-economy.md), jadi jangan mengubahnya jadi PP gaya Pokémon tanpa membaca itu dulu.
- **Initiative Battle mengikuti SPD, bukan selalu pemain dulu.** Ordered event log boleh dimulai bot jika SPD-nya lebih tinggi; pelat event menulis `{nama} moves first.` sebelum animasi supaya ini terbaca sebagai aturan, bukan event terbalik. HUD tetap `Name Lv. N`; pelat hanya nama polos. Semua sprite sheet dihasilkan menghadap forward-left: petarung pemain di sisi kiri harus `flip_h`, bot di kanan tidak, dan arah lunge mengikuti lawan. Loading art Battle tidak boleh memakai toast global milik Home/Scan. Result win/loss/forfeit menimpa footer berukuran tetap, bukan menjadi sibling `BattleContent`, supaya arena dan kaki kedua petarung tidak bergeser saat result muncul.
- **VFX Attack/Special adalah overlay tambahan, bukan ganti pose.** `set_pose("attack")` tetap menampilkan tubuh; `play_fx("fx_strike"|"fx_surge", impact_global)` menaruh sel efek sebagai sibling di bawah anchor petarung. Manifest v12 boleh memberi motion `projectile`, `sweep`, `impact`, atau `bloom`; `AnimaLoader` meneruskannya dan `AnimaPresenter` memilih tween tanpa mengubah event Battle. Manifest lama/tidak dikenal fallback ke `projectile`, dan sheet 2×2 tanpa sel melewati `play_fx` diam-diam. Semua mode mempertahankan beat tetap `FX_TRAVEL_SEC` supaya damage log tidak perlu protokol baru. Urutan Attack wajib `action plate → hide → attack pose → play_fx → FX_TRAVEL_SEC → idle pose → damage/effectiveness plate`; banner tidak boleh menutupi pose Attack dan pose tidak boleh tertahan sampai banner efektivitas selesai. Item memakai overlay yang sama dengan Super effective (`_show_banner`) plus `care_feedback("item")` — kilat emas dua kali pada Anima. Event `item` membawa `effect`/`effect_value`; client tetap punya fallback dari `item_id` kalau field itu kosong.
- **Guard memakai kilau shader, menang memakai lompatan tanpa akhir hanya untuk Hatchling.** Keduanya milik `AnimaPresenter`, bukan event Battle baru. `guard_shimmer()` dipasang di frame pelat Guard muncul — sebelum `await _present_banner`, bukan sesudahnya — supaya kilau dan copy-nya sejalan; `guard_shimmer.gdshader` hanya memetakan uniform `progress` 0→1 menjadi satu sapuan diagonal plus rim silhouette, sehingga waktunya tetap dimiliki Tween dan tidak ada `TIME` yang bisa tertinggal menyala. Shader wajib mengating piksel transparan lewat perkalian (`step(0.004, COLOR.a)`), bukan `return` — Godot menolak `return` di dalam `fragment()`. `victory_celebration(level)` memasang pose Happy lalu memilih gerakannya dari `CareRules.form_key(level)`: **hatchling** (Lv. 1–15) mendapat `_bounce(0, ...)` yang berulang selamanya, sedangkan **adult** (Lv. 16) dan **evolved** (Lv. 36) mendapat flourish membumi `VICTORY_FLOURISH_COUNT` × `VICTORY_FLOURISH_HEIGHT_PX` dengan `TRANS_SINE` — badan yang lebih besar tidak boleh memantul seperti bola. Level-nya dibaca dari `state.player.level` (Duel) atau `_active_member("player").level` (Team/Expedition), dengan fallback `care_score` row lobby. Hanya loop tanpa akhir yang sengaja **tidak** menyambung `_resume_pose_motion` dan menyalakan kill guard `_victory_loop` yang dilepas `set_pose()`; flourish yang selesai sendiri memakai `finished` seperti `play_bounce()`. Tanpa kill guard itu `_feedback` yang selamat menahan `plant_on_anchor()` dan memantulkan pose session berikutnya.
- **Kartu hasil Battle punya dua tombol, dan CTA-nya membaca Energy sesudah battle.** `BattleLeaveButton` / `TeamLeaveButton` (`BATTLE_RETURN_LOBBY`, flat 148×96 di kiri) duduk satu baris dengan retry yang `SIZE_EXPAND_FILL`; Duel memancarkan `exit_requested` ke `scan_flow._leave_battle()` dan Team memakai `back_requested` yang sudah ada. Expedition sengaja tidak punya tombol kedua karena `EXPEDITION_RETURN_MAP` sudah jalan keluarnya — `_set_result_actions_visible()` menyembunyikannya lewat `_expedition_mode`. Android back di session terminal memakai jalur yang sama (`BattleView.can_leave_result()`), bukan meninggalkan session menggantung. Karena `set_lobby()` hanya dipanggil sebelum start, result CTA butuh row terbaru: `BattleView.set_companion()` (dari `_refresh_stats`/`_refresh_care`) dan `TeamBattleView.set_roster()` (dari `_reload_roster`) menyuntikkannya lalu memanggil ulang `_apply_result_actions()`. Kalau `CareRules.battle_unavailable_key()` / `_team_member_unavailable()` menolak, retry menjadi `BATTLE_CHOOSE_ANIMA` / `TEAM_EDIT` plus satu baris `BATTLE_RESULT_BLOCKED % chip` — **chip pendek** (`BATTLE_PICK_*`), bukan kalimat penuh, sebab panel result 236px tumbuh ke atas menutupi arena. Team lobby ikut me-disable `Start` selama `_team_blocked_key()` tidak kosong, dan itu fail open saat roster belum ter-refresh karena server tetap pagar terakhirnya. Visual gate gratisnya `--battle-blocked-demo` dan `--team-result-demo`.
- **Arena adalah fokus tunggal layar Battle aktif.** Header `Battle Arena` + subtitle hanya tampil di lobby. Shop dan Bag hanya ada di Home, jadi Battle tidak menyisakan gutter kosong atau menimpa Retreat; Retreat rata kanan di baris atas (tanpa Turn), lalu fighter HUD; footer hanya empat aksi 96px (Attack, Special, Guard, Item). Copy idle `Choose your action` / training hint dan `BattleFeedback` tidak ditulis. Fighter HUD adalah satu strip versus tanpa `PanelContainer` per monster: identity kiri/kanan hanya nama + Level tanpa ikon/nama elemen, HP mirrored menuju tengah, dan nilai authoritative `current / max` ditumpuk di dalam bar seperti Team Battle/Expedition. Counter harian, tier lawan, dan calon payout tidak tampil di arena karena tidak mengubah keputusan turn; hasil menulis reward aktual, sedangkan lobby menjelaskan perpindahan Battle → Train dan sisa Bits. Retreat tetap punya hit area 96px tetapi tampil sebagai teks datar, bukan panel merah besar. Result berukuran 236px tumbuh ke atas dari footer dengan `z_index` di atas fighter sehingga muat tanpa mendorong arena, tertutup Anima, atau tertutup bottom nav. Copy event Duel/Team/Expedition memakai satu set `BATTLE_EVENT_*` (`{nama} uses {move}.`, `{nama} moves first.`, Guard/item/Switch/KO/timeout) plus `Super effective!`/`Not very effective.` di Oxanium ExtraBold ber-outline di atas pelat theme `BattleEventPlate` gelap tepat di bawah fighter HUD; label child pelat, clip, wrap 2 baris. Setiap label hold 1,4 detik (`ACTION_CUE_SEC`) setelah fade-in selesai sebelum pose/VFX/Summon/KO/hide. Angka damage mengambang di Duel, Team, dan Expedition. Tilt/pop, warna, damage punch, dan haptic dibaca dari `element_multiplier` event server. Client tidak menduplikasi roda elemen.
- **Team Battle memakai command lock yang sama dengan Duel.** `begin_action()` dipanggil di tap, sebelum request; tombol terpilih mendapat underline pulse, tombol lain diredupkan tanpa visual disabled, dan tidak ada copy `Attack locked in` / `Resolving turn`. `begin_action` idempotent supaya submit/replay tidak merestart tween. Retreat Duel/Team/Expedition membuka `UiModal` konfirmasi dulu (`BATTLE_RETREAT_TITLE`); body Expedition memakai `BATTLE_RETREAT_CONFIRM_EXPEDITION` karena forfeit mereset zona saat ini ke awal. Cancel kembali ke arena. Retreat Team/Expedition adalah tombol biasa di paling kanan baris Item/Switch. Grid aksi 3+3: Attack/Special/Guard lalu Item/Switch/Retreat. Pip tim duduk di atas nama Anima. Picker Switch adalah overlay di root `TeamBattleView` (Control, bukan child `TeamArena` VBox — FULL_RECT di VBox jadi row tinggi 0) berisi `BottomSheetPanel` full-width menempel bawah: grid 2×2 berisi art, status In battle/Ready/KO, dan meter HP, `z_index` 10 di atas sprite fighter, tanpa scrim gelap, dan di-clip supaya tidak overflow ke bawah layar. `UiModal` `z_index` 20 supaya konfirmasi Retreat tidak tertutup Anima. Sesudah konfirmasi Retreat, arena menampilkan `BATTLE_RETREATING` di pelat event yang sama dengan Super effective sampai response forfeit kembali. Tombol aksi tetap di layout supaya arena tidak bergeser. Switch sukarela punya Cancel (dan Android back) untuk kembali ke aksi; forced replacement setelah KO tidak, karena server menuntut `switch`. Kalau hanya satu anggota yang masih hidup, client mengirim `switch` ke slot itu tanpa picker. Event `switch` menampilkan copy dan hold 1,4 detik setelah pelat terlihat, baru memainkan `summon_dissolve` + portal `IncubatorEffect` di `body_center_global()` incoming + `summon_reveal`. Event `knockout` langsung memasang pose Defeated sebelum pelat KO muncul, lalu menahan pelat 1,4 detik dan faint tambahan ~1,2 detik sebelum `play_events` melepaskan `_busy` dan membuka picker forced-switch. Jangan `set_session` + `_open_switch_picker` saat masih busy: picker batal dan seluruh aksi termasuk Switch tetap terkunci. HUD nama memakai `Name Lv. N`. `_apply_side` memakai Defeated saat HP 0 supaya `set_session` tidak mengembalikan Idle. Item Battle membuka Bag tanpa tombol Shop. Arena aktif Team/Expedition adalah full-bleed: shell TopHud, chip resource, BottomNav, border `ModalPanel`, judul mode, dan copy `TEAM_CHOOSE_ACTION` disembunyikan; **Retreat** di paling kanan baris `Item`/`Switch` adalah satu-satunya jalan keluar. HUD pip-di-atas-nama plus HP full-width di pelat gelap; Expedition menurunkan pelat itu untuk `{judul} — Zone {n}` atau `{seeker} · Final Battle`. `_chapter_title()` mencocokkan katalog `id` atau `version_id` ke `run.chapter_version_id` sesudah `set_catalog()` mengosongkan `_chapter`. Anima punya ground shadow, dan aksi memakai grid 3+3 tanpa `PrimaryButton` yang membuat Special terlihat beda. Turn Attack/Special tidak `await` prepare art kecuali event `switch` — cache yang sudah di arena dipakai langsung supaya animasi tidak menunggu unduhan. Copy event Attack/Guard/Item/KO/Switch memakai plate arena yang sama dengan Super effective, bukan `TeamFeedback` di atas tombol; judul picker Switch hanya sekali. VFX menarget `body_center_global()` (bbox opak pose) dengan overlay `offset = 0`. Ground shadow `z_index = 0` dan mengikuti lebar tubuh supaya tidak ketutup art zona. `scan_flow._is_immersive_arena()` memutus chrome dari `TeamBattleView.is_arena_open()` atau `ExpeditionView.is_combat_open()`. Banner Super effective / Not very effective memakai helper Duel (`BattleView.effectiveness_key` + `item_banner_text`) di bawah fighter HUD. Jangan menunggu respons server sebelum feedback perintah, dan jangan menulis animasi Summon kedua.
- **Pending Battle bertahan sampai response authoritative, tetapi boot tetap Home.** `GameState.pending_battle`, `pending_team_battle`, dan `pending_expedition` tetap menyimpan session/operation/action/key ketika timeout atau app mati. Startup tidak membuka Battle dan tidak me-replay intent jaringan; lobby Battle menampilkan **Continue Battle**, **Continue Team Battle**, atau **Continue Expedition**, meredupkan mode lain, lalu baru menjalankan resume/replay idempoten setelah pemain memilih Continue. Duel tetap dapat kedaluwarsa sesudah TTL 30 menit. Hanya Battle action yang dikunci saat request; tab lain tetap bisa dibuka karena shell persisten. **Care Dock tidak diredupkan** — meter dan hop-nya sudah bergerak, jadi tombol mati sesudahnya hanya terbaca sebagai loading; yang menjaga satu care in-flight adalah `GameState.pending_care`, dan pemeriksaannya duduk di `_commit_care` supaya Bag yang memanggilnya langsung ikut terpagari. Saat pemain memilih aksi, tombol itu langsung mendapat underline pulse dan haptic; tombol lain diredupkan dan input ketiganya diabaikan tanpa memakai visual disabled. Jangan tulis `Special charged` / `Resolving turn` — itu terasa seperti loading. Ini feedback command, bukan prediksi damage atau initiative—event server tetap satu-satunya hasil turn. Session terminal menghapus pending state. Sesudah event log selesai, `_busy` dilepas sebelum reward/inventory menyusul supaya tap Special berikutnya tidak membeku tanpa request. Inventory hanya di-refresh setelah aksi `item`, tanpa refetch katalog.
- **Play tidak ditutup Bond.** Meter Bond hilang dari UI; JSON menulis `bond: 0`. Anti-farm Play adalah Energy -5 dan +1 EXP maksimal lima kali per hari sipil lokal. `CareRules.play_exp_used()` membandingkan `play_score_on` ke tanggal sipil device hanya sebagai preflight; grant tetap `local_civil_date` di `apply_care()`. Care Dock bangun selalu empat kolom satu baris (Feed/Clean/Sleep/Play); jangan wrap 2×2. **Shop** adalah tombol seukuran chip Bits, overlay tepat di bawahnya di kanan; **Bag** sama ukurannya, rata kiri di pojok kiri atas, sejajar dengan Shop. Keduanya hanya tampil di Home dan tidak menyisakan gutter di Scan/Battle/Collection/Anima. `GameState.shop_locked()` menolak beli selama `pending_battle` / `pending_team_battle` / `pending_expedition` ada — prep item sebelum Start. Trail Shop Tokens di peta Expedition tetap jalan. Shop hanya jual; Feed / Use Energy dari Bag; item Battle di Bag tanpa tombol Use. Chip Shop memakai ikon `shopping-bag`, Bag memakai `backpack`, Name kosong supaya teksnya center, jarak ikon 8 px. Label Play tetap `Play` tanpa `x/y`. Saat cap harian tercapai, atau Hunger/Hygiene tampil penuh, tombolnya hanya redup — Godot menelan `pressed` kalau `disabled` — dan tap memunculkan toast tanpa request care. Saat tidur Feed/Clean/Play disembunyikan dan Wake memakai lebar penuh.
- **Shop mengikuti saldo Bits authoritative terakhir.** `ShopSheet.set_catalog()` menerima saldo bersama katalog/inventory dan men-disable tombol harga yang melebihi saldo; saldo 0 berarti seluruh tombol beli redup. Server `purchase_catalog_item` tetap pagar akhir terhadap saldo stale/request palsu. Sesudah sukses, saldo response langsung membangun ulang Shop dan `FEEDBACK_PURCHASE` wajib menjadi toast transient 2,8 detik—jangan panggil `_say()` tanpa `true`, karena default-nya status persisten.
- **Decay tidak butuh cron.** `apply_care()` menghitung selisih dari `care_synced_at`: cap 48 jam, Hunger 4/jam saat aktif, Energy 7,1/jam saat bangun, Hygiene 4,2/jam. Anima yang tidak di-Summon memakai Hunger 1/jam dan Hygiene 1,05/jam, tidak turun di bawah Hunger 40 / Hygiene 50, dan tidak masuk Dormant baru. Floor menahan decay, tidak mengangkat meter yang sudah di bawah ambang. Bonus terawat +8 dan pemulihan Dormant hanya untuk companion aktif; sync Collection tidak boleh jadi mesin EXP. Tidak ada grace — sync yang sering tetap memotong kebutuhan companion aktif, supaya Feed/Clean terasa. Sleep memulihkan Energy linear sampai penuh dalam 6 jam; +5 EXP hanya pada completion pertama tiap hari lokal, tetapi completion berikutnya tetap memulihkan Energy. Hunger dan Hygiene companion aktif tetap turun selama tidur. Anima yang **tidak di-Summon** ikut tidur (Energy pulih dalam 3 jam, tanpa auto-bangun, tanpa +5 EXP) supaya Collection tidak jadi mesin EXP. Collection menampilkan Idle begitu Energy penuh supaya pemain tahu Anima itu siap di-Summon; row Postgres tetap tidur. Client memasang satu `Timer` dari selisih dua timestamp server (`care_synced_at - sleep_started_at`) lalu sync tepat di batasnya; resume Android/iOS juga memicu sync, jadi jam device tidak dipercaya dan background tidak membuat Anima tertahan tidur. `dormant_since` terpisah dari generation `status`, **tidak** mereset EXP, dan hilang setelah Hunger serta Hygiene sama-sama >=50.
- **Art cache tidak boleh menebak pose saat cold start.** `GameState.last_anima` hanya pilihan terakhir dan sengaja tidak menyimpan care. Menampilkan sheet itu sebelum roster server datang selalu memulai Idle, sehingga Anima tidur terlihat bangun sekelebat. Sprite tetap tersembunyi sampai `_present()` memiliki row authoritative dan menerapkan Sleep/Dormant pada frame yang sama.
- **`rls_auto_enable()` bukan buatan kita.** Ia event trigger bawaan bootstrap Supabase yang menyalakan RLS otomatis pada setiap tabel baru di `public`. Terukur: peran `authenticated` bisa memanggilnya sebagai fungsi biasa dan ia selesai tanpa error maupun efek (`pg_event_trigger_ddl_commands()` kosong di luar konteks trigger). EXECUTE-nya sudah dicabut di migrasi `harden_platform_rls_helper`, dan event trigger-nya diverifikasi tetap menyala sesudahnya — hak eksekusi event trigger diperiksa saat `create event trigger`, bukan saat ia menyala.
- **Advisor `rls_enabled_no_policy` pada `app_config`, `care_events`, `battle_sessions`, `battle_turns`, dan `shop_purchases` itu disengaja.** RLS aktif tanpa policy sama sekali adalah cara menutup tabel dari client; jangan "perbaiki" dengan menambahkan policy baca. Tabel event/session/receipt internal hanya diakses transaction function service-role.
- **Enam WARN `auth_allow_anonymous_sign_ins` juga disengaja, dan "memperbaikinya" akan mematikan game.** Advisor memberi peringatan untuk `profiles`, `animas`, `generations`, `quota_ledger`, `pending_discoveries`, dan `species_library` karena policy-nya `to authenticated`, dan user anonim memakai peran itu. Di Scanima user anonim **adalah** pemainnya — bukan tamu yang menyusup. Yang membatasi tetap `auth.uid() = owner_id`, jadi pemain anonim A tidak bisa membaca data pemain anonim B; `species_library` memang dibaca semua orang karena ia pustaka art bersama. Menambahkan `and not (auth.jwt() ->> 'is_anonymous')::boolean` akan menutup satu-satunya jenis akun yang dimiliki game ini.
- **Satu INFO performa dibiarkan sadar:** `generations.anima_id` tanpa indeks penutup. Ia hanya menyakitkan saat baris `animas` dihapus, dan itu jalur langka; tambahkan indeksnya kalau fitur melepas Anima jadi rutin. Foreign key `battle_sessions.bot_anima_id` sudah punya indeks penutup sendiri.

- **Setiap request terautentikasi memeriksa umur token, bukan hanya saat boot.** `Backend._send()` memanggil `ensure_session()` sebelum mengirim, mengganti header dengan token terbaru, lalu memberi satu bounded refresh+retry jika gateway masih menjawab 401. Ini mencegah Battle panjang mati tepat saat access token habis. Refresh token yang ditolak tetap tidak boleh dijawab dengan sign-in anonim baru: itu akan meninggalkan seluruh Anima di akun yang tidak bisa dijangkau lagi.
- **Node autoload SUDAH ada dalam mode `--script`, tetapi nama globalnya belum.** Menulis `GameState` di skrip yang dijalankan `--script` gagal saat kompilasi dengan `Identifier not found`, sebab skrip itu dikompilasi sebelum autoload terdaftar sebagai global — sementara node-nya sendiri terpasang di bawah root dan bisa diambil dengan `get_root().get_node("GameState")`. Itu yang dipakai `tests/test_client_state.gd`, `tests/live_scan.gd`, dan `tests/live_battle.gd`. Konstanta dan fungsi statis diambil dari `get_script()`, bukan dari instance-nya.
- **Skrip `--script` jalan lebih awal daripada saat node autoload benar-benar masuk tree.** `HTTPRequest` yang ditambahkan di titik itu menolak dengan `ERR_UNCONFIGURED` (`Condition "!is_inside_tree()" is true`). Satu `await process_frame` di awal harness menyelesaikannya; scene sungguhan tidak pernah kena karena `_ready()` jalan setelah tree berdiri.
- **`CameraServer` SUDAH mendukung Android sejak setelah 4.4, dan tetap bukan yang dipakai.** Catatan lama di file ini salah; dokumentasi stable kini menyebut `CameraFeed` terimplementasi di Linux, Android, macOS, dan iOS. Alasan tidak memakainya bukan ketiadaan API: ia memberi feed hidup, sementara yang dibutuhkan satu jepretan, jadi memakainya berarti membangun sendiri UI fokus, eksposur, dan tombol jepret yang sudah gratis dari aplikasi kamera OEM — dengan frame preview yang resolusinya di bawah kamera still-nya. Ia juga masih berdarah: PR #110720 baru memperbaiki stride `YUV_420_888` yang mengacaukan gambar di perangkat dengan padding, dan issue #114468 mencatat pergantian feed rusak sejak fitur ini lahir.
- **Kamera lewat `addons/GodotGetImage` ([fork PhotoPicker](https://github.com/cenullum/GodotGetImagePlugin-Android-PhotoPicker)), dan `.aar`-nya ikut di-commit.** Fork, bukan upstream, karena manifest upstream menyuntikkan `READ_MEDIA_IMAGES` ke APK **walau `getGalleryImage()` tidak pernah dipanggil** — Godot menggabungkan manifest plugin saat export — dan Play menolak izin itu untuk keperluan pilih-satu-foto. Manifest fork sudah diperiksa: hanya `CAMERA`, `minSdkVersion` 21, kamera ditandai opsional. Arsipnya 27 KB dan prebuilt untuk 4.6.2 persis, jadi tidak ada langkah Gradle; ia di-commit supaya build tetap reproducible kalau repo pihak ketiganya hilang. Plafonnya: `.aar` terikat versi Godot, jadi naik versi engine berarti menunggu atau membangun ulang arsip yang cocok.
- **Google auth memakai vendored OAuth2Plugin v1.1 + DeeplinkPlugin v5.3 untuk Godot 4.6.** Token store native-nya AES-GCM/Android Keystore dan iOS Keychain; jaringan PKCE tetap lewat `Backend`, bukan helper OAuth plugin. AAR OAuth lokal membuang `ACCESS_NETWORK_STATE` yang tidak dipakai dan editor plugin tidak menarik AppCompat karena bytecode AAR tidak punya referensi AndroidX; hash hasil patch dicatat di `VENDOR.md`. Guard lokal Deeplink mencegah hook iOS memproses path `.apk`. Naik versi plugin berarti reapply patch dan verifikasi izin/class/deep-link lagi.
- **`resendPermission()` ada di README plugin tapi `private` di `.aar` yang dirilis.** Memanggilnya dari GDScript gagal saat runtime. Terverifikasi lewat `javap` pada `classes.jar`: yang publik hanya `setOptions`, `getGalleryImage`, `getGalleryImages`, `hasCamera`, `getCameraImage`. Pemulihan setelah izin ditolak adalah memanggil `getCameraImage()` lagi — permintaan izinnya menempel di sana — jadi UI harus menyuruh pemain menekan tombolnya sekali lagi, bukan memanggil metode yang tidak ada.
- **Ketiga signal plugin membawa argumen, termasuk yang izin.** Dari bytecode `getPluginSignals()`: `image_request_completed(Dictionary)`, `error(String)`, dan `permission_not_granted_by_user(String)` — yang terakhir tidak terbaca demikian dari README. Arity yang salah membuat `connect` gagal dan handler-nya tidak pernah terpanggil, tanpa galat yang jelas.
- **Tombol foto TIDAK dikunci saat kamera terbuka.** Kamera itu Activity terpisah dan pembatalan tidak memancarkan signal apa pun, jadi kunci yang dipasang saat permintaan dikirim akan mati selamanya bagi pemain yang berubah pikiran. Kuncinya dipasang di `_scan_bytes`, saat byte-nya sudah ada.
- **Izin `INTERNET` MATI secara default di ekspor Android Godot 4, dan ini kegagalan yang paling mahal waktunya.** APK pertama yang dibangun di sini keluar dengan `CAMERA` sebagai satu-satunya izin: ia terpasang, terbuka, lalu mati di sign-in anonim — tanpa dialog izin, tanpa crash, cuma galat jaringan yang menyesatkan, sebab Android menolak socket-nya secara senyap. Preset **wajib** memuat `permissions/internet=true`. `export_presets.cfg` di-gitignore, jadi tidak ada uji di repo yang bisa menjaga ini; catatan ini adalah pagarnya, dan `aapt2 dump permissions` sesudah build adalah pemeriksaannya.
- **Terverifikasi ulang pada APK Google/Seeker: tepat dua izin, `INTERNET` dan `CAMERA`.** Nol `READ_MEDIA_IMAGES`, nol `READ_EXTERNAL_STORAGE`, nol `ACCESS_NETWORK_STATE`. Kelas `GodotGetImage`, `OAuth2Plugin`, dan `DeeplinkPlugin` terkonfirmasi di DEX; manifest memuat `scanima://auth/callback`; APK juga lolos `apksigner verify`. Periksa semuanya setiap kali plugin atau versi engine berubah.
- **Template Android 4.6.2 mematok Gradle 8.11.1, jadi JDK-nya tidak boleh lebih baru dari 23.** Mesin ini punya JDK 26 dan build-nya berhenti di `Unsupported class file major version 70` sebelum menyentuh kode kita. Yang dipakai: `brew install openjdk@17` — **formula, bukan cask `temurin@17`**, sebab cask memasang ke `/Library/Java/...` dan menuntut sudo sementara formula tidak. JDK 26 **tidak** perlu dihapus walau banyak jawaban forum menyuruhnya: Godot punya setelan `Java SDK Path` sendiri, jadi keduanya hidup berdampingan. Alternatif menaikkan `distributionUrl` di `gradle-wrapper.properties` menukar satu masalah pasti dengan pasangan Gradle/AGP yang tidak diuji siapa pun.
- **Godot membaca `ANDROID_HOME` tapi TIDAK membaca `JAVA_HOME`.** SDK-nya terdeteksi sendiri; jalur JDK harus ada di `export/android/java_sdk_path` pada `editor_settings-4.6.tres` (nama file-nya per-minor, bukan `editor_settings-4.tres`). Menulisnya lewat file **hanya aman saat editor tertutup** — editor menyimpan setelannya sendiri ketika keluar dan akan menimpa suntingan dari luar. `export/android/debug_keystore` juga sudah diisi sendiri oleh editor ke keystore yang belum ada; ia dibuat lambat memakai `keytool` dari JDK, jadi preset di sini menunjuk `~/.android/debug.keystore` yang nyata ada supaya hasilnya deterministik.
- **APK sideload memakai native-library compression.** `export_presets.cfg` wajib memuat `gradle_build/compress_native_libraries=true`: pada debug APK, 71,47 MB dari total 76 MB adalah `libgodot_android.so`, dan opsi ini diperkirakan menurunkan berkas transfer ke sekitar 30 MB. Trade-off-nya startup sedikit lebih lambat dan ukuran terpasang tidak banyak berubah; untuk AAB Play Store, evaluasi ulang dan umumnya biarkan library tidak terkompresi.
- **Basis UI 720×1602 (Xiaomi 14 20:9, native 1200×2670) berarti angka Godot kira-kira 2× target dp Android.** Viewport tetap 720 lebar supaya tombol 96 px tidak mengecil; tinggi mengikuti rasio 2670/1200. Stretch `keep` mengunci crop saat window di-resize — jangan kembalikan `expand`, itu yang membuat background dan arena berubah tiap tarik window. Window override 1200×2670 adalah ukuran play Xiaomi 14. Target Material minimum 48dp menjadi `custom_minimum_size.y = 96`, body/button 16sp menjadi sekitar 32 px, spacing 8dp menjadi 16 px. Default font Godot 16 px yang lama setara kira-kira 8sp dan memang terlalu kecil, bukan sekadar selera. Angka bersama hidup di `themes/mobile_theme.tres`; jangan mengecilkan satu tombol secara lokal.
- **`mobile_theme.tres` adalah satu-satunya sumber visual UI.** Palette-nya deep navy + cyan/violet + gold, body memakai Nunito Sans, display memakai Oxanium, dan variasi semantiknya (`PrimaryButton`, `CareDock`, `BottomNavPanel`, empat Care button, `ToastPanel`, `NeedChip` / `NeedChipLow`) dipakai seluruh shell. Ikon Lucide SVG + lisensinya hidup di `game/assets/icons/`; jangan kembali ke Unicode pseudo-icon atau override StyleBox per-node untuk chrome umum. Ikon itu hanya untuk chrome — **elemen sengaja label-only**: delapan belas roster berarti delapan belas aset yang harus dijaga konsisten, sementara namanya sudah cukup di setiap layar yang menampilkannya, jadi `ElementCatalog` tidak punya `icon()`/`apply_icon()` dan `assets/icons/element-*.svg` sudah dihapus. Override lokal tetap hanya empat warna meter yang membawa makna gameplay. `NeedChipLow` menyala pada ambang pose/Battle yang sama (`CareRules.need_is_low`: Hunger < 40, Hygiene < 50, Energy < 20), tanpa ambang baru. `PrimaryButton` wajib menentukan `font_focus_color` serta focus style sendiri—fallback putih di atas cyan membuat label focused tidak terbaca.
- **Chrome interaktif bersama hidup sebagai komponen scene.** `UiModal` menangani info/confirm/input dengan backdrop, Cancel, focus, dan aksi 96px; Core info, Bits info, Delete, Rename, dan bantuan Profile memakai satu instance shell. `ResourceChip` dipakai Animas/Cores/Bits plus chip Shop dan Bag; Animas membuka Collection, Cores dan Bits membuka info. `ResourceChip` menengahkan isinya di dalam target 96px, bukan menempel ke atas. `UiBottomSheet` memiliki chrome slide/dismiss, handle 96px, rhythm 8px setelah handle + 16px antar-konten, surface `BottomSheetPanel` dengan sudut bawah rata, dan safe-area bawah hasil konversi piksel fisik ke viewport. Sheet panjang memakai `scroll_content`: body dibatasi 92% tinggi host, `follow_focus` menjaga field di atas keyboard, dan hanya handle yang menerima drag supaya gesture tidak berebut dengan scroll. Collection sudah hidup di dalam `SafeMargin`, jadi sheet embedded itu mematikan padding safe-area keduanya. Shop/Bag tidak membuat nested scroll: `ShopScroll` internal menargetkan tinggi 560px, menyusut agar panel tetap di bawah cap host 92%, dan hilang saat katalog mode aktif kosong. `UiSkeleton` loading bounded tanpa `_process`, dan `InfoValueRow` menyusun label, value rata kanan pada kolom lebar tetap, lalu tombol bantuan redup paling akhir supaya kolomnya tetap sejajar walau panjang value berbeda. FileDialog native, toast, Battle panel, dan efek procedural tidak dipaksakan masuk komponen ini.
- **Klik tombol memakai empat SFX Kenney Interface (CC0) di `game/assets/audio/ui/`.** `UiJuice` memainkannya dari `button_down` pada satu `AudioStreamPlayer` di root (`UiClickPlayer`, −18 dB plus `CUE_TRIM_DB`): `tap` untuk nav/default (`glass_002`), `care` untuk `Care*Button` (`pluck_001`), `confirm` untuk `PrimaryButton`, `back` untuk Cancel/Back/Dismiss/Leave/`DangerButton`. Bukan AudioManager; tap kedua memotong yang pertama. Tidak ada bus UI sampai settings volume ada.
- **SFX gameplay hidup di `Sfx` (`game/scripts/sfx.gd`), bukan di tombol.** Sembilan one-shot Kenney CC0 di `game/assets/audio/sfx/`, tiga voice di root (`SfxHost`, −10 dB plus `CUE_TRIM_DB`). Hook kanonis: Attack/Special → `AnimaPresenter.play_fx()`, Guard → `guard_shimmer()`, Feed/item → `care_feedback()`, Super effective / Not very effective → `hit_react(multiplier)`, portal Summon+Switch → `IncubatorEffect.start_portal()`, Level Up → `scan_flow._celebrate_level_up()`. Restyle UI atau pindah dock tidak boleh memindahkan `Sfx.play` ke `Button.pressed`; `test_scan_ui.gd` memindai hook itu. Aturan yang sama di `.cursor/rules/sfx-presentation.mdc`.
- **Lagu latar hidup di `MusicDirector`, dan cue-nya di-poll, bukan di-push.** Tiga track di `game/assets/audio/music/` (`lobby_lantern_save_point`, `battle_chromatic_arena_run`, `boss_forge_of_victory`) diputar dua `AudioStreamPlayer` yang saling crossfade 0,9 detik di bus `Music` (`default_bus_layout.tres`, −12 dB supaya SFX duduk di atasnya). Node-nya dibuat `scan_flow` lewat `add_child()` seperti `ExpeditionController`, **bukan autoload** — musik hanya hidup di dalam shell. Cue dipilih `scan_flow._music_cue()` yang dipanggil timer 0,25 detik: di luar tab Battle selalu `lobby`, Expedition combat dan Team arena memakai `boss` kalau `encounter_kind()`/`session_kind()` bernilai `boss`, sisanya `battle` selama ada session. Sengaja tidak di-push dari 21 pemanggil `set_session`/`set_lobby`: satu cabang baru yang lupa memanggil akan menghasilkan layar sunyi tanpa galat. Tiga hal wajib: **satu Tween per player** (`_fades`) sebab satu tween bersama kehilangan `stop()` outgoing begitu cue kedua membunuhnya mid-fade, dan track lama lalu terus berbunyi di bawah yang baru pada volume tempat ia membeku; **posisi tiap cue diingat** sebab lobby berdurasi 7 menit dan restart tiap keluar battle berarti pemain hanya pernah mendengar menit pertamanya; dan **`loop` diset di `_stream()`**, bukan di `.import`, supaya tiga aset itu tetap default import dan tidak bisa lepas satu sama lain. `set()` gagal **diam-diam** untuk properti yang tidak ada — terukur: mengetik `looop` tidak memunculkan satu galat pun — jadi `test_scan_ui.gd` menegakkan `stream.loop` benar-benar true, bukan hanya bahwa track-nya berbunyi. Toggle pemain `GameState.music_enabled()` default menyala, tersimpan sebagai preference device.
- **Musik wajib OGG Vorbis, bukan MP3, dan itu bukan soal ukuran file.** Setiap MP3 membawa encoder delay yang decoder putar ulang sebagai hening pada tiap loop; ketiga aset asli terukur `start: 0.023021` (1105 sample @ 48 kHz). Vorbis `-q:a 4` membuat `start` menjadi 0,000000 dan sekalian membuang cover art MJPEG 360×360 yang ikut terbawa ke APK. `ffmpeg` tidak ada di mesin ini dan brew gagal memasangnya; yang dipakai binary prebuilt sekali pakai lewat `npm install ffmpeg-static` di `/tmp`, tidak ditambahkan ke repo. Aset MP3 sumber tidak ikut di-commit.
- **Jeda loop yang pemain dengar bukan hening, melainkan ending yang ikut dipotong ke dalam loop.** Membuang hening di bawah −50 dB saja **tidak cukup** dan sempat dikira selesai: ketiga track ditulis dengan outro yang meluruh, jadi ambang itu melewatkan bagian −25…−43 dB yang secara angka bukan hening tetapi terdengar persis seperti lubang. Diukur pada battle: 400 ms terakhir jatuh ke −25,5 dB sementara awal track −15,5 dB. Titik potong yang benar berada **sebelum** outro dan **tepat di batas bar**, sebab loop yang wrap di tengah bar terdengar tersandung. Grid ketukan dicari dari onset envelope (beda maju setengah-gelombang) dengan BPM dibatasi kelipatan 0,5 dan panjang loop dipaksa bilangan bulat bar; battle keluar 75,00 BPM dan lima kandidat teratas semuanya menunjuk panjang yang sama, jadi itu bukan artefak pencarian. Hasil: battle 9 bar = **28,800 s**, boss 19 bar = **63,333 s**, lobby 118 bar = **401,710 s**. Tiap file lalu ditutup crossfade 40 ms yang menumpangkan potongan tepat sesudah titik potong ke awal loop, sehingga sambungannya kontinu per sampel dan tidak ada klik. Verifikasinya menyambung file dengan dirinya sendiri lalu mengukur envelope melintasi sambungan: battle berubah dari lubang −26,4 dB menjadi naik landai −22,6 → −18,7 dB. Ini membuang ending yang dikomposisikan, dan itu disengaja — ending tidak pernah terdengar sebagai ending pada track yang berputar terus. 12,12 MB → 6,08 MB. Debug APK sudah diekspor dan diverifikasi memuat keenam belas stream sebagai `.oggvorbisstr` plus `default_bus_layout.res`; audio menaikkannya ke 38 MB, dan izinnya tetap tepat `INTERNET` + `CAMERA`.
- **Level musik dan SFX dipilih dari pengukuran, bukan dikira-kira.** Ketiga track dinormalkan ke **−17 LUFS** (terukur −16,8/−16,9, selisih 0,1 dB) supaya crossfade lobby→battle→boss tidak melompat; sebelumnya battle −13,5 dan lobby −14,6 dengan peak +1,0 dBFS alias sudah clipping. Bus `Music` −12 dB, `SfxHost` −10 dB, `UiClickPlayer` −18 dB. Yang tidak kelihatan tanpa mengukur: SFX Kenney sudah peak-normalised ke ~−1 dBFS semua, sehingga RMS-nya tetap berjarak 10 dB — `sfx_strike` −21,6 dB versus `sfx_guard` −11,5 dB, jadi suara paling sering di battle justru yang paling tenggelam, dan menaikkan bus saja hanya memperbesar jarak itu. `Sfx.CUE_TRIM_DB` dan `UiJuice.CUE_TRIM_DB` meratakan tiap cue ke sekitar −19 dB RMS; trim bernilai 0 adalah aset yang peak-nya sudah mentok dan **tidak bisa** dinaikkan lagi. `test_scan_ui.gd` mengunci urutannya (chrome < gameplay, gameplay > bus musik), bukan angkanya, supaya mixing bisa disetel telinga tanpa mengedit test.
- **Semua micro-interaction Control dimiliki `UiJuice`.** Ia memasang press squash, release bounce, hover/focus, reveal, bottom-sheet slide, klik tombol, dan tween meter sekali secara rekursif; tween lama dibunuh sebelum writer baru. `UiBottomSheet.open()` menunggu satu–dua `process_frame` setelah overlay terlihat dan memaksa FULL_RECT: instance tersembunyi (Atlas) di Android bisa tetap size 0 di kiri atas kalau parent scene tidak mengulang anchor. Shop/Bag membuang dan membuat ulang row dengan `queue_free()`, lalu Container baru menghitung tinggi akhirnya di frame end. Tween yang dimulai sebelum itu menyimpan target tinggi lama; deferred layout menggeser anchor di bawah tween dan sheet pertama terlihat melayang, sedangkan buka kedua benar. `show_bottom_sheet` tidak boleh return dini saat overlay size 0 — itu menaruh panel di (0,0); rest Y memakai parent lalu viewport.
- **Tap tepat pada Anima Home hanya memberi feedback lokal.** `AnimaPresenter.hit_test()` memakai frame aktif dengan padding touch dan `make_canvas_position_local()`, bukan `to_local()`, supaya Stage yang bergeser tidak menggeser area tapnya; awake hop/pop, Sleep sleepy bob, dan Dormant weak accent. Tidak ada care mutation atau request. Input mouse/touch di-dedupe.
- **`Container` memakai `MOUSE_FILTER_STOP` secara default, jadi seluruh rantai di atas Stage wajib `mouse_filter = 2`.** Ini kegagalan senyap: `SafeMargin`, `Shell`, `ViewStack`, `HomeView`, dan `HomeView/Column` menutupi layar penuh, jadi GUI menelan tap sebelum `_unhandled_input()` dan interaksi Anima mati tanpa satu pun galat. Terukur dengan `--home-tap-demo`: satu node saja dikembalikan ke default membuat `reaction=(0, 0)`, sementara rantai tembus klik memberi `reaction=(0, -8.9)`. Tombol Care/nav tetap `STOP` dan tidak boleh diikutkan.
- **`tween.chain().set_parallel(true)` membatalkan chain-nya.** `chain()` menutup step, lalu `set_parallel(true)` langsung membukanya lagi, sehingga hop dan kembalinya jalan bersamaan dan sprite tampak tidak bergerak sama sekali. Pola yang benar: `chain().tween_property(...)` untuk step baru lalu `parallel().tween_property(...)` untuk pasangannya. Ini pernah membuat tap awake/Sleep terlihat mati padahal input sudah sampai.
- **Deploy Edge Function tidak melakukan type check, jadi argumen yang hilang hanya muncul sebagai kegagalan di tangan pemain.** `withSignedRoster(db, value)` dipanggil enam kali; satu pemanggilan di `team_battle` mengirim snapshot saja, sehingga snapshot masuk ke parameter client, `value` menjadi `undefined`, dan setiap `candidates` menjawab `INVALID_TEAM_SNAPSHOT` — Team Battle tidak pernah mendapat rival sejak versi 1. Perbaikan masuk di version 2 dan tetap ada pada version 4 ACTIVE. Skenario 30 di `npm run selftest` memindai setiap pemanggilan helper `_shared` yang parameter pertamanya `SupabaseClient` dan menuntut argumen pertamanya `db`/`client`/`admin`; ganti dengan `deno check` kalau Deno sudah ada di mesin build (mesin ini belum). Node tidak bisa mengimpor `signed_roster.ts` sebagai pengganti uji—specifier `npm:` gagal di ESM loader walau tipenya di-strip.
- **Lawan Team Battle hanya sebanyak sumber yang ada.** Resolver memilih tiga tier dari sumber yang **berbeda**, jadi satu `system_team_templates` aktif berarti satu rival dan `Find New Rivals` yang selalu mengembalikan lawan yang sama. Karena Defense Team terpublish masih nol, `20260815110621_team_battle_system_opponents` menambah `scrap-scavengers` (level 2) dan `vault-wardens` (level 7) di samping `starter-sentinels` (level 4). Terukur lewat `teamCombatPower()`: tim level 5–7 mendapat ratio 0,788 / 0,992 / 1,194 dan tim level 1 mendapat 0,930 / 1,171 / 1,410 — tiga kartu terisi, meski band `tough` (1,05–1,1) memang sempit karena target resolver 1,15 sudah masuk `formidable`. Semua anggota template bertanda `system_asset: "placeholder"`, sehingga `withSignedRoster` melewati Storage sama sekali; jangan beri mereka `sheet_path`.
- **`ItemList.multi_selected` melaporkan seleksi bawaan Godot, bukan pilihan pemain.** Satu tap tanpa Ctrl mengganti seluruh multi-selection, dan `multi_selected` menyala dari state itu **sebelum** `item_clicked` sampai ke `TeamRosterList` yang memulihkan set-nya. Builder Team/Expedition yang menghitung dari `multi_selected` karena itu membaca satu item terpilih walau tiga card sudah ber-checklist, jadi Save mati padahal timnya penuh — terukur sebagai `1/4 selected` di layar dengan tiga checklist. Sumber kebenarannya `_chosen` di `team_roster_list.gd`, dan satu-satunya sinyal yang boleh dihitung adalah `selection_changed` yang ia pancarkan sesudah `_apply_chosen()`. Jangan kembali ke `multi_selected` dan jangan menghitung ulang lewat `get_selected_items()` di dalam handler bawaan itu.
- **Visual shell tetap procedural kecuali font dan ikon UI.** `ScanimaBackground` menggambar gradient, chamber ring, particle, glow floor, dan grid pada 15 fps; `IncubatorEffect` memiliki telur generation serta portal Summon 30 fps; `FirstAnimaEffect` menggambar scanner/orb empty state 15 fps. Stage Anima berada di 60% safe band supaya identity copy tidak tertutup silhouette tinggi. Pose `Idle/Attack/Sleep/Defeated` tidak lagi muncul di production; fungsinya tetap tersedia di `anima_demo`.
- **Semua copy production berasal dari katalog `game/locales/ui.csv`.** English adalah default/fallback dan `LocaleManager` memusatkan angka, rasio, ukuran file, nama element/stage, serta mapping kode gate. Jangan menampilkan error transport/server mentah dan jangan menulis string player-facing baru langsung di `.gd`; tambah key English, lalu pakai `tr()`. Locale baru cukup menambah kolom/resource, mendaftarkannya, dan memilih locale.
- **Target SDK 35 memaksakan edge-to-edge di Android 15.** `DisplayServer.get_display_safe_area()` mengembalikan piksel fisik, bukan koordinat viewport. `scan_flow.gd` mengubahnya dengan rasio viewport/screen sebelum memasang margin. Memakai nilainya langsung akan menggandakan inset pada device ber-DPI tinggi; mengabaikannya menaruh Koleksi/Stats di bawah status bar atau gesture bar.
- **Daftar Anima tidak dipersist lokal.** `Backend.fetch_animas()` membaca ulang hanya row `ready` dari Postgres di bawah RLS; `GameState.last_anima` tetap hanya pilihan terakhir dan bukan salinan roster. Screen Collection memakai `ItemList` dua kolom. Thumbnail 128px dibuat hanya dari sheet yang sudah ada di cache; jangan mengunduh semua sheet ~1 MB saat Collection dibuka hanya demi thumbnail.
- **Toast global menempel di bawah HUD**, bukan di tengah layar. `StatusPanel` di-anchor ke atas `ToastLayer` dengan offset safe-area + tinggi chip supaya tidak menutupi Anima, Care Dock, atau arena. `ToastLayer` harus di atas `ShopSheet` di tree — kalau tidak, overlay Shop/Bag menelan `ERROR_NO_BITS` / `FEEDBACK_PURCHASE`. Feedback aksi selesai seperti pembelian harus memanggil `_say(..., true)` supaya hilang otomatis; status proses saja yang persisten. Tab Scan tetap memakai status in-page.
- **Level Up** tampil di pita identity (bukan di atas tubuh Anima). Setelah banner hilang, `UiModal` menampilkan delta stat grown (`43 → 44`). Expedition mengantre semua anggota yang melintasi batas Level sesudah summary reward: banner bernama → modal lima stat lama/baru → Continue ke anggota berikutnya; Return to Map terkunci sampai queue habis, dan Android back juga maju agar flow tidak tersangkut. Queue memakai `care_score` snapshot encounter sebelum reward lalu refresh roster authoritative sekali sebelum modal pertama. `--level-up-demo` memicu flow satu Anima.
- **Profil Anima** memakai dua kartu `HudSurface` yang sama (About + Combat): Traits grid 2 kolom, stats grid 5 kolom seperti Collection, satu help 96px per section, portrait 132px. Delete adalah teks datar gaya Retreat (bukan `DangerButton` lebar penuh); konfirmasi tetap modal destruktif.
- **Ada dua lock Scan client.** `genesis_cores == 0` meredupkan kamera sampai IAP/ads/BYOK ada; `guest_scan_used_at != null` pada user anonim mengganti CTA menjadi `Sign in to Scan Again` walau Core masih ada. Server `NO_CORE` dan `GUEST_SCAN_USED` tetap pagar terakhir. Jangan grant Core atau slot guest dari client.
- **Tap Collection membuka bottom sheet, bukan langsung mengganti companion.** Sheet mengikuti tinggi konten, handle 96px bisa di-swipe ke bawah untuk menutup, dan Android back (`NOTIFICATION_WM_GO_BACK_REQUEST`, `quit_on_go_back=false`) menutup modal lalu sheet lalu kembali ke Home sebelum quit. Identity dan lima base stat tampil langsung; pada uncached care sync, empat meter lama di-reset/disembunyikan dan `UiSkeleton` tampil sampai row authoritative datang. Cache, error fallback, dan respons basi tetap dijaga revision. `View Profile` membuka row pilihan tanpa mengaktifkannya. `Summon` menyiapkan art dulu, lalu `apply_care('summon')` menulis `profiles.active_anima_id`, menidurkan Anima lain, dan membangunkan yang dipilih; dissolve companion lama, portal, `GameState.last_anima`, dan reveal di Home. Gagal sebelum summon tidak mengganti companion. Thumbnail Collection memakai pose Sleep selama Energy belum penuh, Hungry/Dirty kalau lapar/kotor, Idle kalau siap (termasuk Anima di bangku yang masih ditandai tidur di server), Damaged jika Dormant. Pose itu memakai Energy hasil `CareRules.projected_care()` dari timestamp tidur, bukan `care.energy` mentah di roster — tap sync tidak boleh jadi syarat supaya Anima terlihat siap. Bangku tidak auto-bangun di Postgres supaya Energy tidak luruh dan tidak kena +5 EXP. Tidak ada biaya atau model call.
- **Home membedakan Loading, Error, Empty, dan Ready.** Loading memusatkan `Preparing your habitat` di area Home dan tidak memunculkan toast duplikat, supaya copy tidak tertimpa chip Bag/Shop. Roster error tidak boleh terlihat sebagai pemain baru. Empty hanya muncul setelah fetch roster sukses dan kosong, memakai `FirstAnimaEffect` + CTA menuju tab Scan; kamera tetap butuh tap eksplisit berikutnya. State yang sama dipakai setelah Anima terakhir dihapus. Onboarding Seeker terpisah, baru muncul setelah roster berisi Anima dan `seeker_name` masih null.
- **Setelah setiap scan selesai, modal Rename muncul dengan nama generated sebagai nilai awal.** Save PATCH `nickname`; Cancel menutup tanpa request dan mempertahankan nama yang ada. Profile memakai sebelas `InfoValueRow` dalam scroll view; tiap tombol bantuan 96px membuka penjelasan localized lewat `UiModal`. Dua baris Attack/Special menampilkan `strike_name`/`surge_name` hasil Vision, dengan fallback katalog kalau Anima lama belum punya nama. Nama lama tidak dimigrasi karena database tidak bisa membedakan hasil model dari nickname manual.
- **Rename dipagari trigger `animas_validate_nickname`, dan pagarnya deterministik karena nickname privat.** `nickname` adalah satu-satunya kolom yang boleh ditulis client langsung lewat PATCH PostgREST, dan sampai `20260819123500_anima_name_gate` pagarnya cuma panjang 1..32. Sekarang `_validated_anima_name()` menuntut ASCII `[A-Za-z0-9 '-]`, minimal satu huruf, tanpa spasi ganda, lalu menolak impersonasi/profanity **per kata** (`Admin Bot` ditolak, bukan hanya `admin`). Daftar terlarangnya dipindah ke `_name_is_reserved()` yang dipakai bersama `_validated_seeker_name`, supaya tidak ada dua daftar yang perlahan berbeda isi; perilaku seeker tidak berubah karena `seeker_name` tidak pernah punya spasi. Trigger sengaja **hanya UPDATE**: nama generated lahir di dalam `claim_capture`/`claim_genesis` yang sudah membayar Vision + generation, dan aturan `_shared/vision.mjs` berlaku di sini juga — penamaan tidak boleh menggagalkan capture berbayar. Terverifikasi tidak ada satu pun RPC yang menulis `update animas set nickname`, jadi trigger ini hanya menyala untuk Rename pemain. Validator-nya **tidak** dicabut dari `authenticated`: keduanya fungsi murni tanpa efek samping dan tanpa akses baris, jadi aturan revoke untuk SECURITY DEFINER mata uang tidak berlaku. Client mencerminkan aturan yang sama di `AnimaDetailsView.is_valid_anima_name()` sebagai preflight satu round trip, dan `_anima_rename_error()` memetakan `INVALID_ANIMA_NAME`/`ANIMA_NAME_RESERVED` ke copy `ui.csv`; database tetap pagar terakhirnya, dan daftar impersonasi sengaja tidak ikut turun ke client karena ia berubah tanpa build baru. Gerbang deterministik cukup **karena** nickname tidak pernah sampai ke pemain lain — kalau ia menjadi publik, karakter franchise butuh moderasi model seperti jalur art Atlas, dan skenario 39 `npm run selftest` adalah tripwire-nya: ia memindai sumber Edge Function yang menyentuh `nickname` terhadap allowlist, lalu menuntut keempat pagar proyeksi tetap ada (`atlasDisplayName` owner-only, `delete member.nickname` di `withSignedRoster`, `includeName` di `team_snapshot.mjs`, dan `teamSnapshot(team, false)` di `publishDefense`).
- **Nama generated menghindari nama yang sudah ada di koleksi pemilik, secara best-effort.** `selectMorphemeName()` sudah menerima `takenNames`, tetapi capture tidak pernah mengisinya, jadi dua Anima dari benda serupa lahir kembar. `create_anima` sekarang membaca `animas.nickname` milik pemilik lalu menitipkannya lewat `validateVision(..., takenNames)` → `deriveMorphemeSpeciesName()`, dan `evolve_anima` menitipkannya sebagai `opts.ownerNames` yang masuk ke `takenNames` `deriveName()` bersama nama stage sebelumnya — Rename sesudah Evolve terisi `suggested_name`, jadi kembar lahir dari jalur itu juga. Perbandingannya case-insensitive dan **head morfem tidak ikut berubah**: yang diganti hanya morfem lanjutan, jadi lineage tetap terbaca satu keluarga. Filter ini **usaha terbaik, bukan gerbang**: kolam satu head berhingga, jadi pemilik yang rajin Scan pasti menghabiskannya, dan saat itu terjadi nama kembar dikembalikan apa adanya. Menggagalkan capture $0.07 demi keunikan nama yang bisa di-rename pemain adalah pertukaran yang salah arah. Skenario 36 `npm run selftest` menjaga ketiganya: dedup mengganti tail tanpa menyentuh anchor, kolam habis mengembalikan kembar alih-alih melempar, dan `validateVision`/`validateEvolutionPlan` benar-benar meneruskan daftarnya.
- **Delete Anima memakai PostgREST + RLS native, bukan Edge Function.** Policy hanya mengizinkan `auth.uid() = owner_id`; hard delete tidak merefund Core/Bits. `care_events` cascade, `generations` tetap untuk audit dengan `anima_id = null`, dan `species_library` serta cache device tidak dihapus karena art dapat dipakai row lain. Setelah delete, roster dibaca ulang dan Home memilih row terbaru berikutnya. Migration `20260813071410_allow_owned_anima_deletion` sudah di-apply ke production dan diuji langsung untuk owner, cross-owner, audit, cascade, serta no-refund.
- **Delete Account berbeda dari Delete Anima.** Operasi `seeker/delete_account` memerlukan konfirmasi `DELETE`, menurunkan owner dari JWT, lalu `auth.admin.deleteUser`; cascade menghapus profil/Anima/inventory/session, sedangkan `species_library` tetap. Guest maupun linked account boleh memakai aksi ini. Sesudah sukses client membersihkan SecureStore dan membuat guest baru.
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
- **Keyline putih adalah matte teknis hanya untuk prompt lama yang masih memintanya.** Pada v7 dan sheet lama, `stripWhiteKeylineInPlace()` mengupas putih/off-white yang tersambung ke transparansi, maksimal 6px, lalu menghaluskan dark outline yang terbuka. V11/v12 tidak meminta keyline; dark contour langsung melawan chroma green, sedangkan stripper tetap aman sebagai kompatibilitas input lama. Rollback stripper satu flag: `DEFAULTS.stripWhiteKeyline = false`, lalu `--reprocess` raw yang sama tanpa model call. `replicate_webhook` version 6 ACTIVE membawa pipeline v12. Sheet RGBA lama bisa dimigrasikan tanpa raw lewat `stripWhiteKeylineFromRgba()`; path asli disimpan di `manifest.qa.white_keyline_previous_sheet_path` dan objek lama tidak dihapus. Delapan row `species_library` yang ada pada 15 Agustus 2026 sudah dimigrasikan dan diperiksa visual, termasuk mug putih serta Veridian yang sebelumnya hanya punya cache lokal. Veridian juga punya 17.407 piksel matte putih internal buatan model; mask khusus menghapusnya tanpa menyentuh mata/kerikil dan menyimpan sheet sebelumnya di `manifest.qa.internal_openings_previous_sheet_path`. Jangan menulis detektor putih global karena mata dan tubuh putih tidak bisa dibedakan aman dari matte tertutup. Uji v9 pada Monstera gagal—fenestrasi masih putih dan residu hijau 2,184%. V10 menambah larangan white accent, fenestrasi eksplisit, dan keyline terluar; residu turun ke 0,166% tetapi beberapa slot putih masih terlihat. Keduanya tidak dipromosikan. Fungsi + secret/endpoint migrasi sementara sudah dihapus. Cache client memakai prefix `v4_` supaya build baru tidak terus memakai PNG sebelum dua perbaikan matte; v3 sempat terisi oleh editor yang masih hidup di sela update server. Rollback client cukup mengembalikan `SPRITE_CACHE_VERSION` ke versi yang dituju.
- **V11 adalah candidate borderless, bukan production.** Ia mempertahankan aturan negative-space v10 tetapi menghapus seluruh instruksi white keyline, termasuk VFX, dan meminta dark contour langsung menyentuh `#00FF00`. Generation Monstera selesai 53 detik dengan 9/9 sel: slot putih hilang dan screenshot Godot pada ukuran game terlihat bersih tanpa fringe terang. `green_residue_ratio` tetap melapor 2,074%, tetapi ini false positive dari warna daun sah sekitar RGB `(71,140,28)`: di cincin alpha terluar hanya 1 dari 28.874 piksel punya `g >= 220`. Uji kedua sepatu/cloth selesai 51 detik, 9/9 sel, residue 0,446%, dan juga hanya 1 dari 23.244 piksel tepi yang chroma terang; borderless bersih di ukuran game. Sheet sepatu punya satu fragmen motion Attack yang terlepas ke frame Idle karena model melanggar margin seam—cacat komposisi stokastik, bukan kegagalan keying, dan tidak aman ditebak post-process. Jangan menurunkan ambang chroma atau menulis cleanup berdasarkan warna hijau saja—itu akan mengikis tubuh plant. `app_config.prompt_version` tetap v7 sampai Smoke Set lintas material lulus; bundle v11 lokal belum berarti function production sudah dideploy.
- **V12 adalah baseline seam/VFX dan rollback pertama.** Ia mengurung aksen dalam safe envelope 12% dan `auditSourceGridSeams()` hanya menolak fragmen sekunder dekat seam Idle, tempat prompt memang melarang efek. Vision membawa form/brief/motion `projectile`, `sweep`, `impact`, atau `bloom` ke manifest. Generation sepatu v12 lulus 9/9 dalam 55 detik; v13 mewarisi seluruh kontrak ini lalu menambah fauna dan dual typing.
- **Catatan status:** paragraf V12 di atas adalah decision record promosi sebelumnya. V13 sekarang default dan mewarisi seam/VFX v12 sambil menambah fauna, 18 elemen, dual typing, dan private unique art. Rollback pertama adalah v12 sekaligus mematikan animals/typing-v13/unique flags.
- **Ambang chroma key harus ketat: `sat > 0.85`, `val > 0.5`.** Resep chroma key umum memakai 0,3 dan itu akan **melubangi tubuh Anima berelemen `plant`**, karena hijau daun `rgb(60,160,70)` punya saturasi 0,63 dan hue 126°. Nilai ini muncul di dua tempat dan harus selalu sama: `backend/supabase/functions/_shared/postprocess.mjs` (dipakai eval maupun Edge Function) dan `game/shaders/chroma_key.gdshader`.
- **Post-processing muat di Edge Function dengan lega.** Sebelum matte putih dikupas, terukur 173 ms pada sheet v3 sungguhan (1024×1024, 1,46 MB) di runtime edge, versus 162 ms di Node. Sesudah pengupasan ditambah, satu reproses CLI lengkap pada sheet v7 sungguhan selesai 312 ms termasuk startup Node dan I/O, masih jauh di bawah batas CPU 2 detik; ukur ulang angka edge setelah deploy berikutnya. Jangan memindahkan langkah ini ke worker terpisah "karena mungkin berat"; plafonnya belum dekat.
- **Semua PNG lewat satu encoder, `functions/_shared/png.mjs`.** Post-process, gallery thumbnail, Chapter Factory, dan `eval/catalog_art.mjs` memanggilnya; tidak ada lagi definisi kedua tentang "PNG optimal". Yang dikerjakannya cuma tiga hal lossless: adaptive row filtering, menolkan RGB di bawah alpha 0 (`softenAlphaEdges` hanya menulis alpha 0 dan meninggalkan RGB hijaunya, jadi cincin tepi menyimpan warna acak yang ikut dikompresi padahal tidak pernah terlihat), dan membuang chunk tEXt. Terukur pada sheet Anima production 5,0–14,4% lebih kecil dan katalog Shop 15,4%/15,8%; **filter-nya yang penting, bukan level deflate** — adaptive filtering bernilai 15,17% sementara zlib level 9 hanya 0,22%, jadi jangan tukar `CompressionStream` dengan tuning level. Adaptive filtering TIDAK selalu menang: pada `point-hex-vessel.png` ia 21,67% lebih **besar** daripada filter 0 rata, karena gambar dengan banyak baris identik lebih untung dicocokkan LZ77 baris utuh. Karena itu `encodeOptimizedPng()` mencoba kedua strategi lalu memakai yang lebih kecil — jangan "sederhanakan" menjadi satu pass. Membuang tEXt `Creation Time` juga bukan kosmetik: `sheet_path` adalah SHA-256 byte terenkode, dan stempel `Date.now()` milik ImageScript membuat piksel yang sama menghasilkan hash berbeda setiap encode. Aset ter-commit dijaga `node backend/tools/optimize_png.mjs --check`, dan skenario 33 `npm run selftest` menuntut parity piksel terlihat, determinisme, ukuran tidak pernah naik, plus jalur production benar-benar memakai encoder ini (sidik jarinya: tanpa chunk tEXt). Isi `backend/chapters/<slug>/v<n>/` sengaja **tidak** ikut dioptimasi: `assets/` immutable dengan hash di manifest terpublish dan ledger activation, sedangkan `raw/`/`manual_inbox/` adalah provenance hash — mengecilkan byte-nya memutus verifikasi yang menjadi alasan folder itu ada. Chapter berikutnya lahir optimal sendiri karena Factory memakai encoder yang sama. Ini **tidak** mengecilkan APK secara berarti: Godot mengimpor ulang PNG statis menjadi `.ctex`, jadi yang hemat adalah git dan Storage.
- **Hash PNG berbeda antar runtime walau pikselnya identik.** Sheet yang sama diproses di Node dan di edge memberi 3.544.272 byte channel yang sama persis (nol selisih) dan manifest yang sama, tapi PNG-nya 886 KB versus 964 KB karena setelan deflate-nya beda. Konsekuensinya: `sheet_path` yang berbasis SHA-256 byte terenkode **tidak** stabil lintas runtime. Produksi selalu mengenkode di edge sehingga dedup-nya utuh, tapi jangan pernah membandingkan hash Node dengan hash produksi untuk menyimpulkan ada regresi — bandingkan pikselnya. Encoder bersama menghapus satu penyebabnya (stempel waktu tEXt) sehingga byte-nya kini deterministik **di dalam** satu runtime, tetapi `CompressionStream` Node dan Deno masih memakai implementasi deflate berbeda dan belum diukur berimpit; anggap caveat lintas runtime ini tetap berlaku.
- **Keempat region wajib berukuran sama.** `AnimatedSprite2D` cuma punya satu `offset` untuk seluruh animasi, jadi region yang ukurannya beda membuat sprite tersentak berpindah tiap ganti pose. `AnimaLoader` menolak manifest yang melanggar ini; jangan "perbaiki" dengan melonggarkan pemeriksaannya.
- **Jangan mengukur konsistensi skala dari varians keempat pose.** Pose Sleep memang jauh lebih pendek daripada Idle, jadi metrik itu memberi alarm palsu terus-menerus. Bandingkan Idle vs Attack saja (`standing_height_variance`).
- **Yang ditunggu pemain bukan cuma latensi model.** Terukur di produksi: `create_anima` balik **15 detik** di jalur Genesis (Vision ikut ditunggu di dalamnya, sebab hasilnya yang menentukan apakah kita berhak mendebit Core) dan **11 detik** di jalur cache hit. Jadi UI butuh dua status, bukan satu: belasan detik pertama tanpa apa pun di layar sudah terasa seperti macet, padahal Anima-nya belum tentu menetas sampai ~satu menit kemudian.
- **Pada v13 tidak ada cache-hit capture.** Semua foto yang lolos masuk inkubator setelah Vision dan satu Core claim; angka cache-hit di atas hanya baseline historis.
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
npm run selftest                       # 39 skenario + 12 uji tanda tangan webhook
godot --headless --path game --script res://tests/test_sprite_slicing.gd # 182 check manifest, loader, presenter, Boss Seeker
godot --headless --path game --script res://tests/test_client_state.gd  # 151 check sesi, refresh, pending scan/care/Battle/Shop/evolution, cache art, cache boot, retry transport
godot --headless --path game --script res://tests/test_scan_ui.gd       # 876 check shell + Battle + Shop + Bag + komponen + tap + touch + UI/SFX hooks + prediksi turn/care/Summon + rollback + cache boot + Trophy Showcase/evolution/Atlas + preflight nama
godot --headless --path game --script res://tests/test_i18n.gd          # 4325 check katalog + key + formatter + wrapping
godot --headless --path game --script res://tests/test_game_rules.gd    # 181 check care + EXP/Level/evolution + kontrak event Battle
godot --headless --path game --script res://tests/test_expedition_route_map.gd # 79 check route tree + preview/Enter Node + Skip Shop + prediksi turn/Switch/penutup Boss
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
godot --path game -- --trophy-demo --screenshot=/tmp/trophy.png
godot --path game -- --atlas-demo --screenshot=/tmp/atlas.png
godot --path game -- --empty-demo --screenshot=/tmp/empty.png
godot --path game -- --summon-demo
godot --path game -- --battle-demo --screenshot=/tmp/battle.png
godot --path game -- --battle-small-demo --screenshot=/tmp/battle-small.png
godot --path game -- --battle-normal-demo --screenshot=/tmp/battle-normal.png
godot --path game -- --battle-giant-demo --screenshot=/tmp/battle-giant.png
godot --path game -- --boss-ace-demo --screenshot=/tmp/boss-ace.png
godot --path game -- --boss-scale-demo --screenshot=/tmp/boss-scale.png
godot --path game -- --battle-pending-demo --screenshot=/tmp/battle-pending.png
godot --path game -- --battle-effective-demo --screenshot=/tmp/battle-effective.png
# kilau Guard hidup ~1 detik dan --screenshot menunggu 3, jadi demo ini
# mengulanginya supaya capture jatuh di tengah sapuan
godot --path game -- --battle-guard-demo --screenshot=/tmp/guard-shimmer.png
godot --path game -- --battle-result-demo --screenshot=/tmp/battle-result.png
godot --path game -- --battle-win-demo --screenshot=/tmp/battle-win.png
# result yang terpagari Energy: Choose Anima / Edit Team plus alasannya
godot --path game -- --battle-blocked-demo --screenshot=/tmp/battle-blocked.png
godot --path game -- --team-result-demo --screenshot=/tmp/team-result.png
godot --path game -- --battle-training-demo --screenshot=/tmp/battle-training.png
godot --path game -- --battle-training-active-demo \
 --screenshot=/tmp/battle-training-active.png

# band preview foto tanpa memindai apa pun, jadi tata letaknya bisa diperiksa
# dengan biaya nol. Tanpa ini satu-satunya cara melihatnya adalah membayar scan.
godot --path game -- --preview=$PWD/eval/photos/sepatu.jpg \
 --screenshot=/tmp/scan.png
godot --path game -- --scan-vibe-demo --screenshot=/tmp/scan-vibe.png

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
