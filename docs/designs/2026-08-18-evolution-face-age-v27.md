# Evolution Face Age v27

Status: desain dan implementasi lokal 18 Agustus 2026. Belum ada eval
visual yang disetujui. Capture production tetap v20, evolution production
tetap v21, `feature_evolution=false`. Adult Veridian v26 tetap terkunci.

## Masalah

Evolved v26 Veridian hampir lulus, tetapi mata Hatchling/Adult/Evolved
tetap satu stiker almond besar. Body plan sudah berubah; usia wajah tidak.
v24–v25 sudah menolak wajah Adult yang tersalin, lalu v26 hanya memperbaiki
mobilitas.

Penyebab di kontrak: Adult `source_truth` membekukan “Two large,
almond-shaped eyes”, validator menyalin teks itu ke Evolved, dan image
prompt menaruhnya di PRESERVE. `maturation_path` hanya minta “lebih
angular.”

## Pola yang dipakai

Tiga tahap starter memakai Kindchenschema lalu menggeser rasio
mata-ke-wajah, konstruksi mata, dan massa kraniofasial, sambil menjaga
jumlah mata dan karakter pandang. Mature bukan marah.

## Kontrak v27

v27 = v26 plus `face_age_contract`:

- `age_read`: Adult `adolescent`, Evolved `mature`
- `eye_to_face_ratio`, `eye_construction`, `craniofacial_mass`,
  `mouth_to_eye_relationship`, `prior_copy_forbidden`

Soul tetap count/pairing/role. Size words di `source_truth` tidak
mengalahkan face age. Image prompt mewajibkan menggambar ulang wajah,
bukan menempel mata referensi.

Tidak mengubah Adult v26 yang sudah disetujui. Iterasi Evolved memakai
Idle Adult v26 sebagai image input.
