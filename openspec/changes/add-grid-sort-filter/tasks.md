# Tasks

## 1. 查询模型

- [x] 1.1 新增 SortSpec、FilterOperator、FilterCondition、FilterGroup、QueryView，验证类型可构造且 Equatable
- [x] 1.2 实现 SQLBuilder：ORDER BY、WHERE、标识符与字面量转义，验证单引号、双引号、中文三组用例
- [x] 1.3 QuerySession 增加 apply(view:) 与 resultCount、generation，验证 FakeSession 与 DuckDBSession 都实现
- [x] 1.4 DuckDBSession 实现筛选计数，验证 count 与 WHERE 的结果一致

## 2. 查询执行

- [x] 2.1 block 查询拼上 WHERE 和 ORDER BY，验证排序后第一块是新顺序
- [x] 2.2 查询变化时自增 generation，验证块缓存按代次失效
- [x] 2.3 空结果不发起块查询，验证 resultCount 为 0 时界面停在空提示
- [x] 2.4 写语句仍被 SQLGuard 拒绝，验证 DROP 无法进入查询

## 3. 网格交互

- [x] 3.1 列头点击切换升序、降序、取消，验证三态循环
- [x] 3.2 Shift 点击追加排序键，验证列头显示 1、2 序号
- [x] 3.3 排序状态变化时重建列头并清空缓存，验证不出现旧顺序残留
- [ ] 3.4 行数显示改为"N 行中的 M 行"，验证筛选后数字更新

## 4. 筛选界面

- [ ] 4.1 工具栏加筛选按钮与 popover，验证能添加、删除条件
- [ ] 4.2 条件行支持列、运算符、值，验证运算符随列类型变化
- [ ] 4.3 AND 与 OR 切换生效，验证两种组合行数不同
- [ ] 4.4 清除筛选恢复总行数，验证表格回到第一块

## 5. 验证

- [x] 5.1 单列排序 500MB 文件并记录耗时（第 1 块 0.83 秒，达标）
- [x] 5.2 等值筛选 500MB 文件并记录耗时（查询准备 0.42 秒，达标）
- [x] 5.3 测试程序覆盖排序、筛选、转义、计数、缓存失效，验证全部通过
- [x] 5.4 运行 openspec validate --strict add-grid-sort-filter，验证无报错
- [ ] 5.5 在开发用 bundle 里手动过一遍排序与筛选，验证界面行为与规格一致
