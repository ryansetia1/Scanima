# Anima Name Lineage v32

Status: candidate implemented and paid Vision-evaluated 19 August 2026;
rejected for naming quality, never promoted or live.

## Understanding

- Generated Anima names should read as original monster species, not object
  labels, jobs, ranks, or literal ingredients.
- The Hatchling name is grounded in silhouette, material, and motion, with the
  source object only subtly implied.
- Adult and Evolved names must remain recognizably related to their lineage.
- The system covers both new Scan names and names proposed after Evolution.
- Player nicknames remain freely editable and are never overwritten.
- Existing Anima are not renamed retroactively.
- Naming must reuse the existing Vision calls; no extra model call, cost, or
  latency is allowed.

## Research summary

The comparison used 467 direct English evolution edges from Generations I–IX
through National Dex #1025. Species and evolution relationships came from
PokéAPI. Edges were grouped by the generation that introduced the evolved
species; later-added baby forms were excluded from earlier generations.

A practical spelling heuristic counted a recognizable lineage echo when a pair
shared a contiguous substring of at least three letters, a two-letter word
edge, or at least 45% normalized spelling similarity.

| Generation | Edges | Recognizable echo | Evolved name longer |
| --- | ---: | ---: | ---: |
| I | 72 | 58.3% | 45.8% |
| II | 42 | 54.8% | 54.8% |
| III | 60 | 35.0% | 46.7% |
| IV | 55 | 67.3% | 70.9% |
| V | 74 | 52.7% | 64.9% |
| VI | 35 | 45.7% | 57.1% |
| VII | 33 | 39.4% | 57.6% |
| VIII | 48 | 52.1% | 64.6% |
| IX | 48 | 62.5% | 58.3% |
| **Weighted total** | **467** | **52.7%** | **57.6%** |

The corpus has no universal suffix or continuity rule. Some lines preserve a
clear root (`Pikachu → Raichu`, `Bulbasaur → Ivysaur → Venusaur`), while
others deliberately reinvent the name. Published Pokémonastics research finds
broader sound symbolism: longer names and heavier phonological material can
make post-evolution creatures feel larger or stronger. Tsunekazu Ishihara has
also described English names as individually localized around each creature's
meaning rather than generated from one regular formula.

Scanima adopts the useful lineage principle but makes it more reliable than the
source corpus: every generated Adult and Evolved proposal keeps one explicit
sound anchor.

## Naming contract

### Hatchling

Vision creates:

- `suggested_name`: an original 2–4 syllable species name.
- `name_lineage_anchor`: a lowercase ASCII substring of 3–5 letters that occurs
  in `suggested_name`, includes at least one vowel, and carries the lineage's
  most memorable sound.

The name combines cues from the dominant silhouette, material, and motion.
Tone follows the creature: playful, elegant, severe, strange, or imposing.
It must not be a title, rank, ordinary object label, real-world brand, named
franchise character, or a name ending in `mon`.

### Adult

- Preserve `name_lineage_anchor` exactly.
- Change at least one secondary sound; do not copy the Hatchling name.
- Reflect the new body plan or maturity read rather than merely appending a
  universal suffix.
- Prefer equal length or one additional syllable, but do not force length when
  it harms pronunciation.

### Evolved

- Preserve the same `name_lineage_anchor` exactly.
- Do not copy the Adult name.
- Allow a stronger ending, heavier consonants, broader vowels, or a more
  authoritative rhythm when appropriate.
- Keep the photographed kind and lineage identity; culmination must not read as
  a different species family.

Illustrative only: `Gellume → Gellurion → Gelvarion`. The shared `gel`/`gell`
sound carries identity while the remaining phonology matures. Production names
are still judged against their generated art.

## Data flow and validation

Capture prompt v32 adds `name_lineage_anchor` beside `suggested_name`.
`validateVision()` normalizes the name, then checks that the anchor:

- is 3–5 lowercase ASCII letters;
- has at least one vowel;
- occurs in the normalized generated name.

If the model's proposed capture anchor misses any check, the server derives the
closest valid 3–5 letter substring from `suggested_name` deterministically and
records a validation issue. This keeps a minor naming-format mistake from
failing a paid Scan or requiring a Vision retry. The first paid v32 smoke
produced `ClickGlide` + invalid `glic`; the fallback resolves it to `clic`.

The field remains inside the existing `generations.vision_result`; no schema
migration or client persistence is needed.

Evolution prompt v32 includes `name_lineage_anchor` in its Plan schema.
For Adult, the service reads the capture Vision anchor. For Evolved, it reads
the prior Adult Plan anchor. `validateEvolutionPlan()` requires the returned
anchor to equal the authoritative prior anchor and requires the proposed name
to contain it.

Legacy captures without an anchor may establish one during their next Adult
Plan. The proposed anchor must occur in the generated capture name used by the
lineage, not in the player's current nickname. Evolved then inherits that
Adult anchor normally.

The server continues returning `suggested_name` only as a Rename suggestion.
Saving or cancelling remains the player's choice.

## Sugarworks application

The same silhouette/material/motion approach produced the approved species
names below. They are now live in immutable Sugarworks v6.

| Stable ID | Approved display name |
| --- | --- |
| `sugarworks-gumdrop` | Gellume |
| `sugarworks-taffy` | Velastra |
| `sugarworks-licorice` | Noxcoil |
| `sugarworks-caramel` | Cindrusk |
| `sugarworks-peppermint` | Rimespin |
| `sugarworks-nougat` | Pralith |
| `sugarworks-fudge` | Duskadon |
| `sugarworks-syrup` | Ambermire |
| `sugarworks-cotton` | Nimbelisk |

Stable IDs, assets, stats, moves, encounters, and The Confectioner remain
unchanged.

## Evaluation and rollout

Before promotion:

1. Free selftests cover anchor syntax, deterministic capture repair,
   containment, inheritance, nickname isolation, unchanged-name rejection, and
   legacy capture fallback. This gate passes locally.
2. Three paid Vision-only inputs verify the live model response shape and name
   direction. No image generation or automatic retry is used.
3. The operator reviews pronunciation, semantic grounding, originality, and
   lineage potential before promotion.

The three paid Vision calls cost about $0.009 total and used no image
generation:

| Input | Proposed name | Result |
| --- | --- | --- |
| Mouse | `ClickGlide` | Reject: transparent two-word action compound; model anchor `glic` was not a substring |
| White mug | `Muggleton` | Reject: literal `mug` root and surname-like read; weak `ggle` anchor |
| Original dragon illustration | `Wyrmscale` | Reject: generic `wyrm + scale` compound; anchor required deterministic repair |

The deterministic repair made all three structurally safe, but **0/3** met the
approved creative direction. V32 must not be promoted. Because paid eval has
now established v32 provenance, follow-up prompt wording belongs in a new v33
directory rather than editing v32.

Rollback remains capture v31 and evolution v30. Existing names and saved
nicknames are unaffected because names are suggestions, not automatic writes.

Sugarworks v6 is active in production as version
`ae9cd74f-a32d-4a99-a1f8-19681ecbe54b`, manifest
`a28aee4e9d5d5bc37a21fcd5ba6e2a4e64cc59e4dd132468efa8c2a259250384`.
It reuses the 14 immutable v5 Storage assets and changes only content metadata,
including the nine names. The rejected capture naming contract continues in
[`2026-08-19-anima-name-lineage-v33.md`](2026-08-19-anima-name-lineage-v33.md).

## Decision log

1. **Species names, not codenames.** Job/rank suffixes were rejected because
   they describe roster roles instead of creature identity.
2. **Subtle source reference.** Literal ingredient/object names were rejected
   so generated names can feel like original species.
3. **Mixed tone.** A uniform cute or threatening register was rejected; tone
   follows each Anima's visual character.
4. **Guaranteed anchor.** Pokémon's mixed continuity distribution was rejected
   for runtime generation because unrelated names weaken a player's bond with
   one individual lineage.
5. **Exact 3–5 letter anchor.** Pure phonetic similarity was rejected because
   it cannot be validated reliably without adding a pronunciation system.
6. **No fixed suffix ladder.** It is easy to enforce but would make every
   lineage mechanical.
7. **No extra model call.** Naming remains part of existing capture and
   Evolution Vision outputs.

## Sources

- [PokéAPI documentation](https://pokeapi.co/docs/v2)
- [PokéAPI Pokémon species dataset](https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species.csv)
- Kawahara & Moore,
  [How to express evolution in English Pokémon names](https://doi.org/10.1515/ling-2021-0057)
- [Tsunekazu Ishihara on naming and localization](https://www.nintendolife.com/news/2016/03/tsunekazu_ishihara_on_the_difficulty_of_naming_pokemon_for_different_regions)
