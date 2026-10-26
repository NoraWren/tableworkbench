# Spec Delta

## Purpose

描述执行过的 SQL 如何被记录、去重、搜索和清除，以及历史如何持久化。

## ADDED Requirements

### Requirement: 记录执行过的 SQL

每次 SQL 执行成功后，应用 SHALL 把语句文本记入本地历史，最新的在最前。

#### Scenario: 执行两条
- **WHEN** 用户依次执行 SELECT 1 和 SELECT 2
- **THEN** 历史第一条是 SELECT 2，第二条是 SELECT 1

#### Scenario: 失败不记录
- **WHEN** 用户执行一条语法错误的 SQL
- **THEN** 历史不新增

### Requirement: 去重与上限

同一条语句再次执行 SHALL 移到最前，SHALL NOT 产生重复条目。历史最多保留 200 条，超出淘汰最旧的。

#### Scenario: 重复执行
- **WHEN** 用户再次执行历史里已有的 SELECT 1
- **THEN** SELECT 1 移到第一条，总数不变

#### Scenario: 超过 200 条
- **WHEN** 用户执行第 201 条不同的 SQL
- **THEN** 最旧的一条被移除，总数保持 200

### Requirement: 搜索与回填

历史面板 SHALL 支持按关键词搜索，点击条目 SHALL 把语句填回编辑器。

#### Scenario: 搜索
- **WHEN** 用户在历史里搜 group
- **THEN** 只显示包含 group 的语句

#### Scenario: 回填
- **WHEN** 用户点击一条历史
- **THEN** 编辑器内容变成该语句，可以直接运行

### Requirement: 清除与持久化

历史 SHALL 在重启后保留。用户 SHALL 能一键清空历史。

#### Scenario: 重启
- **WHEN** 用户重启应用
- **THEN** 之前的历史仍在

#### Scenario: 清空
- **WHEN** 用户点击清空历史
- **THEN** 列表为空，重启后仍为空
