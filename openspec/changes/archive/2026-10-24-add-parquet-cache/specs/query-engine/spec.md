# Spec Delta

## Purpose

描述从 Parquet 文件物化基础表时，如何保证与 CSV 路径一致的分块和数据语义。

## ADDED Requirements

### Requirement: 从 Parquet 物化基础表

缓存命中时，应用 SHALL 从 Parquet 创建基础表，并保持与 CSV 路径相同的列名、列顺序和行序。

#### Scenario: 缓存打开的行列一致
- **WHEN** 同一个文件分别通过 CSV 和缓存打开
- **THEN** 列名、列数、总行数和首行内容一致

#### Scenario: 分块可用
- **WHEN** 从 Parquet 打开后请求第 100 块
- **THEN** 返回正确区间，耗时不超过 0.2 秒

### Requirement: data 视图保持一致

从缓存打开后，SQL 抽屉里的 data 视图 SHALL 仍然可用，内容与 CSV 路径一致。

#### Scenario: 查询缓存数据
- **WHEN** 从缓存打开后执行 SELECT count(*) FROM data
- **THEN** 返回文件总行数
