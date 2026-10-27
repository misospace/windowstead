#!/usr/bin/env bash
# CI test for release asset gating (#443).
#
# The release workflow used to upload each platform's zip from that platform's
# own export job, so a failing export still published the release with a
# silently missing platform asset (0.1.0 shipped Linux/Windows/Web, no macOS).
#
# Verifies that:
# 1. "gh release upload" appears exactly once in release.yml and the single
#    occurrence lives in the publish job.
# 2. The publish job needs all four export jobs.
# 3. No export job uploads to the release or mints an app token, and every
#    export job still depends on the validate job.
# 4. Every export job stages its packaged zip as a SHA-pinned workflow
#    artifact.
# 5. The publish job downloads all four staged artifacts.
# 6. The publish job uploads all four staged zips — refusing to upload
#    anything until every one of them is present — and then verifies that all
#    four assets exist on the release.
# 7. Permissions are job-scoped (#446): the workflow level grants no
#    contents:write, validate and the export jobs run with contents:read, and
#    publish alone holds contents:write.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"

PLATFORMS=(linux windows macos web)

fail() {
  echo "::error::$1"
  exit 1
}

# Print the body of a single job block. A job block starts at a line matching
# "^  <jobname>:" and ends at the next line matching "^  [A-Za-z0-9_-]+:".
extract_job() {
  local job="$1"
  awk -v job="$job" '
    $0 ~ "^  " job ":[[:space:]]*$" { in_job = 1; next }
    in_job && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { in_job = 0 }
    in_job { print }
  ' "$RELEASE_YML"
}

# Print every step block of a job, each preceded by a "--- step ---" marker.
# Steps of these workflows are indented by six spaces.
extract_steps() {
  local job="$1"
  extract_job "$job" | awk '
    /^      -[[:space:]]/ { print "--- step ---" }
    { print }
  '
}

# Print every step block of a job whose text matches the given regex.
steps_with() {
  local job="$1"
  local pattern="$2"
  extract_steps "$job" | awk -v pattern="$pattern" '
    /^--- step ---$/ {
      if (buf ~ pattern) print buf
      buf = ""
      next
    }
    { buf = buf $0 "\n" }
    END { if (buf ~ pattern) print buf }
  '
}

# Print the non-comment lines of a step block (comments cannot satisfy a
# check on their own).
step_code() {
  printf '%s\n' "$1" | grep -v -E '^[[:space:]]*#' || true
}

# Print the job names listed under a job's "needs:" key. Handles both the
# inline list form and the block list form.
extract_needs() {
  local job="$1"
  extract_job "$job" | awk '
    /^[[:space:]]*needs:[[:space:]]*\[/ {
      line = $0
      sub(/^[[:space:]]*needs:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      count = split(line, items, ",")
      for (i = 1; i <= count; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
        if (items[i] != "") print items[i]
      }
      next
    }
    /^[[:space:]]*needs:[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*$/ {
      line = $0
      sub(/^[[:space:]]*needs:[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      print line
      next
    }
    /^[[:space:]]*needs:[[:space:]]*$/ { in_needs = 1; next }
    in_needs && /^[[:space:]]*-[[:space:]]*/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
      print item
      next
    }
    in_needs { in_needs = 0 }
  '
}

# A pinned action reference is a 40 character commit SHA, never a tag.
is_sha_pinned() {
  printf '%s\n' "$1" | grep -q -E '@[0-9a-f]{40}([[:space:]]|$)'
}

[ -f "$RELEASE_YML" ] || fail "release workflow not found at $RELEASE_YML"

PUBLISH_BLOCK="$(extract_job publish)"
[ -n "$PUBLISH_BLOCK" ] || fail "release.yml has no publish job"

# 1. Exactly one "gh release upload" in the whole file, and it is in publish.
UPLOAD_COUNT="$(grep -o -F 'gh release upload' "$RELEASE_YML" | wc -l || true)"
[ "$UPLOAD_COUNT" -eq 1 ] \
  || fail "expected exactly 1 'gh release upload' in release.yml, found $UPLOAD_COUNT"
PUBLISH_UPLOAD_COUNT="$(printf '%s\n' "$PUBLISH_BLOCK" | grep -o -F 'gh release upload' | wc -l || true)"
[ "$PUBLISH_UPLOAD_COUNT" -eq 1 ] \
  || fail "the single 'gh release upload' is not inside the publish job"
echo "OK: 'gh release upload' appears exactly once, inside the publish job"

# 2. The publish job needs all four export jobs.
PUBLISH_NEEDS="$(extract_needs publish)"
for platform in "${PLATFORMS[@]}"; do
  if ! printf '%s\n' "$PUBLISH_NEEDS" | grep -qx "$platform"; then
    fail "the publish job does not need the $platform job (needs: $(printf '%s ' $PUBLISH_NEEDS))"
  fi
done
echo "OK: the publish job needs linux, windows, macos and web"

# 3. Export jobs must not upload to the release or mint an app token, and
#    must keep depending on the validate job.
for platform in "${PLATFORMS[@]}"; do
  PLATFORM_BLOCK="$(extract_job "$platform")"
  [ -n "$PLATFORM_BLOCK" ] || fail "release.yml has no $platform job"
  if printf '%s\n' "$PLATFORM_BLOCK" | grep -q -F 'gh release upload'; then
    fail "the $platform job still uploads to the release — only publish may upload"
  fi
  if printf '%s\n' "$PLATFORM_BLOCK" | grep -q -F 'actions/create-github-app-token'; then
    fail "the $platform job still mints an app token — only publish may mint one"
  fi
  PLATFORM_NEEDS="$(extract_needs "$platform")"
  if ! printf '%s\n' "$PLATFORM_NEEDS" | grep -qx 'validate'; then
    fail "the $platform job no longer needs the validate job (needs: $(printf '%s ' $PLATFORM_NEEDS))"
  fi
done
echo "OK: no export job uploads to the release or mints an app token, and each still needs validate"

# 4. Every export job stages its packaged zip as a SHA-pinned artifact.
for platform in "${PLATFORMS[@]}"; do
  STAGE_STEP="$(steps_with "$platform" 'actions/upload-artifact')"
  [ -n "$STAGE_STEP" ] || fail "the $platform job does not stage its release asset"
  if ! printf '%s\n' "$STAGE_STEP" \
    | grep -q -E "^[[:space:]]*name:[[:space:]]*windowstead-$platform[[:space:]]*$"; then
    fail "the $platform staging step does not name artifact windowstead-$platform"
  fi
  if ! printf '%s\n' "$STAGE_STEP" \
    | grep -q -E "^[[:space:]]*path:[[:space:]]*build/windowstead-$platform\.zip[[:space:]]*$"; then
    fail "the $platform staging step does not stage build/windowstead-$platform.zip"
  fi
  if ! printf '%s\n' "$STAGE_STEP" \
    | grep -q -E "^[[:space:]]*if-no-files-found:[[:space:]]*error[[:space:]]*$"; then
    fail "the $platform staging step does not fail when the packaged zip is missing"
  fi
  if ! printf '%s\n' "$STAGE_STEP" | grep -q -E '^[[:space:]]*retention-days:[[:space:]]*[0-9]+[[:space:]]*$'; then
    fail "the $platform staging step does not set a retention period for the staged artifact"
  fi
  STAGE_USES="$(printf '%s\n' "$STAGE_STEP" | grep -E '^[[:space:]]*uses:[[:space:]]*actions/upload-artifact@' || true)"
  is_sha_pinned "$STAGE_USES" \
    || fail "the $platform staging step does not pin actions/upload-artifact to a commit SHA"
done
echo "OK: every export job stages build/windowstead-<platform>.zip as a SHA-pinned artifact"

# 5. The publish job downloads all four staged artifacts.
DOWNLOAD_STEPS="$(steps_with publish 'actions/download-artifact')"
[ -n "$DOWNLOAD_STEPS" ] || fail "the publish job does not download any staged artifacts"
for platform in "${PLATFORMS[@]}"; do
  if ! printf '%s\n' "$DOWNLOAD_STEPS" \
    | grep -q -E "^[[:space:]]*name:[[:space:]]*windowstead-$platform[[:space:]]*$"; then
    fail "the publish job does not download the windowstead-$platform artifact"
  fi
done
DOWNLOAD_USES="$(printf '%s\n' "$DOWNLOAD_STEPS" | grep -E '^[[:space:]]*uses:[[:space:]]*actions/download-artifact@' || true)"
is_sha_pinned "$DOWNLOAD_USES" \
  || fail "the publish job does not pin actions/download-artifact to a commit SHA"
echo "OK: the publish job downloads all four staged artifacts"

# 6. The publish job uploads all four staged zips, checks that every one of
#    them is present before uploading anything, and then verifies the release.
UPLOAD_STEP="$(steps_with publish 'gh release upload')"
[ -n "$UPLOAD_STEP" ] || fail "the publish job has no step that uploads to the release"
UPLOAD_CODE="$(step_code "$UPLOAD_STEP")"
if ! printf '%s\n' "$UPLOAD_CODE" | grep -q -F 'gh release upload'; then
  fail "the release upload is only mentioned in a comment"
fi
if ! printf '%s\n' "$UPLOAD_CODE" | grep -q -F 'env.RELEASE_TAG'; then
  fail "the release upload does not target the release tag"
fi
for platform in "${PLATFORMS[@]}"; do
  if ! printf '%s\n' "$UPLOAD_CODE" | grep -q -F "build/assets/$platform/windowstead-$platform.zip"; then
    fail "the release upload does not upload build/assets/$platform/windowstead-$platform.zip"
  fi
done
if ! printf '%s\n' "$UPLOAD_CODE" | grep -q -F '[ ! -s "$asset" ]'; then
  fail "the release upload does not check that every staged asset is present before uploading"
fi

VERIFY_STEP="$(steps_with publish 'gh release view')"
[ -n "$VERIFY_STEP" ] || fail "the publish job does not verify the uploaded assets"
VERIFY_CODE="$(step_code "$VERIFY_STEP")"
if ! printf '%s\n' "$VERIFY_CODE" | grep -q -F 'gh release view'; then
  fail "the asset verification is only mentioned in a comment"
fi
if printf '%s\n' "$VERIFY_CODE" | grep -q -F 'gh release upload'; then
  fail "the upload and the asset verification must be separate steps"
fi
for platform in "${PLATFORMS[@]}"; do
  if ! printf '%s\n' "$VERIFY_CODE" \
    | grep -q -E "(^|[^A-Za-z0-9/._-])windowstead-$platform\.zip([^A-Za-z0-9._-]|$)"; then
    fail "the publish job does not check the windowstead-$platform.zip asset"
  fi
done

UPLOAD_LINE="$(printf '%s\n' "$PUBLISH_BLOCK" | grep -n -F 'gh release upload' | head -n1 | cut -d: -f1)"
VERIFY_LINE="$(printf '%s\n' "$PUBLISH_BLOCK" | grep -n -F 'gh release view' | head -n1 | cut -d: -f1)"
[ -n "$UPLOAD_LINE" ] || fail "could not locate the upload step in the publish job"
[ -n "$VERIFY_LINE" ] || fail "could not locate the asset verification step in the publish job"
[ "$VERIFY_LINE" -gt "$UPLOAD_LINE" ] \
  || fail "the publish job verifies assets (line $VERIFY_LINE) before uploading them (line $UPLOAD_LINE)"
echo "OK: the publish job uploads all four staged zips and verifies the release assets"

# 7. Permissions are job-scoped: no workflow-level contents:write, validate
#    and the export jobs run with contents:read, and publish alone holds
#    contents:write. The app-token step's "permission-contents: write" is a
#    different key and must not trip the "contents:" checks below, so every
#    match is anchored at the start of the key.
HEADER_SECTION="$(awk '/^jobs:/{exit} {print}' "$RELEASE_YML")"
if printf '%s\n' "$HEADER_SECTION" | grep -q -E '^[[:space:]]*contents:[[:space:]]*write[[:space:]]*$'; then
  fail "release.yml still grants contents:write at the workflow level"
fi
echo "OK: the workflow level does not grant contents:write"

for job in validate "${PLATFORMS[@]}"; do
  JOB_BLOCK="$(extract_job "$job")"
  [ -n "$JOB_BLOCK" ] || fail "release.yml has no $job job"
  if ! printf '%s\n' "$JOB_BLOCK" | grep -q -E '^[[:space:]]+contents:[[:space:]]*read[[:space:]]*$'; then
    fail "the $job job does not run with contents:read"
  fi
  if printf '%s\n' "$JOB_BLOCK" | grep -q -E '^[[:space:]]+contents:[[:space:]]*write[[:space:]]*$'; then
    fail "the $job job must not hold contents:write"
  fi
done
echo "OK: validate and the export jobs run with contents:read"

if ! printf '%s\n' "$PUBLISH_BLOCK" | grep -q -E '^[[:space:]]+contents:[[:space:]]*write[[:space:]]*$'; then
  fail "the publish job does not hold contents:write"
fi
WRITE_HOLDERS=0
for job in validate "${PLATFORMS[@]}" publish; do
  JOB_BLOCK="$(extract_job "$job")"
  if printf '%s\n' "$JOB_BLOCK" | grep -q -E '^[[:space:]]+contents:[[:space:]]*write[[:space:]]*$'; then
    WRITE_HOLDERS=$((WRITE_HOLDERS + 1))
  fi
done
[ "$WRITE_HOLDERS" -eq 1 ] \
  || fail "expected exactly 1 job holding contents:write, found $WRITE_HOLDERS"
echo "OK: publish is the only job holding contents:write"

echo "All release asset gating checks passed"
