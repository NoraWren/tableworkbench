# Proposal

## Why

同一个 500MB CSV 每次打开都要重新解析，实测 2 秒左右；重复打开是高频操作，R-IMP-05 要求第二次打开 1 秒级。缓存还能给后面的 Excel 导入兜底：先转 Parquet，再统一走列式读取。

## What Changes

- 首次打开 CSV/TSV 后，后台把它转成 Parquet，写到 Application Support/TableWorkbench/cache。
- 缓存文件名由路径、大小、修改时间、格式版本算哈希，文件变化自动失效。
- 第二次打开同一个文件直接读 Parquet，并跳过 CSV 解析。
- 缓存上限 10GB，超出按最后访问时间淘汰。
- 写缓存先写临时文件再原子改名，中途退出不会留下半截文件。
- 转换失败不影响当前会话，只记录日志。

## Capabilities

### New Capabilities

- data-import：Parquet 缓存的生成、命中、失效与淘汰。
- query-engine：从 Parquet 物化基础表。

### Modified Capabilities

无。openspec/specs 尚未归档，这里追加新的 requirement。

## Impact

- 新增 ParquetCache 与后台转换任务。
- FileImporter 增加缓存命中分支。
- DuckDBSession 增加从 Parquet 打开。
- 磁盘多占一份缓存，需要容量管理。

## 不做什么

- 不做 Excel，单独一个 change。
- 不加密缓存，不做跨机器迁移。
- 不做缓存管理界面，先自动淘汰。

## 性能与只读

首次打开仍不超过 3 秒，转换在后台；第二次打开目标 1.5 秒内。源文件只读，缓存是派生文件，删除后只影响速度不影响正确性。
