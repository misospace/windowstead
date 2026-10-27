#!/usr/bin/env bash
# CI test for macOS bundle version injection (#444, hardened for #452).
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
# 6. The tag pattern is sourced from the shared validator instead of being
#    duplicated (#452), and loosening the validator propagates to the script.
# 7. The rewrite is scoped to the macOS preset's options block: identical keys
#    in other presets are left untouched (#452).
# 8. A re-indented macOS options block is still rewritten, indentation kept.
# 9. The macOS export step does not shadow the workflow-level RELEASE_TAG
#    with a redundant step-level env (#452).
# 10. The prerelease CFBundleShortVersionString policy is stated in the script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
INJECT_SH="$REPO_ROOT/.github/scripts/inject-release-version.sh"
VALIDATE_SH="$REPO_ROOT/.github/actions/validate-release-tag/validate.sh"

fail() {
  echo "::error::$1"
  exit 1
}

[ -f "$INJECT_SH" ] || fail "missing injection script: $INJECT_SH"
[ -f "$VALIDATE_SH" ] || fail "missing shared validator: $VALIDATE_SH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_presets() {
  local file="$1"
  cat > "$file" <<'CFG'
[preset.0]
name="Linux/X11"

[preset.0.options]

[preset.2]
name="macOS"

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
[preset.2]
name="macOS"

[preset.2.options]
application/icon="res://icon.svg"
CFG
if bash "$INJECT_SH" "1.2.3-rc.1" "$DRIFT" >/dev/null 2>&1; then
  fail "injection succeeded on a presets file with no version fields"
fi
echo "OK: injection fails when version fields are absent (drift guard)"

# 4a. A presets file without any macOS preset must fail rather than rewrite
# whatever other preset carries the keys.
NOMAC="$TMP_DIR/nomacos.cfg"
cat > "$NOMAC" <<'CFG'
[preset.2]
name="Windows Desktop"

[preset.2.options]
application/short_version="0.1.0"
application/version="0.1.0"
CFG
if bash "$INJECT_SH" "1.2.3" "$NOMAC" >/dev/null 2>&1; then
  fail "injection succeeded on a presets file with no macOS preset"
fi
grep -qF 'application/version="0.1.0"' "$NOMAC" \
  || fail "injection modified a presets file it should have rejected"
echo "OK: injection fails when no macOS preset exists (scope guard)"

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

# 6. The tag pattern is sourced from the shared validator, not duplicated.
if grep -Eq "^RELEASE_TAG_PATTERN=" "$INJECT_SH"; then
  fail "inject-release-version.sh defines its own RELEASE_TAG_PATTERN instead of sourcing the shared validator"
fi
grep -qF 'actions/validate-release-tag/validate.sh' "$INJECT_SH" \
  || fail "inject-release-version.sh does not source the shared validator for the tag pattern"
echo "OK: inject-release-version.sh sources the shared tag pattern"

# 6a. Loosening the shared validator must propagate to the injection script:
# in a sandbox tree whose validator also accepts '+' build metadata, the
# script must accept such a tag and still derive the numeric core.
SBOX="$TMP_DIR/sandbox"
mkdir -p "$SBOX/.github/scripts" "$SBOX/.github/actions/validate-release-tag"
cp "$INJECT_SH" "$SBOX/.github/scripts/inject-release-version.sh"
sed 's/\[-\.\]/[-.+]/' "$VALIDATE_SH" > "$SBOX/.github/actions/validate-release-tag/validate.sh"
grep -qF '[-.+]' "$SBOX/.github/actions/validate-release-tag/validate.sh" \
  || fail "could not build a loosened validator copy for the sandbox"
SBX_PRESETS="$TMP_DIR/sandbox-presets.cfg"
make_presets "$SBX_PRESETS"
bash "$SBOX/.github/scripts/inject-release-version.sh" "1.2.3+build.5" "$SBX_PRESETS" >/dev/null \
  || fail "injection script did not follow a loosened shared validator (1.2.3+build.5 rejected)"
[ "$(field "$SBX_PRESETS" 'application/short_version')" = 'application/short_version="1.2.3+build.5"' ] \
  || fail "loosened-validator short_version wrong: $(field "$SBX_PRESETS" 'application/short_version')"
[ "$(field "$SBX_PRESETS" 'application/version')" = 'application/version="1.2.3"' ] \
  || fail "loosened-validator version wrong: $(field "$SBX_PRESETS" 'application/version')"
echo "OK: loosening the shared validator propagates to the injection script"

# 6b. The real (unloosened) validator's pattern still rejects build metadata.
make_presets "$SBX_PRESETS"
if bash "$INJECT_SH" "1.2.3+build.5" "$SBX_PRESETS" >/dev/null 2>&1; then
  fail "injection accepted 1.2.3+build.5 although the shared validator rejects it"
fi
echo "OK: injection rejects tags the current shared validator rejects"

# 7. The rewrite is scoped to the macOS preset's options block (#452).
SCOPED="$TMP_DIR/scoped.cfg"
cat > "$SCOPED" <<'CFG'
[preset.2]
name="macOS"

[preset.2.options]
application/short_version="0.1.0"
application/version="0.1.0"

[preset.9]
name="Android"

[preset.9.options]
application/short_version="9.9.9"
application/version="9.9.9"
CFG
bash "$INJECT_SH" "1.2.3-rc.1" "$SCOPED" >/dev/null \
  || fail "scoped injection failed on a multi-preset file"
grep -qF 'application/short_version="1.2.3-rc.1"' "$SCOPED" \
  || fail "macOS short_version was not rewritten in a multi-preset file"
grep -qF 'application/version="1.2.3"' "$SCOPED" \
  || fail "macOS version was not rewritten in a multi-preset file"
grep -qF 'application/short_version="9.9.9"' "$SCOPED" \
  || fail "injection modified application/short_version outside the macOS preset block"
grep -qF 'application/version="9.9.9"' "$SCOPED" \
  || fail "injection modified application/version outside the macOS preset block"
echo "OK: rewrite is scoped to the macOS preset's options block"

# 8. Re-indented options keys are still rewritten, with indentation kept.
INDENT="$TMP_DIR/indent.cfg"
cat > "$INDENT" <<'CFG'
[preset.2]
name="macOS"

[preset.2.options]
    application/short_version="0.1.0"
    application/version="0.1.0"
CFG
bash "$INJECT_SH" "1.2.3-rc.1" "$INDENT" >/dev/null \
  || fail "injection failed on a re-indented macOS options block"
grep -qF '    application/short_version="1.2.3-rc.1"' "$INDENT" \
  || fail "re-indented short_version was not rewritten correctly"
grep -qF '    application/version="1.2.3"' "$INDENT" \
  || fail "re-indented version was not rewritten correctly"
echo "OK: re-indented macOS options block is rewritten with indentation preserved"

# 9. No step-level env shadows the workflow-level RELEASE_TAG (#452).
if grep -qF 'RELEASE_TAG: ${{ env.RELEASE_TAG }}' "$RELEASE_YML"; then
  fail "release.yml still shadows the workflow-level RELEASE_TAG with a step-level env"
fi
echo "OK: release.yml does not shadow the workflow-level RELEASE_TAG"

# 10. The prerelease CFBundleShortVersionString policy is stated (#452).
grep -qi 'App Store' "$INJECT_SH" \
  || fail "inject-release-version.sh does not state the App Store constraint on CFBundleShortVersionString"
grep -qi 'non-App-Store' "$INJECT_SH" \
  || fail "inject-release-version.sh keeps the raw tag but does not state that direct (non-App-Store) distribution is assumed"
grep -qi 'distribution.*assumed\|assumed.*distribution' "$INJECT_SH" \
  || fail "inject-release-version.sh does not state that direct distribution is assumed"
echo "OK: prerelease CFBundleShortVersionString policy is stated in the script"

echo "All release version injection checks passed"
