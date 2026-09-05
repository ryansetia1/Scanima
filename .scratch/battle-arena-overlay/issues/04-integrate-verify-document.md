# 04: Integrasikan, verifikasi, dan dokumentasikan Battle Arena

**What to build:** Seluruh mode Battle terasa sebagai satu sistem Arena
full-screen ketika dimainkan pada bentuk layar dan ukuran fighter yang berbeda.
Masalah occlusion, ground contact, transisi, atau dokumentasi yang tersisa
ditutup sebelum kontrak baru dianggap selesai.

**Blocked by:** 03 (Boss Encounter Opening)

**Status:** ready-for-agent

- [ ] Duel, Team Battle, Expedition Battle/Elite, dan Expedition Boss memakai
      definisi Battle Arena, Battle Chrome, dan Battle Overlay yang sama tanpa
      sisa footer atau dock yang mengecilkan dunia.
- [ ] Audit memastikan rectangle Arena konstan sepanjang opening, gameplay,
      dialog, picker, konfirmasi, result, resume, dan interruption.
- [ ] Visual QA dilakukan pada portrait dan landscape untuk opening tanpa
      Chrome, pertengahan transisi, gameplay, dialog/picker, serta result di
      setiap mode.
- [ ] Background menutup viewport hingga tepi tanpa gap, stretch yang salah,
      atau bagian transparan ketika Chrome tersembunyi.
- [ ] Safe area perangkat menjaga seluruh target interaktif dari notch dan
      gesture inset tanpa memotong background full-bleed.
- [ ] Fighter kecil, lebar, setinggi manusia, dan sangat tinggi tetap terbaca;
      wajah, badan utama, kaki, contact shadow, dan feedback penting tidak
      tertutup Chrome.
- [ ] Background, ground line, Anima, Seeker, shadow, dan portal tetap menyatu
      selama transisi; parallax tidak membuat karakter tampak meluncur.
- [ ] Duel/Team Opening, Expedition Opening, dan Boss Encounter Opening tidak
      snap saat reveal, sedangkan gameplay tidak reframe ulang ketika Overlay
      muncul atau hilang.
- [ ] Battle World Shake dan haptics mempertahankan perilaku live tanpa
      mengguncang Chrome atau mengulang impact saat koreksi authoritative.
- [ ] Assertion dan komentar lama yang menyatakan dock berada di luar atau di
      bawah Arena dihapus atau ditulis ulang; tidak ada dua kontrak layout yang
      saling bertentangan.
- [ ] Suite opening Battle dan UI shell menjaga perilaku eksternal yang
      disepakati; tidak ada coverage duplikat yang hanya mengunci detail
      implementasi.
- [ ] Seluruh suite Battle, UI, i18n, game rules, sprite slicing, combat parity,
      dan Expedition route lulus.
- [ ] Perubahan direview untuk temuan in-scope berkeyakinan tinggi, dan temuan
      tersebut diperbaiki sebelum ticket selesai.
- [ ] Panduan pemain Battle menggambarkan Duel/Team Opening, Expedition
      Opening, Boss Encounter Opening, dan presentasi Arena yang benar-benar
      live.
- [ ] Spesifikasi Team Battle/Expedition mencatat sequence Boss serta kontrak
      Arena/Chrome baru tanpa memindahkan detail internal ke wiki.
- [ ] `CLAUDE.md` mendapat ringkasan fakta arsitektur lintas mode setelah
      kontrak baru live; hasil rollout dan visual QA historis masuk deploy log.
- [ ] README diperbarui hanya jika ringkasan UI aktifnya masih mengasumsikan
      stage dan dock sebagai dua section.
- [ ] Tidak ada perubahan backend, schema, API, aset, request jaringan, model
      call, atau biaya generation sebagai bagian dari integrasi ini.
