# Proposal

## Why

用户经常临时算一列：金额乘税率、单价减成本、拼接两个字段。为这个去写 SQL 再回来太绕。R-GRID-06 要求表格里能加计算列。

## What Changes

- 工具栏增加“计算列”，输入列名和一个 SQL 表达式。
- 计算列只用于当前会话，不落盘，关闭文件即消失。
- 表达式先做只读校验和试算，失败时给错误，不加空列。
- 计算列参与分块显示，不参与列检查器、透视和导出。
- 计算列上不提供排序和筛选入口。

## Capabilities

### New Capabilities

- data-grid：计算列。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- ColumnInfo 增加 isComputed 标记。
- QuerySession 增加 displayColumns 与 addComputedColumn。
- DuckDBSession 的块查询拼接计算列。
- App 增加计算列面板。

## 不做什么

- 不做图形化公式编辑器。
- 不做计算列的持久化。
- 不做计算列上的排序、筛选、透视。
- 不把计算列写进导出和 SQL 的 data 视图。

## 性能与只读

表达式在块查询时计算，不物化；1000 万行加一列，单块耗时不超过 0.3 秒。表达式只允许出现在 SELECT 投影里，写操作被拒绝。
