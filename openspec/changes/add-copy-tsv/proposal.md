# Proposal

## Why

表格里选中几行，第一条动作通常是复制到别处。R-EXP-04 要求 Command+C 复制选区为 TSV，保留原始精度，空值和长文本不串行。

## What Changes

- Command+C 把选中的行复制成 TSV。
- 表头是否复制跟随设置里的"复制时包含表头"。
- 值保留数据库里的原始字符串，不按界面显示的四舍五入值复制。
- 含制表符、换行、引号的字段用双引号包裹并转义。
- NULL 复制为空字符串。
- 没有选中行时不做任何事。

## Capabilities

### New Capabilities

- data-grid：复制选区。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- DataGrid 增加 TSV 生成和 NSTableView 的 copy: 处理。
- 设置里的复制表头开关开始生效。

## 不做什么

- 不做图片复制、带格式复制。
- 不做跨表格多选区。
- 不做超过 10 万行时的异步进度。

## 性能与只读

复制 1 万行 20 列目标 200 毫秒内。复制只读，不修改数据。

