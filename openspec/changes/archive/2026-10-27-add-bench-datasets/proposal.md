# Proposal

## 对应需求

- R-PERF-05：基准数据集。四份固定数据，一键生成，行数列数体积进 bench.sh 输出，数据集不进 Git。
- R-PERF-01：打开速度的测量依赖这些数据，数据不全时那三条验收跑不出来。
- R-PERF-02、R-PERF-06：同样以这几份数据为输入。

## Why

R-PERF-05 规定四份数据集，但仓库里只有一份生成脚本，且只写 CSV。1 GB Parquet、1000 万行 Parquet、20 MB 三表 xlsx 一直没有生成入口，bench-data/ 里也从来没有过 Parquet 文件。结果是：

- R-PERF-05 的三条验收全是空的，README 里「1 GB Parquet 打开 1.76 秒」「1000 万行 0.028 秒」这些数字没有可复现的来源。
- 别人 clone 下来跑 bench.sh，只能测到 500MB CSV 一份，剩下三份要自己造。
- 本机没有 duckdb 命令行，python 也没有 duckdb 包，想把 CSV 转 Parquet 没有现成工具。

现在补，是因为后面几个性能条目（R-PERF-02 转换耗时、R-PERF-06 内存）都要用这几份数据，数据先立住才好继续。

## What Changes

- 重写 `scripts/make-bench-data.sh`：一条命令生成四份规定数据集，附带 wide-100k.csv、gbk-sample.csv 两份小样本。已有的文件默认跳过，`FORCE=1` 重建，`BENCH_OUT` 可换输出目录。
- Parquet 不再依赖外部命令行，改用应用自己的导出通道（`TableWorkbenchBench --export-parquet`）。同一份代码写出来的 Parquet，测的就是这条读路径。
- xlsx 手写 zip + XML，三个工作表，含合并单元格，公式不写缓存值，正好覆盖「公式取不到值就留空」的行为。
- `TableWorkbenchBench` 新增 `--export-parquet` / `--export-csv` 两个参数。
- `scripts/bench.sh` 在跑计时前先打印数据集清单：文件名、大小、行数、列数。
- 勾 R-PERF-05 三条验收，把实测数字写进 08-performance.md 和 docs/bench-history.md。

## Capabilities

### New Capabilities

- `bench-datasets`：基准数据的生成契约——四份规定数据是什么、由谁生成、不许进 Git、清单怎么输出。

### Modified Capabilities

无。已有的 scroll-bench 只管滚动怎么量，不涉及数据从哪来。

## Impact

- `scripts/make-bench-data.sh`：重写，489 行。
- `scripts/bench.sh`：加数据清单，加一段 10m.parquet 冷读。
- `app/Sources/TableWorkbenchBench/main.swift`：加两个导出参数，加一个导出分支。
- `docs/requirements/08-performance.md`、`docs/requirements/README.md`、`docs/bench-history.md`：验收与实测记录。
- bench-data/ 已经在 .gitignore 里，产物不进仓库。磁盘占用约 3.2 GB。

## 性能与只读

不碰应用运行时。脚本只在 bench-data/ 里写文件，导出走 DuckDB 的 COPY，读的是源文件，不修改原文件。

CSV 转 Parquet 的耗时记进 bench-history（500MB 1.2 秒、1GB 3.1 秒、10m 6.0 秒），但不作为 R-PERF-02 的结论——那条要算进程启动和编码探测，是另一回事。

## 不做什么

- 不用真实用户数据。全部是脚本生成的随机业务数据。
- 不引入 duckdb 命令行、parquet-tools 之类的额外依赖。
- 不为了凑「500 MB 约 800 万行」这个数字去删列或缩短字段。实测 500 MB 只有 326.6 万行，照实写。
- 不做增量更新：数据要么已有跳过，要么整个重写。

