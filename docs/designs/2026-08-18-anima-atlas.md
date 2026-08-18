# Anima Atlas MVP

Status: implemented and verified; server migration and Gallery function version
3 are live, while new APK distribution remains pending, 18 August 2026.

## Intent

Anima Atlas is the player's record of forms they have created or actually met
in Battle. It replaces the public Gallery Feed rather than becoming a second
art browser beside Collection.

The Atlas has one two-column grid with four filters:

- **All** — every unlocked form plus undiscovered Expedition silhouettes.
- **Scanned** — forms created by the player.
- **Expedition** — the finite cast of a selected chapter.
- **Duel** — forms belonging to other Seekers that were actually faced in Duel.

Only Expedition has a completion count. The set of player-created Anima is
unbounded, so Duel and All never claim a global completion percentage.

## Player contract

- Hatchling, Adult, and Evolved are separate Atlas entries.
- A successful Scan registers the Hatchling. A committed evolution registers
  the resulting form.
- An Expedition's roster appears as silhouettes. Its opening active form is
  registered when the authoritative encounter starts. A reserve is registered
  only when an authoritative `switch` or `final_ace` event brings it into the
  arena.
- A player-owned opponent is registered only when the normal Duel matchmaker
  selects it and the authoritative session is committed. The Atlas does not
  alter balance gates, level-sync opponents, or prefer unseen opponents.
- Repeated encounters update the last-seen time and encounter count; they do
  not create duplicate entries.
- An unlocked detail shows its static encounter profile: generated name, art,
  form, elements, safe traits, height, attributes, Attack, and Special. Duel
  entries also show the current Seeker name of the owner. Care, nickname,
  account identifiers, and public-profile links stay private.
- The MVP grants no Bits, Cores, badge, or other reward.

## Publication and privacy

The existing Gallery publication and moderation records become the consent
registry behind the Atlas and Duel pool. The Gallery Feed itself is removed.
During rollout, installed Gallery builds keep their legacy `list`/`hide` wire
operations; the Atlas client uses `atlas_list`/`atlas_detail`, so server and APK
can be released without one temporarily interpreting the other's payload.

One Publish choice covers the Anima's whole lineage. Its consent copy must state
that other Seekers may see the generated profile and the owner's Seeker name
after facing that Anima in Duel.

Unpublish or deleting the Anima removes that lineage's non-owner Atlas
discoveries. Reporting removes it immediately for the reporter; reaching the
existing auto-hide threshold removes it for every non-owner. The owner's own
Scanned entries survive Unpublish but not deletion of the Anima/account.

The server remains the only discovery authority. The client cannot submit a
form ID to unlock. Signed player-art URLs remain short-lived. Cached thumbnails
are display-only and stop being referenced when an entry is no longer returned.
As with any downloaded image, revocation cannot erase copies already present on
a device; the bounded cache eventually evicts them.

## Data ownership

The normalized model has three responsibilities:

1. The existing publication registry owns lineage consent and moderation.
2. A form registry owns one sanitized snapshot per concrete form.
3. A discovery ledger owns the many-to-many relation between Seeker and form,
   including source, first seen, last seen, and count.

This avoids copying a complete profile into every player's row and makes
Unpublish/delete cleanup bounded and explicit.

Historical backfill includes only facts the server can prove: owned form
history, Duel sessions whose publication is still valid, the initial active
Expedition member, and members named by stored authoritative switch/final-ace
events. Ambiguous history remains undiscovered.

## Navigation

The bottom navigation becomes **Home / Scan / Battle / Collection / Menu**.
Menu is a launcher, not a persistent tab. It opens a compact popover above the
button with **Seeker Profile**, **Anima Atlas**, and **Settings**. The old burger
button is removed; the former Seeker bottom sheet is reduced to Settings only.

Settings contains Google account, Music, chapter notifications, Help, and
Delete Account. Anima Profile is opened only from Collection or the Battle
picker, and Back returns to its origin.

The existing Reduced Motion preference, UI, helper, and alternate presentation
paths are removed by explicit product decision. Normal animation timing becomes
the only path. Old local preference keys are ignored safely.

## Non-goals

- No finite global list of player Anima.
- No browsing of Anima that the player has not fought.
- No Gallery Feed, likes, comments, follow, owner profile, or direct challenge.
- No matchmaking changes, level synchronization, research battle, or reward
  economy.
- No client-authoritative discovery or permanent public player-art URL.

## Decision log

- Chose one **Anima Atlas** over separate Gallery and Codex surfaces.
- Chose a single filtered grid over separate tabs.
- Chose Battle-only discovery for other players; merely loading a card never
  counts.
- Chose unchanged fair matchmaking even when two players may never qualify to
  meet.
- Chose separate entries per evolution form.
- Chose whole-lineage Publish consent.
- Chose deletion of non-owner entries after Unpublish/delete/report instead of
  permanent encounter snapshots.
- Chose a normalized form registry plus discovery ledger over per-player
  profile copies or deriving every page from raw battle history.
- Chose no MVP rewards.
- Chose backfill of only still-valid, provable history.
- Chose the bottom-nav Menu popover and removal of the header burger.
- Chose complete removal of Reduced Motion rather than retaining a hidden
  compatibility path.
