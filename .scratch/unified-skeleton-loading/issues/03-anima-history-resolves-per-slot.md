# 03: History Anima resolve per slot

**What to build:** Evolution History dan Synthesis History mempertahankan
struktur yang stabil selama loading lalu menampilkan setiap art slot segera
setelah siap. Pemain dapat melihat source atau form yang sudah tersedia tanpa
menunggu download paling lambat dan tanpa row History dibongkar-pasang.

**Blocked by:** 01 (Collection membuktikan kontrak skeleton kanonis).

**Status:** ready-for-agent

- [ ] Synthesis History menampilkan source art cached secara langsung dan hanya
      memasang skeleton pada source yang benar-benar belum tersedia.
- [ ] Setiap source hasil download diterapkan dan crossfade sendiri selama 0,18
      detik tanpa menunggu source sibling.
- [ ] Evolution History mempertahankan jumlah slot dan arrow yang sesuai dengan
      committed stage selama metadata dan art dimuat.
- [ ] Slot Evolution stabil sepanjang transisi; konten final tidak mengganti
      seluruh row atau menumpuk node baru di atas skeleton lama.
- [ ] Metadata form yang sudah tersedia dapat tampil sementara art slot-nya
      tetap memakai skeleton kanonis.
- [ ] Setiap form art cached atau hasil download resolve secara independen tanpa
      mengulang animasi form yang sudah siap.
- [ ] Anima stage pertama tetap tidak menampilkan section Evolution History
      palsu.
- [ ] Cache-first, stale-response guard, session epoch, pergantian Anima, dan
      failure behavior yang sudah ada tetap berlaku.
- [ ] Test UI production menjaga partial cache, urutan resolve yang berbeda,
      jumlah slot dan arrow, crossfade settle, serta cleanup ketika Anima
      berganti di tengah request.
