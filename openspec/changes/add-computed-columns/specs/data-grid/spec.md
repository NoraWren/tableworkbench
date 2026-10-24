# Spec Delta

## Purpose

描述如何添加计算列、如何校验表达式，以及计算列的显示和生命周期。

## ADDED Requirements

### Requirement: 添加计算列

用户 SHALL 能输入列名和 SQL 表达式添加计算列。列名不能与已有列重复。表达式 SHALL 先经过只读校验和一次试算，失败时不添加列。

#### Scenario: 添加税率列
- **WHEN** 用户添加列名 tax_amount、表达式 amount * 0.06
- **THEN** 表格末尾出现新列，值等于金额乘 0.06

#### Scenario: 列名重复
- **WHEN** 用户用已有列名添加
- **THEN** 提示列名已存在，不添加

#### Scenario: 表达式错误
- **WHEN** 用户输入 amount * 
- **THEN** 显示表达式错误，不出现空列

### Requirement: 计算列的生命周期

计算列 SHALL 只存在于当前会话，关闭文件后消失，重启应用不恢复。

#### Scenario: 关闭再打开
- **WHEN** 用户添加计算列后关闭文件再打开同一文件
- **THEN** 计算列不存在

### Requirement: 计算列不参与分析接口

计算列 SHALL NOT 出现在列检查器、透视字段、导出列和 SQL 的 data 视图里。

#### Scenario: 导出
- **WHEN** 添加计算列后导出 CSV
- **THEN** 文件只有原始列，没有计算列
