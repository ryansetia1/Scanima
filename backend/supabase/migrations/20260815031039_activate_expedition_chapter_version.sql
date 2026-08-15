-- Developer-only publish gate for immutable Expedition chapter versions.
-- Staging uploads assets and writes an inactive approved version; this RPC
-- performs the only atomic active-version swap.

create table public.expedition_chapter_push_events (
  chapter_version_id uuid primary key
    references public.expedition_chapter_versions(id) on delete restrict,
  status text not null default 'pending',
  claimed_at timestamptz not null default now(),
  sent_at timestamptz,
  message_id text,
  error text,
  constraint expedition_chapter_push_status_valid
    check (status in ('pending', 'sent', 'failed', 'uncertain')),
  constraint expedition_chapter_push_sent_complete
    check (status <> 'sent' or (sent_at is not null and message_id is not null))
);

alter table public.expedition_chapter_push_events enable row level security;
revoke all on public.expedition_chapter_push_events
  from public, anon, authenticated;
grant all on public.expedition_chapter_push_events to service_role;

create or replace function public.stage_expedition_chapter_version(
  p_slug text,
  p_sequence integer,
  p_content_version integer,
  p_schema_version integer,
  p_minimum_build jsonb,
  p_manifest jsonb,
  p_manifest_hash text,
  p_asset_prefix text,
  p_approved_at timestamptz,
  p_trophy_slug text,
  p_trophy_display_name text,
  p_trophy_description text,
  p_trophy_art_path text,
  p_trophy_art_hash text,
  p_trophy_metadata jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chapter public.expedition_chapters;
  v_version public.expedition_chapter_versions;
  v_trophy public.expedition_trophies;
begin
  if p_approved_at is null then
    raise exception 'CHAPTER_NOT_APPROVED';
  end if;
  if (
    p_schema_version <> 1
    or jsonb_typeof(p_manifest) <> 'object'
    or coalesce((p_manifest->>'schema_version')::integer, -1) <> p_schema_version
    or coalesce((p_manifest->>'content_version')::integer, -1) <> p_content_version
    or coalesce((p_manifest->>'sequence')::integer, -1) <> p_sequence
    or coalesce(p_manifest->'factory'->>'slug', '') <> p_slug
    or coalesce(p_manifest->'factory'->>'mode', '') <> 'production'
    or coalesce(p_manifest->'assets'->>'prefix', '') <> p_asset_prefix
    or coalesce(p_manifest->>'manifest_hash', '') <> p_manifest_hash
    or p_manifest_hash !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(p_minimum_build) <> 'object'
    or jsonb_typeof(p_manifest->'summary') <> 'object'
    or coalesce(p_manifest->'summary'->>'title', '') = ''
    or jsonb_typeof(p_manifest->'zones') <> 'array'
    or jsonb_array_length(p_manifest->'zones') <> 3
    or jsonb_typeof(p_manifest->'opponents') <> 'array'
    or jsonb_array_length(p_manifest->'opponents') < 4
    or jsonb_typeof(p_manifest->'boss') <> 'object'
  ) then
    raise exception 'INVALID_CHAPTER_MANIFEST';
  end if;

  select *
    into v_chapter
    from public.expedition_chapters
   where slug = p_slug
   for update;

  if not found then
    insert into public.expedition_chapters (slug, sequence, status)
    values (p_slug, p_sequence, 'draft')
    returning * into v_chapter;
  elsif v_chapter.sequence <> p_sequence then
    raise exception 'CHAPTER_SEQUENCE_CONFLICT';
  end if;

  if exists (
    select 1
      from public.expedition_chapter_versions
     where chapter_id = v_chapter.id
       and content_version = p_content_version
  ) then
    raise exception 'CHAPTER_VERSION_EXISTS';
  end if;
  insert into public.expedition_chapter_versions (
    chapter_id, content_version, schema_version, minimum_build, manifest,
    manifest_hash, asset_prefix, approved_at, published_at, active
  ) values (
    v_chapter.id, p_content_version, p_schema_version, p_minimum_build, p_manifest,
    p_manifest_hash, p_asset_prefix, p_approved_at, now(), false
  ) returning * into v_version;

  select *
    into v_trophy
    from public.expedition_trophies
   where chapter_id = v_chapter.id
   for update;
  if not found then
    insert into public.expedition_trophies (
      chapter_id, slug, display_name, description, art_path, art_hash, metadata
    ) values (
      v_chapter.id, p_trophy_slug, p_trophy_display_name, p_trophy_description,
      p_trophy_art_path, p_trophy_art_hash, coalesce(p_trophy_metadata, '{}'::jsonb)
    );
  elsif (
    v_trophy.slug <> p_trophy_slug
    or v_trophy.display_name <> p_trophy_display_name
    or v_trophy.description <> p_trophy_description
    or v_trophy.art_path <> p_trophy_art_path
    or v_trophy.art_hash <> p_trophy_art_hash
    or v_trophy.metadata is distinct from coalesce(p_trophy_metadata, '{}'::jsonb)
  ) then
    raise exception 'CHAPTER_TROPHY_CONFLICT';
  end if;

  return jsonb_build_object(
    'chapter_id', v_chapter.id,
    'version_id', v_version.id,
    'content_version', v_version.content_version,
    'active', false
  );
end $$;

create or replace function public.activate_expedition_chapter_version(
  p_chapter_id uuid,
  p_content_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chapter public.expedition_chapters;
  v_version public.expedition_chapter_versions;
begin
  select *
    into v_chapter
    from public.expedition_chapters
   where id = p_chapter_id
   for update;

  if not found then
    raise exception 'CHAPTER_NOT_FOUND';
  end if;

  select *
    into v_version
    from public.expedition_chapter_versions
   where chapter_id = p_chapter_id
     and content_version = p_content_version
   for update;

  if not found then
    raise exception 'CHAPTER_VERSION_NOT_FOUND';
  end if;

  if v_version.approved_at is null then
    raise exception 'CHAPTER_NOT_APPROVED';
  end if;
  if v_version.published_at is null then
    raise exception 'CHAPTER_NOT_STAGED';
  end if;

  update public.expedition_chapter_versions
     set active = false
   where chapter_id = p_chapter_id
     and active
     and id <> v_version.id;

  update public.expedition_chapter_versions
     set active = true
   where id = v_version.id;

  update public.expedition_chapters
     set status = 'published',
         updated_at = now()
   where id = p_chapter_id;

  return jsonb_build_object(
    'chapter_id', p_chapter_id,
    'version_id', v_version.id,
    'content_version', v_version.content_version,
    'active', true
  );
end $$;

create or replace function public.claim_expedition_chapter_push(
  p_chapter_version_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.expedition_chapter_push_events;
  v_payload jsonb;
begin
  if not coalesce((
    select (value #>> '{}')::boolean
      from public.app_config
     where key = 'feature_chapter_push'
  ), false) then
    raise exception 'FEATURE_DISABLED';
  end if;

  select jsonb_build_object(
    'chapter_version_id', version.id,
    'chapter_id', chapter.id,
    'slug', chapter.slug,
    'content_version', version.content_version,
    'title', version.manifest->'summary'->>'title',
    'description', version.manifest->'summary'->>'description'
  )
    into v_payload
    from public.expedition_chapter_versions version
    join public.expedition_chapters chapter on chapter.id = version.chapter_id
   where version.id = p_chapter_version_id
     and version.active
     and chapter.status = 'published'
   for update of version, chapter;
  if v_payload is null then
    raise exception 'CHAPTER_NOT_ACTIVE';
  end if;

  select *
    into v_event
    from public.expedition_chapter_push_events
   where chapter_version_id = p_chapter_version_id
   for update;
  if found and v_event.status in ('pending', 'sent', 'uncertain') then
    raise exception 'CHAPTER_PUSH_ALREADY_CLAIMED';
  end if;

  insert into public.expedition_chapter_push_events (
    chapter_version_id, status, claimed_at, sent_at, message_id, error
  ) values (
    p_chapter_version_id, 'pending', now(), null, null, null
  )
  on conflict (chapter_version_id) do update
    set status = 'pending',
        claimed_at = now(),
        sent_at = null,
        message_id = null,
        error = null;

  return v_payload;
end $$;

create or replace function public.finish_expedition_chapter_push(
  p_chapter_version_id uuid,
  p_status text,
  p_message_id text default null,
  p_error text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.expedition_chapter_push_events;
begin
  if p_status not in ('sent', 'failed', 'uncertain') then
    raise exception 'INVALID_CHAPTER_PUSH_STATUS';
  end if;
  if p_status = 'sent' and coalesce(p_message_id, '') = '' then
    raise exception 'CHAPTER_PUSH_MESSAGE_ID_REQUIRED';
  end if;

  select *
    into v_event
    from public.expedition_chapter_push_events
   where chapter_version_id = p_chapter_version_id
   for update;
  if not found or v_event.status <> 'pending' then
    raise exception 'CHAPTER_PUSH_NOT_PENDING';
  end if;

  update public.expedition_chapter_push_events
     set status = p_status,
         sent_at = case when p_status = 'sent' then now() else null end,
         message_id = case when p_status = 'sent' then p_message_id else null end,
         error = left(p_error, 500)
   where chapter_version_id = p_chapter_version_id
   returning * into v_event;

  return to_jsonb(v_event);
end $$;

revoke all on function public.stage_expedition_chapter_version(
  text, integer, integer, integer, jsonb, jsonb, text, text, timestamptz,
  text, text, text, text, text, jsonb
) from public, anon, authenticated;
revoke all on function public.activate_expedition_chapter_version(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.claim_expedition_chapter_push(uuid)
  from public, anon, authenticated;
revoke all on function public.finish_expedition_chapter_push(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.stage_expedition_chapter_version(
  text, integer, integer, integer, jsonb, jsonb, text, text, timestamptz,
  text, text, text, text, text, jsonb
) to service_role;
grant execute on function public.activate_expedition_chapter_version(uuid, integer)
  to service_role;
grant execute on function public.claim_expedition_chapter_push(uuid)
  to service_role;
grant execute on function public.finish_expedition_chapter_push(uuid, text, text, text)
  to service_role;
