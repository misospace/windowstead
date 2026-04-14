# Windowstead

Windowstead is a tiny Godot 4 desktop overlay colony sim.

## Current MVP slice

- always-on-top, borderless desktop overlay window
- resizable compact default footprint, aimed at ~400x300
- 2 autonomous workers
- priority-based gather / haul / build task loop
- wood, stone, and food stockpile counters
- 3 buildables with light progression unlocks: hut → workshop → garden
- random ambient events about every 30 seconds
- save/load through an autoload (`user://` on desktop, `localStorage` on web)
- starter export presets for Linux, Windows, and macOS

If transparency is not available on a platform/export template, the game falls back to a compact frameless window positioned near the top-right of the screen.

## Run locally

```bash
./.tools/Godot_v4.2.2-stable_linux.x86_64 --path .
```

## Smoke test

```bash
./.tools/Godot_v4.2.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

## Exports

`export_presets.cfg` includes starter presets for:

- Linux/X11 (`.x86_64`)
- Windows Desktop (`.exe`)
- macOS (`.app`)
