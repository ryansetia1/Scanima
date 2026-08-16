update public.app_config
set value = '"v19"'::jsonb
where key = 'prompt_version';
