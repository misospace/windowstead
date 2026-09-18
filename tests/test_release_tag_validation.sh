#!/usr/bin/env bash
# CI test for release tag validation (#391).
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
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
MANUAL_YML="$REPO_ROOT/.github/workflows/manual-release.yml"
ACTION_DIR="$REPO_ROOT/.github/actions/validate-release-tag"
VALIDATE_SH="$ACTION_DIR/validate.sh"

fail() {
  echo "::error::$1"
  exit 1
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

for invalid in "0.1" "1.2" "abc" '1.2.3"$(reboot)' "v1.2.3"; do
  if RELEASE_TAG_INPUT="$invalid" bash "$VALIDATE_SH" >/dev/null 2>&1; then
    fail "shared validator accepted an invalid tag: $invalid"
  fi
  echo "OK: shared validator rejects invalid tag: $invalid"
done

if RELEASE_TAG_INPUT="" bash "$VALIDATE_SH" >/dev/null 2>&1; then
  fail "shared validator accepted an empty tag"
fi
echo "OK: shared validator rejects an empty tag"

echo "All release tag validation checks passed"
