# 07: Avatarku berdiri dan bereaksi di arena Duel

**What to build:** Hal yang sama seperti tiket 06, tapi di Duel — mode yang
paling sering dimainkan dan satu-satunya arena yang hari ini belum punya figur
Seeker sama sekali, sehingga di sinilah pekerjaan barunya paling banyak.

**Blocked by:** 06 (pola pose sisi pemain dibuktikan lebih dulu di arena yang
sudah punya layer figur dan presenter-nya).

**Status:** ready-for-agent

- [ ] Arena Duel mendapat layer figur dan presenter Seeker yang sama seperti
      Team Battle, dengan penempatan, arah hadap, ground line, dan urutan gambar
      yang setara.
- [ ] Pemetaan pose sisi pemain sama dengan yang sudah terbukti di tiket 06.
- [ ] Bot Duel tetap **tanpa** figur Seeker: rival Duel memang anonim, dan
      asimetri itu disengaja.
- [ ] Dock 2×2 Duel dan HUD-nya tidak tergeser, tidak tertutup, dan tidak
      berubah tinggi.
- [ ] Suite UI client menguji penempatan dan perubahan pose di Duel.
- [ ] `docs/wiki/battle.md` menyebut Duel juga, bukan hanya Team dan Expedition.
