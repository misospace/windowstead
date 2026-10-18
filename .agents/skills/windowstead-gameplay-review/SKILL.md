---
name: windowstead-gameplay-review
description: Review Windowstead gameplay, worker behavior, colony economy, save compatibility, dock layout, orientation, and Godot/GDScript changes.
---

# Windowstead gameplay review

Windowstead is a Godot 4 desktop-resident idle colony sim. Treat it as a desktop companion, not a conventional management-game window.

## Product and gameplay invariants

- The bottom dock is the primary mode. A vertical side dock is a distinct orientation family, not simply a resized bottom dock.
- The world strip is the product. Menus should be temporary overlays rather than persistent sidebars, and the game should remain glanceable and low-attention.
- The player plans and places; workers execute. Review worker intent, colony stance, milestone management, and task progression for edge cases and unintended autonomous behavior.
- Save migration must remain backward-compatible because startup loads the latest save. Check older save shapes, missing fields, and version transitions.
- Resource trends and economy feedback must remain numerically correct over time. Look for cumulative drift, unstable feedback loops, and incorrect aggregation.
- Orientation changes should have explicit behavior rather than silently morphing unrelated layouts.
- GDScript warnings are treated as errors in practice. Use the repository's headless Godot validation when available and report if it was not run.

## Review procedure

1. Identify the player-visible behavior and the state transition the change is intended to make.
2. Trace the behavior through save/load, worker execution, and UI presentation where applicable.
3. Check both bottom and vertical orientation if layout or input behavior changes.
4. Add regression tests or reproducible validation for save migration, economy calculations, worker decisions, or orientation-specific behavior as appropriate.
5. Keep Renovate digest-only reviews compact when only a digest changes and no concrete risk is present.
6. Flag concrete gameplay regressions and correctness risks, not aesthetic preferences that conflict with no documented product constraint.
