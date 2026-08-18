# Anima Name Lineage v35

Status: candidate implemented and paid Vision-evaluated 19 August 2026;
rejected after independent collision review (1/6), never promoted or live.
Production remains capture v31 + evolution v30.

## Goal

V35 tests whether a stricter, structured self-review can stop the two failure
modes left by v34:

- existing dictionary, classical, scientific, or taxonomic terms presented as
  invented names;
- company, app, product, medicine, or device-model names presented as creature
  species.

The established lineage constraints remain unchanged:

- Hatchling receives one coined, pronounceable species name;
- Adult and Evolved preserve one authoritative 3–5 letter sound anchor;
- player nicknames are never overwritten;
- existing Anima are not renamed;
- naming reuses the existing Vision call, with no image generation or automatic
  retry.

## V35 naming contract

Before returning JSON, Vision privately creates at least eight candidates across
four construction families:

1. transformed silhouette + motion;
2. transformed material or coat + temperament;
3. transformed structural feature + movement;
4. a new phonetic root guided only by the creature's visual character.

Candidates still undergo v34's per-subject forbidden-identity and cover tests.
V35 adds these rejection gates:

- not an existing standalone dictionary word;
- not a Latin or Greek word;
- not a common scientific, anatomical, or taxonomic term;
- not one of those terms with only a terminal letter added;
- not primarily readable as a company, app, software package, consumer product,
  device model, medicine, or person's name;
- readable as a living monster species spoken during discovery or battle.

The final name must be guided by at least two distinct visual channels, while
sound fragments are altered enough that they do not remain two readable source
words.

## Structured quality output

Capture v35 adds a nullable `name_quality` object to the Vision schema. A safe,
accepted subject must return all six booleans as `true`:

- `invented_word`
- `source_identity_hidden`
- `creature_species_read`
- `grounded_in_two_visual_cues`
- `not_product_or_brand_read`
- `lineage_ready`

`validateVision()` rejects a v35 result when the object is absent or any value
is not exactly `true`. This is a response-shape and declared-intent guard, not a
dictionary or trademark lookup.

The existing `name_lineage_anchor` validation remains:

- 3–5 lowercase ASCII letters;
- contains at least one vowel;
- occurs inside `suggested_name`;
- has no run of three consonants.

An invalid capture anchor is still repaired deterministically from the generated
name and recorded as an issue. Evolution keeps the v32 authoritative-anchor
contract unchanged.

## Evaluation

Six category-diverse Vision-only calls used the union of both v34 fixture sets
for direct comparison. Total estimated cost was about $0.018. There was no image
generation, model retry, or extra naming call. The handheld WebP was converted
locally to PNG before evaluation.

Every response returned all six `name_quality` values as `true`. Independent
review produced a materially different result:

| Input | V35 name | Anchor | Independent result |
| --- | --- | --- | --- |
| Mouse | `Scurrix` | `scurr` | Pass: pronounceable creature read; only an obscure username collision was found |
| White mug | `Crockle` | `crock` | Reject: existing Scots noun, children's crocodile character, and published bestiary creature |
| Original dragon illustration | `Aerisyn` | `aeris` | Reject: exact active AI/robotics company name and commercial lamp/music name |
| Potted Monstera | `Phyllaura` | `lla` | Reject: near-match to obsolete plant genus `Phyllaurea` and direct botanical `phyll` construction; proposed `phyll` anchor also required repair |
| Running shoe | `Solerix` | `soler` | Reject: exact enterprise-management SaaS product name |
| Handheld console | `Vectron` | `vect` | Reject: exact major POS company/brand and Siemens locomotive trademark |

Creative success is **1/6**. V35 performs worse than v34's expanded 3/6 result.
The central failure is epistemic: the same model that coined a name also marked
its own unsupported collision claims as true. Structured self-attestation
enforces shape but does not provide independent knowledge or verification.

## Decision

V35 is rejected and must not be promoted. Production remains capture v31 +
evolution v30.

A future v36 must change the mechanism rather than add another prose self-check.
At minimum, candidate generation and collision judgment need independent
evidence or a deterministic lexical boundary. The product must decide the
trade-off explicitly:

- accept a maintained local lexical/collision dataset;
- pay for a separate independent naming review;
- or accept that runtime-generated names cannot make a reliable no-collision
  claim.

Another model-authored boolean checklist is not an adequate gate.
V36 subsequently tested a deterministic phonotactic generator and was also
rejected because collision resistance came at the cost of authored creature
identity; see
[`2026-08-19-anima-name-lineage-v36.md`](2026-08-19-anima-name-lineage-v36.md).

## Verification

Free checks cover:

- v35 prompt and schema bundling;
- all six required `name_quality` keys;
- rejection of absent or false quality declarations;
- inherited v32 anchor syntax, containment, deterministic repair, and Evolution
  continuity;
- unchanged v31 capture art and v30 Evolution art prompts.

`npm run selftest` passes with v35 bundled.

## Sources used for independent review

- [Crockle in the Dictionary of the Scots Language](https://dsl.ac.uk/entry/snd00067017)
- [Crockle children's-book character](https://davidhigham.co.uk/books-dh/crockle-saves-the-ark/)
- [Aerisyn AI](https://www.aerisyn.ai/)
- [Phyllaurea botanical synonym](https://www.crescentbloom.com/plants/genus/p/h/phyllaurea.htm)
- [Solerix enterprise software](https://www.solerix.com/index.html)
- [Vectron Systems](https://www.vectron-systems.com/en/company/company-profile/company/)
- [Siemens Vectron locomotive](https://www.mobility.siemens.com/global/en/portfolio/rolling-stock/locomotives/vectron.html)
