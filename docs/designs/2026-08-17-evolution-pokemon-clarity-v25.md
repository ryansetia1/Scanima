# Evolution Pokémon-like Visual Clarity v25

Status: desain disetujui dan diimplementasikan lokal 17–18 Agustus 2026.
Paid Adult Veridian lulus teknis 18 Agustus 2026; keputusan visual masih
menunggu operator. Capture production tetap v20, evolution production tetap
v21, dan `feature_evolution=false`.
Capture production tetap v20, evolution production tetap v21, dan
`feature_evolution=false`.

## Masalah

V24 berhasil membuat Adult/Evolved lebih matang, kuat, dan bergaya Scanima,
tetapi gagal pada visual clarity:

- Adult memakai terlalu banyak kelompok daun, urat, root-finger, pebble joint,
  glow, dan fragmen kecil.
- Evolved menambah `massive`, `numerous`, `deeply textured`, `multi-tiered`,
  `gnarled`, dan aura di atas detail Adult. Detail terakumulasi, bukan
  disederhanakan menjadi bentuk final.
- Wajah Evolved mengubah brow dan ekspresi, tetapi proporsi focal face tetap
  sangat dekat dengan Adult.
- Aura permanen menambah visual noise dan tiga detached fragment pada Idle
  melanggar safe seam.

Kandidat itu menunjukkan bahwa maturity dan apex presence belum cukup. Kontrak
harus memberi **budget bentuk dan detail** yang eksplisit.

## Hasil eval v24

### Adult

- Vision `da4r09rmn9rmr0d0228tnss7jc`, 27 detik.
- GPT Image 2 medium `ytw3r0bmnsrmr0d022aadacanr`, 92 detik.
- 9/9 sel, seam lulus, standing variance 1,2%.
- Broad green residue 1,831% berasal dari tubuh plant; hanya 3 dari 33.268
  piksel outer ring (0,0090%) bright-chroma.
- Soul, maturity, style, dan technical gate lulus.
- Visual clarity ditolak: jumlah bentuk sekunder/tersier dan detail permukaan
  terlalu tinggi untuk ukuran game.

Vision Adult sempat mengeluarkan JSON berpagar Markdown dengan trailing comma.
Parser shared kini menghapus trailing comma di luar string secara bounded; Plan
yang sama kemudian lolos validator tanpa Vision retry.

### Evolved

- Vision `cped0vsg3drmr0d022bsq5cn2w`, 29 detik.
- GPT Image 2 medium `7gqdw557msrmt0d022bvxgkke0`, 71 detik.
- Soul, style, dan ancient-power read bertahan.
- Visual reject: face read masih terlalu dekat dengan Adult dan detail lebih
  padat lagi.
- Technical reject sebelum commit: tiga detached Idle fragments berukuran
  27px, 50px, dan 32px terlalu dekat seam internal.
- Tidak ada image retry otomatis.

## Hasil eval v25

### Adult

- Vision `33dfvphgqnrmt0d023nte5eaec`, 30 detik.
- GPT Image 2 medium `9xw6f70nz9rmt0d023patr82vm`, 75 detik.
- Estimasi konservatif $0,073. Tidak ada image retry.
- Plan `rooted_to_mobile`, tiga primary shapes (`canopy_cluster` dominant),
  dua mata + fenestrasi dikunci.
- 9/9 sel, seam lulus, standing variance 3,4%.
- Broad green residue 2,84% dari tubuh plant; 24/31.813 piksel outer ring
  (0,0754%) bright-chroma.
- Soul dua mata dan senyum bertahan; pot Hatchling hilang.
- Visual masih menunggu operator: tubuh terbaca kolom daun di atas gundukan
  akar/batu, belum jelas mobile, dan daun/akar masih banyak.

Validator sempat menolak `source_detail` `"Pot rim"` karena lantai 8 karakter.
Lantai itu diturunkan ke 4; Plan yang sama dipakai untuk generation tanpa
Vision retry.

### Evolved

Belum di-generate. Urutan tetap Adult approved dulu.

## Riset prinsip

Nama, gambar, karakter, kostum, atau komposisi franchise tidak pernah masuk ke
prompt atau image input. Referensi berikut hanya dipakai untuk menurunkan
prinsip abstrak:

- Ken Sugimori menjelaskan bahwa keterbatasan layar, piksel, dan warna mendorong
  bentuk yang mudah dipahami dan menyimbolkan desain lebih kompleks:
  [Nintendo Online Magazine translation](https://lavacutcontent.com/sugimori-masuda-developer-interview/).
- Game Freak menguji calon monster sebagai siluet hitam dan membandingkan skema
  warnanya agar tetap berbeda:
  [Wired](https://www.wired.com/2011/10/pokemon-feature/).
- Starter awal sengaja tidak terlihat terlalu kuat; kekuatan mulai terbaca
  setelah evolusi. Final stage diberi twist yang mengejutkan dan berdampak:
  [Nintendo Dream translation](https://lavacutcontent.com/ken-sugimori-nintendo-dream-3/)
  dan
  [Pokémon Pia translation](https://www.pokebeach.com/2010/09/pokemon-peer-interview-translations).
- Desain tidak dibuat seratus persen keren/serius. Satu ciri hangat, aneh, atau
  tidak sempurna menjaga karakter tetap memorable:
  [Sugimori interview translation](https://www.siliconera.com/pokmon-designer-on-balancing-cool-or-cute-pokmon-by-adding-uncool-or-uncute-features/).
- Primary/secondary/tertiary shape hierarchy membutuhkan area detail dan area
  istirahat, bukan detail yang menyebar merata:
  [Neil Blevins — Primary, Secondary and Tertiary Shapes](http://neilblevins.com/art_lessons/composition_primary_secondary_and_tertiary_shapes/composition_primary_secondary_and_tertiary_shapes.htm).
- Final evolution tidak identik dengan tubuh besar. Sugimori menjelaskan satu
  final form serpentine tetap ramping dan mendapat authority dari tangan kecil
  yang dilipat di belakang:
  [Nintendo Dream translation](https://lavacutcontent.com/ken-sugimori-nintendo-dream-3/).
- Kenji Watanabe menjelaskan bahwa evolusi Digimon sengaja mendorong fantasy ke
  extremes; final form dapat terasa divine, elegant, tall, atau lanky, bukan
  selalu bulky:
  [Eosmon interview](https://digi-lab.blog/digimon-continues-to-be-loved-thanks-to-its-creators-commitment-with-digimon-character-designer-kenji-watanabe/)
  dan
  [Omegamon interview](https://digi-lab.blog/october-november-2018-gashapon-blog-interviews-with-kenji-watanabe/).
- Watanabe juga mengakui detail berlebih dapat terasa cluttered dan sering
  diminta disederhanakan:
  [20th Anniversary artbook translation](https://garmtranslations.wordpress.com/2018/12/22/digimon-ver-15-artbook-kenji-watanabe-special-interview/).

Prinsip yang diambil: **evolusi menukar dan menyederhanakan bentuk, bukan terus
menambahkan detail; apex fantasy tidak menentukan satu body type**.

## Understanding lock

- Targetnya Pokémon-like clarity dengan rendering Scanima, bukan meniru desain
  franchise.
- Setiap form dibangun dari 2–3 primary shape groups, satu dominant read, dan
  sangat sedikit tertiary detail. `Primary` berarti prioritas baca, bukan tubuh
  wajib besar atau tebal.
- Detail baru harus dibayar dengan merge, enlarge, atau omit detail lama.
- Adult berkembang tetapi tetap sederhana. Evolved unmistakably apex melalui
  dua visual channels yang konkret; ia boleh bulky, slim, elegant, regal,
  swift, mystical, amorphous, atau bentuk lain yang sesuai Plan.
- Vision bebas mempertahankan atau mengganti body archetype Adult selama
  perubahan itu dapat ditelusuri ke sumber dan metamorphosis thesis.
- Soul semantic tetap dikunci. Geometri focal identity wajib makin matang.
- Maturity anatomy-agnostic. Untuk Anima tanpa wajah, Vision mematangkan sensory
  cluster, aperture, leading plane, gesture, atau struktur interaksi yang memang
  ada—tidak menambahkan mata, mulut, atau jaw generik.
- Tidak ada aura, halo, corona, glow eksternal, orbit, atau energi yang
  mengelilingi tubuh pada salah satu dari tujuh character cells.
- Kemegahan energi hanya hidup di `fx_strike` dan `fx_surge`, yang memang
  ditumpuk runtime saat Attack/Special.
- Runtime tetap satu Vision dan satu image generation per stage, tanpa critic
  tambahan atau retry otomatis.
- Evolved boleh lebih pendek daripada Adult pada 0,75×–1,50× tinggi sebelumnya
  bila `height_change_rationale` menjelaskan perubahan body archetype.

## Asumsi dan non-goal

Asumsi:

- Perubahan hanya menyentuh kontrak art; formula stat, Level gate, idempotency,
  privacy, dan spend cap tidak berubah.
- Capture tetap v20.
- Adult dan Evolved v25 dibuat berurutan agar Evolved dapat membandingkan
  complexity budget serta maturity terhadap Adult yang benar-benar disetujui.
- Identity Focal Structure selalu berasal dari struktur yang terlihat pada
  reference saat ini.
- `apex_thesis` bebas; body archetype tidak dipilih dari katalog gender/body.

Non-goal:

- hardcode mata, jaw, daun, akar, pot, bulu, sisik, atau anatomi Veridian;
- membuat semua Evolved humanoid, fierce, armored, bulky, regal, feminine,
  elegant, atau bersayap;
- menambah aura untuk memalsukan power;
- menambah post-generation model critic atau complexity detector pada v25;
- mengubah mekanik pemain sebelum rollout evolusi lulus.

## Pendekatan yang dipilih

V25 menambah **Structured Shape Budget Contract**. Prompt-only ditolak karena
v24 membuktikan instruksi `simple` atau `clear` dapat dikalahkan oleh Plan yang
lebih spesifik dan penuh detail. Post-generation complexity detector disimpan
sebagai future improvement karena baru bertindak setelah image spend dan mudah
false-positive pada fur, feather, textile, atau material bertekstur.

Tidak diperlukan tabel atau migrasi. Plan tetap disimpan dalam
`generations.vision_result`.

## Kontrak data

```jsonc
{
  "shape_budget_contract": {
    "primary_shapes": [
      {
        "shape_id": "main_flow",
        "source_basis": "one visible source structure",
        "stage_expression": "one clean stage-defining silhouette flow",
        "visual_role": "dominant"
      },
      {
        "shape_id": "counter_shape",
        "source_basis": "a second visible source structure",
        "stage_expression": "one grouped counter-shape",
        "visual_role": "support"
      }
    ],
    "dominant_motif": {
      "source_basis": "one visible lineage motif",
      "stage_expression": "one memorable expression at any appropriate scale"
    },
    "identity_focal_structure": {
      "source_read": "the current face, sensory cluster, or interaction plane",
      "preserved_semantics": "the locked soul and emotional role",
      "proportion_maturation": "a concrete ratio/spacing/support change",
      "stage_expression": "the mature focal read for this stage"
    },
    "simplification_actions": [
      {
        "source_detail": "a repeated small feature group",
        "action": "merge",
        "result": "one broad readable shape"
      },
      {
        "source_detail": "incidental tertiary marks",
        "action": "omit",
        "result": "a quiet material plane"
      }
    ],
    "detail_zones": [
      {
        "zone": "identity focal area",
        "purpose": "preserve one memorable character read"
      }
    ],
    "quiet_zones": [
      "first broad low-detail region",
      "second broad low-detail region"
    ],
    "repetition_policy": "broad_grouped_pattern"
  },
  "maturity_contract": {
    "target_read": "adult",
    "identity_focal_maturation": "anatomy-appropriate focal maturation",
    "proportion_delta": "concrete before-to-after ratio change",
    "body_maturation": "large-mass and support development",
    "posture_maturation": "composed stage-appropriate posture",
    "preserved_personality": "semantic emotional identity",
    "stage_delta": "evidence this stage is older than the previous form"
  },
  "presence_contract": {
    "presence_tier": "developing",
    "apex_thesis": "the open source-derived final-power fantasy",
    "presence_channels": ["silhouette_line", "posture"],
    "channel_evidence": [
      {
        "channel": "silhouette_line",
        "drawable_evidence": "one controlled stage-defining contour"
      },
      {
        "channel": "posture",
        "drawable_evidence": "one composed and unmistakably capable stance"
      }
    ],
    "shape_hierarchy": "why the eye reads one shape first without requiring bulk",
    "authority_pose": "stable controlled posture",
    "reliability_cue": "visible reason the body can be depended on"
  },
  "vfx_palette": ["gold", "violet"],
  "height_change_rationale": "why this body archetype becomes taller, equal, or shorter"
}
```

`repetition_policy` hanya boleh `none`, `single_cluster`, atau
`broad_grouped_pattern`. Ia berlaku sama untuk leaves, fur, scales, feathers,
roots, cables, vents, folds, dan motif berulang lain.

`presence_channels` memilih tepat dua dari `silhouette_line`, `proportion`,
`posture`, `negative_space`, `motion_language`, `shape_distribution`, dan
`focal_motif`. Channel adalah cara visual menyampaikan apex, bukan katalog body
type. `apex_thesis` tetap bebas.

## Validasi

Validator v25 wajib menegakkan:

1. `primary_shapes` tepat 2–3 entri dengan `shape_id` unik.
2. Tepat satu shape memiliki `visual_role=dominant`; lainnya `support` atau
   `counterbalance`.
3. Tidak ada `size_rank`, body-size enum, atau tuntutan central mass.
4. `dominant_motif` serta `identity_focal_structure` lengkap.
5. `simplification_actions` memuat 2–4 source detail berbeda dengan aksi
   `merge`, `enlarge`, atau `omit`.
6. Adult memiliki maksimal satu detail zone. Evolved tidak boleh memiliki
   detail zone lebih banyak daripada Adult.
7. Minimal dua quiet zones non-duplikat.
8. `identity_focal_maturation` dan `proportion_delta` konkret serta non-kosong.
9. Evolved mewarisi semantic identity dan membandingkan shape budget Adult.
10. Evolved tetap mengubah minimal dua dimensi Silhouette Delta v22.
11. `presence_channels` tepat dua nilai unik dan `channel_evidence` membuktikan
    masing-masing channel.
12. Tujuh character cells tidak menerima aura field atau aura instruction.
13. `vfx_palette` hanya berisi satu atau dua warna non-green yang sudah
    di-allowlist.
14. Adult tetap memakai band tinggi lama; Evolved v25 boleh 0,75×–1,50× dengan
    `height_change_rationale` konkret.
15. Stored Plan pada resume divalidasi ulang sebelum image generation.
16. Seluruh pagar v22 Silhouette Delta dan v23 Soul Contract tetap berlaku.

Validator menghitung struktur Plan; ia tidak mencoba mengklasifikasikan spesies
atau menebak kualitas gambar.

## Kontrak prompt

Prioritas image prompt v25:

1. layout, seam, chroma, dan pose safety;
2. Identity Invariants;
3. 2–3 primary shape groups;
4. anatomy-agnostic maturity;
5. dominant motif;
6. detail/quiet zones;
7. polish.

Aturan gambar:

- block primary shapes sebelum face detail, texture, atau VFX;
- gunakan broad color/material fields dan sedikit internal line;
- kelompokkan repeated anatomy menjadi bentuk grafis besar;
- detail hanya muncul di Plan detail zones;
- quiet zones tidak boleh diisi veins, cracks, fur lines, scales, joints,
  particles, symbols, atau ornament tanpa kebutuhan struktur;
- character cells tidak memiliki aura, glow eksternal, supernatural particles,
  atau attack effect;
- Battle pose menampilkan tubuh bersih; runtime menambahkan VFX dari dua sel
  effect terpisah;
- Evolved VFX boleh lebih megah daripada Adult tetapi tetap tinggal di safe
  envelope dan tidak mengubah desain tubuh.
- jangan menambah body mass, muscle, armor, femininity, humanoid anatomy, atau
  ukuran hanya sebagai shortcut power;
- terjemahkan `apex_thesis` melalui tepat dua presence channels yang dipilih.

## Visual review

Setiap lineage candidate melewati:

### Clarity gate

- silhouette hitam tetap terbaca pada 96px;
- 2–3 primary shapes dapat ditandai tanpa ambigu;
- satu dominant motif terbaca sebelum detail;
- grayscale menunjukkan value grouping besar;
- reviewer dapat menggambar ulang identitas form dengan 3–5 bentuk;
- ada area visual rest yang nyata.

### Maturity gate

- focal crop ketiga stage dapat diurutkan dari muda ke matang tanpa label;
- perubahan berasal dari proporsi/geometri yang sesuai anatomi sumber;
- personality dan semantic soul tetap terbaca.

### Lineage gate

- Hatchling, Adult, dan Evolved memiliki silhouette berbeda;
- Adult menyiapkan dominant motif;
- Evolved menyelesaikannya sebagai satu dominant read, bukan detail tambahan;
- body archetype boleh berubah bebas bila lineage evidence tetap pointable;
- bulky, slim, elegant, dan compact sama-sama sah sebagai apex.

### Technical gate

- 9/9 sel dan seam audit lulus;
- bright-chroma outer ring di bawah 0,1%;
- tidak ada thought bubble, simbol UI, aura, glow eksternal, atau VFX pada sel
  karakter;
- Godot Idle terbaca pada ukuran game.

## Rollout

1. Simpan v21–v24 immutable untuk rollback dan provenance.
2. Implementasikan v25 schema, Vision prompt, image prompt, validator, bundle,
   dan test gratis.
3. Generate satu Adult v25 dari Hatchling Veridian.
4. Review soul, maturity, silhouette, clarity, dan technical gate.
5. Hanya setelah Adult disetujui, generate satu Evolved v25 dari Adult itu.
6. Tidak ada retry otomatis.
7. Sesudah plant lineage lulus, eval satu fauna dan satu object/illustration.
8. Production config, client minimum, backfill `evolution_version=1`, dan
   `feature_evolution` tetap gate terpisah.

Wiki pemain tidak berubah karena evolusi belum player-live.

## Future improvement

Post-generation complexity detector dapat mengukur edge density, komponen kecil,
dan distribusi detail. Ia baru layak ditambahkan setelah sampel lintas plant,
fauna, textile, dan mechanical menunjukkan ambang yang tidak false-positive.

## Decision log

- Pokémon-like clarity dipilih untuk silhouette, shape hierarchy, line economy,
  stage surprise, dan memorability.
- Variasi apex Digimon dipakai sebagai bukti bahwa final power tidak identik
  dengan bulk; detail-density Digimon tidak diadopsi.
- Structured Shape Budget dipilih dibanding prompt-only.
- Complexity detector ditunda sebagai future improvement.
- Maturity dibuat anatomy-agnostic melalui Identity Focal Structure.
- Detail tidak boleh bertambah otomatis; evolusi wajib menyederhanakan detail
  lama.
- Evolved tidak mendapat detail-zone budget lebih besar dari Adult.
- `primary_masses`, `size_rank`, dan `mass_hierarchy` dibatalkan karena
  menyisipkan bias bulky. V25 memakai `primary_shapes`, dominant read, dan
  `shape_hierarchy`.
- Vision bebas mengganti body archetype; `apex_thesis` bebas dan dua
  `presence_channels` generik membuat alasan visualnya dapat divalidasi.
- Evolved boleh menyusut hingga 0,75× Adult atau tumbuh hingga 1,50× bila
  perubahan tinggi dijelaskan oleh body archetype.
- Aura pada tubuh ditolak seluruhnya. Power final dibaca dari line, proportion,
  posture, negative space, motion, shape distribution, atau focal motif.
- Efek supernatural hanya muncul di `fx_strike` dan `fx_surge`.
- V24 dipertahankan immutable sebagai provenance hasil yang mature tetapi
  over-detailed.
