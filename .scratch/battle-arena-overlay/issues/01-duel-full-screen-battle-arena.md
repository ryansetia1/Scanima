# 01: Duel memakai Battle Arena full-screen

**What to build:** Saat Duel aktif, dunia Battle memenuhi layar dan Battle
Chrome melapisinya tanpa mengambil tinggi Arena. Opening Duel memanfaatkan
framing cinematic tanpa gap bawah, lalu beralih halus ke framing gameplay
sebelum pemain dapat memberi perintah.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Background Duel memenuhi viewport encounter sampai di belakang area
      aman perangkat; tidak ada footer transparan atau pita kosong yang
      mengurangi ukuran Battle Arena.
- [ ] Status fighter, status encounter, command, Item, dan Retreat menjadi
      Battle Chrome di atas Arena dan tidak mengubah rectangle Arena ketika
      muncul, disembunyikan, atau dinonaktifkan.
- [ ] Background boleh terlihat di belakang Chrome, sementara wajah, badan
      utama, kaki, contact shadow, feedback penting, dan kontrol interaktif
      tetap berada di area baca yang aman.
- [ ] Duel/Team Opening dimulai dengan Seeker Avatar pemain dan Anima lawan
      aktif yang sudah Idle beserta contact shadow; Anima pemain dan Chrome
      masih tersembunyi.
- [ ] Sesudah beat 0,4 detik, Seeker memakai pose Switch Command selama 0,42
      detik lalu memanggil Anima pemain dengan portal, reveal, VFX, dan SFX
      existing. Anima lawan tidak memakai entrance atau portal.
- [ ] Framing cinematic sejak shot awal sudah memperhitungkan Anima pemain
      tersembunyi, sehingga reveal tidak membuat camera snap.
- [ ] Setelah Anima pemain siap, seluruh dunia berpindah selama 0,32 detik ke
      framing gameplay sambil Chrome fade-in.
- [ ] Input tetap terkunci sampai framing dan Chrome selesai settle; Chrome
      tersembunyi tidak menerima pointer, focus, Back, atau shortcut.
- [ ] Setiap session Duel baru, termasuk Battle Again, memutar opening;
      Continue, reconnect, authoritative refresh, dan transport retry session
      yang sama langsung kembali ke gameplay.
- [ ] Sheet Seeker Avatar yang tidak tersedia tidak menghambat portal, reveal
      Anima pemain, transition, atau pembukaan input.
- [ ] Camera, background, ground line, Anima, Seeker, shadow, dan portal tetap
      bergerak sebagai satu dunia tanpa kaki meluncur di atas lantai.
- [ ] Membuka Item, konfirmasi Retreat, atau result tidak mengubah ukuran Arena
      maupun framing gameplay.
- [ ] Result menyembunyikan command Chrome dan melapisi pose akhir tanpa
      memindahkan fighter.
- [ ] Battle World Shake tetap hanya mengguncang dunia; Chrome dan Overlay
      tidak ikut bergerak.
- [ ] Perilaku dibuktikan melalui scene production pada portrait dan landscape
      serta regression test opening dan shell yang mengukur hasil visual dan
      input, bukan helper privat.
- [ ] Panduan pemain Battle diperbarui pada bagian Duel bersamaan dengan
      perubahan yang sudah live di build.
