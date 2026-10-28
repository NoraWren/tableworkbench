#!/usr/bin/env bash
# 内存基准（R-PERF-06）。用法：./scripts/bench-memory.sh [--long]
#
# 口径：只看匿名页（task_vm_info.internal），和活动监视器「内存」列同源。
# RSS 里混着读文件留下的系统页缓存，1 GB 的 Parquet 读一遍就能把 RSS 顶到 2 GB，
# 那部分是随时可回收的干净页，不参与判定。文件页与 RSS 只打印作参考。
#
# 两条场景：
#   1. 连续开/关 20 个大文件，静置后回到空载基线 +200 MB 以内；
#   2. 打开一个文件保持不动，静置期间末值与峰值相对起始都不涨超过 +20 MB。
#
# 第 2 条在需求里写的是 30 分钟，跑一次要等半小时，所以默认只跑前 1 条，
# 加 --long 才跑完整的 1800 秒。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
scratch="${TW_BUILD_DIR:-$HOME/Library/Caches/tableworkbench-build}"  # 构建目录必须在 iCloud 之外，见 AGENTS.md 第 10 节

long=0
for arg in "$@"; do
  case "$arg" in
    --long) long=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

# 500 MB 一档、1 GB 一档、千万行一档、超宽表一档、Excel 一档，覆盖不同的读取路径。
files=(
  bench-data/500mb.csv
  bench-data/500mb.parquet
  bench-data/1gb.parquet
  bench-data/10m.csv
  bench-data/10m.parquet
  bench-data/1gb.csv
  bench-data/wide-3000.csv
  bench-data/wide-3000.parquet
  bench-data/wide-100k.csv
  bench-data/sample-20mb.xlsx
)

missing=0
for file in "${files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "缺少基准数据：$file" >&2
    missing=1
  fi
done
if [ "$missing" = "1" ]; then
  echo "先运行 ./scripts/make-bench-data.sh" >&2
  exit 1
fi

echo "构建 release 版本…"
swift build --build-system native --scratch-path "$scratch" --package-path app -c release --product TableWorkbenchMemoryBench >/dev/null
bin="$(swift build --build-system native --scratch-path "$scratch" --package-path app -c release --show-bin-path)/TableWorkbenchMemoryBench"

echo
echo "== 连续开关 20 个大文件（10 个文件 × 2 轮，静置 60 秒后判定，上限 +200 MB）=="
set +e
"$bin" cycle "${files[@]}" --rounds 2 --settle 60
cycle_status=$?
set -e

if [ "$long" = "1" ]; then
  echo
  echo "== 打开 10m.parquet 静置 1800 秒（末值与峰值涨幅都不超过 +20 MB）=="
  set +e
  "$bin" idle 1800 bench-data/10m.parquet
  idle_status=$?
  set -e
else
  idle_status=0
  echo
  echo "30 分钟静置未跑。要跑完整那条：./scripts/bench-memory.sh --long"
fi

echo
echo "说明：基线取「每个文件都热过一遍之后」的空载值，热身的一次性开销照实打印但不算增量。"
echo "      判定读静置后的稳态值；刚跑完的高水位是分配器还没还页，不是泄漏。"

if [ "$cycle_status" != "0" ] || [ "$idle_status" != "0" ]; then
  exit 1
fi
