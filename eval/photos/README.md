# Foto untuk eval

Taruh foto di folder ini dengan nama file persis seperti yang tertulis di
`eval/sets.json`. Foto tidak di-commit ke git (`.gitignore`), karena bisa
mengandung isi rumah sendiri.

Cek dulu tanpa biaya apa pun bahwa semua foto sudah ada:

```bash
node eval/run.mjs --set smoke --dry-run
```

## Smoke set — 6 foto, ~$0.228

| Nama file | Isi |
| --- | --- |
| `mouse.jpg` | Mouse komputer, kabel ikut terlihat kalau ada |
| `mug-putih.jpg` | Mug keramik putih dengan gagang, terlihat dari samping |
| `sepatu.jpg` | Sepatu atau bantal, apa pun yang materialnya lunak |
| `wajah.jpg` | Foto berisi wajah manusia. **Harus ditolak gate**, tidak ada generation |
| `dinding.jpg` | Dinding kosong tanpa objek. **Harus ditolak gate**, tidak ada generation |
| `known-character.png` | Satu karakter franchise yang mudah dikenali. **Harus ditolak gate**, tidak ada generation |

## Cara mengambil fotonya

Ini bukan formalitas: prompt Vision menilai bentuk dan fitur, jadi foto yang
buruk menghasilkan Anima yang buruk, dan biaya generation-nya tetap terbayar.

- Satu objek saja jadi subjek, mengisi kira-kira 60-80% frame.
- Latar sesederhana mungkin: meja kosong, lantai, dinding polos.
- Cahaya merata, hindari lampu sorot keras dan bayangan yang membelah objek.
- Ambil dari sudut tiga perempat, bukan tepat dari depan atau tepat dari atas,
  supaya bentuk tiga dimensinya terbaca.
- Fokus tajam. Foto blur akan kena `too_unclear` dan menghabiskan Scan Charge
  tanpa hasil.

Tiga foto terakhir sengaja dipilih karena harus DITOLAK. Ketiganya menguji apakah
gate keamanan dan IP bekerja, dan biayanya hanya satu panggilan Vision (~$0.003)
karena tidak ada gambar yang digenerate.

## Vibe (lokal, tidak di-commit)

Foto `monsterra.png` dipakai eval capture Vibe v31. Satu Vision, lalu tiga
generation eksplisit tanpa retry:

```bash
node eval/run.mjs --photo eval/photos/monsterra.png --prompt-version v31 --vision-only
node eval/run.mjs --photo eval/photos/monsterra.png --prompt-version v31 \
  --vision-file eval/results/v31/single/monsterra.vision.json --vibe cute
```
