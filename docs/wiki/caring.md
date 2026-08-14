# Perawatan

Anima punya tiga kebutuhan, masing-masing 0–100. Semuanya pelan-pelan turun selama waktu berjalan, termasuk saat app ditutup.

| Kebutuhan | Artinya | Turun kira-kira | Dipulihkan oleh |
| --- | --- | --- | --- |
| **Hunger** | Lapar | Habis dalam ~10 jam | **Feed** |
| **Energy** | Stamina | Habis dalam ~14 jam kalau bangun | **Sleep**, atau item Energy di Shop |
| **Hygiene** | Kebersihan | Habis dalam ~24 jam | **Clean** |

**Clean** masih **5 Bits**. **Feed** memakai makanan dari tas. Play dan Sleep gratis. Item Energy dibeli di Shop, dipakai dari tab Items.

## Shop

Tombol **Shop** seukuran chip **Bits** dan duduk tepat di bawah baris HUD, selaras dengan Bits. Animas / Cores / Bits tetap satu baris. Tetap kelihatan saat Anima tidur, dari tab mana pun.

- Tab **Food**: sembilan makanan, dari Byte Berry (10 Hunger / 2 Bits) sampai Nova Feast (penuh / 20 Bits).
- Tab **Items**: Pulse Cell dan Reactor Pack mengisi Energy; tujuh item lain hanya untuk Battle.
- Tas menumpuk sampai 999. Bits kurang atau tas penuh: pembelian ditolak, tidak terpotong dua kali kalau sinyal putus.

## Feed

Tap **Feed**, pilih makanan yang kamu punya. Hunger yang diisi tergantung makanannya, bukan angka tetap +35.

Tidak bisa dipakai kalau meter Hunger sudah kelihatan penuh — tombol redup, makanan tidak terpakai. Tas kosong mengarah ke tab Food di Shop.

EXP +3 hanya saat Hunger **menyeberang dari bawah 40 ke 40 atau lebih**. Camilan kecil dari 0 tidak cukup; makanan yang lebih mengenyangkan, atau beberapa camilan lalu satu yang menyeberang, baru dapat EXP.

Satu makanan yang cukup kenyang biasanya membuka gerbang Battle lagi (Hunger minimal 40).

## Clean

Mengisi Hygiene **+35**. Sama seperti Feed: ditolak kalau meter sudah penuh.

EXP +3 hanya kalau Anima **kotor** (Hygiene di bawah 50).

## Play

Gratis. Anima senang, Energy **−5**, EXP **+1**.

Paling banyak **lima kali Play yang dapat EXP per hari**, reset tengah malam waktu setempat. Sesudah itu tombol tetap ada tapi tap hanya memberitahu batasnya — Energy tidak dipotong dua kali.

## Sleep

Anima tidur untuk mengisi Energy.

- Companion di Home: penuh dalam **6 jam**, lalu bangun sendiri dan dapat **+5 EXP**.
- Anima di Collection (tidak di-Summon): penuh lebih cepat, **3 jam**, **tanpa** +5 EXP, dan tetap tidur di server supaya Energy tidak langsung luruh lagi.

Hunger dan Hygiene **tetap turun** selama tidur. Bangun pagi tetap perlu makan.

Kalau kamu bangunin sebelum penuh, Energy yang sudah pulih tetap ada, tapi bonus +5 EXP tidak didapat.

**Pulse Cell** (+20) dan **Reactor Pack** (+50) mengisi Energy dari Shop tanpa menunggu tidur. Meter yang sudah penuh menolaknya, dan keduanya **tidak** memberi EXP.

Di Collection, Anima yang Energy-nya sudah penuh kelihatan **bangun** (siap di-Summon), meski ia belum kamu tap.

## Dormant

Kalau Hunger dan Hygiene habis cukup lama (paling lama dihitung ~2 hari), Anima masuk **Dormant**: meringkuk, kelihatan lemah, tidak bisa Battle.

Ia **tidak hilang** dan **EXP-nya tidak direset**. Feed (makanan dari tas) dan Clean sampai kedua meter mencapai 50, ia pulih.

## Pose di Home

Anima menunjukkan keadaannya sendiri: lapar, kotor, tidur, atau lemah saat Dormant. Panel Hunger / Hygiene / Energy ikut menyala merah pada titik yang sama — Hunger di bawah 40, Hygiene di bawah 50, Energy di bawah 20 — supaya tombol Feed / Clean / Sleep kebaca sebagai langkah berikutnya.
