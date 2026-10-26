#!/usr/bin/env bash
# 生成 R-PERF-05 规定的基准数据。产物都在 bench-data/，不进 Git。
#
# 用法：
#   ./scripts/make-bench-data.sh                # 缺什么补什么
#   FORCE=1 ./scripts/make-bench-data.sh        # 全部重新生成
#   BENCH_MB=200 ./scripts/make-bench-data.sh   # 换一份更小的 CSV 快速验流程
#   BENCH_OUT=/tmp/x ./scripts/make-bench-data.sh  # 输出到别的目录（验空目录一键生成用）
#
# 四份数据集：
#   1. 500mb.csv        500 MB 级 CSV，20 列，中文 + 空值 + 日期
#   2. 1gb.parquet      由 1gb.csv 转换而来
#   3. 10m.parquet      1000 万行 × 20 列
#   4. sample-20mb.xlsx 3 个工作表，含合并单元格与无缓存值的公式
#
# Parquet 由应用自己的导出通道生成（TableWorkbenchBench --export-parquet），
# 不依赖外部 duckdb 命令行，保证读写的都是同一份代码产出的 Parquet。
set -euo pipefail

env_or() {
  # $1 变量名  $2 默认值
  local value
  value="$(printenv "$1" 2>/dev/null || true)"
  if [ -z "$value" ]; then echo "$2"; else echo "$value"; fi
}

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(env_or BENCH_OUT "$root/bench-data")"
mkdir -p "$out"

bench_mb="$(env_or BENCH_MB 500)"
big_mb="$(env_or BENCH_BIG_MB 1024)"
tall_mb="$(env_or BENCH_TALL_MB 1550)"
force="$(env_or FORCE 0)"

need() {
  # $1 文件：已有且没设 FORCE 就跳过
  if [ -s "$1" ] && [ "$force" != "1" ]; then
    echo "跳过（已存在）: $(basename "$1")"
    return 1
  fi
  return 0
}

echo "输出目录: $out"
echo "CSV 目标体积: ${bench_mb}MB / ${big_mb}MB / ${tall_mb}MB"

# ---------------------------------------------------------------- 1. 大 CSV
gen_csv() {
  local dir="$1" mb="$2" name="$3"
  python3 - "$dir" "$mb" "$name" <<'PY'
import csv
import os
import random
import sys

out, target_mb, name = sys.argv[1], int(sys.argv[2]), sys.argv[3]
target_bytes = target_mb * 1024 * 1024
random.seed(20261023)

regions = ["华东", "华南", "华北", "西南", "华中"]
channels = ["直销", "渠道", "线上", "续约"]
products = ["标准版", "专业版", "旗舰版", "实施服务", "培训"]
statuses = ["已付款", "待付款", "已退款", "部分付款"]
reps = ["张伟", "李娜", "王强", "刘洋", "陈静", "赵磊"]
cities = [
    ("上海", "上海"), ("杭州", "浙江"), ("深圳", "广东"), ("成都", "四川"),
    ("武汉", "湖北"), ("北京", "北京"), ("南京", "江苏"), ("西安", "陕西"),
]
header = [
    "订单号", "客户名称", "区域", "渠道", "产品", "数量", "单价", "金额", "成本", "毛利",
    "状态", "销售", "城市", "省份", "下单日期", "付款时间", "备注", "折扣", "币种", "批次",
]

path = os.path.join(out, name)
rows = 0
with open(path, "w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(header)
    while handle.tell() < target_bytes:
        batch = []
        for _ in range(2000):
            rows += 1
            qty = random.randint(1, 50)
            price = round(random.uniform(80, 4800), 2)
            amount = round(qty * price, 2)
            cost = round(amount * random.uniform(0.35, 0.75), 2)
            city, province = random.choice(cities)
            note = "" if rows % 17 else "客户要求分批发货"
            batch.append([
                f"A-{rows:09d}", f"客户{rows % 977:03d}", random.choice(regions), random.choice(channels),
                random.choice(products), qty, f"{price:.2f}", f"{amount:.2f}", f"{cost:.2f}",
                f"{amount - cost:.2f}", random.choice(statuses), random.choice(reps),
                city, province, f"2026-{random.randint(1,10):02d}-{random.randint(1,28):02d}",
                "" if rows % 11 == 0 else f"2026-{random.randint(1,10):02d}-{random.randint(1,28):02d} 10:00:00",
                note, f"{random.choice([1.0, 0.95, 0.9, 0.85]):.2f}", "CNY", f"B{rows % 40:02d}",
            ])
        writer.writerows(batch)

print(f"{name}  {os.path.getsize(path) / 1024 / 1024:8.1f} MB  {rows} 行  {len(header)} 列")
PY
}

if need "$out/500mb.csv"; then
  gen_csv "$out" "$bench_mb" "500mb.csv"
fi

if need "$out/1gb.csv"; then
  gen_csv "$out" "$big_mb" "1gb.csv"
fi

# 1000 万行那份按目标体积生成，20 列平均约 160 字节一行
if need "$out/10m.csv"; then
  gen_csv "$out" "$tall_mb" "10m.csv"
fi

# ------------------------------------------------------- 2. 小样本与宽表
gen_small() {
  python3 - "$out" <<'PY'
import csv
import os
import sys

out = sys.argv[1]
regions = ["华东", "华南", "华北", "西南", "华中"]
channels = ["直销", "渠道", "线上", "续约"]
products = ["标准版", "专业版", "旗舰版", "实施服务", "培训"]
statuses = ["已付款", "待付款", "已退款", "部分付款"]
reps = ["张伟", "李娜", "王强", "刘洋", "陈静", "赵磊"]
cities = [("上海", "上海"), ("杭州", "浙江"), ("深圳", "广东"), ("成都", "四川"), ("武汉", "湖北"), ("北京", "北京")]
header = [
    "订单号", "客户名称", "区域", "渠道", "产品", "数量", "单价", "金额", "成本", "毛利",
    "状态", "销售", "城市", "省份", "下单日期", "付款时间", "备注", "折扣", "币种", "批次",
]

wide = os.path.join(out, "wide-100k.csv")
with open(wide, "w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(header)
    for index in range(1, 100_001):
        qty = index % 40 + 1
        price = round(100 + (index % 900) * 1.5, 2)
        amount = round(qty * price, 2)
        city, province = cities[index % len(cities)]
        writer.writerow([
            f"A-{index:09d}", f"客户{index % 977:03d}", regions[index % 5], channels[index % 4],
            products[index % 5], qty, f"{price:.2f}", f"{amount:.2f}", f"{amount * 0.6:.2f}",
            f"{amount * 0.4:.2f}", statuses[index % 4], reps[index % 6], city, province,
            f"2026-{(index % 10) + 1:02d}-{(index % 28) + 1:02d}",
            "" if index % 11 == 0 else f"2026-{(index % 10) + 1:02d}-{(index % 28) + 1:02d} 10:00:00",
            "", "1.00", "CNY", f"B{index % 40:02d}",
        ])

gbk = os.path.join(out, "gbk-sample.csv")
with open(gbk, "w", newline="", encoding="gb18030") as handle:
    writer = csv.writer(handle)
    writer.writerow(header)
    for index in range(1, 5001):
        qty = index % 30 + 1
        price = round(120 + index % 500, 2)
        amount = qty * price
        writer.writerow([
            f"B-{index:06d}", f"客户{index % 200:03d}", "华东", "直销", "标准版", qty,
            f"{price:.2f}", f"{amount:.2f}", f"{amount * 0.6:.2f}", f"{amount * 0.4:.2f}",
            "已付款", "张伟", "上海", "上海", "2026-09-01", "", "测试中文编码", "1.00", "CNY", "B01",
        ])

# 宽表：200 行 × 3000 列，超过默认显示的 200 列，用来验列检查器与宽表滚动。
wide3000 = os.path.join(out, "wide-3000.csv")
with open(wide3000, "w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow([f"列{c}" for c in range(3000)])
    for row in range(200):
        writer.writerow([f"v{c}_{row}" for c in range(3000)])

print(f"wide-100k.csv  {os.path.getsize(wide) / 1024 / 1024:8.1f} MB  100000 行")
print(f"gbk-sample.csv {os.path.getsize(gbk) / 1024 / 1024:8.1f} MB  5000 行（GB18030）")
print(f"wide-3000.csv  {os.path.getsize(wide3000) / 1024 / 1024:8.1f} MB  200 行 × 3000 列")
PY
}

if need "$out/wide-100k.csv" || need "$out/gbk-sample.csv" || need "$out/wide-3000.csv"; then
  gen_small
fi

# --------------------------------------------------------- 3. 多工作表 xlsx
# 手写 zip + XML：openpyxl 写同等规模要慢一倍，也堆不到 20 MB 级。
# 「数据」表刻意让公式没有缓存值，XLSXConverter 只读 v 元素，正好验证公式单元格留空。
# 单表单元格数必须低于 XLSXConverter.maxCells（100 万），否则导入会报"这张表太大了"。
gen_xlsx() {
  python3 - "$out/sample-20mb.xlsx" <<'PY'
import os
import random
import sys
import zipfile

target = sys.argv[1]
random.seed(20261023)

HEADERS = ["订单号", "客户名称", "区域", "产品", "数量", "单价", "金额",
           "折扣", "下单日期", "状态", "备注", "补充说明"]
REGIONS = ["华东", "华南", "华北", "西南", "华中"]
PRODUCTS = ["标准版", "专业版", "旗舰版", "实施服务"]
STATUSES = ["已付款", "待付款", "部分付款"]
REPS = ["张伟", "李娜", "王强", "刘洋", "陈静", "赵磊"]

# 74000 + 1 行 × 12 列 = 888012 个单元格，卡在 100 万以内。
# 备注两列写真实长度的业务说明：短词重复压缩率太高，工作簿会缩到 6 MB 左右。
DATA_ROWS = 74000
SUMMARY_A_ROWS = 20000   # 汇总一：区域 × 产品交叉表，带合并单元格
SUMMARY_B_ROWS = 5000    # 汇总二：销售排行榜

SUBJECTS = ["客户", "甲方", "采购方", "项目组", "渠道伙伴", "区域经理", "售后团队", "财务对接人"]
VERBS = ["要求", "提出", "反馈", "确认", "补充", "催促", "建议", "同意"]
ACTIONS = ["分三批发货", "重新开具发票", "增加一次线上培训", "把验收单寄回公司",
           "调整报价单折扣", "补充历史沟通记录", "提前锁定库存", "更换对接负责人",
           "拆分合同签署", "追加两台设备"]
REASONS = ["因仓库周转较慢", "因开票信息有误", "因新入职人员较多", "因原件需要盖章",
           "按合同第三期约定", "涉及跨区域调拨", "为避免月底冲量", "依上季度复盘结论",
           "受物流时效影响", "结合客户预算安排"]
CARRY = ["已同步财务", "待仓库确认", "走商务审批", "等客户回签",
         "需法务过一遍", "转交售后跟进", "排到下个批次", "本周内闭环"]
sequence = [0]

def long_note(copies):
    parts = []
    for _ in range(copies):
        sequence[0] += 1
        n = sequence[0]
        parts.append(
            f"{random.choice(SUBJECTS)}{n % 997:03d} 号单{random.choice(VERBS)}："
            f"{random.choice(ACTIONS)}，{random.choice(REASONS)}；"
            f"回执 {n:06d}-{random.randint(1000, 9999)}，对接人{random.choice(REPS)}，"
            f"预计 {random.randint(1, 12)} 月 {random.randint(1, 28)} 日前办结，"
            f"{random.choice(CARRY)}。"
        )
    return "".join(parts)

def esc(value):
    return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def col_name(index):
    name = ""
    index += 1
    while index:
        index, rem = divmod(index - 1, 26)
        name = chr(65 + rem) + name
    return name

def inline_cell(col, row, value, style=None):
    ref = f"{col_name(col)}{row}"
    s = f' s="{style}"' if style else ""
    if value is None or value == "":
        return f'<c r="{ref}"{s}/>'
    return f'<c r="{ref}"{s} t="inlineStr"><is><t>{esc(value)}</t></is></c>'

def number_cell(col, row, value, style=None):
    ref = f"{col_name(col)}{row}"
    s = f' s="{style}"' if style else ""
    return f'<c r="{ref}"{s}><v>{value}</v></c>'

# 公式单元格只写 f，不写 v：Excel 没保存过缓存值的那种文件，导入时该列应当留空。
def formula_cell(col, row, body):
    return f'<c r="{col_name(col)}{row}"><f>{esc(body)}</f></c>'

SHEET_HEAD = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<cols><col min="1" max="1" width="14" customWidth="1"/>'
    '<col min="2" max="2" width="18" customWidth="1"/>'
    '<col min="3" max="12" width="12" customWidth="1"/></cols>'
    '<sheetData>'
)
SHEET_TAIL = "</sheetData></worksheet>"

def rows_to_xml(rows):
    for number, cells in rows:
        yield f'<row r="{number}">' + "".join(cells) + "</row>"

def merge_tail(merges):
    if not merges:
        return ""
    parts = [f'<mergeCells count="{len(merges)}">']
    parts += [f'<mergeCell ref="{ref}"/>' for ref in merges]
    parts.append("</mergeCells>")
    return "".join(parts)

# ---------------------------------------------------------------- 数据表
def data_rows():
    yield 1, [inline_cell(i, 1, h, 1) for i, h in enumerate(HEADERS)]
    for index in range(1, DATA_ROWS + 1):
        row = index + 1
        qty = index % 40 + 1
        price = 100 + index % 900
        cells = [
            inline_cell(0, row, f"A-{index:09d}"),
            inline_cell(1, row, f"客户{index % 997:03d}"),
            inline_cell(2, row, REGIONS[index % 5]),
            inline_cell(3, row, PRODUCTS[index % 4]),
            number_cell(4, row, qty),
            number_cell(5, row, price),
            formula_cell(6, row, f"E{row}*F{row}"),
            formula_cell(7, row, f"IF(E{row}>10,0.9,1)"),
            inline_cell(8, row, f"2026-{index % 12 + 1:02d}-{index % 28 + 1:02d}"),
            inline_cell(9, row, STATUSES[index % 3]),
            inline_cell(10, row, "" if index % 13 == 0 else long_note(4)),
            inline_cell(11, row, "" if index % 17 == 0 else long_note(5)),
        ]
        yield row, cells

# -------------------------------------------------------------- 汇总一
def summary_one_rows():
    yield 1, [inline_cell(0, 1, "区域 × 产品 汇总（合并单元格示例）", 1)]
    yield 2, [inline_cell(i, 2, h) for i, h in enumerate(
        ["区域", "标准版", "专业版", "旗舰版", "实施服务", "合计", "占位1", "占位2"])]
    row = 3
    for region in REGIONS:
        for product_index in range(4):
            yield row, [
                inline_cell(0, row, region if product_index == 0 else ""),
                number_cell(1, row, 1000 + product_index * 111),
                number_cell(2, row, 2000 + product_index * 222),
                number_cell(3, row, 3000 + product_index * 333),
                number_cell(4, row, 4000 + product_index * 444),
                formula_cell(5, row, f"SUM(B{row}:E{row})"),
                inline_cell(6, row, ""),
                inline_cell(7, row, ""),
            ]
            row += 1
    for index in range(SUMMARY_A_ROWS):
        yield row, [
            inline_cell(0, row, f"明细{index % 5 + 1}"),
            number_cell(1, row, index % 97),
            number_cell(2, row, index % 89),
            number_cell(3, row, index % 83),
            number_cell(4, row, index % 79),
            formula_cell(5, row, f"SUM(B{row}:E{row})"),
            inline_cell(6, row, ""),
            inline_cell(7, row, ""),
        ]
        row += 1

summary_merges = ["A1:H1"] + [f"A{3 + i * 4}:A{6 + i * 4}" for i in range(len(REGIONS))]

# -------------------------------------------------------------- 汇总二
def summary_two_rows():
    yield 1, [inline_cell(i, 1, h, 1) for i, h in enumerate(
        ["销售", "订单数", "金额", "毛利", "客单价"])]
    for index in range(SUMMARY_B_ROWS):
        row = index + 2
        yield row, [
            inline_cell(0, row, REPS[index % 4] + f"#{index // 4 + 1}"),
            number_cell(1, row, index % 500 + 1),
            number_cell(2, row, round(index * 37.5, 2)),
            number_cell(3, row, round(index * 12.25, 2)),
            number_cell(4, row, round(index * 1.5, 2)),
        ]

styles = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
    '</styleSheet>'
)

content_types = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '</Types>'
)

rels = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>'
)

workbook = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="数据" sheetId="1" r:id="rId1"/>'
    '<sheet name="汇总一" sheetId="2" r:id="rId2"/>'
    '<sheet name="汇总二" sheetId="3" r:id="rId3"/></sheets></workbook>'
)

workbook_rels = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>'
    '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>'
)

def write_sheet(archive, name, rows, merges=()):
    with archive.open(name, "w") as handle:
        handle.write(SHEET_HEAD.encode("utf-8"))
        chunk = []
        for xml in rows_to_xml(rows):
            chunk.append(xml)
            if len(chunk) >= 500:
                handle.write("".join(chunk).encode("utf-8"))
                chunk.clear()
        if chunk:
            handle.write("".join(chunk).encode("utf-8"))
        handle.write((merge_tail(merges) + SHEET_TAIL).encode("utf-8"))

# compresslevel=3：比默认 6 大四分之一，正好落在 20 MB 级，也贴近 Excel 自己的压缩率。
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
    archive.writestr("[Content_Types].xml", content_types)
    archive.writestr("_rels/.rels", rels)
    archive.writestr("xl/workbook.xml", workbook)
    archive.writestr("xl/_rels/workbook.xml.rels", workbook_rels)
    archive.writestr("xl/styles.xml", styles)
    write_sheet(archive, "xl/worksheets/sheet1.xml", data_rows())
    write_sheet(archive, "xl/worksheets/sheet2.xml", summary_one_rows(), summary_merges)
    write_sheet(archive, "xl/worksheets/sheet3.xml", summary_two_rows())

size = os.path.getsize(target) / 1024 / 1024
total = DATA_ROWS + SUMMARY_A_ROWS + SUMMARY_B_ROWS
print(f"sample-20mb.xlsx  {size:8.1f} MB  3 个工作表，约 {total} 行")
PY
}

if need "$out/sample-20mb.xlsx"; then
  gen_xlsx
fi

# ------------------------------------------------------------ 4. Parquet
bench_bin() {
  local bin
  bin="$(swift build --package-path "$root/app" -c release --show-bin-path 2>/dev/null)/TableWorkbenchBench"
  if [ ! -x "$bin" ]; then
    echo "构建 TableWorkbenchBench（release）…" >&2
    swift build --package-path "$root/app" -c release --product TableWorkbenchBench >/dev/null
  fi
  echo "$bin"
}

convert_parquet() {
  local src="$1" dst="$2" bin
  if ! need "$dst"; then return 0; fi
  bin="$(bench_bin)"
  echo "转换 Parquet: $(basename "$src") -> $(basename "$dst")"
  "$bin" "$src" --export-parquet "$dst"
}

convert_parquet "$out/500mb.csv" "$out/500mb.parquet"
convert_parquet "$out/1gb.csv" "$out/1gb.parquet"
convert_parquet "$out/10m.csv" "$out/10m.parquet"

# ------------------------------------------------------------ 5. 清单
echo
echo "== 基准数据集 =="
python3 - "$out" "$bench_mb" <<'PY'
import os
import sys

out, bench_mb = sys.argv[1], sys.argv[2]
files = [
    ("500mb.csv", f"{bench_mb} MB 目标 CSV，20 列"),
    ("500mb.parquet", "上一条转出来的 Parquet"),
    ("1gb.csv", "1 GB 级 CSV"),
    ("1gb.parquet", "1 GB CSV 转出的 Parquet"),
    ("10m.csv", "1000 万行级 CSV"),
    ("10m.parquet", "1000 万行 × 20 列 Parquet"),
    ("sample-20mb.xlsx", "20 MB 级 xlsx，3 个工作表"),
    ("wide-100k.csv", "小样本，100000 行"),
    ("gbk-sample.csv", "GB18030 编码样本"),
    ("wide-3000.csv", "宽表，200 行 × 3000 列"),
]
for name, note in files:
    path = os.path.join(out, name)
    if os.path.exists(path) and os.path.getsize(path) > 0:
        mb = os.path.getsize(path) / 1024 / 1024
        print(f"  {name:20s} {mb:9.1f} MB  {note}")
    else:
        print(f"  {name:20s} {'缺失':>9s}  {note}")
PY

echo
echo "行数与列数的实测值写在 ./scripts/bench.sh 的输出里。"

