# 15 — Katalog perintah

Perintah yang tidak dijalankan setiap hari, dipindahkan verbatim dari `CLAUDE.md`. Pemeriksaan gratis yang wajib dijalankan lebih dulu, deploy, dan smoke check tetap di `CLAUDE.md`.

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

## Uji internet terputus

Harness ini memakai port lokal yang selalu menolak koneksi. Ia tidak menyentuh
Supabase dan menguji klasifikasi transport, error state Home/Battle, serta
Retry UI untuk penyimpanan server-authoritative. Wiring LoadingScreen yang lebih
luas tetap ada di `test_scan_ui.gd`.

```bash
godot --headless --path game --script res://tests/test_offline_resilience.gd
```

Matriks perilaku dan checklist airplane mode Android ada di
[docs/17-offline-resilience.md](17-offline-resilience.md).

## Uji Battle Impact

Seam cepat ini memeriksa profil shake/haptic, copy Critical, wrapper
fighter/scenery, reset saat refit, preference, dan suppression pada replay
authoritative tanpa menjalankan seluruh suite UI:

```bash
godot --headless --path game --script res://tests/test_scan_ui.gd \
  -- --battle-impact-only
```

## Fine-tune background Duel / Team

Tuner ini hanya hidup di editor atau debug build dan baru aktif dengan flag
eksplisit. Ia berhenti sebelum account recovery dan boot backend, lalu memakai
fixture Battle lokal di view production:

```bash
godot --path game -- --battle-background-tuner

# buka profile tertentu langsung; pilihan lain duel/team × portrait/landscape
godot --path game -- --battle-background-tuner=team-landscape

# capture keadaan awal tanpa akun/jaringan
godot --path game -- --battle-background-tuner \
  --screenshot=/tmp/battle-background-tuner.png
```

- Drag area di luar panel untuk menggeser background; mouse wheel mengubah zoom.
- Arrow menggeser 1 px, Shift+Arrow 10 px, Alt+Arrow 0,1 px.
- `All characters Y` menggeser kedua Anima dan seluruh figur Seeker sebagai
  satu foreground. Slider untuk gerak cepat; kotak angka di sebelahnya menerima
  presisi 0,1 px. Nilai positif turun, nilai negatif naik.
- Pilih Duel/Team, portrait/landscape, Opening/Gameplay, serta ukuran fighter
  Small/Normal/Giant. Duel juga menyediakan Night/50%/Day.
- `Replay Transition` mengulang opening sampai framing gameplay.
- Garis cyan mengikuti ground karakter sesudah `All characters Y`; gold adalah
  source foot row background, purple adalah offset X, dan kotak hijau adalah
  safe frame kamera.
- Nilai production Duel dan Team sekarang sama: portrait memakai
  `Offset Y +100 px` + `All characters Y -117 px`; landscape memakai
  `Offset Y +5 px` + `All characters Y -113 px`.
- `Save Local` menulis empat working profile ke
  `user://battle_background_tuning.json`. `Copy GDScript` menyalin sekaligus
  mencetak dictionary empat profile untuk direview lalu ditempel ke
  `BattleBackgroundCalibration.PROFILES`.
- Save/Copy nonaktif kalau salah satu profile tidak menutup impact guard.
  `Clean Preview (H)` menyembunyikan panel dan guides; tekan H lagi untuk kembali.

## Menjalankan game dan demo visual

Setiap flag `--*-demo` memeriksa satu layar tanpa jaringan dan tanpa biaya.

```bash
# game
godot --path game                      # scan_flow: sesi, saldo, Anima dari cache
godot --path game -- --screenshot=/tmp/scan.png       # periksa layar tanpa editor
godot --headless --path game --import  # rebuild cache class, cek parse error

# harness layout Home: memasang home_view.tscn yang sama dengan production plus
# HUD, bottom nav, dan overlay Shop/Bag, dengan satu Anima palsu. Nol jaringan,
# nol akun. F6 di editor dengan scene ini terbuka, atau:
godot --path game res://scenes/home_demo.tscn -- --screenshot=/tmp/home.png
godot --path game -- --core-info --screenshot=/tmp/core.png
godot --path game -- --bits-info --screenshot=/tmp/bits.png
godot --path game -- --sleep-demo --screenshot=/tmp/sleep.png
godot --path game -- --rename-demo --screenshot=/tmp/rename.png
godot --path game -- --delete-demo --screenshot=/tmp/delete.png
godot --path game -- --collection-sheet-demo --screenshot=/tmp/collection-sheet.png
godot --path game -- --collection-sheet-loading-demo --screenshot=/tmp/collection-loading.png
godot --path game -- --thumbnail-loading-demo --screenshot=/tmp/thumbnail-loading.png
godot --path game -- --profile-demo --screenshot=/tmp/profile.png
godot --path game -- --evolution-history-loading-demo --screenshot=/tmp/evolution-loading.png
godot --path game -- --profile-help-demo --screenshot=/tmp/profile-help.png
godot --path game -- --synthesis-history-demo --screenshot=/tmp/synthesis-history.png
godot --path game -- --synthesis-history-loading-demo --screenshot=/tmp/synthesis-loading.png
godot --path game -- --synthesis-history-help-demo --screenshot=/tmp/synthesis-history-help.png
# tap demo mendorong event lewat push_input, jadi log "reaction=(0, -8.9)" adalah
# bukti routing GUI, sementara "(0, 0)" berarti ada Control yang menelan tapnya
godot --path game -- --home-tap-demo
godot --path game -- --level-up-demo --screenshot=/tmp/level-up.png
godot --path game -- --loading-demo --screenshot=/tmp/loading.png
godot --path game -- --trophy-demo --screenshot=/tmp/trophy.png
godot --path game -- --seeker-avatar-demo --screenshot=/tmp/seeker-avatar.png
godot --path game -- --atlas-demo --screenshot=/tmp/atlas.png
godot --path game -- --empty-demo --screenshot=/tmp/empty.png
godot --path game -- --summon-demo
godot --path game -- --battle-demo --screenshot=/tmp/battle.png
godot --path game -- --battle-small-demo --screenshot=/tmp/battle-small.png
godot --path game -- --battle-normal-demo --screenshot=/tmp/battle-normal.png
godot --path game -- --battle-giant-demo --screenshot=/tmp/battle-giant.png
godot --path game -- --boss-ace-demo --screenshot=/tmp/boss-ace.png
godot --path game -- --boss-scale-demo --screenshot=/tmp/boss-scale.png
godot --path game -- --battle-pending-demo --screenshot=/tmp/battle-pending.png
godot --path game -- --battle-effective-demo --screenshot=/tmp/battle-effective.png
# kilau Guard hidup ~1 detik dan --screenshot menunggu 3, jadi demo ini
# mengulanginya supaya capture jatuh di tengah sapuan
godot --path game -- --battle-guard-demo --screenshot=/tmp/guard-shimmer.png
godot --path game -- --battle-result-demo --screenshot=/tmp/battle-result.png
godot --path game -- --battle-win-demo --screenshot=/tmp/battle-win.png
godot --path game -- --team-battle-demo --screenshot=/tmp/team-battle.png
# result yang terpagari Energy: Choose Anima / Edit Team plus alasannya
godot --path game -- --battle-blocked-demo --screenshot=/tmp/battle-blocked.png
godot --path game -- --team-result-demo --screenshot=/tmp/team-result.png
godot --path game -- --battle-training-demo --screenshot=/tmp/battle-training.png
godot --path game -- --battle-training-active-demo \
 --screenshot=/tmp/battle-training-active.png

# band preview foto tanpa memindai apa pun, jadi tata letaknya bisa diperiksa
# dengan biaya nol. Tanpa ini satu-satunya cara melihatnya adalah membayar scan.
godot --path game -- --preview=$PWD/eval/photos/sepatu.jpg \
 --screenshot=/tmp/scan.png
godot --path game -- --scan-vibe-demo --screenshot=/tmp/scan-vibe.png

# preview gratis loading Genesis; tidak memanggil API
godot --path game -- --incubator --screenshot=/tmp/incubator.png
godot --path game -- --hatch-demo  # mainkan loading + reveal sekali, gratis

# alat periksa art, sekarang harus ditunjuk eksplisit karena main scene bukan demo
godot --path game res://scenes/anima_demo.tscn        # sheet placeholder
godot --path game res://scenes/anima_demo.tscn \
    -- --manifest=<abs>.json --pose=sleep --screenshot=/tmp/a.png

# landscape: Godot membaca --resolution, dan tidak ada flag demo untuk orientasi
godot --path game --resolution 1600x720 -- --battle-demo --screenshot=/tmp/l.png
```

## Art Seeker Roster

Art keempat figur sudah dibayar dan ter-commit. Yang di bawah ini hanya
dibutuhkan kalau satu sheet harus diproses ulang, atau kalau roster tumbuh —
baca ADR-0002 dulu, plafonnya ~6 figur.

```bash
# gratis: PNG ter-commit benar-benar keluaran prediction yang tercatat
node backend/tools/generate_seeker_art.mjs --check   # ikut `npm run selftest`

# gratis: audit visual, kesembilan pose x keempat slug jadi satu PNG. WAJIB
# sesudah regenerasi — hash membuktikan art-nya dibayar, bukan bahwa arah
# hadapnya benar. Ia juga mencetak reach skew `attack_command`/`concern_hit`
# sebagai penunjuk "lihat sel ini duluan"; angka itu BUKAN gerbang, sebab
# terukur 7/8 dengan satu alarm palsu (kuncir feminine memanjangkan bbox ke
# kanan dan meniru tanda tangan cermin). Mata yang memutuskan.
node backend/tools/generate_seeker_art.mjs --strip

# gratis: proses ulang raw yang sudah dibayar sesudah post-processing berubah
node backend/tools/generate_seeker_art.mjs --reprocess automaton          # preview hash
node backend/tools/generate_seeker_art.mjs --reprocess automaton --apply  # tulis

# BERBIAYA, satu slug per proses, tanpa retry otomatis. Kalau satu figur gagal,
# ulangi hanya figur itu — jangan pernah dalam loop. Angka ack-nya dibaca dari
# `pricing.mjs`, jadi ia plafon konservatif $0,07 dan bukan harga terukur ~$0,05;
# tool-nya menolak ack yang tidak sama persis.
#
# Sebelum mengedit prompt, lihat file mana yang disentuh: `roster_sheet.md`
# dipakai keempat slug, jadi satu kalimat di sana membatalkan keempat hash dan
# `--check` menuntut $0,28 regenerasi. Perbaikan yang hanya mengenai satu figur
# ditulis di `figures/<slug>.md` supaya harganya tetap $0,07.
node backend/tools/generate_seeker_art.mjs androgynous --paid --apply '--ack=US$0.07'

# placeholder lokal untuk figur yang BELUM punya art; slug yang sudah ada
# dilewati, sebab placeholder lolos semua pemeriksaan roster dan menimpa art
# berbayar gagal senyap
node eval/seeker_art.mjs
node eval/seeker_art.mjs --overwrite   # paksa, hanya kalau memang itu maunya

# ukur pertumbuhan build: export pack dengan dan tanpa asetnya, lalu bandingkan
godot --headless --path game --export-pack Android /tmp/with.pck
mv game/assets/seekers /tmp/hold && \
 godot --headless --path game --export-pack Android /tmp/without.pck; \
 mv /tmp/hold game/assets/seekers
```

## Eval prompt grounding

```bash
# Contoh ini hanya mereproduksi prompt v51 yang sudah REJECTED; jangan jalankan
# generation baru. Production tetap Capture/Evolution v47 dan Synthesis v48.
# Capture Object/Fauna memakai harness yang sama dengan Smoke Set dan Vision
# tersimpan; --skip-facing menjaga eksperimen nol Vision.
node eval/run.mjs \
  --photo eval/results/v41/single/scanima_stock_vehicle.photo.jpg \
  --prompt-version v51 \
  --vision-file eval/results/v41/single/scanima_stock_vehicle.vision.json \
  --skip-facing --dry-run
node eval/run.mjs \
  --photo eval/results/v15/single/scanima-v15-golden-retriever.photo.jpg \
  --prompt-version v51 \
  --vision-file eval/results/v15/single/scanima-v15-golden-retriever.vision.json \
  --skip-facing --dry-run

# Synthesis memakai Plan dan dua pasangan sheet/manifest Source yang sudah ada.
# Help menampilkan argumen lengkap; ganti `/path/to/...` dengan cache lokal.
node eval/synthesis_image.mjs --help
node eval/synthesis_image.mjs \
  --prompt-version v51 --plan-file "/path/to/plan.json" \
  --source-a-sheet "/path/to/a.png" --source-a-manifest "/path/to/a.json" --source-a-name "Source A" \
  --source-b-sheet "/path/to/b.png" --source-b-manifest "/path/to/b.json" --source-b-name "Source B" \
  --mode dominant_a --dry-run

# Evolution control Sunhound memakai Plan + reference yang sudah dibayar:
# nol Vision; --dry-run tidak memanggil API.
node eval/evolution_image.mjs \
  --prompt-version v51 \
  --plan-file eval/results/evolution-sunhound-adult-v28-approved/plan.json \
  --reference-image eval/results/evolution-sunhound-adult-v28-approved/hatchling-idle-reference.png \
  --dry-run
```

## Uji terhadap production

```bash
# jalur client sungguhan terhadap produksi, BERBIAYA ~$0.003 (satu Vision)
# Pakai foto yang spesiesnya SUDAH ada di species_library, kalau tidak ia
# memicu generation $0.07. Sesi uji disimpan di user://live_scan_state.json dan
# sengaja dipertahankan supaya jalan berikutnya memakai pemain uji yang sama.
godot --headless --path game --script res://tests/live_scan.gd \
    -- --photo=$PWD/eval/photos/mug-putih.jpg

# jalur Battle client sungguhan terhadap produksi, NOL model call/Core.
# Memakai sesi uji live_scan; menjalankan start/resume/tiga action/replay/forfeit.
godot --headless --path game --script res://tests/live_battle.gd
```

## Android: build, verifikasi, uji kamera dan Haptics

```bash
# Android. Tidak ada langkah editor yang wajib: --install-android-build-template
# adalah flag CLI, dipakai bersama --export-debug, dan export_presets.cfg boleh
# ditulis tangan. Sekali saja per mesin; sesudahnya cukup baris --export-debug.
# Jangan menambahkan izin storage apa pun di preset — CAMERA sudah datang dari
# manifest plugin, dan izin galeri adalah yang membuat Play menolak. Preset dan
# game/android/ di-gitignore karena keduanya memuat jalur keystore.
godot --headless --path game --install-android-build-template \
    --export-debug Android /tmp/scanima.apk

# Verifikasi APK. Yang diperiksa bukan "file-nya ada" tetapi tepat tiga izin dan
# kelas plugin benar-benar masuk dex; manifest yang ter-merge saja tidak cukup.
B=~/Library/Android/sdk/build-tools/36.1.0
$B/aapt2 dump permissions /tmp/scanima.apk | grep permission  # INTERNET + VIBRATE + CAMERA
unzip -p /tmp/scanima.apk classes.dex | strings | grep -c GodotGetImage
$B/apksigner verify /tmp/scanima.apk && echo tertandatangani

# Uji kamera di perangkat sungguhan. Tidak ada versi headless-nya: satu-satunya
# hal di client yang tidak dijaga npm run selftest. Foto benda yang spesiesnya
# SUDAH ada di species_library supaya jalurnya cache hit (~$0.003, bukan $0.07).
# Yang dibuktikan: izin diminta sekali dan pemulihannya jalan, dimensi di log
# menunjukkan <=1280 px dengan orientasi benar, dan Anima-nya tampil.
# adb tidak ada di PATH di mesin ini; ia hidup di platform-tools SDK.
A=~/Library/Android/sdk/platform-tools/adb
$A install -r /tmp/scanima.apk && $A logcat -s godot:V

# Haptics tidak punya dialog runtime. Sesudah satu aksi Battle atau Level Up,
# main package (bukan `.impactprototype`) harus muncul di histori service:
$A shell dumpsys vibrator_manager | grep 'com.rekansebangku.scanima (uid='
```

## Backend lokal

```bash
# backend lokal, Phase 2 (butuh Docker jalan)
cd backend && supabase start
supabase functions serve create_anima --env-file .env.local
```

## Admin console (`admin/`)

Workspace npm terpisah, lokal saja. Detail kontrak di
[`docs/designs/2026-08-23-atlas-moderation-admin.md`](designs/2026-08-23-atlas-moderation-admin.md)
dan pagar Next.js di `.cursor/rules/admin-guardrails.mdc`.

```bash
cd admin && npm install
npm run dev                      # http://localhost:3000, staff login via Google
npm run lint && npx tsc --noEmit # gratis, jalankan sebelum push
npm run build                    # gerbang wajib sebelum deploy admin_moderation
npx playwright test              # keyboard/responsive/visual smoke 1440/1024/768px

# admin_moderation dideploy seperti Edge Function lain, lihat CLAUDE.md
export SUPABASE_ACCESS_TOKEN=sbp_...
cd backend && supabase functions deploy admin_moderation \
  --project-ref kgcaisvmmpxswevjvgft

# smoke check: 401 tanpa JWT = fungsi boot dan pagar staff berdiri
F=https://kgcaisvmmpxswevjvgft.supabase.co/functions/v1
curl -sS -X POST $F/admin_moderation -d '{}'
```

Bootstrap admin pertama (satu kali, manual, SQL only — tidak ada RPC untuk ini
karena belum ada admin yang bisa memanggilnya). Jalankan HANYA setelah
`ryansetiawan.works@gmail.com` sudah pernah sign in sekali lewat admin app,
supaya baris `auth.users`-nya sungguh ada:

```sql
insert into public.staff_accounts (user_id, role)
select id, 'admin'
from auth.users
where email = 'ryansetiawan.works@gmail.com'
  and exists (
    select 1 from auth.identities
    where user_id = auth.users.id and provider = 'google'
  )
on conflict (user_id) do update set role = 'admin';
```
