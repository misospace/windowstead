#!/usr/bin/env bash
# prune-stale-branches.sh — Clean up merged and stale generated branches.
# Run periodically (e.g., after release or CI) to keep the local repo tidy.
#
# Safety rules:
#   - NEVER delete branches matching `saffron/*` (active agent work).
#   - NEVER delete `main` or `renovate/*`.
#   - Only delete local branches with no remote counterpart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== Pruning stale branches in $(basename "$SCRIPT_DIR") ==="

# 1. Delete merged branches (except saffron active work)
echo ""
echo "--- Merged branches ---"
git branch --merged main \
  | sed 's/^[* ]*//' \
  | grep -v '^main$' \
  | grep -v '^saffron/' \
  | while read -r b; do
      echo "  DELETE (merged): $b"
      git branch -d "$b" 2>/dev/null || true
    done

# 2. Delete unmerged local-only branches (fix/*, pr-*)
echo ""
echo "--- Stale local-only branches ---"
git branch \
  | sed 's/^[* ]*//' \
  | grep -E '^(fix|pr-)' \
  | while read -r b; do
      has_remote=$(git ls-remote --heads origin "$b" 2>/dev/null || true)
      if [ -z "$has_remote" ]; then
        echo "  DELETE (stale): $b"
        git branch -D "$b" 2>/dev/null || true
      else
        echo "  KEEP (has remote): $b"
      fi
    done

echo ""
echo "--- Remaining branches ---"
git branch | sed 's/^[* ]*/  /'
echo ""
echo "Done."
