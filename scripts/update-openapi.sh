#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/update-openapi.sh [--dry-run]
# Exit codes:
#   0 -> changes produced (success; caller should commit & PR)
#   2 -> no changes detected (no-op)
#  >2 -> error, validation failed

DRY_RUN=false
OUT_FILE="docs/spec/openapi.yaml"   # OpenAPI spec output path

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

echo "Running update script (dry-run=$DRY_RUN)..."

# 1) Run your ballerina generator.
# Modify this command to match how your generator is invoked.
# If your generator supports a dry-run flag, pass it here.
if [ "$DRY_RUN" = "true" ]; then
  echo "Generator: running in dry-run mode (won't write files)"
  # Pass dryrun flag to Ballerina module
  bal run regenerate-openapi-connectors -- dryrun outFile="$OUT_FILE" || true
else
  bal run regenerate-openapi-connectors -- outFile="$OUT_FILE"
fi

# 2) Validate the generated OpenAPI spec (Spectral)
# If you don't want to install globally, use `npx @stoplight/spectral`
echo "Validating $OUT_FILE with Spectral..."
if ! npx --yes @stoplight/spectral lint "$OUT_FILE"; then
  echo "Validation failed for $OUT_FILE"
  exit 3
fi

# 3) Detect if git-tracked files changed
# This assumes the script runs in repo root and uses `git` to check tracked files.
STATUS=$(git status --porcelain)

if [ -n "$STATUS" ]; then
  echo "Files changed:"
  git --no-pager diff --name-only
  # If dry-run, don't actually write or commit; signal as no-op for push
  if [ "$DRY_RUN" = "true" ]; then
    echo "Dry-run: changes detected but not written/committed."
    exit 2
  fi
  # Changes exist and we are not in dry-run => success, let caller commit & create PR
  exit 0
else
  echo "No changes detected."
  exit 2
fi
