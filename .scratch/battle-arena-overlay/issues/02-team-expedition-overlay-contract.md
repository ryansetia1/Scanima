# 02: Team Battle dan Expedition reguler memakai kontrak overlay

**What to build:** Team Battle serta encounter Battle/Elite Expedition memakai
Battle Arena full-screen dan Battle Chrome overlay yang sama dengan Duel,
tanpa mengubah command, roster, Switch, result, atau alur Expedition yang sudah
dikenal pemain.

**Blocked by:** 01 (Duel memakai Battle Arena full-screen)

**Status:** ready-for-agent

- [ ] Team Battle dan combat Expedition memakai Battle Arena full-screen yang
      tidak lagi menjadi baris di atas action dock.
- [ ] Fighter HUD, team pips, status encounter, action dock, Switch, Item, dan
      Retreat menjadi Battle Chrome yang tidak mengambil ukuran layout Arena.
- [ ] Kontrak overlay berlaku pada Team Battle, Expedition Battle, Expedition
      Elite, dan fondasi arena Boss; Boss Encounter Opening baru tetap dimiliki
      ticket 03.
- [ ] Background full-bleed, safe area, zona occlusion, ground contact, dan
      framing karakter mengikuti kontrak yang sudah dibuktikan oleh Duel.
- [ ] Team Battle memakai Duel/Team Opening yang sama dengan Duel: Seeker
      pemain dan Anima lawan aktif sudah terlihat saat shot awal, lalu hanya
      Anima pemain yang dipanggil setelah beat 0,4 detik dan pose command 0,42
      detik.
- [ ] Anima lawan Team Battle tidak memakai portal atau entrance. Portal,
      reveal, VFX, dan SFX existing hanya dipakai untuk Anima pemain.
- [ ] Expedition Battle/Elite tetap memakai Expedition Opening: Seeker pemain
      berdiri sendiri, lalu Anima lawan dan Anima pemain di-reveal berurutan.
- [ ] Framing tidak snap ketika Anima pemain Team Battle atau kedua Anima
      Expedition di-reveal, termasuk ketika ukuran fighter sangat berbeda.
- [ ] Team Battle dan Expedition beralih selama 0,32 detik ke framing gameplay
      dan Chrome sebelum input terbuka.
- [ ] Setiap session Team Battle baru, termasuk Battle Again, memutar opening;
      Continue, reconnect, authoritative refresh, dan transport retry session
      yang sama tidak memutarnya ulang.
- [ ] Sheet Seeker Avatar yang tidak tersedia tidak menghambat summon Anima
      pemain maupun pembukaan input.
- [ ] Camera gameplay menghindari HUD dan kontrol tanpa mengecilkan Arena;
      background tetap boleh terlihat di belakang Chrome.
- [ ] Switch sukarela, forced Switch, dan pergantian fighter tetap melakukan
      reframe yang sudah ada tanpa mengubah rectangle Arena atau membuat Chrome
      ikut bergerak.
- [ ] Dialog, Switch picker, Item picker, konfirmasi Retreat, dan result menjadi
      Battle Overlay atau Chrome state yang tidak me-resize Arena.
- [ ] Dialog tengah Battle mempertahankan Chrome yang terlihat tetapi terkunci;
      menutup dialog atau picker tidak mengembalikan framing cinematic.
- [ ] Result menyembunyikan command Chrome, mempertahankan pose dan framing
      akhir, serta tetap menawarkan CTA mode yang sama seperti sekarang.
- [ ] Battle World Shake mengguncang fighter dan scenery tanpa menggerakkan
      HUD, action dock, dialog, picker, atau result.
- [ ] Team builder, rival lobby, Expedition route map, chapter intro, dan
      Loading Screen tidak berubah layout atau alurnya.
- [ ] Scene production diverifikasi pada portrait dan landscape untuk Team,
      Expedition Battle, Expedition Elite, dan arena Boss dengan ukuran fighter
      kecil, lebar, dan tinggi.
- [ ] Regression test opening dan shell mengganti assertion lama yang
      mewajibkan dock berada di bawah stage dengan kontrak overlay dan rectangle
      Arena yang konstan.
- [ ] Panduan pemain Battle diperbarui untuk Team Battle dan Expedition reguler
      bersamaan dengan perilaku yang sudah live.
