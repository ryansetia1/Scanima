-- Kill switch untuk facing audit (lihat replicate_webhook/index.ts +
-- _shared/facing_audit.mjs). Tidak ada perubahan skema: manifest sudah jsonb.
insert into public.app_config (key, value)
values ('feature_facing_audit', 'true'::jsonb)
on conflict (key) do nothing;
