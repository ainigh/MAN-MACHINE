#!/usr/bin/env bash
# Installs the latest release of MachinePromptsMan into ~/Applications (see tasks/11-release.md).
set -euo pipefail
REPO=ainigh/MAN-MACHINE
mkdir -p ~/Applications
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# gh works for a private repo; plain curl is enough once the repo is public.
if command -v gh >/dev/null; then
  URL=$(gh api "repos/$REPO/releases/latest" --jq '.assets[] | select(.name=="MachinePromptsMan.zip") | .url' 2>/dev/null || true)
  if [[ -n "$URL" ]]; then gh api -H "Accept: application/octet-stream" "$URL" > "$TMP/app.zip"; fi
else
  curl -fsSL -o "$TMP/app.zip" "https://github.com/$REPO/releases/latest/download/MachinePromptsMan.zip" || true
fi
if [[ ! -s "$TMP/app.zip" ]]; then echo "No release yet. Build with: scripts/build-app.sh"; exit 1; fi
rm -rf ~/Applications/MachinePromptsMan.app
ditto -x -k "$TMP/app.zip" ~/Applications
open ~/Applications/MachinePromptsMan.app
