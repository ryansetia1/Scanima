-- Lobby Team Battle memilih tiga tier dari sumber yang BERBEDA, jadi satu
-- template aktif hanya menghasilkan satu rival dan "Find New Rivals" selalu
-- mengembalikan lawan yang sama. Dua template tambahan mengisi ujung favorable
-- dan formidable sampai Defense Team pemain mulai terpublish.
--
-- Power diukur lewat teamCombatPower() terhadap dua tim referensi: tim level 5-7
-- memberi ratio 0.788 / 0.992 / 1.194 (favorable, even, formidable) dan tim
-- level 1 memberi 0.930 / 1.171 / 1.410. Anggotanya tetap
-- system_asset = "placeholder" sehingga withSignedRoster melewati Storage.

insert into public.system_team_templates (
  slug, display_name, roster_snapshot, active
) values (
  'scrap-scavengers',
  'Scrap Scavengers',
  '[
    {
      "anima_id":"20000000-0000-4000-8000-000000000001",
      "name":"Twine Runt","species_key":"system_twine_runt","color_bucket":"brown",
      "stage":1,"level":2,"element":"cloth",
      "base_stats":{"hp":42,"atk":40,"def":34,"spd":58,"special":34},
      "hunger":100,"hygiene":100,"strike_name":"Thread Nip","surge_name":"Lint Puff",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"20000000-0000-4000-8000-000000000002",
      "name":"Chip Crumb","species_key":"system_chip_crumb","color_bucket":"amber",
      "stage":1,"level":2,"element":"food",
      "base_stats":{"hp":46,"atk":44,"def":36,"spd":46,"special":32},
      "hunger":100,"hygiene":100,"strike_name":"Crumb Fling","surge_name":"Sugar Rush",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"20000000-0000-4000-8000-000000000003",
      "name":"Cork Bobber","species_key":"system_cork_bobber","color_bucket":"tan",
      "stage":1,"level":2,"element":"wood",
      "base_stats":{"hp":50,"atk":38,"def":44,"spd":40,"special":30},
      "hunger":100,"hygiene":100,"strike_name":"Knot Bump","surge_name":"Bark Roll",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"20000000-0000-4000-8000-000000000004",
      "name":"Fizz Sprout","species_key":"system_fizz_sprout","color_bucket":"lime",
      "stage":1,"level":2,"element":"plant","secondary_element":"air",
      "base_stats":{"hp":44,"atk":36,"def":38,"spd":52,"special":42},
      "hunger":100,"hygiene":100,"strike_name":"Sprig Poke","surge_name":"Pollen Fizz",
      "system_asset":"placeholder","manifest":{}
    }
  ]'::jsonb,
  true
), (
  'vault-wardens',
  'Vault Wardens',
  '[
    {
      "anima_id":"30000000-0000-4000-8000-000000000001",
      "name":"Vault Bolt","species_key":"system_vault_bolt","color_bucket":"steel",
      "stage":1,"level":7,"element":"metal",
      "base_stats":{"hp":62,"atk":60,"def":70,"spd":40,"special":48},
      "hunger":100,"hygiene":100,"strike_name":"Bolt Slam","surge_name":"Ingot Press",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"30000000-0000-4000-8000-000000000002",
      "name":"Kiln Sentry","species_key":"system_kiln_sentry","color_bucket":"rust",
      "stage":1,"level":7,"element":"flame","secondary_element":"ceramic",
      "base_stats":{"hp":58,"atk":66,"def":52,"spd":52,"special":62},
      "hunger":100,"hygiene":100,"strike_name":"Ember Rap","surge_name":"Kiln Flare",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"30000000-0000-4000-8000-000000000003",
      "name":"Hush Prism","species_key":"system_hush_prism","color_bucket":"violet",
      "stage":1,"level":7,"element":"sound","secondary_element":"glass",
      "base_stats":{"hp":54,"atk":46,"def":54,"spd":66,"special":74},
      "hunger":100,"hygiene":100,"strike_name":"Echo Tick","surge_name":"Prism Choir",
      "system_asset":"placeholder","manifest":{}
    },
    {
      "anima_id":"30000000-0000-4000-8000-000000000004",
      "name":"Brine Bastion","species_key":"system_brine_bastion","color_bucket":"teal",
      "stage":1,"level":7,"element":"flow",
      "base_stats":{"hp":74,"atk":48,"def":68,"spd":34,"special":54},
      "hunger":100,"hygiene":100,"strike_name":"Tide Knock","surge_name":"Salt Bulwark",
      "system_asset":"placeholder","manifest":{}
    }
  ]'::jsonb,
  true
)
on conflict (slug) do nothing;
