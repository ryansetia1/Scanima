# 02: Seeker Roster hadir sebagai art ter-bundel yang terperiksa

**What to build:** Empat figur Seeker Roster ada di dalam build sebagai Seeker
Sheet placeholder yang digambar lokal tanpa biaya, dan ada satu pemeriksaan yang
langsung gagal begitu sebuah slug tidak punya sheet atau sebuah sheet tidak
memenuhi kontrak sembilan pose. Belum ada UI apa pun di tiket ini; yang
dihasilkan adalah fondasi art beserta pagarnya.

**Blocked by:** 01 (prefactor: rename kelas art Seeker).

**Status:** ready-for-agent

- [ ] Empat slug roster terdefinisi di satu tempat di client: satu figur
      androgini sebagai default, satu maskulin, satu feminin, satu automaton.
      Slug berupa teks yang menjelaskan dirinya, bukan indeks angka.
- [ ] Empat sheet placeholder dihasilkan tanpa satu pun panggilan API, dengan
      sembilan sel yang bisa dibedakan satu dari yang lain sehingga kesalahan
      pemetaan pose terlihat mata, dan ikut ter-bundel ke build.
- [ ] Kontrak Seeker Sheet tidak diubah sedikit pun: grid 3×3, sembilan nama
      pose yang sama seperti Boss Seeker, manifest v1, chroma green.
- [ ] Suite art mengassert setiap slug roster punya sheet yang benar-benar
      ter-bundel dan lolos build sembilan pose; menghapus satu sheet atau
      menambah slug tanpa sheet membuatnya merah.
- [ ] Komentar `ponytail:` menyebut plafonnya — di atas sekitar enam figur,
      pindahkan pengiriman art ke pola aset chapter (ADR-0002).
