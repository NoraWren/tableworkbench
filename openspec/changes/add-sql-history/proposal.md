# Proposal

## Why

SQL 抽屉现在每次都要重新敲。用户常见的动作是改一下上一条查询再跑，或者翻回几天前的那条。R-SQL-04 要求本地历史。

## What Changes

- 每次执行成功的 SQL 记入本地历史，最多 200 条。
- 连续重复的语句不重复记录；同一条旧语句再次执行时移到最前。
- SQL 抽屉里提供“历史”入口，可搜索、点击回填到编辑器。
- 历史只存本机 UserDefaults，不上传、不进日志。

## Capabilities

### New Capabilities

- sql-console：SQL 历史。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- Features 增加 SQLHistoryStore。
- SQL 抽屉增加历史按钮与列表。
- 测试覆盖记录、上限、去重、搜索、清空、持久化。

## 不做什么

- 不做命名片段（snippets），也不做云端同步。
- 不记录失败的语句。
- 不做语法高亮或格式化。

## 性能与只读

200 条历史占几十 KB，读取和搜索在毫秒级。历史只记录 SQL 文本，不记录结果数据。
