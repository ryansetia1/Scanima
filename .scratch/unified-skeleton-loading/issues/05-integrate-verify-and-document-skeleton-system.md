# 05: Integrasikan, verifikasi, dan dokumentasikan sistem skeleton

**What to build:** Seluruh content skeleton yang disepakati terlihat dan
berperilaku sebagai satu sistem ketika dibandingkan di aplikasi utuh.
Perbedaan yang tersisa diperbaiki, seluruh jalur loading utama diverifikasi
pada layout ponsel, dan kontraknya dicatat agar screen berikutnya tidak
mengarang style sendiri.

**Blocked by:** 02 (Trophy Showcase resolve per kartu), 03 (History Anima
resolve per slot), 04 (Thumbnail Anima pulse dan crossfade di semua roster).

**Status:** ready-for-agent

- [ ] Collection Condition, Trophy Showcase, Evolution History, Synthesis
      History, dan thumbnail async memakai satu keluarga warna, radius, border,
      spacing, pulse, serta timing resolve.
- [ ] Geometri setiap skeleton tetap content-aware dan tidak menyebabkan layout
      jump saat berubah menjadi konten final.
- [ ] Cache-first, progressive per-slot resolve, crossfade 0,18 detik, dan
      fallback statis setelah failure terlihat konsisten pada seluruh target.
- [ ] Visual QA dilakukan pada viewport portrait dan landscape memakai harness
      atau scene production untuk seluruh target, dan temuan in-scope
      diperbaiki sebelum ticket selesai.
- [ ] Audit memastikan tidak ada tile abu-abu atau art slot kosong yang masih
      berfungsi sebagai loading placeholder pada target yang disepakati.
- [ ] Audit memastikan full-screen loader, Synthesis sweep, incubator, Scan
      overlay, Atlas shimmer, Battle loading copy, dan button busy tidak ikut
      berubah menjadi content skeleton.
- [ ] Suite UI client lengkap lulus, termasuk kontrak touch-scroll dan
      selection roster yang sudah ada.
- [ ] Dokumentasi UI internal menjelaskan definisi content skeleton, primitive
      kanonis, cache-first, progressive resolve, crossfade, failure fallback,
      serta pengecualian indikator operasional.
- [ ] Spesifikasi UI Collection menjelaskan thumbnail skeleton dan failure
      fallback yang live tanpa memindahkan detail implementasi ke panduan
      pemain.
- [ ] Wiki pemain, glossary domain, ADR, dan dokumentasi lintas-domain tidak
      diubah karena mekanisme permainan tetap sama.
