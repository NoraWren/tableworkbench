# Proposal

## Why

看到数据之后，用户还要判断这一列能不能用：空值多不多、范围合不合理、最常见的值是什么。看完之后还要把结果带走。R-INSP 和 R-EXP 是 v0.1 的最后两块分析能力。

## What Changes

- 列检查器：选中一列后显示类型、总行数、空值数、去重数、最小/最大、均值/中位数/标准差。
- 数值列显示 20 个区间的直方图，文本列显示最常见的 10 个值。
- 导出当前视图为 CSV 或 Parquet，包含筛选和排序结果。
- 导出先写临时文件再原子改名，避免半截文件。
- 检查器和导出都只读，不改源文件。

## Capabilities

### New Capabilities

- column-inspector：列统计与分布。
- export：导出当前视图。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- DuckDBKit 增加 ColumnStats 与 export。
- QuerySession 增加 columnStats 和 export。
- Features 增加检查器与导出状态。
- App 的检查器面板与工具栏增加入口。

## 不做什么

- 不做相关性分析、质量评分、数据类型修复。
- 不导出 xlsx。
- 导出暂不做进度条和取消，先同步写完；大文件下个版本补。
- 不做图表导出。

## 性能与只读

1000 万行选中一列，统计目标 1 秒内。导出 100 万行 CSV 目标 5 秒内。源文件只读，导出只写用户选择的目标文件。

