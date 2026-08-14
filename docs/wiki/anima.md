# Anima: traits, attributes, EXP

Setiap Anima lahir dari foto. Yang kelihatan di profil dan Collection datang dari benda itu, lalu tumbuh pelan lewat Level.

## Traits

Kartu **About** di profil:

| Trait | Artinya |
| --- | --- |
| **Element** | Bahan / fungsi benda: Metal, Plant, Flow, Spark, Cloth, atau Stone. Penting di Battle. |
| **Rarity** | Seberapa tidak biasa benda itu, 1–5. |
| **Level / form** | Hatchling (Lv. 1–15), Adult (16–35), Evolved (36–40). Wajah Anima belum berubah saat naik form. |
| **EXP** | Poin perawatan dan kemenangan. 5 EXP = 1 Level. |
| **Attack** | Nama jurus biasa, dari benda di foto. |
| **Special** | Nama jurus Special, juga dari foto. |

Kalau Anima lama belum punya nama jurus, yang tampil cuma “Attack” dan “Special”. Itu label, bukan angka tempur.

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
| Menang Battle berhadiah | +4 | Training = 0 |
| Bonus terawat (ketiga kebutuhan &gt; 70) | +8 | Sekali per hari, reset tengah malam waktu setempat |

Dormant **tidak** menghapus EXP.

## Collection dan Summon

Tap kartu membuka sheet, bukan langsung pindah companion.

- **View Profile** — lihat traits dan attributes, ganti nama, atau Delete.
- **Summon** — Anima ini pindah ke Home. Yang tadi di Home tidur.

Hanya satu companion aktif. Anima di bangku tidur supaya Energy pulih (penuh ~3 jam) dan tidak capek sendiri. Kartu Collection memakai pose-nya: Sleep selama Energy pulih, Hungry atau Dirty kalau lapar/kotor, Idle kalau siap, Damaged kalau Dormant. Tidak perlu tap dulu supaya kelihatan.

**Delete** ada di profil sebagai teks kecil, bukan tombol besar. Menghapus itu permanen: tidak ada refund Core atau Bits.
