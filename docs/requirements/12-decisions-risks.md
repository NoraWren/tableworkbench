# 12 决策、待验证事实与风险

这一份是唯一允许写"技术结论"的地方。每条都标注它是已验证、待验证，还是待你拍板。

## 已验证事实（2026-10-23 实测）

| 事实 | 怎么验的 |
|---|---|
| 本机 macOS 27.0.1，build 26A434，arm64 | sw_vers、uname -m |
| 已装 Swift 6.4，命令行工具可用 | swift --version |
| Xcode 未安装，xcodebuild 不可用，xcode-select 指向 CommandLineTools | xcodebuild -version 报错原文 |
| 仓库为空，master 分支没有任何提交 | git log |
| GitHub 直连不稳定，git ls-remote 出现 SSL_ERROR_SYSCALL | git ls-remote duckdb-swift 失败 |
| duckdb/duckdb-swift 仓库存在，139 star，最近一次推送 2026-09-28，许可证 MIT | GitHub API |
| duckdb-swift 是 SPM 包，README 写明一行接入，自带 SwiftUI playground 示例 | 抓取 README |
| **duckdb-swift 最新正式 tag 是 v1.1.3（2024-11-04）**，之后全是 v1.1.4-devN、v2.1.0-devN 这类快照 tag，共 300+ 个 | GitHub tags 接口翻三页 |
| CoreXLSX 仓库存在，906 star，最后推送 2024-03-25，许可证 Apache-2.0 | GitHub API |
| DuckDB 1.1.3 的 read_csv 把空字段读成 NULL，带引号的空串也一样 | 本地测试程序实测 |
| 只用 Command Line Tools 时，SwiftUI 的 @State 等宏与 XCTest 都不可用 | 编译与 swift test 实测 |
| duckdb-swift 1.1.3 的调用链是 Database(store:) → connect() → query(sql) → ResultSet.column(at:).cast(to:) | 探针程序编译并运行通过 |
| cast(to: String.self) 只对 VARCHAR 列有值，其他类型返回 nil，所以块查询在 SQL 里统一 CAST AS VARCHAR | 探针实测 |
| Command Line Tools 下 .xctest 打包会在 codesign 与 CopySwiftLibs 失败，本项目改用测试可执行程序 | swift test 实测 |
| 分块 CSV 导出在 328 万行上超过 80 秒，rowid 区间过滤每块仍全表扫；COPY 是唯一快路径 | 基准程序实测 |
| macOS 14 之后未打包的进程无法可靠激活，open -a 的多文件事件也收不到 | 实测，改用开发用 .app bundle |
| SwiftUI WindowGroup 在 open 事件下会开多个窗口，Window 场景只保留一个 | 实测 |
| Bundle ID 使用 dev.kongqi.tableworkbench | Info.plist，随 R-DEC-06 定名同步 |
| duckdb-swift 锁定 exact 1.1.3，SPM 解析通过 | app/Package.swift |
| CSV、TSV、Parquet、xlsx 四条导入链路都能打开；xlsx 6.2 MB、19.9 万行首次 7.23 秒、二次 0.04 秒 | 测试程序与 bench |
| GB18030 先转成 UTF-8 再交给 DuckDB，中文列名与内容不乱码 | gbk-sample.csv 实测 |
| 500 MB CSV 打开 0.79–1.33 秒；1 GB CSV 首次 4.78 秒、命中缓存二次 1.76–2.19 秒 | scripts/bench.sh 与 1gb.csv |
| 分发包改用 release 构建：dmg 15 MB，解压后的 app bundle 53 MB（debug 构建分别是 27 MB 和 109 MB） | make-dmg.sh、du |
| 冷启动（release，`open -a` 到带标题主窗口，忙等）八批 152 轮中位 0.497 秒、最大 0.563 秒、p95 0.537 秒，超 0.6 秒 0/152；首轮冷读 0.49–1.64 秒 | scripts/bench-launch.py 跑八批 |
| 多出的 0.14 秒在 `willFinish → didFinish` 的系统菜单构建（`NSTextInputMenu` → `isWritingToolsAvailable` → `dlopen`）；`strip -x` 无改善，dyld 不是瓶颈 | 临时打点 + 70 KB 最小 SwiftUI app 对照 |

## 待验证事实（不许当成结论写进代码）

| 待验证项 | 验证方式 | 影响 |
|---|---|---|
| NSTableView 在 1000 万行下的真实帧率 | 实测 | 决定是否需要进一步降级渲染 |

## R-DEC-01 用 SwiftUI 原生，不用 Tauri 或 Electron

- 优先级：P0
- 状态：已定
- 结论：SwiftUI + AppKit 桥接 + DuckDB。
- 理由：目标用户是 Mac 用户，对原生感敏感。包体积 15 MB 对 130 MB 是叙事上的硬差异，而"用 Swift 写的原生 Mac 应用"在 2026 年的 HN 上是加分项。
- 代价：团队没写过 Swift，多两周学习成本；AppKit 桥接占三成工作量。
- 推翻条件：第 2 周技术验证过不了 R-MS-02 的三条放行门槛。
- 依赖：R-MS-02

## R-DEC-02 只读、不落盘的查询模型

- 优先级：P0
- 状态：已定
- 结论：连接只读；允许临时表；不写回源文件。
- 理由：用户粘进来的 SQL 可能带破坏性语句，而"数据不出本机"是卖点，改坏文件会直接毁掉口碑。
- 代价：用户想让工具清理数据时做不到，需要自己导出。
- 推翻条件：无，这条不翻。
- 依赖：R-SQL-02

## R-DEC-03 Parquet 作为唯一缓存格式

- 优先级：P0
- 状态：已定
- 结论：CSV 和 Excel 首次导入转 Parquet，之后统一读 Parquet。
- 理由：一次转换换掉后续所有慢。同时让"700 MB CSV 第二次 0.8 秒"这种 demo 成为可能。
- 代价：磁盘占用约为源文件的 30% 到 80%，需要上限和淘汰策略。
- 推翻条件：无。
- 依赖：R-IMP-05

## R-DEC-04 不上 App Store

- 优先级：P0
- 状态：已定
- 结论：Developer ID 签名 + 公证 + dmg 直接分发。
- 理由：App Store 要开沙盒，本地文件的自由访问会处处受限；审核周期对首发传播是风险。
- 代价：99 美元一年，且要先办下来。
- 推翻条件：无。
- 依赖：R-REL-01

## R-DEC-05 Excel 读取路线

- 优先级：P0
- 状态：已决定
- 结论：走 C 的变体。CoreXLSX 只用来读工作簿和工作表路径，ZIPFoundation 解压容器，自写流式 XMLParser 把单元格写成临时 UTF-8 CSV，再走 CSV 现有的物化与 Parquet 缓存链路。
- 实测：6.2 MB、3 个工作表、首表 199,000 行 × 5 列的样本，首次打开 7.23 秒，二次 0.04 秒，Parquet 缓存 2.8 MB。CoreXLSX 自带的 Codable 解析在同一个文件上超过 2 分 30 秒，因此只保留它的元数据能力。
- 未验证：excel 扩展路线（需要联网下载扩展，与默认离线冲突，没有实测）；20 MB 的更大样本。
- 理由：流式解析把内存峰值压住，且 Excel 与 CSV 共用同一条缓存与取数链路，测试面最小。
- 依赖：R-IMP-06

## R-DEC-06 产品名与 Bundle ID（待你拍板）

- 优先级：P0
- 状态：待决策
- 需要：一个英文名（GitHub 仓库名、包名）、一个中文名（可选）、一个 Bundle ID 前缀。
- 约束：
  - 英文名要能被搜到又不撞现有项目，先查 GitHub、Homebrew、App Store 是否重名。
  - 不要用"Table""Sheet""Data"这类泛词单独做名字。
  - Bundle ID 用维护者域名反写，当前为 dev.kongqi.tableworkbench。
- 影响：不定的后果是包名、目录名、README 全要返工一次。

## R-DEC-07 开源主体与许可证（主体待拍板）

- 优先级：P0
- 状态：许可证已定 Apache-2.0，LICENSE 与 NOTICE 已入库；开源主体待确认
- 建议：以公司名义开源，许可证用 Apache-2.0。
- 理由：Apache-2.0 比 MIT 多一条明确的专利授权，对公司合作方更友好；同时保留将来做商业版的空间。
- 需要确认：职务作品的著作权归属是否已有制度文件；对外开源是否需要内部审批。
- 影响：许可证决定后写进 LICENSE，并且要在发布前定，不能事后改。

## R-DEC-08 语言与本地化

- 优先级：P1
- 状态：已定
- 结论：界面先只做中文，代码与提交信息用中文，README 用英文。
- 理由：主受众是海外开发者，README 英文是硬要求；界面中文不影响海外用户看 GIF 理解产品。
- 代价：海外用户装完看到中文界面可能有落差，README 里要写明。
- 推翻条件：首发后英文用户占比超过一半，再补英文界面。
- 依赖：R-REL-03

## R-DEC-09 不做插件体系

- 优先级：P1
- 状态：已定
- 结论：v0.1 不留插件接口，也不为"将来可能扩展"做抽象。
- 理由：抽象的成本现在就付，收益要等到有人真的来写插件。
- 推翻条件：v0.2 之后有明确的外部需求。
- 依赖：R-SCOPE-06

## R-DEC-10 不采集任何使用数据

- 优先级：P0
- 状态：已定
- 结论：不接统计 SDK、不做崩溃上报、不做使用行为采集。
- 理由：卖点是数据不出本机，任何上报都会自相矛盾。
- 代价：出了问题只能靠用户描述。
- 推翻条件：无。
- 依赖：R-REL-05

## R-DEC-11 AI 分析放在 v0.2，默认关闭

- 优先级：P1
- 状态：已定
- 结论：v0.1 不含 AI。v0.2 第一件事做 AI 分析，默认关闭，用户配置模型后才启用。
- 用户确认：2026-10-23，同意排在 v0.1 之后，不提前，不砍透视表。
- 理由：v0.1 十二周已满，AI 需要三周。默认关闭保证"数据不出本机"这句话在没配置时是真话。
- 代价：首发版本少了 2026 年最有话题性的功能，演示视频里没有 AI 镜头。
- 推翻条件：用户愿意砍掉透视表换 AI 提前。若如此，第 7–8 周改为 AI 基础链路，透视表挪到 v0.2。
- 依赖：R-MS-10、R-AI-01

## R-DEC-12 只做两种模型协议

- 优先级：P1
- 状态：已定
- 结论：只实现 OpenAI 兼容与 Anthropic Messages。其他厂商用兼容端点或自定义 Base URL 接入。
- 理由：这两种覆盖了绝大多数云端服务和本地推理框架（Ollama、LM Studio、vLLM 都提供 OpenAI 兼容接口）。每多一种协议就多一套流式解析和错误映射。
- 代价：少数只提供私有协议的厂商接不进来。
- 推翻条件：有明确用户群体要求，再按需增加。
- 依赖：R-AI-03

## R-DEC-13 发送数据的最小化规则

- 优先级：P0
- 状态：已定
- 结论：默认只发表结构、当前筛选、总行数、20 行均匀样本和本地算好的列统计，上限 32 KB。敏感列默认打码，发送前必须给出可展开的预览。
- 理由：模型不需要全表也能写出正确的 SQL。发得越少，用户越敢开这个功能。
- 代价：极少数问题需要用户手动加大样本才能问清楚。
- 推翻条件：无。
- 依赖：R-AI-10、R-AI-09

## R-DEC-14 大导出暂不做进度与取消

- 优先级：P2
- 状态：已定
- 结论：导出继续用 DuckDB 的 COPY，一条语句写完；不提供百分比进度，取消只在开始前生效。
- 理由：尝试按 rowid 区间分块写 CSV，328 万行跑了 80 秒以上，原因是每块都触发全表扫描，比 COPY 慢一个数量级。为了进度条牺牲十倍速度不值得。
- 代价：R-EXP-02 的进度和取消没有完全满足，大导出期间界面只能显示"正在导出"。
- 推翻条件：duckdb-swift 暴露查询进度或 interrupt，或者改为后台进程导出。
- 依赖：R-EXP-02

## R-DEC-15 DuckDB 内存上限做成两级：导入期 1.4 GB，物化后收回 1200MB

- 优先级：P1
- 状态：已定（2026-10-27 改写，上一版是「全局 1200MB」）
- 结论：连接打开后先 `SET memory_limit` 成导入上限，基础数据物化完成立刻收回常驻上限 1200MB。导入上限只对 64 MB 以上的 CSV 生效（`importMemoryLimitBytes = 1_400_000_000`），Parquet 走视图、小文件用不上，两者都保持 1200MB。临时目录仍指向会话自己的 temp 目录。
- 实测（500 MB CSV 冷打开，每轮先清缓存）：

| memory_limit | 打开秒 | 峰值 RSS |
|---|---|---|
| 1200MB | 1.96–2.08 | 1.18–1.30 GB |
| 1300MB | 1.96–2.08 | 1.18 GB |
| **1400MB** | **1.51–1.53** | **1.28–1.29 GB** |
| 1600MB | 1.52–1.62 | 1.29 GB |
| 2000MB | 1.47–1.66 | 1.34 GB |
| 3000MB | 1.59–1.84 | 1.40 GB |
| 4GB | 1.74–2.13 | 1.43 GB |

  1400MB 是拐点，再往上没有额外收益、峰值反而涨。其他数据集 1200MB → 1400MB：1 GB CSV 3.55–3.79 秒降到 2.92–3.12 秒（峰值 1.55 → 1.73 GB）、1000 万行 5.27 降到 4.80 秒（1.59 → 1.73 GB）、wide-3000 0.523 降到 0.431 秒，两个 Parquet 都是 0.02 秒级没变化。
- 理由：R-PERF-01 是 P0，要求 500 MB CSV 首次打开不超过 2 秒，卡在 1200MB 时一直贴着甚至超预算。既然瓶颈是导入期的工作集而不是常驻占用，就应该把两件事分开：导入期给足，物化完立刻收回。全局抬到 1.4 GB 也能达标，但会让常驻期白白多占 200 MB 额度，没有必要。
- 代价：1 GB CSV 的导入峰值从 1.55 GB 涨到 1.73 GB。R-PERF-06 量的是打开之后的静置稳态匿名页（实测空载基线 662 MB、静置后 258 MB、相对基线 −404 MB），不是导入那一瞬间的尖峰，所以这条不算违反 R-PERF-06；但如果将来要开 10 GB 级 CSV，得给导入上限补个天花板。
- 未验清：1200MB 到底让 DuckDB 多花了哪一步，还没查到底。`duckdb_temporary_files()` 全程 0 字节，说明不是肉眼可见的落盘；单线程 4.33 秒、双线程 3.08 秒、默认 2.0 秒，更像是被上限压住时并行度起不来。这是推断，不影响结论（拐点两侧都有重复测量）。
- 推翻条件：出现能在 1200MB 下把 500 MB CSV 打开压到 1.6 秒的方案；或者内存预算收紧到导入峰值也不许超过 1.5 GB。
- 依赖：R-PERF-01、R-PERF-06

## R-DEC-16 冷打开超预算，按实测写进 README

- 优先级：P0
- 状态：~~已定~~（已被 R-DEC-15 的导入期内存上限推翻，2026-10-27）
- 归档说明：结论保留作历史记录。这条当时的判断是「瓶颈是解析吞吐本身，2.0–2.4 秒压不下去」，实测证明瓶颈是 memory_limit，抬到 1.4 GB 后中位 1.546 秒。下面的「归因」「未采用的加速」两段作废，README 已改。
- 结论：500MB CSV 冷打开保持现在的实现，实测 2.0–2.4 秒（多次运行波动），贴着 R-PERF-01 的 2 秒预算；README 第一屏写“首次 2.1–2.4 秒”，命中缓存另算（现在是 0.02–0.06 秒）。
- 归因：打开耗时 99% 在 `read_csv_auto` 的全量解析（物化 __base），DESCRIBE 与 count(*) 各 2 毫秒；usr 8.7 秒 / 墙钟 2.6 秒说明已经在并行解析，瓶颈是解析吞吐本身。
- 未采用的加速：绕过 auto_detect 自己嗅探列类型再传 `columns`，理论上省 10% 左右；但类型推断一旦与 DuckDB 不一致就会导错列（例如前导零被当数字），风险大于收益。
- 原因：耗时全部落在 500MB 文本的全量解析上，要压到 2 秒以内只能换解析器或改变“打开即物化”的模型，两者都影响后面所有查询的实现。
- 代价：第一屏数字不好看。用户拖进大文件要等两秒多，第二次打开才有“秒开”的体验。
- 推翻条件：接入更快的 CSV 解析路径，或者改成先建视图、首屏只查前 5000 行、行数后台再补。
- 依赖：R-PERF-01、R-IMP-05

## R-DEC-17 Parquet 源不物化（已实施）

- 优先级：P0
- 状态：已定
- 事实：打开 Parquet 时执行 CREATE TABLE “__base” AS SELECT * FROM read_parquet(...)，1000 万行 7 次实测 2.12–3.51 秒，中位数 2.65 秒，4 次在 3 秒内；R-PERF-01 的预算是 3 秒，只能算半数达标。
- 做法：Parquet 源只建视图，用 read_parquet(..., file_row_number=true) 提供 __rid；取块按 __rid 区间过滤并排序，筛选/排序后的 __result 仍用 rowid。data 视图只列真实列，不暴露 __rid。
- 分段计时（release，10m.csv，TW_OPEN_TIMING=1）：物化 __base 2.00 秒，DESCRIBE 2 毫秒，count(*) 3 毫秒。
- 实测：打开 2.48 → 0.028 秒；第 1/10/100 块 0.53–0.62 → 0.045–0.057 秒；328 万行排序准备 1.96 秒、之后各块 0.13 秒；1000 万行排序准备 18.2 秒、之后各块 0.39 秒。500MB 文件峰值 RSS 从 187 MB 降到 83 MB。
- 代价：第一次排序要物化 __result，1000 万行约 18 秒，期间界面只能显示“正在查询”。CSV 源不受影响，仍走物化表。
- 推翻条件：如果后续要给排序加进度或取消，或 18 秒被用户判定不可接受，再考虑分块物化。
- 依赖：R-PERF-01、R-PERF-03、R-PERF-06

## R-DEC-18 宽表滚动的代价（已优化：单元格自绘）

- 优先级：P1
- 状态：已定
- 事实：滚动基准在 20 列时每帧 2.4–2.7 毫秒，100 列升到中位 11.2 毫秒、p95 19.1 毫秒，200 列中位 22.4 毫秒。R-PERF-03 要求 100 列不掉帧，目前没过。
- 原因：每帧要更新列数 × 可见行数的 NSTextField，200 列时约 5000 个，控件布局与校验把 16.7 毫秒吃完了。
- 做法：新增 GridTextCellView，直接画 NSAttributedString，不再用 NSTextField；选中背景仍由 NSTableView 画，tooltip 与截断保留。
- 结果：100 列 p95 从 19.08 降到 3.09 毫秒，200 列从 25.44 降到 8.04 毫秒，三种规模都回到预算内。数字见 docs/bench-history.md。
- 代价：单元格不再可编辑（本来也是只读分析器），文本间距与行高用固定常量。
- 依赖：R-PERF-03、R-GRID-08

## R-DEC-19 透视在应用里比基准慢一个量级（已定位：调试构建）

- 优先级：P1
- 状态：已定
- 事实：同样的分组聚合，基准程序里 0.07 秒，应用里点“生成图表”1.13–1.16 秒（界面显示的耗时就是 pivot 自己量的）。328 万行五个分组，数据量不构成原因。
- 已完成一：去掉 pivot 在聚合前单独跑的 DISTINCT 计数，改成聚合时多取一行判断基数。应用内从 2.75–3.12 秒降到 1.13–1.16 秒，基准从 0.15 秒降到 0.07 秒。
- 已完成二：临时目录检查发现会话没有落盘（所有 tableworkbench-* 目录都是空的），排除内存上限落盘的猜测。
- 根因：应用包一直用调试构建（make-app-bundle.sh 默认 BUILD_CONFIG=debug）。同一份 TableWorkbenchBench，release 透视 0.07 秒，debug 透视 3.83–3.96 秒，差 50 倍。行数转字符串这一步在 debug 下带边界检查与未优化代码，是主要开销。
- 结论：出图慢不是 SQL 或数据量的问题，而是打包配置问题。发版和演示一律用 BUILD_CONFIG=release 构建；R-VIZ-01 的 1 秒目标在 release 下成立。
- 代价：debug 包只适合调试，不能拿它测性能或录演示。
- 依赖：R-PVT-01、R-PERF-01

## R-DEC-20 冷启动达标，多出的 0.14 秒落在系统菜单构建，不优化

- 优先级：P0
- 状态：已定（2026-10-27）
- 事实：release 构建跑八批共 152 轮（负载 4.8–12.1），去掉每批首轮后中位 0.497 秒、最小 0.465、最大 0.563、p95 0.537，超 0.6 秒预算 0/152；各批中位只在 0.489–0.502 之间。首轮冷读 0.493–0.599 秒，单独标注。脚本是 `scripts/bench-launch.py`（会打一行系统负载，跑出来的数字要连着它看）。上一轮（2026-10-26）手工量的 0.55–0.63 秒已作废为历史记录。
- 擦线超的两次：整轮测量里只出现过 2 次，一次 0.608 秒（负载 24.5，Chrome 与 Codex 同时开着），一次 0.642 秒（负载 8.7，但 Codex 渲染进程占 70% CPU）。同批中位没有跟着涨（0.506、0.557），更像是系统把那一轮挤了一下；没做定位，也没当异常值删掉。
- 分段（直接 exec 口径，与 70 KB 最小 SwiftUI 空窗口 app 对照）：exec → App.init 0.013 对 0.007；→ willFinishLaunching 0.105 对 0.099；→ didFinishLaunching 0.245 对 0.102；→ 窗口出现 0.065 对 0.020。合计约 0.43 对 0.23。
- 归因：多出的 0.143 秒在 `willFinish → didFinish`，采样落在 `AppDelegate.makeMainMenu` 里 `NSTextInputMenu` 初始化 → `NSWritingToolsCoordinator isWritingToolsAvailable` → `dlopen`，以及 MenuBarClientCore 的软链接加载。
- 已验证否掉的：dyld 不是瓶颈。`strip -x` 后 0.371 对 0.364 秒，无改善；`willFinishLaunching` 前的 0.10 秒在最小 app 上一样有，是 AppKit 固定开销。
- 结论：指标已达标，不为这 0.14 秒改菜单构建方式。能否绕开没验，动的是产品要的菜单项与快捷键，收益不明、回退风险清楚。
- 没查到底的：上一轮 0.55–0.63 与这一轮 0.465–0.563 的差异。轮询间隔（上一轮 10 毫秒、这一轮忙等）、系统状态、当时的并发进程三条都对不上 0.1 秒这个量。
- 依赖：R-PERF-04、R-REL-02

## R-DEC-21 Xcode 27.1 已装，构建目录挪出 iCloud

- 优先级：P0
- 状态：已定（2026-10-28）
- 事实：Xcode 27.1（27A9275）已从 App Store 安装，App Store 顺手把 `xcode-select` 指到了 Xcode，许可通过界面接受。实测可用的东西：`xcodebuild -version` 有输出；`@State`/`@Bindable`/`#Preview` 探针能编译（此前只有 @Observable 能过，因为 Observation 的宏一直在命令行工具链里）；XCTest.framework 与 Testing.framework 都在 `Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks`（后者要自己带 `-F`，SwiftPM 的测试 target 会自动带）；Instruments.app 在位。
- 撞到的坑：仓库在 ~/Documents（iCloud）下。默认的 SwiftBuild 后端给资源包签名时被 fileprovider 的扩展属性挡住——`resource fork, Finder information, or similar detritus not allowed`；换成 `--build-system native` 后不签资源包，但会一直空转到 CodeSigningHelper，两小时后仍未出二进制。把 scratch 目录挪到 `~/Library/Caches/tableworkbench-build` 之后，native 后端下 release 全量（含 DuckDB 的 C++ 部分）能编完，打出来的 .app 打开 wide-100k.csv 正常显示 100000 行。
- 落地：`scripts/make-app-bundle.sh` 与 6 个 build/bench 脚本都改成 `--build-system native --scratch-path "$scratch"`，`scratch` 默认 `~/Library/Caches/tableworkbench-build`，可用 `TW_BUILD_DIR` 覆盖。仓库内的 `app/.build` 已清掉，避免再往里写。
- 代价：`--build-system native` 已标弃用，SwiftPM 迟早会删。真删了就得把仓库搬出 iCloud，那才是根治。
- 没做的：界面层仍是 ObservableObject 加 @StateObject，测试仍是 TableWorkbenchTests 可执行程序。宏和测试框架现在都可用，但迁移是影响几十个文件的机械改动，用户感知为零，安排在发布之后。
- 推翻条件：如果将来必须在 iCloud 里构建（比如云盘协作），那就不是换参数的问题，得换仓库位置。
- 依赖：R-MS-01

## R-DEC-22 首屏取块改用 LIMIT/OFFSET，NSTableView 不按 300 万行接数据源

- 优先级：P0
- 状态：已定（2026-10-28）
- 事实：R-IMP-01 第一条验收是「拖入 500MB CSV，从松手到表格可滚动不超过 2 秒」。用应用内打点（TW_OPEN_TIMING）量 release 冷开，改前 2.54 秒，拆成四段：read_csv_auto 物化 __base 1.57–1.82 秒、网格视图搭建 0.65 秒、首块取数 0.03 秒、首帧绘制 0.21 秒。之前记的 2.8–2.9 秒是 debug 产物，不能当基线。
- 两处开销的来源：一是取块 SQL 用虚拟 rowid 过滤（WHERE rowid >= a AND rowid < b），DuckDB 用不上统计信息，每取一块都把 326 万行扫一遍，实测 0.40 秒；二是给 NSTableView 设 dataSource 时它按 numberOfRows 把 326 万行记进内部结构，0.57 秒。
- 落地：物化表取块改成 LIMIT size OFFSET offset（第 1 / 100 / 200 块 0.03 / 0.09 / 0.14 秒），顺序靠 preserve_insertion_order 与 __result 的插入序；Parquet 视图那条路不动，仍按 __rid 过滤。网格改成先按 0 行接上 dataSource，视图搭完再 reloadData 带真实行数。五次冷开中位 1.912 秒（1.871–2.148），滚动回归 300 帧 p95 1.34 ms、超预算帧 0。
- 代价：取块顺序依赖插入序而不是显式 ORDER BY。preserve_insertion_order 在 DuckDB 里默认开着，但它是会话级开关，将来有人关掉它，行序会散，取块 SQL 的注释要与这条记录一起看。
- 被否决：给 __base 加一列 row_number() OVER () AS __rid 靠 row group 裁剪（物化从 1.6 秒涨到 5.2 秒，取块没变快）；保留导入期 1.4 GB 上限不收回（取块时间不变）；把缓存转换延后（时间不变，不是它抢的 CPU）。
- 没做到：最慢那轮 2.148 秒仍超预算，超在 CSV 解析本身；缓存命中的 Parquet 视图首块仍是 0.7 秒。两件都留给下一轮，README 不许写成「已经 1.5 秒」。
- 推翻条件：DuckDB 将来给 rowid 加上裁剪，或者改成先建视图、首屏只查前 5000 行、行数后台再补。
- 依赖：R-PERF-01、R-IMP-01、R-GRID-02

## R-DEC-23 排序与筛选物化期间临时借内存上限

- 优先级：P0
- 状态：已定（2026-10-28）
- 事实：R-GRID-04 / R-GRID-05 的两条秒数验收一直没达标（千万行排序 24.69 秒、等值筛选 1.51 秒）。打点拆开看，24.71 秒里有 24.69 秒耗在同一条 CREATE TEMP TABLE __result AS SELECT ... ORDER BY 上，随后 count 只要 0.07 秒。把内存上限从常驻的 1200MB 抬到 4 GB 再跑，同一份数据 7 秒上下，说明大头是被常驻上限逼着落盘，不是排序算法慢。
- 落地：apply(view:) 物化 __result 期间把 memory_limit 临时抬到 min(物理内存的一半, 4 GB)，建完用 defer 收回 1200MB，常驻占用不变。实测排序 5.15–7.82 秒、等值筛选 0.86–0.89 秒（筛选因此达标），500MB 排序 0.71 秒。
- 代价：物化那一刻的峰值内存会涨。10m.parquet 排序期间整进程 RSS 峰值 5.6 GB（16 GB 机器），期间如果同时开别的重应用可能触发交换。上限取物理内存的一半就是为了在 8 GB 机器上自动收窄。
- 没做到：千万行排序仍未进 3 秒预算，最好 5.15 秒。彻底达标要换模型（先按原表顺序出首屏、后台再物化排序结果），属于下一轮的结构性改动。
- 推翻条件：如果 DuckDB 能对 ORDER BY 做外部归并且不重建全表，或者界面改成首屏不依赖排序结果，这条就作废。
- 依赖：R-GRID-04、R-GRID-05、R-PERF-01

## 风险清单

| 编号 | 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|---|
| R-RISK-01 | 团队没写过 Swift，第 2 周验证期超时 | 中 | 高 | 验证期只做一条链路，做不完就砍功能，不加人 |
| R-RISK-02 | duckdb-swift API 与预期差距大，封装成本翻倍 | 中 | 中 | 第 1 周先写最小验证程序，把真实 API 记进本文件 |
| R-RISK-03 | 包体积因静态链接 DuckDB 超过 30 MB | 中 | 中 | 提前实测；超了就改 README 的目标数字，不隐藏 |
| R-RISK-04 | 签名账号审批拖延，卡在发布 | 中 | 高 | 第 1 周就提交申请 |
| R-RISK-05 | 首发无人转发，star 停在三位数 | 中 | 高 | GIF 与 README 提前两周做好，六个渠道分头写文案 |
| R-RISK-06 | Excel 格式千奇百怪，导入投诉集中爆发 | 高 | 中 | v0.1 README 明确写"只读值、不读样式"，并把已知限制列三条以上 |
| R-RISK-07 | GitHub 网络不稳，依赖拉不下来拖慢开发 | 中 | 中 | 先配好代理或本地镜像，把依赖 vendored 一份备份 |
| R-RISK-08 | 做成"又一个表格工具"，没有差异化记忆点 | 中 | 高 | 只讲三个数字和一个价值观，功能列表不上第一屏 |
| R-RISK-09 | 模型生成的 SQL 看似合理但结果错，用户不再信任 | 高 | 高 | 一律先展示 SQL 再执行；一键洞察带验证 SQL；文档里写明 AI 可能出错 |
| R-RISK-10 | 用户担心数据外发，AI 功能不敢开 | 中 | 高 | 默认关闭、发送预览、敏感列打码、本地模型预设，四件事都在界面上说清楚 |
| R-RISK-11 | 各家兼容接口细节不一致，流式解析踩坑 | 中 | 中 | 只支持两种协议，先用 mock 服务和三家真实端点各测一轮 |

## 补充：duckdb-swift 的版本是个坑

仓库天天在推，但正式 tag 只到 2024 年 11 月的 v1.1.3，之后发布的都是带 dev 号的快照。这意味着 Package.swift 里写 `.upToNextMajor(from: "1.0.0")`，SPM 会给你解析到 2024 年的版本，等于用两年前的东西。

两个选择：

- 锁 `revision:` 到 main 上一个验证过的 commit。能拿到新特性，但升级要手动改哈希，出问题也不好查。
- 锁 v1.1.3。稳，但可能是旧的 DuckDB 内核，read_xlsx 之类的扩展不一定能用。

先都跑一遍再定，结论记进这张表的"已验证事实"，不要凭印象选。
