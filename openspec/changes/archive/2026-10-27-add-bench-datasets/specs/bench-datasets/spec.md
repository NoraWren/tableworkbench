## ADDED Requirements

### Requirement: 四份固定数据集

项目 SHALL 提供一条命令，在空目录里生成 R-PERF-05 规定的四份基准数据：500 MB 级 CSV、1 GB 级 Parquet、1000 万行 × 20 列 Parquet、20 MB 级三工作表 xlsx。

生成 MUST 不依赖外部 duckdb 命令行或其他未在 Package.swift 里声明的工具，只使用系统 python3 与应用自身的导出通道。

#### Scenario: 空目录一键生成
- **WHEN** 删掉 bench-data/ 后执行 `./scripts/make-bench-data.sh`
- **THEN** 四份规定数据集全部生成，脚本正常退出，末尾打印每份文件的大小

#### Scenario: 已有文件不重复生成
- **WHEN** 在已经生成过的目录里再跑一次
- **THEN** 每个已有文件打印「跳过（已存在）」，不重写；`FORCE=1` 时全部重写

#### Scenario: 换输出目录
- **WHEN** 用 `BENCH_OUT=/tmp/foo` 执行
- **THEN** 所有产物落在 /tmp/foo，仓库里的 bench-data/ 不受影响

### Requirement: 数据集在基准输出里自证

`scripts/bench.sh` SHALL 在跑任何计时之前打印数据集清单，每行包含文件名、大小、行数、列数。

行数与列数 MUST 来自实际文件，不许写死在脚本里。

#### Scenario: 跑基准先看数据
- **WHEN** 执行 `./scripts/bench.sh`
- **THEN** 输出里先出现一张表，列出每份数据集的大小、行数、列数

#### Scenario: 数据缺了
- **WHEN** 某份数据集不存在
- **THEN** 清单里那一行标「缺失」，脚本不因此报错退出

### Requirement: 基准数据不进仓库

bench-data/ MUST 列在 .gitignore 里，生成物不进 Git。

#### Scenario: 检查暂存区
- **WHEN** 生成数据后执行 `git status`
- **THEN** bench-data/ 下的文件不出现在未跟踪列表里

### Requirement: xlsx 覆盖脏数据特征

生成的 xlsx MUST 包含三个工作表，并至少含一处合并单元格区间与一批只有公式、没有缓存值的单元格。

公式单元格在导入后 MUST 留空，不许编造计算值。

#### Scenario: 导入生成的 xlsx
- **WHEN** 用 XLSXConverter 读取 sample-20mb.xlsx 的「数据」表
- **THEN** 三张表都能被枚举出来，公式所在的金额、折扣两列是空值

#### Scenario: 单表不超上限
- **WHEN** 生成 xlsx
- **THEN** 任何一张表的单元格数低于 XLSXConverter.maxCells，不会触发「这张表太大了」

