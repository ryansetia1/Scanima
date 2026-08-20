# 16 — Riwayat versi prompt

Pohon `backend/prompts/` lengkap beserta provenance setiap versi yang ditolak, dipindahkan verbatim dari `CLAUDE.md`. Versi yang production sekarang beserta rollback-nya ada di `CLAUDE.md`; spesifikasi isi prompt ada di [`02-prompt-engineering.md`](02-prompt-engineering.md).

Alasan versi ditolak disimpan karena empat mekanisme berbeda pernah mendarat di band hasil yang sama — tanpa catatannya, revisi berikutnya mengulang percobaan yang sudah dibayar.

## Pohon versi

```
backend/prompts/
├── v1/
│   ├── vision_system.md          # system prompt untuk Vision LLM
│   ├── vision_schema.json        # responseSchema Gemini (subset OpenAPI, bukan JSON Schema penuh)
│   ├── sprite_sheet.md           # baseline nano-banana-pro
│   └── sprite_sheet_evolve.md    # varian untuk evolusi, pakai sprite lama sebagai image_input
├── v2/
│   ├── vision_system.md          # gate yang sama dengan v1
│   ├── vision_schema.json        # kontrak yang sama dengan v1
│   ├── sprite_sheet.md           # GPT Image 2 medium + anime cel-shaded style
│   └── sprite_sheet_evolve.md
├── v3/                           # predecessor: v2 + blok BRAND MARKS
│   ├── vision_system.md          # identik v2
│   ├── vision_schema.json        # identik v2
│   ├── sprite_sheet.md           # logo merek diganti marking ciptaan
│   └── sprite_sheet_evolve.md
├── v4/                           # predecessor: material + damage
│   ├── vision_system.md          # + surface_finish dan damage_hints
│   ├── vision_schema.json        # material/damage nullable, cache key tetap
│   ├── sprite_sheet.md           # permukaan polos; damage wajib sesuai material
│   └── sprite_sheet_evolve.md
├── v5/                           # predecessor candidate: karakter + body plan
│   ├── vision_system.md          # + karakter, limb plan, larangan suffix -mon
│   ├── vision_schema.json        # presentation nullable, cache key tetap
│   ├── sprite_sheet.md           # Idle non-angry; tubuh mengikuti objek
│   └── sprite_sheet_evolve.md    # presentation + zero-limb tetap dipertahankan
├── v6/                           # predecessor candidate: facing lock kiri
│   ├── vision_system.md          # identik v5; species cache key tidak berubah
│   ├── vision_schema.json        # identik v5
│   ├── sprite_sheet.md           # v5 + facing lock empat pose ke canvas-left
│   └── sprite_sheet_evolve.md    # facing lock dipertahankan lintas evolusi
├── v7/                           # rollback production: sheet 3x3 + nama move
│   ├── vision_system.md          # v6 + strike_name / surge_name dua kata; species_key tetap
│   ├── vision_schema.json        # dua field move, cache key tidak berubah
│   ├── sprite_sheet.md           # sembilan sel: 7 pose karakter + 2 efek battle
│   └── sprite_sheet_evolve.md    # grid 3x3 dipertahankan lintas evolusi
├── v8/                           # predecessor candidate: facing lock kolom kiri
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v7 + anti-inward facing pada Idle/Happy/Damaged
│   └── sprite_sheet_evolve.md    # facing lock kolom kiri dipertahankan lintas evolusi
├── v9/                           # REJECTED: negative-space generik diabaikan model
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v7 + lubang/celah internal bukan matte putih
│   └── sprite_sheet_evolve.md    # uji Monstera tetap menghasilkan celah putih
├── v10/                          # REJECTED: membaik, tetapi slot putih masih tersisa
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v9 + material highlight + Monstera hole lock
│   └── sprite_sheet_evolve.md    # uji Monstera 0,166% residu, belum bersih visual
├── v11/                          # predecessor: borderless clean, seam leak sepatu
│   ├── vision_system.md          # identik v7; species cache key tidak berubah
│   ├── vision_schema.json        # identik v7
│   ├── sprite_sheet.md           # v10 + dark contour langsung melawan green
│   └── sprite_sheet_evolve.md    # efek/evolusi juga tanpa border putih
├── v12/                          # rollback: safe seam + VFX per-Anima
│   ├── vision_system.md          # v11 + brief/form/motion Attack dan Special
│   ├── vision_schema.json        # strike_vfx/surge_vfx; species_key tetap
│   ├── sprite_sheet.md           # aksen Battle utuh dalam safe envelope 12%
│   └── sprite_sheet_evolve.md    # identitas VFX ikut bertahan saat evolusi
├── v13/                          # ROLLBACK: 18 elemen + fauna + unique private art
│   ├── vision_system.md          # object/animal gate + dual typing
│   ├── vision_schema.json        # subject_kind + secondary_element
│   ├── sprite_sheet.md           # objek, grid v12
│   ├── sprite_sheet_fauna.md     # hewan, Damaged tanpa gore
│   └── sprite_sheet_evolve.md
├── v14/                          # REJECTED: masih terlihat seperti anjing anime
│   ├── vision_system.md          # identik v13
│   ├── vision_schema.json        # identik v13
│   ├── sprite_sheet.md           # objek identik v13
│   ├── sprite_sheet_fauna.md     # monsterization floor + expression lock
│   └── sprite_sheet_evolve.md    # identik v13
├── v15/                          # production art baseline; rollback v18
│   ├── vision_system.md          # identik v13
│   ├── vision_schema.json        # identik v13
│   ├── sprite_sheet.md           # objek identik v13
│   ├── sprite_sheet_fauna.md     # proportion + landmark + organic motif
│   └── sprite_sheet_evolve.md    # identik v13
├── v16/                          # CANDIDATE: facing + gaze lock lintas semua Anima
│   ├── vision_system.md          # identik v15
│   ├── vision_schema.json        # identik v15
│   ├── sprite_sheet.md           # objek + source facing/gaze canvas-left
│   ├── sprite_sheet_fauna.md     # v15 + source facing/gaze canvas-left
│   └── sprite_sheet_evolve.md    # evolusi mempertahankan facing/gaze
├── v17/                          # rollback: v15 + tinggi kanonis Vision awal
│   ├── vision_system.md          # v15 + body_height_cm 20–2000
│   ├── vision_schema.json        # kontrak v15 + body_height_cm
│   ├── sprite_sheet.md           # identik v15; nol perubahan art
│   ├── sprite_sheet_fauna.md     # identik v15; nol perubahan art
│   └── sprite_sheet_evolve.md    # identik v15
├── v18/                          # rollback: v17 + floor handheld 70–120 cm
│   ├── vision_system.md          # real scale anchor + playable floor + deliberate exaggeration
│   ├── vision_schema.json        # kontrak sama; deskripsi tinggi diperjelas
│   ├── sprite_sheet.md           # identik v17/v15; nol perubahan art
│   ├── sprite_sheet_fauna.md     # identik v17/v15; nol perubahan art
│   └── sprite_sheet_evolve.md    # identik v17/v15
├── v19/                          # rollback: v18 + floor boneka gendong ~50 cm
│   ├── vision_system.md          # handheld kecil jadi Anima berbadan kecil
│   ├── vision_schema.json        # kontrak sama; deskripsi floor diperjelas
│   ├── sprite_sheet.md           # identik v18/v15; nol perubahan art
│   ├── sprite_sheet_fauna.md     # identik v18/v15; nol perubahan art
│   └── sprite_sheet_evolve.md    # identik v18/v15
├── v20/                          # DEFAULT capture: ilustrasi orisinal + gate franchise
│   ├── vision_system.md          # known_character + klasifikasi subjek ilustrasi
│   ├── vision_schema.json        # reason known_character
│   ├── sprite_sheet.md           # identik byte-for-byte dengan v19
│   ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v19
│   └── sprite_sheet_evolve.md    # identik byte-for-byte dengan v19
├── v21/                          # rollback evolution, terlalu konservatif
│   ├── vision_system.md          # capture tetap identik v20
│   ├── vision_schema.json        # capture tetap identik v20
│   ├── vision_evolve_system.md   # Evolution Director + lineage/effect contract
│   ├── vision_evolve_schema.json # Evolution Plan string anchors
│   ├── sprite_sheet.md           # identik byte-for-byte dengan v20
│   ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v20
│   └── sprite_sheet_evolve.md    # Adult/Evolved konservatif
├── v22/                          # predecessor silhouette-first
│   ├── vision_system.md          # capture tetap identik v20
│   ├── vision_schema.json        # capture tetap identik v20
│   ├── vision_evolve_system.md   # Silhouette Delta + archetype
│   ├── vision_evolve_schema.json # transformed anchors + body-plan delta
│   ├── sprite_sheet.md           # identik byte-for-byte dengan v20
│   ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v20
│   └── sprite_sheet_evolve.md    # body plan baru tiap stage dari Idle
├── v23/                          # predecessor: soul pass, apex reject
    ├── vision_system.md          # capture tetap identik v20
    ├── vision_schema.json        # capture tetap identik v20
    ├── vision_evolve_system.md   # v22 + Identity Invariants
    ├── vision_evolve_schema.json # v22 + soul contract
    ├── sprite_sheet.md           # identik byte-for-byte dengan v20
    ├── sprite_sheet_fauna.md     # identik byte-for-byte dengan v20
    └── sprite_sheet_evolve.md    # identity priority + green safety
├── v24/                          # predecessor: maturity pass, clarity reject
    ├── vision_evolve_system.md   # v23 + Maturity/Apex Presence
    ├── vision_evolve_schema.json # maturation path + presence contract
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
├── v25/                          # predecessor: clarity pass, mobility reject
    ├── vision_evolve_system.md   # Shape Budget + open apex thesis/channels
    ├── vision_evolve_schema.json # primary shapes + VFX-only palette
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v26/                          # predecessor: mobility pass
    ├── vision_evolve_system.md   # v25 + mobility_contract
    ├── vision_evolve_schema.json # v25 + locomotion/support fields
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v27/                          # predecessor: face-age craniofacial
    ├── vision_evolve_system.md   # v26 + face_age_contract
    ├── vision_evolve_schema.json # v26 + age_read/ratio fields
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v28/                          # predecessor: walker exile (Sunhound ular)
    ├── vision_evolve_system.md   # v27 + silhouette_break_contract
    ├── vision_evolve_schema.json # v27 + prior/forbidden/new contour
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v29/                          # predecessor: kind lock + contour delta
    ├── vision_evolve_system.md   # v28 minus gait exile, plus kind_noun
    ├── vision_evolve_schema.json # v28 + source/continued kind
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v30/                          # production evolution: name lineage
    ├── vision_evolve_system.md   # v29 + suggested_name lineage
    ├── vision_evolve_schema.json # v29 + suggested_name
    └── sprite_sheet_evolve.md    # capture diwarisi dari v20 saat bundling
└── v31/                          # capture Vibe; evolution tetap v30
    ├── vision_system.md          # identik v20
    ├── vision_schema.json        # identik v20
    ├── sprite_sheet.md           # v20 + {{vibe_direction}}
    ├── sprite_sheet_fauna.md     # v20 + {{vibe_direction}}
    └── vibe_directions.json      # natural/cute/brave/wild/sinister
├── v32/                          # rejected: valid structure, naming quality 0/3
    ├── vision_system.md          # v31 + species naming/anchor 3–5 huruf
    ├── vision_schema.json        # v31 + name_lineage_anchor
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # v30 + exact authoritative name anchor
    ├── vision_evolve_schema.json # v30 + name_lineage_anchor
    └── sprite_sheet_evolve.md    # identik v30
├── v33/                          # rejected: coined-word naming quality 1/3
    ├── vision_system.md          # v32 + anti-compound/source-literal self-check
    ├── vision_schema.json        # v32 + pronounceable anchor contract
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v32
    ├── vision_evolve_schema.json # identik v32
    └── sprite_sheet_evolve.md    # identik v30
├── v34/                          # rejected after expanded eval: 3/6
    ├── vision_system.md          # v33 + private candidates + cover test
    ├── vision_schema.json        # v33 + identity-copy contract
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v32
    ├── vision_evolve_schema.json # identik v32
    └── sprite_sheet_evolve.md    # identik v30
├── v35/                          # rejected: structured self-review 1/6
    ├── vision_system.md          # v34 + lexical/product/creature checks
    ├── vision_schema.json        # v34 + required name_quality declaration
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v32
    ├── vision_evolve_schema.json # identik v32
    └── sprite_sheet_evolve.md    # identik v30
├── v36/                          # rejected: deterministic phonotactics 0/6
    ├── vision_system.md          # naming capture dipindah ke server
    ├── vision_schema.json        # tanpa field naming model
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # nama final dari server
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
├── v37/                          # rejected: hybrid semantic roots 0/6
    ├── vision_system.md          # enam root semantik terurut
    ├── vision_schema.json        # name_roots; final word milik server
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # semantic anchor + server continuation
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v38/                          # rejected: transformed roots 1/6
    ├── vision_system.md          # semantic seed 3–8 huruf, bukan final anchor
    ├── vision_schema.json        # enam seed; transform final milik server
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # empat cadence family seimbang
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v39/                          # rejected: scored candidate selection 3/6
    ├── vision_system.md          # seed sama; server memilih dari 32 kandidat
    ├── vision_schema.json        # identik v38
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # gerbang struktur untuk Adult/Evolved
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v40/                          # superseded sebelum eval berbayar
    ├── vision_system.md          # seed sama; campuran 2–3 suku kata
    ├── vision_schema.json        # identik v38
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # identik v39
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
└── v41/                          # candidate: dua morfem terbaca, menunggu operator
    ├── vision_system.md          # enam morfem 3–5 huruf + kalibrasi register
    ├── vision_schema.json        # root morfem terbaca, bukan seed acak
    ├── sprite_sheet*.md          # identik v31
    ├── vibe_directions.json      # identik v31
    ├── vision_evolve_system.md   # anchor utuh; eskalasi di makna morfem
    ├── vision_evolve_schema.json # field naming sementara untuk wire shape
    └── sprite_sheet_evolve.md    # identik v30
```

## Provenance v32–v41

V41 adalah production untuk capture maupun evolution; kontrak siluet/mobility/
face-age v29 dan art v30 tetap berlaku di dalamnya, dan v31/v30 adalah rollback.
Adult Veridian v26, Adult Sunhound v28, Evolved Sunhound
v29, serta Adult+Evolved Playtron v29 terkunci per Anima; lock Plan membawa
`suggested_name` operator.
Candidate **Name Lineage v32** sudah diimplementasikan lokal tetapi
**ditolak pada paid Vision eval** dan tidak pernah dipromosikan/live: Scan
membuat nama spesies dari
siluet/material/gerak plus anchor bunyi 3–5 huruf; Adult dan Evolved wajib
mempertahankan anchor authoritative yang sama tanpa fixed suffix atau model
call tambahan. Validator memperbaiki anchor capture invalid secara
deterministik; Evolution tetap exact. Legacy fallback memakai nama generated,
bukan nickname. Bundel prompt dan selftest gratis lulus, tetapi tiga Vision
berbayar (mouse, mug, ilustrasi naga; ~$0.009; nol image generation/retry)
menghasilkan `ClickGlide`, `Muggleton`, dan `Wyrmscale`: 0/3 lolos arah nama
spesies karena compound Inggris transparan/literal/surname-like. Production
tetap capture v31 + evolution v30.
Candidate **v33** memperbaiki akar reject tanpa dictionary hardcode: nama wajib
satu coined word pronounceable, bukan compound Inggris transparan, label/sinonim
sumber, ingredient literal, atau person/surname/place/title/job/rank. Anchor
tetap 3–5 huruf tetapi v33 menolak tiga consonant beruntun; v32 tetap
reproducible. Tidak ada model call/migrasi/perubahan art tambahan. Bundel dan
selftest gratis lulus. Paid Vision-only eval tiga fixture yang sama (~$0.009,
nol image generation/retry) menghasilkan `Cursora`, `Glazel`, dan `Dracovent`;
semua struktur/anchor valid tanpa repair, tetapi hanya `Glazel` lolos arah
kreatif. `Cursora` masih literal terhadap cursor dan `Dracovent` masih generic
draco + vent, jadi v33 ditolak 1/3 dan tidak live; revisi berikutnya wajib v34.
Candidate **v34** membuat filter itu operasional tanpa dictionary server:
Vision membangun forbidden identity list per subjek, membuat minimal lima
kandidat privat, menolak salinan empat huruf beruntun, lalu melakukan cover
test. Paid Vision-only eval tiga fixture yang sama (~$0.009, nol image
generation/retry) menghasilkan `Curvix`, `Glazel`, dan `Skalyn`; ketiganya
lolos arah nama dan anchor tanpa repair. Mug mencatat satu normalisasi
`strike_vfx` yang tidak terkait naming. Set kedua yang lebih beragam memakai
Monstera, sepatu, dan handheld; fixture WebP dikonversi lokal setelah gagal
sebelum API, jadi tetap tepat tiga paid call (~$0.009). Hasil `Fenestra`,
`Kineto`, dan `Portex` ditolak karena dictionary/scientific term, generic
kinetic root, atau product/brand-like read. Agregat v34 3/6: v34 ditolak dan
tidak live; revisi berikutnya wajib v35. Production tetap capture v31 +
evolution v30.
Candidate **v35** menambah delapan kandidat lintas empat construction family,
explicit dictionary/scientific/product/creature-read checks, serta enam boolean
`name_quality` yang wajib `true` di validator. Bundel dan seluruh selftest gratis
lulus. Enam paid Vision-only call (~$0.018, nol image generation/retry)
menghasilkan `Scurrix`, `Crockle`, `Aerisyn`, `Phyllaura`, `Solerix`, dan
`Vectron`; model menyatakan seluruh quality flag true. Audit independen menolak
lima terakhir: existing Scots word/character/bestiary creature, perusahaan
AI/produk, nomenklatur botani, SaaS, serta brand POS/lokomotif. Hanya `Scurrix`
lolos, jadi v35 ditolak **1/6** dan tidak live. Fakta penting: self-attestation
terstruktur menegakkan bentuk response, bukan kebenaran collision claim; revisi
berikutnya harus mengganti mekanisme dengan bukti independen atau lexical
boundary deterministik, bukan menambah checklist model lagi.
Candidate **v36** menguji batas deterministik itu: model tidak lagi membuat nama;
server meng-hash `species_key`, element, strongest stat, brief, dan features
menjadi anchor + syllable fonotaktik, sedangkan Evolution memakai anchor + Plan.
Bundel dan selftest gratis lulus. Enam paid Vision-only call (~$0.018, nol image
generation/retry) menghasilkan `Zimnuzem`, `Basgutun`, `Deshupil`, `Vadvuter`,
`Luvsufak`, dan `Therhalok`. Exact-name audit tidak menemukan collision langsung,
tetapi keenamnya ditolak kreatif: random/awkward, source character tidak dapat
dibaca, dan beberapa mendekati kata/nama/product lain. V36 ditolak **0/6** dan
tidak live. Kesimpulan: unique hash bukan authored species name; revisi berikut
harus hybrid—semantic phoneme/candidates dari model, selection/transformation
deterministik yang menjaga cue terbaik.
Candidate **v37** mengimplementasikan hybrid itu tanpa call/dependency baru.
Capture Vision meranking tepat enam `name_roots` 3–5 huruf dengan channel +
evidence dari silhouette/material/motion/temperament/structure. Server menolak
root yang menyalin `object_label`/`species_key`, memilih root valid terkuat,
lalu menambah continuation terkurasi berdasar visual payload + strongest stat.
Adult/Evolved mempertahankan anchor itu dengan continuation stage-specific dari
Plan. Model tidak membuat final word atau collision claim. Bundel, seluruh
selftest, dan dry run enam foto lulus tanpa API. Enam paid Vision-only call
(~$0.018, nol image generation/retry) menghasilkan `Glidora`, `Serpora`,
`Folialia`, dan `Tecnelia`; mug/sepatu gagal validator pada root `cylin` dan
`stride`. Keempat jalur valid tetap memilih root literal/generic (`glid`,
`serp`, `folia`, `tecn`); exact search menemukan penggunaan `Glidora` dan
`Serpora`. V37 ditolak **0/6** dan tidak live. Formatting root minor seharusnya
dinormalisasi deterministik di versi berikut, tetapi akar masalahnya adalah
server suffix tidak dapat menyelamatkan root dictionary/category yang literal.
Candidate **v38** menerima semantic seed 3–8 huruf lalu mengubah onset, vowel,
dan coda menjadi anchor baru. Continuation tidak lagi mengikuti strongest stat:
hash identitas visual memilih keluarga `closed`/`hard`/`liquid`/`open`, dan
Adult/Evolved memakai keluarga stage-specific yang sama-sama seimbang. Seluruh
selftest + dry run lulus; enam paid Vision-only call (~$0.018, nol image
generation/retry) valid 6/6 dan menghasilkan `Kuka`, `Graskorin`, `Zoskesk`,
`Bomari`, `Daxorin`, `Vororn`. Bias `-a/-ia` berhasil hilang: sample tersebar
open 2, liquid 2, hard 2, dengan ending `-a/-in/-esk/-ari/-in/-orn`. Namun audit
independen menolak lima: KUKA adalah perusahaan robotik, Bomari perusahaan
aktif, Daxorin artis, Vororn punya penggunaan historis/niche, dan Zoskesk sulit
diucapkan. Hanya `Graskorin` lolos provisional, jadi v38 ditolak **1/6** dan
tidak live. Diversitas cadence terbukti masalah terpisah dari collision dan
creature-read; memperbaiki rima saja tidak cukup.
Candidate **v39** menyerang akar reject v38: ia hanya membentuk satu kandidat
lalu memakainya. `nameStructureScore()` memberi penalti deterministik untuk
nama < 7 huruf, < 3 suku kata, rantai CV tunggal tanpa klaster/coda, bigram
berulang, tiga konsonan beruntun, dan substring identitas sumber; keempat reject
terukur v38 semuanya jatuh negatif sementara `Graskorin` positif.
`selectCadenceName()` membangun 32 kandidat (4 cadence family × 8 continuation),
membuang yang di bawah lantai, lalu memilih memakai hash identitas visual. Skor
adalah **gerbang, bukan fungsi objektif**: memilih skor tertinggi terukur
konvergen — 151/200 fixture berakhir `-rin`, yaitu bias rima yang baru
dibetulkan v38. Karena anchor selalu berakhir konsonan, medial v38 dibuang; itu
sekalian memperbaiki bug join vokal yang membuat family `closed`/`hard` tidak
pernah terjangkau. Terukur: hard 51 / liquid 51 / open 49 / closed 49, dan tail
tiga huruf terpadat turun 51/200 → 21/200. Tujuh paid Vision-only (~$0.021, nol
image generation/retry) valid 6/6 dan menghasilkan `Fimdakar`, `Zolvela`,
`Vurralis`, `Diskurak`, `Dorralis`, `Kurvesun`. Audit independen: tiga lolos, dua
borderline (`Diskurak` terbaca `Disk-` literal untuk mouse, `Dorralis` beda satu
huruf dari nama orang `Doralis` sekaligus mengulang tail `-ralis`), dan
`Kurvesun` **reject** karena `kurv-` vulgar di Ceko, Slovakia, Hungaria, Serbia,
Kroasia, dan Polandia. V39 ditolak **3/6** dan tidak live. Fakta penting: sisa
kegagalan bukan lagi bentuk kata melainkan fakta leksikal dunia nyata
(brand, nama orang, kata kasar lintas bahasa) yang tidak terlihat oleh
fonotaktik dan sudah terbukti tidak bisa diklaim model sendiri di v35. Empat
mekanisme berbeda v35–v39 semuanya mentok di 0/6–3/6, jadi revisi aturan
generasi berikutnya diperkirakan mendarat di band yang sama; yang harus berubah
adalah **bukti yang tersedia saat seleksi**, bukan cara kandidat dibentuk.
**Satu perbaikan v39 dipertahankan walau versinya ditolak:** penamaan tidak
boleh menggagalkan capture berbayar. `sepatu.jpg` kehilangan satu Vision karena
seed hanya mencakup tiga visual channel, jadi
`deriveCuratedHybridSpeciesName()` sekarang jatuh ke fonotaktik deterministik
v36 untuk setiap kegagalan seed, mencatat sebabnya di
`selected_name_root.seed_fallback`, dan tetap melewati gerbang struktur. Pagar
yang sama hidup di jalur morfem v41: seluruh akar rusak jatuh ke fonotaktik v36
alih-alih menggagalkan Vision yang sudah dibayar.

Riset pembanding seluruh generasi Pokémon membalik premisnya: Pokémon sendiri
memakai nama yang bertabrakan dengan kata, brand, dan nama orang nyata
(Onix/Onyx, Ditto, Golem, Arbok, Eevee), sementara aturan kita menolak nama
bermakna demi keunikan leksikal lalu meloloskan nama tanpa nyawa. Catatannya di
[`docs/pokemon-name-research.html`](docs/pokemon-name-research.html). **V40**
(campuran suku kata + blocklist beku) diimplementasikan tetapi digantikan
sebelum satu pun eval berbayar. **V41** berhenti mentransformasi root: morfem
terbaca dari Vision bertahan utuh sebagai paruh pertama nama sekaligus anchor
lineage, dan server menyambungnya dengan morfem bermakna dari tabel per elemen
(mineral `lith`/`crag`/`elisk`, tidal `rime`/`mire`/`brine`, ember
`ember`/`pyre`/`lume`), persis cara Noxcoil dan Ambermire dibangun. Aturan
kamus, compound, dan tabrakan nama dicabut; blocklist profanity tetap. Evolution
memakai anchor yang sama dengan tail per stage — biasa untuk Adult, berwibawa
untuk Evolved — jadi eskalasi ada di makna morfem, bukan di jumlah huruf.
Dua perbaikan produksi dipertahankan apa pun keputusannya: satu akar rusak tidak
lagi membuang lima akar sehat (`normalizeNameRoots` melewatinya dan mencatatnya
di `rejected_roots`), dan aturan pronounceable v33 tidak lagi berlaku saat jalur
morfem memiliki anchor — tanpa itu `cindr` milik `Cindrusk` diganti diam-diam.
Dua ronde Vision-only sembilan subjek (~$0.054, nol image generation/retry):
ronde pertama mengukur bug akar terbuang (5/9 memakai fonotaktik v36), ronde
kedua 9/9 anchor dari Vision dan menghasilkan `Vitrelisk`, `Lumecrag`,
`Resonelisk`, `Stridusk`, `Verdarbor`, `Glidfold`, `Pixelquill`, `Loopfold`,
`Dracovenom`. Lineage lulus tanpa syarat: head bertahan huruf demi huruf di
ketiga stage dan tidak bergantung pada Evolution Plan, jadi bentuk lineage bisa
diperiksa tanpa Plan berbayar atau image generation. Register adalah satu-satunya
sisa kegagalan: morfem Latin/material terbaca spesies, kata modern/teknologi
terbaca merchandise, dan empat dari lima kasus lemah sudah menawarkan morfem
lebih baik di peringkat bawah responsnya sendiri.
Operator menolak tail stage ronde kedua, dan keduanya sudah diperbaiki lalu
diukur ulang offline dari Vision JSON tersimpan tanpa satu pun panggilan API.
**Tail tidak boleh menjanjikan anatomi yang tidak ada di Plan:** `Loophorn` dan
`Lumegirt` memasang tanduk pada sarung tangan dan lampu, dan `-coil` pada konsol,
`-pelt` pada naga bersisik, serta `-thorn` pada Monstera tanpa duri adalah janji
yang sama. `planFeatureTails()` memindai `stage_brief`, archetype, mobility
contract, contour read, dan shape budget untuk enam belas fitur tubuh; hanya yang
cocok boleh dipakai, sementara `MORPHEME_BODY_TAILS` mencabut seluruh kelas itu
dari kolam keluarga di stage evolusi. Capture sengaja tetap memakainya karena di
sana morfem menggambarkan material objek aslinya — jalur yang sama yang
menghasilkan Noxcoil dan Duskadon. **Evolved berhenti berima:** penyebabnya
mekanis, bukan gaya — `monolith`/`paragon` melewati 12 karakter di atas head lima
huruf lalu dijatuhkan lantai struktur, dan `throne` tidak pernah terjangkau
karena onset `thr` selalu berbiaya seam >= 3, jadi kolam yang benar-benar
diterima menyusut ke tiga entri. Kolam Evolved sekarang delapan gelar pendek
(`sovran`, `titan`, `zenith`, `astral`, `aegis`, `apex`, `aeon`, `aether`) dan
Adult melanjut ke keluarga materialnya sendiri supaya terbaca spesies saudara.
Tiga cacat lain ikut tertutup: `Cylinonyx` terukur menjadi Hatchling sekaligus
Adult (nama stage sebelumnya sekarang dikecualikan), elisi menghasilkan `Aquamen`
yang terbaca dua kata Inggris dan `Glideeon` yang menumpuk tiga vokal (potongan
elisi wajib mulai konsonan), dan `y` di ujung head kini dihitung vokal untuk seam
sehingga `Cozyweave`/`Cozyseam` tidak lagi tertolak.
Bacaan operator berikutnya menemukan sembilan nama semuanya tiga suku kata dengan
ekor yang masih berulang, lalu meminta mesinnya **dikecilkan**, bukan ditambah:
nama ini placeholder yang boleh di-rename pemain, jadi cukup berbunyi seperti nama
Pokémon. Dua sebabnya mekanis. Tail berawal vokal selalu dua suku kata, dan seam
lama yang dibatasi dua konsonan mengunci setiap head berkoda ganda (`dash`, `dusk`,
`glaz`) pada tail itu — jadi head satu suku kata tidak pernah bisa menghasilkan
nama dua suku kata; batas tiga membuka `Dashcoil` sementara `Cindrvolt` tetap
tertutup di empat. Ekor berulang lahir dari `nameStructureScore()` +
`NAME_STRUCTURE_FLOOR` di atas seam: kolam tiap keluarga tersisa dua–tiga entri,
dan kolam kecil berulang secara aritmetika. Karena itu **seluruh lapisan seleksi
v39–v41 dicabut dari jalur ini** — nol skor, nol 32 kandidat, nol tiga tingkat
fallback. Yang tersisa: kolam lebar, tiga filter (profanity, seam, nama yang sudah
dipakai stage sebelumnya), satu indeks hash, sekitar lima belas baris menggantikan
enam puluh; cap 12 huruf di `morphemeSeamOk()` mengambil satu-satunya tugas yang
masih dimiliki scorer. Tiap keluarga ditambah empat morfem pendek, dan kolam
Evolved menerima gelar satu suku kata `king`/`zard`/`myth`/`doom` — Pokémon sendiri
memakai Nidoking, Slowking, dan Charizard. Aturan anatomi bersifat
**negatif**: hanya fitur yang Plan sebut boleh muncul, tetapi ia **ikut** ke kolam
dan tidak menggantikannya. Versi yang memaksa anatomi menang sudah diukur salah —
Plan bersatu fitur mengunci setiap Adult pada morfem yang sama (`Glidhusk`,
`Celerhusk`, `Glazehusk` pada tiga subjek berbeda) dan sekalian membuka satu crash
yang hanya bisa terjadi saat uang sudah keluar: kolam Evolved tinggal satu tail,
Adult sudah memakainya, filter nama terpakai mengosongkannya, derivasi melempar.
Anatomi yang ikut ke kolam menghapus kelas kegagalan itu, dan filter di dalam
seleksi kini usaha terbaik bukan gerbang — nama kembar itu gangguan kosmetik,
evolusi berbayar yang gagal bukan. Terukur atas tiga puluh head pada satu Plan
identik (kasus terburuk): lima belas ekor Adult berbeda, terpadat 5/30. Metrik
diversitas di selftest sendiri sempat off-by-one — ia menghitung huruf terakhir
head sebagai bagian ekor — dan sudah dibetulkan. Terukur offline atas
sembilan subjek ronde dua tanpa panggilan API: Hatchling dari 9/9 tiga suku kata
menjadi 2 dua suku kata / 3 tiga / 4 empat dengan tujuh ekor berbeda, dan Evolved
sembilan ekor berbeda dari sembilan. Head ronde dua sendiri dua suku kata (`aqua`,
`folia`, `cylin`), jadi prompt sekarang meminta Vision menjaga sebagian besar akar
satu suku kata; simulasi dua belas head satu suku kata mendarat di 5 dua suku kata
/ 7 tiga dengan sebelas ekor berbeda — bentuk Sugarworks. Selftest menuntut nama
dua suku kata tetap terjangkau supaya ini tidak diam-diam kembali.
Ronde ketiga enam subjek baru (~$0.018, nol image generation) memunculkan empat
cacat yang semuanya berupa aturan yang sudah ditulis tetapi baru separuh
diterapkan. **Gerbang anatomi ternyata hanya menjaga evolusi:** capture memberi
`Fenesthorn` pada Monstera tanpa duri, jadi `featureTailsFromText()` sekarang
melayani Plan maupun `signature_features` dan capture memakai gerbang negatif yang
sama. Satu-satunya pengecualian adalah kelas cangkang (`husk`, `usk`) karena setiap
objek punya kulit luar dan `Cindrusk` dibangun begitu; bulu tidak ikut — `Dracopelt`
pada naga bersisik adalah janji yang sama. **Plastik menarik morfem tekstil:**
`Pixlyarn` lahir karena plastic/cloth/paper berbagi keluarga `drape`, jadi `yarn`,
`twill`, dan `eider` dibuang dan diganti `arc`, `sheath`, `ridge`. **Memilih rentang
bit hash masih tebakan:** `seed % 4` harus menjadi `seed >>> 24` di v40 dengan sebab
yang sama seperti `seed >>> 8` memberi tiga dari enam Anima ekor Adult identik di
sini, jadi `mixNameSeed()` menjalankan satu finalizer lowbias32 atas seluruh 32 bit
dan modulo apa pun aman — terukur atas dua puluh empat head ber-Plan identik, ekor
berbeda naik dari 9/24 menjadi 12–15/24. **Elisi bisa menghancurkan morfemnya:**
`Dracolder` menyisakan `lder` yang bukan suku kata, jadi potongan elisi wajib
dibuka satu konsonan lalu vokal — `elisk`→`lisk` dan `adon`→`don` tetap lolos.
Hasil enam subjek: `Pixlusk`→`Pixlward`→`Pixlfold`, `Vitrore`→`Vitrforge`→
`Vitrsovran`, `Thrumridge`→`Thrumadon`→`Thrumzard`, `Resonforge`→`Resonvein`→
`Resondoom`, `Fenessap`→`Fenesbastion`→`Feneszenith`, `Dracosting`→`Dracocoil`→
`Dracopex`; enam ekor berbeda dari enam di ketiga stage, suku kata tersebar 2/3/4.
**Operator menyetujui ronde ketiga dan v41 dikunci player-live 19 Agustus 2026**
untuk capture maupun evolution; detail dan angka di
[`docs/designs/2026-08-19-anima-name-lineage-v41.md`](docs/designs/2026-08-19-anima-name-lineage-v41.md).

Sugarworks v6 sudah production dengan sembilan nama
spesies baru dan aset v5 yang direuse seperti dicatat di atas. Detail ada di
[`docs/designs/2026-08-19-anima-name-lineage-v39.md`](docs/designs/2026-08-19-anima-name-lineage-v39.md);
provenance reject v38 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v38.md`](docs/designs/2026-08-19-anima-name-lineage-v38.md);
provenance reject v37 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v37.md`](docs/designs/2026-08-19-anima-name-lineage-v37.md);
provenance reject v36 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v36.md`](docs/designs/2026-08-19-anima-name-lineage-v36.md);
provenance reject v35 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v35.md`](docs/designs/2026-08-19-anima-name-lineage-v35.md);
provenance reject v34 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v34.md`](docs/designs/2026-08-19-anima-name-lineage-v34.md);
provenance reject v33 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v33.md`](docs/designs/2026-08-19-anima-name-lineage-v33.md);
provenance reject v32 tetap di
[`docs/designs/2026-08-19-anima-name-lineage-v32.md`](docs/designs/2026-08-19-anima-name-lineage-v32.md).
Client Scan mengirim `capture_vibe`; server menolak nilai di luar allowlist
sebelum Vision, menolak non-Natural saat prompt < v31 (`VIBE_UNAVAILABLE`),
dan mengunci vibe di `generations.capture_vibe` pada claim pertama. Eval
Monstera 18 Agustus 2026 (satu Vision, tiga generation Cute/Brave/Sinister,
nol retry) lulus baca visual operator. Crop pertama gagal karena Cute/Sinister
bocor seam Idle dan Brave kena audit detached-character v26 milik evolusi.
Capture v31 membuang bocoran Idle deterministik dan tidak memakai audit tubuh
terlepas itu; `--reprocess` ketiga raw lulus 9/9 tanpa panggilan model.
