# Proposal

## Why

R-IMP-01 的第一条验收是「拖入 500MB CSV，从松手到表格可滚动不超过 2 秒」。上一轮只量到一次，记的是 2.8–2.9 秒，还写着「超预算、样本不足、待复测」。这次复测发现那个数字跑的是 debug 产物，口径本身不成立；换成 release 并按应用内打点分段后，2 秒预算主要丢在三个地方：取块 SQL 用虚拟 rowid 过滤要全表扫、NSTableView 按 300 万行接数据源、以及 CSV 解析本身。前两处可以在这轮改掉，第三处不动（解析吞吐没有便宜的改法）。

## What Changes

- 应用内加一层打开计时打点 `OpenTiming`：设 `TW_OPEN_TIMING` 后，把「松手 / 物化 __base / DESCRIBE / count(*) / 会话就绪 / 首块 / 表格首帧」按相对秒数写进标准错误，`TW_OPEN_TIMING_FILE` 设了就同时写文件。拖放落到窗口上时起点归零，外部脚本不参与计时。
- 物化表取块从 `WHERE rowid >= a AND rowid < b ORDER BY rowid` 改成 `LIMIT size OFFSET offset`。DuckDB 的 rowid 是虚拟列，过滤用不上统计信息，每块都要扫整表；LIMIT/OFFSET 在第 1 / 100 / 200 块上是 0.03 / 0.09 / 0.14 秒，每个位置都更快。Parquet 视图那条路保持 `__rid` 过滤不变。
- 网格接数据源改成先按 0 行接上，视图搭完再 `reloadData` 带真实行数，省掉 AppKit 在设 dataSource 时按 326 万行建内部结构的那 0.57 秒。
- 不改 CSV 解析，不做 __rid 列，不动缓存转换时机（三条都试过，见 design）。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `data-import`：打开耗时的口径从「无界面 API 路径」补成「拖入到首帧」这一条，并写明打点方式。
- `grid-paging`：首块取数的实现约束（物化表用 LIMIT/OFFSET、Parquet 视图用 __rid）写进能力契约。

## Impact

- 新增 `app/Sources/DuckDBKit/OpenTiming.swift`；`DropTarget`、`WorkspaceModel`、`DuckDBSession`、`GridDataSource`、`GridTableView`、`DataGridView` 各加几行打点或改动。
- 取块 SQL 改动影响所有读块的路径：网格、复制、导出。`TableWorkbenchTests` 覆盖到排序后取块与导出，全绿；滚动基准 300 帧 p95 1.34 ms、超预算帧 0。
- 性能预算：首屏从 2.54 秒降到 1.912 秒（五次中位），仍有一轮 2.148 秒超预算，超在 CSV 解析，取舍见 design 与 R-DEC-22。
