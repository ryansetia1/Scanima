-- Cover Atlas foreign keys used by account, chapter-version, and form cleanup.
create index atlas_forms_owner_idx
  on public.atlas_forms (owner_id);

create index atlas_forms_chapter_version_idx
  on public.atlas_forms (chapter_version_id);

create index seeker_atlas_form_idx
  on public.seeker_atlas_discoveries (form_id);
