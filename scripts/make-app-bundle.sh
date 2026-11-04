#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/TableWorkbench.app"
config="debug"
if printenv BUILD_CONFIG >/dev/null 2>&1; then config="$(printenv BUILD_CONFIG)"; fi
if [ "$config" != "release" ]; then
  echo "提示：当前是 debug 构建，测性能或录演示请用 BUILD_CONFIG=release（debug 的查询会慢几十倍）" >&2
fi

# 构建目录必须落在 iCloud 之外。仓库在 ~/Documents 下，产物放进 .build 会被 fileprovider
# 追着同步：默认 SwiftBuild 后端给资源包签名时撞上 FinderInfo/fileprovider 扩展属性直接失败
# （resource fork ... not allowed），换 native 后端也会在编译完后空转不动。
# 把 scratch 目录挪到 ~/Library/Caches 之后，两种后端都能编完。见 R-DEC-21。
scratch="${TW_BUILD_DIR:-$HOME/Library/Caches/tableworkbench-build}"
swift build --build-system native --scratch-path "$scratch" --package-path "$root/app" -c "$config" --product TableWorkbench >/dev/null
bin="$(swift build --build-system native --scratch-path "$scratch" --package-path "$root/app" -c "$config" --show-bin-path)/TableWorkbench"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin" "$bundle/Contents/MacOS/TableWorkbench"
cp "$root/app/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/app/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
# Apache-2.0 第 4 条要求分发二进制时附上许可证与 NOTICE，打包时一并放进资源目录。
cp "$root/LICENSE" "$bundle/Contents/Resources/LICENSE"
cp "$root/NOTICE" "$bundle/Contents/Resources/NOTICE"

codesign --force --deep --sign - "$bundle" >/dev/null 2>&1 || true
echo "$bundle"
