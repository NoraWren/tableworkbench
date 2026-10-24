# Spec Delta

## Purpose

描述多工作表 xlsx 打开时如何让用户选择要导入的工作表。

## ADDED Requirements

### Requirement: 工作表选择

打开含多个工作表的 xlsx 时，应用 SHALL 弹出工作表选择器。用户确认后只导入选中的一张；取消则不入库。

#### Scenario: 选择第二张表
- **WHEN** 文件有三张表，用户选择第二张
- **THEN** 表格显示第二张的数据，左栏文件名带工作表名

#### Scenario: 取消选择
- **WHEN** 用户在选择器里点取消
- **THEN** 不新增文件，不报错

#### Scenario: 单工作表
- **WHEN** 文件只有一张表
- **THEN** 不弹选择器，直接导入
