# 02 数据导入

## R-IMP-01 打开入口

- 优先级：P0
- 状态：已定义
- 场景：用户拿到一个文件，想立刻看到内容。
- 行为：四个入口，行为一致。
  1. 把文件从 Finder 拖到窗口任意位置，窗口整体高亮后放开。
  2. `⌘O` 打开文件面板，支持多选。
  3. 菜单 File → Open，同一个动作。
  4. 从 Finder 双击已关联的文件类型直接启动应用。
- 验收：
  - [ ] 拖入 500 MB CSV，从松手到表格可滚动，不超过 2 秒（M 系列，SSD，不含首次缓存转换）。接收通路 2026-10-27 已改到窗口层并用回调测过，秒数要真机拖一次才量得出来
  - [x] 一次拖入 5 个文件，5 个都出现在左栏，第一个自动选中（模型测试覆盖）
  - [x] 拖入不支持的格式，给出明确提示并说明支持哪些，不静默失败（.xls 提示“不支持这个文件格式”）
- 边界：不做"打开文件夹批量导入"。多选只处理选中文件，不递归子目录。
- 依赖：R-IMP-05、R-PERF-01

## R-IMP-02 格式矩阵

- 优先级：P0
- 状态：已定义
- 行为：v0.1 支持的格式与处理方式。

| 格式 | 后缀 | 读取方式 | 状态 |
|---|---|---|---|
| CSV | `.csv` | `read_csv_auto`，显式传分隔符、引号、编码 | P0 |
| TSV | `.tsv`, `.tab` | 同上，分隔符固定制表符 | P0 |
| Parquet | `.parquet` | `read_parquet`，直接挂视图 | P0 |
| Excel | `.xlsx` | CoreXLSX 读工作簿元数据，ZIPFoundation 解压，流式 XMLParser 转 CSV 后走缓存链路，见 R-IMP-06 | P0 |
| JSON | `.json`, `.ndjson` | `read_json_auto` | P2，v0.2 |
| 旧版 Excel | `.xls` | 不支持，提示另存为 xlsx | 不做 |

- 验收：
  - [ ] 六种后缀识别都有单元测试，未知后缀给出可读错误
  - [ ] 文件超过 2 GB 不阻止打开，但状态栏显示文件大小
- 边界：不做 zip 内文件自动发现，不读数据库连接。
- 依赖：R-IMP-03、R-IMP-06

## R-IMP-03 类型推断与列名清洗

- 优先级：P0
- 状态：已定义
- 场景：CSV 没有表头，或者表头里有空格、换行、重名、中文括号。
- 行为：
  - 默认判断第一行是否为表头，判断不确定时在导入确认条给一个开关。
  - 列名做最小清洗：去首尾空白、连续空白折成一个下划线、空列名补成 `column_3`、重名补后缀 `_2`。
  - 类型推断失败时整列按 `VARCHAR` 处理，不静默截断。
  - 日期列识别为 `DATE` 或 `TIMESTAMP`，识别不了的保留原字符串。
- 验收：
  - [ ] 表头含中文、空格、括号的 CSV 能正确显示列名
  - [ ] 一列混有 `1`、`1.5`、`—` 时不报错，按文本处理并在检查器标注类型冲突
  - [ ] 推断结果在打开后能从检查器看到，不藏在设置里
- 边界：不提供逐列指定类型的完整映射界面，v0.1 只有"首行是表头"和"分隔符"两个开关。
- 依赖：R-INSP-01、R-IMP-04

## R-IMP-04 编码探测

- 优先级：P0
- 状态：已定义
- 场景：国内导出的 CSV 经常是 GBK，DuckDB 默认按 UTF-8 读会乱码或报错。
- 行为：
  1. 读取前 64 KB 做编码判定，先试 UTF-8（含 BOM），失败或出现大量替换字符时按 GB18030 处理。
  2. 判定结果写进导入状态，用户能看到"按 GBK 读取"。
  3. 用户可手动切换 UTF-8 / GB18030 / UTF-16LE，切换后立即重读，保留已保存的筛选。
- 验收：
  - [x] 含中文的 GBK CSV 打开后列名和内容都不乱码（12 万行 GBK 文件转码后逐字符一致）
  - [x] 带 BOM 的 UTF-8 CSV 打开后首列名没有多余字符
  - [ ] 手动选错编码时不崩溃，只显示替换字符并允许再选
- 边界：转码按 4 MB 分块，见 R-PERF-06。
- 边界：不自动探测日文、韩文编码，遇到乱码由用户手动选。
- 依赖：R-IMP-05

## R-IMP-05 Parquet 缓存

- 优先级：P0
- 状态：已完成
- 场景：同一个大 CSV 第二次打开还慢，用户会以为应用什么都没记住。
- 行为：
  - 首次打开文本或 Excel 时，后台把数据转成 Parquet，存到 `~/Library/Application Support/<AppName>/cache/`。
  - 缓存键为绝对路径 + 文件大小 + 修改时间（秒级）+ 缓存格式版本号，任一变化即视为新文件。
  - 转换在后台进行，界面先显示前若干行让用户开始看；完成后状态栏提示"已缓存，下次秒开"。
  - 缓存上限默认 10 GB，超出后按最后访问时间淘汰。
- 验收：
  - [x] 同一个 500 MB CSV 第二次打开不超过 1 秒（实测 0.59 秒）
  - [x] 修改文件后再次打开能识别为已变化并重新转换，不读旧缓存
  - [x] 缓存目录被手动清空后再次打开不报错，走首次导入路径
  - [x] 转换中途退出应用，下次打开不会读到半截缓存文件（先写临时文件再改名）
- 边界：缓存不做加密，不做跨机器迁移。放弃缓存只影响速度，不影响数据正确性。
- 依赖：R-PERF-02、R-DEC-03

## R-IMP-06 Excel 读取方案

- 优先级：P0
- 状态：已完成
- 场景：用户最常拖进来的其实是 xlsx，不是 CSV。
- 行为：三条候选路线评估后选中 C 的变体，实测数据见 R-DEC-05 与 docs/bench-history.md。

| 路线 | 做法 | 优点 | 风险 |
|---|---|---|---|
| A | DuckDB 的 excel / spatial 扩展在读时展开 | 少一个依赖，跟其余格式同一条链路 | 扩展要联网下载，离线不可用；多工作表命名规则要实测 |
| B | CoreXLSX 解析成行，再写入 DuckDB | 纯 Swift，可离线 | 大文件内存占用高，只读单元格值不读公式 |
| C | 内置一条"xlsx 转 Parquet"的独立通道 | 一次转换，后续统一走 Parquet | 多一条代码路径，多一份测试面 |

- 验收：
  - [x] 选定路线在多工作表样本上实测，耗时写进 R-DEC-05 与 docs/bench-history.md（6.2 MB、19.9 万行，首次 7.23 秒，二次 0.04 秒）
  - [x] 引入的依赖许可证都是 MIT 或 Apache-2.0（CoreXLSX Apache-2.0、ZIPFoundation MIT）
  - [x] 公式单元格取缓存值；拿不到缓存值时留空，不猜不报错
  - [x] 多工作表：选择器列出全部工作表，点「全部导入」后每张表在侧栏单独一条、各自可切换（2026-10-26 真机验证，sample-20mb.xlsx 三张表同时打开，数据 199000 行，切到汇总二显示华东 1000；截图 `docs/media/verification/xlsx-sheets-all.png`、`xlsx-sheet-switch.png`）
- 边界：多工作表默认只导入用户选中的一张，选择器另给「全部导入」，每个工作表单独一条、各自缓存；工作表超过 20 张时拒绝全部导入并提示先单独打开。不保留格式、颜色、批注。
- 依赖：R-DEC-05

## R-IMP-07 导入错误处理

- 优先级：P1
- 状态：已完成（2026-10-28 真机验证，顺带修掉技术细节展开后被窗口裁掉）
- 场景：文件被占用、权限不足、编码坏掉、文件其实是别的格式改了后缀。
- 行为：
  - 错误一律给出三样东西：哪一步失败、DuckDB 的原始报错、用户能做的下一步。
  - 原始报错可折叠，默认收起，普通用户不需要看。
  - 打开失败不留下半成品视图和空表。
- 验收：
  - [x] 把一张 PNG 改名成 `.csv` 打开，提示"看起来不是文本文件"，不崩（2026-10-28 真机：标题「看起来不是文本文件」，副标题「确认文件没有被改成 .csv 后缀，或者换一个文件试试。」，展开技术细节得到「样本里含 NUL 字节或大量控制字符」；截图 [import-error-not-text.png](../media/verification/import-error-not-text.png)、[import-error-detail.png](../media/verification/import-error-detail.png)）
  - [x] 无读权限的文件，提示去系统设置授予权限（`chmod 000` 的文件打开后提示「没有读取这个文件的权限」，副标题「到系统设置里给应用授予文件访问权限，或把文件复制到桌面再试。」；截图 [import-error-permission.png](../media/verification/import-error-permission.png)）
  - [x] 导入失败的条目不出现在左栏的历史列表里（上面两次失败后左栏仍是「还没有打开文件」）
- 修过的问题：2026-10-28 发现「查看技术细节」只有小箭头能点、点文字没反应，且展开后内容被窗口底边裁掉。改成整行按钮，短报错按内容高度显示，超过 8 行才限高 120pt 滚动。见 openspec/changes/archive/2026-10-28-fix-error-card-clipped。
- 边界：不做自动修复脏文件。
- 依赖：R-IMP-02

## R-IMP-08 拖放接收层

- 优先级：P0
- 状态：已实现并真机验证（2026-10-27 改到窗口层，同日真机从访达拖拽成功）
- 为什么单独记一条：入口 1 长期不通，2026-10-26 录 GIF 时发现访达拖拽触发不了，修法改了架构位置，值得留档。
- 根因：SwiftUI 的 `.dropDestination(for: URL.self)` 挂在 `NavigationSplitView` 上时，生成的拖放目标视图是分栏视图的**兄弟节点**。AppKit 投递拖放先 `hitTest` 找最深的视图，再沿父链往上找 `registeredDraggedTypes` 匹配的那个；兄弟链不在父链上，拖拽落不到它身上。
- 修法：窗口内容视图换成自绘的 `FileDropContainerView`（`DropTarget.swift`），注册 `public.file-url`，原 SwiftUI 视图整个装在里面。这样任意位置的父链都能走回接收器，`NSTableView` 也抢不走。
- 安装时机：必须延一轮主队列。在 `viewDidMoveToWindow` 里当场换 contentView，SwiftUI 随后会把 `NSHostingView` 重新挂回 `NSThemeFrame`，容器变空壳（离屏探针复现过）。
- 只接本地文件：剪贴板用 `urlReadingFileURLsOnly` 读，纯文字、网页图片一律返回不接收，不弹提示。
- 悬停高亮：拖入时给容器 layer 描 3pt 强调色边框，松手或移出撤掉，不进布局。
- 验证：`TableWorkbenchTests` 造真 `NSWindow`，断言 contentView 是容器、注册了 `.fileURL`、铺满内容区、只一层、重复安装不叠层；再用假 `NSDraggingInfo` 按 AppKit 顺序走完 `draggingEntered` → `draggingUpdated` → `prepareForDragOperation` → `performDragOperation`，断言 URL 交到处理函数；换成纯文字断言全部拒绝。`TW_DROP_PROBE=1 TableWorkbenchUIAudit` 打印注册视图与覆盖面积（1200×828 = 100%）。
- 证据：离屏悬停高亮 [drop-window-highlight.png](../media/verification/drop-window-highlight.png)（真实视图树，模拟文件悬停，边框 3pt）；工具栏窗口换 contentView 前后内容区都是 900×628，toolbar 没丢。
- 真机验证（2026-10-27 23:29，release 包）：从访达把 bench-data/wide-100k.csv 鼠标拖进主窗口，悬停时窗口内描边亮起 [drop-real-hover.png](../media/verification/drop-real-hover.png)，松开后 100,000 行、15.7 MB、UTF-8 直接进表 [drop-real-loaded.png](../media/verification/drop-real-loaded.png)；同法再拖 bench-data/500mb.csv（524.4 MB）得到 3,266,000 行 [drop-real-500mb.png](../media/verification/drop-real-500mb.png)。系统真把访达的拖拽会话送到接收器这一步，此前是整条链上唯一没验的环节，这一轮补齐。
- 多文件：代码把落下的所有 URL 一起交给打开链路（`performDragOperation` → `open(urls:)`），实测一次拖入 sample-20mb.xlsx 与 wide-100k.csv，两条都进左栏；一次拖 5 个以上没逐条数过。
- 没证明的：跨卷、网络盘、外接盘上的文件拖入未验；从访达以外的应用（浏览器下载列表、解压工具窗口）拖入未验。
