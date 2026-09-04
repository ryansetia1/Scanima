# Unified Skeleton Loading

**Status:** `ready-for-agent`
**Kosakata:** [CONTEXT.md](../../CONTEXT.md) — Anima, Seeker

## Problem Statement

Saat Scanima menunggu data, placeholder kontennya terlihat seperti berasal dari
sistem desain yang berbeda-beda. Evolution History dan Synthesis History di
Anima Profile memakai squircle cyan yang pulse, Collection memakai rangkaian
bar, Trophy Showcase memakai kotak biru polos, dan thumbnail Anima memakai
kotak abu-abu statis. Sebagian art slot bahkan sempat kosong setelah metadata
datang tetapi sebelum PNG selesai diunduh.

Perbedaan itu membuat perpindahan antar-screen terasa tidak konsisten dan
menyamarkan arti state yang sedang dilihat. Pemain tidak selalu bisa membedakan
konten yang sedang dimuat, konten cached yang sudah siap, dan art yang gagal
tersedia setelah retry habis. Beberapa grup juga menunggu download paling
lambat sebelum menampilkan slot yang sebenarnya sudah siap.

## Solution

Semua content skeleton pada client pemain memakai satu bahasa visual yang
mengambil Evolution History dan Synthesis History sebagai reference: surface
rounded dari keluarga `StatValuePanel`, warna dan border cyan yang sama, serta
pulse lembut dengan ritme yang sama. Bentuk placeholder tetap mengikuti konten
tujuan—art memakai squircle, meter tetap menyerupai meter, dan jumlah slot
tetap mencerminkan konten yang akan datang.

Konten cached tetap tampil langsung tanpa skeleton. Saat beberapa art selesai
pada waktu berbeda, setiap slot mengganti skeleton-nya sendiri melalui
crossfade singkat tanpa menunggu sibling. Thumbnail Anima memakai texture
beranimasi yang dapat dipasang pada kontrol list yang sudah ada, sehingga
interaksi drag, tap, deselect, badge, dan disabled state tidak perlu dirancang
ulang. Jika retry thumbnail benar-benar habis, pulse berhenti dan berubah
menjadi fallback statis.

Loading operasional yang bukan content skeleton—full-screen loader, sweep,
incubator, Scan overlay, Atlas shimmer, button busy, dan copy koneksi—tetap
memakai presentasi khususnya masing-masing.

## User Stories

1. Sebagai Seeker, aku ingin semua content skeleton terlihat berasal dari satu
   sistem desain, supaya aplikasi terasa utuh saat berpindah screen.
2. Sebagai Seeker yang membuka Collection sebelum condition selesai dimuat, aku
   ingin meter placeholder memakai bahasa visual yang sama dengan History,
   supaya state loading langsung dapat dikenali.
3. Sebagai Seeker yang membuka Trophy Showcase tanpa cache, aku ingin melihat
   slot trophy yang stabil, supaya layout tidak terasa kosong atau melompat.
4. Sebagai Seeker yang metadata trophy-nya sudah tiba tetapi PNG-nya belum, aku
   ingin setiap kartu tetap memiliki skeleton, supaya slot kosong tidak
   disalahartikan sebagai trophy rusak.
5. Sebagai Seeker dengan sebagian trophy cached, aku ingin art cached tampil
   langsung, supaya aplikasi tidak menyembunyikan data yang sudah tersedia.
6. Sebagai Seeker dengan beberapa trophy yang sedang diunduh, aku ingin setiap
   kartu selesai secara independen, supaya satu download lambat tidak menahan
   seluruh showcase.
7. Sebagai Seeker yang membuka Evolution History, aku ingin jumlah placeholder
   mencerminkan jumlah form yang diharapkan, supaya struktur lineage tetap
   terbaca selama loading.
8. Sebagai Seeker yang form evolusinya selesai pada waktu berbeda, aku ingin
   setiap form muncul segera setelah siap, supaya aku tidak menunggu art lain
   yang lebih lambat.
9. Sebagai Seeker yang membuka Synthesis History, aku ingin source art cached
   tetap terlihat sementara source lain dimuat, supaya konten siap tidak
   berkedip kembali menjadi loading.
10. Sebagai Seeker yang salah satu source art-nya baru selesai diunduh, aku
    ingin slot itu langsung berubah menjadi art, supaya progress nyata terlihat
    tanpa progress bar palsu.
11. Sebagai Seeker yang melihat roster Collection, aku ingin thumbnail yang
    belum tersedia memakai skeleton cyan, bukan kotak abu-abu yang tidak
    menjelaskan state-nya.
12. Sebagai Seeker yang memilih Anima untuk Battle, aku ingin thumbnail loading
    terlihat sama dengan thumbnail loading di Collection, supaya arti visualnya
    konsisten.
13. Sebagai Seeker yang memilih roster Team Battle atau Expedition, aku ingin
    skeleton thumbnail tidak mengubah perilaku urutan tap dan deselect, supaya
    pemilihan tim tetap dapat dipercaya.
14. Sebagai Seeker yang memilih source Synthesis, aku ingin thumbnail pending
    memakai kontrak yang sama tanpa mengubah cara picker dipakai.
15. Sebagai Seeker yang art thumbnail-nya selesai diunduh, aku ingin skeleton
    berubah halus menjadi art, supaya pembaruan tidak terasa seperti flash.
16. Sebagai Seeker yang koneksinya cepat, aku ingin cache langsung tampil tanpa
    minimum loading duration, supaya aplikasi tidak sengaja diperlambat demi
    memamerkan animasi.
17. Sebagai Seeker yang koneksinya lambat, aku ingin pulse tetap berjalan hanya
    selama download atau retry masih mungkin, supaya animasi mempunyai arti.
18. Sebagai Seeker yang download thumbnail-nya gagal sampai batas retry, aku
    ingin pulse berhenti pada fallback stabil, supaya aplikasi tidak berpura-
    pura masih bekerja.
19. Sebagai Seeker yang berganti akun, aku ingin seluruh skeleton dan transisi
    lama dibersihkan, supaya art akun sebelumnya tidak pernah muncul.
20. Sebagai Seeker yang berpindah screen saat download berlangsung, aku ingin
    callback lama tidak menimpa screen atau Anima yang sekarang aktif.
21. Sebagai Seeker, aku ingin section title dan copy yang sudah tersedia tetap
    terbaca selama skeleton aktif, supaya placeholder tidak menghapus konteks.
22. Sebagai Seeker, aku ingin skeleton tidak dapat menerima fokus atau tap,
    supaya placeholder tidak menciptakan target interaksi palsu.
23. Sebagai Seeker, aku ingin peralihan skeleton ke konten berlangsung cepat
    dan tenang, supaya ia tidak bersaing dengan art atau aksi utama.
24. Sebagai Seeker, aku ingin full-screen loading, Scan analysis, incubator,
    dan loading Battle tetap berbeda dari content skeleton, supaya setiap
    indikator tetap sesuai dengan jenis pekerjaan yang berlangsung.
25. Sebagai Seeker yang membuka Atlas, aku ingin shimmer kartu tetap seperti
    sekarang, karena ia menandai pengambilan detail dan bukan konten kosong.
26. Sebagai pemilik produk, aku ingin perubahan ini tidak menambah request,
    retry, atau panggilan model, supaya konsistensi visual tidak mengubah biaya
    maupun beban jaringan.
27. Sebagai developer, aku ingin warna, radius, border, pulse, dan timing resolve
    mempunyai satu kontrak kanonis, supaya screen baru tidak mengarang skeleton
    sendiri.
28. Sebagai developer, aku ingin kontrol list yang sudah matang tetap dipakai,
    supaya polish skeleton tidak membuka kembali bug drag-scroll dan selection.
29. Sebagai developer, aku ingin transisi thumbnail dibersihkan setelah selesai,
    supaya roster besar tidak menumpuk frame texture sementara.
30. Sebagai developer, aku ingin satu suite UI yang memakai scene dan kontrol
    sungguhan menjaga kontrak ini, supaya regresi terlihat pada perilaku yang
    benar-benar dialami pemain.

## Implementation Decisions

- Scope hanya client pemain Godot. Admin console bukan bagian dari pekerjaan
  ini.
- Istilah **content skeleton** berarti placeholder yang mempertahankan ruang
  konten yang belum tersedia. Full-screen loading, progress operasional,
  incubator, scan effect, shader shimmer, text status, dan disabled button
  bukan content skeleton.
- Reference kanonis adalah skeleton art pada Evolution History dan Synthesis
  History: keluarga surface `StatValuePanel`, radius dan border cyan yang sama,
  serta pulse dua arah selama 0,62 detik per sisi dengan easing sine.
- Geometri bersifat content-aware. Art menggunakan squircle; meter dan text
  mempertahankan proporsi konten akhirnya, tetapi mengambil surface, warna,
  radius, spacing, dan pulse dari kontrak yang sama.
- Section title, label, dan metadata yang sudah diketahui tidak diganti dengan
  skeleton. Hanya nilai atau art yang benar-benar belum tersedia yang memakai
  placeholder.
- Loading cache-first tetap berlaku. Data atau texture cached dicat langsung
  dan tidak pernah sengaja diturunkan kembali menjadi skeleton saat
  revalidation.
- Tidak ada minimum skeleton duration. Response yang selesai sebelum skeleton
  sempat terlukis langsung menampilkan konten.
- Resolve menggunakan crossfade alpha 0,18 detik: outgoing memakai ease-in
  quadratic dan incoming memakai ease-out quadratic. Tidak ada scale, stagger,
  atau delay tambahan.
- Crossfade grup hanya dipakai untuk condition meter karena seluruh nilainya
  datang dari satu payload authoritative. Trophy, Evolution History, Synthesis
  History, dan thumbnail resolve per-slot.
- Trophy Showcase mempertahankan skeleton per kartu setelah metadata tiba
  sampai texture kartu tersebut siap. Kartu cached tidak ikut skeleton.
- Evolution History memakai slot stabil alih-alih menghancurkan seluruh row
  saat state berubah. Arrow dan jumlah form tetap stabil; setiap slot dapat
  menerima metadata dan art secara independen.
- Synthesis History dan Evolution History menerapkan hasil texture segera
  setelah setiap fetch selesai, bukan menunggu seluruh batch art.
- Kontrol list roster yang ada tidak diganti. Touch scrolling, press
  selection, urutan tap, deselect, badge, dan disabled-state tetap menjadi
  kontrak kontrol tersebut.
- Thumbnail loading direpresentasikan sebagai `AnimatedTexture`. Frame pulse
  memakai token skeleton kanonis; resolve memakai enam frame alpha blend dalam
  0,18 detik.
- Resource animasi thumbnail dikoordinasikan per cache key. Semua surface yang
  sedang menampilkan Anima yang sama melihat state yang sama tanpa memerlukan
  node overlay per item.
- Setelah resolve, frame sementara dilepas dan resource berhenti pada texture
  final. Resource loading dan callback membawa session epoch agar pergantian
  akun membatalkan hasil lama.
- Batas retry thumbnail tetap tiga dan perilaku jaringan tidak berubah. Selama
  request atau retry masih mungkin, skeleton pulse; setelah batas habis,
  resource berubah menjadi fallback skeleton statis.
- Failure fallback tidak menambah dialog, toast, atau copy baru. Pekerjaan ini
  hanya memperjelas state visual yang sebelumnya berupa kotak abu-abu permanen.
- Skeleton selalu mengabaikan input dan tidak mengambil fokus.
- Tidak ada dependency baru, perubahan backend, perubahan payload, atau
  perubahan penyimpanan.
- Kontrak skeleton dicatat pada dokumentasi UI internal dan spesifikasi UI.
  Panduan pemain, glossary domain, ADR, dan dokumen arsitektur lintas-domain
  tidak berubah karena mekanisme permainan tidak berubah.

## Testing Decisions

Tes yang baik menguji perilaku yang pemain lihat melalui scene dan kontrol
sungguhan: kapan skeleton tampil, kapan cache menang, bagaimana slot resolve,
dan apakah interaksi list tetap sama. Tes tidak mengunci nama dictionary,
jumlah helper privat, atau urutan internal pemanggilan fungsi.

**Satu automated seam utama:** suite UI client yang sudah meng-instance
komponen production. Tidak dibuat test file khusus untuk texture animator.

Suite itu menjaga:

1. Skeleton kanonis pulse saat loading, mengabaikan input, dan berhenti serta
   mereset opacity saat selesai atau disembunyikan.
2. Condition meter memakai skeleton content-aware lalu crossfade sebagai satu
   grup ketika payload authoritative tiba.
3. Trophy cached langsung tampil, trophy uncached mempertahankan skeleton per
   kartu, dan kartu resolve tanpa menunggu sibling.
4. Evolution History mempertahankan jumlah slot dan arrow selama loading,
   lalu setiap form resolve tanpa menumpuk skeleton dan konten.
5. Synthesis History menampilkan cache per-slot dan mengakhiri skeleton source
   pertama walaupun source kedua masih menunggu.
6. Thumbnail miss menghasilkan pulse texture, success melewati crossfade
   0,18 detik, dan frame sementara dilepas setelah settle.
7. Thumbnail yang mencapai batas retry berhenti pulse pada fallback statis.
8. Pergantian session membatalkan resolve lama dan membersihkan resource
   transisi.
9. `ItemList` sungguhan tetap menerima icon beranimasi tanpa mengubah perilaku
   drag-scroll, press selection, urutan tap, deselect, badge, atau dim state.
10. Cache hit tidak pernah menampilkan skeleton atau crossfade palsu.
11. Pergantian Anima atau penutupan view saat transisi berjalan tidak
    meninggalkan tween yang menulis ke node tidak valid.

Tes tween menunggu metadata tween atau state settle yang sebenarnya, bukan
timer dengan margin tebakan. Pemeriksaan visual dilakukan terpisah melalui
harness production pada viewport portrait dan landscape untuk Collection,
Trophy Showcase, Evolution History, dan Synthesis History.

## Out of Scope

- Mengubah full-screen `LoadingScreen`, sweep Synthesis Review, Incubator,
  Scan overlay, Battle/Team/Expedition loading copy, button busy, atau Home
  empty effect.
- Mengubah shimmer Atlas atau Guard.
- Mengganti `ItemList` dengan custom grid atau custom row.
- Menambah progress percentage, minimum display duration, stagger, scale
  animation, atau fake progress.
- Mengubah jumlah retry, menambah retry periodik, atau mengubah antrean
  download.
- Menambah error dialog atau icon baru untuk art yang gagal.
- Mengubah backend, database, API, cache persistence, mata uang, atau gameplay.
- Mengubah admin console.
- Mengubah wiki pemain, glossary domain, atau membuat ADR.

## Further Notes

- Perubahan ini tidak memanggil model dan tidak menambah biaya runtime.
- `AnimatedTexture` memakai frame diskret, tetapi enam frame dalam 0,18 detik
  cukup untuk resolve singkat dan menghindari render target per thumbnail pada
  roster besar.
- Pulse thumbnail boleh berbagi frame image kanonis, tetapi state resolve harus
  terpisah per cache key karena setiap Anima menerima art pada waktu berbeda.
- Art yang sudah cached selalu lebih berharga daripada konsistensi animasi:
  jangan pernah menyembunyikan cache hanya agar semua slot sempat pulse.
- Kalau implementasi menuntut penggantian kontrol roster atau perubahan
  protokol download, hentikan dan kembali ke spec; itu berarti solusi sudah
  keluar dari batas yang disepakati.
