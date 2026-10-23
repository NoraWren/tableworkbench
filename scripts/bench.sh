#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [ ! -f bench-data/500mb.csv ]; then
  echo "缺少基准数据，先运行 ./scripts/make-bench-data.sh" >&2
  exit 1
fi

echo "构建 release 版本…"
swift build --package-path app -c release --product TableWorkbenchBench >/dev/null

bin="$(swift build --package-path app -c release --show-bin-path)/TableWorkbenchBench"

echo
echo "== 500MB CSV =="
/usr/bin/time -l "$bin" bench-data/500mb.csv --json 2>&1 | tee /tmp/tableworkbench-bench.log

echo
echo "峰值内存（maximum resident set size，字节）"
grep -E "maximum resident set size" /tmp/tableworkbench-bench.log || true
