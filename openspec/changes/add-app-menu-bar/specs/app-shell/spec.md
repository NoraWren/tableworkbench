# Specification Delta

## Purpose

描述应用菜单栏的结构、快捷键，以及菜单项在无可用对象时如何置灰。

## ADDED Requirements

### Requirement: 文件与查询菜单

应用 SHALL 在菜单栏提供「文件」与「查询」两组菜单。文件菜单包含打开文件、导出、关闭文件；查询菜单包含运行、取消、新建查询。

#### Scenario: 没有打开文件

- **WHEN** 应用没有打开任何文件
- **THEN** 导出、关闭文件、运行、新建查询都置灰，只有打开文件可用

#### Scenario: 打开文件后运行查询

- **WHEN** 用户打开一个 CSV 并按 Command+R
- **THEN** 执行 SQL 抽屉里的语句，结果进入查询结果视图

### Requirement: 视图菜单与侧栏记忆

应用 SHALL 在视图菜单提供侧栏、检查器、SQL 抽屉三个开关，并把折叠状态持久化。

#### Scenario: 重启后恢复折叠

- **WHEN** 用户隐藏侧栏后退出并重新打开应用
- **THEN** 侧栏仍保持折叠
