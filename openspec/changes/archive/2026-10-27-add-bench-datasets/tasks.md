# Tasks

## 1. 生成脚本

- [x] 1.1 重写 `scripts/make-bench-data.sh`，一条命令产出四份规定数据：验收：空目录跑完退出码 0，共 10 个文件、3.9 GB
- [x] 1.2 加 `need <file>` 跳过逻辑与 `FORCE=1` 强制重建：验收：第二次跑每份文件打印「跳过（已存在）」，文件 mtime 不变
- [x] 1.3 加 `BENCH_OUT` 换输出目录：验收：`BENCH_OUT=/tmp/foo` 跑出的产物全在 /tmp/foo，仓库 bench-data/ 不动
- [x] 1.4 Parquet 走应用自己的导出通道：验收：脚本惰性构建 `TableWorkbenchBench`，用它导出，不引入 duckdb 命令行或 python duckdb 包
- [x] 1.5 xlsx 手写 zip + XML，三张表，含合并单元格与只有 `<f>` 没有 `<v>` 的公式：验收：`数据` 12 列 × 74000 行 = 888012 个单元格 ≤ `XLSXConverter.maxCells`，成品 21.3 MB
- [x] 1.6 补回 wide-3000.csv（200 行 × 3000 列）：验收：重建脚本后测试不再出现「3000 列文件不存在」的 SKIP，宽表用例 423 项全过

## 2. 基准输出

- [x] 2.1 `TableWorkbenchBench` 新增 `--export-parquet` / `--export-csv`：验收：500mb.csv 转 Parquet 实测 1.216 秒、326.6 万行
- [x] 2.2 `scripts/bench.sh` 跑计时前先打印数据集清单（文件名、大小、行数、列数），行数从文件里实际数：验收：CSV 数换行、xlsx 数 `<row` 标签、Parquet 调 `--json` 拿 rows/columns
- [x] 2.3 某份数据不存在时清单标「缺失」且不中断：验收：临时移走一份文件重跑，输出有该行，脚本继续跑到计时段
- [x] 2.4 补一段 10m.parquet 冷读计时：验收：输出里有这一段的秒数

## 3. 验证

- [x] 3.1 把 bench-data/ 改名后从空目录一键重建，全程约 3 分钟跑完：验收：生成日志无报错，末尾清单齐全
- [x] 3.2 回读三份 Parquet：验收：`openSeconds` 0.028 / 0.023 / 0.021 秒，行数与 CSV 源一致（326.6 万 / 668.8 万 / 1012.4 万）
- [x] 3.3 导进 sample-20mb.xlsx 核对三张表：验收：`数据` 74000 行、`汇总一` 20022 行、`汇总二` 5001 行；148000 个公式单元格的缓存值全部为空
- [x] 3.4 勾掉 `docs/requirements/08-performance.md` 的 R-PERF-05 三条验收，写实测表：验收：文件里状态为「已完成」，数字与 scripts 实跑一致
- [x] 3.5 更新 `docs/requirements/README.md` 与 `docs/bench-history.md`：验收：状态表提到基准数据补齐，bench-history 新增「基准数据集重建（2026-10-27）」
- [x] 3.6 全量构建无新增警告：验收：`swift build` 只剩既有的 ld `search path` 与 ZIPFoundation watchOS 弃用警告
