-- Vision v17 adds canonical body height while preserving v15 sprite prompts.
update public.app_config
set value = '"v17"'::jsonb,
    updated_at = now()
where key = 'prompt_version';
