# Monster Camera --- Anime Cel-Shaded Style Guide

## Purpose

This document defines the **visual generation contract** for the
camera-to-monster feature.

The game takes a real-world object captured by the camera and transforms
it into a creature-monster suitable for a Tamagotchi-like game.

The object validation / gating step is handled separately by the
existing Gemini 2.5 Flash vision pipeline. **Do not modify, duplicate,
or bypass that validation system as part of this style implementation.**

This guide is specifically for the **image-generation prompt layer**
that runs after an object has already been accepted.

The core goal is:

> Different real-world objects should become different monsters, while
> all monsters still look like they belong to the same game.

Examples:

-   computer mouse → mouse-like monster
-   cup → cup-like monster
-   keyboard → keyboard-like monster
-   backpack → backpack-like monster
-   controller → controller-like monster

The subject changes. The **visual language does not**.

------------------------------------------------------------------------

# 1. Visual Identity

The target style is:

**2D Japanese anime creature design + clean cel shading +
cute-but-fierce monster design + polished game character illustration.**

It should feel like a creature from an anime-inspired monster-collecting
game.

It should NOT feel like:

-   a photorealistic CGI creature
-   a 3D game asset render
-   a toy or figurine
-   pixel art
-   realistic concept art
-   painterly fantasy illustration
-   generic AI anime art

The most important visual characteristics are:

1.  Strong silhouette
2.  Clean anime linework
3.  Flat base colors
4.  Crisp cel-shaded shadows
5.  Slightly exaggerated creature anatomy
6.  Expressive face
7.  Clear relationship between the original object and the monster
    design
8.  Consistent character proportions across poses
9.  Simple, readable shapes
10. Polished game-art presentation

------------------------------------------------------------------------

# 2. Style DNA

Every generation should inherit the following style DNA.

## Linework

Use:

-   clean
-   confident
-   controlled
-   moderately bold
-   graphic
-   black or very dark colored outlines

Avoid:

-   sketchy lines
-   rough pencil texture
-   extremely thin outlines
-   painterly edges
-   noisy linework

Preferred prompt language:

> clean confident anime linework, bold graphic contours, controlled
> outlines, crisp edges

------------------------------------------------------------------------

# 3. Rendering

The rendering is **2D cel shading**, not physically based rendering.

Use:

-   flat base colors
-   one primary shadow layer
-   optional secondary darker shadow
-   crisp shadow boundaries
-   small controlled highlights
-   limited gradients

Preferred prompt language:

> flat base colors, crisp 2--3 level cel shading, hard-edged anime
> shadows, controlled highlights, minimal gradients

The image should look illustrated rather than rendered.

### Important

Do NOT ask for:

> realistic lighting\
> physically accurate materials\
> cinematic volumetric lighting\
> photorealistic reflections\
> realistic skin/fur/material rendering\
> global illumination\
> ray tracing

These terms push the generation toward 3D realism.

------------------------------------------------------------------------

# 4. Shape Language

The creature should be built from simple, readable shapes.

Use:

-   rounded masses
-   chunky anatomy
-   exaggerated limbs
-   strong silhouettes
-   simplified details
-   readable appendages
-   stylized proportions

The creature can be cute, but should have enough visual personality to
feel like a monster rather than a mascot.

Preferred prompt language:

> simplified stylized forms, strong readable silhouette, compact
> creature proportions, slightly exaggerated anatomy, appealing monster
> design

------------------------------------------------------------------------

# 5. Object-to-Creature Transformation

This is one of the most important rules.

The monster should **not simply be an object with eyes and arms attached
to it**.

Instead, the object's physical characteristics should become part of the
creature's anatomy and design language.

For example, a computer mouse might become:

-   mouse shell → creature body
-   scroll wheel → horn / crest / spine detail
-   cable → tail
-   USB connector → tail tip / weapon / stinger
-   side texture → scales / markings
-   buttons → armor plates
-   ergonomic curves → body silhouette

A cup might become:

-   cup → torso
-   lid → head armor
-   straw → horn / antenna / tail
-   liquid → internal energy
-   printed graphics → body markings
-   handle → arm / tail / wing

A keyboard might become:

-   keyboard body → armored torso
-   keys → teeth / scales / armor plates
-   cable → tail
-   key legends → markings
-   function keys → decorative armor

The object must remain recognizable.

### Core rule

> Preserve the object's most distinctive physical features, but
> reinterpret them as creature anatomy, armor, markings, limbs, tails,
> weapons, or accessories.

------------------------------------------------------------------------

# 6. Recognizability Priority

The generated monster should still clearly communicate:

> "This monster came from THAT object."

Use the following priority order:

### Priority 1 --- Silhouette

The overall shape should retain recognizable characteristics from the
original object.

### Priority 2 --- Signature features

Preserve approximately 3--6 distinctive features.

### Priority 3 --- Color identity

Retain the dominant colors when they contribute strongly to object
recognition.

### Priority 4 --- Surface details

Use smaller visual details as creature markings, armor, scales,
patterns, etc.

Do not preserve every tiny detail.

Too much literal replication makes the creature look like a decorated
object instead of a character.

------------------------------------------------------------------------

# 7. Creature Personality

The object should influence personality where possible.

Examples:

  Object         Possible personality
  -------------- -------------------------------
  Gaming mouse   aggressive, fast, mischievous
  Coffee cup     sleepy, cozy, friendly
  Keyboard       energetic, technical, nervous
  Backpack       adventurous, reliable
  Controller     playful, competitive
  Desk lamp      curious, observant
  Camera         watchful, mysterious
  Headphones     energetic, music-loving

Personality should be expressed primarily through:

-   eyes
-   eyebrows / eye shape
-   mouth
-   posture
-   limb position
-   silhouette

Do not rely only on decorative effects.

------------------------------------------------------------------------

# 8. Facial Design

Faces should use an anime-inspired creature language.

Preferred:

-   expressive large or stylized eyes
-   strong eye shapes
-   readable pupils
-   expressive mouth
-   simple facial features
-   clear emotional states

The eyes should remain visually consistent between the four states.

The character may become more aggressive in battle, but the underlying
eye design should remain identifiable.

Avoid overly human facial anatomy.

------------------------------------------------------------------------

# 9. Four Required States

The generated character has four canonical states.

The same creature must appear in all four.

## IDLE

Purpose:

Show the creature's default personality.

Characteristics:

-   relaxed standing pose
-   neutral or mildly expressive face
-   balanced silhouette
-   no major effects
-   full body visible

Prompt:

> relaxed neutral idle pose, natural stance, calm expression, clear
> readable silhouette

------------------------------------------------------------------------

## BATTLE

Purpose:

Show the creature's energetic combat personality.

Characteristics:

-   dynamic pose
-   stronger facial expression
-   aggressive or determined eyes
-   limbs extended or positioned dynamically
-   slight action effects if appropriate

Possible effects:

-   motion lines
-   sparks
-   dust
-   small debris
-   energy accents

Keep effects subordinate to the character.

Prompt:

> dynamic battle pose, energetic action stance, fierce expressive face,
> exaggerated movement, restrained anime action effects

Do not turn every monster into an explosion.

------------------------------------------------------------------------

## SLEEP

Purpose:

Show a cute, peaceful state.

Characteristics:

-   relaxed body
-   closed eyes
-   curled or lowered posture
-   peaceful expression
-   subtle Z symbols

Prompt:

> cute peaceful sleeping pose, relaxed body, closed eyes, soft
> expression, small floating Z symbols

The sleep state should remain clearly recognizable as the same
character.

------------------------------------------------------------------------

## DAMAGED

Purpose:

Communicate that the monster has taken damage without redesigning it.

Characteristics:

-   same body
-   same proportions
-   same colors
-   same face design
-   visible cracks / scratches / dents
-   small bandages where appropriate
-   tired or pained expression
-   subtle debris or loose parts

Possible damage should relate to the object.

Examples:

Mouse:

-   cracked shell
-   damaged cable
-   exposed wires
-   loose USB connector

Cup:

-   cracked ceramic
-   spilled liquid
-   chipped lid

Keyboard:

-   broken keys
-   cracked chassis
-   exposed wiring

Prompt:

> damaged but recognizable version of the same character, visible cracks
> and scratches, small object-specific damage, exhausted expression

Do not completely destroy the character.

------------------------------------------------------------------------

# 10. Character Consistency

The four states are not four separate character designs.

They are:

> ONE CHARACTER shown in four different conditions.

Maintain:

-   identical body proportions
-   identical head/body relationship
-   identical color palette
-   identical markings
-   identical facial structure
-   identical signature object features
-   identical accessories
-   identical anatomy

Only change:

-   pose
-   expression
-   state-specific effects
-   condition/damage

This is especially important for downstream game use.

------------------------------------------------------------------------

# 11. Composition

The default presentation is a clean 2×2 character sheet.

Layout:

``` text
┌───────────────┬───────────────┐
│               │               │
│     IDLE      │    BATTLE     │
│               │               │
├───────────────┼───────────────┤
│               │               │
│     SLEEP     │    DAMAGED    │
│               │               │
└───────────────┴───────────────┘
```

Requirements:

-   pure or near-white background
-   equal spacing
-   consistent character scale
-   full body visible
-   no cropping
-   no environment
-   no decorative frame
-   minimal visual clutter

Labels:

``` text
IDLE
BATTLE
SLEEP
DAMAGED
```

Use simple dark typography.

------------------------------------------------------------------------

# 12. Background

Default:

> clean white background

Avoid:

-   environmental backgrounds
-   rooms
-   landscapes
-   dramatic scenery
-   gradients
-   complex shadows
-   decorative backgrounds

A subtle grounding shadow is acceptable if it helps the character feel
planted.

------------------------------------------------------------------------

# 13. Color Strategy

The object's original color identity should influence the monster.

Do not automatically make every creature black, colorful, or neon.

Use:

-   original dominant colors
-   darker versions for shadows
-   lighter versions for highlights
-   1--2 optional accent colors

The final palette should remain relatively compact.

A useful rule:

> Dominant object colors should occupy most of the character; accent
> colors should communicate personality or special features.

------------------------------------------------------------------------

# 14. Effects

Effects should support the character rather than overpower it.

Good:

-   small sparks
-   restrained energy glow
-   motion lines
-   small debris
-   subtle dust
-   tiny magical particles

Avoid:

-   huge explosions
-   excessive particle effects
-   giant aura
-   full-screen effects
-   effects hiding the character

The character is always the primary visual element.

------------------------------------------------------------------------

# 15. Negative Style Constraints

Always include a negative-style block equivalent to:

> photorealistic, realistic CGI, 3D render, toy, figurine, plastic
> model, physically based rendering, ray tracing, realistic materials,
> cinematic lighting, volumetric lighting, painterly, watercolor, oil
> painting, pixel art, voxel art, low-poly 3D, overly detailed textures,
> excessive gradients, realistic anatomy, live-action

The purpose is not to reject content.

It is to prevent the visual style from drifting away from the game's
established 2D anime identity.

------------------------------------------------------------------------

# 16. Recommended Prompt Architecture

Do NOT generate the entire prompt from scratch for every object.

Use a stable prompt template with dynamic variables.

Recommended architecture:

``` text
[GLOBAL STYLE LOCK]

[OBJECT DESCRIPTION]

[RECOGNIZABLE FEATURES]

[COLOR PALETTE]

[PERSONALITY]

[FOUR STATE REQUIREMENTS]

[COMPOSITION]

[NEGATIVE STYLE CONSTRAINTS]
```

The **GLOBAL STYLE LOCK should remain almost completely static**.

Only object-specific information should change.

------------------------------------------------------------------------

# 17. Global Style Lock

Use this as the stable core of the generator:

``` text
2D Japanese anime creature character design, polished game character illustration, cute-but-fierce monster aesthetic, clean confident anime linework, bold graphic contours, simplified stylized forms, strong readable silhouette, compact creature proportions, slightly exaggerated anatomy, expressive anime creature face, flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows, controlled highlights, minimal gradients, clean white background, cohesive character design, polished 2D illustration, not a 3D render.
```

------------------------------------------------------------------------

# 18. Object Transformation Template

Dynamic portion:

``` text
Transform the provided real-world object into an original creature-monster.

OBJECT:
{{object_name}}

DESCRIPTION:
{{object_description}}

DISTINCTIVE FEATURES:
{{feature_1}}
{{feature_2}}
{{feature_3}}
{{feature_4}}
{{feature_5}}

COLOR IDENTITY:
{{color_description}}

PERSONALITY:
{{personality}}
```

The application should populate these values from the already-approved
object analysis.

Do not independently perform object validation here.

------------------------------------------------------------------------

# 19. Full Generation Prompt Template

Recommended production template:

``` text
Create a polished character reference sheet for an original creature-monster based on the provided real-world object.

GLOBAL STYLE:
2D Japanese anime creature character design, polished game character illustration, cute-but-fierce monster aesthetic, clean confident anime linework, bold graphic contours, simplified stylized forms, strong readable silhouette, compact creature proportions, slightly exaggerated anatomy, expressive anime creature face, flat base colors, crisp 2–3 level cel shading, hard-edged anime shadows, controlled highlights, minimal gradients, clean white background, cohesive character design, polished 2D illustration, not a 3D render.

OBJECT TRANSFORMATION:
Transform the object into a creature rather than simply placing a face and limbs onto the object.

Preserve the object's most recognizable physical characteristics and reinterpret them as creature anatomy, armor, markings, limbs, tails, horns, weapons, or accessories.

OBJECT:
{{object_name}}

DESCRIPTION:
{{object_description}}

DISTINCTIVE FEATURES:
{{distinctive_features}}

COLOR IDENTITY:
{{color_palette}}

PERSONALITY:
{{personality}}

The resulting creature must remain clearly recognizable as a monster derived from the original object.

CHARACTER CONSISTENCY:
All four poses must depict the exact same character.
Maintain identical body proportions, facial design, colors, markings, accessories, anatomy, and signature object-derived features.

CHARACTER SHEET:
Create exactly four full-body poses arranged in a clean 2×2 grid.

TOP LEFT — IDLE:
Relaxed neutral pose, natural stance, calm default expression, clear readable silhouette.

TOP RIGHT — BATTLE:
Dynamic anime battle pose, energetic stance, fierce expressive face, exaggerated movement, restrained action effects such as motion lines, sparks, dust, or small debris where appropriate.

BOTTOM LEFT — SLEEP:
Cute peaceful sleeping pose, relaxed body, closed eyes, subtle floating Z symbols.

BOTTOM RIGHT — DAMAGED:
The same character after taking damage. Add object-appropriate cracks, scratches, dents, loose parts, small bandages, or exposed components. Tired or pained expression. Keep the character clearly recognizable.

COMPOSITION:
Clean white background, equal spacing, consistent scale, full body visible, no cropping, no environment, minimal grounding shadow, clean character presentation sheet.

Add simple dark labels below each pose:
IDLE
BATTLE
SLEEP
DAMAGED

NEGATIVE STYLE:
photorealistic, realistic CGI, 3D render, toy, figurine, plastic model, physically based rendering, ray tracing, realistic materials, cinematic lighting, volumetric lighting, painterly, watercolor, oil painting, pixel art, voxel art, low-poly 3D, overly detailed textures, excessive gradients, realistic anatomy, live-action.
```

------------------------------------------------------------------------

# 20. Application Architecture Recommendation

The generation pipeline should conceptually be:

``` text
Camera
   ↓
Image
   ↓
Existing Gemini 2.5 Flash Validation
   ↓
Approved Object
   ↓
Object Metadata
   ├── object_name
   ├── object_description
   ├── distinctive_features[]
   ├── color_palette
   └── personality
   ↓
Stable Monster Style Prompt
   +
Dynamic Object Prompt
   ↓
Image Generation Model
   ↓
Monster Character Sheet
```

The style prompt should be treated as **configuration**, not business
logic.

------------------------------------------------------------------------

# 21. Keep Style Configuration Separate

Recommended conceptual structure:

``` ts
const MONSTER_STYLE = {
  name: "anime-cel-shaded-monster",
  version: "1.0",

  globalStyle: `...`,

  composition: `...`,

  states: {
    idle: `...`,
    battle: `...`,
    sleep: `...`,
    damaged: `...`,
  },

  negativeStyle: `...`,
};
```

Then dynamically inject:

``` ts
const objectContext = {
  name,
  description,
  distinctiveFeatures,
  colorPalette,
  personality,
};
```

The final prompt is assembled from these components.

This makes it possible to tune the game's art direction later without
rewriting the object-generation logic.

------------------------------------------------------------------------

# 22. Version the Style

Do not silently change the master prompt.

Use:

``` text
monster-style-v1
monster-style-v1.1
monster-style-v2
```

A style prompt is effectively part of the game's art direction.

Changing it can make newly generated monsters visually incompatible with
older monsters.

If the game stores generated monsters permanently, consider storing:

``` text
style_version
generation_model
prompt_version
```

alongside the generated monster metadata.

------------------------------------------------------------------------

# 23. Consistency Rules for Future Iterations

When improving the style:

### Safe changes

Usually safe:

-   slightly changing shadow intensity
-   adjusting line thickness
-   adjusting background white level
-   changing label typography
-   slightly tuning saturation
-   refining highlight behavior

### Risky changes

Potentially disruptive:

-   changing from cel shading to soft shading
-   changing body proportions
-   changing eye style
-   changing outline style
-   introducing 3D rendering
-   changing the overall silhouette language
-   switching to painterly rendering
-   changing the number of shadow levels substantially

These should trigger a new style version.

------------------------------------------------------------------------

# 24. Quality Checklist

Before accepting a generated monster, visually check:

### Object Identity

-   Is the source object still recognizable?
-   Are its 3--6 strongest features preserved?
-   Were those features integrated creatively?

### Character Design

-   Does it look like a creature rather than an object with a face?
-   Is the silhouette strong?
-   Is the character visually appealing?
-   Does it have a clear personality?

### Style

-   Does it look 2D?
-   Is the cel shading crisp?
-   Are the outlines clean?
-   Are gradients limited?
-   Does it avoid photorealistic / 3D rendering?

### Four States

-   Are all four states clearly the same character?
-   Is IDLE relaxed?
-   Is BATTLE dynamic?
-   Is SLEEP cute and peaceful?
-   Is DAMAGED visibly damaged but still recognizable?

### Composition

-   Exactly four poses?
-   2×2 grid?
-   Full body?
-   Consistent scale?
-   White background?
-   No accidental cropping?

------------------------------------------------------------------------

# 25. Important Implementation Principle

The AI should be given **creative freedom inside a fixed visual
grammar**.

Do not over-specify exactly what every monster must look like.

The purpose of the system is to allow surprising transformations.

For example, the system should be able to discover that:

> a cable could become a tail

or:

> a handle could become a horn

or:

> buttons could become armor

without forcing every object into the same anatomy.

The consistency should come from:

**linework + shading + proportions + color discipline + silhouette
quality + presentation**

---not from forcing every monster to have the same body.

This is what will make the game feel like a coherent monster universe
rather than a collection of AI-generated pictures.

------------------------------------------------------------------------

# 26. Core Principle

The entire feature can be summarized as:

> **Same art direction, different creature identity.**

The camera determines **what the monster is**.

The style system determines **how the monster belongs to the game**.
