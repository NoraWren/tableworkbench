#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/bench-data"
target_mb="500"
if printenv BENCH_MB >/dev/null 2>&1; then target_mb="$(printenv BENCH_MB)"; fi
target_name="${target_mb}mb.csv"
if printenv BENCH_NAME >/dev/null 2>&1; then target_name="$(printenv BENCH_NAME)"; fi

mkdir -p "$out"

python3 - "$out" "$target_mb" "$target_name" <<'PY'
import csv
import os
import random
import sys

out = sys.argv[1]
target_mb = int(sys.argv[2])
target_name = sys.argv[3]
target_bytes = target_mb * 1024 * 1024
random.seed(20261023)

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

path = os.path.join(out, target_name)
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
                f"{amount - cost:.2f}", "已付款" if rows % 13 else "待付款", random.choice(reps),
                city, province, f"2026-{random.randint(1,10):02d}-{random.randint(1,28):02d}",
                "" if rows % 11 == 0 else f"2026-{random.randint(1,10):02d}-{random.randint(1,28):02d} 10:00:00",
                note, f"{random.choice([1.0, 0.95, 0.9, 0.85]):.2f}", "CNY", f"B{rows % 40:02d}",
            ])
        writer.writerows(batch)

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

def size(path):
    return os.path.getsize(path) / 1024 / 1024

print(f"500mb.csv      {size(path):8.1f} MB  {rows} 行")
print(f"wide-100k.csv  {size(wide):8.1f} MB  100000 行")
print(f"gbk-sample.csv {size(gbk):8.1f} MB  5000 行（GB18030）")
PY

echo "数据目录: $out"
