# 需求目录

这里只放需求，不放设计稿和代码说明。设计相关的结论写到 `12-decisions-risks.md`。

## 编号规则

`R-<域>-<两位序号>`，域和文件一一对应：

| 域 | 文件 |
|---|---|
| SCOPE | `01-product-scope.md` |
| IMP | `02-data-import.md` |
| GRID | `03-data-grid.md` |
| SQL | `04-sql-console.md` |
| PVT | `05-pivot-table.md` |
| INSP | `06-column-inspector.md` |
| EXP | `07-export.md` |
| PERF | `08-performance.md` |
| SHELL | `09-app-shell.md` |
| REL | `10-packaging-release.md` |
| MS | `11-milestones.md` |
| DEC | `12-decisions-risks.md` |

编号只增不改。删除的需求不重新编号，保留原文并划掉。

## 每条需求的格式

```
## R-IMP-05 Parquet 缓存

- 优先级：P0
- 状态：待实现
- 场景：一句话说明用户在哪一步遇到它
- 行为：实现后用户看到什么、系统做什么（可用编号列表）
- 验收：
  - [ ] 可勾选的具体检查项，尽量带数字
- 边界：明确不做什么
- 依赖：关联的其他编号
```

验收项必须能被第三方复现。写"响应快"不算，写"1000 万行文件打开到可交互不超过 1 秒"才算。

## 状态图例

| 状态 | 含义 |
|---|---|
| 已定义 | 文档写完，代码没开始 |
| 待验证 | 依赖一个还没跑通的技术假设 |
| 进行中 | 有人在做 |
| 已完成 | 验收项全勾，基准没退化 |
| 已废弃 | 不做了，保留编号和原因 |

## 当前进度

全部条目都是"已定义"或"待验证"，代码尚未开始。当前阻塞项是安装 Xcode。

各文件的完成情况，改完代码后在这里更新：

| 文件 | 条目数 | 已完成 | 状态 |
|---|---|---|---|
| 01-product-scope.md | 6 | 0 | 已定义 |
| 02-data-import.md | 7 | 0 | 部分待验证 |
| 03-data-grid.md | 8 | 0 | 已定义 |
| 04-sql-console.md | 5 | 0 | 已定义 |
| 05-pivot-table.md | 4 | 0 | 已定义 |
| 06-column-inspector.md | 4 | 0 | 已定义 |
| 07-export.md | 4 | 0 | 已定义 |
| 08-performance.md | 7 | 0 | 已定义 |
| 09-app-shell.md | 6 | 0 | 已定义 |
| 10-packaging-release.md | 6 | 0 | 已定义 |
| 11-milestones.md | 9 | 0 | 前置条件未就绪 |
| 12-decisions-risks.md | 10 | 0 | 3 项待拍板 |

共 76 条需求。
