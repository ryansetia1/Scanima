-- PostgREST resolves `expedition_trophies(*)` embeds from foreign keys only.
-- seeker_featured_trophies points at seeker_trophies(owner_id, trophy_id), so
-- the featured select answered 400 and the whole `trophies` operation threw a
-- 500 -- the Trophy Showcase never rendered for anyone who cleared a chapter.
-- The composite key above already guarantees the row exists; this direct key is
-- what makes the relationship discoverable.

alter table public.seeker_featured_trophies
  add constraint seeker_featured_trophies_trophy_id_fkey
  foreign key (trophy_id) references public.expedition_trophies(id)
  on delete restrict;
