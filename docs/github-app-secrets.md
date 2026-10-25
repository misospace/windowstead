# GitHub App secrets (canonical names)

All workflows that mint a GitHub App token via `actions/create-github-app-token`
must use the same two repository secrets. Do not introduce new names.

| Secret | Purpose |
|---|---|
| `BOT_CLIENT_ID` | GitHub App client ID (numeric app ID) |
| `BOT_APP_PRIVATE_KEY` | GitHub App private key (PEM) — signs the JWT for app authentication |

Workflows that use them:

- `.github/workflows/ai-pr-review.yaml`
- `.github/workflows/manual-release.yml`
- `.github/workflows/release-please.yaml`
- `.github/workflows/release.yml` — mints the release upload token in its
  `publish` job, which uploads the platform assets once every export job has
  succeeded

Every workflow that mints a token for the release itself must use the app
token flow rather than the default `GITHUB_TOKEN`.

## Rotation

When rotating the app's private key, update `BOT_APP_PRIVATE_KEY` once in the
repository settings — every workflow picks up the new value on its next run.
`BOT_CLIENT_ID` only changes if the app itself is replaced.
