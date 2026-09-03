# Seeker Avatar

**Status:** `ready-for-agent`
**Keputusan terkait:** [ADR-0001](../../docs/adr/0001-seeker-avatar-is-chosen-not-derived.md),
[ADR-0002](../../docs/adr/0002-seeker-avatar-art-ships-in-the-build.md)
**Kosakata:** [CONTEXT.md](../../CONTEXT.md) — Seeker, Seeker Avatar, Seeker
Roster, Boss Seeker, Seeker Sheet, Seeker Demographics

## Problem Statement

Pemain adalah seorang Seeker, tapi Seeker tidak punya wujud. Yang dia lihat
tentang dirinya cuma sebuah nama teks di sudut kiri atas dan beberapa baris
statistik. Di layar Profile-nya sendiri, potret yang tampil justru gambar Anima
peliharaannya, bukan dirinya.

Ketimpangan itu paling terasa di battle. Saat menghadapi Boss Seeker di
Expedition, pemain melihat lawannya sebagai manusia utuh yang berdiri di arena,
bereaksi saat Anima-nya kena, dan bersorak saat menang — sementara sisi pemain
kosong, hanya ada Anima dan sebuah dock tombol. Lawan punya wajah; pemain
tidak. Di Atlas, nama pemain sudah tampil ke pemain lain pada kartu hasil duel,
tapi namanya berdiri sendirian tanpa apa pun yang membuatnya terasa seperti
seseorang.

## Solution

Pemain memilih satu Seeker Avatar — figur visual dirinya — dari Seeker Roster
berisi empat figur yang sudah digambar. Pilihan itu murni ekspresi diri: tidak
memberi keuntungan mekanis, tidak memakai mata uang, dan tidak pernah
diturunkan dari Seeker Demographics yang dia isi saat onboarding.

Avatar itu lalu hadir di tiga tempat. Di Profile, ia mengisi slot potret yang
sebelumnya menampilkan Anima aktif, memakai pose profil. Di arena — Duel, Team
Battle, dan Expedition — ia berdiri di sisi pemain sebagai cermin dari posisi
Boss Seeker, memberi perintah saat pemain menyerang, khawatir saat Anima-nya
kena, dan menang atau kalah bersama pemain. Di kartu Atlas, ia tampil kecil di
sebelah nama pemilik yang memang sudah publik.

Pemain memilih avatarnya di onboarding, di sheet yang sama tempat dia menamai
Seeker-nya, dengan figur default sudah terpilih sehingga tidak pernah
memblokir. Setelah itu dia bisa mengganti kapan saja dari Profile, gratis dan
tanpa masa tunggu.

## User Stories

1. Sebagai Seeker, aku ingin memilih figur visual untuk diriku, supaya
   identitasku di game ini bukan cuma sebaris teks.
2. Sebagai Seeker baru, aku ingin memilih avatarku di layar yang sama tempat
   aku menamai diriku, supaya "siapa aku" diputuskan sekali, bukan tersebar di
   dua tempat.
3. Sebagai Seeker baru yang tidak peduli soal avatar, aku ingin sudah ada figur
   default terpilih, supaya aku bisa langsung menekan tombol selesai dan
   kembali ke Anima pertamaku.
4. Sebagai Seeker yang berubah pikiran, aku ingin mengganti avatarku dari
   Profile, supaya pilihan awal tidak mengikatku selamanya.
5. Sebagai Seeker yang suka bereksperimen, aku ingin mengganti avatar
   sesering yang aku mau tanpa masa tunggu, supaya ia terasa seperti ekspresi
   dan bukan seperti komitmen.
6. Sebagai Seeker yang tidak ingin dijadikan laki-laki atau perempuan, aku
   ingin ada figur yang benar-benar netral untuk dipilih, supaya "aku memilih
   ini" bukan berarti "game menyerah menggambarkanku".
7. Sebagai Seeker yang memilih tidak menjawab pertanyaan gender saat
   onboarding, aku ingin jawaban itu tidak menentukan wujudku, supaya
   keputusanku untuk tidak menjawab dihormati alih-alih ditebak.
8. Sebagai Seeker, aku ingin wujudku dan data diriku bisa diubah secara
   terpisah, supaya mengganti penampilan tidak berarti mengubah data pribadi.
9. Sebagai Seeker, aku ingin membuka Profile dan melihat diriku di sana, supaya
   halaman itu terasa seperti halamanku dan bukan halaman Anima-ku.
10. Sebagai Seeker yang melihat picker avatar, aku ingin melihat keempat figur
    sekaligus, supaya aku bisa membandingkan sebelum memilih.
11. Sebagai Seeker, aku ingin figurku terlihat berdiri di arena Duel, supaya
    mode yang paling sering kumainkan juga menampilkan diriku.
12. Sebagai Seeker, aku ingin figurku terlihat di arena Team Battle, supaya aku
    hadir saat mengomandoi lebih dari satu Anima.
13. Sebagai Seeker, aku ingin figurku terlihat di combat Expedition berhadapan
    dengan Boss Seeker, supaya konfrontasinya terasa antara dua orang, bukan
    antara satu orang dan sebuah dock tombol.
14. Sebagai Seeker, aku ingin figurku menghadap ke arah lawan, supaya
    komposisi arenanya terbaca sebagai dua pihak yang berhadapan.
15. Sebagai Seeker, aku ingin figurku memberi pose perintah saat aku memilih
    Attack, Special, atau Switch, supaya perintahku terlihat berasal dari
    seseorang.
16. Sebagai Seeker, aku ingin figurku bereaksi saat Anima-ku terkena serangan,
    supaya pertarungannya punya taruhan yang terlihat.
17. Sebagai Seeker, aku ingin figurku ikut menang atau kalah di akhir battle,
    supaya hasilnya terasa milikku.
18. Sebagai Seeker, aku ingin figurku tidak pernah menutupi Anima-ku atau dock
    aksi, supaya kehadirannya tidak mengganggu permainan.
19. Sebagai Seeker, aku ingin figurku tidak ikut bicara di battle, supaya
    tidak ada dialog yang memaksakan kata-kata ke mulutku.
20. Sebagai Seeker yang bertanding tanpa koneksi bagus, aku ingin avatarku
    tetap muncul, supaya kehadiranku tidak bergantung pada unduhan yang bisa
    gagal.
21. Sebagai Seeker yang mempublikasikan Anima ke Atlas, aku ingin avatarku
    tampil di sebelah namaku di kartu hasil duel, supaya pemain lain melihat
    siapa yang menemukannya.
22. Sebagai Seeker yang menjelajah Atlas, aku ingin melihat avatar pemain lain
    tanpa menunggu gambar dimuat, supaya menjelajah tetap cepat.
23. Sebagai Seeker yang bertanding melawan roster rival, aku ingin lawan tetap
    anonim seperti sekarang, supaya publikasiku ke Atlas tidak berubah menjadi
    pengungkapan identitas.
24. Sebagai Seeker yang masih Guest, aku ingin punya wujud default seperti
    pemain lain, supaya belum masuk akun tidak berarti tidak punya rupa.
25. Sebagai Seeker yang berpindah akun di perangkat yang sama, aku ingin avatar
    yang tampil selalu milik akun yang aktif, supaya tidak ada sisa identitas
    akun sebelumnya.
26. Sebagai Seeker, aku ingin figur avatar digambar dengan gaya yang sama
    dengan Boss Seeker dan Anima, supaya ia terlihat berasal dari dunia yang
    sama.
27. Sebagai pemain yang membaca panduan, aku ingin wiki menjelaskan apa itu
    avatar, di mana ia terlihat, dan cara menggantinya, supaya aku tidak perlu
    menebak.
28. Sebagai pemilik produk, aku ingin fitur ini tidak memanggil model gambar
    saat runtime, supaya jumlah pemain tidak menaikkan biaya sama sekali.
29. Sebagai pemilik produk, aku ingin seluruh fitur bisa dibangun dan diuji
    dengan art placeholder gratis, supaya generation berbayar hanya dijalankan
    sekali setelah layout terbukti benar.
30. Sebagai developer yang menambah figur kelima nanti, aku ingin biayanya satu
    sheet dan satu nilai baru, supaya roster bisa tumbuh tanpa merancang ulang
    apa pun.

## Implementation Decisions

### Seeker Roster dan art-nya

- Roster berisi **empat figur** saat rilis: satu figur androgini sebagai
  default, satu maskulin, satu feminin, dan satu automaton. Tiap figur
  diidentifikasi oleh slug teks, bukan indeks angka, mengikuti gaya katalog
  Shop yang menamai sheet-nya alih-alih menomori.
- Figur netral adalah **anggota roster yang dipilih**, bukan fallback untuk
  jawaban demografis (ADR-0001). Ia juga yang tergambar untuk pemain yang belum
  memilih.
- Setiap figur digambar pada **Seeker Sheet** yang sudah ada — 1024×1024, grid
  3×3, sembilan pose dengan nama yang sama seperti Boss Seeker, chroma green,
  manifest v1. Kontraknya **tidak boleh diubah**: itulah yang membuat loader,
  presenter, dan helper potret yang sudah ada bisa dipakai tanpa modifikasi.
- Sheet dibundel ke build, bukan disajikan dari Storage (ADR-0002). Sertakan
  komentar `ponytail:` yang menyebut plafonnya: di atas sekitar enam figur,
  pindahkan pengiriman ke pola aset chapter.
- Karena kontrak sheet itu kini dipakai berdua, kelas sheet dan presenter-nya
  **diganti nama** supaya tidak lagi menyandang kata "Boss" — dikerjakan sebagai
  prefactor sebelum apa pun yang lain. Panel dialognya tidak ikut diganti nama,
  karena avatar pemain memang tidak bicara, dan kunci payload serta path Storage
  yang memakai `boss_seeker` tidak disentuh karena itu kontrak wire.
- Produksi art dua tahap: **placeholder lokal dulu** dengan biaya nol, mengikuti
  pola generator art katalog yang sudah punya mode placeholder; empat
  generation berbayar (~$0.20–0.28 total, satu panggilan per figur, tanpa retry
  otomatis) dijalankan **sekali di akhir**, setelah picker, Profile, dan
  penempatan arena terbukti benar dengan placeholder. Sheet hasilnya di-commit.

### Penyimpanan pilihan

- Satu **kolom baru** pada record profil pemain, bertipe teks, dengan `CHECK`
  terhadap daftar slug roster. `NULL` berarti belum memilih dan digambar sebagai
  figur default; ini yang membedakan pemain yang memilih default dari pemain
  yang membiarkannya.
- Hak tulis diberikan lewat **`grant update` per-kolom yang aditif** ke role
  `authenticated`. Jangan memakai `revoke update` pada tabelnya, karena itu akan
  mencabut hak kolom yang sudah ada dan mengharuskan pemberian ulang.
- **Tidak ada RPC dan tidak ada operasi Edge Function baru untuk menulis.**
  Aturan server-authoritative di project ini mengikat mata uang; avatar bukan
  mata uang, tidak unik, tidak ber-namespace, dan RLS sudah membatasi pemain ke
  row-nya sendiri, sehingga hal terburuk yang bisa dilakukan client adalah
  memakai avatar valid pada dirinya sendiri. Sertakan komentar singkat di
  migrasinya yang menyebutkan ini keputusan sadar, supaya tidak "diperbaiki"
  menjadi RPC oleh pembaca berikutnya.
- Nilai itu ikut dikembalikan oleh fungsi ringkasan profil Seeker, supaya client
  membacanya lewat jalur yang sama dengan saldo dan statistik.

### Paparan ke pemain lain

- Payload kartu Atlas membawa avatar pemilik **di sebelah nama pemilik yang
  sudah publik**, dan hanya pada kartu yang memang sudah menampilkan nama itu.
  Join ke profil sudah ada di query-nya; yang ditambah hanya satu kolom yang
  diminta.
- Payload roster rival Duel dan Team Battle **tetap tidak membawa apa pun** yang
  mengidentifikasi pemilik. Penghapusan field pemilik yang sudah berjalan di
  sana tidak boleh dilonggarkan.

### Onboarding dan penggantian

- Picker ditambahkan sebagai **satu baris di bottom sheet onboarding yang sudah
  satu-submit**, dengan figur default sudah terpilih. Tidak ada langkah wizard
  baru.
- Avatar dikirim sebagai **argumen opsional** pada operasi penyelesaian profil,
  mengikuti pola yang sudah dipakai birth year dan gender.
- Penggantian memakai **action popover Profile yang sudah ada** (tempat Rename
  dan Delete hidup), tanpa masa tunggu. Cooldown 30 hari pada Rename ada karena
  nama Seeker unik dan publik; avatar tidak keduanya.

### Profile dan arena

- Slot potret Profile menampilkan avatar memakai **pose profil**, menggantikan
  thumbnail Anima aktif. Helper potret Seeker Sheet yang sudah dipakai dialog
  Boss dipakai apa adanya.
- **Top HUD tidak berubah.** Nama Seeker tetap teks tanpa ikon.
- Di arena, figur pemain adalah **cermin dari Boss Seeker**: posisi horizontal
  di sisi pemain sejauh Boss Seeker berada di sisi lawan, ground line yang sama,
  z-order di belakang Anima pemain, `flip_h` aktif supaya menghadap lawan, dan
  penjepitan ke tepi kamera saat zoom yang mencerminkan penjepitan Boss Seeker
  ke tepi seberang.
- **Pemetaan pose dimiliki view, bukan presenter**, mengikuti pemisahan yang
  sudah berlaku untuk Boss Seeker. Pemicunya adalah event sisi pemain: pose
  perintah saat Attack, Special, dan Switch; pose khawatir saat Anima pemain
  kena; pose menang atau kalah di penutup; kembali ke idle di antaranya.
- Avatar pemain **tidak memakai dialog**. Tidak ada integrasi ke panel bicara
  Boss Seeker.
- Duel belum punya figur Seeker sama sekali hari ini, sedangkan Team Battle dan
  Expedition sudah punya layer figur beserta presenter-nya. Kerjakan Team dan
  Expedition lebih dulu supaya pola pemetaan pose sisi pemain terbukti di tempat
  yang infrastrukturnya sudah ada, lalu bawa ke Duel.

### Dokumentasi yang wajib ikut

- **Wiki pemain berubah di langkah yang sama dengan kodenya**: halaman Battle
  dan Atlas terkena, dan avatar tidak masuk ke halaman care, economy, maupun
  anima — jadi kemungkinan besar butuh satu halaman Seeker baru beserta
  pembaruan indeks wiki. Tulis yang live di build, bukan rencana.
- `CLAUDE.md` mendapat satu baris di daftar fakta arsitektur, **hanya setelah
  fitur ini live**, bukan saat masih dikerjakan.

## Testing Decisions

Tes yang baik di sini menguji **perilaku yang pemain rasakan**, bukan detail
implementasi: bahwa picker muncul dengan default terpilih, bahwa potret Profile
menampilkan avatar, bahwa figur berdiri di sisi yang benar menghadap arah yang
benar, bahwa pose berubah saat pemain memerintah, dan bahwa payload rival tetap
anonim. Jangan mengassert nama variabel internal atau urutan pemanggilan
fungsi.

**Nol seam baru.** Empat seam yang sudah ada menampung semuanya:

1. **Suite UI client (`test_scan_ui.gd`)** — seam tertinggi dan yang utama. Ia
   sudah meng-instantiate scene sungguhan untuk onboarding sheet, Profile view,
   Team Battle view, dan Duel, dan sudah punya fixture yang memfabrikasi sheet
   Seeker 1024×1024 di memori lalu mengassert geometri panggung. Prior art-nya
   persis di sana: pakai ulang fixture itu untuk avatar pemain alih-alih
   membuat yang baru.
2. **Suite art dan slicing (`test_sprite_slicing.gd`)** — kontrak art. Di sini
   hidup **pemeriksaan yang paling penting dari seluruh fitur ini**: setiap slug
   di roster punya sheet yang benar-benar ter-bundel dan lolos build sembilan
   pose. Itu satu hal yang paling mungkin rusak diam-diam saat roster bertambah
   atau saat sebuah sheet diganti. Prior art: pemeriksaan Boss Seeker yang sudah
   ada di suite yang sama.
3. **Uji pagar akses SQL (`quota_rules.sql`)** — kolom baru: nilai di luar
   roster ditolak, update pada row sendiri lolos, update pada row pemain lain
   ditolak. Prior art: file itu sudah penuh pemeriksaan grant dan revoke pada
   tabel profil. Pertahankan bentuknya sebagai satu blok `DO` satu transaksi,
   karena sifat itulah yang membuatnya aman dijalankan terhadap database remote.
4. **Suite i18n (`test_i18n.gd`)** — locale key baru untuk picker dan aksi
   penggantian. Sekalian **masukkan file Profile dan onboarding Seeker ke daftar
   file UI yang dipindai**, karena hari ini keduanya tidak ada di sana sehingga
   key di dalamnya tidak dijaga apa pun.

## Out of Scope

- **Toko kosmetik dan sink Bits.** Aksesori, warna alternatif, atau bagian
  avatar yang dibeli tidak termasuk. Jalur upgrade-nya sudah diketahui — sheet
  aksesori pada grid sembilan pose yang sama sebagai sprite anak kedua — tapi
  presisi registrasinya terhadap kepala di sembilan pose harus dibuktikan lebih
  dulu sebelum dijanjikan.
- **Avatar hasil generation dari foto pemain.** Ditolak: bertabrakan dengan gate
  keamanan capture yang memang ada untuk menolak manusia, berbiaya per pemain
  per perubahan, dan menaruh rupa manusia tanpa moderasi di surface publik.
- **Avatar di top HUD.**
- **Wajah untuk rival.** Roster Duel dan Team Battle sengaja anonim dan tetap
  begitu.
- **Dialog untuk avatar pemain.**
- **Kustomisasi bebas**, unggahan gambar, dan variasi art per level atau per
  evolusi.
- **Lokalisasi ke bahasa kedua.** Katalog UI hari ini hanya punya satu bahasa;
  fitur ini tidak mengubah itu.

## Further Notes

- Fitur ini nol panggilan model saat runtime. Satu-satunya biaya model adalah
  empat generation sekali bayar di tahap art, dan itu dijalankan paling akhir.
- Karena art dibundel, tidak ada balapan unduhan yang perlu dijaga terhadap
  pergantian akun: yang perlu diperhatikan hanya bahwa avatar yang tergambar
  mengikuti profil akun yang aktif, sejalan dengan aturan epoch sesi yang sudah
  berlaku untuk state UI lain.
- ADR-0001 dan ADR-0002 adalah bagian normatif dari spec ini. Kalau
  implementasi merasa perlu melanggar salah satunya, itu bukan detail
  implementasi — hentikan dan ubah ADR-nya lebih dulu.
