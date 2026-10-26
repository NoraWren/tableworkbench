# sql-console Specification

## Purpose
描述 SQL 抽屉如何编辑和执行查询（Command+R 运行、补全、片段、历史回填），结果如何呈现（行数、耗时、千分位、截断提示、空结果占位），以及错误提示与只读边界如何处理。

## Requirements

### Requirement: 打开抽屉并运行查询

用户 SHALL 能从底部抽屉编辑 SQL，并用 Command+R 或运行按钮执行。执行中 SHALL 显示进行状态，结果 SHALL 包含列名、行数、耗时。

#### Scenario: 执行 SELECT
- **WHEN** 用户输入 SELECT * FROM data LIMIT 10 并运行
- **THEN** 结果区显示 10 行数据和列名，状态显示耗时

#### Scenario: 空结果
- **WHEN** 查询返回 0 行
- **THEN** 结果区显示"0 行"，不显示空白表格，也不报错

### Requirement: 结果上限与截断提示

单次查询结果 SHALL 最多保留 100000 行。超过时 SHALL 提示只显示前 100000 行，并说明可以加 LIMIT 或聚合。

#### Scenario: 大结果截断
- **WHEN** 查询返回 200000 行
- **THEN** 结果区显示 100000 行，并出现截断提示

### Requirement: 只读与错误呈现

SQL 抽屉 SHALL 只允许 SELECT、WITH、DESCRIBE、SUMMARIZE 和 CREATE TEMP。其他语句 SHALL 在执行前被拒绝。语法错误 SHALL 同时显示 DuckDB 原文和一句中文说明。

#### Scenario: 写语句被拒绝
- **WHEN** 用户执行 DROP TABLE data
- **THEN** 查询不发送给引擎，界面提示只读

#### Scenario: 语法错误
- **WHEN** 用户执行 SELEC * FROM data
- **THEN** 界面显示原始错误和中文说明，不崩溃

### Requirement: 查询不修改源文件

执行 SQL SHALL NOT 修改源文件，允许创建临时表和临时视图。

#### Scenario: 创建临时表
- **WHEN** 用户执行 CREATE TEMP TABLE t AS SELECT 1 AS a
- **THEN** 语句成功，随后可以查询 t，源文件哈希不变
