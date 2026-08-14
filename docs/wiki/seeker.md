# Seeker — identitas pemain

**Seeker** adalah identitas kamu di Scanima, terpisah dari nickname tiap
**Anima**. Game langsung berjalan tanpa login sebagai guest. Setelah satu Scan,
hubungkan Google untuk Scan lagi dan menjaga progres lintas perangkat.

## Guest: main tanpa login

- Guest baru mendapat **1 Core** dan **50 Bits**.
- Guest boleh menyelesaikan **satu Scan**.
- Kalau spesiesnya baru, Scan memakai 1 Core dan menyalakan inkubator.
- Kalau art spesiesnya sudah ada, Core tidak berkurang, tetapi kesempatan Scan
  guest tetap selesai.
- Sesudahnya tombol Scan menjadi **Sign in to Scan Again**.
- Home, Care, Battle, Shop, Collection, dan profil Anima tetap bisa dipakai.

Kalau Genesis benar-benar gagal dan Core dikembalikan, kesempatan guest ikut
kembali selama belum ada Scan sukses lain.

## Create Your Seeker

Sesudah Anima pertama menetas, sheet **Create Your Seeker** meminta:

- **Seeker Name** — wajib, unik, dan tanpa spasi. Panjangnya 3–16 karakter;
  mulai dengan huruf, lalu boleh memakai huruf, angka, atau `_`.
- **Birth Year** — opsional, untuk pemain usia 13+.
- **Gender** — opsional dan boleh dilewati.

Sheet boleh ditutup dulu. Selama nama belum dibuat, game akan menawarkannya lagi.
**Change Seeker Name** tersedia sesudahnya, dengan jeda 30 hari antarperubahan.

## Menu Seeker

Tap ikon menu 96px di baris HUD atas.

| Aksi | Fungsi |
| --- | --- |
| **Seeker Profile** | Lihat Level, EXP, koleksi, kemenangan, dan tanggal bergabung |
| **Sign in with Google** | Hubungkan guest atau pulihkan Seeker lama |
| **Reduced Motion** | Kurangi gerakan UI, Care, Battle, dan inkubator |
| **Help** | Penjelasan singkat Seeker |
| **Delete Account** | Hapus seluruh akun secara permanen |

Reduced Motion adalah setting perangkat. Ia tetap tersimpan saat kamu berganti
akun.

## Google: link atau restore

Kalau Google itu belum punya Seeker Scanima, **link** mempertahankan semua progres
guest: Anima, Bits, tas, EXP, dan kemenangan. Akun mendapat **2 Core tambahan
sekali**, sehingga grant starter lifetime menjadi 3 Core. Ini bukan reset saldo:
kalau Core guest sudah dipakai untuk Genesis, saldo sesudah link biasanya 2.

Kalau Google itu sudah punya Seeker, game menampilkan peringatan **Restore
Existing Seeker**. Restore membuka progres akun Google tersebut dan **tidak
menggabungkan** progres guest di perangkat ini. Pilih Cancel untuk tetap menjadi
guest.

Kalau browser ditutup atau callback gagal, tap **Sign in with Google** lagi untuk
mengulang tanpa menunggu; progres guest tetap aman. Link baru dinyatakan selesai
setelah starter Core tersimpan. Jika sinkronisasi Core gagal, restart game untuk
mencoba grant yang sama lagi tanpa risiko Core ganda.

## Seeker Profile

| Baris | Artinya |
| --- | --- |
| **Seeker Level** | Level kosmetik; tidak mengubah stat atau hadiah Battle |
| **Seeker EXP** | Tumbuh saat Anima lahir siap, mendapat EXP Care, atau menang Battle berhadiah EXP |
| **Anima** | Jumlah Anima siap pakai |
| **Species Discovered** | Jumlah spesies unik dalam koleksi |
| **Enemies Defeated** | Semua duel menang, termasuk Train |
| **Joined** | Tanggal akun dibuat |

Portrait memakai companion aktif.

## Seeker dan Anima berbeda

- Nama Seeker unik untuk pemain; nickname Anima hanya nama monster itu.
- **Change Seeker Name** punya jeda 30 hari; Rename Anima tidak.
- Seeker Level hanya kosmetik; Level Anima menumbuhkan attributes.
- **Delete** di profil Anima menghapus satu monster. **Delete Account** menghapus
  Seeker, semua Anima, Cores, Bits, tas, dan riwayat Battle.

Penghapusan akun permanen dan tidak memberi refund. Art spesies bersama tetap
berada di pustaka untuk pemain lain.

## Lihat juga

- [Ekonomi](economy.md) — Cores, guest Scan, dan cache hit
- [Anima](anima.md) — EXP, nickname, dan Delete Anima
- [Battle](battle.md) — Battle, Train, dan kemenangan
