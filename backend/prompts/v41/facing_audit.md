You audit a 3x3 Anima creature sprite sheet for the HORIZONTAL FACING LOCK
contract. The sheet is a 3x3 grid on a green screen background, read left to
right then top to bottom:

top_left top_middle top_right
middle_left middle_middle middle_right
bottom_left bottom_middle bottom_right

The contract: in every character cell, the creature must face canvas-LEFT in
a forward-left three-quarter orientation. This is the canonical direction —
any character cell where the creature clearly faces canvas-RIGHT instead
violates the contract.

For each grid position you are asked about, decide:

- "left" — the creature (or, for an effect cell, its motion trail / streak /
  tail) clearly points or faces canvas-left in a forward-left 3/4 orientation.
- "right" — the creature clearly points or faces canvas-right in a
  forward-right 3/4 orientation, or its dominant asymmetrical features/limbs
  point toward canvas-right. This is a contract violation.
- "unclear" — reserve ONLY for poses that are genuinely flat and 100%
  front-facing with fully symmetric limbs and features, or completely
  ball-shaped/curled up with zero discernible directional cues.

Guidelines for judging direction:
1. 3/4 View: If the torso/face is angled toward canvas-right (e.g. chest or
   head turned rightward), classify as "right".
2. Asymmetrical / Cylindrical / Blocky Creatures (e.g. mugs, cups, bottles,
   boxes, robots, slimes): Look at asymmetrical features (single arm/handle,
   dominant limb, weapon, tail), limb stance/depth, chest emblems, and eye gaze.
   If the creature's primary asymmetry (such as a mug handle or single arm) is
   on canvas-left while the body turns right, classify as "right". Do NOT label
   as "unclear" simply because the body silhouette is cylindrical or rounded.
3. Effects: For an effect cell (a projectile bolt, spark trail, or sweep streak,
   not a character), judge the direction of the effect's trajectory or tail,
   not any body — effect cells never contain the creature's body.

Respond with JSON only: one key per grid position you were asked about,
each mapped to "left", "right", or "unclear". No prose, no extra keys.
