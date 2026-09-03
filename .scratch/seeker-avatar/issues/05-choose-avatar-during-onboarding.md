# 05: Aku memilih Seeker Avatar-ku saat onboarding

**What to build:** Saat menamai Seeker-ku untuk pertama kali, aku sekalian
memilih wujudnya di sheet yang sama — karena "siapa aku" semestinya diputuskan
sekali, bukan tersebar di dua layar. Figur default sudah terpilih, jadi kalau
aku tidak peduli aku bisa langsung menekan selesai dan kembali ke Anima
pertamaku.

**Blocked by:** 01 (pagar locale key), 03 (penyimpanan), 04 (picker-nya lahir di
Profile dan dipakai ulang di sini).

**Status:** ready-for-agent

- [ ] Satu baris picker ditambahkan ke bottom sheet onboarding yang sudah ada.
      Tetap satu submit; tidak ada langkah wizard baru.
- [ ] Figur default sudah terpilih saat sheet terbuka, sehingga picker tidak
      pernah bisa memblokir penyelesaian onboarding.
- [ ] Avatar dikirim sebagai argumen **opsional** saat profil diselesaikan,
      mengikuti pola yang sudah dipakai birth year dan gender.
- [ ] Jawaban gender tidak memengaruhi figur yang terpilih, dan memilih figur
      tidak mengubah jawaban gender (ADR-0001).
- [ ] Suite UI client menguji pada scene sungguhan: default terpilih saat sheet
      dibuka, submit tanpa menyentuh picker tetap berhasil, dan memilih figur
      lain benar-benar terkirim.
- [ ] `docs/wiki/seeker.md` menyebut bahwa avatar dipilih saat onboarding dan
      bahwa penggantiannya gratis kapan saja.
