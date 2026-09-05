# Full-Screen Battle Arena and Boss Encounter Opening

**Status:** `ready-for-agent`
**Keputusan terkait:** [ADR-0003](../../docs/adr/0003-battle-chrome-overlays-full-screen-arena.md)
**Kosakata:** [CONTEXT.md](../../CONTEXT.md) — Seeker, Seeker Avatar, Boss
Seeker, Boss Encounter Opening, Battle Arena, Battle Chrome, Battle Overlay

## Problem Statement

Arena Battle sekarang dibangun sebagai dua bagian vertikal: stage di atas dan
footer atau action dock di bawah. Ketika Battle Chrome disembunyikan selama
opening, bagian bawah itu hanya dibuat transparan; ruangnya tetap dicadangkan.
Akibatnya dunia Battle terlihat berhenti sebelum dasar layar dan meninggalkan
gap kosong yang cukup besar tepat ketika opening seharusnya terasa paling
cinematic. Struktur yang sama juga membatasi desain UI Battle berikutnya karena
setiap perubahan tinggi Chrome ikut mengubah ukuran dunia, kamera, skala Anima,
dan posisi Seeker.

Final Battle Expedition mempunyai masalah tambahan. Opening Boss Seeker saat
ini masih memperlihatkan Anima pemain dan Battle Chrome sejak awal, lalu hanya
memanggil Anima Boss sebelum input dibuka. Konfrontasinya belum terbaca sebagai
dua Seeker yang saling berhadapan dan masing-masing memanggil Anima pertamanya.

## Solution

Setiap encounter aktif memakai Battle Arena full-screen dan full-bleed sebagai
dunia yang ukurannya tetap. Battle Chrome menjadi lapisan screen-space di atas
Arena, sedangkan dialog, picker, konfirmasi, dan result menjadi Battle Overlay
di atas keduanya. Background boleh memenuhi layar sampai belakang notch dan
gesture area; karakter, informasi penting, dan kontrol interaktif tetap
mengikuti safe area. Muncul atau hilangnya UI tidak pernah lagi memperbesar
atau mengecilkan Arena.

Opening memakai framing cinematic yang memanfaatkan area layar saat Chrome
tersembunyi. Setelah kedua Anima siap, seluruh dunia bergerak sekali selama
0,32 detik menuju framing gameplay yang menghindari area Chrome. Background,
ground line, Anima, Seeker, shadow, portal, dan kamera tetap terasa sebagai satu
dunia; Chrome fade-in bersamaan dan input baru terbuka setelah transisi selesai.
Framing itu lalu stabil sampai encounter selesai, termasuk ketika dialog,
picker, atau result tampil.

Boss Encounter Opening memakai koreografi khusus. Setelah Loading Screen
hilang, hanya Seeker Avatar pemain dan Boss Seeker yang terlihat selama jeda
0,7 detik. Dialog opening Boss kemudian muncul tanpa overlay gelap. Setelah
dialog ditutup, Boss Seeker memanggil Anima pertamanya, lalu Seeker pemain
memanggil Anima pertamanya. Baru setelah keduanya siap, framing berpindah ke
gameplay, Battle Chrome muncul, dan Battle dapat disentuh.

## User Stories

1. Sebagai Seeker, aku ingin arena memenuhi seluruh layar selama Battle,
   supaya dunia tidak terlihat berhenti di atas sebuah bagian kosong.
2. Sebagai Seeker, aku ingin background tetap terlihat di belakang HUD dan
   tombol, supaya Battle terasa sebagai satu tempat utuh dan bukan dua panel
   yang ditumpuk.
3. Sebagai Seeker, aku ingin ukuran Arena tetap sama ketika kontrol muncul,
   supaya lingkungan tidak meloncat atau terpotong oleh perubahan UI.
4. Sebagai Seeker, aku ingin opening memakai ruang yang tersedia saat kontrol
   belum dibutuhkan, supaya pengenalan petarung terasa lebih cinematic.
5. Sebagai Seeker, aku ingin Chrome muncul di atas Arena, supaya kontrol terasa
   menjadi bagian dari presentasi Battle dan bukan lantai terpisah.
6. Sebagai Seeker di perangkat berponi layar, aku ingin background tetap
   full-bleed tetapi karakter dan kontrol tetap aman, supaya layar terisi tanpa
   ada informasi yang tertutup notch.
7. Sebagai Seeker di perangkat dengan gesture bar, aku ingin semua tombol
   mudah disentuh tanpa meninggalkan pita kosong pada background, supaya
   keselamatan input tidak mengorbankan komposisi.
8. Sebagai Seeker dalam mode portrait, aku ingin Anima, Seeker, HUD, dan tombol
   tetap terbaca di atas Arena full-screen, supaya perubahan struktur tidak
   membuat layar utama Battle sesak.
9. Sebagai Seeker dalam mode landscape, aku ingin framing dan occlusion Chrome
   menyesuaikan bentuk layar, supaya petarung tidak tertutup kontrol.
10. Sebagai Seeker di Duel, aku ingin opening dan gameplay memakai Arena
    full-screen yang sama, supaya mode Battle utama tidak lagi menyisakan gap.
11. Sebagai Seeker di Team Battle, aku ingin status roster dan action dock
    melapisi Arena tanpa mengecilkannya, supaya timku tetap terasa berada di
    dunia yang sama.
12. Sebagai Seeker di Duel atau Team Battle, aku ingin masuk ketika Anima lawan
    sudah menunggu lalu memanggil Anima-ku sendiri, supaya Battle dimulai cepat
    tanpa dua entrance yang tidak diperlukan.
13. Sebagai Seeker di Expedition Battle atau Elite, aku ingin presentasi Arena
    konsisten dengan mode lain, supaya perpindahan antar-node tidak terasa
    seperti UI yang berbeda.
14. Sebagai Seeker di Final Battle Expedition, aku ingin menghadapi Boss
    Seeker di Arena full-screen, supaya encounter puncaknya punya komposisi
    paling kuat.
15. Sebagai Seeker, aku ingin wajah, badan utama, kaki, dan shadow petarung
    tidak tertutup Chrome, supaya ukuran Arena penuh tidak mengurangi
    keterbacaan.
16. Sebagai Seeker, aku ingin background dan efek dunia tetap boleh terlihat
    di belakang Chrome, supaya overlay tidak kembali terasa seperti bagian
    layar yang kosong.
17. Sebagai Seeker, aku ingin teks aksi dan feedback penting menghindari tombol
    interaktif, supaya informasi turn tidak tertutup ketika dibutuhkan.
18. Sebagai Seeker, aku ingin perubahan dari framing opening ke framing
    gameplay bergerak halus, supaya karakter tidak tiba-tiba melompat posisi.
19. Sebagai Seeker, aku ingin background, ground line, karakter, shadow, dan
    portal tetap bergerak sebagai satu dunia, supaya kaki tidak meluncur di
    atas lantai yang diam.
20. Sebagai Seeker, aku ingin Chrome fade-in bersamaan dengan reframe dunia,
    supaya Battle mulai dalam satu beat yang jelas.
21. Sebagai Seeker, aku ingin input tetap terkunci sampai transisi selesai,
    supaya tap pertama tidak terjadi saat tombol atau kamera masih bergerak.
22. Sebagai Seeker, aku ingin framing gameplay tetap stabil setelah dibuka,
    supaya dialog dan picker tidak terus membuat karakter membesar atau
    mengecil.
23. Sebagai Seeker yang membuka Switch atau Item picker, aku ingin picker
    tampil di atas Battle tanpa mengubah dunia di belakangnya, supaya pilihan
    tidak mengganggu orientasiku.
24. Sebagai Seeker yang menerima dialog Boss di tengah Battle, aku ingin
    Chrome tetap terlihat tetapi tidak dapat disentuh, supaya aku tetap paham
    state Battle tanpa dapat mengirim aksi di balik dialog.
25. Sebagai Seeker yang melihat result, aku ingin command Chrome menghilang dan
    result melapisi pose akhir yang stabil, supaya kemenangan atau kekalahan
    tidak memindahkan petarung.
26. Sebagai Seeker, aku ingin Battle Shake hanya mengguncang dunia dan bukan
    Chrome, supaya kontrol tetap mudah dibaca pada Arena full-screen.
27. Sebagai Seeker yang memasuki Final Battle, aku ingin mula-mula hanya
    melihat Seeker Avatar-ku dan Boss Seeker, supaya encounter terbaca sebagai
    konfrontasi antara dua Seeker.
28. Sebagai Seeker yang memasuki Final Battle, aku ingin kedua Anima masih
    tersembunyi pada shot pembuka, supaya setiap Summon mempunyai makna.
29. Sebagai Seeker, aku ingin ada jeda natural sebelum Boss bicara, supaya
    kehadiran kedua Seeker sempat terbaca sebelum dialog mengambil fokus.
30. Sebagai Seeker, aku ingin tap selama jeda awal diabaikan, supaya aku tidak
    melewati dialog yang bahkan belum muncul.
31. Sebagai Seeker, aku ingin dialog opening tetap menampilkan nama dan
    portrait Boss tanpa overlay gelap, supaya identitas pembicara jelas dan
    arena tetap terlihat.
32. Sebagai Seeker, aku ingin dapat menutup dialog opening dengan tap, tombol
    konfirmasi, atau Back, supaya interaksinya sama dengan dialog Boss sekarang.
33. Sebagai Seeker, aku ingin Boss Seeker mengambil pose command lalu memanggil
    Anima pertamanya setelah dialog, supaya lawan memperkenalkan ancamannya
    lebih dulu.
34. Sebagai Seeker, aku ingin Seeker Avatar-ku kemudian mengambil pose command
    dan memanggil Anima pertamaku, supaya pihak pemain mendapat entrance yang
    setara.
35. Sebagai Seeker, aku ingin Summon kedua dimulai tanpa tap atau jeda tambahan,
    supaya opening tetap mengalir dan tidak terasa lambat.
36. Sebagai Seeker, aku ingin animasi Summon tidak dapat dilewati setelah
    dialog ditutup, supaya urutan Boss lalu pemain selalu terbaca utuh.
37. Sebagai Seeker, aku ingin HUD dan action dock baru muncul setelah kedua
    Anima siap, supaya kontrol tidak mendahului dunia Battle.
38. Sebagai Seeker, aku ingin opening khusus ini berlaku pada setiap Boss
    Seeker Expedition, supaya chapter mendatang tidak kembali memakai
    Expedition Opening.
39. Sebagai Seeker yang mencoba ulang zona Boss, aku ingin koreografi penuh
    diputar dengan dialog rematch, supaya retry tetap diakui oleh Boss.
40. Sebagai Seeker yang melanjutkan encounter tersimpan, aku ingin langsung
    kembali ke Battle tanpa replay opening, supaya Continue tidak membuang
    waktuku.
41. Sebagai Seeker dengan koneksi yang memicu refresh session, aku ingin
    encounter yang sama pulih menjadi Arena siap tanpa mengulang atau
    menyisakan setengah opening, supaya aku tidak terjebak.
42. Sebagai Seeker yang berpindah akun atau meninggalkan encounter saat
    opening berjalan, aku ingin dialog, portal, dan animasi lama dibatalkan,
    supaya state akun sebelumnya tidak muncul kembali.
43. Sebagai Seeker yang memindahkan app ke background lalu kembali ke view
    yang sama, aku ingin opening melanjutkan fase yang sedang berjalan, supaya
    gangguan singkat tidak mengulang sequence.
44. Sebagai Seeker ketika copy dialog atau art kosmetik gagal tersedia, aku
    ingin Summon dan Battle tetap dapat berjalan, supaya kegagalan presentasi
    tidak mengunci Expedition.
45. Sebagai Seeker, aku ingin dialog command, ace terakhir, victory, dan defeat
    tetap bekerja seperti sekarang, supaya opening baru tidak mengubah karakter
    atau budget bicara Boss.
46. Sebagai pemilik produk, aku ingin perubahan ini memakai pose, portal,
    dialog, musik, SFX, VFX, dan art yang sudah ada, supaya polish layout tidak
    menambah biaya produksi aset.
47. Sebagai desainer UI masa depan, aku ingin Arena tidak bergantung pada
    tinggi Chrome hari ini, supaya HUD dapat didesain ulang sebagai elemen di
    dalam Arena tanpa migrasi struktur dunia lagi.
48. Sebagai developer, aku ingin Duel, Team Battle, dan Expedition berbagi
    kontrak layer dan framing yang sama, supaya mode baru tidak mengarang
    pembagian stage/footer sendiri.
49. Sebagai developer, aku ingin regression test mengukur perilaku scene
    production, supaya refactor internal tetap bebas selama hasil pemain tidak
    berubah.
50. Sebagai pemain yang membaca panduan, aku ingin opening dan presentasi
    Battle yang dijelaskan sesuai build yang benar-benar kumainkan, supaya
    panduan tidak mendokumentasikan rencana atau perilaku lama.

## Implementation Decisions

### Kontrak layer Battle

- ADR-0003 bersifat normatif. Semua encounter aktif memakai tiga konsep dari
  glossary: Battle Arena sebagai dunia full-screen, Battle Chrome sebagai UI
  persisten di atasnya, dan Battle Overlay sebagai UI sementara di lapisan
  tertinggi encounter.
- Kontrak ini berlaku untuk Duel, Team Battle, Expedition Battle/Elite, dan
  Expedition Boss. Lobby Battle, team builder, route map, dan Loading Screen
  tetap memakai layout sekarang.
- Battle Arena memenuhi viewport encounter dan tidak menjadi baris di atas
  footer atau dock. Tidak ada kontrol Battle yang boleh mengambil ukuran
  layout dari Arena.
- Background Arena full-bleed sampai tepi viewport, termasuk di belakang
  device inset. Konten penting dan seluruh target interaktif memakai safe area.
- Battle Chrome mencakup status fighter dan roster, status encounter, command,
  Item, Switch, dan Retreat. Variasi tombol per mode tetap dipertahankan; scope
  ini tidak merancang ulang isi atau hierarki kontrolnya.
- Battle Overlay mencakup dialog, picker, konfirmasi, dan result. Loading atau
  modal global tetap berada di atas seluruh encounter.
- Feedback turn yang melekat pada aksi—pelat aksi, damage, effectiveness, dan
  feedback serupa—tetap terikat ke presentasi Arena, tetapi ditempatkan agar
  tidak tertutup target interaktif Chrome.
- Chrome yang disembunyikan tidak menerima pointer, focus, Back, atau shortcut.
  Alpha nol saja tidak dianggap state tersembunyi bila kontrol masih dapat
  menangkap input.

### Framing dan occlusion

- Ukuran Battle Arena konstan sejak encounter dipasang sampai dilepas. Dialog,
  picker, result, serta perubahan visibility Chrome tidak boleh memicu resize
  Arena.
- Framing karakter dihitung terhadap area baca, bukan ukuran Arena yang sudah
  dikurangi footer. Opening memakai cinematic framing area yang luas; gameplay
  memakai framing area yang mengurangi occlusion aktual dari Chrome.
- Occlusion berasal dari geometri Chrome yang benar-benar dirender dan safe
  area perangkat, bukan angka tinggi footer yang disalin per mode. Background
  tetap boleh tergambar di balik zona itu.
- Wajah, badan utama, kaki, contact shadow, dan feedback penting dijaga di luar
  zona kontrol. Karakter yang sangat besar tetap mengikuti batas skala dan
  framing Battle yang sudah hidup.
- Perubahan cinematic ke gameplay adalah satu transisi 0,32 detik. Kamera,
  fighter layer, kedua Seeker, ground contact, portal, dan shadow bergerak
  sebagai satu dunia; background mengikuti dengan parallax lebih lembut.
- Battle Chrome fade-in selama transisi yang sama. Input baru dibuka setelah
  framing dan Chrome settle.
- Setelah gameplay framing aktif, dialog tengah Battle, picker, konfirmasi,
  dan result tidak mengembalikan cinematic framing. Tidak ada reframe berulang
  hanya karena Overlay muncul atau Chrome dinonaktifkan.
- Result menyembunyikan command Chrome tanpa mengubah Arena atau gameplay
  framing. Pose akhir tetap berada di tempat yang sama di belakang result.
- Battle World Shake dan feedback impact tetap hanya memengaruhi dunia;
  Chrome dan Overlay tidak ikut terguncang.

### Duel/Team Opening dan Expedition Opening

- Duel/Team Opening berlaku pada session Duel atau Team Battle baru. Shot awal
  menampilkan Seeker Avatar pemain dan Anima lawan aktif yang sudah Idle beserta
  contact shadow; Anima pemain dan Battle Chrome masih tersembunyi.
- Anima lawan tidak memakai portal atau animasi Summon. Shot awal ditahan selama
  0,4 detik dengan seluruh input terkunci.
- Seeker Avatar pemain lalu mengambil pose Switch Command selama beat 0,42
  detik dan memanggil Anima pemain memakai portal, reveal, VFX, dan SFX yang
  sudah ada. Tidak ada dialog, teks Battle Start, aset, atau entrance tambahan.
- Framing cinematic sejak shot awal sudah memperhitungkan Anima pemain yang
  tersembunyi, sehingga reveal tidak mengubah camera framing.
- Setelah Anima pemain siap, seluruh dunia berpindah selama 0,32 detik ke
  framing gameplay sambil Battle Chrome fade-in. Input baru terbuka setelah
  keduanya settle.
- Duel/Team Opening diputar pada setiap session baru, termasuk Battle Again.
  Continue, reconnect, authoritative refresh, dan transport retry session yang
  sama langsung kembali ke gameplay tanpa replay.
- Seeker Avatar adalah kosmetik: jika sheet-nya tidak tersedia, portal dan
  reveal Anima pemain tetap berjalan lalu Battle dibuka.
- Expedition Opening tetap memakai koreografi empat langkah yang sudah live
  untuk encounter Battle/Elite: Seeker Avatar pemain berdiri sendiri, Anima
  lawan di-Summon, Seeker pemain memberi command, lalu Anima pemain di-Summon.
  Sesudah kedua Anima siap, framing dan Chrome bertransisi bersama selama 0,32
  detik sebelum input terbuka.
- Expedition Opening hanya diputar pada encounter baru, bukan Continue,
  authoritative refresh, atau transport retry.

### Boss Encounter Opening

- Boss Encounter Opening adalah jalur Expedition Boss khusus dan tidak
  menggunakan Duel/Team Opening maupun Expedition Opening.
- Sequence dimulai setelah Loading Screen benar-benar hilang. Boss opening
  tidak boleh berjalan tersembunyi di belakang loading.
- Shot awal menampilkan background, contact shadow, Seeker Avatar pemain, dan
  Boss Seeker dalam pose idle. Kedua Anima, status, dan command Chrome
  tersembunyi.
- Shot diam berlangsung 0,7 detik. Input selama beat ini diabaikan.
- Boss kemudian menyampaikan tepat satu line `boss_intro` pada attempt pertama
  atau `rematch` pada retry. Dialog mempertahankan portrait profil, nama,
  petunjuk continue, dan arena tanpa dim overlay.
- Menutup dialog dengan tap, confirm, atau Back melanjutkan sequence; Back
  tidak meninggalkan encounter.
- Boss Seeker mengambil pose Switch Command, mempertahankan command beat yang
  sudah ada, lalu portal dan reveal Anima Boss pertama dimainkan. Sesudah
  reveal, Boss kembali Idle.
- Tanpa tap atau delay tambahan, Seeker Avatar pemain mengambil pose Switch
  Command dengan beat yang sama, lalu portal dan reveal Anima pemain pertama
  dimainkan. Sesudah reveal, Seeker kembali Idle.
- Kedua Summon memakai presenter, portal, VFX, SFX, dan timing reveal yang
  sudah ada. Tidak ada aset atau efek baru dan tidak ada skip setelah dialog
  ditutup.
- Camera framing stabil selama pause, dialog, dan kedua Summon; Anima yang
  masih tersembunyi tetap diperhitungkan agar tiap reveal tidak menghasilkan
  snap. Setelah reveal pemain selesai, satu transisi 0,32 detik membawa dunia
  ke gameplay framing sambil menampilkan Chrome.
- Battle dianggap mulai bagi pemain ketika transisi selesai dan input terbuka,
  walaupun session authoritative sudah aktif sebelumnya.
- Dialog command, final ace, victory, defeat, Trophy, dan result Boss setelah
  opening tidak berubah. Dialog command dan ace mempertahankan Chrome yang
  terlihat tetapi terkunci.
- Sequence berlaku untuk seluruh Boss Seeker Expedition, bukan hanya chapter
  atau Boss yang sekarang aktif.

### Replay, interruption, dan fallback

- Attempt Boss pertama memakai copy opening; retry zona memakai copy rematch
  dan memutar koreografi penuh.
- Continue, reconnect, replay event, transport retry, dan refresh encounter
  yang sama tidak memutar opening ulang.
- App yang masuk background tanpa mengganti view mempertahankan fase opening
  dan melanjutkannya saat kembali.
- Authoritative refresh untuk session yang sama membatalkan sequence lokal dan
  langsung berkumpul pada gameplay state yang lengkap: kedua Anima terlihat,
  framing gameplay aktif, Chrome sesuai state, dan input mengikuti session.
- Pergantian session, akun, mode, atau view membatalkan seluruh pekerjaan
  opening lama: dialog ditutup, portal dihentikan, callback usang diabaikan,
  dan tidak ada state lama yang dapat membuka input pada encounter baru.
- Boss opening memakai pagar cancellation/revision setara dengan Duel/Team
  Opening dan Expedition Opening. Satu coroutine lama tidak boleh menulis state
  setelah konteksnya berubah.
- Line opening kosong dilewati tanpa menampilkan dialog kosong. Seeker sheet
  atau portrait kosmetik yang gagal tersedia disembunyikan, dan sequence tetap
  berlanjut.
- Kegagalan art fighter yang memang membuat encounter belum layak dipresentasi
  tetap mengikuti Loading/error contract sekarang; fitur ini tidak menciptakan
  fallback art atau request baru.

### Dokumentasi

- Saat perubahan live, panduan pemain Battle diperbarui bersamaan dengan kode:
  Duel/Team Opening, Expedition Opening, Boss Encounter Opening, dan fakta bahwa
  Chrome melapisi Arena harus sesuai dengan build.
- Spesifikasi Team Battle/Expedition diperbarui untuk sequence Boss dan
  kontrak Arena/Chrome yang baru.
- Fakta arsitektur lintas mode dicatat singkat di `CLAUDE.md` setelah build
  benar-benar memakai kontrak baru. Riwayat rollout atau hasil visual QA masuk
  deploy log, bukan `CLAUDE.md`.
- README hanya diubah bila ringkasan UI aktifnya masih menyatakan atau
  mengasumsikan stage dan dock sebagai dua section. Dokumentasi tidak boleh
  mengklaim perubahan ini live sebelum implementasi selesai.

## Testing Decisions

Tes yang baik mengamati scene dan kontrol production seperti pemain:
rectangle Arena, visibility dan hit-testing Chrome, urutan figur yang terlihat,
transisi framing, input gate, serta state akhir setelah interruption. Tes tidak
mengunci nama helper privat, bentuk dictionary internal, atau urutan pemanggilan
fungsi selama hasil visual dan interaksinya sama.

**Dua automated seam yang sudah ada, tanpa test file baru:**

1. **Suite opening Battle (`test_battle_intro.gd`) adalah seam utama.** Suite
   ini sudah menjalankan scene Duel, Team Battle, dan Expedition sungguhan pada
   viewport ponsel. Perluas agar menjaga:
   - ukuran Arena identik sebelum, selama, dan sesudah Chrome tampil;
   - Duel/Team dimulai dengan Seeker pemain dan Anima lawan yang sudah terlihat,
     lalu hanya me-reveal Anima pemain;
   - Expedition Battle/Elite tetap me-reveal lawan lalu pemain;
   - Boss dimulai dengan dua Seeker dan nol Anima/Chrome;
   - beat 0,7 detik tidak menerima input;
   - dismiss dialog memicu Summon Boss lalu Summon pemain;
   - framing tidak snap pada tiap reveal;
   - transisi 0,32 detik berakhir dengan Chrome dan input aktif;
   - rematch memutar penuh, sedangkan Continue/refresh tidak;
   - cancellation session lama tidak dapat mengubah session baru;
   - missing line atau kosmetik tidak mengunci Battle.
2. **Suite UI shell (`test_scan_ui.gd`) menjaga kontrak yang melintasi view.**
   Gunakan scene production untuk memastikan:
   - Arena full-bleed di bawah safe area dan shell immersive;
   - Chrome berada di atas Arena dan tidak mengambil layout space;
   - transparent/hidden Chrome tidak menangkap input;
   - dialog, Switch/Item picker, konfirmasi, dan result berada di layer yang
     benar;
   - membuka atau menutup Overlay tidak mengubah rectangle atau gameplay
     framing Arena;
   - result mengganti command Chrome tanpa memindahkan pose akhir;
   - Battle Shake tidak menggerakkan Chrome;
   - assertion lama yang mewajibkan dock sebagai sibling di bawah stage
     dihapus atau diganti dengan kontrak overlay baru, bukan dipertahankan
     sebagai coverage paralel.

Pemeriksaan visual wajib memakai scene production pada portrait dan landscape,
minimal pada Duel, Team Battle, Expedition Battle/Elite, dan Expedition Boss. Ambil
keadaan opening tanpa Chrome, pertengahan transisi, gameplay dengan Chrome,
dialog/picker, dan result. Verifikasi:

- background menutup viewport tanpa gap;
- notch dan gesture inset tidak menutup target interaktif;
- kaki dan contact shadow tetap menempel pada lantai;
- Anima dan Seeker tidak tertutup HUD atau tombol;
- background parallax tidak membuat karakter tampak meluncur;
- reveal Boss dan pemain tidak memicu snap;
- Chrome tidak ikut Battle Shake;
- komposisi tetap terbaca untuk petarung kecil, lebar, dan sangat tinggi.

Seluruh suite Battle, UI, i18n, game rules, sprite slicing, combat parity, dan
Expedition route yang sudah menjadi pagar perubahan arena tetap dijalankan.
Tidak ada test backend, migrasi, deploy Edge Function, atau paid evaluation
karena kontrak server dan aset tidak berubah.

## Out of Scope

- Mendesain ulang visual, copy, ikon, ukuran tombol, atau susunan command
  Battle Chrome.
- Membuat Chrome baru yang tampak menyatu dengan dunia; spec ini hanya
  menyiapkan struktur layer agar redesign itu dapat dilakukan kemudian.
- Mengubah lobby Battle, rival picker, team builder, Expedition route map,
  chapter intro di peta, atau Loading Screen.
- Mengubah formula combat, action, PP, Energy, reward, EXP, Bits, Tokens,
  Trophy, AI, roster, atau urutan turn.
- Mengubah API, payload, database, idempotency, session lifecycle server, atau
  prediksi local-first.
- Menambah dialog, copy naratif, voice, musik, SFX, VFX, pose, Seeker Sheet,
  Anima art, background art, atau model call.
- Mengubah budget dialog Boss setelah opening atau koreografi final ace,
  victory, defeat, dan Trophy.
- Menambah tombol Skip Intro, preference Reduced Motion, atau variasi timing
  berdasarkan perangkat.
- Mengubah Expedition Opening selain cara Arena, framing, dan Chrome
  mempresentasikannya.
- Menyatukan seluruh implementasi Duel dan Team/Expedition ke satu view atau
  melakukan refactor combat yang tidak dibutuhkan oleh kontrak layer.
- Mengubah Home, Care, Scan, Collection, Atlas, Shop, atau admin console.

## Further Notes

- ADR-0003 dan istilah glossary adalah bagian normatif spec. Jika implementasi
  perlu mengembalikan footer yang mengambil tinggi Arena, hentikan dan revisi
  keputusan tersebut lebih dulu.
- Perubahan ini nol request jaringan, nol schema backend, nol model call, dan
  nol biaya generation.
- Background sumber tidak perlu digambar ulang. Framing runtime dan full-bleed
  cover harus mempertahankan kontrak ground contact aset yang sudah ada.
- Opening Boss memakai aset serta presenter existing. Nilai fitur berasal dari
  sequencing, framing, dan layer, bukan efek baru.
- Wiki tetap mendokumentasikan build live. Ia baru diperbarui dalam ticket
  implementasi yang mengaktifkan perilaku pemain ini, tidak pada tahap spec.
