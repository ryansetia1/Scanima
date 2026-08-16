# Godot Ultimate Mode

`godot-ultimate-mode` is one end-to-end operating skill for professional Godot
4.x game development. It combines the useful parts of the installed Godot,
game-UI, animation, sound, clean-code, optimization, debugging, and review skills
without loading every discipline into every task.

The workflow starts by reading the project and defining the smallest
player-visible result. It then establishes state ownership and activates only the
domain gates the task needs: gameplay/physics/input, UI/UX/accessibility,
animation/game feel, audio, VFX/shaders, persistence, or performance. Every
non-trivial change receives a runnable check. Before completion, the skill reviews
the implementation across correctness, Godot lifecycle, architecture,
accessibility, feedback systems, persistence/security, performance, and
verification. High-confidence in-scope findings are fixed automatically and the
checks are rerun.

## Usage

Invoke it explicitly with prompts such as:

- `/godot-ultimate-mode add a responsive inventory screen`
- `Use Godot ultimate mode to implement this combat animation and sound`
- `Bikin fitur dash ini pakai godot ultimate mode`
- `Review and finish this Godot implementation properly`

The skill also triggers on broad Godot tasks that clearly need multiple game
development disciplines.

## Design approach

This is an orchestrator, not a demand to over-engineer every feature. A gameplay
bug may need only diagnosis, one shared fix, and a regression check. A complete
screen may activate UI, input, animation, audio, and visual QA together. Existing
project rules always win over generic advice, and optimization begins with
profiling rather than automatic pooling or rewrites. The bundled source map
records which installed skills supplied each discipline and how conflicting or
version-sensitive recommendations were resolved.

## Files

- `SKILL.md` — staged operating workflow and mandatory final review.
- `references/domain-gates.md` — focused checklists for each game-development
  discipline.
- `references/source-map.md` — installed source skills, conflict policy, and
  official external references.
- `evals/evals.json` — representative prompts used to check expected behavior.

## Installation

The canonical source lives in:

```text
.agents/skills/godot-ultimate-mode/
```

Global Cursor and Claude installations should be symlinks to that directory so
repository updates immediately update both platforms:

```bash
ln -sfn "$PWD/.agents/skills/godot-ultimate-mode" \
  "$HOME/.cursor/skills/godot-ultimate-mode"
ln -sfn "$PWD/.agents/skills/godot-ultimate-mode" \
  "$HOME/.claude/skills/godot-ultimate-mode"
```

Use “stop Godot ultimate mode” or “normal mode” to deactivate the workflow.
