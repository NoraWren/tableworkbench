# Design

## Context

见 proposal.md 的 Why。当前状态：QuerySession 只有 block(offset:size:)，DuckDBSession 每次拼 LIMIT/OFFSET，网格按块取数并做 8 块 LRU。排序和筛选没有入口，也没有查询状态。

## Goals / Non-Goals

**Goals:**

- 排序和筛选都是查询状态，不是视图排序。
- 查询变化时缓存和行数同步更新。
- 列头点击、Shift 多列、筛选条件、AND/OR 都有明确行为。

**Non-Goals:**

- 不做嵌套条件树、正则、计算列。
- 不做保存的筛选视图。
- 不做 rowid 物化，深分页仍然是 LIMIT/OFFSET。

## Decisions

### D1 查询状态放在 DuckDBKit，界面只发意图

新增 QueryView：排序数组加筛选组。QuerySession 增加 apply(view:) 和 resultCount。界面不拼 SQL，只把"按金额降序""区域等于华东"翻译成 QueryView。

备选：界面拼 SQL 传给 session。会把转义和列名校验散到 UI 层，容易出注入和拼错列名。

### D2 SQL 生成集中在一个 Builder

OrderByBuilder 与 WhereBuilder 都在 DuckDBKit。标识符用双引号包裹并双写内部引号；字符串值用单引号包裹并双写单引号。运算符映射：等于 =，不等于 <>，包含 LIKE '%v%'，大于 >，小于 <，介于 BETWEEN，为空 IS NULL，不为空 IS NOT NULL。

备选：DuckDB 预处理语句绑定参数。更安全，但 Swift 包这次的 API 需要额外验证，先用转义，后续可以替换。

### D3 计数分两层

打开文件时算一次总行数，存进 session。筛选变化时用同样的 WHERE 算一次 count(*)，存进 resultCount。总行数不变，界面显示"N 行中的 M 行"。

备选：每次取块都 count。浪费一次全表扫描，滚动时会明显变慢。

### D4 块缓存按查询代次失效

session 里维护 generation，每次 apply(view:) 自增。DataGrid 的缓存以 generation 为界，变化时整体清空。界面用 entry.queryVersion 触发视图重建。

备选：缓存 key 加查询哈希。可以做，但当前只有 8 块，整体清空更简单。

### D5 列头点击通过 NSTableViewDelegate

用 tableView(_:didClick:) 拿到列，读 NSEvent.modifierFlags 判断 Shift。不拦截 mouseDown，避免破坏列宽拖动和选中。

排序状态存在 WorkspaceModel 的 Entry 里，DataGridView 只负责把点击转成回调，并在重建列头时显示箭头和序号。

### D6 筛选界面用 popover

工具栏一个"筛选"按钮，弹出条件列表。每行是列、运算符、值三个控件；底部 AND/OR 切换和"应用"按钮。条件数量限制 10 个，避免界面失控。

值输入在应用时才生成 SQL，输入过程中不查询。

### D7 深分页保持现状

排序后的结果仍用 ORDER BY + LIMIT/OFFSET。第 100 块会继续变慢，这是已知问题，rowid 物化留给独立 change。

实测：500MB（328 万行）按金额降序，第一块 0.83 秒，第 100 块 3.24 秒；未排序时第 100 块 0.52 秒。排序让深分页更慢，rowid 物化的优先级要提到下一个 change。

## Risks / Trade-offs

- [1000 万行排序超过 3 秒] → 先测 500MB 样本（328 万行），如果单列排序超过 1.5 秒，把 README 的目标改成 5 秒并记录实测。
- [Shift 多列排序在 macOS 上手势不直观] → 列头显示序号，首次使用在筛选面板里加一行说明。
- [筛选 popover 条件太多] → 限制 10 个，超过时提示。
- [值转义遗漏] → 所有字符串值只经过一个 escapeLiteral 函数，单元测试覆盖单引号、反斜杠和中文。
- [筛选后空结果] → resultCount 为 0 时表格显示空提示，不请求块。

## Migration Plan

新增功能，没有数据迁移。回滚删除 QueryView 相关代码，session 回到只有 block(offset:size:) 的版本。

## Open Questions

无。排序是否持久化到下次打开同一个文件，留到筛选视图保存那个 change。
