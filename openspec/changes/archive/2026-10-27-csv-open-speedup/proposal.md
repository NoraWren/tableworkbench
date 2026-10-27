## 对应需求

- R-PERF-01：打开速度。第一条「500 MB CSV 首次打开不超过 2 秒」此前实测 2.0–2.4 秒，长期贴着预算，
  按 R-DEC-16 记成了「超预算、照实写进 README」。

## Why

上一轮把原因归到「解析吞吐本身，换解析器才能压下来」，这个结论是错的。真正的瓶颈是连接上的
`memory_limit='1200MB'`：500 MB CSV 物化 `__base` 要 1.3 GB 出头的工作内存，卡在 1200MB
时物化阶段要多花约 0.45 秒。把上限抬到 1.4 GB 就够，8 次冷打开中位 1.546 秒，第一次真正达标。

同一组参数还会顺带改善更大的文件：1 GB CSV 3.55–3.79 秒降到 2.92–3.12 秒，1000 万行 5.27 降到 4.80 秒。

## What Changes

- `DuckDBSession` 新增两级内存上限：常驻 `1200MB` 不变，导入期对 64 MB 以上的 CSV 临时抬到 1.4 GB，
  `CREATE TABLE "__base"` 完成立刻收回常驻值。Parquet 走视图，不需要放宽，保持原样。
- 更新 R-PERF-01 第一条验收与状态，把 R-DEC-15 从「单一 1200MB」改写为两级上限，
  R-DEC-16 标注被推翻，bench-history 补一节记录那张参数矩阵和被否掉的并行方案。
- README 第一屏「首次打开」从 2.1–2.4 秒改成新实测。

## Capabilities

### New Capabilities

无。这是已有 query-engine 能力里「物化的资源边界」的一条实现约束，不新增能力面。

### Modified Capabilities

- query-engine：打开 CSV 时物化的内存上限 SHALL 在导入期与常驻期分开，且导入期放宽 SHALL 只对
  超过阈值的 CSV 生效；物化结束 SHALL 立刻收回常驻上限。

## Impact

- app/Sources/DuckDBKit/DuckDBSession.swift：`open(source:)` 的两处 `SET memory_limit`，新增
  `importMemoryLimit(for:)`。
- docs/requirements/08-performance.md、docs/requirements/12-decisions-risks.md、docs/bench-history.md、README.md。
- 不动导入流程、不动查询路径、不动缓存格式。已有 Parquet 缓存继续有效，不需要重建。

## 性能与只读

这是一次纯性能改动，把 R-PERF-01 从擦线推到稳定达标，没有放宽任何预算。代价是导入期峰值内存变高，
记在 R-DEC-15 的「代价」一栏，并说明为什么它不违反 R-PERF-06：

| 数据集 | 1200MB 峰值 RSS | 1400MB 峰值 RSS |
|---|---|---|
| 500mb.csv | 1.18–1.30 GB | 1.28–1.29 GB |
| 1gb.csv | 1.55 GB | 1.73 GB |

R-PERF-06 量的是打开后的静置稳态匿名页（实测静置后 258 MB，空载基线 662 MB），
不是导入那一瞬间的峰值，所以这条验收不受影响；R-PERF-06 那一轮的 bench-memory.sh 判定仍然是「通过」。

## 不做什么

- 不改行序。`preserve_insertion_order=false` 能让打开降到 0.80 秒，但行序会打乱
  （首行变成 A-000049815），网格的第一屏和「第 1 行」全部失去意义，不能用。
- 不换解析器，不做自嗅探列类型。上一轮已经论证过风险大于收益，这次证明根本不需要。
- 不做「先建视图、首屏只查前 5000 行」的模型改造。已经达标，没有理由动打开即物化这个根基。
