# Design

## Context

见 proposal.md。当前 QuerySession 用 LIMIT/OFFSET，DuckDBSession 把 CSV 挂成视图。排序筛选已经下推，但每次取块都要重新扫描并排序，第 100 块 3.24 秒。

## Goals / Non-Goals

**Goals:**

- 取块代价与偏移量无关。
- 排序/筛选只付一次物化代价。
- 内存和打开时间在预算内。

**Non-Goals:**

- 不做磁盘缓存。
- 不做增量更新，文件变化重开即重新物化。
- 不改界面。

## Decisions

### D1 打开时物化基础表

CREATE TABLE "__base" AS SELECT row_number() OVER () AS "__rid", * FROM read_csv_auto(...)。表的列除了 __rid 与原列。

备选：继续用视图加 rowid 伪列。CSV 视图没有 rowid，窗口函数又会在每次查询时重算，等于没有优化。

### D2 行号顺序要验证

DuckDB 的 CSV 扫描可能并行。先用 500MB 样本检查第 1 行是否为 A-000000001；如果顺序不稳定，物化前 SET threads=1，建表后恢复。

备选：按文件行号自己解析。会把 CSV 解析的坑重新背一遍，不值得。

### D3 排序筛选结果单独物化

apply(view:) 时：

1. DROP TABLE IF EXISTS "__result"。
2. CREATE TEMP TABLE "__result" AS SELECT row_number() OVER () AS "__rid", <列> FROM (SELECT <列> FROM "__base" WHERE ... ORDER BY ...)。
3. 记录 resultCount。

没有排序和筛选时，直接读 "__base"，不建 "__result"。

### D4 取块按行号区间

SELECT ... FROM "__result"（或 "__base"）WHERE "__rid" > offset AND "__rid" <= offset + size ORDER BY "__rid"。

行号连续，所以 BETWEEN 加主键式过滤，DuckDB 扫描量只有块大小。

### D5 旧的临时结果表要删

每次 apply 先 DROP，避免多份结果表叠加占内存。关闭连接时整库释放。

### D6 内存不够时的退路

基础表和结果表会同时存在，最坏是两份全量列。500MB 实测：打开 1.30GB；筛选 1.31GB；排序加筛选 1.65GB；排序全量 2.62GB。

排序全量超过 1.5GB，但这是排序物化的固有代价。D6 的退路（物化结果后删基础表，清空筛选时重读 CSV）没有启用，因为它会让每次切换查询都多一次 500MB 扫描。当前接受 2.62GB 的排序峰值，后续如果做磁盘 Parquet 缓存再优化。

## Risks / Trade-offs

- [打开时间从 0.6 秒涨到 2 秒以上] → 先测；超过 3 秒就改成后台物化，首屏用视图顶一下。
- [行号顺序不稳定] → 用 threads=1 物化，接受更慢的一次性代价。
- [内存翻倍] → 先测峰值，超过 1.5GB 再启用 D6。
- [排序物化耗时 1 秒以上] → 接受，因为只付一次；界面显示"排序中"。

## Migration Plan

改的是会话内的查询路径，没有数据迁移。回滚恢复 LIMIT/OFFSET 的 block 实现。

## Open Questions

无。
