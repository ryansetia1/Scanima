# Anima Name Lineage v38

Status: implemented and paid Vision-evaluated 19 August 2026; rejected for
creative quality and independent collisions (1/6), never promoted or live.
Production remains capture v31 + evolution v30.

## Product correction

V37 exposed two independent defects:

1. valid results appended suffixes to literal roots such as `serp`, `folia`, and
   `tecn`;
2. strongest-stat suffix selection sent four different subjects toward the same
   open-vowel cadence.

V38 keeps Vision's semantic authorship but treats its root as an input seed,
not the authoritative lineage anchor. It also makes cadence a balanced visual
identity decision rather than a projection of one stat.

No second model call, image-generation change, dependency, migration, or
production promotion is introduced.

## Capture contract

Vision returns exactly six ranked `name_roots`, covering at least four of
`silhouette`, `material`, `motion`, `temperament`, and `structure`.

Each `root` is a lowercase 3–8 letter semantic seed with a vowel or `y`. This
lenient boundary accepts model responses such as `cylin` and `stride`; formatting
that the server can normalize must not waste a paid Scan.

The server:

1. removes non-letters and validates six distinct seeds plus channel coverage;
2. rejects seeds that directly copy `object_label` or `species_key`;
3. selects the strongest remaining seed;
4. maps its initial consonant to a different onset in the same broad phonetic
   family;
5. rotates its first vowel and selects a channel-specific coda;
6. stores the resulting 3–5 letter form as the authoritative anchor;
7. hashes the full visual identity into one of four equal cadence families:
   `closed`, `hard`, `liquid`, or `open`;
8. appends a deterministic continuation from that family.

The selected seed, transformed anchor, and cadence family remain in evaluation
provenance.

## Evolution contract

Adult and Evolved preserve the authoritative Hatchling anchor exactly. Their
stable hash uses target stage plus the validated transformation archetype,
stage brief, locomotion mode, and new contour read.

Adult and Evolved each have separate continuation tables, but both tables retain
the four equal cadence families. One stat cannot force an entire lineage toward
an `-a` or `-ia` ending.

## Verification

Free checks cover:

- source-label seed rejection;
- acceptance of 3–8 letter seeds including `cylin` and `stride`;
- deterministic seed-to-anchor transformation;
- 3–5 letter anchor containment;
- reachability of all four cadence families;
- Adult/Evolved lineage preservation;
- v38 prompt bundling;
- byte-identical v31 capture art and v30 Evolution art prompts.

`npm run selftest` and the six-photo v38 dry run pass.

## Paid evaluation

Six Vision-only calls used the same fixtures as v35–v37. Cost was approximately
$0.018, with no image generation or retry.

| Input | Seed → anchor | Result | Cadence | Review |
| --- | --- | --- | --- | --- |
| Mouse | `clicker` → `kuk` | `Kuka` | open | Reject: exact KUKA robotics company and too short/generic |
| White mug | `cylind` → `grask` | `Graskorin` | liquid | Provisional pass: creature-like and no exact-name collision found |
| Original dragon | `draco` → `zosk` | `Zoskesk` | hard | Reject: `skesk` consonant cluster is awkward to pronounce |
| Potted Monstera | `verdant` → `bom` | `Bomari` | open | Reject: exact active company name |
| Running shoe | `sprint` → `dax` | `Daxorin` | liquid | Reject: exact recording-artist usage |
| Handheld console | `pixel` → `vor` | `Vororn` | hard | Reject: historical/niche usage and repetitive `vor-or` sound |

Response reliability improved from 4/6 to **6/6**. Cadence distribution was
open 2, liquid 2, hard 2, closed 0; endings were
`-a`, `-orin`, `-esk`, `-ari`, `-orin`, and `-orn`. The systemic all-`a` defect
is fixed even though this six-item sample did not draw the closed family.

Creative success is **1/6**. Transforming one semantic seed and balancing
cadence are insufficient collision controls, and deterministic phonetic shifts
can still create poor mouthfeel.

## Decision

V38 is rejected and must not be promoted. Production remains capture v31 +
evolution v30.

The measured lesson is that these are separate acceptance gates:

- semantic connection to the creature;
- pronounceable creature-read;
- cadence diversity across the roster;
- independent collision review.

A future immutable version must select among multiple fully formed candidates
with evidence independent from the model that authored them. It must not regress
the v38 cadence balance or reintroduce paid-call failures for repairable seed
formatting.

## Independent review sources

- [KUKA](https://www.kuka.com/)
- [Bomari company record](https://www.informa.es/directorio-empresas/Empresa_BOMARI.html)
- [Daxorin artist result](https://songstats.com/track/m8vk5p3d/still-the-same)
- [Vororn historical usage](https://doi.org/10.3406/revec.1958.5964)

V39 implemented the measured repair — scored selection over 32 candidates — and
its rejected evaluation is recorded in
[Anima Name Lineage v39](2026-08-19-anima-name-lineage-v39.md).
