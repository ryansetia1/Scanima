# Plan — structured failure logging (evolve/synthesize/battle)

Status: **not started**. Ini rencana eksekusi, bukan dokumentasi permanen — hapus atau
gabungkan ke `docs/14-deploy-log.md` setelah selesai dikerjakan.

## Kenapa

Sekarang debugging kegagalan `evolve_anima`/`synthesize_anima`/`battle_anima` 100%
manual lewat grep Supabase log (lihat pola investigasi di `docs/14-deploy-log.md` —
E005 safety false-positive, thinking budget bug, dll, semua ditemukan begitu).
`generations.error`/`status` sudah ada tapi cuma keisi untuk satu jalur sempit
(dispatch gambar yang "pasti gagal"). Catch-all 500 di ketiga fungsi diam-diam
menelan error tanpa jejak apapun — bahkan tanpa `console.error` di dua dari tiga
fungsi.

Tujuan: satu tempat query-able untuk lihat kegagalan terbaru, tanpa bikin sistem
replay penuh (itu future work kalau ternyata masih kurang).

## Prinsip

- **Reuse dulu, baru bikin baru.** `evolve_anima` dan `synthesize_anima` sudah punya
  kolom `generations.error`/`status` dan RPC `fail_evolution`/`fail_synthesis` —
  tinggal dipanggil di lebih banyak tempat, bukan bikin tabel baru buat mereka.
- **Battle belum punya apa-apa** (`battle_sessions` gak punya kolom error/status
  `failed`), jadi butuh 1 tabel baru — tapi kecil, khusus battle dulu, bukan
  generic event-log yang dipakai ketiganya (YAGNI — gabungin nanti kalau kepake).
- **Jangan log data mentah/PII.** Field terstruktur aja (generation_id/session_id,
  rules_version/prompt_version, error message, timestamp). Jangan simpan
  photo_path, token, atau full request body.
- **Ini logging pasif, bukan currency path.** Tidak mengubah currency/response
  behavior — hanya menambah insert di jalur error yang sudah ada, jadi risikonya
  rendah dan tidak kena aturan idempotency-key/spend-cap.

## Bagian A — Evolve & Synthesize: isi jalur yang sudah ada

File: `backend/supabase/functions/evolve_anima/index.ts`

- Baris ~281–297: error dari RPC di-match by-string ke HTTP code, lalu jatuh ke
  `return json(500, { error: msg })` di baris 297 — **tanpa nulis apapun ke DB**.
- Baris 835 sudah manggil RPC `fail_evolution` tapi cuma untuk kasus dispatch
  gambar yang "definitely didn't start" (sekitar baris 804–832).
- **Kerjaan**: sebelum `return json(500, ...)` di baris 297 (dan di tempat lain
  yang jatuh ke situ), panggil `fail_evolution(generation_id, msg)` kalau
  `generation_id` sudah ada di scope saat itu. Kalau belum ada di scope di titik
  itu, telusuri dari mana `generation_id` didapat lebih awal di function dan
  thread lewat closure/variable — **verifikasi ini saat eksekusi**, laporan
  eksplorasi belum mengonfirmasi apakah variabelnya sudah tersedia di baris 297.

File: `backend/supabase/functions/synthesize_anima/index.ts`

- Helper `synthesisError()` di baris 75–99 jadi satu titik sentral pemetaan status
  code — ini titik paling murah buat nyuntik logging, karena hampir semua path
  error lewat sini.
- RPC `fail_synthesis` sudah dipanggil di baris 709, sama sempitnya dengan
  evolve (cuma untuk dispatch gagal).
- **Kerjaan**: di dalam `synthesisError()`, kalau `generation_id` tersedia di
  parameter/closure saat dipanggil, panggil `fail_synthesis(generation_id, message)`
  sebelum return response. Kalau `synthesisError()` dipanggil dari tempat yang
  belum tentu punya `generation_id` (mis. gagal sebelum row generation dibuat),
  skip logging DB untuk kasus itu — gak semua error perlu baris DB, cukup yang
  terjadi setelah generation row ada.

Tidak perlu migration baru untuk bagian ini — kolom dan RPC sudah ada.

## Bagian B — Battle: tabel baru (satu-satunya migration di plan ini)

File baru: `backend/supabase/migrations/<timestamp>_battle_failure_log.sql`

```sql
create table public.battle_failures (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.battle_sessions(id),
  owner_id uuid references auth.users(id),
  op text,                    -- operasi/aksi yang lagi diproses saat gagal
  rules_version int,
  error text not null,
  context jsonb,              -- field terstruktur non-PII aja, lihat "Prinsip"
  created_at timestamptz not null default now()
);

alter table public.battle_failures enable row level security;
-- sengaja tanpa policy apapun: default-deny untuk anon & authenticated.
-- Edge Function insert lewat service-role client, yang bypass RLS,
-- jadi tidak perlu RPC atau grant/revoke tambahan.
```

File: `backend/supabase/functions/battle_anima/index.ts`

- Baris 134–151: satu-satunya outer try/catch di antara ketiga fungsi ini.
  Baris 147–148 map error ke `ERROR_STATUS`, baris 149 sudah `console.error`
  untuk fallback yang gak ke-map.
- **Kerjaan**: di catch block itu (baris ~149, sebelum/sesudah `console.error`
  yang sudah ada), tambah:
  ```ts
  await adminClient().from("battle_failures").insert({
    session_id: session_id ?? null,   // pakai variable yang sudah ada di scope
    owner_id: user_id ?? null,
    op: body?.action ?? null,
    rules_version: RULES_VERSION,     // atau variable versi yang sudah dipakai di file ini
    error: String(error?.message ?? error),
  });
  ```
  Jangan taruh `body` mentah ke `context` — kalau context dibutuhkan, pilih
  field spesifik aja.

## Deploy

```bash
supabase db push --linked --workdir backend   # apply migration baru
export SUPABASE_ACCESS_TOKEN=sbp_...
cd backend && supabase functions deploy evolve_anima synthesize_anima battle_anima \
  --project-ref kgcaisvmmpxswevjvgft
```

## Definition of done (per CLAUDE.md)

Tambah satu blok assert ke `backend/tests/quota_rules.sql` (dalam blok `DO`
yang sama, rollback-safe) yang mengecek:
1. `battle_failures` ada, `relrowsecurity = true`.
2. Tidak ada row di `pg_policies` untuk `battle_failures` (default-deny
   benar-benar kosong, bukan kelupaan bikin policy longgar).

Smoke manual setelah deploy: picu kegagalan sengaja (payload salah/invalid)
ke masing-masing dari tiga fungsi, lalu cek:
- `select * from generations where status='failed' order by created_at desc limit 1;`
- `select * from battle_failures order by created_at desc limit 1;`

keduanya harus keisi baris baru yang relevan.

## Eksplisit di luar scope (skip untuk sekarang)

- Tabel `failure_reports` generic yang dipakai ketiganya — gabungin nanti kalau
  query terpisah (generations vs battle_failures) ternyata beneran mengganggu.
- Replay/state-dump penuh ala fitur feedback STS2 — baru worth dibangun kalau
  structured log ini masih kurang buat reproduce bug.
- First-run onboarding curation & UI-fuzzing QA bot — dibahas terpisah, ditunda
  sesuai request user.
