# Design

## Context

见 proposal.md。现有链路是 FileImporter 判断扩展名，CSV 走 read_csv_auto，Parquet 缓存命中走 openParquet。xlsx 需要先变成一种现有链路能吃的格式。

## Goals / Non-Goals

**Goals:**

- 正确读出第一个工作表的值。
- 复用现有物化、分块、SQL 和缓存。
- 转换失败有清晰错误。

**Non-Goals:**

- 格式和公式重算。
- 多表同时导入。
- 图片、图表、批注。

## Decisions

### D1 用 CoreXLSX，不联网装 DuckDB 扩展

CoreXLSX 是 Apache-2.0 的 Swift 包，离线可用，带 ZIPFoundation。DuckDB 的 excel 扩展需要 INSTALL，离线不可靠。

### D2 xlsx 先转临时 CSV

XLSXConverter 输出 UTF-8、逗号分隔、首行表头的临时 CSV，然后复用 FileImporter 的 CSV 路径。这样编码、类型推断、物化、缓存全部不用重写。

备选：直接写 Parquet。需要自己处理类型映射，收益只是省一次 CSV 写入。

### D3 缓存键加入工作表名

variant 用 "xlsx:<工作表名>"，避免同一文件不同工作表互相覆盖。

### D4 临时 CSV 由缓存任务负责删除

转换是后台的，FileImporter 不能在返回前删临时文件。ParquetCache 增加 cleanupAfterConversion，转换完成或失败后删除。

### D5 日期先按原始值输出

DuckDB 的 CSV 读取会推断日期。CoreXLSX 的日期解析依赖样式，先输出单元格原始值；如果样式明确是日期，再格式化成 ISO。先保证不丢数据。

### D6 单元格上限保护

单表超过 100 万单元格时拒绝并提示，避免一个异常文件把内存打满。

## Risks / Trade-offs

- [CoreXLSX 最后更新 2023 年] → 只读值，不依赖冷门 API；出问题可以换自写解析。
- [CoreXLSX 的 Codable 解析太慢] → 实测 19.9 万行超过 2 分 30 秒，改成 ZIPFoundation 解压 + XMLParser 流式写 CSV，降到 7.23 秒。CoreXLSX 只保留工作表发现。
- [大 xlsx 内存占用] → 逐行写 CSV，不把整表放内存；单元格上限保护。
- [日期和数字格式丢失] → 先保原始值，格式化后续再做。
- [工作表选择缺失] → 引擎支持 sheetName，界面后续补。

## Migration Plan

新增格式支持，没有数据迁移。回滚删除 xlsx 分支和 CoreXLSX 依赖。

## Open Questions

无。
