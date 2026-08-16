# Anima: traits, attributes, EXP

Setiap Anima lahir dari foto satu benda atau hewan non-manusia. Bentuk, jurus,
dan stats-nya mengikuti subjek itu, lalu tumbuh pelan lewat Level. Art setiap
Anima unik dan privat kecuali kamu memilih memublikasikannya ke Gallery.

Setiap Anima juga lahir dengan ukuran tubuh khas. Ukurannya berangkat dari
subjek asli, tetapi transformasi bisa membesarkan benda genggam kecil menjadi
companion yang tetap terbaca atau membuat monster tertentu jauh lebih besar.
Ukuran ini dipakai untuk proporsi di Battle: ada Anima yang mungil, normal, atau
sangat besar. Tingginya mengikuti kartu arena HP, jadi tetap terbaca sama di layar
tinggi maupun lebar dan tidak memenuhi seluruh layar tinggi. Angkanya belum ditampilkan di Profile dan tidak menambah
Health atau damage; ia murni mengatur skala visual yang tetap dibatasi agar HUD
terbaca.

Sesudah Anima pertama menetas, game menawarkan **Create Your Seeker**. Nama
Seeker adalah identitas pemain dan berbeda dari nickname Anima. Sheet boleh
ditutup dan dilanjutkan nanti.

## Traits

Kartu **About** di profil:

| Trait | Artinya |
| --- | --- |
| **Element** | Satu elemen utama dan kadang elemen kedua: Metal, Wood, Stone, Ceramic, Glass, Plastic, Cloth, Paper, Plant, Food, Fauna, Flow, Spark, Flame, Frost, Air, Toxin, atau Sound. Penting di Battle. |
| **Rarity** | Seberapa tidak biasa benda itu, 1–5. |
| **Level / form** | Hatchling (Lv. 1–15), Adult (16–35), Evolved (36–40). Wajah Anima belum berubah saat naik form. |
| **EXP** | Poin perawatan dan kemenangan. 5 EXP = 1 Level. |
| **Attack** | Nama jurus biasa, dari benda di foto. |
| **Special** | Nama jurus Special, juga dari foto. |

Kalau Anima lama belum punya nama jurus, yang tampil cuma “Attack” dan “Special”. Itu label, bukan angka tempur.

Elemen utama selalu dipakai **Attack**. **Special** memakai elemen kedua jika
ada, atau elemen utama jika Anima hanya punya satu elemen. Hewan memakai Fauna
sebagai elemen utama; elemen kedua hanya diberikan bila ciri yang terlihat
benar-benar mendukungnya.

## Attributes

Lima angka tempur. Vision membaca foto, lalu Level mengalikannya sedikit.

| Stat | Dari benda | Dipakai untuk |
| --- | --- | --- |
| **Health** | Besar / padat / berat | Nyawa di Battle |
| **Attack** | Tajam, runcing, menonjol | Damage tombol Attack |
| **Defense** | Keras dan tahan banting | Mengurangi damage yang masuk |
| **Speed** | Ringan atau terasa bergerak | Siapa serang dulu, peluang crit |
| **Special** | Ada “isi” tersembunyi: tombol, kabel, cairan, kompartemen | Damage tombol Special |

Cangkir cenderung Defense tinggi, Special rendah. Gunting cenderung Attack tinggi. Remote cenderung Special tinggi. Bukan bug kalau Attack lebih besar dari Special — itu sifat bendanya.

Naik Level membuat kelima angka itu tumbuh kira-kira **2% per level**, plus lonjakan di Adult dan Evolved.

## EXP dan Level

```
Level = 1 + (EXP ÷ 5), paling tinggi 40
```

Contoh: 25 EXP → Level 6.

| Aksi | EXP | Catatan |
| --- | --- | --- |
| Feed yang menyeberangkan Hunger ke 40 | +3 | Camilan yang masih di bawah 40 = 0 |
| Clean saat kotor (Hygiene di bawah 50) | +3 | Bersih = 0 |
| Sleep penuh (companion di Home) | +5 | Bangun lebih awal = 0 |
| Play | +1 | Maks 5 kali per hari, reset tengah malam waktu setempat |
| Menang Duel berhadiah | +4 | Training = 0 |
| Menang Team Battle berhadiah | +2 aktif / +1 bench | Dua kemenangan pertama per hari; KO = 0 |
| Menang encounter Expedition | +2 aktif / +1 bench | Tiga encounter pertama per hari; KO = 0 |
| Bonus terawat (ketiga kebutuhan &gt; 70) | +8 | Sekali per hari, reset tengah malam waktu setempat |

Dormant **tidak** menghapus EXP.

## Collection dan Summon

Tap kartu membuka sheet, bukan langsung pindah companion.

- **View Profile** — lihat traits dan attributes, ganti nama, atau Delete.
- **Summon** — Anima ini pindah ke Home. Yang tadi di Home tidur.

Hanya satu companion aktif. Anima di bangku tidur supaya Energy pulih (penuh ~3 jam) dan tidak capek sendiri. Kartu Collection memakai pose-nya: Sleep selama Energy pulih, Hungry atau Dirty kalau lapar/kotor, Idle kalau siap, Damaged kalau Dormant. Tidak perlu tap dulu supaya kelihatan.

**Delete** ada di profil sebagai teks kecil, bukan tombol besar. Menghapus itu
permanen: tidak ada refund Core atau Bits. Ini hanya menghapus satu Anima.
**Delete Account** di menu [Seeker](seeker.md) menghapus seluruh akun.

Rename Anima tidak memiliki cooldown Seeker. **Change Seeker Name** adalah aksi
terpisah dan hanya tersedia sekali setiap 30 hari.
