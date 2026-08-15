-- Rollout Team Battle/Expedition. Hanya config; schema gameplay datang dalam
-- migration vertikal masing-masing supaya feature flag bisa tetap mati.
insert into public.app_config (key, value) values
  ('feature_team_battle', 'false'::jsonb),
  ('feature_expedition', 'false'::jsonb),
  ('feature_chapter_push', 'false'::jsonb),
  ('team_battle_energy_per_member', '10'::jsonb),
  ('team_battle_rewarded_wins_per_day', '2'::jsonb),
  ('team_battle_bits_per_day', '40'::jsonb),
  ('team_battle_active_exp', '2'::jsonb),
  ('team_battle_bench_exp', '1'::jsonb),
  ('expedition_energy_per_member', '10'::jsonb),
  ('expedition_rewarded_encounters_per_day', '3'::jsonb),
  ('expedition_active_exp', '2'::jsonb),
  ('expedition_bench_exp', '1'::jsonb)
on conflict (key) do nothing;
