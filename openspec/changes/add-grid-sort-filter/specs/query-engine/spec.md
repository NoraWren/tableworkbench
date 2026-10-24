# Spec Delta

## Purpose

描述排序与筛选如何被翻译成查询、如何保证块顺序一致，以及查询变化时缓存如何失效。

## ADDED Requirements

### Requirement: 查询描述下推

排序和筛选 SHALL 被翻译成 SQL 的 ORDER BY 和 WHERE 交给 DuckDB 执行，应用 SHALL NOT 在内存中对全量数据排序或过滤。

#### Scenario: 生成 ORDER BY
- **WHEN** 用户按"金额"降序、再按"区域"升序排序
- **THEN** 查询包含 ORDER BY 区域 ASC, 金额 DESC，返回顺序与之一致

#### Scenario: 生成 WHERE
- **WHEN** 用户添加"状态 不等于 已退款"和"金额 大于 100"
- **THEN** 查询包含两个条件的 WHERE，AND 组合时用 AND 连接，OR 组合时用 OR 连接

#### Scenario: 没有排序和筛选
- **WHEN** 用户没有设置任何排序和筛选
- **THEN** 查询不带 ORDER BY 和 WHERE，按文件原顺序返回

### Requirement: 查询变化使块缓存失效

排序或筛选变化后，已缓存的块 SHALL 全部失效，后续取块 SHALL 使用新的查询。

#### Scenario: 切换排序
- **WHEN** 用户把升序改为降序
- **THEN** 第一块返回的是降序后的前 5000 行，不出现旧顺序的残留

#### Scenario: 添加筛选
- **WHEN** 用户添加一个筛选条件
- **THEN** 总行数不变、结果行数更新，块缓存被清空

### Requirement: 筛选计数与分块一致

筛选后的结果行数 SHALL 与按块读取到的总行数一致，块之间 SHALL NOT 重复或遗漏。

#### Scenario: 分块读取筛选结果
- **WHEN** 筛选结果有 12000 行，依次读取第 0、1、2 块
- **THEN** 三块分别为 5000、5000、2000 行，首尾行与 count 查询一致

### Requirement: 值转义与只读

用户输入的筛选值 SHALL 被安全转义后再拼进 SQL。查询 SHALL 仍然只能读取，写语句 SHALL 被拒绝。

#### Scenario: 单引号值
- **WHEN** 筛选值是 O'Brien
- **THEN** 生成的 SQL 使用两个单引号转义，查询成功

#### Scenario: 写语句
- **WHEN** 查询描述里混入 DROP TABLE
- **THEN** SQLGuard 在发往 DuckDB 之前拒绝执行
