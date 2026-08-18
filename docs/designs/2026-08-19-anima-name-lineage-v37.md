# Anima Name Lineage v37

Status: hybrid candidate implemented and paid Vision-evaluated 19 August 2026;
rejected for root quality and response reliability (0/6), never promoted or
live. Production remains capture v31 + evolution v30.

## Product correction

V36 solved exact collision by turning visual data into hash-selected syllables,
but removed the authored identity that made the approved Sugarworks names feel
like Scanima. A name being unique is insufficient when players cannot hear the
creature's silhouette, material, movement, or temperament in it.

V37 restores semantic authorship while retaining an independent server boundary:

- Vision proposes short semantic sound ingredients, not a complete name;
- the server rejects roots that copy source identity;
- the server owns final word formation and lineage continuity;
- no second model call, dependency, external lookup, or image-generation change
  is introduced.

## Capture contract

Capture Vision returns exactly six `name_roots`, ordered strongest first. Each
entry contains:

- `root`: 3–5 lowercase ASCII letters, with a vowel and no three-consonant run;
- `channel`: `silhouette`, `material`, `motion`, `temperament`, or `structure`;
- `evidence`: a concise visible reason from the analyzed subject.

The six entries must cover at least four channels. Vision alters each cue through
clipping, vowel change, consonant shift, or blending. Roots are not complete
names and make no collision claim.

The server:

1. validates all six roots and channel coverage;
2. derives identity tokens from `object_label` and `species_key`;
3. rejects an exact source token or a 4+ letter root copied inside one;
4. selects the first remaining root, preserving Vision's semantic ranking;
5. chooses a curated continuation deterministically from the visual payload and
   strongest stat;
6. stores the root as the authoritative `name_lineage_anchor`.

Example only: a mouse analysis may rank source-copy `mouse` first and
silhouette-root `curv` second. The server rejects `mouse`, keeps `curv`, and may
form a name such as `Curvella`. Vision provided the recognizable character;
the server formed the final word.

## Evolution contract

Adult and Evolved never request a new semantic root. They preserve the
authoritative Hatchling anchor exactly.

The server selects a stage-specific curated continuation from a stable hash of:

- anchor;
- target stage;
- transformation archetype;
- stage brief;
- locomotion mode;
- new contour read.

Adult and Evolved use separate continuation sets, so lineage stays recognizable
without one universal suffix. Model-returned name fields remain temporary wire
values and are replaced before the Plan is stored.

## Why this boundary

The two rejected extremes are closed:

- v35: model authors and self-reviews the complete name; semantic quality is
  strong, but collision claims are unreliable;
- v36: server authors the complete name from a hash; collision risk drops, but
  semantic identity disappears.

V37 assigns each side only the task it can perform:

- Vision recognizes which visual sound cues best represent the creature;
- deterministic code enforces source hiding, word formation, and lineage.

It does not promise legal trademark clearance. The runtime goal is a distinctive
creature read with materially lower verbatim-regurgitation risk.

## Verification

Free checks cover:

- exactly six distinct roots;
- valid root phonotactics;
- at least four visual channels;
- rejection of a root copied from source identity;
- deterministic final word formation;
- selected-root provenance;
- capture anchor containment;
- deterministic Adult/Evolved names preserving that anchor;
- v37 prompt/schema bundling;
- unchanged v31 capture art and v30 Evolution art prompts.

`npm run selftest` and the v37 six-photo dry run pass without API calls.

## Paid evaluation

Six Vision-only calls used the same fixtures as v35/v36. Estimated cost was
about $0.018, with no image generation or retry.

| Input | Selected root | Final result | Review |
| --- | --- | --- | --- |
| Mouse | `glid` / motion | `Glidora` | Reject: exact active website/app name; root remains a transparent form of “glide” |
| White mug | — | Validation failure | Model returned `cylin`; strict phonotactic validation rejected it |
| Original dragon | `serp` / silhouette | `Serpora` | Reject: literal serpent root, exact historical/company usage, and near-brand read |
| Potted Monstera | `folia` / structure | `Folialia` | Reject: literal Latin/botanical `folia` with a suffix; not an original creature root |
| Running shoe | — | Validation failure | Model returned six-letter `stride`; strict root-length validation rejected it |
| Handheld console | `tecn` / structure | `Tecnelia` | Reject: transparent technology root and product/person-like construction |

Creative success is **0/6**. Two of six paid responses fail on formatting that a
production Scan should repair rather than expose. More importantly, all four
successful paths select recognizable dictionary/classical/category roots.
Server-owned suffixes prevent verbatim model names but cannot make a literal
root feel original.

Independent exact-name review found existing usage for `Glidora` and `Serpora`;
`Folialia` remains botanical by construction, while `Tecnelia` reads as a
technology product or proper name.

## Decision

V37 is rejected and must not be promoted. Production remains capture v31 +
evolution v30.

Any repair belongs in a new immutable prompt version. It must address both:

1. deterministic normalization of minor root-format violations such as `cylin`
   and `stride`, without another paid call;
2. transformed semantic roots rather than clipped dictionary/category words.

Merely changing the continuation table cannot rescue roots such as `serp`,
`folia`, or `tecn`.

V38 implemented the measured repair and its rejected evaluation is recorded in
[Anima Name Lineage v38](2026-08-19-anima-name-lineage-v38.md).
