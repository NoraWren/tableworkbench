## 对应需求

- R-PERF-04：包体积与启动。第三条验收「冷启动到窗口可交互不超过 0.6 秒」此前没有可重复的测量手段，只有两种轮询间隔拼出来的四次数字。
- R-PERF-07：基准记录。数字要能一条命令复跑，才配写进 README 第一屏。

## Why

README 第一屏三格里，「冷启动」是唯一一格既没脚本、也没稳定数字的。上一轮
（2026-10-26）临时量了 0.55 / 0.58 / 0.62 / 0.63 秒，四次里两次超 0.6 秒预算，
于是文档里写成了「擦线未达标」。

那个数字有两个问题。一是没有脚本，下次谁量都要重写一遍计时逻辑，口径还会飘。
二是当时不知道 0.5 秒里哪一段是自己的、哪一段是 AppKit 的，也就没法回答
「这 0.03 秒的超出该不该改代码」。

所以这一轮做两件事：把冷启动量成一键可复跑的数字，把 0.5 秒拆成能归因的几段。

## What Changes

- 新增 `scripts/bench-launch.py`：先 `osascript` 退出上一个进程，再 `open -a`
  绝对路径拉起，忙等 `CGWindowListCopyWindowInfo` 到出现带标题的主窗口，
  每轮一个数，末行输出中位/最小/最大与超预算次数。
- 窗口判定同时看「layer == 0」和「宽 > 600 且高 > 300」，避免菜单栏、状态条
  这类碎片被当成主窗口；owner name 从 `Info.plist` 的 `CFBundleDisplayName` 与
  `CFBundleName` 两个都试（中文显示名和可执行文件名不一样）。
- 首轮单独标出来。新二进制要从磁盘冷读，那一轮不代表用户双击的常态，但也不藏。
- 八批共 152 轮实测（负载 4.8–12.1）：去掉每批首轮后中位 0.497 秒、最小 0.465、
  最大 0.563、p95 0.537，超预算 0/152；各批中位只在 0.489–0.502 之间。首轮冷读
  0.493–0.599 秒。整轮测量里另有 2 次擦线超（0.608 在负载 24.5、0.642 在 Codex
  占 70% CPU 时），同批中位没跟着涨，没删也没解释成异常。
- 分段归因：exec → App.init 0.013、→ willFinishLaunching 0.105、
  → didFinishLaunching 0.245、→ 窗口出现 0.065，合计约 0.43 秒（直接 exec 口径）。
  与 70 KB 的最小 SwiftUI 空窗口 app 逐段对照后，多出的约 0.14 秒落在
  `willFinish → didFinish` 的系统菜单构建上。
- 脚本开头打一行系统负载。冷启动对 CPU 竞争很敏感，一个孤零零的秒数读不出可信度。
- 勾掉 08-performance.md 的 R-PERF-04 第三条，更新 README、bench-history、
  release-checklist、10-packaging-release.md 与 12-decisions-risks.md（新增 R-DEC-20）。

## Capabilities

### New Capabilities

- `launch-bench`：冷启动的测量契约——从哪一刻开始计时、到哪一刻停、窗口怎么认、
  首轮怎么算、超预算怎么判定。

### Modified Capabilities

无。已有的 `memory-bench`、`scroll-bench`、`click-bench` 都不涉及启动路径。

## Impact

- `scripts/bench-launch.py`：新增。
- `docs/requirements/08-performance.md`、`docs/requirements/10-packaging-release.md`、
  `docs/requirements/12-decisions-risks.md`、`docs/bench-history.md`、
  `docs/release-checklist.md`、`README.md`：验收与数字。
- 不改应用代码。应用侧的代码路径一行没动，只新增了测量脚本。

## 性能与只读

只读。脚本只负责拉起和退出应用，不打开任何数据文件，不碰数据库，不写用户目录。
它自己会占满一个核（忙等），口径是精度优先；`--poll-ms` 可以换成间隔轮询。

## 不做什么

- 不为这 0.14 秒去改系统菜单的构建方式。菜单项、标题、快捷键都是产品要的，
  为了一个已经达标的数字去动它，收益不明、回退风险倒是清楚。
- 不把 `TW_LAUNCH_TIMING` 那段临时代码留在仓库里。分阶段结论写进文档就够，
  真要再拆一次，照着 design 里记的四个打点位置重打即可。
- 不量「双击」这条系统路径本身。脚本用 `open -a`，与访达双击走同一段 launchd，
  这是目前能自动化的最接近的口径；比直接 exec 多约 0.09 秒，这部分是系统开销。
