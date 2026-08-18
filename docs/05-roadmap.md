# 05 — Roadmap Pengembangan

Status diperbarui **18 Agustus 2026**. Roadmap ini hanya memuat kontrak build
aktif dan pekerjaan yang masih relevan. Decision record sebelum pivot private
art tetap tersedia di riwayat Git serta dokumen teknis, tetapi tidak lagi
menentukan exit criteria.

Sumber kontrak aktif:

- [08 — Private Art dan Anima Atlas](08-private-art-and-gallery.md) untuk
  capture, elemen, fauna, Core mingguan, publication lineage, dan Atlas.
- [09 — Team Battle dan Expedition](09-team-battle-and-expedition.md) untuk
  mode battle empat Anima, chapter, dan push.
- [04 — Game Systems dan Economy](04-game-systems-economy.md) untuk care,
  Battle, EXP/Level, reward, dan ekonomi.
- [Wiki pemain](wiki/README.md) untuk mekanisme yang benar-benar live.

## Ringkasan status

| Fase | Tujuan | Status |
| --- | --- | --- |
| 0 | Arsitektur, prompt, dan desain sistem | **Selesai** |
| 1 | Membuktikan pipeline art end-to-end | **Selesai**, dengan validation debt |
| 2 | Backend dan core game loop | **Selesai**, dengan device/playtest debt |
| 3 | Fitur rilis, polish, dan monetisasi | **Berjalan** |
| 4 | Soft launch dan pengukuran skala nyata | **Belum mulai** |

Urutan kerja tetap mengikuti risiko. Namun, fitur yang sudah live tidak dibangun
ulang hanya agar sesuai urutan roadmap lama. Team Battle, Expedition, Anima Atlas,
Boss Seeker, dan Chapter Factory sudah melampaui scope Phase 3 awal.

## Kontrak produk yang aktif

Roadmap lama memakai Discovery Scan, cache hit lintas pemain, enam elemen, dan
sheet 2×2. Semuanya sudah digantikan:

- Setiap capture yang diterima memakai **1 Genesis Core** dan membuat art privat
  unik untuk Anima tersebut.
- Capture mendukung benda serta hewan non-manusia yang aman.
- Ada 18 elemen dengan secondary element opsional.
- Sheet production memakai grid 3×3: tujuh pose karakter dan dua VFX.
- Anima Atlas mencatat form Scanned/Expedition/Duel. Publication lineage
  bersifat opt-in dan dimoderasi; entry Duel hanya mengekspos nama Seeker.
- Akun Google mendapat 1 Core otomatis setiap tujuh hari server saat bank Core
  gratis di bawah 3, tanpa catch-up.
- Tidak ada cache-hit capture baru. `species_library`, `claim_genesis`, dan
  `record_cache_hit` hanya jalur rollback legacy.

Karena itu, rasio cache hit bukan lagi KPI biaya atau exit criterion.

## Phase 1 — Pipeline art

**Status: selesai.**

Pipeline production sudah berjalan dari foto hingga sprite di Godot:

1. Vision memeriksa subjek, menulis traits/stat/typing, dan menentukan tinggi
   kanonis.
2. GPT Image 2 medium menghasilkan sheet 3×3.
3. Edge Function melakukan chroma key, slicing berbasis ownership piksel,
   pengukuran render, dan menulis manifest.
4. Godot mengunduh sheet privat, membuat pose, VFX, serta animasi prosedural.

Prompt production adalah **v19**. Art direction sprite tetap baseline v15;
v17–v19 menambahkan dan mengkalibrasi `body_height_cm`. V18, v17, v15, dan v13
menjadi rollback berurutan untuk kebijakan tinggi, art, dan kontrak capture.

Yang sudah terbukti:

- Smoke Set historis membuktikan gate, true-to-subject, keying, dan slicing.
- Fauna v15 lulus evaluasi visual 9/9 sel.
- Post-processing Node dan Edge menghasilkan piksel identik.
- `test_sprite_slicing.gd` menjaga kontrak manifest dan loader.
- Jalur produksi sudah menghasilkan art privat yang dapat dimuat client.

### Validation debt

Ini bukan blocker implementasi Phase 2, tetapi perlu ditutup sebelum soft launch:

- Jalankan dan arsipkan Smoke Set pada konfigurasi production v19.
- Jalankan Full Set 20 foto dengan acceptance gate 3×3 yang baru:
  minimal 16/20 true-to-subject, seluruh sheet 9/9, dan tidak ada cacat keying
  yang terlihat pada ukuran game.
- Simpan bukti pemeriksaan sprite di perangkat fisik.

Jangan menjalankan Full Set saat Smoke Set belum bersih. Tidak ada generation
berbayar otomatis atau retry tanpa batas.

## Phase 2 — Backend dan core game loop

**Status: selesai untuk kontrak build aktif.**

Yang sudah live:

- Guest Seeker tanpa login gate, Google link same-UID, restore akun lama tanpa
  merge, token aman, dan hapus akun.
- RLS, hak tulis per kolom, RPC uang service-role-only, idempotency, spend cap,
  serta ledger.
- Capture unik privat, upload langsung ke Storage, penghapusan foto mentah, dan
  resume inkubator setelah restart.
- Home, Scan, Collection, Anima Profile, care server-authoritative, Shop, Bag,
  Summon, Delete, EXP/Level, Sleep, dan Dormant.
- Kamera OEM dan single-photo picker tanpa izin galeri luas.
- APK debug dengan hanya izin `INTERNET` dan `CAMERA`.
- Duel Battle 1v1, item, reward harian, Training, dan replay pending intent.
- Anima Atlas, publication lineage opt-in, dan bot dari art yang disetujui.

Test lokal menjaga quota/RLS, prompt bundle, auth, pending intent, care,
sprite/manifest, UI mobile, Battle, dan katalog i18n.

### Verification debt

Pekerjaan berikut belum menjadi bukti yang reproducible di repo:

- Uji kamera dan Google callback pada perangkat Android sungguhan.
- Uji dua request capture paralel dengan idempotency key yang sama.
- Uji buka-tutup lintas hari yang mengikat decay server ke presentasi client.
- Playtest eksternal 3–5 orang selama tiga hari tanpa kehilangan data.
- Dashboard operasional untuk biaya harian, request gagal, refund, dan pemain
  dengan pengeluaran tertinggi. Spend cap sudah ada, tetapi bukan dashboard.

Fresh database juga harus menghasilkan flag yang sama dengan production.
Perubahan flag out-of-band wajib dicatat melalui migrasi atau runbook rollout.

## Phase 3 — Fitur rilis, polish, dan monetisasi

**Status: berjalan.**

### Sudah selesai atau live untuk playtest

- Duel Battle server-authoritative.
- Team Battle async empat Anima melawan Defense Team.
- Expedition dengan tiga zona, Boss, checkpoint, reward, dan biaya masuk sekali
  per chapter.
- The Sugarworks v3, Boss Seeker runtime, ace terakhir, Chapter Factory, dan
  announcement in-app.
- Onboarding identitas Seeker setelah hatch pertama.
- Weekly Core otomatis.
- Visual shell mobile, target tap 96 px, haptic, ikon elemen, dan feedback
  visual care/Battle.
- Bottom nav Menu, Settings, serta profil Anima yang hanya dibuka lewat
  Collection/Battle picker.

Team Battle, Expedition, dan chapter push in-app saat ini aktif untuk device
playtest. Jika ditemukan blocker, matikan flag rollout tanpa mengubah kontrak
data run yang sudah ada.

### P0 — blocker kesiapan Play Store

#### 1. Privacy policy dan data safety

- Tulis privacy policy yang menjelaskan kamera, upload foto, Replicate,
  penghapusan foto mentah, akun guest/Google, Anima Atlas/publication, dan
  retention data.
- Host di URL publik dan tautkan dari aplikasi.
- Isi Data Safety Play Store berdasarkan perilaku build, bukan rencana.

**Selesai jika:** policy dapat dibuka dari app dan deklarasi Play cocok dengan
izin serta data flow APK.

#### 2. IAP Genesis Core dan penyelesaian pending capture

- Tambahkan produk Core melalui Google Play Billing.
- Verifikasi receipt di server sebelum ledger mengkredit Core.
- Sediakan endpoint/UI untuk melanjutkan `pending_discoveries` dengan Core yang
  baru didapat tanpa mengulang Vision berbayar.
- Jaga debit Core dan pembuatan capture dalam transaksi idempoten.

**Selesai jika:** satu transaksi nyata di internal testing mengkredit Core satu
kali, replay tidak menggandakan saldo, dan pending capture dapat dituntaskan.

#### 3. Audio minimum yang utuh

- SFX untuk Feed, Clean, Sleep/Wake, Play, Summon, Attack, Special, Guard, Item,
  hit, KO, menang, dan kalah.
- Musik latar Home serta Battle dengan pengaturan mute/volume.
- Pengaturan audio berdiri sendiri dari timing animasi.

**Selesai jika:** seluruh aksi yang terlihat juga memiliki feedback audio yang
sesuai dan tidak saling menumpuk.

#### 4. Observability dan external playtest

- Ukur crash-free session, capture success/failure, waktu hatch, biaya per
  accepted Anima, refund, funnel first scan, serta retention D1/D3/D7.
- Jalankan minimal 10 penguji selama tujuh hari.
- Catat blocker, kehilangan data, dan biaya per pemain.

**Selesai jika:** crash-free session di atas 99%, tidak ada kehilangan data, dan
hasil retention/cost tersedia untuk keputusan soft launch. Target awal D3 tetap
40%, tetapi kegagalan target harus menghasilkan keputusan produk, bukan angka
yang disembunyikan.

### P1 — menyelesaikan janji core game

#### 5. Evolution vertical slice

- **Player-live 18 Agustus 2026:** `feature_evolution=true`,
  `evolution_prompt_version=v30`, `evolution_version` default 1.
- Gerbang syarat authoritative di server (Level 16/36, combat lock, satu evolusi aktif).
- `evolve_anima` memakai crop Idle privat dari form saat ini sebagai `image_input`
  (bukan foto asli/full sheet), dengan lease Vision/dispatch idempoten.
- Ritual evolusi di client dapat resume dan tidak mendebit Genesis Core.
- Sheet Adult/Evolved yang sudah disetujui operator (Sunhound, Playtron, Adult
  Veridian) terkunci di `anima_evolution_locks` dan tidak memanggil Replicate.
- Combat move effects + stage stat multipliers parity JS/GDScript rules v3.

**Selesai jika:** pemain dengan Level 16/36 melihat **Evolve**, ritual selesai
tanpa Core, art stage baru tampil, dan Battle memakai multiplier/efek committed.
Guardian/Ravager tetap future improvement.

#### 6. Tutorial first-session

Tutorial tiga layar adalah pekerjaan terpisah dari onboarding identitas Seeker.
Tujuannya membawa pemain ke foto pertama dalam 60 detik tanpa menjelaskan semua
sistem sekaligus.

**Selesai jika:** pemain baru memahami Scan, keselamatan subjek, biaya 1 Core,
dan berhasil membuka kamera dari tutorial. Empty-state CTA tetap menjadi jalur
ulang setelah tutorial.

#### 7. Performance dan accessibility pass

- Profil 60 fps pada HP Android mid-range selama care, Duel, Team Battle, dan
  Expedition.
- Periksa memori setelah 30 menit berpindah tab dan battle berulang.
- Audit kontras teks, focus keyboard/controller, screen reader copy yang
  relevan, dan seluruh target tap.

**Selesai jika:** 60 fps stabil pada baseline device, tidak ada pertumbuhan
memori tanpa batas, dan masalah aksesibilitas blocker ditutup.

#### 8. Migrasi Vision sebelum retirement

`google/gemini-2.5-flash` dijadwalkan retirement **20 Oktober 2026**.

- Jalankan Vision-only Smoke Set pada kandidat `google/gemini-3-flash`.
- Bandingkan gate, traits, stat, typing, `species_key`, dan tinggi kanonis.
- Jalankan Smoke Set generation hanya setelah hasil Vision diterima.
- Ganti `VISION_MODEL` tanpa mengubah kontrak payload.

**Selesai jika:** kandidat lulus eval dan production env sudah berpindah sebelum
deadline, dengan rollback yang tercatat.

### P2 — monetisasi tambahan dan distribusi

- Rewarded ads hanya boleh memberi Scan Charge atau Bits, tidak pernah Core.
- BYOK menyimpan token pemain di secure storage dan tidak mengirimkannya ke
  backend Scanima. Jalur ini tidak boleh menghasilkan biaya model bagi kita.
- Subscription hanya masuk setelah IAP Core satu-kali dan receipt verification
  terbukti stabil.

Ads dan BYOK tidak boleh menunda IAP minimum serta privacy policy.

### Push OS

Announcement, popup, dan badge in-app sudah authoritative. Push OS adalah bonus,
bukan syarat agar chapter terlihat.

Pekerjaan tersisa:

- Konfigurasi Firebase app dan plugin messaging Android.
- Pasang `FCM_PROJECT_ID` serta kredensial pengiriman yang benar.
- Uji opt-in, token refresh, background delivery, tap routing, dan dedupe pada
  perangkat nyata.

Jangan menjalankan ulang `notify --apply` sebelum kredensial FCM tersedia.

### Exit criteria Phase 3

- [ ] Foto → care → Level → evolusi art berjalan tanpa jalan buntu.
- [ ] IAP Core nyata berhasil dan receipt replay aman.
- [ ] Pending capture dapat dituntaskan setelah mendapat Core.
- [ ] Rewarded ads, jika dirilis, tidak punya jalur grant Core.
- [ ] BYOK, jika masuk build Phase 3, menghasilkan Anima tanpa biaya model kita.
- [ ] Seluruh aksi utama memiliki feedback audio dan visual.
- [ ] Privacy policy tertaut dan Data Safety cocok dengan build.
- [ ] 60 fps serta memori stabil terbukti pada perangkat baseline.
- [ ] 10 penguji bermain tujuh hari tanpa kehilangan data.
- [ ] Biaya, crash-free session, dan retention dapat diukur.

Item bertanda “jika dirilis” boleh dipindahkan sesudah soft launch melalui
keputusan eksplisit. IAP minimum, privacy, observability, dan penyelesaian
pending capture tidak opsional untuk rilis berbayar.

## Phase 4 — Soft launch

**Status: belum mulai.**

### Tahap 1 — distribusi terbatas

- Android APK melalui itch.io atau kanal uji setara.
- Web demo memakai upload file dan menjelaskan bahwa kamera tidak tersedia.
- Batasi jumlah pemain melalui invite/promo agar spend cap dapat dipantau.
- Gunakan in-app announcement untuk chapter; push OS tetap bonus.

Tujuan tahap ini adalah mengukur perilaku nyata, bukan mengejar pendapatan:
capture per pemain, conversion first scan, biaya per accepted Anima, retention,
crash, moderation, dan beban support.

### Tahap 2 — Play Store

- Siapkan listing, ikon/screenshot/video, content rating, Data Safety, privacy
  URL, support contact, dan produk IAP.
- Jalankan closed testing sesuai persyaratan Play Console yang berlaku untuk
  akun saat pengajuan; verifikasi syarat aktual di Console, jangan mengandalkan
  angka historis roadmap.
- Lanjutkan staged rollout hanya setelah crash, biaya, refund, dan support queue
  stabil.

### Exit criteria Phase 4

- Crash-free session di atas 99%.
- Retention hari-1 di atas 35% dan hari-7 di atas 15%, atau ada keputusan sadar
  untuk mengubah produk sebelum memperluas rollout.
- Tidak ada insiden Vision gate yang mengekspos konten terlarang.
- Rata-rata biaya API per accepted Anima terukur dan tetap di dalam envelope
  konservatif **$0.07**, bukan bergantung pada cache hit.
- Setidaknya satu transaksi IAP nyata berhasil di production.
- Biaya API per pemain dibandingkan dengan pendapatan per pemain; selisih yang
  disubsidi harus diketahui dan diterima sadar.
- Spend cap, refund, moderation, dan rollback chapter telah diuji operasional.

## Risiko aktif

| Risiko | Dampak | Penanganan |
| --- | --- | --- |
| Art tidak cukup true-to-subject pada variasi luas | Premis produk melemah | Smoke/Full Set current prompt dan review manusia |
| Setiap capture unik membuat biaya linear | Margin negatif | Core server-authoritative, IAP, spend cap, observability |
| Vision gate bocor | Risiko keselamatan dan toko aplikasi | Gate sebelum debit/generation, moderation, Report/Hide |
| Model berubah harga atau retired | Capture berhenti atau mahal | Env model, eval sebelum cutover, rollback prompt/model |
| Pending capture tidak bisa dituntaskan | Pemain buntu setelah Vision | Claim endpoint/UI idempoten bersama IAP |
| Akun guest kehilangan akses | Kehilangan koleksi | Google link same-UID, secure token, restore warning |
| Push OS gagal | Engagement chapter turun | Jalur in-app tetap authoritative |
| Play Store menolak deklarasi data | Rilis tertunda | Privacy/Data Safety diverifikasi terhadap APK jadi |
| Scope creep multiplayer/collection | Phase 3 tidak selesai | Pertahankan daftar non-goal di bawah |

## Yang sengaja tidak dikerjakan

Fitur berikut bukan blocker Phase 3 atau Phase 4:

- PvP real-time, ranked ladder, battle pass, dan trading.
- Breeding atau generation anak.
- Deck/card system untuk Expedition.
- Animasi frame-by-frame.
- Full iOS release pipeline sebelum Android terbukti.
- Lokalisasi tambahan sebelum English/default copy stabil.
- Ace-exclusive move dan full multi-phase Boss.

Team Battle tetap async melawan snapshot Defense Team. Scope baru hanya masuk
setelah exit criteria fase aktif ditutup atau roadmap ini diubah melalui
keputusan eksplisit.
