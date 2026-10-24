# Specification Delta

## ADDED Requirements

### Requirement: 打开 Parquet 文件

应用 SHALL 支持直接打开 .parquet 文件，跳过文本编码探测与缓存转换。

#### Scenario: 打开导出的 Parquet

- **WHEN** 用户打开一个由应用导出的 .parquet 文件
- **THEN** 表格显示与导出前一致的行数和列名，侧栏来源类型显示 Parquet
