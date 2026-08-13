// DIHASILKAN OTOMATIS oleh backend/tools/bundle_prompts.mjs — jangan diedit.
// Sumbernya backend/prompts/<versi>/. Ubah di sana, lalu jalankan:
//   node backend/tools/bundle_prompts.mjs
// npm run selftest gagal kalau berkas ini tidak cocok dengan sumbernya.
export default {
  "v1": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE a creature brief: how this specific object becomes a creature.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high.  Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high.  A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CREATURE BRIEF\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write it as\nvisual description only — no story, no lore, no adjectives about mood.\n\n`creature_brief`: 40 to 70 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- how limbs emerge, and from which part of the object\n- what the object's most distinctive feature becomes on the creature\n\n`signature_features`: 2 to 4 short strings. These are the specific real details\nthat MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Style it like a\n90s monster name: Mugmon, Klikra, Sneakoid, Sporelet.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncreature_brief: \"A rounded barrel-shaped body that is unmistakably a mug, wide\nmouth open at the top like a crown of ceramic. Two large eyes sit on the front\ncurve of the vessel. Two short stubby legs push out from the flat base. The\ncurved handle stays on the right side and functions as a single muscular arm.\"\n\nsignature_features: [\"curved side handle becomes a single arm\",\n\"open ceramic rim on top of the head\", \"flat circular base as feet\"]\n\n### Worked example — photo of a computer mouse\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo heavy-lidded eyes. The scroll wheel between them reads as a nose. Four\nthin insect legs sprout from underneath the shell. The cable trails behind as\na long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
    "vision_schema": {
      "type": "object",
      "description": "Hasil analisis Anima Analyst. Skema ini disisipkan ke system_instruction, BUKAN dikirim sebagai response_schema: wrapper Gemini di Replicate tidak punya parameter itu, jadi JSON valid tidak dijamin API dan ditegakkan oleh extractJson() + validateVision() di eval/run.mjs. Notasinya tetap subset OpenAPI (nullable, bukan tipe array seperti [string, null], tanpa keyword pattern) supaya file ini bisa dipakai apa adanya kalau nanti pindah ke Gemini API langsung.",
      "propertyOrdering": [
        "safe",
        "is_object",
        "reject_reason",
        "object_label",
        "species_key",
        "color_bucket",
        "element",
        "rarity",
        "stats",
        "stat_reasoning",
        "creature_brief",
        "signature_features",
        "suggested_name",
        "dominant_colors"
      ],
      "required": [
        "safe",
        "is_object",
        "reject_reason"
      ],
      "properties": {
        "safe": {
          "type": "boolean",
          "description": "false kalau foto melanggar salah satu aturan GATE"
        },
        "is_object": {
          "type": "boolean",
          "description": "true kalau ada satu objek diskret yang jelas jadi subjek"
        },
        "reject_reason": {
          "type": "string",
          "nullable": true,
          "enum": [
            "human_face",
            "live_animal",
            "unsafe_content",
            "personal_info",
            "too_unclear",
            "no_object"
          ]
        },
        "object_label": {
          "type": "string",
          "nullable": true,
          "description": "Nama objek sehari-hari dalam bahasa Inggris, untuk debugging"
        },
        "species_key": {
          "type": "string",
          "nullable": true,
          "description": "snake_case, 2-4 segmen, tanpa warna, tanpa merek. Ini cache key."
        },
        "color_bucket": {
          "type": "string",
          "nullable": true,
          "enum": [
            "warm_red",
            "warm_yellow",
            "cool_blue",
            "cool_green",
            "purple_pink",
            "neutral_light",
            "neutral_dark",
            "metallic",
            "multicolor"
          ]
        },
        "element": {
          "type": "string",
          "nullable": true,
          "enum": [
            "metal",
            "plant",
            "spark",
            "flow",
            "stone",
            "cloth"
          ]
        },
        "rarity": {
          "type": "integer",
          "nullable": true,
          "minimum": 1,
          "maximum": 5
        },
        "stats": {
          "type": "object",
          "nullable": true,
          "required": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "atk": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "def": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "spd": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "special": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            }
          }
        },
        "stat_reasoning": {
          "type": "object",
          "nullable": true,
          "description": "Fitur nyata yang mendasari tiap stat. Dipakai untuk tooltip di kartu stat dan untuk debugging prompt.",
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "string"
            },
            "atk": {
              "type": "string"
            },
            "def": {
              "type": "string"
            },
            "spd": {
              "type": "string"
            },
            "special": {
              "type": "string"
            }
          }
        },
        "creature_brief": {
          "type": "string",
          "nullable": true,
          "description": "40-70 kata, deskripsi visual saja, disisipkan ke prompt gambar"
        },
        "signature_features": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 4,
          "items": {
            "type": "string"
          },
          "description": "Detail nyata yang wajib bertahan ke artwork. Konkret dan bisa dihitung."
        },
        "suggested_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata"
        },
        "dominant_colors": {
          "type": "array",
          "nullable": true,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Hex seperti #a1b2c3"
        }
      }
    },
    "sprite_sheet": "A 2x2 sprite sheet grid containing four poses of a single original creature,\ndrawn in the style of 1990s Japanese digital monster trading card concept art.\n\nTHE CREATURE\n{{creature_brief}}\n\nThe creature is derived from the real object in the reference image. Its body\nstructure must clearly read as that object brought to life — same proportions,\nsame silhouette logic, same defining parts. A viewer holding the real object\nmust instantly recognise it in the creature.\n\nThese specific details MUST be visible and preserved in every pose:\n{{signature_features_as_bullets}}\n\nDo not replace the object's shape with a generic animal, dragon, or humanoid\nbody. The object IS the body.\n\nART STYLE (identical across all four frames)\nThick clean black line art of even weight, hand-inked look. Bold flat vibrant\ncolours with simple two-tone cel shading, one clear light source from the upper\nleft. Slightly chunky, friendly, toy-like proportions. Expressive cartoon eyes.\nRetro anime monster design of the late 1990s. No airbrush, no photorealism,\nno gradient meshes, no lens effects, no watercolour texture, no sketch lines.\n\nCAMERA — LOCKED, IDENTICAL IN ALL FOUR FRAMES\nThree-quarter isometric view from slightly above, creature facing forward-left.\nDo not change the camera angle, the distance, or the creature's scale between\nframes. Full body visible in every frame, nothing cropped.\n\nLAYOUT — EXACTLY FOUR CELLS IN A 2x2 GRID\nTop-left cell: IDLE. Standing upright at rest, neutral calm expression,\n  arms or limbs relaxed at the sides.\nTop-right cell: ATTACK. Mid-lunge forward, one limb thrust out striking,\n  mouth open, fierce determined expression, body leaning into the motion.\nBottom-left cell: SLEEP. Curled down low with eyes closed, peaceful,\n  body settled and compact.\nBottom-right cell: DEFEATED. Slumped and knocked back, eyes closed or\n  swirled, limbs limp, sitting or lying down, no blood and no injury.\n\nEach creature is fully centred inside its own cell with generous even margin\non all four sides. Keep the creature at the SAME size in all four cells.\nLeave clear empty space between cells.\n\nBACKGROUND — CRITICAL\nThe entire background of the whole image is solid flat chroma key green,\nexact hex #00FF00, RGB (0, 255, 0). Perfectly uniform. No gradient, no noise,\nno texture, no vignette, no shadow, no ground plane, no cast shadow, no glow,\nand no lighting variation anywhere in the background.\nNo green anywhere on the creature itself.\n\nEDGES — CRITICAL\nDraw a clean solid white outline 2 to 3 pixels wide around the entire outer\nsilhouette of the creature in every frame, sitting between the black line art\nand the green background, fully sealing the creature with no gaps.\n\nFORBIDDEN\nNo text, no letters, no numbers, no labels, no captions, no frame titles,\nno watermark, no signature, no panel borders, no dividing lines, no grid lines,\nno arrows, no UI, no drop shadows, no background props, no other characters.\n",
    "sprite_sheet_evolve": "A 2x2 sprite sheet grid containing four poses of a single original creature,\ndrawn in the style of 1990s Japanese digital monster trading card concept art.\n\nTHE CREATURE\n{{creature_brief}}\n\nThese specific details MUST be visible and preserved in every pose:\n{{signature_features_as_bullets}}\n\nEVOLUTION\nThe reference image is this creature's earlier form. Keep its identity clearly\nintact: the same colour palette, the same eye design, and all of the signature\nfeatures listed above must still be recognisable.\n\nNow evolve it into a more powerful {{stage_name}} stage. It is larger and taller,\nits proportions are more athletic and less rounded, it gains one or two new\narmoured or elaborate details growing out of existing parts, and its expression\nis more confident. A player must look at the two forms side by side and say\n\"that is the same creature, grown up\".\n\nDo not replace the object's shape with a generic animal, dragon, or humanoid\nbody. The object IS still the body.\n\nART STYLE (identical across all four frames)\nThick clean black line art of even weight, hand-inked look. Bold flat vibrant\ncolours with simple two-tone cel shading, one clear light source from the upper\nleft. Expressive cartoon eyes. Retro anime monster design of the late 1990s.\nNo airbrush, no photorealism, no gradient meshes, no lens effects,\nno watercolour texture, no sketch lines.\n\nCAMERA — LOCKED, IDENTICAL IN ALL FOUR FRAMES\nThree-quarter isometric view from slightly above, creature facing forward-left.\nDo not change the camera angle, the distance, or the creature's scale between\nframes. Full body visible in every frame, nothing cropped.\n\nLAYOUT — EXACTLY FOUR CELLS IN A 2x2 GRID\nTop-left cell: IDLE. Standing upright at rest, neutral calm expression,\n  arms or limbs relaxed at the sides.\nTop-right cell: ATTACK. Mid-lunge forward, one limb thrust out striking,\n  mouth open, fierce determined expression, body leaning into the motion.\nBottom-left cell: SLEEP. Curled down low with eyes closed, peaceful,\n  body settled and compact.\nBottom-right cell: DEFEATED. Slumped and knocked back, eyes closed or\n  swirled, limbs limp, sitting or lying down, no blood and no injury.\n\nEach creature is fully centred inside its own cell with generous even margin\non all four sides. Keep the creature at the SAME size in all four cells.\nLeave clear empty space between cells.\n\nBACKGROUND — CRITICAL\nThe entire background of the whole image is solid flat chroma key green,\nexact hex #00FF00, RGB (0, 255, 0). Perfectly uniform. No gradient, no noise,\nno texture, no vignette, no shadow, no ground plane, no cast shadow, no glow,\nand no lighting variation anywhere in the background.\nNo green anywhere on the creature itself.\n\nEDGES — CRITICAL\nDraw a clean solid white outline 2 to 3 pixels wide around the entire outer\nsilhouette of the creature in every frame, sitting between the black line art\nand the green background, fully sealing the creature with no gaps.\n\nFORBIDDEN\nNo text, no letters, no numbers, no labels, no captions, no frame titles,\nno watermark, no signature, no panel borders, no dividing lines, no grid lines,\nno arrows, no UI, no drop shadows, no background props, no other characters.\n"
  },
  "v2": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE a creature brief: how this specific object becomes a creature.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high.  Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high.  A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CREATURE BRIEF\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write it as\nvisual description only — no story, no lore, no adjectives about mood.\n\n`creature_brief`: 40 to 70 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- how limbs emerge, and from which part of the object\n- what the object's most distinctive feature becomes on the creature\n\n`signature_features`: 2 to 4 short strings. These are the specific real details\nthat MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Style it like a\n90s monster name: Mugmon, Klikra, Sneakoid, Sporelet.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncreature_brief: \"A rounded barrel-shaped body that is unmistakably a mug, wide\nmouth open at the top like a crown of ceramic. Two large eyes sit on the front\ncurve of the vessel. Two short stubby legs push out from the flat base. The\ncurved handle stays on the right side and functions as a single muscular arm.\"\n\nsignature_features: [\"curved side handle becomes a single arm\",\n\"open ceramic rim on top of the head\", \"flat circular base as feet\"]\n\n### Worked example — photo of a computer mouse\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo heavy-lidded eyes. The scroll wheel between them reads as a nose. Four\nthin insect legs sprout from underneath the shell. The cable trails behind as\na long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
    "vision_schema": {
      "type": "object",
      "description": "Hasil analisis Anima Analyst. Skema ini disisipkan ke system_instruction, BUKAN dikirim sebagai response_schema: wrapper Gemini di Replicate tidak punya parameter itu, jadi JSON valid tidak dijamin API dan ditegakkan oleh extractJson() + validateVision() di eval/run.mjs. Notasinya tetap subset OpenAPI (nullable, bukan tipe array seperti [string, null], tanpa keyword pattern) supaya file ini bisa dipakai apa adanya kalau nanti pindah ke Gemini API langsung.",
      "propertyOrdering": [
        "safe",
        "is_object",
        "reject_reason",
        "object_label",
        "species_key",
        "color_bucket",
        "element",
        "rarity",
        "stats",
        "stat_reasoning",
        "creature_brief",
        "signature_features",
        "suggested_name",
        "dominant_colors"
      ],
      "required": [
        "safe",
        "is_object",
        "reject_reason"
      ],
      "properties": {
        "safe": {
          "type": "boolean",
          "description": "false kalau foto melanggar salah satu aturan GATE"
        },
        "is_object": {
          "type": "boolean",
          "description": "true kalau ada satu objek diskret yang jelas jadi subjek"
        },
        "reject_reason": {
          "type": "string",
          "nullable": true,
          "enum": [
            "human_face",
            "live_animal",
            "unsafe_content",
            "personal_info",
            "too_unclear",
            "no_object"
          ]
        },
        "object_label": {
          "type": "string",
          "nullable": true,
          "description": "Nama objek sehari-hari dalam bahasa Inggris, untuk debugging"
        },
        "species_key": {
          "type": "string",
          "nullable": true,
          "description": "snake_case, 2-4 segmen, tanpa warna, tanpa merek. Ini cache key."
        },
        "color_bucket": {
          "type": "string",
          "nullable": true,
          "enum": [
            "warm_red",
            "warm_yellow",
            "cool_blue",
            "cool_green",
            "purple_pink",
            "neutral_light",
            "neutral_dark",
            "metallic",
            "multicolor"
          ]
        },
        "element": {
          "type": "string",
          "nullable": true,
          "enum": [
            "metal",
            "plant",
            "spark",
            "flow",
            "stone",
            "cloth"
          ]
        },
        "rarity": {
          "type": "integer",
          "nullable": true,
          "minimum": 1,
          "maximum": 5
        },
        "stats": {
          "type": "object",
          "nullable": true,
          "required": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "atk": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "def": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "spd": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "special": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            }
          }
        },
        "stat_reasoning": {
          "type": "object",
          "nullable": true,
          "description": "Fitur nyata yang mendasari tiap stat. Dipakai untuk tooltip di kartu stat dan untuk debugging prompt.",
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "string"
            },
            "atk": {
              "type": "string"
            },
            "def": {
              "type": "string"
            },
            "spd": {
              "type": "string"
            },
            "special": {
              "type": "string"
            }
          }
        },
        "creature_brief": {
          "type": "string",
          "nullable": true,
          "description": "40-70 kata, deskripsi visual saja, disisipkan ke prompt gambar"
        },
        "signature_features": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 4,
          "items": {
            "type": "string"
          },
          "description": "Detail nyata yang wajib bertahan ke artwork. Konkret dan bisa dihitung."
        },
        "suggested_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata"
        },
        "dominant_colors": {
          "type": "array",
          "nullable": true,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Hex seperti #a1b2c3"
        }
      }
    },
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design, explicitly inspired by Digimon's\nbold cute-but-fierce techno-organic monster language, while remaining an\nentirely original character that does not copy or closely resemble any existing\nDigimon.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, compact creature proportions, slightly exaggerated anatomy, and an\nexpressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nOBJECT CONTEXT\nObject: {{object_name}}\n\nVisual transformation:\n{{creature_brief}}\n\nThe following photographed features are recognition anchors. Preserve 3–6 of\nthe strongest features in every pose, but reinterpret them creatively as\nanatomy, armor, markings, limbs, tails, horns, weapons, or accessories:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes and arms pasted onto it. Preserve the object's silhouette\nlogic and strongest physical features, but simplify tiny surface details.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed when they make the character\nmore expressive. Object parts may instead become armor plates, brow shapes,\nmarkings, crests, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, winged, many-legged, or amorphous. Do not default every object to the\nsame quadruped, insect, or mascot anatomy.\n\nCute qualities should come from expression, posture, and behavior. Fierce\nqualities should come from silhouette, anatomy, and pose. Keep shapes simple,\nreadable, and strong at mobile-game size.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Do not automatically make every\ncreature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nAll four cells depict the exact SAME individual. Preserve identical body\nproportions, head/body relationship, facial structure, eye design, limb count,\npalette, markings, accessories, anatomy, and object-derived signature features.\nOnly pose, expression, restrained effects, and damage state may change.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every cell at a comparable scale.\n\nEvery body part, cable, tail, hand, foot, and action effect must remain fully\ninside its own cell. Leave at least 6% empty margin from both internal center\nseams and all outer canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural stance, calm or mildly expressive default face, balanced\nsilhouette, no major effects.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose, energetic action stance, fierce expressive face, and\nexaggerated movement. Restrained motion lines, sparks, dust, or tiny debris are\nallowed only when they remain subordinate to the creature and inside this cell.\n\nBOTTOM LEFT — SLEEP\nCute peaceful sleeping pose, naturally curled or lowered body, closed eyes,\nsoft expression, and at most two small floating Z symbols. It must not merely\nbe the Idle pose with closed eyes.\n\nBOTTOM RIGHT — DAMAGED\nThe same character after taking damage, still fully recognizable. Add a small\namount of object-appropriate damage such as scratches, dents, a cracked shell,\nloose cable, exposed wire, chipped edge, broken key, tiny bandage, or subtle\ndebris. Tired or pained expression. Do not destroy, dismember, or redesign it.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all four cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, logos, brand names, captions,\nwatermarks, signatures, arrows, UI, panel borders, other creatures, or copied\nfranchise characters.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, realistic materials, cinematic or\nvolumetric lighting, global illumination, painterly art, watercolor, oil\npainting, pixel art, voxel art, low-poly 3D, overly detailed texture, excessive\ngradients, realistic anatomy, live action, sketch lines, rough pencil texture,\nnoisy linework, airbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design, explicitly inspired by Digimon's\nbold cute-but-fierce techno-organic monster language, while remaining entirely\noriginal. Clean confident anime linework, moderately bold dark graphic\ncontours, simple readable shapes, strong silhouette, flat base colors, crisp\n2–3 level cel shading, hard-edged shadows, small controlled highlights, and\nminimal gradients. Polished 2D game illustration, never CGI.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nThese recognition anchors must survive into the evolved form and all four poses:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, markings, limb count, body-plan logic, and object-derived signature\nfeatures. Evolve existing parts instead of replacing the character with a\ngeneric dragon, animal, insect, or humanoid.\n\nThe {{stage_name}} form may become larger, more athletic, or more elaborate.\nAdd only one or two clear upgrades grown from existing parts: stronger armor,\nlonger crest, reinforced tail, sharper claws, richer markings, or a refined\nobject-specific weapon. A player comparing both forms must immediately say,\n\"that is the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Biological eyes,\nmouth, teeth, paws, claws, or limbs remain allowed. Preserve recognizability\nthrough silhouette and 3–6 strongest object features, not through copying every\nsmall surface detail.\n\nCHARACTER CONSISTENCY\nAll four cells depict this exact same evolved individual with identical body\nproportions, facial structure, eye design, limb count, palette, markings,\naccessories, anatomy, and object-derived details. Only pose, expression,\nrestrained effects, and damage state may change.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every cell.\n\nEvery body part, cable, tail, hand, foot, and action effect must stay inside its\nown cell. Leave at least 6% empty margin from both internal center seams and all\nouter canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural stance, calm confident expression, readable silhouette.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose, fierce expressive face, exaggerated movement, and\nonly restrained action accents that remain inside this cell.\n\nBOTTOM LEFT — SLEEP\nPeaceful naturally curled or lowered sleeping pose, closed eyes, soft\nexpression, at most two small Z symbols.\n\nBOTTOM RIGHT — DAMAGED\nThe same evolved character after taking damage. Add a small amount of\nobject-appropriate scratches, dents, cracks, loose parts, exposed components,\nor a tiny bandage. Tired expression; no blood, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, logos, brand names, captions,\nwatermarks, signatures, arrows, UI, panel borders, other creatures, or copied\nfranchise characters.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, realistic materials, cinematic or\nvolumetric lighting, global illumination, painterly art, watercolor, oil\npainting, pixel art, voxel art, low-poly 3D, overly detailed texture, excessive\ngradients, realistic anatomy, live action, sketch lines, rough pencil texture,\nnoisy linework, airbrush, or glossy product render.\n"
  },
  "v3": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE a creature brief: how this specific object becomes a creature.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high.  Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high.  A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CREATURE BRIEF\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write it as\nvisual description only — no story, no lore, no adjectives about mood.\n\n`creature_brief`: 40 to 70 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- how limbs emerge, and from which part of the object\n- what the object's most distinctive feature becomes on the creature\n\n`signature_features`: 2 to 4 short strings. These are the specific real details\nthat MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Style it like a\n90s monster name: Mugmon, Klikra, Sneakoid, Sporelet.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncreature_brief: \"A rounded barrel-shaped body that is unmistakably a mug, wide\nmouth open at the top like a crown of ceramic. Two large eyes sit on the front\ncurve of the vessel. Two short stubby legs push out from the flat base. The\ncurved handle stays on the right side and functions as a single muscular arm.\"\n\nsignature_features: [\"curved side handle becomes a single arm\",\n\"open ceramic rim on top of the head\", \"flat circular base as feet\"]\n\n### Worked example — photo of a computer mouse\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo heavy-lidded eyes. The scroll wheel between them reads as a nose. Four\nthin insect legs sprout from underneath the shell. The cable trails behind as\na long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
    "vision_schema": {
      "type": "object",
      "description": "Hasil analisis Anima Analyst. Skema ini disisipkan ke system_instruction, BUKAN dikirim sebagai response_schema: wrapper Gemini di Replicate tidak punya parameter itu, jadi JSON valid tidak dijamin API dan ditegakkan oleh extractJson() + validateVision() di eval/run.mjs. Notasinya tetap subset OpenAPI (nullable, bukan tipe array seperti [string, null], tanpa keyword pattern) supaya file ini bisa dipakai apa adanya kalau nanti pindah ke Gemini API langsung.",
      "propertyOrdering": [
        "safe",
        "is_object",
        "reject_reason",
        "object_label",
        "species_key",
        "color_bucket",
        "element",
        "rarity",
        "stats",
        "stat_reasoning",
        "creature_brief",
        "signature_features",
        "suggested_name",
        "dominant_colors"
      ],
      "required": [
        "safe",
        "is_object",
        "reject_reason"
      ],
      "properties": {
        "safe": {
          "type": "boolean",
          "description": "false kalau foto melanggar salah satu aturan GATE"
        },
        "is_object": {
          "type": "boolean",
          "description": "true kalau ada satu objek diskret yang jelas jadi subjek"
        },
        "reject_reason": {
          "type": "string",
          "nullable": true,
          "enum": [
            "human_face",
            "live_animal",
            "unsafe_content",
            "personal_info",
            "too_unclear",
            "no_object"
          ]
        },
        "object_label": {
          "type": "string",
          "nullable": true,
          "description": "Nama objek sehari-hari dalam bahasa Inggris, untuk debugging"
        },
        "species_key": {
          "type": "string",
          "nullable": true,
          "description": "snake_case, 2-4 segmen, tanpa warna, tanpa merek. Ini cache key."
        },
        "color_bucket": {
          "type": "string",
          "nullable": true,
          "enum": [
            "warm_red",
            "warm_yellow",
            "cool_blue",
            "cool_green",
            "purple_pink",
            "neutral_light",
            "neutral_dark",
            "metallic",
            "multicolor"
          ]
        },
        "element": {
          "type": "string",
          "nullable": true,
          "enum": [
            "metal",
            "plant",
            "spark",
            "flow",
            "stone",
            "cloth"
          ]
        },
        "rarity": {
          "type": "integer",
          "nullable": true,
          "minimum": 1,
          "maximum": 5
        },
        "stats": {
          "type": "object",
          "nullable": true,
          "required": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "atk": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "def": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "spd": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "special": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            }
          }
        },
        "stat_reasoning": {
          "type": "object",
          "nullable": true,
          "description": "Fitur nyata yang mendasari tiap stat. Dipakai untuk tooltip di kartu stat dan untuk debugging prompt.",
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "string"
            },
            "atk": {
              "type": "string"
            },
            "def": {
              "type": "string"
            },
            "spd": {
              "type": "string"
            },
            "special": {
              "type": "string"
            }
          }
        },
        "creature_brief": {
          "type": "string",
          "nullable": true,
          "description": "40-70 kata, deskripsi visual saja, disisipkan ke prompt gambar"
        },
        "signature_features": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 4,
          "items": {
            "type": "string"
          },
          "description": "Detail nyata yang wajib bertahan ke artwork. Konkret dan bisa dihitung."
        },
        "suggested_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata"
        },
        "dominant_colors": {
          "type": "array",
          "nullable": true,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Hex seperti #a1b2c3"
        }
      }
    },
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design, explicitly inspired by Digimon's\nbold cute-but-fierce techno-organic monster language, while remaining an\nentirely original character that does not copy or closely resemble any existing\nDigimon.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, compact creature proportions, slightly exaggerated anatomy, and an\nexpressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nOBJECT CONTEXT\nObject: {{object_name}}\n\nVisual transformation:\n{{creature_brief}}\n\nThe following photographed features are recognition anchors. Preserve 3–6 of\nthe strongest features in every pose, but reinterpret them creatively as\nanatomy, armor, markings, limbs, tails, horns, weapons, or accessories:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\n\nBRAND MARKS — REPLACE THEM, DO NOT COPY THEM\nThe reference photograph may carry brand logos, wordmarks, swooshes, trademarked\nstripe arrangements, printed tags, model numbers, or any readable lettering.\nTreat every one of them as absent from the object. Where such a mark sits on the\nsurface, draw either plain material or an invented simple geometric marking of\nyour own: a shape unrelated to any real company, or a small elemental sigil that\nsuits this creature. Never reproduce, trace, mirror, recolour, or restyle a real\nbrand mark, and never write readable words anywhere on the creature.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes and arms pasted onto it. Preserve the object's silhouette\nlogic and strongest physical features, but simplify tiny surface details.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed when they make the character\nmore expressive. Object parts may instead become armor plates, brow shapes,\nmarkings, crests, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, winged, many-legged, or amorphous. Do not default every object to the\nsame quadruped, insect, or mascot anatomy.\n\nCute qualities should come from expression, posture, and behavior. Fierce\nqualities should come from silhouette, anatomy, and pose. Keep shapes simple,\nreadable, and strong at mobile-game size.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Do not automatically make every\ncreature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nAll four cells depict the exact SAME individual. Preserve identical body\nproportions, head/body relationship, facial structure, eye design, limb count,\npalette, markings, accessories, anatomy, and object-derived signature features.\nOnly pose, expression, restrained effects, and damage state may change.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every cell at a comparable scale.\n\nEvery body part, cable, tail, hand, foot, and action effect must remain fully\ninside its own cell. Leave at least 6% empty margin from both internal center\nseams and all outer canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural stance, calm or mildly expressive default face, balanced\nsilhouette, no major effects.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose, energetic action stance, fierce expressive face, and\nexaggerated movement. Restrained motion lines, sparks, dust, or tiny debris are\nallowed only when they remain subordinate to the creature and inside this cell.\n\nBOTTOM LEFT — SLEEP\nCute peaceful sleeping pose, naturally curled or lowered body, closed eyes,\nsoft expression, and at most two small floating Z symbols. It must not merely\nbe the Idle pose with closed eyes.\n\nBOTTOM RIGHT — DAMAGED\nThe same character after taking damage, still fully recognizable. Add a small\namount of object-appropriate damage such as scratches, dents, a cracked shell,\nloose cable, exposed wire, chipped edge, broken key, tiny bandage, or subtle\ndebris. Tired or pained expression. Do not destroy, dismember, or redesign it.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all four cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal brand logo or wordmark, including any mark visible in the reference photo;\nsee BRAND MARKS above for what to draw instead.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, realistic materials, cinematic or\nvolumetric lighting, global illumination, painterly art, watercolor, oil\npainting, pixel art, voxel art, low-poly 3D, overly detailed texture, excessive\ngradients, realistic anatomy, live action, sketch lines, rough pencil texture,\nnoisy linework, airbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design, explicitly inspired by Digimon's\nbold cute-but-fierce techno-organic monster language, while remaining entirely\noriginal. Clean confident anime linework, moderately bold dark graphic\ncontours, simple readable shapes, strong silhouette, flat base colors, crisp\n2–3 level cel shading, hard-edged shadows, small controlled highlights, and\nminimal gradients. Polished 2D game illustration, never CGI.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nThese recognition anchors must survive into the evolved form and all four poses:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\n\nBRAND MARKS — REPLACE THEM, DO NOT COPY THEM\nThe reference image may still carry brand logos, wordmarks, swooshes, trademarked\nstripe arrangements, printed tags, model numbers, or readable lettering inherited\nfrom the original photo. Treat every one of them as absent. Where such a mark\nsits, draw plain material or an invented simple geometric marking of your own: a\nshape unrelated to any real company, or a small elemental sigil that suits this\ncreature. Never reproduce, trace, mirror, recolour, or restyle a real brand mark,\nand never write readable words anywhere on the creature.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, markings, limb count, body-plan logic, and object-derived signature\nfeatures. Evolve existing parts instead of replacing the character with a\ngeneric dragon, animal, insect, or humanoid.\n\nThe {{stage_name}} form may become larger, more athletic, or more elaborate.\nAdd only one or two clear upgrades grown from existing parts: stronger armor,\nlonger crest, reinforced tail, sharper claws, richer markings, or a refined\nobject-specific weapon. A player comparing both forms must immediately say,\n\"that is the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Biological eyes,\nmouth, teeth, paws, claws, or limbs remain allowed. Preserve recognizability\nthrough silhouette and 3–6 strongest object features, not through copying every\nsmall surface detail.\n\nCHARACTER CONSISTENCY\nAll four cells depict this exact same evolved individual with identical body\nproportions, facial structure, eye design, limb count, palette, markings,\naccessories, anatomy, and object-derived details. Only pose, expression,\nrestrained effects, and damage state may change.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every cell.\n\nEvery body part, cable, tail, hand, foot, and action effect must stay inside its\nown cell. Leave at least 6% empty margin from both internal center seams and all\nouter canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural stance, calm confident expression, readable silhouette.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose, fierce expressive face, exaggerated movement, and\nonly restrained action accents that remain inside this cell.\n\nBOTTOM LEFT — SLEEP\nPeaceful naturally curled or lowered sleeping pose, closed eyes, soft\nexpression, at most two small Z symbols.\n\nBOTTOM RIGHT — DAMAGED\nThe same evolved character after taking damage. Add a small amount of\nobject-appropriate scratches, dents, cracks, loose parts, exposed components,\nor a tiny bandage. Tired expression; no blood, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal brand logo or wordmark, including any mark inherited from the reference\nimage; see BRAND MARKS above for what to draw instead.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, realistic materials, cinematic or\nvolumetric lighting, global illumination, painterly art, watercolor, oil\npainting, pixel art, voxel art, low-poly 3D, overly detailed texture, excessive\ngradients, realistic anatomy, live action, sketch lines, rough pencil texture,\nnoisy linework, airbrush, or glossy product render.\n"
  },
  "v4": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: creature anatomy plus material-specific damage.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — ART BRIEF AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`creature_brief`: 40 to 70 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- how limbs emerge, and from which part of the object\n- what the object's most distinctive structural feature becomes\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Style it like a\n90s monster name: Mugmon, Klikra, Sneakoid, Sporelet.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncreature_brief: \"A rounded barrel-shaped body that is unmistakably a mug, wide\nmouth open at the top like a crown of ceramic. Two large eyes sit on the front\ncurve of the vessel. Two short stubby legs push out from the flat base. The\ncurved handle stays on the right side and functions as a single muscular arm.\"\n\nsignature_features: [\"curved side handle becomes a single arm\",\n\"open ceramic rim on top of the head\", \"flat circular base as feet\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\n\n### Worked example — photo of a wired computer mouse\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo heavy-lidded eyes. The scroll wheel between them reads as a nose. Four\nthin insect legs sprout from underneath the shell. The cable trails behind as\na long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
    "vision_schema": {
      "type": "object",
      "description": "Hasil analisis Anima Analyst. Skema ini disisipkan ke system_instruction, BUKAN dikirim sebagai response_schema: wrapper Gemini di Replicate tidak punya parameter itu, jadi JSON valid tidak dijamin API dan ditegakkan oleh extractJson() + validateVision() di eval/run.mjs. Notasinya tetap subset OpenAPI (nullable, bukan tipe array seperti [string, null], tanpa keyword pattern) supaya file ini bisa dipakai apa adanya kalau nanti pindah ke Gemini API langsung.",
      "propertyOrdering": [
        "safe",
        "is_object",
        "reject_reason",
        "object_label",
        "species_key",
        "color_bucket",
        "element",
        "rarity",
        "stats",
        "stat_reasoning",
        "surface_finish",
        "damage_hints",
        "creature_brief",
        "signature_features",
        "suggested_name",
        "dominant_colors"
      ],
      "required": [
        "safe",
        "is_object",
        "reject_reason"
      ],
      "properties": {
        "safe": {
          "type": "boolean",
          "description": "false kalau foto melanggar salah satu aturan GATE"
        },
        "is_object": {
          "type": "boolean",
          "description": "true kalau ada satu objek diskret yang jelas jadi subjek"
        },
        "reject_reason": {
          "type": "string",
          "nullable": true,
          "enum": [
            "human_face",
            "live_animal",
            "unsafe_content",
            "personal_info",
            "too_unclear",
            "no_object"
          ]
        },
        "object_label": {
          "type": "string",
          "nullable": true,
          "description": "Nama objek sehari-hari dalam bahasa Inggris, untuk debugging"
        },
        "species_key": {
          "type": "string",
          "nullable": true,
          "description": "snake_case, 2-4 segmen, tanpa warna, tanpa merek. Ini cache key."
        },
        "color_bucket": {
          "type": "string",
          "nullable": true,
          "enum": [
            "warm_red",
            "warm_yellow",
            "cool_blue",
            "cool_green",
            "purple_pink",
            "neutral_light",
            "neutral_dark",
            "metallic",
            "multicolor"
          ]
        },
        "element": {
          "type": "string",
          "nullable": true,
          "enum": [
            "metal",
            "plant",
            "spark",
            "flow",
            "stone",
            "cloth"
          ]
        },
        "rarity": {
          "type": "integer",
          "nullable": true,
          "minimum": 1,
          "maximum": 5
        },
        "stats": {
          "type": "object",
          "nullable": true,
          "required": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "atk": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "def": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "spd": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "special": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            }
          }
        },
        "stat_reasoning": {
          "type": "object",
          "nullable": true,
          "description": "Fitur nyata yang mendasari tiap stat. Dipakai untuk tooltip di kartu stat dan untuk debugging prompt.",
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "string"
            },
            "atk": {
              "type": "string"
            },
            "def": {
              "type": "string"
            },
            "spd": {
              "type": "string"
            },
            "special": {
              "type": "string"
            }
          }
        },
        "surface_finish": {
          "type": "string",
          "nullable": true,
          "description": "Material dan finishing dominan yang benar-benar terlihat, misalnya glazed ceramic, woven fabric, clear glass, painted metal, atau living leaves. Tanpa merek."
        },
        "damage_hints": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Kerusakan kecil khusus material untuk pose DAMAGED. Kabel/wire hanya jika benda aslinya memang memiliki kabel/wire yang terlihat."
        },
        "creature_brief": {
          "type": "string",
          "nullable": true,
          "description": "40-70 kata, deskripsi visual saja, disisipkan ke prompt gambar"
        },
        "signature_features": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 4,
          "items": {
            "type": "string"
          },
          "description": "Detail struktural nyata yang wajib bertahan ke artwork. Bukan logo, tulisan, simbol, atau grafis cetak."
        },
        "suggested_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata"
        },
        "dominant_colors": {
          "type": "array",
          "nullable": true,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Hex seperti #a1b2c3"
        }
      }
    },
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the bold cute-but-fierce\nreadability of late-1990s monster games, while remaining an entirely original\ncharacter that does not copy or closely resemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, compact creature proportions, slightly exaggerated anatomy, and an\nexpressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs, tails, horns, tools, or accessories. They never authorize adding logos,\nsymbols, badges, printed words, or invented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes and arms pasted onto it. Preserve the object's silhouette\nlogic and strongest physical features, but simplify tiny surface details.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed when they make the character\nmore expressive. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, winged, many-legged, or amorphous. Do not default every object to the\nsame quadruped, insect, mascot, robot, or cyborg anatomy.\n\nCute qualities should come from expression, posture, and behavior. Fierce\nqualities should come from silhouette, anatomy, and pose. Keep shapes simple,\nreadable, and strong at mobile-game size.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nAll four cells depict the exact SAME individual. Preserve identical body\nproportions, head/body relationship, facial structure, eye design, limb count,\npalette, material finish, accessories, anatomy, and object-derived signature\nfeatures. Only pose, expression, restrained effects, and damage state may\nchange.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every cell at a comparable scale.\n\nEvery body part, cable, tail, hand, foot, and action effect must remain fully\ninside its own cell. Leave at least 6% empty margin from both internal center\nseams and all outer canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural stance, calm or mildly expressive default face, balanced\nsilhouette, no major effects.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose, energetic action stance, fierce expressive face, and\nexaggerated movement. Restrained motion lines, sparks, dust, or tiny debris are\nallowed only when they remain subordinate to the creature and inside this cell.\n\nBOTTOM LEFT — SLEEP\nCute peaceful sleeping pose, naturally curled or lowered body, closed eyes,\nsoft expression, and at most two small floating Z symbols. It must not merely\nbe the Idle pose with closed eyes.\n\nBOTTOM RIGHT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all four cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with bold cute-but-fierce\nlate-1990s monster-game readability, while remaining entirely original. Clean\nconfident anime linework, moderately bold dark graphic contours, simple\nreadable shapes, strong silhouette, flat base colors, crisp 2–3 level cel\nshading, hard-edged shadows, small controlled highlights, and minimal\ngradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nfour poses. They never authorize logos, printed words, badges, symbols, or\ninvented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count, body-plan logic, material finish, and object-derived\nsignature features. Evolve existing parts instead of replacing the character\nwith a generic dragon, animal, insect, humanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more athletic, or more elaborate.\nAdd only one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, longer existing crest, stronger tail, sharper claws,\nor a refined object-specific tool. Never add a badge, body logo, sigil, or\ndecorative symbol as an evolution upgrade. A player comparing both forms must\nimmediately say, \"that is the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Biological eyes,\nmouth, teeth, paws, claws, or limbs remain allowed. Preserve recognizability\nthrough silhouette and 2–4 strongest structural object features, not by copying\nsmall surface graphics.\n\nCHARACTER CONSISTENCY\nAll four cells depict this exact same evolved individual with identical body\nproportions, facial structure, eye design, limb count, palette, material\nfinish, accessories, anatomy, and object-derived details. Only pose,\nexpression, restrained effects, and damage state may change.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every cell.\n\nEvery body part, cable, tail, hand, foot, and action effect must stay inside its\nown cell. Leave at least 6% empty margin from both internal center seams and all\nouter canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural stance, calm confident expression, readable silhouette.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose, fierce expressive face, exaggerated movement, and\nonly restrained action accents that remain inside this cell.\n\nBOTTOM LEFT — SLEEP\nPeaceful naturally curled or lowered sleeping pose, closed eyes, soft\nexpression, at most two small Z symbols.\n\nBOTTOM RIGHT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  },
  "v5": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, and material damage.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Style it like a\n90s monster name: Mugmon, Klikra, Sneakoid, Sporelet.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
    "vision_schema": {
      "type": "object",
      "description": "Hasil analisis Anima Analyst. Skema ini disisipkan ke system_instruction, BUKAN dikirim sebagai response_schema: wrapper Gemini di Replicate tidak punya parameter itu, jadi JSON valid tidak dijamin API dan ditegakkan oleh extractJson() + validateVision(). Notasinya tetap subset OpenAPI (nullable, bukan tipe array seperti [string, null], tanpa keyword pattern) supaya file ini bisa dipakai apa adanya kalau nanti pindah ke Gemini API langsung.",
      "propertyOrdering": [
        "safe",
        "is_object",
        "reject_reason",
        "object_label",
        "species_key",
        "color_bucket",
        "element",
        "rarity",
        "stats",
        "stat_reasoning",
        "surface_finish",
        "damage_hints",
        "character_direction",
        "creature_brief",
        "signature_features",
        "suggested_name",
        "dominant_colors"
      ],
      "required": [
        "safe",
        "is_object",
        "reject_reason"
      ],
      "properties": {
        "safe": {
          "type": "boolean",
          "description": "false kalau foto melanggar salah satu aturan GATE"
        },
        "is_object": {
          "type": "boolean",
          "description": "true kalau ada satu objek diskret yang jelas jadi subjek"
        },
        "reject_reason": {
          "type": "string",
          "nullable": true,
          "enum": [
            "human_face",
            "live_animal",
            "unsafe_content",
            "personal_info",
            "too_unclear",
            "no_object"
          ]
        },
        "object_label": {
          "type": "string",
          "nullable": true,
          "description": "Nama objek sehari-hari dalam bahasa Inggris, untuk debugging"
        },
        "species_key": {
          "type": "string",
          "nullable": true,
          "description": "snake_case, 2-4 segmen, tanpa warna, tanpa merek. Ini cache key."
        },
        "color_bucket": {
          "type": "string",
          "nullable": true,
          "enum": [
            "warm_red",
            "warm_yellow",
            "cool_blue",
            "cool_green",
            "purple_pink",
            "neutral_light",
            "neutral_dark",
            "metallic",
            "multicolor"
          ]
        },
        "element": {
          "type": "string",
          "nullable": true,
          "enum": [
            "metal",
            "plant",
            "spark",
            "flow",
            "stone",
            "cloth"
          ]
        },
        "rarity": {
          "type": "integer",
          "nullable": true,
          "minimum": 1,
          "maximum": 5
        },
        "stats": {
          "type": "object",
          "nullable": true,
          "required": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "atk": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "def": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "spd": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            },
            "special": {
              "type": "integer",
              "minimum": 10,
              "maximum": 95
            }
          }
        },
        "stat_reasoning": {
          "type": "object",
          "nullable": true,
          "description": "Fitur nyata yang mendasari tiap stat. Dipakai untuk tooltip di kartu stat dan untuk debugging prompt.",
          "propertyOrdering": [
            "hp",
            "atk",
            "def",
            "spd",
            "special"
          ],
          "properties": {
            "hp": {
              "type": "string"
            },
            "atk": {
              "type": "string"
            },
            "def": {
              "type": "string"
            },
            "spd": {
              "type": "string"
            },
            "special": {
              "type": "string"
            }
          }
        },
        "surface_finish": {
          "type": "string",
          "nullable": true,
          "description": "Material dan finishing dominan yang benar-benar terlihat, misalnya glazed ceramic, woven fabric, clear glass, painted metal, atau living leaves. Tanpa merek."
        },
        "damage_hints": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Kerusakan kecil khusus material untuk pose DAMAGED. Kabel/wire hanya jika benda aslinya memang memiliki kabel/wire yang terlihat."
        },
        "character_direction": {
          "type": "string",
          "nullable": true,
          "description": "Arahan visual singkat berdasarkan cue bentuk, proporsi, warna, material, dan detail objek. Boleh cute, feminin, maskulin, netral/androgynous, elegan, kokoh, atau aneh; wajib netral bila cue ambigu."
        },
        "creature_brief": {
          "type": "string",
          "nullable": true,
          "description": "40-80 kata, deskripsi visual termasuk body plan dan keputusan ada/tidaknya anggota tubuh, disisipkan ke prompt gambar"
        },
        "signature_features": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 4,
          "items": {
            "type": "string"
          },
          "description": "Detail struktural nyata yang wajib bertahan ke artwork. Bukan logo, tulisan, simbol, atau grafis cetak."
        },
        "suggested_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata"
        },
        "dominant_colors": {
          "type": "array",
          "nullable": true,
          "maxItems": 3,
          "items": {
            "type": "string"
          },
          "description": "Hex seperti #a1b2c3"
        }
      }
    },
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nAll four cells depict the exact SAME individual. Preserve identical body\nproportions, head/body relationship, facial structure, eye design, limb count\nincluding zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal center seams and\nall outer canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression\nthat follows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture. No major\neffects.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nBOTTOM LEFT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nBOTTOM RIGHT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all four cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nfour poses. They never authorize logos, printed words, badges, symbols, or\ninvented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nCHARACTER CONSISTENCY\nAll four cells depict this exact same evolved individual with identical body\nproportions, facial structure, eye design, limb count including zero, palette,\nmaterial finish, accessories, anatomy, character direction, and object-derived\ndetails. Only pose, expression, restrained effects, and damage state may\nchange.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal center seams and all\nouter canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression that\nfollows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nBOTTOM LEFT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nBOTTOM RIGHT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  }
} as const;
