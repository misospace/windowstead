#!/usr/bin/env bash
# Single source of truth for the release tag pattern and for the operator
# input normalization.
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

# Operator input may carry a single leading 'v' (for example 'v0.0.20').
# The prefix is stripped here — not in the calling workflow — so the canonical
# tag is always plain semver and every entry point accepts the same input.
normalize_release_tag() {
  local tag="${1-}"
  printf '%s' "${tag#v}"
}

# When sourced (for example by .github/scripts/inject-release-version.sh),
# expose RELEASE_TAG_PATTERN and stop here: the sourcing script gets the one
# definition of the tag pattern without re-running the validation (#452).
# The subshell-return probe is the standard sourced-vs-executed test and
# works on the bash 3.2 shipped with macOS.
if (return 0 2>/dev/null); then
  return 0
fi

RAW_TAG="${RELEASE_TAG_INPUT-}"
TAG="$(normalize_release_tag "$RAW_TAG")"

# Keep the reported input on one line. A newline in the input would start a
# new workflow command in the log.
SAFE_RAW_TAG="${RAW_TAG//$'\n'/ }"
SAFE_RAW_TAG="${SAFE_RAW_TAG//$'\r'/ }"

if [[ -z "$TAG" ]]; then
  echo "::error::Invalid release tag: ${SAFE_RAW_TAG:-<empty>} — the release tag is required and must match ${RELEASE_TAG_PATTERN} (for example 0.0.22). Aborting before any export job runs."
  exit 1
fi

if [[ ! "$TAG" =~ $RELEASE_TAG_PATTERN ]]; then
  echo "::error::Invalid release tag: $SAFE_RAW_TAG — must match ${RELEASE_TAG_PATTERN} (for example 0.0.22). Aborting before any export job runs."
  exit 1
fi

# Publish the canonical tag so every downstream step uses the normalized form
# (the raw input may still carry the 'v' prefix).
if [[ -n "${GITHUB_OUTPUT-}" ]]; then
  echo "tag=$TAG" >> "$GITHUB_OUTPUT"
fi

echo "Release tag is valid: $TAG"
