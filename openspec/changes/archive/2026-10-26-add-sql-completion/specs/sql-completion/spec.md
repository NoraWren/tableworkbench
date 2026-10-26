# Spec Delta

## Purpose

描述 SQL 编辑器在输入表名、列名前缀时的候选行为，以及哪些情况下不该弹。

## ADDED Requirements

### Requirement: 按前缀弹候选

用户敲出词前缀后，编辑器 SHALL 在光标附近弹出候选列表。前缀为空时 SHALL NOT 弹。

#### Scenario: 输入 sel
- **WHEN** 用户在空编辑器里敲 `sel`
- **THEN** 候选列表出现，`SELECT` 排在第一位，原文本不变

#### Scenario: 只敲了一个空格
- **WHEN** 光标前是空格
- **THEN** 不弹候选

### Requirement: 按语境决定补什么

`FROM`、`JOIN` 等取表名的位置之后 SHALL 只给表名；`表名.` 之后 SHALL 只给这张表的列；其他位置 SHALL 混合给出关键字与列名。

#### Scenario: FROM 之后
- **WHEN** 用户输入 `SELECT * FROM da`
- **THEN** 候选里有 `data`，没有列名

#### Scenario: 表名限定之后
- **WHEN** 用户输入 `SELECT data.金`
- **THEN** 候选只有 `金额`

#### Scenario: 未知表名限定
- **WHEN** 用户输入 `SELECT nope.金`
- **THEN** 不弹候选

### Requirement: 键盘接受

候选可见时，Tab、回车、上、下与 Esc SHALL 归候选面板使用；候选不可见时这些键 SHALL 保持原行为。

#### Scenario: Tab 接受
- **WHEN** 候选里 `SELECT` 高亮，用户按 Tab
- **THEN** 编辑器内容变成 `SELECT`，候选收起

#### Scenario: Esc 关闭
- **WHEN** 候选可见，用户按 Esc
- **THEN** 候选收起，文本不变

#### Scenario: 回车正常换行
- **WHEN** 候选不可见，用户按回车
- **THEN** 光标换到下一行

### Requirement: 字面量与注释里不打扰

光标在字符串字面量或 `--` 注释里时，编辑器 SHALL NOT 弹候选。

#### Scenario: 写在引号里
- **WHEN** 用户输入 `WHERE 城市 = '杭` 且光标在引号后
- **THEN** 不弹候选

#### Scenario: 写在注释里
- **WHEN** 用户输入 `-- 这是注释` 且光标在行内
- **THEN** 不弹候选

### Requirement: 接受后不重复弹同名

候选接受后，如果前缀正好等于该候选，SHALL NOT 再把它列为候选。

#### Scenario: 接受 SELECT 之后
- **WHEN** 用户接受 `SELECT`，光标停在词尾
- **THEN** 候选收起且不再重开，Tab 仍能切焦点

