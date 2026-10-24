# Proposal

## Why

v0.1 的第一块地基还没落地：仓库里只有需求文档和流程配置，没有一行可运行的代码。R-MS-02 要求在两周内证明三件事：SwiftUI 原生壳能跑、DuckDB 能接进来、大 CSV 能进 NSTableView 并流畅滚动。任何一件不成立，后面十二周的计划都要改，所以必须先做这一块。

对应需求：R-MS-01、R-MS-02、R-IMP-01、R-IMP-02、R-IMP-04、R-GRID-01、R-GRID-02、R-GRID-03、R-PERF-01。

## What Changes

- 新建 SPM 工程 app/，拆出四个 target：TableWorkbenchApp、Features、DataGrid、DuckDBKit。
- 应用壳：单窗口，左侧数据源列表、中间数据网格、右侧检查器占位、底部 SQL 抽屉占位。
- 打开文件：拖放与 Command+O 两个入口，支持 CSV 和 TSV。
- 编码与格式：UTF-8（含 BOM）与 GB18030 探测，分隔符自动识别，失败时给可读错误。
- 查询：DuckDB 只读连接，把文件挂成视图，按 5000 行一块取数。
- 网格：NSViewRepresentable 包 NSTableView，显示表头、行号，滚动到边界时取下一块。
- 基准脚本：scripts/make-bench-data.sh 生成 500MB CSV，scripts/bench.sh 记录打开耗时与内存。
- 单元测试：编码探测、分块换算、SQL 组装三块各有一组测试。

## Capabilities

### New Capabilities

- app-shell: 应用启动、单窗口三栏布局、空状态、文件打开入口。
- data-import: CSV/TSV 的格式识别、编码探测、导入错误处理。
- data-grid: NSTableView 网格、分块取数、行列渲染与滚动。
- query-engine: DuckDB 只读连接、文件挂载、查询执行与结果集封装。

### Modified Capabilities

无。openspec/specs 目前为空，这是第一批能力。

## Impact

- 新增 app/ 下的 SPM 工程，新增 scripts/ 下两个脚本。
- 新增依赖 duckdb-swift（MIT）。版本未定：正式 tag 只到 v1.1.3，main 上是 dev 快照，需要实测后锁定。
- 不改动 docs/requirements 下的任何文件，只在代码注释和 change 里引用需求编号。
- 本机没有 Xcode，本 change 用 swift build 与 swift run 验证；.app 打包、签名、公证留给 R-MS-08。

## 不做什么

- 不做排序、筛选、计算列。
- 不做 SQL 抽屉的执行，只留一个可折叠的空面板。
- 不做透视、检查器统计、导出。
- 不做 xlsx，不读 Parquet 缓存。
- 不做 AI 分析，那是 v0.2 的 R-MS-10。
- 不改动现有的需求文档和 OpenSpec 配置。

理由：这些能力各自都能独立成一个 change。先把"能打开、能滚、能查"这条最小链路跑通，才知道性能数字站不站得住。

## 性能与只读

本 change 直接触碰两条硬约束，单独说明。

性能：目标是 500MB CSV 打开到可滚动不超过 3 秒，第一阶段允许比最终预算慢 1 秒。1000 万行的滚动测试放到数据网格完成后再跑，本 change 只验证 10 万行不掉帧。基准脚本必须能在空目录一键生成数据，结果写进 docs/bench-history.md。

只读：连接以只读方式打开，文件只挂视图，不建表、不写回。允许的做法仅限 SELECT、DESCRIBE、SUMMARIZE。任何写语句在 DuckDBKit 层被拒绝，界面层再拦一次。

## 风险

- GitHub 直连不稳定，duckdb-swift 可能拉不下来。备选顺序：重试、走代理、用 codeload 下载 v1.1.3 压缩包做本地路径依赖。仍然不行就先把 DuckDBKit 做成协议加假实现，保证应用壳和网格能独立编译，等依赖可用再替换。
- 没有 Xcode，SwiftUI 预览和 .app 打包不可用。先用 swift run 跑可执行文件，窗口和菜单行为与正式包一致，差异记录在设计文档里。MDEOF
wc -l openspec/changes/bootstrap-app-skeleton/proposal.md && openspec status --change bootstrap-app-skeleton --json | python3 -c "import sys,json;d=json.load(sys.stdin);print([(a['id'],a['status']) for a in d['artifacts']])"