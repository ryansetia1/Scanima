-- This legacy publication predates generated-name persistence. Repair only the
-- known generic projection; player Rename values remain private everywhere else.
update public.gallery_entries
set display_name = 'Veridian',
    updated_at = now()
where anima_id = 'c80ddef5-533d-4f36-9f26-7f449981e996'
  and display_name = 'Anima';

update public.atlas_forms
set display_name = 'Veridian',
    updated_at = now()
where anima_id = 'c80ddef5-533d-4f36-9f26-7f449981e996'
  and display_name = 'Anima';

update public.battle_sessions
set bot_snapshot = jsonb_set(
  bot_snapshot,
  '{name}',
  to_jsonb('Veridian'::text),
  true
)
where bot_anima_id = 'c80ddef5-533d-4f36-9f26-7f449981e996'
  and coalesce(bot_snapshot->>'name', '') in ('', 'Anima');
