-- Grounded-pose art contract: Capture and Evolution use v47; Synthesis adds
-- the v48 solid-support override. Roll back to v41 / v41 / v45.
insert into public.app_config (key, value)
values
  ('prompt_version', '"v47"'::jsonb),
  ('evolution_prompt_version', '"v47"'::jsonb),
  ('synthesis_prompt_version', '"v48"'::jsonb)
on conflict (key) do update
set value = excluded.value;
