# Evolution Kind Lock + Contour Delta v29

Status: desain dan implementasi lokal 18 Agustus 2026. Capture production
tetap v20, evolution production tetap v21, `feature_evolution=false`.
Adult Sunhound v28 dan Adult Veridian v26 tetap terkunci.

## Masalah

v28 memaksa Evolved meninggalkan gait kaki Adult (coil/tether/undulate).
Itu menambal Veridian walker-copy, lalu merusak Sunhound: Vision memilih
ular emas. Galon, tank, atau gedung akan kena jebakan yang sama.

Larangan keluarga gait bukan kontrak siluet. Ia spesifik kaki.

## Kontrak v29

v29 = v28 minus exile gait, plus dua pagar independen:

1. **Kind lock.** Form berikutnya tetap kategori benda yang difoto.
   `kind_noun` diulang di `source_kind_read` dan `continued_kind_read`.
   Anjing tetap hewan itu, galon tetap wadah, tank tetap kendaraan,
   gedung tetap arsitektur, tanaman tetap tanaman. Ganti kategori
   (serpent/worm/ooze/hewan lain) gagal meski outline baru.
2. **Contour delta.** Outline hitam 96 px wajib baru (massa, postur,
   proporsi, atau apendiks dari sumber). Salinan lebih tebal/tinggi/
   hias gagal. Kelas tumpuan yang sama **boleh** jika outline beda.
   Tidak ada larangan walk/stride. Coil tidak wajib.

Idle terlampir adalah identity, warna, material, **dan jenis benda**.

Tidak mengubah Adult yang sudah dikunci. Iterasi Evolved Sunhound
memakai Idle Adult v28 approved.
