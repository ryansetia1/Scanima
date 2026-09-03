# 06: Avatarku berdiri dan bereaksi di arena Team Battle dan Expedition

**What to build:** Saat bertarung, aku melihat diriku berdiri di sisiku
menghadapi lawan — memberi perintah saat aku menyerang, khawatir saat Anima-ku
terkena, dan menang atau kalah bersamaku. Selama ini hanya Boss Seeker yang
punya wujud di arena; tiket ini menutup ketimpangan itu di dua mode yang
infrastruktur figurnya sudah ada.

**Blocked by:** 02 (Seeker Roster), 03 (penyimpanan, supaya figur yang tampil
adalah yang dipilih; `NULL` menggambar default sehingga tiket ini tetap
demoable tanpa picker).

**Status:** ready-for-agent

- [ ] Figur pemain berdiri di sisi pemain sejauh Boss Seeker berdiri di sisi
      lawan, pada ground line yang sama, di belakang Anima pemain dalam urutan
      gambar, dan menghadap ke arah lawan.
- [ ] Saat kamera zoom, figur terjepit ke tepi layar sisi pemain, mencerminkan
      penjepitan Boss Seeker ke tepi seberang.
- [ ] Pose mengikuti event **sisi pemain**: pose perintah saat Attack, Special,
      dan Switch; pose khawatir saat Anima pemain terkena; pose menang atau
      kalah di penutup; kembali idle di antaranya. Pemetaan dimiliki view, bukan
      presenter — sama seperti pemisahan yang sudah berlaku untuk Boss Seeker.
- [ ] Seeker Avatar pemain tidak memakai panel dialog dan tidak pernah bicara.
- [ ] Figur tidak menutupi Anima pemain maupun dock aksi, pada portrait maupun
      landscape, dan tidak menggeser HUD arena.
- [ ] Suite UI client menguji penempatan, arah hadap, dan perubahan pose pada
      event, memakai fixture sheet Seeker in-memory yang sudah ada di suite itu.
- [ ] `docs/wiki/battle.md` menyebut kehadiran avatar pemain di arena.
