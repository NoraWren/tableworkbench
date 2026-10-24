# Design

## Context

见 proposal.md。网格已经有按块取数，块大小 5000 行，块内按 rowid 定位。

## Goals / Non-Goals

**Goals:**

- 双击到面板出现控制在一次块查询的时间里。
- 复用现有的取数通道，不新增查询协议。

**Non-Goals:**

- 行间导航、编辑、关联跳转。

## Decisions

### D1 只取一行，按显示列取

用 session.block(offset: row, size: 1, columns: shownColumns) 取一行。宽表里 shownColumns 已经是裁剪后的 200 列，正好满足“2000 列也能 300 毫秒出来”；普通表就是全部列。

### D2 双击用 NSTableView 的 doubleAction

GridTableView 加一个闭包，DataGridView 把它接到状态层。比在 SwiftUI 层叠手势可靠，也不会和选中、拖选打架。

### D3 面板用 sheet

需求写的是侧边面板，但检查器已经占了右侧，再塞一个面板会和列统计抢位置。用 sheet 竖排展示，关掉就回到表格，交互更干净；演示时也更容易看懂。

### 被否决的方案

- 复用检查器显示行详情：检查器是列维度，混进行维度会让两种视角打架。
- 用 NSPopover：长文本要滚动，popover 的高度不好控制。

## 风险

双击和单击选中的事件顺序：AppKit 先选中再触发 doubleAction，选中状态会先更新一次，不影响详情内容。
