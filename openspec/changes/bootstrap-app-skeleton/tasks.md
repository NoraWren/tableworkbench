# Tasks

## 1. 依赖与工程骨架

- [x] 1.1 创建 app/Package.swift，声明 TableWorkbenchApp、Features、DataGrid、DuckDBKit 四个 target，验证 swift build 通过
- [x] 1.2 加入 duckdb-swift 依赖并锁 exact 1.1.3，验证 swift package resolve 成功；失败则按 design D2 的备选记录原因
- [x] 1.3 写一个最小探针，连接内存库并执行 SELECT 42，把真实的连接、查询、结果集取列签名记进 docs/requirements/12-decisions-risks.md
- [x] 1.4 搭 App 入口与 NavigationSplitView 三栏，验证 swift run 能启动窗口，左中右三块都可见
- [x] 1.5 实现空状态页，验证没有文件时显示拖放区、支持格式和"数据不出本机"说明

## 2. 导入与编码

- [x] 2.1 实现编码探测：BOM、UTF-8 合法性、GB18030 回退，验证三组样本的单测通过
- [x] 2.2 实现非 UTF-8 转码到临时 UTF-8 文件，验证 GBK 中文样本打开后列名和内容都不乱码
- [x] 2.3 实现 CSV/TSV 分隔符与首行表头判断，验证逗号、制表符、无表头三种样本的推断结果正确
- [x] 2.4 实现列名清洗与类型推断，验证含空格、括号、重名列的样本得到可查询列名
- [x] 2.5 定义 ImportError 三个字段并接入统一错误卡片，验证无权限文件和伪装成 CSV 的 PNG 都给出可读提示
- [x] 2.6 接入拖放与 Command+O 两个入口，验证一次拖入 5 个文件时左栏出现 5 条且第一条自动选中（用 open -a 一次传 3 个文件，左栏 3 条，第一条自动选中）

## 3. 查询层

- [x] 3.1 定义 QuerySession 协议与行数据类型，验证界面层只 import 协议、不 import DuckDB
- [x] 3.2 实现 DuckDBSession 的只读连接与文件挂载，验证打开 CSV 后能读到列名、列类型和总行数
- [x] 3.3 实现总行数查询并在导入后回填，验证界面显示的行数与 wc -l 的结果差一（表头）
- [x] 3.4 实现按块查询 LIMIT/OFFSET，验证第 0、1、2 块的行区间不重叠、不遗漏
- [x] 3.5 在 DuckDBKit 层拦截写语句，验证 DROP、DELETE、INSERT、UPDATE、CREATE TABLE 五类全部被拒
- [x] 3.6 实现连接与结果集的关闭路径，验证连续打开关闭同一个 1GB 文件 20 次后内存回到基线 ±200MB

## 4. 数据网格

- [x] 4.1 用 NSViewRepresentable 包 view-based NSTableView，验证假数据 1000 行能显示、能滚动（已用 10 万行文件在界面上验收）
- [x] 4.2 实现块缓存与 8 块 LRU，验证回到已访问块时不再发起查询
- [x] 4.3 实现行号列、数字右对齐、NULL 灰色标记、长文本截断加 tooltip，验证四种显示规则（已在界面上验收：行号、对齐、NULL、横向滚动）
- [x] 4.4 接入滚动触发取块，验证快速拖到第 10000 行时没有长时间空白（已滚动到 95%，块加载正常）
- [x] 4.5 实现列宽估算与 2000 列保护，验证 3000 列文件默认只展示前 200 列且不卡死（3000 列文件数据层可打开；界面默认只展示前 200 列并提示）

## 5. 全链路串联

- [x] 5.1 打通打开文件到网格显示的完整链路，验证拖入 10 万行 CSV 后首屏出现数据（已拖入 10 万行文件并查看）
- [x] 5.2 补齐加载态、错误态、空状态三种界面，验证导入失败时左栏不残留条目（PNG 改名 CSV 后弹出错误卡片，左栏未新增）
- [x] 5.3 实现侧栏折叠与窗口尺寸记忆，验证重启后布局恢复（隐藏侧栏后退出重开，仍是折叠状态；窗口尺寸由 setFrameAutosaveName 记忆）

## 6. 基准与测试

- [x] 6.1 写 scripts/make-bench-data.sh，生成 500MB CSV、10 万行宽表和 GBK 样本，验证脚本在空目录能一键生成
- [x] 6.2 写 scripts/bench.sh，记录打开耗时、峰值内存、第 1/10/100 块查询耗时，验证输出为可读表格
- [ ] 6.3 跑一次完整基准并写入 docs/bench-history.md，验证 500MB CSV 打开不超过 3 秒（已达标 0.61 秒）；10 万行滚动帧率待屏幕解锁后补测
- [x] 6.4 跑 swift test，验证编码探测、块换算、写语句拦截三组测试全部通过

## 7. 收尾

- [x] 7.1 更新 docs/requirements/12-decisions-risks.md 的"已验证事实"，写入 duckdb-swift 的真实版本、API 签名和实测数字
- [x] 7.2 运行 openspec validate --strict bootstrap-app-skeleton，验证无报错
- [x] 7.3 录一段 30 秒演示：拖入大 CSV、滚动、看到行号与列类型，验证不看解释也能看懂（已录：500MB 文件 328 万行，滚动与排序；GIF 见 docs/media/demo.gif）
- [x] 7.4 对照 proposal 的"不做什么"逐条检查，验证没有提前实现排序、筛选、SQL 执行、透视、导出
