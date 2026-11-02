# Contributing to Windowstead

Windowstead is a tiny Godot 4 desktop-overlay colony sim. Contributions are welcome — this is a small, focused project and easy to jump into.

## Prerequisites

- **Godot 4** (editor or command-line). The pinned version and its download URL live in `godot-toolchain.json`. Unzip the Linux build from that URL into `.tools/`, or set `GODOT_BIN` to any local Godot install.
- A text editor or IDE with GDScript support.
- Git (for PRs).

## Running locally

```bash
# Run the game
mise exec -- just --justfile .justfile run

# Headless smoke test (automated)
mise exec -- just --justfile .justfile test
```

The `just` targets run a Godot binary from `.tools/`. The Linux file name contains the version from `godot-toolchain.json`, so it changes on every toolchain update. Set `GODOT_BIN` to run a different Godot install.

## Project structure

```
project.godot          # Godot project root
scenes/main.tscn       # Main UI scene (grid, sidebar, HUD)
scripts/main.gd        # Core game loop, rendering, worker AI
scripts/game_state.gd  # Save/load autoload singleton
theme/theme.tres       # Theme resources
tests/test_runner.gd   # Headless smoke tests
export_presets.cfg     # Linux/Windows/macOS export presets
```

The game is intentionally monolithic: one scene, two scripts. Everything lives in `main.gd` — the tick loop, worker task selection, rendering, and UI wiring. `game_state.gd` handles persistence (desktop `user://` or web `localStorage`).

## Dev workflow

1. **Branch from `main`.** Use descriptive names: `fix/issue-NN-short`, `feat/short-description`.
2. **Make one focused change.** Windowstead is small, but scope discipline keeps PRs reviewable.
3. **Smoke test before pushing.** Run the headless test at minimum. If you touch rendering or UI, launch the editor and verify the game runs.
4. **Open a PR.** Link the issue number in the PR body.

## Testing

The smoke test runs the game headless and exercises the save/load cycle:

```bash
mise exec -- just --justfile .justfile test
```

Run every suite in `tests/` with `mise exec -- just --justfile .justfile validate`. CI runs the same matrix.

If your change touches persistence, add a corresponding test to `tests/test_runner.gd`.

## PR process

- PRs target `main`.
- Link the related issue in the PR description.
- Keep descriptions concise: what changed and why.
- No merge conflicts expected on `main` — pull before pushing.

## Code style

- GDScript idioms: `const`, `var`, `func`, `@onready` for node references.
- Use `String()` casts when concatenating with `+` or `%` formatting.
- Keep `main.gd` readable — it's ~800 lines of dense logic. Comments help.

## What to work on

Check the [issues](https://github.com/misospace/windowstead/issues) for open work. Small fixes are great starting points. If you want to propose something new, open an issue first.
