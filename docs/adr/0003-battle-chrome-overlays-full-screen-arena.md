# Battle Chrome overlays a full-screen Battle Arena

Battle controls previously lived in rows below the combat stage, so even hidden
controls continued to shrink the visible world and left an empty lower section
during opening sequences. We decided that Duel, Team Battle, and every
Expedition encounter instead share a full-screen, full-bleed Battle Arena;
Battle Chrome and temporary Battle Overlays are higher screen-space layers that
never resize it. This keeps the arena composition independent from today's
control layout and lets future battle UI be designed as part of the arena
without another structural migration.

## Consequences

Backgrounds may extend behind device insets and interface layers, while fighters,
Seekers, important feedback, and interactive controls remain inside their safe
areas. Camera framing accounts for Chrome as an occlusion zone rather than as
missing arena space: openings use the wider cinematic framing, then the whole
battle world transitions once into stable gameplay framing as Chrome appears.
Dialogs, pickers, confirmations, and results overlay that stable composition;
they do not trigger further arena resizing or reframing.
