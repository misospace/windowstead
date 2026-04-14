# Windowstead pivot research brief

Issue: `joryirving/windowstead#2`

## Research Notes
- Verified repo state before changes: `main` only had README/license/Renovate, and PR #3 (`feat/initial-playable-skeleton`) carried the first Vite prototype.
- The current playable logic was entirely in `src/main.ts`: one-file simulation, 2 workers, gather/haul/build priorities, queued structures, event log, and `localStorage` save/load.
- There was no existing native windowing layer, no game engine setup, no asset pipeline worth preserving, and no reusable desktop-overlay behavior from the web prototype.
- Because the request is a pivot, not an incremental patch, the cleanest path is a fresh Godot 4 root project on a new branch from `main`, then re-implement only the proven MVP loop from the prototype.
- The web prototype already proved the tiny colony loop shape works: seeded wood/stone nodes, a stockpile, worker task scoring by priority and distance, placeholder structures, and an ambient log cadence.

## Recommended Approach
- Replace the Vite app with a Godot 4 project rooted at the repo top level: `project.godot`, `scenes/main.tscn`, `scripts/main.gd`, `scripts/game_state.gd`, theme/icon, and `export_presets.cfg`.
- Keep the first pass intentionally small: one `Control`-driven scene, a grid of buttons for the world, sidebar controls for builds/priorities/save, and a timer-based autonomous sim loop in GDScript.
- Use an Autoload singleton for persistence so desktop builds save to `user://` while web builds can use `localStorage` through `JavaScriptBridge`.
- Set borderless + always-on-top by default, enable transparent window mode when the platform supports it, and fall back to a compact frameless top-right window when it does not.
- Preserve the functional MVP from the prototype rather than overbuilding engine systems: 2 workers, gather/haul/build tasks, hut/workshop/garden placeholders, stockpile resources, event log, and export presets for Linux/Windows/macOS.
