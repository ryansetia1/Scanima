# 09: Empat figur sungguhan menggantikan placeholder

**What to build:** Roster placeholder ditukar dengan art final, sekali bayar,
**setelah** semua penempatan dan interaksi terbukti benar. Ini satu-satunya
tiket dalam fitur ini yang mengeluarkan uang, dan ia terakhir justru supaya
tidak ada generation yang dibayar dua kali karena layout ternyata salah.

**Blocked by:** 04, 05, 06, 07, 08 (seluruh surface sudah terbukti dengan art
placeholder).

**Status:** ready-for-agent

- [ ] Empat generation dijalankan sekali, satu per figur, sekitar $0.20–0.28
      total, **tanpa retry otomatis**. Kalau satu figur gagal, ulangi hanya
      figur itu secara eksplisit — jangan pernah membungkusnya dalam loop.
- [ ] Art mengikuti art direction Seeker Sheet yang sudah ada: siluet orisinal,
      warna cel flat, tanpa gradient atau glow, tanpa kemiripan franchise.
- [ ] Satu figur benar-benar terbaca netral sebagai **pilihan**, bukan sebagai
      siluet atau placeholder yang belum selesai (ADR-0001).
- [ ] Sheet dikeying, dislice, lolos pemeriksaan roster yang sama dari tiket 02,
      dan di-commit.
- [ ] Verifikasi visual di harness yang sudah ada, pada portrait dan landscape,
      untuk Profile maupun ketiga arena, sebelum tiket ditutup.
- [ ] Pertumbuhan ukuran build diukur. Kira-kira +3,2 MB sesuai ADR-0002; kalau
      ternyata jauh lebih besar, hentikan dan evaluasi ulang ADR itu alih-alih
      menerima angkanya diam-diam.
- [ ] `CLAUDE.md` mendapat satu baris di daftar fakta arsitektur, karena fitur
      ini baru sekarang live.
- [ ] Halaman wiki yang sudah ditulis di tiket 04 sampai 08 diperiksa masih
      akurat terhadap build.
