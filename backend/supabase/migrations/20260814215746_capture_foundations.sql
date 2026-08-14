-- Fondasi capture privat, 18 elemen, Core mingguan, dan rollout flags.
-- Backward-compatible: typing_version 1 mempertahankan element legacy bebas;
-- fitur baru default mati lewat app_config sampai client minimum siap.

-- ---------------------------------------------------------------------------
-- Anima: subject_kind, dual typing, art privat per row
-- ---------------------------------------------------------------------------
alter table public.animas
  add column subject_kind text not null default 'object',
  add column secondary_element text,
  add column typing_version smallint not null default 1,
  add column sheet_path text,
  add column manifest jsonb;

alter table public.animas
  add constraint animas_subject_kind_valid
    check (subject_kind in ('object', 'animal')),
  add constraint animas_typing_version_positive
    check (typing_version >= 1),
  add constraint animas_secondary_v1_null
    check (typing_version >= 2 or secondary_element is null),
  add constraint animas_secondary_distinct
    check (secondary_element is null or secondary_element <> element),
  add constraint animas_element_v2_valid
    check (
      typing_version < 2
      or element = any (array[
        'metal', 'wood', 'stone', 'ceramic', 'glass', 'plastic', 'cloth', 'paper',
        'plant', 'food', 'fauna', 'flow', 'spark', 'flame', 'frost', 'air',
        'toxin', 'sound'
      ]::text[])
    ),
  add constraint animas_secondary_v2_valid
    check (
      secondary_element is null
      or typing_version < 2
      or secondary_element = any (array[
        'metal', 'wood', 'stone', 'ceramic', 'glass', 'plastic', 'cloth', 'paper',
        'plant', 'food', 'fauna', 'flow', 'spark', 'flame', 'frost', 'air',
        'toxin', 'sound'
      ]::text[])
    );

-- ---------------------------------------------------------------------------
-- Profil: jejak grant Core mingguan
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column last_weekly_core_at timestamptz;

-- ---------------------------------------------------------------------------
-- Rollout flags + versi client minimum (default mati / nol)
-- ---------------------------------------------------------------------------
insert into public.app_config (key, value) values
  ('feature_typing_v13', 'false'::jsonb),
  ('feature_unique_generation', 'false'::jsonb),
  ('feature_animals', 'false'::jsonb),
  ('feature_weekly_core', 'false'::jsonb),
  ('feature_gallery', 'false'::jsonb),
  ('min_client_version', '{"android":0,"ios":0,"desktop":0}'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Storage privat: sheet pemilik + thumbnail gallery (service-managed)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('anima_sheets', 'anima_sheets', false, 4194304, array['image/png']),
  ('gallery_thumbs', 'gallery_thumbs', false, 1048576,
   array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

-- Pemilik hanya membaca prefix uid/anima_id/... miliknya; tulis/hapus service role.
create policy "baca anima sheet milik sendiri" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'anima_sheets'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- gallery_thumbs sengaja tanpa policy client: feed nanti lewat signed URL service.

-- ---------------------------------------------------------------------------
-- Antrian cleanup storage internal (RLS tertutup)
-- ---------------------------------------------------------------------------
create table public.storage_cleanup_queue (
  id           bigserial primary key,
  bucket_id    text not null,
  object_path  text not null,
  reason       text not null,
  attempts     integer not null default 0,
  last_error   text,
  created_at   timestamptz not null default now(),
  processed_at timestamptz,
  constraint storage_cleanup_queue_attempts_nonnegative
    check (attempts >= 0)
);

alter table public.storage_cleanup_queue enable row level security;

revoke all on public.storage_cleanup_queue from public, anon, authenticated;
revoke all on sequence public.storage_cleanup_queue_id_seq
  from public, anon, authenticated;

grant all on public.storage_cleanup_queue to service_role;
grant usage, select on sequence public.storage_cleanup_queue_id_seq to service_role;

create or replace function public.queue_anima_sheet_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.sheet_path is not null and old.sheet_path <> '' then
    insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
    values ('anima_sheets', old.sheet_path, 'anima_deleted');
  end if;
  return old;
end $$;

create trigger anima_cleanup_private_sheet
before delete on public.animas
for each row execute function public.queue_anima_sheet_cleanup();

revoke all on function public.queue_anima_sheet_cleanup()
  from public, anon, authenticated;
grant execute on function public.queue_anima_sheet_cleanup() to service_role;

-- ---------------------------------------------------------------------------
-- Grant Core mingguan: linked Google saja, rolling 7 hari, cap saldo 3, no catch-up
-- ---------------------------------------------------------------------------
create or replace function public._grant_weekly_core_if_eligible(p_owner uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_enabled boolean;
  v_is_anonymous boolean;
  v_has_google boolean;
begin
  select coalesce((ac.value #>> '{}')::boolean, false) into v_enabled
    from public.app_config ac
   where ac.key = 'feature_weekly_core';
  if not coalesce(v_enabled, false) then
    return false;
  end if;

  select coalesce(u.is_anonymous, false),
         exists (
           select 1
             from auth.identities i
            where i.user_id = p_owner and i.provider = 'google'
         )
    into v_is_anonymous, v_has_google
    from auth.users u
   where u.id = p_owner;
  if not found or v_is_anonymous or not v_has_google then
    return false;
  end if;

  select * into v_profile
    from public.profiles
   where id = p_owner
   for update;
  if not found then
    raise exception 'NO_PROFILE';
  end if;

  -- Bank penuh: jangan sentuh last_weekly_core_at supaya eligibility tetap.
  if v_profile.genesis_cores >= 3 then
    return false;
  end if;

  if v_profile.last_weekly_core_at is not null
     and v_profile.last_weekly_core_at + interval '7 days' > now() then
    return false;
  end if;

  update public.profiles
     set genesis_cores = genesis_cores + 1,
         last_weekly_core_at = now()
   where id = p_owner;

  insert into public.quota_ledger (owner_id, currency, delta, reason)
  values (p_owner, 'genesis_cores', 1, 'weekly_core');

  return true;
end $$;

-- Jalur debit target untuk capture privat. Fungsi lama claim_genesis tetap
-- hidup sementara flag rollout mati; create_anima berpindah ke fungsi ini
-- hanya setelah client minimum dan schema baru siap.
create or replace function public.claim_capture(
  p_owner             uuid,
  p_key               text,
  p_nickname          text,
  p_species           text,
  p_color             text,
  p_stage             smallint,
  p_element           text,
  p_secondary_element text,
  p_subject_kind      text,
  p_rarity            int,
  p_stats             jsonb,
  p_care              jsonb,
  p_vision            jsonb,
  p_prompt_version    text,
  p_model             text,
  p_cost              numeric,
  p_photo_path        text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_anima public.animas;
  v_cores int;
  v_guest_used timestamptz;
  v_is_anonymous boolean;
  v_cap numeric;
  v_spent numeric;
begin
  select * into v_gen
    from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  perform public._grant_weekly_core_if_eligible(p_owner);

  select p.genesis_cores, p.guest_scan_used_at, coalesce(u.is_anonymous, false)
    into v_cores, v_guest_used, v_is_anonymous
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = p_owner
   for update of p;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_is_anonymous and v_guest_used is not null then raise exception 'GUEST_SCAN_USED'; end if;
  if v_cores <= 0 then raise exception 'NO_CORE'; end if;

  select (value #>> '{}')::numeric into v_cap
    from public.app_config where key = 'daily_spend_cap_usd';
  if v_cap is not null then
    select coalesce(sum(cost_usd_estimate), 0) into v_spent
      from public.generations
     where created_at >= date_trunc('day', now()) and cost_usd_estimate > 0;
    if v_spent + p_cost > v_cap then raise exception 'SPEND_CAP'; end if;
  end if;

  update public.profiles
     set genesis_cores = genesis_cores - 1,
         guest_scan_used_at = case when v_is_anonymous then now() else guest_scan_used_at end
   where id = p_owner;

  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, stage, status,
     subject_kind, element, secondary_element, typing_version,
     rarity, base_stats, care, strike_name, surge_name)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'incubating',
     p_subject_kind, p_element, p_secondary_element, 2,
     least(5, greatest(1, p_rarity)), p_stats, p_care,
     left(btrim(coalesce(p_vision->>'strike_name', '')), 24),
     left(btrim(coalesce(p_vision->>'surge_name', '')), 24))
  returning * into v_anima;

  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model,
     cost_usd_estimate, vision_result, photo_path)
  values
    (p_owner, v_anima.id, p_key, 'create', 'pending', p_prompt_version, p_model,
     p_cost, p_vision, p_photo_path)
  returning * into v_gen;

  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
  values (p_owner, 'genesis_cores', -1, 'genesis', v_gen.id);

  return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_anima.id);
exception
  when unique_violation then
    select * into v_gen
      from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

create or replace function public.seeker_profile_summary(p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_anima_count integer;
  v_species_count integer;
begin
  perform public._grant_weekly_core_if_eligible(p_owner);

  select * into v_profile from public.profiles where id = p_owner;
  if not found then raise exception 'NO_PROFILE'; end if;

  select count(*)::integer, count(distinct species_key)::integer
    into v_anima_count, v_species_count
    from public.animas
   where owner_id = p_owner and status = 'ready';

  return jsonb_build_object(
    'id', v_profile.id,
    'seeker_name', v_profile.seeker_name,
    'seeker_name_changed_at', v_profile.seeker_name_changed_at,
    'birth_year', v_profile.birth_year,
    'gender', v_profile.gender,
    'seeker_xp', v_profile.seeker_xp,
    'guest_scan_used_at', v_profile.guest_scan_used_at,
    'account_upgraded_at', v_profile.account_upgraded_at,
    'battle_victories', v_profile.battle_victories,
    'anima_count', v_anima_count,
    'species_count', v_species_count,
    'active_anima_id', v_profile.active_anima_id,
    'genesis_cores', v_profile.genesis_cores,
    'bits', v_profile.bits,
    'client_config', jsonb_build_object(
      'min_client_version', coalesce(
        (select value from public.app_config where key = 'min_client_version'),
        '{"android":0,"ios":0,"desktop":0}'::jsonb
      )
    ),
    'created_at', v_profile.created_at
  );
end $$;

revoke all on function public._grant_weekly_core_if_eligible(uuid)
  from public, anon, authenticated;
revoke all on function public.claim_capture(
  uuid, text, text, text, text, smallint, text, text, text, int, jsonb, jsonb,
  jsonb, text, text, numeric, text
) from public, anon, authenticated;

grant execute on function public._grant_weekly_core_if_eligible(uuid)
  to service_role;
grant execute on function public.claim_capture(
  uuid, text, text, text, text, smallint, text, text, text, int, jsonb, jsonb,
  jsonb, text, text, numeric, text
) to service_role;
