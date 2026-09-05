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
- [ ] Opening Team Battle dan Expedition Battle/Elite mempertahankan urutan
      lawan lalu pemain, memakai framing cinematic tanpa Chrome, dan beralih
      selama 0,32 detik ke framing gameplay sebelum input terbuka.
- [ ] Framing tidak snap ketika masing-masing Anima di-reveal, termasuk ketika
      ukuran kedua fighter sangat berbeda.
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
