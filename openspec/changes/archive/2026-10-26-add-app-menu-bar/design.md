# Design

## Context

SwiftUI 的 Commands 在 App 场景里声明，拿不到 ContentView 的局部状态。SQL 文本、当前选中的文件都在界面层。

## Goals / Non-Goals

**Goals**

- 菜单项能读可用状态并触发界面动作。
- 状态只有一份，菜单和工具栏不会不一致。

**Non-Goals**

- 不做快捷键自定义。
- 不做多窗口菜单状态。

## Decisions

### D1 用 CommandBus 做桥

单例 ObservableObject，界面在 onAppear 和选中变化时填 closures 与布尔状态，Commands 视图用 @ObservedObject 读取，按钮 disabled 跟着状态走。

### D2 视图开关共用 @AppStorage

侧栏、检查器、SQL 抽屉三个开关都写 UserDefaults，菜单和界面读同一个键，避免两套状态。

### D3 关闭文件改用 Shift+Command+W

Command+W 是系统关窗口，替换会破坏习惯。

### D4 菜单项集中成一张表

菜单的标题、快捷键、可用条件写在 \`MenuCatalog\`，菜单视图遍历这张表生成 Button，测试也读同一份。需求文件里写了快捷键而实现漏挂的情况，断言能直接报出来。快捷键查重用「修饰键排序 + 字符」拼出的字符串，同一组合出现两次会失败。

### D5 快捷键只挂在菜单上

工具栏按钮和 SQL 面板原本各自挂了 Command+O、Command+F、Shift+Command+E、Command+J、Command+Option+I、Command+R，与菜单重复。重复注册时系统会静默丢掉一个，落到哪个不确定。现在全部撤掉，工具栏只留 \`.help\` 提示，命令统一走菜单。

## Risks / Trade-offs

- [clos捕获 ContentView 的值拷贝] → 捕获的是 @StateObject/@ObservedObject 的引用包装，实际操作仍落在同一个对象上。
- [菜单项在极端时序下状态滞后] → onReceive entries 与 onChange selection 都会刷新。

## Migration Plan

无数据迁移。

## Open Questions

无。
