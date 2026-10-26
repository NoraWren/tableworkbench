# Proposal

## Why

网格现在只能按文件原顺序往下看。真实使用的第一步通常是"按金额排一下""只看华东"，没有这两件事，十万行和一千万行没有区别。R-GRID-04 和 R-GRID-05 是 v0.1 的 P0，也是后面透视和 SQL 抽屉的基础。

对应需求：R-GRID-04、R-GRID-05、R-GRID-02、R-SQL-02。

## What Changes

- 列头点击排序：升序、降序、取消三态；按住 Shift 点击追加多列排序，列头显示序号。
- 工具栏筛选：每个条件由列、运算符、值组成，多个条件可选 AND 或 OR。
- 行数显示从"N 行"变成"N 行中的 M 行"，旁边提供清除筛选。
- 排序和筛选全部下推给 DuckDB：生成 ORDER BY 和 WHERE，Swift 侧不做内存排序或过滤。
- 查询变化时块缓存整体失效，按新的行序重新取数。
- 字符串值统一转义，只读校验继续生效。

## Capabilities

### New Capabilities

- data-grid：排序与筛选的交互行为。
- query-engine：查询描述、SQL 生成与结果计数。

### Modified Capabilities

无。openspec/specs 目前为空，data-grid 和 query-engine 的规格还在 bootstrap-app-skeleton 里，本 change 追加新的 requirement，名称不重复。

## Impact

- DuckDBKit 增加排序、筛选和查询描述类型，新增 SQL 生成与转义。
- QuerySession 增加应用查询描述的方法，DuckDBSession 与 FakeSession 都要实现。
- DataGrid 增加列头点击排序和排序指示器。
- Features 和 App 增加筛选条件的状态与界面。
- 单元测试覆盖 SQL 生成、转义、块顺序和筛选计数。

## 不做什么

- 不做嵌套条件树、正则筛选、计算列。
- 不做筛选视图的保存与复用。
- 不改动文件，不写回源数据。
- 不做深分页的 rowid 物化，那是一个独立的性能 change。

## 性能与只读

排序在 DuckDB 内完成，1000 万行的单列排序目标 3 秒内；筛选的等值条件目标 1 秒内。500MB 样机上测，数字写进 docs/bench-history.md。

只读约束不变：WHERE 和 ORDER BY 只出现在 SELECT 里，写操作仍在 SQLGuard 和连接层被拒绝。

深分页仍然是 LIMIT/OFFSET，第 100 块的 0.52 秒问题本 change 不解决，留给 rowid 物化。
