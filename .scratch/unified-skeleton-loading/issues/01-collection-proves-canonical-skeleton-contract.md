# 01: Collection membuktikan kontrak skeleton kanonis

**What to build:** Satu kontrak content skeleton yang mengambil visual History
di Anima Profile sebagai reference, lalu dipakai end-to-end oleh Condition di
Collection. Pemain melihat placeholder yang content-aware selama care
authoritative belum tersedia dan crossfade singkat ke meter sebenarnya tanpa
menunda cache yang sudah siap.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Warna, radius, border, spacing, input behavior, dan pulse content
      skeleton didefinisikan pada satu primitive kanonis, bukan disalin oleh
      tiap screen.
- [ ] Pulse memakai ritme reference History: 0,62 detik per sisi dengan easing
      sine, berhenti saat hidden atau selesai, lalu mengembalikan opacity ke
      keadaan netral.
- [ ] Bentuk placeholder Condition tetap menyerupai label dan meter, tetapi
      memakai surface dan motion kanonis yang sama dengan skeleton art.
- [ ] Cache Condition yang tersedia langsung menampilkan meter tanpa skeleton
      atau minimum loading duration.
- [ ] Cache miss menampilkan skeleton, lalu seluruh grup meter crossfade selama
      0,18 detik tanpa scale atau stagger ketika payload authoritative tiba.
- [ ] Skeleton mengabaikan input dan tidak menambah target fokus atau tap.
- [ ] Error definitif menghentikan pulse dan mempertahankan fallback/error
      behavior Collection yang sudah ada.
- [ ] Test UI memakai scene production dan menunggu state tween yang sebenarnya,
      bukan fixed sleep, untuk menjaga loading, cache-first, resolve, dan
      cleanup.
- [ ] Full-screen loader, incubator, Atlas shimmer, serta indikator loading
      non-content tidak berubah.
