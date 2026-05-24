# Godot Toolchain Update Guide

## Overview

Godot engine version, status, download URLs, and SHA-256 checksums are centralized in a single file:

```
godot-toolchain.json
```

Both CI workflows (`test.yml` and `release.yml`) consume this file at runtime via a reusable composite action (`.github/actions/load-godot-toolchain`) — there is no duplication of version strings or checksums across workflow files.

## How to Update

1. **Determine the new Godot version** from the [Godot releases page](https://github.com/godotengine/godot-builds/releases).
2. **Verify SHA-256 checksums** against the actual release assets:
   ```bash
   curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/4.3.0-stable/Godot_v4.3.0-stable_linux.x86_64.zip" -o /tmp/godot_linux.zip && sha256sum /tmp/godot_linux.zip
   curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/4.3.0-stable/Godot_v4.3.0-stable_export_templates.tpz" -o /tmp/godot_templates.tpz && sha256sum /tmp/godot_templates.tpz
   curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/4.3.0-stable/Godot_v4.3.0-stable_macos.universal.zip" -o /tmp/godot_macos.zip && sha256sum /tmp/godot_macos.zip
   ```
3. **Update `godot-toolchain.json`:**
   - Change `"version"` to the new version (e.g., `"4.3.0"`).
   - Update `"status"` if needed (`stable`, `rc`, etc.).
   - Replace the `"sha256"` values for each platform (`linux`, `templates`, `macos`) with the verified checksums.
4. **Commit and push** — the CI workflows will automatically pick up the new values via the composite action.
5. **Test locally** (optional): run `just test` if you have Godot installed, or trigger a PR to verify CI passes.

## Composite Action

The step `.github/actions/load-godot-toolchain` reads `godot-toolchain.json` and exposes these outputs:

| Output | Description |
|--------|-------------|
| `version` | Godot engine version |
| `status` | Release status (`stable`, `rc`, `beta`) |
| `linux_url` | Linux binary download URL |
| `linux_sha256` | Linux binary SHA-256 checksum |
| `templates_url` | Export templates download URL |
| `templates_sha256` | Export templates SHA-256 checksum |
| `macos_url` | macOS binary download URL |
| `macos_sha256` | macOS binary SHA-256 checksum |

Usage in a workflow:

```yaml
- uses: ./.github/actions/load-godot-toolchain
  id: godot-config

- run: echo "Using Godot ${{ steps.godot-config.outputs.version }}"
```

## File Structure

```jsonc
{
  "version": "4.2.2",        // Godot engine version
  "status": "stable",         // Release status: stable | rc | beta
  "download_base": "<base>",  // Base URL for all downloads
  "files": {
    "linux": {
      "url": "...",           // Template with ${version}, ${status}, ${download_base}
      "sha256": "..."         // SHA-256 of the linux binary zip
    },
    "templates": {
      "url": "...",
      "sha256": "..."         // SHA-256 of the export templates zip
    },
    "macos": {
      "url": "...",
      "sha256": "..."         // SHA-256 of the macOS binary zip
    }
  }
}
```

## Validation Checklist

- [ ] All three `sha256` checksums match the actual downloaded files.
- [ ] The version string matches between this file and `project.godot` `[application].config.features`.
- [ ] CI test workflow passes on a PR before merging.
- [ ] If updating to a new major/minor Godot version, verify export templates are compatible with existing project settings.
