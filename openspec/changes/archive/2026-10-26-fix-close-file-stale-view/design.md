# Design

## Context

见 proposal.md。`WorkspaceModel` 是一个 `ObservableObject`，`ContentView` 的 `detailContent` 按固定优先级挑要画的东西：一键分析结果 → 分析中 → 单张图 → 生成图表中 → SQL 结果 → 数据网格 → 空状态拖放区。前五个分支都在 `selectedEntry` 为 nil 时照样成立，所以只要它们的 `@Published` 值没被清空，就一直压在数据网格和空状态上面。

## Goals / Non-Goals

**Goals:**

- 文件关掉后中栏回到空状态拖放区。
- 换文件时上一份的分析结果与 SQL 结果一律不出现。
- 新增展示态时只需要在一个地方登记。

**Non-Goals:**

- 不重排 `detailContent` 的分支顺序，也不改成按 entry 存放结果。

## Decisions

### D1 用一个私有方法集中清理

`resetPresentation()` 里把列统计、选中行、行详情、单图、一键分析、SQL 结果和几个进行中标记一起置空。`selection` 的 `didSet` 和 `closeSelected()` 都调它。

被否决的方案：在各处的 `@Published` 上加 `didSet` 互相清理。否决原因是一个字段的清理依赖另一个字段的赋值顺序，分支会越加越绕，而且 `@Published` 的 `didSet` 在初始化期也会触发。

被否决的方案：把结果按 entry id 存成字典。否决原因是这会顺带改掉「切文件」的语义，超出这次修 bug 的范围，而且内存里会同时留住多份查询结果。

### D2 先清展示态再关连接

`closeSelected()` 里先 `resetPresentation()`，再 `session.close()`，最后删 entry 并改 `selection`。顺序反过来的话，改 `selection` 触发的 SwiftUI 重绘有一帧可能去读刚关掉的会话。

### D3 进行中标记也要清

`isAnalyzing`、`isBuildingChart`、`isRunningSQL` 一起置 false。否则用户在分析跑到一半时关掉文件，中栏会卡在「正在分析…」上，而那个任务的目标连接已经关掉。分析任务本身回来之后写的是 `autoCharts`，此时文件已经不在列表里，值会在下一次 `resetPresentation()` 里被清掉。

## Risks / Trade-offs

- [分析任务在关闭后才返回，把结果写回去] → 任务返回时 entry 已从 `entries` 移除，写回的 `autoCharts` 不会显示在任何 entry 下；再切一次文件就会被清掉。彻底的做法是给任务加取消令牌，这次不做，因为现有任务本身很快（328 万行 0.18 秒）。

## Migration Plan

不涉及数据迁移。

## Open Questions

无。
