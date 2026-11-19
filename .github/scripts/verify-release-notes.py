#!/usr/bin/env python3
"""Guard the open release notes against silent commit drops (#501).

release-please 17.6.0 (pinned by release-please-action v5) drops any
commit whose message contains a column-0 line with a nested
parenthesis: @conventional-commits/parser throws and
parseConventionalCommits swallows the error. Issue #497 lost d47adc5
that way and nothing failed.

This guard parses only the commit header -- the one line a body
poison cannot hide -- and fails when a commit that should be listed
is absent from CHANGELOG.md on the open release branch
(release-please--branches--main).

A commit is a candidate when its header parses as a conventional
commit and its type maps to a visible (not hidden) section in
release-please-config.json. A candidate is covered when its short SHA
or its "(#NNN)" pull-request reference appears in the open release
section of the notes -- the first "## " section, where Release Please
writes the pending release. A number or SHA mentioned only in an
older release entry cannot cover a dropped commit.

A MISSING candidate with a (#NNN) reference is also checked for a
PR-body override-marker hijack (#505): preprocessCommitMessage
(src/commit.ts) replaces the commit message with the first
BEGIN_COMMIT_OVERRIDE ... END_COMMIT_OVERRIDE extraction of the merged
PR body whenever it is non-empty, so a body that merely names the
begin marker in prose makes release-please parse that prose and drop
the whole commit. When the extraction is not exactly one clean
conventional-commit header, the commit is reported as hijacked rather
than merely missing.

Nothing is skipped silently: every commit in the range is reported as
covered, missing, or excluded, with the reason.

Usage:
  python3 verify-release-notes.py [--repo PATH] [--config PATH]
      [--to REF] [--changelog-ref REF] [--changelog-path PATH]
      [--changelog-file PATH]

Exit codes: 0 all candidates covered or nothing to check, 1 one or
more commits missing from the notes (including when the notes branch
itself is absent), 2 operational error (bad config, not a repository).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

FIELD = "\x1f"
RECORD = "\x1e"
# Same header grammar release-please uses: type(scope)!: description.
HEADER_RE = re.compile(r"^(?P<type>[A-Za-z][A-Za-z0-9._-]*)(\([^()]*\))?!?:\s")
PR_REF_RE = re.compile(r"\(#(\d+)\)")
SKIP_LABEL_RE = re.compile(r"^skip[\s-]changelog$", re.IGNORECASE)
BEGIN_OVERRIDE_MARKER = "BEGIN_COMMIT_OVERRIDE"
END_OVERRIDE_MARKER = "END_COMMIT_OVERRIDE"


def die(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(2)


def git(repo: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args], cwd=repo, capture_output=True, text=True)
    if check and result.returncode != 0:
        die(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def visible_types(config_path: Path):
    """Return (visible, hidden) conventional types from changelog-sections."""
    try:
        sections = json.loads(config_path.read_text())["changelog-sections"]
        visible, hidden = set(), set()
        for section in sections:
            (hidden if section.get("hidden") else visible).add(
                section["type"].lower())
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        die(f"cannot read changelog-sections from {config_path}: {exc}")
    return visible, hidden


def last_tag(repo: Path, to_ref: str) -> str:
    return git(repo, "describe", "--tags", "--abbrev=0", to_ref, check=False)


def list_commits(repo: Path, from_ref: str, to_ref: str):
    rng = f"{from_ref}..{to_ref}" if from_ref else to_ref
    raw = git(repo, "log", "--no-merges", "--reverse",
              f"--format=%H{FIELD}%s{RECORD}", rng)
    commits = []
    for record in raw.split(RECORD):
        record = record.strip("\n")
        if record:
            sha, subject = record.split(FIELD, 1)
            commits.append({"sha": sha, "short": sha[:7], "subject": subject})
    merges = [line.strip() for line in
              git(repo, "log", "--merges", "--format=%h", rng).splitlines()
              if line.strip()]
    return rng, commits, merges


def read_changelog(repo: Path, ref: str, path: str, file_override: str):
    """Return the notes text, or None when the open release branch has none."""
    if file_override:
        try:
            return Path(file_override).read_text()
        except OSError:
            return None
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"], cwd=repo,
        capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def open_release_section(changelog: str) -> str:
    """Return the pending-release section: the first "## " block.

    Release Please lists the open release as the first "## " section
    of CHANGELOG.md. Scanning only that block keeps a "(#NNN)"
    reference or SHA that appears solely in an older release entry,
    or in unrelated text there, from falsely covering a dropped
    commit. A notes file without "## " headings is scanned whole.
    """
    lines = changelog.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if line.startswith("## ")), None)
    if start is None:
        return changelog
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[start:end])


def github_slug(repo: Path):
    slug = os.environ.get("GITHUB_REPOSITORY", "")
    if slug.count("/") == 1:
        return slug
    url = git(repo, "remote", "get-url", "origin", check=False)
    match = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url)
    return match.group(1) if match else None


def label_check_available(repo: Path):
    """Return the repo slug when PR labels can be queried, else None."""
    if not shutil.which("gh"):
        return None
    if not (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")):
        return None
    return github_slug(repo)


def pr_has_skip_changelog_label(slug: str, number: str):
    """Return True/False, or None with a note when the query failed."""
    result = subprocess.run(
        ["gh", "api", f"repos/{slug}/issues/{number}/labels"],
        capture_output=True, text=True)
    if result.returncode != 0:
        return None, (f"label query for PR #{number} failed: "
                      f"{result.stderr.strip().splitlines()[0] if result.stderr.strip() else 'unknown error'}")
    try:
        labels = [item.get("name", "") for item in json.loads(result.stdout)]
    except ValueError:
        return None, f"label query for PR #{number} returned unreadable JSON"
    return any(SKIP_LABEL_RE.fullmatch(name) for name in labels), None


def pr_override_marker_hijack(slug: str, number: str):
    """Return (hijacked, message) for the merged PR body of a candidate.

    Mirrors release-please preprocessCommitMessage (src/commit.ts):
    the text between the first BEGIN_COMMIT_OVERRIDE and the first
    END_COMMIT_OVERRIDE after it replaces the commit message whenever
    it is non-empty (#505). A hijack is an extraction that is not
    exactly one clean conventional-commit header: release-please hands
    that text to the parser, the parser throws, and the whole commit
    is dropped. hijacked is None only when the body could not be read;
    message is then a note and never implies a silent pass.
    """
    result = subprocess.run(
        ["gh", "api", f"repos/{slug}/pulls/{number}"],
        capture_output=True, text=True)
    if result.returncode != 0:
        return None, (f"PR body query for PR #{number} failed: "
                      f"{result.stderr.strip().splitlines()[0] if result.stderr.strip() else 'unknown error'}")
    try:
        body = json.loads(result.stdout).get("body") or ""
    except (ValueError, AttributeError):
        return None, f"PR body query for PR #{number} returned unreadable JSON"
    begins = body.count(BEGIN_OVERRIDE_MARKER)
    if begins == 0:
        return False, None
    ends = body.count(END_OVERRIDE_MARKER)
    # Unbounded split, indexed like release-please: with several begin
    # markers the window is the text between the first two begins.
    extraction = (body.split(BEGIN_OVERRIDE_MARKER)[1]
                  .split(END_OVERRIDE_MARKER)[0].strip())
    if not extraction:
        # An empty block is a no-op: release-please keeps the commit message.
        return False, None
    lines = extraction.splitlines()
    if len(lines) == 1 and HEADER_RE.match(lines[0]):
        return False, None
    return True, (f"PR body override-marker hijack "
                  f"({begins} begin marker(s), {ends} end marker(s); "
                  f"the first extraction is not one clean "
                  f"conventional-commit header)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default=".", help="git repository path")
    parser.add_argument("--config", default=None,
                        help="release-please config (default <repo>/release-please-config.json)")
    parser.add_argument("--to", default="HEAD", help="range end (default HEAD)")
    parser.add_argument("--changelog-ref",
                        default="origin/release-please--branches--main",
                        help="open release branch holding the notes")
    parser.add_argument("--changelog-path", default="CHANGELOG.md")
    parser.add_argument("--changelog-file", default=None,
                        help="read the notes from this file instead of --changelog-ref (tests)")
    args = parser.parse_args()

    repo = Path(args.repo)
    if git(repo, "rev-parse", "--git-dir", check=False) == "":
        die(f"not a git repository: {repo}")
    config = Path(args.config) if args.config else repo / "release-please-config.json"
    visible, hidden = visible_types(config)

    tag = last_tag(repo, args.to)
    rng, commits, merges = list_commits(repo, tag, args.to)
    scope = f"{tag}..{args.to}" if tag else f"full history to {args.to}"
    if not tag:
        print("note: no previous release tag found; guarding all history")

    notes_source = args.changelog_file or f"{args.changelog_ref}:{args.changelog_path}"
    changelog = read_changelog(repo, args.changelog_ref,
                               args.changelog_path, args.changelog_file)
    scan_text = open_release_section(changelog) if changelog is not None else None
    slug = label_check_available(repo)
    if changelog is None:
        notes = [f"no notes found at {notes_source}"]
    else:
        notes = []

    rows = []
    missing = []
    for commit in commits:
        subject = commit["subject"]
        match = HEADER_RE.match(subject)
        if match is None:
            rows.append((commit, "skipped: header is not a conventional commit"))
            continue
        ctype = match.group("type").lower()
        if ctype in hidden:
            rows.append((commit, f"skipped: type '{ctype}' is a hidden changelog section"))
            continue
        if ctype not in visible:
            rows.append((commit, f"skipped: type '{ctype}' has no changelog section"))
            continue
        pr_ref = (PR_REF_RE.findall(subject) or [None])[-1]
        if scan_text is not None:
            # Coverage is literal "appears in the open release
            # section" (#501): the short SHA as a substring, or the
            # PR reference with a digit boundary, but only inside the
            # first "## " section. A stale mention in an older
            # release entry, or an unrelated "closes #NNN" there,
            # must not cover a dropped commit. A false SHA match
            # would need another commit sharing this 7-hex prefix,
            # so substring is enough.
            covered_by = None
            if commit["short"] in scan_text:
                covered_by = f"sha {commit['short']}"
            elif pr_ref and re.search(rf"#{pr_ref}(?!\d)", scan_text):
                covered_by = f"PR #{pr_ref} reference"
            if covered_by:
                rows.append((commit, f"covered ({covered_by})"))
                continue
        if pr_ref and slug:
            has_label, label_note = pr_has_skip_changelog_label(slug, pr_ref)
            if label_note:
                notes.append(label_note)
            if has_label:
                rows.append((commit,
                             f"excluded: PR #{pr_ref} carries the skip-changelog label"))
                continue
        if pr_ref:
            reason = ""
            if slug:
                hijacked, hijack_note = pr_override_marker_hijack(slug, pr_ref)
                if hijacked is None:
                    notes.append(hijack_note)
                elif hijacked:
                    reason = f" ({hijack_note})"
            rows.append((commit, f"MISSING{reason}"))
        else:
            rows.append((commit, "MISSING (no (#NNN) PR reference; "
                                 "skip-changelog label cannot be checked)"))
        missing.append(commit)

    for commit, status in rows:
        print(f"{commit['short']} [{status}] {commit['subject']}")
    for note in notes:
        print(f"note: {note}")
    if merges:
        print(f"note: {len(merges)} merge commit(s) excluded from the "
              f"range: {', '.join(merges)}")
    if slug is None and any(s.startswith("MISSING") for _, s in rows):
        print("note: PR label check unavailable (need gh + token + repo slug); "
              "skip-changelog exclusions and PR-body override-marker "
              "hijacks could not be verified")

    if missing:
        listing = ", ".join(commit["short"] for commit in missing)
        print(f"::error::{len(missing)} visible-type commit(s) since "
              f"{tag or '(no tag)'} missing from {notes_source}: {listing}",
              file=sys.stderr)
        print(f"::error::release-please silently drops commits that break "
              f"the conventional-commit parser (issue #497); recover the "
              f"entry with a BEGIN_COMMIT_OVERRIDE block on the commit's "
              f"merged PR body, per the release-please README", file=sys.stderr)
        if any("override-marker hijack" in status for _, status in rows):
            print(f"::error::at least one drop carries the PR-body "
                  f"override-marker hijack shape (issue #505): rewrite the "
                  f"marker mention in the PR body in words, or repair the "
                  f"block so it holds exactly one clean conventional-commit "
                  f"header", file=sys.stderr)
        write_summary(scope, notes_source, rows, notes, merges)
        return 1

    summary = (f"clean: {len(commits)} commit(s) in {scope} checked against "
               f"{notes_source}")
    if changelog is None:
        summary += " (no open release notes found; no visible-type commits to cover)"
    print(summary)
    write_summary(scope, notes_source, rows, notes, merges, ok_summary=summary)
    return 0


def write_summary(scope, notes_source, rows, notes, merges, ok_summary=None):
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if not target:
        return
    lines = ["## Release Notes Guard (#501)", "",
             f"- Range: `{scope}`",
             f"- Notes: `{notes_source}`", ""]
    if ok_summary:
        lines.insert(2, f"**{ok_summary}**")
    if not rows:
        lines.append("No commits in range.")
    for commit, status in rows:
        subject = commit["subject"].replace("|", "\\|")
        marker = "x" if status.startswith("MISSING") else " "
        lines.append(f"- [{marker}] `{commit['short']}` {status} -- {subject}")
    for note in notes:
        lines.append(f"- note: {note}")
    if merges:
        lines.append(f"- {len(merges)} merge commit(s) excluded from the "
                     f"range: {', '.join(merges)}")
    with open(target, "a") as handle:
        handle.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
