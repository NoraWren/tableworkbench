#!/usr/bin/env bash
# 跑性能基准。先列一遍数据集（文件、大小、行数、列数），再跑 500MB CSV 的打开计时。
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
echo "== 基准数据集（R-PERF-05）=="
python3 - "$bin" <<'PY'
import json
import os
import subprocess
import sys
import unicodedata
import zipfile

bench_bin = sys.argv[1]
root = os.getcwd()
data = os.path.join(root, "bench-data")

# 四份规定数据集 + 两份小样本，缺了就标“缺失”，不算失败。
DATASETS = [
    ("500mb.csv", "500 MB CSV，20 列"),
    ("1gb.parquet", "1 GB Parquet"),
    ("10m.parquet", "1000 万行 × 20 列 Parquet"),
    ("sample-20mb.xlsx", "20 MB xlsx，3 个工作表"),
    ("wide-100k.csv", "小样本，100000 行"),
    ("gbk-sample.csv", "GB18030 编码样本"),
    ("wide-3000.csv", "宽表，200 行 × 3000 列"),
]


def count_csv_lines(path):
    lines = 0
    with open(path, "rb") as handle:
        while True:
            block = handle.read(1 << 22)
            if not block:
                break
            lines += block.count(b"\n")
    return max(0, lines - 1)


def count_csv_columns(path):
    with open(path, "rb") as handle:
        header = handle.readline()
    try:
        return len(header.decode("utf-8").rstrip(b"\r\n".decode()).split(","))
    except UnicodeDecodeError:
        return len(header.decode("gb18030").rstrip().split(","))


def count_xlsx(path):
    # 只数 <row 标签，不解 XML，几十万行也够快。
    rows = 0
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.startswith("xl/worksheets/sheet"):
                continue
            with archive.open(name) as handle:
                while True:
                    block = handle.read(1 << 20)
                    if not block:
                        break
                    rows += block.count(b"<row ")
    return rows


def probe(name, path):
    if name.endswith(".parquet"):
        done = subprocess.run(
            [bench_bin, path, "--json"], capture_output=True, text=True, check=True
        )
        payload = json.loads(done.stdout)
        return payload["rows"], payload["columns"]
    if name.endswith(".xlsx"):
        return count_xlsx(path), "多表"
    return count_csv_lines(path), count_csv_columns(path)


def width(text):
    # 中文按两格算，否则表格对不齐
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)

def pad(text, target, align="left"):
    gap = max(0, target - width(text))
    return text + " " * gap if align == "left" else " " * gap + text

print(pad("数据集", 20) + pad("大小", 10, "right") + "  " + pad("行数", 13, "right")
      + "  " + pad("列数", 6, "right") + "  说明")
for name, note in DATASETS:
    path = os.path.join(data, name)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        print(pad(name, 20) + pad("缺失", 10, "right") + "  " + pad("—", 13, "right")
              + "  " + pad("—", 6, "right") + "  " + note)
        continue
    mb = os.path.getsize(path) / 1024 / 1024
    rows, columns = probe(name, path)
    print(pad(name, 20) + pad(f"{mb:.1f}MB", 10, "right") + "  "
          + pad(f"{rows:,}", 13, "right") + "  " + pad(str(columns), 6, "right")
          + "  " + note)
PY

echo
echo "== 500MB CSV =="
/usr/bin/time -l "$bin" bench-data/500mb.csv --json 2>&1 | tee /tmp/tableworkbench-bench.log

echo
echo "峰值内存（maximum resident set size，字节）"
grep -E "maximum resident set size" /tmp/tableworkbench-bench.log || true

echo
echo "== 10m.parquet 冷读 =="
/usr/bin/time -l "$bin" bench-data/10m.parquet --json 2>&1 | tee /tmp/tableworkbench-parquet.log

echo
echo "峰值内存（字节）"
grep -E "maximum resident set size" /tmp/tableworkbench-parquet.log || true

