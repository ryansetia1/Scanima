# Anima Name Lineage v36

Status: deterministic candidate implemented and paid Vision-evaluated
19 August 2026; rejected for creative quality (0/6), never promoted or live.
Production remains capture v31 + evolution v30.

## Why v36 exists

V35 proved that model-authored quality declarations are not independent
evidence. The model marked every collision check `true`, while five of six names
were existing words, products, companies, or brands.

V36 therefore removes naming judgment from Vision entirely:

- capture Vision does not return `suggested_name`, `name_lineage_anchor`, or
  `name_quality`;
- the server derives a name and lineage anchor deterministically after the
  visual payload passes validation;
- Adult and Evolved names are derived from the authoritative anchor and
  validated Evolution Plan;
- no second model call, external data source, runtime network lookup, or image
  generation is added.

## Deterministic mechanism

`deriveDeterministicSpeciesName()` hashes:

- `species_key`;
- subject kind;
- primary and secondary element;
- strongest stat;
- `creature_brief`;
- `signature_features`.

The strongest stat selects one of five onset families: vitality, attack,
defense, speed, or special. A seeded phonotactic generator then constructs:

1. a 3–4 letter pronounceable anchor;
2. one open middle syllable;
3. one final syllable with an optional coda.

The same validated Vision payload always returns the same name. Different visual
payloads normally produce different names. The anchor occurs exactly at the
start of the result and remains valid under the v32 lineage validator.

`deriveDeterministicEvolutionName()` keeps the same anchor and hashes the target
stage plus canonical Plan fields: archetype, stage brief, height, locomotion,
contour read, and kind. Adult adds two generated syllables; Evolved adds three.
The validator replaces model-returned temporary name fields before storing the
Plan.

## Evaluation

Six Vision-only calls used the same category-diverse fixtures as v35. Estimated
cost was about $0.018, with no image generation or retry. Exact-name web review
found no direct collision for any generated result:

| Input | V36 name | Anchor | Creative review |
| --- | --- | --- | --- |
| Mouse | `Zimnuzem` | `zim` | Reject: repetitive nonce sound; no agile/precise creature identity |
| White mug | `Basgutun` | `bas` | Reject: arbitrary harsh syllables; no sturdy ceramic character |
| Original dragon | `Deshupil` | `des` | Reject: weak majestic/serpentine read and starts with existing `desh` word/name |
| Potted Monstera | `Vadvuter` | `vad` | Reject: synthetic label sound; no botanical elegance |
| Running shoe | `Luvsufak` | `luv` | Reject: awkward near-vulgar/product-like mouthfeel; no swift creature read |
| Handheld console | `Therhalok` | `ther` | Reject: generic fantasy/place sound; no compact digital identity |

Collision avoidance improved from v35, but creative success is **0/6**. The
names are mechanically pronounceable yet feel like random hashes rendered as
syllables. Their visual inputs affect the seed, but a player cannot hear the
silhouette, material, motion, or temperament in the result.

This violates the original product requirement: the source should be subtle,
not absent, and the name should feel intentionally authored rather than merely
unique.

## Decision

V36 is rejected and must not be promoted. Production remains capture v31 +
evolution v30.

The experiment establishes two separate requirements:

1. model generation provides semantic and aesthetic grounding but cannot
   reliably self-check lexical or brand collision;
2. unconstrained deterministic phonotactics reduce exact collision but destroy
   authored creature identity.

A future mechanism needs a hybrid boundary: model-proposed semantic phonemes or
multiple candidates, followed by deterministic selection or transformation
that preserves the strongest readable cue. Pure model self-review and pure
hash-to-syllable generation are both closed directions.

V37 implements that hybrid boundary locally by letting Vision rank semantic
sound roots while the server owns source filtering and final word formation;
see [`2026-08-19-anima-name-lineage-v37.md`](2026-08-19-anima-name-lineage-v37.md).

## Verification

`npm run selftest` passes with checks for:

- deterministic capture output and stable anchor;
- different species payloads producing different names;
- replacement of model-authored names and `name_quality`;
- deterministic Adult/Evolved names preserving the authoritative anchor;
- v36 capture schema omitting model-authored naming fields;
- unchanged v31 capture art and v30 Evolution art prompts.
