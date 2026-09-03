# Anima quadruped “floating” — fact-finding diagnosis

**Date:** 2026-09-03  
**Scope:** Why four-legged and long-bodied Anima read as floating in Home lobby and Battle arena.  
**Constraint:** Zero paid API calls; all evidence from local files and free scripts.

---

## 1. Verdict

**Primary cause: (A) art — drawn-in high-angle perspective. Battle background
alignment amplifies it; Home alignment does not.**

**Not primary: (B) client placement bug.** The client correctly plants the **deepest opaque pixel** of each pose on the floor line. That is working as designed. The problem is that quadruped sheets encode a **tilted ground plane inside the sprite**: the near paw reaches the bbox bottom while the far paws sit above it. Aligning the bbox bottom to the arena floor therefore plants the **near** foot while the **far** feet read as airborne.

**The decisive, independently verified fact is in section 4, not section 2:** the production sprite prompt has explicitly demanded a *"three-quarter view from slightly above"* since `v1`, and it is still there in `v41/sprite_sheet.md:109`, `v41/sprite_sheet_fauna.md:152`, and `v41/sprite_sheet_evolve.md:330`. The high angle is **instructed, not model drift**. There is no rule anywhere requiring all ground-contact points to share one plane. So the owner's guess was right: the rule genuinely does not exist yet.

**Magnitude, corrected and owner-calibrated.** The useful advisory measurement
is the gap from the floor to the second shallow local minimum in the lower
silhouette profile, not max–min over every column. It is **2.7% of body height**
for accepted Sunhound, **4.2%** for marginal Gearbit Racer, **11.8%** for
rejected Chromquartz, and **17.4%** for rejected Stridarc. Veridian scores
**24.8%** but is visually acceptable because its pot is a broad base, proving
that this metric can rank candidates but cannot be an automatic gate.

| Candidate | Role | Confidence |
|-----------|------|------------|
| **(A) Generated art** | Root cause for quadrupeds/long bodies | **High** |
| **(B) Client grounding** | Not broken; cannot fix perspective retroactively | **High** (that it is not the bug) |
| **(C) Battle background alignment** | Amplifier, not the art root cause | **High** |

**What would change this verdict**

- Idle quadruped sheets with two separated low-contact regions in a narrow band
  that still float in Home would implicate client placement more strongly.
- Proof that `plant_on_anchor()` is skipped or uses frame bottom instead of alpha bbox on Home/Battle paths.
- A body-plan classifier reliable enough to make the pixel metric an automatic
  gate; current evidence explicitly shows that no such classifier exists.

---

## 2. Evidence

### 2.1 Measurement method

Script (free, local):  
`.scratch/anima-grounding/measure_grounding.mjs`

Run:

```bash
node .scratch/anima-grounding/measure_grounding.mjs
```

Uses `imagescript`, alpha threshold **0.12** (matches `AnimaPresenter.OPAQUE_ALPHA_MIN`). For each pose cell it reports:

- Tight alpha bbox bottom row
- Fraction of occupied silhouette columns inside the bottom contact band
- Width/count of contiguous contact runs
- Shallow local minima in the bottom-column profile
- **Second support gap**: depth of the second shallow local minimum relative to
  body height and estimated Home display pixels

Full JSON: `/tmp/anima-grounding/measurements.json`

### 2.2 Specimens

The current script covers approved evolution controls plus production cache
specimens: Sunhound, Veridian, Playtron, Gearbit Racer, Chromvein, Mugingot,
Drowake, Chromquartz, and Stridarc. Chromquartz is a v45 Synthesis Result from
Gearbit Racer + Chromvein; Stridarc is a v41 vehicle capture. Production sheets
are read from the private local Godot cache or a one-time read-only download,
never committed.

### 2.3 Owner-calibrated key numbers — **idle pose**

| Specimen | Owner verdict | Second shallow minimum | Estimated Home pixels |
|---|---|---:|---:|
| Sunhound Adult | Acceptable | 2.7% body | ~9 px |
| Gearbit Racer | Marginal / slightly off | 4.2% body | ~12 px |
| Chromquartz | Rejected / worst | 11.8% body | ~46 px |
| Stridarc | Rejected / bad | 17.4% body | ~39 px |
| Veridian Adult | Acceptable broad base | 24.8% body | not meaningful |

The ordering matches the owner's visual judgment for quadruped/wheeled forms,
but Veridian is the decisive counterexample against a threshold. The production
field is therefore named `qa.idle_grounding.second_shallow_minimum_gap_ratio`,
not “foot gap”, and remains advisory.

### 2.4 Invalid metrics removed

The first draft reported **foot spread** as max–min over every silhouette
column. It was invalid because tails, ears, and snouts contaminated the range;
Playtron also scored high despite being a compact biped. The first draft's
**belly gap** was invalid for the opposite reason: empty space under a standing
quadruped is normal anatomy. Both calculations were deleted from the script.

All specimens still confirm one correct invariant: the bbox bottom sits 6 px
above frame bottom, matching `framePadding: 6`. The client plants that opaque
bottom correctly.

### 2.5 Comparison artifacts

Idle crops and `/tmp/anima-grounding/measurements.json` are regenerated by
`measure_grounding.mjs`. V46 before/after sheets and Idle crops will be written
under `eval/results/v46/` after the three authorized generation calls; production
cache sheets remain untouched.

---

## 3. How the client grounds a sprite today

Grounding is **alpha-bbox-bottom**, not multi-foot detection.

### 3.1 Post-process (sheet assembly)

`backend/supabase/functions/_shared/postprocess.mjs` — `planFrames()`:

```770:792:backend/supabase/functions/_shared/postprocess.mjs
 * Jangkarnya bottom-center bbox, yaitu titik tumpu di tanah. Keempat pose jadi
 * berdiri di garis tanah yang sama, termasuk pose sleep dan defeated yang
 * memang lebih rendah.
 ...
      destY: row * frameH + (frameH - opts.framePadding - bb.h),
```

Each pose’s detected bbox is **bottom-aligned** inside its frame with 6 px padding. `render_metrics.reference_height_px` comes from idle bbox height.

### 3.2 Loader initial offset

`game/scripts/anima_loader.gd`:

```142:145:game/scripts/anima_loader.gd
		# Sprite di-render centered, sementara isi frame rata bawah. Menggeser
		# ke atas setengah frame membuat titik tumpu kreatur jatuh di origin
		# node, sehingga tween "bernapas" membesar dari kaki, bukan dari perut.
		"ground_offset": Vector2(0.0, -frame_size.y / 2.0),
```

This is a centered-sprite default; **runtime planting overrides it.**

### 3.3 Presenter — what counts as “feet”

`game/scripts/anima_presenter.gd`:

```148:155:game/scripts/anima_presenter.gd
## Geser sprite supaya kaki opak duduk di origin node, bukan dasar sel kotak.
func plant_on_anchor() -> void:
	var bounds := opaque_local_rect()
	if bounds.size == Vector2.ZERO:
		return
	_base_position = -_feet_local(bounds)
```

```282:285:game/scripts/anima_presenter.gd
func _feet_local(bounds: Rect2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return Vector2(offset.x, 0.0)
	return _flip_local(Vector2(bounds.get_center().x, bounds.end.y))
```

**Feet = horizontal center + bottom of trimmed opaque bbox** (alpha ≥ 0.12, edge haze stripped in `_tight_used_rect()`).

Contact shadow follows the same point (`sync_ground_shadow()`).

### 3.4 Floor lines

| Surface | Constant | Value |
|---------|----------|-------|
| Home portrait | `HomeBackground.PLATFORM_TARGET_PORTRAIT_RATIO` | **68%** of base art rect height |
| Home landscape | `HomeBackground.PLATFORM_TARGET_LANDSCAPE_RATIO` | **69%** |
| Duel / Team / Expedition | `BattleScale.GROUND_Y_RATIO` | **91%** of arena height |

Home: `scan_flow.gd` `stage_position_for()` places `Stage` at the art-derived ground line (not raw viewport).

Battle: `battle_view.gd` `_position_fighters()` sets anchor Y to `arena.height * 0.91`, scales fighters, then calls `plant_on_anchor()` on each sprite.

Home is aligned by construction: its focal row is transformed together with the
background. Battle is not equivalent. Static portrait cover-fit plus vertical
pan `0.5` places the PNG's painted 91% foot baseline about **89 px** away from
the arena's independent `height * 0.91` anchor in the measured viewport;
landscape can push that painted baseline below the visible crop. This amplifies
the defect in Battle, but it cannot explain the same floating read in Home.

**Conclusion:** if one near support defines the bbox bottom, it touches the
runtime floor correctly. Other supports drawn higher still look airborne. The
art contract is the shared root cause; Battle background alignment is a
separate amplifier and is not part of the approved v46 scope.

---

## 4. What the prompt says about camera height today

### 4.1 Rule that **exists** — horizontal facing (not vertical)

Production v41 `sprite_sheet.md`:

```96:99:backend/prompts/v41/sprite_sheet.md
HORIZONTAL FACING LOCK — BATTLE CONTRACT
In EVERY character cell, the creature must face canvas-left in the same
forward-left three-quarter orientation. Never mirror, turn around, or swap an
asymmetrical landmark in any one cell.
```

This locks **yaw**, not pitch.

### 4.2 Rule that **exists** — camera explicitly **slightly above**

Same file, composition block:

```108:110:backend/prompts/v41/sprite_sheet.md
COMPOSITION — EXACTLY NINE CELLS IN A 3x3 ARRANGEMENT
Keep the same camera: three-quarter view from slightly above, facing
forward-left. Full body visible in every character cell at comparable scale.
```

Identical wording appears in `sprite_sheet_fauna.md`, `sprite_sheet_evolve.md`, and **every prompt version back to v1** (`backend/prompts/v1/sprite_sheet.md`: “Three-quarter isometric view from slightly above”).

Evolve v41 idle cell additionally requires:

```338:343:backend/prompts/v41/sprite_sheet_evolve.md
TOP LEFT — IDLE
...
Discrete support points with visible negative space
beneath or between them. Not fused to a mound, pot, plinth, stump, or wall.
```

That **allows** visible gaps between supports — it does not require all four feet on one plane.

### 4.3 Rules that **forbid** drawn ground in the sprite

```202:206:backend/prompts/v41/sprite_sheet.md
BACKGROUND — TECHNICAL TRANSPORT LAYER
The entire canvas background must be solid, flat, perfectly uniform chroma key
green #00FF00, RGB (0,255,0). No gradient, noise, texture, floor, shadow, glow,
scenery, props, panel borders, or grid lines.
```

So the model must imply ground via **body perspective**, not a floor ellipse — exactly what high-angle quadruped drawing produces.

### 4.4 Fauna / quadruped-specific

` sprite_sheet_fauna.md`:

> “Quadrupeds stay quadrupedal unless the brief explicitly supports another plan.”

No rule for eye-level camera, equal foot Y, or “all four feet planted.”

Vision v41 mentions quadruped **height** from ground contact to crown (`vision_system.md`) but not camera pitch or foot coplanarity.

### 4.5 Style guide

`docs/monster_camera_anime_cel_shaded_style_guide.md` §12:

> “A subtle grounding shadow is acceptable if it helps the character feel planted.”

Chroma-key production prompts **override** this for sheets (no shadow/floor in sprite). The guide does not specify eye-level vs high-angle camera.

### 4.6 Owner belief vs facts

The owner believed there is **no rule** for camera height / ground contact. In fact:

- **Vertical camera rule exists** and has been **“slightly above” since v1** — it likely **causes** the symptom rather than omitting a fix.
- **No rule exists** for “all four feet on the same ground plane” or “eye-level horizon for quadrupeds.”

---

## 5. Prior art

No prior paid experiment targeting quadruped floating or camera pitch was found in:

- `docs/16-prompt-version-history.md` (no matches for perspective / floating / ground contact)
- `docs/adr/` (no matches)
- `.cursor/rules/art-and-prompt-pipeline.mdc` (discusses facing v16, borderless v11, seams — not vertical camera)

**Related but distinct work:**

1. **Arena background foot-contact (Aug 2026)** — `docs/14-deploy-log.md`: six Duel/Team backgrounds recomposited so **foot-contact baseline is at 91%** of image height, matching Expedition. That fixed **background** horizon vs arena line, not sprite perspective.

2. **Home scale normalization (Aug 2026)** — same log: Home uses `stage_scale_for()` with `reference_height_px` so lobby size tracks body height, not raw PNG resolution. Sunhound measured 275 px vs Padronic 227 px at 1602 px art — scaling issue, not floating root cause.

3. **Sunhound evolution paid runs** — `docs/14-deploy-log.md` lines ~1776–1794: paid Adult v28 / Evolved v29 approved for silhouette and canine identity. Operator concern was **evolved gait/silhouette**, not ground contact. Approved art is the specimen measured here.

4. **Seeker avatar arena** — deploy log mentions Boss Seeker ground shadow and foot baseline; separate system (`SeekerSheet` uses per-pose opaque bottom, same bottom-center idea).

**Conclusion:** This specific defect does not appear to have been A/B tested in prompt version history. Fixing it would be a **new** prompt contract change, not a revert.

---

## 6. Owner decision and bounded experiment

The question frontier was closed before implementation:

- Create candidate **v46** for object Capture, Fauna Capture, and Synthesis;
  Evolution remains v41.
- Keep the forward-left three-quarter view slightly above, but make it shallow.
- For grounded bodies with 4+ supports, require at least two separated supports
  in a narrow shared contact band; preserve small perspective depth.
- Exempt bipeds, broad bases/pots/rooted forms, serpentine bodies, one-legged
  forms, and intentional hover/flying bodies.
- Store `qa.idle_grounding` as advisory geometry only; never auto-reject art.
- Spend exactly **three** image generations (~US$0.21): one object using stored
  v41 Vision, one fauna using stored v15 Vision, and one Chromquartz recreation
  from Gearbit Racer + Chromvein using its stored Synthesis Plan and
  `dominant_b`.
- Zero new Vision calls, zero automatic retry, and stop without extra generation
  if any result fails.
- Show all three full sheets, Idle crops, and before/after measurements to the
  owner before any deployment.

This does not retrofit existing Anima. If approved, a new Chromquartz is made
through Synthesis; the production record and cached sheet are not overwritten.
Battle background alignment remains a separately scoped amplifier.

## 7. Implementation status

V46 prompt files, inheritance tests, the single-shot Synthesis eval path, paid
acknowledgement gates, overwrite guards, and non-blocking manifest metrics are
implemented locally. All three real prompt assemblies pass dry-run with zero
API calls.

The three authorized generations then completed 9/9 cells with exactly three
image calls and zero Vision calls:

| Path | Before | V46 | Numeric direction |
|---|---:|---:|---|
| Object stock vehicle | 4.2% | 2.9% | improved |
| Fauna Golden Retriever | 2.7% | 4.3% | worsened slightly |
| Chromquartz Synthesis | 11.8% | 8.9% | improved, still high |

These mixed results are evidence against auto-promoting on the metric alone.
The owner judged Chromvein good, Fauna worse, and Chromquartz visually unchanged.
V46 is therefore **rejected** and retained only as paid experiment provenance.
Production configuration remains v41 Capture / v45 Synthesis.

## 8. Resolution — v47 Capture/Evolution + v48 Synthesis

V47 removed the four-support-only exception, moved the camera to a
forward-left three-quarter view near eye-level, and applied the contract to
Object, Fauna, Synthesis, and Evolution. Every land body uses anatomy-appropriate
contact in grounded poses; a support from the front half and rear half must
share a shallow contact band when both exist. Sleep rests on the same implied
plane; Battle may leave it only for a clear jump or intentional flight.

Four authorized image generations reused stored Vision/Plans and completed 9/9
cells with zero Vision and no retry:

| Path | Before | V47 | Owner outcome |
|---|---:|---:|---|
| Object stock vehicle | 4.2% | 5.8% | accepted visually; metric remains advisory |
| Fauna Golden Retriever | 2.7% | 2.0% | accepted |
| Chromquartz Synthesis | 11.8% | 10.0% | rejected; still visibly sloped |
| Sunhound Adult Evolution | 3.8% | 2.7% | accepted |

The failed Synthesis image exposed two loopholes: the minimum front/rear pair
did not constrain every visible support, and glow/debris beneath a wheel could
masquerade as ground contact. The owner explicitly kept natural three-quarter
depth, so a single hard pixel baseline was not used.

V48 changes only `sprite_sheet_synthesis.md`. Every visible weight-bearing
support must end in solid body pixels with a small flattened tangent or weight
compression; glow, aura, sparks, dust, debris, trails, puddles, floor marks,
and shadows do not count. The far-support offset remains natural but is capped
at half that support's own height or radius.

One authorized Chromquartz generation reused the same Plan and Source sheets.
It completed 9/9 cells with zero Vision/retry, reduced the advisory second
shallow minimum from 11.8% to 6.4% (v47: 10.0%), removed the pose-scale warning,
and was approved visually. The v47/v48 phase used exactly five image calls,
US$0.35 at the conservative guard price; including rejected v46, the complete
grounding investigation used eight image calls, US$0.56, and no new Vision.

Production rolled out on 3 September 2026:

- `prompt_version=v47`
- `evolution_prompt_version=v47`
- `synthesis_prompt_version=v48`
- `create_anima` 28, `evolve_anima` 19, `synthesize_anima` 10, dan
  `replicate_webhook` 18 ACTIVE
- migration `20260903145920_prompt_grounding_v47_v48`
- rollback v41 / v41 / v45

All real prompt assemblies passed dry-run, the generated bundle matched source,
`npm run selftest` passed, unauthenticated smoke requests to all three
generators returned 401, dan webhook menolak signature palsu dengan 401.
Webhook ikut membawa bundle baru supaya facing audit tidak fail-open sebagai
`prompt_absent` untuk v47/v48. The change affects future generation only;
existing cached/production sheets were not overwritten.

---

## Appendix — file index

| Artifact | Path |
|----------|------|
| This diagnosis | `.scratch/anima-grounding/diagnosis.md` |
| Measurement script | `.scratch/anima-grounding/measure_grounding.mjs` |
| Measurement JSON | `/tmp/anima-grounding/measurements.json` |
| Comparison PNGs | `/tmp/anima-grounding/*.png` |
