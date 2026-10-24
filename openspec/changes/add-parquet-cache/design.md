# Design

## Context

见 proposal.md。当前 FileImporter 每次调用 DuckDBSession.open(url:format:)，DuckDBSession 直接 read_csv_auto 再物化。打开 500MB 约 2 秒，全部花在解析和建表上。

## Goals / Non-Goals

**Goals:**

- 二次打开走 Parquet，时间明显下降。
- 缓存键可靠，文件改动不会读到旧数据。
- 写入原子，容量可控。

**Non-Goals:**

- Excel、加密、跨机器。
- 缓存管理界面。

## Decisions

### D1 缓存键用内容指纹

SHA256(绝对路径 + 文件大小 + 修改时间秒 + 缓存格式版本 v1)。不哈希文件内容，避免每次打开都全量读一遍。

备选：哈希内容。最可靠，但等于把文件读一遍，抵消缓存收益。

### D2 首次打开直接读 CSV，后台转 Parquet

不在打开路径里先转 Parquet 再读，否则首次打开会多一次全量读写。首次打开沿用现在的 CSV 物化，同时在独立连接里执行 COPY 到 Parquet。

### D3 后台转换用独立连接

ParquetCache 在 detached task 里建一个临时 in-memory Database，执行：

COPY (SELECT * FROM read_csv_auto(...)) TO 'cache.tmp' (FORMAT PARQUET, COMPRESSION ZSTD)

完成后再 rename 成正式文件名。与主会话的连接互不影响。

### D4 先写临时文件再改名

转换写 hash.parquet.tmp，成功后 FileManager.moveItem 到 hash.parquet。读取只认正式文件名，半截文件不会被命中。

### D5 命中时走 openParquet

DuckDBSession 增加 openParquet：CREATE TABLE "__base" AS SELECT * FROM read_parquet('...')，其余流程与 CSV 路径一致。列名和顺序由 Parquet 元数据决定，与 CSV 路径一致。

### D6 淘汰按最后访问时间

转换完成后扫描缓存目录，总量超过 10GB 时按 contentModificationDate 从旧到新删除。当前文件跳过。上限做成可注入属性，方便测试。

## Risks / Trade-offs

- [后台转换与主会话同时占内存] → 转换连接单独限制 256MB，转换完释放。
- [缓存目录增长] → 每次写入后执行淘汰。
- [文件修改时间精度不足] → 用秒级时间加文件大小，足够识别常见修改；极端同秒同大小改动无法识别，记录为已知限制。
- [Parquet 列类型与 CSV 推断不同] → 转换时直接 COPY CSV 的推断结果，类型保持一致。

## Migration Plan

新增缓存，没有数据迁移。回滚删除 ParquetCache 与 openParquet，FileImporter 回到纯 CSV。

## Open Questions

无。
