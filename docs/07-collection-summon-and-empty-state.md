# Collection Summon dan Empty State

Status: diimplementasikan dan diverifikasi 13 Agustus 2026.

## Ringkasan kebutuhan

- Tap kartu Anima di Collection tidak langsung berpindah layar.
- Bottom sheet memberi dua aksi: `View Profile` dan `Summon`.
- `Summon` hanya mengganti companion aktif di Home; tidak memakai biaya,
  cooldown, model call, atau state aktif baru di database.
- Bottom sheet menampilkan base stats dan care stats authoritative.
- Pemain tanpa Anima mendapat Home empty state dengan CTA scan yang jelas.
- Loading, roster error, dan roster kosong harus menjadi tiga state berbeda.
- Tidak ada tutorial carousel atau onboarding flag baru.

## Asumsi non-fungsional

- Roster tetap berukuran puluhan Anima per pemain.
- Hanya art Anima yang dipilih yang boleh diunduh; Collection tidak mengunduh
  seluruh sheet hanya untuk thumbnail.
- Satu care sync gratis per Anima per kunjungan Collection cukup. Tidak ada loop
  atau retry otomatis.
- Endpoint care tetap owner-only dan server-authoritative. Perubahan ini tidak
  menambah data pribadi, mata uang, migration, atau endpoint.
- View hanya mempresentasikan state dan memancarkan intent. `scan_flow` tetap
  mengorkestrasi async/navigation; `Backend` tetap satu-satunya transport.

## Keputusan

### Bottom sheet, bukan action dock atau tombol per kartu

Tap kartu membuka backdrop dan bottom sheet. Sheet memuat portrait, nama,
Element, Stage, rarity, badge `Active`, lima base stat (HP, ATK, DEF, SPD,
Special), serta empat care meter (Hunger, Energy, Hygiene, Bond).

Base stats tampil langsung. Care section memakai skeleton sampai satu sync
server selesai, lalu hasilnya di-cache selama Collection tetap terbuka. Respons
async membawa revision pilihan; respons lama diabaikan jika sheet sudah ditutup
atau pemain memilih Anima lain.

Footer memakai `View Profile` sebagai aksi sekunder dan `Summon` sebagai CTA.
Pada companion aktif, CTA berubah menjadi `Summoned` dan disabled. Sheet ditutup
lewat backdrop atau Back/Escape, tanpa X kecil. Semua aksi minimal 96px.

### Summon adalah transisi tematik tanpa mekanik ekonomi

Saat `Summon` ditekan, CTA masuk loading sementara art pilihan dipastikan ada.
Companion lama dan `GameState.last_anima` belum berubah pada tahap ini. Jika
download atau sync gagal, sheet tetap terbuka dan companion lama dipertahankan.

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
- Semantik: companion aktif lokal, bukan summon berbiaya atau bertimer.
- Surface pilihan: bottom sheet dengan stats sekilas.
- Stats: base stats dan care stats authoritative.
- Care freshness: sync satu kali saat Anima dipilih.
- Transisi: dissolve companion lama, portal, lalu reveal companion baru.
- First-time UX: contextual Home empty state, bukan redirect atau tutorial.
