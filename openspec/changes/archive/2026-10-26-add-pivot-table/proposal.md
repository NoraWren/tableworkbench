# Proposal

## Why

用户经常要回答"每个区域每个月的金额是多少"这类问题。写 SQL 可以，但大多数人不愿意写；R-PVT-01 要求拖拽字段就能出交叉表。

## What Changes

- 透视配置：行维度、列维度、值字段与聚合方式。
- 聚合支持求和、计数、去重计数、平均、最大、最小。
- 生成条件聚合 SQL，在 DuckDB 内完成，不在内存里做行列转置。
- 行基数和列基数有上限保护，超出时提示。
- 结果复用现有的结果网格，可返回数据视图。
- 透视面板支持把字段拖到行、列、值区域。

## Capabilities

### New Capabilities

- pivot-table：透视配置、结果与基数保护。

### Modified Capabilities

无。openspec/specs 尚未归档，这里给 query-engine 追加新的 requirement。

## Impact

- DuckDBKit 增加 PivotSpec 与条件聚合生成。
- QuerySession 增加 pivot。
- Features 与 App 增加透视状态和面板。
- 结果网格复用 SQLResult。

## 不做什么

- 不做图表、下钻、百分比布局。
- 不做计算字段。
- 不做透视配置的保存与复用。

## 性能与只读

328 万行、两级分组的目标 2 秒内。行列基数上限：行 5000，列 200。只读约束不变，透视只读。

