# Design

## Context

复制入口在 GridTableView.copy，直接同步生成 TSV 写剪贴板。

## Goals / Non-Goals

**Goals**

- 大选区先确认。

**Non-Goals**

- 异步复制。

## Decisions

### D1 用 NSAlert.runModal

这是需要用户决策的场景，符合 R-SHELL-05；实现最短。

## Risks / Trade-offs

- [模态阻塞] → 只在超阈值时出现，用户点掉就继续。

## Migration Plan

无。

## Open Questions

无。
