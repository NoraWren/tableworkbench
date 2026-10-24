#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/TableWorkbench.app"
config="debug"
if printenv BUILD_CONFIG >/dev/null 2>&1; then config="$(printenv BUILD_CONFIG)"; fi

swift build --package-path "$root/app" -c "$config" --product TableWorkbench >/dev/null
bin="$(swift build --package-path "$root/app" -c "$config" --show-bin-path)/TableWorkbench"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin" "$bundle/Contents/MacOS/TableWorkbench"
cp "$root/app/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/app/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$bundle" >/dev/null 2>&1 || true
echo "$bundle"
