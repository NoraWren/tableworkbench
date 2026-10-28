# Spec Delta

## Purpose

给 `sql-console` 补一条运行语义：编辑器里有选区时只执行选中那一段。补全、历史、只读边界都不变。

## ADDED Requirements

### Requirement: 有选区时只运行选中语句

编辑器里存在非空选区时，运行命令 SHALL 只执行选区内的文本；选区为空时 SHALL 执行整篇文本。执行后进入历史的 SHALL 是实际执行的那段文本。

#### Scenario: 抽屉里放两条语句只跑其中一条
- **WHEN** 编辑器里是两行 SQL，用户选中第一行后按 Command+R
- **THEN** 只执行第一行，结果区与历史里都是这条语句

#### Scenario: 没有选区时跑全篇
- **WHEN** 编辑器里是两行 SQL，光标在末尾没有选区，用户按 Command+R
- **THEN** 整篇文本被送去执行
