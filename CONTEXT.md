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

**Boss Encounter Opening**:
The Final Battle opening that begins with the player's Seeker Avatar facing the
Boss Seeker alone, then reveals the Boss Anima and player Anima in that order
before battle controls become available.
_Avoid_: Cinematic intro, Chapter Intro, regular battle intro

**Boss Seeker Voice Profile**:
The six-part writing identity that fixes a Boss Seeker's motive, relationship
with the player, speech rhythm, emotional arc, natural language, and patterns
to avoid. It keeps all nine dialogue moments recognizably in character without
forcing jargon or catchphrases.
_Avoid_: Catchphrase list, dialogue gimmick

**Seeker Sheet**:
The nine-pose art contract every Seeker figure is drawn on: one idle pose, the
four command poses, two reaction poses, a victory and a defeat pose, and a
profile pose. Shared by Boss Seekers and Seeker Avatars alike.
_Avoid_: Sprite sheet (that means Anima art), avatar sheet

**Seeker Demographics**:
The optional birth year and gender a player may give during onboarding. They
describe the person holding the phone, never the Seeker Avatar.
_Avoid_: Profile data, gender (as a stand-in for appearance)

**Battle Impact Beat**:
The single instant when a visible attack connects. Target reaction, damage
feedback, world shake, and haptic feedback land together on this beat. A
knockout strengthens the same beat instead of adding another impact when the
result appears.
_Avoid_: Attack start, result shake, repeated knockout hit

**Battle World Shake**:
Brief impact motion applied to the battle world—combatants and scenery
together—while the HUD remains stable.
_Avoid_: Fighter shake, full-screen shake, HUD shake

**Haptics**:
Device-wide tactile feedback for command acknowledgement, Battle Impact Beats,
and progression celebrations. The player's device-local Haptics preference
controls all of them together.
_Avoid_: Battle vibration, rumble setting

**Battle Arena**:
The full-screen battle space containing the environment, Anima, Seekers,
shadows, portals, and world effects. Its size never changes when battle
interface elements appear or disappear.
_Avoid_: Stage row, space above the action dock

**Battle Chrome**:
The persistent screen-space battle interface layered over the Battle Arena,
including fighter status, encounter status, commands, and Retreat.
_Avoid_: Battle Chroma, footer, dock section

**Battle Overlay**:
A temporary battle interface layered above the Battle Arena and Battle Chrome,
such as dialogue, a picker, a confirmation, or a result.
_Avoid_: Battle Chrome, arena element

**Critical Hit**:
A chance-based damage spike influenced by Speed. Battle presents it as a
stronger Battle Impact Beat and an explicit arena message, independently of
element effectiveness.
_Avoid_: Critical effectiveness, critical move
