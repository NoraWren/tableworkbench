# Design

## Context

见 proposal.md。已有 SQLHistoryStore 用 UserDefaults 存历史。片段可以复用同样的存储模式，但按名字去重而不是按时间。

## Goals / Non-Goals

**Goals:**

- 命名保存、覆盖、删除、回填。
- 本地持久化。
- 侧栏可见。

**Non-Goals:**

- 分组、导入导出、参数化。

## Decisions

### D1 独立 SQLSnippetStore

与历史分开存，key 为 sqlSnippets。结构是 id/name/sql/date 的数组，按名字大小写不敏感去重。

### D2 保存时覆盖同名

保存前删除同名条目，再插到最前，保证列表反映最近使用。

### D3 侧栏只读展示

侧栏列出片段名，点击回填并展开 SQL 抽屉；删除放在片段行的上下文菜单或删除按钮上。

### D4 上限 200

与历史一致，避免无限增长。

## Risks / Trade-offs

- [片段名重复但大小写不同] → 按大小写不敏感去重。
- [SQL 含敏感值] → 只存本机，可删除。

## Migration Plan

新增功能，没有数据迁移。

## Open Questions

无。
