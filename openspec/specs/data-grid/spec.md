# data-grid Specification

## Purpose
描述数据网格在单表列数超过上限时如何裁剪显示、如何按可见列取数，以及用户如何从检查器逐列启用其余列并保持原顺序。

## Requirements

### Requirement: 宽表按可见列取数

系统 SHALL 在单表列数超过 2000 时只向查询引擎取前 200 列，且返回的列顺序与界面显示一致。

#### Scenario: 打开 3000 列的 CSV

- **WHEN** 用户打开 3000 列的 CSV
- **THEN** 表格显示前 200 列，单元格有值，不出现整表 NULL，界面可继续滚动

#### Scenario: 普通表不受影响

- **WHEN** 用户打开 20 列的表
- **THEN** 全部列正常显示，取块仍返回 20 列

### Requirement: 宽表列可逐列启用

系统 SHALL 在列数超过 2000 时只显示前 200 列，并允许用户从检查器逐列启用其余列，启用后按原顺序追加。

#### Scenario: 启用第 2100 列

- **WHEN** 用户打开 3000 列的表，并在检查器点开第 2100 列的眼睛按钮
- **THEN** 表格显示 201 列，第 2100 列出现在最后，单元格有值

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
