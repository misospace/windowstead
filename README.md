# Windowstead

Windowstead is a Godot 4 desktop-resident idle colony sim: an ambient, edge-mounted companion interface where a tiny settlement keeps working while you use the rest of your desktop.

## Current MVP slice

- always-on-top, borderless desktop companion window
- bottom and side dock modes with orientation-specific grid shapes
- in-game startup menu for new/load/settings/exit and dock-style selection
- 2 autonomous workers
- priority-based gather / haul / build task loop
- wood, stone, and food stockpile counters
- 3 buildables with light progression unlocks: hut → workshop → garden
- random ambient events about every 30 seconds
- save/load through an autoload (`user://` on desktop, `localStorage` on web)
- starter export presets for Linux, Windows, and macOS

If transparency is not available on a platform/export template, the game falls back to a compact frameless window positioned near a screen edge.

## Run locally

With `just`:

```bash
mise exec -- just --justfile .justfile run
```

Directly on macOS:

```bash
./.tools/macos/Godot.app/Contents/MacOS/Godot --path .
```

Directly on Linux:

```bash
./.tools/Godot_v4.2.2-stable_linux.x86_64 --path .
```

## Smoke test

With `just`:

```bash
mise exec -- just --justfile .justfile validate
```

Directly on macOS:

```bash
./.tools/macos/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_runner.gd
```

Directly on Linux:

```bash
./.tools/Godot_v4.2.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

## Exports

`export_presets.cfg` includes starter presets for:

- Linux/X11 (`.x86_64`)
- Windows Desktop (`.exe`)
- macOS (`.app`)

Local export helpers:

```bash
mise exec -- just --justfile .justfile build-macos
mise exec -- just --justfile .justfile build-linux
mise exec -- just --justfile .justfile build-windows
```

To validate and build for the current platform:

```bash
mise exec -- just --justfile .justfile local-build
```

Tooling is pinned with `.mise.toml`. Run `mise trust` once in the repo if mise prompts before installing or executing tools. The Godot binary defaults to the repo-local `.tools` path. Override it with `GODOT_BIN=/path/to/Godot` if needed.

## Contributors

Windowstead is maintained by Miso Space with help from local and AI-assisted contributors. Contributions should preserve the desktop-companion dock UX: bottom strip first, temporary popup menus, and low-attention colony behavior.
