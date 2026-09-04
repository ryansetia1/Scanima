# 04: Thumbnail Anima pulse dan crossfade di semua roster

**What to build:** Thumbnail Anima yang belum tersedia memakai skeleton
beranimasi dengan bahasa visual yang sama di Collection, picker Battle,
Team Battle, Expedition, Synthesis, dan surface portrait. Saat art tiba,
placeholder berubah halus menjadi thumbnail tanpa mengganti kontrol list atau
perilaku touch yang sudah matang.

**Blocked by:** 01 (Collection membuktikan kontrak skeleton kanonis).

**Status:** ready-for-agent

- [ ] Cache miss menghasilkan texture skeleton rounded dengan token dan pulse
      yang sama seperti primitive kanonis, bukan tile abu-abu polos.
- [ ] State thumbnail dikoordinasikan per cache key sehingga semua surface yang
      menampilkan Anima yang sama menerima loading, resolve, dan final art yang
      konsisten.
- [ ] Cache hit dari memory atau disk langsung menampilkan thumbnail final tanpa
      pulse atau minimum display duration.
- [ ] Download sukses menjalankan crossfade enam frame selama 0,18 detik lalu
      berhenti pada texture final dan melepaskan frame sementara.
- [ ] Download dan retry tetap memakai antrean, attempt cap, dan network
      behavior yang sudah ada; tidak ada request atau retry baru.
- [ ] Selama request atau retry masih mungkin, skeleton pulse. Setelah attempt
      ketiga gagal, pulse berhenti pada fallback skeleton statis.
- [ ] Seluruh `ItemList` production tetap dipakai; drag-scroll, press
      selection, urutan tap, deselect, level badge, dan dim state tidak berubah.
- [ ] Texture yang sama bekerja pada ukuran icon roster yang berbeda dan pada
      surface portrait tanpa stretch atau crop yang tidak sesuai.
- [ ] Pergantian akun/session membatalkan resolve lama, membersihkan resource
      animasi, dan mencegah thumbnail UID sebelumnya muncul.
- [ ] Test UI memakai list dan provider production untuk menjaga pulse,
      crossfade, static failure, cache-first, cleanup, serta seluruh kontrak
      touch/selection yang sudah ada.
