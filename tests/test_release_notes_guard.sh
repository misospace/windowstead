#!/usr/bin/env bash
# CI test for the release notes guard (#501).
#
# Issue #497 proved the failure mode is silent: release-please 17.6.0
# drops any commit whose message body contains a column-0 line with a
# nested parenthesis, because @conventional-commits/parser throws and
# parseConventionalCommits swallows the error. d47adc5 vanished from
# the 0.1.1 notes with no signal anywhere.
#
# The guard (.github/scripts/verify-release-notes.py) parses only the
# commit header, so a poison body cannot hide a commit from it.
#
# Verifies:
# 1. A candidate commit whose short SHA appears in the notes passes.
# 2. A commit with a conventional header but a parser-breaking poison
#    body is reported MISSING when absent from the notes (the exact
#    #497 shape, d47adc5 style).
# 3. The "(#NNN)" pull-request reference alone counts as coverage.
# 3b. Coverage is limited to the open release section: a PR number or
#     short SHA mentioned only in an older release entry does not
#     cover a dropped commit; the same reference in the open section
#     does.
# 4. Hidden-section types (ci, test) and non-conventional headers are
#    skipped with a visible reason, never silently.
# 5. A merged PR carrying the skip-changelog label is excluded with
#    that reason, verified via the GitHub API; a failed label query
#    keeps the commit missing, and an unavailable query says so; a
#    missing commit without a (#NNN) reference reports why no label
#    check ran.
# 5c. A MISSING commit whose merged PR body names the override marker
#     is checked for the #505 hijack shape: an unpaired or dirty
#     first BEGIN_COMMIT_OVERRIDE ... END_COMMIT_OVERRIDE extraction is
#     reported as a PR-body override-marker hijack; a clean paired
#     block and a marker-free body stay plain MISSING; a failed body
#     query degrades to a note, never a silent pass.
# 6. Absent notes with uncovered candidates fail loudly.
# 7. Notes are read from the release branch ref in CI, and a missing
#    branch is reported as no notes.
# 8. No previous tag falls back to full history; an empty range passes.
# 9. The workflow is wired, read-only, and test.yml runs this test.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/verify-release-notes.py"
GUARD_YML="$REPO_ROOT/.github/workflows/release-notes-guard.yml"
TEST_YML="$REPO_ROOT/.github/workflows/test.yml"
CONFIG="$REPO_ROOT/release-please-config.json"

fail() {
  echo "::error::$1"
  exit 1
}

[ -f "$SCRIPT" ] || fail "guard script not found at $SCRIPT"
command -v python3 >/dev/null || fail "python3 required"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="$TMP_DIR/fakebin"
mkdir -p "$FAKE_BIN"

# make_fake_gh — a stand-in for the GitHub API queries the guard makes.
# The labels endpoint answers with FAKE_GH_JSON (or fails with
# FAKE_GH_EXIT); the pulls endpoint answers with FAKE_PULL_JSON (or
# fails with FAKE_PULL_EXIT); an unset body fixture reads as a PR with
# no body fields. Every call is logged to FAKE_GH_LOG.
cat >"$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
case "$*" in
  */labels*) json="$FAKE_GH_JSON"; exit_code="${FAKE_GH_EXIT:-0}" ;;
  */pulls/*) json="$FAKE_PULL_JSON"; exit_code="${FAKE_PULL_EXIT:-0}" ;;
  *) json=''; exit_code=0 ;;
esac
if [ "$exit_code" != "0" ]; then
  echo "gh: simulated API failure" >&2
  exit "$exit_code"
fi
if [ -n "$json" ]; then printf '%s\n' "$json"; else printf '%s\n' '{}'; fi
EOF
chmod +x "$FAKE_BIN/gh"

# new_repo <dir> — scratch git repo with one tagged base commit.
new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email guard@example.invalid
  git -C "$dir" config user.name "Guard Test"
  git -C "$dir" config commit.gpgsign false
  echo base > "$dir/base.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "chore: base commit"
  git -C "$dir" tag 0.9.0
}

# commit <dir> <subject> [body-file] — one commit, prints the short SHA.
commit() {
  local dir="$1" subject="$2" body_file="${3:-}"
  echo "$(date +%s%N)" >> "$dir/base.txt"
  git -C "$dir" add -A
  if [ -n "$body_file" ]; then
    git -C "$dir" commit -q -F "$body_file"
  else
    git -C "$dir" commit -q -m "$subject"
  fi
  git -C "$dir" rev-parse --short=7 HEAD
}

# run_guard <notes-file|__absent__> <repo> — runs the guard without any
# real credentials, capturing output and exit code in OUT / RC.
run_guard() {
  local notes="$1" repo="$2"
  local args=(--repo "$repo" --config "$CONFIG" --changelog-file "$notes")
  if [ "$notes" = "__absent__" ]; then
    args=(--repo "$repo" --config "$CONFIG" --changelog-file "$TMP_DIR/no-such-notes.md")
  fi
  OUT="$(env -u GH_TOKEN -u GITHUB_TOKEN -u GITHUB_REPOSITORY -u FAKE_GH_LOG \
    python3 "$SCRIPT" "${args[@]}" 2>&1)" && RC=0 || RC=$?
}

REPO="$TMP_DIR/repo"
new_repo "$REPO"

# 1. A commit covered by its short SHA passes.
SHA1="$(commit "$REPO" 'fix(alpha): keep the dock anchored (#101)')"
NOTES="$TMP_DIR/notes.md"
printf '# Changelog\n\n## 0.9.1\n\n* **alpha:** keep the dock anchored ([#101](https://example.invalid)) ([%s](https://example.invalid))\n' "$SHA1" > "$NOTES"
run_guard "$NOTES" "$REPO"
[ "$RC" -eq 0 ] || fail "SHA-covered commit rejected: $OUT"
grep -qF "covered (sha $SHA1)" <<< "$OUT" || fail "SHA coverage not reported: $OUT"
echo "OK: short SHA in notes covers the commit"

# 2. The #497 shape: conventional header, poison body line at column 0
#    with a nested parenthesis (the exact d47adc5 pattern). release-please
#    would drop it; the notes fixture omits it; the guard must report it.
POISON="$TMP_DIR/poison.txt"
cat > "$POISON" <<'EOF'
fix(goals): count only completed builds in any_build goal progress (issue #478) (#102)

Uses build.get("complete", false) with a truthiness check rather than
bool(build.get("complete")) -- bool(null) raises when the key is missing.
EOF
SHA2="$(commit "$REPO" '' "$POISON")"
run_guard "$NOTES" "$REPO"
[ "$RC" -eq 1 ] || fail "commit missing from notes accepted (exit $RC): $OUT"
grep -qF "$SHA2 [MISSING]" <<< "$OUT" || fail "missing commit SHA not reported: $OUT"
grep -qF "visible-type commit(s) since 0.9.0 missing" <<< "$OUT" \
  || fail "missing-commit error summary absent: $OUT"
echo "OK: parser-breaking poison body surfaces as MISSING"

# 3. The (#NNN) reference alone counts as coverage (BEGIN_COMMIT_OVERRIDE
#    keeps the SHA in the entry link, so either match is enough).
printf '* **goals:** count only completed builds ([#102](https://example.invalid))\n' >> "$NOTES"
run_guard "$NOTES" "$REPO"
[ "$RC" -eq 0 ] || fail "PR-reference-covered commit rejected: $OUT"
grep -qF "covered (PR #102 reference)" <<< "$OUT" || fail "PR coverage not reported: $OUT"
echo "OK: (#NNN) reference in notes covers the commit"

# 3b. Coverage is scoped to the open release section: a PR number or
#     short SHA that appears only in an older release entry (a stale
#     "closes #NNN" mention) must not cover a dropped commit. The
#     same reference inside the open section does cover it.
OLDREPO="$TMP_DIR/oldrepo"
new_repo "$OLDREPO"
SHAB="$(commit "$OLDREPO" 'fix(beta): stale reference trap (#107)')"
OLDNOTES="$TMP_DIR/oldnotes.md"
cat > "$OLDNOTES" <<EOF
# Changelog

## 0.9.1

* **alpha:** unrelated entry ([aaa1111](https://example.invalid))

## 0.9.0

* **legacy:** closes #107 and cites ${SHAB} in an older entry
EOF
run_guard "$OLDNOTES" "$OLDREPO"
[ "$RC" -eq 1 ] || fail "old-section PR/SHA mention falsely covered the commit: $OUT"
grep -qF "$SHAB [MISSING]" <<< "$OUT" || fail "stale-section false coverage not rejected: $OUT"
cat > "$OLDNOTES" <<EOF
# Changelog

## 0.9.1

* **alpha:** unrelated entry ([aaa1111](https://example.invalid))
* **beta:** stale reference trap ([#107](https://example.invalid))

## 0.9.0

* **legacy:** closes #107 and cites ${SHAB} in an older entry
EOF
run_guard "$OLDNOTES" "$OLDREPO"
[ "$RC" -eq 0 ] || fail "open-section PR reference rejected: $OUT"
grep -qF "covered (PR #107 reference)" <<< "$OUT" || fail "open-section coverage not reported: $OUT"
echo "OK: coverage is scoped to the open release section"

# 4. Hidden-section types, unknown types, and truly non-conventional
#    headers are skipped, each with its own visible reason.
commit "$REPO" 'ci: deploy nothing (#103)' >/dev/null
commit "$REPO" 'simplify: tidy the dock code (#104)' >/dev/null
commit "$REPO" 'tidy dock code without a type prefix' >/dev/null
run_guard "$NOTES" "$REPO"
[ "$RC" -eq 0 ] || fail "skipped types failed the guard: $OUT"
grep -qF "hidden changelog section" <<< "$OUT" || fail "ci skip reason absent: $OUT"
grep -qF "no changelog section" <<< "$OUT" || fail "unknown-type skip reason absent: $OUT"
grep -qF "header is not a conventional commit" <<< "$OUT" \
  || fail "non-conventional skip reason absent: $OUT"
echo "OK: hidden, unknown, and non-conventional types skipped with reasons"

# 5. skip-changelog label exclusion, via a fake gh.
SHA5="$(commit "$REPO" 'fix(gamma): labeled out (#105)')"
run_guard "$NOTES" "$REPO"
[ "$RC" -eq 1 ] || fail "unlabeled missing commit accepted: $OUT"
grep -qF "$SHA5 [MISSING]" <<< "$OUT" || fail "missing commit not reported without label check: $OUT"
grep -qF "label check unavailable" <<< "$OUT" || fail "unavailable-label-check note absent: $OUT"
export FAKE_GH_LOG="$TMP_DIR/gh.log"
OUT="$(env PATH="$FAKE_BIN:$PATH" GH_TOKEN=fake GITHUB_REPOSITORY=octo/guard-test \
  FAKE_GH_LOG="$FAKE_GH_LOG" FAKE_GH_JSON='[{"name":"Bug"},{"name":"Skip Changelog"}]' \
  python3 "$SCRIPT" --repo "$REPO" --config "$CONFIG" --changelog-file "$NOTES" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] || fail "skip-changelog-labeled commit still failed the guard: $OUT"
grep -qF "skip-changelog label" <<< "$OUT" || fail "exclusion reason absent: $OUT"
grep -qF "repos/octo/guard-test/issues/105/labels" "$FAKE_GH_LOG" \
  || fail "label query used an unexpected endpoint: $(cat "$FAKE_GH_LOG")"
# No skip label on the PR -> still missing.
OUT="$(env PATH="$FAKE_BIN:$PATH" GH_TOKEN=fake GITHUB_REPOSITORY=octo/guard-test \
  FAKE_GH_LOG="$FAKE_GH_LOG" FAKE_GH_JSON='[{"name":"Bug"}]' \
  python3 "$SCRIPT" --repo "$REPO" --config "$CONFIG" --changelog-file "$NOTES" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] || fail "missing commit without skip label accepted: $OUT"
# A failed label query must not silently pass the commit either.
OUT="$(env PATH="$FAKE_BIN:$PATH" GH_TOKEN=fake GITHUB_REPOSITORY=octo/guard-test \
  FAKE_GH_LOG="$FAKE_GH_LOG" FAKE_GH_JSON='[]' FAKE_GH_EXIT=1 \
  python3 "$SCRIPT" --repo "$REPO" --config "$CONFIG" --changelog-file "$NOTES" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] || fail "missing commit accepted after a failed label query: $OUT"
grep -qF "label query for PR #105 failed" <<< "$OUT" || fail "label query failure not surfaced: $OUT"
echo "OK: skip-changelog exclusions reported, failures stay red"

# 5b. A missing candidate with no (#NNN) reference says the label cannot
#     be checked, instead of silently implying one was.
SHA6="$(commit "$REPO" 'fix(zeta): direct push without a PR ref')"
run_guard "$NOTES" "$REPO"
[ "$RC" -eq 1 ] || fail "no-PR-ref missing commit accepted: $OUT"
grep -qF "no (#NNN) PR reference" <<< "$OUT" \
  || fail "no-PR-ref note absent for $SHA6: $OUT"
echo "OK: missing commit without a PR reference reports why no label check"

# 5c. PR-body override-marker hijack detection (#505), via the fake gh.
#     The merged PR body of the missing candidate is fetched from
#     repos/<slug>/pulls/<n>; an extraction that is not exactly one
#     clean conventional-commit header names the drop reason.
HIJREPO="$TMP_DIR/hijrepo"
new_repo "$HIJREPO"
SHA8="$(commit "$HIJREPO" 'fix(theta): prose-named marker (#301)')"
HIJNOTES="$TMP_DIR/hijnotes.md"
printf '# Changelog\n\n## 0.9.1\n\n* **alpha:** unrelated ([bbb2222](https://example.invalid))\n' > "$HIJNOTES"
run_body_guard() {
  OUT="$(env PATH="$FAKE_BIN:$PATH" GH_TOKEN=fake GITHUB_REPOSITORY=octo/guard-test \
    FAKE_GH_LOG="$TMP_DIR/gh-hij.log" FAKE_GH_JSON='[{"name":"Bug"}]' \
    FAKE_PULL_JSON="${FAKE_PULL_JSON-}" FAKE_PULL_EXIT="${FAKE_PULL_EXIT:-0}" \
    python3 "$SCRIPT" --repo "$HIJREPO" --config "$CONFIG" \
    --changelog-file "$HIJNOTES" 2>&1)" && RC=0 || RC=$?
}
# Unpaired begin marker named in prose: release-please replaces the
# message with the trailing prose and drops the commit.
FAKE_PULL_JSON='{"body":"Recover with a BEGIN_COMMIT_OVERRIDE block per the runbook."}' \
  run_body_guard
[ "$RC" -eq 1 ] || fail "hijacked-body commit accepted: $OUT"
grep -qF "$SHA8 [MISSING (PR body override-marker hijack" <<< "$OUT" \
  || fail "unpaired begin marker not reported as hijack: $OUT"
grep -qF "repos/octo/guard-test/pulls/301" "$TMP_DIR/gh-hij.log" \
  || fail "body query used an unexpected endpoint: $(cat "$TMP_DIR/gh-hij.log")"
# A paired block holding exactly one clean header is a working override,
# not a hijack; the commit stays MISSING because the notes lack it.
FAKE_PULL_JSON='{"body":"Summary line.\nBEGIN_COMMIT_OVERRIDE\nfix(theta): honest entry (#301)\nEND_COMMIT_OVERRIDE\nAfterword."}' \
  run_body_guard
[ "$RC" -eq 1 ] || fail "clean-override commit accepted: $OUT"
grep -qF "$SHA8 [MISSING]" <<< "$OUT" || fail "clean-override commit not MISSING: $OUT"
if grep -qF "hijack" <<< "$OUT"; then fail "clean paired block falsely flagged as hijack: $OUT"; fi
# A duplicated begin marker after a clean window matches release-please's
# split('BEGIN_COMMIT_OVERRIDE')[1]: the window is text between the
# first two begins, so a clean first window is still a working override.
FAKE_PULL_JSON='{"body":"BEGIN_COMMIT_OVERRIDE\nfix(theta): honest entry (#301)\nBEGIN_COMMIT_OVERRIDE"}' \
  run_body_guard
[ "$RC" -eq 1 ] || fail "double-begin clean-window commit accepted: $OUT"
if grep -qF "hijack" <<< "$OUT"; then fail "clean first window with duplicate begin falsely flagged: $OUT"; fi
# A body without markers is plain MISSING.
FAKE_PULL_JSON='{"body":"No markers here."}' run_body_guard
grep -qF "$SHA8 [MISSING]" <<< "$OUT" || fail "marker-free commit not MISSING: $OUT"
if grep -qF "hijack" <<< "$OUT"; then fail "marker-free body falsely flagged: $OUT"; fi
# A failed body query adds a note and never claims a hijack.
FAKE_PULL_JSON='{}' FAKE_PULL_EXIT=1 run_body_guard
[ "$RC" -eq 1 ] || fail "commit accepted after a failed body query: $OUT"
grep -qF "PR body query for PR #301 failed" <<< "$OUT" \
  || fail "body query failure not surfaced: $OUT"
grep -qF "$SHA8 [MISSING]" <<< "$OUT" || fail "failed body query lost the MISSING row: $OUT"
if grep -qF "hijack" <<< "$OUT"; then fail "failed body query claimed a hijack: $OUT"; fi
echo "OK: PR-body override-marker hijack named, clean blocks spared, query failure noted"

# 6. No notes at all, uncovered candidates -> loud failure.
run_guard "__absent__" "$REPO"
[ "$RC" -eq 1 ] || fail "absent notes with candidates accepted (exit $RC)"
grep -qF "no notes found at" <<< "$OUT" || fail "absent-notes note missing: $OUT"
grep -qF "$SHA5 [MISSING]" <<< "$OUT" || fail "absent notes did not report candidates: $OUT"
echo "OK: absent notes with uncovered candidates fail loudly"

# 7. Notes read from the release branch itself -- the CI path,
#    git show <ref>:CHANGELOG.md -- and a missing branch reported as
#    no notes rather than an unreadable crash.
cp "$NOTES" "$REPO/CHANGELOG.md"
git -C "$REPO" add CHANGELOG.md
git -C "$REPO" commit -q -m "stage notes for the release branch"
git -C "$REPO" branch release-please--branches--main
run_guard_ref() {
  OUT="$(env -u GH_TOKEN -u GITHUB_TOKEN -u GITHUB_REPOSITORY \
    python3 "$SCRIPT" --repo "$REPO" --config "$CONFIG" \
    --changelog-ref release-please--branches--main 2>&1)" && RC=0 || RC=$?
}
run_guard_ref
[ "$RC" -eq 1 ] || fail "branch notes accepted with a missing commit: $OUT"
grep -qF "covered (sha $SHA1)" <<< "$OUT" || fail "branch notes missed SHA coverage: $OUT"
grep -qF "covered (PR #102 reference)" <<< "$OUT" || fail "branch notes missed PR coverage: $OUT"
grep -qF "$SHA5 [MISSING]" <<< "$OUT" || fail "branch notes missed the missing commit: $OUT"
git -C "$REPO" branch -D release-please--branches--main >/dev/null
run_guard_ref
[ "$RC" -eq 1 ] || fail "absent notes branch accepted: $OUT"
grep -qF "no notes found at release-please--branches--main:CHANGELOG.md" <<< "$OUT" \
  || fail "absent notes branch not reported as no notes: $OUT"
echo "OK: notes read from the release branch ref, absence reported"

# 8. No previous tag guards full history; an empty range passes.
BARE="$TMP_DIR/bare"
mkdir -p "$BARE"
git -C "$BARE" init -q -b main
git -C "$BARE" config user.email guard@example.invalid
git -C "$BARE" config user.name "Guard Test"
git -C "$BARE" config commit.gpgsign false
echo x > "$BARE/x.txt"
git -C "$BARE" add -A
SHA7="$(git -C "$BARE" commit -q -m 'fix(omega): first unreleased thing (#201)' && git -C "$BARE" rev-parse --short=7 HEAD)"
run_guard "__absent__" "$BARE"
[ "$RC" -eq 1 ] || fail "no-tag repo accepted: $OUT"
grep -qF "no previous release tag" <<< "$OUT" || fail "no-tag note missing: $OUT"
grep -qF "$SHA7 [MISSING]" <<< "$OUT" || fail "no-tag repo missed the commit: $OUT"
printf '* omega thing ([%s](https://example.invalid))\n' "$SHA7" > "$NOTES"
run_guard "$NOTES" "$BARE"
[ "$RC" -eq 0 ] || fail "no-tag repo with covered commit rejected: $OUT"
git -C "$BARE" tag 1.0.0
run_guard "$NOTES" "$BARE"
[ "$RC" -eq 0 ] || fail "empty range rejected: $OUT"
grep -qF "clean: 0 commit(s)" <<< "$OUT" || fail "empty range summary missing: $OUT"
echo "OK: no-tag fallback works, empty range passes"

# 9. Workflow wiring and least privilege.
[ -f "$GUARD_YML" ] || fail "guard workflow missing at $GUARD_YML"
grep -qF 'python3 .github/scripts/verify-release-notes.py --repo .' "$GUARD_YML" \
  || fail "guard workflow does not run the shared script"
grep -qF 'cron:' "$GUARD_YML" || fail "guard workflow has no schedule"
grep -qF 'branches: ["main"]' "$GUARD_YML" || fail "guard workflow does not run on pushes to main"
grep -qF 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' "$GUARD_YML" \
  || fail "guard workflow does not pin actions/checkout"
grep -qF 'fetch-depth: 0' "$GUARD_YML" \
  || fail "guard workflow does not fetch full history for git describe"
grep -qF 'issues: read' "$GUARD_YML" \
  || fail "guard workflow cannot query PR labels: issues: read missing"
grep -qF 'cancel-in-progress: true' "$GUARD_YML" \
  || fail "guard workflow has no concurrency cancellation"
if grep -qE 'contents: write|pull-requests: write|issues: write' "$GUARD_YML"; then
  fail "guard workflow asks for write permissions; it is a read-only check"
fi
# The Release Please delay must run before the checkout: the guard reads
# the notes branch only from the checkout snapshot, so a wait placed
# after it would always read stale notes.
wait_line="$(grep -n 'name: Wait for Release Please' "$GUARD_YML" | cut -d: -f1)"
checkout_line="$(grep -n 'uses: actions/checkout' "$GUARD_YML" | head -1 | cut -d: -f1)"
[ -n "$wait_line" ] && [ -n "$checkout_line" ] && [ "$wait_line" -lt "$checkout_line" ] \
  || fail "the Release Please delay must run before the checkout step"
grep -qF 'bash tests/test_release_notes_guard.sh' "$TEST_YML" \
  || fail "test.yml no longer runs tests/test_release_notes_guard.sh"
echo "OK: guard workflow wired, read-only, and gated in test.yml"

echo "All release notes guard checks passed"
