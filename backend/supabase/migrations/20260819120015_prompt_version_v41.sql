-- Anima Name Lineage v41 goes live for both capture and evolution. The four art
-- prompts are byte-identical to the versions they replace (capture sprite v31,
-- evolve sprite v30), so this flip changes names only and needs no art eval.
-- Rollback: prompt_version back to "v31" and evolution_prompt_version to "v30".
update public.app_config
set value = '"v41"'::jsonb
where key = 'prompt_version';

update public.app_config
set value = '"v41"'::jsonb
where key = 'evolution_prompt_version';
