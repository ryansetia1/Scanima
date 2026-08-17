-- Evolution name lineage: v30 Plan suggested_name, lock backfill.
-- commit_evolution sengaja tidak menulis nickname; Rename client yang mengubahnya.

update public.app_config
   set value = '"v30"'::jsonb
 where key = 'evolution_prompt_version';

update public.anima_evolution_locks
   set evolution_plan = evolution_plan || jsonb_build_object('suggested_name', 'Veridara')
 where anima_id = 'c80ddef5-533d-4f36-9f26-7f449981e996'
   and target_stage = 2;

update public.anima_evolution_locks
   set evolution_plan = evolution_plan || jsonb_build_object('suggested_name', 'Sunhundor')
 where anima_id = '2168d17e-440d-4ba3-9004-5104800c6722'
   and target_stage = 2;

update public.anima_evolution_locks
   set evolution_plan = evolution_plan || jsonb_build_object('suggested_name', 'Sunhundrax')
 where anima_id = '2168d17e-440d-4ba3-9004-5104800c6722'
   and target_stage = 3;

update public.anima_evolution_locks
   set evolution_plan = evolution_plan || jsonb_build_object('suggested_name', 'Playtrax')
 where anima_id = '99b04a1c-07be-4753-be04-ae68183817e6'
   and target_stage = 2;

update public.anima_evolution_locks
   set evolution_plan = evolution_plan || jsonb_build_object('suggested_name', 'Playtrion')
 where anima_id = '99b04a1c-07be-4753-be04-ae68183817e6'
   and target_stage = 3;
