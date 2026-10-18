---
name: windowstead-workflow-security
description: Review Windowstead GitHub Actions, reviewer workflow, GitHub App credentials, model-provider secrets, token scope, and least-privilege configuration.
---

# Windowstead workflow security

## Required secrets and variables

The AI review workflow uses a short-lived GitHub App token rather than a personal access token.

Secrets:
- BOT_CLIENT_ID: GitHub App client ID.
- BOT_APP_PRIVATE_KEY: private key used to mint the app token.
- LITELLM_API_KEY: credential for the LiteLLM model proxy.

Variables:
- LITELLM_URL: model proxy base URL.
- PRIMARY_FORMAT and PRIMARY_MODEL: primary provider format and model identifier.
- FALLBACK_FORMAT and FALLBACK_MODEL: fallback provider format and model identifier.

## Least-privilege checklist

- Keep workflow permissions minimal: contents read and pull-request write only unless a documented feature requires more.
- Use the repository's GitHub App token flow, not a personal access token or an unnecessarily broad default token.
- Scope tool-allowed-gh-api-repos to exactly misospace/windowstead. Do not use a wildcard; the reviewer should not gain API access to unrelated repositories.
- Keep tool access disabled for fork PRs. Do not weaken the fork trust boundary to make a review pass.
- Read docs/github-app-secrets.md before adding a new workflow that mints an app token. Never print, persist, or include credentials in artifacts or review output.
- Verify workflow configuration against the actual YAML. If a comment or older document disagrees with the live setting, treat the live configuration as the evidence and correct the mismatch deliberately.
