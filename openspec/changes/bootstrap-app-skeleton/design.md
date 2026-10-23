# Design

## Context

见 proposal.md 的 Why。这里只列影响实现的现状。

- 仓库里没有代码，openspec/specs 为空，这是第一个 change。
- 本机 macOS 27.0.1、arm64、Swift 6.4，只有 Command Line Tools，没有 Xcode。已实测 SwiftUI 与 AppKit 用 swift build 能编译，缺的是 .app 打包、签名和 SwiftUI 预览。
- 目标系统是 macOS 14，状态层用 @Observable，表格用 NSTableView 桥接。
- duckdb-swift 仓库 139 star，许可证 MIT，正式 tag 只到 v1.1.3（2024-11-04），main 上全是 dev 快照。本机访问 GitHub 时好时坏，第一次拉取可能失败。
- 需求文档是行为的唯一来源，本 change 只引用编号，不改写文档。

## Goals / Non-Goals

**Goals:**

- 一个能 swift build、能 swift run 启动的最小应用，窗口、三栏、空状态都可用。
- 打开 500MB CSV 并在 3 秒内显示前 5000 行，滚动能继续取块。
- DuckDB 走真实依赖，不用假数据冒充性能结果。
- 编码探测、块换算、SQL 组装有可重复的单元测试。
- 为后续 change 留下稳定的模块边界，排序筛选、SQL 抽屉、透视都能接进来。

**Non-Goals:**

- 不做排序、筛选、计算列、透视、检查器统计、导出。
- 不做 xlsx、Parquet 缓存、多文件。
- 不做 .app 打包、签名、公证、自动更新。
- 不引入第三方 UI 库、图表库、网络库。

## Decisions

### D1 先用 SPM 工程，Xcode 工程晚一步

用 app/Package.swift 组织，target 拆成 TableWorkbenchApp、Features、DataGrid、DuckDBKit。理由是本机没有 Xcode，SPM 能编译也能 swift run 启动可执行文件，先把链路跑通。等 R-MS-08 再做 .app 打包和签名。

备选：等 Xcode 装好再开工。代价是整条链路停摆，而且 SwiftUI 代码在 SPM 里同样能验证，没有必要等。

代价：swift run 启动的可执行文件没有 Info.plist 和 Bundle ID，Keychain、文件类型关联、菜单栏名称这些要等打包后才完整。开发期接受。

### D2 DuckDB 藏在协议后面

DuckDBKit 暴露一个 QuerySession 协议：打开文件、取列信息、取总行数、按块取行、关闭。界面层只依赖协议，不 import DuckDB。

理由有两个。第一，GitHub 拉不下来时，应用壳和网格仍能用一个内存假实现编译和演示。第二，单元测试不需要真实 DuckDB 就能覆盖分块、缓存和错误映射。

备选：界面直接调 DuckDB。省一层，但一旦依赖拉取失败，整个工程都编译不了。

同时保留一个真实实现 DuckDBSession，性能数字只能来自它。

### D3 版本先锁 v1.1.3，再用 main 快照对比

先锁 exact 1.1.3，保证 API 和文档稳定。拉下来之后写一个探针程序，确认连接、查询、结果集取列三个调用能跑通，把真实签名记进 12-decisions-risks.md。

如果 v1.1.3 在 Swift 6.4 下编译不过，再换 main 上的一个具体 commit，用 revision 锁定，并记录原因。

备选：直接用 main。新，但每天在变，出问题难定位，不适合作为第一块地基。

### D4 第一版用 LIMIT/OFFSET 分块

按块查 SELECT ... LIMIT 5000 OFFSET n。实现简单，块之间无状态。

已知代价：深分页时 OFFSET 要扫过前面的行，越翻越慢。本 change 先用基准测出真实曲线，如果第 100 块明显超过 200 毫秒，再改成物化 rowid：建临时表时加 row_number 列，之后按区间查。

备选：一上来就物化 rowid。对 500MB CSV 会多一次全量扫描和一份内存，第一版不值得。

### D5 查询在串行队列，界面只拿快照

DuckDB 连接绑定一个串行队列，所有查询排队执行。返回给界面的块是值类型数组，不共享 C 指针。界面更新回主线程。

理由：DuckDB 连接不是线程安全的，跨线程共享会出难查的崩溃。串行队列还能天然实现"新查询取消旧查询"的顺序。

代价：两次查询不能并行。本阶段只有一个网格，够用。

### D6 GBK 先转码再交给 DuckDB

DuckDB 的 CSV 读取接口没有任意编码参数。做法是：读前 64KB 判断编码；不是 UTF-8 时，把整个文件转成临时 UTF-8 文件，再交给 DuckDB 读取。转码后的路径记在导入结果里。

备选：让 DuckDB 直接读 GBK。实测不支持，会得到乱码或类型推断失败。

代价：GBK 文件首次打开多一次全量读写，500MB 大概多 1 到 2 秒。这个代价在 v0.2 做 Parquet 缓存时可以摊掉。

### D7 网格用 view-based NSTableView，块缓存 8 块

NSTableView 的 dataSource 只回答"总行数"和"第 i 行"。行落在哪个块由块大小算出，缓存最近 8 块，超出按 LRU 淘汰。cell view 必须复用，列宽在数据装载后批量设置，不在 viewFor 里计算。

备选：SwiftUI Table。十万行就会卡，直接排除。

### D8 错误分三层

DuckDBKit 抛底层错误；Features 把它映射成 ImportError，带 userMessage、technicalDetail、recoverySuggestion 三个字段；界面只渲染这一种错误卡片。

理由：需求要求"错误一律给出哪一步失败、原始报错、下一步"，三层结构能让每个错误都凑齐这三样，不会有的地方只弹一句"打开失败"。

### D9 应用壳用 NavigationSplitView

左栏 List，中栏 VStack（网格加可折叠底栏占位），右栏用 inspector 修饰符。左右栏的显示状态用 @AppStorage 持久化。

### 模块与依赖方向

    TableWorkbenchApp  →  Features  →  DataGrid
                              ↓
                          DuckDBKit

DuckDBKit 不依赖任何上层模块。DataGrid 只依赖 DuckDBKit 里的行数据类型，不依赖 Features。

文件布局：

    app/
    ├── Package.swift
    ├── Sources/
    │   ├── TableWorkbenchApp/   App 入口、窗口、菜单
    │   ├── Features/            导入流程、状态模型、错误映射
    │   ├── DataGrid/            NSTableView 桥接、块缓存
    │   └── DuckDBKit/           协议、真实实现、假实现、类型映射
    └── Tests/DuckDBKitTests/

### 一次打开的数据流

1. 用户拖入文件，Features 收到 URL。
2. 读前 64KB 判断编码；非 UTF-8 就转码到临时文件。
3. DuckDBKit 创建只读连接，把文件挂成视图，读出列名与类型。
4. 查询总行数，创建表格模型。
5. 网格请求第 0 块，DuckDBKit 执行 LIMIT 5000 OFFSET 0。
6. 结果转成行数组，回到主线程刷新表格。
7. 滚动到 4500 行附近时预取下一块，用户感知不到等待。

## Risks / Trade-offs

- [duckdb-swift 拉不下来] → 先重试，再用 codeload 下 v1.1.3 压缩包做本地路径依赖；两者都失败就把 DuckDBKit 切到假实现，保证壳和网格可编译，依赖恢复后替换。
- [v1.1.3 与 Swift 6.4 不兼容] → 换 main 上的具体 commit 并锁 revision，把编译错误和解决方式记进决策文件；再不行就评估降级工具链。
- [OFFSET 深分页变慢] → 基准里单独测第 1、10、100、200 块的耗时，超过 200 毫秒就启用 rowid 物化方案。
- [GBK 转码拖慢首次打开] → 状态栏显示"转码中"，并把转码耗时单独计时；首次打开目标从 2 秒放宽到 3 秒，README 里按实测数字写。
- [没有 Xcode 导致菜单和窗口行为与正式包不同] → 在 design 和后续任务里记录差异，打包阶段集中修；不把开发期行为当成最终验收。
- [NSTableView 列宽计算拖慢首屏] → 列宽按表头文本和样本值估算一次，滚动中不重算；列数超过 200 时用固定宽度。

## Migration Plan

这是新增功能，没有数据迁移。回滚方式是删除 app/ 与 scripts/，不归档这个 change；已归档的 specs 只有在 change 归档后才生成，本阶段不存在。

## Open Questions

无。产品名、Bundle ID、许可证都不影响本 change 的代码结构，按 R-DEC-06 和 R-DEC-07 后续再定。
