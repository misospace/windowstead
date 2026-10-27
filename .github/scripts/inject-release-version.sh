#!/usr/bin/env bash
# Single source of truth for writing a release tag into export_presets.cfg (#444).
#
# The macOS export maps application/short_version to CFBundleShortVersionString
# (free-form string, carries the full tag) and application/version to
# CFBundleVersion, which Apple constrains to at most three period-separated
# non-negative integers. A prerelease tag such as 1.2.3-rc.1 must therefore
# land only in short_version; version gets the numeric core (1.2.3).
#
# Usage:
#   inject-release-version.sh <release-tag> [presets-file]
#     Rewrites application/short_version and application/version in
#     presets-file (default: export_presets.cfg). Fails if either field is
#     absent, so preset drift can never silently ship an untracked version.
#
#   inject-release-version.sh --build-version <release-tag>
#     Prints the derived CFBundleVersion for the tag and exits. Used by the
#     release workflow's Info.plist assertion so the build-version derivation
#     lives in exactly one place.
set -euo pipefail

# Same tag shape as .github/actions/validate-release-tag/validate.sh:
# plain semver with an optional build/prerelease suffix.
RELEASE_TAG_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$'

derive_build_version() {
  local tag="$1"
  # Group 1 captures the numeric core so CFBundleVersion can drop any
  # prerelease/build suffix (1.2.3-rc.1 -> 1.2.3): Apple allows at most three
  # period-separated non-negative integers.
  if [[ ! "$tag" =~ ^([0-9]+\.[0-9]+\.[0-9]+)([-.][0-9A-Za-z.-]+)?$ ]]; then
    echo "::error::Invalid release tag: $tag — must match ${RELEASE_TAG_PATTERN}" >&2
    return 1
  fi
  echo "${BASH_REMATCH[1]}"
}

if [[ "${1-}" == "--build-version" ]]; then
  if [[ $# -ne 2 ]]; then
    echo "Usage: $0 --build-version <release-tag>" >&2
    exit 2
  fi
  build_version="$(derive_build_version "$2")"
  echo "$build_version"
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <release-tag> [presets-file]" >&2
  exit 2
fi

RELEASE_TAG_INPUT="$1"
PRESETS_FILE="${2:-export_presets.cfg}"

if [[ ! -f "$PRESETS_FILE" ]]; then
  echo "::error::Presets file not found: $PRESETS_FILE" >&2
  exit 1
fi

SHORT_VERSION="$RELEASE_TAG_INPUT"
BUILD_VERSION="$(derive_build_version "$RELEASE_TAG_INPUT")"

# Replace whatever the field currently holds, then verify below — the
# verification (not the match pattern) is what catches drift.
sed -i.bak \
  -e "s|^application/short_version=.*$|application/short_version=\"${SHORT_VERSION}\"|" \
  -e "s|^application/version=.*$|application/version=\"${BUILD_VERSION}\"|" \
  "$PRESETS_FILE"
rm -f "${PRESETS_FILE}.bak"

if ! grep -qxF "application/short_version=\"${SHORT_VERSION}\"" "$PRESETS_FILE"; then
  echo "::error::application/short_version was not injected into $PRESETS_FILE — the preset file may have drifted." >&2
  exit 1
fi
if ! grep -qxF "application/version=\"${BUILD_VERSION}\"" "$PRESETS_FILE"; then
  echo "::error::application/version was not injected into $PRESETS_FILE — the preset file may have drifted." >&2
  exit 1
fi

echo "Injected version into ${PRESETS_FILE}: short_version=${SHORT_VERSION} version=${BUILD_VERSION}"
