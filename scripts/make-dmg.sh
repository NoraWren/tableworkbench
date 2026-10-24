#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.1.0"
if [ -n "$VERSION" ]; then version="$VERSION"; fi
bundle="$root/build/TableWorkbench.app"

"$root/scripts/make-app-bundle.sh" >/dev/null

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$bundle"
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

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$dmg"
fi

echo "$dmg"
echo "下一步：用 notarytool submit 提交公证，然后 xcrun stapler staple。"
