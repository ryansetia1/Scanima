-- Re-review the seven production Anima as playable creatures rather than
-- literal source objects. Tiny handheld objects get a readable battle scale,
-- fauna stays close to real anatomy, and obviously transformed monsters may
-- exaggerate mass. Render metrics come from the current private Idle sheets.

update public.animas as anima
set body_height_cm = calibration.body_height_cm,
    manifest = jsonb_set(
      coalesce(anima.manifest, '{}'::jsonb),
      '{render_metrics}',
      jsonb_build_object(
        'reference_width_px', calibration.reference_width_px,
        'reference_height_px', calibration.reference_height_px
      ),
      true
    )
from (
  values
    ('a20bb2f0-e063-4b7c-8bab-bfaf261400b8'::uuid,  90, 362, 401), -- Mugshots: mug-sized source, compact brawler
    ('19949c2e-5d3d-41f6-9b02-4f0740b1cace'::uuid, 180, 438, 517), -- Hydron: gallon bottle transformed into a heavy guardian
    ('594fe414-e404-4db5-82d7-d6f1c7fee1a5'::uuid,  95, 441, 328), -- Deckon: handheld source, low quadruped
    ('99b04a1c-07be-4753-be04-ae68183817e6'::uuid, 100, 225, 266), -- Playtron: 13 cm source enlarged to a readable companion
    ('c80ddef5-533d-4f36-9f26-7f449981e996'::uuid, 175, 274, 327), -- Veridian: large indoor Monstera, exaggerated but not kaiju-sized
    ('1b5a7be0-55a2-45a9-889e-1ae5bf8f0c77'::uuid,  90, 233, 305), -- klasik: handheld source enlarged to a floating companion
    ('2168d17e-440d-4ba3-9004-5104800c6722'::uuid,  75, 320, 333)  -- Sunhound: retriever crown height kept near real anatomy
) as calibration(id, body_height_cm, reference_width_px, reference_height_px)
where anima.id = calibration.id;
