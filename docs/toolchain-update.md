# Godot Toolchain Update Guide

## Overview

Godot engine version, status, download URLs, and SHA-256 checksums are centralized in a single file:

```
godot-toolchain.json
```

Both CI workflows (`test.yml` and `release.yml`) consume this file at runtime via a shared "Load Godot toolchain config" step — there is no duplication of version strings or checksums across workflow files.

## How to Update

1. **Determine the new Godot version** from the [Godot releases page](https://github.com/godotengine/godot-builds/releases).
2. **Update `godot-toolchain.json`:**
   - Change `"version"` to the new version (e.g., `"4.3.0"`).
   - Update `"status"` if needed (`stable`, `rc`, etc.).
   - Download each asset and compute its SHA-256:
     ```bash
     curl -fsSL <url> -o /tmp/godot.zip && sha256sum /tmp/godot.zip
     ```
   - Replace the `"sha256"` values for each platform (`linux`, `templates`, `macos`).
3. **Commit and push** — the CI workflows will automatically pick up the new values.
4. **Test locally** (optional): run `just test` if you have Godot installed, or trigger a PR to verify CI passes.

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
