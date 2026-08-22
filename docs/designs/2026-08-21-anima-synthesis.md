# Anima Synthesis

Status: implemented in source; rollout remains guarded by `feature_synthesis`,
21 August 2026.

## Intent

Synthesis is a non-biological experiment that combines two owned **Source
Anima** into one new, private **Result Anima**. It exists for creative surprise:
players choose which source should dominate, improve the pair's Resonance
through progression and care, then reveal a coherent design that did not exist
before.

Synthesis is not breeding. Source Anima are never consumed, no family terms
appear in player copy, and a Result is simply another Anima that may later be
used as a Source.

## Player contract

- Both Source Anima remain playable.
- Each Source must be ready, not Dormant or evolving, and at least Level 10.
- The two Source IDs must differ.
- Synthesis always uses each Source's current committed form as its visual and
  data reference. Historical unlocked forms remain visible elsewhere but cannot
  be selected for Synthesis.
- The player chooses **Dominant A**, **Balanced**, or **Dominant B**.
- One unordered Source pair can succeed once in each mode, for at most three
  Results. A failed attempt does not consume that mode.
- Results may be used in later Syntheses after reaching Level 10. There is no
  generation-depth or relationship restriction.
- Every Result starts as a Hatchling at Level 1.
- A successful attempt costs 1 Genesis Core and 250 Bits.
- Only one Synthesis may be active per account.

## Resonance

The server computes and rolls the authoritative chance:

```
40
+ Level bonus        0..20
+ current Care       0..20
+ stat/element fit   0..15
+ dominant-mode      0 or 10
+ calibration        0..20
```

The final value is clamped to 100%. Level bonus grows from Level 10 to Level 40.
Care uses the authoritative Hunger, Energy, and Hygiene of both Sources after
decay. Affinity compares normalized base-stat shapes and source elements.
Dominant A/B receives 10%; Balanced receives none. Each prior Resonance failure
for that exact pair and mode adds 5%, to a maximum of 20%.

The UI shows the percentage and its breakdown before confirmation. A failure:

- performs no LLM or image-generation call;
- spends no Core or Bits;
- reduces each Source's Energy by 10;
- starts a one-hour cooldown for that pair and mode; and
- increases Calibration by 5% for its next attempt.

Feature availability, ownership, status, current-form parity, balances, spend
cap, and active-Synthesis limit are checked before the roll. A system rejection
is not a Resonance failure and applies no penalty.

## Guided inheritance

The selected mode supplies weights of 70/30, 50/50, or 30/70. A Vision LLM sees
one private Idle crop from each current form plus sanitized source metadata and
returns a validated Synthesis Plan.

### Naming

Result names use the same v41 morpheme pipeline as Scan. The Planner returns
six ranked `name_roots`; it does not invent the final species word. The server
keeps the strongest root intact, appends an element tail, stores
`name_lineage_anchor` on the birth plan, and later Evolve reads that
synthesis generation as the capture lineage. Stored v42/v43 plans keep the
name they already reserved.

### Visual

Dominant mode takes silhouette, mobility, and body structure primarily from the
dominant Source; the other contributes material, palette, motif, or a secondary
landmark. Balanced mode must preserve at least two recognizable features from
each Source. Every plan describes one coherent creature, never two bodies
attached together or a vertical half-and-half split.

Adult and Evolved references are translated into Hatchling proportions because
the Result starts at stage 1. Existing v41 silhouette, mobility, facing,
face-age, safe-layout, and Scanima style locks still apply.

### Attributes

For each of the five base stats, the server offers four candidates: Source A,
Source B, weighted blend, or a bounded remix near the source range. The LLM
chooses candidate kinds and explains the semantic fit; it never supplies raw
numbers.

The server constructs the final values, clamps each to 10..95, and normalizes
the total to the weighted average power budget of both Sources. Source Level and
stage affect Resonance, not Result power. Synthesis therefore creates a
different build without granting free combat strength.

### Elements and moves

The LLM may select primary and optional secondary elements freely from the
existing 18-element roster when justified by the coherent visual concept.
Primary and secondary cannot match. No new element value may be invented.
Attack/Special names and effects are derived only after elements are validated.

Rarity is descriptive and never changes combat power. Body height remains a
bounded visual property.

## Player flow

Synthesis Lab is opened from the Collection header or from an Anima Profile
shortcut that preselects Source A:

1. Tap the Source A visual card and choose from a Collection-style art list that
   shows art, Level, and elements.
2. Choose Source B the same way. Both selected current-form artworks remain
   visible in the Lab; there is no form picker.
3. Choose Dominant A, Balanced, or Dominant B.
4. Review Resonance as a scannable panel: hero chance, factor chips, and a
   five-stat grid.
5. Attempt Synthesis opens a confirmation dialog for the 1 Core + 250 Bits
   success cost and the miss penalty, then starts the attempt.
6. On failure, open a dedicated dialog. A Resonance miss shows its chance,
   care/cooldown consequence, and Calibration; a technical failure explicitly
   confirms the Core + Bits refund. Terminal dialogs consume backdrop taps and
   Back/cancel input; only their explicit acknowledgement button closes them.
7. On success, replace the editor with a dedicated Incubator Capsule state.
   The unknown private Result forms in the capsule while two compact Source
   cards preserve each Source's art, name, Level, and elements.
8. When art is ready, open a success dialog and animate the Result portrait into
   view. **View Result** opens its profile and then offers Rename.

The persistent shell may change tabs while generation runs. Restart replays the
same idempotency key and resumes the same Result instead of rolling or charging
again. The capsule is an indeterminate activity indicator: it never invents a
percentage or ETA, and its ambient drawing stops while the state is hidden.

## Synthesis History and Atlas

The Result profile stores a private Synthesis History snapshot containing:

- both Source IDs and display names (nickname first);
- current form/stage at claim time and a small private thumbnail;
- mode, successful Resonance, and date; and
- the validated inheritance summary, shown only on demand from the
  Resonance help control.

Source rows may later evolve or be deleted without corrupting this record.
Model input and History art are stored as separate derivatives from the same
private Source sheet. The model reference keeps its chroma-green matte, while
History uses `cropIdleThumb()`—the same transparent Idle crop as Atlas. Legacy
successful Results are repaired lazily on the first History request. Profile
reserves two fixed-size art slots until those transparent PNGs arrive, but each
loading pulse is a compact centered squircle rather than a full-width slab. The
client never reconstructs alpha from green pixels. Profile actions sit directly
below identity; History and stat cards do not need to be traversed before Use in
Synthesis, Publish, or Delete.

Publishing a Result to Atlas also publishes the two names, current-form
thumbnails, and mode as a snapshot attached to that Result. The Publish
confirmation must explicitly disclose this. It does not publish the complete
Source profiles as separate Atlas entries.

## Authority, privacy, and recovery

- The client sends intent and renders previews; Postgres owns eligibility,
  Resonance, randomness, currencies, cooldown, mode uniqueness, and Result rows.
- Money RPCs are service-role-only. Public tables have RLS enabled and no client
  write path for Synthesis state.
- Source art stays private and is read through service-role signed URLs. The
  client reuses the Collection thumbnail cache for selection, while a private
  two-source reference board is persisted before temporary Source Delete/Evolve
  locks are released.
- `preview_synthesis` and `attempt_synthesis` reject any supplied stage that
  differs from `animas.stage`; old clients cannot restore historical-form
  selection.
- One successful attempt creates the Result, generation, Core ledger, Bits
  ledger, and mode lock in one transaction.
- A technical LLM, dispatch, webhook, or post-processing failure marks the
  Result failed, refunds Core and Bits exactly once, and reopens the mode. It
  does not increase Calibration.
- Planner prose is clipped to its documented field limits at the service trust
  boundary. Prompt v43 also exposes those limits to Vision and gives the larger
  plan enough output budget, so harmless verbosity no longer converts a paid
  attempt into a technical failure.
- Image generation is never retried automatically without the same idempotency
  record and an explicit bounded policy.

## Non-functional defaults

- Failed attempts should return in under one normal API round trip; successful
  generation remains asynchronous and uses the existing incubator pattern.
- Synthesis participates in `daily_spend_cap_usd`.
- Cost, minimum Level, Resonance weights, Energy penalty, and cooldown are
  server config so balancing does not require a new APK.
- Telemetry records chance, mode, outcome, latency, and refund reason. It does
  not make private art public.
- Touch targets, focus/back navigation, localization expansion, portrait and
  landscape layouts, and interruption-safe animation are acceptance
  requirements.

## Non-goals

- No Source consumption, fertility, family tree, age, or biological terminology.
- No unrestricted LLM-authored numeric stats or new element identifiers.
- No preview image, image reroll, multiple candidate eggs, or paid generation
  on Resonance failure.
- No automatic Atlas publication.
- No trading, real-time PvP, or power exclusive to Synthesis.

## Decision log

- Chose creative surprise over Monster Rancher's retirement/offspring loop.
- Chose persistent Sources to protect attachment and four-Anima rosters.
- Chose three modes per unordered pair over unlimited rerolls or one fixed mix.
- Chose a Level 10 gate with the current committed form as an absolute Source
  invariant; historical-form combinations add ambiguity without improving the
  experiment.
- Chose open recursive Synthesis with no generation-depth restriction for the
  simplest player rule; Core, Bits, and per-pair modes remain the cost brakes.
- Chose visible Resonance that can reach 100% over hidden permanent RNG.
- Chose Energy/cooldown consequences over losing currency on failure.
- Chose Guided Synthesis over a free-form LLM or deterministic weighted average.
- Chose 1 Core + 250 Bits because every success creates one paid private sheet.
- Chose public Source snapshots with explicit Result-publish consent over silent
  leakage or automatically publishing full Source profiles.
- Chose a dedicated Incubator Capsule over leaving the completed editor disabled:
  it communicates the state clearly, keeps both Source identities visible, and
  avoids presenting inactive controls as if they still matter.
