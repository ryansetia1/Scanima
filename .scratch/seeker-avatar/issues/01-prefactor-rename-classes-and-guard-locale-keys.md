# 01: Prefactor — rename kelas art Seeker dan jaga locale key layar Seeker

**What to build:** Dua pekerjaan mekanis yang tidak mengubah apa pun bagi
pemain, dikerjakan lebih dulu supaya delapan tiket sesudahnya jadi lebih mudah:
kelas art Seeker berhenti menyandang kata "Boss" karena figur yang sama akan
dipakai untuk Seeker Avatar, dan locale key dua layar Seeker mulai dijaga
sebelum tiket 04 dan 05 menambahkan key baru tepat di sana. Keduanya tidak
menyentuh file yang sama, jadi urutan di antara keduanya tidak penting.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

## Rename kelas art

- [ ] `BossSeekerSheet` menjadi `SeekerSheet` dan `BossSeekerPresenter` menjadi
      `SeekerPresenter`, termasuk nama file `snake_case`-nya, beserta seluruh
      pemanggil dan `preload`/`load`-nya.
- [ ] `BossSeekerDialog` **tidak** diganti nama. Seeker Avatar pemain tidak
      bicara, jadi panel dialog itu memang tetap milik Boss Seeker.
- [ ] Kunci payload server, nama slot manifest chapter, dan path Storage yang
      memakai `boss_seeker` **tidak disentuh**. Itu kontrak wire dengan backend
      dan chapter yang sudah ter-publish, bukan nama kelas client.
- [ ] Rename file dilakukan lewat jalur yang aman terhadap editor Godot yang
      mungkin terbuka, sehingga tidak ada UID yang rusak.
- [ ] Tidak ada sisa `BossSeekerSheet` atau `BossSeekerPresenter` di repo.

## Jaga locale key layar Seeker

- [ ] Script dan scene Profile Seeker serta onboarding sheet Seeker masuk ke
      daftar file UI yang dipindai suite i18n. Hari ini keduanya tidak ada di
      sana, sehingga key di dalamnya tidak dijaga apa pun.
- [ ] Key apa pun yang terungkap hilang oleh pemindaian baru itu diperbaiki —
      ditambahkan ke katalog kalau memang dipakai, atau referensinya dibersihkan
      kalau sudah mati.
- [ ] Menghapus satu key yang dipakai dua layar itu membuat suite i18n merah.

## Selesai kalau

- [ ] Empat suite yang tersentuh tetap hijau: UI client, art/slicing, i18n, dan
      route map Expedition.
