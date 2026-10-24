# Design

## Context

见 proposal.md。QuerySession 有物化表 __base 和筛选结果 __result，结果统一用 SQLResult。检查器和导出都可以直接查这两张表。

## Goals / Non-Goals

**Goals:**

- 统计和导出都走 SQL，不在 Swift 里全量遍历。
- 导出结果与当前筛选一致。
- 文件写入安全。

**Non-Goals:**

- 图表、质量评分、类型修复。
- xlsx 导出。
- 进度条和取消。

## Decisions

### D1 统计用三到四条 SQL

1. 总行数、非空数、去重数、最小/最大、均值/中位数/标准差，一条聚合。
2. 文本列取前 10 个高频值。
3. 数值列取 min/max 后，用 width_bucket 生成 20 个区间计数。

比一次查询更清晰，也避免把直方图塞进复杂 SQL。

### D2 源表跟随筛选

有筛选时统计 __result，没有时统计 __base。这样检查器和表格看到的是同一批行。

### D3 导出用 COPY，先写临时文件

COPY (SELECT ... FROM 表) TO '目标.tmp'，成功后 move 到目标。CSV 用 HEADER 和 UTF-8；Parquet 用 SNAPPY。

### D4 导出列顺序

直接用 SELECT 列清单，顺序与 columns 一致；不包含 __rid/rowid 和隐藏列。

### D5 检查器复用列列表

点击检查器里的列触发统计，结果缓存在会话内；筛选变化后失效。

## Risks / Trade-offs

- [去重计数在千万行上慢] → DuckDB 很快，先精确；超过 1 秒再考虑近似并标注。
- [直方图区间边界] → width_bucket 返回 1..20，超界值夹到两端。
- [导出大文件阻塞] → 同步 COPY，v0.1 接受；后续加进度和取消。
- [目标文件已存在] → 覆盖前先删除旧文件，写临时文件再改名。

## Migration Plan

新增功能，没有数据迁移。回滚删除 ColumnStats 与 export。

## Open Questions

无。
