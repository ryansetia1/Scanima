# 04: Aku melihat dan mengganti Seeker Avatar-ku di Profile

**What to build:** Membuka Profile, aku melihat **diriku** di slot potret alih-
alih Anima peliharaanku, dan aku bisa mengganti figurnya kapan saja dari menu
yang sudah ada di layar itu — gratis, tanpa masa tunggu, dan langsung terlihat.

**Blocked by:** 01 (pagar locale key), 02 (Seeker Roster), 03 (penyimpanan).

**Status:** ready-for-agent

- [ ] Slot potret Profile menampilkan avatar terpilih memakai pose profil,
      menggantikan thumbnail Anima aktif yang ada di sana sekarang. `NULL`
      menggambar figur default.
- [ ] Aksi ganti avatar hidup di action popover Profile yang sudah ada, dan
      memunculkan picker yang menampilkan keempat figur sekaligus dengan yang
      aktif tertandai jelas.
- [ ] Memilih figur menulis pilihan lalu tampil optimistis, dan me-rollback
      kalau server menolak — tanpa meredupkan panel atau sheet-nya, mengikuti
      pola Care dan Shop.
- [ ] Tidak ada masa tunggu apa pun, dan mengganti avatar tidak menyentuh Seeker
      Demographics sedikit pun (ADR-0001).
- [ ] Top HUD tidak berubah: nama Seeker tetap teks tanpa ikon.
- [ ] Suite UI client menguji tiga hal pada scene sungguhan: potret memakai pose
      profil, picker menandai figur yang aktif, dan penggantian terlihat tanpa
      perlu membuka ulang layar.
- [ ] `docs/wiki/seeker.md` dibuat — apa itu Seeker Avatar, di mana ia terlihat,
      dan cara menggantinya — dan indeks wiki diperbarui. Tulis yang live di
      build, bukan rencana.
