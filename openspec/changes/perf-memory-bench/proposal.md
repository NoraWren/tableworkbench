## 对应需求

- R-PERF-06：内存。剩下两条验收是「连续打开关闭 20 个大文件，内存回到基线附近（允许 ±200 MB）」和「不做任何操作放 30 分钟，内存不上涨」，一直没有测量手段。

## Why

R-PERF-06 之前只有两条靠临时脚本量出来的数字：打开 1 GB 文件峰值 RSS 不超过 1.5 GB、
转码不整文件读入。剩下两条要的是「反复开关不掉血」和「放着不涨」，这两件事没有程序就测不出来，
靠眼睛看活动监视器既不可重复，也没有一个明确的口径。

补测量的时候先要回答一个前提问题：量什么。我一开始用的 RSS，读数完全不能用——
1 GB 的 Parquet 读一遍，RSS 直接顶到 2 GB，可那部分全是系统文件页缓存，随时能回收，
和应用自己占着多少内存没关系。同一份程序连跑两次，基线一次 17 MB、一次 1961 MB，
差了两个数量级。这个口径不钉死，后面所有数字都没有意义。

## What Changes

- 新增 executable target TableWorkbenchMemoryBench，两个子命令：
  - cycle：先每个文件热一遍取空载基线，然后连续开关 N 轮，静置后判定是否回到基线 ±200 MB 内。
  - idle：打开一个文件保持打开，定时采样看静置期间涨不涨。
- 新增 scripts/bench-memory.sh，一条命令跑完两条验收并给出判定。
- 判定口径写进需求与设计文档：只看匿名页（task_vm_info.internal），文件页与 RSS 只作参考；
  基线取「每个文件都开过一遍之后」；判定取静置后的稳态值。
- 在 08-performance.md 勾掉 R-PERF-06 剩下两条并记下实测，bench-history.md 补一节。

## Capabilities

### New Capabilities

- memory-bench：内存的测量契约——量哪个字段、基线怎么取、什么时候读判定值。

### Modified Capabilities

无。这次只补测量与文档，不改运行时行为。

## Impact

- app/Package.swift：新增一个 executable target。
- app/Sources/TableWorkbenchMemoryBench/main.swift：新增。
- scripts/bench-memory.sh：新增。
- docs/requirements/08-performance.md、docs/bench-history.md：验收与实测记录。

## 性能与只读

只读。基准只打开文件、读首块、读一列统计，然后关掉，不写任何数据。

这次没有放宽任何预算：R-PERF-06 的 ±200 MB 和 30 分钟两条阈值原样保留，
改的是「量哪个字段」和「什么时候读判定值」，以及把这两个选择的依据写清楚。

## 不做什么

- 不做长时间刷循环压力测试（比如连续开关 8 小时）。这一轮先覆盖需求写明的 20 次和 30 分钟。
- 不把基准接进 CI。本机没有远端，也没有稳定的机器口径，接进去只会产生噪音。
- 不改 DuckDB 的 memory_limit、threads 等运行时参数。测过 300MB 与 2 线程两档，
  对内存曲线没有可解释的改善，而 1200MB 是 R-DEC-15 为了打开速度定的，不动它。
- 不用 RSS 做判定，尽管活动监视器上更好看。理由见 design.md 第 2 节。

