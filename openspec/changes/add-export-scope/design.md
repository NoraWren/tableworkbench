# Design

## Context

见 proposal.md。DuckDBSession 里有两张表：物化的 `__base` 和筛选排序后的 `__result`。网格按 OFFSET/LIMIT 从这两张表取块，所以"网格里第 n 行"和"表里的第 n 行"是同一个口径。

## Goals / Non-Goals

**Goals:**

- 三种导出范围都用一条 SQL 完成，不在 Swift 里逐行遍历。
- 范围与网格看到的内容一致。
- 界面上的默认值仍是当前视图，老习惯不变。

**Non-Goals:**

- 进度条、取消、断点续传。
- 按列选择导出。

## Decisions

### D1 三种范围翻译成三条不同的 COPY

- 当前视图：`COPY (SELECT 列 FROM __result 或 __base)`，与现有实现相同。
- 全部行：`COPY (SELECT 列 FROM __base)`，不看筛选和排序，行数为 `rowCount`。
- 选中行：先 `CREATE TEMP TABLE "__export_rows" AS SELECT 列, row_number() OVER () - 1 AS "__row" FROM (当前视图查询)`，再 `COPY (SELECT 列 FROM "__export_rows" WHERE "__row" IN (...))`。导出后立刻 DROP。

选中行用快照表而不是逐行 `LIMIT 1 OFFSET n`：几千行时后者要发几千条语句，慢两个数量级。快照表只扫描一次。

### D2 行号口径与网格一致

网格取块用的也是 `__result` 的物化顺序，选中行导出用同一条查询算行号，两边对得上。排序后的顺序由 `__result` 的物化顺序决定，这一点和网格完全相同。

### D3 计算列不导出

沿用现有测试"导出不含计算列"的结论：计算列只活在会话里，导出写的是源表列。

### D4 选择框放在 SwiftUI 里，保存面板仍用 NSSavePanel

NSSavePanel 的 accessoryView 要写一堆 AppKit 布局代码，而且行数文案要跟着筛选结果变。用一个 SwiftUI sheet 先选范围和格式，确认后再弹保存面板，代码少一半，也方便以后加"导出选中列"。

### 被否决的方案

- 在保存面板里塞 accessoryView：要手写 Auto Layout，且格式切换时文件名后缀要手动同步，收益不大。
- 选中行逐条查询再拼接 CSV：语句数量等于行数，几千行就卡死。

## 风险

`row_number() OVER ()` 的顺序依赖 DuckDB 物化顺序。如果将来换成并行扫描导致顺序变化，网格和导出会同时错，不会出现两边不一致；届时按 D4 给 `__result` 加显式行号列解决。
