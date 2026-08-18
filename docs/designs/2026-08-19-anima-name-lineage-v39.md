# Anima Name Lineage v39

Status: implemented and paid Vision-evaluated 19 August 2026; rejected for
independent collision and cross-language safety (3/6), never promoted or live.
Production remains capture v31 + evolution v30.

One production-safety fix from this evaluation is kept regardless of the
rejection: naming may no longer abort a paid capture.

## Product correction

V38 produced structurally valid responses 6/6 and fixed cadence bias, but only
1/6 names survived review. The measured cause was not the transform — it was
that v38 formed exactly **one** candidate word and used it unconditionally.

Four of the five v38 rejects share defects that are visible in the word itself,
without a dictionary, a second model call, or an external lookup:

| Rejected v38 name | Structural defect |
| --- | --- |
| `Kuka` | four letters, two syllables |
| `Vororn` | two syllables, repeats the bigram `or` |
| `Zoskesk` | two syllables, repeats the cluster `sk` |
| `Bomari` | single-consonant open CV chain, no cluster or coda |

So v39 changes the selection step, not the prompt rules again. It keeps the v38
semantic seed, keeps the server-side phoneme transform, and keeps the balanced
cadence families. No second model call, dependency, migration, or art change.

## Mechanism

`nameStructureScore()` scores a word deterministically: it penalises words under
seven letters, fewer than three syllables, single-consonant open CV chains,
repeated bigrams, three-consonant runs, source-identity substrings, and a `mon`
ending. It rewards nine letters or more and three-to-four syllables.

`selectCadenceName()` builds 32 candidates — four cadence families × eight
two-syllable continuations — discards everything below the structure floor, then
picks among the survivors using the visual-identity hash.

The score is a **gate**, not an objective function. Measured: choosing the
highest-scoring candidate converges on one structural optimum, and 151 of 200
fixtures ended in `-rin`. That is the same rhyme bias v38 had just removed, so
diversity has to come from the hash and quality from the floor.

Because the anchor always ends in a consonant, the medial syllable v38 needed is
gone. Each family supplies its continuation directly, which also removed the bug
where vowel-initial short endings such as `en` and `ak` were collapsed by the
vowel-collision join and made the `closed` and `hard` families unreachable.

Adult and Evolved reuse the same gate with stage-specific continuation tables,
so a stage name can never fall below the floor either.

## Naming must not burn a Core

`sepatu.jpg` lost a paid Vision call to `name_roots v38 harus mencakup minimal
empat visual channel`. The subject was fine; only the seed metadata was thin.

`deriveCuratedHybridSpeciesName()` now falls back to the v36 deterministic
phonotactics when the seeds are unusable for any reason, records the cause in
`selected_name_root.seed_fallback`, and still passes the structure gate. This is
the same principle v38 applied to root formatting, extended to every seed-shaped
failure. Keep this fix even if the naming mechanism is replaced.

## Verification

Free: `npm run selftest` asserts that the four measured v38 rejects all score
below `Graskorin` and below zero; that selection is deterministic; that every
chosen candidate clears the floor; that 100 fixtures cover at least three
cadence families; that Adult and Evolved preserve the anchor and clear the floor;
that thin seed metadata degrades instead of throwing; and that v39 bundles the
scored-selection contract without touching capture or Evolution art.

Measured cadence balance across 200 fixtures: hard 51, liquid 51, open 49,
closed 49. The most frequent three-letter tail fell from 51/200 to 21/200.

## Paid evaluation

Seven Vision-only calls, ~$0.021, zero image generation and zero retries. Six
subjects, plus one repeat of `sepatu.jpg` to confirm the degradation fix
end-to-end. Validation was 6/6.

| Subject | Name | Cadence | Review |
| --- | --- | --- | --- |
| Monstera | `Fimdakar` | hard | pass |
| Dragon illustration | `Zolvela` | open | pass |
| Handheld console | `Vurralis` | liquid | pass, mildly name-like |
| Computer mouse | `Diskurak` | hard | borderline: `Disk-` reads as literal tech |
| Running shoe | `Dorralis` | liquid | borderline: one letter from `Doralis`, a real given name; repeats the `-ralis` tail |
| Ceramic mug | `Kurvesun` | closed | reject: `kurv-` is vulgar in Czech, Slovak, Hungarian, Serbian, Croatian, and Polish |

Creative and safety success is **3/6**. That beats v38's 1/6 and matches v34,
and the cadence balance held. It is still not a pass.

## Decision

V39 rejected. Production remains capture v31 + evolution v30. The structure gate
and the seed-fallback fix stay in the shared runtime because both are measured
improvements, but the version is not promoted.

The residual failures are a different class from every previous rejection:
`Kurvesun` is not a weak word, it is a word that means something offensive in six
languages, and `Dorralis` is not badly formed, it is a real person's name minus
one letter. Neither is visible to phonotactics, and v35 already measured that the
model cannot be trusted to assert it.

Across v35 through v39 four independent generation mechanisms — model
self-review, pure server hash, hybrid semantic roots, and scored candidate
selection — all cap between 0/6 and 3/6, and the residual is always a lexical
fact about the real world. A further generation-rule revision is therefore
predicted to land in the same band.

The next version must change **what evidence is available at selection time**,
not how candidates are formed. Options, in ascending cost:

1. ship a small offline blocklist of profanity stems and high-frequency
   name/brand affixes, applied as another deterministic gate over the existing
   32 candidates — bounded, no runtime dependency, but a maintained list;
2. have Vision return several fully formed candidates and let a separate,
   cheaper review call rank them, so the asserting model is not the authoring
   model;
3. accept operator review for the small number of names players actually keep,
   as Sugarworks v6 already did successfully.

## Independent review sources

- [`kurva` in Czech, Slovak, Hungarian, and Serbian](https://en.wiktionary.org/wiki/kurva)
- [Czech dictionary entry marking `kurva` as vulgar](https://ssjc.ujc.cas.cz/search.php?heslo=kurva&hsubstr=no)
- [`Doralis` as an existing given name and surname](https://forebears.io/surnames/doralis)
- [v38 provenance and its rejected names](2026-08-19-anima-name-lineage-v38.md)
