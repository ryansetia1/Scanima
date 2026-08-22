# 15 — Katalog perintah

Perintah yang tidak dijalankan setiap hari, dipindahkan verbatim dari `CLAUDE.md`. Pemeriksaan gratis yang wajib dijalankan lebih dulu, deploy, dan smoke check tetap di `CLAUDE.md`.

Di macOS, binary Godot ada di `/Applications/Godot.app/Contents/MacOS/Godot` dan tidak ada di PATH.

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
godot --path game -- --profile-demo --screenshot=/tmp/profile.png
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

## Android: build, verifikasi, uji kamera

```bash
# Android. Tidak ada langkah editor yang wajib: --install-android-build-template
# adalah flag CLI, dipakai bersama --export-debug, dan export_presets.cfg boleh
# ditulis tangan. Sekali saja per mesin; sesudahnya cukup baris --export-debug.
# Jangan menambahkan izin storage apa pun di preset — CAMERA sudah datang dari
# manifest plugin, dan izin galeri adalah yang membuat Play menolak. Preset dan
# game/android/ di-gitignore karena keduanya memuat jalur keystore.
godot --headless --path game --install-android-build-template \
    --export-debug Android /tmp/scanima.apk

# Verifikasi APK. Yang diperiksa bukan "file-nya ada" tetapi tepat dua izin dan
# kelas plugin benar-benar masuk dex; manifest yang ter-merge saja tidak cukup.
B=~/Library/Android/sdk/build-tools/36.1.0
$B/aapt2 dump permissions /tmp/scanima.apk | grep permission  # INTERNET + CAMERA
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
```

## Backend lokal

```bash
# backend lokal, Phase 2 (butuh Docker jalan)
cd backend && supabase start
supabase functions serve create_anima --env-file .env.local
```
