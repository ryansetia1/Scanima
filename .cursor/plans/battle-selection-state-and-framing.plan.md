# Battle selection, state, and framing

## Understanding

- Team Battle selection must make the chosen members and their battle order
  unambiguous.
- The first picked Anima is slot 1 and starts the battle; reopening the builder
  preserves saved slot order.
- A Team win uses **Next Battle**; loss, draw, or forfeit uses **Try Again**.
  Both return to the builder with the current roster preselected.
- Duel presentation state must not leak a Retreating plate into a later session.
- Leaving or backing out during Team rival search must always restore the Duel
  lobby instead of leaving the Duel entry hidden.
- Duel and Team static arenas should match Expedition's visual balance: 40–45%
  open sky, 22–26% continuous floor, and fighter foot-contact at the shared 91%
  ground line.
- Full art parity requires six bounded GPT Image 2 medium calls: Duel day/night
  in portrait/landscape and Team in portrait/landscape, with no automatic retry
  and a conservative total ceiling of US$0.42.

## Assumptions and non-goals

- Existing combat, rewards, Energy costs, backend authority, and rival selection
  rules do not change.
- Team Battle remains builder-first; the result CTA does not create an instant
  rematch path.
- Team Battle remains a single-lighting arena; no Team day/night system is added.
- Existing API-key, provenance, explicit-cost, and one-call-per-process guards
  remain intact.

## Decision log

1. Use explicit pick order as the sole roster-slot authority. `ItemList` index
   order is rejected because it silently changes the starter.
2. Draw numbered 1–4 badges from that same ordered state. A plain checklist is
   rejected because it cannot communicate which Anima starts.
3. Use **Next Battle** after a win and **Try Again** after a loss. Both open the
   current ordered roster in the builder.
4. Clear transient event-plate state at Battle view lifecycle boundaries and
   close Team sub-mode before busy guards can block Duel restoration.
5. Regenerate all six dependent arena assets rather than mixing old and new
   Duel geometry. The accepted framing fixes composition and 91% ground contact
   in source art, then uses normal 1.0× cover and centered 0.5 pan instead of the
   old 1.18× crop locked near the bottom.

## Verification

- Add focused headless regressions for ordered selection, saved-order restore,
  result copy, Retreating cleanup, and Team-to-Duel restoration.
- Run the Battle/UI Godot suite and relevant localization checks.
- Review portrait and landscape Duel/Team screenshots against Expedition,
  including day/night geometry alignment.
- Validate changed GDScript and check Godot parser/runtime errors.
