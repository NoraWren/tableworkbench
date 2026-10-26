# Design

## Context

见 proposal.md。DuckDBSession 的 columns 是原始列，块查询用 SQLBuilder.selectList。计算列不属于表，只属于查询投影。

## Goals / Non-Goals

**Goals:**

- 计算列显示在网格末尾。
- 表达式错误不产生空列。
- 不影响检查器、透视、导出和 SQL。

**Non-Goals:**

- 持久化、排序筛选、图形化编辑。

## Decisions

### D1 计算列与基础列分开存

base columns 保持不动，computed 单独一个数组。displayColumns = columns + computed。这样统计、透视、导出继续用 columns，不会遇到不存在的列。

### D2 块查询追加投影

SELECT 基础列 CAST、计算列 CAST((表达式) AS VARCHAR) AS 计算列名。只影响网格，不影响 data 视图。

### D3 添加前试算

执行 SELECT (表达式) FROM __base LIMIT 1，捕获错误；同时 SQLGuard 校验，禁止写操作。

### D4 计算列禁排序

ColumnInfo.isComputed 为 true，GridDataSource 的点击回调跳过。排序/筛选在基础列上继续可用。

### D5 生命周期跟会话

关闭文件释放连接，computed 数组随之消失。

## Risks / Trade-offs

- [表达式很重导致每块变慢] → 用户自己控制；单块耗时超过 0.3 秒时在文档里提示。
- [计算列类型都是文本] → 先保证显示，数字对齐和排序后续再做。
- [表达式包含分号或写语句] → SQLGuard 拒绝，试算前校验。

## Migration Plan

新增功能，没有数据迁移。

## Open Questions

无。
