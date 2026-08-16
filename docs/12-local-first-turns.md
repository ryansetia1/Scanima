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
replay-nya cocok. Skenario 31 di `npm run selftest` menjaga keduanya.

## Di mana aturannya hidup

| Lapis | File | Dipakai |
| --- | --- | --- |
| Server | `backend/supabase/functions/_shared/battle.mjs` | Duel |
| Server | `backend/supabase/functions/_shared/team_combat.mjs` | Team + Expedition |
| Client | `game/scripts/sim/deterministic_rng.gd` | PRNG |
| Client | `game/scripts/sim/element_rules.gd` | Roster, alias, matchup 18 elemen |
| Client | `game/scripts/sim/battle_sim.gd` | Duel |
| Client | `game/scripts/sim/team_sim.gd` | Team + Expedition |

Port GDScript-nya meniru semantik JavaScript, bukan menulis ulang rumusnya:
`Math.imul` 32-bit, `Number()`, dan `clampInt` semuanya diemulasi. `ElementRules`
memiliki `ROSTER` dan `ALIASES`; `ElementCatalog` hanya memakai ulang keduanya
untuk label dan ikon. Urutan itu sengaja — kalau dibalik, simulasi ikut menarik
autoload `LocaleManager` dan gagal dikompilasi di mode `--script`.

## Dua pagar yang menjaga parity

1. **Golden vectors.** `node backend/tools/emit_sim_vectors.mjs` menjalankan
   resolver JavaScript pada PRNG, fungsi skalar, `createFighter`, reward preview,
   serta skenario Duel dan Team penuh — termasuk jalur Boss `final_ace` — lalu
   menuliskan input dan output-nya. `tests/test_battle_sim_parity.gd` memutar
   ulang vektor itu di GDScript. Input fighter ikut diemit; test tidak boleh
   punya tabelnya sendiri, karena tabel kembar itulah yang dulu menyimpang.
2. **Pemindai konstanta.** Skenario 32 di `npm run selftest` membaca konstanta di
   `game/scripts/sim/*.gd` dan membandingkannya dengan pasangannya di `_shared`.
   Konstanta yang diubah di satu sisi gagal di CI, bukan di tangan pemain.

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

- **Switch, di semua mode.** Anggota yang masuk butuh sprite sheet-nya, dan sheet
  itu belum tentu ada di cache. Mengunduhnya di tengah prediksi menghapus seluruh
  keuntungan latensinya. Turn yang menghasilkan event `switch` — termasuk forced
  switch sesudah KO dan `final_ace` Boss — jatuh ke jalur lama.
- **Item Expedition.** `ExpeditionController` tidak memegang katalog Shop, jadi
  `TeamSim` menolak aksinya dan prediksinya kosong. Upgrade-nya mengoper katalog
  dari `scan_flow`.
- **Seluruh mata uang.** Bits, Cores, EXP, `battle_wins`, dan inventory tetap
  hanya berubah dari response server. Prediksi tidak pernah menulis saldo.

## Care

`scan_flow.optimistic_care()` memproyeksikan meter sesudah satu aksi memakai
`CareRules.projected_care()` — decay yang sama dengan Collection — lalu menambah
delta aksinya: Clean `+CARE_RESTORE`, Play `-PLAY_ENERGY_COST`, Feed dan item
Energy memakai `effect_value` dari row katalog yang sudah dipegang client. Aksi
lain (Sleep, Wake, Summon) mengembalikan Dictionary kosong dan tidak mengecat
apa pun.

Urutannya penting: meter dicat **sebelum** `_home_view.set_busy(true)`, sebab
`_refresh_care()` menghitung ulang keadaan tombol dari `_busy`. Urutan terbalik
membuka lagi Care Dock selama request masih jalan.

Kalau `care_anima` menolak, `_commit_care` mengembalikan `care` sebelumnya dan
mengecat ulang. Meter yang salah karena koneksi putus jadi tidak menetap sampai
sync berikutnya.

## Shop

`_apply_optimistic_purchase()` mengurangi Bits dan menambah jumlah item di tas
pada frame yang sama dengan tap, lalu `purchase_catalog_item` tetap pagar akhir.
Sheet Shop sengaja **tidak** dikunci selama request: `set_busy()` membangun ulang
seluruh daftar, dan kedipan itulah yang dulu terbaca sebagai lag. Kalau server
menolak, saldo dan tas dikembalikan lalu daftar dicat ulang sekali.

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
