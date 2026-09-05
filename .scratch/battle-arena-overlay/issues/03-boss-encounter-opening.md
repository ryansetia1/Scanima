# 03: Boss Encounter Opening

**What to build:** Final Battle Expedition dibuka sebagai konfrontasi dua
Seeker: kedua Anima belum terlihat, Boss berbicara setelah jeda natural, lalu
Boss dan pemain memanggil Anima pertama mereka secara berurutan sebelum Battle
Chrome dan input muncul.

**Blocked by:** 02 (Team Battle dan Expedition reguler memakai kontrak overlay)

**Status:** ready-for-agent

- [ ] Boss Encounter Opening berlaku untuk setiap Expedition Boss, bukan hanya
      The Confectioner atau chapter aktif sekarang.
- [ ] Sequence baru dimulai setelah Loading Screen benar-benar hilang dan tidak
      berjalan tersembunyi di belakangnya.
- [ ] Shot pembuka hanya menampilkan background, contact shadow, Seeker Avatar
      pemain, dan Boss Seeker dalam pose idle; kedua Anima dan Battle Chrome
      belum terlihat.
- [ ] Camera memakai framing cinematic yang stabil dan sudah memperhitungkan
      kedua Anima tersembunyi, sehingga tiap Summon tidak menimbulkan snap.
- [ ] Ada beat diam 0,7 detik sebelum dialog; tap, confirm, Back, dan command
      Battle tidak melakukan apa pun selama beat itu.
- [ ] Dialog opening mempertahankan portrait, nama Boss, petunjuk continue, dan
      arena tanpa overlay gelap.
- [ ] Tap, confirm, atau Back menutup dialog lalu melanjutkan sequence tanpa
      meninggalkan encounter.
- [ ] Sesudah dialog, Boss Seeker mengambil pose Switch Command, mempertahankan
      command beat yang sudah ada, lalu portal dan reveal Anima Boss pertama
      dimainkan sebelum Boss kembali Idle.
- [ ] Tanpa tap atau delay tambahan, Seeker Avatar pemain mengambil pose Switch
      Command lalu portal dan reveal Anima pemain pertama dimainkan sebelum
      Seeker kembali Idle.
- [ ] Kedua Summon memakai pose, presenter, portal, VFX, SFX, musik, dan timing
      reveal yang sudah ada; tidak ada aset baru dan sequence tidak dapat
      di-skip setelah dialog ditutup.
- [ ] Setelah Anima pemain siap, seluruh dunia berpindah selama 0,32 detik ke
      framing gameplay sambil Battle Chrome fade-in; input baru terbuka setelah
      semuanya settle.
- [ ] Attempt pertama memakai dialog opening, sedangkan retry zona memakai
      dialog rematch dan memutar koreografi penuh.
- [ ] Continue, reconnect, event replay, transport retry, dan authoritative
      refresh encounter yang sama tidak memutar opening ulang.
- [ ] App yang masuk background lalu kembali ke view yang sama melanjutkan fase
      opening yang sedang berjalan.
- [ ] Refresh session yang sama membatalkan cinematic dan berkumpul pada Arena
      siap dengan kedua Anima, gameplay framing, Chrome, dan input yang sesuai
      state authoritative.
- [ ] Pergantian session, akun, mode, atau view menutup dialog, menghentikan
      portal, membatalkan pekerjaan lama, dan mencegah callback usang mengubah
      encounter baru.
- [ ] Cancellation mempunyai pagar revision setara opening reguler; coroutine
      Boss lama tidak dapat membuka input atau mengubah visibility setelah
      konteksnya berganti.
- [ ] Line dialog kosong dilewati, sedangkan Seeker sheet atau portrait
      kosmetik yang gagal dimuat disembunyikan tanpa mengunci Summon maupun
      Battle.
- [ ] Dialog command, final ace, victory, defeat, Trophy, result, dan budget
      bicara Boss setelah opening tidak berubah.
- [ ] Regression test scene production menjaga seluruh urutan visibility,
      timing, dismiss, input gate, replay, cancellation, dan fallback tanpa
      mengassert helper privat.
- [ ] Panduan pemain Battle dan spesifikasi Expedition diperbarui bersamaan
      dengan Boss Encounter Opening yang sudah live.
