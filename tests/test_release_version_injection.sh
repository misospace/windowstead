#!/usr/bin/env bash
# CI test for macOS bundle version injection (#444).
#
# application/version maps to CFBundleVersion, which Apple constrains to at
# most three period-separated non-negative integers, so a prerelease tag like
# 1.2.3-rc.1 must not land in it verbatim.
#
# Verifies:
# 1. inject-release-version.sh puts the full tag in application/short_version
#    and the numeric core in application/version for prerelease tags.
# 2. Plain semantic-version tags keep both fields equal to the tag.
# 3. --build-version prints the derived CFBundleVersion and rejects invalid tags.
# 4. Injection fails when a version field is absent from the presets file.
# 5. release.yml's macOS job runs the script and asserts both CFBundleVersion
#    and CFBundleShortVersionString on the exported Info.plist, and no longer
#    seds the raw tag into application/version.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
INJECT_SH="$REPO_ROOT/.github/scripts/inject-release-version.sh"

fail() {
  echo "::error::$1"
  exit 1
}

[ -f "$INJECT_SH" ] || fail "missing injection script: $INJECT_SH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_presets() {
  local file="$1"
  cat > "$file" <<'CFG'
[preset.2.options]
application/icon="res://icon.svg"
application/bundle_identifier="com.misospace.windowstead"
application/signature=""
application/short_version="0.1.0"
application/version="0.1.0"
CFG
}

field() {
  local file="$1" key="$2"
  grep "^${key}=" "$file"
}

# 1. Prerelease tag: full tag in short_version, numeric core in version.
PRE="$TMP_DIR/prerelease.cfg"
make_presets "$PRE"
bash "$INJECT_SH" "1.2.3-rc.1" "$PRE" >/dev/null \
  || fail "injection script rejected prerelease tag 1.2.3-rc.1"
[ "$(field "$PRE" 'application/short_version')" = 'application/short_version="1.2.3-rc.1"' ] \
  || fail "prerelease tag did not land in application/short_version: $(field "$PRE" 'application/short_version')"
[ "$(field "$PRE" 'application/version')" = 'application/version="1.2.3"' ] \
  || fail "prerelease build version is not the numeric core: $(field "$PRE" 'application/version')"
echo "OK: prerelease tag 1.2.3-rc.1 -> short_version=1.2.3-rc.1 version=1.2.3"

# 1a. Longer prerelease forms also reduce to the numeric core.
for tag in "2.0.0-alpha.10" "0.9.0-beta.2"; do
  P="$TMP_DIR/core.cfg"
  make_presets "$P"
  bash "$INJECT_SH" "$tag" "$P" >/dev/null \
    || fail "injection script rejected prerelease tag $tag"
  core="${tag%%[-+]*}"
  [ "$(field "$P" 'application/version')" = "application/version=\"$core\"" ] \
    || fail "tag $tag produced non-core build version: $(field "$P" 'application/version')"
done
echo "OK: prerelease tags reduce to the numeric core build version"

# 2. Plain semver tag: both fields equal the tag (unchanged behavior).
PLAIN="$TMP_DIR/plain.cfg"
make_presets "$PLAIN"
bash "$INJECT_SH" "0.0.22" "$PLAIN" >/dev/null \
  || fail "injection script rejected plain tag 0.0.22"
[ "$(field "$PLAIN" 'application/short_version')" = 'application/short_version="0.0.22"' ] \
  || fail "plain tag did not land in application/short_version"
[ "$(field "$PLAIN" 'application/version')" = 'application/version="0.0.22"' ] \
  || fail "plain tag changed application/version: $(field "$PLAIN" 'application/version')"
echo "OK: plain tag 0.0.22 keeps both fields equal to the tag"

# 3. --build-version derivation mirrors the injection.
for pair in "1.2.3-rc.1:1.2.3" "0.0.22:0.0.22" "2.0.0-alpha.10:2.0.0"; do
  tag="${pair%%:*}"
  expected="${pair#*:}"
  actual="$(bash "$INJECT_SH" --build-version "$tag")" \
    || fail "--build-version rejected valid tag $tag"
  [ "$actual" = "$expected" ] \
    || fail "--build-version for $tag printed '$actual', expected '$expected'"
done
echo "OK: --build-version derives the conforming build version"

for invalid in "0.1" "abc" '1.2.3"$(reboot)' "v1.2.3" ""; do
  if bash "$INJECT_SH" --build-version "$invalid" >/dev/null 2>&1; then
    fail "--build-version accepted invalid tag: $invalid"
  fi
  P="$TMP_DIR/invalid.cfg"
  make_presets "$P"
  if bash "$INJECT_SH" "$invalid" "$P" >/dev/null 2>&1; then
    fail "injection accepted invalid tag: $invalid"
  fi
done
echo "OK: invalid tags are rejected by both modes"

# 4. Drift guard: absent version fields must fail the injection.
DRIFT="$TMP_DIR/drift.cfg"
cat > "$DRIFT" <<'CFG'
[preset.2.options]
application/icon="res://icon.svg"
CFG
if bash "$INJECT_SH" "1.2.3-rc.1" "$DRIFT" >/dev/null 2>&1; then
  fail "injection succeeded on a presets file with no version fields"
fi
echo "OK: injection fails when version fields are absent (drift guard)"

if bash "$INJECT_SH" "1.2.3" "$TMP_DIR/nonexistent.cfg" >/dev/null 2>&1; then
  fail "injection succeeded on a missing presets file"
fi
echo "OK: injection fails when the presets file is missing"

# 5. Workflow wiring.
grep -q -F '.github/scripts/inject-release-version.sh' "$RELEASE_YML" \
  || fail "release.yml does not run .github/scripts/inject-release-version.sh"
echo "OK: release.yml runs the injection script"

if grep -qF 'application/version=' "$RELEASE_YML"; then
  fail "release.yml still rewrites application/version inline instead of via the script"
fi
echo "OK: release.yml no longer seds application/version inline"

grep -q -F 'CFBundleShortVersionString' "$RELEASE_YML" \
  || fail "release.yml does not read CFBundleShortVersionString from the exported Info.plist"
grep -q -F 'CFBundleVersion' "$RELEASE_YML" \
  || fail "release.yml does not read CFBundleVersion from the exported Info.plist"
grep -q -F "get('CFBundleVersion','')" "$RELEASE_YML" \
  || fail "release.yml does not load CFBundleVersion from the exported Info.plist"
echo "OK: release.yml asserts both CFBundleShortVersionString and CFBundleVersion"

echo "All release version injection checks passed"
