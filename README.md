# Windowstead

Windowstead is now a tiny Godot 4 desktop colony sim.

## Current slice

- 2 autonomous workers
- gather / haul / build task loop
- wood and stone resource nodes
- hut / workshop / garden placeholder structures
- stockpile economy
- priority sliders for gather, haul, build
- ambient settlement log
- save/load through an autoload (`user://` on desktop, `localStorage` on web)
- desktop overlay defaults: borderless, always-on-top, transparent when supported

If transparency is not available on a platform/export template, the game falls back to a compact frameless window positioned near the top-right of the screen.

## Run locally

```bash
./.tools/Godot_v4.2.2-stable_linux.x86_64 --path .
```

## Exports

`export_presets.cfg` includes starter presets for:

- Linux/X11 (`.x86_64`)
- Windows Desktop (`.exe`)
- macOS (`.app`)

No installer ceremony, just executable builds like civilized people.
