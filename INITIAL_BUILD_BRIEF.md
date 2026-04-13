# Windowstead initial build brief

Issue: `joryirving/windowstead#2`

## Research notes
- The repository is currently almost empty: `README.md`, `LICENSE`, `renovate.json`.
- There is no existing engine, framework choice, app shell, renderer, or game loop to extend.
- That means the first iteration risk is product-shaping and architecture choice, not patching existing code.
- The issue has already been tightened to a small vertical slice: tiny desktop-overlay colony sim, 2 workers, 3 task types, 3 structures/upgrades, simple priorities, one event system, save/load.

## Recommendation
Use a stronger model for the first pass.

Why:
- greenfield repo
- needs MVP discipline more than speed
- easy to overbuild into fake RimWorld instead of a tiny ambient overlay sim

## First implementation target
Build the smallest playable skeleton with these characteristics:

### Product shape
- compact single-window desktop game
- one small map/screen
- two autonomous workers visible at all times
- resource nodes and a tiny build loop
- obvious idle progress without constant player input

### Systems for v1
- render loop
- simulation tick loop
- worker entity model
- task assignment queue
- pathing simple enough to ship quickly
- gather / haul / build actions
- three buildables/upgrades
- simple priority controls
- one lightweight event type
- save/load of current run state

### Explicit non-goals
- combat
- procedural world generation
- large maps
- deep colony simulation
- complex survival needs
- multiplayer
- heavy AI behavior trees

## Suggested technical bias
Pick the stack that gets to a visible prototype fastest.

Good default bias:
- TypeScript
- Electron or Tauri only if overlay/window behavior needs it early
- otherwise plain web app first if that gets a playable loop on screen faster
- canvas-based rendering over premature engine complexity

## Recommended implementation order
1. choose shell/runtime and boot app
2. create fixed-size single-screen playfield
3. add 2 workers moving on a simple grid or waypoint system
4. implement gather/haul/build loop
5. add one resource counter HUD
6. add three structures/upgrades
7. add basic priority controls
8. add one event system
9. add save/load
10. polish readability and charm

## Definition of done for first PR
A teammate can run the app and see:
- a small game window
- two workers autonomously doing useful work
- resources increasing over time
- at least one player choice that changes behavior
- enough structure to iterate instead of restarting from scratch

## Instruction for first coding pass
Favor visible progress and clean seams over completeness.
Do not spend the first pass building generic systems for future hypotheticals.
Ship bones first.