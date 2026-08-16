update public.app_config
set value = '"v18"'::jsonb
where key = 'prompt_version';
