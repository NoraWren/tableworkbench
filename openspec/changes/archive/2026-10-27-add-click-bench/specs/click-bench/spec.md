## Purpose

给「点击一行，选中态多久出现」这件事一个能重复跑、不用人眼盯的数字。没有 Xcode 就没有 Instruments，这条 P0 验收不能一直靠手感，于是造一个离屏窗口，往网格上真发鼠标事件，把事件分发、命中测试、选中改写、受影响行重绘这几步的耗时量出来。

## ADDED Requirements

### Requirement: 一条命令量出点击延迟

项目 SHALL 提供 `scripts/bench-click.sh`，无人值守地跑完一次点击基准，输出每次点击的均值、中位、p95、最大值，以及超出 50 毫秒预算的次数。

脚本 MUST 至少覆盖 `bench-data/500mb.csv`，存在 `bench-data/wide-100k.csv` 时一并覆盖。

#### Scenario: 跑一次基准
- **WHEN** 执行 `./scripts/bench-click.sh`
- **THEN** 构建基准程序、装成最小 .app、逐份数据跑点击，终端打印每份的均值/p95/最大值与是否通过

#### Scenario: 缺数据
- **WHEN** `bench-data/500mb.csv` 不存在
- **THEN** 脚本提示先跑 `make-bench-data.sh` 并以非零码退出

### Requirement: 选中必须真的发生

每一次点击后，基准程序 MUST 核对被点的那一行确实进入了网格的选中集。

没生效的次数 MUST 被打印出来，且程序以非零码退出，避免出现「耗时很漂亮但根本没选中」的假数字。

#### Scenario: 点击被吞掉
- **WHEN** 某次点击没能改变选中集
- **THEN** 结果里 `missed` 大于 0，`bench-click.sh` 判定不通过并返回非零

### Requirement: 测量必须在能成为 key window 的环境里跑

基准程序 MUST 以 .app bundle 的形式运行。裸进程激活不了，窗口不是 key window，点击会被系统当成「激活应用」吞掉。

#### Scenario: 装包后运行
- **WHEN** `scripts/make-clickbench-bundle.sh` 跑完
- **THEN** `build/ClickBench.app` 存在且可执行，`bench-click.sh` 通过它跑基准

