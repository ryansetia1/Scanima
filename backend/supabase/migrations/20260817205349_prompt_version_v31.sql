-- Capture Vibe v31 is the new default. Evolution stays v30.
update public.app_config
set value = '"v31"'::jsonb
where key = 'prompt_version';
