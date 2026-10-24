# query-engine Specification

## Purpose
描述从 CSV 或 Parquet 物化基础表时如何分配行号、如何按行号区间取块、排序筛选结果如何物化，以及资源边界是什么。

## Requirements

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
