#!/usr/bin/env bash
# CI test for release tag validation (#391, #491).
#
# Verifies:
#   1. .github/workflows/release.yml runs the shared validate-release-tag
#      composite action as its first validate-job step, i.e. before any
#      export job's sed substitution interpolates the tag.
#   2. The tag pattern in .github/actions/validate-release-tag/validate.sh
#      (single source of truth) is the same regex
#      .github/workflows/manual-release.yml enforces.
#   3. The shared validation script accepts a valid tag (0.0.22) and rejects
#      invalid tags with a non-zero exit code.
#   4. The shared validator accepts a single leading "v", publishes the
#      canonical tag, and both entry points build that canonical tag (#491).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
MANUAL_YML="$REPO_ROOT/.github/workflows/manual-release.yml"
ACTION_DIR="$REPO_ROOT/.github/actions/validate-release-tag"
VALIDATE_SH="$ACTION_DIR/validate.sh"
ACTION_YML="$ACTION_DIR/action.yml"

fail() {
  echo "::error::$1"
  exit 1
}

# Print the body of a single job block. A job block starts at a line matching
# "^  <jobname>:" and ends at the next line matching "^  [A-Za-z0-9_-]+:".
extract_job() {
  local job="$1"
  awk -v job="$job" '
    $0 ~ "^  " job ":[[:space:]]*$" { in_job = 1; next }
    in_job && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { in_job = 0 }
    in_job { print }
  ' "$RELEASE_YML"
}

# 1. release.yml must run the shared composite action.
grep -q -F 'uses: ./.github/actions/validate-release-tag' "$RELEASE_YML" \
  || fail "release.yml does not run the shared validate-release-tag composite action"

# 1a. The validation step must come before any ${{ env.RELEASE_TAG }} use,
# so an invalid tag exits before the sed substitution is reached.
VALIDATE_LINE="$(grep -n -F 'uses: ./.github/actions/validate-release-tag' "$RELEASE_YML" | head -n1 | cut -d: -f1)"
[ -n "$VALIDATE_LINE" ] || fail "could not locate the validate-release-tag step in release.yml"
FIRST_USE_LINE="$(grep -n '\${{ env.RELEASE_TAG }}' "$RELEASE_YML" | head -n1 | cut -d: -f1)"
if [ -n "$FIRST_USE_LINE" ] && [ "$FIRST_USE_LINE" -lt "$VALIDATE_LINE" ]; then
  fail "release.yml uses \${{ env.RELEASE_TAG }} at line $FIRST_USE_LINE before the validation step at line $VALIDATE_LINE"
fi
echo "OK: validate-release-tag (line $VALIDATE_LINE) precedes first RELEASE_TAG use (line ${FIRST_USE_LINE:-n/a})"

# 2. The shared pattern is the single source of truth and must stay identical
# to the documented regex.
SHARED_PATTERN="$(grep -o "RELEASE_TAG_PATTERN='[^']*'" "$VALIDATE_SH" | cut -d"'" -f2)"
[ -n "$SHARED_PATTERN" ] || fail "could not read RELEASE_TAG_PATTERN from validate.sh"
EXPECTED_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$'
[ "$SHARED_PATTERN" = "$EXPECTED_PATTERN" ] \
  || fail "shared pattern ($SHARED_PATTERN) drifted from the documented regex ($EXPECTED_PATTERN)"
echo "OK: shared pattern matches the documented regex: $SHARED_PATTERN"

# 2a. manual-release.yml must delegate to the same composite action, so both
# entry points agree on what a valid tag looks like.
grep -q -F 'uses: ./.github/actions/validate-release-tag' "$MANUAL_YML" \
  || fail "manual-release.yml does not delegate to the shared validate-release-tag action"
echo "OK: manual-release.yml delegates to the shared validate-release-tag action"

# 3. Exercise the shared validation script.
run_validation() {
  RELEASE_TAG_INPUT="$1" bash "$VALIDATE_SH"
}

run_validation "0.0.22" >/dev/null \
  || fail "shared validator rejected a valid tag: 0.0.22"
echo "OK: shared validator accepts 0.0.22"

# 3a. Only a single lowercase leading "v" is stripped, so these stay invalid.
for invalid in "0.1" "1.2" "abc" '1.2.3"$(reboot)' "vv1.2.3" "1.2.3v" "V1.2.3" "v"; do
  if RELEASE_TAG_INPUT="$invalid" bash "$VALIDATE_SH" >/dev/null 2>&1; then
    fail "shared validator accepted an invalid tag: $invalid"
  fi
  echo "OK: shared validator rejects invalid tag: $invalid"
done

if RELEASE_TAG_INPUT="" bash "$VALIDATE_SH" >/dev/null 2>&1; then
  fail "shared validator accepted an empty tag"
fi
echo "OK: shared validator rejects an empty tag"

# 4. A leading "v" is accepted, and the validator publishes the canonical tag
# so every downstream step uses the stripped form (#491).
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/release-tag-output.XXXXXX")"
trap 'rm -f "$OUTPUT_FILE"' EXIT

GITHUB_OUTPUT="$OUTPUT_FILE" RELEASE_TAG_INPUT="v0.0.22" bash "$VALIDATE_SH" >/dev/null \
  || fail "shared validator rejected a v-prefixed tag: v0.0.22"
grep -q -x 'tag=0\.0\.22' "$OUTPUT_FILE" \
  || fail "shared validator did not publish the canonical tag for v0.0.22"
echo "OK: shared validator accepts v0.0.22 and publishes the canonical tag 0.0.22"

: > "$OUTPUT_FILE"
GITHUB_OUTPUT="$OUTPUT_FILE" RELEASE_TAG_INPUT="0.0.22" bash "$VALIDATE_SH" >/dev/null \
  || fail "shared validator rejected a valid tag: 0.0.22"
grep -q -x 'tag=0\.0\.22' "$OUTPUT_FILE" \
  || fail "shared validator did not publish the canonical tag for 0.0.22"
echo "OK: shared validator publishes the canonical tag for 0.0.22"

# 4a. The composite action must expose the canonical tag as an output.
grep -q -F 'value: ${{ steps.validate.outputs.tag }}' "$ACTION_YML" \
  || fail "the validate-release-tag action does not expose the canonical tag output"
echo "OK: the validate-release-tag action exposes the canonical tag output"

# 4b. manual-release.yml must not strip the prefix itself. The shared
# validator owns the rule, so the two entry points cannot disagree.
if grep -q -E '\$\{[A-Za-z_][A-Za-z0-9_]*#v\}' "$MANUAL_YML"; then
  fail "manual-release.yml strips the v prefix itself instead of using the shared validator"
fi
MANUAL_TAG_USES="$(grep -c -F 'steps.validate.outputs.tag' "$MANUAL_YML" || true)"
[ "$MANUAL_TAG_USES" -ge 2 ] \
  || fail "manual-release.yml does not use the canonical tag from the shared validator for both the tag and the release"
echo "OK: manual-release.yml uses the canonical tag from the shared validator"

# 4c. release.yml must build and publish the canonical tag, not the raw input.
grep -q -F 'ref: ${{ steps.validate.outputs.tag }}' "$RELEASE_YML" \
  || fail "release.yml does not check out the canonical tag from the shared validator"
for job in linux windows macos web publish; do
  JOB_BLOCK="$(extract_job "$job")"
  [ -n "$JOB_BLOCK" ] || fail "release.yml has no $job job"
  printf '%s\n' "$JOB_BLOCK" | grep -q -F 'RELEASE_TAG: ${{ needs.validate.outputs.tag }}' \
    || fail "the $job job does not use the canonical tag from the shared validator"
done
extract_job publish | grep -q -E '^[[:space:]]*-[[:space:]]+validate[[:space:]]*$' \
  || fail "the publish job does not need the validate job, so it cannot read the canonical tag"
echo "OK: release.yml builds and publishes the canonical tag from the shared validator"

echo "All release tag validation checks passed"
