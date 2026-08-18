-- Anima Atlas: one immutable-ish form record, many per-Seeker discoveries.
-- Gallery rows remain the lineage publication/moderation registry; the public
-- feed is retired by the client/Edge Function in the same release.

insert into public.app_config (key, value)
select 'feature_atlas', value
  from public.app_config
 where key = 'feature_gallery'
on conflict (key) do nothing;

create table public.atlas_forms (
  id                   uuid primary key default gen_random_uuid(),
  stable_key           text not null unique,
  source_kind          text not null,
  anima_id             uuid references public.animas(id) on delete cascade,
  publication_id       uuid references public.gallery_entries(id) on delete set null,
  owner_id             uuid references public.profiles(id) on delete cascade,
  chapter_id           uuid references public.expedition_chapters(id) on delete cascade,
  chapter_version_id   uuid references public.expedition_chapter_versions(id) on delete set null,
  source_slug          text not null,
  stage                smallint not null,
  display_name         text not null,
  subject_kind         text not null default 'object',
  element              text not null,
  secondary_element    text,
  rarity               smallint not null default 1,
  base_stats           jsonb not null,
  body_height_cm       integer not null,
  strike_name          text not null default '',
  surge_name           text not null default '',
  sheet_path           text not null,
  manifest             jsonb not null,
  thumb_path           text,
  moderation_status    text not null default 'pending',
  catalog_active       boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint atlas_forms_source_valid check (source_kind in ('player', 'expedition')),
  constraint atlas_forms_stage_valid check (stage between 1 and 3),
  constraint atlas_forms_name_valid check (char_length(display_name) between 1 and 48),
  constraint atlas_forms_subject_valid check (subject_kind in ('object', 'animal', 'chapter')),
  constraint atlas_forms_rarity_valid check (rarity between 1 and 5),
  constraint atlas_forms_stats_object check (jsonb_typeof(base_stats) = 'object'),
  constraint atlas_forms_height_valid check (body_height_cm between 20 and 2000),
  constraint atlas_forms_manifest_object check (jsonb_typeof(manifest) = 'object'),
  constraint atlas_forms_moderation_valid
    check (moderation_status in ('pending', 'approved', 'rejected')),
  constraint atlas_forms_identity_valid check (
    (
      source_kind = 'player'
      and anima_id is not null
      and owner_id is not null
      and chapter_id is null
      and chapter_version_id is null
    )
    or
    (
      source_kind = 'expedition'
      and anima_id is null
      and publication_id is null
      and owner_id is null
      and chapter_id is not null
      and chapter_version_id is not null
    )
  )
);

create unique index atlas_forms_player_stage_idx
  on public.atlas_forms (anima_id, stage)
  where source_kind = 'player';

create index atlas_forms_publication_idx
  on public.atlas_forms (publication_id, stage)
  where publication_id is not null;

create index atlas_forms_chapter_idx
  on public.atlas_forms (chapter_id, catalog_active, source_slug, stage)
  where source_kind = 'expedition';

create table public.seeker_atlas_discoveries (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null references public.profiles(id) on delete cascade,
  form_id               uuid not null references public.atlas_forms(id) on delete cascade,
  discovery_source      text not null,
  first_seen_at         timestamptz not null default now(),
  last_seen_at          timestamptz not null default now(),
  encounter_count       integer not null default 1,
  level_at_first_seen   integer,
  level_at_last_seen    integer,
  constraint seeker_atlas_discovery_unique unique (owner_id, form_id),
  constraint seeker_atlas_source_valid
    check (discovery_source in ('scanned', 'expedition', 'duel')),
  constraint seeker_atlas_count_positive check (encounter_count >= 1),
  constraint seeker_atlas_first_level_valid
    check (level_at_first_seen is null or level_at_first_seen between 1 and 40),
  constraint seeker_atlas_last_level_valid
    check (level_at_last_seen is null or level_at_last_seen between 1 and 40),
  constraint seeker_atlas_time_order check (last_seen_at >= first_seen_at)
);

create index seeker_atlas_owner_recent_idx
  on public.seeker_atlas_discoveries (owner_id, last_seen_at desc, id desc);

create index seeker_atlas_owner_source_idx
  on public.seeker_atlas_discoveries
  (owner_id, discovery_source, last_seen_at desc, id desc);

alter table public.atlas_forms enable row level security;
alter table public.seeker_atlas_discoveries enable row level security;

revoke all on public.atlas_forms from public, anon, authenticated;
revoke all on public.seeker_atlas_discoveries from public, anon, authenticated;
grant all on public.atlas_forms to service_role;
grant all on public.seeker_atlas_discoveries to service_role;

create or replace function public._atlas_upsert_discovery(
  p_owner uuid,
  p_form_id uuid,
  p_source text,
  p_seen_at timestamptz default now(),
  p_level integer default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form public.atlas_forms;
  v_seen_at timestamptz := coalesce(p_seen_at, now());
  v_level integer := case
    when p_level is null then null
    else greatest(1, least(40, p_level))
  end;
begin
  select * into v_form from public.atlas_forms where id = p_form_id;
  if not found then raise exception 'ATLAS_FORM_NOT_FOUND'; end if;

  if p_source = 'scanned' then
    if v_form.source_kind <> 'player' or v_form.owner_id is distinct from p_owner then
      raise exception 'ATLAS_SOURCE_MISMATCH';
    end if;
  elsif p_source = 'duel' then
    if v_form.source_kind <> 'player'
       or v_form.owner_id = p_owner
       or v_form.publication_id is null
       or v_form.moderation_status <> 'approved'
       or not exists (
         select 1
           from public.gallery_entries entry
          where entry.id = v_form.publication_id
            and entry.published
            and not entry.auto_hidden
       )
       or exists (
         select 1
           from public.gallery_hidden hidden
          where hidden.owner_id = p_owner
            and hidden.entry_id = v_form.publication_id
       ) then
      return;
    end if;
  elsif p_source = 'expedition' then
    if v_form.source_kind <> 'expedition' then
      raise exception 'ATLAS_SOURCE_MISMATCH';
    end if;
  else
    raise exception 'ATLAS_SOURCE_INVALID';
  end if;

  insert into public.seeker_atlas_discoveries (
    owner_id, form_id, discovery_source,
    first_seen_at, last_seen_at, encounter_count,
    level_at_first_seen, level_at_last_seen
  ) values (
    p_owner, p_form_id, p_source,
    v_seen_at, v_seen_at, 1,
    v_level, v_level
  )
  on conflict (owner_id, form_id) do update set
    last_seen_at = greatest(
      public.seeker_atlas_discoveries.last_seen_at,
      excluded.last_seen_at
    ),
    encounter_count = case
      when public.seeker_atlas_discoveries.discovery_source = 'scanned'
        then public.seeker_atlas_discoveries.encounter_count
      when excluded.last_seen_at > public.seeker_atlas_discoveries.last_seen_at
        then public.seeker_atlas_discoveries.encounter_count + 1
      else public.seeker_atlas_discoveries.encounter_count
    end,
    level_at_last_seen = case
      when excluded.last_seen_at >= public.seeker_atlas_discoveries.last_seen_at
        then coalesce(excluded.level_at_last_seen, public.seeker_atlas_discoveries.level_at_last_seen)
      else public.seeker_atlas_discoveries.level_at_last_seen
    end;
end $$;

create or replace function public.register_player_atlas_form(
  p_anima_id uuid,
  p_stage smallint
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anima public.animas;
  v_saved public.anima_forms;
  v_generation public.generations;
  v_entry public.gallery_entries;
  v_form public.atlas_forms;
  v_sheet_path text;
  v_manifest jsonb;
  v_height integer;
  v_strike_name text;
  v_surge_name text;
  v_seen_at timestamptz;
  v_display_name text;
  v_moderation text := 'pending';
  v_thumb_path text;
begin
  select * into v_anima from public.animas where id = p_anima_id;
  if not found then raise exception 'ANIMA_NOT_FOUND'; end if;
  if p_stage not between 1 and 3 then raise exception 'ATLAS_STAGE_INVALID'; end if;

  if v_anima.stage = p_stage and v_anima.status in ('ready', 'evolving') then
    v_sheet_path := v_anima.sheet_path;
    v_manifest := v_anima.manifest;
    v_height := v_anima.body_height_cm;
    v_strike_name := v_anima.strike_name;
    v_surge_name := v_anima.surge_name;
  else
    select * into v_saved
      from public.anima_forms
     where anima_id = p_anima_id and stage = p_stage;
    if not found then raise exception 'ATLAS_FORM_NOT_FOUND'; end if;
    v_sheet_path := v_saved.sheet_path;
    v_manifest := v_saved.manifest;
    v_height := v_saved.body_height_cm;
    v_strike_name := v_saved.strike_name;
    v_surge_name := v_saved.surge_name;
  end if;

  if coalesce(v_sheet_path, '') = ''
     or v_manifest is null
     or jsonb_typeof(v_manifest) <> 'object' then
    raise exception 'ATLAS_FORM_NO_ART';
  end if;

  select * into v_generation
    from public.generations
   where anima_id = p_anima_id
     and status = 'succeeded'
     and coalesce(target_stage, 1) = p_stage
   order by created_at desc
   limit 1;

  v_display_name := left(
    coalesce(nullif(btrim(v_generation.vision_result->>'suggested_name'), ''), 'Anima'),
    48
  );
  v_seen_at := coalesce(v_generation.created_at, v_saved.created_at, v_anima.created_at, now());

  select * into v_entry
    from public.gallery_entries
   where anima_id = p_anima_id;
  if found and v_entry.stage = p_stage then
    v_moderation := v_entry.moderation_status;
    v_thumb_path := v_entry.thumb_path;
  end if;

  insert into public.atlas_forms (
    stable_key, source_kind, anima_id, publication_id, owner_id,
    chapter_id, chapter_version_id, source_slug, stage,
    display_name, subject_kind, element, secondary_element, rarity,
    base_stats, body_height_cm, strike_name, surge_name,
    sheet_path, manifest, thumb_path, moderation_status, catalog_active
  ) values (
    format('player:%s:%s', p_anima_id, p_stage),
    'player', p_anima_id, v_entry.id, v_anima.owner_id,
    null, null, p_anima_id::text, p_stage,
    v_display_name, v_anima.subject_kind, v_anima.element,
    v_anima.secondary_element, v_anima.rarity,
    v_anima.base_stats, v_height, v_strike_name, v_surge_name,
    v_sheet_path, v_manifest, v_thumb_path, v_moderation, true
  )
  on conflict (stable_key) do update set
    publication_id = coalesce(excluded.publication_id, public.atlas_forms.publication_id),
    display_name = excluded.display_name,
    subject_kind = excluded.subject_kind,
    element = excluded.element,
    secondary_element = excluded.secondary_element,
    rarity = excluded.rarity,
    base_stats = excluded.base_stats,
    body_height_cm = excluded.body_height_cm,
    strike_name = excluded.strike_name,
    surge_name = excluded.surge_name,
    sheet_path = excluded.sheet_path,
    manifest = excluded.manifest,
    thumb_path = coalesce(excluded.thumb_path, public.atlas_forms.thumb_path),
    moderation_status = case
      when public.atlas_forms.moderation_status = 'approved' then 'approved'
      else excluded.moderation_status
    end,
    updated_at = now()
  returning * into v_form;

  perform public._atlas_upsert_discovery(
    v_anima.owner_id,
    v_form.id,
    'scanned',
    v_seen_at,
    public.anima_level_from_exp(v_anima.care_score)
  );
  return v_form.id;
end $$;

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

  insert into public.atlas_forms (
    stable_key, source_kind, anima_id, publication_id, owner_id,
    chapter_id, chapter_version_id, source_slug, stage,
    display_name, subject_kind, element, secondary_element, rarity,
    base_stats, body_height_cm, strike_name, surge_name,
    sheet_path, manifest, moderation_status, catalog_active
  ) values (
    format('expedition:%s:%s:%s', v_chapter.slug, v_slug, v_stage),
    'expedition', null, null, null,
    v_chapter.id, p_version_id, v_slug, v_stage,
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

create or replace function public.sync_atlas_expedition_version(
  p_version_id uuid
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.expedition_chapter_versions;
  v_member jsonb;
  v_count integer := 0;
begin
  select * into v_version
    from public.expedition_chapter_versions
   where id = p_version_id;
  if not found then raise exception 'CHAPTER_VERSION_NOT_FOUND'; end if;

  update public.atlas_forms
     set catalog_active = false, updated_at = now()
   where source_kind = 'expedition'
     and chapter_id = v_version.chapter_id;

  for v_member in
    select distinct on (member->>'anima_id', member->>'stage') member
      from jsonb_array_elements(v_version.manifest->'opponents') opponent
      cross join lateral jsonb_array_elements(opponent->'roster') member
     order by member->>'anima_id', member->>'stage'
  loop
    perform public._atlas_register_expedition_member(p_version_id, v_member, true);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function public._atlas_record_expedition_member(
  p_owner uuid,
  p_version_id uuid,
  p_member jsonb,
  p_seen_at timestamptz default now()
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form_id uuid;
begin
  if coalesce(p_member->>'anima_id', '') !~ '^[a-z0-9][a-z0-9-]{2,63}$'
     or coalesce(p_member->>'stage', '') !~ '^[1-3]$'
     or jsonb_typeof(p_member->'base_stats') <> 'object'
     or jsonb_typeof(p_member->'manifest') <> 'object'
     or coalesce(p_member->>'sheet_path', '') = '' then
    return;
  end if;
  v_form_id := public._atlas_register_expedition_member(
    p_version_id,
    p_member,
    false
  );
  perform public._atlas_upsert_discovery(
    p_owner,
    v_form_id,
    'expedition',
    p_seen_at,
    case
      when coalesce(p_member->>'level', '') ~ '^[0-9]+$'
        then (p_member->>'level')::integer
      else null
    end
  );
end $$;

create or replace function public.atlas_register_anima_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.gallery_entries;
begin
  if new.status <> 'ready' then return new; end if;
  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.stage is not distinct from new.stage
     and old.sheet_path is not distinct from new.sheet_path then
    return new;
  end if;

  perform public.register_player_atlas_form(new.id, new.stage);

  if tg_op = 'UPDATE'
     and (old.stage is distinct from new.stage or old.sheet_path is distinct from new.sheet_path) then
    select * into v_entry
      from public.gallery_entries
     where anima_id = new.id;
    if found and v_entry.published then
      update public.atlas_forms
         set thumb_path = v_entry.thumb_path,
             moderation_status = v_entry.moderation_status,
             updated_at = now()
       where anima_id = new.id and stage = old.stage;
      update public.gallery_entries
         set stage = new.stage,
             moderation_status = 'pending',
             thumb_path = null,
             updated_at = now()
       where id = v_entry.id;
    end if;
  end if;
  return new;
end $$;

create trigger anima_atlas_register_ready
after insert or update of status, stage, sheet_path on public.animas
for each row
execute function public.atlas_register_anima_ready();

create or replace function public.atlas_sync_publication()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.register_player_atlas_form(new.anima_id, new.stage);
  update public.atlas_forms
     set publication_id = new.id,
         moderation_status = case
           when stage = new.stage then new.moderation_status
           else moderation_status
         end,
         thumb_path = case
           when stage = new.stage then coalesce(new.thumb_path, thumb_path)
           else thumb_path
         end,
         updated_at = now()
   where anima_id = new.anima_id;

  if not new.published or new.auto_hidden then
    delete from public.seeker_atlas_discoveries discovery
     using public.atlas_forms form
     where discovery.form_id = form.id
       and form.anima_id = new.anima_id
       and discovery.owner_id <> form.owner_id;
  end if;
  return new;
end $$;

create trigger gallery_atlas_sync_publication
after insert or update of published, moderation_status, auto_hidden, stage, thumb_path
on public.gallery_entries
for each row execute function public.atlas_sync_publication();

create or replace function public.atlas_cleanup_deleted_publication()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.seeker_atlas_discoveries discovery
   using public.atlas_forms form
   where discovery.form_id = form.id
     and form.anima_id = old.anima_id
     and discovery.owner_id <> form.owner_id;
  return old;
end $$;

create trigger gallery_atlas_cleanup_deleted
before delete on public.gallery_entries
for each row execute function public.atlas_cleanup_deleted_publication();

create or replace function public.atlas_hide_reporter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.gallery_hidden (owner_id, entry_id)
  values (new.reporter_id, new.entry_id)
  on conflict do nothing;

  delete from public.seeker_atlas_discoveries discovery
   using public.atlas_forms form
   where discovery.form_id = form.id
     and form.publication_id = new.entry_id
     and discovery.owner_id = new.reporter_id;
  return new;
end $$;

create trigger gallery_report_hides_atlas
after insert on public.gallery_reports
for each row execute function public.atlas_hide_reporter();

create or replace function public.atlas_record_battle_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stage smallint;
  v_form_id uuid;
begin
  if new.bot_anima_id is null then return new; end if;
  if coalesce(new.bot_snapshot->>'stage', '') !~ '^[1-3]$' then return new; end if;
  v_stage := (new.bot_snapshot->>'stage')::smallint;

  if not exists (
    select 1
      from public.gallery_entries entry
     where entry.anima_id = new.bot_anima_id
       and entry.published
       and not entry.auto_hidden
  ) then
    return new;
  end if;

  v_form_id := public.register_player_atlas_form(new.bot_anima_id, v_stage);
  perform public._atlas_upsert_discovery(
    new.owner_id,
    v_form_id,
    'duel',
    new.created_at,
    case
      when coalesce(new.bot_snapshot->>'level', '') ~ '^[0-9]+$'
        then (new.bot_snapshot->>'level')::integer
      else null
    end
  );
  return new;
end $$;

create trigger battle_session_records_atlas
after insert on public.battle_sessions
for each row execute function public.atlas_record_battle_session();

create or replace function public.atlas_record_expedition_start()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version_id uuid;
  v_slot integer;
  v_member jsonb;
begin
  select chapter_version_id into v_version_id
    from public.expedition_runs
   where id = new.run_id;
  v_slot := greatest(0, coalesce((new.state #>> '{opponent,active_slot}')::integer, 0));
  v_member := new.opponent_snapshot->v_slot;
  if v_version_id is not null and v_member is not null then
    perform public._atlas_record_expedition_member(
      new.owner_id,
      v_version_id,
      v_member,
      new.created_at
    );
  end if;
  return new;
end $$;

create trigger expedition_encounter_records_atlas
after insert on public.expedition_encounters
for each row execute function public.atlas_record_expedition_start();

create or replace function public.atlas_record_expedition_turn()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_encounter public.expedition_encounters;
  v_version_id uuid;
  v_event jsonb;
  v_member jsonb;
  v_slot integer;
begin
  select * into v_encounter
    from public.expedition_encounters
   where id = new.encounter_id;
  if not found then return new; end if;
  select chapter_version_id into v_version_id
    from public.expedition_runs
   where id = v_encounter.run_id;

  for v_event in
    select value
      from jsonb_array_elements(coalesce(new.response->'events', '[]'::jsonb))
  loop
    v_member := null;
    if v_event->>'actor' = 'opponent' and v_event->>'type' = 'switch'
       and coalesce(v_event->>'to_slot', '') ~ '^[0-3]$' then
      v_slot := (v_event->>'to_slot')::integer;
      v_member := v_encounter.opponent_snapshot->v_slot;
    elsif v_event->>'actor' = 'opponent' and v_event->>'type' = 'final_ace' then
      select member into v_member
        from jsonb_array_elements(v_encounter.opponent_snapshot) member
       where member->>'anima_id' = v_event->>'anima_id'
       limit 1;
    end if;
    if v_version_id is not null and v_member is not null then
      perform public._atlas_record_expedition_member(
        v_encounter.owner_id,
        v_version_id,
        v_member,
        new.created_at
      );
    end if;
  end loop;
  return new;
end $$;

create trigger expedition_turn_records_atlas
after insert on public.expedition_encounter_turns
for each row execute function public.atlas_record_expedition_turn();

create or replace function public.atlas_sync_active_chapter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.active then
    perform public.sync_atlas_expedition_version(new.id);
  end if;
  return new;
end $$;

create trigger expedition_version_syncs_atlas
after insert or update of active on public.expedition_chapter_versions
for each row
when (new.active)
execute function public.atlas_sync_active_chapter();

-- Current data backfill. Every call is idempotent through stable/unique keys.
do $$
declare
  v_row record;
  v_form_id uuid;
  v_member jsonb;
  v_event jsonb;
  v_slot integer;
begin
  for v_row in
    select id from public.expedition_chapter_versions where active
  loop
    perform public.sync_atlas_expedition_version(v_row.id);
  end loop;

  for v_row in
    select anima_id, stage from public.anima_forms
  loop
    perform public.register_player_atlas_form(v_row.anima_id, v_row.stage);
  end loop;
  for v_row in
    select id, stage from public.animas
     where status in ('ready', 'evolving') and sheet_path is not null and manifest is not null
  loop
    perform public.register_player_atlas_form(v_row.id, v_row.stage);
  end loop;

  for v_row in
    select session.*, entry.id as entry_id
      from public.battle_sessions session
      join public.gallery_entries entry on entry.anima_id = session.bot_anima_id
     where entry.published and entry.moderation_status = 'approved' and not entry.auto_hidden
       and coalesce(session.bot_snapshot->>'stage', '') ~ '^[1-3]$'
     order by session.created_at
  loop
    v_form_id := public.register_player_atlas_form(
      v_row.bot_anima_id,
      (v_row.bot_snapshot->>'stage')::smallint
    );
    update public.atlas_forms
       set publication_id = v_row.entry_id,
           moderation_status = 'approved',
           updated_at = now()
     where id = v_form_id;
    perform public._atlas_upsert_discovery(
      v_row.owner_id,
      v_form_id,
      'duel',
      v_row.created_at,
      case
        when coalesce(v_row.bot_snapshot->>'level', '') ~ '^[0-9]+$'
          then (v_row.bot_snapshot->>'level')::integer
        else null
      end
    );
  end loop;

  for v_row in
    select encounter.*, run.chapter_version_id
      from public.expedition_encounters encounter
      join public.expedition_runs run on run.id = encounter.run_id
     order by encounter.created_at
  loop
    v_slot := greatest(
      0,
      least(3, coalesce((v_row.state #>> '{opponent,active_slot}')::integer, 0))
    );
    v_member := v_row.opponent_snapshot->v_slot;
    if v_member is not null then
      perform public._atlas_record_expedition_member(
        v_row.owner_id,
        v_row.chapter_version_id,
        v_member,
        v_row.created_at
      );
    end if;
  end loop;

  for v_row in
    select turn.*, encounter.owner_id, encounter.opponent_snapshot,
           run.chapter_version_id
      from public.expedition_encounter_turns turn
      join public.expedition_encounters encounter on encounter.id = turn.encounter_id
      join public.expedition_runs run on run.id = encounter.run_id
     order by turn.created_at
  loop
    for v_event in
      select value
        from jsonb_array_elements(coalesce(v_row.response->'events', '[]'::jsonb))
    loop
      v_member := null;
      if v_event->>'actor' = 'opponent' and v_event->>'type' = 'switch'
         and coalesce(v_event->>'to_slot', '') ~ '^[0-3]$' then
        v_member := v_row.opponent_snapshot->((v_event->>'to_slot')::integer);
      elsif v_event->>'actor' = 'opponent' and v_event->>'type' = 'final_ace' then
        select member into v_member
          from jsonb_array_elements(v_row.opponent_snapshot) member
         where member->>'anima_id' = v_event->>'anima_id'
         limit 1;
      end if;
      if v_member is not null then
        perform public._atlas_record_expedition_member(
          v_row.owner_id,
          v_row.chapter_version_id,
          v_member,
          v_row.created_at
        );
      end if;
    end loop;
  end loop;
end $$;

revoke all on function public._atlas_upsert_discovery(
  uuid, uuid, text, timestamptz, integer
) from public, anon, authenticated;
revoke all on function public.register_player_atlas_form(uuid, smallint)
  from public, anon, authenticated;
revoke all on function public._atlas_register_expedition_member(uuid, jsonb, boolean)
  from public, anon, authenticated;
revoke all on function public.sync_atlas_expedition_version(uuid)
  from public, anon, authenticated;
revoke all on function public._atlas_record_expedition_member(
  uuid, uuid, jsonb, timestamptz
) from public, anon, authenticated;
revoke all on function public.atlas_register_anima_ready()
  from public, anon, authenticated;
revoke all on function public.atlas_sync_publication()
  from public, anon, authenticated;
revoke all on function public.atlas_cleanup_deleted_publication()
  from public, anon, authenticated;
revoke all on function public.atlas_hide_reporter()
  from public, anon, authenticated;
revoke all on function public.atlas_record_battle_session()
  from public, anon, authenticated;
revoke all on function public.atlas_record_expedition_start()
  from public, anon, authenticated;
revoke all on function public.atlas_record_expedition_turn()
  from public, anon, authenticated;
revoke all on function public.atlas_sync_active_chapter()
  from public, anon, authenticated;

grant execute on function public._atlas_upsert_discovery(
  uuid, uuid, text, timestamptz, integer
) to service_role;
grant execute on function public.register_player_atlas_form(uuid, smallint)
  to service_role;
grant execute on function public._atlas_register_expedition_member(uuid, jsonb, boolean)
  to service_role;
grant execute on function public.sync_atlas_expedition_version(uuid)
  to service_role;
grant execute on function public._atlas_record_expedition_member(
  uuid, uuid, jsonb, timestamptz
) to service_role;
