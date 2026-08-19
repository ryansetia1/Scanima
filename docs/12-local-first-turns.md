# 12 — Turn local-first dan determinisme client

Keluhan yang memicu dokumen ini: setiap tap aksi Battle menunggu satu round trip
HTTP sebelum apa pun bergerak di layar. Jeda visual 1,4 detik pelat aksi memang
disengaja dan tidak diubah; yang diperbaiki adalah jeda **sebelum** pelat itu
muncul.

Arsitekturnya tetap server-authoritative. Yang berubah hanya urutannya: client
menghitung turn dengan aturan yang identik lalu menganimasikannya sementara
request-nya terbang, dan hasil server tetap yang tersimpan.

## Kenapa boleh disimulasikan di client

Combat Scanima sepenuhnya deterministik. Tidak ada input tersembunyi selama
turn: state awal (`battle_sessions.state`) sudah ada di client karena arena
membaca HP dan PP dari sana, dan RNG-nya PRNG ber-seed dari `state.seed` +
`state.turn`. Dengan aturan yang sama, dua runtime harus sampai ke event log yang
sama.

Sebelum ini benar, `resolveTurn` menyeed RNG-nya dengan
`seed:turn:idempotency_key`, dan `idempotency_key` dipilih client. Itu berarti
client bisa mengocok ulang seed sampai mendapat crit. `RULES_VERSION = 2`
membuang key itu dari seed; state lama tetap memakai formula lamanya supaya
replay-nya cocok. **Rules v3** (Agustus 2026) sudah live di backend dan menambah
move effects serta committed form multiplier. Anima dengan
`evolution_version>=1` memakai jalur committed form; snapshot `0` tetap legacy.
`rules_version < 3` replay tanpa efek.
Skenario 31 dan 38 di `npm run selftest` menjaga keduanya.

## Di mana aturannya hidup

| Lapis | File | Dipakai |
| --- | --- | --- |
| Server | `backend/supabase/functions/_shared/battle.mjs` | Duel |
| Server | `backend/supabase/functions/_shared/team_combat.mjs` | Team + Expedition |
| Client | `game/scripts/sim/deterministic_rng.gd` | PRNG |
| Client | `game/scripts/sim/element_rules.gd` | Roster, alias, matchup 18 elemen |
| Server | `backend/supabase/functions/_shared/move_effects.mjs` | Katalog efek + helper v3 (aktif hanya untuk form committed) |
| Client | `game/scripts/sim/move_effects.gd` | Port katalog efek |
| Client | `game/scripts/sim/battle_sim.gd` | Duel |
| Client | `game/scripts/sim/team_sim.gd` | Team + Expedition |

Port GDScript-nya meniru semantik JavaScript, bukan menulis ulang rumusnya:
`Math.imul` 32-bit, `Number()`, dan `clampInt` semuanya diemulasi. `ElementRules`
memiliki `ROSTER` dan `ALIASES`; `ElementCatalog` hanya memakai ulang keduanya
untuk label dan ikon. Urutan itu sengaja — kalau dibalik, simulasi ikut menarik
autoload `LocaleManager` dan gagal dikompilasi di mode `--script`.

## Dua pagar yang menjaga parity

1. **Golden vectors.** `node backend/tools/emit_sim_vectors.mjs` menjalankan
   resolver JavaScript pada PRNG, fungsi skalar, `createFighter`, EXP yield,
   serta skenario Duel dan Team penuh — termasuk jalur Boss `final_ace` — lalu
   menuliskan input dan output-nya. `tests/test_battle_sim_parity.gd` memutar
   ulang vektor itu di GDScript. Input fighter ikut diemit; test tidak boleh
   punya tabelnya sendiri, karena tabel kembar itulah yang dulu menyimpang.
2. **Pemindai konstanta.** Skenario 32 di `npm run selftest` membaca konstanta di
   `game/scripts/sim/*.gd` dan membandingkannya dengan pasangannya di `_shared`.
   Konstanta yang diubah di satu sisi gagal di CI, bukan di tangan pemain. Ia
   juga menjaga arah sebaliknya: tier dan Bits hadiah **tidak boleh** kembali ke
   `battle_sim.gd`. Keduanya hasil mensimulasikan matchup di server dan client
   tidak pernah menampilkan hadiah sebelum server menjawab, jadi port-nya hanya
   permukaan yang bisa menyimpang tanpa satu pun pemanggil.

## Alur satu turn

```
tap
 ├─ begin_action()               → underline pulse + haptic, frame yang sama
 ├─ _predict_*_turn()            → simulasi lokal dari state authoritative
 ├─ _dispatch_*()                → request terbang, TIDAK di-await
 ├─ play_events(prediksi)        → animasi penuh berjalan
 ├─ set_busy(masih terbang?)     → tombol redup kalau server belum menjawab
 └─ await hasil server
      ├─ ringkasannya sama  → set_session(row authoritative), tanpa animasi ulang
      └─ berbeda            → play_events(event server), arena snap ke hasil resmi
```

Pembandingnya ringkasan yang **dilihat pemain**, bukan seluruh state: status,
nomor turn, HP/PP petarung Duel, lalu tiap event beserta `target_hp` dan
`damage`-nya. Selisih yang tak terlihat di layar tidak perlu memicu animasi
ulang, karena `set_session` tetap memasang row authoritative.

## Yang sengaja tetap menunggu server

- **Switch yang sheet-nya belum ada di arena.** Anggota yang masuk butuh sprite
  sheet-nya, dan mengunduhnya di tengah prediksi menghapus seluruh keuntungan
  latensinya. Yang dipakai sebagai gerbang adalah cache arena, bukan jenis
  aksinya: `TeamSim.switch_targets()` membaca `anima_id` yang masuk dari tiap
  event `switch`, lalu prediksi hanya lanjut kalau `_team_art_cache` /
  `_art_cache` sudah memegang semuanya. Dalam praktiknya hampir selalu memegang,
  sebab `_prepare_team_active_art()` dan `_prepare_active_art()` memuat **seluruh**
  slot kedua party saat session dibuka — bukan hanya yang aktif. Switch sukarela,
  forced switch sesudah KO, dan switch bot karena itu dianimasikan seketika.
- **`final_ace` Boss.** Ini bukan soal art. Pelat dan dialog `last_anima`-nya
  tampil sekali per run, jadi memancarkannya dari tebakan berarti mempertaruhkan
  beat naratif yang tidak bisa ditarik kembali. Sekali per run, satu round trip.
- **Turn yang menutup encounter Boss.** Ia membawa baris `victory`/`defeat`,
  ringkasan hadiah, dan reveal Trophy first-clear sekaligus, dan ketiganya dibaca
  dari reward authoritative. Menebaknya berarti menampilkan angka turn sebelumnya
  lalu memperbaikinya di depan pemain. Satu round trip di detik terakhir run,
  ketika pemain memang berhenti menekan tombol.
- **Item Expedition.** `ExpeditionController` tidak memegang katalog Shop, jadi
  `TeamSim` menolak aksinya dan prediksinya kosong. Upgrade-nya mengoper katalog
  dari `scan_flow`.
- **Seluruh mata uang.** Bits, Cores, EXP, `battle_wins`, dan inventory tetap
  hanya berubah dari response server. Prediksi tidak pernah menulis saldo.
- **Commit evolusi.** Client boleh langsung menampilkan chamber dan menyimpan
  `pending_evolution`, tetapi tidak menebak stage, art, move, VFX, atau effect.
  Kelimanya baru tampil setelah generation privat lolos QA, RPC commit atomik,
  row authoritative menunjukkan stage berikutnya, dan cache stage baru selesai
  diunduh. Kegagalan download mempertahankan pending lalu mencoba lagi; ia tidak
  mengembalikan sprite lama sebagai form yang seolah sudah committed.
  Device yang menemukan row `evolving` tanpa intent lokal memakai resume-only:
  ia menempel ke generation server yang sudah ada dan tidak membuka spend baru.

## Care

`scan_flow.optimistic_care()` memproyeksikan meter sesudah satu aksi memakai
`CareRules.projected_care()` — decay yang sama dengan Collection — lalu menambah
delta aksinya: Clean `+CARE_RESTORE`, Play `-PLAY_ENERGY_COST`, Feed dan item
Energy memakai `effect_value` dari row katalog yang sudah dipegang client. Aksi
lain (Sleep, Wake, Summon) mengembalikan Dictionary kosong dan tidak mengecat
apa pun.

Care Dock **tidak** diredupkan selama request. Pemain sudah melihat hop-nya dan
meternya bergerak; tombol yang mati sesudah itu satu-satunya hal yang tersisa
untuk dibaca sebagai loading. Yang menjaga jalur uang tetap satu adalah
`GameState.pending_care`, dan pemeriksaannya duduk di `_commit_care` sendiri —
bukan di pemanggilnya — sebab Bag memanggil `_commit_care` langsung tanpa lewat
Care Dock, sehingga versi lama bisa menimpa pending key milik Feed yang masih
terbang.

Kalau `care_anima` menolak, `_commit_care` mengembalikan `care` sebelumnya dan
mengecat ulang. Meter yang salah karena koneksi putus jadi tidak menetap sampai
sync berikutnya.

## Ganti companion

Summon tidak bisa optimistis — sprite tidak boleh ditukar sebelum server
mengizinkan — tetapi round trip-nya tidak perlu dilihat pemain. `_activate_anima`
memuat art dari cache, memanggil `_dispatch_summon()` tanpa `await`, lalu
langsung pindah ke Home dan memainkan dissolve (0,28 s) plus charge portal
(0,18 s). Baru sesudah itu `_await_summon()` menagih hasilnya. Portal yang
berputar sudah bagian dari ritual Summon, jadi sisa latensi apa pun terbaca
sebagai animasi, bukan tunggu.

Kalau server menolak, portal ditutup dengan `burst()` dan companion lama
di-`summon_reveal()` kembali. Karena `_anima.apply()` belum pernah dipanggil,
`sprite_frames` masih memegang Anima lama dan rollback-nya tidak perlu memuat
apa pun. Jalur picker Battle (`stay_on_tab`) tetap berurutan: tidak ada animasi
transisi di sana untuk ditumpangi.

## Shop

`_apply_optimistic_purchase()` mengurangi Bits dan menambah jumlah item di tas
pada frame yang sama dengan tap, lalu `purchase_catalog_item` tetap pagar akhir.
Sheet Shop sengaja **tidak** dikunci selama request: `set_busy()` membangun ulang
seluruh daftar, dan kedipan itulah yang dulu terbaca sebagai lag. Kalau server
menolak, saldo dan tas dikembalikan lalu daftar dicat ulang sekali.

## Loading di Expedition

Satu run Expedition adalah dua belas node plus checkpoint, dan setiap langkahnya
dulu memanggil `_view.set_loading()`. Panel itu mengganti seluruh isi layar, jadi
peta yang baru dibaca pemain hilang lalu digambar ulang — dua belas kali per run,
untuk request yang paling sering selesai di bawah satu detik.

`CONTEXT_LOADING` di `expedition_controller.gd` sekarang menyebut **hanya** dua
operasi yang memang menukar konteks layar: `start_run` (hub → peta) dan `abandon`
(peta → hub). `start_zone`, `enter_node`, `checkpoint_choice`, `choose`, dan
`refresh_shop` mempertahankan panel yang sedang tampil dan cukup diredupkan
`_set_busy(true)` selama request-nya terbang; `_load_chapter` dan `_save_team`
tidak mengumumkan apa pun. Kesembilan key `ui.csv` yang tidak lagi punya
pemanggil sudah dihapus, bukan ditinggalkan menganggur.

Art encounter berikutnya tidak perlu ditunggu di detik pemain menekan node,
sebab payload run sudah menyebutkan semuanya: `arena_background_url` (4–5 MB per
zona), `party_state`, dan `boss_seeker`. `_preload_run_art()` karena itu
dipanggil dari `_present()` **tanpa `await`** setiap kali peta tampil tanpa
encounter aktif, dan lawan ikut kalau `_chapter_manifest` masih dipegang dari
layar detail chapter — manifest itu membawa `sheet_url` publik untuk setiap
roster, jadi zona berjalan (plus roster Boss di zona terakhir) bisa disiapkan
lebih dulu. Dua pagarnya: `_preload_running` menolak preload kedua, dan
`_prepare_active_art()` menunggu `_preload_settled` kalau pemain menekan node
lebih cepat daripada unduhannya — jadi tap yang mendahului preload memakai
unduhan yang sama alih-alih memulai unduhan kedua atas byte yang sama.

Anggota tim adalah Anima pemain sendiri, dan sheet-nya biasanya sudah ada di
`user://animas/` dari Home/Collection. `_load_art()` sekarang membaca cache disk
itu lewat `GameState.has_sprite_for_anima(anima_id, stage)` sebelum menyentuh
signed URL, jadi empat sheet ~1 MB tidak diunduh ulang tiap run. Kunci cache-nya
memuat stage, jadi Anima yang baru berevolusi tetap mendapat art barunya.

Hub mengirim `chapters` dan `team` bersamaan lewat `_dispatch()`/
`_await_dispatch()` — helper yang sama yang dipakai commit turn. Keduanya tidak
saling bergantung, jadi hub menunggu satu round trip. `Backend.ensure_session()`
dipanggil lebih dulu karena `Backend` belum punya guard refresh in-flight: dua
request paralel yang sama-sama menemukan token nyaris kedaluwarsa akan memakai
refresh token yang sama dua kali.

Yang **tetap** menunggu server tidak berubah: hasil encounter, reward, EXP,
Bits, item, checkpoint, dan reveal Trophy semuanya tetap dari response. Prediksi
turn Expedition juga tidak disentuh — ia masih berhenti di `final_ace`, turn
penutup Boss, dan item, dengan alasan yang sama seperti di atas.

## Turn yang gagal terkirim

Dua lapis, dan keduanya perlu:

1. **Ulang sendiri.** `Backend._send()` menerima jatah `retries` dan hanya
   memakainya untuk operasi `turn`. Yang diulang hanya kegagalan transport —
   `_send_once()` menandainya `transport: true` — karena server yang sudah
   menjawab 4xx berarti sudah memutuskan. Backoff 2 lalu 4 detik; total ~6 detik
   saat benar-benar offline, dan itu tertutup animasi yang sudah berjalan.
   Commit turn aman diulang: `idempotency_key`-nya sudah dipegang server.
2. **Mundur.** Sesudah jatah habis, arena dikembalikan ke session terakhir yang
   disahkan server (`session_before` di Duel/Team, `_encounter` di Expedition).
   Tanpa ini arena tertinggal di masa depan dan tap berikutnya mengirim nomor
   turn yang belum pernah ada, yang dijawab `STALE_BATTLE`.

Antrean multi-turn offline **tidak** dibangun. Session Duel kedaluwarsa 30 menit,
forced switch butuh sprite sheet yang belum tentu ter-cache, dan reward tidak
bisa ditampilkan sebelum server menghitungnya — jadi pemain yang bermain lima
turn offline berisiko kehilangan semuanya sekaligus. Menunggu enam detik lalu
mengulang satu aksi lebih jujur.

## Boot dari cache

`user://boot_cache.json` menyimpan salinan **display-only** respons server
terakhir: profil, roster, katalog, dan inventory. Ia dipakai `_paint_boot_cache()`
untuk menggambar Home sebelum satu pun request selesai, lalu ditimpa data segar.

- Cache milik UID lain tidak pernah dipakai; satu device bisa berpindah dari
  guest ke akun Google dan roster keduanya berbeda.
- `clear_account_state()` dan `discard_guest_local_state()` menghapusnya.
- Meter care yang digambar dari cache selalu lewat `CareRules.projected_care()`,
  jadi angkanya tetap benar setelah app lama ditutup.
- Katalog tetap di-fetch sekali per sesi (`_catalog_synced`) supaya harga baru
  tidak tertahan cache.
- Roster yang gagal di-refresh tidak menghapus tampilan cache; errornya toast.

Cache tidak pernah jadi otoritas. Saldo, kebutuhan, dan inventory yang
dibelanjakan tetap hanya dari Postgres.

## Biaya server per turn

`withSignedRoster()` dulu menandatangani ulang setiap sheet roster pada setiap
commit turn — hingga delapan `createSignedUrl` per tap. `_shared/signed_roster.ts`
sekarang menyimpan cache module-level (`signSheetUrl`) yang memakai ulang URL
selama masih jauh dari kedaluwarsa. Isolate yang mati kehilangan cache-nya dan
menandatangani ulang; itu benar, bukan bug.
