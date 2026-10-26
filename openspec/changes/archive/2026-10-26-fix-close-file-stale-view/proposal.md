# Proposal

## 对应需求

- R-SHELL-04：空状态与引导。没有任何文件时，中栏必须是拖放区。
- R-VIZ-05：一键分析结果区。结果属于某一份数据，文件关掉就不该再出现。
- R-SQL-02：SQL 结果区。同理，结果绑在打开的连接上。

## Why

做演示录屏时撞到的：`500mb.csv` 跑完一键分析，用「文件 > 关闭文件」把文件关掉，左侧数据源已经回到「还没有打开文件」，中栏却还挂着五张图，标题写着「5 张图 · 自动挑了区域、金额求和……」，每张图下面还有「4 组 · 0.04 秒」的耗时。关掉的是一份已经 `close()` 的 DuckDB 连接，屏幕上却是它的结果。

根因在 `WorkspaceModel`：切文件时 `selection` 的 `didSet` 会清列统计、选中行、行详情和单张图，但漏了 `autoCharts`、`sqlResult`、`isAnalyzing`、`isBuildingChart` 这几个展示态。`closeSelected()` 走的是同一条路径，先 `close()` 会话再删 entry，然后把 `selection` 置成剩下的第一个文件。所以只要关文件或换文件前停在图表页、SQL 结果页，中栏就会留着上一份数据的结果。

这不只是观感问题：结果区上方的「返回数据」按钮在文件关掉后按下没有反应（`selectedEntry` 已经是 nil），用户没有别的办法退出这个页面，只能再开一个文件。

## What Changes

- 把「清掉挂在当前文件上的展示态」收敛成一个私有方法，`selection` 的 `didSet` 和 `closeSelected()` 都调它，以后新增展示态只有一处要改。
- 清的东西：列统计与统计列名、选中行、行详情、单张图、一键分析结果、SQL 结果与结果标题，以及 `isAnalyzing` / `isBuildingChart` / `isRunningSQL` 这几个进行中标记。
- 关闭文件时先清展示态再 `close()` 会话，避免清的过程中还去读已关闭的连接。
- 测试补「关掉文件后中栏回到空状态」和「换文件时清掉上一份的一键分析结果」两条断言。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- workbench-view：新增「展示态跟随当前文件」的要求，文件关掉或切换后中栏不许残留上一份的结果。

## Impact

- `app/Sources/Features/WorkspaceModel.swift`：`selection` 的 `didSet`、`closeSelected()`，新增一个私有清理方法。
- `app/Sources/TableWorkbenchTests/main.swift`：补两条断言。

## 性能与只读

不新增任何 SQL，清理只是把几个引用置 nil，比现在少做一遍读取。只读约束不变。

## 不做什么

- 不做「关掉文件但保留图表快照」的功能。图表是查询结果的可视化，连接关掉后它就没有数据来源，留着只会误导。
- 不动单张图的 `clearChart()` 行为，它本来就是对的。
