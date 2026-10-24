# Tasks

## 1. 取数

- [x] 1.1 QuerySession 增加 block(offset:size:columns:) 默认实现
- [x] 1.2 DuckDBSession 按传入列拼 SELECT，计算列按表达式生成，验证列顺序
- [x] 1.3 测试覆盖宽表只取 3 列且首值为 v0_0

## 2. 界面

- [x] 2.1 DataGridView 暴露 visibleColumns(from:)，视图与取数共用
- [x] 2.2 ContentView 把可见列传给 provider，验证 3000 列表格有数据

## 3. 验证

- [x] 3.1 在开发用 bundle 里打开 wide-3000.csv，确认不卡死、无 NULL
- [x] 3.2 跑 TableWorkbenchTests 全部通过
- [ ] 3.3 列面板启用第 2100 列（依赖后续改动）
