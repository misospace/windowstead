# Spec — Windowstead

## Gameplay overview

Windowstead is a tiny autonomous colony sim running as a desktop overlay. Two workers — **Jun** and **Mara** — manage resources, construct buildings, and keep the settlement fed. The player sets priorities and places buildings; the workers handle the rest.

## Resource system

Three resources: **wood**, **stone**, **food**.

Resources exist in two pools:
- **Resources** — the player's stockpile (central storage). Workers haul here first.
- **Harvested** — tracked separately, used for the food economy.

### Resource nodes

The world grid is seeded with:
- **Trees** (wood) — 6 units each, deterministic placement via hash function
- **Rocks** (stone) — 5 units each
- **Berries** (food) — 4 units each

Nodes deplete as workers gather. Empty nodes become `ground` tiles.

### Ambient events

Every 66 ticks (~1 minute at normal speed), a random event fires:
1. **Trail mix** — Food +2 from a neighbor
2. **Break** — A random worker takes a 6-tick break
3. **Supply drop** — A new resource node spawns on an empty tile

## Economy / building costs

| Structure | Wood | Stone | Unlock requirement |
|-----------|------|-------|-------------------|
| Hut | 6 | 2 | None (always available) |
| Workshop | 4 | 6 | Hut must be complete |
| Garden | 3 | 1 | Workshop must be complete |

### Structure bonuses (on completion)

| Structure | Bonus |
|-----------|-------|
| Hut | Food +1 |
| Workshop | Unlocks garden; +0.16 build speed to other structures |
| Garden | Food +3 |

### Build process

1. Player clicks a build button → placement mode activates
2. Player clicks an empty `ground` tile → build is queued
3. Workers follow priority order to complete builds:
   - **Gather** resources from nodes
   - **Haul** resources to stockpile
   - **Deliver** resources to the build site
   - **Build** — once all costs are delivered, workers spend ticks on progress

Build speed: base 0.34 progress per tick. Workshop completion adds +0.16 to non-workshop builds.

## Worker AI

### Task priority

Workers choose tasks by priority order, configurable via UI (rank up/down for each task type). Default: **build → haul → gather**.

### Task selection

For each priority level, workers:
1. Gather available tasks of that kind
2. Sort by Manhattan distance (closest first)
3. Pick the nearest task

### Task types

| Kind | Behavior |
|------|----------|
| **Gather** | Move to resource node, collect 1 unit, then haul to stockpile |
| **Haul** | Carry resource from stockpile to build site (if build exists) or back to stockpile |
| **Build** | Move to building site, add progress per tick |

### Worker states

- **Working** — executing a task
- **Idle** — no task assigned (rare — workers always find something to do)
- **Breaking** — `break_ticks` > 0, skipped each tick until it reaches 0

### Movement

Workers move one tile per tick along the shortest Manhattan path. Position interpolation is animated on `WorldOverlay` using eased lerp between `prev_pos` and `pos`.

## Tick system

- **Base tick**: 0.9 seconds
- **Speed settings**: Slow (×1.6), Normal (×1.0), Fast (×0.65)
- **Focus mode**: ×2.5 multiplier (slows everything)
- **Event interval**: Every 66 ticks (~60 seconds at normal speed)

## UI layout

Three dock anchors (configurable):
- **Right** — 30×5 grid, sidebar on right (default)
- **Left** — 7×16 grid, sidebar on left (vertical orientation)
- **Bottom** — 30×5 grid, sidebar below (compact mode)

Each anchor has different tile sizes, padding, and sidebar dimensions.

## Save / load

- Auto-saves every tick (via `persist()`).
- Manual save via UI button.
- Load checks version compatibility and layout bounds.
- New game clears all state and re-seeds the world.
