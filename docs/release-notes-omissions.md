# Missing Release Notes Entries

Some merged commit can disappear from the release notes with no failed check. The pending 0.1.1 changelog dropped `d47adc5` (`fix(goals): count only completed builds in any_build goal progress (issue #478) (#481)`, PR #481), while all ten other fix commits since 0.1.0 appeared. Issue #497 tracked the omission. This page records the root cause and the recovery procedure.

## Root Cause

`.github/workflows/release-please.yaml` runs `googleapis/release-please-action`, pinned at `v5.0.0`. That release bundles release-please 17.6.0.

release-please parses each commit message with `@conventional-commits/parser`. The parser throws on a body line that starts at column 0 and contains a second `(` before the first `)`. The squash-merge message of `d47adc5` contains such a line:

```text
bool(build.get("complete")) — bool(null) raises "Nonexistent 'bool'
constructor" in Godot 4.7.1 when the key is missing.
```

The parser fails with `unexpected token '(' at 9:15, valid tokens [)]`. release-please catches the error and writes only a debug log line (`commit could not be parsed: <sha> <header>`). It then drops the whole commit from the generated notes. The release PR updates on schedule with the entry missing, and nothing fails.

The same line parses when it starts with one space. Only the column-0 start plus the nested parenthesis matters. The `#349` reference, the em dash, and the `Co-authored-by:` footer do not affect parsing.

Upstream fixed this in googleapis/release-please#2936 (`sanitizeBodyScopes`, merged 2026-10-16). No published release up to release-please 17.11.2 contains the fix (checked 2026-11-18). Update the action pin when a release that contains the fix exists. After that bump, messages like the one above parse again.

The fallback Manual Release workflow (`.github/workflows/manual-release.yml`) runs `gh release create --generate-notes`. GitHub builds those notes from the merged pull requests in the tag range and never runs the parser above, so that path drops no entries. It also writes no `CHANGELOG.md` section, so the merged release-please PR stays the source of the repository changelog.

## Recovered Entry for 0.1.1

release-please replaces a commit message when the pull request body of that commit contains a `BEGIN_COMMIT_OVERRIDE` block. See `preprocessCommitMessage` in `src/commit.ts` of release-please. The body of PR #481 now carries this block:

```text
BEGIN_COMMIT_OVERRIDE
fix(goals): count only completed builds in any_build goal progress (issue #478) (#481)
END_COMMIT_OVERRIDE
```

The override header parses as type `fix`, scope `goals`. release-please regenerates the open release PR notes from scratch on every run, so the next run adds the entry back to the 0.1.1 section. Trigger the next run in one of two ways:

1. Wait for the next push to `main`. The Release Please workflow runs on every push to `main`.
2. Re-run the newest Release Please workflow run from the Actions tab.

After the run, make sure that the `Bug Fixes` section of 0.1.1 in the `CHANGELOG.md` on PR #461 lists the `**goals:**` entry.

Do not edit `CHANGELOG.md` on the `release-please--branches--main` branch. Each run rebuilds that file from `main` and force-pushes the branch, so an edit there disappears on the next run.

## Procedure When an Entry Is Missing

1. Make sure the commit is in the release range:

   ```bash
   git log --oneline <last-tag>..main --grep "^fix"
   ```

2. Make sure the pull request of the commit has no `skip-changelog` label.
3. Print the merged commit message:

   ```bash
   git log -1 --format=%B <sha>
   ```

4. Look for a body line that starts at column 0 and contains a second `(` before the first `)`. A line such as `bool(build.get("complete")) ...` is one example.
5. If you find such a line, add a `BEGIN_COMMIT_OVERRIDE` block to the pull request body. Put one clean conventional-commit header between the markers.
6. Trigger the next release-please run as described above, then make sure the entry appears in the `CHANGELOG.md` of the release pull request.

## Commit Message Guidance

Do not start a body line at column 0 with `name(` when a second `(` appears before the closing `)`. Rewrite the sentence or indent the line. This guidance applies while the action pin bundles a release-please version older than the #2936 fix.
