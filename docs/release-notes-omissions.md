# Missing Release Notes Entries

A merged commit can disappear from the release notes with no failed check. Two mechanisms caused this during the 0.1.1 cycle. `d47adc5` was dropped by a parser bug (issue #497). `b844831` was dropped when the recovery mechanism itself was hijacked by a pull-request body (issue #505). This page records both root causes and the recovery procedure.

## Root Cause 1: Parser Throw on a Poison Body Line

`.github/workflows/release-please.yaml` runs `googleapis/release-please-action`, SHA-pinned to `45996ed` (`v5.0.0`). That release bundles release-please 17.6.0.

release-please parses each commit message with `@conventional-commits/parser`. The parser throws on a body line that starts at column 0 with `name(...)`-style text containing a nested or unclosed `(`. The squash-merge message of `d47adc5` contains such a line:

```text
bool(build.get("complete")) — bool(null) raises "Nonexistent 'bool'
constructor" in Godot 4.7.1 when the key is missing.
```

The parser fails with `unexpected token '(' at 9:15, valid tokens [)]`. release-please catches the error and writes only a debug log line (`commit could not be parsed: <sha> <header>`). It then drops the whole commit from the generated notes. The release PR updates on schedule with the entry missing, and nothing fails.

The same line parses when it starts with one space. Only the column-0 start plus the parenthesis shape matters. The `#349` reference, the em dash, and the `Co-authored-by:` footer do not affect parsing.

Upstream fixed this in googleapis/release-please#2936 (`sanitizeBodyScopes`, merged 2026-10-16). No published release up to release-please 17.11.2 contains the fix (checked 2026-11-18). Update the action pin when a release that contains the fix exists. After that bump, messages like the one above parse again.

The fallback Manual Release workflow (`.github/workflows/manual-release.yml`) runs `gh release create --generate-notes`. GitHub builds those notes from the merged pull requests in the tag range and never runs the parser above, so that path drops no entries. It also writes no `CHANGELOG.md` section, so the merged release-please PR stays the source of the repository changelog.

## Root Cause 2: A PR Body That Hijacks the Override

The recovery block described below introduces its own failure mode. `preprocessCommitMessage` in `src/commit.ts` of release-please takes the text after the first `BEGIN_COMMIT_OVERRIDE` in the pull-request body, up to the first `END_COMMIT_OVERRIDE`, and uses that text as the commit message whenever it is not empty. It does not check that the markers are paired or intentional.

So a prose mention of the begin marker in a PR body — even inside backticks — hijacks the extraction. The captured text is ordinary prose, not a conventional-commit header, so the parser throws, the error is swallowed the same way as root cause 1, and the commit is dropped. The commit message itself can parse cleanly and the commit is dropped anyway.

`b844831` (PR #500, the pull request that added this page) carried one begin-marker mention inline in its PR body prose, with no end marker anywhere in the body. Its commit message parses as type `docs`; the hijacked extraction does not parse. The entry went missing from the open release notes, and the Release Notes Guard failed on `main` (issue #505). PR #502's body has the same shape with three unpaired mentions; no entry was lost there only because its type `ci` is a hidden changelog section.

Verified against release-please 17.6.0's own extractor and parser: the byte-exact `b844831` message parses (type `docs`, scope `release`), and the first-occurrence extraction from PR #500's old body fails to parse.

## Recovery Mechanism: Override Blocks

release-please replaces a commit message when the pull request body of that commit contains a `BEGIN_COMMIT_OVERRIDE` block. See `preprocessCommitMessage` in `src/commit.ts` of release-please. Between the markers goes exactly one clean conventional-commit header, for example:

```text
BEGIN_COMMIT_OVERRIDE
fix(goals): count only completed builds in any_build goal progress (issue #478) (#481)
END_COMMIT_OVERRIDE
```

release-please regenerates the open release PR notes from scratch on every run, so the next run re-adds the entry. Trigger the next run in one of two ways:

1. Wait for the next push to `main`. The Release Please workflow runs on every push to `main`.
2. Re-run the newest Release Please workflow run from the Actions tab.

Do not edit `CHANGELOG.md` on the `release-please--branches--main` branch. Each run rebuilds that file from `main` and force-pushes the branch, so an edit there disappears on the next run.

## Recovered Entries for 0.1.1

**`d47adc5` (root cause 1).** The body of PR #481 carries the override block quoted above. Its header parses as type `fix`, scope `goals`, and the entry is back in the `Bug Fixes` section of the open 0.1.1 notes.

**`b844831` (root cause 2).** The body of PR #500 was edited (platform edit, outside any diff): the inline marker mention was rewritten in words ("an override block"), and the paired block below was appended, so it is the only marker occurrence in that body:

```text
BEGIN_COMMIT_OVERRIDE
docs(release): document release-notes omission root cause (issue #497) (#500)
END_COMMIT_OVERRIDE
```

The extraction now yields the clean `docs` header. The next Release Please run re-adds the entry to the `Documentation` section of 0.1.1.

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

4. Look for a body line that starts at column 0 with `name(...)`-style text containing a nested or unclosed `(`. A line such as `bool(build.get("complete")) ...` is one example.
5. Print the pull-request body and count the override markers:

   ```bash
   gh api repos/<owner>/<repo>/pulls/<n> --jq .body | grep -o "BEGIN_COMMIT_OVERRIDE" | wc -l
   gh api repos/<owner>/<repo>/pulls/<n> --jq .body | grep -o "END_COMMIT_OVERRIDE" | wc -l
   ```

   The intended block must be the first occurrence of the begin marker in the body: the extractor reads from that first marker to the first end marker and uses the result instead of the commit message whenever it is not empty. An earlier begin marker, such as one in prose, outranks the block and drops the commit even when its message parses. Mentions after the paired block are harmless, but keeping exactly one pair is the safe habit.
6. Fix the cause you found. For a parser poison line, the pull request needs an override block with one clean conventional-commit header between the markers. For a hijacked body, rewrite every other mention of the marker in words first, so the intended block's opener is the first occurrence in the body.
7. Trigger the next release-please run as described above, then make sure the entry appears in the `CHANGELOG.md` of the release pull request.

## Commit Message and PR Body Guidance

Do not start a body line at column 0 with `name(` when a second `(` appears before the closing `)`. Rewrite the sentence or indent the line. This applies while the action pin bundles a release-please version older than the #2936 fix.

Do not write the marker strings in a pull-request body except as one intentional paired block. Referring to the mechanism in prose is safe only when the literal marker text is avoided, for example "commit-override block". This includes handoff templates and agent-authored bodies. This rule is not tied to the #2936 pin: `preprocessCommitMessage` stays marker-driven in current release-please, so a hijacked body keeps dropping its commit until upstream changes the extraction.
