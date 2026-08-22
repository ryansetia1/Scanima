insert into public.app_config (key, value)
values ('synthesis_prompt_version', '"v43"'::jsonb)
on conflict (key) do update set value = excluded.value;
