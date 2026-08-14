-- Guest Seeker + upgrade akun Google.
-- Semua grant, slot Scan, nama unik, EXP, dan kemenangan tetap server-authoritative.

alter table public.profiles
  add column seeker_name text,
  add column seeker_name_changed_at timestamptz,
  add column birth_year smallint,
  add column gender text,
  add column seeker_xp integer not null default 0,
  add column guest_scan_used_at timestamptz,
  add column account_upgraded_at timestamptz,
  add column battle_victories integer not null default 0;

alter table public.profiles
  add constraint profiles_seeker_name_format check (
    seeker_name is null
    or seeker_name ~ '^[A-Za-z][A-Za-z0-9_]{2,15}$'
  ),
  add constraint profiles_birth_year_valid check (
    birth_year is null or birth_year between 1900 and 9999
  ),
  add constraint profiles_gender_valid check (
    gender is null
    or gender in ('woman', 'man', 'non_binary', 'another_identity', 'prefer_not_to_say')
  ),
  add constraint profiles_seeker_progress_nonnegative check (
    seeker_xp >= 0 and battle_victories >= 0
  );

create unique index profiles_seeker_name_lower_unique
  on public.profiles (lower(seeker_name))
  where seeker_name is not null;

alter table public.profiles alter column genesis_cores set default 1;

-- Saldo akun lama tidak disentuh. Ledger ini merekonstruksi grant starter tiga
-- Core mereka supaya upgrade Google kelak hanya melengkapi total lifetime ke 3.
insert into public.quota_ledger (owner_id, currency, delta, reason)
select p.id, 'genesis_cores', 3, 'starter_legacy'
  from public.profiles p
 where not exists (
   select 1
     from public.quota_ledger q
    where q.owner_id = p.id
      and q.currency = 'genesis_cores'
      and q.reason in ('starter_guest', 'starter_legacy', 'starter_google')
 );

create unique index quota_ledger_starter_guest_owner_unique
  on public.quota_ledger (owner_id)
  where reason = 'starter_guest';
create unique index quota_ledger_starter_legacy_owner_unique
  on public.quota_ledger (owner_id)
  where reason = 'starter_legacy';
create unique index quota_ledger_starter_google_owner_unique
  on public.quota_ledger (owner_id)
  where reason = 'starter_google';

-- Akun anonim lama yang sudah punya Anima dianggap sudah memakai kesempatan
-- guest. Mereka mempertahankan seluruh saldo dan Anima yang sudah ada.
update public.profiles p
   set guest_scan_used_at = coalesce(
     (
       select min(a.born_at)
         from public.animas a
        where a.owner_id = p.id
     ),
     (
       select min(g.created_at)
         from public.generations g
        where g.owner_id = p.id
          and g.status in ('cache_hit', 'succeeded')
     )
   )
 where exists (
   select 1 from auth.users u where u.id = p.id and coalesce(u.is_anonymous, false)
 )
   and (
     exists (select 1 from public.animas a where a.owner_id = p.id)
     or exists (
       select 1 from public.generations g
        where g.owner_id = p.id and g.status in ('cache_hit', 'succeeded')
     )
   );

-- Seeker baru dimulai dari histori yang masih dapat dibuktikan. Training lama
-- tidak dapat direkonstruksi karena sebelumnya memang tidak disimpan.
update public.profiles p
   set seeker_xp = coalesce((
         select count(*)::integer * 5 + coalesce(sum(a.care_score), 0)::integer
           from public.animas a
          where a.owner_id = p.id and a.status = 'ready'
       ), 0),
       battle_victories = coalesce((
         select sum(a.battle_wins)::integer
           from public.animas a
          where a.owner_id = p.id
       ), 0);

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
    values
      (v_profile, 'bits', 50, 'care_starter'),
      (v_profile, 'genesis_cores', 1, 'starter_guest');
  end if;
  return new;
end $$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create or replace function public._validated_seeker_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_lower text;
begin
  if v_name !~ '^[A-Za-z][A-Za-z0-9_]{2,15}$' then
    raise exception 'INVALID_SEEKER_NAME';
  end if;
  v_lower := lower(v_name);
  if v_lower = any(array[
    'admin', 'administrator', 'moderator', 'scanima', 'seeker',
    'support', 'system', 'official', 'staff', 'null'
  ])
  or v_lower ~ '(fuck|shit|bitch|cunt|kontol|memek|ngentot)' then
    raise exception 'SEEKER_NAME_RESERVED';
  end if;
  return v_name;
end $$;

create or replace function public.complete_seeker_profile(
  p_owner uuid,
  p_name text,
  p_birth_year integer default null,
  p_gender text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_name text;
  v_min_year integer := extract(year from current_date)::integer - 13;
begin
  v_name := public._validated_seeker_name(p_name);
  if p_birth_year is not null and (p_birth_year < 1900 or p_birth_year > v_min_year) then
    raise exception 'INVALID_BIRTH_YEAR';
  end if;
  if p_gender is not null
     and p_gender not in ('woman', 'man', 'non_binary', 'another_identity', 'prefer_not_to_say') then
    raise exception 'INVALID_GENDER';
  end if;

  select * into v_profile
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  if v_profile.seeker_name is not null then
    if lower(v_profile.seeker_name) = lower(v_name)
       and v_profile.birth_year is not distinct from p_birth_year
       and v_profile.gender is not distinct from p_gender then
      return to_jsonb(v_profile);
    end if;
    raise exception 'SEEKER_PROFILE_COMPLETE';
  end if;

  begin
    update public.profiles
       set seeker_name = v_name,
           seeker_name_changed_at = now(),
           birth_year = p_birth_year,
           gender = p_gender
     where id = p_owner
    returning * into v_profile;
  exception
    when unique_violation then raise exception 'SEEKER_NAME_TAKEN';
  end;
  return to_jsonb(v_profile);
end $$;

create or replace function public.rename_seeker(
  p_owner uuid,
  p_name text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_name text;
begin
  v_name := public._validated_seeker_name(p_name);
  select * into v_profile
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_profile.seeker_name is null then raise exception 'SEEKER_PROFILE_INCOMPLETE'; end if;
  if v_profile.seeker_name = v_name then return to_jsonb(v_profile); end if;
  if v_profile.seeker_name_changed_at is not null
     and v_profile.seeker_name_changed_at + interval '30 days' > now() then
    raise exception 'SEEKER_NAME_COOLDOWN';
  end if;

  begin
    update public.profiles
       set seeker_name = v_name,
           seeker_name_changed_at = now()
     where id = p_owner
    returning * into v_profile;
  exception
    when unique_violation then raise exception 'SEEKER_NAME_TAKEN';
  end;
  return to_jsonb(v_profile);
end $$;

create or replace function public.seeker_profile_summary(p_owner uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_anima_count integer;
  v_species_count integer;
begin
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
    'created_at', v_profile.created_at
  );
end $$;

create or replace function public.upgrade_seeker_account(p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_is_anonymous boolean;
  v_granted integer;
  v_delta integer;
begin
  select is_anonymous into v_is_anonymous
    from auth.users
   where id = p_owner;
  if not found then raise exception 'AUTH_USER_NOT_FOUND'; end if;
  if coalesce(v_is_anonymous, false) then raise exception 'ACCOUNT_STILL_ANONYMOUS'; end if;
  if not exists (
    select 1 from auth.identities where user_id = p_owner and provider = 'google'
  ) then
    raise exception 'GOOGLE_IDENTITY_REQUIRED';
  end if;

  select * into v_profile
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_profile.account_upgraded_at is not null then
    return public.seeker_profile_summary(p_owner);
  end if;

  select coalesce(sum(delta), 0)::integer into v_granted
    from public.quota_ledger
   where owner_id = p_owner
     and currency = 'genesis_cores'
     and reason in ('starter_guest', 'starter_legacy', 'starter_google');
  v_delta := greatest(0, 3 - v_granted);

  update public.profiles
     set genesis_cores = genesis_cores + v_delta,
         account_upgraded_at = now()
   where id = p_owner;
  if v_delta > 0 then
    insert into public.quota_ledger (owner_id, currency, delta, reason)
    values (p_owner, 'genesis_cores', v_delta, 'starter_google');
  end if;
  return public.seeker_profile_summary(p_owner);
end $$;

-- Satu sumber Seeker EXP: setiap kenaikan EXP Anima yang sudah lolos transaksi
-- Care/Battle dicerminkan atomik ke profil. Penurunan administratif tidak
-- mengurangi Seeker EXP.
create or replace function public.mirror_seeker_xp_from_anima()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.care_score > old.care_score then
    update public.profiles
       set seeker_xp = seeker_xp + (new.care_score - old.care_score)
     where id = new.owner_id;
  end if;
  return new;
end $$;

create trigger animas_mirror_seeker_xp
after update of care_score on public.animas
for each row
when (new.care_score > old.care_score)
execute function public.mirror_seeker_xp_from_anima();

-- Anima memberi +5 hanya pada transisi lahir: INSERT cache-hit langsung ready,
-- atau UPDATE incubating -> ready setelah Genesis selesai.
create or replace function public.award_ready_anima_seeker_xp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' and new.status = 'ready')
     or (tg_op = 'UPDATE' and old.status is distinct from 'ready' and new.status = 'ready') then
    update public.profiles set seeker_xp = seeker_xp + 5 where id = new.owner_id;
  end if;
  return new;
end $$;

create trigger animas_award_ready_seeker_xp
after insert or update of status on public.animas
for each row execute function public.award_ready_anima_seeker_xp();

-- Battle victory adalah kemenangan terminal akun, bukan hanya progression win.
-- Karena trigger melihat transisi status, Training dan replay masing-masing
-- tetap dihitung tepat sekali.
create or replace function public.count_seeker_battle_victory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from 'won' and new.status = 'won' then
    update public.profiles
       set battle_victories = battle_victories + 1
     where id = new.owner_id;
  end if;
  return new;
end $$;

create trigger battle_sessions_count_seeker_victory
after update of status on public.battle_sessions
for each row
when (old.status is distinct from 'won' and new.status = 'won')
execute function public.count_seeker_battle_victory();

create or replace function public.record_cache_hit(
  p_owner          uuid,
  p_key            text,
  p_nickname       text,
  p_species        text,
  p_color          text,
  p_stage          smallint,
  p_element        text,
  p_rarity         int,
  p_stats          jsonb,
  p_care           jsonb,
  p_vision         jsonb,
  p_prompt_version text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_anima public.animas;
  v_guest_used timestamptz;
  v_is_anonymous boolean;
begin
  select * into v_gen from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

  select p.guest_scan_used_at, coalesce(u.is_anonymous, false)
    into v_guest_used, v_is_anonymous
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = p_owner
   for update of p;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_is_anonymous and v_guest_used is not null then raise exception 'GUEST_SCAN_USED'; end if;

  insert into public.animas
    (owner_id, nickname, species_key, color_bucket, stage, status,
     element, rarity, base_stats, care, strike_name, surge_name)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'ready',
     p_element, least(5, greatest(1, p_rarity)), p_stats, p_care,
     left(btrim(coalesce(p_vision->>'strike_name', '')), 24),
     left(btrim(coalesce(p_vision->>'surge_name', '')), 24))
  returning * into v_anima;

  insert into public.generations
    (owner_id, anima_id, idempotency_key, kind, status, prompt_version, model,
     cost_usd_estimate, vision_result, finished_at)
  values
    (p_owner, v_anima.id, p_key, 'create', 'cache_hit', p_prompt_version, 'cache',
     0, p_vision, now())
  returning * into v_gen;

  update public.species_library
     set times_reused = times_reused + 1
   where species_key = p_species and color_bucket = p_color and stage = p_stage;
  if v_is_anonymous then
    update public.profiles set guest_scan_used_at = now() where id = p_owner;
  end if;

  return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_anima.id);
exception
  when unique_violation then
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

create or replace function public.claim_genesis(
  p_owner          uuid,
  p_key            text,
  p_nickname       text,
  p_species        text,
  p_color          text,
  p_stage          smallint,
  p_element        text,
  p_rarity         int,
  p_stats          jsonb,
  p_care           jsonb,
  p_vision         jsonb,
  p_prompt_version text,
  p_model          text,
  p_cost           numeric,
  p_photo_path     text
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
  select * into v_gen from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
  end if;

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
     element, rarity, base_stats, care, strike_name, surge_name)
  values
    (p_owner, p_nickname, p_species, p_color, p_stage, 'incubating',
     p_element, least(5, greatest(1, p_rarity)), p_stats, p_care,
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
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return jsonb_build_object('generation_id', v_gen.id, 'anima_id', v_gen.anima_id);
end $$;

create or replace function public.refund_generation(p_gen_id uuid, p_reason text)
returns public.generations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen public.generations;
  v_debited bool;
  v_is_anonymous bool;
begin
  select * into v_gen from public.generations where id = p_gen_id for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;
  if v_gen.status = 'succeeded' then raise exception 'ALREADY_SUCCEEDED'; end if;

  select exists (
    select 1 from public.quota_ledger
     where ref_id = p_gen_id and currency = 'genesis_cores' and delta < 0
  ) into v_debited;

  if v_debited and not exists (
    select 1 from public.quota_ledger where ref_id = p_gen_id and reason = 'refund'
  ) then
    update public.profiles set genesis_cores = genesis_cores + 1 where id = v_gen.owner_id;
    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (v_gen.owner_id, 'genesis_cores', 1, 'refund', p_gen_id);
  end if;

  if v_debited then
    select coalesce(is_anonymous, false) into v_is_anonymous
      from auth.users where id = v_gen.owner_id;
    if v_is_anonymous and not exists (
      select 1
        from public.generations g
       where g.owner_id = v_gen.owner_id
         and g.id <> p_gen_id
         and g.status in ('cache_hit', 'succeeded', 'pending', 'running')
    ) then
      update public.profiles set guest_scan_used_at = null where id = v_gen.owner_id;
    end if;
  end if;

  update public.generations
     set status = 'failed',
         error = coalesce(p_reason, error),
         finished_at = coalesce(finished_at, now())
   where id = p_gen_id
  returning * into v_gen;
  return v_gen;
end $$;

revoke all on function public._validated_seeker_name(text)
  from public, anon, authenticated;
revoke all on function public.complete_seeker_profile(uuid, text, integer, text)
  from public, anon, authenticated;
revoke all on function public.rename_seeker(uuid, text)
  from public, anon, authenticated;
revoke all on function public.seeker_profile_summary(uuid)
  from public, anon, authenticated;
revoke all on function public.upgrade_seeker_account(uuid)
  from public, anon, authenticated;
revoke all on function public.mirror_seeker_xp_from_anima()
  from public, anon, authenticated;
revoke all on function public.award_ready_anima_seeker_xp()
  from public, anon, authenticated;
revoke all on function public.count_seeker_battle_victory()
  from public, anon, authenticated;
revoke all on function public.record_cache_hit(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.claim_genesis(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text, text, numeric, text
) from public, anon, authenticated;
revoke all on function public.refund_generation(uuid, text)
  from public, anon, authenticated;

grant execute on function public.complete_seeker_profile(uuid, text, integer, text)
  to service_role;
grant execute on function public.rename_seeker(uuid, text)
  to service_role;
grant execute on function public.seeker_profile_summary(uuid)
  to service_role;
grant execute on function public.upgrade_seeker_account(uuid)
  to service_role;
grant execute on function public.record_cache_hit(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text
) to service_role;
grant execute on function public.claim_genesis(
  uuid, text, text, text, text, smallint, text, int, jsonb, jsonb, jsonb, text, text, numeric, text
) to service_role;
grant execute on function public.refund_generation(uuid, text)
  to service_role;

-- Hak kolom baru tertutup walau migrasi sebelumnya pernah memberi UPDATE tabel.
revoke update on public.profiles from anon, authenticated;
grant update (display_name, last_seen_at) on public.profiles to authenticated;
