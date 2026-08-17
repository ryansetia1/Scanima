# Evolution Maturity and Apex Presence v24

Status: diimplementasikan dan diuji 17 Agustus 2026; maturity lulus, tetapi
visual clarity dan Evolved technical gate ditolak. Digantikan desain v25 di
[Evolution Pokémon-like Visual Clarity v25](2026-08-17-evolution-pokemon-clarity-v25.md).
Capture production tetap v20, evolution production tetap v21, dan
`feature_evolution=false`.

## Masalah

V23 berhasil memperbaiki kehilangan soul pada Evolved Veridian: dua mata
ekspresif, senyum, dan motif Monstera tetap terbaca dalam silhouette aerial yang
distinct. Namun hasilnya masih terlihat seperti karakter muda yang mendapat
sayap dan tentakel. Massa inti kecil, appendage tipis, serta pose ringan membuat
form itu terasa lincah dan rapuh, bukan payoff Lv36 yang kuat, megah,
supernatural, dan dapat diandalkan.

Adult v22 juga distinct, tetapi wajah dan proporsinya belum menunjukkan
kematangan yang cukup dari Hatchling. Identity Invariants v23 mengunci soul,
tetapi `source_truth` yang terlalu literal dapat ikut membekukan geometri wajah
Hatchling.

## Hasil eval v23

Satu eval Evolved dari Adult v22 yang sudah disetujui memakai:

- Vision `j5h7znae15rmw0d021srrzkvhw`, 22 detik;
- GPT Image 2 medium `cpaew95acnrmr0d021sr60pwm4`, 90 detik;
- estimasi biaya konservatif $0,073;
- tiga Identity Invariants: dua mata ekspresif, senyum lembut, dan daun
  Monstera berfenestrasi;
- archetype `unfolding`, dengan carapace berubah menjadi sayap dan root-leg
  menjadi tendril;
- 9/9 sel, seam 12% lulus, dan standing variance 2,2%.

Kandidat itu **silhouette pass** dan **soul pass**, tetapi **maturity/apex
reject**. Ia juga **technical reject**: broad green residue 3,025% dan
643/41.433 piksel cincin alpha (1,5519%) masih bright-chroma, terutama pada
Attack dan `fx_strike`. Model mengikuti brief Vision `shimmering green toxin`
meskipun template gambar telah melarang luminous green. Tidak ada retry
berbayar otomatis.

## Hasil eval v24

Adult v24:

- Vision `da4r09rmn9rmr0d0228tnss7jc`, 27 detik;
- GPT Image 2 medium `ytw3r0bmnsrmr0d022aadacanr`, 92 detik;
- 9/9 sel, seam lulus, standing variance 1,2%;
- hanya 3/33.268 piksel outer ring bright-chroma;
- soul, maturity, style, dan technical gate lulus;
- visual clarity ditolak karena terlalu banyak leaf cluster, vein, root-finger,
  pebble joint, glow, dan fragmen kecil.

Evolved v24:

- Vision `cped0vsg3drmr0d022bsq5cn2w`, 29 detik;
- GPT Image 2 medium `7gqdw557msrmt0d022bvxgkke0`, 71 detik;
- soul dan ancient-power read bertahan;
- wajah masih terlalu dekat dengan Adult dan detail makin padat;
- post-process menolak tiga detached Idle fragment 27px/50px/32px dekat seam.

Root cause-nya ada di Plan serta template v24 sendiri: `more numerous`,
`deeply textured`, `multi-tiered`, `gnarled`, dan aura permanen mengakumulasi
detail. Tidak ada retry berbayar otomatis.

## Understanding lock historis v24

- Adult Lv16 harus terlihat lebih matang daripada Hatchling pada wajah, tubuh,
  material, dan postur.
- Evolved Lv36 harus menjadi payoff grinding: sangat kuat, megah, majestic,
  supernatural, dan dapat diandalkan.
- Soul dikunci secara semantik. Geometri wajah boleh dan wajib berkembang
  selama jumlah/relationship fitur serta emotional identity tetap terbaca.
- Aura supernatural menjadi penanda utama Evolved, tetapi harus memperkuat
  anatomi dan pusat kekuatan, bukan menggantikannya.
- Kontrak berlaku sama untuk semua Anima. Vision menerjemahkannya dari material,
  struktur, dan personality sumber; tidak ada hardcode sayap, halo, mahkota,
  humanoid, atau Veridian.
- Siluet setiap stage tetap distinct. Appendage atau aura tidak boleh
  menenggelamkan massa inti.
- Runtime tetap satu Vision dan satu image generation per stage, tanpa critic
  tambahan atau retry otomatis.

## Asumsi dan non-goal

Asumsi:

- Adult adalah kematangan menengah; Evolved adalah bentuk matang/apex.
- Aura boleh menonjol pada pose normal selama berbentuk jelas, berada di safe
  envelope, dan tidak mengganggu wajah atau silhouette.
- Perubahan ini hanya menyentuh kontrak art. Formula stat, syarat Level,
  idempotency, privacy, dan spend cap tidak berubah.
- Tambahan token Plan tetap kecil dibanding latensi image generation.

Non-goal:

- menyamakan semua Evolved menjadi bersayap, memakai halo, atau bergaya dewa;
- memakai glow besar untuk memalsukan rasa kuat;
- membuat semua wajah galak atau menghapus personality lama;
- menambah post-generation model critic pada v24;
- mengubah mekanik pemain sebelum seluruh gate rollout evolusi lulus.

## Pendekatan yang dipilih

V24 menambah **Structured Maturity + Apex Presence Contract** pada Evolution
Plan. Prompt-only ditolak karena tidak dapat membuktikan Plan memahami
kematangan dan presence sebelum image spend. Vision critic kedua disimpan
sebagai future improvement karena menambah biaya, latensi, dan kebijakan retry.

Tidak diperlukan tabel atau migrasi baru. Field baru tetap disimpan di
`generations.vision_result` dan divalidasi oleh shared evolution validator.

## Kontrak data

Setiap Plan v24 membawa:

```jsonc
{
  "maturity_contract": {
    "target_read": "adult",
    "facial_maturation": "The paired eyes become longer and more composed...",
    "body_maturation": "The body develops a stronger load-bearing core...",
    "posture_maturation": "The stance becomes deliberate and stable...",
    "preserved_personality": "The warm, curious confidence remains...",
    "stage_delta": "No baby head-to-body ratio or tentative posture remains..."
  },
  "presence_contract": {
    "presence_tier": "developing",
    "power_center": "A dense ceramic-root heart beneath the canopy...",
    "mass_hierarchy": "The torso core remains dominant over appendages...",
    "authority_pose": "A planted, calm pose with controlled limbs...",
    "aura_architecture": "An amber orbit contained behind the body...",
    "aura_palette": ["amber", "violet"],
    "grandeur_cues": [
      "source-derived mantle geometry",
      "large stable power center"
    ],
    "reliability_cue": "Four thick supports visibly carry the body..."
  }
}
```

`maturity_contract.target_read` wajib `adult` untuk stage 2 dan `apex` untuk
stage 3. `presence_tier` wajib `developing` untuk Adult dan `apex` untuk
Evolved.

Identity Invariant v24 menambah:

```jsonc
{
  "maturation_path": "The two eyes may lengthen and gain a stronger brow; their count, separation, green gaze, and warm alert identity remain."
}
```

`maturation_path` dipilih saat Adult dari fakta Hatchling, lalu dikunci bersama
`identity_id`, `domain`, `source_truth`, `identity_role`, dan
`evolved_policy`. `current_expression` tetap berubah per stage.

## Validasi

Validator v24 wajib menegakkan:

1. Seluruh field maturity/presence non-kosong dan tier sesuai target stage.
2. Ada 2–4 Identity Invariants; masing-masing memiliki `maturation_path`.
3. Evolved membawa invariant semantic dan maturation path yang identik dengan
   Adult setelah normalisasi.
4. `grandeur_cues` memuat minimal dua entri non-duplikat.
5. `aura_palette` memuat satu atau dua warna dari allowlist:
   `gold`, `amber`, `orange`, `crimson`, `rose`, `magenta`, `violet`,
   `indigo`, `blue`, atau `pale_cyan`.
6. Teks aura, Attack VFX, dan Special VFX menolak `green`, `lime`,
   `chartreuse`, `emerald`, serta sinonim near-chroma. Hijau alami tetap boleh
   pada anatomi tubuh.
7. Plan Evolved menyatakan satu `power_center`, massa inti yang dominan,
   authority pose, dan reliability cue.
8. Stored Plan pada resume divalidasi ulang sebelum image generation.
9. Seluruh pagar v22 Silhouette Delta dan v23 Soul Contract tetap berlaku.

Field deskriptif tidak menghitung stat. Validator hanya memastikan arah desain
lengkap dan aman sebelum spend gambar.

## Kontrak prompt

Prioritas image prompt v24:

1. layout, seam, chroma, dan pose safety;
2. semantic soul;
3. stage maturity;
4. apex presence;
5. silhouette delta;
6. detail dekoratif.

Adult wajib meninggalkan baby proportions tanpa kehilangan personality. Aura
baru terlihat sebagai kekuatan yang mulai bangun. Evolved wajib memiliki
komposisi apex: wajah matang, pusat kekuatan besar, pose Idle tenang-dominan,
aura menonjol, dan appendage yang mendukung massa inti.

Yang tidak dihitung sebagai maturity/apex:

- wajah sama dengan aksesori baru;
- mata dibuat galak tanpa perkembangan struktur wajah;
- lebih besar, lebih banyak, lebih tajam, atau lebih bercahaya saja;
- sayap/tentakel yang membuat core terlihat kecil;
- aura kabur generik tanpa arsitektur;
- mahkota, halo, armor, atau humanoid sebagai shortcut.

Aura boleh berupa mantle, orbit, corona, current, veil, atau struktur lain yang
diturunkan dari sumber. Bentuk itu bukan katalog wajib dan tidak boleh membuat
semua Anima homogen.

## Visual review

Setiap lineage candidate melewati:

### Soul gate

- 2–4 invariant tetap terlihat dan recognizable;
- perubahan wajah mengikuti `maturation_path`;
- personality/emotional role tidak hilang;
- aturan `transfigure` v23 tetap terpenuhi.

### Maturity gate

Face dan body crop Hatchling, Adult, serta Evolved dibandingkan pada ukuran
setara. Tanpa label stage, reviewer harus dapat mengurutkan ketiganya dari
paling muda ke paling matang.

### Apex gate

Pada 96 px, Evolved harus jelas terbaca sebagai:

- form terkuat;
- form termegah dan paling supernatural;
- form yang stabil serta dapat diandalkan;
- satu tubuh dengan aura pendukung, bukan tubuh kecil di balik efek.

### Technical gate

- 9/9 sel dan seam audit lulus;
- bright-chroma alpha-edge ratio di bawah 0,1%;
- broad green residue hanya informasi untuk subjek plant;
- tidak ada thought bubble, simbol UI, aura bocor, atau VFX pada sel karakter;
- Godot Idle tetap terbaca pada ukuran game.

## Rollout

1. Simpan v21–v23 immutable untuk rollback dan provenance.
2. Implementasikan v24 serta jalankan bundle, validator, compatibility, dan
   resume tests gratis.
3. Generate satu Adult v24 dari Hatchling Monstera.
4. Hanya setelah Adult lulus soul, maturity, silhouette, dan technical gate,
   generate satu Evolved v24 dari Adult itu.
5. Tidak ada retry otomatis. Estimasi lineage eval penuh sekitar $0,146, tetapi
   spend kedua baru dilakukan setelah Adult diterima.
6. Sesudah plant lineage lulus, eval satu fauna dan satu object/illustration.
7. Production config, client minimum, backfill `evolution_version=1`, dan
   `feature_evolution` tetap gate terpisah.

Wiki pemain tidak berubah karena evolusi belum player-live.

## Decision log

- Structured contract dipilih dibanding prompt-only agar kegagalan arah desain
  berhenti sebelum image spend.
- Semantic identity dikunci, sedangkan geometri mengikuti maturation path,
  supaya soul bertahan tanpa baby face.
- Aura-forward dipilih untuk payoff Evolved, tetapi anatomy dan mass hierarchy
  tetap fondasi agar form tidak rapuh.
- Aura/VFX green dilarang di Plan, bukan hanya template gambar, karena eval v23
  membuktikan brief Vision yang lebih spesifik mengalahkan negative instruction.
- Adult digenerate ulang sebelum Evolved karena kematangan harus terbaca sebagai
  tangga tiga stage, bukan diperbaiki hanya pada endpoint.
- Vision critic kedua ditunda sampai sampling lintas subject membuktikan kontrak
  terstruktur masih sering dilanggar.
- Eval v24 membatalkan keputusan aura-forward dan detail-as-presence. V25
  menghapus aura dari seluruh character cells dan menggantinya dengan Shape
  Budget, anatomy-agnostic focal maturity, serta VFX-only supernatural power.
