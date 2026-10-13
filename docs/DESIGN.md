# Design — Windowstead

## Architecture

Windowstead is a Godot 4 desktop-resident idle colony sim built around a single scene and one main script, with several supporting modules. It is designed as an edge-mounted companion interface, not a conventional game window.

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
│       │       ├── Tick speed slider (Slow / Normal / Fast)
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
| `scripts/main.gd` | Game loop, rendering, worker AI, UI wiring, state management (2561 lines) |
| `scripts/game_state.gd` | Autoload singleton for save/load (desktop `user://` + web `localStorage`) |
| `scripts/constants.gd` | Centralised immutable game constants (worker names, tick rate, build costs, thresholds) |
| `scripts/layout_math.gd` | Pure layout math for dock and tile geometry; grid dimensions per orientation |
| `scripts/rotating_goal.gd` | Rotating colony goal system — resource targets, build targets, and completion rewards |
| `scripts/milestone_manager.gd` | Fixed early-game milestone goals (sits above rotating micro-goals) |
| `scripts/colony_stance.gd` | Colony stance data model — nudges task selection without micromanagement |
| `scripts/worker_cap_logic.gd` | Worker capacity calculation logic extracted from main.gd for testability |

### Persistence

`game_state.gd` exposes `save_game()`, `load_game()`, `save_settings()`, `load_settings()`, and `clear_game()`. Desktop builds write JSON to `user://windowstead.save` and `user://windowstead.settings`. Web builds use `localStorage` via `JavaScriptBridge`.

Save format is a single JSON dictionary. `validate_save_schema()` in `scripts/game_state.gd` is the source of truth for the validated fields. Persisted keys: `tick`, `harvested`, `resources`, `priority_order`, `colony_stance`, `dock_anchor`, `workers`, `tiles`, `builds`, `next_build_id`, `reserved_resources`, `events`, `active_goal`, `completed_goal_ids`, `active_rewards`, `current_milestone_id`, `completed_milestone_ids`, `save_version`, plus `migration_log` on saves upgraded from version 1.

### Grid dimensions

Grid dimensions differ by dock orientation family (defined in `layout_math.gd`):

| Orientation | Width | Height |
|-------------|-------|--------|
| Bottom      | 32    | 5      |
| Side        | 10    | 24     |

The chosen dock style is saved with the colony and locked for that save.

### Window behavior

The window is borderless + always-on-top by default. Transparent window mode is enabled when the platform supports it; otherwise it falls back to a compact frameless window positioned near a screen edge. Bottom and side dock modes are separate orientation families with different grid dimensions, tile sizing, and overlay placement. The chosen dock style is saved with the colony and locked for that save.

## Data model

### State dictionary

```
{
  "tick": int,
  "harvested": {"wood": int, "stone": int, "food": int},
  "resources": {"wood": int, "stone": int, "food": int},
  "priority_order": ["build", "haul", "gather"],
  "colony_stance": String,
  "dock_anchor": "bottom" | "left" | "right",
  "workers": [
    {
      "name": String,
      "pos": {"x": int, "y": int},
      "prev_pos": {"x": int, "y": int},
      "carrying": {"<resource>": int},
      "task": {"kind": String, "target": {"x": int, "y": int}, "resource": String, "build_id": int},
      "break_ticks": int,
      "spawn_tick": int   // optional; set on recruit, backfilled by the v1 → 2 migration
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
  "active_goal": {
    "id": String,
    "type": String,       // "resource" | "build" | "build_complete"
    "target": Dictionary, // {"resource": "wood", "amount": 10} or {"build_kind": "hut"}
    "current_progress": int,
    "completed": bool,
    "reward": String      // Optional reward label
  },
  "completed_goal_ids": [String],
  "active_rewards": [
    {"type": String, "remaining": int, "duration": int,
     "label": String, "trickle_ticks": int, "resource": String}  // "resource" only on trickle rewards
  ],
  "current_milestone_id": String,
  "completed_milestone_ids": [String],
  "reserved_resources": {"<resource>": int},
  "migration_log": [
    {"from_version": int, "to_version": int, "step": String}
  ],
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

- Versioned with `save_version` (currently 2). A save with no `save_version` key is treated as the current version.
- On load, every save passes through `validate_save_schema()` and then `migrate_save()` (shared by the desktop and web paths).
- Version 1 saves are migrated in place to version 2 by `migrate_v1_to_v2()` and load normally — nothing is reset.
- Future or unknown versions (greater than the current `SAVE_VERSION`) and version 0 are rejected: `migrate_save()` returns an empty dictionary, the load fails with an error message, and the running colony is left untouched. No reset happens on any load path.
- `migrate_v1_to_v2()` writes `migration_log` (appending a step entry) and backfills `spawn_tick` on workers that lack it. The other newer fields (`active_goal`, `completed_goal_ids`, `active_rewards`, `current_milestone_id`, `completed_milestone_ids`, `colony_stance`, `reserved_resources`) are backfilled separately by `ColonySim.ensure_defaults()` after load, not by the migration.
- Layout compatibility is checked: tile array size must match current grid, worker/build positions must be in bounds.
- Settings are stored separately from game state.
