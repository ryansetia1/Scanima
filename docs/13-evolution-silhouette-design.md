# 13 — Evolution Silhouette Language

Status: desain dan implementasi v22 repo selesai 17 Agustus 2026. Capture tetap
v20 dan pengalaman pemain tetap gated. Adult Monstera v22 sudah disetujui.
Evolved pertama membuktikan siluet lineage tetapi ditolak teknis karena
near-chroma green dan ditolak visual karena dua mata ekspresif berubah menjadi
satu aperture tanpa character read. V23 kemudian mempertahankan soul dan siluet,
tetapi ditolak karena belum terasa matang/megah sebagai final evolution serta
masih memiliki bright-chroma. V24 memperbaiki maturity dan presence, tetapi
Adult/Evolved terlalu detail, focal face Evolved masih terlalu dekat dengan
Adult, dan aura Idle melanggar seam. Desain penggantinya adalah Shape Budget +
Pokémon-like Visual Clarity v25. Paid Adult Veridian lulus teknis 9/9 sel +
seam, tetapi visual masih kolom daun di atas gundukan akar/batu. Desain v26
menambah mobility anatomy-agnostic tanpa mengubah Shape Budget v25. Paid Adult
v26 disetujui operator; Evolved masih diiterasi dari sheet Adult itu.
V27 menambah face-age craniofacial contract di atas v26.
Paid Evolved v27 masih siluet walker Adult. V28 mengunci silhouette break
(coil/tether) supaya Evolved tidak menyalin gait kaki Adult. Paid Evolved
Sunhound v28 lulus teknis lalu **visual reject**: limbless coil terbaca ular.
V29 mengganti exile gait dengan kind lock + contour delta yang berlaku untuk
hewan, galon, tank, maupun gedung.

## Mengapa v21 ditolak

Eval Adult Veridian/Monstera v21 menjalankan satu Vision Plan dan satu GPT Image
2 medium. Hasil teknisnya sehat: 9/9 sel, seam lulus, Vision 10 detik, generation
70 detik, estimasi biaya konservatif $0.073. Namun art direction gagal.

Form baru mempertahankan komposisi yang sama: pot di bawah, wajah di tengah, dan
tiga massa daun radial. Perubahannya hanya daun lebih banyak, akar terlihat, dan
pot retak. Ia terbaca sebagai detail upgrade, bukan evolusi.

Penyebabnya ada di kontrak v21:

- Vision diminta membuat Adult bridge dengan hanya satu atau dua upgrade.
- Prompt gambar mengunci facial structure, limb count, body-plan logic, dan
  structural features lama sekaligus.
- Tiga anchor wajib “survive”, tetapi tidak wajib bertransformasi.
- Tidak ada kontrak yang memindahkan dominant mass, posture, locomotion, atau
  outer contour.

Technical QA bukan bukti visual evolution berhasil. Kandidat v21 ini ditolak
untuk promosi.

## Understanding summary

- Hatchling, Adult, dan Evolved masing-masing harus punya body plan dan siluet
  yang langsung berbeda pada ukuran thumbnail.
- Lineage dijaga oleh dua–tiga motif struktural, material, palet, dan character
  essence—bukan anatomi lama secara utuh.
- Benda asal boleh berubah fungsi; komponen literal tidak wajib tetap literal.
- Anatomi baru boleh tumbuh dari bagian lama yang dapat ditunjuk.
- Adult dan Evolved masing-masing membutuhkan satu faktor wow dan metamorfosis
  utama yang berbeda.
- Runtime tetap satu Vision Plan dan satu image generation tanpa auto-retry.
- Nama, gambar, karakter, kostum, atau komposisi franchise tidak masuk prompt
  maupun image input. Referensi hanya diterjemahkan menjadi prinsip abstrak.

## Evolution Plan v22

Capture prompt tetap v20. V22 hanya mengubah
`vision_evolve_system`, `vision_evolve_schema`, dan
`sprite_sheet_evolve`.

Tiga lineage anchor berubah dari string menjadi transformasi terstruktur:

```jsonc
{
  "lineage_anchors": [
    {
      "source_feature": "fenestrated leaf openings",
      "next_expression": "a split canopy contour with the same openings",
      "mode": "retain"
    },
    {
      "source_feature": "round ceramic pot",
      "next_expression": "a compact torso core built from ceramic segments",
      "mode": "transform"
    },
    {
      "source_feature": "fibrous roots",
      "next_expression": "four weight-bearing root limbs",
      "mode": "transform"
    }
  ],
  "transformation_archetype": "rooted_to_mobile",
  "metamorphosis_thesis": "A stationary potted sprout becomes a mobile canopy guardian.",
  "changed_dimensions": [
    "dominant_mass",
    "outer_contour",
    "locomotion_or_body_plan"
  ],
  "dominant_mass_shift": "radial top-heavy canopy to forward-driving torso and rear canopy",
  "posture_change": "stationary squat to low mobile stance",
  "outer_contour_change": "round radial crown to long asymmetric wedge",
  "locomotion_or_body_plan_change": "roots become load-bearing limbs",
  "derived_anatomy": [
    {
      "new_part": "root limbs",
      "derived_from": "visible fibrous roots",
      "source_anchor_index": 3
    }
  ]
}
```

Allowlist archetype awal sengaja kecil:

- `breakout`
- `unfolding`
- `inversion`
- `rooted_to_mobile`
- `shell_shedding`
- `mass_redistribution`

Validator mewajibkan:

1. Tepat tiga anchor non-duplikat.
2. Minimal dua anchor memakai `mode=transform`.
3. Minimal dua dari empat dimensi berubah: dominant mass, posture, outer
   contour, locomotion/body plan.
4. Anatomi baru menunjuk indeks anchor `transform`; `derived_from` wajib identik
   case-insensitive dengan `source_feature` anchor itu supaya tidak bisa muncul
   sebagai upgrade generik.
5. Evolved tidak memakai archetype utama Adult.
6. Seluruh aturan tinggi, move name, VFX, dan effect allowlist lama tetap
   berlaku.

Field deskriptif tidak dipakai untuk menghitung combat. Ia hanya mengunci arah
desain sebelum generation berbayar.

## Kontrak prompt gambar

Urutannya berubah menjadi **silhouette first, detail second**. Model lebih dulu
membangun satu body plan dari `metamorphosis_thesis`, lalu menerapkan material,
palet, ekspresi, pose, dan shading.

Yang tetap dikunci lintas stage:

- tiga anchor beserta hasil transformasinya;
- keluarga material dan palet;
- character essence;
- facing lock dan kontrak teknis sheet.

Yang tidak lagi wajib identik:

- facial geometry dan lokasi wajah;
- limb count;
- proporsi;
- body-plan logic;
- distribusi massa.

Prompt melarang:

- outer contour Idle yang sama;
- susunan massa yang sama dengan reference;
- form lama yang hanya diberi aksesori atau detail;
- perubahan yang hanya berupa lebih besar, lebih banyak, lebih tebal, retak,
  glow, atau generic armor;
- generic dragon, humanoid, robot, atau cyborg sebagai shortcut.

Tujuh pose tetap menggambar individu baru yang sama. Kebebasan perubahan hanya
berlaku antar-stage, bukan antar-sel dalam satu sheet.

## Runtime dan kompatibilitas

Alur tidak menambah round trip:

```text
Idle privat
  → Vision Plan v22
  → validator silhouette delta
  → satu image generation
  → chroma/seam/pose QA
  → commit atomik
```

Plan invalid berhenti sebelum image generation. Output gambar yang gagal QA
teknis tetap memakai rollback yang sudah ada. Tidak ada visual similarity hard
gate di runtime karena satu generation sudah dibayar dan pixel heuristic terlalu
rapuh untuk menjadi otoritas.

Untuk Evolved, Edge Function membaca Plan Adult dari `generations.vision_result`
untuk generation sukses `target_stage=2`, lalu mengirim archetype serta
transformasi sebelumnya ke Evolution Director. `anima_forms` hanya menyimpan
form lama ketika stage berikutnya berhasil commit, jadi ia belum memuat Adult
saat ritual Evolved dimulai. Plan v21 lama tanpa field baru memakai
`prior_archetype=unknown`; saat desain ini ditulis belum ada form Adult
production.

Privasi, idempotency, lease, spend cap, no-Core policy, dan cleanup reference
tidak berubah.

## Visual review

Eval v22 menghasilkan panel:

1. reference berwarna;
2. silhouette hitam reference pada 96 px;
3. Idle baru;
4. silhouette hitam baru pada 96 px;
5. sheet sembilan sel.

Reviewer harus dapat menunjuk:

- minimal dua dimensi siluet yang berubah;
- ketiga anchor dan bentuk transformasinya;
- satu visual hook khas stage baru;
- hubungan material dan lineage dengan form sebelumnya.

Pixel overlap boleh ditampilkan sebagai informasi, tetapi tidak menjadi
threshold penerimaan.

## Rollout dan test

Urutan berbayar tetap sempit:

1. Seluruh schema/validator/bundle/selftest gratis harus lulus.
2. Satu Monstera Adult v22.
3. Jika Adult lulus, satu Evolved dari Adult itu.
4. Jika lineage lengkap lulus, masing-masing satu fauna dan satu
   object/illustration.
5. Baru promosi `app_config.evolution_prompt_version` ke v22.

Feature pemain, default/backfill `evolution_version=1`, dan wiki tetap gate
terpisah.

Test gratis wajib mencakup:

- kurang dari dua transformed anchor ditolak;
- kurang dari dua changed dimension ditolak;
- anatomy tanpa sumber ditolak;
- archetype Evolved yang mengulang Adult ditolak;
- prompt assembly tidak menyisakan placeholder;
- bundle prompt tidak stale;
- capture v20 tetap byte-identik.

## Hasil eval Adult v22

Satu run Veridian/Monstera memakai satu Vision dan satu GPT Image 2 medium:

- Vision `yk6yq7eas1rmw0d020rswdg5wr`, 15 detik;
- image `jjfmhvgfe9rmy0d020sbzf09ew`, 85 detik;
- estimasi biaya konservatif $0.073;
- archetype `rooted_to_mobile`, seluruh empat dimensi siluet berubah;
- tinggi Plan 188 cm dari 150 cm;
- 9/9 sel, seam 12% lulus, stage manifest 2;
- broad green residue 1,084% berasal dari tubuh plant; bright-chroma pada cincin
  alpha hanya 1/22.276 piksel (0,0045%);
- varians Idle/Attack 17,1% adalah lunge Attack dan tetap warning review;
- aspect silhouette berubah 0,838 → 1,445; normalized overlap 0,501, hanya
  sebagai informasi.

Form baru membuang susunan pot-upright dan menjadi crawler rendah dengan
leaf-carapace, empat support gelap, dan wajah lama di bawah leading leaf.
Siluetnya langsung berbeda di thumbnail dan tetap terbaca pada render Godot.
Statusnya **technical pass; visual approved**. Belum ada promosi config maupun
deploy v22.

## Hasil eval Evolved v22 pertama

Evolved dibuat dari crop Idle Adult yang disetujui, tetap satu Vision + satu
GPT Image 2 medium:

- Vision `s84n4hxgedrmt0d020xvkpdtzc`, 18 detik;
- image `m4x3477yysrmw0d020xtpqfwz4`, 75 detik;
- estimasi biaya konservatif $0.073;
- archetype `unfolding`, berbeda dari Adult `rooted_to_mobile`;
- seluruh empat dimensi siluet berubah; tinggi 250 cm dari 188 cm;
- 9/9 sel, seam lulus, standing variance hanya 0,9%;
- aspect Adult 1,445 → Evolved 0,786; normalized overlap 0,361.

Secara desain, leaf-carapace rendah membuka menjadi core tegak dengan fan
Monstera dan root-tendrils. Lineage tiga stage terbaca jelas. Namun model memakai
luminous green dekat warna transport pada core, motion accents, dan VFX:
`green_residue_ratio=4,42%`, serta 1.395/43.206 piksel cincin alpha (3,2287%)
masih bright-chroma. Hasil keying menampilkan fringe dan lubang pada core.

Kandidat ini **silhouette-direction pass, technical reject, identity reject**.
Sesuai kontrak biaya, tidak ada auto-retry. Selain fringe/lubang chroma, dua mata
ekspresif Hatchling/Adult diganti satu core/aperture sehingga form baru kehilangan
"soul" walau siluetnya kuat.

Desain pengganti ada di
[`designs/2026-08-17-evolution-identity-invariants-v23.md`](designs/2026-08-17-evolution-identity-invariants-v23.md).
V23 menambah 2–4 Identity Invariants yang dipilih Vision dari Hatchling,
dikunci melalui Adult Plan, lalu diwariskan ke Evolved. Maksimal satu invariant
boleh `transfigure` dengan turunan visual yang jelas; minimal dua lainnya dan
minimal satu identity read wajah/sensory tetap dipertahankan. Implementasi v23
memulihkan source v22 sesuai prompt dua eval lama, lalu memindahkan
`FOREGROUND GREEN SAFETY` ke versi baru agar provenance tetap reproducible.

## Hasil eval Evolved v23

Satu Vision bridge memilih tiga Identity Invariants dari Hatchling untuk Adult
v22 approved, lalu satu GPT Image 2 medium membuat Evolved:

- Vision `j5h7znae15rmw0d021srrzkvhw`, 22 detik;
- image `cpaew95acnrmr0d021sr60pwm4`, 90 detik;
- estimasi biaya konservatif $0,073;
- 9/9 sel, seam lulus, standing variance 2,2%;
- dua mata ekspresif, senyum lembut, dan daun Monstera tetap terbaca;
- form aerial `unfolding` distinct dari Adult crawler.

Kandidat ini **silhouette pass** dan **soul pass**, tetapi **maturity/apex
reject**. Massa inti kecil, tendril tipis, pose ringan, serta wajah yang masih
muda membuatnya terbaca seperti Hatchling yang mendapat sayap, bukan payoff
Lv36 yang kuat, megah, supernatural, dan dapat diandalkan.

Ia juga **technical reject**: broad green residue 3,025% dan 643/41.433 piksel
alpha-edge (1,5519%) masih bright-chroma, terutama Attack dan `fx_strike`.
Vision Plan secara spesifik meminta `shimmering green toxin`; larangan umum pada
template gambar tidak cukup kuat untuk mengalahkannya. Tidak ada retry otomatis.

Desain pengganti ada di
[`designs/2026-08-17-evolution-maturity-apex-presence-v24.md`](designs/2026-08-17-evolution-maturity-apex-presence-v24.md).
V24 menambah maturity path untuk Identity Invariants, kontrak kematangan
Adult/Evolved, satu power center, mass hierarchy, authority pose, aura
architecture, grandeur cues, reliability cue, serta allowlist aura non-green.
Eval v24 kemudian lulus maturity tetapi ditolak karena over-detail, focal face
Evolved terlalu dekat dengan Adult, dan aura Idle melanggar seam. Desain aktif
berikutnya ada di
[`designs/2026-08-17-evolution-pokemon-clarity-v25.md`](designs/2026-08-17-evolution-pokemon-clarity-v25.md).
Revisi final v25 mengganti `primary_masses`/`mass_hierarchy` dengan
`primary_shapes`/`shape_hierarchy`: dominant berarti first read, bukan badan
besar. Vision bebas memilih body archetype melalui open apex thesis dan dua
presence channels; Evolved boleh menyusut secara bounded bila transformasinya
beralasan. Schema, prompt, validator, prior Shape Budget handoff, bundle, dan
selftest gratis sudah tersedia lokal.

## Asumsi dan non-goal

Asumsi:

- Satu candidate per ritual adalah batas biaya tetap.
- Human review cukup untuk promosi prompt version; tidak dibutuhkan reviewer
  runtime.
- Latensi tambahan token Plan kecil dibanding generation gambar.
- Katalog archetype dapat ditambah lewat prompt version baru bila bentuknya
  mulai repetitif.

Non-goal:

- branching Guardian/Ravager;
- dua candidate lalu best-of-two;
- image retry otomatis;
- perubahan formula combat atau effect catalog;
- meniru bahasa visual franchise tertentu.

## Decision log

| Keputusan | Alternatif | Alasan |
| --- | --- | --- |
| Setiap stage wajib distinct | Adult moderat, wow hanya Evolved | Middle stage yang terlalu mirip tidak memberi payoff evolusi |
| Benda boleh berubah fungsi | Benda selalu literal | Literal lock mengabadikan body plan lama |
| Anatomi baru harus derived | Limb count selalu tetap / bebas total | Derived anatomy memberi kejutan tanpa kehilangan lineage |
| Satu candidate | Dua candidate / retry otomatis | Menjaga biaya dan aturan spend yang sudah disepakati |
| Delta Contract + archetype kecil | Delta saja / hard pixel gate | Lebih konkret dari teks bebas tanpa membuat semua form formulaik |
| Review silhouette manual | Runtime similarity rejection | Human review hanya terjadi saat promosi prompt dan tidak membuang spend pemain |
| V23 mengunci Identity Invariants | Prompt identity bebas / profile lineage terpisah | Menjaga soul lintas stage tanpa migrasi; profile terpisah disimpan untuk branching evolution |
