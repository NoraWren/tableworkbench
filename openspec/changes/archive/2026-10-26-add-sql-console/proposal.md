# Proposal

## Why

网格的筛选只能回答事先想到的条件。真实分析里总会出现"按客户分组算一下毛利""看看复购间隔"这种问题，必须有一块能写 SQL 的地方。R-SQL-01 到 R-SQL-03 是 v0.1 的 P1，也是透视表之外的第二个分析入口。

## What Changes

- 打开文件时提供稳定的视图 data，指向文件全量数据，不受当前网格排序和筛选影响。
- QuerySession 增加 runSQL，返回列、行、耗时和是否截断。
- 结果上限 100000 行，超过时明确提示"只显示前 100000 行"。
- 只允许 SELECT、WITH、DESCRIBE、SUMMARIZE 和 CREATE TEMP，其他语句拒绝。
- SQL 抽屉从占位变成可编辑、可运行，Command+R 执行，结果显示在网格区域。
- 结果区可以返回数据视图。

## Capabilities

### New Capabilities

- sql-console：SQL 抽屉的编辑、执行、结果与错误呈现。

### Modified Capabilities

无。openspec/specs 尚未归档，这里给 query-engine 追加新的 requirement。

## Impact

- DuckDBKit 增加 SQLResult 与 runSQL。
- DuckDBSession 增加 data 视图和执行路径。
- Features 增加 SQL 状态与结果。
- App 的 SQL 抽屉从占位变成真实功能。

## 不做什么

- 不做多语句、事务脚本。
- 不做历史记录、自动补全、格式化。
- 不做执行计划可视化。
- 不做真正的取消。duckdb-swift 1.1.3 没有暴露 interrupt，查询发出后只能等它跑完。这条记成已知缺口，等上游支持或换绑定再补。

## 性能与只读

328 万行的分组聚合目标 2 秒内；结果超过 100000 行截断并提示。

只读约束不变：可执行的语句白名单之外一律拒绝，连接层仍然拒绝写操作，源文件字节不变。
