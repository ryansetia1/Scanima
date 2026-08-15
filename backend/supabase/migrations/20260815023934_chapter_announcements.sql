-- Server-authoritative one-time Home popup and New badge receipts. A receipt
-- is per chapter (not version), so content revisions never masquerade as a new
-- chapter announcement.

create table public.seeker_chapter_receipts (
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  chapter_id         uuid not null references public.expedition_chapters(id)
                       on delete cascade,
  home_popup_seen_at timestamptz,
  chapter_opened_at  timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  primary key (owner_id, chapter_id),
  constraint seeker_chapter_receipt_order_valid check (
    chapter_opened_at is null
    or home_popup_seen_at is not null
  )
);

alter table public.seeker_chapter_receipts enable row level security;
revoke all on table public.seeker_chapter_receipts from public, anon, authenticated;

create or replace function public.expedition_announcements_payload(p_owner uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with eligible as (
    select
      chapter.id as chapter_id,
      version.id as version_id,
      version.published_at,
      version.manifest->'summary' as summary,
      receipt.home_popup_seen_at,
      receipt.chapter_opened_at
    from public.profiles profile
    join public.expedition_chapters chapter
      on chapter.status = 'published'
    join public.expedition_chapter_versions version
      on version.chapter_id = chapter.id
     and version.active
     and version.published_at > profile.created_at
    left join public.seeker_chapter_receipts receipt
      on receipt.owner_id = profile.id
     and receipt.chapter_id = chapter.id
    where profile.id = p_owner
      and receipt.chapter_opened_at is null
  )
  select jsonb_build_object(
    'unread', coalesce(jsonb_agg(jsonb_build_object(
      'chapter_id', chapter_id,
      'version_id', version_id,
      'published_at', published_at,
      'summary', summary
    ) order by published_at) filter (where chapter_id is not null), '[]'::jsonb),
    'home_popup', coalesce(jsonb_agg(jsonb_build_object(
      'chapter_id', chapter_id,
      'version_id', version_id,
      'published_at', published_at,
      'summary', summary
    ) order by published_at) filter (
      where chapter_id is not null and home_popup_seen_at is null
    ), '[]'::jsonb)
  )
  from eligible
$$;

create or replace function public.ack_expedition_home_popup(
  p_owner uuid,
  p_chapter_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if cardinality(p_chapter_ids) > 20
     or (select count(distinct id) from unnest(p_chapter_ids) id)
          <> cardinality(p_chapter_ids) then
    raise exception 'INVALID_ANNOUNCEMENT_SELECTION';
  end if;

  select count(*) into v_count
  from public.profiles profile
  join public.expedition_chapters chapter on chapter.id = any(p_chapter_ids)
  join public.expedition_chapter_versions version
    on version.chapter_id = chapter.id
   and version.active
   and version.published_at > profile.created_at
  where profile.id = p_owner
    and chapter.status = 'published';
  if v_count <> cardinality(p_chapter_ids) then
    raise exception 'INVALID_ANNOUNCEMENT_SELECTION';
  end if;

  insert into public.seeker_chapter_receipts (
    owner_id, chapter_id, home_popup_seen_at
  )
  select p_owner, chapter_id, now() from unnest(p_chapter_ids) chapter_id
  on conflict (owner_id, chapter_id) do update
    set home_popup_seen_at = coalesce(
          seeker_chapter_receipts.home_popup_seen_at,
          excluded.home_popup_seen_at
        ),
        updated_at = now();

  return public.expedition_announcements_payload(p_owner);
end $$;

create or replace function public.mark_expedition_chapter_opened(
  p_owner uuid,
  p_chapter_version_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chapter_id uuid;
begin
  select chapter.id into v_chapter_id
  from public.expedition_chapters chapter
  join public.expedition_chapter_versions version
    on version.chapter_id = chapter.id and version.active
  where version.id = p_chapter_version_id
    and chapter.status = 'published';
  if v_chapter_id is null then raise exception 'CHAPTER_NOT_AVAILABLE'; end if;

  insert into public.seeker_chapter_receipts (
    owner_id, chapter_id, home_popup_seen_at, chapter_opened_at
  ) values (
    p_owner, v_chapter_id, now(), now()
  )
  on conflict (owner_id, chapter_id) do update
    set home_popup_seen_at = coalesce(
          seeker_chapter_receipts.home_popup_seen_at,
          excluded.home_popup_seen_at
        ),
        chapter_opened_at = coalesce(
          seeker_chapter_receipts.chapter_opened_at,
          excluded.chapter_opened_at
        ),
        updated_at = now();

  return public.expedition_announcements_payload(p_owner);
end $$;

revoke all on function public.expedition_announcements_payload(uuid)
  from public, anon, authenticated;
revoke all on function public.ack_expedition_home_popup(uuid, uuid[])
  from public, anon, authenticated;
revoke all on function public.mark_expedition_chapter_opened(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.expedition_announcements_payload(uuid)
  to service_role;
grant execute on function public.ack_expedition_home_popup(uuid, uuid[])
  to service_role;
grant execute on function public.mark_expedition_chapter_opened(uuid, uuid)
  to service_role;
