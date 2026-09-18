#!/usr/bin/env bash
# Single source of truth for the release tag pattern.
#
# Both .github/workflows/release.yml (workflow_dispatch release_tag) and
# .github/workflows/manual-release.yml (version input) validate through this
# script, so the two entry points agree on what a valid tag looks like.
# Keep in sync with tests/test_release_tag_validation.sh, which reuses this
# pattern to exercise the validation logic.
set -euo pipefail

# Plain semver with an optional build/prerelease suffix.
# Example matches: 0.0.22, 1.2.3-rc.1, 2.0.0-alpha.10
RELEASE_TAG_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$'

TAG="${RELEASE_TAG_INPUT-}"

if [[ -z "$TAG" ]]; then
  echo "::error::Invalid release tag: <empty> — the 'release_tag' input is required and must match ${RELEASE_TAG_PATTERN}"
  exit 1
fi

if [[ ! "$TAG" =~ $RELEASE_TAG_PATTERN ]]; then
  echo "::error::Invalid release tag: $TAG — must match ${RELEASE_TAG_PATTERN} (for example 0.0.22). Aborting before any export job runs."
  exit 1
fi

echo "Release tag is valid: $TAG"
