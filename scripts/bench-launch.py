#!/usr/bin/env python3
"""冷启动计时。用法：./scripts/bench-launch.py [--rounds N]

口径：从 open -a 返回（launchd 已经接单）到 CGWindowList 里出现主窗口为止，
默认忙等，精度优先。每轮先把上一个进程真正退掉再起，只保证进程不在，
不管别的程序占了多少 CPU —— 所以开头会打一行负载，跑出来的数字要连着它看。

数字单位是秒，保留三位。第一次单独标出来：新二进制要从磁盘冷读，
那一轮不代表用户双击的常态，但也不许藏。
"""
import argparse
import statistics
import subprocess
import sys
import time
from pathlib import Path

import Quartz

WINDOW_TITLE = "本地表格工作台"


def running_pids(name):
    out = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True).stdout
    return [int(x) for x in out.split()]


def quit_app(name, bundle_id, timeout=10.0):
    subprocess.run(["osascript", "-e", f'tell application id "{bundle_id}" to quit'],
                   capture_output=True)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not running_pids(name):
            return True
        time.sleep(0.05)
    for pid in running_pids(name):
        subprocess.run(["kill", "-9", str(pid)], capture_output=True)
    time.sleep(0.2)
    return not running_pids(name)


def window_state(owner_names):
    """返回 (是否有主窗口, 是否有标题)。两个时点分开记，免得口径含糊。"""
    appeared = False
    titled = False
    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    ) or []
    for w in windows:
        if w.get("kCGWindowOwnerName") not in owner_names:
            continue
        if w.get("kCGWindowLayer") != 0:
            continue
        bounds = w.get("kCGWindowBounds") or {}
        # 主窗口 1512×875，菜单/工具栏那些碎片都过不了这个宽度。
        if bounds.get("Width", 0) > 600 and bounds.get("Height", 0) > 300:
            appeared = True
            if (w.get("kCGWindowName") or "").strip() == WINDOW_TITLE:
                titled = True
    return appeared, titled


def launch_once(app_path, owner_names, process_name, bundle_id, poll_ms):
    if not quit_app(process_name, bundle_id):
        raise SystemExit("上一个进程退不掉，先手动退出再跑")
    time.sleep(0.3)
    start = time.perf_counter()
    subprocess.run(["open", "-a", app_path], check=True)
    while True:
        appeared, titled = window_state(owner_names)
        now = time.perf_counter() - start
        if appeared:
            return now, now if titled else None
        if time.perf_counter() - start > 5:
            raise SystemExit("5 秒内没等到主窗口")
        if poll_ms > 0:
            time.sleep(poll_ms / 1000.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=6)
    ap.add_argument("--app", default="build/TableWorkbench.app")
    ap.add_argument("--budget", type=float, default=0.6)
    ap.add_argument("--poll-ms", type=float, default=0.0,
                    help="轮询间隔，0 表示忙等（精度最高，但会占满一个核）")
    args = ap.parse_args()

    app_path = str(Path(args.app).resolve())
    plist = f"{app_path}/Contents/Info.plist"
    if not Path(plist).is_file():
        raise SystemExit(
            f"找不到 {app_path}/Contents/Info.plist。\n"
            "先把应用装出来：BUILD_CONFIG=release ./scripts/make-app-bundle.sh"
        )

    def plist_value(key, default=""):
        out = subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", plist],
                             capture_output=True, text=True).stdout.strip()
        return out or default

    # CGWindowList 的 kCGWindowOwnerName 取的是显示名，和可执行文件名不一定一样。
    process_name = plist_value("CFBundleName", "TableWorkbench")
    owners = {plist_value("CFBundleDisplayName", process_name), process_name}
    bundle_id = subprocess.run(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", plist],
        capture_output=True, text=True).stdout.strip()

    print(f"应用：{app_path}")
    print(f"进程名：{process_name}，窗口归属：{' / '.join(sorted(owners))}")
    print(f"预算：{args.budget:.2f} 秒")
    print(f"轮询：{'忙等' if args.poll_ms <= 0 else f'{args.poll_ms:.0f} ms'}")
    # 负载高的时候冷启动会跟着变慢，记一行便于复跑时对照。
    loads = subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True, text=True).stdout.strip()
    print(f"负载：{loads}")
    print()
    times = []
    titles = []
    for i in range(1, args.rounds + 1):
        elapsed, titled_at = launch_once(app_path, owners, process_name, bundle_id, args.poll_ms)
        times.append(elapsed)
        if titled_at is not None:
            titles.append(titled_at)
        flag = "首轮，含冷读" if i == 1 else ("超" if elapsed > args.budget else "过")
        title_note = f"，标题 {titled_at:.3f}" if titled_at is not None else "，标题未就绪"
        print(f"  {i:>2}  {elapsed:.3f} 秒   {flag}{title_note}")

    warm = times[1:] or times
    med = statistics.median(warm)
    print()
    print(f"全部 {len(times)} 轮：中位 {statistics.median(times):.3f}，最小 {min(times):.3f}，最大 {max(times):.3f}")
    print(f"去掉首轮 {len(warm)} 轮：中位 {med:.3f}，最小 {min(warm):.3f}，最大 {max(warm):.3f}")
    over = [t for t in warm if t > args.budget]
    print(f"去掉首轮后超预算：{len(over)}/{len(warm)}")
    if titles:
        print(f"标题就绪：中位 {statistics.median(titles):.3f}，最大 {max(titles):.3f}"
              f"（{len(titles)}/{len(times)} 轮）")
    quit_app(process_name, bundle_id)
    return 0 if not over else 1


if __name__ == "__main__":
    sys.exit(main())
