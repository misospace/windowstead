# AI PR Review: windowstead

## Required Secrets and Variables

The AI PR reviewer workflow uses a GitHub App token (not a PAT) for least-privilege access. The following secrets and variables must be configured for the workflow to operate correctly.

### Secrets

| Secret | Purpose |
|---|---|
| `BOT_CLIENT_ID` | GitHub App client ID — used by `actions/create-github-app-token` to generate a short-lived token scoped to this repository only |
| `BOT_APP_PRIVATE_KEY` | GitHub App private key (PEM) — signs the JWT for app authentication |
| `LITELLM_API_KEY` | API key for the LiteLLM proxy that routes AI model requests |

### Variables

| Variable | Purpose |
|---|---|
| `LITELLM_URL` | Base URL of the LiteLLM proxy (primary and fallback) |
| `PRIMARY_FORMAT` | Chat completion format for the primary model (e.g. `openai`) |
| `PRIMARY_MODEL` | Primary AI model identifier |
| `FALLBACK_FORMAT` | Chat completion format for the fallback model |
| `FALLBACK_MODEL` | Fallback AI model identifier |

### Least-Privilege Notes

- The workflow uses a GitHub App token (`actions/create-github-app-token`) instead of a PAT or `GITHUB_TOKEN`. This token is scoped to the repository that installed the app and expires automatically.
- `tool_allowed_gh_api_repos` is set to `misospace/windowstead` — the AI reviewer can only call the GitHub API for this repository, not `*`.
- Fork tool use is disabled (`tool_enable_for_forks: "false"`).
- The workflow permissions are minimal: `contents: read` and `pull-requests: write`.

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
