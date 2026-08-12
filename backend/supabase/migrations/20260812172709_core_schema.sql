-- Skema inti Scanima. Sumber kebenaran desainnya docs/01-architecture-dataflow.md
-- bagian 4; kalau ada perbedaan, dokumen itu yang harus ikut diperbarui, bukan
-- migrasi ini yang diedit. Migrasi yang sudah di-apply ke remote tidak pernah
-- diubah lagi.
--
-- Tiga mata uang, dan pembagiannya bukan kosmetik ekonomi melainkan cermin
-- biaya nyata kita (lihat docs/04-game-systems-economy.md):
--   scan_charges  -> Discovery Scan, ~$0.003 per panggilan Vision
--   genesis_cores -> Genesis, ~$0.07 per sheet, ini yang harus dijaga ketat
--   bits          -> item perawatan, biaya kita nol

create table profiles (
  id              uuid primary key references auth.users on delete cascade,
  display_name    text,
  scan_charges    int  not null default 8,
  scan_charge_max int  not null default 8,
  genesis_cores   int  not null default 3, -- 3 gratis saat onboarding
  bits            int  not null default 0,
  next_refill_at  timestamptz,
  byok_enabled    bool not null default false,
  created_at      timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  -- Saldo negatif berarti ada jalur debit yang lolos dari fungsi klaim. Lebih
  -- baik transaksinya gagal keras di sini daripada saldo minus diam-diam
  -- membiarkan generation gratis.
  constraint profiles_saldo_tidak_negatif check (
    scan_charges >= 0 and genesis_cores >= 0 and bits >= 0
    and scan_charges <= scan_charge_max
  )
);

-- Pustaka art global, di-share lintas pemain. Inti penghematan biaya: satu
-- sheet dipakai semua pemain yang men-scan spesies dan warna yang sama.
create table species_library (
  species_key    text primary key,
  color_bucket   text not null,
  sheet_path     text not null, -- Storage: sheets/<hash>.png (RGBA)
  manifest       jsonb not null, -- region 4 pose, kontraknya di docs/03
  stage          smallint not null default 1, -- 1=baby, 2=adult, 3=perfect
  prompt_version text not null,
  times_reused   int  not null default 0,
  created_at     timestamptz not null default now(),
  unique (species_key, color_bucket, stage)
);

create table animas (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references profiles on delete cascade,
  nickname       text not null,
  species_key    text not null,
  color_bucket   text not null,
  stage          smallint not null default 1,
  status         text not null default 'incubating',
  element        text not null,
  rarity         smallint not null,
  base_stats     jsonb not null, -- { hp, atk, def, spd, special }
  care           jsonb not null, -- { hunger, energy, hygiene, bond }
  care_score     int  not null default 0, -- akumulasi, gerbang evolusi
  born_at        timestamptz not null default now(),
  care_synced_at timestamptz not null default now(), -- basis perhitungan decay
  created_at     timestamptz not null default now(),
  constraint animas_status_dikenal check (status in ('incubating', 'ready', 'failed')),
  constraint animas_rarity_1_5 check (rarity between 1 and 5)
);
create index animas_owner_status_idx on animas (owner_id, status);

-- Ledger setiap panggilan berbayar. Append-only; jangan pernah di-update
-- kecuali kolom status dan finished_at oleh fungsi kuota.
create table generations (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references profiles on delete cascade,
  anima_id          uuid references animas on delete set null,
  idempotency_key   text not null,
  kind              text not null,
  status            text not null default 'pending',
  prediction_id     text,
  prompt_version    text not null,
  model             text not null,
  cost_usd_estimate numeric(8, 4) not null default 0,
  vision_result     jsonb,
  error             text,
  created_at        timestamptz not null default now(),
  finished_at       timestamptz,
  -- Pagar idempotency yang sebenarnya. Fungsi claim_generation memeriksa lebih
  -- dulu supaya request kedua dapat row yang sama alih-alih error, tapi indeks
  -- ini yang menjamin dua transaksi paralel tidak bisa dua-duanya menang.
  unique (owner_id, idempotency_key),
  constraint generations_kind_dikenal check (kind in ('create', 'evolve')),
  constraint generations_status_dikenal check (
    status in ('pending', 'running', 'succeeded', 'failed', 'rejected', 'cache_hit')
  )
);
create index generations_owner_created_idx on generations (owner_id, created_at desc);
create index generations_prediction_idx on generations (prediction_id) where prediction_id is not null;

-- Jejak setiap perubahan mata uang, untuk audit dan sengketa.
create table quota_ledger (
  id         bigserial primary key,
  owner_id   uuid not null references profiles on delete cascade,
  currency   text not null,
  delta      int  not null,
  reason     text not null,
  ref_id     uuid, -- generations.id bila relevan
  created_at timestamptz not null default now(),
  constraint quota_ledger_currency_dikenal check (
    currency in ('scan_charges', 'genesis_cores', 'bits')
  ),
  constraint quota_ledger_delta_bukan_nol check (delta <> 0)
);
create index quota_ledger_owner_created_idx on quota_ledger (owner_id, created_at desc);

-- Satu generation hanya boleh direfund sekali, dan yang menjamin itu adalah
-- indeks ini, bukan ketelitian fungsi refund_generation. Tanpa ini, webhook
-- Replicate yang terkirim dua kali mengkredit dua Core untuk satu kegagalan.
create unique index quota_ledger_refund_sekali_idx
  on quota_ledger (ref_id) where reason = 'refund';

-- Temuan Tertunda: spesies baru ditemukan tapi pemain belum punya Core. Hasil
-- Vision sudah dibayar, jadi disimpan supaya bisa diklaim nanti tanpa memfoto
-- ulang objek yang mungkin sudah tidak ada di dekat pemain.
create table pending_discoveries (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references profiles on delete cascade,
  species_key   text not null,
  color_bucket  text not null,
  vision_result jsonb not null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '7 days',
  claimed_at    timestamptz,
  unique (owner_id, species_key, color_bucket)
);

-- Sakelar darurat biaya, dibaca create_anima sebelum memicu Genesis. Ditaruh di
-- tabel, bukan di env Edge Function, supaya bisa diubah tanpa deploy saat
-- tagihan meledak jam tiga pagi. Lihat docs/04-game-systems-economy.md.
create table app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

insert into app_config (key, value) values
  ('daily_spend_cap_usd', '25'::jsonb),
  ('image_model', '"openai/gpt-image-2"'::jsonb),
  ('prompt_version', '"v3"'::jsonb);
