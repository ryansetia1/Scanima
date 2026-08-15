# Chapter Factory — Anima Sprite Sheet

Generate one 1024×1024 PNG sprite sheet on `#00FF00` chroma green.

Layout 3×3 (v7+ Scanima):
Idle, Attack, Sleep | Happy, Hungry, Dirty | Damaged, fx_strike, fx_surge

Rules:
- Original candy-themed monster; no logos, brand names, or recognizable IP characters
- Anime cel-shaded Scanima style
- In all seven creature cells, the face or equivalent leading sensory plane and
  whole body face forward-left toward canvas-left; never face the viewer, sheet
  center, a neighboring cell, or canvas-right
- In every open-eye pose, both pupils focus on the same canvas-left target along
  the body direction; never look at the viewer, inward toward sheet center,
  toward canvas-right, cross-eyed, or in two different directions
- Sleep keeps both eyes closed; Damaged may be half-lidded but preserves the
  same canvas-left gaze; a faceless creature keeps its equivalent sensory focus
  canvas-left
- Never mirror anatomy or swap an asymmetrical landmark between cells
- Dark contour against green; no white matte keyline
- fx cells are VFX-only without creature body
- Subject must match the chapter cast entry (name, element, silhouette brief)

Do not auto-retry failed generations.
