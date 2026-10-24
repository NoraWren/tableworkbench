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

- [x] 4.1a 没有文件时，导出、关闭文件、运行、新建查询都置灰；打开文件后恢复
- [x] 4.1b 点「查询 → 运行」执行 SQL 抽屉里的语句，结果进入查询结果视图
- [ ] 4.1c 逐个点其余菜单项，验证动作
- [ ] 4.2 用快捷键 Command+R、Command+N、Shift+Command+E 验证与菜单一致
