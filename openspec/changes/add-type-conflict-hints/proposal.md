# Proposal

## Why

一列里大部分是数字、夹着几个横线或"—"时，DuckDB 会整列按文本处理。用户看到左对齐的金额会以为工具错了。R-INSP-04 要求把这种类型冲突说清楚。

## What Changes

- 列统计增加"看起来是数字的行数"和几个反例。
- 文本列里如果一部分能按数字解析、一部分不能，检查器显示橙色提示。
- 提示说明整列按文本处理，并给出两个反例值。
- 纯文本列和纯数字列不显示该提示。

## Capabilities

### New Capabilities

- column-inspector：类型冲突提示。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- ColumnStats 增加 numericCount 与 nonNumericExamples。
- columnStats 对文本列多一条计数查询和一条示例查询。
- 检查器增加提示区块。

## 不做什么

- 不自动改列类型。
- 不做逐行修复。
- 不处理日期格式的冲突，先只覆盖数值。

## 性能与只读

1000 万行文本列多两次扫描，允许在统计总耗时 1 秒的预算内；超出时把示例查询去掉。只读。
