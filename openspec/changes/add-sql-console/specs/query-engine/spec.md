# Spec Delta

## Purpose

描述执行用户 SQL 时如何提供稳定的数据视图、如何限制结果规模，以及返回什么结构。

## ADDED Requirements

### Requirement: 稳定的 data 视图

打开文件后，应用 SHALL 提供名为 data 的视图，内容为文件全量数据，不受网格当前排序和筛选影响。

#### Scenario: 查询 data
- **WHEN** 用户执行 SELECT count(*) FROM data
- **THEN** 返回文件总行数，即使网格正在筛选

### Requirement: 执行用户 SQL 并返回结构

执行入口 SHALL 返回列名、行数据、返回行数、耗时和是否截断。列顺序 SHALL 与查询一致。

#### Scenario: 分组聚合
- **WHEN** 用户执行按区域分组的金额求和
- **THEN** 返回两列，行数等于区域数，数值与网格筛选结果一致

#### Scenario: 结果列顺序
- **WHEN** 用户执行 SELECT 金额, 区域 FROM data LIMIT 1
- **THEN** 返回的列先是金额，再是区域

### Requirement: 结果规模上限

执行 SHALL 在用户 SQL 外层加 100001 行的上限，返回最多 100000 行，并用标志位说明是否被截断。

#### Scenario: 超过上限
- **WHEN** 用户 SQL 会返回 20 万行
- **THEN** 返回 100000 行且 truncated 为 true
