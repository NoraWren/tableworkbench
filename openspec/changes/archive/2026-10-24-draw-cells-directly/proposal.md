# Proposal

## 对应需求

- R-PERF-03：100 列横向滚动不掉帧。
- R-DEC-18：宽表滚动的单元格开销。

## Why

滚动基准显示 100 列时 p95 19 毫秒、7% 的帧超预算，200 列时几乎每帧都超。瓶颈不在查询，而在每帧重建几千个 NSTextField：控件的布局、校验、可编辑性都不需要，只读表格用不上。

## What Changes

- 新增 GridTextCellView，直接画 NSAttributedString。
- 网格的单元格从 NSTextField 换成这个轻量视图，右对齐、空值置灰、截断与 tooltip 保留。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- data-grid：单元格渲染方式变化，外部行为不变。

## Impact

- DataGrid 增加一个文件，GridDataSource 改几行。
- 表格不再可编辑（它本来就只读）。

## 性能与只读

100 列 p95 从 19.08 毫秒降到 3.09 毫秒，200 列从 25.44 降到 8.04，都回到 16.7 毫秒预算内。只读约束不变。

## 不做什么

- 不做单元格编辑、不做富文本。
- 不改行高与列宽策略。
