## ADDED Requirements

### Requirement: 中断残留不得永久堆积

转换过程中产生的临时文件 MUST 在转换失败时立即删除，并在下次启动时清扫超过 1 小时的过期残留。

缓存占用的统计与容量淘汰 MUST 把临时文件计入，临时文件不得绕过缓存上限。

#### Scenario: 转换失败
- **WHEN** 一次转换因为磁盘写入错误中断
- **THEN** 该次留下的临时文件被删除，缓存目录不留 .parquet.tmp

#### Scenario: 上次被杀留下的残留
- **WHEN** 应用启动时缓存目录里有修改时间超过 1 小时的 .parquet.tmp
- **THEN** 这些文件被删除，修改时间在 1 小时内的保留

#### Scenario: 临时文件计入容量
- **WHEN** 缓存目录里既有 .parquet 也有 .parquet.tmp
- **THEN** 容量统计把它们加在一起，超过上限时按最后修改时间从旧到新淘汰
