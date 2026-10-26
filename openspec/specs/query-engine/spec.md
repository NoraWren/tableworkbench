# query-engine Specification

## Purpose

描述打开文件后基础数据以什么形式存在（CSV 物化成表，Parquet 小表物化、大表留作视图），内部行号怎么分配与使用，排序筛选结果如何物化，以及 data 视图对外暴露哪些列。

## Requirements

### Requirement: 从 Parquet 读取基础数据

缓存命中时，应用 SHALL 从 Parquet 读取基础数据，并保持与 CSV 路径相同的列名、列顺序和行序。行数 × 列数不超过 2000 万时 SHALL 物化成表，超过时 SHALL 保留为视图，取块改用 file_row_number 区间过滤。

#### Scenario: 缓存打开的行列一致
- **WHEN** 同一个文件分别通过 CSV 和缓存打开
- **THEN** 列名、列数、总行数和首行内容一致

#### Scenario: 分块可用
- **WHEN** 从 Parquet 打开后请求第 100 块
- **THEN** 返回正确区间，耗时不超过 0.2 秒（1000 万行实测 0.057 秒）

#### Scenario: 打开不拷数据
- **WHEN** 打开 1000 万行、20 列的 Parquet 缓存
- **THEN** 打开耗时不超过 0.5 秒，不把整表拷进内存

### Requirement: data 视图保持一致

从缓存打开后，SQL 抽屉里的 data 视图 SHALL 仍然可用，内容与 CSV 路径一致。内部行号列 SHALL NOT 出现在 data 视图或列检查器里。

#### Scenario: 查询缓存数据
- **WHEN** 从缓存打开后执行 SELECT count(*) FROM data
- **THEN** 返回文件总行数

#### Scenario: 不暴露内部行号
- **WHEN** 从缓存的 Parquet 打开后执行 SELECT * FROM data
- **THEN** 结果列只有文件本身的列，不含内部行号

### Requirement: 基础数据物化并分配行号

打开文件后，应用 SHALL 把文件内容物化成本会话内的表，并分配从 1 开始、连续且唯一的行号。行号顺序 SHALL 与文件行序一致。

#### Scenario: 第一行与文件一致
- **WHEN** 用户打开一个首行为 A-000000001 的 CSV
- **THEN** 行号为 1 的记录内容就是该行

#### Scenario: 行号连续
- **WHEN** 文件有 1000 行
- **THEN** 行号范围为 1 到 1000，没有空洞和重复

### Requirement: 按行号区间取块

取块 SHALL 使用行号区间查询，不再使用 OFFSET。第 N 块 SHALL 返回行号 (N-1)*5000+1 到 N*5000 的记录，块之间不重叠、不遗漏。

#### Scenario: 读取第 100 块
- **WHEN** 应用请求第 100 块
- **THEN** 返回行号 495001 到 500000，耗时不超过 0.2 秒

#### Scenario: 最后一块不满
- **WHEN** 结果有 12003 行，请求第 3 块
- **THEN** 返回 2003 行，不报错

### Requirement: 排序筛选结果物化

排序或筛选变化时，应用 SHALL 把结果物化成带行号的临时表。之后的取块 SHALL 直接命中该表，不重新排序。

#### Scenario: 排序后取第 100 块
- **WHEN** 用户按金额降序排序后滚到第 100 块
- **THEN** 返回新顺序下的第 100 块，耗时不超过 0.5 秒

#### Scenario: 更换查询
- **WHEN** 用户从降序改为升序
- **THEN** 旧的临时表被删除，新结果重新物化，块内容是新顺序

### Requirement: 物化的资源边界

物化 SHALL NOT 修改源文件。500MB 文件打开时间 SHALL 不超过 3 秒，峰值内存 SHALL 不超过 1.5GB，关闭文件后内存 SHALL 回落。

#### Scenario: 打开 500MB 文件
- **WHEN** 用户打开 500MB CSV
- **THEN** 打开到可交互不超过 3 秒，峰值常驻内存不超过 1.5GB

#### Scenario: 关闭文件
- **WHEN** 用户关闭文件
- **THEN** 物化表被释放，连续开关 20 次内存回到基线附近

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
