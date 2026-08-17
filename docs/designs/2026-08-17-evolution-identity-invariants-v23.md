# Evolution Identity Invariants v23

Status: desain, implementasi, dan test gratis selesai 17 Agustus 2026. Satu eval
Evolved membuktikan soul contract, tetapi kandidat ditolak karena maturity/apex
presence dan bright-chroma. V23 tidak dipromosikan. Capture tetap v20,
production evolution tetap v21, dan `feature_evolution=false`.

## Masalah

Adult Monstera v22 berhasil mengubah body plan dan siluet tanpa kehilangan
karakter Hatchling. Evolved v22 juga distinct dan powerful, tetapi mengganti dua
mata ekspresif dengan satu core/aperture. Siluetnya lulus arah desain, namun
"soul" lineage hilang.

`lineage_anchors` v22 menjaga asal struktur dan material, tetapi tidak mengunci
fitur yang membawa identity read seperti jumlah mata, relationship sensor, atau
ekspresi. V23 menambah kontrak semantic identity yang terpisah dari Silhouette
Delta Contract.

## Understanding lock

- Vision memilih 2–4 Identity Invariants dari Hatchling ketika merancang Adult.
- Evolved mewarisi daftar itu dan tidak boleh memilih identitas baru.
- Invariant boleh matang tanpa harus mempertahankan geometri literal.
- Maksimal satu invariant boleh berubah ekstrem dengan mode `transfigure`.
- `transfigure` hanya sah bila total invariant minimal tiga, turunannya tetap
  terlihat jelas, dan minimal dua invariant lain tetap utuh.
- Siluet, posture, mass distribution, locomotion, dan body plan tetap boleh
  berubah radikal.
- Untuk sumber yang memiliki wajah atau sensor, minimal satu identity read
  wajah/sensor harus tetap dipertahankan.
- Tidak ada model call, image candidate, atau retry otomatis tambahan.

## Pendekatan yang dipilih

Identity Invariants hidup sebagai data terstruktur di Evolution Plan yang sudah
disimpan dalam `generations.vision_result`. Pendekatan ini tidak membutuhkan
tabel atau migrasi baru dan dapat divalidasi sebelum image generation berbayar.

Alternatif prompt-only ditolak karena tidak dapat mendeteksi drift plan.
Lineage identity profile terpisah dicatat sebagai future improvement untuk
branching evolution atau jumlah stage yang lebih banyak.

## Kontrak data

Setiap plan v23 membawa:

```json
{
  "identity_invariants": [
    {
      "identity_id": "paired_expressive_eyes",
      "domain": "face_expression",
      "source_truth": "Exactly two separate visible eyes form the primary face.",
      "identity_role": "A gentle, alert, companion-like gaze.",
      "current_expression": "The paired eyes mature into sharper but warm leaf-framed eyes.",
      "evolved_policy": "preserve",
      "realization_mode": "preserve",
      "visible_lineage_evidence": "Both eyes remain separate, readable, and emotionally expressive."
    }
  ]
}
```

Domain allowlist awal:

- `face_expression`
- `sensory`
- `structural_motif`
- `surface_signature`
- `motion_language`

Field yang dikunci setelah Adult Plan:

- `identity_id`
- `domain`
- `source_truth`
- `identity_role`
- `evolved_policy`

Field yang boleh berubah per-stage:

- `current_expression`
- `realization_mode`
- `visible_lineage_evidence`

`evolved_policy` bernilai `preserve` atau `may_transfigure`.
`realization_mode` bernilai `preserve` atau `transfigure`. Adult wajib
`preserve` untuk semua invariant. Evolved hanya boleh memakai `transfigure`
pada invariant yang sebelumnya diberi policy `may_transfigure`.

## Validasi

Validator v23 wajib menegakkan:

1. Ada 2–4 invariant dengan `identity_id` slug yang unik.
2. Semua enum dinormalisasi dan semua field semantic tidak kosong.
3. Maksimal satu `may_transfigure`; bila ada, total invariant minimal tiga.
4. Adult memakai `realization_mode=preserve` untuk seluruh invariant.
5. Evolved memiliki ID set, domain, source truth, identity role, dan policy yang
   sama dengan Adult setelah normalisasi case dan whitespace.
6. Urutan array bukan identitas. Validator mencocokkan berdasarkan
   `identity_id`, lalu mengembalikan urutan kanonis Adult.
7. Maksimal satu `transfigure`, hanya pada policy `may_transfigure`, dan minimal
   dua invariant lain tetap `preserve`.
8. Jika prior plan membawa domain `face_expression` atau `sensory`, minimal satu
   invariant dari kelompok itu tetap `preserve`.
9. `transfigure` wajib menyebut ekspresi baru dan bukti turunan visual. Nilai
   yang hanya mengatakan hidden, lost, atau implied ditolak.
10. Plan v23 Evolved tanpa prior Identity Invariants ditolak eksplisit sebelum
    image generation.
11. Stored plan pada resume divalidasi ulang dengan prior plan yang sama.

V21 dan v22 tetap memakai kontrak validator lamanya.

## Data flow

Adult:

```text
crop Idle Hatchling
  → Vision Plan v23 memilih 2–4 invariant + silhouette plan
  → validator Adult
  → image prompt
  → satu image generation
  → technical QA
```

Evolved:

```text
crop Idle Adult + Identity Invariants Adult Plan
  → Vision Plan v23 menyelesaikan invariant yang sama
  → validator membandingkan prior/current plan
  → image prompt
  → satu image generation
  → technical QA
```

Plan invalid berhenti sebelum spend image. Privasi, idempotency, lease,
spend cap, cleanup, dan aturan no-Core tidak berubah.

## Kontrak prompt

Vision Adult hanya memilih fitur Hatchling yang benar-benar terlihat, bukan
anatomi generik, pose sementara, atau VFX. `source_truth` menyatakan fakta visual
objektif, sedangkan `identity_role` menyatakan character/emotional read yang
dibawa fitur itu.

Vision Evolved menerima invariant terkunci dan dilarang memilih ulang,
menyatukan, menutupi, atau menggantinya dengan simbol abstrak.

Prioritas image prompt:

1. layout, safety, dan chroma contract;
2. Identity Invariants;
3. Silhouette Delta Contract;
4. detail, ornamentasi, dan polish.

Untuk invariant `preserve`, prompt melarang:

- dua mata menjadi satu core atau aperture;
- wajah diganti mask atau armor;
- fitur hanya tersirat tetapi tidak terlihat;
- jumlah atau relationship fitur berubah;
- emotional read menjadi kosong atau antagonistik tanpa dasar lineage.

`Transfigure` tetap wajib memiliki turunan visual yang dapat ditunjuk.
Silhouette contract tetap mewajibkan minimal dua changed dimensions dan tidak
boleh mundur menjadi form lama yang hanya diberi aksesori.

V23 juga membawa `FOREGROUND GREEN SAFETY`: bright/neon/luminous green tidak
boleh dipakai pada foreground atau VFX karena warna itu bertabrakan dengan
transport chroma `#00FF00`.

## Versioning dan kompatibilitas

V22 dipertahankan sebagai provenance prompt yang menghasilkan Adult approved
dan Evolved pertama. Green-safety hardening yang ditulis setelah eval dipindah
ke v23 agar artifact v22 dapat direproduksi.

Tidak ada form Adult production v22 karena feature masih off. Untuk eval lokal
Monstera, satu Vision v23 pada Hatchling memilih invariant, lalu Adult v22 yang
sudah disetujui tetap dipakai sebagai image reference Evolved. Adult tidak
digenerate ulang.

## Visual review

Selain lineage silhouette panel, eval v23 membuat `identity-review.png` berisi:

- Hatchling, Adult, dan Evolved berwarna;
- close-up area wajah atau sensory;
- silhouette ketiga stage;
- daftar invariant beserta realization mode;
- checklist visible, recognizable, emotional role retained, dan transfigure
  descendant clear.

Metrics siluet tetap otomatis. Identity pass adalah keputusan manusia saat
promosi candidate; tool tidak mengklaim dapat mengukur "soul" dari piksel.

## Verification dan paid eval

Test gratis:

- validator Adult/Evolved happy path;
- invariant drift, missing prior plan, transfigure tanpa eligibility, kurang
  dari dua preserve, dan kehilangan face/sensory read ditolak;
- array reorder dinormalisasi ke urutan Adult;
- stored plan resume divalidasi ulang;
- kontrak v21/v22 tetap lulus;
- prompt bundle tidak stale, capture v20 tetap identik, green-safety ada, dan
  nama franchise tidak masuk prompt.

Paid eval sempit:

1. satu Vision v23 pada Hatchling Monstera, sekitar $0.003;
2. satu GPT Image 2 medium Evolved dari Adult approved, pagar konservatif
   sekitar $0.07;
3. technical QA, lineage silhouette review, identity review, dan render Godot;
4. tidak ada auto-retry bila candidate ditolak.

## Hasil eval v23

Eval Evolved memakai Adult v22 approved sebagai reference dan satu Vision bridge
untuk memilih tiga invariant dari Hatchling:

- Vision `j5h7znae15rmw0d021srrzkvhw`, 22 detik;
- GPT Image 2 medium `cpaew95acnrmr0d021sr60pwm4`, 90 detik;
- estimasi biaya konservatif $0,073;
- 9/9 sel, seam lulus, standing variance 2,2%;
- dua mata, senyum lembut, dan daun Monstera tetap terbaca;
- archetype aerial `unfolding` memberi siluet distinct dari Adult crawler.

Kandidat ini **silhouette pass** dan **soul pass**, tetapi **maturity/apex
reject**: pusat tubuh terlalu kecil, tendril tipis, serta wajah dan proporsi
masih terasa seperti Hatchling yang mendapat sayap. Ia juga **technical reject**:
643/41.433 piksel alpha-edge (1,5519%) bright-chroma, terutama Attack dan
`fx_strike`. Vision Plan menulis `shimmering green toxin`, sehingga instruksi
spesifik itu mengalahkan green-safety umum pada template gambar.

Tidak ada retry otomatis. V23 digantikan oleh desain
[Evolution Maturity and Apex Presence v24](2026-08-17-evolution-maturity-apex-presence-v24.md).
Production config, feature flag, backfill, dan wiki pemain tidak berubah.

## Future improvement

- Simpan lineage identity profile terpisah ketika branching evolution atau lebih
  dari dua stage membutuhkan sumber kebenaran lintas banyak plan.
- Tambahkan post-generation semantic Vision verifier bila sampling menunjukkan
  image model masih sering melanggar plan. Itu akan menjadi call berbayar
  tambahan dan bukan bagian v23 awal.
