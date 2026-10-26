# Design

## Context

见 proposal.md。SQL 抽屉的编辑器状态在 ContentView 的 SQLState 里，执行入口是 WorkspaceModel.runSQL。

## Goals / Non-Goals

**Goals:**

- 本地历史，重启保留。
- 去重、上限、搜索、回填。
- 不记录失败语句和结果数据。

**Non-Goals:**

- 命名片段、云同步、跨设备。

## Decisions

### D1 独立 SQLHistoryStore

Features 里放一个 ObservableObject，内部用 UserDefaults 存 JSON 数组。默认 key 是 sqlHistory，测试可注入 suite 和 key。

### D2 执行成功后记录

WorkspaceModel.runSQL 成功拿到结果后才调用 history.record。失败不记录，避免历史里全是错语句。

### D3 去重规则

同一条语句已存在时删除旧条目再插到最前，保证不重复且顺序反映最近使用。

### D4 上限 200

插入后截断到 200，不额外做后台清理。

### D5 面板放在 SQL 抽屉

SQL 抽屉里加“历史”按钮，popover 里搜索框、列表、清空。点击条目回填，不自动执行。

## Risks / Trade-offs

- [UserDefaults 被清空] → 历史丢失，不影响功能。
- [SQL 里含敏感值] → 只存本机；文档说明历史会记录完整语句，用户可清空。
- [200 条不够] → 先固定，后续再做成可配置。

## Migration Plan

新增功能，没有数据迁移。

## Open Questions

无。
