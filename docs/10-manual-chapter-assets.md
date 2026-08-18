# Manual Chapter Asset Generation (ChatGPT)

Dokumen ini adalah runbook developer untuk membuat aset visual chapter secara
manual di aplikasi ChatGPT, lalu menyerahkan PNG mentah ke repository agar
diproses oleh Chapter Factory. Jalur ini melengkapi generation otomatis lewat
Replicate; ia tidak menggantikan validasi, review manusia, approval, publish,
activation, atau notification gate.

## Keputusan dan batasan

- Format utama tetap **14 gambar factory-native**: 9 sheet Anima, 3 background
  zona, 1 sheet Boss Seeker, dan 1 Trophy.
- Setiap Anima dan Boss Seeker dibuat sebagai satu sheet 3×3. Kita tidak
  membuat 81 file pose terpisah karena lebih sulit menjaga identitas karakter.
- File Trophy manual berisi **Inner Core saja**. Chapter Factory mengecilkan dan
  membungkusnya dengan canonical transparent point-top Hexagonal Vessel yang
  sederhana saat post-process, sehingga Vessel identik piksel demi piksel di
  semua chapter sementara bentuk Inner Core boleh beragam.
- File hasil ChatGPT masuk ke `manual_inbox/`, bukan langsung ke `assets/`.
  Folder `assets/` hanya untuk hasil yang sudah diproses dan memiliki manifest.
- Unduh PNG asli. Jangan memakai screenshot, JPEG, upscale, crop, atau menghapus
  background sendiri.
- Aset manual harus melewati post-process, hashing, provenance, review HTML,
  dan approval yang sama seperti aset Replicate.
- Menaruh file di folder tidak pernah otomatis mem-publish chapter.
- Jangan memakai foto pemain, rahasia, API key, atau gambar franchise sebagai
  reference image.

Asumsi: ChatGPT mungkin menghasilkan ukuran selain ukuran target. Itu masih
dapat diproses jika aspect ratio dan layout benar. Kesalahan susunan sel,
karakter yang berubah antar-pose, label, grid line, atau background yang bukan
chroma green tidak dapat diperbaiki aman hanya dengan resize.

## Alur singkat

1. Pastikan `brief.json` dan `design.json` chapter sudah final. Untuk content
   version 2+, setiap cast member dan Boss Seeker wajib memiliki
   `body_height_cm` 20–2000; Boss roster tepat satu `special`, ace tidak boleh
   lebih lemah dari reguler terkuat, dan `boss.ace_passive` harus memakai
   allowlist.
2. Buka satu conversation ChatGPT baru untuk satu chapter.
3. Tempel **Prompt 0 — Style and layout lock** sekali.
4. Kirim prompt slot satu per satu. Satu prompt menghasilkan satu gambar.
5. Periksa hasil sebelum lanjut. Regenerate hanya slot yang gagal; tidak ada
   auto-retry.
6. Unduh PNG asli dan beri nama persis sesuai bagian folder di bawah.
7. Isi `generation-notes.md`.
8. Kirim handoff message yang tersedia di akhir dokumen.

Memakai satu conversation membantu warna, contour, dan rendering tetap
konsisten. Jika pindah conversation, tempel Prompt 0 lagi sebelum prompt slot.

## Prompt 0 — Style and layout lock

Tempel blok ini sebagai pesan pertama di conversation ChatGPT:

```text
We are producing original production art for Scanima, an all-ages mobile
monster adventure. Establish and preserve this visual lock for every image in
this conversation:

- original designs only; no recognizable franchise character, costume,
  device, logo, symbol, composition, or branded packaging
- shape-first original 2D monster-adventure game art with clean dark charcoal
  contours, deliberate line-weight changes, flat color hierarchy, one
  hard-edged shadow tone, and restrained highlights
- every design must remain readable after heavy downscaling; rendering supports
  the large shapes instead of compensating for a weak silhouette
- no text, letters, numbers, labels, watermark, signature, UI, border, panel
  frame, or visible grid line
- no white sticker outline or white matte keyline around foreground subjects
- keep recurring materials, palette, contour weight, and lighting direction
  consistent throughout this chapter

For every Anima sprite sheet:
- create exactly one square 1024×1024 image with a perfectly flat, opaque,
  uniform #00FF00 chroma-green background
- use an invisible 3×3 grid with equal cells and generous empty green space;
  keep every foreground pixel safely inside its own cell and away from seams
- cells left-to-right, top-to-bottom are:
  Idle, Attack, Sleep / Happy, Hungry, Dirty / Damaged, Strike VFX, Surge VFX
- the first seven cells show the same creature with identical anatomy,
  markings, palette, and scale
- in all seven character cells, the head/face or equivalent leading sensory
  plane and the whole body face forward-left toward canvas-left; never turn
  toward the viewer, sheet center, a neighboring cell, or canvas-right
- in every open-eye pose, both pupils look toward the same canvas-left target
  along the body direction; never look at the viewer, inward toward sheet
  center, outward to canvas-right, or in two different directions; Sleep keeps
  both eyes closed, while Damaged may use half-lidded eyes without changing
  their canvas-left direction
- Damaged means exhausted and defeated, with no gore
- Strike VFX and Surge VFX contain effects only, with no creature body or
  duplicated character parts
- do not use bright chroma green in the creature or either VFX

For every Boss Seeker sprite sheet:
- treat the result as an official 2D game character model sheet, not splash
  art, fashion concept art, or a glossy generative-anime illustration
- cells 1 through 8 keep one identical three-quarter forward-left orientation
  toward canvas-left: face/nose, shoulders, torso, hips, and support stance
  stay leftward; gestures may lean but never yaw right, show the back, or
  mirror asymmetrical landmarks
- cell 9 keeps that same three-quarter forward-left head, neck, nose plane, and
  diagonal shoulder angle; both eyes remain visible, but only the pupils turn
  to make direct eye contact with the player/camera
- in cell 9 the nose stays off-center and shoulders never become square;
  "Profile" is its UI pose name, not a side-profile instruction
- make the character recognizable as a solid black silhouette using one
  dominant outfit geometry, one intentional asymmetry, no more than two
  theme motifs, and zero or one command prop
- define a deliberate adult age, body build, face shape, nose, eyes, posture,
  and gesture language; never fall back to the same youthful oval anime face
- vary adult age, height, body build, face, posture, outfit archetype, and
  gesture language across chapter bosses; never make every Boss Seeker a young
  slim fashionable character
- use four to six major flat colors, economical contours, one hard cel-shadow,
  and only small controlled highlights
- build clothing from a few large intentional shapes appropriate to that
  character's role; outfits may be formal, practical, ceremonial, eccentric,
  soft, armored, or plain as long as the silhouette is unique and memorable
- express the chapter theme through shape language instead of attaching
  literal decorations everywhere
- no gradient shading, glow, bloom, rim light, glossy material rendering,
  hyper-detailed hair, random belts/straps/buckles/piping, symmetrical generic
  long coat, or repeated tiny ornaments

When a later prompt asks for a zone, keep this same cel-shaded style lock and
use that prompt's 16:9 combat-arena canvas and floor rules instead of a
chroma-green sprite sheet. When a later prompt asks for a Boss Seeker or
Trophy, follow that prompt's canvas and layout rules instead. Generate
exactly one image per request. Do not add an explanation around the image.
```

## Template reusable untuk chapter lain

Ganti semua `<PLACEHOLDER>` dari `brief.json` dan `design.json`. Untuk Anima,
kirim satu prompt per cast member.

### Template Anima

```text
Create the 3×3 Anima sprite sheet using the locked Scanima contract.

Chapter: <CHAPTER_TITLE>
Anima: <ANIMA_NAME>
Primary element: <PRIMARY_ELEMENT>
Secondary element: <SECONDARY_ELEMENT>
Core silhouette: <BODY_PLAN_AND_DISTINCT_LANDMARKS>
Main palette and materials: <PALETTE_AND_MATERIALS>
Personality: <SHORT_PERSONALITY>

Keep the body plan non-generic and unmistakable in silhouette. Preserve the
same anatomy and markings in all seven creature cells.

Facing and gaze lock: in all seven body cells, the face/leading sensory plane
and whole body point forward-left toward canvas-left. In every open-eye pose,
both pupils focus on the same canvas-left target along that body direction —
never at the viewer, sheet center, or canvas-right, and never cross-eyed. Sleep
closes both eyes. Damaged may be half-lidded but keeps the same leftward gaze.
Never mirror anatomy or swap asymmetrical landmarks between cells.

Attack move, <STRIKE_NAME>: show a compact readable physical action in the
Attack cell. Its separate Strike VFX cell contains only
<STRIKE_EFFECT_DESCRIPTION>.

Special move, <SURGE_NAME>: preserve the creature in the normal pose cells.
Its separate Surge VFX cell contains only <SURGE_EFFECT_DESCRIPTION>, larger
and more spectacular than the Strike VFX but still fully inside the cell.

The result must be one image only: square, opaque #00FF00 background, exact
cell order, no labels, no dividers, no text, no white keyline, and no
recognizable IP or branded object.
```

### Template Boss Seeker

```text
Create exactly one original Boss Seeker sprite sheet for <CHAPTER_TITLE>.

Canvas: square 1024×1024, flat opaque uniform #00FF00 background, invisible
3×3 equal grid, generous green margins, and no foreground crossing a seam.

Cells left-to-right, top-to-bottom:
1. Intro/Idle
2. Attack Command
3. Special Command
4. Switch Command
5. Concern/Hit
6. Last Anima
7. Victory
8. Defeat
9. Profile portrait

Angle lock: cells 1 through 8 always keep the same three-quarter forward-left
orientation toward canvas-left. The face/nose, shoulders, torso, hips, and
support stance remain leftward; a pose may bend or lean but must never yaw
toward canvas-right, expose the back, or mirror asymmetrical outfit details.
Cell 9 changes only the crop and gaze: make it a chest-up dialogue portrait
using the same three-quarter forward-left head, neck, nose plane, and diagonal
shoulder angle. Keep both eyes visible, but turn only the pupils to make direct
eye contact with the player/camera. The nose stays off-center and shoulders
never become square. "Profile" is the UI pose name, not a request for a
side-profile view.

Character: <BOSS_SEEKER_NAME>, <ORIGINAL_CHARACTER_DESCRIPTION>.
Background story: <FORMATIVE_EVENT_BELIEF_AND_REASON_TO_CHALLENGE_PLAYER>.
Theme motifs: <THEME_MOTIFS>.
Palette: <FOUR_TO_SIX_MAJOR_FLAT_COLORS>.
Command prop: <ZERO_OR_ONE_ORIGINAL_PROP>.

Design the silhouette first. Choose one dominant garment shape, one deliberate
asymmetry, no more than two theme motifs, and zero or one prop. State a
specific adult age range, body build, face shape, nose, eye design, posture,
and gesture language so the result cannot collapse into a default youthful
anime character. Use economical dark contours and one hard-edged cel-shadow.
Boss Seekers across chapters must vary in age, height, build, face, posture,
outfit archetype, and gesture language; the outfit does not need to be
fashionable, only unique, role-specific, and memorable.
Do not rely on gradient rendering, glow, glossy materials, decorative clutter,
random straps/buckles/piping, a symmetrical generic long coat, or many tiny
themed ornaments.

The same original all-ages character, face, hair, outfit, proportions, and prop
must remain consistent in all nine cells. Command gestures must read clearly
at mobile size. The Profile cell must work as a portrait crop. No creature,
text, logo, branded costume, recognizable franchise device, visible grid,
white matte keyline, or bright chroma-green foreground.
```

### Template zone

```text
Create exactly one original 16:9 landscape background for a Scanima
Expedition combat arena.

Chapter: <CHAPTER_TITLE>
Zone: <ZONE_TITLE>
Environment: <ENVIRONMENT_DESCRIPTION>
Palette and lighting: <PALETTE_AND_LIGHTING>
Recurring chapter motifs: <MOTIFS>

This is a Battle backdrop, not a node-map illustration. Match the chapter
Anima and Boss Seeker with a polished hand-painted 2D anime environment:
large readable shapes, six to nine harmonized color groups, clean charcoal
or plum line accents, two controlled shadow/value steps, and a restrained
second tier of material and structural detail. Keep the central combat
sightline readable without making every zone use the same layout.

Only the lower 22–26% is one continuous solid floor plane wide enough for two
fighters and a Boss Seeker. The bottom 14–18% stays unbroken across the center
60% of the width. No liquid, lava, syrup, rails, gutters, chasms, vents,
fences, or props under the fighter foot line. Keep spectacle in the middle
distance and reserve roughly the upper 40–45% for open sky. Use a distant
eye-level establishing shot with no oversized foreground floor.

Vary composition between zones: asymmetrical, depth-centered, or diagonal are
all valid. Do not default to one centered hero object; a centered composition
should use open depth and unequal framing forms. Keep the right-third lower
band uncluttered. Integrate the theme through materials and construction,
not oversized literal props or a toy-diorama look.

No photoreal or PBR rendering, glossy 3D, plastic toy rendering, airbrush
gradients, bloom, glow, steam, particle haze, repeated micro-detail, soft
focus, or fake upscale artifacts. Opaque background, no chroma green. No
character, creature, text, logo, sign lettering, watermark, UI, node icon,
or recognizable IP landmark. Generate one crisp landscape image only, using
the largest exact 16:9 output available (target 1536×864 or larger).
```

### Template Trophy

```text
Create exactly one original square Chapter Core collectible for
<CHAPTER_TITLE>.

Trophy: <CHAPTER_CORE_NAME>
Chapter palette: <FOUR_OR_FIVE_FLAT_COLORS>
Silhouette motif: <CHAPTER_SPECIFIC_PERIMETER_INSIDE_HEXAGONAL_SAFE_WINDOW>
Internal construction: <ONE_INTEGRATED_CHAPTER_SPECIFIC_CORE>
Meaning: <FIRST_CLEAR_MEANING>

Generate the chapter-specific **Inner Core only**. Chapter Factory adds the
canonical transparent `point_hex_vessel_v1` Vessel after generation; do not
draw glass, an orb, a crystal container, or any outer frame.

Use the two-layer Chapter Core v3 grammar: one centered, front-facing Inner Core
that fits safely inside the Vessel's central hexagonal window. Keep visual
weight, dark contour thickness, flat rendering, and complexity consistent
across chapters, but let this chapter use a rounded, angular, faceted, folded,
asymmetric, or otherwise unique perimeter made from a few large pinches, cuts,
lobes, points, or facet groups. The Inner Core silhouette must remain distinct
when filled solid black. Theme both its perimeter and internal construction;
never stamp a random emblem or letter onto a generic gem.

Use six to ten large color regions maximum, four or five flat colors, one hard
shadow plane, and one small highlight plane. A thematic object may inspire the
shape language, but flatten it into an original Core construction instead of
rendering a literal prop or miniature scene.

Canvas must have a perfectly flat opaque uniform #00FF00 background. Dark
contour touches green directly. No pedestal, floor shadow, glow, aura,
particles, transparent shell, miniature scene, stamped emblem, badge, medal,
coin, text, logo, watermark, white matte keyline, recognizable IP, or bright
chroma-green region. Leave generous green space around the Inner Core for the
Vessel composite. Generate one image only, target 512×512 or larger square.
```

## Prompt siap pakai — The Sugarworks v1

Kirim prompt berikut satu per satu setelah Prompt 0. Jangan meminta ChatGPT
mengubah nama, elemen, move, jumlah cast, atau urutan pose; semua itu sudah
dikunci oleh `design.json`.

### 1. Gellume

Simpan sebagai `animas/sugarworks-gumdrop.png`.

```text
Create the locked 3×3 Anima sprite sheet for Gellume in The Sugarworks.

Design an original compact gumdrop monster with a low rounded-triangle
silhouette, translucent raspberry-pink candy flesh, darker berry core,
scattered faceted sugar-crystal freckles, two short springy legs, and two
stubby elastic arms. Give it a mischievous face embedded naturally in the
front surface, not a mask or device. It should feel energetic and common but
not disposable or generic.

Primary element: Food. Secondary element: Spark.
Attack, Sugar Jab: a quick forward-left crystal-knuckle jab.
Strike VFX only: a tight burst of three pink sugar shards and a small golden
electric snap.
Special, Candy Burst.
Surge VFX only: a round raspberry candy shockwave with faceted sugar fragments
and violet-gold sparks.

Preserve identical crystals, core shape, anatomy, and proportions in all seven
body cells. In every body cell, the face and body point forward-left toward
canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 2. Velastra

Simpan sebagai `animas/sugarworks-taffy.png`.

```text
Create the locked 3×3 Anima sprite sheet for Velastra in The Sugarworks.

Design an original agile taffy monster with a narrow amber-orange torso,
two long ribbon-like elastic arms, short bent legs, and one braided taffy tail
that creates a clear diagonal silhouette. Its glossy stretched bands reveal
warm coral and honey layers. The face is small, alert, and naturally formed in
the upper torso. Avoid humanoid clothing and avoid wrapped-candy packaging.

Primary element: Food. Secondary element: Flow.
Attack, Stretch Snap: one elastic arm snaps forward-left and recoils.
Strike VFX only: a narrow amber whip arc with two elastic speed rings.
Special, Taffy Whip.
Surge VFX only: a broad spiraling ribbon lash of amber, coral, and honey,
without any body parts.

Keep the braid, stripe order, anatomy, and body volume identical in all seven
body cells. In every body cell, the face and body point forward-left toward
canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 3. Noxcoil

Simpan sebagai `animas/sugarworks-licorice.png`.

```text
Create the locked 3×3 Anima sprite sheet for Noxcoil in The Sugarworks.

Design an original serpentine monster built from three interwoven matte
black-violet licorice cords. Give it a coiled lower body, two hooked rope arms,
a raised head segment, magenta inner bands, and small glossy berry-red sensory
nodes. Preserve enough violet highlights that details remain visible against
the dark contour. Do not make it a normal snake and do not use packaging.

Primary element: Toxin. Secondary element: Food.
Attack, Twist Lash: one hooked cord arm whips forward-left.
Strike VFX only: a sharp violet-black braided lash arc with magenta droplets.
Special, Dark Drizzle.
Surge VFX only: a contained spiral rain of glossy dark syrup and violet toxic
mist, without the creature.

Keep cord count, braid pattern, nodes, and silhouette identical in all seven
body cells. In every body cell, the face and body point forward-left toward
canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 4. Cindrusk

Simpan sebagai `animas/sugarworks-caramel.png`.

```text
Create the locked 3×3 Anima sprite sheet for Cindrusk in The Sugarworks.

Design an original stocky armored candy monster with a glowing molten-caramel
core protected by cracked hard-caramel plates. Use a broad beetle-like chest,
four sturdy asymmetrical limbs, a low shielded head, amber glass edges, and
small dark toasted seams. Keep every drip attached to the silhouette and away
from cell boundaries. It must not resemble a normal animal or a machine.

Primary element: Food. Secondary element: Flame.
Attack, Shell Crack: a heavy plated shoulder strike toward forward-left.
Strike VFX only: a compact amber impact fracture with three caramel chips.
Special, Molten Coat.
Surge VFX only: a bright amber-orange molten ring with hard-candy plate
fragments, no creature body.

Keep plate count, crack pattern, core placement, and anatomy identical in all
seven body cells. In every body cell, the face and body point forward-left
toward canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 5. Rimespin

Simpan sebagai `animas/sugarworks-peppermint.png`.

```text
Create the locked 3×3 Anima sprite sheet for Rimespin in The
Sugarworks.

Design an original frost-candy monster with an offset radial peppermint-disc
torso, dark contour, crimson and ivory spiral plates, a small icy-blue core,
two ribbon-like frost arms, and three short shard legs. Break the perfect
circle with one raised plate and an asymmetric trailing ribbon so the
silhouette is distinctive. Ivory is body material, not an outer white
keyline. Use no green foreground.

Primary element: Frost. Secondary element: Air.
Attack, Mint Slice: one frost ribbon makes a forward-left cutting motion.
Strike VFX only: a thin crimson-ivory crescent with pale-blue ice splinters.
Special, Cold Ribbon.
Surge VFX only: a wide helix of pale-blue wind, peppermint-red accents, and
frost crystals, without the creature.

Keep spiral direction, plate count, core, anatomy, and palette identical in all
seven body cells. In every body cell, the face and body point forward-left
toward canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 6. Pralith

Simpan sebagai `animas/sugarworks-nougat.png`.

```text
Create the locked 3×3 Anima sprite sheet for Pralith in The Sugarworks.

Design an original broad guardian monster formed from warm cream nougat
blocks, with embedded amber and cocoa geometric inclusions, two massive
forearms, two short stable legs, a recessed face, and one offset honey-crystal
crest. Its silhouette should feel protective and heavy without human armor,
a sword, heraldry, or a shield prop.

Primary element: Food. Secondary element: Stone.
Attack, Block Bash: a compact forearm body-check toward forward-left.
Strike VFX only: a cream-and-amber block impact with small angular crumbs.
Special, Honey Guard.
Surge VFX only: a thick hexagonal amber barrier flare with warm honey light,
without the creature.

Keep inclusion placement, crest, block shapes, and anatomy identical in all
seven body cells. In every body cell, the face and body point forward-left
toward canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 7. Duskadon

Simpan sebagai `animas/sugarworks-fudge.png`.

```text
Create the locked 3×3 Anima sprite sheet for Duskadon in The Sugarworks.

Design an original crouched cocoa monster with a powerful quadrupedal wedge
silhouette, layered dark-fudge plates, two angular chocolate fangs, bronze
metallic seams, a compact tail blade made of hardened fudge, and glowing
amber eyes. It may feel predatory but remains all-ages, stylized, and clearly
a confection creature rather than a real animal. No wrapper or brand marks.

Primary element: Food. Secondary element: Metal.
Attack, Cocoa Claw: one plated forelimb slashes forward-left.
Strike VFX only: three short cocoa-brown claw arcs with bronze sparks.
Special, Bitter Surge.
Surge VFX only: a dense dark-cocoa energy wave with bronze geometric
fragments and amber highlights, without the creature.

Keep plates, fang shape, seams, eyes, and anatomy identical in all seven body
cells. In every body cell, the face and body point forward-left toward
canvas-left. Every open-eye pose uses two pupils focused on the same
canvas-left target, never at the viewer, sheet center, canvas-right, or in
different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 8. Ambermire

Simpan sebagai `animas/sugarworks-syrup.png`.

```text
Create the locked 3×3 Anima sprite sheet for Ambermire in The Sugarworks.

Design an original semi-fluid amber guardian with a tall droplet-shaped torso,
a crown-like splash frozen into its head silhouette, two thick liquid arms,
three stable pooled feet, suspended golden bubbles inside the body, and a dark
caramel core visible through the translucent syrup. Keep all puddles and drips
attached and safely inside each cell. Do not use a bottle, label, or packaging.

Primary element: Flow. Secondary element: Food.
Attack, Sticky Bind: one liquid arm loops forward-left like a binding cord.
Strike VFX only: a compact amber syrup loop with three suspended droplets.
Special, Golden Flood.
Surge VFX only: a broad golden wave crest with caramel bubbles and flowing
light, without the creature.

Keep bubble positions, core, splash crown, anatomy, and body volume consistent
in all seven body cells. In every body cell, the face and body point
forward-left toward canvas-left. Every open-eye pose uses two pupils focused on
the same canvas-left target, never at the viewer, sheet center, canvas-right,
or in different directions; Sleep closes both eyes and Damaged keeps the same
leftward gaze even if half-lidded. Never mirror anatomy. One image only; exact
locked layout and chroma background.
```

### 9. Nimbelisk

Simpan sebagai `animas/sugarworks-cotton.png`.

```text
Create the locked 3×3 Anima sprite sheet for Nimbelisk, the unique special
Anima of The Confectioner in The Sugarworks.

Design an original airborne storm monster with an asymmetric manta-like body
made from tightly spun cotton-candy fibers, a deep indigo core, raspberry and
pale-cyan cloud lobes, four swept-back sugar-filament fins, two needle-like
sensory spines, and a luminous eye set into the core. It must look rarer,
faster, and more formidable than the other cast while remaining all-ages.
Do not make a normal cloud with a face.

Primary element: Air. Secondary element: Food.
Attack, Cloud Needle: the sensory spines aim in a fast forward-left dive.
Strike VFX only: a thin pale-cyan pressure needle with raspberry fiber trails.
Special, Spun Tempest.
Surge VFX only: a large contained cotton-candy cyclone of cyan, raspberry, and
indigo fibers with a hollow center, without the creature.

Keep core, lobe count, fin arrangement, spines, and anatomy identical in all
seven body cells. In every body cell, the eye/core sensory focus, leading plane,
and whole body point forward-left toward canvas-left. Every open-eye pose
focuses on the same canvas-left target, never at the viewer, sheet center, or
canvas-right; Sleep closes the eye and Damaged keeps the same leftward focus
even if half-lidded. Never mirror anatomy. One image only; exact locked layout
and chroma background.
```

### 10. Zone 1 — Gumdrop Yard

Simpan sebagai `zones/zone-1.png`.

```text
Create exactly one original 16:9 landscape background for The Sugarworks,
Zone 1: Gumdrop Yard.

Show an open candy-brick storage courtyard from a distant eye-level camera.
Reserve the upper 40–45% for clear morning sky and only the lower 22–26% for
a continuous solid floor. Cluster monumental gumdrop silos left of center,
place low warehouses farther away on the opposite side, and preserve an
irregular open view through the middle. Any syrup stays sealed inside tanks
or pipes, never as open runnels, gutters, or puddles underfoot.

Use a polished hand-painted 2D anime environment style with six to nine
harmonized raspberry, amber, ivory, and muted-mint color groups, two
controlled value steps, selective material texture, and crisp native-
resolution edges. Keep the right-third lower band clear for a Boss Seeker.
Avoid a toy diorama, oversized literal candy props, soft focus, glossy 3D,
bloom, glow, steam, repeated micro-detail, characters, text, logos, UI, or
recognizable IP. Generate one opaque landscape image at the largest exact
16:9 output available.
```

### 11. Zone 2 — Caramel Foundry

Simpan sebagai `zones/zone-2.png`.

```text
Create exactly one original 16:9 landscape background for The Sugarworks,
Zone 2: Caramel Foundry.

Show a refractory foundry from a distant eye-level camera. Reserve the upper
40–45% for open readable sky and only the lower 22–26% for a continuous
dark-cocoa brick or caramel-slab work floor. Use a depth-centered industrial
aisle: the eye travels through an open central corridor framed by unequal
foundry structures on both sides, with no single center object and no
mirrored symmetry. Vats, conveyor bridges, amber pipes, and cooling racks
stay behind a low guard wall, never cutting the arena with molten channels.

Use a polished hand-painted 2D anime environment style with six to nine
harmonized warm color groups, two controlled value steps, selective material
texture, and crisp native-resolution edges. Escalation comes from warmer
light and larger industrial silhouettes, not detail soup. Keep the
right-third lower band clear. Avoid a toy diorama, soft focus, glossy 3D,
bloom, glow, steam, characters, text, logos, UI, or recognizable IP.
Generate one opaque landscape image at the largest exact 16:9 output.
```

### 12. Zone 3 — Peppermint Furnace

Simpan sebagai `zones/zone-3.png`.

```text
Create exactly one original 16:9 landscape background for The Sugarworks,
Zone 3: Peppermint Furnace.

Show a broad peppermint-stone or candy-brick boss forecourt from a distant
eye-level camera. Reserve the upper 40–45% for open sky and only the lower
22–26% for continuous solid ground. Step crimson-and-ivory furnace towers,
frost-lined cooling stacks, and a distant sealed boss gate across different
depths on a gentle diagonal; do not place one hero object on a center
pedestal. Frost and heat stay in background machinery. No chasms, lava pits,
ice rivers, vapor carpets, or vents underfoot.

Use a polished hand-painted 2D anime environment style with six to nine
harmonized color groups, two controlled value steps, selective material
texture, and crisp native-resolution edges. Keep the right-third lower band
clear for a Boss Seeker. Avoid a toy diorama, oversized literal candy props,
soft focus, glossy 3D, bloom, glow, steam, characters, text, logos, UI, or
recognizable IP. Generate one opaque landscape image at the largest exact
16:9 output available.
```

### 13. Boss Seeker — The Confectioner

Simpan sebagai `boss/confectioner-seeker.png`.

```text
Create exactly one original 3×3 Boss Seeker sprite sheet for The Confectioner,
the commander of The Sugarworks.

Canvas: square 1024×1024, perfectly flat opaque uniform #00FF00 background,
invisible equal 3×3 grid, generous green margins, no foreground crossing
seams, no visible dividers.

Cells left-to-right, top-to-bottom:
1. Intro/Idle: upright appraising stance, closed folio resting at one hip
2. Attack Command: open folio under one arm, precise two-finger forward cue
3. Special Command: folio opened wide, decisive page-turn gesture
4. Switch Command: snapping the folio closed while the free hand redirects
5. Concern/Hit: balance broken, closed folio held protectively to the chest
6. Last Anima: focused low stance, folio open to its final blank page
7. Victory: measured nod while calmly closing the folio
8. Defeat: kneeling but unharmed, closed folio placed on the floor beside her
9. Profile/Dialogue: chest-up at the same three-quarter forward-left angle,
   both eyes visible, pupils making direct eye contact with the player, nose
   off-center, shoulders diagonal, and one folio corner visible

Angle lock: cells 1 through 8 keep the exact same three-quarter forward-left
orientation toward canvas-left. Her nose, face plane, shoulders, torso, hips,
feet, and asymmetric left cape stay consistently oriented and never swap
sides. Poses may lean, kneel, or move their arms, but she must never turn
toward canvas-right, face directly forward, expose her back, or become mirrored
in those eight cells. Cell 9 preserves the same head, neck, nose plane, and
diagonal shoulder angle; both eyes remain visible while only the pupils turn to
meet the player. Keep her nose off-center and never square her shoulders.
"Profile" names the UI slot; do not draw a side-profile or front-facing
passport portrait.

Background story: at twenty-three, The Confectioner became the Sugarworks'
youngest archive curator after reconstructing recipes damaged in a furnace
failure. She treats every recipe and Anima as living evidence, and challenges
Seekers to prove that improvisation deserves a place beside tradition. Her
calm authority comes from observation and exact judgment, not age or physical
size.

Character design: an original twenty-three-year-old woman with a short compact
build, upright appraising posture, and all-ages non-sexualized presentation.
Give her a soft-square face, hooded almond eyes, blunt eyebrows, a straight
nose, and a controlled expression that looks analytical rather than cute. Her
dark-plum hair is a crisp inverted bob with one long side lock, creating one
clear asymmetry without glossy individual strands.

Her dominant silhouette is an ivory knee-length bell coat-dress. Its hem uses
exactly four large angular folded-wrapper panels, not frills or tiny pleats. A
short dark-plum shoulder cape falls visibly longer only on her left side, while
a clean raspberry center panel keeps the torso readable. Use fitted plum
leggings and amber ankle boots. One oversized flat amber archive-seal clasp is
the outfit's only focal ornament. The confectionery theme comes from large
folded-wrapper construction and layered archive-box shapes, never from candy
pieces pasted onto clothing.

Her only prop is one octagonal dark-plum recipe folio with broad flat amber
corners and one muted-mint closure band. Its cover and pages contain no writing,
letters, symbols, logo, glow, or floating effects. It is a substantial archive
book, not a kitchen tool, wand, weapon, capture device, tablet, or branded
object. Preserve its exact octagonal shape and color blocking in every cell.

Use exactly six major flat color groups: dark plum, ivory, raspberry, amber,
muted mint, and her skin tone. Use economical dark contours, one hard-edged
cel-shadow, and tiny controlled highlights. Her complete silhouette must be
recognizable when filled black. Treat this as an official 2D game character
model sheet, not splash art, fashion concept art, or a glossy generative-anime
illustration.

No whisk, baton, scarf, giant bow, generic long coat, candy jewelry, head
ornament, random belt, strap, buckle, piping, gradient, glow, bloom, rim light,
glossy material rendering, or repeated decorative clutter. Keep the same face,
hair, bell coat-dress, four wrapper panels, asymmetric cape, body proportions,
palette, and folio in all nine cells. Gestures must read at mobile size; the
Profile cell must work as a portrait crop. No Anima, food package, text, logo,
recognizable franchise costume/device, white matte keyline, or bright
chroma-green foreground. Generate one image only.
```

### 14. Trophy — Sugarfold Core

Simpan sebagai `trophy/sugarworks-trophy.png`.

```text
Create exactly one original square **Inner Core** for the Sugarfold Core,
awarded for defeating The Confectioner and clearing The Sugarworks. Generate
the Inner Core only. Chapter Factory adds the canonical transparent
point-top Hexagonal Vessel after generation; do not draw the Vessel, glass, orb,
crystal shell, container, or outer frame.

Use the two-layer Chapter Core v3 grammar. Center one front-facing Inner Core
inside the Vessel's central hexagonal safe window, but do not imitate the
Vessel's regular hexagonal contour. Its unique perimeter has one broad shallow concave
wrapper-pressure pinch on the left and one matching pinch on the right. Keep
the top and bottom as short clipped points. These two side pinches must remain
visible when the complete Inner Core silhouette is filled solid black.

Construct the whole Core from four large raspberry corner facets that
structurally hold one amber central lozenge. One broad ivory fold enters from
one side and one broad muted-mint fold enters from the opposite side; both
connect the outer perimeter to the amber lozenge. They are separate opposing
structural folds, not one continuous ribbon, letter, logo, or symbol. Do not
place a badge or emblem on top of a generic gem.

Use exactly five flat color groups: dark berry contour/shadow, raspberry,
amber, ivory, and muted mint. Limit the entire design to eight to ten large
color regions, one hard shadow plane, and one small flat highlight plane. The
result should suggest compressed candy glass and folded wrapper pressure
through abstract geometry, not by drawing a literal candy or wrapper icon.

Use opaque flat cel shading, not realistic transparent crystal rendering.
Canvas must be square with a perfectly flat opaque uniform #00FF00 background,
and the dark contour must touch green directly. Leave generous green margins
so the Inner Core can be scaled into the Vessel. No glass shell, orb, crystal
container, outer frame, pedestal, stand, floor shadow, aura, glow, particle,
sparkle, star, sprinkle, drip, attached object, whisk, utensil, furnace,
miniature scene, text, letter, symbol, logo, plaque, badge, emblem, medal, coin,
watermark, white matte keyline, recognizable IP, or bright chroma-green region.
Generate one image only, target 512×512 or larger square.
```

## Lokasi file hasil ChatGPT

Untuk The Sugarworks, buat struktur berikut. `manual_inbox` adalah area handoff
sementara dan aman; jangan menimpa output di `assets/`.

```text
backend/chapters/the-sugarworks/v1/manual_inbox/
├── generation-notes.md
├── animas/
│   ├── sugarworks-gumdrop.png
│   ├── sugarworks-taffy.png
│   ├── sugarworks-licorice.png
│   ├── sugarworks-caramel.png
│   ├── sugarworks-peppermint.png
│   ├── sugarworks-nougat.png
│   ├── sugarworks-fudge.png
│   ├── sugarworks-syrup.png
│   └── sugarworks-cotton.png
├── zones/
│   ├── zone-1.png
│   ├── zone-2.png
│   └── zone-3.png
├── boss/
│   └── confectioner-seeker.png
└── trophy/
    └── sugarworks-trophy.png
```

Jika ada beberapa candidate, file pilihan tetap memakai nama canonical di
atas. Candidate lain boleh diletakkan di
`manual_inbox/_alternates/<slot-name>/`; sebutkan pilihan final di notes.

Untuk chapter lain, gunakan:

```text
backend/chapters/<chapter-slug>/v<content-version>/manual_inbox/
```

Nama 9 Anima, Boss Seeker, dan Trophy harus diambil dari `design.json`; nama
zona tetap `zone-1.png`, `zone-2.png`, dan `zone-3.png`.

### Template `generation-notes.md`

```markdown
# Manual generation notes

- Provider: ChatGPT image generation
- Generated by: <nama operator>
- Generated at: <tanggal dan timezone>
- Conversation: <nama/penanda lokal; jangan tempel private share URL>
- External reference images: none
- Manual edits after download: none

## Selected slots

- anima:<id> — first result / regenerated once because <reason>
- zone:1 — first result
- boss_seeker — selected candidate 2 because <reason>
- trophy — first result

## Known concerns

- <kosong jika tidak ada>
```

Jangan masukkan token, email pribadi, ChatGPT share link privat, atau informasi
akun ke notes.

## Checklist sebelum handoff

Untuk seluruh file:

- format PNG asli dan dapat dibuka;
- 14 file canonical tersedia;
- tidak ada teks, logo, watermark, signature, atau recognizable IP;
- tidak memakai screenshot atau JPEG yang diubah nama;
- tidak ada gambar pemain atau reference image berhak cipta.

Untuk 9 Anima:

- satu sheet persegi dengan susunan 3×3 yang benar;
- tujuh pose memperlihatkan karakter yang sama;
- Strike VFX dan Surge VFX tidak memuat tubuh karakter;
- tidak ada label, border, atau grid line;
- foreground tidak menyentuh atau melintasi seam;
- background flat `#00FF00`, bukan transparan atau gradient;
- tidak ada white sticker outline dan tidak ada foreground chroma-green.

Untuk Boss Seeker:

- sembilan pose tepat dan urut;
- wajah, pakaian, prop, dan proporsi konsisten;
- gesture command terbaca dan Profile cocok sebagai portrait;
- background serta seam mengikuti aturan sheet;
- manifest hasil proses memiliki `render_metrics.reference_height_px` dan
  `reference_width_px` dari bbox opak Intro/Idle, bukan ukuran frame.

Untuk zona:

- landscape 16:9, opaque, dan tanpa karakter/UI;
- style cel-shaded yang sama dengan Anima/Boss Seeker, bukan render 3D glossy;
- lantai padat kontinu di 30–35% bawah, tanpa cairan/rel/jurang di bawah kaki;
- detail cukup untuk identitas zona, tidak sampai mendistrak pertarungan;
- Zone 1 → 3 terasa satu chapter dengan escalation palet dan siluet, bukan noise.

Untuk Trophy:

- raw PNG memuat satu Inner Core tanpa Vessel, pedestal, atau objek lain;
- Inner Core muat dalam central hexagonal safe window, tetapi bentuk luarnya boleh
  beragam dan tetap khas saat siluet diisi hitam;
- 6–10 region besar, 4–5 warna flat, dan internal construction terintegrasi;
- motif membentuk perimeter dan bagian dalam, bukan emblem yang ditempel;
- tidak ada glass/orb/container, glow, particle, transparency, atau miniatur scene;
- final preview menunjukkan Inner Core dibungkus point-top Hexagonal Vessel yang sama;
- Inner Core dan final composite sama-sama terbaca kecil;
- background flat `#00FF00`.

## Handoff ke coding agent

Setelah semua file diletakkan, kirim:

```text
Semua 14 raw asset manual untuk The Sugarworks v1 sudah ada di
backend/chapters/the-sugarworks/v1/manual_inbox/.
Tolong ingest jalur manual: pertahankan raw, validasi seluruh slot,
post-process/slice, catat provenance ChatGPT manual, rebuild manifest dan
review.html, lalu laporkan slot yang lolos/gagal. Jangan approve, publish,
activate, atau kirim push.
```

Agent kemudian harus:

1. mencocokkan file dengan `brief.json` dan `design.json`;
2. mempertahankan bytes mentah sebelum perubahan;
3. menolak file hilang, rusak, layout salah, atau foreground berbahaya;
4. resize dan chroma-key dengan aturan canonical;
5. segment 9 sheet Anima, membangun manifest Boss, memproses Trophy, dan
   menormalisasi tiga zona;
6. mencatat hash serta provenance `manual_chatgpt` tanpa memalsukan prediction
   ID atau cost ledger Replicate;
7. rebuild `chapter.manifest.json` dan `review.html`;
8. menjalankan selftest serta review visual;
9. berhenti sebelum approval/publish.

Perintahnya:

```bash
# validasi dan post-process di memory; tidak menulis output
node backend/tools/chapter_factory.mjs \
  --chapter-dir=backend/chapters/the-sugarworks/v1 ingest-manual

# tulis hanya setelah seluruh slot yang dipilih lolos
node backend/tools/chapter_factory.mjs \
  --chapter-dir=backend/chapters/the-sugarworks/v1 ingest-manual --apply

# bangun ulang sheet/manifest Boss dari raw yang sudah dibayar, tanpa model call
node backend/tools/chapter_factory.mjs \
  --chapter-dir=backend/chapters/<slug>/v<version> reprocess-boss --apply

# bangun ulang ketiga backdrop dari raw tanpa model call. Crop 16:9 tidak lagi
# dipaksa turun ke 768×432; resolusi sumber dipertahankan sampai batas 2048 px.
node backend/tools/chapter_factory.mjs \
  --chapter-dir=backend/chapters/<slug>/v<version> reprocess-zones --apply
```

Gunakan `--slots=anima:<id>,zone:1,...` untuk ingest parsial setelah preview
melaporkan slot gagal. Satu invocation bersifat all-or-nothing: jika satu slot
pilihan gagal, tidak ada asset, manifest, review, atau provenance yang ditulis.
Output `passed` berisi manual input yang lolos, `failed` berisi slot yang harus
diperbaiki, dan `skipped` berisi slot production yang sudah dipenuhi jalur lain
seperti Replicate.

Jika reviewer manusia memilih cleanup untuk fragmen Attack yang benar-benar
terlepas ke sel Idle, jalankan ulang slot itu dengan
`--cleanup-seams=anima:<id>`. Opsi ini tidak melonggarkan gate atau mengubah raw:
ia menghapus hanya connected component yang dilaporkan detector, mencatat jumlah
component/piksel di manifest dan provenance, lalu menjalankan seam audit ulang.
Jangan memakai opsi ini tanpa keputusan reviewer.

Approval tetap harus diberikan manusia bernama setelah membuka review HTML.
Publish, activation, dan chapter push selalu merupakan perintah terpisah dengan
gate eksplisit.
