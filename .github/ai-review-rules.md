# AI PR Review: windowstead

## Review conventions

Windowstead is a Godot 4 desktop-resident idle colony sim using GDScript. Review for correctness, gameplay integrity, and maintainability.

Areas to watch:
- **Save/version migration**: the game auto-loads the latest save on startup — migration logic must be backward-compatible
- **Worker systems** (`scripts/`): worker intent, colony stance, milestone management — verify logic handles edge cases
- **Resource trends / economy feedback**: ensure calculations are correct and don't drift over time
- **UI/UX constraints**: bottom dock is the primary mode; vertical side dock is an alternate family, not just a resized version; the world strip is the product, not menus
- **GDScript**: warnings are treated as errors in practice; validate with headless Godot runner
- **Orientation changes**: explicit behavior over silent layout morphing

For Renovate digest-only updates (same tag, only `@sha256:` changes):
- Keep review compact: short recommendation, changed files, non-blocking caveats only
- No need for full section structure unless there's an actual warning or blocker

## Review tone

- Be direct and practical.
- Flag only real defects, regressions, or meaningful risks as blocking.
- Do not nitpick formatting, naming, or style unless it affects readability or correctness.
- Prefer `approve` or non-blocking comments for PRs that look reasonable overall.
