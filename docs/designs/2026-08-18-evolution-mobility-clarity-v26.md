# Evolution Mobility v26

Status: Adult v26 disetujui operator 18 Agustus 2026. Artefak terkunci di
`eval/results/evolution-veridian-adult-v26-approved/` (gitignored). Evolved
masih diiterasi dari Idle Adult itu. Capture production tetap v20, evolution
production tetap v21, dan `feature_evolution=false`.

## Masalah v25

Paid Adult Veridian v25 lulus teknis 9/9 sel + seam. Soul dua mata, senyum,
dan daun fenestrasi aman. Yang ditolak hanya mobility: tubuh terbaca kolom
daun di atas gundukan akar/batu, terpatri di tanah. Hop Home dan gerak Battle
akan aneh pada tubuh yang menyatu dengan base.

Draft v26 sebelumnya menambahkan Shape Budget tepat dua, `detail_zones=[]`,
dan gate detached ekstra. Itu di luar permintaan; v26 sekarang hanya menambah
kontrak mobility di atas v25.

## Kontrak v26

V26 = v25 + `mobility_contract`. Shape Budget tetap 2–3 primary shapes.

Setiap Adult/Evolved wajib terlihat bisa hop, walk, roll, crawl, leap, atau
reposition. Aturan ini anatomy-agnostic: tanaman, pot, patung, furnitur,
peralatan, objek dinding, dan sumber diam lain harus menurunkan sistem gerak
dari fitur sumber yang sudah ada. Sumber yang sudah mobile memperjelas gait-nya.

Plan wajib menulis:

- `locomotion_mode`
- `source_derivation`
- `support_geometry`
- `movement_read`
- `idle_stability`
- `battle_mobility`

Idle boleh menyentuh tanah di beberapa titik tumpu terpisah, tetapi negative
space di bawah tubuh atau di antara tumpuan wajib terlihat. Mengganti satu
base diam dengan base diam lain (pot → gundukan, stand → stump, bracket →
plinth) gagal. `changed_dimensions` wajib memuat `locomotion_or_body_plan`.

Post-process `>= v26` tetap menolak detached mark di character cells selain
maksimal dua Z Sleep. Itu pagar teknis, bukan perubahan art direction.

## Paid eval Adult

- Reference: Hatchling Veridian Idle yang sama.
- Vision `btj0466pqsrmr0d023tryp7t7r`, 30 detik.
- GPT Image 2 medium `hp42d9er7srmw0d023v834e7zw`, 74 detik.
- Estimasi konservatif $0,073. Tidak ada image retry. Vision tidak diulang;
  lantai `locomotion_mode` diturunkan 12→4 karena `"rooted_walk"` tertolak.
- Plan `rooted_to_mobile` / `rooted_walk`, tiga primary shapes termasuk
  `root_limbs`, negative space di bawah tubuh.
- 9/9 sel, seam lulus, detached lulus, standing variance 1,5%.
- Broad green residue 2,45% dari tubuh plant. Character-cell bright-chroma
  hampir nol; 177/200 piksel bright ada di `fx_surge`.
- Pot dan gundukan batu Hatchling hilang. Idle berdiri di empat tumpuan
  terpisah. Operator menyetujui Adult ini 18 Agustus 2026; sheet terkunci
  untuk iterasi Evolved. Jangan menimpa arsip itu.

### Evolved

Vision pertama dari Adult approved (`t5bmhnfcfdrmt0d023xtt9acg4`, 32 detik)
ditolak validator sebelum image: Identity Invariants mata dihapus, satu
detail zone ditambah, dan `mobility_contract` kembali ke root-mass yang
menyatu dengan tanah. Tidak ada generation gambar.

## Rollout

Urutan gate:

1. paid Adult v26 lulus visual mobility tanpa merusak soul/clarity v25;
2. generate Evolved dari Adult approved;
3. baru deploy prompt/function, client minimum, backfill, dan flag.

Tidak ada retry image otomatis. Wiki pemain tidak berubah sampai evolusi live.
