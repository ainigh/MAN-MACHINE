#!/usr/bin/env bash
# Installs the latest release of MachinePromptsMan into ~/Applications (see tasks/11-release.md).
set -euo pipefail
REPO=ainigh/machine-prompts-man
mkdir -p ~/Applications
URL=$(gh api "repos/$REPO/releases/latest" --jq '.assets[] | select(.name=="MachinePromptsMan.zip") | .url')
if [[ -z "$URL" ]]; then echo "No release yet. Build with: swift build -c release && scripts/build-app.sh"; exit 1; fi
TMP=$(mktemp -d)
gh api -H "Accept: application/octet-stream" "$URL" > "$TMP/app.zip"
rm -rf ~/Applications/MachinePromptsMan.app
ditto -x -k "$TMP/app.zip" ~/Applications
open ~/Applications/MachinePromptsMan.app
