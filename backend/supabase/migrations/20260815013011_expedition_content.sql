-- Immutable Expedition chapter versions, permanent unlocks, and collectible
-- Trophy ownership. Client access stays behind the Expedition Edge Function.

insert into public.app_config (key, value) values
  ('expedition_first_clear_bits', '25'::jsonb),
  ('expedition_shop_refresh_bits', '3'::jsonb)
on conflict (key) do nothing;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'chapter_assets',
  'chapter_assets',
  true,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'application/json']
) on conflict (id) do nothing;

create table public.expedition_chapters (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  sequence    integer not null unique,
  status      text not null default 'draft',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint expedition_chapters_slug_valid
    check (slug ~ '^[a-z0-9][a-z0-9-]{2,47}$'),
  constraint expedition_chapters_sequence_positive check (sequence >= 1),
  constraint expedition_chapters_status_valid
    check (status in ('draft', 'published', 'retired'))
);

create table public.expedition_chapter_versions (
  id                uuid primary key default gen_random_uuid(),
  chapter_id        uuid not null references public.expedition_chapters(id)
                      on delete cascade,
  content_version   integer not null,
  schema_version    integer not null default 1,
  minimum_build     jsonb not null default
                      '{"android":0,"ios":0,"desktop":0}'::jsonb,
  manifest          jsonb not null,
  manifest_hash     text not null,
  asset_prefix      text not null,
  approved_at       timestamptz,
  published_at      timestamptz,
  active            boolean not null default false,
  created_at        timestamptz not null default now(),
  constraint expedition_version_positive check (content_version >= 1),
  constraint expedition_schema_supported check (schema_version = 1),
  constraint expedition_manifest_object check (jsonb_typeof(manifest) = 'object'),
  constraint expedition_manifest_hash_valid check (manifest_hash ~ '^[0-9a-f]{64}$'),
  constraint expedition_asset_prefix_valid
    check (asset_prefix ~ '^expeditions/[a-z0-9][a-z0-9-]{2,47}/v[1-9][0-9]*/$'),
  constraint expedition_active_is_published
    check (not active or (approved_at is not null and published_at is not null)),
  constraint expedition_chapter_version_unique unique (chapter_id, content_version)
);

create unique index expedition_one_active_version
  on public.expedition_chapter_versions (chapter_id)
  where active;

create index expedition_versions_chapter_created_idx
  on public.expedition_chapter_versions (chapter_id, created_at desc);

create table public.expedition_trophies (
  id          uuid primary key default gen_random_uuid(),
  chapter_id  uuid not null unique references public.expedition_chapters(id)
                on delete restrict,
  slug        text not null unique,
  display_name text not null,
  description text not null,
  art_path    text not null,
  art_hash    text not null,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  constraint expedition_trophy_slug_valid
    check (slug ~ '^[a-z0-9][a-z0-9-]{2,47}$'),
  constraint expedition_trophy_name_valid
    check (char_length(display_name) between 1 and 48),
  constraint expedition_trophy_description_valid
    check (char_length(description) between 1 and 240),
  constraint expedition_trophy_path_valid
    check (art_path ~ '^expeditions/[a-z0-9][a-z0-9-]{2,47}/trophy/'),
  constraint expedition_trophy_hash_valid check (art_hash ~ '^[0-9a-f]{64}$'),
  constraint expedition_trophy_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create table public.expedition_progress (
  owner_id         uuid not null references public.profiles(id) on delete cascade,
  chapter_id       uuid not null references public.expedition_chapters(id)
                     on delete cascade,
  unlocked_at      timestamptz not null default now(),
  first_cleared_at timestamptz,
  clear_count      integer not null default 0,
  best_run_at      timestamptz,
  primary key (owner_id, chapter_id),
  constraint expedition_progress_clear_nonnegative check (clear_count >= 0)
);

create table public.seeker_trophies (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  trophy_id  uuid not null references public.expedition_trophies(id) on delete restrict,
  earned_at  timestamptz not null default now(),
  run_id     uuid,
  primary key (owner_id, trophy_id)
);

create table public.seeker_featured_trophies (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  slot       smallint not null,
  trophy_id  uuid not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, slot),
  unique (owner_id, trophy_id),
  constraint seeker_featured_trophy_slot_valid check (slot between 0 and 2),
  foreign key (owner_id, trophy_id)
    references public.seeker_trophies(owner_id, trophy_id) on delete cascade
);

create or replace function public.guard_expedition_version_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.published_at is not null then
    raise exception 'PUBLISHED_CHAPTER_IMMUTABLE';
  end if;
  if tg_op = 'UPDATE' and old.published_at is not null
     and (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then
    raise exception 'PUBLISHED_CHAPTER_IMMUTABLE';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger expedition_version_immutable
before update or delete on public.expedition_chapter_versions
for each row execute function public.guard_expedition_version_immutable();

alter table public.expedition_chapters enable row level security;
alter table public.expedition_chapter_versions enable row level security;
alter table public.expedition_trophies enable row level security;
alter table public.expedition_progress enable row level security;
alter table public.seeker_trophies enable row level security;
alter table public.seeker_featured_trophies enable row level security;

revoke all on public.expedition_chapters from public, anon, authenticated;
revoke all on public.expedition_chapter_versions from public, anon, authenticated;
revoke all on public.expedition_trophies from public, anon, authenticated;
revoke all on public.expedition_progress from public, anon, authenticated;
revoke all on public.seeker_trophies from public, anon, authenticated;
revoke all on public.seeker_featured_trophies from public, anon, authenticated;
revoke all on function public.guard_expedition_version_immutable()
  from public, anon, authenticated;

grant all on public.expedition_chapters to service_role;
grant all on public.expedition_chapter_versions to service_role;
grant all on public.expedition_trophies to service_role;
grant all on public.expedition_progress to service_role;
grant all on public.seeker_trophies to service_role;
grant all on public.seeker_featured_trophies to service_role;
grant execute on function public.guard_expedition_version_immutable()
  to service_role;
