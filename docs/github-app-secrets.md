# GitHub App secrets (canonical names)

Workflows mint GitHub App tokens via `actions/create-github-app-token` using
one of two repository secret pairs, one per app.

| Secret | App | Purpose |
|---|---|---|
| `BOT_CLIENT_ID` | its-saffron | GitHub App client ID (numeric app ID) |
| `BOT_APP_PRIVATE_KEY` | its-saffron | GitHub App private key (PEM) — signs the JWT for app authentication |
| `MISO_APP_ID` | itsmiso | GitHub App ID |
| `MISO_APP_PRIVATE_KEY` | itsmiso | GitHub App private key (PEM) |

Workflows that use each pair:

- `BOT_CLIENT_ID` / `BOT_APP_PRIVATE_KEY` (its-saffron)
  - `.github/workflows/ai-pr-review.yaml` — publishes the AI PR review
  - `.github/workflows/manual-release.yml`
  - `.github/workflows/release.yml` — mints the release upload token in its
    `publish` job, which uploads the platform assets once every export job has
    succeeded
- `MISO_APP_ID` / `MISO_APP_PRIVATE_KEY` (itsmiso)
  - `.github/workflows/release-please.yaml` — opens the release pull request

## The author/reviewer split

The hard constraint is not "one shared secret pair"; it is:

**The app that opens a pull request must differ from the app that reviews
it.** GitHub rejects a native `APPROVE` when the reviewing app is the PR
author, which fails the `review` check with `ERROR: Native approval failed.`
(see PR #459, where release-please and ai-pr-review both used the its-saffron
pair).

`tests/test_release_workflow_gating.sh` enforces this by comparing the secret
names each workflow feeds to `create-github-app-token`: any overlap fails the
check. Do not make `release-please.yaml` use the `BOT_*` pair, and do not make
`ai-pr-review.yaml` use the `MISO_*` pair.

Note: `allow-approve` has no effect in pr-reviewer-action v3.x — it is
deprecated and inert, and publication is decided by `publish-mode` alone.
With `publish-mode: review_verdict` there is no way to opt out of the native
approval when the verdict is approve, so the app split is the only protection
against self-review.

Every workflow that mints a token for the release itself must use the app
token flow rather than the default `GITHUB_TOKEN`.

## Rotation

When rotating an app's private key, update the matching secret
(`BOT_APP_PRIVATE_KEY` or `MISO_APP_PRIVATE_KEY`) in the repository settings —
every workflow using that app picks up the new value on its next run. The
client/ID secrets only change if the app itself is replaced.
