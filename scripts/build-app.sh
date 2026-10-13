#!/usr/bin/env bash
# Builds MachinePromptsMan.app (ad-hoc signed) into build/. `universal` builds both arches.
# VERSION may be set by CI; otherwise it comes from the git tag.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHES=()
[[ "${1:-}" == "universal" ]] && ARCHES=(--arch arm64 --arch x86_64)
# ${a[@]+...} because macOS ships bash 3.2, where an empty array trips `set -u`.
swift build -c release ${ARCHES[@]+"${ARCHES[@]}"}
BIN=$(swift build -c release ${ARCHES[@]+"${ARCHES[@]}"} --show-bin-path)/MachinePromptsMan
APP=build/MachinePromptsMan.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MachinePromptsMan"
VERSION=${VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.ainigh.machine-prompts-man</string>
  <key>CFBundleName</key><string>MachinePromptsMan</string>
  <key>CFBundleExecutable</key><string>MachinePromptsMan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>${VERSION#v}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --deep "$APP"
(cd build && ditto -c -k --keepParent MachinePromptsMan.app MachinePromptsMan.zip)
echo "built $APP ($VERSION)"
