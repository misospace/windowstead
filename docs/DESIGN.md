# Design — Windowstead

## Architecture

Windowstead is a Godot 4 desktop-overlay colony sim built around a single scene and two scripts.

### Scene graph

```
Control (root)
├── Backdrop (panel with transparent bg)
│   └── Margin → Root (HBoxContainer)
│       ├── Left (VBoxContainer)
│       │   ├── Title / Subtitle / Activity labels
│       │   ├── WorldPanel (PanelContainer)
│       │   │   └── WorldGrid (GridContainer — tile buttons)
│       │   │   └── WorldOverlay (Control — worker sprites)
│       │   └── SidebarScroll (ScrollContainer)
│       │       ├── Build buttons
│       │       ├── Save / New Game / Settings buttons
│       │       ├── Priority controls (rank up/down)
│       │       ├── Tick speed slider
│       │       ├── Dock side selector
│       │       ├── Focus mode toggle
│       │       └── Zoom slider
│       └── CrewList (VBoxContainer — worker status labels)
└── HudMenuButton / HudHint
```

The world grid is dynamically generated at runtime — `build_world()` creates a tile for each grid cell with icon, amount, progress, and worker-sprite sub-nodes. Workers are rendered as animated pixel-art sprites on `WorldOverlay`, interpolated between tiles each frame.

### Scripts

| Script | Role |
|--------|------|
| `scripts/main.gd` | Game loop, rendering, worker AI, UI wiring, state management (~800 lines) |
| `scripts/game_state.gd` | Autoload singleton for save/load (desktop `user://` + web `localStorage`) |

### Persistence

`game_state.gd` exposes `save_game()`, `load_game()`, `save_settings()`, `load_settings()`, and `clear_game()`. Desktop builds write JSON to `user://windowstead.save` and `user://windowstead.settings`. Web builds use `localStorage` via `JavaScriptBridge`.

Save format is a single JSON dictionary with keys: `tick`, `harvested`, `resources`, `priority_order`, `workers`, `tiles`, `builds`, `next_build_id`, `events`, `save_version`.

### Window behavior

The window is borderless + always-on-top by default. Transparent window mode is enabled when the platform supports it; otherwise it falls back to a compact frameless window positioned near a screen edge. Three anchor modes: right, left, bottom — each with different grid dimensions, tile sizes, and sidebar layouts.

## Data model

### State dictionary

```
{
  "tick": int,
  "harvested": {"wood": int, "stone": int, "food": int},
  "resources": {"wood": int, "stone": int, "food": int},
  "priority_order": ["build", "haul", "gather"],
  "workers": [
    {
      "name": String,
      "pos": {"x": int, "y": int},
      "prev_pos": {"x": int, "y": int},
      "carrying": {"<resource>": int},
      "task": {"kind": String, "target": {"x": int, "y": int}, "resource": String, "build_id": int},
      "break_ticks": int
    }
  ],
  "tiles": [
    {"kind": String, "amount": int, "resource": String, "build_kind": String}
  ],
  "builds": [
    {"id": int, "kind": String, "pos": {"x": int, "y": int},
     "delivered": {"wood": int, "stone": int}, "progress": float, "complete": bool}
  ],
  "next_build_id": int,
  "events": [{"tick": int, "text": String}],
  "save_version": int
}
```

### Tile kinds

| Kind | Meaning |
|------|---------|
| `ground` | Empty, buildable |
| `tree` | Wood resource node (amount depletes) |
| `rock` | Stone resource node |
| `berries` | Food resource node |
| `stockpile` | Central resource hub |
| `foundation` | In-progress build |
| `hut` / `workshop` / `garden` | Completed structures |

### Structure progression

```
hut (unlocked) → workshop (needs hut) → garden (needs workshop)
```

Each structure has build costs in wood and stone. Workers must haul resources to the stockpile first, then deliver to the build.

## Save format

- Versioned with `save_version` (currently 1).
- On load, version mismatch triggers a colony reset.
- Layout compatibility is checked: tile array size must match current grid, worker/build positions must be in bounds.
- Settings are stored separately from game state.
