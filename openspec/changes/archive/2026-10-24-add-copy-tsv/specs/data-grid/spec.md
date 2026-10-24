# Spec Delta

## Purpose

描述选中行如何复制成 TSV，以及表头、空值和特殊字符如何处理。

## ADDED Requirements

### Requirement: 复制选区

表格获得焦点且存在选中行时，Command+C SHALL 把选中行复制为 TSV 文本，列顺序与表格一致。

#### Scenario: 复制三行
- **WHEN** 用户选中三行并按 Command+C
- **THEN** 剪贴板里是三行 TSV，粘贴到文本编辑器后每行一条记录

#### Scenario: 没有选中行
- **WHEN** 用户没有选中任何行就按 Command+C
- **THEN** 剪贴板不变，不报错

### Requirement: 表头开关

复制是否包含表头 SHALL 跟随设置里的"复制时包含表头"，默认包含。

#### Scenario: 关闭表头
- **WHEN** 用户关闭复制表头并复制两行
- **THEN** 剪贴板里只有两行数据，没有列名

### Requirement: 特殊字符与空值

含制表符、换行或引号的字段 SHALL 用双引号包裹并双写内部引号。NULL SHALL 复制为空字符串。

#### Scenario: 字段含制表符
- **WHEN** 某个值是 a<TAB>b
- **THEN** 剪贴板里该字段是带引号的 "a<TAB>b"，粘贴后不拆成两列

#### Scenario: 空值
- **WHEN** 某一行某列是 NULL
- **THEN** 该位置复制为空，不写 NULL 字样
