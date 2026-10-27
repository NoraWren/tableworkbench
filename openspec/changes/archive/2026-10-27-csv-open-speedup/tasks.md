# Tasks

## 1. 定位

- [x] 1.1 排除解析器侧参数：threads 1/2/4/8、force_compression、checkpoint_threshold、COPY 转 Parquet
- [x] 1.2 扫描 memory_limit 1200 / 1300 / 1400 / 1600 / 2000 / 3000MB / 4GB，记录打开秒与峰值 RSS
- [x] 1.3 确认 1400MB 是拐点，再往上无收益、峰值继续涨
- [x] 1.4 在 1gb.csv、10m.csv、wide-3000.csv 和两个 Parquet 上复核 1200MB → 1400MB 的影响
- [x] 1.5 核实 duckdb_temporary_files() 全程 0 字节，机制只能记为推断

## 2. 实现

- [x] 2.1 DuckDBSession 增加 residentMemoryLimit / importMemoryLimitBytes / importMemoryLimitFileThreshold
- [x] 2.2 新增 importMemoryLimit(for:)，只对 64 MB 以上的 CSV 放宽
- [x] 2.3 open 开场用导入上限，CREATE TABLE "__base" 之后立刻收回常驻上限
- [x] 2.4 清掉定位期间加的实验开关（TW_PRE_SQL / TW_DEBUG_ERROR / TW_PARALLEL_CSV / TW_THREADS）

## 3. 验证

- [x] 3.1 8 次冷打开（每轮清缓存）：1.851 / 1.529 / 1.581 / 1.546 / 1.549 / 1.576 / 1.527 / 1.532 秒，中位 1.546
- [x] 3.2 首行仍为 A-000000001，行列数与改动前一致
- [x] 3.3 scripts/bench.sh 复跑：500mb.csv 1.834 秒，峰值 RSS 1,302,773,760 字节
- [x] 3.4 查询路径无退化：排序准备 1.687 秒、取块 0.126–0.148 秒、透视 0.082 秒、列统计 0.186 秒
- [x] 3.5 TableWorkbenchTests 429 PASS / 0 FAIL
- [x] 3.6 scripts/bench-memory.sh 判定通过（空载基线 662 MB，静置后 258 MB，热身峰值 +474）

## 4. 文档

- [x] 4.1 08-performance.md 勾掉 R-PERF-01 第一条，状态改「已完成」，写新实测
- [x] 4.2 12-decisions-risks.md 把 R-DEC-15 改写成两级上限，R-DEC-16 标注被推翻
- [x] 4.3 bench-history.md 补「CSV 冷打开（2026-10-27）」一节
- [x] 4.4 README 第一屏「首次打开」换成新数字
- [x] 4.5 openspec validate --all --strict 通过
