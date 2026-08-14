# Collection Summon dan Empty State

Status: diimplementasikan dan diverifikasi 13 Agustus 2026.

## Ringkasan kebutuhan

- Tap kartu Anima di Collection tidak langsung berpindah layar.
- Bottom sheet memberi dua aksi: `View Profile` dan `Summon`.
- `Summon` mengganti companion aktif di Home dan di server (`profiles.active_anima_id`). Anima lain tidur: Energy pulih sampai penuh dalam 3 jam, Hunger/Hygiene tetap turun, tanpa +5 EXP. Tidak ada biaya, cooldown, atau model call.
- Bottom sheet menampilkan base stats dan care stats authoritative.
- Pemain tanpa Anima mendapat Home empty state dengan CTA scan yang jelas.
- Loading, roster error, dan roster kosong harus menjadi tiga state berbeda.
- Tidak ada tutorial carousel atau onboarding flag lokal baru untuk Collection.
  Onboarding identitas Seeker adalah sheet terpisah sesudah hatch pertama dan
  memakai `seeker_name is null` dari server sebagai satu-satunya status.

## Asumsi non-fungsional

- Roster tetap berukuran puluhan Anima per pemain.
- Hanya art Anima yang dipilih yang boleh diunduh; Collection tidak mengunduh
  seluruh sheet hanya untuk thumbnail.
- Satu care sync gratis per Anima per kunjungan Collection cukup. Tidak ada loop
  atau retry otomatis.
- Endpoint care tetap owner-only dan server-authoritative. `Summon` menulis
  `profiles.active_anima_id` lewat `apply_care('summon')`; client tidak bisa
  PATCH kolom itu.
- View hanya mempresentasikan state dan memancarkan intent. `scan_flow` tetap
  mengorkestrasi async/navigation; `Backend` tetap satu-satunya transport.

## Keputusan

### Bottom sheet, bukan action dock atau tombol per kartu

Tap kartu membuka backdrop dan bottom sheet. Sheet memuat portrait, nama,
Element, Level + form, rarity, badge `Active`, lima base stat yang sudah
tumbuh menurut level (HP, ATK, DEF, SPD, Special), serta tiga kebutuhan
(Hunger, Energy, Hygiene) plus bar EXP.

Base stats tampil langsung. Pada cache miss, care meter lama di-reset dan
disembunyikan lalu `UiSkeleton` menggantikannya sampai satu sync server selesai.
Cache hit menampilkan meter seketika; error menghentikan skeleton dan memakai
fallback/error copy yang sudah ada. Hasil authoritative di-cache selama
Collection tetap terbuka. Respons async membawa revision pilihan; respons lama
diabaikan jika sheet sudah ditutup atau pemain memilih Anima lain.

Chrome backdrop/handle/panel/dismiss dimiliki `UiBottomSheet`; `CollectionView`
tetap memiliki identity, cache, sync, revision, dan intent Summon/Profile. Batas
ini sengaja menjaga komponen reusable bebas dari aturan domain.

Footer memakai `View Profile` sebagai aksi sekunder dan `Summon` sebagai CTA.
Pada companion aktif, CTA berubah menjadi `Summoned` dan disabled. Sheet ditutup
lewat backdrop atau Back/Escape, tanpa X kecil. Semua aksi minimal 96px.

### Summon menidurkan companion yang tidak dipakai

Saat `Summon` ditekan, CTA masuk loading sementara server mengklaim companion
baru dan art pilihan dipastikan ada. Companion lama tidur di Postgres; Energy-nya
pulih pada sync berikutnya. `GameState.last_anima` belum berubah sampai art siap.
Jika download atau summon gagal, sheet tetap terbuka dan companion lama dipertahankan.

Setelah siap:

1. bottom sheet ditutup dan Home dibuka;
2. companion lama fade + shrink menjadi spark;
3. ring portal cyan-violet terbuka di Stage;
4. sprite pilihan dipasang dan muncul dengan squash-and-settle;
5. pilihan baru disimpan ke `GameState.last_anima`;
6. care state authoritative diterapkan.

Efek ini tidak memakai telur/inkubator karena Anima bukan sedang menetas.
Reduced Motion langsung mengganti companion tanpa dissolve atau portal. Efek
dissolve cukup memakai fade, scale, dan spark; tidak perlu shader baru yang
berisiko bentrok dengan chroma key.

### Empty state adalah bagian dari Home

Home memiliki state eksplisit:

- `Loading`: sesi/profile/roster belum selesai; tampilkan status persiapan.
- `Error`: roster gagal dimuat; tampilkan Retry, bukan onboarding.
- `Empty`: fetch roster berhasil dan hasilnya kosong.
- `Ready`: companion aktif tersedia.

State Empty menampilkan visual scanner/orb procedural yang tenang, headline
`Awaken Your First Anima`, satu kalimat penjelasan, dan CTA 96px
`Scan Your First Object`. CTA hanya membuka tab Scan; kamera tetap dibuka oleh
aksi eksplisit di layar Scan agar permission request memiliki konteks.
Setelah satu Scan guest sukses, CTA utama di tab Scan berubah menjadi
`Sign in to Scan Again`; Home/Collection dan Anima yang sudah lahir tetap dapat
dipakai.

Care Dock tetap tersembunyi, Profile disabled, sedangkan resource HUD dan bottom
navigation tetap terlihat. Collection kosong memakai versi ringkas dengan CTA
`Start First Scan`. State yang sama dipakai setelah Anima terakhir dihapus,
sehingga tidak diperlukan flag first-launch.

## Penanganan galat

- Tombol sheet dikunci selama Summon.
- Respons care/art yang revision-nya basi tidak boleh mengubah sheet.
- Kegagalan art tidak boleh mengubah companion aktif atau membuka Home kosong.
- Kegagalan care menampilkan nilai terakhir; menutup lalu membuka sheet
  menjalankan retry. Base stats dan kedua aksi tetap tersedia.
- Error roster tidak boleh dirender sebagai roster kosong.

## Verifikasi

- `test_scan_ui.gd`: sheet hidden/open, kedua section stats, active CTA, kedua
  route, stale-response guard, Loading/Error/Empty/Ready Home, touch target, dan
  Reduced Motion.
- `test_sprite_slicing.gd`: dissolve/reveal mengembalikan visibility dan
  transform presenter.
- Demo gratis: `--collection-sheet-demo`, `--empty-demo`, `--summon-demo`.
- Screenshot diperiksa pada 720×1280 dan 360×640.
- Seluruh demo memakai fixture lokal dan tidak memanggil model atau generation.

## Decision log

- Istilah utama: `Summon`, agar perpindahan companion terasa tematik.
- Semantik: companion aktif server-authoritative (`profiles.active_anima_id`); yang lain tidur.
- Thumbnail dan portrait Collection: Sleep selama Energy belum penuh (companion tidur atau Anima di bangku), Idle jika Energy penuh — termasuk yang masih ditandai tidur di server — Damaged jika Dormant. Energy penuh di bangku tidak auto-bangun di Postgres, supaya tidak luruh dan tidak kena +5 EXP.
- Surface pilihan: bottom sheet dengan stats sekilas.
- Stats: base stats dan care stats authoritative.
- Care freshness: sync satu kali saat Anima dipilih.
- Transisi: dissolve companion lama, portal, lalu reveal companion baru.
- First-time UX: contextual Home empty state, bukan redirect atau tutorial.
- Identitas Seeker dibuat sesudah Anima pertama ada, sehingga nama Seeker tidak
  menjadi login gate dan tidak tercampur dengan nickname Anima.
