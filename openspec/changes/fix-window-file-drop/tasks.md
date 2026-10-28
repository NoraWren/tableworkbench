# Tasks

## 1. 接收层

- [x] 1.1 新增 FileDropContainerView，注册 public.file-url，实现 draggingEntered / draggingUpdated / draggingExited / prepareForDragOperation / performDragOperation / concludeDragOperation
- [x] 1.2 WindowDropInstaller 把窗口 contentView 换成容器并把原视图装进去，重复调用只换处理函数
- [x] 1.3 装的时候延一轮主队列，避免 SwiftUI 把 hosting 视图挂回 NSThemeFrame
- [x] 1.4 悬停描边只在 layer 上改宽高与颜色，不触发布局

## 2. 接进界面

- [x] 2.1 ContentView 去掉 .dropDestination(for: URL.self)，改用 DropTargetInstaller
- [x] 2.2 拖入的 URL 交给既有 handleOpen，去重、xlsx 多工作表、不支持格式的行为不变

## 3. 验证

- [x] 3.1 测试断言容器装在窗口内容视图上、注册 .fileURL、铺满内容区、只一层、重复安装返回同一对象
- [x] 3.2 FakeDraggingInfo 走一遍四步回调，断言返回 .copy 且 URL 交到处理函数
- [x] 3.3 拖纯文字断言不接收、不触发打开
- [x] 3.4 TW_DROP_PROBE 打印注册视图与覆盖面积，并截换成容器后的窗口图
- [x] 3.5 TableWorkbenchTests 全绿（498 项）
- [x] 3.6 真机从访达拖一次 bench-data/wide-100k.csv，补一张截图到 docs/media/verification/（2026-10-27 23:29 真机拖 wide-100k.csv 与 500mb.csv 各一次，悬停高亮、100,000 行、3,266,000 行三张截图在 docs/media/verification/drop-real-*.png）
- [ ] 3.7 重录第一屏 GIF，把拖入动作放进前 3 秒

## 4. 文档

- [x] 4.1 docs/requirements/02-data-import.md 的 R-IMP-01 写清根因与修法
- [x] 4.2 docs/release-checklist.md 那句"访达拖拽触发不了"改成实际结论
- [x] 4.3 openspec validate --strict fix-window-file-drop 通过
