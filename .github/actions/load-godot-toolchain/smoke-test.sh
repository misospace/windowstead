#!/usr/bin/env bash
# Shared headless smoke test and failure gate for every platform this
# composite action runs on. The launch and the gate are defined here only
# once so platform steps cannot drift apart. The timeout is Python-side
# because macOS runners lack the coreutils timeout command.
set -uo pipefail

GODOT_BIN="${1:?usage: smoke-test.sh <godot-binary>}"
SMOKE_LOG="smoke.log"
SMOKE_TIMEOUT_SECONDS=15

export SMOKE_TIMEOUT_SECONDS
python3 - "$GODOT_BIN" "$SMOKE_LOG" <<'PY'
import os
import subprocess
import sys

godot = sys.argv[1]
log_path = sys.argv[2]
timeout_seconds = int(os.environ["SMOKE_TIMEOUT_SECONDS"])
with open(log_path, "w") as log:
    try:
        result = subprocess.run(
            [godot, "--headless", "--path", ".", "--fixed-fps", "60", "--quit-after", "300"],
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired:
        print(f"Smoke test timed out after {timeout_seconds} seconds", file=sys.stderr)
        sys.exit(124)
sys.exit(result.returncode)
PY
SMOKE_EXIT=$?

if [ ! -f "$SMOKE_LOG" ]; then
  echo "::error::Smoke test produced no smoke.log" >&2
  exit 1
fi
cat "$SMOKE_LOG"
if [ "$SMOKE_EXIT" -ne 0 ]; then
  echo "::error::Smoke test exited with code $SMOKE_EXIT" >&2
  exit "$SMOKE_EXIT"
fi
if grep -E "SCRIPT ERROR|ERROR:" "$SMOKE_LOG"; then
  echo "::error::Smoke test logged an engine/script error" >&2
  exit 1
fi
