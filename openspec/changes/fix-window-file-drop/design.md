# Design

## 查询

这次没有任何查询变化。拖入文件之后走的是既有的打开链路：探测编码、转 Parquet、挂视图，条目进左栏，全部由 `WorkspaceModel.open(urls:)` 负责。拖放层只把 `[URL]` 交出去，不拼 SQL、不读数据。

## Swift 侧封装

三层，从上往下：

1. `DropTargetInstaller`（`NSViewRepresentable`）挂在 SwiftUI 树里，唯一作用是拿到 `window`。它自己不接收拖拽。
2. `WindowDropInstaller` 把窗口的 contentView 换成 `FileDropContainerView`，把原来的 contentView 塞进去铺满，`autoresizingMask` 跟着窗口走。
3. `FileDropContainerView` 实现 `draggingEntered` / `draggingUpdated` / `draggingExited` / `prepareForDragOperation` / `performDragOperation`，闭包由 `DropHandlerBox` 持有，SwiftUI 每次更新只替换盒子里的函数。

装的时候必须延一轮。实测在 `viewDidMoveToWindow` 里当场换 contentView，SwiftUI 随后会把 `NSHostingView` 重新挂回 `NSThemeFrame`，容器成了空壳（换之前子视图列表里 hosting 在容器内，下一轮它就跑回了主题框架）。所以 `DropTargetInstaller` 在 `viewDidMoveToWindow` 里 `DispatchQueue.main.async` 再装，`WindowDropInstaller` 装完再校验一次 `content.superview`，不对就重新 `addSubview`。

为什么不用 SwiftUI 的 `.dropDestination`：它生成的 `_PlatformDraggingDestinationView` 和 `SystemSplitView` 是兄弟节点，AppKit 沿父链找不到它。离线探针 `TW_DROP_PROBE=1` 能直接看到这份结构。

为什么不在 `NSTableView` 的子类里接：表格是滚动容器里的一层，文件拖到侧栏、工具栏、空白处都落不到表格上。R-IMP-01 要求"窗口任意位置"，必须挂在祖先层。

为什么不做成 SwiftUI 的 `.onDrop(of:delegate:)`：那是旧 API，底层同样是往 SwiftUI 自己的宿主视图上注册，仍躲不开兄弟层那条父链。回到 AppKit 的 `NSDraggingDestination` 是最短路径。

## UI 线程边界

拖放回调全部在 AppKit 主线程上，同步执行。闭包里只做一件事：把 URL 数组交给 `ContentView.handleOpen(urls:)`，之后进 `WorkspaceModel.open`，打开本身已经在后台线程跑，主线程不等。悬停高亮只改 layer 属性，不触发布局。

## 验证

- `TableWorkbenchTests` 造一个真 `NSWindow`，装 `WorkbenchRootView`，等容器装好后断言：contentView 是 `FileDropContainerView`、注册了 `.fileURL`、`bounds` 与窗口内容区一致、hosting 在容器子视图里、只有一层、重复安装返回同一个对象、处理函数能被替换。
- 用 `FakeDraggingInfo` 喂一个写着文件 URL 的 `NSPasteboard`，按 AppKit 的顺序调 `draggingEntered` → `draggingUpdated` → `prepareForDragOperation` → `performDragOperation`，断言返回 `.copy` 且 URL 交到处理函数；换成纯文字再走一遍，断言 `draggingEntered` 返回空、`performDragOperation` 返回 false、处理函数没被调用。
- `TW_DROP_PROBE=1 TableWorkbenchUIAudit` 打印注册视图、覆盖面积、兄弟层，并截一张换成容器后的窗口图，确认渲染没坏。

真机用鼠标拖一次仍然要人来做。自动化能证明"接收器在对的层、类型匹配、回调把 URL 交出去了"，证明不了系统真的把访达的拖拽会话送进来——那需要 X 事件，测试进程造不出来。
