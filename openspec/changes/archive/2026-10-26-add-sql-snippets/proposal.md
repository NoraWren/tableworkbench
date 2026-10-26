# Proposal

## Why

历史是按时间排的，常用查询会被新语句冲下去。用户需要把"每月毛利"这种固定语句起个名字，随时点开。R-SQL-04 要求片段出现在侧栏。

## What Changes

- SQL 抽屉支持把当前语句存为命名片段。
- 同名片段再次保存时覆盖，不产生重复。
- 片段列在侧栏的“SQL 片段”分组，点击把语句填回编辑器。
- 片段存在本机 UserDefaults，可删除。

## Capabilities

### New Capabilities

- sql-console：命名 SQL 片段。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- Features 增加 SQLSnippetStore。
- SQL 抽屉增加“存为片段”。
- 侧栏增加片段列表。

## 不做什么

- 不做片段分组、导入导出、云端同步。
- 不做参数化片段。

## 性能与只读

片段只存 SQL 文本，数量不设硬上限但按 200 条截断。只读，不联网。
