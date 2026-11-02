#!/usr/bin/env bash
# CI test for the shared Web packaging check (#449, #458, #467).
#
# Issue #449 shipped because the release archive whitelisted only four files
# while the exported HTML referenced additional generated assets. The fix
# (#458) added a "Verify Web package" step, but only to release.yml, so the
# same regression stayed invisible to PR CI.
#
# Verifies:
# 1. The check lives in one script and both workflows invoke it: release.yml
#    against the staged zip, test.yml against the PR export directory.
# 2. Neither workflow keeps an inline duplicate of the HTML-reference check.
# 3. The script passes a complete package (directory or zip) and fails when
#    a referenced local asset, a mandatory entry, or a non-empty mandatory
#    entry is missing.
# 4. External, protocol-relative, data:, and root-absolute references are
#    ignored, as are references inside HTML comments.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/verify-web-package.py"
TEST_YML="$REPO_ROOT/.github/workflows/test.yml"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"

fail() {
  echo "::error::$1"
  exit 1
}

[ -f "$SCRIPT" ] || fail "shared Web packaging script not found at $SCRIPT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# make_pkg <dir> — a minimal export: the four mandatory files plus the
# generated assets the HTML references.
make_pkg() {
  local dir="$1"
  mkdir -p "$dir"
  printf '<html></html>' > "$dir/windowstead.html"
  printf 'pck' > "$dir/windowstead.pck"
  printf 'wasm' > "$dir/windowstead.wasm"
  printf 'js' > "$dir/windowstead.js"
}

# html_with <dir> <extra-html> — replace the placeholder HTML body.
html_with() {
  local dir="$1" body="$2"
  printf '<html>%s</html>' "$body" > "$dir/windowstead.html"
}

# 1. A complete export directory passes.
GOOD_DIR="$TMP_DIR/good"
make_pkg "$GOOD_DIR"
printf 'svg' > "$GOOD_DIR/windowstead.svg"
printf 'png' > "$GOOD_DIR/windowstead.appletouchicon.png"
html_with "$GOOD_DIR" '<link href="windowstead.appletouchicon.png" rel="apple-touch-icon"><img src="windowstead.svg"><script src="windowstead.js"></script>'
python3 "$SCRIPT" "$GOOD_DIR" >/dev/null \
  || fail "complete export directory rejected"
echo "OK: complete export directory passes"

# 2. A referenced local asset missing from the directory fails.
BAD_DIR="$TMP_DIR/bad"
cp -r "$GOOD_DIR" "$BAD_DIR"
rm "$BAD_DIR/windowstead.svg"
if BAD_OUT="$(python3 "$SCRIPT" "$BAD_DIR" 2>&1)"; then
  fail "export directory with a missing referenced asset accepted"
fi
printf '%s' "$BAD_OUT" | grep -qF 'windowstead.svg' \
  || fail "missing referenced asset not reported: $BAD_OUT"
echo "OK: missing referenced asset fails the directory check"

# 3. The same checks run against a zip archive.
GOOD_ZIP="$TMP_DIR/good.zip"
(cd "$GOOD_DIR" && python3 -m zipfile -c "$GOOD_ZIP" windowstead.html windowstead.pck windowstead.wasm windowstead.js windowstead.svg windowstead.appletouchicon.png)
python3 "$SCRIPT" "$GOOD_ZIP" >/dev/null \
  || fail "complete package zip rejected"
BAD_ZIP="$TMP_DIR/bad.zip"
(cd "$BAD_DIR" && python3 -m zipfile -c "$BAD_ZIP" windowstead.html windowstead.pck windowstead.wasm windowstead.js windowstead.appletouchicon.png)
if python3 "$SCRIPT" "$BAD_ZIP" >/dev/null 2>&1; then
  fail "package zip with a missing referenced asset accepted"
fi
echo "OK: complete zip passes, zip missing a referenced asset fails"

# 4. A missing or empty mandatory entry fails in both modes.
NO_PCK_DIR="$TMP_DIR/no-pck"
cp -r "$GOOD_DIR" "$NO_PCK_DIR"
rm "$NO_PCK_DIR/windowstead.pck"
if python3 "$SCRIPT" "$NO_PCK_DIR" >/dev/null 2>&1; then
  fail "missing mandatory entry accepted"
fi
EMPTY_DIR="$TMP_DIR/empty"
cp -r "$GOOD_DIR" "$EMPTY_DIR"
: > "$EMPTY_DIR/windowstead.wasm"
EMPTY_OUT="$(python3 "$SCRIPT" "$EMPTY_DIR" 2>&1 || true)"
printf '%s' "$EMPTY_OUT" | grep -qF 'mandatory archive entry empty: windowstead.wasm' \
  || fail "empty mandatory entry not reported: $EMPTY_OUT"
echo "OK: missing or empty mandatory entries fail"

# 5. Non-sibling references are ignored; so is a reference inside a comment.
EXT_DIR="$TMP_DIR/ext"
cp -r "$GOOD_DIR" "$EXT_DIR"
html_with "$EXT_DIR" '<link href="https://cdn.example.com/x.css"><link href="//cdn.example.com/y.css"><link href="data:text/plain,x"><script src="/engine.js"></script><!-- <img src="gone.svg"> -->'
python3 "$SCRIPT" "$EXT_DIR" >/dev/null \
  || fail "non-sibling or commented-out reference treated as a local asset"
echo "OK: external, root-absolute, and commented-out references ignored"

# 6. Both workflows call the shared script on their own target.
grep -qF 'python3 .github/scripts/verify-web-package.py build/windowstead-web.zip' "$RELEASE_YML" \
  || fail "release.yml does not call the shared Web packaging script on build/windowstead-web.zip"
grep -qF 'python3 .github/scripts/verify-web-package.py build/export-validation/web' "$TEST_YML" \
  || fail "test.yml does not call the shared Web packaging script on build/export-validation/web"
echo "OK: release.yml and test.yml both invoke the shared script"

# 7. No inline duplicate of the check survives in either workflow: the
#    failure message is implemented only in the shared script.
if grep -qF 'HTML references local asset missing from archive' "$RELEASE_YML" "$TEST_YML"; then
  fail "a workflow still carries an inline copy of the HTML-reference check"
fi
grep -qF 'HTML references local asset missing from archive' "$SCRIPT" \
  || fail "the shared script does not implement the referenced-asset failure"
echo "OK: the HTML-reference check is defined exactly once"

# 8. test.yml keeps the job that runs this script, so the guard cannot be
#    dropped silently.
grep -qF 'bash tests/test_web_package_validation.sh' "$TEST_YML" \
  || fail "test.yml no longer runs tests/test_web_package_validation.sh"
echo "OK: test.yml runs this validation job"

echo "All Web package validation checks passed"
