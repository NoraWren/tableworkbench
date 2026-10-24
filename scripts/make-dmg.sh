#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.1.0"
if printenv VERSION >/dev/null 2>&1; then version="$(printenv VERSION)"; fi
sign_identity=""
if printenv SIGN_IDENTITY >/dev/null 2>&1; then sign_identity="$(printenv SIGN_IDENTITY)"; fi
bundle="$root/build/TableWorkbench.app"

BUILD_CONFIG=release "$root/scripts/make-app-bundle.sh" >/dev/null

if [ -n "$sign_identity" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$sign_identity" "$bundle"
else
  echo "未设置 SIGN_IDENTITY，使用 ad-hoc 签名，Gatekeeper 会拦截。" >&2
fi

dmg="$root/build/TableWorkbench-$version.dmg"
rm -f "$dmg"

hdiutil create \
  -volname "TableWorkbench $version" \
  -srcfolder "$bundle" \
  -ov \
  -format UDZO \
  "$dmg" >/dev/null

if [ -n "$sign_identity" ]; then
  codesign --force --sign "$sign_identity" "$dmg"
fi

echo "$dmg"
echo "下一步：用 notarytool submit 提交公证，然后 xcrun stapler staple。"
