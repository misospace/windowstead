# CLAUDE.md

## Project Summary

Windowstead is a Godot 4 desktop-resident idle colony sim.

The core inspiration is:
- Rusty's Retirement for desktop-native, low-attention, edge-docked UX
- RimWorld-style indirect control for priorities, planning, and agent-driven work

The intended fantasy is:
- "My colony is alive while I work."

## Product Direction

Treat Windowstead as a desktop companion, not a normal management game window.

Key rules:
- Bottom dock is the primary mode.
- Vertical side dock is an alternate orientation family, not the default.
- The world strip is the product.
- Menus should be temporary popup overlays, not persistent sidebars.
- The player plans and places; workers execute.
- The game should be glanceable, low-attention, and forgiving when ignored.

## UX Constraints

Prefer these behaviors:
- Tile-first dock sizing: choose square tile geometry first, with tile size responsive to screen/work-area percentage, then derive dock size from the grid and UI chrome
- Bottom-of-screen strip as the strongest presentation
- Separate layout assumptions for bottom vs vertical mode
- Focus Mode and zoom as first-class UX features
- Dense tile strip with minimal dead space
- Workers rendered over the strip with visible movement
- Build placement directly on the world, with clear preview/cancel feedback

Avoid these regressions:
- Building a normal app-like sidebar UI
- Making bottom and vertical mode just resized versions of each other
- Hiding the actual game behind menus
- Requiring high attention or frequent urgent clicks

## Current Collaboration Preferences

- Push directly to `main` unless told otherwise.
- Do not cut a release after every small change; discuss between releases when practical.
- Detailed GitHub issues are used to delegate work to a local model, so issue text should be concrete and implementation-oriented.

## Review / Implementation Notes

- Save/version migration should be migration-first because the game auto-loads the latest save on startup.
- If changing orientation family in a meaningful way, prefer explicit behavior over silent layout morphing.
- Screen/work-area percentage can inform target tile size, but final dock sizing should be driven by tile geometry rather than sizing the dock first.
- Bottom dock should stay shallow and wide.
- Side dock should stay modest in width, especially on ultrawide monitors.

## Validation

Useful checks:

```bash
./.tools/Godot_v4.2.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

macOS runtime validation has also been important in this repo because GDScript warnings are treated as errors in practice.

## Open Work Themes

The current major themes are:
- bottom-dock-first polish
- distinct vertical mode behavior
- popup management UX
- denser strip filling
- smoother worker motion
- clearer economy/build bottleneck feedback
- focus mode and zoom
