# Battle

Duel singkat lawan Anima yang sudah dipublikasikan pemain lain (tanpa identitas
pemilik) atau lawan sistem. Kamu mengirim perintah; server yang menghitung
hasilnya.

Arena tidak menunggu jaringan sebelum bergerak. Begitu kamu menekan sebuah
aksi, turn-nya langsung dimainkan memakai aturan yang sama persis dengan yang
dipakai server, dan hasil resmi menyusul di belakang layar. HP, PP, hadiah, dan
Bits yang tersimpan selalu versi server. Kalau keduanya sampai berbeda — jarang,
tetapi mungkin setelah koneksi bermasalah — arena memutar ulang hasil resminya.
Pergantian Anima (Switch) ikut langsung dimainkan, termasuk penggantian paksa
sesudah KO. Yang masih menunggu jawaban server hanya saat Boss menurunkan Anima
terakhirnya dan item di Expedition.

Sinyal yang putus sebentar — lift, terowongan, kereta — tidak membuang aksimu.
Turn yang gagal terkirim dicoba ulang sendiri beberapa detik sebelum menyerah,
jadi biasanya pertarungan lanjut tanpa kamu menyadari apa pun. Kalau koneksinya
benar-benar hilang, arena mundur ke keadaan terakhir yang sudah disahkan server
dan kamu bisa mengulang aksi yang sama.

## Mode yang tersedia

Layar Battle menampilkan **Duel**, **Team Battle**, dan **Expedition** sejak
tab dibuka. Tombol mode langsung bisa ditekan; hanya dimatikan kalau server
memang menutup mode itu.

Menutup app saat fight atau Expedition masih berjalan tidak membuang progress.
Saat app dibuka lagi, kamu tetap masuk ke **Home**. Buka tab **Battle**, lalu
pilih **Continue Battle**, **Continue Team Battle**, atau **Continue Expedition**
untuk melanjutkan mode yang tersimpan. Mode Battle lain diredupkan sampai mode
itu selesai atau kamu Retreat. Turn yang sempat terkirim dipulihkan dengan aman
dan biaya Energy tidak dipotong lagi. Duel yang dibiarkan lebih dari 30 menit
tetap dapat kedaluwarsa.

## Team Battle

Pilih tepat **4 Anima** untuk melawan tim lain berisi 1–4 Anima. Arena tetap
menampilkan satu fighter aktif dari setiap tim.

- Pemilih tim menampilkan pose kebutuhan Anima saat ini. Teks **Ready**, **Low
  Energy**, **Dormant**, atau **Not ready** tetap terlihat agar kesiapan tidak
  bergantung pada warna saja. Ketuk card untuk menambah atau melepasnya; card
  yang masuk tim diberi checklist di kanan atas.
- Setelah tim disimpan, lobby menawarkan sampai **tiga rival** dengan tier dan
  Bits-nya masing-masing. **Find New Rivals** mengocok ulang pilihannya. Selama
  belum banyak pemain memasang Defense Team, sebagian rival adalah tim sistem.
- Memulai battle memakai **10 Energy dari setiap anggota**.
- Attack, Special, Guard, dan Item bekerja seperti Duel. **Super effective!**
  dan **Not very effective.** tampil besar di arena, tepat di bawah HUD. Pelat
  nama serangan tampil lebih dulu sekitar 1,4 detik lalu hilang. Sesudah itu
  pose Attack dan VFX dimainkan; saat VFX mengenai lawan, penyerang langsung
  kembali Idle sebelum teks efektivitas berikutnya.
- Saat battle berjalan, layar jadi arena penuh: judul Scanima, menu, chip
  Animas/Cores/Bits, dan navigasi bawah hilang. Satu-satunya jalan keluar
  adalah **Retreat** di paling kanan baris bawah. Tombol aksi dua baris
  seimbang: **Attack** / **Special** / **Guard**, lalu **Item** / **Switch** /
  **Retreat**. HUD menaruh pip tim di atas nama Anima, lalu HP. Di Expedition,
  label `{judul chapter} — Zone {n}` duduk di atas pelat HP; Final Battle
  menulis `{nama Seeker} · Final Battle`. Bar HP berwarna biru di atas 50%,
  langsung berubah oranye pada 50% ke bawah, lalu merah pada 20% ke bawah.
  Angka HP tetap terlihat. Saat berpijak, kaki Anima dan Boss Seeker bertemu
  tepat di tengah bayangan lembut agar karakter tidak terlihat melayang.
- **Switch** sukarela memakai satu turn. Tombol aksi tetap di tempatnya
  supaya arena tidak bergeser. Picker naik sebagai lembar dari bawah layar
  dan menampilkan art, nama plus
  Level, status **In battle** / **Ready** / **KO**, dan sisa HP tiap anggota.
  **Cancel** menutup picker dan mengembalikan tombol aksi. Setelah Anima KO, pose Defeated tampil
  sebentar, lalu picker pengganti terbuka tanpa memakai turn berikutnya — di
  situ Cancel tidak ada karena pengganti wajib. Kalau hanya satu Anima yang
  masih hidup, ia langsung masuk arena tanpa picker. Anima yang masuk memakai
  animasi Summon yang sama seperti di Home. HUD menampilkan nama plus Level,
  misalnya **Soundhund Lv. 5**.
- Ketuk Attack, Special, Guard, Item, atau Switch langsung mengunci tombol
  itu (garis di bawahnya). Tidak ada teks “locked in” atau “Resolving”.
  Turn-nya juga langsung dimainkan tanpa menunggu jaringan: pelat gelap menulis
  **{nama} uses {move}.**, **{nama} braces for impact.**, item, Switch, atau
  KO dan diam sekitar 1,4 detik. Untuk serangan, pelat itu hilang sebelum pose
  Attack dan VFX dimulai. Penyerang kembali Idle tepat saat VFX mengenai
  target, baru **Super effective!** atau **Not very effective.** tampil pada
  pelat yang sama. Angka damage muncul di atas Anima yang kena, sama seperti
  Duel.
- Satu item Battle berlaku untuk seluruh encounter, bukan satu per anggota.
  **Item** membuka Bag; tombol **Shop** tidak muncul di tengah battle.
- Dua kemenangan progression pertama per hari memberi EXP yang mengikuti
  rata-rata Level roster lawan dan tier rival. Lawan yang lebih tinggi memberi
  bonus underdog. Setiap anggota memakai Level-nya saat battle dimulai:
  anggota yang pernah aktif dan masih hidup menerima setengah hadiah penuh
  (dibulatkan ke atas), bench hidup menerima seperempat (dibulatkan ke atas),
  dan anggota KO mendapat 0. Kartu hasil menyebut nama dan jumlah aktual setiap
  Anima, termasuk sesudah battle dipulihkan dari restart.
- Bits dibayar sampai total **40 per hari** dari Team Battle. Cap ini terpisah
  dari Duel.
- Kalah, draw, atau Retreat tidak memberi hadiah.

**Defense Team** bersifat opt-in. Saat diaktifkan, snapshot timmu dapat menjadi
lawan anonim untuk pemain lain; identitas Seeker dan nickname privat tidak ikut
ditampilkan.

## Expedition

**The Sugarworks** adalah chapter Expedition pertama. Pilih tepat **4 Anima**,
lalu tempuh tiga zona yang masing-masing berisi empat node pilihan. Jalur dapat
berisi Battle, Elite, Recovery, Cache, Shop, atau Mystery sebelum melawan Boss
Seeker.

- Pemilih tim memakai art dan status kesiapan yang sama dengan Team Battle.
- Peta zona berupa jalur bercabang. Ikon menunjukkan jenis node: pedang untuk
  Battle, pedang berkilau untuk Elite, peti untuk Cache, hati untuk Recovery,
  tanda tanya untuk Mystery, dan pedang bersilang untuk Boss. Ketuk node yang
  bisa dijangkau untuk melihat pratinjau jalurnya; perjalanan baru dikunci
  setelah menekan **Enter Node**. Node terang bisa dipilih. Jalur yang sudah
  dilewati dan yang belum terbuka sama-sama meredup; hanya pratinjau ke depan
  yang disorot, tanpa label status tambahan.
- Rincian HP empat anggota tidak memenuhi peta saat semuanya sehat. Ringkasan
  **Team HP** baru muncul ketika ada anggota yang terluka; pilihan pemulihan
  tetap menampilkan target dan HP lengkap saat dibutuhkan.
- **Begin Expedition** membutuhkan **30 Energy dari setiap anggota** dan
  memotongnya satu kali saat run dibuat. Setelah itu **Start Zone** untuk zona
  1–3 dan Boss tidak memerlukan atau memotong Energy lagi, termasuk ketika
  Energy anggota sudah 0. Retry dan melanjutkan run juga tidak membayar ulang.
- Encounter Expedition memakai arena penuh yang sama: art zona mengisi layar,
  Anima berpijak dengan bayangan, dan **Retreat** di paling kanan baris
  bawah adalah satu-satunya cara keluar. Navigasi tab dan chip resource tidak
  tampil selama fight.
- HP penuh saat Zona 1 dimulai. Sesudah Zona 1 dan 2, pilih satu manfaat sebelum
  **Start Zone**: **Recover** memulihkan 50% max HP semua anggota dan
  membangunkan Anima KO dengan 50% HP; **Power Up** mempertahankan HP lalu
  menaikkan Attack, Guard, dan Speed 10% selama zona berikutnya saja.
- Kamu bisa mengganti Anima aktif saat battle. HP bertahan antar-node dan
  melewati checkpoint sesuai pilihanmu, sedangkan PP kembali penuh pada
  encounter berikutnya.
- Sesudah menang Battle, Elite, atau Boss, layar hasil menampilkan Tokens,
  EXP tiap anggota, dan siapa yang naik Level. Stats dari Level baru dipakai
  di fight berikutnya di zona yang sama. Jika beberapa Anima naik Level,
  setelah ringkasan hadiah kamu melihat banner dan perbandingan stat
  **lama → baru** untuk satu Anima terlebih dahulu. Ketuk **Continue** untuk
  melihat Anima berikutnya; **Return to Map** baru aktif setelah semuanya selesai.
- Anima special milik Boss Seeker tidak pernah muncul di node Battle atau Elite.
  Jika roster node memakai tim Boss, slot special diganti Anima reguler dari
  zona itu. Special baru dapat masuk sebagai Anima terakhir di Final Battle.
- **Tokens** adalah mata uang run, bukan Bits. Dipakai di **Trail Shop**. Saldo
  **You have 6 Tokens to spend** hanya tampil saat ada yang bisa dibeli.
  Tekan **Skip Shop** untuk melanjutkan tanpa membeli jika tidak menginginkan
  offer yang tersedia; HP, Tokens, dan boost tidak berubah.
  Cache, Mystery, dan Recovery yang cuma satu hadiah gratis menampilkan
  efeknya — misalnya **Raise Attack · +12%** atau **Collect 3 Tokens** — lalu
  **Continue** kembali ke peta. Tokens hilang saat run selesai.
- Empat anggota terkunci selama run. Tim baru bisa diedit setelah chapter
  selesai atau **Abandon**.
- **Abandon** selalu meminta konfirmasi. Ini mengakhiri run permanen: progress
  zona aktif, Tokens, dan boost tidak dapat dipakai lagi, serta Energy masuk
  tidak kembali. Reward yang sudah diterima tetap aman. Run baru membuat route
  baru.
- Run bisa ditutup dan dilanjutkan lagi; progress zona yang selesai tidak hilang.
- Jika seluruh tim KO, atau kamu **Retreat** dari fight, attempt zona itu
  dimulai ulang dari awal. Zona sebelumnya tetap selesai.
- Expedition memiliki budget **30 total EXP roster per hari**. Selama masih ada
  sisa budget, satu encounter dibayar penuh; sesudah budget terlewati,
  encounter berikutnya memberi 0 EXP. Pembagiannya mengikuti rata-rata Level
  roster lawan: anggota yang pernah aktif mendapat setengah, bench hidup
  seperempat (keduanya dibulatkan ke atas), dan KO mendapat 0. **Boss selalu
  memberi payout party normal sekali per run** meski budget hari itu habis;
  ini bukan bonus kedua. Tokens tetap dapat diperoleh.
- Menyelesaikan zona The Sugarworks memberi Bits permanen: **10** dari Zone 1,
  **20** dari Zone 2, dan **30** dari Zone 3. Totalnya dibatasi **60 Bits per
  chapter per hari** untuk seluruh run akun itu dan reset tengah malam waktu
  setempat. Chapter berikutnya dapat memakai jadwal berbeda.
- First clear Boss memberi bonus **25 Bits** di luar cap harian itu, serta
  **Sugarfold Core** untuk koleksi Trophy Seeker. Begitu baris terakhir The
  Confectioner ditutup, gambar Core-nya muncul beserta pengumuman bahwa Core itu
  sudah menjadi milikmu; **tap to continue** membawamu ke ringkasan hadiah.
  Core-nya tersimpan permanen di **Trophy Showcase** pada profil Seeker, yang
  memajang semua Core yang pernah kamu menangkan. Tidak ada yang perlu diatur
  atau disimpan di sana — buka profilnya dan Core-nya sudah ada.
- Boss menampilkan **The Confectioner** dulu, tanpa Anima lawan. Ia berbicara
  tanpa overlay gelap. **Tap to continue** menutup baris itu, lalu The
  Confectioner memanggil Anima-nya ke arena dan fight baru dimulai. Selama
  fight ia berdiri di belakang Anima lawan, paling banyak bicara sekali lagi
  saat perintah, ketika ace terakhirnya masuk, lalu saat menang atau kalah.
- Cotton adalah ace The Confectioner dan selalu disimpan sampai semua Anima
  regulernya KO. Saat Cotton masuk, **Final Confection** aktif sekali dan
  memberinya +1 PP untuk encounter itu.
- The Confectioner tetap berpijak di tempat yang sama ketika mengganti pose.
  Ia tidak memakai pose terkena damage saat Anima-nya Guard, dan baru bereaksi
  tepat ketika serangan benar-benar mengenai Anima. Setelah beat damage selesai,
  ia langsung kembali normal sebelum teks **Super effective!** atau
  **Not very effective.** muncul.
- Ukuran Anima dan The Confectioner di arena mengikuti tinggi tubuh mereka.
  Anima setinggi manusia mengisi kurang dari setengah arena pada layar HP,
  supaya dua petarung plus trainer masih punya ruang. Anima
  berbadan kecil (sekitar boneka yang bisa digendong) tetap lebih pendek dari
  companion biasa. Anima yang sangat lebar membuat kamera menjauh untuk
  memuat seluruh petarung, termasuk The Confectioner.
  Anima yang jauh lebih tinggi dari 3 meter tetap dihitung setinggi
  sekitar 3 meter — hampir dua kali The Confectioner. Kamera lalu
  menyesuaikan jarak agar kedua Anima dan The Confectioner terlihat utuh:
  petarung kecil membuat kamera mendekat, sedangkan petarung besar membuat
  kamera menjauh dan memperlihatkan lebih banyak latar. Setiap encounter bisa
  mengambil potongan kiri, tengah, atau kanan yang berbeda dari lokasi yang
  sama; framing itu tidak bergeser lagi selama pertarungan berlangsung. Latar
  jauh diberi blur halus sementara lantai dekat petarung tetap lebih jelas,
  supaya Anima dan Seeker mudah dibaca. The Confectioner tetap berada dekat
  sisi kanan, di belakang posisi Anima lawan.
  Kalau Anima itu lebih tinggi dari sekitar
  60% tinggi The Confectioner, ia berdiri di belakang The Confectioner.
  The Confectioner juga punya bayangan di kaki. Margin arena mengikuti tepi tubuh yang terlihat,
  bukan ruang transparan di dalam sprite. Monster besar tetap terasa besar,
  tetapi semuanya dijaga agar tidak menutup HUD. The Confectioner tampil full
  body.

Chapter baru menampilkan popup sekali di Home dan badge **New** sampai chapter
dibuka. Push perangkat bersifat opsional; popup dan badge di dalam game tetap
menjadi pemberitahuan utama.

## Syarat masuk Duel

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
- EXP yang mengikuti Level lawan, selisih Level, dan tier Tough/Formidable
- +1 kemenangan progression pada Anima

Lawan Level tinggi memberi lebih banyak EXP, terutama jika Level Anima-mu lebih
rendah. Nilainya dikunci dari snapshot awal duel, jadi kenaikan Level di hasil
tidak mengubah reward yang baru saja diperoleh. Kartu hasil menyebut nama dan
jumlah EXP aktual. Training tidak
menampilkan klaim EXP karena memang tidak memberikannya.

Di Duel, lawan dan tingkat kesulitannya dipilih server; tidak ada pengaturan
tier manual. Arena hanya menampilkan nama, Level, HP, dan perintah yang berguna
untuk turn saat ini. Hadiah Bits yang benar-benar didapat baru ditulis di kartu
hasil. Saat jatah tiga kemenangan berhadiah habis, lobby mengubah tombol menjadi
**Train** dan menjelaskan apakah Bits harian masih tersedia.

Sesudah 3/3, tombol yang sama jadi **Train**. Duelnya sama; EXP dan kemenangan
progression Anima berhenti, tetapi **Bits masih dibayar** sampai cap **100 Bits
per hari**. Sesudah 100/100, Training nol hadiah. Core tidak pernah didapat dari
sini.

Stat **Enemies Defeated** di [Seeker Profile](seeker.md) menghitung semua duel
menang, termasuk Train. Jatah tiga kemenangan pertama hanya menentukan hadiah
EXP dan progression harian.

Kalah atau **Retreat** juga nol hadiah. **Retreat** membuka konfirmasi dulu;
Cancel kembali ke arena. Di Expedition, konfirmasi itu menjelaskan bahwa zona
saat ini dimulai ulang dari awal. Sesudah kamu konfirmasi, arena menampilkan
**Retreating** di pelat event yang sama dengan Super effective sampai fight
berakhir. Di Duel, **Retreat** rata kanan di baris atas arena (tanpa nomor
Turn). Di Team Battle dan Expedition, **Retreat** ada di paling kanan baris
Item / Switch. Shop dan Bag hanya ada di Home, jadi arena tetap bersih. Beli item di
**Shop** sebelum memulai Duel, Team Battle, atau Expedition — tombol Shop
redup selama battle atau run masih berjalan.

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

Siapa yang gerak dulu mengikuti **Speed**. Pelat menulis **{nama} moves first.**
sebelum animasi, jadi giliran bot duluan bukan bug.

## PP

PP adalah budget **satu duel**, mulai dari **3**.

- Special −1
- Guard +1
- Tidak pulih tiap giliran
- Habis di akhir duel — duel berikutnya mulai 3 lagi

Kalau PP habis, tombol Special mati. Satu-satunya jalan Special lagi adalah Guard dulu.

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
Nama jurus netral, Guard, item, Switch, dan KO memakai pelat yang sama di
arena: **{nama} uses {move}.**, **{nama} braces for impact.**, **{nama} uses
an item.**, **{nama} enters the arena.**, **{nama} is knocked out.** Setiap
label diam sekitar 1,4 detik sebelum aksi atau pelat hilang.
