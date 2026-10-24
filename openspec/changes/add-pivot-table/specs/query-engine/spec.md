# Spec Delta

## Purpose

描述透视如何被翻译成条件聚合 SQL，以及结果如何返回。

## ADDED Requirements

### Requirement: 条件聚合

透视 SHALL 使用 GROUP BY 加条件聚合生成交叉表。每个列维度取值 SHALL 变成一个条件列。

#### Scenario: 两个列值
- **WHEN** 列维度有华东和华南两个取值
- **THEN** SQL 生成两个 SUM(CASE WHEN ...) 列，列名包含取值

#### Scenario: 没有列维度
- **WHEN** 只配置行和值
- **THEN** SQL 只包含 GROUP BY 和聚合，不生成条件列

### Requirement: 返回结构一致

透视结果 SHALL 复用 SQL 结果的列、行、行数和耗时结构，列顺序为行维度在前、聚合列在后。

#### Scenario: 列顺序
- **WHEN** 行维度是区域和渠道
- **THEN** 结果前两列是区域、渠道，后面才是聚合值
