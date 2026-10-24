# Spec Delta

## Purpose

描述文本列里数字与文本混杂时如何检测并提示。

## ADDED Requirements

### Requirement: 检测数字与文本混杂

文本列中如果有部分非空值能按数字解析、另一部分不能，检查器 SHALL 显示类型冲突提示，包含数字行数、非数字行数和最多两个反例。

#### Scenario: 混有横线
- **WHEN** 列里有 100、200、—、300 四个值
- **THEN** 提示 3 行是数字、1 行不是，反例显示 —

### Requirement: 不误报

纯文本列（没有数字值）和数值列 SHALL NOT 显示类型冲突提示。

#### Scenario: 纯文本
- **WHEN** 城市列只有上海、北京
- **THEN** 不显示类型冲突

#### Scenario: 数值列
- **WHEN** 金额列被推断为 DOUBLE
- **THEN** 不显示类型冲突
