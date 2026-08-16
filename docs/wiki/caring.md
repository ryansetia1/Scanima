# Perawatan

Anima punya tiga kebutuhan, masing-masing 0–100. Semuanya pelan-pelan turun selama waktu berjalan, termasuk saat app ditutup.

Kalau gerakan terasa terlalu ramai, aktifkan **Reduced Motion** dari menu
[Seeker](seeker.md). Informasi dan tombol tetap ada; animasinya yang dikurangi.

| Kebutuhan | Artinya | Turun kira-kira | Dipulihkan oleh |
| --- | --- | --- | --- |
| **Hunger** | Lapar | Habis dalam ~25 jam di Home | **Feed** |
| **Energy** | Stamina | Habis dalam ~14 jam kalau bangun | **Sleep**, atau item Energy di Bag |
| **Hygiene** | Kebersihan | Habis dalam ~24 jam | **Clean** |

**Clean** gratis. **Feed** memakai makanan dari **Bag**. Play dan Sleep juga gratis. Item Energy dibeli di Shop, dipakai dari **Bag**.

Meter bergerak di detik yang sama dengan ketukanmu. Angka resminya datang dari
server sesaat kemudian dan menimpa tampilan itu; kalau aksinya ternyata ditolak
(misalnya koneksi putus), meternya kembali ke nilai sebelumnya.

Membuka app juga tidak lagi memperlihatkan layar tunggu: companion terakhirmu
langsung tampil beserta perkiraan meternya, lalu angka resmi dari server
menyusul beberapa saat kemudian.

## Shop dan Bag

Tombol **Shop** seukuran chip **Bits** dan duduk tepat di bawah baris HUD, selaras dengan Bits di kanan. **Bag** sama ukurannya, rata kiri di pojok kiri atas, sejajar dengan Shop. Keduanya hanya tampil di **Home**, termasuk saat Anima tidur; tab lain tetap bersih. Animas / Cores / Bits tetap satu baris.

Shop hanya untuk beli. Isi tas dibuka dari **Bag**. Beli makanan dan item
**sebelum** memulai Duel, Team Battle, atau Expedition. Selama battle atau
run masih berjalan, **Shop** redup dan menolak pembelian; **Bag** tetap bisa
memakai makanan dan Energy yang sudah ada.

- Shop tab **Food**: sembilan makanan, dari Byte Berry (10 Hunger / 1 Bit) sampai Nova Feast (penuh / 10 Bits).
- Shop tab **Items**: Pulse Cell dan Reactor Pack mengisi Energy; tujuh item lain hanya untuk Battle.
- **Bag** tab **Food**: makanan yang kamu punya. Tap **Feed** untuk memberi makan.
- **Bag** tab **Items**: Pulse Cell / Reactor Pack punya tombol **Use**. Item Battle tidak — itu dipakai dari tombol **Item** di arena.
- Tas menumpuk sampai 999. Bits kurang atau tas penuh: pembelian ditolak, tidak terpotong dua kali kalau sinyal putus.

## Feed

Tap **Feed** di Care Dock, atau buka **Bag** lalu tab Food, lalu pilih makanan yang kamu punya. Hunger yang diisi tergantung makanannya, bukan angka tetap +35.

Tidak bisa dipakai kalau meter Hunger sudah kelihatan penuh — tombol redup, makanan tidak terpakai. Tas kosong mengarah ke tab Food di Shop.

EXP +3 hanya saat Hunger **menyeberang dari bawah 40 ke 40 atau lebih**. Camilan kecil dari 0 tidak cukup; makanan yang lebih mengenyangkan, atau beberapa camilan lalu satu yang menyeberang, baru dapat EXP.

Lapar atau kotor tidak mengunci Battle, tapi stats duel turun — makin rendah meternya, makin lemah. Feed dan Clean mengembalikan stats. Feed juga memberi EXP +3 saat Hunger menyeberang 40. Hunger plus Hygiene yang habis lama-lama jadi Dormant.

## Clean

Gratis. Mengisi Hygiene **+35**. Ditolak kalau meter sudah penuh.

EXP +3 hanya kalau Anima **kotor** (Hygiene di bawah 50).

## Play

Gratis. Anima senang, Energy **−5**, EXP **+1**.

Paling banyak **lima kali Play yang dapat EXP per hari**, reset tengah malam waktu setempat. Sesudah itu tombol tetap ada tapi tap hanya memberitahu batasnya — Energy tidak dipotong dua kali.

## Sleep

Anima tidur untuk mengisi Energy.

- Companion di Home: penuh dalam **6 jam**, lalu bangun sendiri. Siklus penuh
  pertama tiap Anima pada hari itu mendapat **+5 EXP**; siklus berikutnya tetap
  mengisi Energy tetapi tidak memberi EXP lagi sampai reset tengah malam waktu
  setempat.
- Anima di Collection (tidak di-Summon): penuh lebih cepat, **3 jam**, **tanpa** +5 EXP, dan tetap tidur di server supaya Energy tidak langsung luruh lagi.

Hunger dan Hygiene **tetap turun** selama tidur di Home. Anima di Collection turun jauh lebih pelan dan tidak sampai lapar atau kotor — mereka istirahat aman sampai di-Summon. Bangun pagi di Home tetap perlu makan.

Kalau kamu bangunin sebelum penuh, Energy yang sudah pulih tetap ada, tapi bonus +5 EXP tidak didapat.

**Pulse Cell** (+20) dan **Reactor Pack** (+50) mengisi Energy dari **Bag** (tab Items) tanpa menunggu tidur. Beli dulu di Shop. Meter yang sudah penuh menolaknya, dan keduanya **tidak** memberi EXP.

Di Collection, kartu memakai pose-nya: Sleep selama Energy pulih, Idle kalau siap Summon, Damaged kalau sudah Dormant sebelum istirahat. Yang sudah lapar atau kotor sebelum di-Summon tetap kelihatan begitu; companion yang istirahat sehat tidak sampai lapar atau kotor. Tidak perlu tap dulu.

## Dormant

Kalau companion di Home dibiarkan Hunger dan Hygiene habis cukup lama (paling lama dihitung ~2 hari), ia masuk **Dormant**: meringkuk, kelihatan lemah, tidak bisa Battle. Anima di Collection tidak masuk Dormant baru; yang sudah Dormant sebelum istirahat tetap perlu makan dan dibersihkan sesudah di-Summon.

Ia **tidak hilang** dan **EXP-nya tidak direset**. Feed (makanan dari tas) dan Clean sampai kedua meter mencapai 50, ia pulih.

## Pose di Home

Anima menunjukkan keadaannya sendiri: lapar, kotor, tidur, atau lemah saat Dormant. Panel Hunger / Hygiene / Energy ikut menyala merah pada titik yang sama — Hunger di bawah 40, Hygiene di bawah 50, Energy di bawah 20 — supaya tombol Feed / Clean / Sleep kebaca sebagai langkah berikutnya.
