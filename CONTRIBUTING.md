# 参与开发

这是一个 Mac 上的只读数据分析工具：打开大文件要快，滚动要跟手，数据不出本机。改动围绕这三件事展开。

## 环境

- macOS 14 或更新
- Swift 6（只装 Command Line Tools 也能构建；Xcode 可选）
- 不需要 Node、Python 或包管理器

构建和运行：

```bash
cd app
swift build
swift run TableWorkbench
```

跑测试（退出码为 0 表示全过）：

```bash
cd app
swift run TableWorkbenchTests
```

开发用 .app 和 dmg：

```bash
./scripts/make-app-bundle.sh
./scripts/make-dmg.sh
```

## 提交前

1. `swift build` 和 `swift run TableWorkbenchTests` 都通过。
2. 改了取数、缓存、渲染路径的，附一份 `scripts/bench.sh` 的前后对比。没有数字的性能改动不合并。
3. 新增依赖先在 `docs/third-party.md` 登记：名称、版本、许可证、用途、不引入会怎样。只收 MIT、Apache-2.0、BSD。
4. 行为变化同步到 `docs/requirements/` 对应条目，勾选只在整条需求验完后进行。

## 代码结构

| 目录 | 负责 |
|---|---|
| `app/Sources/DuckDBKit` | 文件识别、导入、Parquet 缓存、只读连接 |
| `app/Sources/DataGrid` | NSTableView 桥接、分块取数、排序筛选 |
| `app/Sources/Features` | SQL 抽屉、透视、列检查器、图表、导出 |
| `app/Sources/TableWorkbenchApp` | 窗口、菜单、文件打开事件 |

## 需求变更

较大的功能先写 OpenSpec 提案（`openspec/changes/`），说清目的、行为、验收和风险，评审通过再写代码。小修小补直接提 PR。

## 提交信息

沿用 `type: 中文描述`，例如 `fix: 图表面板记住上次选择`。type 用 feat、fix、perf、docs、chore、refactor。

## 边界

这个项目是分析器。单元格编辑、公式、仪表盘联动、协作、云同步都不在范围内，相关 PR 会被拒绝。只读连接是硬约束：任何写回源文件的代码都不接受。
