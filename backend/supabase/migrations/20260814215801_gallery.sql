-- Galeri art-only: RLS tertutup, akses lewat Edge Function service role saja.

create table public.gallery_moderations (
  art_hash       text primary key,
  status         text not null,
  reject_reason  text,
  created_at     timestamptz not null default now(),
  constraint gallery_moderations_status_valid
    check (status in ('approved', 'rejected'))
);

create table public.gallery_entries (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  anima_id           uuid not null unique references public.animas(id) on delete cascade,
  art_hash           text not null,
  display_name       text not null,
  element            text not null,
  secondary_element  text,
  stage              smallint not null,
  thumb_path         text,
  moderation_status  text not null default 'pending',
  published          boolean not null default false,
  auto_hidden        boolean not null default false,
  report_count       integer not null default 0,
  published_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint gallery_entries_moderation_valid
    check (moderation_status in ('pending', 'approved', 'rejected')),
  constraint gallery_entries_report_count_nonnegative
    check (report_count >= 0),
  constraint gallery_entries_display_name_len
    check (char_length(display_name) between 1 and 24)
);

create index gallery_entries_feed_idx
  on public.gallery_entries (published_at desc, id desc)
  where published and moderation_status = 'approved' and not auto_hidden;

create index gallery_entries_owner_idx
  on public.gallery_entries (owner_id, anima_id);

create table public.gallery_reports (
  id           bigserial primary key,
  entry_id     uuid not null references public.gallery_entries(id) on delete cascade,
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  constraint gallery_reports_unique_reporter unique (entry_id, reporter_id)
);

create table public.gallery_hidden (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  entry_id   uuid not null references public.gallery_entries(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, entry_id)
);

create or replace function public.queue_gallery_thumb_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.thumb_path is not null and old.thumb_path <> '' then
    insert into public.storage_cleanup_queue (bucket_id, object_path, reason)
    values ('gallery_thumbs', old.thumb_path, 'gallery_entry_deleted');
  end if;
  return old;
end $$;

create trigger gallery_entry_cleanup_thumb
before delete on public.gallery_entries
for each row execute function public.queue_gallery_thumb_cleanup();

alter table public.gallery_moderations enable row level security;
alter table public.gallery_entries enable row level security;
alter table public.gallery_reports enable row level security;
alter table public.gallery_hidden enable row level security;

revoke all on public.gallery_moderations from public, anon, authenticated;
revoke all on public.gallery_entries from public, anon, authenticated;
revoke all on public.gallery_reports from public, anon, authenticated;
revoke all on public.gallery_hidden from public, anon, authenticated;
revoke all on sequence public.gallery_reports_id_seq from public, anon, authenticated;
revoke all on function public.queue_gallery_thumb_cleanup()
  from public, anon, authenticated;

grant all on public.gallery_moderations to service_role;
grant all on public.gallery_entries to service_role;
grant all on public.gallery_reports to service_role;
grant all on public.gallery_hidden to service_role;
grant usage, select on sequence public.gallery_reports_id_seq to service_role;
grant execute on function public.queue_gallery_thumb_cleanup() to service_role;
