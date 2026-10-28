# Proposal

## Why

03-data-grid 里有十几条验收一直空着。它们不是没实现，是没量过：滚动帧耗时、200 屏内存、排序与筛选的秒数、首块到底查了几次。空着的验收框会让后来的人重复判断“这个到底验没验过”，也让 README 的性能叙事缺一块证据。

## What Changes

- 新增一个只看不改的调试开关 `TW_LOG_BLOCK_SQL`：设了之后每次取块把 SQL 打到标准错误，并写进 `TW_OPEN_TIMING_FILE` 指定的文件。它只用来留证“首次显示只查一次块、SQL 里是 LIMIT 5000”，不影响正常路径。
- 用仓库现有的 `make-bench-data.sh` 重新生成基准数据集，跑 `bench-scroll.sh`、`TableWorkbenchBench` 的排序与筛选，再把 10m.csv 连滚 120 秒采样内存与 CPU。
- 结论写进 `docs/bench-history.md` 新的一节，逐条勾掉 03-data-grid 里已经量到的验收，超预算的两条写明数字与原因但不勾。

## Capabilities

这次没有外部可见行为的变化，只有调试输出与验收记录，因此不产生规格增量。

## Impact

- 代码：`DuckDBSession` 加一行环境位判断与一次日志输出，`OpenTiming` 抽出 `append` 供它复用。
- 验收：R-GRID-02 三条全部补齐并标为已完成；R-GRID-01/03/04/05 各补齐一部分，剩下的分别是界面截图与两条超预算项。
- 性能预算：排序 24.69 秒、等值筛选 1.51 秒均未达标，按 R-DEC-17 的结论记为已知限制，不动实现。
