---
name: godot-ultimate-mode
description: A complete Godot 4.x game-development operating mode that combines scope control, architecture, typed GDScript, gameplay, UI/UX, accessibility, animation, game feel, audio, VFX, shaders, persistence, debugging, profiling, optimization, testing, and a mandatory final implementation review. Use for building, changing, debugging, optimizing, or reviewing Godot games; triggers include "godot ultimate mode", "ultimate godot", "build this Godot feature properly", "bikin fitur Godot lengkap", and requests that need several game-development disciplines at once.
metadata:
  short-description: Build, polish, verify, and review Godot games
  version: "1.0.0"
  author: Ryan Setiawan
  date: "2026-08-16"
---

# Godot Ultimate Mode

Use one staged workflow for Godot work. Do not apply every specialty to every
task. Activate only the domain gates touched by the requested player experience.
The goal is a small, playable, maintainable change—not a showcase of patterns.

## Authority and conflict order

Resolve conflicting advice in this order:

1. The user's current request and explicit constraints.
2. Repository rules such as `CLAUDE.md`, `AGENTS.md`, `.cursor/rules`, engine
   version, project settings, and established local patterns.
3. Runtime evidence from the actual project, tests, profiler, target device, and
   debugger.
4. Current official Godot documentation for the project's engine version.
5. This skill and its bundled references.

Never replace a working project convention with a generic "best practice"
without concrete evidence. Never invent APIs from memory when the installed
engine or docs can verify them.

## Phase 0 — Understand before changing

Inspect the real flow end to end before editing:

- Identify the Godot version, renderer, target platforms, project root, autoloads,
  input actions, main scenes, and relevant repository rules.
- Trace state ownership, callers, signals, scene instances, resources, and
  persistence boundaries around the requested behavior.
- For a bug, reproduce the symptom and collect runtime evidence. Fix the shared
  root cause, not only the reported screen or caller.
- For a feature, state the smallest player-visible acceptance result in one
  sentence. Ask only for choices that materially alter behavior or architecture.
- Preserve existing save compatibility, input bindings, scene ownership, and
  public signal contracts unless the request explicitly changes them.

When a structured Godot bridge such as GodotIQ is available, use its project,
scene, dependency, signal, validation, runtime, and screenshot tools instead of
guessing from raw scene text. Follow that bridge's repository rules.

## Phase 1 — Decide what deserves to exist

Climb this ladder and stop at the first answer that solves the task:

1. Can the requested behavior be omitted or narrowed without losing the goal?
2. Does the project already have a component, resource, scene, theme, audio bus,
   animation helper, pool, save path, or test harness to reuse?
3. Does Godot already provide the feature through a native node, Resource,
   signal, Container, AnimationPlayer, AudioBus, InputMap, server API, or import
   setting?
4. Can one existing function or scene be corrected instead of adding a system?
5. Only then write the minimum new code and data needed.

Avoid speculative managers, global buses, plugin dependencies, universal state
machines, object pools, and settings. Add them only when measured scale or
multiple real consumers justify them. Never be minimal about security, data-loss
prevention, accessibility, target-device calibration, or explicit requirements.

## Phase 2 — Establish ownership and architecture

For every changed state, answer:

- Who owns the data?
- Who is allowed to mutate it?
- Who needs to observe the change?

Use these Godot defaults unless the project says otherwise:

- Signals travel up; direct method calls travel down within an owned scene.
- Presentation reads state and emits intent. It does not become gameplay
  authority.
- Use `Resource` for serializable, Inspector-authored data; `RefCounted` for
  transient logic/data packets; `Node` only when scene-tree lifecycle, processing,
  signals, or transforms are required.
- Prefer composition and small scenes over deep inheritance.
- Keep autoloads few and focused on truly global infrastructure or durable state.
- Use typed GDScript, typed signals, `@onready`, stable unique node names, and
  `is_instance_valid()` where references may outlive nodes.
- Give each animated property, game state, and persisted field one writer at a
  time. Competing tweens, AnimationPlayer tracks, UI previews, and server
  responses are ownership bugs.
- Keep gameplay in fixed physics ticks where collision or deterministic movement
  matters. Render-only feedback belongs in frame updates or animation systems.

Before adding an abstraction, name its current consumers. One consumer usually
means a direct implementation is cleaner.

## Phase 3 — Activate relevant domain gates

Read `references/domain-gates.md`, but apply only the sections touched by the
task.

### Gameplay, physics, and input

Use InputMap actions rather than physical keys. Separate player intent from
simulation so controller, touch, AI, replay, and networking can share behavior.
Keep collision layers/masks explicit. Treat feel features—buffering, coyote time,
anticipation, hit pause, camera response—as gameplay requirements only when they
serve the genre and requested mechanic.

### Game UI and UX

Use Containers, anchors, Themes, type variations, safe areas, and a deliberate
focus graph. Every action must work with each supported input method. Keep HUD
information glanceable during motion, never encode meaning by color alone, and
provide visible focus, readable text, adequate touch targets, localization, and
reduced-motion behavior. UI sends intent and renders authoritative state.

### Animation and game feel

Choose one authority: `AnimatedSprite2D` for frame animation, `AnimationPlayer`
for reusable timelines and method/audio tracks, `AnimationTree` for real
blending/state graphs, and `Tween` for dynamic one-off transitions. Synchronize
gameplay events explicitly. Kill or replace conflicting tweens. Motion must
communicate state, timing, weight, or consequence—not decorate every control.

### Audio

Route Music, SFX, UI, Voice, and ambience through deliberate buses. Use global,
2D, or 3D players according to spatial need. Convert linear settings to decibels,
cap repeated voices, vary repetitive SFX subtly, and pair important audio with
visual or haptic feedback. Audio cannot be the sole carrier of critical
information.

### VFX and shaders

Start with built-in materials, particles, AnimationPlayer, and simple shaders.
Make one-shot effects self-cleaning. Define particle bounds and platform budgets.
Prefer uniforms and shared materials over per-instance duplication. Test shaders
on the actual renderer and lowest target device; a beautiful effect that breaks
the frame budget is unfinished.

### Persistence and online authority

Persist data, never live Nodes. Use `user://`, explicit schema versions,
validation, safe defaults, and migration paths. Make writes recoverable where
progress loss matters. Treat loaded saves, network payloads, and user content as
untrusted. Never let a client decide authoritative currency, inventory, rewards,
or competitive outcomes.

### Performance

Profile before optimizing. Establish a target frame budget and test a release
build on target hardware. Locate whether the bottleneck is script, physics,
rendering, memory, loading, UI, audio, or networking. Apply the smallest measured
fix, then measure again. Pooling, MultiMesh, threaded loading, lower-level server
APIs, and custom LOD are escalation paths—not defaults.

## Phase 4 — Implement and verify in tight loops

For each coherent change:

1. Make the smallest edit that satisfies the acceptance result.
2. Parse/validate the changed script or scene immediately.
3. Run the narrowest existing automated check that can fail for this behavior.
4. Exercise the scene or flow at runtime and inspect debugger errors.
5. For visual changes, capture and inspect the relevant resolution/state.
6. For input, animation, audio, mobile, or performance work, test the actual
   interaction—not only static code.

Non-trivial logic leaves one runnable regression check. Prefer an existing test
harness; otherwise add the smallest headless assertion or scene test. Do not add
a test framework solely for one check. Visual polish also needs visual QA, and
performance claims need before/after measurements.

## Phase 5 — Mandatory final review and auto-fix

Before declaring completion, review the resulting diff and runtime behavior:

1. **Spec and player experience:** Does it do exactly what was requested? Are
   failure, cancel, pause, resume, and boundary states coherent?
2. **Godot lifecycle:** Are node readiness, freeing, signals, async work,
   physics timing, resource sharing, and scene ownership safe?
3. **Architecture and clean code:** Is ownership clear? Are names and functions
   readable? Did the change reuse canonical project helpers and avoid accidental
   globals or duplicate authorities?
4. **UI/UX and accessibility:** Are supported inputs, focus/back navigation,
   safe areas, text, contrast, color redundancy, localization, touch size, and
   reduced motion covered where relevant?
5. **Animation, audio, and VFX:** Is timing synchronized, interruption safe,
   feedback layered but restrained, and lifecycle cleanup deterministic?
6. **Persistence and security:** Are external values validated, secrets absent,
   saves compatible, and authoritative state protected?
7. **Performance:** Did the change introduce hot-path allocations, repeated tree
   searches, unbounded work, synchronous loading, excessive draw/audio voices,
   or unjustified processing?
8. **Verification:** Do tests, parser/import checks, runtime checks, screenshots,
   target-device checks, and measurements match the risk?

Assign confidence to findings. Automatically fix findings at 80% confidence or
higher when the fix is in scope, reversible, and does not change product intent.
Do not silently perform broad refactors, destructive migrations, paid calls, or
unrequested asset generation. Rerun affected verification after every auto-fix.
If no high-confidence issue remains, state that the implementation review
passed. If a blocker needs user input or unavailable hardware, report it
explicitly instead of claiming completion.

## Final response

Lead with the outcome. Then report:

- what changed,
- the most relevant verification performed,
- the final review verdict,
- any real blocker or target-device check still required.

Keep the report proportional to the task. Do not dump the entire checklist.

## Deactivation

“Stop Godot ultimate mode”, “normal mode”, or an equivalent instruction returns
to the default workflow.
