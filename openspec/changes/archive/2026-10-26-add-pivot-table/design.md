# Design

## Context

见 proposal.md。QuerySession 已有 runSQL 和物化表 __base/__result。透视可以生成一条 SELECT，复用 SQL 结果的执行与显示。

## Goals / Non-Goals

**Goals:**

- 用一条 SQL 完成透视。
- 列维度取值动态生成列。
- 基数保护明确。

**Non-Goals:**

- 图表、下钻、百分比。
- 配置保存。

## Decisions

### D1 条件聚合，而不是 PIVOT 语句

先生成列维度的去重组合，再拼 SUM(CASE WHEN ...)、COUNT(CASE WHEN ...) 等。这样结果列名可控，空组合也能补零。

备选：DuckDB 的 PIVOT 语句。语法更短，但列名和空值行为不易控制，也不方便多值字段。

### D2 列维度组合用多列 DISTINCT

多个列维度时，查询 SELECT DISTINCT c1, c2，最多取 201 行判断是否超限。组合名用 " / " 连接。

### D3 行基数先查一次

SELECT count(*) FROM (SELECT DISTINCT 行维度 FROM 表)，超过 5000 直接拒绝，避免生成巨大结果。

### D4 源表选择

有筛选时用 __result（已物化的筛选结果），否则用 __base。排序不影响透视。

### D5 结果复用 SQLResult

透视 SQL 走与 runSQL 相同的执行路径：DESCRIBE 取列名、CAST 成 VARCHAR、限制 10 万行。界面复用结果网格。

### D6 多值字段的列名

单值无列维度：列名用"金额 求和"。有列维度：列名用"金额 求和 / 华东"。多值多列时能区分。

## Risks / Trade-offs

- [列维度取值过多] → 200 上限，提示改用行维度或筛选。
- [条件列很多导致 SQL 很长] → 200 列上限，SQL 约几百 KB，可接受。
- [空组合] → CASE 条件不匹配时 SUM 为 NULL；界面显示 NULL，不强行补零。
- [大表行基数查询耗时] → 一次去重查询，328 万行约 0.3 秒。

## Migration Plan

新增功能，没有数据迁移。回滚删除 Pivot 相关代码。

## Open Questions

无。
