# Godot Domain Gates

Open only the sections relevant to the current task. Repository conventions and
measured project behavior override generic guidance.

## 1. Project and GDScript gate

- Confirm the installed Godot version and renderer before using version-sensitive
  APIs.
- Follow local naming, typing, folder, scene, and autoload conventions.
- Keep scripts typed. Use typed arrays/signals where the codebase supports them.
- Cache stable node references with typed `@onready` members. Prefer unique names
  or exported references over deep paths.
- Use `is_instance_valid()` when asynchronous work, queued frees, or cross-scene
  references can outlive a Node.
- Keep functions focused on one level of abstraction. Avoid large lifecycle
  methods that mix input, simulation, persistence, and presentation.
- Prefer feature-local signals. Add global bus events only for genuinely global
  lifecycle facts, and keep the event set small.
- Duplicate mutable `Resource` instances or mark them local to scene when each
  instance needs independent runtime state.
- Avoid `load()` in hot paths. Use preload for small fixed assets and threaded
  loading for large runtime assets when measurements justify it.
- Preserve scene isolation: reusable scenes should run or degrade safely without
  hidden dependencies on a specific parent.

## 2. Gameplay, physics, and input gate

- Read actions from InputMap, not hardcoded keys or controller buttons.
- Model intent independently from its source so player, touch, controller, AI,
  replay, or server input can use the same simulation entry point.
- Use `_physics_process()` for movement and collision-sensitive state. Do not
  yield inside physics processing.
- Make collision layers answer “what am I?” and masks answer “what do I query?”
- Avoid modifying physics state while queries are being flushed; defer only the
  specific tree/shape change required by the engine, not arbitrary initialization.
- Keep animation from becoming the sole authority for collision or damage unless
  the project deliberately uses method tracks and tests their timing.
- For action mechanics, evaluate genre-relevant feel: input buffering, coyote
  time, anticipation, recovery, cancel windows, hit pause, knockback, camera
  response, and readable telegraphs. Implement only what the mechanic needs.
- For multiplayer or durable economies, clients send intent; the authority
  validates and calculates outcomes.

Verification:

- Exercise every supported input path and cancel/back path.
- Test low/high frame rates where movement timing matters.
- Verify collision edges, repeated input, interrupted actions, pause/resume, and
  scene transitions.

## 3. Game UI and UX gate

Structure:

- Use `Container` nodes for layout, anchors for relationship to parent bounds, and
  a shared `Theme` for fonts, colors, spacing, icons, and semantic variations.
- Treat UI as a projection of state. Buttons emit intent; controllers or owning
  systems mutate gameplay.
- Keep transparent decorative Controls from swallowing input. Audit
  `mouse_filter`, focus modes, modal layers, and back behavior.
- Establish a small intentional layering scale instead of escalating `z_index`.

Player usability:

- Critical information must be glanceable during motion and readable over varied
  backgrounds. Use outlines, shadows, or panels where the world can reduce
  contrast.
- Every element must earn screen space. Prefer contextual visibility and
  progressive disclosure to a permanently crowded HUD.
- Keep critical text and interaction inside platform safe areas. Account for
  notches, gesture areas, overscan, and the project's viewport-to-screen scaling.
- Resolve prompts from current InputMap bindings and active input family. Never
  hardcode “Press A” or a default keyboard key.
- Build and test a complete controller focus graph, including modal focus trap,
  focus restoration, tab changes, and an escape route from every screen.
- Make touch targets meet the target platform's physical guidance; a small icon
  may live inside a larger hit target.
- Never encode enemy/ally, rarity, damage type, or error state by color alone.
  Add shape, icon, pattern, position, or text.
- Support localization expansion and avoid player-facing literals when the
  project has a translation catalog.
- Motion guides attention. Keep common UI transitions short and interruptible.
  Respect reduced motion with instant or opacity-only alternatives.

Visual QA:

- Inspect representative narrow, wide, short, tall, low-resolution, and target
  hardware layouts—not only the editor viewport.
- Test keyboard/controller-only and touch-only completion where supported.
- Test longest localized strings, empty/loading/error/full states, focus visuals,
  modal stacking, and UI over the brightest and busiest gameplay backgrounds.

## 4. Animation and game-feel gate

Choose the lightest authority:

- `AnimatedSprite2D`: isolated frame animation.
- `AnimationPlayer`: reusable timelines, multiple properties, method/audio
  events, UI sequences, props, and cutscenes.
- `AnimationTree`: actual blending, layered motion, directional blend spaces, or
  complex state graphs.
- `Tween`: dynamic, runtime-calculated, one-off transitions.
- Shader/MultiMesh: very large crowds or repeated procedural movement only after
  profiling proves scene-tree animation is the bottleneck.

Rules:

- One system writes a property at a time. Stop or kill the old tween before
  replacing it. Do not call `AnimationPlayer.play()` while AnimationTree owns it.
- Use `animation_finished` for non-looping clips and loop-specific signals for
  loops.
- Keep AnimationPlayer method tracks discrete. Add/reset baseline tracks when
  animated properties must restore.
- Synchronize footsteps, hit frames, VFX, and audio with explicit animation
  events or tested frame markers—not arbitrary timers.
- Keep physics-moving animation in physics callback mode or extract root motion
  into the CharacterBody simulation.
- Define interruption behavior: what happens when hit, paused, scene-changed,
  hidden, or freed halfway through the motion?
- Animation is communication. Use anticipation for intent, impact for consequence,
  recovery for timing, and restrained ambient motion for life. Avoid motion on
  every UI element.

Verification:

- Test rapid state changes, direction flips, repeated taps, pause/time-scale,
  reduced motion, off-screen culling, and node deletion during animation.
- Watch for one-frame wrong poses, snapping, foot sliding, conflicting writers,
  and event duplication.

## 5. Audio gate

Architecture:

- Route audio to deliberate buses such as Music, SFX, UI, Voice, and Ambience.
  Keep Master for final control/limiting.
- Use `AudioStreamPlayer` for non-spatial music/UI/voice,
  `AudioStreamPlayer2D` for positional 2D, and `AudioStreamPlayer3D` only when 3D
  attenuation and spatial cues matter.
- Convert linear slider values with `linear_to_db()` and handle mute near zero.
- Use appropriate import modes: streaming for long music/voice, memory-efficient
  samples for short frequently played SFX.

Game feel and safety:

- Keep UI feedback subtle, short, and consistent in timbre.
- Pair important audio cues with visual or haptic feedback.
- Vary repeated sounds within a controlled pitch/volume/sample range.
- Cap concurrent copies of the same loud SFX. Pool voices only when creation
  churn is measured or the project already has a pool.
- Crossfade or musically transition background tracks when abrupt cuts would
  break the experience.
- Configure attenuation for spatial players and test headphone/speaker behavior.
- Handle pause, app background, route changes, and platform interruptions where
  the target platform exposes them.

Verification:

- Check every player has the correct bus and stream.
- Test volume sliders, mute/unmute, repeated impacts, pause/resume, scene changes,
  headphones, and target-device output.
- Listen for clipping, missing cues, fatigue, phase buildup, and spatial sounds
  that remain audible outside their intended range.

## 6. VFX, particles, and shader gate

- Start with built-in nodes/materials and the simplest effect that communicates
  the event.
- Prefer GPU particles for large visual-only effects; choose CPU particles only
  for platform/support or interpolation requirements that have been verified.
- Configure particle bounds and keep one-shots non-emitting until positioned.
  Restart safely and clean up from completion signals.
- Trails normally need global coordinates so emitted particles remain in world
  space.
- Use shared ShaderMaterials plus uniforms or instance uniforms. Avoid duplicating
  materials for one value.
- Move math out of fragment work when it can be precomputed, sampled, or handled
  in vertex work.
- Use renderer-compatible shader features and a lower-cost path when the target
  platform cannot afford the primary effect.
- Do not use shader branching, discard, transparency modes, turbulence, or
  screen-space effects based on folklore; profile their actual cost and visual
  consequences.
- VFX must not obscure actionable gameplay or make UI unreadable. Reduced motion,
  photosensitivity, and screen-shake controls apply here.

Verification:

- Inspect effect start, interruption, cleanup, pooling/restart, bounds/culling,
  overlap with HUD, lowest-quality setting, and lowest target device.
- Measure frame time and overdraw in a worst-case burst, not an isolated preview.

## 7. Save/load and persistence gate

- Save plain validated data, not Nodes, runtime instance IDs, or transient object
  references.
- Use `user://` and include an explicit schema version.
- Load fields with safe defaults, validate types/ranges, and migrate old versions
  deliberately.
- Preserve Godot-native types with an appropriate format; do not force large or
  strict typed data through JSON.
- Treat imported/downloaded saves as untrusted. Never enable object decoding for
  untrusted binary data.
- Protect important progress with recoverable writes, backups, or atomic rename
  patterns proportionate to risk.
- Keep settings persistence separate from large world/progress state when their
  lifecycles differ.
- Do not block gameplay frames with large serialization. First measure save size
  and write time; thread or chunk only when needed.
- Test upgrades from real previous save fixtures whenever schema changes.

Verification:

- New game with no file.
- Valid current save.
- Old-version migration.
- Missing/extra fields.
- Corrupt/truncated file.
- Boundary values and tampered input.
- Interrupted write and recovery where progress loss is material.

## 8. Debugging and performance gate

Debugging order:

1. Reproduce reliably.
2. Record the exact error, state, scene, input, and timing.
3. Trace the first invalid state change rather than the last visible symptom.
4. Inspect signal connections, scene ownership, async lifetime, and all callers of
   the shared function being changed.
5. Add the smallest diagnostic that distinguishes competing hypotheses.
6. Fix the root cause and add a regression check.

Performance order:

1. Define the target platform, frame rate, and budget.
2. Profile a release-like build on representative hardware.
3. Classify the bottleneck: CPU script, physics, GPU/render, UI, memory, loading,
   audio, network, or thermal/battery.
4. Change one thing.
5. Measure before/after under the same workload.
6. Keep the optimization only if it improves the target metric without harming
   correctness or maintainability.

Common measured escalation paths:

- Disable processing when inactive.
- Cache stable lookups and avoid repeated tree/group scans in hot paths.
- Reduce update frequency for non-critical checks.
- Use texture atlases, shared materials, batching, culling, and appropriate import
  compression.
- Thread large loading/serialization safely.
- Use MultiMesh, spatial partitioning, pools, or low-level Server APIs only after
  node/creation overhead is proven.

Never claim an FPS, memory, draw-call, load-time, or battery improvement without a
measurement.

## 9. Final implementation review gate

Review tests and acceptance criteria first, then the implementation. Report only
high-confidence findings that are caused or exposed by the change.

Block completion for:

- broken player behavior, data loss, security/authority violations,
- parser/runtime errors or failing relevant tests,
- lifecycle races, invalid freed-node access, duplicate state writers,
- inaccessible required UI flow,
- save incompatibility without migration,
- unbounded hot-path work or a measured target-budget regression,
- missing verification for non-trivial logic.

Automatically fix in-scope findings at 80% confidence or higher when reversible.
Rerun the narrow checks after each fix and finish with a concise verdict:
`passed`, `passed with target-device check remaining`, or `blocked` with the
specific evidence.
