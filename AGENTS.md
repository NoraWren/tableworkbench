# AGENTS.md

这个文件是仓库的入口。动代码之前先读完它，再按需要打开 `docs/requirements/` 下的文件。

本仓库的文档、代码注释、提交信息、与用户的对话，一律用中文。

## 1. 一句话

给本地大文件一个现代的分析界面：拖进 CSV、TSV、Parquet、Excel，秒开，能排序、筛选、跑 SQL、拖透视表，全程数据不出本机。

它是分析器，不是编辑器。改数据交给 Excel，看懂数据交给它。

对外只讲一句对比，数字必须实测后再写进 README：Excel 打开要三分钟的文件，这里 0.3 秒。

## 2. 为什么做这个

用户 2026-10-23 定的目标：给公司挣一个拿得出手的开源作品，判断标准是"有没有人转发"，不是"有没有人天天用"。

这条目标决定了三件事，优先级从高到低：

1. **演示效果。** 每个功能都要能录进 30 秒的 GIF，录不进去的功能不做。
2. **能验证的硬指标。** 打开速度、滚动帧率、包体积，三个数字写在 README 第一屏。
3. **功能数量。** 宁可少做三个功能，也要把这三个数字做实。

## 3. 当前状态

2026-10-24：v0.1 主体已经能跑。CSV/TSV/Parquet/xlsx 导入、分块网格、排序筛选、SQL 抽屉、透视、列检查器、导出和 dmg 打包都已实现，bench-data 下有 500MB 与 3000 列两份测试数据。

未完成的主要部分：Developer ID 签名与公证（缺账号）、滚动帧率实测、30 秒演示录屏。没有 Xcode 时，界面层用 ObservableObject 加 @StateObject，测试用 TableWorkbenchTests 可执行程序跑断言。

本机环境（已实测）：

| 项 | 实测结果 |
|---|---|
| 系统 | macOS 27.0.1（26A434），arm64 |
| Swift | 6.4，Xcode 工具链（`xcode-select -p` 指向 /Applications/Xcode.app/Contents/Developer） |
| Xcode | **已装 27.1（27A9275）**，2026-10-28 从 App Store 安装并接受许可；`@State`/`@Bindable`/`#Preview` 已实测可编译 |
| 构建目录 | **必须落在 iCloud 之外**：`~/Library/Caches/tableworkbench-build`。仓库在 ~/Documents 下，产物放进 .build 会被 fileprovider 拖住，见第 10 节 |
| 网络 | GitHub 直连不稳定，`git ls-remote` 可能失败，首次拉 SPM 依赖需要代理或镜像 |

Xcode 已于 2026-10-28 装好（27.1，27A9275），App Store 安装时把 `xcode-select` 自动指到了 Xcode，`xcodebuild -version` 有输出。许可通过界面接受，没用上 `sudo xcodebuild -license`。

装完之后还没动的两件事：界面层仍在用 ObservableObject 加 @StateObject（宏现在可用了，但换回去是一轮影响几十个文件的机械改动，发布前不做）；测试仍用 TableWorkbenchTests 可执行程序（XCTest 与 Swift Testing 现在都可用，迁移同样留到发布后）。

## 4. 技术栈（已锁定）

| 层 | 选型 | 状态 |
|---|---|---|
| 界面 | SwiftUI，`NavigationSplitView` + `.inspector` | 已定 |
| 数据表格 | AppKit `NSTableView`（view-based），通过 `NSViewRepresentable` 桥接 | 已定，见 R-GRID-01 |
| 查询引擎 | DuckDB 官方 Swift 包 `duckdb/duckdb-swift`，SPM 接入 | 已定，版本首轮集成时锁定 |
| Excel | 待验证：DuckDB excel 扩展 / CoreXLSX / 先转 CSV | 待决策，见 R-DEC-05 |
| 状态管理 | `@Observable`（Observation 框架） | 已定 |
| AI 接入 | OpenAI 兼容与 Anthropic Messages 两种协议，密钥存 Keychain，默认关闭 | v0.2，见 R-AI-01 |
| 最低系统 | macOS 14 | 已定 |
| 分发 | dmg + Developer ID 签名 + 公证，不上 App Store | 已定，见 R-REL-02 |

禁止引入的技术：Electron、任何 WebView 壳、Node 运行时、跨平台 UI 框架。这个项目的卖点就是原生，套壳会直接毁掉叙事。

## 5. 架构原则

四层，依赖单向向下：

```
SwiftUI Views            窗口、侧栏、检查器、工具栏、菜单
      ↓
@Observable 状态层        TableModel / QueryModel / ImportModel / AIModel
      ↓
DataGrid (AppKit)        NSViewRepresentable → NSTableView
      ↓
DuckDBKit               连接、语句、结果集、分块取数
AIClient                协议适配、上下文构造、流式解析（旁路，不碰数据库）
```

四条硬规矩：

1. **一切计算下推给 SQL。** 排序、筛选、聚合、透视都翻译成 SQL 交给 DuckDB，Swift 侧不做全量排序或过滤，也不把百万行读进数组。
2. **UI 只认"块"。** 表格按块取数，块大小 5000 行，最近使用的块留在内存里做 LRU，见 R-GRID-02。
3. **导入一次，之后秒开。** 文本和 Excel 首次打开时转成 Parquet 存本地缓存，之后直接读 Parquet，见 R-IMP-05。
4. **DuckDB 的 C 内存由 DuckDBKit 统一释放。** 结果集、预处理语句、连接都要有明确的关闭路径，不能靠 ARC 猜。
5. **AI 只产文本，不碰数据库。** 模型生成的 SQL 先进编辑器，用户点运行才走 DuckDBKit 的只读通道。
6. **密钥只进 Keychain。** 配置文件、日志、崩溃报告、导出包都不许出现 API Key。

## 6. 需求索引

需求放在 `docs/requirements/`，每个文件一个主题，条目编号形如 `R-IMP-03`。下面的链接都是相对仓库根目录的路径。

| 编号前缀 | 文件 | 覆盖内容 | 优先级 | 状态 |
|---|---|---|---|---|
| R-SCOPE | [docs/requirements/01-product-scope.md](docs/requirements/01-product-scope.md) | 定位、目标用户、场景、非目标 | P0 | 已定义 |
| R-IMP | [docs/requirements/02-data-import.md](docs/requirements/02-data-import.md) | 打开入口、格式矩阵、编码探测、Parquet 缓存、Excel | P0 | 部分待验证 |
| R-GRID | [docs/requirements/03-data-grid.md](docs/requirements/03-data-grid.md) | NSTableView 桥接、分块加载、排序筛选、复制 | P0 | 已定义 |
| R-SQL | [docs/requirements/04-sql-console.md](docs/requirements/04-sql-console.md) | SQL 抽屉、只读边界、取消、历史 | P1 | 已定义 |
| R-PVT | [docs/requirements/05-pivot-table.md](docs/requirements/05-pivot-table.md) | 拖拽透视、聚合、列基数限制 | P1 | 已定义 |
| R-INSP | [docs/requirements/06-column-inspector.md](docs/requirements/06-column-inspector.md) | 列统计、直方图、采样策略 | P1 | 已定义 |
| R-EXP | [docs/requirements/07-export.md](docs/requirements/07-export.md) | 导出 CSV/Parquet、剪贴板、进度 | P1 | 已定义 |
| R-PERF | [docs/requirements/08-performance.md](docs/requirements/08-performance.md) | 性能预算、基准数据集、测量方法 | P0 | 已定义 |
| R-SHELL | [docs/requirements/09-app-shell.md](docs/requirements/09-app-shell.md) | 窗口、菜单、快捷键、深色模式、错误态 | P1 | 已定义 |
| R-REL | [docs/requirements/10-packaging-release.md](docs/requirements/10-packaging-release.md) | 签名、公证、README、GIF、发布渠道 | P0 | 已定义 |
| R-MS | [docs/requirements/11-milestones.md](docs/requirements/11-milestones.md) | 12 周里程碑与放行门槛 | P0 | 前置条件未就绪 |
| R-AI | [docs/requirements/13-ai-analysis.md](docs/requirements/13-ai-analysis.md) | 模型配置、问数、一键洞察、隐私与安全 | P1 | 已定义，v0.2 |
| R-DEC | [docs/requirements/12-decisions-risks.md](docs/requirements/12-decisions-risks.md) | 已定决策、待验证事实、待决策项、风险 | P0 | 3 项待拍板 |
| — | [docs/requirements/README.md](docs/requirements/README.md) | 编号规则、状态图例、写作规范 | — | — |
| — | [docs/requirements/glossary.md](docs/requirements/glossary.md) | 术语表 | — | — |

## 6.1 OpenSpec 工作流

仓库已经用 OpenSpec 管理规格和改动。配置在 [openspec/config.yaml](openspec/config.yaml)，工作流技能在 [.agents/skills](.agents/skills)。

三处文档的分工是固定的，别搞混：

| 位置 | 放什么 | 什么时候写 |
|---|---|---|
| [docs/requirements/](docs/requirements/) | 需求池，编号 R-XXX-nn，带验收、边界、依赖 | 实现之前 |
| [openspec/specs/](openspec/specs/) | 能力契约，描述已经稳定下来的行为 | 一个能力做完之后 |
| [openspec/changes/](openspec/changes/) | 一次改动的提案、设计、任务 | 每次动手之前 |

五条规矩：

1. 任何实现都先有 change。没有 proposal 和 tasks 的改动不开工。
2. proposal 里必须列出对应的需求编号，比如 R-IMP-06。需求全文不复制进 change，引用编号就够。
3. 提案、规格、设计、任务全部用中文写。SHALL/MUST 这类关键字保留英文，细化规则在 [openspec/config.yaml](openspec/config.yaml) 的 rules 段。
4. 归档 change 时，同步更新 openspec/specs 和 docs/requirements 里对应条目的验收勾选，两处都要动。
5. 性能预算和只读约束写在 config.yaml 的 context 里。改动如果绕不过它们，在 proposal 里单列一节写明取舍。

常用命令：

    openspec list                        # 看进行中的 change
    openspec new change <name>           # 新建
    openspec status --change <name> --json
    openspec validate --strict <name>
    openspec archive <name>

## 7. 目录结构（首次实现时创建）

```
本地表格工作台/
├── AGENTS.md
├── README.md                    # 对外门面，发布阶段再写
├── .agents/skills/              # OpenSpec 工作流技能
├── openspec/                    # 规格与改动，配置在 config.yaml
│   ├── config.yaml
│   ├── specs/
│   └── changes/
├── docs/requirements/           # 需求，已存在
├── app/
│   ├── Package.swift            # SPM 工程，DuckDBKit 单独成 target 便于测试
│   ├── Sources/
│   │   ├── TableWorkbenchApp/   # App 入口、窗口、菜单
│   │   ├── Features/            # 导入、网格、SQL、透视、检查器、导出、AI
│   │   ├── DataGrid/            # NSViewRepresentable + NSTableView
│   │   ├── DuckDBKit/           # 连接、语句、结果集、分块、类型映射
│   │   └── AIClient/            # 协议适配、上下文构造、流式解析
│   └── Tests/DuckDBKitTests/
└── scripts/
    ├── make-bench-data.sh       # 生成基准数据集
    ├── bench.sh                 # 跑性能基准并输出报告
    ├── bench-launch.py          # 冷启动计时，脚本自己拉起和退出应用
    ├── bench-record.py          # 跑基准并追加到 docs/bench-history.md
    └── record-demo.sh           # 整屏录一段，按窗口坐标裁成演示 GIF
```

`TableWorkbench` 是模块名占位，产品名待定，见 R-DEC-06。

## 7.1 接手时的第一步

新会话进来，照这个顺序做，不要跳过：

1. 读本文件的第 1、4、5、8 节，知道这是什么、用什么做、守什么规矩。
2. 读 [docs/requirements/12-decisions-risks.md](docs/requirements/12-decisions-risks.md) 的"已验证事实"和"待验证事实"两张表。上一轮验过的东西不要重验，没验过的不要当结论用。
3. 如果写代码，先看 [docs/requirements/11-milestones.md](docs/requirements/11-milestones.md) 里当前周对应的那一条，只看那一条。
4. 要动代码，先跑 openspec list 看有没有进行中的 change；没有就按 [openspec/config.yaml](openspec/config.yaml) 的规则新建一个，提案里引用需求编号。
5. 界面验收按 [docs/manual-verification.md](docs/manual-verification.md) 逐条过，发版按 [docs/release-checklist.md](docs/release-checklist.md) 走。
6. 需要拍板的三件事在最后，其余按文档默认值推进，不用回头问。

## 8. 工作规则

1. 接任务先读本文件、`docs/requirements/README.md`、以及任务相关的需求文件。代码和需求冲突时，以需求文件为准，并把冲突写在回复里。
2. 需求变更先改文档再改代码。编号不复用、不删除，废弃条目保留原文并标"~~已废弃~~（原因）"。
3. [docs/requirements/08-performance.md](docs/requirements/08-performance.md) 里的性能预算是硬约束。为了跑通功能而放宽预算，必须在 `12-decisions-risks.md` 记一条决策，并说明为什么不影响演示。
4. 不许编造 API。DuckDB Swift 包、excel 扩展、CoreXLSX 的实际接口，先写最小验证程序跑通，再把结论记进 `12-decisions-risks.md` 的"已验证事实"。
5. 新增第三方依赖必须先说明三件事：许可证（只接受 MIT / Apache-2.0 / BSD）、最近一次提交时间、对包体积的影响。记入决策文件后再引入。
6. 用户数据不进日志、不上传网络、不进崩溃报告。唯一的网络访问是 DuckDB 扩展下载和更新检查，两者都必须可关闭，且默认不静默联网。
7. 一个可运行状态一次提交。提交信息格式：`feat|fix|perf|docs|chore: 中文描述`。
8. 每完成一个需求条目，在对应文件里勾掉验收项，并更新 `docs/requirements/README.md` 的状态表。
9. 界面文案、示例数据、截图、README 全部自己写。参考开源项目时只看文档和交互，不搬代码、不搬文案、不搬示例数据。

## 9. 验收与运行

```
# 构建（两个参数缺一不可：产物必须在 iCloud 之外，原因见 10 节）
cd app && swift build --build-system native --scratch-path ~/Library/Caches/tableworkbench-build

# 测试（当前用仓库内的测试可执行程序；XCTest 与 Swift Testing 已可用，迁移留到发布后）
cd app && swift run --build-system native --scratch-path ~/Library/Caches/tableworkbench-build TableWorkbenchTests

# 启动应用（开发期直接跑可执行文件）
cd app && swift run --build-system native --scratch-path ~/Library/Caches/tableworkbench-build TableWorkbench

# 组装开发用 .app（macOS 14 之后未打包的进程无法可靠激活）
./scripts/make-app-bundle.sh
open build/TableWorkbench.app
open -a build/TableWorkbench.app file1.csv file2.csv

# 打包 dmg（没有签名证书时是 ad-hoc，Gatekeeper 会拦）
./scripts/make-dmg.sh

# 用 Xcode 打开（没有 .xcodeproj，工程就是 SPM 包；宏与 Preview 在这个环境里才生效）
open app/Package.swift

# 性能基准（M1 之后必须有）
./scripts/make-bench-data.sh && ./scripts/bench.sh
./scripts/bench-record.py      # 跑基准并追加一行记录，退化超过 10% 返回非零

# 冷启动（先装 release 包，脚本自己拉起和退出应用；开头会打系统负载）
BUILD_CONFIG=release ./scripts/make-app-bundle.sh && ./scripts/bench-launch.py --rounds 20

# 录演示 GIF（倒计时结束后自己把动作做完，录完按窗口坐标裁；脚本只负责录与裁）
./scripts/record-demo.sh --geometry "566,60,944,546" --seconds 7 --out docs/media/demo.gif
```

一个需求算完成，要同时满足四条：

1. 需求文件里的验收项全部勾掉；
2. 构建无新增警告；
3. `scripts/bench-record.py` 四项都不比同口径的上一次退化超过 10%（退出码 0）；
4. 能录一段不超过 30 秒的演示，看的人不用解释就明白在干什么。

## 10. 容易踩的坑

- **DuckDB 结果集是 C 内存。** Swift 侧忘记 close 会一天跑出 OOM，所有结果集必须在 DuckDBKit 里包一层 `withQuery` 之类的受控作用域。
- **中文 CSV 多半是 GBK。** DuckDB 默认按 UTF-8 读，遇到 GBK 直接报错或乱码，必须先探测编码再转，见 R-IMP-04。
- **Excel 是脏数据源。** 合并单元格、公式、日期序列号、隐藏行都会让自动推断出错。v0.1 只读单元格的值，公式取缓存值，拿不到就留空并标记。
- **NSTableView 的列宽和复用。** view-based 模式下 cell view 必须复用，列宽计算要在数据变化时批量更新，别在 `viewFor` 里做重活。
- **行号不要用第二张 NSTableView。** 放进 NSScrollView 当行头时尺寸不可控，会被裁成一位数字。用自绘视图跟随主表滚动，见 design D10。
- **Gatekeeper。** 没签名的 dmg 用户打不开，会直接劝退。签名账号要提前一个月办。
- **不要为了快而跳过基准。** 这个项目的全部叙事建在三个数字上，数字虚了，项目就没了。
- **构建目录不能放在 iCloud 里。** 仓库在 ~/Documents 下，fileprovider 会给产物打上 FinderInfo 与 `com.apple.fileprovider.fpfs#P` 扩展属性。默认的 SwiftBuild 后端给资源包签名时直接失败（`resource fork, Finder information, or similar detritus not allowed`），换 native 后端则会在编译完之后空转、停在 CodeSigningHelper 不动。把 scratch 目录挪到 `~/Library/Caches/tableworkbench-build` 之后，release 全量能编完。脚本里已经这么设了（`TW_BUILD_DIR` 可覆盖）。
- **`--build-system native` 已被标弃用。** 现在必须带，原生后端不签资源包。将来 SwiftPM 真删了这个开关，正解是把仓库移出 iCloud，而不是继续加别的绕法。
- **手跑 swift 命令也要带这两个参数。** `swift build --build-system native --scratch-path ~/Library/Caches/tableworkbench-build`。漏掉 scratch 就会在 iCloud 里重建 .build，重新踩上面那个坑。
- **拉 duckdb-swift 要走代理。** 本机系统代理是 127.0.0.1:7897，git 默认不走，首次 resolve 需要设置 HTTPS_PROXY 和 HTTP_PROXY。

## 11. 还需要用户拍板的事

只有三件，其余都可以按文档默认值推进：

1. 产品名和 Bundle ID（R-DEC-06）。
2. 开源主体和许可证（R-DEC-07）。
3. 是否接受 12 周、全职一人的节奏（R-MS-01）。
