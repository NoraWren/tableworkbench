# Tasks

## 1. 命令总线

- [x] 1.1 增加 CommandBus 单例，暴露可用状态与动作 closures
- [x] 1.2 ContentView 在 onAppear、选中变化、运行状态变化时刷新命令状态

## 2. 菜单

- [x] 2.1 文件菜单：打开文件、导出、关闭文件，挂在 importExport 组
- [x] 2.2 查询菜单：运行、取消（置灰）、新建查询
- [x] 2.3 视图菜单：侧栏、检查器、SQL 抽屉，快捷键与需求一致

## 3. 侧栏状态

- [x] 3.1 NavigationSplitView 绑定 columnVisibility 到 UserDefaults
- [x] 3.2 隐藏侧栏后退出重开，验证仍为折叠状态

## 4. 验证

- [ ] 4.1 在界面上逐个点菜单项，验证动作与置灰状态
- [ ] 4.2 用快捷键 Command+R、Command+N、Shift+Command+E 验证与菜单一致
