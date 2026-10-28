# Proposal

## Why

R-IMP-01 的第一条入口是把文件从访达拖进窗口，但这条一直没验过，也没录进演示。离线探针查到的原因是：SwiftUI 的 `.dropDestination` 挂在 `NavigationSplitView` 上，生成出来的拖放目标视图落在分栏视图的**兄弟层**；AppKit 投递拖放是先 `hitTest` 再沿父链找注册了拖放类型的视图，兄弟链不在父链上，所以拖拽落不到它身上。README 第一句话就是"拖进一个 500MB 的 CSV"，这条路径不通，对外的话就站不住。

## What Changes

- 窗口内容视图换成自绘的 `FileDropContainerView`，注册 `public.file-url`，原来的 SwiftUI 视图整个装进去。任何位置的父链都能走回它，`NSTableView` 也抢不走。
- 拖进来时给窗口内容描一圈强调色边框，松手前一直保持，松手或移出就撤掉；R-IMP-01 要求"窗口整体高亮"。
- 只接受本地文件 URL。拖进来一段文字、一张图（非文件）、一个网页链接，一律返回不接收，不弹任何提示。
- 装这一层要等 SwiftUI 把 hosting 视图挂稳再做，否则 SwiftUI 会把 hosting 视图重新挂回 `NSThemeFrame`，容器就空了。
- 去掉 `ContentView` 上原来的 `.dropDestination(for: URL.self)`，避免两套接收器抢同一份拖拽。
- `TableWorkbenchUIAudit` 增加 `TW_DROP_PROBE=1` 探针，把注册了拖放类型的视图、覆盖面积、兄弟层打出来，顺带截一张换成容器之后的窗口图。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `data-import`：新增"窗口接收拖入文件"一条，写明接收器在哪一层、接什么、不接什么。

## Impact

- 新增 `app/Sources/WorkbenchUI/DropTarget.swift`；`ContentView.swift` 改用 `DropTargetInstaller`。
- `TableWorkbenchTests` 增加 12 条断言：容器是否装上、是否注册 `public.file-url`、是否铺满、是否只套一层、重复安装是否换处理函数、真走一遍 `draggingEntered`/`draggingUpdated`/`performDragOperation`、文字是否被拒。
- 打开动作本身（去重、xlsx 多工作表弹选择器、不支持格式报错）复用 `OpenRequestBus` 那条路，逻辑一行没改。

## 不做什么

- 不做拖到 Dock 图标、不做拖到左栏某一条上替换文件、不做文件夹递归导入。R-IMP-01 边界里已经写明不做文件夹批量导入。
- 不做自定义拖拽预览图。系统默认的图标加文件名够用，做预览图要多一份快照代码，收益看不见。
- 不改 `PivotPanel` 里那几处 `.dropDestination(for: String.self)`。它们拖的是面板内的字段标签，同一个视图自己既当源又当目标，父链关系正常，和访达拖文件不是一回事。

## 性能与只读

- 接收层只读剪贴板里的文件 URL，不读文件内容，不碰数据库。
- 覆盖层是一个空 `NSView` 加一个 `NSHostingView` 子视图，没有额外绘制；拖拽悬停时只改 layer 的边框宽度和颜色，不进布局。
- 不触碰 R-PERF 的任何一条预算：冷打开、二次打开、滚动帧率、dmg 体积都没变。
