# 17 — Resilience saat internet terputus

Scanima bukan game offline penuh. Home dapat digambar dari cache dan satu turn
Battle dapat dianimasikan lokal, tetapi saldo, inventory, care, reward, dan
progress tetap server-authoritative. Tidak ada antrean multi-turn offline.

Dokumen ini mencatat perilaku build saat ini untuk tiga skenario QA. Tidak ada
error transport mentah yang ditampilkan kepada pemain.

## Matriks perilaku

| Skenario | Yang tetap berjalan | Saat retry habis | Pemulihan |
| --- | --- | --- | --- |
| Internet mati di tengah Duel / Team Battle / Expedition | Turn yang sudah ditekan dianimasikan dari simulasi lokal. Commit transport dicoba ulang dua kali, sesudah jeda 2 lalu 4 detik. | Arena kembali ke state server terakhir dan menampilkan error in-game + **Retry**. Reward, Bits, EXP, dan inventory tidak ditebak. | Sambungkan internet lalu tekan **Retry** atau lanjutkan session tersimpan dari Battle. |
| Internet mati saat boot / loading | Home yang pernah berhasil dimuat tetap terlihat dari `boot_cache`; meter diproyeksikan dari sync terakhir. | Tanpa cache, Home menampilkan **Your habitat is offline** + **Retry**. Boot yang lambat, termasuk saat offline, berubah menjadi **Still connecting…**; tidak blank atau crash native. | Tekan **Retry**. Start/resume Battle dan Expedition juga berakhir pada panel error game, bukan overlay yang tertinggal. |
| Internet mati saat Care disimpan | Animasi dan meter muncul optimistis. | Meter kembali ke nilai sebelum tap; intent dan idempotency key tetap tersimpan. Toast menjelaskan koneksi terputus. | Ulangi aksi Care yang sama (untuk Feed/Use, item yang sama). Aksi lain ditahan sampai intent selesai. Boot berikutnya juga mencoba intent itu lagi. |
| Internet mati saat pembelian disimpan | Bits dan inventory bergerak optimistis. | Keduanya di-rollback. Hanya item yang belum terkonfirmasi menampilkan **Retry**; tombol Buy lain ditahan. | Sambungkan internet lalu tekan **Retry** pada item itu. Boot berikutnya juga mencoba key yang sama. |
| Internet mati sesudah foto terunggah tetapi jawaban Scan hilang | Pending Scan dan idempotency key tetap tersimpan; Core tidak dibuat menjadi percobaan kedua. | Tab Scan kembali ke state aman dengan tombol **Retry**. | Sambungkan internet lalu tekan **Retry**. Request memakai foto dan key yang sama. Generation yang sudah punya Anima tetap dapat dilanjutkan sesudah restart. |
| Internet mati ketika foto belum selesai terunggah | Foto belum mencapai tahap debit Core. | Preview ditutup dan muncul error upload yang meminta cek koneksi. | Pilih foto lagi sesudah online. |
| App ditutup ketika mutation sedang terbang | `pending_scan`, `pending_care`, `pending_purchase`, dan bookmark Battle/Team/Expedition ditulis ke `state.json` lewat file sementara + rename. | Tidak ada mutation kedua dengan key baru. | Care/Shop/Scan dipulihkan saat boot. Battle tetap menunggu pilihan **Continue** agar app tidak mengambil alih layar pemain. |
| App ditutup sesudah Anima Team KO, sebelum pengganti dipilih | Resume membaca state `forced_switch` authoritative dan membuka replacement picker. | Pending Attack/Guard/Item pemicu KO dikonfirmasi, bukan direplay hingga mengunci input. Pending Switch yang response-nya hilang tetap direplay memakai key semula. | Pilih anggota yang masih hidup; forced Switch gratis dan battle berlanjut. |

## Pagar data

- Retry otomatis hanya dipakai commit turn dan hanya untuk kegagalan transport.
  Response 4xx adalah keputusan server dan tidak diulang.
- Care, Shop, dan Scan mengulang secara manual memakai idempotency key yang sama.
- Cache Home display-only. Ia tidak memberi izin belanja, reward, atau perubahan
  meter tanpa server.
- Response dari UID lama dibuang melalui `session_epoch`.

## Test otomatis

Harness berikut memakai `127.0.0.1:1`, yang selalu menolak koneksi lokal. Ia
tidak memanggil Supabase dan tidak menghabiskan Core, Bits, atau biaya model.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/test_offline_resilience.gd
```

Yang dijaga secara behavior:

1. koneksi lokal yang ditolak menjadi transport failure dan operasi turn
   mendapat dua retry terbatas;
2. error state Battle menampilkan error game + **Retry**;
3. error state Home menampilkan copy offline dan sinyal tombol **Retry** bekerja;
4. state Shop yang kehilangan response menampilkan satu **Retry** yang dapat
   ditekan hanya pada item pending;
5. CTA Scan tersimpan tetap terang dan membaca **Retry** walau Core sudah 0;
6. policy murni Care hanya menerima intent yang persis sama, sedangkan policy
   Scan mempertahankan transport/5xx tetapi tidak 4xx.

Harness juga memindai kontrak orchestration di `scan_flow.gd`: Care harus
mencocokkan intent lama, retry Shop harus mengirim pending sebelum boleh membuat
pembelian baru, dan kegagalan transport/5xx Scan harus mengaktifkan retry. Ini
gagal kalau hook tersebut dihapus, tetapi bukan pengganti uji radio end-to-end.
Rollback arena ke `session_before` dan wiring cache/loading yang lebih luas tetap
dijaga `test_scan_ui.gd`; itu termasuk pergantian copy LoadingScreen menjadi
**Still connecting…** saat boot melewati batas lambat.

## Checklist perangkat

Automasi tidak menggantikan uji radio Android:

1. Mulai Duel, tekan Attack, lalu aktifkan airplane mode sebelum request selesai.
   Pastikan animasi jalan, kemudian arena rollback dan **Retry** muncul.
2. Tutup app setelah Home pernah berhasil dimuat. Buka dalam airplane mode:
   cache tetap terlihat. Bersihkan data app lalu ulangi: Home harus berakhir pada
   error offline + **Retry**, bukan blank.
3. Tekan Clean dan Buy, lalu putuskan jaringan. Pastikan perubahan optimistis
   kembali, intent dapat di-retry, dan restart tidak mendebit dua kali.
4. Putuskan jaringan setelah upload Scan dimulai. Pastikan **Retry** memakai
   percobaan tersimpan, bukan meminta Core kedua.
5. Tutup app ketika Team Battle meminta pengganti sesudah KO. Buka lagi lewat
   **Continue Team Battle**, pilih anggota hidup, dan pastikan Switch berjalan
   tanpa replay serangan lama atau input lock.
