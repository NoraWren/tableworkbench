# Spec Delta

## Purpose

描述命名片段如何保存、覆盖、展示、回填和删除。

## ADDED Requirements

### Requirement: 保存片段

用户 SHALL 能把当前 SQL 以名字保存为片段。名字或语句为空时 SHALL 拒绝。同名片段 SHALL 覆盖旧内容。

#### Scenario: 保存新片段
- **WHEN** 用户把 SELECT ... 保存为“每月毛利”
- **THEN** 侧栏出现“每月毛利”，点击后编辑器填入该语句

#### Scenario: 同名覆盖
- **WHEN** 用户再次保存“每月毛利”但语句不同
- **THEN** 列表仍只有一条，内容是新的

### Requirement: 回填与删除

点击片段 SHALL 把语句填回 SQL 编辑器，SHALL NOT 自动执行。用户 SHALL 能删除片段。

#### Scenario: 回填
- **WHEN** 用户点击片段
- **THEN** 编辑器内容变成片段语句，SQL 抽屉展开

#### Scenario: 删除
- **WHEN** 用户删除片段
- **THEN** 侧栏不再显示，重启后也不在

### Requirement: 持久化

片段 SHALL 在重启后保留。

#### Scenario: 重启
- **WHEN** 用户重启应用
- **THEN** 片段列表与名称不变
