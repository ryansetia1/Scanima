# Battle

Duel singkat lawan Anima pemain lain (tanpa nama mereka). Kamu mengirim perintah; server yang menghitung hasilnya.

## Syarat masuk

Companion harus:

- bangun (bukan Sleep)
- tidak Dormant
- **Energy minimal 20**
- **Hunger minimal 40** (tidak dalam pose lapar)

Tiap duel baru memotong **20 Energy**. Duel yang sudah jalan tidak dipotong lagi kalau app sempat tertutup.

Kalau syaratnya kurang, tombol Battle/Train redup dan memberi alasan. Satu Feed biasanya cukup untuk Hunger.

## Battle atau Train

Tiga kemenangan pertama per hari (reset **00:00 UTC**) adalah Battle berhadiah:

- **+5 Bits**
- **+4 EXP**
- +1 kemenangan tercatat

Sesudah 3/3, tombol yang sama jadi **Train**. Duelnya sama, hadiahnya nol. Core tidak pernah didapat dari sini.

Kalah atau **Forfeit** juga nol hadiah.

## Tiga perintah

| Tombol | Yang terjadi |
| --- | --- |
| **Attack** | Pukulan biasa. Memakai stat Attack. Power 50. Defense lawan penuh. |
| **Special** | Jurus lebih berat. Memakai stat Special. Power 75. Defense lawan dihitung setengah. Memakan 1 PP. |
| **Guard** | Bertahan (damage masuk dikurangi). Mengembalikan 1 PP. |

Special terasa “tembus” karena memotong Defense, bukan karena angka Special di profil selalu lebih besar.

Siapa yang gerak dulu mengikuti **Speed**. Angka Speed kedua petarung diumumkan sebelum animasi, jadi giliran bot duluan bukan bug.

## PP

PP adalah budget **satu duel**, mulai dari **3**.

- Special −1
- Guard +1
- Tidak pulih tiap giliran
- Habis di akhir duel — duel berikutnya mulai 3 lagi

Kalau PP habis, satu-satunya jalan Special lagi adalah Guard dulu. Tombol yang mati tanpa kalimat itu membingungkan; game akan memberitahumu.

## Damage, sederhana

```
damage ≈ stat × (power ÷ 50) × peredam Defense
```

- Attack: `Attack × 1.0 × (100 ÷ (100 + Defense lawan))`
- Special: `Special × 1.5 × (100 ÷ (100 + setengah Defense lawan))`

Masih ada pengali kecil: elemen, crit dari Speed, Guard, dan sedikit random.

## Elemen

Satu roda, satu arah. Kuat terhadap yang di depannya (×1.5), lemah terhadap yang di belakangnya (×0.67).

Metal → Plant → Flow → Spark → Cloth → Stone → kembali ke Metal

Contoh: Flow (air, gelas) kuat lawan Spark (listrik), lemah lawan Plant.

Saat kena, layar bisa menulis **Super effective!** atau **Not very effective.**
