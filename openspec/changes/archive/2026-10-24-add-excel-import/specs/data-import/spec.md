# Spec Delta

## Purpose

描述 xlsx 如何被读取、单元格值如何转换、缓存如何命中，以及哪些内容不被支持。

## ADDED Requirements

### Requirement: 读取第一个工作表

打开 .xlsx 时，应用 SHALL 读取第一个工作表，并把第一行作为表头。列名和顺序 SHALL 与工作表一致。

#### Scenario: 单工作表
- **WHEN** 用户打开一个两行三列的 xlsx
- **THEN** 表格显示两行数据，列名来自第一行

#### Scenario: 多工作表
- **WHEN** 文件有三个工作表
- **THEN** 默认导入第一个工作表，其余不出现

### Requirement: 单元格值转换

单元格 SHALL 按类型转成文本：共享字符串和行内字符串原样保留，数字保留原始精度，布尔显示为 TRUE/FALSE。公式单元格 SHALL 取缓存值，缓存值缺失时留空。合并单元格 SHALL 只保留左上角的值。

#### Scenario: 公式单元格
- **WHEN** 单元格是 =SUM(A1:A3) 且文件里有缓存值 6
- **THEN** 表格显示 6

#### Scenario: 空单元格
- **WHEN** 某一行中间有一个空单元格
- **THEN** 该位置显示为 NULL，不导致列错位

### Requirement: xlsx 缓存

xlsx 的 Parquet 缓存 SHALL 以原文件和工作表名作为键。第二次打开同一个工作表 SHALL 直接读缓存。

#### Scenario: 二次打开
- **WHEN** 用户再次打开同一个 xlsx
- **THEN** 从缓存读取，打开时间不超过 2 秒

### Requirement: 错误处理

文件损坏、不是 xlsx、没有工作表时 SHALL 给出可读错误，不崩溃，也不在左栏留下条目。

#### Scenario: 损坏的文件
- **WHEN** 用户把一个文本文件改名成 .xlsx 打开
- **THEN** 提示无法解析工作簿，左栏不新增条目
