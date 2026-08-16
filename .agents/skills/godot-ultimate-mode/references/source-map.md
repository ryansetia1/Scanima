# Source Map and Conflict Policy

This skill was synthesized on 2026-08-16 from the following skills already
installed on the device. It copies the durable operating principles needed for a
standalone workflow; it does not require those source skills at runtime.

## Primary local sources

- `ultimate-mode`: staged scope control, clean implementation, verification, and
  confidence-filtered final review.
- `godot-master`: Godot-specific state ownership, signal architecture, Resources
  versus Nodes, domain decision gates, runtime lifecycle, and profiling-first
  escalation.
- `godot-best-practices`, `godot-development`, and
  `godot-gdscript-patterns`: typed GDScript, scenes, node references, signals,
  resources, input, and project organization.
- `godot-debugging` and the Godot Master `debugging-profiling` reference:
  evidence-first diagnosis, debugger use, lifecycle failures, and regression
  verification.
- `godot-optimization`: bottleneck classification and measure-before/after
  performance work.
- Godot Master references `2d-animation`, `animation-player`,
  `animation-tree-mastery`, and `tweening`: animation authority selection,
  synchronization, interruption, and lifecycle safety.
- `godot-particles` and `godot-shaders-basics`: VFX ownership, cleanup, renderer
  cost, shared materials, and platform validation.
- `godot-save-load-systems`: versioned persistence, validation, migration, and
  recovery.
- `godot-ui` and `godot-ui-theming`: Control/Container layout, shared Theme
  resources, focus, responsiveness, and input routing.
- repository skill `game-ui-design`: HUD information hierarchy, controller-first
  navigation, safe areas, readability during motion, accessibility, and target
  hardware testing.
- `sound-engineer` and Godot Master `audio-systems`: bus routing, spatial choice,
  UI audio, adaptive music, concurrency, and audio budgets.
- `clean-code`: intention-revealing names, focused functions, readable control
  flow, and restrained comments.
- `code-review-and-quality`: correctness, architecture, security, performance,
  verification, severity, and high-confidence review.

## Conflict resolution applied

Several source files contain broad or version-sensitive absolutes. This skill
intentionally replaces them with evidence-based rules:

- Project conventions and the installed Godot version beat generic folder
  structures or API examples.
- Native Godot features and existing project helpers beat new managers,
  frameworks, or dependencies.
- Signals are not mandatory for every call. Use direct calls down an owned scene
  and signals up or across ownership boundaries.
- Object pooling, global buses, AnimationTree, procedural audio, custom shaders,
  threading, MultiMesh, and low-level Server APIs are escalation tools, not
  defaults.
- Performance numbers are targets to establish per project, not universal facts.
  Profile a release-like build on target hardware.
- Accessibility requirements are adapted to the real viewport and physical
  device scale instead of blindly copying web pixel values.
- Save formats are selected by data needs. JSON is not automatically preferred.
- Debug-only assertions never replace release-path validation.
- Examples from older skills are illustrative, not proof that an API exists in
  the project's engine version.

## External references

No internet search was required to cover the requested domains because the local
skill set was complete. For version-sensitive implementation details, consult
the current official documentation that matches the project:

- Godot stable documentation: https://docs.godotengine.org/en/stable/
- Godot class reference: https://docs.godotengine.org/en/stable/classes/
- Godot engine repository: https://github.com/godotengine/godot

Use community articles only after official docs and runtime evidence, and verify
their Godot version before applying code.
