# Tasks

## 1. 引擎

- [x] 1.1 ColumnInfo 增加 isComputed，验证默认 false
- [x] 1.2 QuerySession 增加 displayColumns 与 addComputedColumn，验证 FakeSession 实现
- [x] 1.3 添加前试算与只读校验，验证错误表达式被拒绝
- [x] 1.4 块查询拼接计算列，验证值正确
- [x] 1.5 计算列不影响导出与统计，验证列数不变

## 2. 界面

- [x] 2.1 工具栏加计算列面板，验证列名与表达式输入（填“毛利2”与“金额 - 成本”）
- [x] 2.2 添加后网格刷新，验证新列在末尾（第 21 列，值 81.2 等于 203.0 - 121.8）
- [x] 2.3 计算列点击排序被忽略，验证不报错（实机点「毛利2」表头，表头文字与行序不变；测试断言普通列排序照常）

## 3. 验证

- [x] 3.1 测试程序覆盖添加、重复名、错误表达式、导出不受影响
- [x] 3.2 运行 openspec validate --strict add-computed-columns，验证无报错
