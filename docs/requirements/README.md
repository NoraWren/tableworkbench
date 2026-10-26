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
| AI | `13-ai-analysis.md` |
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

v0.1 的主要功能已经实现并在本机跑通：CSV/TSV/Parquet/xlsx 导入、分块网格、排序筛选、SQL 抽屉、透视、列检查器、导出和 dmg 打包。Xcode 仍未安装，SwiftUI 宏和 XCTest 用替代方案绕开，逐条验收框只在整条需求验完后才勾。

| 文件 | 条目数 | 状态 |
|---|---|---|
| 01-product-scope.md | 7 | 已定义 |
| 02-data-import.md | 7 | 已实现，验收框待同步 |
| 03-data-grid.md | 8 | 已实现，R-GRID-08 已完成 |
| 04-sql-console.md | 5 | 已实现；R-SQL-02/04 已完成，R-SQL-01/03/05 剩个别验收项待同步 |
| 05-pivot-table.md | 4 | 已实现；R-PVT-01/02/03/04 的勾选已同步，剩“多级表头逐级合并”未做 |
| 06-column-inspector.md | 4 | 已实现，验收框待同步 |
| 07-export.md | 4 | 已实现，导出范围新增选择框，验收框待同步 |
| 08-performance.md | 7 | 基准已补齐：滚动帧耗时与冷启动都有实测；500MB 冷打开 2.0–2.4 秒贴着预算 |
| 09-app-shell.md | 7 | 已实现；R-SHELL-02 菜单与 11 条快捷键逐条实测通过，其余条目验收框待同步 |
| 10-packaging-release.md | 6 | dmg 已出，签名与公证缺账号 |
| 11-milestones.md | 10 | 前置条件未就绪（Xcode） |
| 12-decisions-risks.md | 17 | 3 项待拍板 |
| 13-ai-analysis.md | 15 | 已定义，v0.2 |
| 14-charts.md | 5 | 图表四类、一键分析已实现，R-VIZ-02/03/04/05 验收已勾；release 出图 0.07 秒 |

共 101 条需求。
