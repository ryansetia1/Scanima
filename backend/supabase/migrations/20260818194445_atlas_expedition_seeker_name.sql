-- Special Expedition forms belong to the chapter's authored Boss Seeker.
-- Keep this denormalized on the Atlas form so list/detail do not parse or join
-- the complete immutable chapter manifest on every read.

alter table public.atlas_forms
  add column chapter_seeker_name text;

alter table public.atlas_forms
  add constraint atlas_forms_chapter_seeker_name_valid
  check (
    chapter_seeker_name is null
    or (
      source_kind = 'expedition'
      and char_length(chapter_seeker_name) between 1 and 48
    )
  );

create or replace function public._atlas_register_expedition_member(
  p_version_id uuid,
  p_member jsonb,
  p_catalog_active boolean default false
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.expedition_chapter_versions;
  v_chapter public.expedition_chapters;
  v_form public.atlas_forms;
  v_slug text := btrim(coalesce(p_member->>'anima_id', ''));
  v_stage smallint := coalesce((p_member->>'stage')::smallint, 0);
  v_chapter_seeker_name text;
begin
  select * into v_version
    from public.expedition_chapter_versions
   where id = p_version_id;
  if not found then raise exception 'CHAPTER_VERSION_NOT_FOUND'; end if;
  select * into v_chapter
    from public.expedition_chapters
   where id = v_version.chapter_id;
  if not found then raise exception 'CHAPTER_NOT_FOUND'; end if;

  if v_slug !~ '^[a-z0-9][a-z0-9-]{2,63}$'
     or v_stage not between 1 and 3
     or jsonb_typeof(p_member->'base_stats') <> 'object'
     or jsonb_typeof(p_member->'manifest') <> 'object'
     or coalesce(p_member->>'sheet_path', '') = '' then
    raise exception 'ATLAS_EXPEDITION_FORM_INVALID';
  end if;

  v_chapter_seeker_name := case
    when p_member->'special' = 'true'::jsonb
      then left(
        nullif(btrim(v_version.manifest #>> '{boss_seeker,display_name}'), ''),
        48
      )
    else null
  end;

  insert into public.atlas_forms (
    stable_key, source_kind, anima_id, publication_id, owner_id,
    chapter_id, chapter_version_id, source_slug, chapter_seeker_name, stage,
    display_name, subject_kind, element, secondary_element, rarity,
    base_stats, body_height_cm, strike_name, surge_name,
    sheet_path, manifest, moderation_status, catalog_active
  ) values (
    format('expedition:%s:%s:%s', v_chapter.slug, v_slug, v_stage),
    'expedition', null, null, null,
    v_chapter.id, p_version_id, v_slug, v_chapter_seeker_name, v_stage,
    left(coalesce(nullif(btrim(p_member->>'name'), ''), 'Anima'), 48),
    'chapter', coalesce(nullif(p_member->>'element', ''), 'neutral'),
    nullif(p_member->>'secondary_element', ''),
    greatest(1, least(5, coalesce((p_member->>'rarity')::smallint, 1))),
    p_member->'base_stats',
    greatest(20, least(2000, coalesce((p_member->>'body_height_cm')::integer, 120))),
    left(coalesce(p_member->>'strike_name', ''), 24),
    left(coalesce(p_member->>'surge_name', ''), 24),
    p_member->>'sheet_path',
    p_member->'manifest',
    'approved',
    p_catalog_active
  )
  on conflict (stable_key) do update set
    chapter_version_id = case
      when excluded.catalog_active then excluded.chapter_version_id
      else public.atlas_forms.chapter_version_id
    end,
    chapter_seeker_name = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.chapter_seeker_name
      else public.atlas_forms.chapter_seeker_name
    end,
    display_name = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.display_name else public.atlas_forms.display_name
    end,
    element = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.element else public.atlas_forms.element
    end,
    secondary_element = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.secondary_element else public.atlas_forms.secondary_element
    end,
    rarity = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.rarity else public.atlas_forms.rarity
    end,
    base_stats = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.base_stats else public.atlas_forms.base_stats
    end,
    body_height_cm = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.body_height_cm else public.atlas_forms.body_height_cm
    end,
    strike_name = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.strike_name else public.atlas_forms.strike_name
    end,
    surge_name = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.surge_name else public.atlas_forms.surge_name
    end,
    sheet_path = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.sheet_path else public.atlas_forms.sheet_path
    end,
    manifest = case
      when excluded.catalog_active or not public.atlas_forms.catalog_active
        then excluded.manifest else public.atlas_forms.manifest
    end,
    catalog_active = public.atlas_forms.catalog_active or excluded.catalog_active,
    updated_at = now()
  returning * into v_form;
  return v_form.id;
end $$;

revoke all on function public._atlas_register_expedition_member(
  uuid, jsonb, boolean
) from public, anon, authenticated;
grant execute on function public._atlas_register_expedition_member(
  uuid, jsonb, boolean
) to service_role;

do $$
declare
  v_version_id uuid;
begin
  for v_version_id in
    select id from public.expedition_chapter_versions where active
  loop
    perform public.sync_atlas_expedition_version(v_version_id);
  end loop;
end $$;
