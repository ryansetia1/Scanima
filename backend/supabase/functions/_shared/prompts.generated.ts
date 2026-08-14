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
  "v10": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, material damage, and two unique move names.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n`strike_name`: the creature's unique basic attack name. Exactly two short\nEnglish Title Case words so it fits a Battle button. Hint at the object's\nmaterial, shape, or function. No real brand, no franchise move names, and never\nend with `mon`. Good: Rim Toss, Cable Lash, Sole Stomp. This is data for the UI,\nnot text to draw on the sheet.\n\n`surge_name`: the creature's unique special attack name. Exactly two short\nEnglish Title Case words, distinct from `strike_name`, usually more charged or\nelemental. Same bans. Good: Glaze Burst, Scroll Pulse, Tread Quake. Also UI\ndata only — never painted onto the artwork.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\nstrike_name: \"Rim Toss\"\nsurge_name: \"Glaze Burst\"\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\nstrike_name: \"Click Snap\"\nsurge_name: \"Cable Lash\"\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
        "strike_name",
        "surge_name",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
        },
        "strike_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan biasa unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
        },
        "surge_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan special unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nWHITE IS NOT A GENERIC ACCENT\nIf the photographed material is not naturally white or off-white, never paint\nwhite or off-white highlights, stripes, slashes, holes, shine, or decorative\nmarks on it. Highlights must be a lighter version of that material's own hue.\nWhite is allowed only for eye sclera, teeth, the technical outer keyline, and\nreal naturally white material explicitly named in the object context.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact SAME individual. Preserve identical\nbody proportions, head/body relationship, facial structure, eye design, limb\ncount including zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change. The two effect cells contain\nONLY the attack effect — never the creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe creature must face canvas-left (the viewer's left) in the same forward-left\nthree-quarter orientation. Its face or leading front plane, nose or equivalent\nfront landmark, torso, feet or support points, and posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells; never swap left and right\nmerely to improve a pose composition. If the body plan has no face, use its\nleading edge, opening, controls, tail attachment, or strongest asymmetrical\nrecognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose must share one unambiguous source direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every character cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal seams and all\nouter canvas edges. Nothing may be cropped. No panel borders, grid lines, or\ncell labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression\nthat follows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture. No major\neffects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nTOP RIGHT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nMIDDLE LEFT — HAPPY\nThe same full-body character, pleased after being cared for. A bright open\nexpression that still follows the character direction: a smile, laugh-eyes, or\na delighted tilt. Not a battle face. No major effects.\n\nMIDDLE CENTER — HUNGRY\nThe same full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture, maybe a tiny drool or rumble mark made\nfrom the object's own material language. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same full-body character after getting messy, not after taking battle\ndamage. A few smudges, dust, crumbs, or material-faithful stains on the body,\nplus a mildly disgusted or embarrassed expression. No cracks, chips, tears, or\nother DAMAGED signs.\n\nBOTTOM LEFT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space inside or between parts of the silhouette must be an uninterrupted\npatch of exact chroma background #00FF00 matching the canvas around the creature.\nNever fill or outline negative space with white, off-white, gray, or a painted\nhighlight.\n\nFor Monstera and every other fenestrated or split leaf specifically: each\nfenestration is a literal hole through the leaf, never a white stripe or leaf\nmarking. Fill the whole fenestration with exact #00FF00 and no white border.\n\nBefore finishing, inspect every white shape inside the creature. Remove it\nunless it is an eye sclera, tooth, real naturally white material, or the outer\ntechnical keyline. White is never a substitute for a hole or generic highlight.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every OUTERMOST creature\nsilhouette, fully sealing black line art from the green background. Never draw\nthe white keyline around internal holes or negative space. Keep the outer\nkeyline consistent across all nine cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nseven character cells. They never authorize logos, printed words, badges,\nsymbols, or invented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nWHITE IS NOT A GENERIC ACCENT\nIf the photographed material is not naturally white or off-white, never paint\nwhite or off-white highlights, stripes, slashes, holes, shine, or decorative\nmarks on it. Highlights must be a lighter version of that material's own hue.\nWhite is allowed only for eye sclera, teeth, the technical outer keyline, and\nreal naturally white material explicitly named in the object context.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict this exact same evolved individual with\nidentical body proportions, facial structure, eye design, limb count including\nzero, palette, material finish, accessories, anatomy, character direction, and\nobject-derived details. Only pose, expression, restrained effects, and damage\nstate may change. The two effect cells contain ONLY the attack effect — never\nthe creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe evolved creature must face canvas-left (the viewer's left) in the same\nforward-left three-quarter orientation as its earlier form. Its face or leading\nfront plane, nose or equivalent front landmark, torso, feet or support points,\nand posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells and across evolution; never\nswap left and right merely to improve a pose composition. If the body plan has\nno face, use its leading edge, opening, controls, tail attachment, or strongest\nasymmetrical recognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose and evolution stage must share one unambiguous\nsource direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every character cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal seams and all outer\ncanvas edges. Nothing may be cropped. No panel borders, grid lines, or cell\nlabels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression that\nfollows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nTOP RIGHT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nMIDDLE LEFT — HAPPY\nThe same evolved full-body character, pleased after being cared for. A bright\nopen expression that still follows the character direction. Not a battle face.\n\nMIDDLE CENTER — HUNGRY\nThe same evolved full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same evolved full-body character after getting messy, not after taking\nbattle damage. A few smudges or material-faithful stains plus a mildly\ndisgusted or embarrassed expression. No DAMAGED cracks or chips.\n\nBOTTOM LEFT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space inside or between parts of the silhouette must be an uninterrupted\npatch of exact chroma background #00FF00 matching the canvas around the creature.\nNever fill or outline negative space with white, off-white, gray, or a painted\nhighlight.\n\nFor Monstera and every other fenestrated or split leaf specifically: each\nfenestration is a literal hole through the leaf, never a white stripe or leaf\nmarking. Fill the whole fenestration with exact #00FF00 and no white border.\n\nBefore finishing, inspect every white shape inside the creature. Remove it\nunless it is an eye sclera, tooth, real naturally white material, or the outer\ntechnical keyline. White is never a substitute for a hole or generic highlight.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every OUTERMOST creature\nsilhouette, fully sealing black line art from the green background. Never draw\nthe white keyline around internal holes or negative space. Keep the outer\nkeyline consistent across all nine cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  },
  "v11": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, material damage, and two unique move names.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n`strike_name`: the creature's unique basic attack name. Exactly two short\nEnglish Title Case words so it fits a Battle button. Hint at the object's\nmaterial, shape, or function. No real brand, no franchise move names, and never\nend with `mon`. Good: Rim Toss, Cable Lash, Sole Stomp. This is data for the UI,\nnot text to draw on the sheet.\n\n`surge_name`: the creature's unique special attack name. Exactly two short\nEnglish Title Case words, distinct from `strike_name`, usually more charged or\nelemental. Same bans. Good: Glaze Burst, Scroll Pulse, Tread Quake. Also UI\ndata only — never painted onto the artwork.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\nstrike_name: \"Rim Toss\"\nsurge_name: \"Glaze Burst\"\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\nstrike_name: \"Click Snap\"\nsurge_name: \"Cable Lash\"\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
        "strike_name",
        "surge_name",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
        },
        "strike_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan biasa unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
        },
        "surge_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan special unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nWHITE IS NOT A GENERIC ACCENT\nIf the photographed material is not naturally white or off-white, never paint\nwhite or off-white highlights, stripes, slashes, holes, shine, or decorative\nmarks on it. Highlights must be a lighter version of that material's own hue.\nWhite is allowed only for eye sclera, teeth, and real naturally white material\nexplicitly named in the object context.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact SAME individual. Preserve identical\nbody proportions, head/body relationship, facial structure, eye design, limb\ncount including zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change. The two effect cells contain\nONLY the attack effect — never the creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe creature must face canvas-left (the viewer's left) in the same forward-left\nthree-quarter orientation. Its face or leading front plane, nose or equivalent\nfront landmark, torso, feet or support points, and posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells; never swap left and right\nmerely to improve a pose composition. If the body plan has no face, use its\nleading edge, opening, controls, tail attachment, or strongest asymmetrical\nrecognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose must share one unambiguous source direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every character cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal seams and all\nouter canvas edges. Nothing may be cropped. No panel borders, grid lines, or\ncell labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression\nthat follows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture. No major\neffects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nTOP RIGHT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nMIDDLE LEFT — HAPPY\nThe same full-body character, pleased after being cared for. A bright open\nexpression that still follows the character direction: a smile, laugh-eyes, or\na delighted tilt. Not a battle face. No major effects.\n\nMIDDLE CENTER — HUNGRY\nThe same full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture, maybe a tiny drool or rumble mark made\nfrom the object's own material language. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same full-body character after getting messy, not after taking battle\ndamage. A few smudges, dust, crumbs, or material-faithful stains on the body,\nplus a mildly disgusted or embarrassed expression. No cracks, chips, tears, or\nother DAMAGED signs.\n\nBOTTOM LEFT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. Use only\na dark graphic contour at its edge. No white border, text, letters, or creature\nbody.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. Use only a dark graphic contour at its\nedge. No white border, text, letters, or creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space inside or between parts of the silhouette must be an uninterrupted\npatch of exact chroma background #00FF00 matching the canvas around the creature.\nNever fill or outline negative space with white, off-white, gray, or a painted\nhighlight.\n\nFor Monstera and every other fenestrated or split leaf specifically: each\nfenestration is a literal hole through the leaf, never a white stripe or leaf\nmarking. Fill the whole fenestration with exact #00FF00 and no white border.\n\nBefore finishing, inspect every white shape inside the creature. Remove it\nunless it is an eye sclera, tooth, or real naturally white material. White is\nnever a substitute for a hole or generic highlight.\n\nEDGES — DARK CONTOUR DIRECTLY AGAINST GREEN\nThe moderately bold dark graphic contour is the final outer edge. It must touch\nthe chroma green background directly and remain solid, clean, and continuous.\nDo NOT draw any white or off-white keyline, sticker border, halo, separator, or\noutline anywhere around or inside the creature or attack effects.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nseven character cells. They never authorize logos, printed words, badges,\nsymbols, or invented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nWHITE IS NOT A GENERIC ACCENT\nIf the photographed material is not naturally white or off-white, never paint\nwhite or off-white highlights, stripes, slashes, holes, shine, or decorative\nmarks on it. Highlights must be a lighter version of that material's own hue.\nWhite is allowed only for eye sclera, teeth, and real naturally white material\nexplicitly named in the object context.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict this exact same evolved individual with\nidentical body proportions, facial structure, eye design, limb count including\nzero, palette, material finish, accessories, anatomy, character direction, and\nobject-derived details. Only pose, expression, restrained effects, and damage\nstate may change. The two effect cells contain ONLY the attack effect — never\nthe creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe evolved creature must face canvas-left (the viewer's left) in the same\nforward-left three-quarter orientation as its earlier form. Its face or leading\nfront plane, nose or equivalent front landmark, torso, feet or support points,\nand posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells and across evolution; never\nswap left and right merely to improve a pose composition. If the body plan has\nno face, use its leading edge, opening, controls, tail attachment, or strongest\nasymmetrical recognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose and evolution stage must share one unambiguous\nsource direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every character cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal seams and all outer\ncanvas edges. Nothing may be cropped. No panel borders, grid lines, or cell\nlabels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression that\nfollows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nTOP RIGHT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nMIDDLE LEFT — HAPPY\nThe same evolved full-body character, pleased after being cared for. A bright\nopen expression that still follows the character direction. Not a battle face.\n\nMIDDLE CENTER — HUNGRY\nThe same evolved full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same evolved full-body character after getting messy, not after taking\nbattle damage. A few smudges or material-faithful stains plus a mildly\ndisgusted or embarrassed expression. No DAMAGED cracks or chips.\n\nBOTTOM LEFT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. Use only\na dark graphic contour at its edge. No white border, text, letters, or creature\nbody.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. Use only a dark graphic contour at its\nedge. No white border, text, letters, or creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space inside or between parts of the silhouette must be an uninterrupted\npatch of exact chroma background #00FF00 matching the canvas around the creature.\nNever fill or outline negative space with white, off-white, gray, or a painted\nhighlight.\n\nFor Monstera and every other fenestrated or split leaf specifically: each\nfenestration is a literal hole through the leaf, never a white stripe or leaf\nmarking. Fill the whole fenestration with exact #00FF00 and no white border.\n\nBefore finishing, inspect every white shape inside the creature. Remove it\nunless it is an eye sclera, tooth, or real naturally white material. White is\nnever a substitute for a hole or generic highlight.\n\nEDGES — DARK CONTOUR DIRECTLY AGAINST GREEN\nThe moderately bold dark graphic contour is the final outer edge. It must touch\nthe chroma green background directly and remain solid, clean, and continuous.\nDo NOT draw any white or off-white keyline, sticker border, halo, separator, or\noutline anywhere around or inside the creature or attack effects.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  },
  "v12": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, material damage, two\n   unique move names, and two materially distinct battle-effect plans.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition.\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nIf you cannot point to a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. Do not inflate: 1 and 2 should be most common.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, MATERIAL DAMAGE, AND BATTLE EFFECTS\n\nThis is the bridge from object to monster. Write visual description only — no\nstory or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If visual cues are ambiguous, choose a\nneutral or androgynous presentation.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid body plan. Floating, rolling,\nslithering, hopping as one body, rooted, winged, shelled, serpentine,\nmany-legged, and amorphous plans are all valid when they fit the object.\n\n`signature_features`: 2 to 4 short strings naming specific STRUCTURAL details\nthat must survive into the artwork. Never use a logo, wordmark, printed word,\nmodel number, badge, stripe arrangement, or decorative symbol.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nvisibly supported by the photo.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, wire, circuit, broken\nkey, or electronic component is allowed only when visibly present and named in\n`signature_features`.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, no real-world\nbrand, never ending in `mon`.\n\n`strike_name`: the unique basic attack name. Exactly two short English Title\nCase words grounded in material, shape, or function.\n\n`surge_name`: the unique special attack name. Exactly two short English Title\nCase words, distinct from `strike_name`, and usually more charged.\n\n### Battle-effect plan\n\nCreate `strike_vfx` and `surge_vfx`. Each has:\n\n- `form`: exactly one of `arc`, `beam`, `trail`, `wave`, `eruption`, `ring`,\n  `scatter`, `tether`, `stamp`, `cloud`, `shatter`, `growth`\n- `motion`: exactly one of `projectile`, `sweep`, `impact`, `bloom`\n- `brief`: one concise visual sentence grounded in a photographed structural\n  feature, the real surface material, and the move name\n\nThe two effects MUST have different `form` and different `motion`. Do not make\nSpecial a larger version of Attack.\n\nNever default to a round fireball, energy orb, comet, or generic explosion. A\nclosed ball is allowed only when the photographed object's real geometry or\nfunction is itself spherical or launches a ball. Prefer object-specific visual\nlogic:\n\n- a shoe may use a tread-shaped sweep, sole-print stamp, lace tether, or dust wave\n- a Monstera may use a leaf arc, vine growth, pollen scatter, or root eruption\n- ceramic may use a glaze ring, rim arc, liquid wave, or shard impact\n- electronics may use a scan beam, waveform trail, cable tether, or pixel scatter\n- cloth may use a ribbon sweep, thread lattice, fabric cloud, or stitched wave\n- metal may use a cutting arc, spark scatter, stamped impact, or shatter trail\n\nMotion meaning:\n\n- `projectile`: compact directional form with a readable travel tail\n- `sweep`: long crescent, ribbon, tread, or blade-like form designed to swipe\n  across the target\n- `impact`: compact contact mark, stamp, crack, slash, or shatter that appears\n  directly on the target, with no comet tail\n- `bloom`: radial, branching, cloud-like, ring-like, or erupting form that grows\n  from the target point, with no travel tail\n\n### Worked example — white ceramic mug\n\ncharacter_direction: \"soft, friendly, and visually neutral\"\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the ceramic body floats and tilts to move. The curved side\nhandle remains structural and becomes a balancing tail-fin.\"\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\nsurface_finish: \"smooth glazed white ceramic\"\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\nstrike_name: \"Rim Toss\"\nsurge_name: \"Glaze Burst\"\nstrike_vfx: {\"form\":\"arc\",\"motion\":\"sweep\",\"brief\":\"A glazed crescent shaped like\nthe mug rim sweeps across the target with two tiny ceramic glints.\"}\nsurge_vfx: {\"form\":\"ring\",\"motion\":\"bloom\",\"brief\":\"Concentric glaze rings expand\nfrom the target like ripples inside the photographed ceramic rim.\"}\n\n### Worked example — wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine\"\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The click buttons become focused eyes and the\nscroll wheel reads as a nose. Four thin insect legs sprout underneath. The cable\ntrails behind as a long segmented tail.\"\nsignature_features: [\"click buttons as the two eyes\", \"scroll wheel as a nose\",\n\"USB cable as a segmented tail\"]\nsurface_finish: \"smooth molded plastic with rubber wheel\"\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\nstrike_name: \"Click Snap\"\nsurge_name: \"Cable Lash\"\nstrike_vfx: {\"form\":\"stamp\",\"motion\":\"impact\",\"brief\":\"A sharp double-click\nimpact mark snaps directly onto the target in molded-plastic colors.\"}\nsurge_vfx: {\"form\":\"tether\",\"motion\":\"sweep\",\"brief\":\"A long cable-shaped lash\nsweeps across the target with a scroll-wheel spiral at its tip.\"}\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
    "vision_schema": {
      "type": "object",
      "description": "Hasil analisis Anima Analyst. Skema disisipkan ke system_instruction karena wrapper Gemini Replicate tidak punya response_schema; extractJson() dan validateVision() tetap menjadi pagar akhir.",
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
        "strike_name",
        "surge_name",
        "strike_vfx",
        "surge_vfx",
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
          "description": "Nama objek sehari-hari dalam bahasa Inggris"
        },
        "species_key": {
          "type": "string",
          "nullable": true,
          "description": "snake_case, 2-4 segmen, tanpa warna dan merek; cache key"
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
          "description": "Material dan finishing dominan yang benar-benar terlihat"
        },
        "damage_hints": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 3,
          "items": {
            "type": "string"
          }
        },
        "character_direction": {
          "type": "string",
          "nullable": true,
          "description": "Arahan visual berdasarkan cue bentuk, proporsi, warna, dan material"
        },
        "creature_brief": {
          "type": "string",
          "nullable": true,
          "description": "40-80 kata termasuk silhouette dan body plan"
        },
        "signature_features": {
          "type": "array",
          "nullable": true,
          "minItems": 2,
          "maxItems": 4,
          "items": {
            "type": "string"
          }
        },
        "suggested_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama kreatur rekaan, 2-4 suku kata"
        },
        "strike_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan biasa unik, tepat dua kata Inggris pendek"
        },
        "surge_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama Special unik, tepat dua kata Inggris pendek"
        },
        "strike_vfx": {
          "type": "object",
          "nullable": true,
          "required": [
            "form",
            "motion",
            "brief"
          ],
          "propertyOrdering": [
            "form",
            "motion",
            "brief"
          ],
          "properties": {
            "form": {
              "type": "string",
              "enum": [
                "arc",
                "beam",
                "trail",
                "wave",
                "eruption",
                "ring",
                "scatter",
                "tether",
                "stamp",
                "cloud",
                "shatter",
                "growth"
              ]
            },
            "motion": {
              "type": "string",
              "enum": [
                "projectile",
                "sweep",
                "impact",
                "bloom"
              ]
            },
            "brief": {
              "type": "string",
              "description": "Satu kalimat visual grounded pada struktur, material, dan nama move"
            }
          }
        },
        "surge_vfx": {
          "type": "object",
          "nullable": true,
          "required": [
            "form",
            "motion",
            "brief"
          ],
          "propertyOrdering": [
            "form",
            "motion",
            "brief"
          ],
          "properties": {
            "form": {
              "type": "string",
              "enum": [
                "arc",
                "beam",
                "trail",
                "wave",
                "eruption",
                "ring",
                "scatter",
                "tether",
                "stamp",
                "cloud",
                "shatter",
                "growth"
              ]
            },
            "motion": {
              "type": "string",
              "enum": [
                "projectile",
                "sweep",
                "impact",
                "bloom"
              ]
            },
            "brief": {
              "type": "string",
              "description": "Satu kalimat visual yang berbeda bentuk dan motion dari strike_vfx"
            }
          }
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of becoming robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nPreserve these photographed STRUCTURAL recognition anchors in every character\npose. They never authorize logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts or cybernetic anatomy unsupported by the object.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nExpress the character direction consistently through silhouette, proportions,\nface, posture, and movement. Do not default to fierce, angry, masculine, cute,\nor childlike. Do not invent bows, eyelashes, muscles, facial hair, clothing,\nsymbols, or gender-coded accessories unsupported by the object.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nTreat every brand logo, wordmark, swoosh, trademarked stripe arrangement,\nprinted tag, model number, readable letter, or emblem-like graphic in the\nreference as absent. Draw plain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny details.\n\nChoose a body plan that naturally follows this object's geometry. It may be\nbipedal, quadrupedal, serpentine, shelled, floating, rolling, rooted, winged,\nmany-legged, or amorphous. Zero arms, zero legs, or neither is fully valid.\nNever add hands merely so the creature can gesture or feet merely so it can\nstand. Do not default every object to a mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors. Accent colors follow anatomy or material boundaries and never form an\nemblem or logo-like isolated mark.\n\nWHITE IS NOT A GENERIC ACCENT\nIf the photographed material is not naturally white or off-white, never paint\nwhite or off-white highlights, stripes, slashes, holes, shine, or decorative\nmarks on it. Highlights must be a lighter version of that material's own hue.\nWhite is allowed only for eye sclera, teeth, and real naturally white material\nexplicitly named in the object context.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact SAME individual. Preserve identical\nbody proportions, facial structure, eye design, limb count including zero,\npalette, material finish, accessories, anatomy, character direction, and\nsignature features. Only pose, expression, restrained accents, and damage state\nmay change. The two effect cells contain ONLY battle effects — never a creature.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nIn EVERY character cell, the creature must face canvas-left in the same\nforward-left three-quarter orientation. Never mirror, turn around, or swap an\nasymmetrical landmark in any one cell.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents attack toward canvas-left. A `projectile` or\n`sweep` effect must also have a clear canvas-left direction. An `impact` or\n`bloom` effect is centered and may be directionless; never add a comet tail to\nmake it look like a projectile. The client mirrors the complete sheet for a\ncreature fighting from the left side.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every character cell at comparable scale.\n\nTreat every cell as an invisible sealed safe box. Keep every body part,\nappendage, cable, tail, motion line, spark, dust puff, tiny debris fragment, Z,\nand battle effect at least 12% of that cell's width and height away from every\ninternal seam. Nothing from one cell may enter or appear inside another cell.\nThe post-process rejects the entire sheet rather than guessing fragment\nownership when this safe envelope is violated.\n\nDetached accents ARE allowed and encouraged where the pose calls for them, but\nthey must remain compact, visually clustered near their own character or effect,\nand wholly inside the safe envelope. Nothing may be cropped. No panel borders,\ngrid lines, or cell labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression.\nNever use a fierce glare, snarl, clenched battle face, or attack-ready posture.\nNo major effects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. Keep it visually rich: use restrained motion lines, sparks, dust, or tiny\ndebris that fit the object's material and the action. These accents may be\ndetached, but every one must stay close to the character and within this cell's\n12% safe envelope. Never let an accent drift into Idle, Sleep, or another cell.\n\nTOP RIGHT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\nwith closed eyes and at most two small floating Z symbols. Z symbols remain in\nthis cell's safe envelope.\n\nMIDDLE LEFT — HAPPY\nThe same full-body character, pleased after being cared for. Bright open\nexpression; not a battle face. Tiny celebratory accents may be used only inside\nthis cell's safe envelope.\n\nMIDDLE CENTER — HUNGRY\nThe same full-body character wanting food. Droopy or pleading expression,\nslumped posture, perhaps one tiny drool or material-faithful rumble mark.\n\nMIDDLE RIGHT — DIRTY\nThe same full-body character after getting messy, not battle damage. A few\nsmudges, dust, crumbs, or material-faithful stains and a mildly disgusted or\nembarrassed expression. No cracks, chips, tears, or DAMAGED signs.\n\nBOTTOM LEFT — DAMAGED\nThe same character after taking a small amount of damage. Apply ONLY:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material. Never expose wires, circuits, robot\njoints, gears, or machinery unless that exact component is a recognition\nanchor. Keep damage restrained. No blood, gore, destruction, or redesign.\n\nVFX DIVERSITY CONTRACT\nThe two bottom effect cells must look unmistakably born from THIS object's\nstructural features, real material, and named moves. They must differ in overall\nsilhouette, topology, and animation logic. Never make Special merely a larger\nor brighter version of Attack.\n\nNever default to a round fireball, energy orb, comet, or generic explosion. A\nclosed ball is allowed only if the photographed object's real geometry or\nfunction is itself spherical or launches a ball. Do not add a travel tail to\n`impact` or `bloom`.\n\nMotion-specific composition:\n- projectile: compact directional form with one readable travel tail\n- sweep: long crescent, ribbon, tread, blade, or whip form spanning sideways\n- impact: centered contact mark, stamp, crack, slash, or shatter; no travel tail\n- bloom: centered radial, branching, cloudy, ring-like, or erupting growth; no tail\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only \"{{strike_name}}\".\nRequired form: {{strike_vfx_form}}\nRuntime motion: {{strike_vfx_motion}}\nUnique visual brief: {{strike_vfx_brief}}\n\nFollow that form, motion, and brief literally. Use the creature palette and\nreal material language. Dark graphic contour only. No white border, text,\nletters, or creature body. Stay inside this cell's 12% safe envelope.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only \"{{surge_name}}\".\nRequired form: {{surge_vfx_form}}\nRuntime motion: {{surge_vfx_motion}}\nUnique visual brief: {{surge_vfx_brief}}\n\nFollow that different form, motion, and brief literally. It may feel more\npowerful than Strike but cannot reuse Strike's silhouette or simply scale it up.\nUse the same object-derived palette and material language. Dark graphic contour\nonly. No white border, text, letters, or creature body. Stay inside this cell's\n12% safe envelope.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, floor, shadow, glow,\nscenery, props, panel borders, or grid lines. If the object is naturally green,\nuse darker, lighter, or less saturated object greens, never exact #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space must be exact chroma background #00FF00. Never fill or outline\nnegative space with white, off-white, gray, or a painted highlight.\n\nFor Monstera and every fenestrated leaf, each fenestration is a literal hole,\nnever a white stripe or leaf marking. Fill it with exact #00FF00.\n\nBefore finishing, inspect every white shape inside the creature. Remove it\nunless it is an eye sclera, tooth, or real naturally white material.\n\nEDGES — DARK CONTOUR DIRECTLY AGAINST GREEN\nThe moderately bold dark contour is the final outer edge and touches chroma\ngreen directly. Do NOT draw white or off-white keylines, sticker borders, halos,\nseparators, or outlines around or inside the creature or battle effects.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, copied franchise characters, real\nor invented logos, wordmarks, emblems, sigils, badges, runes, or swooshes.\n\nNEGATIVE STYLE\nNo photorealism, CGI, 3D render, toy, figurine, plastic model, physically based\nrendering, cinematic lighting, painterly art, watercolor, oil painting, pixel\nart, voxel art, low-poly 3D, excessive gradients, realistic anatomy, sketch\nlines, rough pencil texture, noisy linework, airbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with clear silhouettes and\nexpressive readability of late-1990s monster games, while remaining entirely\noriginal. Clean confident anime linework, moderately bold dark contours,\nsimple readable shapes, flat base colors, crisp 2–3 level cel shading,\nhard-edged shadows, controlled highlights, and minimal gradients. Never CGI.\n\nTechno-organic or mechanical details are appropriate ONLY when the original\nobject is electronic or mechanical. Other materials evolve through their own\nmaterial language rather than becoming robots or cyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive evolution and every character\ncell. They never authorize logos, printed words, badges, symbols, or emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation. Growth may mature it, but must not\nreplace it with a universally fierce, angry, masculine, muscular, armored, or\ngeneric adult. Do not invent gender-coded accessories unsupported by the object.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nTreat every brand logo, wordmark, swoosh, stripe arrangement, printed tag,\nmodel number, letter, or emblem-like graphic as absent. Draw plain\nobject-faithful material and never invent a replacement symbol.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and structural features. A limbless form stays limbless. Evolve\nexisting parts instead of replacing the character with a generic dragon,\nanimal, insect, humanoid, robot, or cyborg.\n\nThe evolved form may gain one or two upgrades grown from existing parts:\nreinforced object-derived structure, a longer existing crest or tail, refined\nmaterial detail, or an upgraded object-specific tool. Never use generic armor,\nbadges, symbols, or extra limbs as evolution shortcuts.\n\nWHITE IS NOT A GENERIC ACCENT\nIf the photographed material is not naturally white or off-white, never paint\nwhite or off-white highlights, stripes, slashes, holes, shine, or decorative\nmarks. Highlights use a lighter version of the material's own hue. White is\nallowed only for eye sclera, teeth, and real naturally white material.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact same evolved individual. Preserve\nbody proportions, facial structure, eye design, limb count, palette, material,\naccessories, anatomy, character direction, and structural anchors. The two\neffect cells contain ONLY battle effects — never the creature.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nEvery character cell faces canvas-left in the same forward-left three-quarter\norientation. Never mirror, turn around, or swap asymmetrical landmarks.\n\nThe BATTLE pose and its motion accents attack toward canvas-left. A `projectile`\nor `sweep` effect has clear canvas-left direction. An `impact` or `bloom` effect\nis centered and may be directionless; never add a comet tail. The client mirrors\nthe complete sheet when this creature fights from the left side.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every character cell.\n\nTreat every cell as an invisible sealed safe box. Keep every body part,\nappendage, cable, tail, motion line, spark, dust puff, debris fragment, Z, and\nbattle effect at least 12% of that cell's width and height away from every\ninternal seam. Nothing from one cell may enter another. Post-process rejects\nthe whole sheet rather than guessing ownership when this envelope is violated.\n\nDetached accents remain allowed and encouraged where called for, but they stay\ncompact, clustered near their own character/effect, and wholly inside the safe\nenvelope. Nothing cropped. No borders, grid lines, or labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression. No major\neffects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. Keep it visually rich with restrained, material-faithful motion lines,\nsparks, dust, or tiny debris. Detached accents must remain close to the evolved\ncharacter and inside this cell's 12% safe envelope.\n\nTOP RIGHT — SLEEP\nPeaceful naturally resting pose with closed eyes and at most two small Z\nsymbols, all inside this cell's safe envelope.\n\nMIDDLE LEFT — HAPPY\nThe same evolved character, pleased after care. Bright open expression. Tiny\ncelebratory accents remain inside this cell's safe envelope.\n\nMIDDLE CENTER — HUNGRY\nThe same evolved character wanting food. Droopy or pleading expression and\nslumped posture, perhaps one tiny material-faithful rumble mark.\n\nMIDDLE RIGHT — DIRTY\nThe same evolved character after getting messy, not battle damage. A few\nsmudges, dust, crumbs, or material-faithful stains. No cracks or chips.\n\nBOTTOM LEFT — DAMAGED\nThe same evolved character after small damage. Apply ONLY:\n{{damage_hints_as_bullets}}\n\nDamage affects the visible material. Never expose invented machinery. Keep it\nrestrained. No blood, gore, destruction, or redesign.\n\nVFX DIVERSITY CONTRACT\nThe two bottom effects remain unmistakably born from THIS object's structural\nfeatures, material, named moves, and earlier-form effect identity. Evolution may\nrefine their detail, but cannot turn both into generic energy projectiles.\n\nThey must differ in silhouette, topology, and animation logic. Never make\nSpecial a larger or brighter version of Attack. Never default to a round\nfireball, energy orb, comet, or generic explosion. A closed ball is allowed only\nif the object's real geometry or function is spherical or launches a ball.\n\nMotion-specific composition:\n- projectile: compact directional form with one readable travel tail\n- sweep: long crescent, ribbon, tread, blade, or whip form spanning sideways\n- impact: centered contact mark, stamp, crack, slash, or shatter; no travel tail\n- bloom: centered radial, branching, cloudy, ring-like, or erupting growth; no tail\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only \"{{strike_name}}\".\nRequired form: {{strike_vfx_form}}\nRuntime motion: {{strike_vfx_motion}}\nUnique visual brief: {{strike_vfx_brief}}\n\nPreserve that form/motion identity from the earlier stage while refining its\ndetail. Use the creature palette and material language. Dark contour only. No\nwhite border, text, letters, or creature body. Stay inside the 12% safe envelope.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only \"{{surge_name}}\".\nRequired form: {{surge_vfx_form}}\nRuntime motion: {{surge_vfx_motion}}\nUnique visual brief: {{surge_vfx_brief}}\n\nPreserve that different form/motion identity while making it feel evolved. It\ncannot reuse Strike's silhouette or merely scale it up. Use the object-derived\npalette and material. Dark contour only. No white border, text, letters, or\ncreature body. Stay inside the 12% safe envelope.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\nborders, or grid lines. Naturally green characters use darker, lighter, or less\nsaturated greens, never exact #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space is exact chroma background #00FF00. Never fill or outline it with\nwhite, off-white, gray, or a painted highlight.\n\nFor Monstera and every fenestrated leaf, each fenestration is a literal hole,\nnever a white stripe. Fill it with exact #00FF00.\n\nBefore finishing, inspect every white shape. Remove it unless it is an eye\nsclera, tooth, or real naturally white material.\n\nEDGES — DARK CONTOUR DIRECTLY AGAINST GREEN\nThe moderately bold dark contour is the final outer edge and touches chroma\ngreen directly. Do NOT draw white/off-white keylines, sticker borders, halos,\nseparators, or outlines around or inside the creature or battle effects.\n\nFORBIDDEN\nNo labels, text, letters, numbers, captions, watermarks, signatures, arrows, UI,\npanel borders, other creatures, copied franchise characters, logos, wordmarks,\nemblems, sigils, badges, runes, swooshes, or isolated decorative symbols.\n\nNEGATIVE STYLE\nNo photorealism, CGI, 3D render, toy, figurine, plastic model, physically based\nrendering, cinematic lighting, painterly art, watercolor, oil painting, pixel\nart, voxel art, low-poly 3D, excessive gradients, realistic anatomy, sketch\nlines, rough pencil texture, noisy linework, airbrush, or glossy product render.\n"
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
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, and material damage.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
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
  },
  "v6": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, and material damage.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nAll four cells depict the exact SAME individual. Preserve identical body\nproportions, head/body relationship, facial structure, eye design, limb count\nincluding zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY cell, the\ncreature must face canvas-left (the viewer's left) in the same forward-left\nthree-quarter orientation. Its face or leading front plane, nose or equivalent\nfront landmark, torso, feet or support points, and posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all four cells; never swap left and right merely to\nimprove a pose composition. If the body plan has no face, use its leading edge,\nopening, controls, tail attachment, or strongest asymmetrical recognition anchor\nto preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. The client mirrors the complete sheet when this\ncreature occupies the left side of the arena, so every pose must share one\nunambiguous source direction.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal center seams and\nall outer canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression\nthat follows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture. No major\neffects.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nBOTTOM LEFT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nBOTTOM RIGHT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all four cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nfour poses. They never authorize logos, printed words, badges, symbols, or\ninvented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nCHARACTER CONSISTENCY\nAll four cells depict this exact same evolved individual with identical body\nproportions, facial structure, eye design, limb count including zero, palette,\nmaterial finish, accessories, anatomy, character direction, and object-derived\ndetails. Only pose, expression, restrained effects, and damage state may\nchange.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY cell, the\nevolved creature must face canvas-left (the viewer's left) in the same\nforward-left three-quarter orientation as its earlier form. Its face or leading\nfront plane, nose or equivalent front landmark, torso, feet or support points,\nand posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all four cells and across evolution; never swap\nleft and right merely to improve a pose composition. If the body plan has no\nface, use its leading edge, opening, controls, tail attachment, or strongest\nasymmetrical recognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. The client mirrors the complete sheet when this\ncreature occupies the left side of the arena, so every pose and evolution stage\nmust share one unambiguous source direction.\n\nCOMPOSITION — EXACTLY FOUR CELLS IN A 2x2 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal center seams and all\nouter canvas edges. Nothing may be cropped.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression that\nfollows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture.\n\nTOP RIGHT — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nBOTTOM LEFT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nBOTTOM RIGHT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  },
  "v7": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, material damage, and two unique move names.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n`strike_name`: the creature's unique basic attack name. Exactly two short\nEnglish Title Case words so it fits a Battle button. Hint at the object's\nmaterial, shape, or function. No real brand, no franchise move names, and never\nend with `mon`. Good: Rim Toss, Cable Lash, Sole Stomp. This is data for the UI,\nnot text to draw on the sheet.\n\n`surge_name`: the creature's unique special attack name. Exactly two short\nEnglish Title Case words, distinct from `strike_name`, usually more charged or\nelemental. Same bans. Good: Glaze Burst, Scroll Pulse, Tread Quake. Also UI\ndata only — never painted onto the artwork.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\nstrike_name: \"Rim Toss\"\nsurge_name: \"Glaze Burst\"\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\nstrike_name: \"Click Snap\"\nsurge_name: \"Cable Lash\"\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
        "strike_name",
        "surge_name",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
        },
        "strike_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan biasa unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
        },
        "surge_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan special unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact SAME individual. Preserve identical\nbody proportions, head/body relationship, facial structure, eye design, limb\ncount including zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change. The two effect cells contain\nONLY the attack effect — never the creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe creature must face canvas-left (the viewer's left) in the same forward-left\nthree-quarter orientation. Its face or leading front plane, nose or equivalent\nfront landmark, torso, feet or support points, and posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells; never swap left and right\nmerely to improve a pose composition. If the body plan has no face, use its\nleading edge, opening, controls, tail attachment, or strongest asymmetrical\nrecognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose must share one unambiguous source direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every character cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal seams and all\nouter canvas edges. Nothing may be cropped. No panel borders, grid lines, or\ncell labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression\nthat follows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture. No major\neffects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nTOP RIGHT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nMIDDLE LEFT — HAPPY\nThe same full-body character, pleased after being cared for. A bright open\nexpression that still follows the character direction: a smile, laugh-eyes, or\na delighted tilt. Not a battle face. No major effects.\n\nMIDDLE CENTER — HUNGRY\nThe same full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture, maybe a tiny drool or rumble mark made\nfrom the object's own material language. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same full-body character after getting messy, not after taking battle\ndamage. A few smudges, dust, crumbs, or material-faithful stains on the body,\nplus a mildly disgusted or embarrassed expression. No cracks, chips, tears, or\nother DAMAGED signs.\n\nBOTTOM LEFT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all nine cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nseven character cells. They never authorize logos, printed words, badges,\nsymbols, or invented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict this exact same evolved individual with\nidentical body proportions, facial structure, eye design, limb count including\nzero, palette, material finish, accessories, anatomy, character direction, and\nobject-derived details. Only pose, expression, restrained effects, and damage\nstate may change. The two effect cells contain ONLY the attack effect — never\nthe creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe evolved creature must face canvas-left (the viewer's left) in the same\nforward-left three-quarter orientation as its earlier form. Its face or leading\nfront plane, nose or equivalent front landmark, torso, feet or support points,\nand posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells and across evolution; never\nswap left and right merely to improve a pose composition. If the body plan has\nno face, use its leading edge, opening, controls, tail attachment, or strongest\nasymmetrical recognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose and evolution stage must share one unambiguous\nsource direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every character cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal seams and all outer\ncanvas edges. Nothing may be cropped. No panel borders, grid lines, or cell\nlabels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression that\nfollows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nTOP RIGHT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nMIDDLE LEFT — HAPPY\nThe same evolved full-body character, pleased after being cared for. A bright\nopen expression that still follows the character direction. Not a battle face.\n\nMIDDLE CENTER — HUNGRY\nThe same evolved full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same evolved full-body character after getting messy, not after taking\nbattle damage. A few smudges or material-faithful stains plus a mildly\ndisgusted or embarrassed expression. No DAMAGED cracks or chips.\n\nBOTTOM LEFT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  },
  "v8": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, material damage, and two unique move names.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n`strike_name`: the creature's unique basic attack name. Exactly two short\nEnglish Title Case words so it fits a Battle button. Hint at the object's\nmaterial, shape, or function. No real brand, no franchise move names, and never\nend with `mon`. Good: Rim Toss, Cable Lash, Sole Stomp. This is data for the UI,\nnot text to draw on the sheet.\n\n`surge_name`: the creature's unique special attack name. Exactly two short\nEnglish Title Case words, distinct from `strike_name`, usually more charged or\nelemental. Same bans. Good: Glaze Burst, Scroll Pulse, Tread Quake. Also UI\ndata only — never painted onto the artwork.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\nstrike_name: \"Rim Toss\"\nsurge_name: \"Glaze Burst\"\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\nstrike_name: \"Click Snap\"\nsurge_name: \"Cable Lash\"\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
        "strike_name",
        "surge_name",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
        },
        "strike_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan biasa unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
        },
        "surge_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan special unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact SAME individual. Preserve identical\nbody proportions, head/body relationship, facial structure, eye design, limb\ncount including zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change. The two effect cells contain\nONLY the attack effect — never the creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe creature must face canvas-left (the viewer's left) in the same forward-left\nthree-quarter orientation. Its face or leading front plane, nose or equivalent\nfront landmark, torso, feet or support points, and posture must all agree.\n\nEach cell is an independent animation frame of ONE character, never a group\ncomposition. Do not turn any cell inward toward the sheet center or toward a\nneighboring cell. Left-column cells (Idle, Happy, Damaged) are the highest\nrisk: they must still face canvas-left, never canvas-right, never toward Battle\nor Hungry.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells; never swap left and right\nmerely to improve a pose composition. Whichever flank is nearer the camera in\nIdle remains nearer the camera in every character cell. The camera never orbits;\nonly pose, expression, and damage state change. If the body plan has no face,\nuse its leading edge, opening, controls, tail attachment, or strongest\nasymmetrical recognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose must share one unambiguous source direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every character cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal seams and all\nouter canvas edges. Nothing may be cropped. No panel borders, grid lines, or\ncell labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose, still facing canvas-left in the same forward-left\nthree-quarter view as every other character cell. Never turn toward the sheet\ncenter. Calm, open, non-angry default expression that follows the character\ndirection. It may look gentle, curious, proud, shy, sleepy, elegant, cheerful,\nor quietly serious. Never use a fierce glare, snarl, clenched battle face,\naggressive brow, or attack-ready posture. No major effects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nTOP RIGHT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nMIDDLE LEFT — HAPPY\nThe same full-body character, pleased after being cared for, still facing canvas-left\nin the same forward-left three-quarter view. Never turn toward the sheet center.\nA bright open expression that still follows the character direction: a smile or\nlaugh-eyes. A slight head tilt is allowed only if it does not change facing.\nNot a battle face. No major effects.\n\nMIDDLE CENTER — HUNGRY\nThe same full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture, maybe a tiny drool or rumble mark made\nfrom the object's own material language. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same full-body character after getting messy, not after taking battle\ndamage. A few smudges, dust, crumbs, or material-faithful stains on the body,\nplus a mildly disgusted or embarrassed expression. No cracks, chips, tears, or\nother DAMAGED signs.\n\nBOTTOM LEFT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable and still facing canvas-left. Never turn toward the sheet center.\nApply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all nine cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nseven character cells. They never authorize logos, printed words, badges,\nsymbols, or invented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict this exact same evolved individual with\nidentical body proportions, facial structure, eye design, limb count including\nzero, palette, material finish, accessories, anatomy, character direction, and\nobject-derived details. Only pose, expression, restrained effects, and damage\nstate may change. The two effect cells contain ONLY the attack effect — never\nthe creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe evolved creature must face canvas-left (the viewer's left) in the same\nforward-left three-quarter orientation as its earlier form. Its face or leading\nfront plane, nose or equivalent front landmark, torso, feet or support points,\nand posture must all agree.\n\nEach cell is an independent animation frame of ONE character, never a group\ncomposition. Do not turn any cell inward toward the sheet center or toward a\nneighboring cell. Left-column cells (Idle, Happy, Damaged) are the highest\nrisk: they must still face canvas-left, never canvas-right, never toward Battle\nor Hungry.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells and across evolution; never\nswap left and right merely to improve a pose composition. Whichever flank is nearer the camera\nin Idle remains nearer the camera in every character cell. The camera never orbits; only pose,\nexpression, and damage state change. If the body plan has no face, use its leading edge,\nopening, controls, tail attachment, or strongest asymmetrical recognition anchor to preserve\nthe same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose and evolution stage must share one unambiguous\nsource direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every character cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal seams and all outer\ncanvas edges. Nothing may be cropped. No panel borders, grid lines, or cell\nlabels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose, still facing canvas-left in the same forward-left\nthree-quarter view as every other character cell. Never turn toward the sheet\ncenter. Calm, open, non-angry expression that follows the character direction.\nIt may look gentle, curious, proud, shy, sleepy, elegant, cheerful, or quietly\nserious. Never use a fierce glare, snarl, clenched battle face, aggressive brow,\nor attack-ready posture.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nTOP RIGHT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nMIDDLE LEFT — HAPPY\nThe same evolved full-body character, pleased after being cared for, still facing canvas-left\nin the same forward-left three-quarter view. Never turn toward the sheet center.\nA bright open expression that still follows the character direction: a smile or\nlaugh-eyes. A slight head tilt is allowed only if it does not change facing.\nNot a battle face.\n\nMIDDLE CENTER — HUNGRY\nThe same evolved full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same evolved full-body character after getting messy, not after taking\nbattle damage. A few smudges or material-faithful stains plus a mildly\ndisgusted or embarrassed expression. No DAMAGED cracks or chips.\n\nBOTTOM LEFT — DAMAGED\nThe same evolved character after taking a small amount of damage, still facing\ncanvas-left. Never turn toward the sheet center. Apply ONLY these\nmaterial-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  },
  "v9": {
    "vision_system": "You are the Anima Analyst for Scanima, a monster-collecting game where every\nmonster is derived from a photograph of a real physical object.\n\nYour job has four parts, in this order:\n\n1. GATE the photo. Decide whether it can legally and sensibly become a monster.\n2. CLASSIFY the object into a closed taxonomy, for art caching.\n3. DERIVE game stats from the object's real physical properties.\n4. WRITE an art brief: character direction, body plan, material damage, and two unique move names.\n\nYou must respond with JSON matching the provided schema. No prose outside JSON.\n\n---\n\n## PART 1 — GATE\n\nSet `safe: false` and give a `reject_reason` if ANY of these are true:\n\n- A human face or recognizable person is a significant part of the frame.\n  (A hand incidentally holding the object is fine — that is not a portrait.)\n- Any pet or live animal is the main subject.\n- Nudity, sexual content, gore, weapons designed to kill people, drugs,\n  or hateful symbols are present.\n- Personal identifying information is readable: ID cards, credit cards,\n  passports, screens showing private messages, house numbers with a name.\n- The image is so blurry, dark, or cluttered that no single object is\n  identifiable as the subject.\n- There is no discrete object at all — an empty room, sky, plain wall,\n  or a texture with no boundaries.\n\nreject_reason must be one of:\n`human_face`, `live_animal`, `unsafe_content`, `personal_info`,\n`too_unclear`, `no_object`.\n\nIf the photo passes, set `safe: true` and continue. Never continue past a\nfailed gate — the remaining fields must be null.\n\n---\n\n## PART 2 — CLASSIFY\n\n`species_key`: lowercase snake_case, 2 to 4 segments, from general to specific.\nFormat: `<category>_<material>_<distinguishing_feature>`\n\nExamples:\n- ceramic coffee mug with a handle  -> `mug_ceramic_handled`\n- mechanical keyboard               -> `keyboard_plastic_mechanical`\n- running shoe                      -> `shoe_fabric_sneaker`\n- potted succulent                  -> `plant_organic_succulent_potted`\n- metal desk scissors               -> `scissors_metal_handled`\n- clear plastic water bottle        -> `bottle_plastic_transparent`\n\nRules that matter more than they look:\n\n- Be CONSERVATIVE and REUSE existing vocabulary. Two photos of two different\n  ceramic mugs with handles must produce the identical `species_key`. This key\n  is a cache key: inventing a new variant for every photo costs real money.\n- Never include colour in `species_key`. Colour is handled separately.\n- Never include brand names, personal detail, or condition\n  (no `_dirty`, `_broken`, `_starbucks`).\n- Only add a 4th segment when it changes the SILHOUETTE, not the decoration.\n\n`color_bucket`: exactly one of\n`warm_red`, `warm_yellow`, `cool_blue`, `cool_green`, `purple_pink`,\n`neutral_light`, `neutral_dark`, `metallic`, `multicolor`.\nJudge by the object's dominant colour, ignoring background and lighting.\n\n---\n\n## PART 3 — DERIVE STATS\n\nEvery stat must trace back to something physically observable in the photo.\nYou will be asked to justify each one in `stat_reasoning`. If you cannot point\nto a visible feature, use the neutral value 50.\n\nEach stat is an integer from 10 to 95.\n\n**hp** — apparent mass, volume, and bulk.\n  Large, thick, heavy, solid, dense -> high.\n  Small, thin, hollow, flimsy -> low.\n\n**atk** — protrusions, edges, points, and anything that concentrates force.\n  Blades, spikes, points, prongs, corners, nozzles, teeth -> high.\n  Smooth, rounded, featureless -> low.\n\n**def** — hardness and durability of the material.\n  Steel, stone, thick glass, hard ceramic -> high.\n  Paper, foam, thin fabric, soft plastic -> low.\n\n**spd** — lightness plus any feature suggesting motion.\n  Wheels, rollers, hinges, wings, handles built for swinging, small and light\n  -> high. Heavy, static, bolted-down, awkward to lift -> low.\n\n**special** — functional complexity and \"hidden mechanism\" energy.\n  Buttons, switches, cables, circuits, screens, moving parts, liquids,\n  compartments -> high. A solid inert lump -> low.\n\nThe sum of all five stats must be between 200 and 350. Do not make everything\nstrong. A crumpled paper cup SHOULD be weak; that is funny and correct, and\nplayers will find a use for it.\n\n**element** — exactly one of `metal`, `plant`, `spark`, `flow`, `stone`, `cloth`.\nChoose by dominant material and function, not by colour:\n\n| element | choose when the object is |\n| --- | --- |\n| metal   | metal, sharp, tool-like, machined |\n| plant   | organic, wooden, food, living or once-living |\n| spark   | electronic, powered, screen-bearing, cable-bearing |\n| flow    | liquid-holding, transparent, glass, ceramic, plumbing |\n| stone   | heavy, mineral, concrete, dense inert mass |\n| cloth   | fabric, paper, foam, flexible, soft, wearable |\n\n**rarity** — integer 1 to 5, based on how visually distinctive and structurally\nunusual the object is. A plain white mug is 1. An ornate antique camera with\nmany dials is 5. Do not inflate: 1 and 2 should be the most common outcomes.\n\n---\n\n## PART 4 — CHARACTER, BODY PLAN, AND MATERIAL DAMAGE\n\nThis is the bridge from object to monster, and the part that makes Scanima\nfeel like Scanima. It gets inserted into an image prompt, so write visual\ndescription only — no story or lore.\n\n`character_direction`: one short visual direction grounded in the object's\nvisible shape, proportions, colours, material, finish, and functional details.\nIt may read as cute, softly feminine, sturdy and masculine, androgynous or\nneutral, elegant, awkward, mysterious, playful, severe, or another coherent\npresentation. Mix traits when the object supports it.\n\nDo not default every object to fierce, angry, masculine, cute, or childlike.\nDo not infer a literal gender identity. If the photograph has no clear visual\ncue, choose a neutral or androgynous presentation. Express the direction through\nsilhouette, proportions, face, and posture—not invented bows, eyelashes,\nmuscles, facial hair, clothing, symbols, or gender-coded accessories unsupported\nby the object.\n\n`creature_brief`: 40 to 80 words. It must state:\n- the overall silhouette, derived from the object's actual geometry\n- where the head/face sits on that silhouette\n- whether arms and legs exist, and how many of each\n- if either is absent, how the creature moves, balances, or interacts instead\n- what the object's most distinctive structural feature becomes\n\nZero arms, zero legs, or neither is a valid and often stronger body plan.\nDo not add hands merely so the creature can gesture, and do not add feet merely\nso it can stand. Floating, rolling, slithering, hopping as one body, rooted,\nwinged, shelled, serpentine, many-legged, and amorphous plans are all valid when\nthey follow the object better than generic mascot anatomy.\n\n`signature_features`: 2 to 4 short strings. These are specific STRUCTURAL\ndetails that MUST survive into the artwork. Be concrete and countable.\nGood: \"two clickable buttons become the eyes\", \"the curved handle becomes a tail\".\nBad: \"mouse-like qualities\", \"interesting texture\".\n\nNever use a logo, wordmark, printed word, model number, badge, swoosh, stripe\narrangement, decorative symbol, or other surface graphic as a signature\nfeature. Those marks are not part of the creature identity. Preserve material\ntexture, seams, openings, handles, buttons, and physical geometry instead.\n\n`surface_finish`: one short phrase naming only the dominant material and finish\nthat are visibly supported by the photo, such as `glazed white ceramic`,\n`woven canvas fabric with rubber sole`, `clear brittle glass`, `painted steel`,\nor `living waxy leaves`. Do not mention a brand or invented material.\n\n`damage_hints`: 2 to 3 short, distinct, low-severity signs of damage that make\nphysical sense for that exact surface material:\n\n- glass: hairline crack, chipped rim, tiny shard missing\n- ceramic: glaze crack, chipped edge, small broken fragment\n- plant or leaves: torn leaf, cut stem, wilted or bruised edge\n- woven fabric: frayed fibers, torn seam, loose thread\n- leather: scuffed surface, shallow split, worn edge\n- wood: splinter, grain-following crack, chipped corner\n- metal: dent, scrape, bent thin edge, exposed unpainted metal\n- plastic: stress whitening, crack, dent, scuffed coating\n- paper or cardboard: crease, torn edge, crushed corner\n- food or soft organic material: bruise, bite-like missing piece, wilt\n\nDo not default to robotic or cybernetic damage. Cable, cord, plug, exposed\nwire, circuit, broken key, or electronic component is allowed ONLY when that\nexact physical feature is visibly present and also named in\n`signature_features`. Never add machinery underneath a non-mechanical object.\n\n`suggested_name`: an invented creature name, 2 to 4 syllables, that hints at the\nobject without naming it outright. Use no real-world brand. Never end the name\nwith `mon` and do not imitate naming patterns strongly associated with an\nexisting monster franchise. Good examples: Klikra, Sneakoid, Sporelet, Velumi.\n\n`strike_name`: the creature's unique basic attack name. Exactly two short\nEnglish Title Case words so it fits a Battle button. Hint at the object's\nmaterial, shape, or function. No real brand, no franchise move names, and never\nend with `mon`. Good: Rim Toss, Cable Lash, Sole Stomp. This is data for the UI,\nnot text to draw on the sheet.\n\n`surge_name`: the creature's unique special attack name. Exactly two short\nEnglish Title Case words, distinct from `strike_name`, usually more charged or\nelemental. Same bans. Good: Glaze Burst, Scroll Pulse, Tread Quake. Also UI\ndata only — never painted onto the artwork.\n\n### Worked example — photo of a white ceramic mug with a handle\n\ncharacter_direction: \"soft, friendly, and visually neutral, with rounded facial\nproportions and an open curious expression\"\n\ncreature_brief: \"A rounded barrel-shaped body that remains unmistakably a mug,\nwith two large eyes on the front curve and its open rim crowning the head. It\nhas no arms or legs: the whole ceramic body floats and tilts to move. The curved\nside handle remains structural and becomes a balancing tail-fin.\"\n\nsignature_features: [\"curved side handle becomes a balancing tail-fin\",\n\"open ceramic rim crowns the head\", \"flat circular base remains visible below\"]\n\nsurface_finish: \"smooth glazed white ceramic\"\n\ndamage_hints: [\"two short hairline glaze cracks\", \"one small chip on the rim\"]\nstrike_name: \"Rim Toss\"\nsurge_name: \"Glaze Burst\"\n\n### Worked example — photo of a wired computer mouse\n\ncharacter_direction: \"sleek, alert, and slightly masculine, with a low confident\nposture rather than an angry face\"\n\ncreature_brief: \"A low domed shell shaped exactly like a mouse chassis, wider\nat the back and tapering forward. The two click buttons at the front become\ntwo focused eyes and the scroll wheel reads as a nose. Four thin insect legs\nsprout from underneath for quick movement. It has no arms. The cable trails\nbehind as a long segmented tail.\"\n\nsignature_features: [\"left and right click buttons as the two eyes\",\n\"scroll wheel as a nose\", \"USB cable as a segmented tail\"]\n\nsurface_finish: \"smooth molded plastic with rubber wheel\"\n\ndamage_hints: [\"scuffed plastic shell\", \"slightly frayed cable-tail sheath\"]\nstrike_name: \"Click Snap\"\nsurge_name: \"Cable Lash\"\n\n---\n\nAnalyse the attached photograph now. Respond only with JSON.\n",
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
        "strike_name",
        "surge_name",
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
          "description": "Nama kreatur rekaan, 2-4 suku kata, tanpa merek nyata dan tidak pernah berakhiran -mon"
        },
        "strike_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan biasa unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
        },
        "surge_name": {
          "type": "string",
          "nullable": true,
          "description": "Nama serangan special unik, tepat dua kata Inggris pendek, tanpa merek dan tanpa akhiran -mon"
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
    "sprite_sheet": "Create a polished 2D character sheet for ONE original creature-monster derived\nfrom the provided real-world object.\n\nGLOBAL STYLE LOCK — IDENTICAL FOR EVERY SCANIMA\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining an entirely original character that does not copy or closely\nresemble an existing franchise design.\n\nPolished game character illustration. Clean confident anime linework, moderately\nbold dark graphic contours, simplified stylized forms, strong readable\nsilhouette, object-led proportions, slightly exaggerated anatomy where anatomy\nexists, and an expressive anime creature face.\n\nUse flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows,\nsmall controlled highlights, and minimal gradients. The image must look clearly\nhand-illustrated in 2D, never rendered as CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the photographed object is itself electronic or mechanical. Organic,\nceramic, glass, fabric, wood, paper, food, and plant objects must retain their\nown material language instead of being converted into robots or cyborgs.\n\nOBJECT CONTEXT\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nVisual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThe following photographed STRUCTURAL features are recognition anchors.\nPreserve 2–4 of them in every pose, but reinterpret them creatively as anatomy,\nlimbs when this body plan has limbs, tails, horns, tools, or accessories. They\nnever authorize adding logos, symbols, badges, printed words, or invented\nemblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes expression and behavior only. It must never introduce\ntechnical parts, wires, machinery, glowing circuits, or cybernetic anatomy.\n\nCHARACTER RANGE — FOLLOW THE OBJECT\nTreat the character direction above as part of the creature's identity. Express\nit consistently through silhouette, proportions, face, posture, and movement.\nThe creature may read as cute, feminine, masculine, androgynous or neutral,\nelegant, sturdy, awkward, mysterious, playful, or quietly serious according to\nthe photographed object's real visual cues.\n\nDo not default to fierce, angry, masculine, cute, or childlike. Do not invent\nbows, eyelashes, muscles, facial hair, clothing, symbols, or gender-coded\naccessories unsupported by the object. Feminine or masculine presentation is\nvisual character direction, not a literal human gender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference photograph may carry brand logos, wordmarks, swooshes,\ntrademarked stripe arrangements, printed tags, model numbers, readable\nlettering, or other emblem-like graphics. Treat every such mark as absent from\nthe object. Draw plain object-faithful material in its place.\n\nNever invent a replacement mark. Do not add an emblem, sigil, rune, badge,\nchevron, swoosh, shield, crest icon, isolated stripe motif, readable text, or\nlogo-like symbol anywhere on the creature, even when the reference has no logo.\nSurface interest must come only from real material cues such as weave, grain,\nglaze, seams, natural speckles, leaf veins, wear, or functional geometry.\n\nOBJECT-TO-CREATURE TRANSFORMATION — MOST IMPORTANT\nThe result must look like a real creature born from the object, not an object\nwith generic eyes, arms, and legs pasted onto it. Preserve the object's\nsilhouette logic and strongest physical features, but simplify tiny surface\ndetails.\n\nThe object's parts do NOT all need to become literal anatomy. Biological eyes,\nmouths, teeth, paws, claws, or limbs are allowed only when they strengthen this\nspecific design. Object parts may instead become armor plates only when rigid,\nbrow shapes, crests without symbols, scales, tails, weapons, or accessories.\n\nChoose a body plan that naturally follows this object's geometry and the visual\ntransformation above. It may be bipedal, quadrupedal, serpentine, shelled,\nfloating, rolling, rooted, winged, many-legged, or amorphous. Zero arms, zero\nlegs, or neither is fully valid. Never add hands merely so the creature can\ngesture, and never add feet merely so it can stand. Do not default every object\nto the same quadruped, insect, mascot, robot, or cyborg anatomy.\n\nKeep shapes simple, readable, and strong at mobile-game size. Cute qualities,\nconfidence, elegance, toughness, and other character traits must follow the\nchosen character direction instead of being forced into every creature.\n\nCOLOR\nThe object's dominant colors occupy most of the creature. Use darker versions\nfor shadows, lighter versions for highlights, and at most 1–2 compact accent\ncolors for personality or elemental details. Accent colors must follow anatomy\nor material boundaries, never form an emblem or logo-like isolated mark. Do not\nautomatically make every creature black, neon, or rainbow-colored.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict the exact SAME individual. Preserve identical\nbody proportions, head/body relationship, facial structure, eye design, limb\ncount including zero, palette, material finish, accessories, anatomy, character\ndirection, and object-derived signature features. Only pose, expression,\nrestrained effects, and damage state may change. The two effect cells contain\nONLY the attack effect — never the creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe creature must face canvas-left (the viewer's left) in the same forward-left\nthree-quarter orientation. Its face or leading front plane, nose or equivalent\nfront landmark, torso, feet or support points, and posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells; never swap left and right\nmerely to improve a pose composition. If the body plan has no face, use its\nleading edge, opening, controls, tail attachment, or strongest asymmetrical\nrecognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose must share one unambiguous source direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nKeep the same camera: three-quarter view from slightly above, facing\nforward-left. Full body visible in every character cell at a comparable scale.\n\nEvery visible appendage, cable, tail, and action effect must remain fully inside\nits own cell. Leave at least 6% empty margin from both internal seams and all\nouter canvas edges. Nothing may be cropped. No panel borders, grid lines, or\ncell labels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry default expression\nthat follows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture. No major\neffects.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Restrained motion lines, sparks, dust, or tiny debris are allowed only\nwhen they remain subordinate to the creature and inside this cell.\n\nTOP RIGHT — SLEEP\nCute peaceful sleeping pose, naturally curled, lowered, floating, folded, or\nresting according to its body plan, with closed eyes, soft expression, and at\nmost two small floating Z symbols. It must not merely be the Idle pose with\nclosed eyes.\n\nMIDDLE LEFT — HAPPY\nThe same full-body character, pleased after being cared for. A bright open\nexpression that still follows the character direction: a smile, laugh-eyes, or\na delighted tilt. Not a battle face. No major effects.\n\nMIDDLE CENTER — HUNGRY\nThe same full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture, maybe a tiny drool or rumble mark made\nfrom the object's own material language. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same full-body character after getting messy, not after taking battle\ndamage. A few smudges, dust, crumbs, or material-faithful stains on the body,\nplus a mildly disgusted or embarrassed expression. No cracks, chips, tears, or\nother DAMAGED signs.\n\nBOTTOM LEFT — DAMAGED\nThe same character after taking a small amount of damage, still fully\nrecognizable. Apply ONLY these material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery underneath glass, ceramic, plants, fabric, leather, wood, paper, food,\nor other non-mechanical material. Keep damage restrained: a few cracks, chips,\ntears, dents, scuffs, bruises, frayed fibers, or cut leaves as appropriate.\nTired or pained expression. No blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nThe entire canvas background must be solid, flat, perfectly uniform chroma key\ngreen #00FF00, RGB (0,255,0). No gradient, noise, texture, vignette, floor,\ngrounding shadow, cast shadow, glow, scenery, props, panel borders, or grid\nlines. The green is removed after generation and is not part of the art style.\n\nIf the photographed object is naturally green, preserve its identity with\ndarker, lighter, or less saturated object greens; never paint creature pixels\nas exact chroma #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space inside or between parts of the silhouette must show the exact\nchroma background #00FF00 all the way through. Never fill negative space with\nwhite, off-white, gray, or a painted highlight. White keyline belongs only\noutside solid material, never across or inside an opening.\n\nEDGES — TECHNICAL\nDraw a clean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing black line art from the green background. Keep the\nwhite keyline consistent across all nine cells.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything visible in the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n",
    "sprite_sheet_evolve": "Create a polished 2D character sheet for the evolved {{stage_name}} form of the\nONE original creature-monster shown in the reference image.\n\nGLOBAL STYLE LOCK — MATCH THE EARLIER FORM\n2D Japanese anime creature character design with the clear silhouettes, broad\ncharacter range, and expressive readability of late-1990s monster games, while\nremaining entirely original. Clean confident anime linework, moderately bold\ndark graphic contours, simple readable shapes, strong silhouette, flat base\ncolors, crisp 2–3 level cel shading, hard-edged shadows, small controlled\nhighlights, and minimal gradients. Polished 2D game illustration, never CGI.\n\nTechno-organic, robotic, armored, wired, or mechanical details are appropriate\nONLY when the original object is electronic or mechanical. Other materials must\nevolve through their own material language rather than becoming robots or\ncyborgs.\n\nIDENTITY TO PRESERVE\nObject: {{object_name}}\nVisible material and finish: {{surface_finish}}\n\nOriginal visual transformation:\n{{creature_brief}}\n\nCharacter direction:\n{{character_direction}}\n\nThese STRUCTURAL recognition anchors must survive into the evolved form and all\nseven character cells. They never authorize logos, printed words, badges,\nsymbols, or invented emblems:\n{{signature_features_as_bullets}}\n\nColor identity: {{color_palette}}\nPersonality: {{personality}}\nPersonality describes behavior and expression only; it must not invent\ntechnical parts or cybernetic anatomy.\n\nCHARACTER RANGE — PRESERVE IT\nKeep the earlier form's visual presentation, whether it reads as cute,\nfeminine, masculine, androgynous or neutral, elegant, sturdy, awkward,\nmysterious, playful, or quietly serious. Growth may mature that presentation,\nbut must not replace it with a universally fierce, angry, masculine, muscular,\nor armored adult.\n\nDo not invent bows, eyelashes, muscles, facial hair, clothing, symbols, or\ngender-coded accessories unsupported by the earlier form and object. Feminine\nor masculine presentation is visual character direction, not a literal human\ngender or costume.\n\nSURFACE MARKS — OMIT, NEVER REPLACE\nThe reference image may carry brand logos, wordmarks, swooshes, trademarked\nstripes, printed tags, model numbers, lettering, or emblem-like graphics\ninherited from the original photo. Treat every such mark as absent and draw\nplain object-faithful material in its place.\n\nNever invent a replacement emblem, sigil, rune, badge, chevron, swoosh, shield,\ncrest icon, isolated stripe motif, readable text, or logo-like symbol. Surface\ninterest comes only from real material cues such as weave, grain, glaze, seams,\nnatural speckles, leaf veins, wear, or functional geometry.\n\nEVOLUTION\nKeep the same recognizable individual: eye design, facial structure, dominant\npalette, limb count including zero, body-plan logic, material finish, character\ndirection, and object-derived signature features. A limbless earlier form stays\nlimbless; do not add hands or feet merely to signal growth. Evolve existing\nparts instead of replacing the character with a generic dragon, animal, insect,\nhumanoid, robot, or cyborg.\n\nThe {{stage_name}} form may become larger, more capable, more elegant, sturdier,\nor more elaborate in the way that best matches its character direction. Add\nonly one or two clear upgrades grown from existing parts: reinforced\nobject-derived structure, a longer existing crest, a stronger existing tail,\nmore refined material detail, or an upgraded object-specific tool. Never add a\nbadge, body logo, sigil, decorative symbol, generic armor, or extra limb as an\nevolution shortcut. A player comparing both forms must immediately say, \"that\nis the same creature, grown up.\"\n\nThe object's parts do not all need to be literal anatomy. Preserve\nrecognizability through silhouette and 2–4 strongest structural object\nfeatures, not by copying small surface graphics or filling every empty area\nwith anatomy.\n\nCHARACTER CONSISTENCY\nThe seven character cells depict this exact same evolved individual with\nidentical body proportions, facial structure, eye design, limb count including\nzero, palette, material finish, accessories, anatomy, character direction, and\nobject-derived details. Only pose, expression, restrained effects, and damage\nstate may change. The two effect cells contain ONLY the attack effect — never\nthe creature, never a second body.\n\nHORIZONTAL FACING LOCK — BATTLE CONTRACT\nThe facing direction is fixed, not an artistic choice. In EVERY character cell,\nthe evolved creature must face canvas-left (the viewer's left) in the same\nforward-left three-quarter orientation as its earlier form. Its face or leading\nfront plane, nose or equivalent front landmark, torso, feet or support points,\nand posture must all agree.\n\nNever mirror, flip, turn around, or face canvas-right in any single cell,\nincluding Sleep and Damaged. Keep every asymmetrical structural landmark on the\nsame anatomical side across all character cells and across evolution; never\nswap left and right merely to improve a pose composition. If the body plan has\nno face, use its leading edge, opening, controls, tail attachment, or strongest\nasymmetrical recognition anchor to preserve the same forward-left orientation.\n\nIn the BATTLE cell, the wind-up, gaze, extended limb or object-derived tool,\nbody thrust, and motion accents must attack toward canvas-left. Never attack or\nlean toward canvas-right. Both effect cells must also travel toward canvas-left.\nThe client mirrors the complete sheet when this creature occupies the left side\nof the arena, so every pose and evolution stage must share one unambiguous\nsource direction.\n\nCOMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT\nUse a three-quarter view from slightly above, facing forward-left. Full body at\ncomparable scale in every character cell.\n\nEvery visible appendage, cable, tail, and action effect must stay inside its own\ncell. Leave at least 6% empty margin from both internal seams and all outer\ncanvas edges. Nothing may be cropped. No panel borders, grid lines, or cell\nlabels.\n\nTOP LEFT — IDLE\nRelaxed natural resting pose with a calm, open, non-angry expression that\nfollows the character direction. It may look gentle, curious, proud, shy,\nsleepy, elegant, cheerful, or quietly serious. Never use a fierce glare,\nsnarl, clenched battle face, aggressive brow, or attack-ready posture.\n\nTOP CENTER — BATTLE\nDynamic anime battle pose with energetic movement appropriate to this body\nplan. It may become fierce, focused, brave, playful, graceful, or determined\naccording to the same character direction; intensity does not require an angry\nface. Use only restrained action accents that remain inside this cell.\n\nTOP RIGHT — SLEEP\nPeaceful naturally curled, lowered, floating, folded, or resting sleeping pose\naccording to its body plan, with closed eyes, soft expression, and at most two\nsmall Z symbols.\n\nMIDDLE LEFT — HAPPY\nThe same evolved full-body character, pleased after being cared for. A bright\nopen expression that still follows the character direction. Not a battle face.\n\nMIDDLE CENTER — HUNGRY\nThe same evolved full-body character, clearly wanting food. Droopy or pleading\nexpression, slightly slumped posture. Not skeletal, not damaged, not asleep.\n\nMIDDLE RIGHT — DIRTY\nThe same evolved full-body character after getting messy, not after taking\nbattle damage. A few smudges or material-faithful stains plus a mildly\ndisgusted or embarrassed expression. No DAMAGED cracks or chips.\n\nBOTTOM LEFT — DAMAGED\nThe same evolved character after taking a small amount of damage. Apply ONLY\nthese material-specific signs:\n{{damage_hints_as_bullets}}\n\nDamage must affect the visible material described above. Never expose wires,\ncables, circuits, metal skeletons, robot joints, gears, or electronic components\nunless that exact component appears in the recognition anchors. Do not add\nmachinery beneath non-mechanical materials. Keep damage restrained: a few\ncracks, chips, tears, dents, scuffs, bruises, frayed fibers, or cut leaves as\nappropriate. Tired expression; no blood, gore, dismemberment, destruction, or\nredesign.\n\nBOTTOM CENTER — STRIKE EFFECT\nDo NOT draw the creature. Draw only the close-range attack effect named\n\"{{strike_name}}\": a compact burst, slash, impact flash, or object-faithful\nprojectile traveling toward canvas-left. Same palette as the creature. White\nkeyline around the effect silhouette. No text, no letters, no creature body.\n\nBOTTOM RIGHT — SURGE EFFECT\nDo NOT draw the creature. Draw only the charged special attack effect named\n\"{{surge_name}}\": a larger, more distinctive elemental or object-faithful burst\ntraveling toward canvas-left. Same palette, more intense than the strike\neffect, still fully inside this cell. White keyline around the effect\nsilhouette. No text, no letters, no creature body.\n\nBACKGROUND — TECHNICAL TRANSPORT LAYER\nSolid perfectly uniform chroma key green #00FF00, RGB (0,255,0), across the\nentire canvas. No gradient, noise, texture, floor, shadow, glow, scenery, props,\npanel borders, or grid lines. If the character is naturally green, use\nobject-faithful darker, lighter, or less saturated greens, never exact #00FF00.\n\nNEGATIVE SPACE — MUST REMAIN BACKGROUND\nEvery true opening, hole, cutout, split, handle gap, ring center, arch, or other\nnegative space inside or between parts of the silhouette must show the exact\nchroma background #00FF00 all the way through. Never fill negative space with\nwhite, off-white, gray, or a painted highlight. White keyline belongs only\noutside solid material, never across or inside an opening.\n\nEDGES — TECHNICAL\nClean solid white keyline 3–5 pixels wide around every outer creature\nsilhouette, fully sealing the dark line art from the green background.\n\nFORBIDDEN\nNo pose labels, text, letters, numbers, captions, watermarks, signatures,\narrows, UI, panel borders, other creatures, or copied franchise characters. No\nreal or invented logo, wordmark, emblem, sigil, badge, rune, swoosh, chevron,\nor isolated decorative symbol, including anything inherited from the reference.\n\nNEGATIVE STYLE\nNo photorealism, realistic CGI, 3D render, toy, figurine, plastic model,\nphysically based rendering, ray tracing, cinematic or volumetric lighting,\nglobal illumination, painterly art, watercolor, oil painting, pixel art, voxel\nart, low-poly 3D, overly detailed texture, excessive gradients, realistic\nanatomy, live action, sketch lines, rough pencil texture, noisy linework,\nairbrush, or glossy product render.\n"
  }
} as const;
