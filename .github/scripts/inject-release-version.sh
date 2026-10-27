#!/usr/bin/env bash
# Single source of truth for writing a release tag into export_presets.cfg (#444).
#
# The macOS export maps application/short_version to CFBundleShortVersionString
# and application/version to CFBundleVersion, which Apple constrains to at most
# three period-separated non-negative integers. A prerelease tag such as
# 1.2.3-rc.1 therefore lands in full in short_version, while version gets the
# numeric core (1.2.3).
#
# Prerelease policy for CFBundleShortVersionString (#452): the raw tag is kept,
# including any prerelease/build suffix. That is not a conforming
# CFBundleShortVersionString for App Store validation (up to three
# period-separated non-negative integers), so direct (non-App-Store)
# distribution of prerelease builds is assumed.
#
# The tag pattern is NOT defined here. It is sourced from
# .github/actions/validate-release-tag/validate.sh, the shared single source of
# truth for release tags, so the validator and this script can never disagree
# about what a valid tag looks like (#452).
#
# The rewrite is scoped to the macOS preset's options block: only lines inside
# [preset.N.options] for the preset named "macOS" are modified, and the
# post-write verification proves every line outside that block is unchanged
# (#452). Leading whitespace inside the block is tolerated and preserved.
#
# Usage:
#   inject-release-version.sh <release-tag> [presets-file]
#     Rewrites application/short_version and application/version inside the
#     macOS preset's options block of presets-file (default:
#     export_presets.cfg). Fails if the macOS preset or either field is
#     absent, so preset drift can never silently ship an untracked version.
#
#   inject-release-version.sh --build-version <release-tag>
#     Prints the derived CFBundleVersion for the tag and exits. Used by the
#     release workflow's Info.plist assertion so the build-version derivation
#     lives in exactly one place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SH="${SCRIPT_DIR}/../actions/validate-release-tag/validate.sh"
if [[ ! -f "$VALIDATE_SH" ]]; then
  echo "::error::Shared release tag validator not found: $VALIDATE_SH" >&2
  exit 1
fi
# Defines RELEASE_TAG_PATTERN; validation itself only runs when validate.sh is
# executed directly (see its sourced-vs-executed guard).
# shellcheck source=../actions/validate-release-tag/validate.sh
. "$VALIDATE_SH"

derive_build_version() {
  local tag="$1"
  if [[ ! "$tag" =~ $RELEASE_TAG_PATTERN ]]; then
    echo "::error::Invalid release tag: $tag — must match ${RELEASE_TAG_PATTERN}" >&2
    return 1
  fi
  # Numeric core (1.2.3-rc.1 -> 1.2.3): the first three dot-separated
  # components, each truncated at its first non-digit. Derivation follows
  # whatever the shared pattern accepts (any suffix delimiter, including a
  # future '+' build-metadata suffix) without redefining the pattern here.
  local parts
  IFS=. read -r -a parts <<< "$tag"
  echo "${parts[0]%%[!0-9]*}.${parts[1]%%[!0-9]*}.${parts[2]%%[!0-9]*}"
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

# Locate the macOS preset index so the rewrite can be scoped to its options
# block instead of matching version keys wherever they appear (#452).
MACOS_PRESET_INDEX="$(
  awk -F'"' '
    /^\[preset\.[0-9]+\][[:space:]]*$/ {
      cur = $0
      sub(/^\[preset\./, "", cur)
      sub(/\][[:space:]]*$/, "", cur)
    }
    cur != "" && /^name=/ && $2 == "macOS" { print cur; exit }
  ' "$PRESETS_FILE"
)"
if [[ -z "$MACOS_PRESET_INDEX" ]]; then
  echo "::error::No macOS preset found in $PRESETS_FILE — cannot scope the version injection." >&2
  exit 1
fi
MACOS_OPTIONS_SECTION="[preset.${MACOS_PRESET_INDEX}.options]"

# Lines outside the macOS options block, and in-block field reads, extracted
# identically from any version of the file, for the verification below.
outside_block_lines() {
  awk -v section="$MACOS_OPTIONS_SECTION" '
    $0 == section { inblock = 1; next }
    /^\[[^]]*\][[:space:]]*$/ { inblock = 0 }
    !inblock { print }
  ' "$1"
}

block_field() {
  awk -v section="$MACOS_OPTIONS_SECTION" -v key="$2" '
    $0 == section { inblock = 1; next }
    /^\[[^]]*\][[:space:]]*$/ { inblock = 0 }
    inblock {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (substr(line, 1, length(key) + 1) == key "=") {
        sub(/^[^=]*=/, "", line)
        gsub(/^"|"$/, "", line)
        print line
        exit
      }
    }
  ' "$1"
}

# Replace whatever the two fields currently hold inside the block (preserving
# any leading indentation), leaving every other line byte-identical; the
# verification below — not the match pattern — is what catches drift.
TMP_PRESETS="$(mktemp "${TMPDIR:-/tmp}/export_presets.XXXXXX")"
trap 'rm -f "$TMP_PRESETS" "${TMP_PRESETS}.diff"' EXIT

awk -v section="$MACOS_OPTIONS_SECTION" -v short="$SHORT_VERSION" -v build="$BUILD_VERSION" '
  $0 == section { inblock = 1; print; next }
  /^\[[^]]*\][[:space:]]*$/ { inblock = 0 }
  inblock && /^[[:space:]]*application\/short_version=/ {
    line = $0
    sub(/application\/short_version=.*$/, "application/short_version=\"" short "\"", line)
    print line
    next
  }
  inblock && /^[[:space:]]*application\/version=/ {
    line = $0
    sub(/application\/version=.*$/, "application/version=\"" build "\"", line)
    print line
    next
  }
  { print }
' "$PRESETS_FILE" > "$TMP_PRESETS"

# Verification: the two fields must hold the expected values inside the macOS
# block, and nothing outside that block may have changed.
if [[ "$(block_field "$TMP_PRESETS" application/short_version)" != "$SHORT_VERSION" ]]; then
  echo "::error::application/short_version was not injected into $MACOS_OPTIONS_SECTION in $PRESETS_FILE — the preset file may have drifted." >&2
  exit 1
fi
if [[ "$(block_field "$TMP_PRESETS" application/version)" != "$BUILD_VERSION" ]]; then
  echo "::error::application/version was not injected into $MACOS_OPTIONS_SECTION in $PRESETS_FILE — the preset file may have drifted." >&2
  exit 1
fi

if ! diff -u <(outside_block_lines "$PRESETS_FILE") <(outside_block_lines "$TMP_PRESETS") > "${TMP_PRESETS}.diff" 2>&1; then
  echo "::error::Version injection would change lines outside the macOS preset block ($MACOS_OPTIONS_SECTION) of $PRESETS_FILE:" >&2
  cat "${TMP_PRESETS}.diff" >&2
  exit 1
fi
rm -f "${TMP_PRESETS}.diff"

# All checks passed: publish the rewrite in place, preserving file
# permissions and the original's trailing-newline state, so even EOF bytes
# outside the block are untouched.
if [[ -n "$(tail -c 1 "$PRESETS_FILE")" ]]; then
  printf '%s' "$(cat "$TMP_PRESETS")" > "$PRESETS_FILE"
else
  cat "$TMP_PRESETS" > "$PRESETS_FILE"
fi

echo "Injected version into ${PRESETS_FILE}: short_version=${SHORT_VERSION} version=${BUILD_VERSION} (block ${MACOS_OPTIONS_SECTION})"
