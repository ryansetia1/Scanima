# Scanima

A mobile virtual pet game where players photograph the real world to discover
creatures, raise them, and battle with them. This glossary fixes the words the
codebase and the design conversations use, so that one concept never travels
under three names.

## Language

**Anima Idle Pose**:
The calm, grounded resting image used whenever an Anima is present but not
performing another pose, including while waiting between commands in battle.
_Avoid_: Idle animation, battle idle

**Neutral Idle Gaze**:
An Anima's relaxed gaze toward a distant point along the natural direction of
its level head or snout. It never looks at the Seeker, up, down, or with a
side-eye. The rule only constrains eyes whose direction is naturally readable;
it never rotates the established three-quarter Idle head pose, adds pupils, or
changes an Anima's anatomy.
_Avoid_: Camera gaze, screen-centred gaze, forward gaze

**Seeker**:
The player's identity inside the game world — the one who discovers Anima,
cares for them, and sends them into battle.
_Avoid_: Trainer, user, player

**Seeker Avatar**:
The visual figure that stands in for a Seeker on screen. Chosen by the player
from a fixed set, purely cosmetic, and never derived from anything the player
told us about themselves.
_Avoid_: Character, skin, player sprite, portrait

**Seeker Roster**:
The fixed, hand-authored set of Seeker Avatars a player may choose from.
Growing it means drawing one more figure, never generating one per player.
_Avoid_: Avatar list, character pool, skins

**Boss Seeker**:
A Seeker authored as part of a chapter rather than played, who opposes the
player during an Expedition.
_Avoid_: NPC, rival, boss trainer

**Seeker Sheet**:
The nine-pose art contract every Seeker figure is drawn on: one idle pose, the
four command poses, two reaction poses, a victory and a defeat pose, and a
profile pose. Shared by Boss Seekers and Seeker Avatars alike.
_Avoid_: Sprite sheet (that means Anima art), avatar sheet

**Seeker Demographics**:
The optional birth year and gender a player may give during onboarding. They
describe the person holding the phone, never the Seeker Avatar.
_Avoid_: Profile data, gender (as a stand-in for appearance)
