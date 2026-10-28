# Proposal

## Why

R-SQL-01 有一条验收是「Command+R 在有选区时只执行选中的语句」，但实现里运行命令直接取整篇文本，选中一段再按 Command+R 还是跑全篇。抽屉里经常放着两三条语句，只跑选中那条是最常见的用法。

## What Changes

- 编辑器在选区变化时把选中文字放进 `SQLSelectionBus`，选区为空就清空。
- 运行命令改成：有选区只跑这段，没有选区跑整篇。历史记录的仍是实际执行的那条。
- 补两条断言：选中一段时槽位里是这段、没有选区时槽位清空。

## Capabilities

### Modified Capabilities

- `sql-console`：把「运行只跑选区」写进契约，并写明选区为空的语义。

## Impact

- 代码：`SQLEditorUI` 加一个共享槽位与选区回调，`ContentView` 的运行命令读它。
- 另外把 R-SQL-01 的千万行分组实测补上：10m.parquet 上城市分组 0.075 秒、区域加渠道 0.065 秒，都在 2 秒预算内。
- 取消那条做不到，原因（拿不到 `duckdb_interrupt`）写进需求文件与 bench-history，不假装实现。
