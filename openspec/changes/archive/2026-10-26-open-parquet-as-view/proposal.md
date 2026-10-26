# Proposal

## 对应需求

- R-PERF-01：1000 万行、20 列 Parquet 打开不超过 3 秒。
- R-DEC-17：Parquet 源不物化。

## Why

分段计时显示，10m.csv 打开 2.0 秒里 2.00 秒全部花在 `CREATE TABLE __base AS SELECT * FROM read_parquet(...)`，DESCRIBE 与 count(*) 各只有 2–3 毫秒。把 1000 万行从 Parquet 拷进内存没有任何收益：Parquet 本身是列存，按行组读取已经足够快。

## What Changes

- Parquet 源按大小二选一：行数 × 列数不超过 2000 万时仍然物化（宽表按列投影走 Parquet 反而慢），超过就走视图 `SELECT * EXCLUDE (file_row_number), file_row_number AS "__rid" FROM read_parquet(..., file_row_number=true)`。
- 取块改用 `__rid` 过滤并排序；筛选/排序后的 __result 仍用 rowid。
- `data` 视图改成显式列清单，不把 `__rid` 暴露给用户。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- data-import：Parquet 打开方式变化，外部行为不变。

## Impact

- DuckDBSession 增加 orderColumn，块查询按数据源选 rowid 或 __rid。
- CSV 仍物化，不受影响。

## 性能与只读

10m.csv 打开从 2.48 秒降到 0.028 秒，取块从 0.53–0.62 秒降到 0.045–0.057 秒。代价是第一次排序要物化 __result：328 万行 2.0 秒，1000 万行 18 秒。只读约束不变。

## 不做什么

- 不把 CSV 也改成视图（CSV 每次扫描都要重新解析）。
- 不做行组级别的预取。
