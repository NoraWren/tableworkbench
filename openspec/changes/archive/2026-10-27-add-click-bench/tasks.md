# Tasks

## 1. 基准程序

- [x] 1.1 新增 `TableWorkbenchClickBench` executable target，依赖 Features / DataGrid / DuckDBKit：验收：`swift build --product TableWorkbenchClickBench` 通过
- [x] 1.2 在离屏窗口里建出网格，找到 NSScrollView 与 NSTableView：验收：TW_CLICK_DEBUG 能打出窗口 key 状态与行数列数
- [x] 1.3 逐行发鼠标按下与抬起，量「按下 → 选中集包含该行 → displayIfNeeded 返回」：验收：输出含均值、中位、p95、最大、超 50 ms 计数
- [x] 1.4 每次点击核对该行是否真的进了选中集，没进计入 missed 并非零退出：验收：裸进程下实测 missed 5/5、退出码 1；.app 下 missed 0
- [x] 1.5 加 120 秒看门狗，防事件跟踪循环挂死：验收：故意不排抬起事件时程序 120 秒后退出码 3
- [x] 1.6 支持 `TW_CLICK_OUT` 写结果文件、`TW_CLICK_DEBUG` 打命中信息：验收：.app 里跑也能拿到结果行

## 2. 装包与脚本

- [x] 2.1 `scripts/make-clickbench-bundle.sh` 装出最小 .app 并 ad-hoc 签名：验收：`build/ClickBench.app/Contents/MacOS/ClickBench` 存在且可执行
- [x] 2.2 新增 `scripts/bench-click.sh`，跑 500mb.csv 与 wide-100k.csv：验收：终端打印每份的均值/p95/最大与判定
- [x] 2.3 判定规则：missed 必须为 0，p95 必须小于 50 ms，否则脚本返回非零：验收：构造一次失败时退出码非 0
- [x] 2.4 尾注写明口径不含显卡合成与垂直同步：验收：脚本末尾有这一句

## 3. 验收与记录

- [x] 3.1 实跑 500mb.csv 与 wide-100k.csv 各 40 次，missed 为 0：验收：两份结果文件都存在且 missed=0
- [x] 3.2 勾掉 `docs/requirements/08-performance.md` 的 R-PERF-03 第三条并写实测：验收：状态改为已完成，数字与实跑一致
- [x] 3.3 `docs/bench-history.md` 新增「点击选中延迟（2026-10-27）」一节：验收：含口径、数据、次数、结果
- [x] 3.4 `openspec validate --all --strict` 全过：验收：校验项数从 19 变成 20，零报错
- [x] 3.5 测试程序仍全部通过：验收：`app/.build/debug/TableWorkbenchTests` 输出 423 PASS / 0 FAIL
- [x] 3.6 全量构建无新增警告：验收：`swift build` 只剩既有的 ld search path 与 ZIPFoundation 弃用警告

