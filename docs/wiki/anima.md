# Anima: traits, attributes, EXP

Setiap Anima lahir dari foto satu benda atau hewan non-manusia. Bentuk, jurus,
dan stats-nya mengikuti subjek itu, lalu tumbuh pelan lewat Level. Art setiap
Anima unik dan privat kecuali kamu memilih **Publish Lineage to Atlas**.

Setiap Anima juga lahir dengan ukuran tubuh khas. Ukurannya berangkat dari
subjek asli. Benda genggam kecil (konsol, remote, mainan) menjadi Anima
**berbadan kecil** — kira-kira sebesar boneka yang masih bisa dipeluk dan
digendong, bukan setinggi anak. Hewan mengikuti tinggi aslinya. Benda yang
memang besar, atau monster yang siluetnya menjulang, boleh jauh lebih tinggi.
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
| **Level / form** | Hatchling (Lv. 1–15), Adult (16–35), Evolved (36–40). Naik Level tidak mengganti wajah sendiri — tap **Evolve** di profil atau Collection saat siap. |
| **EXP** | Poin perawatan dan kemenangan. Level awal naik cepat; Level tinggi butuh lebih banyak EXP. |
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

Naik Level membuat kelima angka itu tumbuh kira-kira **2% per level**. Lonjakan Adult dan Evolved datang sesudah ritual **Evolve**, bukan otomatis di angka Level itu.

Setiap kali Anima naik Level, satu dialog muncul: judul **{nama} Level Up**, lalu Level barunya sebagai angka besar (**Lv. 4**), lalu kelima stat dengan nilai **lama → baru**.

## EXP dan Level

Biaya naik Level bertambah setiap lima Level:

| Level saat ini | EXP ke Level berikutnya |
| --- | --- |
| 1–5 | 5 |
| 6–10 | 10 |
| 11–15 | 15 |
| 16–20 | 20 |
| 21–25 | 25 |
| 26–30 | 30 |
| 31–35 | 35 |
| 36–39 | 40 |

Adult dimulai pada **150 total EXP**, Evolved pada **700**, dan Level 40
tercapai pada **860**. Di Level 40, meter menampilkan **MAX**.

Saat Level cukup, Collection menandai kartu **Ready to Evolve** dan profil
menampilkan tombol **Evolve**. Konfirmasi **Begin Evolution** memasukkan Anima
ke chamber. Ritual ini **gratis** — tidak memakai Core — dan Anima tidak bisa
Battle atau dirawat sampai selesai. Kalau gagal, bentuk lama tetap dipakai.

Sesudah sukses, art-nya berganti, nama Attack/Special bisa berubah, dan jurus
bisa mendapat efek tambahan di Battle. Game juga mengusulkan **nama baru**
untuk form itu, lalu membuka **Rename** seperti sesudah Scan. **Save Name**
memakai usulan itu atau suntinganmu. **Cancel** mempertahankan nama lama.
Usulan itu mempertahankan awal nama asli Anima dan hanya mengganti akhirannya,
jadi satu garis terbaca sebagai satu keluarga — Vitrore menjadi Vitrforge lalu
Vitrsovran. Kalau kamu sudah memberi nickname sendiri, usulannya tetap mengikuti
nama aslinya, dan **Cancel** menjaga nickname-mu.
Hatchling menjadi Adult di Level 16;
Adult menjadi Evolved di Level 36. Satu ritual per tahap, berurutan.
Setiap form yang selesai menjadi entry terpisah di [Anima Atlas](atlas.md).

| Aksi | EXP | Catatan |
| --- | --- | --- |
| Feed yang menyeberangkan Hunger ke 40 | +3 | Camilan yang masih di bawah 40 = 0 |
| Clean saat kotor (Hygiene di bawah 50) | +3 | Bersih = 0 |
| Sleep penuh (companion di Home) | +5 | Maks sekali per Anima per hari; bangun lebih awal = 0 |
| Play | +1 | Maks 5 kali per hari, reset tengah malam waktu setempat |
| Menang Duel berhadiah | Mengikuti Level lawan | Lawan lebih tinggi dan tier Tough/Formidable memberi lebih banyak; Training = 0 |
| Menang Team Battle berhadiah | Bagian dari hadiah lawan | Pernah aktif mendapat sekitar separuh; bench hidup sekitar seperempat; KO = 0 |
| Menang encounter Expedition | Bagian dari hadiah lawan | Budget tim 30 EXP per hari; Boss tetap membayar sekali per run; KO = 0 |
| Bonus terawat (ketiga kebutuhan &gt; 70) | +8 | Hanya companion di Home, sekali per hari, reset tengah malam waktu setempat |

Dormant **tidak** menghapus EXP.

## Collection dan Summon

Tap kartu membuka sheet, bukan langsung pindah companion.

- **View Profile** — lihat traits dan attributes, ganti nama, Evolve, atur
  publikasi lineage, atau Delete.
- **Summon** — Anima ini pindah ke Home. Yang tadi di Home tidur. Portalnya mulai
  begitu kamu menekan, bukan sesudah menunggu; kalau pergantiannya gagal, portal
  menutup dan companion lamamu kembali.

Hanya satu companion aktif. Anima di bangku tidur supaya Energy pulih (penuh ~3 jam) dan tidak capek sendiri. Hunger dan Hygiene di Collection turun pelan dan berhenti sebelum lapar atau kotor, jadi merawat tim tidak berarti memberi makan semua orang setiap hari. Yang sudah lapar, kotor, atau Dormant sebelum istirahat tetap begitu sampai di-Summon lalu diurus di Home. Kartu Collection memakai pose-nya: Sleep selama Energy pulih, Idle kalau siap, Damaged kalau Dormant, dan **Ready to Evolve** kalau Level sudah cukup untuk Adult atau Evolved. Setiap kartu juga menandai Level-nya (**Lv. 12**) di pojok kiri atas. Tidak perlu tap dulu supaya kelihatan.

**Delete** ada di profil sebagai teks kecil, bukan tombol besar. Menghapus itu
permanen: tidak ada refund Core atau Bits. Ini hanya menghapus satu Anima.
**Delete Account** di menu [Seeker](seeker.md) menghapus seluruh akun.

Profil Anima tidak lagi menjadi tab bottom navigation. Buka dari Collection atau
picker Anima di Battle.

Rename Anima tidak memiliki cooldown Seeker. **Change Seeker Name** adalah aksi
terpisah dan hanya tersedia sekali setiap 30 hari.

## Nama Anima

Nama yang kamu tulis sendiri boleh memakai huruf, angka, spasi, apostrof, dan
tanda hubung, sampai 32 karakter, dan harus memuat setidaknya satu huruf. Spasi
di awal dan akhir dibuang. Kata kasar dan nama yang menyamar sebagai staf
(Admin, Moderator, Support, Scanima) ditolak dengan pesan di layar; namanya tidak
tersimpan dan sheet-nya tetap terbuka supaya kamu bisa mencoba lagi.

Nama hasil Scan dan Evolve berusaha menghindari nama yang sudah ada di
koleksimu, jadi dua Anima serupa tidak lahir kembar. Kalau pilihannya benar-benar
habis, nama kembar tetap diberikan — kamu bisa mengganti salah satunya.

Nickname buatanmu hanya terlihat olehmu. Lawan Battle, Defense Team, dan
[Anima Atlas](atlas.md) memakai nama spesies hasil Scan, bukan nickname.
