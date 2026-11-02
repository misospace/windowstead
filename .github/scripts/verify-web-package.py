#!/usr/bin/env python3
"""Verify a packaged Godot Web export (#449, #458, #467).

Single source of truth for the Web packaging check, called from both
release.yml (against the staged release zip) and test.yml (against the
PR export directory), so the two workflows cannot drift apart.

Checks:
  1. The mandatory entries windowstead.html/.pck/.wasm/.js are present
     and non-empty.
  2. Every local asset the exported HTML references through src/href
     (splash image, favicon, Apple touch icon, ...) is packaged next to
     the HTML. Issue #449 shipped because the release archive whitelisted
     only four files while the HTML referenced more generated assets.

Usage:
  python3 verify-web-package.py <path>

<path> is either a zip archive (the staged release package) or a
directory (a fresh export directory). External, protocol-relative,
data:, and root-absolute references are ignored.
"""
import re
import sys
import zipfile
from pathlib import Path

HTML_NAME = "windowstead.html"
MANDATORY = ["windowstead.html", "windowstead.pck", "windowstead.wasm", "windowstead.js"]

# src/href values that are not sibling assets: external URLs,
# protocol-relative refs, data: URIs, root-absolute paths.
def is_external(ref: str) -> bool:
    return not ref or ref.startswith("//") or ":" in ref.split("/", 1)[0] or ref.startswith("/")


def collect_entries(target: Path):
    """Return (entries, size_of, read_bytes) for a zip file or a directory."""
    if target.is_dir():
        entries = {
            path.relative_to(target).as_posix()
            for path in target.rglob("*")
            if path.is_file()
        }
        return entries, lambda name: (target / name).stat().st_size, lambda name: (target / name).read_bytes()
    if target.is_file():
        archive = zipfile.ZipFile(target)
        entries = {name for name in archive.namelist() if not name.endswith("/")}
        return entries, lambda name: archive.getinfo(name).file_size, archive.read
    return None


def main() -> int:
    if len(sys.argv) != 2:
        print(f"::error::usage: {Path(sys.argv[0]).name} <zip-or-export-dir>", file=sys.stderr)
        return 2
    target = Path(sys.argv[1])
    collected = collect_entries(target)
    if collected is None:
        print(f"::error::Web package target not found: {target}", file=sys.stderr)
        return 1
    entries, size_of, read_bytes = collected

    failures = []
    refs = set()

    for name in MANDATORY:
        if name not in entries:
            failures.append(f"mandatory archive entry missing: {name}")
        elif size_of(name) == 0:
            failures.append(f"mandatory archive entry empty: {name}")

    if HTML_NAME in entries:
        html = read_bytes(HTML_NAME).decode("utf-8", errors="replace")
        html = re.sub(r"<!--.*?-->", "", html, flags=re.DOTALL)
        for value in re.findall(r"""(?:src|href)\s*=\s*["']([^"']+)["']""", html, flags=re.IGNORECASE):
            ref = value.split("#", 1)[0].split("?", 1)[0].strip()
            if is_external(ref):
                continue
            refs.add(ref)

    for ref in sorted(refs):
        if ref not in entries:
            failures.append(f"HTML references local asset missing from archive: {ref}")

    if failures:
        for failure in failures:
            print(f"::error::{failure}")
        return 1
    print(f"Web package verified: mandatory entries present, {len(refs)} local HTML asset references all packaged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
