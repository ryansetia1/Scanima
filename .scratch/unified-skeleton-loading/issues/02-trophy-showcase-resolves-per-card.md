# 02: Trophy Showcase resolve per kartu

**What to build:** Trophy Showcase memakai kontrak skeleton kanonis dari
metadata pertama sampai art tiap trophy siap. Pemain tidak lagi melihat slot
kosong di antara datangnya daftar trophy dan PNG, sementara kartu cached dan
download yang selesai lebih cepat dapat tampil tanpa menunggu sibling.

**Blocked by:** 01 (Collection membuktikan kontrak skeleton kanonis).

**Status:** ready-for-agent

- [ ] Showcase tanpa cache menampilkan tiga placeholder content-aware dengan
      visual dan pulse kanonis.
- [ ] Setelah metadata tiba, grid dan label trophy boleh tampil tetapi setiap
      art slot yang belum memiliki texture tetap memegang skeleton sendiri.
- [ ] Art cached tampil langsung tanpa skeleton, crossfade palsu, atau flash.
- [ ] Setiap PNG hasil download resolve secara independen melalui crossfade
      alpha 0,18 detik; satu kartu lambat tidak menahan kartu lain.
- [ ] Resolve satu kartu tidak mengubah ukuran showcase, menggeser kartu lain,
      atau mengulang animasi kartu yang sudah siap.
- [ ] Empty showcase dan kegagalan definitif mempertahankan behavior yang sudah
      ada serta tidak meninggalkan pulse tanpa pekerjaan aktif.
- [ ] Navigasi keluar atau pergantian session saat download berlangsung tidak
      membiarkan callback lama menulis ke kartu yang sudah tidak valid.
- [ ] Test UI production menjaga jalur tanpa cache, partial cache, progressive
      per-card resolve, empty state, failure cleanup, dan hasil akhir tanpa
      skeleton bertumpuk.
