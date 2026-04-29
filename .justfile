#!/usr/bin/env -S just --justfile

set quiet := true
set shell := ['bash', '-eu', '-o', 'pipefail', '-c']

godot := env_var_or_default('GODOT_BIN', if os() == 'macos' { justfile_dir() + '/.tools/macos/Godot.app/Contents/MacOS/Godot' } else { justfile_dir() + '/.tools/Godot_v4.2.2-stable_linux.x86_64' })

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

[doc('Run all local validation checks')]
validate: test test-layout

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
