#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
scratch="${TW_BUILD_DIR:-$HOME/Library/Caches/tableworkbench-build}"  # 构建目录必须在 iCloud 之外，见 AGENTS.md 第 10 节

if [ ! -f bench-data/wide-100k.csv ]; then
  echo "缺少基准数据，先运行 ./scripts/make-bench-data.sh" >&2
  exit 1
fi

echo "构建 release 版本…"
swift build --build-system native --scratch-path "$scratch" --package-path app -c release --product TableWorkbenchScrollBench >/dev/null
bin="$(swift build --build-system native --scratch-path "$scratch" --package-path app --show-bin-path -c release)/TableWorkbenchScrollBench"

run() {
  local file="$1"
  local seconds="$2"
  echo
  echo "== $(basename "$file")   ${seconds}s =="
  "$bin" "$file" "$seconds"
}

run bench-data/wide-100k.csv 5
run bench-data/500mb.csv 5
if [ -f bench-data/10m.csv ]; then run bench-data/10m.csv 10; fi
if [ -f bench-data/wide-3000.csv ]; then run bench-data/wide-3000.csv 5; fi

echo
echo "说明：数字是主线程每帧的布局 + 绘制耗时，不含显卡合成与垂直同步。"
