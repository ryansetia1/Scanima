# 14 — Log deploy

Riwayat rollout yang sebelumnya hidup di `CLAUDE.md`. Isinya dipindahkan verbatim; urutannya sama dengan urutan di file asal, bukan kronologis. Yang berlaku sekarang diringkas sebagai tabel status di `CLAUDE.md` — file ini adalah catatan bagaimana keadaan itu tercapai, termasuk probe production dan angka yang terukur saat itu.

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

## Daftar migration yang sudah live

- Migration Battle `20260813103446_battle_vertical_slice`, indeks bot `20260813105258_index_battle_bot_anima`, cap reward `20260813174007_limit_daily_battle_rewards`, indeks unik ledger `20260813174454_index_battle_reward_ledger_ref`, perbaikan status `20260813180241_refine_battle_reward_status`, guard Energy `20260813193612_require_battle_energy`, decay realtime + biaya Energy Battle `20260813195613_decay_realtime_and_battle_energy`, EXP/Level tanpa Bond `20260813201820_exp_level_growth`, gerbang Feed/Clean penuh `20260813220036_reject_full_feed_clean`, dan tidur Anima yang tidak di-Summon `20260813220954_bench_unsummoned_sleep` + `20260813221113_apply_care_bench_summon` + Energy bangku 3 jam `20260813224221_bench_sleep_faster` + gerbang Hunger Battle `20260814043053_reject_hungry_battle` (sudah di-drop: lapar tidak mengunci Bits) + reset hari sipil lokal `20260814064443_local_day_reset` + `20260814064550_local_day_reset_status` + `20260814064614_local_day_reset_care` sudah live. Lapar tidak mengunci Battle: `20260814101323_allow_hungry_battle`. Clean gratis: `20260814104237_free_clean`. Shop live: `20260814082442_shop_inventory_bits` + `20260814082512_shop_inventory_rpcs` + `20260814082545_shop_apply_care` + `20260814082612_shop_battle_rewards` + `20260814082658_shop_commit_battle_turn`. Guest Seeker/Google live lewat `20260814153135_seeker_google_accounts`; guard guest sebelum Vision lewat `20260814172154_guard_guest_scan_before_vision`. Capture/private art live lewat `20260814215746_capture_foundations`; Gallery lewat `20260814215801_gallery`. Tinggi kanonis live lewat `20260815214409_anima_body_height`; kalibrasi tinggi/metrics lewat `20260815225656_recalibrate_anima_heights_and_metrics`; prompt production v18 lewat `20260815225859_prompt_version_v18`. Tinggi Veridian 150 cm lewat `20260815234322_lower_veridian_height`. Starter lifetime 4 + Care rebalance live lewat `20260816074701_starter_four_and_care_rebalance`. Floor bangku / well_cared aktif-only live lewat `20260816082652_bench_care_safe_rest`. Tiered EXP, reward Battle berskala, cap Sleep harian, dan budget Expedition 30 live lewat `20260816200507_tiered_exp_and_battle_rewards`. Lawan Duel sistem live lewat `20260817072847_system_duel_opponents`. Typing kanonis Playtron + sinkron proyeksi Atlas live lewat `20260820134728_backfill_legacy_handheld_typing`. `shop` version 4, `care_anima` version 9, `battle_anima` version 26, `create_anima` version 22, `seeker` version 5, `replicate_webhook` version 10, `gallery` version 2, `team_battle` version 8, dan `expedition` version 16 ACTIVE; semua kecuali webhook memakai `verify_jwt=true`. `create_anima` membundel seluruh versi lokal; `app_config.prompt_version = "v31"` production, v20 rollback capture tanpa Vibe, v19 rollback gate, v18 rollback kebijakan tinggi handheld, v17 rollback kebijakan tinggi awal, v15 rollback art, dan v13 rollback kontrak capture. Tujuh Anima ready production sudah dibackfill `body_height_cm` dan `render_metrics` hasil ukur sheet privat. Enam Anima ready legacy sudah dipindahkan ke `anima_sheets`, diretype v2, dan bucket `sheets` dibuat privat. `apply_care()` menolak Hunger/Hygiene >= 99.5 dengan `NEED_FULL`. `Summon` menulis `profiles.active_anima_id` dan menidurkan sisanya. `care_anima` menyimpan `timezone_offset_minutes` lewat `set_profile_timezone` sebelum RPC; snapshot player/bot membawa `level` dari `care_score`, `body_height_cm`, plus `strike_name`/`surge_name`, dan `createFighter` memakai growth multiplier. Error boundary tetap membaca `message` dari object PostgREST, bukan hanya instance `Error`; tanpa itu exception RPC yang dikenal jatuh menjadi 500 generik. Probe SQL production membuktikan win ketiga dibayar dan win keempat menjadi Training tanpa satu pun mutation progression.
