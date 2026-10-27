#!/usr/bin/env python3
"""跑一轮基准，把结果追加到 docs/bench-history.md 的「记录」表。

用法：
  ./scripts/bench-record.py                # 构建、跑 3 轮、追加一行
  ./scripts/bench-record.py --runs 5       # 跑 5 轮取中位
  ./scripts/bench-record.py --from-logs    # 不重跑，用上一次的测量文件补录
  ./scripts/bench-record.py --dry-run      # 只打印要追加的行与比对结果，不写文件

为什么要跑多轮：同一个提交、同一台机器，500MB 打开时间在历史记录里量到过
0.79 秒和 1.33 秒（10-24 那一行自己就写了两次）。单次数字拿来和基线比 10%，
量到的是这一轮的运气。所以四项都取 3 轮中位，明细一并打印。

基线是「记录」表里同一机型的最后一行。任一项比基线慢（或高）超过 10%，
就在那个单元格后面标 ⚠️ 和变化百分比，并在终端单独列一遍。

表是唯一的状态：脚本只往表尾插一行，不重写历史行，不新增列。
写完回读比对，除新增行外还有任何差异就恢复原文件。
"""
import argparse
import datetime
import difflib
import json
import platform
import re
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HISTORY = ROOT / "docs" / "bench-history.md"
RESULT_FILE = Path("/tmp/tableworkbench-bench-measure.json")
LEGACY_CSV_LOG = Path("/tmp/tableworkbench-bench.log")
LEGACY_PARQUET_LOG = Path("/tmp/tableworkbench-parquet.log")
TABLE_HEADING = "## 记录"
THRESHOLD = 1.10
CSV_DATA = ROOT / "bench-data" / "500mb.csv"
PARQUET_DATA = ROOT / "bench-data" / "10m.parquet"

# 四个数字的列顺序，与表头一致。
METRICS = [
    ("open", "500MB 打开"),
    ("memory", "峰值内存"),
    ("block1", "第 1 块"),
    ("block100", "第 100 块"),
]


def fail(code, message):
    print(message, file=sys.stderr)
    return code


def machine_label():
    """机型串要和表里已有的写法一致：MBP18,3 / M1 Pro / 16GB。"""
    def sysctl(key):
        done = subprocess.run(["sysctl", "-n", key], capture_output=True, text=True)
        return done.stdout.strip() if done.returncode == 0 else ""

    model = sysctl("hw.model") or platform.machine()
    if model.startswith("MacBookPro"):
        model = "MBP" + model[len("MacBookPro"):]
    cpu = sysctl("machdep.cpu.brand_string") or "未知 CPU"
    # sysctl 报 "Apple M1 Pro"，表里历史行写的是 "M1 Pro"，去掉厂商前缀才可比。
    if cpu.startswith("Apple "):
        cpu = cpu[len("Apple "):]
    memory = sysctl("hw.memsize")
    gigabytes = f"{int(memory) // (1024 ** 3)}GB" if memory.isdigit() else "未知内存"
    return f"{model} / {cpu} / {gigabytes}"


def load_average():
    """取 1 分钟负载。打开和取块都吃 CPU，负载高的机器上同一份代码能差 20%。"""
    done = subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True, text=True)
    if done.returncode != 0:
        return None
    parts = done.stdout.replace("{", " ").replace("}", " ").split()
    for part in parts:
        try:
            return float(part)
        except ValueError:
            continue
    return None


def extract_json(text, source):
    """日志里 JSON 之外还混着 /usr/bin/time 的统计行，找第一段配平的 {...}。"""
    start = text.find("{")
    if start < 0:
        raise ValueError(f"{source} 里没有 JSON")
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        ch = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return json.loads(text[start:index + 1])
    raise ValueError(f"{source} 里的 JSON 没有闭合")


def peak_rss(text):
    match = re.search(r"^\s*(\d+)\s+maximum resident set size", text, re.MULTILINE)
    return int(match.group(1)) if match else None


def run_once(binary, data_path, label):
    """用 /usr/bin/time -l 包一次，拿 JSON 和峰值 RSS，明细打出来。

    缓存目录每次新开：用户机器上 bench-data/500mb.csv 早就有 Parquet 缓存，
    直接跑量到的是 0.02 秒的缓存命中，和历史行里的首次打开不是一回事。
    """
    with tempfile.TemporaryDirectory(prefix="tw-bench-cache-") as cache_dir:
        done = subprocess.run(
            ["/usr/bin/time", "-l", str(binary), str(data_path), "--json",
             "--cache-dir", cache_dir],
            capture_output=True, text=True)
    if done.returncode != 0:
        raise ValueError(f"{label} 跑失败：{done.stderr.strip()}")
    combined = done.stdout + done.stderr
    payload = extract_json(combined, f"{label} 输出")
    memory = peak_rss(combined)
    if memory is None:
        raise ValueError(f"{label} 输出里没有 maximum resident set size")
    if payload.get("usedCache"):
        raise ValueError(f"{label} 命中了 Parquet 缓存，不是冷打开，这一轮作废")
    return payload, memory


def measure(runs):
    for path in (CSV_DATA, PARQUET_DATA):
        if not path.exists():
            raise FileNotFoundError(f"缺少 {path}，先跑 ./scripts/make-bench-data.sh")

    print("构建 release 版本…")
    built = subprocess.run(["swift", "build", "--package-path", str(ROOT / "app"),
                            "-c", "release", "--product", "TableWorkbenchBench"],
                           capture_output=True, text=True)
    if built.returncode != 0:
        raise ValueError("swift build 失败：\n" + built.stderr[-2000:])
    located = subprocess.run(["swift", "build", "--package-path", str(ROOT / "app"),
                              "-c", "release", "--show-bin-path"],
                             capture_output=True, text=True)
    binary = Path(located.stdout.strip()) / "TableWorkbenchBench"
    load = load_average()
    print(f"负载：{load if load is not None else '未知'}（1 分钟）")

    opens, memories, firsts, hundreds, details = [], [], [], [], []
    for index in range(1, runs + 1):
        payload, memory = run_once(binary, CSV_DATA, f"500MB 第 {index} 轮")
        blocks = {block["block"]: block["seconds"] for block in payload.get("blocks", [])}
        if 1 not in blocks or 100 not in blocks:
            raise ValueError(f"500MB 第 {index} 轮缺少第 1 块或第 100 块")
        opens.append(payload["openSeconds"])
        memories.append(memory)
        firsts.append(blocks[1])
        hundreds.append(blocks[100])
        details.append((payload["openSeconds"], memory, blocks[1], blocks[100]))
        print(f"  第 {index} 轮  打开 {payload['openSeconds']:.3f} s  "
              f"峰值 {memory / 1024 / 1024:.0f} MB  "
              f"第 1 块 {blocks[1]:.3f} s  第 100 块 {blocks[100]:.3f} s")

    # 10m.parquet 只确认 1000 万行这条路还能跑，不参与四个数字。
    run_once(binary, PARQUET_DATA, "10m.parquet")

    return {
        "runs": runs,
        "cacheState": "cold",
        "loadAverage": load,
        "open": statistics.median(opens),
        "memory": statistics.median(memories),
        "block1": statistics.median(firsts),
        "block100": statistics.median(hundreds),
        "details": [{"open": o, "memory": m, "block1": b1, "block100": b100}
                    for o, m, b1, b100 in details],
    }


def read_measurements(from_logs, runs):
    """有 --from-logs 就复用上一次的测量文件，否则真跑一轮。"""
    if from_logs:
        if RESULT_FILE.exists():
            payload = json.loads(RESULT_FILE.read_text())
            # 早期版本写的是 coldOpen 布尔，兼容一下。
            if "cacheState" not in payload:
                payload["cacheState"] = "cold" if payload.get("coldOpen") else "unknown"
            print(f"复用 {RESULT_FILE}（{payload.get('runs', 1)} 轮，"
                  f"{payload.get('measuredAt', '时间未记')}）")
            return payload
        # 退回 bench.sh 留下的单轮日志，兼容老流程。
        for path in (LEGACY_CSV_LOG, LEGACY_PARQUET_LOG):
            if not path.exists():
                raise FileNotFoundError(f"{RESULT_FILE} 和 {path} 都不存在，先跑一次基准")
        text = LEGACY_CSV_LOG.read_text(errors="replace")
        payload = extract_json(text, str(LEGACY_CSV_LOG))
        blocks = {block["block"]: block["seconds"] for block in payload.get("blocks", [])}
        memory = peak_rss(text)
        if memory is None or 1 not in blocks or 100 not in blocks:
            raise ValueError(f"{LEGACY_CSV_LOG} 不完整")
        print(f"复用 bench.sh 的单轮日志 {LEGACY_CSV_LOG}")
        if payload.get("usedCache") is True:
            state = "hit"
        elif payload.get("usedCache") is False:
            state = "cold"
        else:
            state = "unknown"
        return {
            "runs": 1,
            "cacheState": state,
            "open": payload["openSeconds"],
            "memory": memory,
            "block1": blocks[1],
            "block100": blocks[100],
            "details": [],
        }

    payload = measure(runs)
    payload["measuredAt"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    RESULT_FILE.write_text(json.dumps(payload, indent=2))
    return payload


def git_head():
    done = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True)
    if done.returncode != 0:
        return "未知"
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                           capture_output=True, text=True).stdout.strip()
    return done.stdout.strip() + ("+dirty" if dirty else "")


def format_seconds(value):
    return f"{value:.3f} s"


def format_memory(value):
    megabytes = value / 1024 / 1024
    if megabytes >= 1024:
        return f"{megabytes / 1024:.2f} GB"
    return f"{megabytes:.0f} MB"


def format_metric(key, value):
    return format_memory(value) if key == "memory" else format_seconds(value)


def parse_cell(key, text):
    """把表里已有单元格还原成一个数（秒或字节）。括号注只取头一个数字。"""
    match = re.search(r"(\d+(?:\.\d+)?)", text)
    if not match:
        return None
    number = float(match.group(1))
    if key != "memory":
        return number
    tail = text[match.end():].lstrip()
    if tail.startswith("GB"):
        return number * 1024 * 1024 * 1024
    if tail.startswith("MB"):
        return number * 1024 * 1024
    return None


def split_cells(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def cache_state(cell):
    """从「500MB 打开」那一格判断口径：命中缓存、冷打开，还是没标过。"""
    if "缓存" in cell:
        return "hit"
    if "冷打开" in cell:
        return "cold"
    return "unknown"


def find_table(lines):
    """返回 (表块起止下标, 数据行下标列表)。表块含表头与分隔行。"""
    try:
        heading = next(i for i, line in enumerate(lines) if line.strip() == TABLE_HEADING)
    except StopIteration:
        raise ValueError(f"bench-history 里找不到 {TABLE_HEADING}")
    start = heading + 1
    while start < len(lines) and not lines[start].lstrip().startswith("|"):
        if lines[start].strip():
            raise ValueError(f"{TABLE_HEADING} 后面不是表格")
        start += 1
    end = start
    while end < len(lines) and lines[end].lstrip().startswith("|"):
        end += 1
    return (start, end), list(range(start + 2, end))


def build_row(payload, machine, commit):
    cells = [datetime.date.today().isoformat(), commit, machine]
    cells += [format_metric(key, payload[key]) for key, _ in METRICS]
    # 内存列不受时长口径影响，缓存命中时那一格照写字节数。
    return cells


def compare(row_cells, baseline_cells, baseline_note):
    """退化项就地标进单元格，返回清单给终端打印。"""
    degraded = []
    for offset, (key, label) in enumerate(METRICS):
        new_text = row_cells[3 + offset]
        old_text = baseline_cells[3 + offset]
        old_value = parse_cell(key, old_text)
        new_value = parse_cell(key, new_text)
        if old_value is None or new_value is None:
            continue
        ratio = new_value / old_value
        if ratio > THRESHOLD:
            percent = (ratio - 1) * 100
            row_cells[3 + offset] = f"{new_text} ⚠️ +{percent:.0f}%"
            # 打印时去掉口径标记，两边都只剩数值，读起来才对齐。
            clean_old = old_text.replace("（冷打开）", "").replace("（缓存）", "").strip()
            degraded.append((label, clean_old, new_text, percent, baseline_note))
    return degraded


def ratios(row_cells, baseline_cells):
    lines = []
    for offset, (key, label) in enumerate(METRICS):
        old_value = parse_cell(key, baseline_cells[3 + offset])
        new_value = parse_cell(key, row_cells[3 + offset])
        if old_value is None or new_value is None:
            lines.append(f"  {label}：无法比较（缺数字）")
            continue
        change = (new_value / old_value - 1) * 100
        sign = "+" if change >= 0 else ""
        lines.append(f"  {label}：{format_metric(key, old_value)} → "
                     f"{format_metric(key, new_value)}  {sign}{change:.0f}%")
    return lines


def verified(old_lines, new_lines):
    """diff 只允许出现新增行，出现任何删除或替换就算失败。"""
    diff = list(difflib.unified_diff(old_lines, new_lines, lineterm="", n=0))
    changed = [line for line in diff if line[:1] in "+-" and not line.startswith(("+++", "---"))]
    return changed, all(line.startswith("+") for line in changed)


def main():
    parser = argparse.ArgumentParser(description="跑基准并把结果追加到 bench-history 的「记录」表")
    parser.add_argument("--from-logs", action="store_true",
                        help=f"不重跑，复用 {RESULT_FILE}（没有就退回 bench.sh 的单轮日志）")
    parser.add_argument("--dry-run", action="store_true", help="只打印，不写文件")
    parser.add_argument("--runs", type=int, default=3, help="跑几轮取中位（默认 3）")
    parser.add_argument("--force", action="store_true",
                        help="上一行数字完全相同也照样追加（默认视为重复记录，不写）")
    parser.add_argument("--history", default=str(HISTORY),
                        help="记录文件路径（默认 docs/bench-history.md）")
    args = parser.parse_args()

    history = Path(args.history)
    if not history.exists():
        return fail(2, f"找不到 {history}")

    try:
        payload = read_measurements(args.from_logs, max(1, args.runs))
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as error:
        return fail(2, f"{error}")

    machine = machine_label()
    commit = git_head()
    row_cells = build_row(payload, machine, commit)
    # 命中缓存的打开是 0.02 秒量级，和冷打开差着数量级，必须在单元格里说明。
    state = payload.get("cacheState", "unknown")
    if state == "hit":
        row_cells[3] = f"{row_cells[3]}（缓存）"
    elif state == "cold":
        row_cells[3] = f"{row_cells[3]}（冷打开）"
    old_text = history.read_text()
    old_lines = old_text.splitlines(keepends=True)

    try:
        _, data_rows = find_table(old_lines)
    except ValueError as error:
        return fail(2, f"{error}")

    if not data_rows:
        return fail(2, "「记录」表里还没有数据行，先手工加一行基线")

    baseline_cells = None
    baseline_note = ""
    skipped = []
    last_cells = None
    for index in reversed(data_rows):
        cells = split_cells(old_lines[index])
        if last_cells is None and len(cells) >= 7 and cells[2] == machine:
            last_cells = cells
        if len(cells) < 7 or cells[2] != machine:
            continue
        # 缓存命中和冷打开差着数量级，只能同口径比。
        other = cache_state(cells[3])
        if other != state:
            skipped.append(f"  {cells[0]} / {cells[1]}：口径是"
                           f"{'缓存命中' if other == 'hit' else '未标注'}，不参与比对")
            continue
        baseline_cells, baseline_note = cells, f"{cells[0]} / {cells[1]}"
        break

    # --from-logs 连跑两次会追加两行一模一样的数，那是重复记录，不是两次测量。
    if last_cells is not None and not args.force:
        same = all(row_cells[3 + offset].replace("（冷打开）", "").strip()
                   == last_cells[3 + offset].replace("（冷打开）", "").strip()
                   for offset in range(len(METRICS)))
        if same:
            print()
            print(f"没有追加：四项数字与表尾 {last_cells[0]} / {last_cells[1]} 完全相同。")
            print("这多半是把同一份测量又记了一次。真要再记一行，加 --force。")
            return 0

    print()
    print(f"机型：{machine}")
    print(f"提交：{commit}")
    if payload.get("details"):
        print(f"轮数：{payload['runs']}，四项取中位")
    if payload.get("loadAverage") is not None:
        print(f"负载：{payload['loadAverage']}（1 分钟，脚本自动记录）")
    if state == "cold":
        print("口径：冷打开（每轮用空的 Parquet 缓存目录）")
    elif state == "hit":
        print("口径：沿用 bench.sh 的日志，可能是缓存命中，已在单元格标出")
    else:
        print("口径：沿用 bench.sh 的老日志，无法确认是否命中缓存，建议重跑")
    if baseline_cells is None:
        others = {split_cells(old_lines[i])[2] for i in data_rows
                  if len(split_cells(old_lines[i])) >= 7}
        if others and machine not in others:
            print("没有可比基线：表里没有同机型的行，只追加不比对。")
            print(f"表里的机型是 {'、'.join(sorted(others))}，按 bench-history 的约定另起一节。")
        else:
            print(f"没有同口径的基线：表里没有同为「{'冷打开' if state == 'cold' else '缓存命中'}」"
                  f"的 {machine} 记录，只追加不比对。")
        for line in skipped:
            print(line)
        print("从这一行起口径带标记，下一次跑就能和它比了。")
        degraded = []
    else:
        print(f"基线：{baseline_note}")
        degraded = compare(row_cells, baseline_cells, baseline_note)
        for line in ratios(row_cells, baseline_cells):
            print(line)

    new_line = "| " + " | ".join(row_cells) + " |\n"
    # 表尾那一行如果没有换行符，先补一个，否则新行会粘上去。
    if not old_lines[data_rows[-1]].endswith("\n"):
        old_lines = (old_lines[:data_rows[-1]] + [old_lines[data_rows[-1]] + "\n"]
                     + old_lines[data_rows[-1] + 1:])
    insert_at = data_rows[-1] + 1
    new_lines = old_lines[:insert_at] + [new_line] + old_lines[insert_at:]

    print()
    print("追加：")
    print("  " + new_line.rstrip())

    if degraded:
        print()
        print("⚠️ 退化超过 10%：")
        for label, old_value, new_value, percent, note in degraded:
            print(f"  {label:<8} {old_value} → {new_value}  +{percent:.0f}%（基线 {note}）")
        print("  写进提交说明：原因和打算怎么办。")
        load = payload.get("loadAverage")
        if load is not None and load >= 8:
            print(f"  当时负载 {load}，比核数还高。先排除机器忙，再决定要不要改代码。")
    elif baseline_cells is not None:
        print()
        print("四项都在 10% 以内。")

    if args.dry_run:
        print()
        print("--dry-run，未写文件。")
        return 1 if degraded else 0

    changed, ok = verified(old_lines, new_lines)
    if not ok:
        return fail(3, "回读比对失败：改动不止一行新增，未写文件")

    history.write_text("".join(new_lines))

    # 真正写完之后再验一遍文件本身，防止磁盘上留下半截。
    after = history.read_text().splitlines(keepends=True)
    changed, ok = verified(old_lines, after)
    if not ok or after != new_lines:
        history.write_text(old_text)
        return fail(3, "写入后回读不一致，已恢复原文件")

    shown = history.relative_to(ROOT) if history.is_relative_to(ROOT) else history
    print()
    print(f"已追加到 {shown}，历史行未改动。")
    print("看一遍 git diff 再提交。")
    return 1 if degraded else 0


if __name__ == "__main__":
    sys.exit(main())
