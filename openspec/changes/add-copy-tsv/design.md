# Design

## Context

见 proposal.md。表格用 NSTableView，数据按块加载，cellValue(row:columnIndex:) 返回字符串。复制只需要把选中行读出来拼成 TSV。

## Goals / Non-Goals

**Goals:**

- 复制路径独立于导出，不查 DuckDB 全表。
- 转义规则可单元测试。
- 表头开关生效。

**Non-Goals:**

- 图片、富文本、跨表多选区。

## Decisions

### D1 用 NSTableView 的 copy: 响应

自定义 GridTableView，实现 copy(_:)，从 dataSource（GridDataSource）取选中行和列。SwiftUI 默认的 Edit 菜单会把 Command+C 发给第一响应者，不需要额外菜单。

### D2 TSVBuilder 独立成纯函数

转义和拼接放在 TSVBuilder，不依赖 AppKit，便于测试。

### D3 复制原始字符串

cellValue 返回的是 DuckDB CAST 成 VARCHAR 的值，未经过界面格式化，满足"保留原始精度"。

### D4 表头读 UserDefaults

copyIncludesHeader 由设置页写入，复制时读取，默认 true。

### D5 NULL 用空串

TSV 没有 NULL 概念，空串是通用约定；界面上的 NULL 标记只用于显示。

## Risks / Trade-offs

- [选中大量行时阻塞主线程] → 复制在主线程同步执行，1 万行 20 列约几十毫秒；10 万行再考虑后台。
- [字段里有制表符] → 用引号包裹，粘贴到 Excel 仍可能被拆分，这是 TSV 的固有限制，文档里说明。
- [复制按钮不可发现] → 依赖 Edit 菜单和 Command+C，符合 Mac 习惯。

## Migration Plan

新增功能，没有数据迁移。

## Open Questions

无。
