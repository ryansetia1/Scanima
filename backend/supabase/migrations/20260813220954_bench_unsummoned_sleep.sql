-- Anima yang bukan companion aktif tidur. Kursi aktif hidup di
-- profiles.active_anima_id; client tidak boleh menulis kolom ini.
alter table public.profiles
  add column if not exists active_anima_id uuid
    references public.animas(id) on delete set null;

alter table public.care_events drop constraint if exists care_events_action_valid;
alter table public.care_events add constraint care_events_action_valid
  check (action in ('feed', 'clean', 'sleep', 'wake', 'play', 'summon'));
