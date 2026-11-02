#!/usr/bin/env -S just --justfile

set quiet := true
set shell := ['bash', '-eu', '-o', 'pipefail', '-c']

godot := if env_var_or_default('GODOT_BIN', '') != '' { env_var('GODOT_BIN') } else if os() == 'macos' { justfile_dir() + '/.tools/macos/Godot.app/Contents/MacOS/Godot' } else { `
version=''
status=''
if [ -f godot-toolchain.json ]; then
  cfg=$(tr -d '[:space:]' < godot-toolchain.json)
  version=$(printf '%s' "$cfg" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  status=$(printf '%s' "$cfg" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
fi
pinned=".tools/Godot_v${version}-${status}_linux.x86_64"
if [ -f "$pinned" ] && [ -x "$pinned" ]; then printf '%s' "$PWD/$pinned"; exit 0; fi
if [ -f "$pinned" ]; then
  printf 'justfile: %s matches the pin but is not executable. Run: chmod +x %s\n' "$PWD/$pinned" "$PWD/$pinned" >&2
  exit 1
fi
found=''
if [ -d .tools ]; then
  found=$(find .tools -maxdepth 1 -type f -name 'Godot_v*linux.x86_64' | sort)
fi
n=0
if [ -n "$found" ]; then n=$(printf '%s\n' "$found" | wc -l); fi
if [ "$n" -eq 1 ]; then printf '%s' "$PWD/$found"; exit 0; fi
if [ "$n" -gt 1 ]; then
  printf 'justfile: no Godot binary matches the pinned %s-%s in %s, and %s candidates are present:\n%s\n' "${version:-unknown}" "${status:-unknown}" "$PWD/.tools" "$n" "$found" >&2
  printf 'remove the stale binaries or set GODOT_BIN.\n' >&2
  exit 1
fi
printf 'justfile: no Godot binary found in %s (pinned: Godot_v%s-%s_linux.x86_64).\n' "$PWD/.tools" "${version:-unknown}" "${status:-unknown}" >&2
printf 'download the linux file listed in godot-toolchain.json into .tools/, or set GODOT_BIN.\n' >&2
exit 1
` }

[private]
default:
    just --list

[doc('Open the project in Godot')]
run:
    '{{ godot }}' --path '{{ justfile_dir() }}'

[doc('Run the main headless test suite')]
test:
    '{{ godot }}' --headless --path '{{ justfile_dir() }}' --script res://tests/test_runner.gd

[doc('Run layout regression tests')]
test-layout:
    '{{ godot }}' --headless --path '{{ justfile_dir() }}' --script res://tests/test_layout_math.gd

[doc('Run E2E gameplay flow tests')]
test-e2e:
    '{{ godot }}' --headless --path '{{ justfile_dir() }}' --script res://tests/test_e2e.gd

[doc('Run every test suite in tests/ (same matrix as CI)')]
test-all:
    FAILED=0; \
    for suite in '{{ justfile_dir() }}'/tests/test_*.gd; do \
      name=$(basename "$suite" .gd); \
      if [ "$name" = "test_case" ]; then continue; fi; \
      echo "== $name"; \
      log=$(mktemp); \
      '{{ godot }}' --headless --path '{{ justfile_dir() }}' --script "res://tests/$name.gd" 2>&1 | tee "$log"; \
      if [ "${PIPESTATUS[0]}" -ne 0 ] || grep -q "SCRIPT ERROR" "$log"; then FAILED=1; fi; \
      rm -f "$log"; \
    done; \
    exit $FAILED

[doc('Run all local validation checks (canonical matrix)')]
validate: test-all

[doc('Export a local macOS app bundle')]
build-macos:
    mkdir -p '{{ justfile_dir() }}/build/release/macos'
    '{{ godot }}' --headless --path '{{ justfile_dir() }}' --export-release 'macOS' '{{ justfile_dir() }}/build/release/macos/windowstead.app'

[doc('Export a local Linux binary')]
build-linux:
    mkdir -p '{{ justfile_dir() }}/build/release/linux'
    '{{ godot }}' --headless --path '{{ justfile_dir() }}' --export-release 'Linux/X11' '{{ justfile_dir() }}/build/release/linux/windowstead.x86_64'

[doc('Export a local Windows binary')]
build-windows:
    mkdir -p '{{ justfile_dir() }}/build/release/windows'
    '{{ godot }}' --headless --path '{{ justfile_dir() }}' --export-release 'Windows Desktop' '{{ justfile_dir() }}/build/release/windows/windowstead.exe'

[doc('Validate and export for the current local platform')]
local-build: validate
    if [[ "$(uname -s)" == "Darwin" ]]; then \
      just --justfile '{{ justfile_dir() }}/.justfile' build-macos; \
    else \
      just --justfile '{{ justfile_dir() }}/.justfile' build-linux; \
    fi
