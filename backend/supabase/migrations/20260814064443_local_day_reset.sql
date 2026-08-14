-- Hari harian (Play EXP, bonus terawat, hadiah Battle) memakai 00:00 sipil
-- di offset zona profil, bukan UTC. Offset datang dari device (menit timur
-- UTC) dan dikunci 24 jam supaya ganti zona tidak jadi hari extra.
-- Jam HP tidak dipakai untuk grant; hanya reset_at/server_now yang dihitung
-- server.

alter table public.profiles
  add column if not exists timezone_offset_minutes int not null default 0
    check (timezone_offset_minutes between -840 and 840),
  add column if not exists timezone_offset_set_at timestamptz;

create or replace function public.local_civil_date(
  p_now timestamptz,
  p_offset_minutes int
) returns date
language sql
immutable
set search_path = ''
as $$
  select (
    (p_now at time zone 'UTC')
    + make_interval(mins => greatest(-840, least(840, coalesce(p_offset_minutes, 0))))
  )::date;
$$;

create or replace function public.local_day_start(
  p_now timestamptz,
  p_offset_minutes int
) returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select (
    date_trunc(
      'day',
      (p_now at time zone 'UTC')
      + make_interval(mins => greatest(-840, least(840, coalesce(p_offset_minutes, 0))))
    )
    - make_interval(mins => greatest(-840, least(840, coalesce(p_offset_minutes, 0))))
  ) at time zone 'UTC';
$$;

create or replace function public.set_profile_timezone(
  p_owner uuid,
  p_offset_minutes int
) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offset int := greatest(-840, least(840, coalesce(p_offset_minutes, 0)));
  v_current int;
  v_set_at timestamptz;
begin
  select timezone_offset_minutes, timezone_offset_set_at
    into v_current, v_set_at
    from public.profiles
   where id = p_owner
   for update;
  if not found then
    return 0;
  end if;
  if v_current = v_offset then
    return v_current;
  end if;
  -- ponytail: kunci 24 jam, bukan IANA + anti-hop canggih. Plafon: satu
  -- ganti zona per hari; upgrade ke IANA + ignore-until-old-reset kalau
  -- pemain lintas zona jadi rutin.
  if v_set_at is not null and v_set_at > now() - interval '24 hours' then
    return v_current;
  end if;
  update public.profiles
     set timezone_offset_minutes = v_offset,
         timezone_offset_set_at = now()
   where id = p_owner;
  return v_offset;
end $$;
