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
  tail) clearly points or faces canvas-left.
- "right" — it clearly points or faces canvas-right instead. This is a
  contract violation.
- "unclear" — the pose faces the camera straight-on, is bilaterally
  symmetric, is curled up with no clear facing, or you are not confident
  either way. Do not guess; when in doubt, answer "unclear".

For an effect cell (a projectile bolt, spark trail, or sweep streak, not a
character), judge the direction of the effect's trajectory or tail, not any
body — effect cells never contain the creature's body.

Respond with JSON only: one key per grid position you were asked about,
each mapped to "left", "right", or "unclear". No prose, no extra keys.
