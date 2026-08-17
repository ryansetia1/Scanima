# Evolution Silhouette Break v28

Status: desain dan implementasi lokal 18 Agustus 2026. Capture production
tetap v20, evolution production tetap v21, `feature_evolution=false`. Adult
Veridian v26 tetap terkunci.

## Masalah

Evolved v27 Veridian lolos Plan `mature` + `unfolding`, tetapi gambarnya
masih walker empat kaki berkanope yang sama dengan Adult. Detail bertambah;
kontur hitam tidak pindah. v26-a5 yang body-nya sempat disetujui justru
`coiling_crawl`, bukan walker.

Penyebab: attached Idle Adult menjadi composition blueprint, dan Plan
masih boleh menulis `pillar_stride` setelah `rooted_walk`. Validator
hanya menolak nama archetype yang sama, bukan keluarga gait yang sama.

## Kontrak v28

v28 = v27 plus `silhouette_break_contract`:

- `prior_silhouette_read`, `forbidden_copy`, `new_contour_read`,
  `topology_change`
- Evolved tidak boleh menyalin gait kaki Adult (`walk` / `stride` /
  `pillar-leg` / `rooted_walk`)
- Image: Idle adalah identity/warna/material, bukan limb count atau stance

Tidak mengubah Adult v26. Iterasi Evolved memakai Idle Adult v26.
Happy character cell dilarang sparkle/bintang terlepas (penyebab reject
teknis v26-a5 dan v27-a1).
