#!/usr/bin/env bash
# 缓存转换基准（R-PERF-02）。用法：./scripts/bench-cache.sh [重复次数，默认 3]
#
# 口径：500 MB CSV 打开后，后台任务把 CSV 转成 Parquet 存入缓存目录的耗时。
# 不含进程启动与编码探测（那两项算在 R-PERF-01 的打开耗时里），含 DuckDB 读写与产物改名。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
scratch="${TW_BUILD_DIR:-$HOME/Library/Caches/tableworkbench-build}"  # 构建目录必须在 iCloud 之外，见 AGENTS.md 第 10 节

rounds="${1:-3}"
budget=20
source_file="bench-data/500mb.csv"

if [ ! -f "$source_file" ]; then
  echo "缺少基准数据，先运行 ./scripts/make-bench-data.sh" >&2
  exit 1
fi

echo "构建 release 版本…"
swift build --build-system native --scratch-path "$scratch" --package-path app -c release --product TableWorkbenchBench >/dev/null
bin="$(swift build --build-system native --scratch-path "$scratch" --package-path app -c release --show-bin-path)/TableWorkbenchBench"

echo
echo "== 500 MB CSV 后台转 Parquet（预算 ${budget} 秒）=="

fail=0
for round in $(seq 1 "$rounds"); do
  # 必须先删掉正式产物和临时文件，否则量到的是命中缓存。
  python3 - "$source_file" <<'PY'
import hashlib
import os
import sys

source = os.path.abspath(sys.argv[1])
st = os.stat(source)
raw = "%s|%d|%d|v1|UTF-8" % (source, st.st_size, int(st.st_mtime))
key = hashlib.sha256(raw.encode()).hexdigest()
cache = os.path.expanduser("~/Library/Application Support/TableWorkbench/cache")
for suffix in (".parquet", ".parquet.tmp"):
    path = os.path.join(cache, key + suffix)
    if os.path.exists(path):
        os.remove(path)
PY

  seconds="$("$bin" "$source_file" --warm-cache 2>&1 | sed -n 's/^缓存生成: \([0-9.]*\) 秒.*/\1/p')"
  if [ -z "$seconds" ]; then
    echo "第 ${round} 轮：没有拿到转换耗时" >&2
    fail=1
    continue
  fi

  verdict="通过"
  over="$(python3 -c "print(1 if float('$seconds') > $budget else 0)")"
  if [ "$over" = "1" ]; then
    verdict="超出预算"
    fail=1
  fi
  echo "第 ${round} 轮：${seconds} 秒  ${verdict}"
done

echo
echo "== 转换中退出不损坏源文件 =="

python3 - "$bin" "$source_file" <<'PY'
import hashlib
import os
import signal
import subprocess
import sys
import time

binary, source = sys.argv[1], sys.argv[2]
digest_before = hashlib.md5(open(source, "rb").read()).hexdigest()

# 先把缓存清掉，保证这次真的在转换。
st = os.stat(source)
raw = "%s|%d|%d|v1|UTF-8" % (os.path.abspath(source), st.st_size, int(st.st_mtime))
key = hashlib.sha256(raw.encode()).hexdigest()
cache = os.path.expanduser("~/Library/Application Support/TableWorkbench/cache")
paths = [os.path.join(cache, key + s) for s in (".parquet", ".parquet.tmp")]
for path in paths:
    if os.path.exists(path):
        os.remove(path)

proc = subprocess.Popen(
    [binary, source, "--warm-cache"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True
)
time.sleep(2.8)
os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
proc.wait()
time.sleep(0.3)

digest_after = hashlib.md5(open(source, "rb").read()).hexdigest()
final_exists = os.path.exists(paths[0])
tmp_size = os.path.getsize(paths[1]) if os.path.exists(paths[1]) else 0

print("源文件校验和一致: %s" % ("是" if digest_before == digest_after else "否"))
print("中断后没有正式缓存: %s" % ("是" if not final_exists else "否"))
print("中断残留临时文件: %d 字节（SIGKILL 杀进程，进程内清理跑不到）" % tmp_size)
sys.exit(0 if digest_before == digest_after and not final_exists else 1)
PY

echo
echo "说明：耗时不含进程启动与编码探测；滚动与筛选可用性见 docs/bench-history.md。"
echo "      kill -9 之后留下的 .tmp 由下次启动清扫，阈值 1 小时，避免误删正在写的转换。"
exit "$fail"
