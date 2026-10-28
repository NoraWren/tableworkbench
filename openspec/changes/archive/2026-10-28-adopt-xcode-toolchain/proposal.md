# Proposal

## Why

2026-10-28 按要求装了 Xcode 27.1。装完发现两件事：一是宏和测试框架确实到位了（`@State`/`@Bindable`/`#Preview` 可编译、XCTest 与 Testing 框架都在、Instruments 在位）；二是默认的 SwiftBuild 后端在 ~/Documents（iCloud）里给资源包签名会失败，换 native 后端则会一直空转，release 构建拿不到产物。构建链路必须先修好，否则装了 Xcode 反而编不出包。

## What Changes

- 所有 swift 构建统一改成 `--build-system native --scratch-path "$scratch"`，`scratch` 默认 `~/Library/Caches/tableworkbench-build`，可用 `TW_BUILD_DIR` 覆盖。
- 改到的脚本：`make-app-bundle.sh`、`bench.sh`、`bench-scroll.sh`、`bench-cache.sh`、`bench-memory.sh`、`make-clickbench-bundle.sh`、`make-bench-data.sh`。
- 清掉仓库里的 `app/.build`，避免产物再写回 iCloud。
- 把 Xcode 已装、宏可用、构建目录约束写进 AGENTS.md 的环境表与"容易踩的坑"，结论记进 R-DEC-21。

## 需求编号

R-MS-01（前置条件：Xcode 与 SPM 依赖就绪）。

## 不做什么

- 不把界面层迁回 `@Observable`/`@State`。宏现在可用，但那是影响几十个文件的机械改动，用户感知为零，发布前不动。
- 不把测试迁到 Swift Testing。理由同上，留到发布后。
- 不把仓库搬出 iCloud。这次靠构建目录外置绕开，搬仓库会打断现有工作区路径。

## 性能与只读

纯构建链路，不碰查询、不改运行时行为，性能预算与只读约束不受影响。构建耗时变化：release 全量约十几分钟（DuckDB 的 C++ 部分），与换工具链前同量级。

