# Design

## 问题

透视结果的列名是 `金额 求和 / 华南 / 直销` 这种一根斜杠串到底的扁平名字。数据是对的，但两级列维度在图上看不出层次：哪几列属于华南，要一个个读列名才能拼出来。R-PVT-04 要求表头逐级合并，这是这次要补的。

## 三方分工

**DuckDB 查询。** 不动。生成 SQL 的列别名仍是一整串扁平名字，聚合条件、`GROUP BY`、`ORDER BY`、`LIMIT 5001` 全部照旧。这样“查看 SQL”把同一份语句填进抽屉后跑出来的列名与透视一致，R-PVT-02 那条验收不会被这次改动碰坏。

列组合的排序也要跟着改一处：目前 `SELECT DISTINCT 列维度` 没有 `ORDER BY`，组合出来的顺序由 DuckDB 决定。多级表头要求相同前缀相邻，否则合并出来的表头会断开成好几段。所以取组合的查询加上按维度顺序的 `ORDER BY`，只影响列的先后，不影响列集合。

**Swift 侧封装。** 新增一个纯数据的时间点模型，描述“第几层第几列到第几列、写什么字”：

```
struct PivotHeaderCell: Hashable, Sendable {
    let title: String
    let level: Int
    let startColumn: Int
    let span: Int
}

struct PivotHeader {
    let levelCount: Int
    let rowDimensionCount: Int
    let cells: [PivotHeaderCell]
}
```

层级完全由 `PivotSpec` 加上取到的列组合算出来，不查库。计算规则：行维度列各占一层、纵向贯穿；`value × combo` 的笛卡尔展开按维度逐级分组，同前缀合并。只有一份值时省掉值标题那一层，避免表头上方多出一行只有一个格子。

这个结构挂在结果上，用一个独立的 `PivotResult` 包装 `SQLResult` 与 `PivotHeader`，`SQLResult` 本身不动。理由是 SQL 抽屉返回的任意查询没有维度概念，强行给它一个表头字段只会让所有地方都要判空；透视是唯一知道自己有几级维度的路径，层级就跟着透视结果走。

**UI 线程边界。** 表头层级在后台线程算完，跟结果一起过主线程。界面只做绘制，不做分组。

## 渲染

`NSTableView` 的表头只有一行，装不下多层。用自绘的 `NSTableHeaderView` 子类：重写 `draw(_:)`，按层级画格子，横向位置取 `tableView.rect(ofColumn:)`，滚动偏移取 `scrollView.contentView.bounds.minX`，纵向按层数均分表头高度。`headerView` 的 frame 高度改成 `层数 × 22`。

点击排序仍走原来的 `tableView(_:didClick:)`，`NSTableHeaderView` 已经负责把点击列号报给表格，不用自己算命中。

冻结首列：横向滚动时，行维度列和左侧行号条要保持可见。做法是在网格容器左侧放一个自绘视图，按可见行绘制前几列的文字，跟随纵向滚动。这套跟随机制 `RowNumbersView` 已经在用，冻结列复用同一套通知。列宽要跟着 `NSTableColumn.width` 走，所以冻结视图只负责画，宽度在布局时对齐。

## 被否决的方案

- 用两个 `NSTableView` 拼冻结列：行高与选中状态要双向同步，滚动时容易错行，行号条那边已经证明过这条路不可控。
- 把表头画进第一行数据里：排序箭头、选中、双击进详情全都会打架。
- 改列名为多段结构让系统表头自己合并：`NSTableView` 不支持跨列合并表头，且列名是取数的键，改了会连累复制与导出。

## 未验证点

`NSTableHeaderView` 子类在 `autohidesScrollers` 与横向滚动同时启用时，`draw(_:)` 里的 `dirtyRect` 可能只覆盖一段。首次实现后要用离屏截图确认整条表头都画出来了，而不是只有左边一截。
