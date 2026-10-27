#!/usr/bin/env bash
# 点击选中延迟基准。用法：./scripts/bench-click.sh [点击次数，默认 40]
#
# 口径：鼠标按下从 NSTableView.mouseDown 进入，到该行进入选中集、受影响行重绘完为止的
# 主线程耗时。不含显卡合成与垂直同步，也不含人手反应时间。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

clicks="${1:-40}"
budget=50

if [ ! -f bench-data/500mb.csv ]; then
  echo "缺少基准数据，先运行 ./scripts/make-bench-data.sh" >&2
  exit 1
fi

echo "构建点击基准并装成最小 .app…"
"$root/scripts/make-clickbench-bundle.sh" >/dev/null
app="$root/build/ClickBench.app"

# 结果文件必须落在仓库外，而且不能用 /var/folders 下的临时目录：
# .app 是 ad-hoc 签名、经 launchd 启动，写那里的随机目录会失败。
outdir="/tmp/clickbench-$$"
mkdir -p "$outdir"
cb_cleanup() { python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$outdir"; }
trap cb_cleanup EXIT

fail=0

run() {
  local file="$1"
  local result="$outdir/$(basename "$file").txt"
  echo
  echo "== $(basename "$file")   ${clicks} 次点击 =="
  # 必须用 open 启动：直接跑可执行文件的进程激活不了，窗口不是 key window。
  # 参数一律给绝对路径：.app 的工作目录是 /，相对路径会被当成不存在。
  TW_CLICK_OUT="$result" open -n -W -a "$app" --args "$root/$file" "$clicks" || true

  if [ ! -f "$result" ]; then
    echo "  没有拿到结果文件，这一步失败"
    fail=1
    return
  fi

  local body mean p95 maxv over missed
  body="$(cat "$result")"
  mean="$(sed -n 's/.*mean=\([0-9.]*\).*/\1/p' <<<"$body")"
  p95="$(sed -n 's/.*p95=\([0-9.]*\).*/\1/p' <<<"$body")"
  maxv="$(sed -n 's/.*max=\([0-9.]*\).*/\1/p' <<<"$body")"
  over="$(sed -n 's/.*over50=\([0-9]*\).*/\1/p' <<<"$body")"
  missed="$(sed -n 's/.*missed=\([0-9]*\).*/\1/p' <<<"$body")"

  if [ -z "${p95:-}" ]; then
    echo "  结果文件内容无法解析：$body"
    fail=1
    return
  fi

  echo "  均值 ${mean} ms  p95 ${p95} ms  最大 ${maxv} ms  超 ${budget} ms 的点击 ${over} 次"

  if [ "${missed:-1}" != "0" ]; then
    echo "  判定：不通过。有 ${missed} 次点击没有真的选中该行，整份结果不可用"
    fail=1
  elif [ "$(echo "${p95} >= ${budget}" | bc)" = "1" ]; then
    echo "  判定：不通过。p95 ${p95} ms 超过预算 ${budget} ms"
    fail=1
  else
    echo "  判定：通过。p95 ${p95} ms 在预算 ${budget} ms 内"
  fi
}

run bench-data/500mb.csv
if [ -f bench-data/wide-100k.csv ]; then run bench-data/wide-100k.csv; fi
if [ -f bench-data/10m.parquet ]; then run bench-data/10m.parquet; fi

echo
echo "说明：数字是主线程上事件分发、命中、选中改写、受影响行重绘的耗时，不含显卡合成与垂直同步。"
echo "必须通过 .app 启动：裸进程拿不到 key window，点击会被系统当成激活应用吞掉。"
exit "$fail"

