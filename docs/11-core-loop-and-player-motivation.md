# 11 — Core Loop dan Motivasi Pemain

> **Status, 17 Agustus 2026:** dokumen ini membaca pengalaman yang sudah hidup
> di build saat ini. Ini adalah diagnosis produk, bukan keputusan redesign atau
> janji fitur. Hipotesis tentang perasaan pemain tetap perlu dibuktikan lewat
> playtest. Backend pipeline ritual Adult/Evolved sudah live, tetapi gate pemain
> masih off, jadi belum dihitung sebagai payoff pemain di diagnosis ini.

## Inti fantasi

> **Aku mengubah bagian dari dunia nyataku menjadi companion unik, merawatnya,
> lalu membuktikan kekuatannya.**

Inilah janji Scanima yang paling khas. Scan memberi rasa penemuan, Care
membangun hubungan, dan Battle memberi tempat untuk membuktikan hasil
perawatan serta pertumbuhan itu.

## Tiga pertanyaan core loop

### 1. What is the player doing?

Pemain tidak hanya menekan **Feed** atau **Attack**. Dalam bahasa pengalaman,
mereka sedang:

- menemukan companion dari dunia nyata;
- merawat dan mempersiapkannya;
- memilih Anima serta menyusun tim;
- menguji keputusan mereka dalam Battle;
- menumbuhkan Anima dan membangun Collection yang personal.

Aktivitas itu hidup dalam dua loop utama.

#### Loop khas: discovery dan ownership

**Scan → hatch → beri nama → miliki Anima unik → masukkan ke Collection atau
tim**

Loop ini menjual fantasi Scanima dengan paling jelas. Foto milik pemain menjadi
sesuatu yang hanya mereka miliki, sehingga curiosity berubah menjadi ownership.

#### Loop harian: care dan battle

**Periksa kebutuhan → Feed / Clean / Sleep / Play → Battle atau Expedition →
dapat EXP dan Bits → naik Level atau membeli persediaan → ulangi**

Inilah aktivitas yang paling sering dilakukan setelah Anima menetas. Care
menentukan kesiapan, sedangkan Duel, Team Battle, dan Expedition menjadi tempat
pertumbuhan dan penguasaan permainan.

Karena itu ada perbedaan penting:

> **Scan adalah daya tarik paling khas, tetapi Care dan Battle adalah core loop
> yang paling sering dimainkan.**

### 2. What's stopping them?

Hambatan Scanima terbagi menjadi empat kelompok.

#### Kondisi Anima

- Energy menentukan apakah Anima siap Battle.
- Hunger dan Hygiene yang rendah membuatnya lebih lemah.
- Dormant menghentikan Battle sampai Anima dipulihkan.

Hambatan ini membuat Anima terasa seperti makhluk yang perlu dijaga, bukan kartu
tempur yang selalu siap dipakai. Anima tidak mati dan EXP tidak hilang, sehingga
kegagalan perawatan tetap bisa dipulihkan.

#### Sumber daya dan waktu

- Cores membatasi Scan baru.
- Bits membatasi makanan dan item.
- Sleep memulihkan Energy melalui waktu.
- Hatch membutuhkan waktu sekitar satu menit.
- Grant Core berikutnya bergantung pada kalender.

Sebagian besar hambatan ini mengatur tempo, tetapi tidak semuanya dapat
diselesaikan melalui keputusan pemain. Cores adalah contoh paling penting:
rajin merawat, menang Battle, dan menyelesaikan Expedition tidak membawa pemain
lebih dekat ke Scan berikutnya.

Hal ini juga memengaruhi pembukaan mode tim. Pemain linked mempunyai total tiga
kesempatan starter, sementara Team Battle dan Expedition membutuhkan empat
Anima. Dengan ekonomi live saat ini, Anima keempat paling cepat datang dari
grant Core mingguan berikutnya.

#### Tantangan Battle

- elemen dan kekuatan lawan;
- pilihan Attack, Special, Guard, atau Item;
- PP yang harus dikelola;
- Speed dan urutan serang;
- Switch, komposisi tim, serta HP yang bertahan sepanjang zona Expedition.

Ini adalah hambatan yang paling dapat dikuasai pemain. Kekalahan memberi alasan
untuk belajar, mengganti strategi, merawat Anima, atau menyusun tim yang lebih
baik—bukan hanya menunggu.

#### Batas hadiah

Cap harian menjaga ekonomi dan mencegah farming tanpa batas. Namun sesudah EXP
dan Bits mencapai batasnya, pemain yang masih ingin Battle kehilangan sebagian
alasan progres untuk melanjutkan.

Secara ringkas:

- Battle menghentikan pemain dengan **tantangan**.
- Care menghentikan pemain dengan **tanggung jawab**.
- Energy dan Cores menghentikan pemain dengan **waktu**.

Tantangan dan tanggung jawab dapat terasa bermakna. Terlalu banyak hambatan
berbasis waktu dapat terasa seperti game menahan pemain.

### 3. Why are they doing it?

#### Curiosity

**“Benda atau hewan ini akan menjadi monster seperti apa?”**

Ini adalah motivasi awal terkuat dan pembeda utama Scanima.

#### Ownership

Anima terasa personal karena berasal dari foto dan lingkungan pemain sendiri,
bukan karakter yang dimiliki semua orang.

#### Attachment

Memberi nama, melihat kebutuhan, menidurkan, membersihkan, dan memulihkan Anima
membangun perasaan **“ini milikku dan aku menjaganya.”**

#### Growth

EXP, Level, stats, dan kemenangan membuktikan bahwa waktu pemain menghasilkan
kemajuan. Saat ini payoff tersebut terutama berupa angka: label Adult dan
Evolved belum mengubah wajah atau bentuk Anima. Karena itu pertumbuhan belum
sepenuhnya memenuhi fantasi monster yang benar-benar berkembang.

Implementasi kandidat menutup celah ini lewat ritual eksplisit Lv16/Lv36, art
privat baru, nama move/VFX baru, dan efek Battle yang commit bersama form. Namun
kesimpulan produk di atas baru boleh diubah setelah eval lineage berbayar,
rollout client, aktivasi flag, dan playtest membuktikan bahwa hasilnya tetap
terbaca sebagai companion yang sama.

#### Mastery

Elemen, PP, Guard, Item, Speed, Switch, dan komposisi tim memberi ruang untuk
belajar dan menjadi lebih baik.

#### Completion dan achievement

Collection, kemenangan, chapter Expedition, Boss Seeker, dan Trophy memberi
tujuan jangka menengah serta panjang.

#### Expression

Nama Anima, isi Collection, pilihan companion, susunan tim, publication lineage,
dan nama Seeker pada entry Duel Anima Atlas menjadi cara pemain menunjukkan
identitasnya.

## Diagnosis utama

Build saat ini mempunyai sedikit ketegangan antara janji utama dan aktivitas
utamanya:

- **Janji utama:** menemukan Anima baru dari dunia nyata.
- **Aktivitas harian:** merawat dan bertarung.
- **Hadiah harian:** menjadi lebih kuat dan mempertahankan persediaan.
- **Mata rantai yang belum tertutup:** aktivitas harian tidak memajukan pemain
  menuju Scan berikutnya.

Bits terutama kembali ke makanan dan item. Tanpa tujuan emosional yang cukup
kuat, loop berisiko terbaca sebagai:

> **Battle untuk membeli makanan → makanan menjaga Anima agar bisa Battle
> lagi.**

Ini dapat bekerja bagi pemain yang sudah terikat pada Anima atau menyukai
Battle. Namun pemain yang datang karena fantasi Scan tidak mempunyai jalur aktif
menuju penemuan berikutnya.

Ada dua penguat risiko lain; yang kedua sudah ditangani di balancing live:

1. Pertumbuhan Level belum mempunyai perubahan visual, sehingga payoff jangka
   panjang masih didominasi angka.
2. **Sudah ditangani:** starter lifetime Google sekarang 4 Scan, jadi roster
   Team Battle / Expedition dapat diisi tanpa menunggu grant mingguan. Hunger
   aktif 4/jam, Collection memakai 25% decay dengan floor di atas ambang
   Hungry/Dirty, dan harga Food diturunkan — maintenance linear empat Anima
   bukan lagi pajak harian yang memaksa grind Bits.

Hipotesis yang tersisa: playtest perlu mengamati apakah pemain merasa sedang
**membangun companion** atau hanya **memelihara akses untuk kembali bertarung**.
Celah Scan harian (aktivitas tidak menghasilkan Core) masih terbuka.

## Pilihan arah produk

Pertanyaan strategis yang perlu dijawab:

> **Apakah Scanima terutama tentang menemukan banyak companion unik, membangun
> hubungan dengan beberapa companion, atau menguasai Battle bersama sebuah
> tim?**

Ketiganya dapat hidup bersama, tetapi satu harus menjadi pusat gravitasi.

### Jika discovery menjadi pusat

Aktivitas berulang perlu memberi rasa bahwa pemain bergerak menuju kesempatan
Scan berikutnya, tetap dalam batas biaya yang aman. Tanpa jembatan itu, Scan
lebih mirip hook pembuka daripada loop.

### Jika attachment menjadi pusat

Care dan Level perlu memberi perubahan yang lebih terasa daripada meter dan
angka—misalnya kepribadian, respons, hubungan, atau pertumbuhan visual. Tujuannya
agar satu Anima tetap menarik untuk waktu yang panjang.

### Jika mastery menjadi pusat

Battle dan Expedition menjadi tujuan utama, sementara Scan dapat tetap langka
sebagai perekrutan anggota baru. Kedalaman pilihan, variasi encounter, dan
aspirasi tim kemudian harus menanggung retensi utama.

## Ringkasan posisi sekarang

- **Hook terkuat:** Scan dan kejutan hasilnya.
- **Loop paling lengkap:** Care → Battle → EXP/Bits → persiapan berikutnya.
- **Jembatan emosional:** ownership dan attachment terhadap Anima personal.
- **Celah terbesar yang tersisa:** permainan aktif belum mengarah kembali ke
  discovery (Battle tidak menghasilkan Core).
- **Sudah dikalibrasi:** starter 4 Scan menutup roster tim; Care Collection
  tidak lagi menghukum pemain yang merawat lebih dari satu Anima.
- **Payoff jangka panjang yang belum penuh:** pertumbuhan visual Anima.

Versi paling ringkas dari perjalanan yang ingin dirasakan pemain adalah:

> **Aku menemukan sesuatu → ia menjadi milikku → aku merawatnya → aku
> membuatnya kuat → aku membuktikannya → aku ingin menemukan atau menumbuhkan
> yang berikutnya.**

Core loop sehat ketika pemain selalu memahami tindakan berikutnya, hambatannya
terasa dapat dijawab, dan hadiahnya membawa mereka kembali ke janji utama game.
