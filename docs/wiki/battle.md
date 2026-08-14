# Battle

Duel singkat lawan Anima yang sudah dipublikasikan pemain lain (tanpa identitas
pemilik) atau lawan sistem. Kamu mengirim perintah; server yang menghitung
hasilnya.

## Syarat masuk

Companion harus:

- bangun (bukan Sleep)
- tidak Dormant
- **Energy minimal 20**

Lapar atau kotor tidak mengunci Battle, tapi Anima jadi **lebih lemah** di duel itu. Makin lapar atau makin kotor, potongannya makin dalam (HP, Attack, Special, Guard, Speed). Keduanya sekaligus lebih parah, tapi tidak sampai membuat duel mustahil. Bits tetap dari kekuatan lawan, bukan dari seberapa lemah kamu. Feed dan Clean mengembalikan stats.

Tiap duel baru memotong **20 Energy**. Duel yang sudah jalan tidak dipotong lagi kalau app sempat tertutup. Energy pulih lewat **Sleep** (gratis).

Kalau companion aktif tidak memenuhi syarat, tombolnya jadi **Choose Anima**. Tap membuka daftar Anima-mu: yang siap bisa dipilih, yang belum siap redup dengan alasan singkat (Low Energy, Sleeping, Dormant). Tap kartu membuka sheet seperti di Collection — **View Profile** tetap ada, **Battle** atau **Train** langsung memulai duel (Anima bangku di-Summon otomatis).

## Battle atau Train

Tiga kemenangan pertama per hari (reset **tengah malam waktu setempat**) adalah Battle berhadiah:

- Bits menurut kekuatan lawan (kira-kira 5–16)
- **+4 EXP**
- +1 kemenangan progression pada Anima

Layar lobby menulis tier lawan (Favorable / Even / Tough / Formidable) dan Bits yang akan didapat, plus **Progress x/3** dan **Bits x/100**.

Sesudah 3/3, tombol yang sama jadi **Train**. Duelnya sama; EXP dan kemenangan
progression Anima berhenti, tetapi **Bits masih dibayar** sampai cap **100 Bits
per hari**. Sesudah 100/100, Training nol hadiah. Core tidak pernah didapat dari
sini.

Stat **Enemies Defeated** di [Seeker Profile](seeker.md) menghitung semua duel
menang, termasuk Train. Itu berbeda dari **Progress x/3**, yang hanya menentukan
hadiah EXP harian.

Kalah atau **Forfeit** juga nol hadiah. **Forfeit** ada di pojok kanan atas arena. Shop dan Bag hanya ada di Home, jadi arena tetap bersih.

## Empat perintah

| Tombol | Yang terjadi |
| --- | --- |
| **Attack** | Pukulan biasa. Memakai stat Attack. Power 50. Defense lawan penuh. |
| **Special** | Jurus lebih berat. Memakai stat Special. Power 75. Defense lawan dihitung setengah. Memakan 1 PP. |
| **Guard** | Bertahan (damage masuk dikurangi). Mengembalikan 1 PP. |
| **Item** | Satu item dari tas, mengganti aksi turn itu. Hanya sekali per duel. |

Item Battle dibeli di Shop. Picker hanya menampilkan tujuh item tempur (bukan makanan atau Energy). Di **Bag** item itu kelihatan tapi tanpa tombol Use. Saat dipakai, label besar di arena menulis efeknya (misalnya **Attack +35%!**), dan Anima berkilat. Sesudah terpakai, tombol **Item** meredup sampai duel selesai.

| Item | Efek singkat |
| --- | --- |
| Vital Patch | Pulihkan HP |
| Power Chip | Attack lebih keras turn berikutnya |
| Surge Lens | Special lebih keras |
| Aegis Plate | Damage masuk berkurang |
| Tempo Coil | Speed naik — bisa gerak lebih dulu |
| PP Capsule | PP dan batas PP naik untuk duel ini |
| Phase Shield | Pukulan berikutnya hampir terhapus |

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

**Attack** memakai elemen utama. **Special** memakai elemen kedua, atau elemen
utama kalau Anima hanya punya satu. Serangan kuat bernilai ×1.5 dan serangan
yang ditahan bernilai ×0.67.

- Metal → Plant, Wood
- Wood → Spark, Sound
- Stone → Metal, Ceramic
- Ceramic → Toxin, Flame
- Glass → Toxin, Air
- Plastic → Flow, Glass
- Cloth → Stone, Sound
- Paper → Food, Stone
- Plant → Flow, Air
- Food → Fauna, Frost
- Fauna → Plant, Cloth
- Flow → Spark, Paper
- Spark → Cloth, Metal
- Flame → Wood, Frost
- Frost → Fauna, Plastic
- Air → Flame, Paper
- Toxin → Food, Plastic
- Sound → Glass, Ceramic

Kalau lawan punya dua elemen, satu weakness dan satu resistance saling
membatalkan menjadi normal. Dua weakness tidak ditumpuk lebih tinggi dari ×1.5,
dan dua resistance tidak ditumpuk lebih rendah dari ×0.67.

Saat kena, layar bisa menulis **Super effective!** atau **Not very effective.**
