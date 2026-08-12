# CLAUDE.md — konteks untuk AI coding agent

Baca file ini sebelum menyentuh kode Scanima. Update file ini setiap ada perubahan signifikan pada stack, konvensi, atau keputusan arsitektur.

## Apa itu Scanima

Game mobile virtual pet. Pemain memfoto objek nyata, foto itu jadi monster (**Anima**) lewat Vision LLM + image generation. Lalu dirawat gaya Tamagotchi, dievolusikan, dan dipakai bertarung. Detail lengkap di [README.md](README.md) dan [docs/](docs/).

## Aturan yang tidak bisa dinegosiasikan

1. **API key tidak pernah masuk ke build Godot.** Hanya ada satu, `REPLICATE_API_TOKEN`, dan ia hanya hidup di Supabase Edge Function secrets. Client Godot bicara ke Edge Function, bukan ke Replicate. Satu-satunya pengecualian adalah mode BYOK di mana token milik pemain sendiri disimpan lokal di device.
2. **Setiap panggilan image generation berbiaya ~\$0.07.** Default-nya GPT Image 2 medium; biaya berbasis token dan dua run nyata berada di sekitar angka ini. Jangan pernah menulis kode yang bisa memanggil generation dalam loop, retry otomatis tanpa batas, atau tanpa idempotency key. Kalau ragu, jangan panggil.
3. **Semua mata uang bersifat server-authoritative.** Ada tiga: `scan_charges` (Discovery Scan), `genesis_cores` (spesies baru), `bits` (item perawatan). Client boleh menampilkan sisanya, tapi keputusan boleh-tidaknya generate hanya diambil di Postgres dalam transaksi yang sama dengan pencatatan debit. Jangan pernah menambah `genesis_cores` dari callback iklan.
4. **Jangan commit foto pemain, output generation, atau `.env`.** Foto mentah dihapus dari Storage setelah post-processing selesai.

## Konvensi Godot / GDScript

- Godot 4.x, Mobile renderer, project 2D. Root project ada di `game/`.
- File script `snake_case.gd`, nama class `PascalCase`, node `PascalCase`.
- Type hints di mana-mana: `var hp: int = 0`, `func feed(amount: int) -> void:`.
- Referensi node lewat `@onready var sprite: AnimatedSprite2D = %AnimaSprite` (pakai unique name `%`, bukan path panjang yang gampang putus saat scene di-refactor).
- Cek validitas objek dengan `is_instance_valid()` sebelum akses, khususnya untuk node yang bisa di-free saat async request masih jalan.
- Semua state game yang persist lewat satu autoload `GameState`; jangan sebar `save()` ke banyak node.
- Sprite Anima **tidak** diimpor sebagai resource `.import` — datang saat runtime dari server, disimpan di `user://animas/`.

## Konvensi backend

- Supabase Edge Functions berjalan di Deno. Pakai `npm:` specifier hanya untuk paket pure-JS/TS. **Jangan pakai `sharp`** (butuh native binary, tidak jalan di edge runtime); untuk manipulasi piksel pakai `ImageScript`.
- Migrasi SQL di `backend/supabase/migrations/`, satu file per perubahan, tidak pernah diedit setelah di-apply ke remote.
- RLS wajib aktif di semua tabel yang menyimpan data pemain. Edge Function pakai service role key, client pakai anon key.
- Semua endpoint yang menghabiskan uang menerima `idempotency_key` dari client.

## Prompt versioning

Prompt hidup di `backend/prompts/<version>/` sebagai file teks, bukan string literal di dalam kode:

```
backend/prompts/
├── v1/
│   ├── vision_system.md          # system prompt untuk Vision LLM
│   ├── vision_schema.json        # responseSchema Gemini (subset OpenAPI, bukan JSON Schema penuh)
│   ├── sprite_sheet.md           # baseline nano-banana-pro
│   └── sprite_sheet_evolve.md    # varian untuk evolusi, pakai sprite lama sebagai image_input
└── v2/
    ├── vision_system.md          # gate yang sama dengan v1
    ├── vision_schema.json        # kontrak yang sama dengan v1
    ├── sprite_sheet.md           # GPT Image 2 medium + anime cel-shaded style
    └── sprite_sheet_evolve.md
```

`vision_schema.json` **tidak** dikirim sebagai parameter API — ia disisipkan ke `system_instruction`, sebab wrapper Gemini di Replicate tidak punya `response_schema`. Notasinya tetap subset OpenAPI (`"nullable": true`, bukan `["string", "null"]`, tanpa `pattern`) supaya file yang sama bisa langsung dipakai kalau nanti pindah ke Gemini API langsung. Bentuk data ditegakkan `extractJson()` dan `validateVision()` di `eval/run.mjs`, bukan diharapkan dari model.

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md) dan sumber art direction v2 ada di [docs/monster_camera_anime_cel_shaded_style_guide.md](docs/monster_camera_anime_cel_shaded_style_guide.md). Jangan mengarang aturan style baru; konsistensi visual antar Anima bergantung pada style lock itu.

## Fakta teknis yang mudah salah

- **Jalur image production tidak punya alpha.** Runtime `openai/gpt-image-2` menolak `background: "transparent"` dengan `invalid_value` walaupun opsi itu tercantum di schema wrapper; nano-banana-pro juga tidak memberi alpha yang bisa diandalkan. Transparansi tetap berasal dari chroma key `#00FF00` + post-processing.
- **Vision dan image generation dua-duanya lewat Replicate**, bukan API provider langsung. Default Vision `google/gemini-2.5-flash`; default gambar `openai/gpt-image-2` dengan `quality: "medium"`, `aspect_ratio: "1024x1024"`, dan `background: "opaque"`. Jangan tambahkan `GEMINI_API_KEY` atau `OPENAI_API_KEY`; satu token Replicate tetap cukup.
- **Wrapper Gemini di Replicate tidak punya `response_schema`.** Parameter yang tersedia cuma `prompt`, `images`, `videos`, `system_instruction`, `temperature`, `top_p`, `max_output_tokens`, `thinking_budget`, `dynamic_thinking`. Jadi JSON valid tidak dijamin API: kontrak skema disisipkan ke `system_instruction`, dan `extractJson()` di `eval/run.mjs` menangani bungkus ```json serta kalimat pengantar. Jangan hapus parser itu dengan asumsi model selalu patuh.
- **Set `thinking_budget: 0` untuk panggilan Vision.** Token thinking ditagih sebagai output, dan tugas ini ekstraksi terstruktur, bukan penalaran. Kalau `dynamic_thinking` true ia menimpa `thinking_budget`, jadi biarkan false.
- **Output wrapper Vision itu array potongan string**, bukan satu string. Harus disambung sebelum di-parse. Model gambar sebaliknya mengembalikan satu URI.
- **`gemini-2.5-flash` retirement 20 Oktober 2026.** Ini plafon yang sudah diketahui, bukan kejutan: `# ponytail: Vision di 2.5-flash karena satu vendor satu token. Plafon 20 Okt 2026; upgrade dengan mengganti env VISION_MODEL ke google/gemini-3-flash, tanpa ubah kode.` Jangan diam-diam mengganti modelnya tanpa menjalankan ulang Smoke Set, karena stat dan `species_key` bisa bergeser.
- **Slicing sheet bukan pembagian grid atau bbox kuadran keras.** GPT Image 2 terbukti menggambar tangan Attack melewati center seam. `segmentPosePixels()` menetapkan komponen alpha 8-connected ke kuadran yang memuat mayoritas pikselnya, menyimpan ownership per piksel, lalu `blitOwned()` menyalin hanya piksel milik pose itu. Mengganti ini dengan crop 512×512 akan memotong tangan/kabel lagi.
- **Halo hijau di tepi TIDAK diperbaiki dengan menurunkan ambang saturasi.** Campuran keyline putih dengan `#00FF00` berbentuk `(t,255,t)` dan bersaturasi bisa hanya 0,5 — untuk menghapusnya lewat ambang, ambangnya harus turun di bawah saturasi hijau daun (0,63) dan tubuh Anima `plant` jadi bolong. Yang dipakai: erosi hanya pada cincin 1px terluar (harus bertetangga piksel transparan) dengan syarat `g >= 220` dan hijau dominan. Terukur menurunkan residu dari 0,21% ke 0,014%. Lihat `isKeyContaminatedEdge()` di `eval/postprocess.mjs`.
- **Ambang chroma key harus ketat: `sat > 0.85`, `val > 0.5`.** Resep chroma key umum memakai 0,3 dan itu akan **melubangi tubuh Anima berelemen `plant`**, karena hijau daun `rgb(60,160,70)` punya saturasi 0,63 dan hue 126°. Nilai ini muncul di tiga tempat dan harus selalu sama: `eval/postprocess.mjs`, `game/shaders/chroma_key.gdshader`, dan Edge Function nanti.
- **Keempat region wajib berukuran sama.** `AnimatedSprite2D` cuma punya satu `offset` untuk seluruh animasi, jadi region yang ukurannya beda membuat sprite tersentak berpindah tiap ganti pose. `AnimaLoader` menolak manifest yang melanggar ini; jangan "perbaiki" dengan melonggarkan pemeriksaannya.
- **Jangan mengukur konsistensi skala dari varians keempat pose.** Pose Sleep memang jauh lebih pendek daripada Idle, jadi metrik itu memberi alarm palsu terus-menerus. Bandingkan Idle vs Attack saja (`standing_height_variance`).
- **Latensi GPT Image 2 medium terukur 57–63 detik** untuk dua sheet 1024×1024; desain incubator tetap harus menganggap sekitar satu menit dan tahan app masuk background. Quality high terukur ~153 detik dan tidak dipakai.
- **GPT Image 2 medium dipilih setelah perbandingan nyata.** Medium memakai 1.756 output token dan ~57–63 detik; high memakai 7.024 output token dan ~153 detik tanpa lompatan kualitas yang sebanding. Jangan naikkan quality diam-diam.
- **nano-banana-pro tetap rollback/A-B saja** lewat `IMAGE_MODEL`; model itu pernah berulang kali memberi `ModelRateLimitError (E003)`. Kalau dipakai lagi, resolusi 1K dan 2K berharga sama sehingga minta `"2K"`.

## Perintah umum

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

```bash
# gratis, jalankan ini dulu
npm run selftest                       # 17 skenario, termasuk lintas center seam
godot --headless --path game --script res://tests/test_sprite_slicing.gd
node eval/run.mjs --set smoke --dry-run # cek foto + template tanpa API

# kontrak Node <-> Godot, juga gratis
node eval/selftest.mjs --emit /tmp/scanima_e2e
godot --headless --path game --script res://tests/test_sprite_slicing.gd \
    -- --manifest=/tmp/scanima_e2e/manifest.json

# game
godot --path game                      # demo, pakai sheet placeholder
godot --path game -- --manifest=<abs>.json --pose=sleep --screenshot=/tmp/a.png
godot --headless --path game --import  # rebuild cache class, cek parse error

# eval prompt, BERBIAYA
node eval/run.mjs --set smoke --vision-only  # gate + stat saja, ~$0.015
node eval/run.mjs --set smoke                # 5 foto, ~$0.225, untuk iterasi
node eval/run.mjs --set full                 # 20 foto, ~$1.32, gerbang penerimaan

# backend lokal, Phase 2
cd backend && supabase start
supabase functions serve create_anima --env-file .env.local
```

Default-nya `smoke`, prompt `v2`, dan GPT Image 2 `medium`. Jangan jalankan `full` sebagai bagian dari iterasi biasa — ia enam kali lebih mahal dan tidak memberi informasi tambahan sampai Smoke Set sudah bersih. Sebelum memicu satu pun generation gambar, `--vision-only` sudah cukup untuk menguji gate keamanan dan pemetaan stat dengan biaya ~$0.015.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`
