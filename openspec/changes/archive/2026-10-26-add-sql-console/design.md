# Design

## Context

见 proposal.md。当前 QuerySession 只有分块取数和 apply(view:)，SQL 抽屉是占位。物化后基础表叫 __base，没有面向用户的稳定表名。

## Goals / Non-Goals

**Goals:**

- 用户写一条 SELECT 就能看到结果。
- 结果规模和等待时间可控。
- 写操作被拒绝。

**Non-Goals:**

- 多语句、事务、取消。
- 历史、补全、格式化。

## Decisions

### D1 data 视图指向 __base

打开文件时执行 CREATE VIEW "data" AS SELECT * FROM "__base"。这样用户 SQL 永远看到文件全量数据，网格的排序筛选不会改变 data 的含义。

备选：让 data 指向当前筛选结果。会让同一条 SQL 在不同时间返回不同结果，不适合作为分析入口。

### D2 结果包一层 LIMIT 100001

SELECT 和 WITH 开头时，执行 SELECT * FROM (用户 SQL) AS __sql LIMIT 100001。取到 100001 行就说明被截断，只保留前 100000 行。

备选：先 count 再取。会执行两次，代价翻倍。

### D3 语句白名单

去掉首尾空白和分号，取第一个关键字。允许 SELECT、WITH、DESCRIBE、SUMMARIZE；CREATE 只允许后面跟 TEMP。其余走 SQLGuard 拒绝。

### D4 列类型统一按文本返回

结果列全部 CAST 成 VARCHAR 后取字符串，列类型标成 text。原因是通过 duckdb-swift 拿列类型名称需要额外映射，而 SQL 结果的主要用途是看数，网格排序不参与。

备选：用 DESCRIBE 拿类型。多一次查询，收益小。

### D5 执行和分块共用一把锁

runSQL 与 block 用同一把 NSLock。一条长查询会阻塞网格取数，这是可接受的，因为用户在等结果。真正的取消需要 interrupt，当前绑定没有暴露。

### D6 结果复用 DataGridView

SQL 结果转成内存块，用 DataGridView 显示，分块由内存数组提供，不查 DuckDB。结果最多 100000 行，内存可控。

## Risks / Trade-offs

- [长查询无法取消] → 明确记录为缺口，不假装支持；v0.1 用结果上限和单语句控制。
- [结果全部按文本显示] → 数字不右对齐，可接受；后续补类型映射。
- [100000 行全部读进内存] → 约几十 MB，可接受。
- [查询阻塞网格] → 执行时显示进行状态，禁止重复提交。

## Migration Plan

新增功能，没有数据迁移。回滚删除 SQLResult 和抽屉界面。

## Open Questions

无。
