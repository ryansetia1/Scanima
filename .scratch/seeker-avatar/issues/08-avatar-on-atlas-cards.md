# 08: Pemain lain melihat Seeker Avatar-ku di kartu Atlas

**What to build:** Kartu Atlas hasil duel yang sudah menampilkan namaku sekarang
juga menampilkan wujudku, digambar dari art yang sudah ada di perangkat sehingga
menjelajah Atlas tidak jadi lebih lambat sedikit pun. Yang **tidak** berubah:
roster rival tetap anonim seperti sekarang.

**Blocked by:** 02 (Seeker Roster, art lokalnya), 03 (kolom yang dibaca).

**Status:** ready-for-agent

- [ ] Payload kartu Atlas membawa avatar pemilik **hanya** pada kartu yang
      memang sudah menampilkan nama pemilik. Tidak ada surface baru yang dibuka.
- [ ] Kartu menggambarnya kecil dari art lokal: nol permintaan jaringan tambahan
      per kartu, termasuk untuk avatar pemain lain.
- [ ] Slug yang tidak dikenal client jatuh ke figur default alih-alih kosong
      atau error — supaya menambah figur di server tidak memecahkan client lama.
- [ ] Payload roster rival Duel dan Team Battle tetap tanpa field pengidentifikasi
      pemilik, dan ada assert yang membuktikannya masih begitu sesudah tiket ini.
- [ ] `docs/wiki/atlas.md` menyebut avatar yang tampil di kartu.
