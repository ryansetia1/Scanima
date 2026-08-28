# Kartu Collection tanpa art, kartu hantu, dan grid yang mati sesudah Summon

Status: **dieksekusi 26 Agustus 2026.** Phase 0–5 selesai; lihat commit untuk diff. Semua uji Godot yang tersentuh lulus (`test_client_state.gd` 199 check, `test_scan_ui.gd` 1485 check minus 3 kegagalan pra-ada yang tidak terkait perubahan ini).

**Regresi ditemukan dan diperbaiki 27–28 Agustus 2026:** fix di sini membuat Anima **hilang** (bukan lagi kotak abu) dari Collection satu per satu setelah Summon berulang, sampai grid kosong. Root cause bukan di rencana Phase 0–5 manapun di atas — reference aliasing GDScript di `CollectionView._selected_row`, tidak terkait guard dedup id yang ditambahkan di sini (guard itu justru yang membuat gejalanya kelihatan sebagai "hilang", bukan "duplikat" seperti kartu hantu). Kronologi lengkap dan pelajarannya ada di [`docs/14-deploy-log.md`](../14-deploy-log.md#kartu-hantu-collection-dan-bug-susulannya-anima-menghilang-setelah-summon-26–28-agustus-2026); pagar teknisnya di `.cursor/rules/client-shell-ui.mdc`.

## Gejala yang dilaporkan

1. Sesudah Summon, satu-dua Anima di Collection kehilangan art — jadi kotak abu
   kosong 128×128.
2. Kadang semua Anima tetap ber-art tapi **ketambahan satu slot** yang tidak
   ada pemiliknya, juga kotak abu kosong.
3. Summon Anima lain berkali-kali membuat kotak abu itu berpindah ke slot Anima
   yang di-Summon sebelumnya; kalau semua Anima di-Summon bergantian, akhirnya
   **semua** slot jadi kotak abu.
4. Kotak abu tidak bisa di-tap. Pemain stuck.
5. Satu-satunya perbaikan: quit app lalu buka lagi. Terjadi di build mana pun.

Fakta penting yang mempersempit ruang penyebab: **restart menyembuhkannya.**
Art-nya ada di disk (`user://animas/v6_<id>_<stage>/`) dan tidak pernah dihapus
kode mana pun — tidak ada `remove_recursive`, tidak ada pruning cache. Jadi yang
rusak adalah **state di memori**, bukan file. Empat state di memori itu yang
harus dibongkar.

## Akar masalah

Lima penyebab, semuanya terkonfirmasi dengan membaca jalur kodenya. Dan
kesimpulan yang penting: **empat dari lima hidup di satu subsistem yang sama** —
`_thumbnail_for()` / `_run_thumbnail_backfill()` di `game/scripts/scan_flow.gd`
(RC1, RC2, RC4, RC5) — plus latch `_busy` (RC3). Ketiga gejala besar (art
hilang, kartu hantu, grid mati) karena itu bukan tiga bug terpisah: dua di
antaranya dipicu oleh hal yang **persis sama**, yaitu Summon mengubah
`_summoned_id()` sehingga pose berubah dan `cache_key` baru diterbitkan.

### RC1 — "art ada" diputuskan dari "file-nya ada", bukan dari "art-nya bisa dimuat"

`GameState._has_sprite_at()` (`game/scripts/game_state.gd:885`) hanya memeriksa
`manifest.json` bisa di-parse dan file sheet-nya eksis. Ia **tidak** memvalidasi
apa pun yang justru bisa ditolak `AnimaLoader.build()`
(`game/scripts/anima_loader.gd:66`): `version != 1`, `frame_size` tidak sah,
`region.size != frame_size`, region keluar batas sheet, pose `idle` tidak ada,
atau PNG yang terpotong sehingga `image.load()` gagal.

Konsekuensinya berantai:

- `_prepare_anima_art()` (`scan_flow.gd:5108`) **short-circuit** di
  `has_sprite_for_anima()` dan mengembalikan hasil `load_from_manifest()` apa
  adanya — termasuk kalau hasilnya gagal. Ia tidak pernah mencoba mengunduh
  ulang.
- `_run_thumbnail_backfill()` (`scan_flow.gd:5370`) `continue` begitu
  `has_sprite_for_anima()` true, **tanpa** `_populate_collection()`. Jadi item
  yang di-queue justru dibuang diam-diam.

Bundel art yang rusak di disk karena itu dipercaya selamanya dan tidak pernah
diunduh ulang.

### RC2 — `_thumbnail_backfill_seen` adalah latch "menyerah permanen", dan kuncinya ikut pose

`scan_flow.gd:5337`:

```gdscript
if not _thumbnail_backfill_seen.has(cache_key):
    _thumbnail_backfill_seen[cache_key] = true
    _queue_thumbnail_backfill(row, anima_id, stage)
```

Tanda `seen` dipasang **sebelum** percobaannya dijalankan dan hanya dibersihkan
di `_reset_account_presentation()` (`scan_flow.gd:3101`) — yaitu saat ganti
akun. Jadi satu kegagalan apa pun (unduhan gagal, timeout, epoch berubah,
manifest ditolak loader, `sheet_path` kosong sehingga jatuh ke pustaka species
legacy yang sudah tidak dipakai) = **kotak abu untuk sisa sesi**. Restart
mengosongkan Dictionary-nya, dan itulah kenapa quit-and-reopen menyembuhkan.

Yang menjelaskan kaitannya dengan **Summon** secara spesifik: `cache_key`
memuat pose —

```gdscript
var pose := CareRules.collection_pose(row, _summoned_id())
var cache_key := "%s|%d|%s" % [anima_id, stage, pose]
```

`CareRules.collection_pose()` (`game/scripts/care_rules.gd:173`) mengembalikan
`"sleep"` untuk Anima yang **bukan** active, dan pose bangun untuk yang active.
Jadi setiap Summon **menerbitkan cache key baru** untuk dua Anima sekaligus:
yang baru di-Summon (sleep → bangun) dan yang sebelumnya di-Summon
(bangun → sleep). Key baru = percobaan baru = kesempatan baru untuk kena latch.
Karena itu kotak abu muncul tepat di slot Anima yang di-Summon sebelumnya, dan
menumpuk mengikuti urutan Summon pemain sampai semua slot abu. Gejala 1 dan 3
adalah satu mekanisme.

Dua kebocoran tambahan di fungsi yang sama:

- `if GameState.session_epoch != account_epoch: break` (`scan_flow.gd:5382`)
  membuang sisa antrean sementara semua entri tetap ditandai `seen` — ganti akun
  di tengah backfill membuat semua Anima sisanya abu permanen.
- `_thumbnail_backfill_running` adalah gate serial tunggal tanpa reset di luar
  loop. Kalau coroutine-nya ditinggalkan, `_queue_thumbnail_backfill()` terus
  menumpuk antrean yang tidak akan pernah didrain lagi.

### RC3 — `_busy` adalah latch satu arah, dan `_summon_in_flight` tidak pernah direset saat gagal

Ini penyebab "tidak bisa di-tap, pemain stuck". Terkonfirmasi lewat audit jalur:

- `_collection_view.set_busy()` (`collection_view.gd:153`) adalah **satu-satunya**
  penulis `_list.mouse_filter`, dan satu-satunya pemanggilnya adalah
  `_set_busy()` (`scan_flow.gd:6410`). Jadi `_busy` yang nyangkut = grid
  Collection permanen `MOUSE_FILTER_IGNORE`.
- `_activate_anima()` memasang `_set_busy(true)` di `scan_flow.gd:1360` dan
  melepasnya hanya di ekor coroutine panjang (1376 / 1382 / 1389 / 1406 /
  **1417**). Tidak ada teardown terpusat. Jalur sukses (1409–1419) punya tepat
  satu titik pelepasan setelah `_adopt_companion()`, `_anima.apply()`,
  `_refresh_care()`, dan `await _sync_active_care()` — galat runtime di mana pun
  di situ membatalkan coroutine dan `_busy` nyangkut selamanya.
- `_dispatch_summon()` (`scan_flow.gd:1440`) dipanggil **tanpa await** dan tanpa
  penanganan galat. Kalau ia mati, `_summon_in_flight` tetap `true` (ditulis
  hanya di 1441/1443, tidak direset di logout maupun ganti akun),
  `_summon_settled` tidak pernah dipancarkan, dan `await _await_summon()`
  (1399) memblokir selamanya. Lebih buruk: setiap Summon berikutnya juga
  langsung memblokir di 1449.
- Tidak ada jalur pemulihan. `_switch_destination()` tidak pernah memanggil
  `_set_busy`; `begin_visit()` (`collection_view.gd:176`) tidak menyentuh
  `_busy` maupun `mouse_filter`; `NOTIFICATION_APPLICATION_RESUMED` tidak
  membersihkannya. Dan karena semua entry point yang akhirnya akan memanggil
  `_set_busy(false)` dipagari `if _busy: return`, latch itu tidak bisa
  dibersihkan aksi pemain apa pun. **Restart satu-satunya jalan** — persis yang
  dilaporkan.

Skew tambahan di jalur reject: `set_sheet_busy(false)` (1400) mengaktifkan
kembali tombol tanpa memulihkan `mouse_filter`, jadi ada ±1 detik tombol hidup
di atas grid mati, plus tab Synthesis dan tombol empty-state tetap disabled
karena `set_sheet_busy()` tidak memanggil `_update_synthesis_state()`.

Kebocoran sekerabat di luar Summon: `_delete_confirmed()` (`scan_flow.gd:1533`)
`return` tanpa `_set_busy(false)` saat respons dianggap stale.

### RC4 — slot hantu: `set_rows()` di-reenter di tengah loopnya

Bukan baris tambahan di `_roster`. Audit mencatat `_roster` punya **tepat lima**
mutation site (`push_front` :5275, `clear()` :3092, tiga rebind :729/:1544/:5200
— nol `append`/`erase`/`insert`), dan semuanya dipagari `id` non-kosong.
`CollectionView.set_rows()` sendiri juga satu `add_item` per baris. **Yang bisa
menghasilkan kartu ekstra adalah re-entrancy**, dan rantainya begini:

1. Loop `set_rows()` memanggil `thumbnail_provider.call(row)`
   (`collection_view.gd:106`) → `_thumbnail_for()` (`scan_flow.gd:5296`).
2. Tidak ada manifest yang bisa dipakai → `_queue_thumbnail_backfill()`
   (:5337) → **`_run_thumbnail_backfill()` dipanggil sinkron** (:5354).
3. Backfill `pop_front()` mengambil item **tertua** (:5366), bukan yang baru
   didorong.
4. `_prepare_anima_art()` bisa **kembali tanpa pernah `await`** di :5104,
   :5109, dan :5110–5113. Untuk item ber-`anima_id` kosong — guard `continue`
   di :5370 dilewati karena guard itu sendiri mensyaratkan `anima_id` tidak
   kosong — jalur legacy `has_sprite(species, color, stage)` mengembalikan
   `ok = true` **secara sinkron**.
5. `if bool(loaded.get("ok", false)): _populate_collection()` (:5384–5385) →
   `set_rows(_roster, ...)` **masuk ulang saat loop luar masih berjalan**:
   panggilan dalam melakukan `_list.clear()` lalu menambahkan N baris; sesudah
   ia kembali, loop luar melanjutkan dari indeks *k* dan terus `add_item`.
6. Baris yang gagal di loop luar mengembalikan `_placeholder_icon` — tekstur
   rata `Color(0.16, 0.18, 0.22)` yang dibangun di :5340–5346 — lalu
   ditambahkan sebagai item ke-N.

Hasilnya `item_count == N + (N - k)`. **Kalau baris yang jatuh ke jalur sinkron
itu baris terakhir, tepat satu kartu ekstra bertekstur abu** — persis gejala 2.
`_status` tetap membaca `rows.size()` (`collection_view.gd:127`), jadi
hitungannya bilang N sementara grid menampilkan N+1, dan kartu ekstranya adalah
render ulang baris yang sudah tergambar — "bukan Anima saya". Rekonsiliasi
`_selected_row` di `collection_view.gd:132–141` jalan di panggilan dalam dan
tidak membersihkan tambahan milik loop luar.

Dan ini yang mengikatnya ke **Summon**, mekanisme yang sama dengan RC2: Summon
mengubah `_summoned_id()`, jadi Anima baru **dan** Anima yang sebelumnya active
sama-sama dapat `cache_key` segar, luput dari `_thumbnail_backfill_seen`
(:5337), dan mempersenjatai ulang langkah 2 **dari dalam** loop `set_rows()`
Collection. Summon adalah cara paling andal membuat antrean itu start dari
dalam loop.

Yang **belum** terbukti: baris mana di jalur pemain yang punya `species_key`
non-kosong tapi `id` **dan** `anima_id` dua-duanya kosong (syarat langkah 4).
Satu-satunya produsen bentuk itu yang ditemukan adalah harness demo
`--team-demo` (`scan_flow.gd:7142`), yang dev-only; member Team Battle
sungguhan selalu membawa `anima_id` (`team_battle_view.gd:953`, :1694). Jadi
mekanismenya terkonfirmasi secara struktural, produsen barisnya belum. Itu
tidak menunda perbaikan: fix-nya satu `call_deferred` dan menutup re-entrancy
untuk **semua** view yang berbagi `_thumbnail_for` (Team Battle, Expedition,
Synthesis, battle picker — :270, :271, :338, :1459), terlepas dari bentuk
barisnya. Instrumentasi Phase 0 yang akan menyebut barisnya kalau ia muncul
lagi.

Dua kebocoran yang membuat langkah 3 bisa memungut item basi: `break` di
:5382–5383 keluar dengan item masih di antrean lalu menyetel
`_thumbnail_backfill_running = false` (:5386), sehingga `_thumbnail_for()`
berikutnya — dari dalam `set_rows()` — merestart drain dan langsung menemukan
item lama itu.

### RC5 — dua clobber nyata di `_upsert_roster()`, dan satu phantom durable dari boot cache

Temuan sampingan audit, semuanya kecil tapi nyata:

- **`_apply_care_response()` (:3446) menimpa art field dengan NULL.** RPC care
  mengembalikan `'anima', to_jsonb(v_anima)` dari `select * into v_anima`
  (`backend/supabase/migrations/20260816200507_tiered_exp_and_battle_rewards.sql:451`),
  jadi **setiap** kolom ikut — termasuk NULL. `animas.sheet_path` dan
  `animas.manifest` nullable
  (`backend/supabase/migrations/20260814215746_capture_foundations.sql:12`).
  Untuk Anima yang art-nya datang dari pustaka species, satu respons
  care/summon/sync menulis `sheet_path = null` ke baris roster. `_thumbnail_for`
  lalu membaca `str(null)` = `"<null>"` — **non-kosong** — sehingga `use_anima`
  jadi true di :5305, bentuk cache key berubah (:5307–5310), dan lookup
  memprioritaskan `has_sprite_for_anima()` di atas cache species yang
  sebenarnya memegang art-nya. Art-nya masih selamat lewat `elif` di :5316,
  tapi churn cache key-nya nyata — dan ini persis field yang merge di
  `_present()` :5039–5044 ada untuk memperbaiki.
- **`_present()` (:5060) mengosongkan `nickname`.** :5035 memaksa
  `"nickname": nickname`, dan `_present_row()` (:3243) mengirim
  `str(row.get("nickname", ""))`. Baris yang dipresentasikan dari sumber tanpa
  nickname jadi kehilangan nickname-nya di `_roster`.
- **`_paint_boot_cache()` (:5200) adalah satu-satunya vektor phantom yang
  durable.** `fetch_animas` memfilter `status=in.(ready,evolving)`
  (`backend.gd:232`), tapi `_upsert_roster` tidak. Baris apa pun yang didorong
  lokal dengan status lain — atau Anima yang sudah dihapus — ikut tertulis ke
  `user://boot_cache.json` oleh `remember_boot_cache()` (:735, :1041, :1847)
  lalu dicat ulang ke `_roster` di :5200 pada **setiap** cold start sampai
  roster jaringan datang. `_reset_account_presentation()` (:3091) membersihkan
  state runtime, file-nya tidak.
- **Filter `id` di :726 dan :5195 bukan null guard.** `str(null)` =
  `"<null>"`, jadi `id` JSON-null lolos dua-duanya lalu tidak akan pernah
  match perbandingan `_upsert_roster` di :5267 → duplikat permanen. Tidak
  terjangkau dari PostgREST (PK not null), tapi guard-nya menyesatkan.

Catatan: `godotengine/godot#100663` (instabilitas `ItemList.clear()` pada list
bermetadata) **tidak** dipakai sebagai penjelasan — RC4 sudah cukup, dan
metadata kita Dictionary, bukan Node.

## Rencana perbaikan

Urutan sengaja: **Phase 0 → 4 → 3 → 1 → 2 → 5.**

Phase 4 naik ke depan karena sesudah audit ia bukan lagi pagar defensif: inti
perbaikannya adalah dua `call_deferred` yang menutup RC4 sepenuhnya, diff-nya
paling kecil dari semuanya, dan ia juga menghilangkan churn `cache_key` yang
memperbesar peluang RC2 kena latch. Phase 3 berikutnya karena itu bagian
"pemain stuck". Phase 1 dan 2 terakhir karena keduanya menyentuh jalur unduhan
art — yang paling banyak permukaannya, dan paling butuh Phase 0 sudah menyala
supaya kegagalannya terbaca.

### Phase 0 — diagnostik, tanpa perubahan perilaku

- Satu `print` di `_thumbnail_for()` saat ia mengembalikan placeholder,
  menyebut `id`, `stage`, `pose`, dan **alasannya** (tidak ada `sheet_path` /
  art tidak ada di disk / teks galat `AnimaLoader`). Sekarang nol diagnostik
  untuk kegagalan yang justru dilaporkan pemain.
- Satu `print` di `set_rows()` kalau `rows.size() != _list.item_count` sesudah
  loop. Ini yang membuktikan RC4 di lapangan (dan yang akan menyebut baris
  pemicunya, satu-satunya bagian RC4 yang belum terbukti).

### Phase 1 — "art ada" berarti "art bisa dimuat"

- Satu helper `_load_cached_art(anima_id, species, color, stage) -> Dictionary`
  yang mencoba `AnimaLoader.load_from_manifest()` (per-Anima dulu, legacy
  species kedua) dan mengembalikan hasilnya apa adanya. `_prepare_anima_art()`
  dan `_run_thumbnail_backfill()` memakai helper itu alih-alih mempercayai
  `has_sprite_*`. Kalau gagal → jatuh ke unduhan, bukan mengembalikan
  kegagalan.
- Hapus bundel yang rusak sebelum mengunduh ulang, supaya penulisan berikutnya
  benar-benar menggantinya.
- `has_sprite_*` tetap ada untuk pemakaian murah lain; yang berubah hanya
  siapa yang berwenang memutuskan "perlu unduh atau tidak".

### Phase 2 — buang latch, jadikan self-healing

- `_thumbnail_backfill_seen` menjadi set **in-flight**, di-key
  `anima_id|stage` (unit art, bebas pose, bukan `cache_key`), dan entri-nya
  **dihapus saat percobaan selesai** — sukses maupun gagal.
- Tambah `_thumbnail_art_attempts: Dictionary` — hitungan percobaan per
  `anima_id|stage`, dibatasi 3, dan **direset di `begin_visit()`** supaya
  membuka tab Collection lagi memberi kesempatan baru tanpa restart.
- Backfill: kalau art ternyata sudah ada di disk **dan bisa dimuat**, tetap
  `_populate_collection()`, bukan `continue` diam-diam.
- Epoch berubah: bersihkan antrean **dan** map in-flight/attempts, bukan
  `break` yang meninggalkan tanda `seen`.
- `_thumbnail_backfill_running` boleh dinyalakan ulang oleh
  `_populate_collection()` kalau antrean tidak kosong tapi tidak ada kemajuan,
  supaya coroutine yang ditinggalkan tidak mengunci subsistemnya.
- Tandai plafonnya dengan komentar `ponytail:` (3 percobaan per kunjungan tab,
  serial satu unduhan).

### Phase 3 — buang latch `_busy`

- Pecah `_activate_anima()` jadi pembungkus + `_activate_anima_inner()`.
  Pembungkusnya: `_set_busy(true)` → `var ok := await inner()` →
  `_set_busy(false)` → `return ok`. Satu titik teardown, semua jalur lewat
  situ.
- `_dispatch_summon()`: set `_summon_in_flight = false` **sebelum** emit, dan
  buat emit-nya tidak bisa dilewati.
- `_await_summon()` dapat deadline (bukan `await` telanjang), supaya dispatcher
  yang mati tidak bisa memblokir selamanya.
- Hapus `set_sheet_busy()` dan pakai `set_busy()` di ketiga call site-nya —
  satu-satunya efek berbedanya adalah skew `mouse_filter` + tab Synthesis, dan
  skew itu bug.
- Tutup kebocoran sekerabat di `_delete_confirmed()` (`scan_flow.gd:1533`) dengan
  pola pembungkus yang sama.

### Phase 4 — tutup re-entrancy (RC4) dan clobber (RC5)

Yang utama satu baris, dan ia menutup RC4 untuk **semua** view yang berbagi
`_thumbnail_for`, bukan hanya Collection:

- **`_thumbnail_for()` jadi getter murni.** Pindahkan start drain-nya ke
  `call_deferred` (`scan_flow.gd:5355`) **dan** jadikan repaint di :5385
  `_populate_collection.call_deferred()`. Dua-duanya, bukan salah satu: yang
  pertama mencegah drain dimulai dari dalam loop, yang kedua mencegah repaint
  dari drain yang sudah jalan. Sesudah ini tidak ada jalur sinkron dari
  `set_rows()` kembali ke `set_rows()`.
- Flag `_populating` di `set_rows()` sebagai asuransi kedua: panggilan yang
  masuk ulang di-*coalesce* jadi satu repaint sesudah loop selesai, bukan
  `_list.clear()` di tengah jalan.
- `CollectionView.set_rows()`: lewati baris ber-`id` kosong dan dedup by `id`.
  Dua baris, dan kartu yang tidak bisa dipakai jadi mustahil tampil apa pun
  penyebabnya di hulu. Pakai pemeriksaan yang **juga menolak `"<null>"`**, bukan
  hanya `is_empty()` — lubang yang sama ada di `:726` dan `:5195`.
- `_upsert_roster()`: merge tidak boleh menimpa `sheet_path` / `manifest` /
  `species_key` / `color_bucket` / `nickname` dengan nilai kosong atau null
  (RC5, `_apply_care_response` dan `_present`).
- `remember_boot_cache()`: simpan hanya baris ber-`status in (ready, evolving)`,
  supaya boot cache tidak bisa mengecat ulang Anima yang sudah dihapus atau
  berstatus lain pada cold start (RC5, phantom durable).

### Phase 5 — pemeriksaan yang bisa dijalankan

`game/tests/test_scan_ui.gd`:

- `set_rows()` dengan `id` kembar + satu baris `id` kosong + satu baris
  `id = "<null>"` → `item_count` sama dengan jumlah baris sah yang unik.
- **Pagar RC4:** `set_rows()` dengan thumbnail provider yang memanggil
  `set_rows()` lagi dari dalam (meniru langkah 5 rantai RC4) →
  `item_count == rows.size()`. Ini reproduksi langsung kartu hantu-nya, dan ia
  gagal pada kode sekarang.
- `set_busy(true)` lalu `set_sheet_busy(false)` (atau penggantinya) →
  `mouse_filter` tidak boleh IGNORE saat tombolnya hidup.
- Pagar grep sesuai konvensi repo: `_thumbnail_backfill_seen` wajib di-`erase`
  di jalur gagal; `_activate_anima` wajib punya tepat satu `_set_busy(false)`;
  `_dispatch_summon` wajib mereset `_summon_in_flight` sebelum emit.

`game/tests/test_client_state.gd`:

- Bundel art di disk yang ditolak `AnimaLoader` (region tidak sah, PNG
  terpotong) wajib dilaporkan "tidak tersedia" sehingga jalur art mengunduh
  ulang alih-alih mempercayainya.

## Biaya

Nol. Tidak ada perubahan backend, tidak ada migrasi, tidak ada panggilan model
atau generation. Seluruhnya client-side; unduhan ulang sheet menyentuh Storage
yang sudah dibayar, bukan Replicate.
