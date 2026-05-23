# Branch Cleanup Expectations

## Overview

This document defines the branch hygiene policy for the windowstead repository to reduce noise from merged and stale generated branches.

## Branch Categories

| Category | Pattern | Action |
|----------|---------|--------|
| Main branch | `main` | Never delete |
| Active agent work | `saffron/*` | Never delete (tracked by Dispatch) |
| Renovate branches | `renovate/*` (remote-only) | Never delete |
| Merged fix branches | `fix/*`, `pr-*` | Delete after merge confirmed |
| Stale generated branches | `fix/*`, `pr-*` (no remote) | Delete if unmerged and no remote counterpart |

## Cleanup Procedure

Run the automated cleanup script:

```bash
./scripts/prune-stale-branches.sh
```

This script:
1. Deletes merged local branches (except `saffron/*` active work).
2. Deletes unmerged local-only branches matching `fix/*` or `pr-*` (no remote counterpart).
3. Reports remaining branches.

## When to Run

- After each release workflow dispatch (#121).
- Periodically (weekly) as part of release hygiene.
- Before starting large batches of automated fix work.

## Acceptance Criteria (Issue #127)

- [x] Identified merged/stale generated branches.
- [x] Deleted 43 safe-to-remove local branches (35 `fix/*` + 8 `pr-*`).
- [x] Created `scripts/prune-stale-branches.sh` for future automated cleanup.
- [x] Documented branch cleanup expectations here.

## Future Automated Work

When AI agents generate fix branches:
1. Use the `saffron/issue-{N}-{short-desc}` naming convention for agent work.
2. All other generated branches should follow `fix/issue-{N}-{short-desc}` or `pr-{N}`.
3. These patterns are recognized by `scripts/prune-stale-branches.sh` for automatic cleanup.
