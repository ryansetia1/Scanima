# Anima Name Lineage v41

Status: implemented and paid Vision-evaluated 19 August 2026 across two rounds;
**awaiting operator judgement**, never promoted or live. Production remains
capture v31 + evolution v30.

V40 was implemented (syllable mix, frozen profanity blocklist, cadence
distribution fix) but superseded before any paid evaluation: the Pokémon naming
research changed the premise, and evaluating one more phonotactic transform
would have measured the wrong thing.

## Why the premise was reversed

Versions v32–v40 all chased the same target — a word that collides with nothing
in the real world — through six different mechanisms, and every one of them
landed in the same 0/6–3/6 band. The research comparing every Pokémon generation
against our own rules found the target itself was wrong:

- Pokémon ships names that collide with real words, brands, and people
  (Onix/Onyx, Ditto, Golem, Arbok, Eevee) and reads fine anyway.
- Our rules rejected meaningful names for collision risk while accepting
  meaningless ones that passed phonotactics, which is how `Zimnuzem` and
  `Vadvuter` got through while `Glazel` was thrown away.
- The operator-approved Sugarworks lineup — Gellume, Velastra, Noxcoil,
  Cindrusk, Rimespin, Pralith, Duskadon, Ambermire, Nimbelisk — is not built
  from unique sounds at all. Every one is **two readable morphemes**.

So v41 stops transforming the root. The model's morpheme survives intact as the
first half of the name and as the lineage anchor; the server appends a meaningful
morpheme instead of a phonetic suffix. The dictionary, compound, and collision
rules are withdrawn. The frozen profanity blocklist stays, because that is a
safety floor and not a taste rule.

## Mechanism

The head comes from Vision, ranked: exactly six readable morphemes of 3–5 letters
with a channel and one visible piece of evidence. The server discards entries
that copy the source label and takes the strongest survivor.

The tail comes from a curated table keyed by the creature's element, so a
material cue and a name cue never contradict each other:

| Family | Elements | Tails |
| --- | --- | --- |
| mineral | metal, stone, ceramic, glass | lith, crag, shard, forge, spire, elisk, onyx, ingot, slate, vein, quartz, ore |
| verdant | wood, plant, food | frond, thorn, bloom, root, vine, grove, arbor, acanth, sap, bark, husk, seed |
| tidal | flow, frost | mire, rime, tide, brine, drift, eddy, abyss, silt, wake, foam, murk, shoal |
| ember | flame, spark | ember, pyre, cinder, blaze, volt, lume, arc, ignis, coal, flare, soot, kiln |
| drape | plastic, cloth, paper | weave, fold, shroud, quill, seam, husk, usk, coil, eider, twill, knot, hem, yarn |
| feral | fauna, toxin | fang, maw, talon, pelt, venom, adon, ursa, spur, howl, gnaw, prowl, sting |
| zephyr | air, sound | gale, echo, chime, plume, whorl, spin, astra, gust, hush, veer, drone |

Every family mixes one- and two-syllable tails, and that is the only lever the
server has over name length: the head belongs to Vision, so a one-syllable tail
is the only route to a two-syllable name like Noxcoil or Pralith.

Evolution keeps the head and changes the tail. Adult continues into its own
material family so it reads as a sibling species — Bulbasaur to Ivysaur — while
Evolved reaches for a title (`sovran`, `titan`, `zenith`, `astral`, `aegis`,
`apex`, `aeon`, `aether`, plus the short `king`, `zard`, `myth`, `doom`) because
Lv36 is the payoff. Pokémon itself uses short titles that collide with ordinary
words — Nidoking, Slowking, Charizard — so those are fair here, and being one
syllable they let an Evolved name stay short. Escalation lives in what the tail
means, not in letter count.

The anatomy rule is **negative**, not positive. `planFeatureTails()` scans
`stage_brief`, `transformation_archetype`, the mobility contract, the new contour
read, and the shape budget for sixteen body features, and only what it finds may
appear — `MORPHEME_BODY_TAILS` strips every other body-part morpheme out of the
family pool, so a Plan that never mentions a coil cannot produce `Aquacoil`. What
it finds joins the pool; it does not replace it. Making anatomy win outright was
tried and measured wrong: a Plan naming one feature then locked every Adult onto
the same morpheme — `Glidhusk`, `Celerhusk`, `Glazehusk` across three unrelated
subjects. Capture deliberately keeps its body morphemes, because there the word
describes the photographed object's own material and the operator approved
`Noxcoil` and `Duskadon` through exactly that path.

Selection itself is deliberately thin: build every tail in the pool, drop the
unsafe, the unreadable, and any name already used earlier in the lineage, then
index the survivors with the visual-identity hash. There is no score, no
candidate ranking, and no fallback tiers — see "Gating removed" below.

`morphemeSeamOk()` is the one readability rule left. At most three consonants may
meet at the seam, the joined word stays within twelve letters, an elided tail
fragment must keep three letters, and it must begin with a consonant — `glide` +
`aeon` as `Glideeon` only moves the vowel pile-up rather than resolving it. A
trailing `y` counts as a vowel, since `cozy` does not end in a `zy` cluster and
treating it as one left every `y`-final head with a single legal tail.

The nine approved Sugarworks names are the calibration target, and the selftest
reassembles all nine from a head plus a tail in this table.

## Two production fixes kept regardless of the verdict

**One bad root no longer discards the other five.** Round one measured the cost:
Vision returned `wyrm` (no vowel), `stride` (six letters), and channel values
`sound` and `special` that are element names rather than channels. The v37
validator threw on the whole array for any one of them, so five of nine subjects
fell back to the v36 deterministic phonotactics that the operator had already
rejected — while five perfectly good roots sat unused in the same response.
`normalizeNameRoots(vision, allowClusters, skipInvalid)` now skips the bad entry,
records it in `selected_name_root.rejected_roots`, and honours the model's
ranking among the survivors. Round two: 9/9 anchors from Vision.

**A cluster anchor survives validation.** `validateVision` applied the v33
"pronounceable" rule after the morpheme path had already chosen the anchor, and
that rule rejects three consecutive consonants — which would have silently
replaced `cindr`, the head of the approved `Cindrusk`. The rule no longer applies
when the morpheme path owns the anchor.

## Verification

Free: `npm run selftest` 38 scenarios, bundle freshness, v41 dry run. The v41
assertions cover Sugarworks reassembly, the four measured v38 rejects still
failing the structural floor, element-to-family mapping, tail diversity, seam
rejection, graceful skipping of partial and total root failure, cluster-anchor
survival through `validateVision`, and lineage preservation for both stages.

## Paid evaluation

Two rounds, Vision-only, nine subjects each, zero image generation and zero
automatic retries. One round-one call was retried after Replicate answered
`ModelError E004` and was never billed. Approximately $0.054 total.

Round one measured the mechanism and found the discarded-root bug: 5/9 names came
from phonotactics rather than Vision, which made the round unusable as a test of
the premise. Round two, after the fix and after replacing object-noun tails
(`anvil`, `apron`, `plate`, `acorn`, `well`) with morphological ones:

| Subject | Hatchling | Adult | Evolved | Head | Read |
| --- | --- | --- | --- | --- | --- |
| glazed mug | Vitrelisk | Vitrarch | Vitrargos | `vitr` | species |
| oil lamp | Lumecrag | Lumegirt | Lumekorax | `lume` | species |
| keyed bugle | Resonelisk | Resonridge | Resonargos | `reson` | species |
| running shoe | Stridusk | Stridhorn | Stridaegis | `strid` | species |
| monstera | Verdarbor | Verdarch | Verdaegis | `verd` | botanical-scientific |
| wired mouse | Glidfold | Glidward | Glidregis | `glid` | borderline product |
| handheld console | Pixelquill | Pixelhorn | Pixelkorax | `pixel` | product |
| knit mittens | Loopfold | Loophorn | Loopkorax | `loop` | product |
| dragon illustration | Dracovenom | Dracoridge | Dracoregis | `draco` | names the kind |

Lineage is the unambiguous success. The head survives letter-for-letter across
all three stages in 9/9 cases, and it is independent of the Evolution Plan:
sweeping three different archetypes over five anchors moves only the tail, never
the anchor. That is the Pokémon pattern the operator asked for, and it needs no
paid Plan call or image generation to verify.

Register is the remaining failure, and it is now a single identifiable cause.
When the model's top-ranked morpheme is a Latin, archaic, or material fragment
the name reads as a species; when it is an everyday modern or technology word it
reads as merchandise. In four of the five weak cases the same response already
offered a better morpheme further down its own ranking — the lamp offered `vitr`
and `phial`, the mittens `fleec` and `plush`, the dragon `serpe` and `aethr`, the
mouse `plia` and `curv`. The prompt gained explicit register calibration between
the rounds and that moved the result from 3/9 to 4/9 clear plus 2 borderline, so
the instruction helps but does not settle it.

## Stage tails, rebuilt after operator review

The operator rejected the round-two stage tails on two counts, and both were
reproducible offline from the stored Vision JSON with zero further API calls.

**A tail must not promise anatomy the Plan never mentions.** `Loophorn` and
`Lumegirt` put a horn on a mitten and a lamp. `-horn` was only the visible case:
`-coil` on a console, `-pelt` on a scaled dragon, and `-thorn` on a thornless
monstera are the same broken promise, and the player sees the name and the sprite
on one screen. Fixed by making anatomy earn its place from the Plan text and by
stripping the whole class from the family pool otherwise. Re-derived over the nine
stored subjects, the neutral Plan now yields zero body morphemes at either stage,
while a Plan that states paired horns still reaches `Cylinhorn` and `Glidecrest`.

**Evolved converged on `-argos`, `-korax`, and `-aegis`.** The cause was
mechanical rather than stylistic: `monolith` and `paragon` push a five-letter head
past twelve characters, the structural floor then drops them, and `throne` can
never join at all because a `thr` onset always costs at least three consonants at
the seam. The reachable pool had quietly shrunk to three entries. The pool is now
eight short titles, and re-derivation over the same nine subjects spreads them
across four distinct morphemes on an identical Plan — the worst case, since real
Plans differ per Anima and contribute their own anatomy.

Two defects surfaced during that re-derivation and are fixed with it:
`Cylinonyx` was measured as both Hatchling and Adult, because Adult continues into
the same family pool its Hatchling drew from; and elision produced `Aquamen`,
which reads as two English words, and `Glideeon`, which stacks three vowels.

The remaining register ceiling is unchanged — it lives in which morpheme the model
ranks first, not in how the two are joined.

## Gating removed

The operator's next reading found every name three syllables long and tails still
repeating (`-weave`, `-vran`, `-eon`), and asked for the machinery to shrink
rather than grow: the name is a placeholder the player can rename, so it only has
to sound like a Pokémon name.

The three-syllable run was not a coincidence. A tail beginning with a vowel is
always two syllables in these tables, and the old seam limit of two consonants
locked every double-coda head (`dash`, `dusk`, `glaz`) onto exactly those tails —
so a one-syllable head could not produce a two-syllable name. Raising the limit to
three opens `Dashcoil` and `Duskfang` while `Cindrvolt` stays shut at four. The
repeated endings had the same shape of cause: `nameStructureScore()` plus the
`NAME_STRUCTURE_FLOOR` gate, applied on top of the seam rule, cut each family's
reachable pool to two or three entries, and a small pool repeats by arithmetic.

So the v39–v41 selection layer is gone from this path: no scoring, no 32-candidate
build, no preferred/widened/relaxed tiers. What remains is a wide pool, three
filters (profanity, seam, name already used in this lineage), and one hash index —
roughly fifteen lines replacing sixty. A twelve-letter cap inside
`morphemeSeamOk()` does the one job the scorer still had. Each family also gained
four short morphemes, since one-syllable tails are what make two-syllable names
possible at all.

Removing the tiers exposed a real crash on the way through, and it is worth
recording because it could only fail while spending money: while anatomy still
replaced the pool, a Plan naming exactly one body feature gave Evolved a
single-tail pool, Adult had already taken that name, the used-name filter emptied
the pool, and derivation threw. Letting anatomy join the pool instead removes the
class of failure, and the used-name filter inside selection is now best-effort
rather than a gate — a duplicate name is a cosmetic annoyance, a failed paid
evolution is not. The selftest covers both the crash case and the lock.

Measured over thirty heads on one identical Plan, the worst case the mechanism can
face: fifteen distinct Adult tails, densest 5/30. With real per-Anima Plans the
three evaluated subjects land on `-elder`, `-fold`, `-forge` at Adult and
`-astral`, `-doom`, `-quartz` at Evolved. The diversity metric in the selftest was
off by one — it counted the head's last letter as part of the tail and therefore
over-reported — and is fixed with this.

Measured over the nine stored round-two subjects with zero API calls: Hatchling
syllables went from 9/9 at three to 2 two-syllable, 3 three-syllable, and 4
four-syllable, with seven distinct tails; Evolved reached nine distinct tails out
of nine. Those heads are round-two's own two-syllable roots (`aqua`, `folia`,
`cylin`), so the prompt now also asks Vision to keep most roots to one punchy
syllable. Simulated across twelve one-syllable heads and eight elements, that
lands at 5 two-syllable and 7 three-syllable names with eleven distinct tails —
the Sugarworks shape. The selftest asserts a two-syllable name is reachable, so
this cannot silently drift back.

## Round three: six fresh subjects

Six paid Vision-only calls on subjects round two had not exercised — plastic
handheld, whale-oil lamp (glass), knit mitten (cloth), keyed bugle (metal),
Monstera (plant), Asian dragon illustration (fauna) — plus offline lineage
derivation. Four defects surfaced, and each one is a rule that was stated but only
half-applied.

**The anatomy rule only guarded evolution.** Capture produced `Fenesthorn` for a
thornless Monstera: exactly the `-horn`-without-horns case, on the stage the player
sees first. Capture has no Plan, but it has `signature_features` and
`creature_brief`, so `featureTailsFromText()` now serves both and capture runs the
same negative gate. The single exception is the shell class (`husk`, `usk`): every
object has an outer skin and `Cindrusk` is built exactly that way. Fur is not in
it — `Dracopelt` on a scaled dragon is the same false promise, and the first pass
that exempted `pelt`, `carapace`, and `mantle` produced it.

**Plastic drew textile morphemes.** `Pixlyarn` for a plastic console: plastic,
cloth, and paper share the `drape` family, so `yarn`, `twill`, and `eider` were
reachable for objects that are not woven. They are gone, replaced by `arc`,
`sheath`, and `ridge`, which read as fold, sheet, or shell on any of the three.

**Picking a hash bit range was still a guess.** `seed % 4` had to become
`seed >>> 24` in v40 for the same reason `seed >>> 8` gave three of six Anima the
same Adult tail here: FNV-1a is not evenly spread enough to index with directly.
`mixNameSeed()` runs one lowbias32 finalizer over all 32 bits, so any modulo is
safe and the class of bug is closed rather than moved. Measured over twenty-four
heads on one identical Plan — the worst case the mechanism can face — distinct
tails rose from 9/24 to 12–15/24 across four families.

**Elision could destroy the morpheme.** `Dracolder` from `draco` + `elder`: the
surviving fragment `lder` is not a syllable. The fragment must now open as one
consonant plus a vowel, which keeps `elisk` → `lisk` (Nimbelisk) and `adon` →
`don` (Duskadon) while rejecting `lder`.

Result, with per-Anima Plans and zero image generation:

| Subject | Element | Hatchling | Adult | Evolved |
| --- | --- | --- | --- | --- |
| handheld | plastic | Pixlusk (2) | Pixlward (2) | Pixlfold (2) |
| oil lamp | glass | Vitrore (3) | Vitrforge (3) | Vitrsovran (3) |
| mitten | cloth | Thrumridge (3) | Thrumadon (3) | Thrumzard (2) |
| keyed bugle | metal | Resonforge (4) | Resonvein (3) | Resondoom (3) |
| Monstera | plant | Fenessap (3) | Fenesbastion (4) | Feneszenith (4) |
| dragon | fauna | Dracosting (3) | Dracocoil (3) | Dracopex (3) |

Six distinct tails from six at every stage, and syllables spread 2/3/4 rather than
converging. `Dracocoil` is anatomy the Plan asked for — its brief calls the body
serpentine — which is the gate working in the direction it should.

## Decision

**Accepted and live, 19 August 2026.** Operator approved round three, and
`prompt_version` plus `evolution_prompt_version` both moved to `"v41"` in
migration `20260819120015_prompt_version_v41.sql`. `create_anima`, `evolve_anima`,
and `replicate_webhook` were deployed from source; smoke without JWT or signature
answers 401 on all three. The flip carries no art risk — all four image prompts
are byte-identical to the versions they replace, verified by shasum — and no
`generations` row was created in the window between the config flip and the
deploy. Rollback is `"v31"` for capture and `"v30"` for evolution; both remain in
the bundle. If register is the only blocker, the next step is not
another prompt revision — five versions have shown that instructions to the model
do not hold — but choosing the head server-side from the six offered morphemes,
which requires a register signal the server can actually compute.

## Provenance

- v40: implemented, superseded before evaluation.
- v39: rejected 3/6, [design](2026-08-19-anima-name-lineage-v39.md).
- v38: rejected 1/6, [design](2026-08-19-anima-name-lineage-v38.md).
- v37: rejected 0/6, [design](2026-08-19-anima-name-lineage-v37.md).
- v36: rejected 0/6, [design](2026-08-19-anima-name-lineage-v36.md).
- v35: rejected 1/6, [design](2026-08-19-anima-name-lineage-v35.md).
- v34: rejected 3/6, [design](2026-08-19-anima-name-lineage-v34.md).
- v33: rejected 1/3, [design](2026-08-19-anima-name-lineage-v33.md).
- v32: rejected 0/3, [design](2026-08-19-anima-name-lineage-v32.md).
- Pokémon comparison that reversed the premise:
  [research](../pokemon-name-research.html).

## Evaluation fixtures

Round two used three existing eval photos (`mouse.jpg`, `mug-putih.jpg`,
`sepatu.jpg`), `monsterra.jpeg`, `original-dragon-color.jpg`, the Retroid
handheld fixture converted from WebP, and three newly fetched object photos under
CC0 or public domain from Wikimedia Commons: a whale-oil lamp and knit mittens
from the Metropolitan Museum, and a keyed bugle from the same collection. The new
photos are local test fixtures downscaled to 1280 px and are deliberately not
committed, matching the rule against committing player photos or model output.
