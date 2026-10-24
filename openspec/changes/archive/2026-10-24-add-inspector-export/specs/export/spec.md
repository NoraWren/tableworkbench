# Spec Delta

## Purpose

描述如何把当前视图导出成 CSV 或 Parquet，以及导出范围和文件安全如何保证。

## ADDED Requirements

### Requirement: 导出当前视图

用户 SHALL 能把当前视图导出为 CSV 或 Parquet。当前视图 SHALL 包含生效的筛选和排序，SHALL NOT 包含隐藏列。

#### Scenario: 导出 CSV
- **WHEN** 用户导出筛选后的 4 行
- **THEN** 文件只有 4 行数据，列顺序与表格一致

#### Scenario: 导出 Parquet
- **WHEN** 用户选择 Parquet
- **THEN** 文件能被 DuckDB 读回，行数和类型一致

### Requirement: 文件安全

导出 SHALL 先写临时文件，成功后再改名为目标文件。失败或取消时 SHALL NOT 留下半截文件。

#### Scenario: 写入失败
- **WHEN** 目标目录没有写权限
- **THEN** 报错，目标位置不出现文件

### Requirement: 中文与编码

CSV 导出 SHALL 使用 UTF-8 编码，打开后中文不乱码。

#### Scenario: 中文 CSV
- **WHEN** 导出的数据含中文列名和中文内容
- **THEN** 用 Excel 或文本编辑器打开都不乱码
