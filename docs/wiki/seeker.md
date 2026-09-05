# Seeker — identitas pemain

**Seeker** adalah identitas kamu di Scanima, terpisah dari nickname tiap
**Anima**. Game langsung berjalan tanpa login sebagai guest. Setelah satu Scan,
hubungkan Google untuk Scan lagi dan menjaga progres lintas perangkat.

## Guest: main tanpa login

- Guest baru mendapat **1 Core** dan **50 Bits**.
- Guest boleh menyelesaikan **satu Scan**.
- Scan yang diterima memakai 1 Core dan menyalakan inkubator untuk membuat art
  privat yang unik.
- Sesudahnya tombol Scan menjadi **Sign in to Scan Again**.
- Home, Care, Battle, Shop, Collection, profil Anima, dan Anima Atlas tetap bisa
  dipakai.

Kalau Genesis benar-benar gagal dan Core dikembalikan, kesempatan guest ikut
kembali selama belum ada Scan sukses lain.

## Create Your Seeker

Sesudah Anima pertama menetas, sheet **Create Your Seeker** meminta:

- **Seeker Name** — wajib, unik, dan tanpa spasi. Panjangnya 3–16 karakter;
  mulai dengan huruf, lalu boleh memakai huruf, angka, atau `_`.
- **Seeker Avatar** — barisan empat figur. Satu figur sudah terpilih saat sheet
  terbuka, jadi kamu boleh langsung menekan **Create Seeker** tanpa
  menyentuhnya. Ia bisa diganti kapan saja nanti, gratis.
- **Birth Year** — opsional, untuk pemain usia 13+.
- **Gender** — opsional dan boleh dilewati.

Semuanya tersimpan sekali lewat **Create Seeker**; tidak ada langkah lanjutan.
Jawaban **Gender** tidak menentukan figur mana yang terpilih, dan memilih figur
tidak mengubah jawaban **Gender** — keduanya pertanyaan yang berbeda.

Sheet boleh ditutup dulu. Selama nama belum dibuat, game akan menawarkannya lagi.
**Change Seeker Name** tersedia sesudahnya, dengan jeda 30 hari antarperubahan.

## Menu

Tap **Menu** di bottom navigation. Popover berisi:

| Aksi | Fungsi |
| --- | --- |
| **Seeker Profile** | Identitas akunmu: sign in, Level, EXP, koleksi, kemenangan, tanggal bergabung, dan Trophy Showcase |
| **Settings** | Pengaturan aplikasi |

Di **Settings**:

| Aksi | Fungsi |
| --- | --- |
| **Music** | Nyalakan atau matikan lagu latar. Default menyala |
| **Help** | Penjelasan singkat Seeker |

Aksi akun tidak ada di Settings. **Sign in with Google**, **Sign Out**,
**Change Seeker Name**, dan **Delete Account** semuanya hidup di
**Seeker Profile**.

Music adalah setting perangkat dan tetap tersimpan saat kamu berganti akun.

Lagu latar berganti sendiri mengikuti layar: satu lagu tenang untuk Home, Scan,
Collection, dan lobby Battle, satu lagu cepat begitu Duel, Team Battle, atau
node Expedition dimulai, dan satu lagu terpisah untuk Boss Seeker. Perpindahan
memakai crossfade, dan lagu Home melanjutkan dari posisi terakhir sesudah battle
selesai, bukan mengulang dari awal.

## Google: guest terpisah atau pindah progres

Guest perangkat disimpan tetap pada instalasi ini. Saat menekan **Sign in with
Google**, pilih salah satu. Tidak ada yang dihapus di kedua pilihan; yang berbeda
adalah akun mana yang kamu lihat sesudahnya. Kalau guest sudah punya Anima,
**Move Guest Progress** berdiri lebih dulu karena hanya ia yang membawa Anima itu
ikut:

- **Move Guest Progress** — guest menjadi Seeker Google dengan UID yang sama.
  Semua progres ikut pindah dan layarmu tidak berubah. Setelah **Sign Out**,
  perangkat membuat guest baru yang kosong; guest lama hanya bisa dibuka melalui
  Google tersebut.
- **Keep Guest Separate** — Google membuka Seeker miliknya sendiri, dan Seeker itu
  mulai dari nol. Anima guest tidak dihapus, tapi ia tinggal di akun guest dan
  tidak terlihat sampai **Sign Out** mengembalikan guest itu beserta Anima, Bits,
  tas, dan EXP miliknya.

Guest hanya hidup di perangkat ini dan tidak punya email. Uninstall atau clear
data menghapus satu-satunya jalan masuk ke akun guest, jadi pilih **Move Guest
Progress** kalau Anima guest itu ingin kamu simpan untuk seterusnya.

Google selalu menampilkan pemilih akun. Kalau akun yang dipilih sudah memiliki
Seeker, progres guest **tidak pernah digabungkan**. Game hanya menawarkan **Sign
In Separately** ke Seeker Google itu atau Cancel untuk tetap menjadi guest.

Seeker Google baru mendapat **3 Core tambahan sekali**, sehingga grant starter
lifetime menjadi 4 Core. Ini bukan reset saldo: kalau Core guest sudah dipakai
sebelum **Move Guest Progress**, saldo sesudah pindah biasanya 3.

Untuk berpindah dari Google A ke Google B: **Sign Out** dulu ke guest, lalu tekan
**Sign in with Google** dan pilih Google B. **Sign Out** hanya mencabut sesi di
perangkat ini; perangkat lain tetap login.

Pergantian akun dan **Delete Account** ditolak sementara Scan, Care, pembelian
Shop, Battle, Evolution, Synthesis, atau Expedition masih aktif. Selesaikan atau
tutup aktivitas itu dulu agar intent akun lama tidak terkirim memakai akun baru
atau berlomba dengan penghapusan permanen.

Kalau browser ditutup atau callback gagal, tap **Sign in with Google** lagi untuk
mengulang tanpa menunggu; guest tetap aman. Google baru dinyatakan siap setelah
starter Core tersimpan. Jika sinkronisasi Core gagal, restart game untuk mencoba
grant yang sama lagi tanpa risiko Core ganda.

## Seeker Profile

Tombol besar di bawah namamu adalah aksi akun: **Sign in with Google** saat
kamu masih guest, **Sign Out** saat Google sudah terhubung. Ikon titik tiga di
kanan judul membuka **Change Seeker Name**, **Change Seeker Avatar**, dan —
hanya untuk akun yang sudah terhubung Google — **Delete Account**.

| Baris | Artinya |
| --- | --- |
| **Seeker Level** | Level kosmetik; tidak mengubah stat atau hadiah Battle |
| **Seeker EXP** | Tumbuh saat Anima lahir siap, mendapat EXP Care, atau menang Battle berhadiah EXP |
| **Anima** | Jumlah Anima siap pakai |
| **Species Discovered** | Jumlah spesies unik dalam koleksi |
| **Enemies Defeated** | Semua duel menang, termasuk Train |
| **Joined** | Tanggal akun dibuat |
| **Trophy Showcase** | Semua Core dari chapter Expedition yang sudah kamu selesaikan. Kalau belum ada, profil tetap menampilkan section-nya dengan petunjuk cara mendapatkannya |

## Seeker Avatar

Potret di atas namamu adalah **kamu**, bukan Anima yang sedang di-Summon.

Figurnya kamu pilih pertama kali di **Create Your Seeker**, di sheet yang sama
tempat kamu menamai dirimu. Sesudah itu, buka ikon titik tiga lalu **Change
Seeker Avatar**: pickernya menampilkan keempat figur sekaligus dan menandai yang
sedang kamu pakai.

- Gratis, tanpa masa tunggu, dan boleh diganti sesering yang kamu mau. Potretnya
  berganti di ketukan yang sama; kalau server menolak, figur sebelumnya kembali
  sendiri.
- Murni kosmetik. Ia tidak menyentuh stat, hadiah, maupun **Gender** dan **Birth
  Year** yang kamu isi di **Create Your Seeker** — keduanya tidak saling
  mengikuti, jadi figur mana pun boleh dipakai siapa pun.
- Belum pernah memilih berarti kamu memakai figur default.
- Selain di Seeker Profile, figurmu berdiri di arena **Duel**, **Team Battle**,
  dan **Expedition** — lihat [Battle](battle.md#kamu-di-arena).
- Seeker lain melihatnya juga: kalau Anima-mu terpublish dan mereka pernah duel
  denganmu, figurmu berdiri di sebelah namamu di profil Atlas Anima itu — lihat
  [Atlas](atlas.md#isi-profil-atlas). Lawan di arena tetap anonim; figurmu tidak
  ikut ke sana.
- Top HUD belum menampilkannya; ia tetap menulis nama Seeker sebagai teks biasa.

## Seeker dan Anima berbeda

- Nama Seeker unik untuk pemain; nickname Anima hanya nama monster itu.
- **Change Seeker Name** punya jeda 30 hari; Rename Anima tidak.
- Seeker Level hanya kosmetik; Level Anima menumbuhkan attributes.
- **Sign Out** hanya mengganti akun aktif di perangkat ini.
- **Delete** di profil Anima menghapus satu monster. **Delete Account** menghapus
  Seeker aktif, semua Anima, Cores, Bits, tas, dan riwayat Battle miliknya.

Penghapusan akun permanen dan tidak memberi refund. Art spesies bersama tetap
berada di pustaka untuk pemain lain. Jika Seeker Google memakai **Keep Guest
Separate**, guest perangkat diperiksa dulu lalu dibuka kembali setelah
penghapusan. Jika guest itu tidak dapat dipulihkan, **Delete Account** dibatalkan.
Menghapus guest atau Seeker hasil **Move Guest Progress** membuat guest baru yang
kosong.

## Lihat juga

- [Ekonomi](economy.md) — Cores dan guest Scan
- [Anima](anima.md) — EXP, nickname, dan Delete Anima
- [Anima Atlas](atlas.md) — form Scanned, Expedition, dan Duel
- [Battle](battle.md) — Battle, Train, dan kemenangan
