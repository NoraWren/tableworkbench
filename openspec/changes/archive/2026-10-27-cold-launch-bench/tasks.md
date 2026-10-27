# Tasks

## 1. 计时脚本

- [x] 1.1 新增 `scripts/bench-launch.py`，`osascript` 退出旧进程 → `open -a` → 忙等 CGWindowList：验收：跑起来逐轮打印耗时
- [x] 1.2 `open -a` 传绝对路径：验收：从仓库任意目录跑都能拉起（`open -a` 收相对路径会失败）
- [x] 1.3 owner name 同时试 `CFBundleDisplayName` 与 `CFBundleName`：验收：中文显示名与可执行名不同时仍能认出窗口
- [x] 1.4 主窗口判定加 layer == 0 且宽 > 600 高 > 300：验收：不再把菜单栏碎片当主窗口
- [x] 1.5 首轮单独标注并从统计里排除，仍在逐轮列表可见：验收：首轮 1.643 秒被标成「首轮，含冷读」
- [x] 1.6 标题就绪时点与窗口出现时点分开记：验收：输出里两者各有一列，20/20 轮一致
- [x] 1.7 超预算返回非零码，5 秒没窗口直接报错：验收：`--budget 0.1` 时退出码非 0
- [x] 1.8 缺 .app 时提示先跑 make-app-bundle.sh：验收：`--app build/nope.app` 提示并以 1 退出
- [x] 1.9 开头打印系统负载：验收：输出含「负载：{ 12.3 25.8 35.6 }」一行

## 2. 分段归因

- [x] 2.1 临时打点记 exec / App.init / willFinishLoading / didFinishLaunching / 窗口四段：验收：四段数字相加与脚本总量对得上
- [x] 2.2 写 70 KB 最小 SwiftUI 空窗口 app 做对照：验收：同一机器同一轮测出 0.23 秒基线
- [x] 2.3 验证 dyld 不是瓶颈：验收：`strip -x` 后 0.371 对 0.364，无改善
- [x] 2.4 定位多出的 0.14 秒在系统菜单构建：验收：采样显示 `NSTextInputMenu` → `isWritingToolsAvailable` → `dlopen`
- [x] 2.5 清掉临时打点 `TW_LAUNCH_TIMING`：验收：`rg 'TW_LAUNCH_TIMING' app/Sources` 无输出

## 3. 验收与记录

- [x] 3.1 release 重新组包后跑八批共 160 轮：验收：去掉每批首轮 152 轮，中位 0.497、最小 0.465、最大 0.563、p95 0.537，超预算 0/152
- [x] 3.1a 把整轮测量里擦线超的 2 次单独记下（负载 24.5 的 0.608、Codex 占 70% CPU 时的 0.642）：验收：写进 R-DEC-20，不当异常值删掉
- [x] 3.2 勾掉 `docs/requirements/08-performance.md` R-PERF-04 第三条并写实测：验收：状态改为已完成，数字与实跑一致
- [x] 3.3 `docs/bench-history.md` 新增「冷启动（2026-10-27）」一节：验收：含口径、首轮 20 次原始数字、十批分布表、分段表、最小 app 对照表
- [x] 3.4 README 第一屏冷启动行与正文那句「擦线」同步改：验收：不再出现 0.55–0.63
- [x] 3.5 `docs/release-checklist.md` 与 `10-packaging-release.md` 的旧数字同步改：验收：两处都写 0.497 并注明轮次
- [x] 3.6 `docs/requirements/README.md` 状态表同步：验收：冷启动那条不再写「擦着 0.6 秒」
- [x] 3.7 `openspec validate --all --strict` 全过：验收：校验项数从 22 变成 23，零报错
- [x] 3.8 测试程序仍全部通过：验收：`app/.build/debug/TableWorkbenchTests` 输出 429 PASS / 0 FAIL
