# Spec Delta

## Purpose

描述应用如何以只读方式连接查询引擎、如何把本地文件变成可查询的数据源、查询结果如何分块返回，以及错误如何呈现。

## ADDED Requirements

### Requirement: 连接只读且不修改源文件

应用 SHALL 以只读方式打开数据库连接。任何写操作 SHALL 被拒绝，源文件的字节内容 SHALL 保持不变。

#### Scenario: 尝试执行写语句
- **WHEN** 用户或内部代码尝试执行 DROP、DELETE、INSERT、UPDATE 或 CREATE TABLE
- **THEN** 语句被拒绝并返回明确原因，源文件的哈希与操作前一致

### Requirement: 本地文件挂载为可查询的数据源

打开 CSV 或 TSV 后，应用 SHALL 把文件挂载为一个可查询的视图，视图的列名和类型 SHALL 与导入时的推断结果一致。

#### Scenario: 查询已打开的文件
- **WHEN** 应用对已打开的 CSV 执行 SELECT 查询
- **THEN** 返回的列名与界面显示一致，行数与文件数据行数一致

### Requirement: 查询结果按块返回

查询结果 SHALL 支持按偏移量分块读取，块大小 SHALL 为 5000 行。读取第 N 块 SHALL 返回对应的行区间，不重复也不遗漏。

#### Scenario: 读取第三块
- **WHEN** 应用请求第 3 块数据
- **THEN** 返回第 10001 到 15000 行，总行数信息与实际一致

### Requirement: 错误信息可读

查询失败时，应用 SHALL 同时给出 DuckDB 的原始错误和一句中文解释，并 SHALL NOT 让界面停留在加载状态。

#### Scenario: SQL 语法错误
- **WHEN** 一条查询存在语法错误
- **THEN** 界面显示原始错误、中文说明和出错位置，加载状态结束

### Requirement: 资源及时释放

关闭文件或退出应用时，应用 SHALL 释放在用的连接和结果集。连续打开和关闭大文件 SHALL NOT 造成内存持续增长。

#### Scenario: 连续打开关闭二十次
- **WHEN** 用户连续打开并关闭同一个 1GB 文件 20 次
- **THEN** 常驻内存回到基线附近，波动不超过 200MB
