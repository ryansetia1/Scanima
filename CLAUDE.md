# CLAUDE.md — konteks untuk AI coding agent

Baca file ini sebelum menyentuh kode Scanima. Update file ini setiap ada perubahan signifikan pada stack, konvensi, atau keputusan arsitektur.

## Apa itu Scanima

Game mobile virtual pet. Pemain memfoto objek nyata, foto itu jadi monster (**Anima**) lewat Vision LLM + image generation. Lalu dirawat gaya Tamagotchi, dievolusikan, dan dipakai bertarung. Detail lengkap di [README.md](README.md) dan [docs/](docs/).

## Aturan yang tidak bisa dinegosiasikan

1. **API key tidak pernah masuk ke build Godot.** `REPLICATE_API_TOKEN` dan `GEMINI_API_KEY` hanya hidup di Supabase Edge Function secrets. Client Godot bicara ke Edge Function, bukan ke Replicate/Google. Satu-satunya pengecualian adalah mode BYOK di mana token milik pemain sendiri disimpan lokal di device.
2. **Setiap panggilan image generation berbiaya ~$0.134.** Jangan pernah menulis kode yang bisa memanggil generation dalam loop, retry otomatis tanpa batas, atau tanpa idempotency key. Kalau ragu, jangan panggil.
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
│   ├── sprite_sheet.md           # template prompt untuk nano-banana-pro
│   └── sprite_sheet_evolve.md    # varian untuk evolusi, pakai sprite lama sebagai image_input
└── v2/
```

`vision_schema.json` memakai `"nullable": true`, bukan `["string", "null"]`, dan tidak memakai `pattern` — `responseSchema` Gemini hanya menerima subset OpenAPI. Batasan yang tidak bisa diungkapkan di skema ditegakkan di `validateVision()` pada `eval/run.mjs`, bukan diharapkan dari model.

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md). Jangan mengarang aturan style baru; style lock sudah didefinisikan di sana dan konsistensi visual antar Anima bergantung padanya.

## Fakta teknis yang mudah salah

- **Model image tidak bisa menghasilkan alpha channel.** Minta "transparent background" ke nano-banana-pro akan menghasilkan piksel putih solid atau checkerboard yang dilukis. Transparansi didapat dari chroma key hijau `#00FF00` + post-processing. Jangan hapus langkah ini dengan asumsi model bisa diperbaiki lewat prompt.
- **`gemini-1.5-flash` sudah mati** (404). Model Vision saat ini `gemini-3.1-flash-lite`. `gemini-2.5-flash` retirement 20 Oktober 2026, jangan jadikan target baru.
- **Slicing sheet bukan pembagian grid buta.** Model tidak selalu menaruh subjek tepat di tengah kuadran; pakai bbox berbasis alpha. Region final datang dari `manifest.json`, dan Godot hanya membacanya.
- **Ambang chroma key harus ketat: `sat > 0.85`, `val > 0.5`.** Resep chroma key umum memakai 0,3 dan itu akan **melubangi tubuh Anima berelemen `plant`**, karena hijau daun `rgb(60,160,70)` punya saturasi 0,63 dan hue 126°. Nilai ini muncul di tiga tempat dan harus selalu sama: `eval/postprocess.mjs`, `game/shaders/chroma_key.gdshader`, dan Edge Function nanti.
- **Keempat region wajib berukuran sama.** `AnimatedSprite2D` cuma punya satu `offset` untuk seluruh animasi, jadi region yang ukurannya beda membuat sprite tersentak berpindah tiap ganti pose. `AnimaLoader` menolak manifest yang melanggar ini; jangan "perbaiki" dengan melonggarkan pemeriksaannya.
- **Jangan mengukur konsistensi skala dari varians keempat pose.** Pose Sleep memang jauh lebih pendek daripada Idle, jadi metrik itu memberi alarm palsu terus-menerus. Bandingkan Idle vs Attack saja (`standing_height_variance`).
- **Latensi generation 15-45 detik**, bukan 5-10. UI incubator harus tahan durasi itu dan tahan app masuk background.
- Resolusi 1K dan 2K berharga sama di nano-banana-pro, jadi selalu minta `"2K"`.

## Perintah umum

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

```bash
# gratis, jalankan ini dulu
npm run selftest                       # 14 pemeriksaan post-processing
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
node eval/run.mjs --set smoke --vision-only  # gate + stat saja, ~$0.002
node eval/run.mjs --set smoke                # 5 foto, ~$0.40, untuk iterasi
node eval/run.mjs --set full                 # 20 foto, ~$2,41, gerbang penerimaan

# backend lokal, Phase 2
cd backend && supabase start
supabase functions serve create_anima --env-file .env.local
```

Default-nya `smoke`. Jangan jalankan `full` sebagai bagian dari iterasi biasa — ia enam kali lebih mahal dan tidak memberi informasi tambahan sampai Smoke Set sudah bersih. Sebelum keduanya, setel kata-kata prompt manual di aplikasi Gemini: itu gratis. Dan sebelum menyentuh Replicate sama sekali, `--vision-only` sudah cukup untuk menguji gate keamanan dan pemetaan stat, dengan biaya seperseratus.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`
