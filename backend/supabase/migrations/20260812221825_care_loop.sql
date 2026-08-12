-- Phase 2 care loop. Semua perubahan kebutuhan, care_score, dan Bits terjadi di
-- satu transaksi ini. Client tidak lagi boleh PATCH care langsung: begitu Bits
-- ikut terlibat, nilai kebutuhan bukan sekadar kosmetik dan retry jaringan harus
-- idempotent seperti jalur Genesis.

alter table public.profiles alter column bits set default 30;

-- Dua profil yang sudah lahir sebelum care loop mendapat paket awal yang sama
-- dengan pemain baru. Sebelum migrasi ini belum ada jalur memperoleh/memakai
-- Bits, jadi saldo nol pasti berarti belum pernah menerima starter pack.
with penerima as (
  update public.profiles
     set bits = 30
   where bits = 0
  returning id
)
insert into public.quota_ledger (owner_id, currency, delta, reason)
select id, 'bits', 30, 'care_starter' from penerima;

-- Trigger bootstrap ikut mencatat grant Bits. Saldo Scan/Core awal belum punya
-- ledger historis; care loop mulai bersih dari mata uang yang baru aktif ini.
create or replace function public.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile uuid;
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing
  returning id into v_profile;

  if v_profile is not null then
    insert into public.quota_ledger (owner_id, currency, delta, reason)
    values (v_profile, 'bits', 30, 'care_starter');
  end if;
  return new;
end $$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

alter table public.animas
  add column sleep_started_at timestamptz,
  add column sleep_energy_at_start double precision,
  add column well_cared_on date,
  add column play_score_on date,
  add column play_score_today smallint not null default 0,
  add column dormant_since timestamptz,
  add constraint animas_sleep_energy_valid
    check (sleep_energy_at_start is null or sleep_energy_at_start between 0 and 100),
  add constraint animas_play_score_valid
    check (play_score_today between 0 and 5),
  add constraint animas_sleep_pair
    check (
      (sleep_started_at is null and sleep_energy_at_start is null)
      or (sleep_started_at is not null and sleep_energy_at_start is not null)
    );

-- Satu row per intent pemain. Tabel ini tertutup total dari Data API; ia hanya
-- dipakai fungsi service-role untuk mencegah double debit/double score saat
-- request diulang setelah timeout atau app mati.
create table public.care_events (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.profiles(id) on delete cascade,
  anima_id         uuid not null references public.animas(id) on delete cascade,
  idempotency_key  text not null,
  action           text not null,
  bits_spent       int not null default 0,
  care_score_delta int not null default 0,
  created_at       timestamptz not null default now(),
  constraint care_events_key_valid
    check (length(idempotency_key) between 1 and 128),
  constraint care_events_action_valid
    check (action in ('feed', 'clean', 'sleep', 'wake', 'play')),
  constraint care_events_bits_valid check (bits_spent >= 0),
  constraint care_events_owner_key_unique unique (owner_id, idempotency_key)
);

create index care_events_anima_id_idx on public.care_events(anima_id);
alter table public.care_events enable row level security;
revoke all on public.care_events from anon, authenticated;
grant all on public.care_events to service_role;

-- care dan care_synced_at dulu sengaja client-writable. Sekarang keduanya ikut
-- menentukan debit Bits dan care_score, jadi hak itu ditutup dan hanya nickname
-- yang tetap boleh diubah langsung.
revoke update on public.animas from anon, authenticated;
grant update (nickname) on public.animas to authenticated;

create or replace function public.apply_care(
  p_owner uuid,
  p_anima_id uuid,
  p_action text,
  p_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anima              public.animas;
  v_event              public.care_events;
  v_event_id           uuid;
  v_replayed           bool := false;
  v_now                timestamptz := now();
  v_today              date := (now() at time zone 'UTC')::date;
  v_elapsed_hours      double precision;
  v_effective_hours    double precision;
  v_sleep_hours        double precision;
  v_hunger             double precision;
  v_energy             double precision;
  v_hygiene            double precision;
  v_bond               double precision;
  v_pre_action_need     double precision;
  v_bits                int;
  v_bits_cost           int := 0;
  v_score_before        int;
  v_score_delta         int := 0;
  v_sleep_completed     bool := false;
begin
  if p_action not in ('sync', 'feed', 'clean', 'sleep', 'wake', 'play') then
    raise exception 'UNKNOWN_ACTION';
  end if;

  if p_action <> 'sync' and (p_key is null or length(p_key) not between 1 and 128) then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  -- Insert intent lebih dulu. Pada dua request paralel, unique index membuat
  -- yang kedua menunggu commit pemenang lalu masuk ke jalur replay tanpa
  -- mengulang satu pun efek ekonomi.
  if p_action <> 'sync' then
    begin
      insert into public.care_events (owner_id, anima_id, idempotency_key, action)
      values (p_owner, p_anima_id, p_key, p_action)
      returning * into v_event;
      v_event_id := v_event.id;
    exception
      when unique_violation then
        select * into v_event
          from public.care_events
         where owner_id = p_owner and idempotency_key = p_key;
        if not found
           or v_event.anima_id <> p_anima_id
           or v_event.action <> p_action then
          raise exception 'IDEMPOTENCY_CONFLICT';
        end if;
        v_event_id := v_event.id;
        v_replayed := true;
    end;
  end if;

  select * into v_anima
    from public.animas
   where id = p_anima_id and owner_id = p_owner
   for update;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if v_anima.status <> 'ready' then raise exception 'ANIMA_NOT_READY'; end if;

  select bits into v_bits
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  v_hunger := greatest(0.0, least(100.0, coalesce((v_anima.care->>'hunger')::double precision, 0.0)));
  v_energy := greatest(0.0, least(100.0, coalesce((v_anima.care->>'energy')::double precision, 0.0)));
  v_hygiene := greatest(0.0, least(100.0, coalesce((v_anima.care->>'hygiene')::double precision, 0.0)));
  v_bond := greatest(0.0, least(100.0, coalesce((v_anima.care->>'bond')::double precision, 0.0)));
  v_score_before := v_anima.care_score;

  -- Tidak ada Timer/cron. Setiap sync/action menghitung selisih sejak snapshot
  -- server terakhir; delapan jam pertama gratis dan efek dua minggu sama dengan
  -- 56 jam (8 jam grace + cap 48 jam).
  v_elapsed_hours := greatest(
    0.0,
    extract(epoch from (v_now - v_anima.care_synced_at)) / 3600.0
  );
  v_effective_hours := least(48.0, greatest(0.0, v_elapsed_hours - 8.0));

  v_hunger := greatest(0.0, v_hunger - 10.0 * v_effective_hours);
  v_hygiene := greatest(0.0, v_hygiene - 4.2 * v_effective_hours);

  if v_anima.sleep_started_at is null then
    v_energy := greatest(0.0, v_energy - 7.1 * v_effective_hours);
  else
    v_sleep_hours := greatest(
      0.0,
      extract(epoch from (v_now - v_anima.sleep_started_at)) / 3600.0
    );
    v_energy := least(
      100.0,
      coalesce(v_anima.sleep_energy_at_start, v_energy)
      + (100.0 - coalesce(v_anima.sleep_energy_at_start, v_energy))
        * least(1.0, v_sleep_hours / 6.0)
    );
    if v_sleep_hours >= 6.0 then
      v_anima.sleep_started_at := null;
      v_anima.sleep_energy_at_start := null;
      v_anima.care_score := v_anima.care_score + 5;
      v_sleep_completed := true;
    end if;
  end if;

  if v_hunger <= 0.0 and v_hygiene <= 0.0 then
    v_bond := greatest(0.0, v_bond - 2.0 * v_effective_hours);
  end if;

  if v_effective_hours >= 48.0
     and v_hunger <= 0.0
     and v_hygiene <= 0.0
     and v_anima.dormant_since is null then
    v_anima.dormant_since := v_now;
    v_anima.care_score := 0;
  end if;

  -- Bonus "terawat" hanya terjadi pada sync/open, bukan di tengah spam aksi.
  if p_action = 'sync'
     and v_hunger > 70.0
     and v_energy > 70.0
     and v_hygiene > 70.0
     and v_bond > 70.0
     and v_anima.well_cared_on is distinct from v_today then
    v_anima.care_score := v_anima.care_score + 8;
    v_anima.well_cared_on := v_today;
  end if;

  if not v_replayed then
    case p_action
      when 'feed' then
        if v_hunger >= 100.0 then raise exception 'NEED_FULL'; end if;
        if v_bits < 5 then raise exception 'NO_BITS'; end if;
        v_pre_action_need := v_hunger;
        v_hunger := least(100.0, v_hunger + 35.0);
        v_bond := least(100.0, v_bond + 3.0);
        v_bits_cost := 5;
        if v_pre_action_need < 40.0 then
          v_anima.care_score := v_anima.care_score + 3;
        end if;

      when 'clean' then
        if v_hygiene >= 100.0 then raise exception 'NEED_FULL'; end if;
        if v_bits < 5 then raise exception 'NO_BITS'; end if;
        v_pre_action_need := v_hygiene;
        v_hygiene := least(100.0, v_hygiene + 35.0);
        v_bond := least(100.0, v_bond + 3.0);
        v_bits_cost := 5;
        if v_pre_action_need < 50.0 then
          v_anima.care_score := v_anima.care_score + 3;
        end if;

      when 'play' then
        if v_energy < 5.0 then raise exception 'NO_ENERGY'; end if;
        v_energy := v_energy - 5.0;
        v_bond := least(100.0, v_bond + 8.0);
        if v_anima.play_score_on is distinct from v_today then
          v_anima.play_score_on := v_today;
          v_anima.play_score_today := 0;
        end if;
        if v_anima.play_score_today < 5 then
          v_anima.play_score_today := v_anima.play_score_today + 1;
          v_anima.care_score := v_anima.care_score + 1;
        end if;

      when 'sleep' then
        if v_anima.sleep_started_at is not null then raise exception 'ALREADY_SLEEPING'; end if;
        v_anima.sleep_started_at := v_now;
        v_anima.sleep_energy_at_start := v_energy;

      when 'wake' then
        if not v_sleep_completed then
          if v_anima.sleep_started_at is null then raise exception 'NOT_SLEEPING'; end if;
          v_anima.sleep_started_at := null;
          v_anima.sleep_energy_at_start := null;
        end if;

      when 'sync' then
        null;
    end case;
  end if;

  -- Dua Feed dan dua Clean dari nol melewati ambang 50 dan membangunkan Anima.
  if v_anima.dormant_since is not null and v_hunger >= 50.0 and v_hygiene >= 50.0 then
    v_anima.dormant_since := null;
  end if;

  if v_bits_cost > 0 then
    update public.profiles
       set bits = bits - v_bits_cost
     where id = p_owner
    returning bits into v_bits;

    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (p_owner, 'bits', -v_bits_cost, p_action, v_event_id);
  end if;

  v_score_delta := v_anima.care_score - v_score_before;
  v_anima.care := jsonb_build_object(
    'hunger', round(v_hunger::numeric, 2),
    'energy', round(v_energy::numeric, 2),
    'hygiene', round(v_hygiene::numeric, 2),
    'bond', round(v_bond::numeric, 2)
  );
  v_anima.care_synced_at := v_now;

  update public.animas
     set care = v_anima.care,
         care_score = v_anima.care_score,
         care_synced_at = v_anima.care_synced_at,
         sleep_started_at = v_anima.sleep_started_at,
         sleep_energy_at_start = v_anima.sleep_energy_at_start,
         well_cared_on = v_anima.well_cared_on,
         play_score_on = v_anima.play_score_on,
         play_score_today = v_anima.play_score_today,
         dormant_since = v_anima.dormant_since
   where id = v_anima.id
  returning * into v_anima;

  if p_action <> 'sync' and not v_replayed then
    update public.care_events
       set bits_spent = v_bits_cost,
           care_score_delta = v_score_delta
     where id = v_event_id;
  end if;

  return jsonb_build_object(
    'anima', to_jsonb(v_anima),
    'bits', v_bits,
    'replayed', v_replayed
  );
end $$;

revoke all on function public.apply_care(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_care(uuid, uuid, text, text)
  to service_role;
