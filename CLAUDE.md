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
│   ├── vision_system.md      # system prompt untuk Vision LLM
│   └── sprite_sheet.md       # template prompt untuk nano-banana-pro
└── v2/
```

Setiap row di tabel `generations` menyimpan `prompt_version`. Ini yang memungkinkan A/B test dan rollback ketika kualitas art turun. Kalau mengubah prompt, buat versi baru — jangan edit versi yang sudah dipakai produksi.

Spesifikasi isi prompt ada di [docs/02-prompt-engineering.md](docs/02-prompt-engineering.md). Jangan mengarang aturan style baru; style lock sudah didefinisikan di sana dan konsistensi visual antar Anima bergantung padanya.

## Fakta teknis yang mudah salah

- **Model image tidak bisa menghasilkan alpha channel.** Minta "transparent background" ke nano-banana-pro akan menghasilkan piksel putih solid atau checkerboard yang dilukis. Transparansi didapat dari chroma key hijau `#00FF00` + post-processing. Jangan hapus langkah ini dengan asumsi model bisa diperbaiki lewat prompt.
- **`gemini-1.5-flash` sudah mati** (404). Model Vision saat ini `gemini-3.1-flash-lite`. `gemini-2.5-flash` retirement 20 Oktober 2026, jangan jadikan target baru.
- **Slicing sheet bukan pembagian grid buta.** Model tidak selalu menaruh subjek tepat di tengah kuadran; pakai bbox berbasis alpha. Region final datang dari `manifest.json`, dan Godot hanya membacanya.
- **Latensi generation 15-45 detik**, bukan 5-10. UI incubator harus tahan durasi itu dan tahan app masuk background.
- Resolusi 1K dan 2K berharga sama di nano-banana-pro, jadi selalu minta `"2K"`.

## Perintah umum

```bash
# backend lokal
cd backend && supabase start
supabase functions serve create_anima --env-file .env.local
supabase db reset                      # re-apply semua migrasi

# game
godot --path game                      # buka editor
godot --path game --headless --quit    # cek project error tanpa GUI

# eval prompt
node eval/run.mjs --prompt-version v2 --set smoke  # 5 foto, ~$0.40, untuk iterasi
node eval/run.mjs --prompt-version v2 --set full   # 20 foto, ~$2,41, gerbang penerimaan
```

Default-nya `smoke`. Jangan jalankan `full` sebagai bagian dari iterasi biasa — ia enam kali lebih mahal dan tidak memberi informasi tambahan sampai Smoke Set sudah bersih. Dan sebelum keduanya, setel kata-kata prompt manual di aplikasi Gemini: itu gratis.

## Definition of done untuk perubahan non-trivial

Logika non-trivial meninggalkan satu pemeriksaan yang bisa dijalankan: hal terkecil yang gagal kalau logikanya rusak. Tidak perlu framework atau fixture. Contoh yang cukup: satu script assert untuk fungsi chroma key + bbox, atau satu scene Godot yang memuat manifest contoh dan memastikan keempat region terpasang. One-liner sepele tidak butuh test.

Tandai penyederhanaan yang disengaja dengan komentar `ponytail:` yang menyebut plafonnya dan jalur upgrade-nya, misalnya `# ponytail: polling 2s, bukan realtime. Plafon ~500 concurrent hatch; upgrade ke Supabase Realtime kalau kena.`
