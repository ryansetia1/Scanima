# 08 — Art Privat, Galeri, dan Bot Pool

Dokumen ini adalah spesifikasi arsitektur/produk untuk kontrak **art privat + Galeri opsional** yang sedang diimplementasikan. Ia melengkapi [04 — Game Loop & Core Systems](04-game-systems-economy.md) pada bagian ekonomi Scan dan Battle bot pool.

Kontrak ini live sejak cutover 15 Agustus 2026. `species_library` dan bucket
`sheets` privat tetap ada hanya sebagai rollback legacy; capture baru selalu
unik dan privat.

## 1. Prinsip dasar

| Aspek | Target kontrak |
| --- | --- |
| Kepemilikan art | **Privat per pemilik** — setiap capture diterima menghasilkan generation unik milik akun pemain |
| Reuse art antar pemain | **Tidak** — tidak ada cache hit Discovery Scan; dua pemain memfoto objek sama tetap masing-masing membayar generation |
| Visibilitas default | **Privat** — hanya pemilik (dan sistem otoritatif) melihat sheet/manifest penuh |
| Galeri | **Opsional, art-only** — pemain memilih publish thumbnail; tidak ada identitas pemilik atau fitur sosial |
| Bot Battle | Hanya Anima yang **published ke Galeri** masuk pool lawan pemain; fallback sistem jika pool kosong |

Motivasi ekonomi: biaya generation (~$0.07 per capture diterima) harus selalu tertutup Core; biaya Vision (~$0.003) dibatasi Scan Charge agar percobaan gate tidak meledak tanpa batas.

## 2. Objek yang boleh di-scan

**Target gate Vision:**

- **Objek non-hidup** — benda nyata (alat, makanan, tanaman pot, furniture, dll.).
- **Hewan non-manusia** — semua satwa selain manusia, dengan pagar keamanan konten.

**Ditolak (safety gate):**

- Manusia (wajah, tubuh, atau siluet yang terbaca manusia).
- Konten NSFW, kekerasan grafis, simbol hate, atau objek yang melanggar kebijakan platform.

Gate tetap di sisi server (Vision + validasi) sebelum debit Core dan pemicu
generation. Percobaan yang gagal gate **tidak** memicu generation, **tidak**
mendebit Core, dan mengembalikan Scan Charge. Claim awal tetap membatasi request
paralel sebelum Vision, sedangkan refund membuat pemain tidak dihukum karena
foto yang ditolak (lihat [04 §1](04-game-systems-economy.md)).

## 3. Alur capture privat

```mermaid
sequenceDiagram
    participant P as Pemain
    participant C as Client
    participant S as create_anima
    participant V as Vision
    participant G as Image generation

    P->>C: Foto objek
    C->>S: photo_path + idempotency_key
    S->>S: claim_scan_charge (batas Vision)
    S->>V: Analisis ~$0.003
    V-->>S: stat, elemen, move, species_key (dedup internal saja)
    alt Gate gagal
        S-->>C: Tolak ramah, tidak debit Core
    else Gate lolos
        S->>S: Debit 1 Genesis Core (atomik)
        S->>G: Generation privat ~$0.07
        G-->>S: Sheet + manifest
        S->>S: animas ready, art path milik owner
        S-->>C: Anima unik pemain
    end
```

**Catatan desain:**

- `species_key` boleh tetap dipakai untuk deduplikasi internal, analitik, atau moderation — **bukan** untuk reuse art antar pemain.
- Setiap baris `generations` accepted = biaya penuh generation; capture baru
  tidak membuat status `cache_hit`.
- Temuan Tertunda (Vision sudah keluar, Core habis) tetap masuk akal: simpan hasil Vision, klaim nanti tanpa foto ulang, tetap generation privat saat Core tersedia.

## 4. Penyimpanan dan akses

| Data | Pemilik | Client authenticated | Publik |
| --- | --- | --- | --- |
| Sheet RGBA + manifest penuh | Row `animas` / storage path scoped `owner_id` | Hanya `auth.uid() = owner_id` | Tidak |
| Thumbnail Galeri (jika publish) | Sistem + referensi ke generation | Tidak (baca lewat endpoint Galeri) | Ya, moderated |
| Metadata Battle bot (snapshot) | Derived dari publish | Lawan duel: snapshot anonim | Tidak identitas |

**RLS:** semua tabel data pemain tetap `owner_id`-scoped. Galeri hanya mengekspos subset yang sengaja dipublish — bukan salinan profil atau nickname.

**Delete Anima:** hard delete row pemilik; generation audit boleh dipertahankan tanpa `anima_id`. Art privat di storage pemilik dihapus; **tidak** ada entri bersama di pustaka global yang harus dipertahankan untuk pemain lain.

## 5. Galeri — produk dan moderasi

Galeri bukan feed sosial. Kontrak fitur:

| Ada | Tidak ada |
| --- | --- |
| Thumbnail art-only (pose Idle atau frame kurasi) | Nama pemilik, avatar, atau `@handle` |
| Nama Anima + elemen + stage (metadata gameplay netral) | Like, comment, follow, DM |
| Opt-in publish / unpublish oleh pemilik | Leaderboard penemu pertama |
| Moderation queue sebelum thumbnail live | Repost otomatis semua capture |

**Alur publish (live):**

1. Pemain membuka Anima siap (`ready`) dari Collection atau Profile.
2. Aksi **Publish to Gallery** — konfirmasi bahwa thumbnail akan terlihat publik (tanpa identitas).
3. Server enqueue moderation (otomatis + manual jika flag).
4. Setelah `approved`, thumbnail masuk indeks Galeri read-only.
5. **Unpublish** menarik dari indeks; bot pool Battle berhenti memakai Anima itu pada session baru.

Moderation memeriksa thumbnail yang sama seperti gate capture: tidak manusia, tidak NSFW, tidak simbol terlarang. Reject tidak menghapus Anima privat pemain.

## 6. Bot pool Battle

Vertical slice **historis** memakai snapshot anonim dari `species_library` (semua art bersama). **Target:**

```mermaid
graph TD
    Start["start_battle"] --> Pool{"Pool Galeri published"}
    Pool -->|ada kandidat| Match["Pilih snapshot ±15% power,<br/>stage match prioritas"]
    Pool -->|kosong / gagal match| Fallback["Bot sistem<br/>(template stat + art fallback)"]
    Match --> Session["battle_sessions.bot snapshot"]
    Fallback --> Session
```

| Aturan | Detail |
| --- | --- |
| Sumber lawan | Hanya Anima dengan `gallery_published = true` dan moderation `approved` |
| Anonimitas | Snapshot tidak membawa `owner_id`, nickname Seeker, atau link profil |
| Matching | Sama seperti slice live: total base stat ±15%, prioritas stage sama |
| Fallback | Bot sistem deterministik dari seed session — bukan pemain nyata |
| Unpublish | Anima unpublished tidak masuk draw session baru; session aktif tidak diputus |

Ini memberi insentif publish tanpa memaksa: duel tetap jalan lewat fallback, tetapi variasi art lawan datang dari komunitas yang opt-in.

## 7. Implikasi biaya (live vs historis)

| Metrik | Model historis (shared cache) | Target (privat) |
| --- | --- | --- |
| Biaya per capture diterima | $0.003 (hit) – $0.073 (miss) blended | **~$0.073** tetap (Vision + generation) |
| Rasio cache hit | Metrik bisnis utama | **Tidak relevan** untuk margin per capture |
| Scan Charge | Discovery Scan murah | **Batas percobaan Vision** (~$0.003/tembak) |
| Genesis Core | Hanya spesies baru | **Setiap capture diterima** |
| Grant mingguan | Tidak ada | **+1 Core / 7 hari server**, linked only, cap saldo gratis 3 |

Angka historis cache hit (50% → $0.038 blended, dll.) tetap berguna sebagai catatan **mengapa** pivot dilakukan, bukan sebagai proyeksi target.

## 8. Batas implementasi yang sengaja ditunda

- IAP, rewarded ads, BYOK — tetap di roadmap; kontrak Core/Scan tidak menunggu monetisasi final.
- PvP ranked, tim multi-Anima, item drop — di luar scope dokumen ini.
- Migrasi data: Anima lama di pustaka bersama membutuhkan rencana transisi terpisah (freeze publish, tidak dijelaskan di sini).

## 9. Pemeriksaan kontrak

Saat implementasi, verifikasi minimal:

- Dua akun memfoto objek identik → dua generation terpisah, dua debit Core, tidak share `sheet_path`.
- Guest / linked: aturan slot guest dan grant starter tetap; grant mingguan hanya linked, interval 7 hari server, saldo gratis ≤ 3.
- Battle tanpa publish di Galeri → fallback sistem, bukan error.
- Galeri: query publik tidak mengembalikan kolom `owner_id` atau identitas Seeker.
- Unpublish → hilang dari Galeri dan pool bot session berikutnya.

Rincian rumus Battle (18 elemen, Attack/Special element) ada di [04 §5](04-game-systems-economy.md).
