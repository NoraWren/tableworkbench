#!/usr/bin/env bash
# 把 TableWorkbenchClickBench 装成一个最小 .app 再跑。
# 原因：不带 bundle 的进程激活不了，窗口永远不是 key window，
# 网格的点击会被当成「激活应用」吞掉，量出来的不是真实点击路径。
#
# 用法：默认 release 构建（性能数字只认 release）；
#       DEBUG=1 ./scripts/make-clickbench-bundle.sh 装 debug 版本，仅用于排查。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/ClickBench.app"
config="release"
if [ "${DEBUG:-0}" = "1" ]; then config="debug"; fi

swift build --package-path "$root/app" -c "$config" --product TableWorkbenchClickBench >/dev/null
bin="$(swift build --package-path "$root/app" --show-bin-path -c "$config")/TableWorkbenchClickBench"

if [ -d "$bundle" ]; then
  python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$bundle"
fi
mkdir -p "$bundle/Contents/MacOS"
cp "$bin" "$bundle/Contents/MacOS/ClickBench"

cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClickBench</string>
    <key>CFBundleIdentifier</key>
    <string>dev.kongqi.tableworkbench.clickbench</string>
    <key>CFBundleName</key>
    <string>ClickBench</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$bundle" >/dev/null 2>&1 || true
echo "$bundle"

