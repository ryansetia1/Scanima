# Battle

Duel singkat lawan Anima yang sudah dipublikasikan pemain lain (tanpa identitas
pemilik) atau lawan sistem, dipilih supaya duelnya seimbang — lihat
[Siapa lawanmu di Duel](#siapa-lawanmu-di-duel). Kamu mengirim perintah; server
yang menghitung hasilnya.

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

Saat serangan mengenai target, petarung dan arena berguncang singkat; latar
bergerak lebih lembut supaya benturannya terasa tanpa menggoyangkan HUD atau
tombol. Serangan yang ditahan terasa paling ringan, serangan kuat atau Critical
lebih tegas, dan pukulan yang membuat KO paling berat. Haptics berlaku saat
kamu memukul maupun dipukul. **Critical hit!** selalu disebut jelas dan dapat
disusul **Super effective!** atau **Not very effective.** pada baris kedua.
Damage dari status yang membuat KO juga mendapat satu benturan; pelat KO yang
muncul sesudahnya tidak mengguncang atau bergetar lagi.

**Battle Shake** dan **Haptics** dapat dimatikan secara terpisah lewat
**Settings**. Mematikan Battle Shake tidak menghapus reaksi target, kilatan,
angka damage, teks, atau suara serangan. Jika hasil resmi server harus
memperbaiki animasi prediksi, koreksi visualnya tidak mengulang guncangan atau
Haptics yang sudah kamu rasakan.

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
Kalau app ditutup sesudah Anima aktif KO, **Continue Team Battle** kembali ke
pilihan pengganti yang wajib diselesaikan. Pilih Anima yang masih hidup untuk
melanjutkan; aksi sebelum KO tidak diputar ulang dan pilihan ini tidak memakai turn.

## Team Battle

Team Battle selalu membuka pemilih tim lebih dulu. Pilih dan konfirmasi **2–4
Anima**, baru lanjut ke **Find Rivals**. Setiap rival selalu membawa jumlah
Anima yang sama dengan timmu: 2 lawan 2, 3 lawan 3, atau 4 lawan 4. Arena tetap
menampilkan satu fighter aktif dari setiap tim.

- Pemilih tim menampilkan pose, Level, dan kebutuhan Anima saat ini. Teks
  **Ready**, **Low Energy**, **Dormant**, atau **Not ready** tetap terlihat agar
  kesiapan tidak bergantung pada warna saja. Ketuk card untuk menambah atau
  melepasnya. Card terpilih diberi nomor sesuai urutan pilihan: **1** adalah Anima yang memulai
  battle, lalu **2–4** adalah urutan bench. Melepas satu card menomori ulang
  sisanya tanpa mengubah urutan mereka, dan card yang dipilih lagi masuk di
  nomor terakhir. Urutan itu tetap sama saat builder dibuka lagi. **Back** dan
  **Save Team** berbagi lebar baris yang sama. Back membatalkan perubahan yang
  belum disimpan dan kembali ke lobby rival; membuka builder lagi memulihkan
  urutan tim tersimpan.
- Setelah tim disimpan, lobby menawarkan sampai **tiga rival** dengan tier dan
  Bits-nya masing-masing. **Find New Rivals** mengocok ulang pilihannya. Rival
  pemain dirakit dari Anima yang sudah **Publish to Atlas** dan dapat
  mencampurkan Anima dari beberapa Seeker tanpa menampilkan identitas pemilik.
  Kalau publication yang cocok belum cukup, rival berasal dari tim sistem.
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
  **Cancel** menutup picker dan mengembalikan tombol aksi. Begitu pelat
  **{nama} is knocked out.** muncul, Anima itu sudah pose Defeated. Sesudah
  itu picker pengganti terbuka tanpa memakai turn berikutnya — di
  situ Cancel tidak ada karena pengganti wajib. Kalau hanya satu Anima yang
  masih hidup, ia langsung masuk arena tanpa picker. Anima yang masuk memakai
  animasi Summon yang sama seperti di Home. HUD menampilkan nama plus Level,
  misalnya **Soundhund Lv. 5**.
- Ketuk Attack, Special, Guard, Item, atau Switch langsung mengunci tombol
  itu (garis di bawahnya). Tidak ada teks “locked in” atau “Resolving”.
  Turn-nya juga langsung dimainkan tanpa menunggu jaringan: pelat gelap menulis
  **{nama} moves first.** sebelum Attack pertama (siapa yang lebih cepat), lalu
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

Tidak ada langkah **Publish Defense** terpisah. Memilih **Publish to Atlas**
adalah izin yang dipakai sistem untuk memasukkan Anima itu ke rival Team Battle
baru. Unpublish menariknya dari pilihan rival berikutnya; nickname privat,
identitas Seeker, dan session yang sudah berjalan tidak ikut berubah.

## Kamu di arena

Di **Duel**, **Team Battle**, serta node Battle/Elite **Expedition**, latar dan
dunia pertarungan memenuhi seluruh layar, termasuk area di belakang status
fighter dan tombol aksi. Munculnya tombol, **Switch**, picker **Item**,
konfirmasi **Retreat**, atau kartu hasil tidak mengecilkan arena maupun
menggeser petarung. Opening memakai pandangan lebar tanpa interface. Di
**Duel** dan **Team Battle**, Seeker-mu masuk ketika Anima lawan sudah menunggu,
lalu memanggil Anima aktifmu. Di node Battle/Elite **Expedition**, Anima lawan
masih dipanggil lebih dulu sebelum Anima-mu. Setelah fighter siap, dunia
bergeser halus ke pandangan bermain selama 0,32 detik sambil status dan tombol
muncul. Perintah baru dapat ditekan setelah perpindahan itu selesai. Dalam
pandangan bermain, kamera menjaga kaki, badan utama, dan bayangan kontak fighter
tetap terlihat di atas panel status dan tombol aksi, termasuk untuk Anima yang
sangat tinggi.

Di **Duel**, **Team Battle**, dan **Expedition** kamu ikut berdiri di sana. Figur
Seeker-mu — yang kamu pilih lewat **Change Seeker Avatar** di
[Seeker Profile](seeker.md#seeker-avatar) — berdiri di sisimu menghadap lawan,
sejauh Boss Seeker berdiri dari tepi seberang, dengan bayangan di kaki dan tidak
pernah menutupi tombol aksi. Kamera menyisakan satu kolom untuk figur di sisi
yang punya figur, jadi badannya dan badan Anima punya jarak alih-alih tumpang
tindih. Di layar lebar, figur tetap berdiri di samping Anima miliknya alih-alih
tertinggal sendirian di ujung layar; tepi layar hanya menjadi batas agar badannya
tidak terpotong. Setiap pilihan figur punya proporsi tinggi sendiri. Di Final
Battle, perbedaan tinggi itu dipertahankan saat ia berdiri berhadapan dengan
Boss Seeker; sifatnya tetap kosmetik dan tidak mengubah Battle.

Saat menunggu perintah, figur organik bernapas dan sesekali memindahkan berat
badan dengan halus. Automaton memakai gerak mekanis kecil sebagai gantinya.
Boss Seeker organik ikut bernapas saat Idle. Gerak tenang ini berhenti ketika
pose perintah, reaksi, menang, atau kalah sedang tampil.
Di **Team Battle**, latar ikut bergerak lebih lembut saat **Switch** ke Anima
yang jauh berbeda tinggi atau lebar mengubah jarak kamera, jadi perubahan ukuran
Anima terbaca sebagai gerak kamera dan bukan figur yang berubah sendiri. Seeker
dan Anima ikut mendekat atau menjauh bersama, jadi perbandingan tinggi mereka
tetap sama sepanjang gerakan itu. Serangan dan perubahan HP biasa tidak
menghitung ulang framing, jadi latar tidak meloncat saat Anima kena.

Setiap fight baru di **Duel**, **Team Battle**, dan node Battle/Elite
**Expedition** dibuka berurutan: Seeker-mu berdiri sendiri, Anima lawan keluar
dari portal, Seeker-mu memberi perintah, lalu Anima aktifmu dipanggil dari
portal. Nama, HP, turn, dan tombol aksi baru muncul setelah kedua Anima siap;
selama itu arena belum bisa disentuh. Intro ini tidak diputar ulang saat
melanjutkan fight yang tersimpan atau mencoba ulang koneksi. Di battle bertim,
hanya Anima pertama yang dipanggil lewat intro; anggota cadangan masuk lewat
animasi **Switch** biasa. Final Battle Expedition menjadi pengecualian: kamu
dan Boss Seeker terlihat lebih dulu tanpa Anima, lalu Boss memanggil Anima-nya
sebelum Seeker-mu memanggil Anima aktifmu. **Try Again** mengulang pembuka itu,
sedangkan **Continue Expedition** tidak.

Anima yang tingginya sudah melewati kira-kira pinggang figur digambar di
belakangnya: pada ukuran itu figur yang berdiri di belakang kehilangan
siluetnya. Anima yang lebih kecil dari itu tetap berdiri di depan figur. Aturan
yang sama sudah berlaku untuk Boss Seeker di sisi seberang.

Ia bergerak mengikuti giliranmu: pose perintah saat kamu Attack atau Special
(juga Switch, di mode yang punya Switch), pose khawatir saat Anima-mu terkena,
lalu pose menang atau kalah di penutup, dan kembali tenang di antaranya. Guard
dan Item tidak punya pose sendiri. Ia tidak pernah bicara — panel dialog hanya
milik Boss Seeker. Belum pernah memilih figur berarti yang berdiri di sana adalah
figur default. Lawan Duel tidak punya figur Seeker; sisi seberang hanya berisi
Anima-nya.

## Expedition

**The Sugarworks** adalah chapter Expedition pertama. Berbeda dari Team Battle,
Expedition tetap mewajibkan tepat **4 Anima**, lalu tempuh tiga zona yang
masing-masing berisi empat node pilihan. Jalur dapat berisi Battle, Elite,
Recovery, Cache, Shop, atau Mystery sebelum melawan Boss
Seeker.

- Pemilih tim memakai art, Level, dan status kesiapan yang sama dengan Team
  Battle.
- Saat peta Zone 1 pertama kali terbuka untuk run baru, Boss Seeker menyambutmu
  sebelum node dipilih. Sambutan muncul sekali untuk run itu; memulai run baru
  setelah clear dan menerima Trophy akan memunculkannya lagi. Selama sambutan,
  **Enter Node** dan **Abandon** diganti satu tombol **Tap to Continue**. Ketuk
  tombol itu setelah selesai membaca; ketukan pada panel atau area lain tidak
  menutup sambutan.
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
  setelah ringkasan hadiah kamu melihat satu dialog per Anima: judul
  **{nama} Level Up**, Level barunya sebagai angka besar, lalu perbandingan
  stat **lama → baru**. Ketuk **Continue** untuk melihat Anima berikutnya;
  **Return to Map** baru aktif setelah semuanya selesai.
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
- Final Battle dibuka sebagai konfrontasi dua Seeker: kamu dan **The
  Confectioner** sudah berdiri di arena, sementara kedua Anima masih
  tersembunyi. Setelah jeda singkat, Boss bicara tanpa overlay gelap. Panelnya
  muncul di tempat pelat event arena; status HP, tombol Battle, dan picker
  **Switch** disembunyikan sementara supaya hanya dialog dan satu tombol **Tap
  to Continue** yang terlihat. Menekan tombol itu atau mengetuk area dialog
  menutup baris lalu mengembalikan tampilan Battle sebelumnya tanpa mengubah
  pilihan **Switch**. Boss memanggil Anima-nya lebih dulu, lalu
  Seeker-mu memanggil Anima aktifmu. Status dan tombol baru muncul sesudah
  keduanya siap, dan rangkaian Summon tidak dapat dilewati. **Try Again**
  memutar pembuka penuh dengan dialog rematch, sedangkan **Continue
  Expedition** atau sambungan yang pulih langsung kembali ke arena siap tanpa
  mengulang pembuka. Selama
  fight ia berdiri di belakang Anima lawan, paling banyak bicara sekali lagi
  saat perintah, ketika ace terakhirnya masuk, lalu saat menang atau kalah.
- Nimbelisk adalah ace The Confectioner dan selalu disimpan sampai semua Anima
  regulernya KO. Saat Nimbelisk masuk, **Final Confection** aktif sekali dan
  memberinya +1 PP untuk encounter itu.
- The Confectioner tetap berpijak di tempat yang sama ketika mengganti pose.
  Ia tidak memakai pose terkena damage saat Anima-nya Guard, dan baru bereaksi
  tepat ketika serangan benar-benar mengenai Anima. Setelah beat damage selesai,
  ia langsung kembali normal sebelum teks efektivitas biasa muncul. Pada
  Critical, pelat gabungan **Critical hit!** dan efektivitas memang tampil
  bersama angka damage, sementara reaksinya masih berlangsung.
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

## Siapa lawanmu di Duel

Server memilihkan lawan; tidak ada daftar lawan dan tidak ada pengaturan tingkat
kesulitan.

Yang diutamakan tetap **Anima milik pemain lain** yang sudah dipublikasikan ke
Anima Atlas. Arena tidak menampilkan identitas pemiliknya; sesudah kamu benar-benar
melawannya, form itu masuk Atlas dan profilnya dapat menampilkan nama Seeker
pemilik.

Sejak Level jadi tuas kekuatan utama Anima (lihat halaman Anima), lawan
sungguhan disaring dulu lewat **band Level**: hanya Anima lain yang Level-nya
tidak jauh dari Level-mu (kira-kira ±30%, minimum ±3 Level) yang dilirik sama
sekali. Kalau Level asli lawan tidak pas dengan stat-nya untuk band itu, server
menghitung ulang Level tampilan lawan supaya HUD selalu menampilkan angka yang
benar-benar menghasilkan HP dan stat yang kamu lihat — tidak ada lagi "Lv 4"
dengan HP setebal Lv 13. Stat dasar lawan (hasil roll Vision pemiliknya) tidak
pernah disentuh; yang disetel hanya Level efektifnya.

Anima itu hanya dipakai kalau duelnya benar-benar pertandingan, dan server
memastikannya dengan **memainkan duel itu sampai selesai puluhan kali sebelum
kamu menekan apa pun**. Kalau kamu ternyata hampir selalu menang, atau hampir
selalu kalah, lawan itu dilewati dan calon berikutnya dicoba. Server sempat
menilainya cuma dengan taksiran cepat, dan taksiran itu kadang salah cukup jauh
sampai duel yang sangat berat atau sangat mudah tetap lolos; sejak 23 Agustus
2026 yang memutuskan adalah hasil duel yang sudah dimainkan, bukan taksirannya.

Kalau tidak ada Anima pemain yang cocok — dan selama pemain masih sedikit itu
sering terjadi — kamu bertemu **lawan sistem**: **Echo Fledgling**, **Echo
Warden**, atau **Echo Paragon**, mengikuti bentuk Anima-mu sendiri. Karena
pemeriksaannya sekarang lebih ketat, kamu akan lebih sering bertemu mereka
daripada sebelumnya. Itu disengaja: lawan sistem selalu seimbang, sedangkan
lawan sungguhan yang timpang tidak menyenangkan dari sisi mana pun.

Lawan sistem dirakit supaya adil:

- **Level-nya sama** dengan Level Anima-mu, jadi tidak pernah ada lawan yang
  bertumbuh belasan Level di atasmu
- **Kekuatannya disetel untuk Anima-mu sendiri.** Server memainkan duel itu
  berkali-kali dan menyesuaikan lawannya sampai duelnya jadi pertandingan
  sungguhan: kamu unggul, tapi bermain sembarangan bisa membuatmu kalah
- **Elemennya netral**: tidak unggul terhadapmu, dan kamu juga tidak unggul
  terhadapnya. Yang menentukan hasil adalah pilihan Attack/Special/Guard dan
  giliranmu, bukan undian elemen
- **Gaya stat-nya mengikuti Anima-mu**, jadi Anima bertahan menghadapi duel
  bertahan yang panjang dan Anima cepat menghadapi duel yang cepat

Tiga nama itu hanya membedakan penampilan menurut tahap Anima-mu; kekuatannya
selalu dari Level Anima-mu, bukan dari namanya. Art-nya masih placeholder untuk
sekarang. Lawan sistem tetap membayar Bits dan EXP seperti duel biasa, dan tetap
menghitung kemenangan progression.

Bayarannya dinilai dengan cara yang sama seperti lawan sungguhan. Karena
kekuatannya disetel sampai duelnya seimbang, lawan sistem hampir selalu masuk
**Even** dan membayar 8 Bits. Ia tidak pernah menjadi dinding, dan tidak pernah
menjadi latihan sasaran.

## Syarat masuk Duel

Companion harus:

- bangun (bukan Sleep)
- tidak Dormant
- **Energy minimal 20**

Lapar atau kotor tidak mengunci Battle, tapi Anima jadi **lebih lemah** di duel itu. Makin lapar atau makin kotor, potongannya makin dalam (HP, Attack, Special, Guard, Speed). Keduanya sekaligus lebih parah. Feed dan Clean mengembalikan stats.

Duel tetap bisa dimenangkan walau Anima-mu terlantar, dan itu memang disengaja:
kalau Bits habis dan tas kosong, Duel adalah cara mendapatkan Bits untuk beli
makanan, jadi ia tidak boleh berubah menjadi jalan buntu. Lawan sistem ikut
menanggung potongan yang sama besar, sehingga duelnya tetap seimbang. Bits tetap
dari kekuatan lawan, bukan dari seberapa lemah kamu. Yang benar-benar hilang saat
terlantar ada di luar arena: EXP dari Feed, risiko **Dormant**, dan Energy yang
tidak pulih tanpa Sleep.

Tiap duel baru memotong **20 Energy**. Duel yang sudah jalan tidak dipotong lagi kalau app sempat tertutup. Energy pulih lewat **Sleep** (gratis).

Kalau companion aktif tidak memenuhi syarat, tombolnya jadi **Choose Anima**. Tap membuka daftar Anima-mu: yang siap bisa dipilih, yang belum siap redup dengan alasan singkat (Low Energy, Sleeping, Dormant). Tap kartu membuka sheet seperti di Collection — **View Profile** tetap ada, **Battle** atau **Train** langsung memulai duel (Anima bangku di-Summon otomatis).

## Battle atau Train

Tiga kemenangan pertama per hari (reset **tengah malam waktu setempat**) adalah Battle berhadiah:

- Bits menurut seberapa berat duelnya (**7–12** di Duel)
- EXP yang mengikuti Level lawan, selisih Level, dan tier Tough
- +1 kemenangan progression pada Anima

Yang menentukan Bits adalah **kesulitan duelnya, bukan angka stat lawan**. Server
memainkan duel itu sampai selesai berkali-kali sebelum kamu menekan apa pun, lalu
memberi label dari seberapa sering Anima-mu menang: **Favorable** (hampir selalu)
6 Bits, **Even** 8, **Tough** (mendekati lempar koin) 11, **Formidable** 15.
Karena label itu jujur, mengejar lawan berat tidak dirancang lebih untung
maupun lebih rugi — Bits per kemenangan naik, peluang menang turun, dan
rata-rata hasilnya kira-kira sama. Pilih yang kamu nikmati.

Di **Duel** kamu hanya akan melihat **Even** dan **Tough**, karena lawan yang
akan menghabisimu atau yang tidak memberi perlawanan tidak pernah disajikan
(lihat [Siapa lawanmu di Duel](#siapa-lawanmu-di-duel)). Favorable dan Formidable
tetap muncul di **Team Battle** dan **Expedition**, yang menilai kekuatan seluruh
roster dan bukan satu duel.

Menelantarkan Anima **tidak** menaikkan Bits. Duel yang sama dinilai seolah
Hunger dan Hygiene penuh, jadi Anima kelaparan tidak dihitung sebagai lawan
berat.

Lawan Level tinggi memberi lebih banyak EXP, terutama jika Level Anima-mu lebih
rendah. Nilainya dikunci dari snapshot awal duel, jadi kenaikan Level di hasil
tidak mengubah reward yang baru saja diperoleh. Kartu hasil menyebut nama dan
jumlah EXP aktual. Training tidak
menampilkan klaim EXP karena memang tidak memberikannya.

Di Duel, lawan dan tingkat kesulitannya dipilih server (lihat
[Siapa lawanmu di Duel](#siapa-lawanmu-di-duel)); tidak ada pengaturan
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
berakhir. Saat fight Duel, Team Battle, atau Expedition berjalan, nama Seeker,
chip resource, dan navigasi bawah hilang — layar jadi arena penuh.
Di Duel, **Retreat** rata kanan di baris atas arena (tanpa nomor
Turn), dan empat aksi **Attack** / **Special** / **Guard** / **Item** duduk
di kaki layar. Di Team Battle dan Expedition, **Retreat** ada di paling kanan baris
Item / Switch. Shop dan Bag hanya ada di Home, jadi arena tetap bersih. Beli item di
**Shop** sebelum memulai Duel, Team Battle, atau Expedition — tombol Shop
redup selama battle atau run masih berjalan.

## Sesudah battle selesai

Kartu hasil punya dua tombol. Di Duel, tombol besar memakai **Battle Again**
atau **Train Again** setelah 3/3. Di Team Battle, menang memakai **Next Battle**;
kalah, draw, atau Retreat memakai **Try Again**. Keduanya membuka builder dengan
urutan tim sebelumnya sudah terpilih, baru lanjut ke rival berikutnya.
**Return to Lobby** keluar dari battle itu: Duel kembali ke lobby Battle, Team
Battle kembali ke hub-nya. Tombol Android back melakukan hal yang sama. Di
Expedition tidak ada tombol kedua, karena **Return to Map** sudah jalan keluarnya.

Kalau Anima yang baru bertarung tidak bisa langsung bertarung lagi, tombol besar
itu berubah, bukan diam-diam ditolak:

- **Duel** — tombolnya jadi **Choose Anima** dan kartu hasil menambah satu baris
  alasan (misalnya *Cannot battle again · Low Energy*). Tap membuka daftar Anima
  seperti biasa. Feed, Clean, atau Sleep dulu, lalu kembali; begitu Anima-mu
  memenuhi syarat, tombolnya kembali jadi **Battle Again** sendiri.
- **Team Battle** — tombolnya jadi **Edit Team** dengan alasan yang sama. Tap
  membuka builder supaya kamu bisa menukar anggota yang kehabisan Energy. Selama
  ada anggota yang belum siap, tombol **Start** di lobby Team juga tetap redup dan
  menjelaskan alasannya.

Setelah menang, Anima-mu berpose senang. Anima yang belum berevolusi
(Level 1–15) melompat-lompat selama layar hasil masih terbuka. Mulai **Level 16**
badannya lebih besar dan lebih berat, jadi ia mengangkat badan dua kali dengan
tenang lalu kembali diam, bukan melompat.

## Empat perintah

| Tombol | Yang terjadi |
| --- | --- |
| **Attack** | Pukulan biasa. Memakai stat Attack. Power 50. Defense lawan penuh. |
| **Special** | Jurus lebih berat. Memakai stat Special. Power 75. Defense lawan dihitung setengah. Memakan 1 PP. |
| **Guard** | Bertahan (damage masuk dikurangi). Mengembalikan 1 PP. |
| **Item** | Satu item dari tas, mengganti aksi turn itu. Bisa dipakai lagi turn mana pun, dibatasi stok di tas — bukan sekali per duel. |

Item Battle dibeli di Shop. Picker hanya menampilkan tujuh item tempur (bukan makanan atau Energy). Di **Bag** item itu kelihatan tapi tanpa tombol Use. Saat dipakai, label besar di arena menulis efeknya (misalnya **Attack +35%!**), dan Anima berkilat. Selama stoknya masih ada, tombol **Item** tetap aktif sepanjang duel.

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

Sesudah **Evolve**, Attack dan Special bisa mendapat efek tambahan — misalnya
menusuk armor, menembus Guard, meracuni, atau memasang barrier. Efek itu milik
jurus Anima itu, tampil di pelat event, dan tidak menumpuk.

Siapa yang gerak dulu mengikuti **Speed**. Pelat menulis **{nama} moves first.**
sebelum Attack pertama di Duel, Team Battle, dan Expedition, jadi giliran lawan
duluan bukan bug. Guard, Switch, atau Item di giliran itu tidak memakai pelat
ini, karena itu bukan lomba Speed.

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
Critical bukan jurus atau tombol tersendiri: ia muncul secara acak saat Attack
atau Special mengenai target. Speed yang lebih tinggi membuatnya lebih sering,
tetapi satu battle tetap bisa selesai tanpa Critical sama sekali.

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
Nama jurus netral, **{nama} moves first.**, Guard, item, Switch, dan KO memakai pelat yang sama di
arena: **{nama} uses {move}.**, **{nama} braces for impact.**, **{nama} uses
an item.**, **{nama} enters the arena.**, **{nama} is knocked out.** Setiap
label diam sekitar 1,4 detik sebelum aksi atau pelat hilang.

Guard punya penandanya sendiri: begitu pelatnya muncul, badan Anima yang bertahan
disapu kilau sekali, jadi kamu bisa melihat siapa yang mengeras tanpa membaca
teksnya.
Perayaan kemenangan dijelaskan di [Sesudah battle selesai](#sesudah-battle-selesai).
