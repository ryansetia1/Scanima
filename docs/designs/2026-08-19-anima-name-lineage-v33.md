# Anima Name Lineage v33

Status: candidate implemented and paid Vision-evaluated 19 August 2026;
rejected for naming quality (1/3), never promoted or live. Production remains
capture v31 + evolution v30.

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

- `suggested_name`: one original, pronounceable 2–4 syllable coined species
  word.
- `name_lineage_anchor`: a lowercase ASCII substring of 3–5 letters that occurs
  in `suggested_name`, includes at least one vowel, contains no run of three
  consonants, and carries the lineage's most memorable pronounceable sound.

The name combines cues from the dominant silhouette, material, and motion.
Tone follows the creature: playful, elegant, severe, strange, or imposing.
It must not be a transparent compound of recognizable English words, contain
the complete ordinary source label or an obvious synonym, use a literal
ingredient, read as a person/surname/place/title/job/rank, copy a real-world
brand or named franchise character, or end in `mon`.

V33 asks Vision to silently discard and re-coin a draft that fails any check.
The photographed source is suggested through altered sound fragments,
consonant shifts, vowel changes, and blended partial cues—not by joining source
words.

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

Capture prompt v33 retains v32's `name_lineage_anchor` beside `suggested_name`
and adds the coined-word self-check above.
`validateVision()` normalizes the name, then checks that the anchor:

- is 3–5 lowercase ASCII letters;
- has at least one vowel;
- occurs in the normalized generated name;
- has no run of three consonants for v33 capture.

If the model's proposed capture anchor misses any check, the server derives the
closest valid 3–5 letter substring from `suggested_name` deterministically and
records a validation issue. This keeps a minor naming-format mistake from
failing a paid Scan or requiring a Vision retry. The first paid v32 smoke
produced `ClickGlide` + invalid `glic`; the fallback resolves it to `clic`.

The field remains inside the existing `generations.vision_result`; no schema
migration or client persistence is needed. V32 behavior remains frozen for
reproducibility; the stricter consonant-run check is enabled only when prompt
version is v33 or newer.

Evolution prompt v33 keeps v32's `name_lineage_anchor` Plan schema unchanged.
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
names below. They are live in immutable Sugarworks v6.

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

## Why v33 exists

V32's three paid Vision-only calls cost about $0.009 total and used no image
generation:

| Input | V32 proposed name | Result |
| --- | --- | --- |
| Mouse | `ClickGlide` | Reject: transparent two-word action compound; model anchor `glic` was not a substring |
| White mug | `Muggleton` | Reject: literal `mug` root and surname-like read; weak `ggle` anchor |
| Original dragon illustration | `Wyrmscale` | Reject: generic `wyrm + scale` compound; anchor required deterministic repair |

The deterministic repair made all three structurally safe, but **0/3** met the
approved creative direction. V33 addresses the shared cause in the prompt
instead of adding a brittle English dictionary or another model call.

## Evaluation and rollout

Promotion gate:

1. Free selftests cover anchor syntax, deterministic capture repair,
   v33 consonant-run repair, containment, inheritance, nickname isolation,
   unchanged-name rejection, and legacy capture fallback.
2. Paid Vision-only inputs verify the live model response shape and coined-word
   direction. No image generation or automatic retry is used.
3. The operator reviews pronunciation, semantic grounding, originality, and
   lineage potential before promotion.

Three v33 Vision-only calls used the same fixtures as v32 for a direct
comparison. They cost about $0.009 total, used no image generation or retry,
and all passed structural validation without anchor repair:

| Input | V33 proposed name | Anchor | Result |
| --- | --- | --- | --- |
| Mouse | `Cursora` | `curso` | Reject: preserves the complete direct synonym `cursor` with only a terminal vowel |
| White mug | `Glazel` | `glaz` | Pass: one pronounceable coined species word; glaze is a material cue rather than the mug label |
| Original dragon illustration | `Dracovent` | `vent` | Reject: generic `draco + vent` construction; source identity remains too literal |

V33 improved the creative result from 0/3 to 1/3, but that remains below the
promotion bar. Any further prompt revision must use v34 so this paid result
stays reproducible. Production remains capture v31 + evolution v30.

Rollback remains capture v31 and evolution v30. Existing names and saved
nicknames are unaffected because names are suggestions, not automatic writes.

Sugarworks v6 is active in production as version
`ae9cd74f-a32d-4a99-a1f8-19681ecbe54b`, manifest
`a28aee4e9d5d5bc37a21fcd5ba6e2a4e64cc59e4dd132468efa8c2a259250384`.
It is a policy-only content successor: the nine display names changed while
all 14 runtime assets reference the already-published v5 bytes. MCP verification
found all 14 Storage objects, all nine Atlas forms with the new names, v6
active, and v5 retained immutable but inactive.

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
8. **Prompt rule over dictionary filter.** A hardcoded English word list was
   rejected because compounds, synonyms, surnames, and multilingual source
   labels cannot be covered reliably at the server boundary.
9. **Pronounceable anchor only in v33+.** Historical v32 validation remains
   reproducible; v33 additionally rejects three-consonant anchor runs.

## Sources

- [PokéAPI documentation](https://pokeapi.co/docs/v2)
- [PokéAPI Pokémon species dataset](https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species.csv)
- Kawahara & Moore,
  [How to express evolution in English Pokémon names](https://doi.org/10.1515/ling-2021-0057)
- [Tsunekazu Ishihara on naming and localization](https://www.nintendolife.com/news/2016/03/tsunekazu_ishihara_on_the_difficulty_of_naming_pokemon_for_different_regions)
