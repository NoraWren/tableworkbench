# Design

## Context

DataGridView 已经按 maxVisibleColumns/defaultVisibleColumns 裁剪列，但 ContentView 传下去的 provider 调的是 session.block(offset:size:)，DuckDBSession 里固定用 self.displayColumns 拼 SELECT。

## Goals / Non-Goals

**Goals**

- 宽表取块只查界面真正显示的列。
- 列顺序与界面一致，计算列仍按表达式生成。

**Non-Goals**

- 列面板启用/禁用。
- 宽表导入加速。

## Decisions

### D1 协议增加带列的取块方法

QuerySession 增加 block(offset:size:columns:)，默认实现退回全量列，替身会话不用改。

### D2 计算列按传入顺序生成

传入列里 isComputed 的走表达式 AS 别名，其余走 SQLBuilder.selectList，保证返回列顺序与网格一致。

### D3 可见列规则收敛到一个静态方法

DataGridView.visibleColumns(from:) 同时给视图和取数使用，避免两处各写一份阈值。

## Risks / Trade-offs

- [计算列不在前 200 列时取不到] → 现在仍按显示列传，用户启用列后自然包含。

## Migration Plan

无数据迁移。

## Open Questions

无。
