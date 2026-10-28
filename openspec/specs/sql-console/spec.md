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

### Requirement: 记录执行过的 SQL

每次 SQL 执行成功后，应用 SHALL 把语句文本记入本地历史，最新的在最前。

#### Scenario: 执行两条
- **WHEN** 用户依次执行 SELECT 1 和 SELECT 2
- **THEN** 历史第一条是 SELECT 2，第二条是 SELECT 1

#### Scenario: 失败不记录
- **WHEN** 用户执行一条语法错误的 SQL
- **THEN** 历史不新增

### Requirement: 去重与上限

同一条语句再次执行 SHALL 移到最前，SHALL NOT 产生重复条目。历史最多保留 200 条，超出淘汰最旧的。

#### Scenario: 重复执行
- **WHEN** 用户再次执行历史里已有的 SELECT 1
- **THEN** SELECT 1 移到第一条，总数不变

#### Scenario: 超过 200 条
- **WHEN** 用户执行第 201 条不同的 SQL
- **THEN** 最旧的一条被移除，总数保持 200

### Requirement: 搜索与回填

历史面板 SHALL 支持按关键词搜索，点击条目 SHALL 把语句填回编辑器。

#### Scenario: 搜索
- **WHEN** 用户在历史里搜 group
- **THEN** 只显示包含 group 的语句

#### Scenario: 回填
- **WHEN** 用户点击一条历史
- **THEN** 编辑器内容变成该语句，可以直接运行

### Requirement: 清除与持久化

历史 SHALL 在重启后保留。用户 SHALL 能一键清空历史。

#### Scenario: 重启
- **WHEN** 用户重启应用
- **THEN** 之前的历史仍在

#### Scenario: 清空
- **WHEN** 用户点击清空历史
- **THEN** 列表为空，重启后仍为空

### Requirement: 保存片段

用户 SHALL 能把当前 SQL 以名字保存为片段。名字或语句为空时 SHALL 拒绝。同名片段 SHALL 覆盖旧内容。

#### Scenario: 保存新片段
- **WHEN** 用户把 SELECT ... 保存为“每月毛利”
- **THEN** 侧栏出现“每月毛利”，点击后编辑器填入该语句

#### Scenario: 同名覆盖
- **WHEN** 用户再次保存“每月毛利”但语句不同
- **THEN** 列表仍只有一条，内容是新的

### Requirement: 回填与删除

点击片段 SHALL 把语句填回 SQL 编辑器，SHALL NOT 自动执行。用户 SHALL 能删除片段。

#### Scenario: 回填
- **WHEN** 用户点击片段
- **THEN** 编辑器内容变成片段语句，SQL 抽屉展开

#### Scenario: 删除
- **WHEN** 用户删除片段
- **THEN** 侧栏不再显示，重启后也不在

### Requirement: 持久化

片段 SHALL 在重启后保留。

#### Scenario: 重启
- **WHEN** 用户重启应用
- **THEN** 片段列表与名称不变

### Requirement: 有选区时只运行选中语句

编辑器里存在非空选区时，运行命令 SHALL 只执行选区内的文本；选区为空时 SHALL 执行整篇文本。执行后进入历史的 SHALL 是实际执行的那段文本。

#### Scenario: 抽屉里放两条语句只跑其中一条
- **WHEN** 编辑器里是两行 SQL，用户选中第一行后按 Command+R
- **THEN** 只执行第一行，结果区与历史里都是这条语句

#### Scenario: 没有选区时跑全篇
- **WHEN** 编辑器里是两行 SQL，光标在末尾没有选区，用户按 Command+R
- **THEN** 整篇文本被送去执行
