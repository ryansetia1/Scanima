-- Promote prompt v7 (3x3 sheet + move names + battle FX cells) to production.
-- Cache hits on 2x2 library rows stay valid; species_key is unchanged.
update app_config
set value = '"v7"'::jsonb, updated_at = now()
where key = 'prompt_version';
